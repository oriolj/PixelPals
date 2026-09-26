extends Node2D
## Dimmed pause screen: a back arrow (pilot "b") and a play triangle ("a"/start).


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.1, 0.11, 0.17, 0.7))
	draw_circle(Vector2(110, 90), 22, Color("#b13e53"))
	draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
		Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#f4f4f4"))
	draw_circle(Vector2(210, 90), 26, Color("#38b764"))
	draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
		Color("#f4f4f4"))
