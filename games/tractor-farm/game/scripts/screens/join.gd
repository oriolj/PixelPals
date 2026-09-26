extends Node2D
## Join screen: any device presses to take the next seat.
##
## The logic is PixelPals's join screen (same rules, same tests):
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The driver continues with "start", or by holding "a" for HOLD_TIME
##   (a ring fills around the driver panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   HONKER seat, and yields a lower seat to a real device when the seats are
##   full, because it has no "b" to leave and no stick to steer.
## The view is the farm's: three barn-board panels with the seat roles
## (steering wheel, seed bag, rain cloud), device icons and a key legend. No
## text.

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Farm := preload("res://scripts/draw/farm_art.gd")
const Crops := preload("res://scripts/draw/crop_art.gd")

const HOLD_TIME := 1.0
const PANEL_W := 344
const PANEL_H := 470
const PANEL_Y := 60
const PANEL_X: Array[int] = [72, 468, 864]
const TODDLER := "kb:2"

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]


func _ready() -> void:
	Sfx.music("music_farm")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("select", 0.7)
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


# ---------------------------------------------------------------- view

func _bounce_offset(s: int) -> float:
	if _bounce[s] <= 0.0:
		return 0.0
	return -sin(_bounce[s] / 0.35 * PI) * 24.0


func _draw() -> void:
	draw_farm_backdrop(self, _time)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


## Sky, sun, hills and a striped field: the menus' shared backdrop.
static func draw_farm_backdrop(ci: CanvasItem, time: float) -> void:
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 470), Vector2(0, 470)]),
		PackedColorArray([P.SKY_TOP, P.SKY_TOP, P.SKY_LOW, P.SKY_LOW]))
	for i in 4:
		var x := fmod(i * 360.0 + time * 18.0, 1600.0) - 160.0
		S.xform(ci, Vector2(x, 90 + (i % 2) * 60), 0.0, Vector2(0.8, 0.8))
		Farm.cloud(ci, Farm.Face.IDLE, fmod(time + i, 3.3) < 0.14, time, Color(1, 1, 1, 0.75))
	S.reset(ci)
	for b in [[Vector2(200, 470), 360.0, 80.0], [Vector2(760, 480), 460.0, 90.0], [Vector2(1200, 470), 300.0, 70.0]]:
		S.oval(ci, b[0], b[1], b[2], P.GRASS_LIGHT, P.INK, 0.0)
	ci.draw_rect(Rect2(0, 460, 1280, 260), P.GRASS)
	for i in 6:
		var y := 480.0 + i * 40.0
		ci.draw_rect(Rect2(0, y, 1280, 20), P.GRASS_DARK.lerp(P.GRASS, 0.5))


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var by := _bounce_offset(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + by, PANEL_W, PANEL_H)
	var fill := P.CREAM if seated else Color(P.CREAM, 0.55)
	S.box(self, r.grow(8), 30, col if seated else col.darkened(0.3), P.INK, 4.0)
	S.box(self, r, 24, fill, P.INK, 3.0)
	var cx := r.position.x + PANEL_W / 2.0
	# Role icon.
	var icon_c := Vector2(cx, r.position.y + 110)
	S.disc(self, icon_c, 76, col.lightened(0.5) if seated else Color(0.8, 0.8, 0.8), P.INK, 3.0)
	# (seed_bag places itself: crop icons set their own canvas transform.)
	match s:
		0:
			S.xform(self, icon_c, 0.0, Vector2.ONE)
			Farm.steering_wheel(self, 50, col.darkened(0.2) if seated else Color(0.6, 0.6, 0.6))
		1:
			Farm.seed_bag(self, icon_c + Vector2(0, 4), 92, int(_time * 0.8) % 4 if seated else 0)
		2:
			S.xform(self, icon_c + Vector2(0, 6), 0.0, Vector2(0.95, 0.95))
			Farm.cloud(self, Farm.Face.RAIN if seated and int(_time * 2.0) % 2 == 0 else Farm.Face.IDLE, false, _time)
	S.reset(self)
	var dev_c := Vector2(cx, r.position.y + 290)
	if not seated:
		# Blinking "press me" button where the device icon will appear.
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_arc(dev_c, 36, 0, TAU, 40, col.darkened(0.2), 8.0, true)
			draw_circle(dev_c, 16, col.darkened(0.2), true, -1.0, true)
		return
	var d := Players.device_of(s)
	var beat := sin(_time * 6.0 + s) * 4.0
	S.xform(self, dev_c + Vector2(0, beat), 0.0, Vector2(2.2, 2.2))
	if d.begins_with("pad:"):
		Farm.pad_icon(self, 60, P.WHITE)
	else:
		Farm.kb_icon(self, 60, P.WHITE)
	S.reset(self)
	for i in 3:
		S.disc(self, Vector2(cx - 44 + i * 44, r.position.y + 380), 9, col)
	if s == Players.Seat.DRIVER:
		var ty := r.position.y + 430
		var go := P.LEAF_BRIGHT if int(_time * 2.0) % 2 == 0 or hold > 0.0 else P.GRASS_DARK
		S.fill_ink(self, PackedVector2Array([Vector2(cx - 22, ty - 26), Vector2(cx + 26, ty), Vector2(cx - 22, ty + 26)]), go, P.INK, 3.0)
		if hold > 0.0:
			var k := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 44, -PI / 2, -PI / 2 + TAU * k, 48, P.WHITE, 10.0, true)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	S.box(self, Rect2(40, 596, 1200, 104), 20, Color(P.INK, 0.35), P.INK, 0.0)
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := Color(0.75, 0.78, 0.8) if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2
		match block:
			0: _draw_cross_keys(cx - 16, col, true)
			1: _draw_cross_keys(cx + 16, col, false)
			2: _draw_key(Rect2(cx - 88, 636, 176, 32), col)


func _draw_cross_keys(cx: int, col: Color, fire_left: bool) -> void:
	_draw_key(Rect2(cx - 14, 606, 28, 28), col)
	for i in 3:
		_draw_key(Rect2(cx - 46 + i * 32, 640, 28, 28), col)
	var fx := cx - 104 if fire_left else cx + 56
	_draw_key(Rect2(fx, 640, 48, 28), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	S.box(self, Rect2(r.position + Vector2(0, 5), r.size), 6, col.darkened(0.4), P.INK, 2.0)
	S.box(self, r, 6, col, P.INK, 2.0)
