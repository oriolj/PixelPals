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
##   writes Players.riders and goes to the paint screen.

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 184
const COL_H := 280
const COL_Y := 30

const Kit := preload("res://scripts/ui/draw_kit.gd")
const Palette := preload("res://scripts/paint/palette.gd")
const JoinScreen := preload("res://scripts/screens/join.gd")

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
	var gap := 16
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (640 - total) / 2
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
	next_screen = "paint"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("paint")


# ---------------------------------------------------------------- view

func _build_column(s: int) -> void:
	var rider := Art.sprite(picks[s], Game.rider_color(picks[s]), Vector2i(16, 16))
	rider.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rider.scale = Vector2(5, 5)
	add_child(rider)
	_nodes[s] = {"rider": rider}


func _layout() -> void:
	for s in _nodes:
		var cx := _col_x[s] + COL_W / 2
		var hop := -5 if _bump[s] > 0.0 else 0
		var cheer := -absf(sin(_time * 8.0)) * 8.0 if readied[s] else 0.0
		_nodes[s].rider.position = Vector2(cx, COL_Y + 142 + hop + cheer)


func _draw() -> void:
	Kit.wall(self, Rect2(0, 0, 640, 360))
	for s in _nodes:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		Kit.rrect(self, r.grow(3), 18, col.darkened(0.3) if readied[s] else col.darkened(0.1))
		Kit.rrect(self, r, 16, col.lightened(0.55))
		var cx := _col_x[s] + COL_W / 2.0
		# role icon at the top
		Kit.disc(self, Vector2(cx, COL_Y + 38), 28, Kit.WHITE)
		JoinScreen.role_icon(self, s, Vector2(cx, COL_Y + 38), 40.0, true)
		# a little rug under the rider
		Kit.poly(self, Kit.Shapes.ellipse(Vector2(cx, COL_Y + 186), 48, 10, 32), col.darkened(0.2))
		if not readied[s]:
			var wiggle := sin(_time * 6.0) * 2.0
			Kit.arrow(self, Vector2(cx - 70 - wiggle, COL_Y + 142), 22, Vector2.LEFT, Kit.INK.lightened(0.15))
			Kit.arrow(self, Vector2(cx + 70 + wiggle, COL_Y + 142), 22, Vector2.RIGHT, Kit.INK.lightened(0.15))
		else:
			Kit.disc(self, Vector2(cx, COL_Y + 246), 20, Kit.WHITE)
			Kit.icon_check(self, Vector2(cx, COL_Y + 246), 30, Color("#38b764"))
		# Splatter idle bar: fills toward the automatic ready.
		if s == 2 and not readied[s]:
			var w := clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 100.0
			Kit.rrect(self, Rect2(cx - 50, COL_Y + 240, 100, 10), 5, Color(Kit.INK, 0.25))
			if w > 10.0:
				Kit.rrect(self, Rect2(cx - 50, COL_Y + 240, w, 10), 5, col.darkened(0.2))
		# roster dots: own pick bright, others' picks dark
		var n := Game.roster.size()
		var dx0 := cx - (n * 12 - 4) / 2.0
		for i in n:
			var rr := Game.roster[i]
			var c := Color(Kit.INK, 0.18)
			if rr == picks[s]:
				c = Kit.INK
			elif _taken_by_other(s, rr):
				c = Color(Kit.WHITE, 0.9)
			Kit.disc(self, Vector2(dx0 + i * 12 + 4, COL_Y + 214), 4, c)
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 640.0
		draw_rect(Rect2(0, 350, w, 6), Palette.COLORS[1])
