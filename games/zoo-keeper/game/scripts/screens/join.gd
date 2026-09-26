extends Node2D
## Join screen (PixelPals's logic, vector look): any device presses to take
## the next seat.
##
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The keeper continues with "start", or by holding "a" for HOLD_TIME (a ring
##   fills around the keeper panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   SINGER seat, and yields a lower seat to a real device when seats are full.
## No text: seat colours, role icons, device icons and a key-shape legend.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Animals := preload("res://scripts/vector/animals.gd")

const HOLD_TIME := 1.0
const PANEL_W := 352.0
const PANEL_H := 470.0
const PANEL_Y := 40.0
const PANEL_X: Array[float] = [64.0, 464.0, 864.0]
const TODDLER := "kb:2"
const SIDE_ANIMALS: Array[String] = ["monkey", "penguin", "giraffe", "rabbit", "elephant", "seal"]

var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _roles: Array[Node2D] = []
var _devices: Array[Node2D] = []
var _device_kind: Array[String] = ["", "", ""]
var _peekers: Array[Node2D] = []


func _ready() -> void:
	# Animals peek over the bottom edge, bobbing: this is the zoo.
	for i in SIDE_ANIMALS.size():
		var a := Animals.build(SIDE_ANIMALS[i])
		a.scale = Vector2(0.62, 0.62)
		a.position = Vector2(110 + i * 212, 760)
		a.get_node("shadow").visible = false
		add_child(a)
		_peekers.append(a)
	for s in Players.SEAT_COUNT:
		var role := Props.role_icon(s, Players.SEAT_COLORS[s])
		role.scale = Vector2(2.2, 2.2)
		add_child(role)
		_roles.append(role)
		var holder := Node2D.new()
		add_child(holder)
		_devices.append(holder)
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
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("whoosh")
			if s == Players.Seat.DRIVER:
				hold = 0.0
	for d in Players.unseated_devices_just_pressed("any"):
		if Players.device_pressed(d, "b"):
			continue
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
		return
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


## Seat a device. The toddler block goes to the SINGER seat when it is free;
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
		var kind := "" if d == "" else ("pad" if d.begins_with("pad:") else "kb")
		if kind == _device_kind[s]:
			continue
		_device_kind[s] = kind
		for c in _devices[s].get_children():
			c.free()
		if kind == "pad":
			_devices[s].add_child(Props.icon_pad(Pal.CREAM))
		elif kind == "kb":
			_devices[s].add_child(Props.icon_kb(Pal.CREAM))


func _bounce_offset(s: int) -> float:
	if _bounce[s] <= 0.0:
		return 0.0
	return -sin(_bounce[s] / 0.35 * PI) * 22.0


func _layout() -> void:
	for s in Players.SEAT_COUNT:
		var cx := PANEL_X[s] + PANEL_W / 2.0
		var by := _bounce_offset(s)
		var seated := Players.is_seated(s)
		_roles[s].position = Vector2(cx, PANEL_Y + 120 + by)
		_roles[s].modulate = Color.WHITE if seated else Color(0.6, 0.6, 0.7)
		_roles[s].rotation = sin(_time * 3.0 + s) * 0.08 if seated else 0.0
		_devices[s].position = Vector2(cx, PANEL_Y + 290 + by - absf(sin(_time * 4.0 + s)) * 6.0)
		_devices[s].scale = Vector2(1.8, 1.8)
	for i in _peekers.size():
		var a := _peekers[i]
		a.position.y = 790 - absf(sin(_time * 2.0 + i * 0.9)) * 40.0
		Animals.pose(a, "idle", _time + i, -1, sin(_time + i))


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Pal.SKY)
	draw_rect(Rect2(0, 560, 1280, 160), Pal.GRASS)
	for i in 14:
		draw_circle(Vector2(i * 100 + 20, 562), 36, Pal.GRASS)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	var fill := col.darkened(0.45) if seated else Color(Pal.OUTLINE, 0.35)
	_rounded(r, 28, Pal.OUTLINE)
	_rounded(r.grow(-6), 24, col if seated else col.darkened(0.3))
	_rounded(r.grow(-14), 20, fill)
	var cx := r.position.x + PANEL_W / 2.0
	if not seated:
		# Blinking "press me" button where the device icon will appear.
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(cx, r.position.y + 290), 38, col, false, 7.0, true)
			draw_circle(Vector2(cx, r.position.y + 290), 18, col, true, -1.0, true)
		return
	for i in 3:
		draw_circle(Vector2(cx - 40 + i * 40, r.position.y + 380), 9, col, true, -1.0, true)
	if s == Players.Seat.DRIVER:
		var ty := r.position.y + 425
		var tri := PackedVector2Array([Vector2(cx - 20, ty - 26), Vector2(cx + 24, ty), Vector2(cx - 20, ty + 26)])
		var go := Pal.CREAM if int(_time * 2.0) % 2 == 0 or hold > 0.0 else col.darkened(0.2)
		draw_colored_polygon(tri, go)
		draw_polyline(tri + PackedVector2Array([tri[0]]), Pal.OUTLINE, 4.0, true)
		if hold > 0.0:
			var p := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 44, -PI / 2, -PI / 2 + TAU * p, 48, Pal.CREAM, 10.0, true)


func _rounded(r: Rect2, radius: float, c: Color) -> void:
	draw_colored_polygon(VA.rrect(r, radius), c)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col: Color = Pal.CREAM.darkened(0.25) if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2.0
		var y := 580.0
		match block:
			0: _cross_keys(cx - 16, y, col, true)
			1: _cross_keys(cx + 16, y, col, false)
			2: _key(Rect2(cx - 110, y + 34, 220, 34), col)


func _cross_keys(cx: float, y: float, col: Color, fire_left: bool) -> void:
	_key(Rect2(cx - 15, y, 30, 30), col)
	for i in 3:
		_key(Rect2(cx - 49 + i * 34, y + 34, 30, 30), col)
	var fx := cx - 110 if fire_left else cx + 60
	_key(Rect2(fx, y + 34, 50, 30), col.lightened(0.2))


func _key(r: Rect2, col: Color) -> void:
	draw_colored_polygon(VA.rrect(r.grow(3), 8), Pal.OUTLINE)
	draw_colored_polygon(VA.rrect(r, 6), col.darkened(0.3))
	draw_colored_polygon(VA.rrect(Rect2(r.position, r.size - Vector2(0, 6)), 6), col)
