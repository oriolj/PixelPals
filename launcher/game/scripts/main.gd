extends Control
## The TV launcher: a carousel of game cards driven by any pad or keyboard.
##
## Flow: browse -> (A) launch zoom + whoosh -> [import spinner] -> game runs in
## its own process (launcher waits underneath, silent, input ignored) -> the
## game exits -> zoom back, "welcome back" chime, same card selected.
##
## Command-line (after `--`), for development, captures and tests:
##   --root=<abs>            repo root (default: two levels above this project)
##   --demo=browse           scripted navigation for frame captures
##   --select=<slug|power>   start with that card selected
##   --autolaunch=<slug>     select that game and press A (scripted) after 1.5 s
##   --game-arg=<arg>        passed to the game after "--" (repeatable)
##   --windowed-games        launch games without --fullscreen
##   --quit-after-return=<s> quit s seconds after a game came back (tests)
##   --quit-after-seconds=<s> quit after s seconds
##   --shot-dir=<abs>        save a PNG at launch / running / returned
##   --prefs=<path>          recently-played file (default user://launcher.cfg)
##   --mute                  no sound

const Pal := preload("res://scripts/palette.gd")
const Catalog := preload("res://scripts/catalog.gd")
const Carousel := preload("res://scripts/carousel.gd")
const Runner := preload("res://scripts/runner.gd")
const Card := preload("res://scripts/card.gd")
const Background := preload("res://scripts/background.gd")
const Bubbles := preload("res://scripts/bubbles.gd")

const CENTER := Vector2(960, 470)
const NEAR := 640.0      # centre-to-centre distance, focused card to its neighbour
const FAR := 500.0       # between two unfocused cards
const SMALL := 0.7       # unfocused card scale
const LIFT := 26.0
const REPEAT_DELAY := 0.42
const REPEAT_EVERY := 0.17
const POWER_HOLD := 2.0
const RECENT_MAX := 5

var root_dir := ""
var games: Array[Dictionary] = []
var cards: Array = []
var carousel: Carousel
var runner: Runner
var font: Font
var bg: Background
var bubbles: Bubbles

var _pitch: Label
var _hint: HBoxContainer
var _hint_power: HBoxContainer
var _header: Control
var _status: Label
var _fade: ColorRect

var _prefs_path := "user://launcher.cfg"
var _recent: Array = []
var _args := {}
var _game_args: PackedStringArray = []

var _held_dir := {}     # device -> -1/0/1
var _held_time := {}    # device -> seconds held
var _kb_confirm_prev := false
var _need_release := false
var _power_hold := 0.0
var _power_ticks := 0
var _zoom := 0.0        # 0 browse .. 1 the selected card fills the screen
var _zoom_tween: Tween
var _mode := "browse"   # browse | launching | waiting | returning | off
var _pitch_for := -1
var _pitch_fade := 1.0   # tweened on selection change; shown as _pitch_fade * (1 - _zoom)
var _shot_dir := ""


func _ready() -> void:
	_parse_args()
	root_dir = _args.get("root", Catalog.default_root())
	if _args.has("prefs"):
		_prefs_path = _args.prefs
	if _args.has("mute"):
		Sfx.muted = true
	_shot_dir = _args.get("shot-dir", "")
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	font = _make_font()
	var th := Theme.new()
	th.default_font = font
	theme = th

	bg = Background.new()
	add_child(bg)

	runner = Runner.new()
	runner.name = "Runner"
	runner.godot = root_dir.path_join(".tools/godot")
	runner.fullscreen = not _args.has("windowed-games")
	runner.game_args = _game_args
	runner.importing.connect(_on_importing)
	runner.started.connect(_on_started)
	runner.finished.connect(_on_finished)
	runner.failed.connect(_on_failed)
	add_child(runner)

	_build_header()
	_load_prefs()
	games = Catalog.order(Catalog.discover(root_dir), _recent)
	print("launcher: %d games under %s" % [games.size(), root_dir.path_join("games")])
	_build_cards()
	_build_footer()
	_fade = ColorRect.new()
	_fade.color = Color(Pal.NIGHT, 0.0)
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)

	var start := 0
	var want: String = _args.get("select", _args.get("autolaunch", ""))
	if want != "":
		start = maxi(0, _index_of(want))
	carousel.select(start)
	_layout(0.0)
	Sfx.music("music_menu")
	if _args.has("quit-after-seconds"):
		get_tree().create_timer(float(_args["quit-after-seconds"])).timeout.connect(get_tree().quit)
	if _args.has("demo") or _args.has("autolaunch"):
		var d = load("res://scripts/demo.gd").new()
		d.name = "Demo"
		add_child(d)
		d.start(self, _args)


