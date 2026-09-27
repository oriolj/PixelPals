extends Node2D
## Join screen (copied from Pillow Fort): any device presses to take the next seat.
## Seats: shoes = the walker, the laser pointer = the 5-year-old, the treat
## bag = the 2-year-old.
##
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The driver continues with "start", or by holding "a" for HOLD_TIME
##   (a ring fills around the driver panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   TREATS seat (Players.Seat.HONKER), and yields a lower seat to a real device when the seats are
##   full, because it has no "b" to leave and no stick to steer.
## No text: seat colours, role icons, device icons and a key-shape legend.

const HOLD_TIME := 1.0
const PANEL_W := 88
const PANEL_H := 126
const PANEL_Y := 10
const PANEL_X: Array[int] = [16, 116, 216]
const ROLE_ICONS: Array[String] = ["seat_shoes", "seat_laser", "seat_treats"]
const TODDLER := "kb:2"

## A warm house wall: apricot to rose.
const SKY: Array[Color] = [Color("#ffcd75"), Color("#ef7d57"), Color("#b13e53"), Color("#5d275d")]
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
var _legend_icon: AnimatedSprite2D


func _ready() -> void:
	for s in Players.SEAT_COUNT:
		var role := Art.sprite(ROLE_ICONS[s], Players.SEAT_COLORS[s].lightened(0.3), Vector2i(16, 16))
		role.scale = Vector2(2, 2)
		add_child(role)
		_role_sprites.append(role)
		var dev := Art.sprite("icon_kb", WHITE, Vector2i(16, 16))
		dev.scale = Vector2(2, 2)
		dev.visible = false
		add_child(dev)
		_device_sprites.append(dev)
	_legend_icon = Art.sprite("icon_kb", GREY, Vector2i(16, 16))
	_legend_icon.position = Vector2(8 + 8, 160)
	add_child(_legend_icon)
	_refresh_devices()
	_layout()
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	_layout()
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	# Leave first, so a seat freed this frame can be taken next frame.
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("whoosh")
			if s == Players.Seat.DRIVER:
				hold = 0.0
	# Join in press order: earlier frames already took earlier seats; within
	# one frame the device order of Players decides.
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


## Seat a device. The toddler block goes to the HONKER seat when it is free;
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
	return -int(roundf(sin(_bounce[s] / 0.35 * PI) * 6.0))


func _layout() -> void:
	for s in Players.SEAT_COUNT:
		var cx := PANEL_X[s] + PANEL_W / 2
		var by := _bounce_offset(s)
		var seated := Players.is_seated(s)
		_role_sprites[s].position = Vector2(cx, PANEL_Y + 26 + by)
		_role_sprites[s].modulate = Color.WHITE if seated else Color(0.55, 0.55, 0.65)
		# Joined device icon pulses: a one-pixel bob and a brightness beat.
		var beat := int(_time * 3.0 + s) % 2
		_device_sprites[s].position = Vector2(cx, PANEL_Y + 72 + by - beat)
		var glow := 0.85 + 0.15 * sin(_time * 6.0 + s)
		_device_sprites[s].modulate = Color(glow, glow, glow)


func _draw() -> void:
	# Banded sky.
	var band := 180.0 / SKY.size()
	for i in SKY.size():
		draw_rect(Rect2(0, roundf(i * band), 320, ceilf(band)), SKY[i])
	# Soft twinkling stars behind the panels (they peek out between them).
	for i in 18:
		var x := (i * 53 + 7) % 316
		var y := (i * 29 + 5) % 140
		var on := int(_time * 1.5 + i * 0.7) % 3 != 0
		draw_rect(Rect2(x, y, 1, 1), Color("#f4f4f4") if on else Color("#ffcd75"))
		if on and i % 3 == 0:
			draw_rect(Rect2(x - 1, y, 3, 1), Color("#f4f4f4", 0.6))
			draw_rect(Rect2(x, y - 1, 1, 3), Color("#f4f4f4", 0.6))
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	var fill := col.darkened(0.55) if seated else Color(INK, 0.55)
	draw_rect(r, col if seated else col.darkened(0.35))
	draw_rect(r.grow(-2), fill)
	var cx := int(r.position.x) + PANEL_W / 2
	if not seated:
		# Blinking "press me" button where the device icon will appear.
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(cx, r.position.y + 72), 9, col, false, 2.0)
			draw_circle(Vector2(cx, r.position.y + 72), 4, col)
		return
	# Seated: little stars under the device icon, in the seat colour.
	for i in 3:
		draw_rect(Rect2(cx - 13 + i * 10, r.position.y + 96, 6, 2), col)
	if s == Players.Seat.DRIVER:
		# "Go" triangle, and the hold ring around the driver panel.
		var ty := r.position.y + 112
		var tri := PackedVector2Array([Vector2(cx - 5, ty - 7), Vector2(cx + 6, ty), Vector2(cx - 5, ty + 7)])
		var go := WHITE if int(_time * 2.0) % 2 == 0 or hold > 0.0 else GREY
		draw_colored_polygon(tri, go)
		if hold > 0.0:
			_draw_ring(r.grow(3), clampf(hold / HOLD_TIME, 0.0, 1.0), WHITE)


## Draws `progress` of the rectangle's outline, clockwise from top-left, 2 px.
func _draw_ring(r: Rect2, progress: float, col: Color) -> void:
	var w := r.size.x
	var h := r.size.y
	var left := progress * 2.0 * (w + h)
	var sides := [
		[r.position, Vector2(1, 0), w],
		[r.position + Vector2(w - 2, 0), Vector2(0, 1), h],
		[r.position + Vector2(w, h - 2), Vector2(-1, 0), w],
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
			rect = Rect2(start, Vector2(n, 2))
		elif dir.y > 0:
			rect = Rect2(start, Vector2(2, n))
		elif dir.x < 0:
			rect = Rect2(start - Vector2(n, 0), Vector2(n, 2))
		else:
			rect = Rect2(start - Vector2(0, n), Vector2(2, n))
		draw_rect(rect, col)


# ---------------------------------------------------------------- legend

## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	draw_rect(Rect2(0, 146, 320, 34), Color(INK, 0.45))
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := GREY if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2
		match block:
			0: _draw_cross_keys(cx - 4, col, true)
			1: _draw_cross_keys(cx + 4, col, false)
			2: _draw_key(Rect2(cx - 22, 160, 44, 8), col)


## An inverted-T of four keys, plus the fire key beside it.
func _draw_cross_keys(cx: int, col: Color, fire_left: bool) -> void:
	_draw_key(Rect2(cx - 3, 152, 7, 7), col)
	for i in 3:
		_draw_key(Rect2(cx - 11 + i * 8, 160, 7, 7), col)
	var fx := cx - 25 if fire_left else cx + 14
	_draw_key(Rect2(fx, 160, 11, 7), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	draw_rect(r, col.darkened(0.4))
	draw_rect(Rect2(r.position, r.size - Vector2(0, 2)), col)
