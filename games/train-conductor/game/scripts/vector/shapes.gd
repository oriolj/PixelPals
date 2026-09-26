extends RefCounted
## Vector shape helpers (proposed for shared/godot/vector/shapes.gd).
## Every function returns a PackedVector2Array polygon (clockwise on screen),
## and fill_outline() draws one with the toy-look 2 px ink outline.

const INK := Color("#2a2135")


static func circle(c: Vector2, r: float, n := 28) -> PackedVector2Array:
	return ellipse(c, r, r, n)


static func ellipse(c: Vector2, rx: float, ry: float, n := 28) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## Rounded rectangle; r is clamped to half the shorter side.
static func rounded_rect(rect: Rect2, r: float, per_corner := 5) -> PackedVector2Array:
	r = minf(r, minf(rect.size.x, rect.size.y) * 0.5)
	var out := PackedVector2Array()
	var p := rect.position
	var s := rect.size
	var centres := [p + Vector2(s.x - r, r), p + Vector2(s.x - r, s.y - r), p + Vector2(r, s.y - r), p + Vector2(r, r)]
	var start := [-PI / 2, 0.0, PI / 2, PI]
	for k in 4:
		for i in per_corner + 1:
			var a: float = start[k] + (PI / 2) * i / per_corner
			out.append(centres[k] + Vector2(cos(a), sin(a)) * r)
	return out


static func star(c: Vector2, r_out: float, r_in := -1.0, points := 5, rot := -PI / 2) -> PackedVector2Array:
	if r_in < 0.0:
		r_in = r_out * 0.48
	var out := PackedVector2Array()
	for i in points * 2:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * i / points
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


## Equilateral-ish triangle pointing up, fitting a circle of radius r.
static func triangle(c: Vector2, r: float) -> PackedVector2Array:
	return PackedVector2Array([c + Vector2(0, -r), c + Vector2(r * 0.95, r * 0.72), c + Vector2(-r * 0.95, r * 0.72)])


static func square(c: Vector2, r: float) -> PackedVector2Array:
	return rounded_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), r * 0.25, 3)


## The shape of a station colour (see Palette.SHAPES), fitting radius r.
static func token(kind: String, c: Vector2, r: float) -> PackedVector2Array:
	match kind:
		"square":
			return square(c, r)
		"triangle":
			return triangle(c + Vector2(0, r * 0.12), r * 1.08)
		"star":
			return star(c, r * 1.12, r * 0.52)
	return circle(c, r * 0.95, 24)


## A rotated/translated copy of a polygon.
static func xform(pts: PackedVector2Array, t: Transform2D) -> PackedVector2Array:
	return t * pts


## Fill a polygon and outline it (closed) in ink.
static func fill_outline(ci: CanvasItem, pts: PackedVector2Array, fill: Color, width := 2.0, ink := INK) -> void:
	if pts.size() < 3:
		return
	ci.draw_colored_polygon(pts, fill)
	if width > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, ink, width, true)


## Arrow polygon pointing +x, length len, shaft width w, head width hw.
static func arrow(len: float, w: float, hw: float) -> PackedVector2Array:
	var head := hw * 0.9
	return PackedVector2Array([
		Vector2(-len / 2, -w / 2), Vector2(len / 2 - head, -w / 2), Vector2(len / 2 - head, -hw / 2),
		Vector2(len / 2, 0), Vector2(len / 2 - head, hw / 2), Vector2(len / 2 - head, w / 2), Vector2(-len / 2, w / 2)])


## Offset an open polyline sideways by d (positive = right of travel on
## screen, y down). Used for rails, grooves and platform edges.
static func offset_polyline(pts: PackedVector2Array, d: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[maxi(i - 1, 0)]
		var b := pts[mini(i + 1, n - 1)]
		var t := (b - a).normalized()
		out.append(pts[i] + Vector2(-t.y, t.x) * d)
	return out


## True if any two non-adjacent segments of an open polyline cross.
static func self_intersects(pts: PackedVector2Array) -> bool:
	var n := pts.size()
	# Grid buckets keep this near-linear for long polylines.
	var cell := 64.0
	var buckets := {}
	for i in n - 1:
		var r := Rect2(pts[i], Vector2.ZERO).expand(pts[i + 1])
		for gx in range(int(floor(r.position.x / cell)), int(floor(r.end.x / cell)) + 1):
			for gy in range(int(floor(r.position.y / cell)), int(floor(r.end.y / cell)) + 1):
				var k := Vector2i(gx, gy)
				if not buckets.has(k):
					buckets[k] = []
				buckets[k].append(i)
	for k in buckets:
		var segs: Array = buckets[k]
		for x in segs.size():
			for y in range(x + 1, segs.size()):
				var i: int = segs[x]
				var j: int = segs[y]
				if absi(i - j) <= 1:
					continue
				if Geometry2D.segment_intersects_segment(pts[i], pts[i + 1], pts[j], pts[j + 1]) != null:
					return true
	return false
