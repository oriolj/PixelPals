extends Node2D
## Screen-space HUD, no text: 12 delivery pips (each fills with the shape of
## the colour delivered), a sun that crosses the sky as the run goes on (the
## moon at the end), the driver's throttle lever and a speed dial, and the
## pause overlay (back arrow = driver "b", play = "a"/start).

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")

const PIP_R := 17.0
const PIP_GAP := 42.0

var sim
var paused := false
var time := 0.0
var night := 0.0
## pip index -> pop seconds
var pops := {}
var shown := 0


func setup(run_sim) -> void:
	sim = run_sim


func _process(delta: float) -> void:
	time += delta
	while shown < mini(sim.deliveries.size(), sim.DELIVERIES_TO_WIN):
		pops[shown] = 0.5
		shown += 1
	for k in pops:
		pops[k] = maxf(0.0, pops[k] - delta)
	queue_redraw()


func _draw() -> void:
	_draw_pips()
	_draw_sun()
	_draw_lever()
	if paused:
		_draw_pause()


func _draw_pips() -> void:
	var n: int = sim.DELIVERIES_TO_WIN
	var w := n * PIP_GAP + 16.0
	var x0 := 640.0 - w * 0.5
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(x0, 10, w, 56), 26), Color(Palette.WHITE, 0.88), 3.0)
	for i in n:
		var c := Vector2(x0 + 8.0 + PIP_GAP * (i + 0.5), 38)
		if i < sim.deliveries.size():
			var p: float = pops.get(i, 0.0)
			var s := 1.0 + 0.6 * sin(p / 0.5 * PI) if p > 0.0 else 1.0
			Draw.token(self, sim.deliveries[i], c, PIP_R * s)
		else:
			draw_circle(c, PIP_R * 0.55, Color(Palette.INK, 0.18))


func _draw_sun() -> void:
	var k := clampf(sim.time / sim.run_len, 0.0, 1.0)
	var centre := Vector2(1160, 110)
	var arc_r := 80.0
	draw_arc(centre, arc_r, PI, TAU, 24, Color(Palette.WHITE, 0.6), 4.0)
	var p := centre + Vector2.from_angle(PI + PI * k) * arc_r
	if night > 0.5 or sim.ended:
		# The moon.
		Shapes.fill_outline(self, Shapes.circle(p, 20, 24), Palette.CREAM, 3.0)
		draw_circle(p + Vector2(8, -5), 15, Palette.NIGHT.lightened(0.2))
	else:
		for i in 8:
			var a := TAU * i / 8.0 + time * 0.5
			draw_line(p + Vector2.from_angle(a) * 24.0, p + Vector2.from_angle(a) * 32.0, Palette.STATION[2], 5.0)
		Shapes.fill_outline(self, Shapes.circle(p, 20, 24), Palette.GLOW, 3.0)
		draw_arc(p + Vector2(0, 3), 8.0, 0.4, PI - 0.4, 10, Palette.INK, 2.5)
		draw_circle(p + Vector2(-6, -4), 2.2, Palette.INK)
		draw_circle(p + Vector2(6, -4), 2.2, Palette.INK)


func _draw_lever() -> void:
	# Throttle lever (driver): the handle leans forward with the throttle.
	var base := Vector2(70, 650)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(base + Vector2(-44, -10), Vector2(88, 40)), 12), Color(Palette.WHITE, 0.85), 3.0)
	var ang := lerpf(-2.2, -0.9, sim.throttle)
	var tip := base + Vector2.from_angle(ang) * 70.0
	draw_line(base, tip, Palette.INK, 10.0)
	draw_line(base, tip, Palette.ROCK, 6.0)
	Shapes.fill_outline(self, Shapes.circle(tip, 13, 20), Palette.STATION[0], 3.0)
	Shapes.fill_outline(self, Shapes.circle(base, 9, 16), Palette.BLACK, 2.0)
	# Speed dial.
	var dial := Vector2(180, 660)
	Shapes.fill_outline(self, Shapes.circle(dial, 40, 32), Color(Palette.WHITE, 0.9), 3.0)
	for i in 5:
		var a := lerpf(PI * 0.8, PI * 2.2, i / 4.0)
		draw_line(dial + Vector2.from_angle(a) * 30.0, dial + Vector2.from_angle(a) * 37.0, Palette.INK, 3.0)
	draw_arc(dial, 33, PI * 1.85, PI * 2.2, 8, Palette.STATION[0], 6.0)
	var v := clampf(absf(sim.train.speed) / sim.V_MAX, 0.0, 1.0)
	var na := lerpf(PI * 0.8, PI * 2.2, v)
	draw_line(dial, dial + Vector2.from_angle(na) * 30.0, Palette.INK, 4.0)
	draw_circle(dial, 6, Palette.INK)


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color(Palette.INK, 0.6))
	# Back arrow (driver b) on the left, big play triangle on the right.
	var back := Shapes.xform(Shapes.arrow(140, 40, 90), Transform2D(PI, Vector2(420, 360)))
	Shapes.fill_outline(self, Shapes.circle(Vector2(420, 360), 110, 40), Color(Palette.WHITE, 0.15), 0.0)
	Shapes.fill_outline(self, back, Palette.STATION[0], 4.0)
	var pulse := 1.0 + 0.06 * sin(time * 5.0)
	var tri := PackedVector2Array([Vector2(-50, -65), Vector2(75, 0), Vector2(-50, 65)])
	Shapes.fill_outline(self, Shapes.circle(Vector2(860, 360), 110 * pulse, 40), Color(Palette.WHITE, 0.15), 0.0)
	Shapes.fill_outline(self, Shapes.xform(tri, Transform2D(0, Vector2(860, 360)).scaled_local(Vector2.ONE * pulse)), Palette.STATION[3], 4.0)
