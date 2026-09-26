extends Node2D
## Chef select: one column per seated seat (logic copied from PixelPals's
## rider select, redrawn as vector art).
##
## - Left/right (edge-detected, repeating after a short hold) cycles the
##   animal chef through Game.roster, skipping chefs another seat picked.
## - Up/down cycles the chef hat colour (Palette.HATS).
## - "a" readies (a tick), "b" un-readies.
## - FLIPPER (the toddler): any press cycles to the next chef and hat; it
##   auto-readies after FLIPPER_IDLE seconds without a press.
## - The cook's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the cook's start,
##   writes Players.riders + Game.hats and goes to the kitchen.

const VA := preload("res://scripts/vector_art.gd")
const Pal := preload("res://scripts/kitchen/palette.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const FLIPPER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 360
const COL_H := 600
const COL_Y := 50
const FLIPPER := 2

var auto_goto := true
var next_screen := ""

## seat -> chef id ("" when the seat is empty)
var picks: Array[String] = ["", "", ""]
var hat_picks: Array[int] = [0, 1, 2]
var readied: Array[bool] = [false, false, false]
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _vdir: Array[int] = [0, 0, 0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[float] = [0.0, 0.0, 0.0]


func _ready() -> void:
	_default_picks()
	hat_picks = Game.hats.duplicate()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var gap := 40
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (1280 - total) / 2.0
	for i in seated.size():
		_col_x[seated[i]] = x0 + i * (COL_W + gap)
	Sfx.music("music_menu")
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func _default_picks() -> void:
	# Keep valid, distinct picks from the last round; otherwise seat n gets
	# chef n, or the next free one.
	var taken: Array[String] = []
	for s in Players.SEAT_COUNT:
		var r: String = Players.riders[s]
		if Players.is_seated(s) and Game.roster.has(r) and not taken.has(r):
			picks[s] = r
			taken.append(r)
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s) or picks[s] != "":
			continue
		var want: String = Game.roster[s % Game.roster.size()]
		if taken.has(want):
			want = _next_free(s, -1, 1)
		picks[s] = want
		taken.append(want)


## Next chef from roster index `from` in direction `step` that no other seat has.
func _next_free(seat: int, from: int, step: int) -> String:
	var n := Game.roster.size()
	var i := from
	for _k in n:
		i = posmod(i + step, n)
		var r := Game.roster[i]
		if not _taken_by_other(seat, r):
			return r
	return picks[seat]


func _taken_by_other(seat: int, chef: String) -> bool:
	for s in Players.SEAT_COUNT:
		if s != seat and picks[s] == chef:
			return true
	return false


func cycle(seat: int, step: int) -> void:
	var r := _next_free(seat, Game.roster.find(picks[seat]), step)
	if r == picks[seat]:
		return
	picks[seat] = r
	_bump[seat] = 0.2
	Sfx.play("whoosh", 1.2 + 0.1 * seat, -6.0)


func cycle_hat(seat: int, step: int) -> void:
	hat_picks[seat] = posmod(hat_picks[seat] + step, Pal.HATS.size())
	_bump[seat] = 0.2
	Sfx.play("select", 1.1 + 0.1 * seat, -4.0)


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
			if s == FLIPPER:
				_flipper(delta)
			else:
				_seat_input(s, delta)
	if next_screen != "":
		return
	if Players.just_pressed(0, "start"):
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
	queue_redraw()


func _seat_input(s: int, delta: float) -> void:
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		_hold_dir[s] = Players.dir4(s).x
		return
	if s == 0 and Players.just_pressed(s, "b"):
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
	var dy := Players.dir4(s).y
	if dy != 0 and dy != _vdir[s]:
		cycle_hat(s, dy)
	_vdir[s] = dy
	if Players.just_pressed(s, "a"):
		set_ready(s, true)


func _flipper(delta: float) -> void:
	var s := FLIPPER
	if Players.just_pressed(s, "any"):
		cycle(s, 1)
		hat_picks[s] = posmod(hat_picks[s] + 1, Pal.HATS.size())
		set_ready(s, false)
		_idle[s] = 0.0
		return
	_idle[s] += delta
	if _idle[s] >= FLIPPER_IDLE:
		set_ready(s, true)


func _all_ready() -> bool:
	var any := false
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			any = true
			if not readied[s]:
				return false
	return any


## Cook's "b" while not ready: back to join, seats kept (no Players.reset).
func _back_to_join() -> void:
	Sfx.play("whoosh")
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _advance() -> void:
	for s in Players.SEAT_COUNT:
		Players.riders[s] = picks[s] if Players.is_seated(s) else ""
	Game.hats = hat_picks.duplicate()
	Sfx.play("select")
	next_screen = "kitchen"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("kitchen")


# ---------------------------------------------------------------- view

func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Pal.WALL)
	draw_rect(Rect2(0, 0, 1280, 360), Pal.TILES)
	for x in range(0, 1281, 64):
		draw_line(Vector2(x, 0), Vector2(x, 360), Pal.TILE_LINE, 3.0)
	for y in range(0, 361, 58):
		draw_line(Vector2(0, y), Vector2(1280, y), Pal.TILE_LINE, 3.0)
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			_draw_column(s)
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 1280.0
		draw_rect(Rect2(0, 700, w, 14), Color("#6cc36c"))


