extends Node2D
## The Drummer's four pads in a d-pad cross: up = hi-hat (yellow), left =
## snare (blue), right = tom (green), down = kick (red). Gems slide in from
## outside toward the pad to hit; a pad bounces the frame it is pressed and
## glows softly when the auto-drummer plays it.

const Draw := preload("res://scripts/view/draw.gd")

const CENTER := Vector2(538, 142)
const OFFSET := 40.0
const RADIUS := 19.0
const TRAVEL := 34.0
const LOOKAHEAD_BEATS := 1.5

var band: RefCounted
var now := 0
var bounce: Array[float] = [0.0, 0.0, 0.0, 0.0]
var auto_glow: Array[float] = [0.0, 0.0, 0.0, 0.0]
## No live Drummer: the pads show the auto-drummer, dimmed.
var ghost := false
var time := 0.0


func _process(delta: float) -> void:
	time += delta
	for i in 4:
		bounce[i] = maxf(0.0, bounce[i] - delta * 5.0)
		auto_glow[i] = maxf(0.0, auto_glow[i] - delta * 5.0)
	queue_redraw()


func pad_pos(pad: int) -> Vector2:
	return CENTER + Draw.PAD_DIRS[pad] * OFFSET


func gem_pos(g: Dictionary) -> Vector2:
	var f: float = float(int(g.sample) - now) / (LOOKAHEAD_BEATS * band.spb)
	return pad_pos(int(g.pad)) + Draw.PAD_DIRS[int(g.pad)] * TRAVEL * f


func _draw() -> void:
	var fade := 0.45 if ghost else 1.0
	draw_circle(CENTER, 12, Color(Draw.INK, 0.9))
	Draw.sticks(self, CENTER, 0.5, Color(Draw.YELLOW, fade))
	# Target glow: a gem arriving within half a beat.
	var soon := [false, false, false, false]
	if band:
		for g in band.gems_drum:
			var dt: int = int(g.sample) - now
			if not g.hit and dt > -band.spb * 0.25 and dt < band.spb * 0.5:
				soon[int(g.pad)] = true
	for pad in 4:
		var p := pad_pos(pad)
		var col: Color = Draw.PAD_COLORS[pad]
		var r := RADIUS * (1.0 + 0.28 * bounce[pad])
		if soon[pad] and not ghost:
			draw_circle(p, r + 7 + 2 * sin(time * 20.0), Color(col, 0.35))
		draw_circle(p, r + 3, Draw.INK)
		draw_circle(p, r, Color(col.darkened(0.25), fade))
		draw_circle(p, r * 0.78, Color(Draw.WHITE.lerp(col, 0.25), fade))
		if auto_glow[pad] > 0.0:
			draw_circle(p, r * 0.78, Color(col, 0.6 * auto_glow[pad]))
		if bounce[pad] > 0.0:
			draw_circle(p, r * 0.78, Color(col, bounce[pad]))
		_pad_mark(pad, p, r, Color(Draw.INK, 0.55 * fade))
	if band == null:
		return
	for g in band.gems_drum:
		if g.hit:
			continue
		var f: float = float(int(g.sample) - now) / (LOOKAHEAD_BEATS * band.spb)
		if f > 1.0 or f < -0.1:
			continue
		var gp := gem_pos(g)
		var col: Color = Draw.PAD_COLORS[int(g.pad)]
		var a: float = fade * (1.0 if f >= 0.0 else 1.0 + f / 0.1)
		draw_circle(gp, 8, Color(Draw.INK, a))
		draw_circle(gp, 6.5, Color(col, a))
		draw_circle(gp + Vector2(-2, -2), 2.2, Color(Draw.WHITE, a))


func _pad_mark(pad: int, p: Vector2, r: float, col: Color) -> void:
	match pad:
		0:
			Draw.ellipse(self, p, r * 0.5, r * 0.16, col)
			draw_line(p + Vector2(0, -r * 0.35), p + Vector2(0, r * 0.35), col, 2.0)
		1:
			draw_line(p + Vector2(-r * 0.4, -r * 0.4), p + Vector2(r * 0.4, r * 0.4), col, 3.0)
			draw_line(p + Vector2(r * 0.4, -r * 0.4), p + Vector2(-r * 0.4, r * 0.4), col, 3.0)
		2:
			draw_circle(p, r * 0.35, col, false, 3.0)
		3:
			Draw.star(self, p, r * 0.45, col)
