extends RefCounted
## Vector geometry for everything painted onto the canvas: the 8 stamps, the
## splat blobs with drips, and the soft brush dab. Pure data (point lists), so
## the logic tests can check it headless; the painter turns it into draw calls.
##
## A shape is an Array of parts. A part is a Dictionary:
##   {"pts": PackedVector2Array, "col": Color, "edge": Color}  filled polygon
##       with an anti-aliased outline in `edge` (same as col = just smoothing)
##   {"line": PackedVector2Array, "col": Color, "width": float} a stroke

const Palette := preload("res://scripts/paint/palette.gd")

const STAMPS: Array[String] = ["star", "heart", "flower", "fish", "sun", "cat", "car", "house"]
const STAMP_SIZE := 150.0


# ---------------------------------------------------------------- primitives

static func circle(c: Vector2, r: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func ellipse(c: Vector2, rx: float, ry: float, n := 40) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func rounded_rect(r: Rect2, rad: float, per_corner := 6) -> PackedVector2Array:
	var out := PackedVector2Array()
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - rad, rad), -PI / 2],
		[r.position + Vector2(r.size.x - rad, r.size.y - rad), 0.0],
		[r.position + Vector2(rad, r.size.y - rad), PI / 2],
		[r.position + Vector2(rad, rad), PI],
	]
	for c in corners:
		for i in per_corner + 1:
			var a: float = c[1] + (PI / 2) * i / per_corner
			out.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return out


static func polygon_area(pts: PackedVector2Array) -> float:
	var a := 0.0
	for i in pts.size():
		var p := pts[i]
		var q := pts[(i + 1) % pts.size()]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


static func parts_area(parts: Array) -> float:
	var a := 0.0
	for p in parts:
		if p.has("pts"):
			a += polygon_area(p.pts)
	return a


static func part(pts: PackedVector2Array, col: Color, edge := Color(0, 0, 0, 0)) -> Dictionary:
	return {"pts": pts, "col": col, "edge": col if edge.a == 0.0 else edge}


static func line(pts: PackedVector2Array, col: Color, width: float) -> Dictionary:
	return {"line": pts, "col": col, "width": width}


# ---------------------------------------------------------------- stamps

