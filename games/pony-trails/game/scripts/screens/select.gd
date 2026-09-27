extends Node2D
## Select: one column per seated seat, every rider in a riding helmet in the
## seat's colour, and the horses.
##
## - Left/right (edge-detected, repeating after a short hold) cycles the
##   rider through Game.roster, skipping riders another seat already picked.
## - The Rider's up/down picks the mare's coat (bay, chestnut, palomino,
##   grey, black, pinto); the Foal seat's up/down the foal's coat (the same
##   plus appaloosa). The horses trot in place in their coats.
## - "a" readies (check icon), "b" un-readies. Once the Rider is ready, their
##   left/right moves the start-stage row (stable, trail, show).
## - NEIGH seat: any press cycles to the next rider; it auto-readies after
##   HONKER_IDLE seconds without a press.
## - The Rider's "b" while not ready goes back to join (seats kept).
## - All seated seats ready (after a short beat), or the Rider's start,
##   writes the picks and starts the day at the chosen stage.

const AnimSprite := preload("res://scripts/view/anim_sprite.gd")
const Backdrop := preload("res://scripts/view/backdrop.gd")

const REPEAT_DELAY := 0.35
const REPEAT_EVERY := 0.18
const HONKER_IDLE := 3.0
const ADVANCE_BEAT := 1.2
const COL_W := 96
const COL_H := 132
const COL_Y := 6
const ROLE_ICONS: Array[String] = ["seat_rider", "seat_brush", "seat_neigh"]
const STAGE_ICONS: Array[String] = ["stage_stable", "stage_trail", "stage_show"]
const STAGE_Y := 158
const INK := Color("#181425")
const WHITE := Color("#ffffff")

var auto_goto := true
var next_screen := ""

## seat -> rider id ("" when the seat is empty)
var picks: Array[String] = ["", "", ""]
var readied: Array[bool] = [false, false, false]
var mare_coat := 0
var foal_coat := 0
var start_stage := 0
var _hold_dir: Array[int] = [0, 0, 0]
var _hold_time: Array[float] = [0.0, 0.0, 0.0]
var _idle: Array[float] = [0.0, 0.0, 0.0]
var _bump: Array[float] = [0.0, 0.0, 0.0]
var _advance_t := -1.0
var _time := 0.0
var _col_x: Array[int] = [0, 0, 0]
var _nodes := {}  # seat -> {"rider", "left", "right", "check", "role", "horse", "up", "down"}
var _stages: Array[AnimatedSprite2D] = []
var _backdrop: Node2D


func _ready() -> void:
	start_stage = clampi(Game.start_stage, 0, 2)
	mare_coat = maxi(0, Game.MARE_COATS.find(Game.mare_coat))
	foal_coat = maxi(0, Game.FOAL_COATS.find(Game.foal_coat))
	_backdrop = Backdrop.new()
	_backdrop.z_index = -1
	add_child(_backdrop)
	for i in STAGE_ICONS.size():
		var p := Art.sprite(STAGE_ICONS[i], Color("#feae34"), Vector2i(16, 16))
		p.position = Vector2(124 + i * 36, STAGE_Y + 8)
		p.z_index = 2
		add_child(p)
		_stages.append(p)
	_default_picks()
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	var gap := 8
	var total := seated.size() * COL_W + maxi(0, seated.size() - 1) * gap
	var x0 := int((320 - total) / 2.0)
	for i in seated.size():
		var s := seated[i]
		_col_x[s] = x0 + i * (COL_W + gap)
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


func _jockey(seat: int, rider: String) -> String:
	return "jockey_%s_%d" % [rider, seat]


func cycle(seat: int, step: int) -> void:
	var r := _next_free(seat, Game.roster.find(picks[seat]), step)
	if r == picks[seat]:
		return
	picks[seat] = r
	_bump[seat] = 0.2
	Sfx.play("whoosh", 1.2 + 0.1 * seat, -6.0)
	if _nodes.has(seat):
		_nodes[seat].rider.sprite_frames = Art.frames(_jockey(seat, r), Game.rider_color(r), Vector2i(16, 16))
		_nodes[seat].rider.play("default")


func cycle_coat(seat: int, step: int) -> void:
	if seat == Players.Seat.DRIVER:
		mare_coat = posmod(mare_coat + step, Game.MARE_COATS.size())
		Game.mare_coat = Game.MARE_COATS[mare_coat]
	elif seat == Players.Seat.GUNNER:
		foal_coat = posmod(foal_coat + step, Game.FOAL_COATS.size())
		Game.foal_coat = Game.FOAL_COATS[foal_coat]
	else:
		return
	_bump[seat] = 0.2
	Sfx.play("nicker" if seat == Players.Seat.DRIVER else "foal_neigh", 1.0, -4.0)
	_refresh_horse(seat)


