extends Control
## "Who is here": one coloured bubble per connected pad, plus one per keyboard
## block once somebody has pressed a key in it. A bubble pops in when its
## device appears, hops when that device presses something and pops out when
## a pad is unplugged. Right-aligned at the control's top-right corner.

const Pal := preload("res://scripts/palette.gd")
const R := 30.0
const GAP := 18.0

## device key -> {"color": Color, "pop": 0..1 (appear), "hop": seconds left, "gone": bool}
var devices := {}
var _order: Array[String] = []
var _next_color := 0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for id in Input.get_connected_joypads():
		add_device("pad:%d" % id)
	Input.joy_connection_changed.connect(_on_joy)


func _on_joy(id: int, connected: bool) -> void:
	var key := "pad:%d" % id
	if connected:
		add_device(key)
	elif devices.has(key):
		devices[key].gone = true


func add_device(key: String) -> void:
	if devices.has(key):
		devices[key].gone = false
		return
	devices[key] = {"color": Pal.DEVICE_COLORS[_next_color % Pal.DEVICE_COLORS.size()], "pop": 0.0,
		"hop": 0.0, "gone": false}
	_next_color += 1
	_order.append(key)


## A device pressed something: make sure it has a bubble and make it hop.
func ping(key: String) -> void:
	if key.begins_with("demo:"):
		return
	add_device(key)
	devices[key].hop = 0.35


func _process(delta: float) -> void:
	for key in _order.duplicate():
		var d: Dictionary = devices[key]
		if d.gone:
			d.pop -= delta * 4.0
			if d.pop <= 0.0:
				devices.erase(key)
				_order.erase(key)
		else:
			d.pop = minf(1.0, d.pop + delta * 3.0)
		d.hop = maxf(0.0, d.hop - delta)
	queue_redraw()


func _draw() -> void:
	var x := size.x - R
	for i in range(_order.size() - 1, -1, -1):
		var key := _order[i]
		var d: Dictionary = devices[key]
		var s := _ease_back(clampf(d.pop, 0.0, 1.0))
		var hop := sin(d.hop / 0.35 * PI) * 14.0 if d.hop > 0.0 else 0.0
		var c := Vector2(x, R + 6 - hop)
		var col: Color = d.color
		draw_circle(c + Vector2(0, 5), R * s, Color(0, 0, 0, 0.3), true, -1.0, true)
		draw_circle(c, R * s, col, true, -1.0, true)
		draw_arc(c, R * s, 0, TAU, 40, Pal.NIGHT, 4.0, true)
		if s > 0.4:
			if key.begins_with("pad:"):
				_draw_pad(c, s)
			else:
				_draw_keyboard(c, s)
		x -= R * 2 + GAP


static func _ease_back(t: float) -> float:
	var c := 1.9
	return 1.0 + (c + 1.0) * pow(t - 1.0, 3) + c * pow(t - 1.0, 2)


func _draw_pad(c: Vector2, s: float) -> void:
	var k := s * 0.9
	var col := Pal.NIGHT
	draw_rect(Rect2(c + Vector2(-15, -7) * k, Vector2(30, 13) * k), col)
	draw_circle(c + Vector2(-13, 3) * k, 7 * k, col, true, -1.0, true)
	draw_circle(c + Vector2(13, 3) * k, 7 * k, col, true, -1.0, true)
	draw_rect(Rect2(c + Vector2(-13, -2) * k, Vector2(7, 2.5) * k), Pal.WHITE)
	draw_rect(Rect2(c + Vector2(-10.7, -4.3) * k, Vector2(2.5, 7) * k), Pal.WHITE)
	draw_circle(c + Vector2(9, -2) * k, 2 * k, Pal.WHITE, true, -1.0, true)
	draw_circle(c + Vector2(13, 1) * k, 2 * k, Pal.WHITE, true, -1.0, true)


func _draw_keyboard(c: Vector2, s: float) -> void:
	var k := s * 0.9
	draw_rect(Rect2(c + Vector2(-17, -10) * k, Vector2(34, 20) * k), Pal.NIGHT)
	for row in 2:
		for col in 4:
			draw_rect(Rect2(c + Vector2(-14 + col * 7.5, -7 + row * 6.5) * k, Vector2(5, 4.5) * k), Pal.WHITE)
	draw_rect(Rect2(c + Vector2(-9, 5.5) * k, Vector2(18, 3) * k), Pal.WHITE)
