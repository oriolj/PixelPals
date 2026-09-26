extends Node2D
## The Crasher's corner: one big instrument, the sound the next press will
## make (cymbal, gong, cowbell, whoosh). It glows on the bars where a crash
## is suggested and wobbles when hit.

const Draw := preload("res://scripts/view/draw.gd")
const CENTER := Vector2(538, 296)

var band: RefCounted
var now := 0
var sound := 0
var wobble := 0.0
var time := 0.0
## No live Crasher (the Lead's B crashes, or the auto-crash).
var ghost := false


func _process(delta: float) -> void:
	time += delta
	wobble = maxf(0.0, wobble - delta * 2.5)
	queue_redraw()


func suggested() -> bool:
	if band == null:
		return false
	for g in band.gems_crash:
		var dt: int = now - int(g.sample)
		if not g.hit and dt > -band.spb and dt < band.spb * 2.0:
			return true
	return false


func _draw() -> void:
	if suggested():
		var pulse := 0.5 + 0.5 * sin(time * 12.0)
		draw_circle(CENTER + Vector2(0, -6), 44 + 4 * pulse, Color(Draw.YELLOW, 0.18 + 0.12 * pulse))
		for k in 8:
			var a := TAU * k / 8 + time
			Draw.star(self, CENTER + Vector2(0, -6) + Vector2(cos(a), sin(a)) * 50, 4, Color(Draw.YELLOW, 0.7), a)
	var c := CENTER
	var mod := Color(1, 1, 1, 0.55) if ghost else Color.WHITE
	modulate = mod
	Draw.crash_instrument(self, sound, c, 1.7, sin(time * 30.0) * wobble, time)
