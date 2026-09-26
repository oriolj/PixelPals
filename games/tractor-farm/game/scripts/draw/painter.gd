extends Node2D
## A node that draws with a callable: `fn.call(self)` from _draw(). Lets
## screens place any shapes.gd / crop_art.gd / farm_art.gd drawing as its own
## node (own transform, z-order, modulate, material) without a class per prop.

var fn: Callable


func _init(draw_fn := Callable()) -> void:
	fn = draw_fn


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)
