extends RefCounted
## The building site, drawn once from point lists: sky, drifting clouds,
## hills, the platform, the ball pit, the height pole with its flags and the
## cloud line. Each piece is a small Node2D class below.

const Vec := preload("res://scripts/play/vec.gd")
const Rules := preload("res://scripts/play/rules.gd")

## World span drawn left and right of the 640 px screen (for the zoomed-out topple).
const WORLD_L := -760.0
const WORLD_R := 1400.0
const FLAG_COLORS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#38b764"), Color("#73eff7"), Color("#41a6f6"), Color("#5d275d")]
const POLE_X := 216.0


## Screen-fixed sky: a vertical gradient that darkens a little as the camera rises.
class SkyView extends Node2D:
	var rise := 0.0  # 0 at the ground, 1 high up
	var drift := 0.0
	var cam_y := 0.0

	func _draw() -> void:
		var top := Color("#41a6f6").lerp(Color("#3b5dc9"), clampf(rise, 0.0, 1.0) * 0.6)
		var bottom := Color("#73eff7").lerp(Color("#41a6f6"), clampf(rise, 0.0, 1.0) * 0.5)
		var bands := 24
		for i in bands:
			var c := top.lerp(bottom, float(i) / (bands - 1))
			draw_rect(Rect2(0, i * 360.0 / bands, 640, 360.0 / bands + 1.0), c)
		# The sun, top right, and far clouds drifting with a little parallax.
		var sun := Vector2(470, 70 - cam_y * 0.05)
		draw_circle(sun, 34, Color(1, 0.93, 0.6, 0.35), true, -1.0, true)
		Vec.draw_disc(self, sun, 24, Vec.YELLOW, Color("#ef7d57"), 3.0)
		for i in 5:
			var x := fposmod(i * 150.0 + drift * (8.0 + i * 2.0), 800.0) - 80.0
			var y := 40.0 + float((i * 53) % 150) - cam_y * 0.15
			y = fposmod(y, 420.0) - 30.0
			Vec.draw_cloud(self, Vector2(x, y), 0.9 + (i % 3) * 0.2, Color(1, 1, 1, 0.85), Color(0, 0, 0, 0), 0.0)


## Hills behind the site (world, parallax is not needed: the camera only rises).
class Hills extends Node2D:
	func _draw() -> void:
		_hill_row(Rules.PLATFORM_TOP - 70.0, 150.0, 60.0, Color("#38b764"), 0.0)
		_hill_row(Rules.PLATFORM_TOP - 30.0, 110.0, 44.0, Color("#a7f070"), 70.0)

	func _hill_row(base: float, width: float, height: float, col: Color, phase: float) -> void:
		var pts := PackedVector2Array()
		var x := WORLD_L
		pts.append(Vector2(WORLD_L, Rules.PIT_TOP + 60.0))
		while x <= WORLD_R:
			var k := (x + phase) / width
			var y := base - absf(sin(k * PI)) * height * (0.7 + 0.3 * sin(k * 1.7))
			pts.append(Vector2(x, y))
			x += 8.0
		pts.append(Vector2(WORLD_R, Rules.PIT_TOP + 60.0))
		draw_colored_polygon(pts, col)
		var line := pts.slice(1, pts.size() - 1)
		draw_polyline(line, Vec.INK, 3.0, true)
		# A few flowers / bushes dots.
		var rng := RandomNumberGenerator.new()
		rng.seed = int(base)
		for i in 40:
			var fx := rng.randf_range(WORLD_L, WORLD_R)
			var k := (fx + phase) / width
			var fy := base - absf(sin(k * PI)) * height * (0.7 + 0.3 * sin(k * 1.7)) + rng.randf_range(10, 40)
			draw_circle(Vector2(fx, fy), 2.5, col.darkened(0.25), true, -1.0, true)


