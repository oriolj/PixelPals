extends Node2D
## Select: first every seat picks its rider (PixelPals's rules), then the
## Lead picks the song on three album covers (sun, rocket, cat).
##
## Riders phase: one column per seated seat.
## - Left/right (edge, repeating after a short hold) cycles Game.roster,
##   skipping riders another seat picked; "a" readies, "b" un-readies.
## - Crasher: any press cycles; it auto-readies after CRASHER_IDLE seconds.
## - The Lead's "b" while not ready goes back to join (seats kept).
## - All ready (after a short beat), or the Lead's start -> song phase.
## Song phase: the Lead's left/right moves between covers, "a"/start plays
## it, "b" goes back to the riders. The other riders dance meanwhile, and
## any press of theirs makes them hop.

const Draw := preload("res://scripts/view/draw.gd")
const Garage := preload("res://scripts/view/garage.gd")
const Songs := preload("res://scripts/music/songs.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const CRASHER_IDLE := 3.0
const ADVANCE_BEAT := 0.6
const COL_W := 176
const COL_H := 250
const COL_Y := 30
const LEAD := 0
const CRASHER := 2

var auto_goto := true
var next_screen := ""
var phase := "riders"

var picks: Array[String] = ["", "", ""]
var readied: Array[bool] = [false, false, false]
var song := 0
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _song_bump := 0.0
var _col_x: Array[int] = [0, 0, 0]
var _sprites: Array = [null, null, null]
var _garage: Node2D
var _front: Node2D


func _ready() -> void:
	song = Game.song_index
	_default_picks()
	_garage = Garage.new()
	add_child(_garage)
	_front = Front.new()
	_front.screen = self
	add_child(_front)
	var seated := seated_seats()
	var gap := 16
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := (640 - total) / 2
	for i in seated.size():
		var s: int = seated[i]
		_col_x[s] = x0 + i * (COL_W + gap)
		var spr: AnimatedSprite2D = Game.rider_sprite(picks[s], 4)
		add_child(spr)
		_sprites[s] = spr
	Sfx.music("music_menu")
	_layout()
	if seated.is_empty() and auto_goto:
		Game.goto.call_deferred("join")


func seated_seats() -> Array[int]:
	var out: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			out.append(s)
	return out


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
		var want := "penguin" if s == LEAD and Game.roster.has("penguin") else ""
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
	if _sprites[seat]:
		_sprites[seat].sprite_frames = Art.frames(r, Game.rider_color(r), Vector2i(16, 16))
		_sprites[seat].play("default")


func set_ready(seat: int, value: bool) -> void:
	if readied[seat] == value:
		return
	readied[seat] = value
	if value:
		Sfx.play("ready", 1.0 + 0.1 * seat)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	_time += delta
	_song_bump = maxf(0.0, _song_bump - delta)
	for s in Players.SEAT_COUNT:
		_bump[s] = maxf(0.0, _bump[s] - delta)
	if next_screen == "":
		if phase == "riders":
			_riders_phase(delta)
		else:
			_song_phase()
	_garage.beat = 0.5 + 0.5 * sin(_time * 5.0)
	_layout()
	_front.queue_redraw()


func _riders_phase(delta: float) -> void:
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s) or next_screen != "":
			continue
		if s == CRASHER:
			_crasher(delta)
		else:
			_seat_input(s, delta)
	if next_screen != "":
		return
	if Players.just_pressed(LEAD, "start"):
		_to_songs()
		return
	if _all_ready():
		if _advance_t < 0.0:
			_advance_t = 0.0
		_advance_t += delta
		if _advance_t >= ADVANCE_BEAT:
			_to_songs()
	else:
		_advance_t = -1.0


func _seat_input(s: int, delta: float) -> void:
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		_hold_dir[s] = Players.dir4(s).x
		return
	if s == LEAD and Players.just_pressed(s, "b"):
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


func _crasher(delta: float) -> void:
	if Players.just_pressed(CRASHER, "any"):
		cycle(CRASHER, 1)
		set_ready(CRASHER, false)
		_idle[CRASHER] = 0.0
		return
	_idle[CRASHER] += delta
	if _idle[CRASHER] >= CRASHER_IDLE:
		set_ready(CRASHER, true)


func _all_ready() -> bool:
	var any := false
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			any = true
			if not readied[s]:
				return false
	return any


func _to_songs() -> void:
	for s in Players.SEAT_COUNT:
		Players.riders[s] = picks[s] if Players.is_seated(s) else ""
		readied[s] = true
	phase = "songs"
	_advance_t = -1.0
	Sfx.play("select")


func _song_phase() -> void:
	var d := Players.dir4_just_pressed(LEAD)
	if d.x != 0:
		song = posmod(song + d.x, Songs.count())
		_song_bump = 0.25
		Sfx.play("select", [1.0, 1.26, 0.84][song])
	if Players.just_pressed(LEAD, "a") or Players.just_pressed(LEAD, "start"):
		_start_song()
		return
	if Players.just_pressed(LEAD, "b"):
		phase = "riders"
		for s in Players.SEAT_COUNT:
			readied[s] = false
		Sfx.play("select", 0.7)
		return
	for s in [1, 2]:
		if Players.is_seated(s) and Players.just_pressed(s, "any"):
			_bump[s] = 0.25


func _back_to_join() -> void:
	Sfx.play("select", 0.7)
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _start_song() -> void:
	Game.song_index = song
	Sfx.play("ready")
	next_screen = "play"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("play")


