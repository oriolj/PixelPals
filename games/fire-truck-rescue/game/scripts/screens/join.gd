extends Node2D
## Join screen (PixelPals's, relaid for 480x270 with the fire crew's icons).
##
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The driver continues with "start", or by holding "a" for HOLD_TIME
##   (a ring fills around the driver panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   SIREN seat, and yields a lower seat to a real device when the seats are
##   full, because it has no "b" to leave and no stick to steer.
## No text: seat colours, role icons (wheel, hose, siren), device icons and
## a key-shape legend.

const W := 480
const H := 270
const HOLD_TIME := 1.0
const PANEL_W := 132
const PANEL_H := 184
const PANEL_Y := 12
const PANEL_X: Array[int] = [18, 174, 330]
const ROLE_ICONS: Array[String] = ["seat_driver", "seat_hose", "seat_siren"]
const TODDLER := "kb:2"
const LEGEND_Y := 214

const SKY: Array[Color] = [Color("#29366f"), Color("#3b5dc9"), Color("#41a6f6"), Color("#73eff7")]
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")
const GREY := Color("#94b0c2")

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _role_sprites: Array[AnimatedSprite2D] = []
var _device_sprites: Array[AnimatedSprite2D] = []
var _cloud_x: Array[float] = []
var _cloud_tex: Texture2D
var _town_tex: Texture2D


func _ready() -> void:
	_cloud_tex = Art.frames("cloud_bg", Color("#f4f4f4"), Vector2i(32, 16)).get_frame_texture("default", 0)
	_town_tex = Art.frames("town_strip", Color("#38b764"), Vector2i(480, 64)).get_frame_texture("default", 0)
	for i in 6:
		_cloud_x.append(float(i * 86 + 10))
	for s in Players.SEAT_COUNT:
		var role := Art.sprite(ROLE_ICONS[s], Players.SEAT_COLORS[s].lightened(0.3), Vector2i(16, 16))
		role.scale = Vector2(3, 3)
		add_child(role)
		_role_sprites.append(role)
		var dev := Art.sprite("icon_kb", WHITE, Vector2i(16, 16))
		dev.scale = Vector2(2, 2)
		dev.visible = false
		add_child(dev)
		_device_sprites.append(dev)
	_refresh_devices()
	_layout()
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	for i in _cloud_x.size():
		_cloud_x[i] -= delta * (4.0 + i)
		if _cloud_x[i] < -32.0:
			_cloud_x[i] += W + 40.0
	_layout()
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("whoosh")
			if s == Players.Seat.DRIVER:
				hold = 0.0
	for d in Players.unseated_devices_just_pressed("any"):
		if Players.device_pressed(d, "b"):
			continue  # a back press never joins
		var seat := join_device(d)
		if seat != -1:
			joined_now.append(d)
			_bounce[seat] = 0.35
			Sfx.play("join", 1.0 + 0.12 * seat)
			if seat == Players.Seat.DRIVER:
				_hold_armed = false
				hold = 0.0
	_refresh_devices()

	if not Players.is_seated(Players.Seat.DRIVER):
		hold = 0.0
		return
	var driver_dev := Players.device_of(Players.Seat.DRIVER)
	if joined_now.has(driver_dev):
		return  # the joining press never also continues
	if Players.just_pressed(Players.Seat.DRIVER, "start"):
		_continue()
		return
	if Players.pressed(Players.Seat.DRIVER, "a"):
		if _hold_armed:
			hold += delta
			if hold >= HOLD_TIME:
				_continue()
	else:
		_hold_armed = true
		hold = 0.0


## Seat a device. The toddler block goes to the SIREN seat when it is free;
## a real device may bump the toddler block out of a lower seat when full.
func join_device(d: String) -> int:
	if Players.seat_of(d) != -1:
		return -1
	if d == TODDLER and not Players.is_seated(Players.Seat.HONKER):
		return Players.Seat.HONKER if Players.join_seat(d, Players.Seat.HONKER) else -1
	var seat := Players.join(d)
	if seat == -1 and d != TODDLER:
		var t := Players.seat_of(TODDLER)
		if t != -1 and t != Players.Seat.HONKER:
			Players.leave(t)
			seat = Players.join(d)
	return seat


func _continue() -> void:
	hold = 0.0
	Sfx.play("select")
	next_screen = "select"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("select")


# ---------------------------------------------------------------- layout

func _refresh_devices() -> void:
	for s in Players.SEAT_COUNT:
		var d := Players.device_of(s)
		var spr := _device_sprites[s]
		spr.visible = d != ""
		if d != "":
			var icon := "icon_pad" if d.begins_with("pad:") else "icon_kb"
			var sf := Art.frames(icon, WHITE, Vector2i(16, 16))
			if spr.sprite_frames != sf:
				spr.sprite_frames = sf
				spr.play("default")


