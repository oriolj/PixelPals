extends Node2D
## A little bobble hat in a seat's chosen colour (the laser and treat seats
## pick one on the select screen). Origin = the bottom centre of the hat.

var color := Color("#ffcd75"):
	set(v):
		color = v
		queue_redraw()


func _draw() -> void:
	var dark := color.darkened(0.35)
	draw_colored_polygon(PackedVector2Array([Vector2(-6, 0), Vector2(6, 0), Vector2(4, -5), Vector2(-4, -5)]), color)
	draw_rect(Rect2(-6, -2, 12, 2), dark)
	draw_rect(Rect2(-2, -8, 4, 3), Color("#f4f4f4"))
