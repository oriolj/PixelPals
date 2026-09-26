extends Node2D
## Root of the game. Screens are added under this node by Game.goto().


func _ready() -> void:
	Game.boot(self)