## The platform the tower stands on, the ball pit around it and its floor.
class Site extends Node2D:
	var balls: Array = []  # [pos, r, col]

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		var cols := [Vec.RED, Vec.YELLOW, Vec.SKY, Vec.LIME, Vec.ORANGE, Vec.WHITE]
		# 60 balls on screen, more beyond it for the zoomed-out view.
		for i in 150:
			var x := rng.randf_range(WORLD_L + 20.0, WORLD_R - 20.0)
			if i < 60:
				x = rng.randf_range(0.0, 640.0)
			if absf(x - Rules.PLATFORM_X) < Rules.PLATFORM_HALF + 4.0:
				continue
			balls.append([Vector2(x, Rules.PIT_TOP + rng.randf_range(2.0, 34.0)), rng.randf_range(7.0, 10.0),
				cols[rng.randi() % cols.size()]])
		balls.sort_custom(func(a, b): return a[0].y < b[0].y)

	func _draw() -> void:
		# Pit tub (a soft padded rim) and its floor.
		draw_rect(Rect2(WORLD_L, Rules.PIT_TOP - 6.0, WORLD_R - WORLD_L, 200.0), Color("#5d275d"))
		draw_rect(Rect2(WORLD_L, Rules.PIT_TOP - 6.0, WORLD_R - WORLD_L, 6.0), Color("#b13e53"))
		draw_line(Vector2(WORLD_L, Rules.PIT_TOP - 6.0), Vector2(WORLD_R, Rules.PIT_TOP - 6.0), Vec.INK, 3.0, true)
		for b in balls:
			Vec.draw_disc(self, b[0], b[1], b[2], Vec.INK, 2.0)
			draw_circle(b[0] + Vector2(-2.5, -2.5), b[1] * 0.3, Color(1, 1, 1, 0.55), true, -1.0, true)
		# The platform: a friendly stone plinth with a wooden top.
		var half := Rules.PLATFORM_HALF
		var body := Vec.rounded(PackedVector2Array([Vector2(-half + 6, 0), Vector2(half - 6, 0),
			Vector2(half + 6, 90), Vector2(-half - 6, 90)]), 4.0, 2)
		body = Vec.translated(body, Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP))
		Vec.draw_shape(self, body, Color("#566c86"))
		for row in 3:
			var y := Rules.PLATFORM_TOP + 16.0 + row * 16.0
			draw_line(Vector2(Rules.PLATFORM_X - half, y), Vector2(Rules.PLATFORM_X + half, y), Color("#333c57"), 2.0, true)
			for k in 5:
				var x := Rules.PLATFORM_X - half + 20.0 + k * 36.0 + (row % 2) * 16.0
				draw_line(Vector2(x, y - 16.0), Vector2(x, y), Color("#333c57"), 2.0, true)
		var top := Vec.rounded_rect(half * 2.0 + 16.0, 14.0, 5.0)
		top = Vec.translated(top, Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP + 3.0))
		Vec.draw_shape(self, top, Color("#ef7d57"))
		draw_line(Vector2(Rules.PLATFORM_X - half, Rules.PLATFORM_TOP + 1.0), Vector2(Rules.PLATFORM_X + half, Rules.PLATFORM_TOP + 1.0),
			Color(1, 1, 1, 0.45), 2.0, true)
		# The grassy mound where the riders cheer (left).
		var mound := PackedVector2Array()
		for i in 13:
			var a := PI + PI * i / 12.0
			mound.append(Vector2(70 + cos(a) * 78.0, Rules.PIT_TOP + 8.0 + sin(a) * 22.0))
		Vec.draw_shape(self, mound, Color("#38b764"))


## The ball pit's front row, drawn over the blocks so fallen blocks sink in.
class PitFront extends Node2D:
	var balls: Array = []

	func _ready() -> void:
		var rng := RandomNumberGenerator.new()
		rng.seed = 11
		var cols := [Vec.RED, Vec.YELLOW, Vec.SKY, Vec.LIME, Vec.ORANGE, Vec.WHITE]
		var x := WORLD_L
		while x < WORLD_R:
			if absf(x - Rules.PLATFORM_X) > Rules.PLATFORM_HALF + 10.0:
				balls.append([Vector2(x, Rules.PIT_TOP + 22.0 + rng.randf_range(-3.0, 6.0)), rng.randf_range(8.0, 11.0),
					cols[rng.randi() % cols.size()]])
			x += rng.randf_range(12.0, 18.0)

	func _draw() -> void:
		for b in balls:
			Vec.draw_disc(self, b[0], b[1], b[2], Vec.INK, 2.0)
			draw_circle(b[0] + Vector2(-3, -3), b[1] * 0.3, Color(1, 1, 1, 0.55), true, -1.0, true)
		draw_rect(Rect2(WORLD_L, Rules.PIT_TOP + 30.0, WORLD_R - WORLD_L, 200.0), Color("#5d275d"))
		draw_line(Vector2(WORLD_L, Rules.PIT_TOP + 30.0), Vector2(WORLD_R, Rules.PIT_TOP + 30.0), Vec.INK, 3.0, true)


