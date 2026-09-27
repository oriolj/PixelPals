extends Node2D
## The Pilot-only pause: the Pilot's start toggles it; in pause the Pilot's B goes
## back to join (seats kept) and A or start resumes. No other seat can pause.
## A stage screen calls `check()` first thing each step and skips its frame when
## it returns true.

signal back_to_join

var paused := false


func _ready() -> void:
	visible = false
	z_index = 100


## Returns true while paused (the stage skips its step).
func check() -> bool:
	var d := Players.Seat.DRIVER
	if not paused:
		if Players.just_pressed(d, "start"):
			paused = true
			visible = true
			Sfx.play("select")
			return true
		return false
	if Players.just_pressed(d, "b"):
		back_to_join.emit()
		return true
	if Players.just_pressed(d, "start") or Players.just_pressed(d, "a"):
		paused = false
		visible = false
		Sfx.play("select")
		return false
	return true


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), Color(0.094, 0.078, 0.145, 0.72))
	draw_circle(Vector2(110, 90), 22, Color("#e43b44"))
	draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
		Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#ffffff"))
	draw_circle(Vector2(210, 90), 26, Color("#63c74d"))
	draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
		Color("#ffffff"))
