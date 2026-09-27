extends Node2D
## Two parallax star layers (stars_far, stars_near) that drift slowly left,
## drawn at whole-pixel offsets and tiled, over a flat space colour.

const Tex := preload("res://scripts/view/tex.gd")
const SPACE := Color("#181425")

var scroll := 0.0
var speeds := [3.0, 8.0]
var _far: Texture2D
var _near: Texture2D
var backdrop := true


func _ready() -> void:
	_far = Tex.texture("stars_far", Vector2i(320, 180), Color(0, 0, 0, 0))
	_near = Tex.texture("stars_near", Vector2i(320, 180), Color(0, 0, 0, 0))


func tick(dt: float) -> void:
	scroll += dt
	queue_redraw()


func _draw() -> void:
	if backdrop:
		draw_rect(Rect2(0, 0, 320, 180), SPACE)
	var layers := [_far, _near]
	for i in 2:
		var off := -fposmod(floorf(scroll * speeds[i]), 320.0)
		draw_texture(layers[i], Vector2(off, 0))
		draw_texture(layers[i], Vector2(off + 320, 0))