## The height pole: a rope with 8 flags; reached flags are raised in colour,
## and a marker line shows the settled height. The last flag is the cloud line.
class Pole extends Node2D:
	var reached := 0
	var height := 0.0
	var shown_height := 0.0
	var time := 0.0
	var pop := [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

	func flag_y(i: int) -> float:
		return Rules.PLATFORM_TOP - Rules.FLAG_STEP * (i + 1)

	func step(dt: float) -> void:
		time += dt
		shown_height = lerpf(shown_height, height, minf(1.0, dt * 4.0))
		for i in pop.size():
			pop[i] = maxf(0.0, pop[i] - dt)
		queue_redraw()

	func _draw() -> void:
		var x := POLE_X
		var top := flag_y(Rules.FLAGS - 1) - 12.0
		draw_line(Vector2(x, Rules.PIT_TOP), Vector2(x, top), Vec.INK, 7.0, true)
		draw_line(Vector2(x, Rules.PIT_TOP), Vector2(x, top), Color("#ef7d57"), 3.0, true)
		Vec.draw_disc(self, Vector2(x, top - 2.0), 5.0, Vec.YELLOW)
		for i in Rules.FLAGS:
			var y := flag_y(i)
			var col: Color = FLAG_COLORS[i]
			draw_line(Vector2(x - 6, y), Vector2(x + 6, y), Vec.INK, 3.0, true)
			if i < reached:
				var wave := sin(time * 6.0 + i) * 3.0
				var s: float = 1.0 + pop[i] * 1.2
				var pts := PackedVector2Array([Vector2(x - 2, y - 12 * s), Vector2(x - 28 * s, y - 6 * s + wave),
					Vector2(x - 2, y)])
				Vec.draw_shape(self, pts, col, Vec.INK, 2.5)
			else:
				var pts := PackedVector2Array([Vector2(x - 2, y - 6), Vector2(x - 12, y - 3), Vector2(x - 2, y)])
				Vec.draw_shape(self, pts, Color(col, 0.35), Color(Vec.INK, 0.4), 1.5)
		# The height marker: a dashed rope from the pole to the tower top.
		if shown_height > 4.0:
			var y := Rules.PLATFORM_TOP - shown_height
			var dash := 0.0
			while dash < 150.0:
				draw_line(Vector2(x + 4 + dash, y), Vector2(x + 12 + dash, y), Vec.WHITE, 3.0, true)
				dash += 14.0
			Vec.draw_disc(self, Vector2(x, y), 5.0, Vec.WHITE)


## The cloud line: puffy clouds at the target height with faces that cheer
## when the tower reaches them, and a sparkly dotted line across.
class CloudLine extends Node2D:
	var reached := false
	var time := 0.0

	func step(dt: float) -> void:
		time += dt
		queue_redraw()

	func _draw() -> void:
		var y := Rules.PLATFORM_TOP - Rules.CLOUD_HEIGHT
		for i in 40:
			var x := -600.0 + i * 50.0
			if absf(x - Rules.PLATFORM_X) < 60.0:
				continue
			var tw := 0.5 + 0.5 * sin(time * 4.0 + i)
			draw_circle(Vector2(x, y), 2.0 + tw * 1.5, Color(1, 1, 0.8, 0.5 + 0.5 * tw), true, -1.0, true)
		var fill := Color("#fff6c8") if reached else Vec.WHITE
		for c in [Vector2(90, y), Vector2(550, y), Vector2(-150, y - 8), Vector2(790, y - 8)]:
			Vec.draw_cloud(self, c, 1.3, fill)
			var bob := sin(time * (8.0 if reached else 2.0)) * (3.0 if reached else 1.0)
			var e: Vector2 = c + Vector2(0, -2 + bob)
			if reached:
				for dx in [-8.0, 8.0]:
					draw_polyline(PackedVector2Array([e + Vector2(dx - 4, 2), e + Vector2(dx, -2), e + Vector2(dx + 4, 2)]),
						Vec.INK, 2.5, true)
				draw_circle(e + Vector2(0, 9), 4.0, Vec.INK, true, -1.0, true)
			else:
				for dx in [-8.0, 8.0]:
					draw_circle(e + Vector2(dx, 0), 2.5, Vec.INK, true, -1.0, true)
				draw_arc(e + Vector2(0, 5), 4.0, 0.3, PI - 0.3, 6, Vec.INK, 2.0, true)
