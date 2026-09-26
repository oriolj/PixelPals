extends Node2D
## STUB — replaced by the select screen implementation.


func _ready() -> void:
	var r := ColorRect.new()
	r.size = Vector2(320, 180)
	r.color = Color(0.2, 0.2, 0.3)
	add_child(r)
