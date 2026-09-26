extends Node2D
## The paint screen: one big picture on an easel, painted together.
##
## - Seat 1, Brush (adult): moves the round brush, "a" held paints, "b"
##   cycles the size, "start" opens the menu (undo, frame it, keep painting,
##   surprise splats when there is no Splatter, back to join; "b" there goes
##   back to join too).
## - Seat 2, Colourist (5-year-old): each d-pad direction picks one of the 4
##   pots, "a" stamps the next shape at the brush, "b" turns the palette page.
## - Seat 3, Splatter (2-year-old): any press throws a splat onto the least
##   painted part of the canvas (0.5 s cooldown; extra presses giggle).
## Fold-down: with no Colourist the Brush's "b" cycles the colour (size stays
## medium) and a quick tap of "a" stamps. With no Splatter, the menu can turn
## on a surprise splat every 20 s.
##
## Nothing here can end or hurt the picture: only the Brush's menu undoes, and
## the picture autosaves every 30 s.

const Painter := preload("res://scripts/paint/painter.gd")
const Palette := preload("res://scripts/paint/palette.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")
const Coverage := preload("res://scripts/paint/coverage.gd")
const Splatter := preload("res://scripts/paint/splatter.gd")
const Stroke := preload("res://scripts/paint/stroke.gd")
const UndoRing := preload("res://scripts/paint/undo_ring.gd")
const Autosave := preload("res://scripts/paint/autosave.gd")
const BrushInput := preload("res://scripts/paint/brush_input.gd")
const Kit := preload("res://scripts/ui/draw_kit.gd")

const BRUSH := 0
const COLOURIST := 1
const SPLATTER := 2

const CANVAS_RECT := Rect2(16, 12, 512, 288)
const SCALE := 512.0 / 1920.0
const BRUSH_SPEED := 720.0                 # canvas px per second at full stick
const SIZES: Array[float] = [6.0, 16.0, 36.0]  # dab radii: 12 / 32 / 72 px across
const MEDIUM := 1
const SURPRISE_EVERY := 20.0
const HINT_AFTER := 300.0
const FRAME_SECONDS := 3.6
const FLOOR_Y := 316.0
const CROSS_C := Vector2(588, 92)
const POT_OFFSETS: Array[Vector2] = [Vector2(0, -42), Vector2(29, 0), Vector2(0, 42), Vector2(-29, 0)]
const PAGES_Y := 180.0
const SIZES_Y := 212.0
const FRAME_ICON := Vector2(588, 256)
const RIDER_X: Array[float] = [72.0, 588.0, 468.0]
const RIDER_Y := 334.0

## Set false in tests: record next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var painter: Painter
var coverage := Coverage.new()
var splatter := Splatter.new()
var stroke := Stroke.new()
var undo := UndoRing.new()
var autosave := Autosave.new()
var brush_in := BrushInput.new()

var brush := Vector2(960, 540)
var size_idx := MEDIUM
var page := 0
var pot := 0
var colour_idx := 0
var stamp_idx := 0
var time := 0.0
var paused := false
var menu_items: Array[String] = []
var menu_sel := 0
var framing := -1.0
var session_id := ""
var surprise_t := 0.0
var stats := {"dabs": 0, "stamps": 0, "splats": 0, "rainbows": 0, "giggles": 0, "undos": 0, "autosaves": 0}

var _press_pos := Vector2.ZERO
var _pot_bounce: Array[float] = [0.0, 0.0, 0.0, 0.0]
var _hop: Array[float] = [0.0, 0.0, 0.0]
var _giggle_cd := 0.0
var _last_action_frame := -1
var _steps := 0
var _brush_speed := 0.0
var _effects: Array[Dictionary] = []    # {pos (screen), t, col, kind}
var _confetti: Array[Dictionary] = []
var _riders: Array = [null, null, null]
var _loop: AudioStreamPlayer
var _claps := 0
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.randomize()
	splatter.rng.randomize()
	session_id = Time.get_datetime_string_from_system(true).replace("-", "").replace(":", "").replace("T", "-")
	painter = Painter.new()
	painter.name = "Painter"
	add_child(painter)
	colour_idx = Palette.index(page, pot)
	_build_riders()
	_loop = AudioStreamPlayer.new()
	_loop.stream = _load_loop("res://audio/brush_loop.wav")
	_loop.volume_db = -10.0
	add_child(_loop)
	Sfx.music("music_paint")


