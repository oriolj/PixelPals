extends Node2D
## Buddy select: one column per seated seat. Each seat picks an animal buddy
## (it follows the keeper around the zoo) and a hat colour (the keeper wears
## seat 1's hat).
##
## - Left/right (with repeat) cycles the buddy, skipping ones another seat has.
## - Up/down cycles the hat colour.
## - "a" readies (check), "b" un-readies.
## - SINGER: any press cycles to the next buddy; it auto-readies after
##   SINGER_IDLE seconds without a press.
## - The keeper's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the keeper's start, goes
##   to the zoo.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Animals := preload("res://scripts/vector/animals.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const SINGER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 360.0
const COL_H := 560.0
const COL_Y := 60.0
const GAP := 40.0

var auto_goto := true
var next_screen := ""

## seat -> buddy id ("" when the seat is empty)
var picks: Array[String] = ["", "", ""]
var readied: Array[bool] = [false, false, false]
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _hat_dir: Array[int] = [0, 0, 0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[float] = [0.0, 0.0, 0.0]
var _nodes := {}  # seat -> {"buddy", "left", "right", "up", "down", "check", "role"}


func _ready() -> void:
	_default_picks()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * GAP
	var x0 := (1280.0 - total) / 2.0
	for i in seated.size():
		var s := seated[i]
		_col_x[s] = x0 + i * (COL_W + GAP)
		_build_column(s)
	Sfx.music("music_menu")
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func _default_picks() -> void:
	var taken: Array[String] = []
	for s in Players.SEAT_COUNT:
		var r: String = Players.riders[s]
		if Players.is_seated(s) and Game.roster.has(r) and not taken.has(r):
			picks[s] = r
			taken.append(r)
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s) or picks[s] != "":
			continue
		var want := _next_free(s, [-1, 0, 2][s], 1)
		picks[s] = want
		taken.append(want)


func _next_free(seat: int, from: int, step: int) -> String:
	var n := Game.roster.size()
	var i := from
	for _k in n:
		i = posmod(i + step, n)
		var r := Game.roster[i]
		if not _taken_by_other(seat, r):
			return r
	return picks[seat]


func _taken_by_other(seat: int, buddy: String) -> bool:
	for s in Players.SEAT_COUNT:
		if s != seat and picks[s] == buddy:
			return true
	return false


func cycle(seat: int, step: int) -> void:
	var r := _next_free(seat, Game.roster.find(picks[seat]), step)
	if r == picks[seat]:
		return
	picks[seat] = r
	_bump[seat] = 0.25
	Sfx.play("whoosh", 1.2 + 0.1 * seat, -6.0)
	if _nodes.has(seat):
		_replace_buddy(seat)
	Game.voice(r)


func cycle_hat(seat: int, step: int) -> void:
	Game.hats[seat] = posmod(Game.hats[seat] + step, Game.HATS.size())
	_bump[seat] = 0.2
	Sfx.play("select", 1.0 + 0.08 * Game.hats[seat])
	if _nodes.has(seat):
		Animals.set_hat_color(_nodes[seat].buddy, Game.hat_color(seat))


func set_ready(seat: int, value: bool) -> void:
	if readied[seat] == value:
		return
	readied[seat] = value
	if value:
		Sfx.play("ready", 1.0 + 0.1 * seat)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_time += delta
	for s in Players.SEAT_COUNT:
		_bump[s] = maxf(0.0, _bump[s] - delta)
		if next_screen != "":
			return
		if Players.is_seated(s):
			if s == Players.Seat.HONKER:
				_singer(delta)
			else:
				_seat_input(s, delta)
	if Players.just_pressed(Players.Seat.DRIVER, "start"):
		_advance()
		return
	if _all_ready():
		if _advance_t < 0.0:
			_advance_t = 0.0
		_advance_t += delta
		if _advance_t >= ADVANCE_BEAT:
			_advance()
			return
	else:
		_advance_t = -1.0
	_layout()
	queue_redraw()


func _seat_input(s: int, delta: float) -> void:
	var d := Players.dir4(s)
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		_hold_dir[s] = d.x
		_hat_dir[s] = d.y
		return
	if s == Players.Seat.DRIVER and Players.just_pressed(s, "b"):
		_back_to_join()
		return
	var dx := d.x
	if dx != 0 and dx != _hold_dir[s]:
		cycle(s, dx)
		_hold_time[s] = 0.0
	elif dx != 0:
		_hold_time[s] += delta
		if _hold_time[s] >= REPEAT_DELAY:
			_hold_time[s] -= REPEAT_EVERY
			cycle(s, dx)
	_hold_dir[s] = dx
	if d.y != 0 and d.y != _hat_dir[s]:
		cycle_hat(s, d.y)
	_hat_dir[s] = d.y
	if Players.just_pressed(s, "a"):
		set_ready(s, true)


func _singer(delta: float) -> void:
	var s := Players.Seat.HONKER
	if Players.just_pressed(s, "any"):
		cycle(s, 1)
		set_ready(s, false)
		_idle[s] = 0.0
		return
	_idle[s] += delta
	if _idle[s] >= SINGER_IDLE:
		set_ready(s, true)


func _all_ready() -> bool:
	var any := false
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			any = true
			if not readied[s]:
				return false
	return any


func _back_to_join() -> void:
	Sfx.play("whoosh")
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _advance() -> void:
	for s in Players.SEAT_COUNT:
		Players.riders[s] = picks[s] if Players.is_seated(s) else ""
	Sfx.play("select")
	next_screen = "zoo"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("zoo")