func set_ready(seat: int, value: bool) -> void:
	if readied[seat] == value:
		return
	readied[seat] = value
	if value:
		Sfx.play("ready", 1.0 + 0.1 * seat)


func set_stage(i: int) -> void:
	var v := clampi(i, 0, STAGE_ICONS.size() - 1)
	if v != start_stage:
		start_stage = v
		_advance_t = -1.0
		Sfx.play("select", 1.0 + 0.15 * v)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
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
	_backdrop.tick(delta)
	for i in _stages.size():
		_stages[i].position.y = STAGE_Y + 8 - (1 if i == start_stage and int(_time * 3.0) % 2 == 0 else 0)
	_layout(delta)
	queue_redraw()


func _seat_input(s: int, delta: float) -> void:
	if readied[s]:
		if Players.just_pressed(s, "b"):
			set_ready(s, false)
		elif s == Players.Seat.DRIVER:
			var f := Players.dir4_just_pressed(s)
			if f.x != 0:
				set_stage(start_stage + f.x)
		_hold_dir[s] = Players.dir4(s).x
		return
	if s == Players.Seat.DRIVER and Players.just_pressed(s, "b"):
		_back_to_join()
		return
	var flick := Players.dir4_just_pressed(s)
	if flick.y != 0:
		cycle_coat(s, flick.y)
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
		Sfx.play("neigh", 1.1, -6.0)
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
	Game.mare_coat = Game.MARE_COATS[mare_coat]
	Game.foal_coat = Game.FOAL_COATS[foal_coat]
	Game.start_stage = start_stage
	Game.new_day()
	next_screen = Game.start_screen()
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


# ---------------------------------------------------------------- view

func _build_column(s: int) -> void:
	var cx := _col_x[s] + int(COL_W / 2.0)
	var col: Color = Players.SEAT_COLORS[s]
	var role := Art.sprite(ROLE_ICONS[s], col.lightened(0.3), Vector2i(16, 16))
	role.position = Vector2(cx, COL_Y + 13)
	add_child(role)
	var rider := Art.sprite(_jockey(s, picks[s]), Game.rider_color(picks[s]), Vector2i(16, 16))
	rider.scale = Vector2(2, 2)
	add_child(rider)
	var left := Art.sprite("arrow_left", WHITE, Vector2i(8, 8))
	var right := Art.sprite("arrow_right", WHITE, Vector2i(8, 8))
	add_child(left)
	add_child(right)
	var check := Art.sprite("check", Color("#63c74d"), Vector2i(8, 8))
	check.scale = Vector2(2, 2)
	add_child(check)
	var n := {"role": role, "rider": rider, "left": left, "right": right, "check": check}
	if s != Players.Seat.HONKER:
		var horse := AnimSprite.new()
		if s == Players.Seat.DRIVER:
			horse.setup("mare_" + Game.MARE_COATS[mare_coat], "mare", Vector2i(40, 32), Game.coat_color(Game.MARE_COATS[mare_coat]))
		else:
			horse.setup("foal_" + Game.FOAL_COATS[foal_coat], "foal", Vector2i(24, 20), Game.coat_color(Game.FOAL_COATS[foal_coat]))
		horse.play("trot")
		add_child(horse)
		n["horse"] = horse
		var up := Art.sprite("arrow_up", WHITE, Vector2i(8, 8))
		var down := Art.sprite("arrow_down", WHITE, Vector2i(8, 8))
		add_child(up)
		add_child(down)
		n["up"] = up
		n["down"] = down
	_nodes[s] = n


func _refresh_horse(s: int) -> void:
	if not _nodes.has(s) or not _nodes[s].has("horse"):
		return
	var h = _nodes[s].horse
	if s == Players.Seat.DRIVER:
		h.set_sprite("mare_" + Game.MARE_COATS[mare_coat])
	else:
		h.set_sprite("foal_" + Game.FOAL_COATS[foal_coat])


