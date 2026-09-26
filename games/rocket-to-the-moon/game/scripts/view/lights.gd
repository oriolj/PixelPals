extends Node2D
## The countdown lights on a dark panel, centred on x = 0. `out` lights are
## off; the rest glow. Frame 0 of countdown_light is off, frame 1 on.

const GAP := 4

var count := 5
var out := 0:
	set(v):
		out = v
		_refresh()
var _lights: Array[AnimatedSprite2D] = []


func _ready() -> void:
	var size := Art.size_of("countdown_light", Vector2i(12, 12))
	var total := count * size.x + (count - 1) * GAP
	for i in count:
		var l := Art.sprite("countdown_light", Color("#b13e53"), Vector2i(12, 12))
		l.stop()
		l.position = Vector2(-total / 2 + i * (size.x + GAP) + size.x / 2, 0)
		add_child(l)
		_lights.append(l)
	_refresh()
	queue_redraw()


func _refresh() -> void:
	for i in _lights.size():
		var on := i < count - out
		var l := _lights[i]
		if l.sprite_frames.get_frame_count("default") >= 2:
			l.frame = 1 if on else 0
			l.modulate = Color.WHITE
		else:
			l.modulate = Color.WHITE if on else Color(0.3, 0.3, 0.3)


func _draw() -> void:
	var size := Art.size_of("countdown_light", Vector2i(12, 12))
	var total := count * size.x + (count - 1) * GAP
	var r := Rect2(-total / 2 - 5, -size.y / 2 - 4, total + 10, size.y + 8)
	draw_rect(r, Color("#566c86"))
	draw_rect(r.grow(-1), Color("#1a1c2c"))
