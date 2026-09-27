extends Node2D
## Select (adapted from Pillow Fort's): one column per seated seat.
##
## - Walker: left/right cycles the character (Game.roster: the riders plus
##   the private pack), "a" readies, "b" un-readies; "b" while not ready
##   goes back to join (seats kept).
## - Laser (5-year-old): left/right cycles a hat colour, "a" readies.
## - Treats (2-year-old): any press cycles the hat colour; it auto-readies
##   after TODDLER_IDLE seconds without a press.
## All seated seats ready (after a short beat), or the walker's start, writes
## Players.riders and Game.hats and goes to the house. Greyssie and Kira sit
## at the bottom of the screen.

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const TODDLER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 96
const COL_H := 128
const COL_Y := 8
const ROLE_ICONS: Array[String] = ["seat_shoes", "seat_laser", "seat_treats"]
const SKY: Array[Color] = [Color("#ffcd75"), Color("#ef7d57"), Color("#b13e53"), Color("#5d275d")]
const Hat := preload("res://scripts/hat.gd")
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")

var auto_goto := true
var next_screen := ""

## Walker's character.
var pick := ""
## seat -> hat index (laser and treats)
var hat_pick: Array[int] = [0, 2, 3]
var readied: Array[bool] = [false, false, false]
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[int] = [0, 0, 0]
var _nodes := {}


func _ready() -> void:
	pick = Players.riders[Game.WALKER] if Game.roster.has(Players.riders[Game.WALKER]) else Game.roster[0]
	for s in [Game.LASER, Game.TREATS]:
		hat_pick[s] = Game.hats[s]
	if hat_pick[Game.LASER] == hat_pick[Game.TREATS]:
		hat_pick[Game.TREATS] = (hat_pick[Game.LASER] + 1) % Game.HATS.size()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var gap := 8
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (320 - total) / 2
	for i in seated.size():
		_col_x[seated[i]] = x0 + i * (COL_W + gap)
		_build_column(seated[i])
	var ci := 0
	for info in Game.cat_data.cats:
		var c := Art.sprite(info.id + "_sit", info.collar, Vector2i(20, 16))
		c.position = Vector2(130 + ci * 60, 156)
		c.scale = Vector2(2, 2)
		c.flip_h = ci % 2 == 1
		add_child(c)
		ci += 1
	Sfx.music("music_menu")
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func cycle_rider(step: int) -> void:
	var n := Game.roster.size()
	pick = Game.roster[posmod(Game.roster.find(pick) + step, n)]
	_bump[Game.WALKER] = 0.2
	Sfx.play("whoosh", 1.2, -6.0)
	if _nodes.has(Game.WALKER):
		_nodes[Game.WALKER].figure.sprite_frames = Art.frames(pick, Game.rider_color(pick), Vector2i(16, 16))
		_nodes[Game.WALKER].figure.play("default")


## Next hat colour that the other kid seat does not wear.
func cycle_hat(seat: int, step: int) -> void:
	var other := Game.TREATS if seat == Game.LASER else Game.LASER
	var n := Game.HATS.size()
	var i := hat_pick[seat]
	for _k in n:
		i = posmod(i + step, n)
		if not Players.is_seated(other) or i != hat_pick[other]:
			break
	hat_pick[seat] = i
	_bump[seat] = 0.2
	Sfx.play("whoosh", 1.3 + 0.1 * seat, -6.0)
	if _nodes.has(seat):
		_nodes[seat].hat.color = Game.HATS[i]


func set_ready(seat: int, value: bool) -> void:
	if readied[seat] == value:
		return
	readied[seat] = value
	if value:
		Sfx.play("ready", 1.0 + 0.1 * seat)


func _process(delta: float) -> void:
	_time += delta
	for s in Players.SEAT_COUNT:
		_bump[s] = maxf(0.0, _bump[s] - delta)
		if next_screen != "":
			return
		if Players.is_seated(s):
			if s == Game.TREATS:
				_toddler(delta)
			else:
				_seat_input(s, delta)
	if next_screen != "":
		return
	if Players.just_pressed(Game.WALKER, "start"):
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
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		_hold_dir[s] = Players.dir4(s).x
		return
	if s == Game.WALKER and Players.just_pressed(s, "b"):
		_back_to_join()
		return
	var dx := Players.dir4(s).x
	var fire := false
	if dx != 0 and dx != _hold_dir[s]:
		fire = true
		_hold_time[s] = 0.0
	elif dx != 0:
		_hold_time[s] += delta
		if _hold_time[s] >= REPEAT_DELAY:
			_hold_time[s] -= REPEAT_EVERY
			fire = true
	if fire:
		if s == Game.WALKER:
			cycle_rider(dx)
		else:
			cycle_hat(s, dx)
	_hold_dir[s] = dx
	if Players.just_pressed(s, "a"):
		set_ready(s, true)