func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if not a.begins_with("--"):
			continue
		var kv := a.substr(2).split("=", true, 1)
		if kv[0] == "game-arg" and kv.size() > 1:
			_game_args.append(kv[1])
		else:
			_args[kv[0]] = kv[1] if kv.size() > 1 else ""


func _make_font() -> Font:
	var f := SystemFont.new()
	f.font_names = PackedStringArray(["Fredoka", "Nunito", "Baloo 2", "Quicksand", "Comfortaa",
		"Adwaita Sans", "Cantarell", "Noto Sans", "Ubuntu", "DejaVu Sans"])
	f.font_weight = 800
	# No MSDF: the variable system fonts have overlapping contours that MSDF
	# renders with holes. canvas_items stretch rasterises at the TV's size anyway.
	return f


# ------------------------------------------------------------------ building

func _build_header() -> void:
	_header = Control.new()
	_header.position = Vector2(72, 44)
	_header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_header)
	var icon := TextureRect.new()
	icon.texture = _icon_texture()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.size = Vector2(72, 72)
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_header.add_child(icon)
	var t := _label("Couch Games", 46, Pal.WHITE)
	t.position = Vector2(92, 6)
	_header.add_child(t)

	bubbles = Bubbles.new()
	bubbles.position = Vector2(1920 - 72 - 600, 44)
	bubbles.size = Vector2(600, 90)
	add_child(bubbles)


func _icon_texture() -> Texture2D:
	var p := "res://icon.png"
	if not FileAccess.file_exists(p):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(p)) != OK:
		return null
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


func _build_cards() -> void:
	var entries: Array[Dictionary] = games.duplicate()
	entries.append({"kind": "power", "slug": "power", "title": "Turn off",
		"pitch": "Hold A for two seconds to close the launcher.", "playable": false})
	games = entries
	carousel = Carousel.new(games.size())
	var holder := Control.new()
	holder.name = "Cards"
	holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(holder)
	for i in games.size():
		var c := Card.new()
		c.setup(games[i], font)
		if i == 0 and _recent.size() > 0 and games[i].get("slug", "") == _recent[0]:
			c.set_recent(true)
		holder.add_child(c)
		cards.append(c)


func _build_footer() -> void:
	_pitch = _label("", 36, Pal.WHITE)
	_pitch.position = Vector2(160, 790)
	_pitch.size = Vector2(1600, 110)
	_pitch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pitch.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pitch.add_theme_constant_override("outline_size", 8)
	_pitch.add_theme_color_override("font_outline_color", Color(Pal.NIGHT, 0.8))
	add_child(_pitch)

	_hint = _hint_row([["◀ ▶", "Choose"], ["A", "Play"], ["Back + Start", "Leave a game"]])
	_hint_power = _hint_row([["◀ ▶", "Choose"], ["Hold A", "Turn off"]])
	_hint_power.visible = false

	_status = _label("", 40, Pal.YELLOW)
	_status.position = Vector2(0, 930)
	_status.size = Vector2(1920, 60)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.add_theme_constant_override("outline_size", 10)
	_status.add_theme_color_override("font_outline_color", Pal.NIGHT)
	add_child(_status)