## The stamp `kind` centred on `c`, about `s` canvas px across, in colour `col`.
static func stamp(kind: String, c: Vector2, s: float, col: Color) -> Array:
	var edge := col.darkened(0.3)
	var det: Color = Palette.detail_on(col)
	var out: Array = []
	match kind:
		"star":
			var pts := PackedVector2Array()
			for i in 10:
				var a := -PI / 2 + TAU * i / 10.0
				var r := s * (0.5 if i % 2 == 0 else 0.22)
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			out.append(part(pts, col, edge))
			out.append(part(circle(c + Vector2(-0.07, -0.07) * s, s * 0.05, 16), col.lightened(0.5)))
		"heart":
			var pts := PackedVector2Array()
			for i in 48:
				var t := TAU * i / 48.0
				var x := 16.0 * pow(sin(t), 3)
				var y := 13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t)
				pts.append(c + Vector2(x, -y - 2.5) * (s / 34.0))
			out.append(part(pts, col, edge))
			out.append(part(ellipse(c + Vector2(-0.2, -0.17) * s, s * 0.07, s * 0.045, 16), col.lightened(0.5)))
		"flower":
			for i in 6:
				var a := TAU * i / 6.0 - PI / 2
				out.append(part(circle(c + Vector2(cos(a), sin(a)) * s * 0.27, s * 0.2, 28), col, edge))
			var mid := Color("#ffcd75") if col.get_luminance() < 0.6 or col.h > 0.2 else Color("#ef7d57")
			if col.is_equal_approx(Color("#ffcd75")):
				mid = Color("#ef7d57")
			out.append(part(circle(c, s * 0.19, 28), mid, mid.darkened(0.25)))
		"fish":
			var body_c := c + Vector2(-0.08, 0) * s
			out.append(part(PackedVector2Array([c + Vector2(0.18, 0) * s, c + Vector2(0.5, -0.22) * s,
				c + Vector2(0.44, 0) * s, c + Vector2(0.5, 0.22) * s]), col.darkened(0.15), edge))
			out.append(part(PackedVector2Array([body_c + Vector2(-0.1, -0.18) * s, body_c + Vector2(0.08, -0.34) * s,
				body_c + Vector2(0.16, -0.16) * s]), col.darkened(0.15), edge))
			out.append(part(ellipse(body_c, s * 0.34, s * 0.22, 40), col, edge))
			out.append(part(circle(body_c + Vector2(-0.18, -0.05) * s, s * 0.065, 20), Palette.WHITE))
			out.append(part(circle(body_c + Vector2(-0.19, -0.05) * s, s * 0.035, 16), Palette.INK))
			out.append(line(_arc(body_c + Vector2(0.02, 0) * s, s * 0.12, -0.9, 0.9, 10), edge, s * 0.025))
		"sun":
			for i in 12:
				var a := TAU * i / 12.0
				var d := Vector2(cos(a), sin(a))
				var n := Vector2(-d.y, d.x)
				out.append(part(PackedVector2Array([c + d * s * 0.3 + n * s * 0.07, c + d * s * 0.5,
					c + d * s * 0.3 - n * s * 0.07]), col, edge))
			out.append(part(circle(c, s * 0.3, 40), col, edge))
			out.append(part(circle(c + Vector2(-0.1, -0.06) * s, s * 0.035, 14), det))
			out.append(part(circle(c + Vector2(0.1, -0.06) * s, s * 0.035, 14), det))
			out.append(line(_arc(c + Vector2(0, 0.02) * s, s * 0.14, 0.35, PI - 0.35, 12), det, s * 0.03))
		"cat":
			var head := c + Vector2(0, 0.06) * s
			for side in [-1.0, 1.0]:
				out.append(part(PackedVector2Array([head + Vector2(side * 0.33, -0.1) * s,
					head + Vector2(side * 0.3, -0.44) * s, head + Vector2(side * 0.08, -0.3) * s]), col, edge))
				out.append(part(PackedVector2Array([head + Vector2(side * 0.27, -0.16) * s,
					head + Vector2(side * 0.27, -0.36) * s, head + Vector2(side * 0.14, -0.27) * s]), Color("#ff5fa2")))
			out.append(part(ellipse(head, s * 0.36, s * 0.3, 44), col, edge))
			for side in [-1.0, 1.0]:
				out.append(part(ellipse(head + Vector2(side * 0.13, -0.05) * s, s * 0.045, s * 0.065, 16), det))
				for k in 2:
					var y := (0.06 + k * 0.06) * s
					out.append(line(PackedVector2Array([head + Vector2(side * 0.1 * s, y * 0.6),
						head + Vector2(side * 0.44 * s, y - 0.03 * s)]), det, s * 0.018))
			out.append(part(PackedVector2Array([head + Vector2(-0.05, 0.04) * s, head + Vector2(0.05, 0.04) * s,
				head + Vector2(0, 0.1) * s]), Color("#ff5fa2"), Color("#b13e53")))
		"car":
			var body := Rect2(c + Vector2(-0.47, -0.02) * s, Vector2(0.94, 0.26) * s)
			out.append(part(PackedVector2Array([c + Vector2(-0.28, 0.0) * s, c + Vector2(-0.17, -0.26) * s,
				c + Vector2(0.16, -0.26) * s, c + Vector2(0.3, 0.0) * s]), col, edge))
			out.append(part(PackedVector2Array([c + Vector2(-0.21, -0.02) * s, c + Vector2(-0.14, -0.2) * s,
				c + Vector2(-0.02, -0.2) * s, c + Vector2(-0.02, -0.02) * s]), Color("#d8f0ff")))
			out.append(part(PackedVector2Array([c + Vector2(0.02, -0.02) * s, c + Vector2(0.02, -0.2) * s,
				c + Vector2(0.13, -0.2) * s, c + Vector2(0.22, -0.02) * s]), Color("#d8f0ff")))
			out.append(part(rounded_rect(body, s * 0.08), col, edge))
			out.append(part(circle(c + Vector2(0.42, 0.06) * s, s * 0.04, 12), Color("#ffcd75")))
			for x in [-0.25, 0.25]:
				out.append(part(circle(c + Vector2(x, 0.25) * s, s * 0.12, 28), Palette.INK))
				out.append(part(circle(c + Vector2(x, 0.25) * s, s * 0.05, 16), Color("#94b0c2")))
		"house":
			var roof := col.darkened(0.35)
			out.append(part(rounded_rect(Rect2(c + Vector2(-0.3, -0.08) * s, Vector2(0.6, 0.5) * s), s * 0.02), col, edge))
			out.append(part(PackedVector2Array([c + Vector2(-0.42, -0.05) * s, c + Vector2(0, -0.45) * s,
				c + Vector2(0.42, -0.05) * s]), roof, roof.darkened(0.2)))
			out.append(part(rounded_rect(Rect2(c + Vector2(-0.2, 0.14) * s, Vector2(0.14, 0.28) * s), s * 0.04),
				Color("#8b5a2b"), Color("#5d3a1a")))
			out.append(part(rounded_rect(Rect2(c + Vector2(0.04, 0.04) * s, Vector2(0.18, 0.16) * s), s * 0.02),
				Color("#d8f0ff"), Palette.WHITE))
			out.append(line(PackedVector2Array([c + Vector2(0.13, 0.04) * s, c + Vector2(0.13, 0.2) * s]), edge, s * 0.02))
			out.append(line(PackedVector2Array([c + Vector2(0.04, 0.12) * s, c + Vector2(0.22, 0.12) * s]), edge, s * 0.02))
	return out