func _draw_column(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
	VA.rrect(self, r, 34, col.lerp(Color.WHITE, 0.6 if not readied[s] else 0.3), 6.0)
	var cx := r.position.x + COL_W / 2.0
	VA.role_icon(self, s, Vector2(cx, COL_Y + 62), col, 1.4)
	# The stage and the chef on it.
	VA.ellipse(self, Vector2(cx, COL_Y + 470), 120, 22, col.darkened(0.1), 5.0)
	var hop := -12.0 if _bump[s] > 0.0 else 0.0
	var cheer := -absf(sin(_time * 8.0)) * 14.0 if readied[s] else 0.0
	var o := {"hat": Pal.HATS[hat_picks[s]], "arms": 0.9 if readied[s] else 0.15,
		"mouth": "grin" if readied[s] else "smile", "eyes": "happy" if readied[s] else "open",
		"look": Vector2(sin(_time * 1.3 + s) * 0.6, 0.2)}
	VA.creature(self, Transform2D(0.0, Vector2(1.05, 1.05), 0.0, Vector2(cx, COL_Y + 470 + hop + cheer)), picks[s], o)
	if not readied[s]:
		var wig := sin(_time * 6.0) * 5.0
		_arrow(Vector2(cx - 150 - wig, COL_Y + 330), -1, col)
		_arrow(Vector2(cx + 150 + wig, COL_Y + 330), 1, col)
	# Hat colour dots (up/down) and roster dots (left/right).
	for i in Pal.HATS.size():
		var hc := Vector2(cx - 100 + i * 40, COL_Y + 525)
		VA.circle(self, hc, 15 if i == hat_picks[s] else 10, Pal.HATS[i], 4.0 if i == hat_picks[s] else 3.0)
	var n := Game.roster.size()
	for i in n:
		var rr := Game.roster[i]
		var c := Color(Pal.OUTLINE, 0.25)
		if rr == picks[s]:
			c = Pal.OUTLINE
		elif _taken_by_other(s, rr):
			c = Color(Pal.OUTLINE, 0.08)
		draw_circle(Vector2(cx - (n - 1) * 14 + i * 28, COL_Y + 565), 8, c, true, -1.0, true)
	if s == FLIPPER and not readied[s]:
		var w := clampf(_idle[s] / FLIPPER_IDLE, 0.0, 1.0) * 200.0
		VA.rrect(self, Rect2(cx - 100, COL_Y + 585, 200, 12), 6, Color(1, 1, 1, 0.7), 3.0)
		if w > 12.0:
			draw_colored_polygon(VA.rrect_pts(Rect2(cx - 100, COL_Y + 585, w, 12), 6), col.darkened(0.2))
	if readied[s]:
		_tick(Vector2(cx + 120, COL_Y + 130))


func _arrow(c: Vector2, dir: int, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-18 * dir, -30), c + Vector2(22 * dir, 0), c + Vector2(-18 * dir, 30)])
	VA.shape(self, pts, col, 5.0)


func _tick(c: Vector2) -> void:
	VA.circle(self, c, 34, Color("#6cc36c"), 5.0)
	draw_polyline(PackedVector2Array([c + Vector2(-16, 0), c + Vector2(-4, 13), c + Vector2(17, -13)]), Color.WHITE, 9.0, true)
