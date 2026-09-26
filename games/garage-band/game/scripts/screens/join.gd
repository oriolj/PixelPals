extends Node2D
## Join screen (PixelPals's, redrawn in vector at 640x360): any device
## presses to take the next seat of the band.
##
## - Unseated devices that press anything join in press order.
## - A seated device's "b" leaves its seat.
## - The Lead continues with "start", or by holding "a" for HOLD_TIME (a ring
##   fills around the Lead's panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   Crasher seat, and yields a lower seat to a real device when full.
## No text: seat colours, instrument icons, device icons and a key legend.

const Draw := preload("res://scripts/view/draw.gd")
const Garage := preload("res://scripts/view/garage.gd")

const HOLD_TIME := 1.0
const PANEL_W := 176
const PANEL_H := 232
const PANEL_Y := 40
const PANEL_X: Array[int] = [32, 232, 432]
const TODDLER := "kb:2"

var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _garage: Node2D
var _front: Node2D


func _ready() -> void:
	_garage = Garage.new()
	add_child(_garage)
	_front = Front.new()
	_front.screen = self
	add_child(_front)
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	_garage.beat = 0.5 + 0.5 * sin(_time * 4.0)
	_front.queue_redraw()


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
	var lead_dev := Players.device_of(Players.Seat.DRIVER)
	if joined_now.has(lead_dev):
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


## Seat a device. The toddler block goes to the Crasher seat when it is free;
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


func bounce_offset(s: int) -> float:
	if _bounce[s] <= 0.0:
		return 0.0
	return -sin(_bounce[s] / 0.35 * PI) * 12.0


class Front extends Node2D:
	var screen: Node2D

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 640, 360), Color(Draw.INK, 0.35))
		for s in Players.SEAT_COUNT:
			_panel(s)
		_legend()

	func _panel(s: int) -> void:
		var t: float = screen._time
		var col: Color = Players.SEAT_COLORS[s]
		var seated := Players.is_seated(s)
		var r := Rect2(screen.PANEL_X[s], screen.PANEL_Y + screen.bounce_offset(s), screen.PANEL_W, screen.PANEL_H)
		Draw.panel(self, r, col, seated)
		var cx := r.position.x + r.size.x / 2.0
		var icon_s := 2.4 if seated else 2.0
		Draw.role_icon(self, s, Vector2(cx, r.position.y + 62), icon_s, t)
		if not seated:
			# Blinking "press me" button where the device icon will appear.
			if int(t * 2.0 + s * 0.5) % 2 == 0:
				draw_circle(Vector2(cx, r.position.y + 150), 20, col, false, 4.0)
				draw_circle(Vector2(cx, r.position.y + 150), 9, col)
			draw_rect(r.grow(-4), Color(Draw.INK, 0.35))
			return
		var d := Players.device_of(s)
		var glow := 0.85 + 0.15 * sin(t * 6.0 + s)
		var dev_c := Vector2(cx, r.position.y + 150 - (int(t * 3.0 + s) % 2) * 2)
		if d.begins_with("pad:"):
			Draw.gamepad(self, dev_c, 2.2, Color(Draw.WHITE, glow))
		else:
			Draw.keyboard(self, dev_c, 2.0, Color(Draw.WHITE, glow))
		for i in 3:
			Draw.star(self, Vector2(cx - 26 + i * 26, r.position.y + 190), 6, col, t * 2.0 + i)
		if s == Players.Seat.DRIVER:
			var go := Draw.WHITE if int(t * 2.0) % 2 == 0 or screen.hold > 0.0 else Draw.GREY
			Draw.play_triangle(self, Vector2(cx, r.position.y + 214), 0.9, go)
			if screen.hold > 0.0:
				var p := clampf(screen.hold / screen.HOLD_TIME, 0.0, 1.0)
				draw_arc(Vector2(cx, r.position.y + 214), 16, -PI / 2, -PI / 2 + TAU * p, 32, Draw.WHITE, 4.0)

	## Key-shape legend under each panel; a block lights in its seat's colour.
	func _legend() -> void:
		draw_rect(Rect2(0, 292, 640, 68), Color(Draw.INK, 0.6))
		for block in 3:
			var d := "kb:%d" % block
			var seat := Players.seat_of(d)
			var col := Draw.GREY if seat == -1 else Players.SEAT_COLORS[seat]
			var cx: float = screen.PANEL_X[block] + screen.PANEL_W / 2.0
			match block:
				0: _cross_keys(cx - 8, col, true)
				1: _cross_keys(cx + 8, col, false)
				2: _key(Rect2(cx - 44, 320, 88, 16), col)

	func _cross_keys(cx: float, col: Color, fire_left: bool) -> void:
		_key(Rect2(cx - 7, 304, 14, 14), col)
		for i in 3:
			_key(Rect2(cx - 23 + i * 16, 320, 14, 14), col)
		var fx := cx - 51 if fire_left else cx + 28
		_key(Rect2(fx, 320, 22, 14), col.lightened(0.2))

	func _key(r: Rect2, col: Color) -> void:
		Draw.round_rect(self, r, 3, col.darkened(0.4))
		Draw.round_rect(self, Rect2(r.position, r.size - Vector2(0, 3)), 3, col)
