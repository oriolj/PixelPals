extends Node2D
## Rider select: one column per seated seat.
##
## - Left/right (edge-detected, repeating after a short hold) cycles through
##   Game.roster, skipping riders another seat already picked.
## - "a" readies (check icon), "b" un-readies.
## - HONKER: any press cycles to the next rider; it auto-readies after
##   HONKER_IDLE seconds without a press.
## - The driver's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the driver's start,
##   writes Players.riders and goes to the fort.
## Each seat's rider wears a nightcap in the seat colour (its pyjama colour).

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 96
const COL_H := 140
const COL_Y := 20
const ROLE_ICONS: Array[String] = ["seat_flashlight", "seat_seeker", "seat_peekaboo"]
const SKY: Array[Color] = [Color("#5d275d"), Color("#6e2f5f"), Color("#8a3657"), Color("#b13e53")]
const Nightcap := preload("res://scripts/nightcap.gd")
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")

var auto_goto := true
var next_screen := ""

## seat -> rider id ("" when the seat is empty)
var picks: Array[String] = ["", "", ""]
var readied: Array[bool] = [false, false, false]
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[int] = [0, 0, 0]
var _nodes := {}  # seat -> {"rider", "left", "right", "check", "role"}


func _ready() -> void:
	_default_picks()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var gap := 8
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (320 - total) / 2
	for i in seated.size():
		var s := seated[i]
		_col_x[s] = x0 + i * (COL_W + gap)
		_build_column(s)
	Sfx.music("music_menu")
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func _default_picks() -> void:
	# Keep valid, distinct picks from the last round; otherwise the driver
	# gets the penguin and every other seat the next free rider.
	var taken: Array[String] = []
	for s in Players.SEAT_COUNT:
		var r: String = Players.riders[s]
		if Players.is_seated(s) and Game.roster.has(r) and not taken.has(r):
			picks[s] = r
			taken.append(r)
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s) or picks[s] != "":
			continue
		var want := "penguin" if s == Players.Seat.DRIVER and Game.roster.has("penguin") else ""
		if want == "" or taken.has(want):
			want = _next_free(s, -1, 1)
		picks[s] = want
		taken.append(want)


## Next rider from roster index `from` in direction `step` that no other seat has.
func _next_free(seat: int, from: int, step: int) -> String:
	var n := Game.roster.size()
	var i := from
	for _k in n:
		i = posmod(i + step, n)
		var r := Game.roster[i]
		if not _taken_by_other(seat, r):
			return r
	return picks[seat]


func _taken_by_other(seat: int, rider: String) -> bool:
	for s in Players.SEAT_COUNT:
		if s != seat and picks[s] == rider:
			return true
	return false


func cycle(seat: int, step: int) -> void:
	var r := _next_free(seat, Game.roster.find(picks[seat]), step)
	if r == picks[seat]:
		return
	picks[seat] = r
	_bump[seat] = 0.2
	Sfx.play("whoosh", 1.2 + 0.1 * seat, -6.0)
	if _nodes.has(seat):
		_nodes[seat].rider.sprite_frames = Art.frames(r, Game.rider_color(r), Vector2i(16, 16))
		_nodes[seat].rider.play("default")


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
				_honker(delta)
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
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		_hold_dir[s] = Players.dir4(s).x
		return
	if s == Players.Seat.DRIVER and Players.just_pressed(s, "b"):
		_back_to_join()
		return
	var dx := Players.dir4(s).x
	if dx != 0 and dx != _hold_dir[s]:
		cycle(s, dx)
		_hold_time[s] = 0.0
	elif dx != 0:
		_hold_time[s] += delta
		if _hold_time[s] >= REPEAT_DELAY:
			_hold_time[s] -= REPEAT_EVERY
			cycle(s, dx)
	_hold_dir[s] = dx
	if Players.just_pressed(s, "a"):
		set_ready(s, true)