func _layout(delta: float) -> void:
	for s in _nodes:
		var n: Dictionary = _nodes[s]
		var cx := _col_x[s] + int(COL_W / 2.0)
		var hop := -2 if _bump[s] > 0.0 else 0
		var cheer := -(int(_time * 4.0) % 2) * 2 if readied[s] else 0
		n.rider.position = Vector2(cx, COL_Y + 44 + hop + cheer)
		var wiggle := int(_time * 3.0) % 2
		var show_arrows := not readied[s]
		n.left.visible = show_arrows
		n.right.visible = show_arrows
		n.left.position = Vector2(cx - 26 - wiggle, COL_Y + 44)
		n.right.position = Vector2(cx + 26 + wiggle, COL_Y + 44)
		n.check.visible = readied[s]
		n.check.position = Vector2(cx + 30, COL_Y + 13)
		if n.has("horse"):
			n.horse.tick(delta)
			n.horse.position = Vector2(cx, COL_Y + 112 + hop)
			n.up.visible = show_arrows
			n.down.visible = show_arrows
			n.up.position = Vector2(cx + 34, COL_Y + 92 - wiggle)
			n.down.position = Vector2(cx + 34, COL_Y + 106 + wiggle)


func _draw() -> void:
	# The stage row: the chosen start sits on a bright frame in the Rider's colour;
	# once the Rider is ready, arrows invite them to move it.
	var pc: Color = Players.SEAT_COLORS[Players.Seat.DRIVER]
	draw_rect(Rect2(98, STAGE_Y - 4, 124, 26), Color(INK, 0.7))
	for i in STAGE_ICONS.size():
		var r := Rect2(124 + i * 36 - 12, STAGE_Y - 4 + 1, 24, 24)
		if i == start_stage:
			draw_rect(r, pc)
			draw_rect(r.grow(-2), INK)
		if i < STAGE_ICONS.size() - 1:
			draw_rect(Rect2(124 + i * 36 + 13, STAGE_Y + 8, 10, 2), Color(WHITE, 0.4))
	if readied[Players.Seat.DRIVER] and int(_time * 3.0) % 2 == 0:
		draw_colored_polygon(PackedVector2Array([Vector2(92, STAGE_Y + 9), Vector2(97, STAGE_Y + 4), Vector2(97, STAGE_Y + 14)]), pc)
		draw_colored_polygon(PackedVector2Array([Vector2(228, STAGE_Y + 9), Vector2(223, STAGE_Y + 4), Vector2(223, STAGE_Y + 14)]), pc)
	for s in _nodes:
		var col: Color = Players.SEAT_COLORS[s]
		var r := Rect2(_col_x[s], COL_Y, COL_W, COL_H)
		draw_rect(r, col if readied[s] else col.darkened(0.2))
		draw_rect(r.grow(-2), col.darkened(0.6))
		var cx := _col_x[s] + int(COL_W / 2.0)
		# A little stable floor under each rider and horse.
		draw_rect(Rect2(cx - 22, COL_Y + 61, 44, 3), col)
		# Roster dots: one per rider, own pick bright, others' picks dimmed.
		var n := Game.roster.size()
		var dx0 := cx - int((n * 6 - 2) / 2.0)
		for i in n:
			var rr := Game.roster[i]
			var c := Color(WHITE, 0.25)
			if rr == picks[s]:
				c = WHITE
			elif _taken_by_other(s, rr):
				c = Color(INK, 0.8)
			draw_rect(Rect2(dx0 + i * 6, COL_Y + 68, 4, 4), c)
		if s != Players.Seat.HONKER:
			# The coat dots: one per coat in its colour, the chosen one framed.
			var coats: Array[String] = Game.MARE_COATS if s == Players.Seat.DRIVER else Game.FOAL_COATS
			var chosen := mare_coat if s == Players.Seat.DRIVER else foal_coat
			var m := coats.size()
			var cx0 := cx - int((m * 8 - 2) / 2.0)
			for i in m:
				var rr := Rect2(cx0 + i * 8, COL_Y + 118, 6, 6)
				if i == chosen:
					draw_rect(rr.grow(1), WHITE)
				draw_rect(rr, Game.coat_color(coats[i]))
			draw_rect(Rect2(cx - 30, COL_Y + 113, 60, 2), Color("#733e39"))
		else:
			# The NEIGH seat's idle bar fills toward the automatic ready.
			if not readied[s]:
				var w := int(clampf(_idle[s] / HONKER_IDLE, 0.0, 1.0) * 40.0)
				draw_rect(Rect2(cx - 20, COL_Y + 100, 40, 4), Color(INK, 0.6))
				draw_rect(Rect2(cx - 20, COL_Y + 100, w, 4), col)
	if _advance_t >= 0.0:
		var w := int(clampf(_advance_t / ADVANCE_BEAT, 0.0, 1.0) * 320.0)
		draw_rect(Rect2(0, 177, w, 3), WHITE)