func _toddler(delta: float) -> void:
	var s := Game.TREATS
	if Players.just_pressed(s, "any"):
		cycle_hat(s, 1)
		set_ready(s, false)
		_idle[s] = 0.0
		return
	_idle[s] += delta
	if _idle[s] >= TODDLER_IDLE:
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
	Players.riders[Game.WALKER] = pick
	for s in [Game.LASER, Game.TREATS]:
		Game.hats[s] = hat_pick[s]
	Sfx.play("select")
	next_screen = "house"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("house")


# ---------------------------------------------------------------- view

func _build_column(s: int) -> void:
	var cx := _col_x[s] + COL_W / 2
	var col: Color = Players.SEAT_COLORS[s]
	var role := Art.sprite(ROLE_ICONS[s], col.lightened(0.3), Vector2i(16, 16))
	role.position = Vector2(cx, COL_Y + 16)
	add_child(role)
	var figure: AnimatedSprite2D
	if s == Game.WALKER:
		figure = Art.sprite(pick, Game.rider_color(pick), Vector2i(16, 16))
	else:
		figure = Art.sprite(ROLE_ICONS[s], col, Vector2i(16, 16))
	figure.scale = Vector2(2, 2)
	add_child(figure)
	var hat := Hat.new()
	hat.color = Game.HATS[hat_pick[s]]
	hat.visible = s != Game.WALKER
	add_child(hat)
	var left := Art.sprite("arrow_left", WHITE, Vector2i(8, 8))
	var right := Art.sprite("arrow_right", WHITE, Vector2i(8, 8))
	left.scale = Vector2(2, 2)
	right.scale = Vector2(2, 2)
	add_child(left)
	add_child(right)
	var check := Art.sprite("check", Color("#38b764"), Vector2i(8, 8))
	check.scale = Vector2(2, 2)
	check.position = Vector2(cx, COL_Y + 108)
	add_child(check)
	_nodes[s] = {"role": role, "figure": figure, "hat": hat, "left": left, "right": right, "check": check}


func _layout() -> void:
	for s in _nodes:
		var n: Dictionary = _nodes[s]
		var cx := _col_x[s] + COL_W / 2
		var hop := -2 if _bump[s] > 0.0 else 0
		var cheer := -(int(_time * 4.0) % 2) * 2 if readied[s] else 0
		n.figure.position = Vector2(cx, COL_Y + 60 + hop + cheer)
		n.hat.position = Vector2(cx, COL_Y + 40 + hop + cheer)
		var wiggle := int(_time * 3.0) % 2
		var show_arrows: bool = not readied[s] and s != Game.TREATS
		n.left.visible = show_arrows
		n.right.visible = show_arrows
		n.left.position = Vector2(cx - 34 - wiggle, COL_Y + 60)
		n.right.position = Vector2(cx + 34 + wiggle, COL_Y + 60)
		n.check.visible = readied[s]


func _draw() -> void:
	var band := 180.0 / SKY.size()
	for i in SKY.size():
		draw_rect(Rect2(0, roundf(i * band), 320, ceilf(band)), SKY[i])
	# A floor for the cats.
	draw_rect(Rect2(0, 160, 320, 20), Color("#ef7d57"))
	draw_rect(Rect2(0, 160, 320, 1), Color("#b13e53"))
	for s in _nodes:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		draw_rect(r, col if readied[s] else col.darkened(0.2))
		draw_rect(r.grow(-2), col.darkened(0.6))
		var cx := _col_x[s] + COL_W / 2
		draw_rect(Rect2(cx - 22, COL_Y + 78, 44, 4), col)
		if s == Game.TREATS and not readied[s]:
			var w := int(clampf(_idle[s] / TODDLER_IDLE, 0.0, 1.0) * 40.0)
			draw_rect(Rect2(cx - 20, COL_Y + 118, 40, 4), Color(INK, 0.6))
			draw_rect(Rect2(cx - 20, COL_Y + 118, w, 4), col)
		# Choice dots: the roster for the walker, the hat colours for the kids.
		if s == Game.WALKER:
			var n := Game.roster.size()
			var dx0 := cx - (n * 6 - 2) / 2
			for i in n:
				draw_rect(Rect2(dx0 + i * 6, COL_Y + 90, 4, 4), WHITE if Game.roster[i] == pick else Color(WHITE, 0.25))
		else:
			var n := Game.HATS.size()
			var dx0 := cx - (n * 6 - 2) / 2
			for i in n:
				var c: Color = Game.HATS[i]
				if i != hat_pick[s]:
					c = c.darkened(0.5)
				draw_rect(Rect2(dx0 + i * 6, COL_Y + 90 - (2 if i == hat_pick[s] else 0), 4, 4), c)
	if _advance_t >= 0.0:
		var w := int(clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 320.0)
		draw_rect(Rect2(0, 140, w, 3), WHITE)