# ---------------------------------------------------------------- view

func _build_column(s: int) -> void:
	var cx := _col_x[s] + COL_W / 2.0
	var col: Color = Players.SEAT_COLORS[s]
	var role := Props.role_icon(s, col)
	role.scale = Vector2(1.3, 1.3)
	role.position = Vector2(cx, COL_Y + 62)
	add_child(role)
	var holder := Node2D.new()
	add_child(holder)
	var left := Props.arrow(Pal.CREAM, -1)
	var right := Props.arrow(Pal.CREAM, 1)
	add_child(left)
	add_child(right)
	var up := Props.arrow(Pal.CREAM, 1)
	up.rotation = -PI / 2
	up.scale = Vector2(0.7, 0.7)
	var down := Props.arrow(Pal.CREAM, 1)
	down.rotation = PI / 2
	down.scale = Vector2(0.7, 0.7)
	add_child(up)
	add_child(down)
	var check := Props.check(Color("#5cb566"))
	check.scale = Vector2(1.4, 1.4)
	check.position = Vector2(cx, COL_Y + 505)
	add_child(check)
	_nodes[s] = {"role": role, "holder": holder, "buddy": null, "left": left, "right": right,
		"up": up, "down": down, "check": check}
	_replace_buddy(s)


func _replace_buddy(s: int) -> void:
	var holder: Node2D = _nodes[s].holder
	for c in holder.get_children():
		c.free()
	var b := Animals.build(picks[s])
	b.scale = Vector2.ONE * (0.8 if picks[s] == "giraffe" else 1.0)
	Animals.add_hat(b, Game.hat_color(s))
	holder.add_child(b)
	_nodes[s].buddy = b


func _layout() -> void:
	for s in _nodes:
		var n: Dictionary = _nodes[s]
		var cx := _col_x[s] + COL_W / 2.0
		var hop := -12.0 if _bump[s] > 0.0 else 0.0
		(n.holder as Node2D).position = Vector2(cx, COL_Y + 360 + hop)
		if readied[s]:
			Animals.pose(n.buddy, "dance", _time * 1.6)
		else:
			Animals.pose(n.buddy, "idle", _time + s)
		var wiggle := sin(_time * 5.0) * 5.0
		var show_arrows := not readied[s]
		var hat_arrows: bool = show_arrows and s != Players.Seat.HONKER
		n.left.visible = show_arrows and s != Players.Seat.HONKER
		n.right.visible = show_arrows
		n.up.visible = hat_arrows
		n.down.visible = hat_arrows
		n.left.position = Vector2(cx - 140 - wiggle, COL_Y + 290)
		n.right.position = Vector2(cx + 140 + wiggle, COL_Y + 290)
		n.up.position = Vector2(cx + 130, COL_Y + 150 - absf(wiggle))
		n.down.position = Vector2(cx + 130, COL_Y + 210 + absf(wiggle))
		n.check.visible = readied[s]


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Pal.SKY)
	draw_rect(Rect2(0, 600, 1280, 120), Pal.GRASS)
	for s in _nodes:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		draw_colored_polygon(VA.rrect(r, 30), Pal.OUTLINE)
		draw_colored_polygon(VA.rrect(r.grow(-6), 26), col if readied[s] else col.darkened(0.15))
		draw_colored_polygon(VA.rrect(r.grow(-14), 22), col.lightened(0.55))
		var cx := _col_x[s] + COL_W / 2.0
		# Stage under the buddy.
		draw_colored_polygon(VA.ellipse(120, 26, Vector2(cx, COL_Y + 372)), Pal.OUTLINE)
		draw_colored_polygon(VA.ellipse(114, 21, Vector2(cx, COL_Y + 370)), col)
		# Hat swatches (not for the singer): the current one is bigger.
		if s != Players.Seat.HONKER:
			for i in Game.HATS.size():
				var hp := Vector2(cx - 100 + i * 40, COL_Y + 180)
				var rr := 15.0 if i == Game.hats[s] else 10.0
				draw_circle(hp, rr + 3.0, Pal.OUTLINE, true, -1.0, true)
				draw_circle(hp, rr, Game.HATS[i], true, -1.0, true)
		# Roster dots: own pick bright, others' picks dark.
		var n := Game.roster.size()
		for i in n:
			var rr := Game.roster[i]
			var c := Color(Pal.OUTLINE, 0.25)
			if rr == picks[s]:
				c = Pal.OUTLINE
			elif _taken_by_other(s, rr):
				c = Color(Pal.OUTLINE, 0.6)
			draw_circle(Vector2(cx - (n - 1) * 14 + i * 28, COL_Y + 425), 8 if rr == picks[s] else 6, c, true, -1.0, true)
		# Singer idle bar: fills toward the automatic ready.
		if s == Players.Seat.HONKER and not readied[s]:
			var w := clampf(_idle[s] / SINGER_IDLE, 0.0, 1.0) * 200.0
			draw_colored_polygon(VA.rrect(Rect2(cx - 100, COL_Y + 490, 200, 18), 9), Color(Pal.OUTLINE, 0.4))
			if w > 18:
				draw_colored_polygon(VA.rrect(Rect2(cx - 100, COL_Y + 490, w, 18), 9), col.darkened(0.2))
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 1280.0
		draw_rect(Rect2(0, 700, w, 12), Pal.CREAM)