func _load_loop(path: String) -> AudioStream:
	var s: AudioStream = null
	if OS.has_feature("template"):
		s = load(path) if ResourceLoader.exists(path) else null
	else:
		var abs := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs):
			s = AudioStreamWAV.load_from_file(abs)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _build_riders() -> void:
	for s in 3:
		if not Players.is_seated(s):
			continue
		var id: String = Players.riders[s]
		if id == "":
			id = Game.roster[s % Game.roster.size()]
		var spr := Art.sprite(id, Game.rider_color(id), Vector2i(16, 16))
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(3, 3)
		spr.flip_h = RIDER_X[s] > CANVAS_RECT.get_center().x
		spr.z_index = 1
		add_child(spr)
		_riders[s] = spr


# ---------------------------------------------------------------- state

func colour() -> Color:
	return Palette.COLORS[colour_idx]


func radius() -> float:
	return SIZES[size_idx]


## With no Colourist the Brush picks colours and taps stamps itself.
func tap_mode() -> bool:
	return not Players.is_seated(COLOURIST)


func wip_path() -> String:
	return Game.paint_dir.path_join("wip-%s.png" % session_id)


func final_path() -> String:
	return Game.paint_dir.path_join("paint-%s.png" % session_id)


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	time += delta
	_steps += 1
	_giggle_cd = maxf(0.0, _giggle_cd - delta)
	for i in 4:
		_pot_bounce[i] = maxf(0.0, _pot_bounce[i] - delta)
	for i in 3:
		_hop[i] = maxf(0.0, _hop[i] - delta)
	splatter.tick(delta)
	if next_screen != "":
		return
	if framing >= 0.0:
		_framing_step(delta)
	elif paused:
		_menu_input()
		_toddler_giggles_only()
	else:
		if Players.just_pressed(BRUSH, "start"):
			open_menu()
		else:
			_brush_step(delta)
			_colourist_step()
			_splatter_step()
			_surprise_step(delta)
			if autosave.tick(delta):
				_autosave()
	_update_effects(delta)
	_update_riders()
	_update_loop_sound()
	queue_redraw()


func _brush_step(delta: float) -> void:
	var mv := Players.move(BRUSH)
	var prev := brush
	brush = (brush + mv * BRUSH_SPEED * delta).clamp(Vector2.ZERO, Vector2(Painter.SIZE))
	_brush_speed = (brush - prev).length() / maxf(delta, 0.0001)
	if Players.just_pressed(BRUSH, "a"):
		_press_pos = prev
	var moving := mv.length() > Players.DEADZONE
	match brush_in.update(delta, Players.pressed(BRUSH, "a"), moving, tap_mode()):
		"begin":
			begin_action()
			var start := _press_pos if tap_mode() else prev
			_paint_dabs(stroke.begin(start, radius()))
			_paint_dabs(stroke.move_to(brush))
		"paint":
			_paint_dabs(stroke.move_to(brush))
		"end":
			stroke.end()
		"tap":
			stamp()
	if Players.just_pressed(BRUSH, "b"):
		if tap_mode():
			pick_colour((colour_idx + 1) % Palette.COLORS.size())
		else:
			size_idx = (size_idx + 1) % SIZES.size()
			stroke.radius = radius()
			Sfx.play("select", 0.8 + 0.2 * size_idx)
			_hop[BRUSH] = 0.2


func _paint_dabs(dabs: PackedVector2Array) -> void:
	var r := radius()
	var c := colour()
	for p in dabs:
		painter.add_dab(p, r, c)
		coverage.mark_disc(p, r)
	stats.dabs += dabs.size()


func _colourist_step() -> void:
	if tap_mode():
		return
	var d := Players.dir4_just_pressed(COLOURIST)
	if d != Vector2i.ZERO:
		pick_pot(Palette.pot_for_dir(d))
	if Players.just_pressed(COLOURIST, "a"):
		stamp()
	if Players.just_pressed(COLOURIST, "b"):
		turn_page()


