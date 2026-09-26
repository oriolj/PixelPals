extends Node2D
## The big launch button (the press seat's). It pulses with a ring in the
## seat colour while it is waiting for a press, and squashes when pressed.

var color := Color("#a7f070")
var waiting := false:
	set(v):
		waiting = v
		queue_redraw()
var time := 0.0
var _pressed_t := 0.0
var _sprite: AnimatedSprite2D
var px := 2


func _ready() -> void:
	_sprite = Art.sprite("big_button", Color("#b13e53"), Vector2i(24, 16))
	_sprite.stop()
	_sprite.scale = Vector2(px, px)
	add_child(_sprite)


func press() -> void:
	_pressed_t = 0.2


func tick(dt: float) -> void:
	time += dt
	_pressed_t = maxf(0.0, _pressed_t - dt)
	var down := _pressed_t > 0.0
	if _sprite.sprite_frames.get_frame_count("default") >= 2:
		_sprite.frame = 1 if down else 0
	var pulse := waiting and int(time * 3.0) % 2 == 0
	_sprite.position = Vector2(0, -px if pulse and not down else 0)
	queue_redraw()


func _draw() -> void:
	if not waiting:
		return
	var s := Art.size_of("big_button", Vector2i(24, 16)) * px
	var grow := 3 + (2 if int(time * 3.0) % 2 == 0 else 0)
	var r := Rect2(-s.x / 2 - grow, -s.y / 2 - grow, s.x + grow * 2, s.y + grow * 2)
	draw_rect(r, color, false, 2.0)
