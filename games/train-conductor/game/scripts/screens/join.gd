extends Node2D
## Join screen: any device presses to take the next seat.
##
## Logic copied from PixelPals (games/pixelpals/game/scripts/screens/join.gd),
## redrawn in this game's vector style at 1280x720:
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The driver continues with "start", or by holding "a" for HOLD_TIME
##   (a ring fills around the driver panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   whistle seat, and yields a lower seat to a real device when seats are full.
## No text: seat colours, role icons (lever, junction sign, whistle), device
## icons and a key-shape legend. The toy train waits below with its windows.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Icons := preload("res://scripts/screens/icons.gd")
const MenuTrain := preload("res://scripts/screens/menu_train.gd")

const HOLD_TIME := 1.0
const PANEL_W := 340
const PANEL_H := 330
const PANEL_Y := 36
const PANEL_X: Array[int] = [70, 470, 870]
const TODDLER := "kb:2"

var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var train: Node2D


func _ready() -> void:
	train = MenuTrain.new()
	add_child(train)
	train.setup(Vector2(960, 470), _riders(), 1, 1.4)
	Sfx.music("music_menu")


func _riders() -> Array[String]:
	var out: Array[String] = []
	for s in Players.SEAT_COUNT:
		out.append(Game.roster[s % Game.roster.size()] if Players.is_seated(s) else "")
	return out


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
			if train:
				train.toot()
			if seat == Players.Seat.DRIVER:
				_hold_armed = false
				hold = 0.0
	if train:
		train.view.set_riders(_riders())

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
	Icons.backdrop(self, _time)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	Shapes.fill_outline(self, Shapes.rounded_rect(r, 28), col if seated else Color(Palette.WHITE, 0.55), 4.0)
	Shapes.fill_outline(self, Shapes.rounded_rect(r.grow(-12), 20), col.lightened(0.55) if seated else Color(Palette.WHITE, 0.4), 0.0)
	var cx := r.position.x + PANEL_W * 0.5
	var role_col := col if seated else Palette.ROCK.lightened(0.3)
	Icons.role(self, s, Vector2(cx, r.position.y + 95), 2.0, role_col)
	var dev_y := r.position.y + 215
	if not seated:
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_arc(Vector2(cx, dev_y), 34, 0, TAU, 32, col.darkened(0.2), 6.0)
			draw_circle(Vector2(cx, dev_y), 16, col.darkened(0.2))
		return
	var d := Players.device_of(s)
	var bob := sin(_time * 5.0 + s) * 3.0
	if d.begins_with("pad:"):
		Icons.pad(self, Vector2(cx, dev_y + bob), 2.0, Palette.WHITE)
	else:
		Icons.keyboard(self, Vector2(cx, dev_y + bob), 2.0, Palette.WHITE)
	if s == Players.Seat.DRIVER:
		var ty := r.position.y + 290
		var tri := PackedVector2Array([Vector2(cx - 20, ty - 26), Vector2(cx + 26, ty), Vector2(cx - 20, ty + 26)])
		var go := Palette.WHITE if int(_time * 2.0) % 2 == 0 or hold > 0.0 else col.lightened(0.3)
		Shapes.fill_outline(self, tri, go, 3.0)
		if hold > 0.0:
			var k := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 40, -PI / 2, -PI / 2 + TAU * k, 40, Palette.WHITE, 8.0)


## Key-shape legend on the grass: which keys each seat uses; a block lights
## up in the colour of the seat it took.
func _draw_legend() -> void:
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := Palette.WHITE if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PANEL_X[block] + PANEL_W * 0.5
		match block:
			0:
				_cross_keys(cx - 20, col, true)
			1:
				_cross_keys(cx + 20, col, false)
			2:
				_key(Rect2(cx - 110, 640, 220, 40), col)


func _cross_keys(cx: float, col: Color, fire_left: bool) -> void:
	_key(Rect2(cx - 20, 596, 40, 40), col)
	for i in 3:
		_key(Rect2(cx - 64 + i * 44, 640, 40, 40), col)
	var fx := cx - 138.0 if fire_left else cx + 78.0
	_key(Rect2(fx, 640, 60, 40), col.lightened(0.2))


func _key(r: Rect2, col: Color) -> void:
	Shapes.fill_outline(self, Shapes.rounded_rect(r, 8), col.darkened(0.25), 3.0)
	draw_colored_polygon(Shapes.rounded_rect(Rect2(r.position + Vector2(3, 3), r.size - Vector2(6, 12)), 6), col)