func _bounce_offset(s: int) -> int:
	if _bounce[s] <= 0.0:
		return 0
	return -int(roundf(sin(_bounce[s] / 0.35 * PI) * 8.0))


func _layout() -> void:
	for s in Players.SEAT_COUNT:
		var cx := PANEL_X[s] + PANEL_W / 2
		var by := _bounce_offset(s)
		var seated := Players.is_seated(s)
		_role_sprites[s].position = Vector2(cx, PANEL_Y + 40 + by)
		_role_sprites[s].modulate = Color.WHITE if seated else Color(0.55, 0.55, 0.65)
		var beat := int(_time * 3.0 + s) % 2
		_device_sprites[s].position = Vector2(cx, PANEL_Y + 104 + by - beat)
		var glow := 0.85 + 0.15 * sin(_time * 6.0 + s)
		_device_sprites[s].modulate = Color(glow, glow, glow)


func _draw() -> void:
	var band := float(H) / SKY.size()
	for i in SKY.size():
		draw_rect(Rect2(0, roundf(i * band), W, ceilf(band)), SKY[i])
	for i in _cloud_x.size():
		draw_texture(_cloud_tex, Vector2(roundf(_cloud_x[i]), 16 + (i * 41) % 120), Color(1, 1, 1, 0.8))
	draw_texture(_town_tex, Vector2(0, LEGEND_Y - 64))
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	var fill := col.darkened(0.55) if seated else Color(INK, 0.6)
	draw_rect(r, col if seated else col.darkened(0.35))
	draw_rect(r.grow(-3), fill)
	var cx := int(r.position.x) + PANEL_W / 2
	if not seated:
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(cx, r.position.y + 104), 13, col, false, 3.0)
			draw_circle(Vector2(cx, r.position.y + 104), 6, col)
		return
	for i in 3:
		draw_rect(Rect2(cx - 20 + i * 15, r.position.y + 136, 9, 3), col)
	if s == Players.Seat.DRIVER:
		var ty := r.position.y + 162
		var tri := PackedVector2Array([Vector2(cx - 8, ty - 10), Vector2(cx + 9, ty), Vector2(cx - 8, ty + 10)])
		var go := WHITE if int(_time * 2.0) % 2 == 0 or hold > 0.0 else GREY
		draw_colored_polygon(tri, go)
		if hold > 0.0:
			_draw_ring(r.grow(4), clampf(hold / HOLD_TIME, 0.0, 1.0), WHITE)


## Draws `progress` of the rectangle's outline, clockwise from top-left, 3 px.
func _draw_ring(r: Rect2, progress: float, col: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var left := progress * 2.0 * (w + h)
	var sides := [
		[r.position, Vector2(1, 0), w],
		[r.position + Vector2(w - 3, 0), Vector2(0, 1), h],
		[r.position + Vector2(w, h - 3), Vector2(-1, 0), w],
		[r.position + Vector2(0, h), Vector2(0, -1), h],
	]
	for side in sides:
		if left <= 0.0:
			break
		var start: Vector2 = side[0]
		var dir: Vector2 = side[1]
		var n := int(minf(left, side[2]))
		left -= float(side[2])
		var rect: Rect2
		if dir.x > 0:
			rect = Rect2(start, Vector2(n, 3))
		elif dir.y > 0:
			rect = Rect2(start, Vector2(3, n))
		elif dir.x < 0:
			rect = Rect2(start - Vector2(n, 0), Vector2(n, 3))
		else:
			rect = Rect2(start - Vector2(0, n), Vector2(3, n))
		draw_rect(rect, col)


# ---------------------------------------------------------------- legend

## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	draw_rect(Rect2(0, LEGEND_Y, W, H - LEGEND_Y), Color(INK, 0.55))
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := GREY if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2
		match block:
			0: _draw_cross_keys(cx - 6, col, true)
			1: _draw_cross_keys(cx + 6, col, false)
			2: _draw_key(Rect2(cx - 34, LEGEND_Y + 24, 68, 12), col)


## An inverted-T of four keys, plus the fire key beside it.
func _draw_cross_keys(cx: int, col: Color, fire_left: bool) -> void:
	var y0 := LEGEND_Y + 10
	_draw_key(Rect2(cx - 5, y0, 11, 11), col)
	for i in 3:
		_draw_key(Rect2(cx - 17 + i * 12, y0 + 13, 11, 11), col)
	var fx := cx - 37 if fire_left else cx + 21
	_draw_key(Rect2(fx, y0 + 13, 16, 11), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	draw_rect(r, col.darkened(0.4))
	draw_rect(Rect2(r.position, r.size - Vector2(0, 3)), col)