func _honker(delta: float) -> void:
	var s := Players.Seat.HONKER
	if Players.just_pressed(s, "any"):
		cycle(s, 1)
		set_ready(s, false)
		_idle[s] = 0.0
		return
	_idle[s] += delta
	if _idle[s] >= HONKER_IDLE:
		set_ready(s, true)


func _all_ready() -> bool:
	var any := false
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			any = true
			if not readied[s]:
				return false
	return any


## Driver's "b" while not ready: back to join, seats kept (no Players.reset).
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
	next_screen = "fort"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("fort")


# ---------------------------------------------------------------- view

func _build_column(s: int) -> void:
	var cx := _col_x[s] + COL_W / 2
	var col: Color = Players.SEAT_COLORS[s]
	var role := Art.sprite(ROLE_ICONS[s], col.lightened(0.3), Vector2i(16, 16))
	role.position = Vector2(cx, COL_Y + 16)
	add_child(role)
	var rider := Art.sprite(picks[s], Game.rider_color(picks[s]), Vector2i(16, 16))
	rider.scale = Vector2(2, 2)
	add_child(rider)
	var cap := Nightcap.new()
	cap.color = col
	rider.add_child(cap)
	var left := Art.sprite("arrow_left", WHITE, Vector2i(8, 8))
	var right := Art.sprite("arrow_right", WHITE, Vector2i(8, 8))
	left.scale = Vector2(2, 2)
	right.scale = Vector2(2, 2)
	add_child(left)
	add_child(right)
	var check := Art.sprite("check", Color("#38b764"), Vector2i(8, 8))
	check.scale = Vector2(2, 2)
	check.position = Vector2(cx, COL_Y + 118)
	add_child(check)
	_nodes[s] = {"role": role, "rider": rider, "left": left, "right": right, "check": check}


func _layout() -> void:
	for s in _nodes:
		var n: Dictionary = _nodes[s]
		var cx := _col_x[s] + COL_W / 2
		var hop := -2 if _bump[s] > 0.0 else 0
		var cheer := -(int(_time * 4.0) % 2) * 2 if readied[s] else 0
		n.rider.position = Vector2(cx, COL_Y + 66 + hop + cheer)
		var wiggle := int(_time * 3.0) % 2
		var show_arrows := not readied[s]
		n.left.visible = show_arrows
		n.right.visible = show_arrows
		n.left.position = Vector2(cx - 34 - wiggle, COL_Y + 66)
		n.right.position = Vector2(cx + 34 + wiggle, COL_Y + 66)
		n.check.visible = readied[s]


func _draw() -> void:
	var band := 180.0 / SKY.size()
	for i in SKY.size():
		draw_rect(Rect2(0, roundf(i * band), 320, ceilf(band)), SKY[i])
	for s in _nodes:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		draw_rect(r, col if readied[s] else col.darkened(0.2))
		draw_rect(r.grow(-2), col.darkened(0.6))
		# Stage under the rider.
		var cx := _col_x[s] + COL_W / 2
		draw_rect(Rect2(cx - 22, COL_Y + 84, 44, 4), col)
		# Honker idle bar: fills toward the automatic ready.
		if s == Players.Seat.HONKER and not readied[s]:
			var w := int(clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 40.0)
			draw_rect(Rect2(cx - 20, COL_Y + 116, 40, 4), Color(INK, 0.6))
			draw_rect(Rect2(cx - 20, COL_Y + 116, w, 4), col)
		# Roster dots: one per rider, own pick bright, others' picks dimmed.
		var n := Game.roster.size()
		var dx0 := cx - (n * 6 - 2) / 2
		for i in n:
			var rr := Game.roster[i]
			var c := Color(WHITE, 0.25)
			if rr == picks[s]:
				c = WHITE
			elif _taken_by_other(s, rr):
				c = Color(INK, 0.8)
			draw_rect(Rect2(dx0 + i * 6, COL_Y + 98, 4, 4), c)
	if _advance_t >= 0.0:
		var w := int(clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 320.0)
		draw_rect(Rect2(0, 172, w, 4), WHITE)
