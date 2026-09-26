extends Node2D
## Rider select: one column per seated seat. Logic copied from PixelPals
## (games/pixelpals/game/scripts/screens/select.gd), redrawn in vectors:
##
## - Left/right (edge-detected, repeating after a short hold) cycles through
##   Game.roster, skipping riders another seat already picked.
## - "a" readies (tick), "b" un-readies.
## - HONKER: any press cycles to the next rider; it auto-readies after
##   HONKER_IDLE seconds without a press.
## - The driver's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the driver's start,
##   writes Players.riders and goes to the level.
## The toy train below shows each pick in its seat: the driver in the cab,
## the kids on the tender, waving.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Icons := preload("res://scripts/screens/icons.gd")
const MenuTrain := preload("res://scripts/screens/menu_train.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 330
const COL_H := 390
const COL_Y := 24

var auto_goto := true
var next_screen := ""

var picks: Array[String] = ["", "", ""]
var readied: Array[bool] = [false, false, false]
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[float] = [0.0, 0.0, 0.0]
var _sprites := {}  # seat -> AnimatedSprite2D
var train: Node2D


func _ready() -> void:
	_default_picks()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var gap := 40.0
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (1280.0 - total) * 0.5
	for i in seated.size():
		var s := seated[i]
		_col_x[s] = x0 + i * (COL_W + gap)
		var spr := AnimatedSprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(7, 7)
		spr.z_index = 1
		add_child(spr)
		_sprites[s] = spr
		_set_sprite(s)
	train = MenuTrain.new()
	add_child(train)
	train.setup(Vector2(1000, 560), _seated_picks(), 1, 1.8)
	Sfx.music("music_menu")
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func _seated_picks() -> Array[String]:
	var out: Array[String] = []
	for s in Players.SEAT_COUNT:
		out.append(picks[s] if Players.is_seated(s) else "")
	return out


func _set_sprite(s: int) -> void:
	if not _sprites.has(s) or picks[s] == "":
		return
	_sprites[s].sprite_frames = Art.frames(picks[s], Palette.WHITE, Vector2i(16, 16))
	_sprites[s].play("default")


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
	Sfx.play("whoosh", 1.2 + 0.1 * seat, -6.0)
	_set_sprite(seat)
	if train:
		train.view.set_riders(_seated_picks())


func set_ready(seat: int, value: bool) -> void:
	if readied[seat] == value:
		return
	readied[seat] = value
	if value:
		Sfx.play("ready", 1.0 + 0.1 * seat)
		if train:
			train.toot()


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
	Sfx.play("whoosh")
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
	for s in _sprites:
		var cx := _col_x[s] + COL_W * 0.5
		var hop := -10.0 if _bump[s] > 0.0 else 0.0
		var cheer := -absf(sin(_time * 8.0)) * 12.0 if readied[s] else 0.0
		_sprites[s].position = Vector2(cx, COL_Y + 205 + hop + cheer)


func _draw() -> void:
	Icons.backdrop(self, _time)
	for s in _sprites:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		Shapes.fill_outline(self, Shapes.rounded_rect(r, 28), col if readied[s] else col.lightened(0.25), 4.0)
		var cx := _col_x[s] + COL_W * 0.5
		Icons.role(self, s, Vector2(cx, COL_Y + 62), 1.3, col.lightened(0.5))
		# The rider's round window, like on the train.
		Shapes.fill_outline(self, Shapes.circle(Vector2(cx, COL_Y + 200), 78, 40), Palette.SKY.lightened(0.35), 5.0)
		if not readied[s]:
			var wig := sin(_time * 6.0) * 4.0
			Icons.side_arrow(self, Vector2(cx - 120 - wig, COL_Y + 200), 1.4, -1, Palette.WHITE)
			Icons.side_arrow(self, Vector2(cx + 120 + wig, COL_Y + 200), 1.4, 1, Palette.WHITE)
		else:
			Icons.check(self, Vector2(cx, COL_Y + 345), 1.4)
		if s == Players.Seat.HONKER and not readied[s]:
			var w := clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 160.0
			Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(cx - 80, COL_Y + 338, 160, 16), 8), Color(Palette.INK, 0.3), 2.0)
			if w > 8.0:
				draw_colored_polygon(Shapes.rounded_rect(Rect2(cx - 80, COL_Y + 338, w, 16), 8), Palette.WHITE)
		# Roster dots: own pick bright, others' picks dark.
		var n := Game.roster.size()
		var dx0 := cx - (n * 22 - 8) * 0.5
		for i in n:
			var rr := Game.roster[i]
			var c := Color(Palette.WHITE, 0.45)
			if rr == picks[s]:
				c = Palette.WHITE
			elif _taken_by_other(s, rr):
				c = Color(Palette.INK, 0.6)
			draw_circle(Vector2(dx0 + i * 22 + 7, COL_Y + 305), 7 if rr == picks[s] else 5, c)
	if _advance_t >= 0.0:
		var w := clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 1280.0
		draw_rect(Rect2(0, 700, w, 14), Palette.WHITE)
