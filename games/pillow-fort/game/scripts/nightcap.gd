extends Node2D
## A floppy nightcap in the seat colour (the "pyjama colour" of each seat),
## drawn over a 16x16 rider. Child of the rider sprite; origin = rider centre.

var color := Color("#ffcd75"):
	set(v):
		color = v
		queue_redraw()


func _draw() -> void:
	var dark := color.darkened(0.35)
	# Cone flopping to the right, with a shaded underside.
	draw_colored_polygon(PackedVector2Array([Vector2(-5, -5), Vector2(4, -5), Vector2(8, -10), Vector2(2, -11)]), color)
	draw_colored_polygon(PackedVector2Array([Vector2(1, -5), Vector2(4, -5), Vector2(8, -10)]), dark)
	# White brim and pompom.
	draw_rect(Rect2(-6, -6, 12, 2), Color("#f4f4f4"))
	draw_rect(Rect2(8, -12, 2, 2), Color("#f4f4f4"))
