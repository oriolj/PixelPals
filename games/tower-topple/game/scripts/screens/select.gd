extends Node2D
## Rider select (the PixelPals one at 640x360): one column per seated seat.
##
## - Left/right (edge-detected, repeating after a short hold) cycles through
##   Game.roster, skipping riders another seat already picked.
## - "a" readies (tick), "b" un-readies.
## - Toppler: any press cycles to the next rider; it auto-readies after
##   HONKER_IDLE seconds without a press.
## - The Builder's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the Builder's start,
##   writes Players.riders and goes to play.

const Vec := preload("res://scripts/play/vec.gd")
const Icons := preload("res://scripts/icons.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 192
const COL_H := 284
const COL_Y := 30
const ROLE_ICONS: Array[String] = ["hook", "drop", "button"]

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
var _riders := {}  # seat -> AnimatedSprite2D


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
		var rider := Art.sprite(picks[s], Game.rider_color(picks[s]), Vector2i(16, 16))
		rider.scale = Vector2(4, 4)
		add_child(rider)
		_riders[s] = rider
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
		var want := "penguin" if s == Players.Seat.DRIVER and Game.roster.has("penguin") else ""
		if want == "" or taken.has(want):
			want = _next_free(s, -1, 1)
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
	Sfx.play("select", 1.2 + 0.1 * seat, -4.0)
	if _riders.has(seat):
		_riders[seat].sprite_frames = Art.frames(r, Game.rider_color(r), Vector2i(16, 16))
		_riders[seat].play("default")


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
			if s == Players.Seat.HONKER:
				_honker(delta)
			else:
				_seat_input(s, delta)
	if next_screen != "":
		return
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


func _back_to_join() -> void:
	Sfx.play("select", 0.8)
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _advance() -> void:
	for s in Players.SEAT_COUNT:
		Players.riders[s] = picks[s] if Players.is_seated(s) else ""
	Sfx.play("select")
	next_screen = "play"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("play")


func _layout() -> void:
	for s in _riders:
		var cx := _col_x[s] + COL_W / 2.0
		var hop := -4.0 if _bump[s] > 0.0 else 0.0
		var cheer := -(int(_time * 4.0) % 2) * 4.0 if readied[s] else 0.0
		_riders[s].position = Vector2(cx, COL_Y + 132 + hop + cheer)


func _draw() -> void:
	var bands := 18
	for i in bands:
		var c := Color("#41a6f6").lerp(Color("#73eff7"), float(i) / (bands - 1))
		draw_rect(Rect2(0, i * 360.0 / bands, 640, 360.0 / bands + 1), c)
	for s in _riders:
		var col: Color = Players.SEAT_COLORS[s]
		var cx := _col_x[s] + COL_W / 2.0
		var panel := Vec.translated(Vec.rounded_rect(COL_W, COL_H, 16), Vector2(cx, COL_Y + COL_H / 2.0))
		Vec.draw_shape(self, panel, col.darkened(0.55), col if readied[s] else col.darkened(0.2), 4.0)
		Icons.draw(self, ROLE_ICONS[s], Vector2(cx, COL_Y + 34), 44, col.lightened(0.2))
		# Stage under the rider.
		var stage := Vec.translated(Vec.rounded_rect(96, 10, 4), Vector2(cx, COL_Y + 172))
		Vec.draw_shape(self, stage, col, Vec.INK, 2.5)
		if not readied[s]:
			var wiggle := float(int(_time * 3.0) % 2) * 2.0
			Icons.draw(self, "left", Vector2(cx - 68 - wiggle, COL_Y + 132), 28, Vec.WHITE)
			Icons.draw(self, "right", Vector2(cx + 68 + wiggle, COL_Y + 132), 28, Vec.WHITE)
		else:
			Icons.draw(self, "check", Vector2(cx, COL_Y + 240), 40, Color("#38b764"))
		if s == Players.Seat.HONKER and not readied[s]:
			var w := clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 80.0
			draw_rect(Rect2(cx - 40, COL_Y + 236, 80, 8), Color(Vec.INK, 0.6))
			draw_rect(Rect2(cx - 40, COL_Y + 236, w, 8), col)
		var n := Game.roster.size()
		var dx0 := cx - (n * 12 - 4) / 2.0
		for i in n:
			var rr := Game.roster[i]
			var c := Color(Vec.WHITE, 0.25)
			if rr == picks[s]:
				c = Vec.WHITE
			elif _taken_by_other(s, rr):
				c = Color(Vec.INK, 0.8)
			draw_circle(Vector2(dx0 + i * 12 + 4, COL_Y + 198), 4.0, c, true, -1.0, true)
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 640.0
		draw_rect(Rect2(0, 346, w, 8), Vec.WHITE)
