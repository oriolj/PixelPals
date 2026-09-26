extends Node2D
## Centre-bottom and centre-top info with no text: the count-in (four pairs
## of drumsticks lighting one per click), the song's progress (a note
## walking along a line of phrase dots) and the star meter.

const Draw := preload("res://scripts/view/draw.gd")

var band: RefCounted
var now := 0
var star_pulse := 0.0
var time := 0.0


func _process(delta: float) -> void:
	time += delta
	star_pulse = maxf(0.0, star_pulse - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	if band == null:
		return
	var beat: float = band.beat_at(now)
	# Count-in: four stick pairs, lit one per beat.
	if beat < 0.5:
		for k in 4:
			var lit := beat >= k - 4
			var c := Vector2(266 + k * 36, 118)
			var s := 1.3 if lit and beat < k - 3 else 1.0
			draw_circle(c, 17 * s, Color(Draw.INK, 0.75))
			Draw.sticks(self, c, 0.85 * s, Draw.YELLOW if lit else Draw.SLATE)
	# Progress: a line of ten phrase dots and a walking note.
	var y := 342.0
	draw_line(Vector2(222, y), Vector2(418, y), Color(Draw.WHITE, 0.3), 3.0)
	for k in 11:
		var x := 222 + k * 19.6
		draw_circle(Vector2(x, y), 3.0, Color(Draw.WHITE, 0.5))
	var p: float = band.progress(now)
	var nx := lerpf(222, 418, p)
	draw_line(Vector2(222, y), Vector2(nx, y), Draw.YELLOW, 3.0)
	Draw.note(self, Vector2(nx, y - 2 - absf(sin(time * PI * band.bpm / 60.0)) * 4.0), 0.75, Draw.WHITE)
	# Star meter: a star that pops on every gem hit, and a filling bar.
	var total: int = band.gems_lead.size() + band.gems_drum.size() + band.gems_crash.size()
	var frac := clampf(float(band.stars) / maxf(1.0, total * 0.6), 0.0, 1.0)
	var sc := Vector2(222, 318)
	Draw.star(self, sc, 11 + 5 * star_pulse, Draw.INK, 0.0)
	Draw.star(self, sc, 9 + 5 * star_pulse, Draw.YELLOW, 0.0)
	Draw.round_rect(self, Rect2(238, 312, 180, 12), 6, Color(Draw.INK, 0.8))
	if frac > 0.0:
		Draw.round_rect(self, Rect2(240, 314, 176 * frac, 8), 4, Draw.YELLOW)