# ---------------------------------------------------------------- view

func _layout() -> void:
	for s in Players.SEAT_COUNT:
		var spr: AnimatedSprite2D = _sprites[s]
		if spr == null:
			continue
		if phase == "riders":
			spr.scale = Vector2(4, 4)
			var cx := _col_x[s] + COL_W / 2
			var hop := -6.0 if _bump[s] > 0.0 else 0.0
			var cheer := -float(int(_time * 4.0) % 2) * 4.0 if readied[s] else 0.0
			spr.position = Vector2(cx, COL_Y + 130 + hop + cheer)
		else:
			spr.scale = Vector2(3, 3)
			var x: float = [250.0, 320.0, 390.0][s]
			var hop2 := -absf(sin(_time * 5.0 + s)) * 6.0 - (10.0 if _bump[s] > 0.0 else 0.0)
			spr.position = Vector2(x, 284 - 24 + hop2)


class Front extends Node2D:
	var screen: Node2D

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 640, 360), Color(Draw.INK, 0.3))
		if screen.phase == "riders":
			_riders()
		else:
			_songs()

	func _riders() -> void:
		var t: float = screen._time
		for s in screen.seated_seats():
			var col: Color = Players.SEAT_COLORS[s]
			var r := Rect2(screen._col_x[s], screen.COL_Y, screen.COL_W, screen.COL_H)
			Draw.panel(self, r, col, screen.readied[s])
			var cx := r.position.x + r.size.x / 2.0
			Draw.role_icon(self, s, Vector2(cx, r.position.y + 44), 1.6, t)
			Draw.ellipse(self, Vector2(cx, r.position.y + 164), 44, 8, col.darkened(0.3))
			if not screen.readied[s]:
				var wig := float(int(t * 3.0) % 2) * 2.0
				Draw.arrow(self, Vector2(cx - 64 - wig, r.position.y + 130), 1.4, -1.0, Draw.WHITE)
				Draw.arrow(self, Vector2(cx + 64 + wig, r.position.y + 130), 1.4, 1.0, Draw.WHITE)
			else:
				draw_circle(Vector2(cx, r.position.y + 222), 14, Draw.GREEN)
				Draw.check(self, Vector2(cx, r.position.y + 222), 1.3, Draw.WHITE)
			if s == screen.CRASHER and not screen.readied[s]:
				var w := clampf(screen._idle[s] / screen.CRASHER_IDLE, 0.0, 1.0) * 80.0
				draw_rect(Rect2(cx - 40, r.position.y + 218, 80, 8), Color(Draw.INK, 0.6))
				draw_rect(Rect2(cx - 40, r.position.y + 218, w, 8), col)
			# Roster dots: own pick bright, others' picks dark.
			var n := Game.roster.size()
			var dx0 := cx - (n * 12 - 4) / 2.0
			for i in n:
				var rr := Game.roster[i]
				var c := Color(Draw.WHITE, 0.25)
				if rr == screen.picks[s]:
					c = Draw.WHITE
				elif screen._taken_by_other(s, rr):
					c = Color(Draw.INK, 0.8)
				draw_circle(Vector2(dx0 + i * 12 + 4, r.position.y + 190), 4, c)
		if screen._advance_t >= 0.0:
			var w2 := clampf(screen._advance_t / screen.ADVANCE_BEAT, 0.0, 1.0) * 640.0
			draw_rect(Rect2(0, 350, w2, 6), Draw.WHITE)

	func _songs() -> void:
		var t: float = screen._time
		Draw.round_rect(self, Rect2(20, 44, 600, 196), 18, Color(Draw.INK, 0.75))
		for i in Songs.count():
			var id: String = Songs.IDS[i]
			var sel: bool = i == screen.song
			var c := Vector2(176 + i * 144, 128)
			var size := 112.0 if sel else 84.0
			if sel:
				c.y -= absf(sin(t * 4.0)) * 6.0 + screen._song_bump * 20.0
				var col: Color = Songs.get_song(i).color
				draw_circle(c, 80 + 4 * sin(t * 6.0), Color(col, 0.25))
				Draw.round_rect(self, Rect2(c - Vector2(size, size) / 2 - Vector2(6, 6), Vector2(size + 12, size + 12)), 12, Draw.WHITE)
			var r := Rect2(c - Vector2(size, size) / 2, Vector2(size, size))
			Draw.cover(self, id, r, t if sel else 0.0)
			if not sel:
				Draw.round_rect(self, r, 6, Color(Draw.INK, 0.45))
			# Tempo marks under each cover: 1 note = slow, 3 = fast.
			var notes := {"cat": 1, "sun": 2, "rocket": 3}[id] as int
			for k in notes:
				Draw.note(self, Vector2(c.x - (notes - 1) * 9 + k * 18, 222), 0.8, Draw.WHITE if sel else Draw.GREY)
		var wig := float(int(t * 3.0) % 2) * 3.0
		Draw.arrow(self, Vector2(40 - wig, 128), 2.0, -1.0, Draw.WHITE)
		Draw.arrow(self, Vector2(600 + wig, 128), 2.0, 1.0, Draw.WHITE)
		Draw.round_rect(self, Rect2(286, 312, 68, 36), 10, Draw.GREEN)
		Draw.play_triangle(self, Vector2(322, 330), 1.1, Draw.WHITE)