func _splatter_step() -> void:
	if Players.is_seated(SPLATTER) and Players.just_pressed(SPLATTER, "any"):
		splat_press()


func _toddler_giggles_only() -> void:
	if Players.is_seated(SPLATTER) and Players.just_pressed(SPLATTER, "any"):
		_giggle()


func _surprise_step(delta: float) -> void:
	if Players.is_seated(SPLATTER) or not Game.surprise_splats:
		surprise_t = 0.0
		return
	surprise_t += delta
	if surprise_t >= SURPRISE_EVERY:
		surprise_t = 0.0
		splatter.since = INF
		splat_press()


# ---------------------------------------------------------------- actions

## Every action (a stroke, a stamp, a splat) keeps the canvas as it was before
## it, for the Brush's undo. Two actions in one frame share one snapshot.
func begin_action() -> void:
	autosave.mark_dirty()
	var frame := _steps
	if frame == _last_action_frame:
		return
	_last_action_frame = frame
	undo.push({"img": painter.snapshot(), "cov": coverage._fine.duplicate()})


func pick_pot(i: int) -> void:
	if i < 0:
		return
	pot = i
	colour_idx = Palette.index(page, pot)
	_pot_bounce[i] = 0.35
	_hop[COLOURIST] = 0.2
	Sfx.play("pot_pick_%d" % (i + 1))


func pick_colour(idx: int) -> void:
	colour_idx = posmod(idx, Palette.COLORS.size())
	page = colour_idx / Palette.POTS
	pot = colour_idx % Palette.POTS
	_pot_bounce[pot] = 0.35
	Sfx.play("pot_pick_%d" % (pot + 1))


func turn_page() -> void:
	page = (page + 1) % Palette.PAGES
	colour_idx = Palette.index(page, pot)
	_pot_bounce[pot] = 0.35
	_hop[COLOURIST] = 0.2
	Sfx.play("page_turn")


func next_stamp() -> String:
	return Shapes.STAMPS[stamp_idx % Shapes.STAMPS.size()]


func stamp() -> void:
	begin_action()
	var kind := next_stamp()
	stamp_idx += 1
	painter.add_stamp(kind, brush, colour())
	coverage.mark_disc(brush, Shapes.STAMP_SIZE * 0.45)
	stats.stamps += 1
	_hop[COLOURIST if not tap_mode() else BRUSH] = 0.3
	_effects.append({"pos": to_screen(brush), "t": 0.0, "col": colour(), "kind": "ring"})
	Sfx.play("stamp")


## The toddler's press: a splat, or a giggle during the cooldown.
func splat_press() -> void:
	if not splatter.ready_to_splat():
		_giggle()
		return
	begin_action()
	var s := splatter.press(coverage)
	painter.add_parts(s.parts)
	coverage.mark_disc(s.center, s.radius * 1.1)
	stats.splats += 1
	if s.rainbow:
		stats.rainbows += 1
		Sfx.play("rainbow")
	else:
		Sfx.play("splat")
	_hop[SPLATTER] = 0.35
	var col: Color = s.parts[s.parts.size() - 1].col
	_effects.append({"pos": to_screen(s.center), "t": 0.0, "col": col, "kind": "burst"})


func _giggle() -> void:
	stats.giggles += 1
	_hop[SPLATTER] = 0.4
	if _giggle_cd <= 0.0:
		_giggle_cd = 0.35
		Sfx.play("giggle", rng.randf_range(0.9, 1.25))


func do_undo() -> void:
	var e = undo.pop()
	if e == null:
		Sfx.play("select", 0.6, -6.0)
		return
	stroke.end()
	brush_in.reset()
	painter.restore(e.img)
	coverage._fine = e.cov
	stats.undos += 1
	Sfx.play("undo")


func _autosave() -> void:
	if painter.save_png(wip_path()) != null:
		stats.autosaves += 1


# ---------------------------------------------------------------- menu