func _hint_row(items: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for it in items:
		var cap := _label(it[0], 28, Pal.NIGHT)
		var sb := StyleBoxFlat.new()
		sb.bg_color = Pal.WHITE
		sb.set_corner_radius_all(14)
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 2
		sb.content_margin_bottom = 4
		cap.add_theme_stylebox_override("normal", sb)
		row.add_child(cap)
		var l := _label(it[1], 30, Pal.GREY_LIGHT)
		row.add_child(l)
		var spacer := Control.new()
		spacer.custom_minimum_size = Vector2(26, 0)
		row.add_child(spacer)
	add_child(row)
	row.reset_size()
	row.position = Vector2((1920 - row.size.x) / 2.0 + 13, 1000)
	return row


func _label(text: String, fs: int, col: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


# ------------------------------------------------------------------ per frame

func _process(delta: float) -> void:
	if _mode == "browse":
		_read_input(delta)
	carousel.update(delta)
	_layout(delta)


func _layout(_delta: float) -> void:
	bg.scroll = carousel.scroll
	var sel := carousel.index()
	for i in cards.size():
		var c: Card = cards[i]
		var o := carousel.offset(i)
		var a := absf(o)
		var d := a * NEAR if a <= 1.0 else NEAR + (a - 1.0) * FAR
		var x := CENTER.x + signf(o) * d
		var s := lerpf(1.0, SMALL, clampf(a, 0.0, 1.0)) - maxf(0.0, a - 1.0) * 0.04
		var focus := clampf(1.0 - a, 0.0, 1.0)
		var y := CENTER.y - LIFT * focus
		if i == sel and _zoom > 0.0:
			# Launch zoom: the selected card grows toward the whole screen.
			var z := _ease(_zoom)
			s = lerpf(s, 2.9, z)
			y = lerpf(y, 540.0 + 60.0 * z, z)
		c.scale = Vector2(s, s)
		c.position = Vector2(x, y) - Card.SIZE / 2
		c.focus = focus
		c.z_index = 100 - int(a * 10.0) + (50 if i == sel else 0)
		c.visible = absf(x - CENTER.x) < 1500.0
		c.modulate.a = 1.0 if i == sel else 1.0 - _zoom
	_header.modulate.a = 1.0 - _zoom
	bubbles.modulate.a = 1.0 - _zoom
	_hint.modulate.a = 1.0 - _zoom
	_hint_power.modulate.a = 1.0 - _zoom
	bg.dim = _zoom * 0.6
	var is_power: bool = games[sel].get("kind", "") == "power"
	_hint.visible = not is_power
	_hint_power.visible = is_power
	if _pitch_for != sel:
		_pitch_for = sel
		_pitch.text = games[sel].get("pitch", "")
		if not games[sel].get("playable", true) and games[sel].get("kind", "") != "power":
			_pitch.text = "Coming soon: " + _pitch.text if _pitch.text != "" else "Coming soon."
		_pitch_fade = 0.0
		var tw := create_tween()
		tw.tween_property(self, "_pitch_fade", 1.0, 0.25).set_delay(0.08)
	_pitch.modulate.a = _pitch_fade * (1.0 - _zoom)


static func _ease(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


# ------------------------------------------------------------------ input

func _read_input(delta: float) -> void:
	if _need_release:
		if _anything_held():
			return
		_need_release = false
	var step := 0
	var pressed_a := false
	var holding_a := false
	for d in Players.all_devices():
		if Players.device_just_pressed(d, "any"):
			if d != "kb:2" or Input.is_physical_key_pressed(KEY_SPACE):
				bubbles.ping(d)
		var v := Players.device_move(d)
		var dir := 0
		if absf(v.x) > 0.5 and absf(v.x) >= absf(v.y):
			dir = int(signf(v.x))
		var prev: int = _held_dir.get(d, 0)
		if dir != 0 and dir != prev:
			step = dir
			_held_time[d] = 0.0
		elif dir != 0:
			_held_time[d] = _held_time.get(d, 0.0) + delta
			if _held_time[d] > REPEAT_DELAY:
				_held_time[d] -= REPEAT_EVERY
				step = dir
		_held_dir[d] = dir
		# Pads and scripted devices confirm with their "a" (A, X or RT).
		# Keyboards confirm with Enter or Space only (see below), so that
		# kb:1's Ctrl (Ctrl+Q) and kb:2's every-other-key never launch a game.
		if not d.begins_with("kb:"):
			if Players.device_just_pressed(d, "a"):
				pressed_a = true
			if Players.device_pressed(d, "a"):
				holding_a = true
	var kb_confirm := Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_KP_ENTER) \
		or Input.is_physical_key_pressed(KEY_SPACE)
	if kb_confirm and not _kb_confirm_prev:
		pressed_a = true
	_kb_confirm_prev = kb_confirm
	holding_a = holding_a or kb_confirm

	if step != 0:
		move(step)
	var sel := carousel.index()
	if games[sel].get("kind", "") == "power":
		_update_power(holding_a, delta)
	elif pressed_a:
		activate()


func _anything_held() -> bool:
	for d in Players.all_devices():
		if Players.device_pressed(d, "any") or Players.device_move(d) != Vector2.ZERO:
			return true
	return Input.is_physical_key_pressed(KEY_ENTER) or Input.is_physical_key_pressed(KEY_SPACE)


func move(dir: int) -> void:
	if _power_hold > 0.0:
		_reset_power()
	carousel.step(dir)
	Sfx.play("move", 1.0 + 0.04 * (carousel.index() % 3), -2.0)


func select_slug(slug: String) -> void:
	var i := _index_of(slug)
	if i >= 0:
		carousel.select(i)


func _index_of(slug: String) -> int:
	for i in games.size():
		if games[i].get("slug", "") == slug:
			return i
	return -1


func _update_power(holding: bool, delta: float) -> void:
	var c: Card = cards[carousel.index()]
	if holding:
		_power_hold += delta
		var ticks := int(_power_hold / (POWER_HOLD / 4.0))
		if ticks > _power_ticks and ticks < 4:
			Sfx.play("power_tick", 1.0 + 0.12 * ticks)
		_power_ticks = ticks
		if _power_hold >= POWER_HOLD:
			power_off()
	else:
		_power_hold = maxf(0.0, _power_hold - delta * 3.0)
		_power_ticks = int(_power_hold / (POWER_HOLD / 4.0))
	c.hold = clampf(_power_hold / POWER_HOLD, 0.0, 1.0)


func _reset_power() -> void:
	_power_hold = 0.0
	_power_ticks = 0
	for c in cards:
		c.hold = 0.0


func power_off() -> void:
	_mode = "off"
	Sfx.stop_music()
	Sfx.play("power_off")
	var tw := create_tween()
	tw.tween_property(_fade, "color:a", 1.0, 1.0)
	tw.tween_callback(get_tree().quit).set_delay(0.3)


# ------------------------------------------------------------------ launching

## Press A on the selected card.
func activate() -> void:
	var e: Dictionary = games[carousel.index()]
	if not e.get("playable", false):
		Sfx.play("bonk")
		_shake(cards[carousel.index()])
		return
	if runner.busy() or _mode != "browse":
		return
	_mode = "launching"
	Players.quit_combo_enabled = false  # Back+Start belongs to the game now
	_remember(e.slug)
	Sfx.play("launch")
	_tween_zoom(1.0, 0.55)
	get_tree().create_timer(0.6).timeout.connect(_after_zoom.bind(e))


func _after_zoom(e: Dictionary) -> void:
	await _snap("launch")
	if not runner.request_launch(e):
		_come_back()


func _on_importing(e: Dictionary) -> void:
	_status.text = "Getting %s ready…" % e.title
	cards[carousel.index()].show_spinner(true)


func _on_started(_e: Dictionary, _pid: int) -> void:
	_mode = "waiting"
	_status.text = ""
	cards[carousel.index()].show_spinner(false)
	Sfx.stop_music()
	# Stay underneath the game quietly: slow redraws, no sound, no input.
	OS.low_processor_usage_mode = true
	Engine.max_fps = 15
	get_tree().create_timer(1.5).timeout.connect(func(): _snap("running"))


func _on_finished(e: Dictionary) -> void:
	print("launcher: welcome back from %s" % e.slug)
	_come_back()


func _on_failed(_e: Dictionary, reason: String) -> void:
	_status.text = ""
	cards[carousel.index()].show_spinner(false)
	Sfx.play("bonk")
	print("launcher: launch failed: %s" % reason)
	_come_back()


func _come_back() -> void:
	OS.low_processor_usage_mode = false
	Engine.max_fps = 0
	_mode = "returning"
	DisplayServer.window_move_to_foreground()
	if not _args.has("windowed-games") and DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	Sfx.play("welcome")
	_tween_zoom(0.0, 0.6)
	_need_release = true
	_held_dir.clear()
	get_tree().create_timer(0.65).timeout.connect(_back_to_browse)


func _back_to_browse() -> void:
	_mode = "browse"
	Players.quit_combo_enabled = true  # re-arms only after Back+Start are released
	Sfx.music("music_menu")
	print("launcher: restored, selected %s" % games[carousel.index()].get("slug", ""))
	await _snap("returned")
	if _args.has("quit-after-return"):
		get_tree().create_timer(float(_args["quit-after-return"])).timeout.connect(get_tree().quit)


func _tween_zoom(to: float, secs: float) -> void:
	if _zoom_tween:
		_zoom_tween.kill()
	_zoom_tween = create_tween()
	_zoom_tween.tween_property(self, "_zoom", to, secs).set_trans(Tween.TRANS_SINE)


func _shake(c: Control) -> void:
	var tw := create_tween()
	for k in [14.0, -12.0, 8.0, -4.0, 0.0]:
		tw.tween_property(c, "rotation", deg_to_rad(k * 0.25), 0.05)


func _snap(tag: String) -> void:
	if _shot_dir == "":
		return
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(_shot_dir)
	img.save_png(_shot_dir.path_join("%s.png" % tag))
	print("launcher: shot %s" % tag)


# ------------------------------------------------------------------ recently played

func _load_prefs() -> void:
	var cf := ConfigFile.new()
	if cf.load(_prefs_path) == OK:
		_recent = cf.get_value("launcher", "recent", [])


func _remember(slug: String) -> void:
	_recent.erase(slug)
	_recent.push_front(slug)
	_recent = _recent.slice(0, RECENT_MAX)
	var cf := ConfigFile.new()
	cf.set_value("launcher", "recent", _recent)
	cf.save(_prefs_path)
