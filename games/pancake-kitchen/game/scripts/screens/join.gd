extends Node2D
## Join screen: any device presses to take the next seat.
##
## Same rules as PixelPals's join (copied, then redrawn as flat vector art at
## 1280x720):
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The cook (seat 1) continues with "start", or by holding "a" for
##   HOLD_TIME (a ring fills around the cook's panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   FLIPPER seat, and yields a lower seat to a real device when the seats are
##   full, because it has no "b" to leave and no stick to steer.
## No text: seat colours, role icons, device icons and a key-shape legend.

const VA := preload("res://scripts/vector_art.gd")
const Pal := preload("res://scripts/kitchen/palette.gd")

const HOLD_TIME := 1.0
const PANEL_W := 340
const PANEL_H := 470
const PANEL_Y := 50
const PANEL_X: Array[int] = [60, 470, 880]
const FLIPPER := 2
const TODDLER := "kb:2"

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _flip_y: Array[float] = []


func _ready() -> void:
	for i in 7:
		_flip_y.append(float(i))
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	# Leave first, so a seat freed this frame can be taken next frame.
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("whoosh")
			if s == 0:
				hold = 0.0
	for d in Players.unseated_devices_just_pressed("any"):
		if Players.device_pressed(d, "b"):
			continue  # a back press never joins
		var seat := join_device(d)
		if seat != -1:
			joined_now.append(d)
			_bounce[seat] = 0.35
			Sfx.play("join", 1.0 + 0.12 * seat)
			if seat == 0:
				_hold_armed = false
				hold = 0.0

	if not Players.is_seated(0):
		hold = 0.0
		return
	var cook_dev := Players.device_of(0)
	if joined_now.has(cook_dev):
		return  # the joining press never also continues
	if Players.just_pressed(0, "start"):
		_continue()
		return
	if Players.pressed(0, "a"):
		if _hold_armed:
			hold += delta
			if hold >= HOLD_TIME:
				_continue()
	else:
		_hold_armed = true
		hold = 0.0


## Seat a device. The toddler block goes to the FLIPPER seat when it is free;
## a real device may bump the toddler block out of a lower seat when full.
func join_device(d: String) -> int:
	if Players.seat_of(d) != -1:
		return -1
	if d == TODDLER and not Players.is_seated(FLIPPER):
		return FLIPPER if Players.join_seat(d, FLIPPER) else -1
	var seat := Players.join(d)
	if seat == -1 and d != TODDLER:
		var t := Players.seat_of(TODDLER)
		if t != -1 and t != FLIPPER:
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


# ---------------------------------------------------------------- drawing

func _bounce_offset(s: int) -> float:
	if _bounce[s] <= 0.0:
		return 0.0
	return -sin(_bounce[s] / 0.35 * PI) * 24.0


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Pal.WALL)
	# Checkered tablecloth band at the bottom, pancakes flipping in the back.
	for x in 20:
		for y in 3:
			var c := Color("#ff9fb6") if (x + y) % 2 == 0 else Color.WHITE
			draw_rect(Rect2(x * 64, 560 + y * 64, 64, 64), c)
	draw_line(Vector2(0, 560), Vector2(1280, 560), Pal.OUTLINE, 5.0)
	for i in _flip_y.size():
		var ph := fmod(_time * 0.35 + i * 0.37, 1.0)
		var x := 90.0 + i * 180.0
		var y := 540.0 - sin(ph * PI) * 420.0
		VA.pancake(self, Vector2(x, y), 1.0, 0.4, cos(ph * TAU), 0.0, 0.0, 0.6, i)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	var fill := col.lerp(Color.WHITE, 0.55) if seated else Color(1, 1, 1, 0.55)
	VA.rrect(self, r, 34, fill, 6.0)
	if seated:
		draw_polyline(VA.closed(VA.rrect_pts(r.grow(-10), 26)), col, 8.0, true)
	var cx := r.position.x + PANEL_W / 2.0
	# Role icon (pan / jar / flying pancake), big.
	var icon_col := col if seated else col.lerp(Color("#b8b0c0"), 0.6)
	VA.role_icon(self, s, Vector2(cx, r.position.y + 120), icon_col, 2.2)
	if not seated:
		# Blinking "press me" button where the device icon will appear.
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(cx, r.position.y + 300), 44, col, false, 8.0, true)
			VA.circle(self, Vector2(cx, r.position.y + 300), 20, col, 5.0)
		return
	var d := Players.device_of(s)
	var beat := sin(_time * 6.0 + s) * 4.0
	VA.device_icon(self, d.begins_with("pad:"), Vector2(cx, r.position.y + 300 + beat), Color.WHITE, 1.8)
	for i in 3:
		VA.star(self, Vector2(cx - 50 + i * 50, r.position.y + 385), 14, col, _time * 2.0 + i, 3.5)
	if s == 0:
		# "Go" triangle, and the hold ring around the cook's panel.
		var ty := r.position.y + 435
		var tri := PackedVector2Array([Vector2(cx - 22, ty - 26), Vector2(cx + 26, ty), Vector2(cx - 22, ty + 26)])
		var on := int(_time * 2.0) % 2 == 0 or hold > 0.0
		VA.shape(self, tri, Color("#6cc36c") if on else Color("#cfd8c8"), 5.0)
		if hold > 0.0:
			var prog := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 44, -PI / 2, -PI / 2 + TAU * prog, 40, Pal.OUTLINE, 10.0, true)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := Color("#c8c0d0") if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2.0
		match block:
			0: _draw_cross_keys(cx - 16, col, true)
			1: _draw_cross_keys(cx + 16, col, false)
			2: _draw_key(Rect2(cx - 110, 628, 220, 40), col)


## An inverted-T of four keys, plus the main key beside it.
func _draw_cross_keys(cx: float, col: Color, main_left: bool) -> void:
	_draw_key(Rect2(cx - 18, 588, 36, 36), col)
	for i in 3:
		_draw_key(Rect2(cx - 58 + i * 40, 630, 36, 36), col)
	var fx := cx - 130 if main_left else cx + 70
	_draw_key(Rect2(fx, 630, 60, 36), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	VA.rrect(self, Rect2(r.position + Vector2(0, 5), r.size), 8, col.darkened(0.35), 4.0)
	VA.rrect(self, r, 8, col, 4.0)