static func _arc(c: Vector2, r: float, a0: float, a1: float, n: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


# ---------------------------------------------------------------- splats

## A wobbly closed blob: `n` noise-offset radii, smoothed with Catmull-Rom.
static func blob(c: Vector2, r: float, rng: RandomNumberGenerator, n := 16) -> PackedVector2Array:
	var radii: Array[float] = []
	for i in n:
		radii.append(r * rng.randf_range(0.78, 1.18))
	var out := PackedVector2Array()
	var sub := 4
	for i in n:
		for k in sub:
			var t := float(k) / sub
			var r0 := radii[(i - 1 + n) % n]
			var r1 := radii[i]
			var r2 := radii[(i + 1) % n]
			var r3 := radii[(i + 2) % n]
			var rr := 0.5 * ((2.0 * r1) + (-r0 + r2) * t + (2.0 * r0 - 5.0 * r1 + 4.0 * r2 - r3) * t * t
				+ (-r0 + 3.0 * r1 - 3.0 * r2 + r3) * t * t * t)
			var a := TAU * (i + t) / n
			out.append(c + Vector2(cos(a), sin(a)) * rr)
	return out


## A splat: the blob, 3-6 drips running down and a few droplets. `cols` gives
## the colour per ring (one colour = a plain splat; the rainbow passes 6).
## Returns parts, ready to draw; its total area is at most `max_area`.
static func splat(c: Vector2, r: float, cols: Array, rng: RandomNumberGenerator, max_area := INF) -> Array:
	var parts := _splat_parts(c, r, cols, rng.randi())
	var area := parts_area(parts)
	if area > max_area:
		# Shrink it to fit (area scales with r squared); same seed = same shape.
		var k := sqrt(max_area / area) * 0.98
		parts = _splat_parts(c, r * k, cols, rng.randi())
		area = parts_area(parts)
		var tries := 0
		while area > max_area and tries < 8:
			k *= 0.9
			parts = _splat_parts(c, r * k, cols, rng.randi())
			area = parts_area(parts)
			tries += 1
	return parts


static func _splat_parts(c: Vector2, r: float, cols: Array, seed_value: int) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var out: Array = []
	var base: Color = cols[0]
	var shape := blob(c, r, rng, rng.randi_range(12, 20))
	# Drips run down from the lower half of the blob.
	var ndrips := rng.randi_range(3, 6)
	for i in ndrips:
		var a := lerpf(0.2 * PI, 0.8 * PI, (i + rng.randf_range(0.2, 0.8)) / ndrips)
		var start := c + Vector2(cos(a), sin(a)) * r * 0.7
		var w := r * rng.randf_range(0.1, 0.17)
		var length := r * rng.randf_range(0.45, 1.0)
		var dcol: Color = cols[rng.randi() % cols.size()]
		var drip := PackedVector2Array([start + Vector2(-w, 0), start + Vector2(w, 0),
			start + Vector2(w * 0.8, length), start + Vector2(-w * 0.8, length)])
		out.append(part(drip, dcol))
		out.append(part(circle(start + Vector2(0, length), w * 1.05, 20), dcol))
	# Rings: the blob scaled down once per colour (a rainbow has 6 rings).
	for k in cols.size():
		var s := 1.0 - float(k) / cols.size() * 0.85
		var ring := PackedVector2Array()
		for p in shape:
			ring.append(c + (p - c) * s)
		out.append(part(ring, cols[k]))
	# Droplets flung around.
	for i in rng.randi_range(3, 7):
		var a := rng.randf_range(0, TAU)
		var d := r * rng.randf_range(1.2, 1.6)
		out.append(part(circle(c + Vector2(cos(a), sin(a)) * d, r * rng.randf_range(0.05, 0.11), 16),
			cols[rng.randi() % cols.size()]))
	return out


# ---------------------------------------------------------------- brush dab

## A soft round dab: white with alpha falloff (solid core, soft rim), tinted
## per colour when drawn.
static func dab_image(size := 128) -> Image:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := (size - 1) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x - c, y - c).length() / (size * 0.5)
			var a := 1.0 - smoothstep(0.78, 1.0, d)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return img
