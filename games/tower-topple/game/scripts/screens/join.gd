extends Node2D
## Join screen (the PixelPals one, at 640x360 with Tower Topple's seat icons:
## hook = Builder, dropping block = Dropper, big red button = Toppler).
##
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The Builder continues with "start", or by holding "a" for HOLD_TIME
##   (a ring fills around its panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   Toppler seat, and yields a lower seat to a real device when full.
## - Dad plus toddler on two pads: the Builder's down flick moves the Dropper
##   seat's device into the empty Toppler seat (up moves it back).

const Vec := preload("res://scripts/play/vec.gd")
const Icons := preload("res://scripts/icons.gd")

const HOLD_TIME := 1.0
const PANEL_W := 176
const PANEL_H := 248
const PANEL_Y := 18
const PANEL_X: Array[int] = [32, 232, 432]
const ROLE_ICONS: Array[String] = ["hook", "drop", "button"]
const TODDLER := "kb:2"

var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _cloud_x: Array[float] = []


func _ready() -> void:
	for i in 5:
		_cloud_x.append(float(i * 144 + 20))
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	for i in _cloud_x.size():
		_cloud_x[i] -= delta * (8.0 + 2.0 * i)
		if _cloud_x[i] < -64.0:
			_cloud_x[i] += 720.0
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("select", 0.8)
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
	var flick := Players.dir4_just_pressed(Players.Seat.DRIVER)
	if flick == Vector2i.DOWN:
		move_to_toppler()
	elif flick == Vector2i.UP:
		move_to_dropper()
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


## Seat a device. The toddler block goes to the Toppler seat when it is free;
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


## Dad + toddler on pads: move the Dropper's device into the empty Toppler seat.
func move_to_toppler() -> bool:
	if not Players.is_seated(Players.Seat.GUNNER) or Players.is_seated(Players.Seat.HONKER):
		return false
	var d := Players.device_of(Players.Seat.GUNNER)
	Players.leave(Players.Seat.GUNNER)
	Players.join_seat(d, Players.Seat.HONKER)
	_bounce[Players.Seat.HONKER] = 0.35
	Sfx.play("join", 1.24)
	return true


func move_to_dropper() -> bool:
	if Players.is_seated(Players.Seat.GUNNER) or not Players.is_seated(Players.Seat.HONKER):
		return false
	var d := Players.device_of(Players.Seat.HONKER)
	if d == TODDLER:
		return false  # the Space bar has no directions: it stays the Toppler
	Players.leave(Players.Seat.HONKER)
	Players.join_seat(d, Players.Seat.GUNNER)
	_bounce[Players.Seat.GUNNER] = 0.35
	Sfx.play("join", 1.12)
	return true


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
	return -sin(_bounce[s] / 0.35 * PI) * 12.0


func _draw() -> void:
	var bands := 18
	for i in bands:
		var c := Color("#41a6f6").lerp(Color("#73eff7"), float(i) / (bands - 1))
		draw_rect(Rect2(0, i * 360.0 / bands, 640, 360.0 / bands + 1), c)
	for i in _cloud_x.size():
		Vec.draw_cloud(self, Vector2(_cloud_x[i], 40 + (i * 74) % 220), 1.0, Color(1, 1, 1, 0.8), Color(0, 0, 0, 0), 0.0)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var by := _bounce_offset(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + by, PANEL_W, PANEL_H)
	var shape := Vec.translated(Vec.rounded_rect(PANEL_W, PANEL_H, 16), r.get_center())
	Vec.draw_shape(self, shape, col.darkened(0.45) if seated else Color("#333c57"), col if seated else col.darkened(0.3), 4.0)
	var cx := r.position.x + PANEL_W / 2.0
	var icon_col := col.lightened(0.2) if seated else Color(0.6, 0.6, 0.7)
	Icons.draw(self, ROLE_ICONS[s], Vector2(cx, r.position.y + 52), 64, icon_col)
	if not seated:
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(cx, r.position.y + 144), 18, col, false, 4.0, true)
			draw_circle(Vector2(cx, r.position.y + 144), 8, col, true, -1.0, true)
		return
	var d := Players.device_of(s)
	var glow := 0.85 + 0.15 * sin(_time * 6.0 + s)
	var bob := -2.0 * (int(_time * 3.0 + s) % 2)
	Icons.draw(self, "pad" if d.begins_with("pad:") else "kb", Vector2(cx, r.position.y + 144 + bob), 56,
		Color(glow, glow, glow))
	for i in 3:
		draw_colored_polygon(Vec.star(6, Vector2(cx - 22 + i * 22, r.position.y + 192)), col)
	if s == Players.Seat.DRIVER:
		var ty := r.position.y + 222
		var tri := PackedVector2Array([Vector2(cx - 10, ty - 14), Vector2(cx + 12, ty), Vector2(cx - 10, ty + 14)])
		var go := Vec.WHITE if int(_time * 2.0) % 2 == 0 or hold > 0.0 else Vec.GREY
		Vec.draw_shape(self, tri, go, Vec.INK, 3.0)
		if hold > 0.0:
			var p := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 22, -PI / 2, -PI / 2 + TAU * p, 32, Vec.WHITE, 5.0, true)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	draw_rect(Rect2(0, 286, 640, 74), Color(Vec.INK, 0.45))
	for block in 3:
		var dev := "kb:%d" % block
		var seat := Players.seat_of(dev)
		var col := Vec.GREY if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W / 2
		match block:
			0: _draw_cross_keys(cx - 8, col, true)
			1: _draw_cross_keys(cx + 8, col, false)
			2: _draw_key(Rect2(cx - 44, 316, 88, 18), col)


func _draw_cross_keys(cx: int, col: Color, fire_left: bool) -> void:
	_draw_key(Rect2(cx - 7, 300, 15, 15), col)
	for i in 3:
		_draw_key(Rect2(cx - 23 + i * 16, 318, 15, 15), col)
	var fx := cx - 51 if fire_left else cx + 28
	_draw_key(Rect2(fx, 318, 23, 15), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	var outer := Vec.translated(Vec.rounded_rect(r.size.x, r.size.y, 3), r.get_center())
	Vec.draw_shape(self, outer, col.darkened(0.35), Vec.INK, 2.0)
	var inner := Vec.translated(Vec.rounded_rect(r.size.x - 6, r.size.y - 7, 2), r.get_center() + Vector2(0, -1.5))
	draw_colored_polygon(inner, col)
