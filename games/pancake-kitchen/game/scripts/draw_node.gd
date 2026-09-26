extends Node2D
## A Node2D that draws with a callable: `node.fn = func(ci): ...`.
## Screens build their layers from these (no .tscn, no textures).

var fn: Callable


func _draw() -> void:
	if fn.is_valid():
		fn.call(self)


static func make(draw_fn: Callable) -> Node2D:
	var n: Node2D = load("res://scripts/draw_node.gd").new()
	n.fn = draw_fn
	return n