func open_menu() -> void:
	paused = true
	stroke.end()
	brush_in.reset()
	menu_items = ["undo", "frame", "play"]
	if not Players.is_seated(SPLATTER):
		menu_items.append("splats")
	menu_items.append("back")
	menu_sel = menu_items.find("play")
	Sfx.play("select")


func close_menu() -> void:
	paused = false
	Sfx.play("select", 1.2)


func _menu_input() -> void:
	var dx := Players.dir4_just_pressed(BRUSH).x
	if dx != 0:
		var n := clampi(menu_sel + dx, 0, menu_items.size() - 1)
		if n != menu_sel:
			menu_sel = n
			Sfx.play("select", 1.0 + 0.05 * n, -4.0)
	if Players.just_pressed(BRUSH, "start"):
		close_menu()
		return
	if Players.just_pressed(BRUSH, "b"):
		back_to_join()
		return
	if Players.just_pressed(BRUSH, "a"):
		match menu_items[menu_sel]:
			"undo":
				do_undo()
			"frame":
				frame_it()
			"play":
				close_menu()
			"splats":
				Game.surprise_splats = not Game.surprise_splats
				surprise_t = 0.0
				Sfx.play("splat" if Game.surprise_splats else "select")
			"back":
				back_to_join()


func back_to_join() -> void:
	if autosave.dirty:
		_autosave()
	_leave("join")


## Saves the picture for good, then celebrates and opens the gallery.
func frame_it() -> void:
	paused = false
	framing = 0.0
	_claps = 0
	var path := final_path()
	var img := painter.save_png(path)
	if img != null:
		Game.last_painting = img
		Game.last_painting_path = path
		if FileAccess.file_exists(wip_path()):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(wip_path()))
		if Game.pictures_dir != "":
			DirAccess.make_dir_recursive_absolute(Game.pictures_dir)
			img.save_png(Game.pictures_dir.path_join(path.get_file()))
		if Game.shot_dir != "":
			img.save_png(Game.shot_dir.path_join("painting.png"))
	else:
		Game.last_painting = null
		Game.last_painting_path = ""
	autosave.dirty = false
	Sfx.stop_music()
	Sfx.play("frame_it")


func _framing_step(delta: float) -> void:
	framing += delta
	var clap_at := [0.7, 1.05, 1.4, 1.75]
	while _claps < clap_at.size() and framing >= clap_at[_claps]:
		Sfx.play("clap", 0.95 + 0.05 * _claps)
		_claps += 1
		for s in 3:
			_hop[s] = 0.3
	if rng.randf() < 0.8:
		_add_confetti()
	if framing >= FRAME_SECONDS:
		_leave("party")


func _leave(screen_name: String) -> void:
	next_screen = screen_name
	_loop.stop()
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(screen_name)


# ---------------------------------------------------------------- view

func to_screen(p: Vector2) -> Vector2:
	return CANVAS_RECT.position + p * SCALE


func _update_effects(delta: float) -> void:
	for i in range(_effects.size() - 1, -1, -1):
		_effects[i].t += delta
		if _effects[i].t > 0.5:
			_effects.remove_at(i)
	for i in range(_confetti.size() - 1, -1, -1):
		var c: Dictionary = _confetti[i]
		c.pos += c.vel * delta
		c.vel.y += 40.0 * delta
		c.rot += c.spin * delta
		if c.pos.y > 370:
			_confetti.remove_at(i)


func _add_confetti() -> void:
	_confetti.append({"pos": Vector2(rng.randf_range(0, 640), -6), "vel": Vector2(rng.randf_range(-20, 20), rng.randf_range(40, 90)),
		"col": Palette.COLORS[rng.randi() % Palette.COLORS.size()], "rot": rng.randf() * TAU, "spin": rng.randf_range(-6, 6)})


func _update_riders() -> void:
	for s in 3:
		var spr: AnimatedSprite2D = _riders[s]
		if spr == null:
			continue
		var hop := sin(clampf(_hop[s] / 0.4, 0.0, 1.0) * PI) * 10.0
		spr.position = Vector2(RIDER_X[s], RIDER_Y - hop)


