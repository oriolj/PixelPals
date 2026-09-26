extends Node2D
## Rider select: one column per seated seat (PixelPals's rules and tests).
##
## - Left/right (edge-detected, repeating after a short hold) cycles through
##   Game.roster, skipping riders another seat already picked.
## - "a" readies (a tick), "b" un-readies.
## - HONKER: any press cycles to the next rider; it auto-readies after
##   HONKER_IDLE seconds without a press.
## - The driver's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the driver's start,
##   writes Players.riders and goes to the level.
## Each column shows where that rider will sit: the tractor cab, the trailer
## or on top of the rain cloud.

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Farm := preload("res://scripts/draw/farm_art.gd")
const JoinScreen := preload("res://scripts/screens/join.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 344
const COL_H := 520
const COL_Y := 60
const RIDER_Y := 250.0

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
	var gap := 52
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (1280 - total) / 2
	for i in seated.size():
		var s := seated[i]
		_col_x[s] = x0 + i * (COL_W + gap)
		var r := Game.rider_sprite(picks[s], 8.0)
		r.z_index = 2
		add_child(r)
		_riders[s] = r
	Sfx.music("music_farm")
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
	Sfx.play("select", 1.1 + 0.1 * seat, -4.0)
	if _riders.has(seat):
		_riders[seat].sprite_frames = Art.frames(r, Game.rider_color(r), Vector2i(16, 16))
		_riders[seat].play("default")


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


func _back_to_join() -> void:
	Sfx.play("select", 0.7)
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _advance() -> void:
	for s in Players.SEAT_COUNT:
		Players.riders[s] = picks[s] if Players.is_seated(s) else ""
	Sfx.play("select")
	next_screen = "level"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("level")


# ---------------------------------------------------------------- view

func _layout() -> void:
	for s in _riders:
		var cx := _col_x[s] + COL_W / 2.0
		var hop := -10.0 if _bump[s] > 0.0 else 0.0
		var cheer := -absf(sin(_time * 8.0)) * 16.0 if readied[s] else 0.0
		_riders[s].position = Vector2(cx, COL_Y + RIDER_Y + hop + cheer)


func _draw() -> void:
	JoinScreen.draw_farm_backdrop(self, _time)
	for s in _riders:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		S.box(self, r.grow(8), 30, col if readied[s] else col.darkened(0.25), P.INK, 4.0)
		S.box(self, r, 24, P.CREAM, P.INK, 3.0)
		var cx := r.position.x + COL_W / 2.0
		# Where this rider will sit, as a small picture at the top.
		match s:
			0:
				S.xform(self, Vector2(cx, COL_Y + 118), 0.0, Vector2(0.8, 0.8))
				Farm.tractor(self, 0.0)
				Farm.tractor_front(self, 0.0)
			1:
				S.xform(self, Vector2(cx, COL_Y + 104), 0.0, Vector2(0.9, 0.9))
				Farm.trailer(self, [0, 1, 2, 3, 2], 0.0)
			2:
				S.xform(self, Vector2(cx, COL_Y + 74), 0.0, Vector2(0.75, 0.75))
				Farm.cloud(self, Farm.Face.IDLE, false, _time)
		S.reset(self)
		# Stage under the rider.
		S.oval(self, Vector2(cx, COL_Y + RIDER_Y + 70), 84, 16, col.lightened(0.2), P.INK, 3.0)
		if not readied[s]:
			var wig := sin(_time * 6.0) * 4.0
			for side in [-1.0, 1.0]:
				var ax: float = cx + side * (118.0 + wig)
				var ay := COL_Y + RIDER_Y
				S.fill_ink(self, PackedVector2Array([Vector2(ax + side * 22, ay), Vector2(ax - side * 10, ay - 26),
					Vector2(ax - side * 10, ay + 26)]), col, P.INK, 3.0)
		else:
			_draw_check(Vector2(cx, COL_Y + 440), col)
		# Honker idle bar: fills toward the automatic ready.
		if s == Players.Seat.HONKER and not readied[s]:
			var w := clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 180.0
			S.box(self, Rect2(cx - 90, COL_Y + 432, 180, 16), 8, Color(P.INK, 0.25), P.INK, 2.0)
			if w > 8.0:
				S.box(self, Rect2(cx - 90, COL_Y + 432, w, 16), 8, col, P.INK, 0.0)
		# Roster dots.
		var n := Game.roster.size()
		var dx0 := cx - (n * 22 - 8) / 2.0
		for i in n:
			var rr := Game.roster[i]
			var c := Color(P.INK, 0.2)
			if rr == picks[s]:
				c = col.darkened(0.2)
			elif _taken_by_other(s, rr):
				c = Color(P.INK, 0.7)
			draw_circle(Vector2(dx0 + i * 22 + 7, COL_Y + 380), 7, c, true, -1.0, true)
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 1280.0
		draw_rect(Rect2(0, 700, w, 14), P.WHITE)


func _draw_check(c: Vector2, col: Color) -> void:
	S.disc(self, c, 34, P.LEAF_BRIGHT, P.INK, 3.0)
	S.path(self, PackedVector2Array([c + Vector2(-16, 0), c + Vector2(-4, 13), c + Vector2(18, -14)]), P.WHITE, 8.0)