func _update_loop_sound() -> void:
	if _loop.stream == null or Sfx.muted:
		return
	if stroke.active and not paused and framing < 0.0:
		var k := clampf(_brush_speed / BRUSH_SPEED, 0.0, 1.0)
		_loop.pitch_scale = 0.75 + 0.6 * k
		_loop.volume_db = lerpf(-22.0, -8.0, k)
		if not _loop.playing:
			_loop.play()
	elif _loop.playing:
		_loop.stop()


func _draw() -> void:
	Kit.wall(self, Rect2(0, 0, 640, FLOOR_Y))
	Kit.floor_strip(self, Rect2(0, FLOOR_Y, 640, 360 - FLOOR_Y))
	Kit.easel(self, CANVAS_RECT, FLOOR_Y)
	draw_texture_rect(painter.texture(), CANVAS_RECT, false)
	if framing >= 0.0:
		var k := clampf(framing / 0.4, 0.0, 1.0)
		var grow := (1.0 - k) * 30.0
		Kit.gold_frame(self, CANVAS_RECT.grow(grow), 12.0)
	else:
		_draw_effects()
		_draw_cursor()
	_draw_side()
	_draw_floor_marks()
	if paused:
		_draw_menu()
	for c in _confetti:
		draw_set_transform(c.pos, c.rot, Vector2.ONE)
		draw_rect(Rect2(-3, -1.5, 6, 3), c.col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_cursor() -> void:
	var p := to_screen(brush)
	var r := maxf(radius() * SCALE, 2.5)
	Kit.disc(self, p, r, colour())
	Kit.ring(self, p, r + 2.0, Kit.WHITE, 2.0)
	Kit.ring(self, p, r + 3.5, Kit.INK, 1.5)
	# a small crosshair tick so the tiny brush is findable
	for d in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
		draw_line(p + d * (r + 5), p + d * (r + 9), Kit.INK, 1.5, true)


func _draw_effects() -> void:
	for e in _effects:
		var k: float = e.t / 0.5
		if e.kind == "ring":
			Kit.ring(self, e.pos, 8.0 + 26.0 * k, Color(e.col, 1.0 - k), 3.0)
		else:
			for i in 8:
				var a := TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				Kit.disc(self, e.pos + d * (10.0 + 40.0 * k), 4.0 * (1.0 - k) + 1.0, Color(e.col, 1.0 - k))


func _draw_side() -> void:
	# The pot cross: one pot per d-pad direction, the next stamp in the middle.
	var card := Rect2(540, 20, 96, 144)
	Kit.rrect(self, card.grow(1), 10, Kit.WOOD_DARK)
	Kit.rrect(self, card, 10, Kit.WOOD)
	for i in 4:
		var p := CROSS_C + POT_OFFSETS[i] * 0.45
		Kit.arrow(self, p, 9.0, Vector2(Palette.DIRS[i]), Kit.WOOD_LIGHT)
	var preview := Shapes.stamp(next_stamp(), Vector2.ZERO, 26.0, colour())
	Kit.disc(self, CROSS_C, 15.0, Palette.PAPER)
	Kit.parts(self, preview, CROSS_C)
	for i in 4:
		var c := Palette.color(page, i)
		var p := CROSS_C + POT_OFFSETS[i]
		var sel := i == pot
		var s := 0.82
		if sel:
			s = 1.08
			var glow := Players.SEAT_COLORS[COLOURIST]
			var pulse := 1.0 + sin(time * 6.0) * 0.06
			Kit.rrect(self, Rect2(p - Vector2(20, 20) * pulse + Vector2(0, 1), Vector2(40, 42) * pulse), 11, Kit.INK)
			Kit.rrect(self, Rect2(p - Vector2(18, 18) * pulse + Vector2(0, 1), Vector2(36, 38) * pulse), 9, glow.lightened(0.35))
			p.y -= 2.0 + sin(clampf(_pot_bounce[i] / 0.35, 0.0, 1.0) * PI) * 8.0
		else:
			c = c.lerp(Kit.WOOD, 0.15)
		Kit.pot(self, p, c, s)
	# The palette pages: mini 2x2 swatches, the current page raised.
	for pg in Palette.PAGES:
		var x := 556.0 + pg * 32.0
		var cur := pg == page
		var r := Rect2(x - 12, PAGES_Y - 12 - (3 if cur else 0), 24, 24)
		Kit.rrect(self, r.grow(2 if cur else 1), 5, Kit.INK if cur else Kit.WOOD_DARK)
		Kit.rrect(self, r, 4, Kit.WHITE)
		for k in 4:
			var q := Rect2(r.position + Vector2(3 + (k % 2) * 9.5, 3 + (k / 2) * 9.5), Vector2(8.5, 8.5))
			Kit.rrect(self, q, 2, Palette.color(pg, k))
	# Brush size.
	Kit.rrect(self, Rect2(552, SIZES_Y - 12, 72, 24), 8, Color(Kit.WHITE, 0.7))
	Kit.size_dots(self, Vector2(588, SIZES_Y), size_idx, colour())
	# The frame icon: sparkles once the picture has had 5 minutes.
	Kit.icon_frame(self, FRAME_ICON, 44.0)
	if time >= HINT_AFTER:
		for i in 3:
			var ph := fmod(time * 1.5 + i * 0.33, 1.0)
			var a := TAU * (i / 3.0) + time
			Kit.sparkle(self, FRAME_ICON + Vector2(cos(a) * 26, sin(a) * 18), 3.0 + 4.0 * sin(ph * PI), Kit.GOLD_LIGHT)


func _draw_floor_marks() -> void:
	for s in 3:
		if _riders[s] == null:
			continue
		var col: Color = Players.SEAT_COLORS[s]
		Kit.poly(self, Shapes.ellipse(Vector2(RIDER_X[s], RIDER_Y + 22), 22, 6, 24), Color(col, 0.85))
	# The Splatter's splat button floats over its rider, bright when ready.
	if _riders[SPLATTER] != null:
		var ready := splatter.ready_to_splat()
		var p := Vector2(RIDER_X[SPLATTER] + 30, RIDER_Y - 18 + (sin(time * 5.0) * 2.0 if ready else 0.0))
		Kit.icon_splat(self, p, 26.0 if ready else 18.0, Palette.COLORS[(splatter.count * 5) % 12] if ready else Color("#94b0c2"))
	if _riders[BRUSH] != null:
		Kit.icon_brush(self, Vector2(RIDER_X[BRUSH] + 30, RIDER_Y - 16), 24.0, colour())


func _draw_menu() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Color(Kit.INK, 0.55))
	var n := menu_items.size()
	var w := n * 84.0 + 20.0
	var board := Rect2(320 - w / 2, 120, w, 120)
	Kit.rrect(self, board.grow(3), 16, Kit.WOOD_DARK)
	Kit.rrect(self, board, 14, Kit.WOOD)
	for i in n:
		var c := Vector2(board.position.x + 52 + i * 84, board.get_center().y)
		var sel := i == menu_sel
		var s := 58.0 if sel else 46.0
		if sel:
			c.y += sin(time * 6.0) * 2.0
		Kit.disc(self, c, s * 0.62, Kit.WHITE if sel else Kit.WOOD_LIGHT)
		if sel:
			Kit.ring(self, c, s * 0.62 + 3, Kit.INK, 3.0)
		match menu_items[i]:
			"undo":
				Kit.icon_undo(self, c, s, Color("#41a6f6"))
				for k in undo.size():  # one dot per step you can undo
					Kit.disc(self, Vector2(c.x - 22 + (k % 5) * 11, board.end.y - 16 + (k / 5) * 8), 3.0, Kit.WHITE)
			"frame":
				Kit.icon_frame(self, c, s)
			"play":
				Kit.icon_play(self, c, s, Color("#38b764"))
			"splats":
				Kit.icon_splat(self, c, s * 0.9, Color("#ff5fa2") if Game.surprise_splats else Color("#94b0c2"))
				if Game.surprise_splats:
					Kit.icon_check(self, c + Vector2(s * 0.3, s * 0.3), s * 0.4, Color("#38b764"))
			"back":
				Kit.icon_back(self, c, s, Color("#b13e53"))
