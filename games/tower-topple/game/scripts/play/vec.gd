extends RefCounted
## Flat vector look: point lists for rounded shapes and outlined drawing.
##
## Everything in Tower Topple is drawn from these (no PNGs except the riders),
## so it stays crisp at any angle. Colours are the Sweetie 16 palette.
## This is the candidate for shared/godot/vector.gd (see CLAUDE.md).

const INK := Color("#1a1c2c")
const PLUM := Color("#5d275d")
const RED := Color("#b13e53")
const ORANGE := Color("#ef7d57")
const YELLOW := Color("#ffcd75")
const LIME := Color("#a7f070")
const GREEN := Color("#38b764")
const TEAL := Color("#257179")
const NAVY := Color("#29366f")
const BLUE := Color("#3b5dc9")
const SKY := Color("#41a6f6")
const CYAN := Color("#73eff7")
const WHITE := Color("#f4f4f4")
const GREY := Color("#94b0c2")
const SLATE := Color("#566c86")
const DUSK := Color("#333c57")
const OUTLINE_W := 3.0
const CONFETTI := [RED, ORANGE, YELLOW, LIME, GREEN, SKY, CYAN, WHITE]


## Axis-aligned rectangle centred on the origin.
static func rect(w: float, h: float) -> PackedVector2Array:
	return PackedVector2Array([Vector2(-w / 2, -h / 2), Vector2(w / 2, -h / 2),
		Vector2(w / 2, h / 2), Vector2(-w / 2, h / 2)])


## Regular n-gon of radius r centred on the origin (first point straight up).
static func ngon(r: float, n: int, phase := -PI / 2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := phase + TAU * i / n
		out.append(Vector2(cos(a), sin(a)) * r)
	return out


## Rounds every corner of a polygon with a quadratic curve of `seg` points.
## `radii` may be a float (all corners) or an Array (one radius per corner).
static func rounded(poly: PackedVector2Array, radii, seg := 4) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := poly.size()
	for i in n:
		var r: float = radii[i] if radii is Array else float(radii)
		var p := poly[i]
		if r <= 0.0:
			out.append(p)
			continue
		var prev := poly[(i - 1 + n) % n]
		var next := poly[(i + 1) % n]
		var a := p + (prev - p).normalized() * minf(r, prev.distance_to(p) * 0.45)
		var b := p + (next - p).normalized() * minf(r, next.distance_to(p) * 0.45)
		for k in seg + 1:
			var t := float(k) / seg
			out.append(a.lerp(p, t).lerp(p.lerp(b, t), t))
	return out


## Rounded rectangle centred on the origin (the plan's "8-point corners").
static func rounded_rect(w: float, h: float, r: float, seg := 4) -> PackedVector2Array:
	return rounded(rect(w, h), r, seg)


## A block with a half-circle cut out of its bottom edge (an arch / bridge).
static func arch(w: float, h: float, cut_r: float, seg := 16) -> PackedVector2Array:
	var pts := PackedVector2Array([Vector2(-w / 2, h / 2), Vector2(-w / 2, -h / 2),
		Vector2(w / 2, -h / 2), Vector2(w / 2, h / 2)])
	# The cut: from the right foot, over the top of the half circle, to the left foot.
	for i in seg + 1:
		var a := float(i) / seg * PI
		pts.append(Vector2(cos(a) * cut_r, h / 2 - sin(a) * cut_r))
	var radii := [2.0, 7.0, 7.0, 2.0]
	for i in seg + 1:
		radii.append(1.5 if i == 0 or i == seg else 0.0)
	return rounded(pts, radii, 3)


## Area (always positive) and centroid of a simple polygon.
static func area(poly: PackedVector2Array) -> float:
	var s := 0.0
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		s += a.x * b.y - b.x * a.y
	return absf(s) * 0.5


static func centroid(poly: PackedVector2Array) -> Vector2:
	var s := 0.0
	var c := Vector2.ZERO
	for i in poly.size():
		var a := poly[i]
		var b := poly[(i + 1) % poly.size()]
		var cr := a.x * b.y - b.x * a.y
		s += cr
		c += (a + b) * cr
	if absf(s) < 1e-6:
		return Vector2.ZERO
	return c / (3.0 * s)


static func translated(poly: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + by)
	return out


static func scaled(poly: PackedVector2Array, s: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in poly:
		out.append(p * s)
	return out


static func closed(poly: PackedVector2Array) -> PackedVector2Array:
	var out := poly.duplicate()
	if poly.size() > 0:
		out.append(poly[0])
	return out


## Fill plus a thick ink outline (the house look).
static func draw_shape(ci: CanvasItem, poly: PackedVector2Array, fill: Color, outline := INK,
		width := OUTLINE_W) -> void:
	ci.draw_colored_polygon(poly, fill)
	if width > 0.0:
		ci.draw_polyline(closed(poly), outline, width, true)


## Shape with a soft bevel: darker rim, lighter inset face.
static func draw_bevel(ci: CanvasItem, poly: PackedVector2Array, fill: Color, inset := 4.0) -> void:
	ci.draw_colored_polygon(poly, fill.darkened(0.18))
	var inner := Geometry2D.offset_polygon(poly, -inset, Geometry2D.JOIN_ROUND)
	for part in inner:
		ci.draw_colored_polygon(translated(part, Vector2(-1, -1)), fill)
		# A small shine near the top-left.
	ci.draw_polyline(closed(poly), INK, OUTLINE_W, true)


## Outlined circle.
static func draw_disc(ci: CanvasItem, at: Vector2, r: float, fill: Color, outline := INK,
		width := OUTLINE_W) -> void:
	ci.draw_circle(at, r + width * 0.5, outline, true, -1.0, true)
	ci.draw_circle(at, r - width * 0.5, fill, true, -1.0, true)


## A fluffy cloud: overlapping discs with one shared outline.
static func draw_cloud(ci: CanvasItem, at: Vector2, s: float, fill := WHITE, outline := INK,
		width := 3.0) -> void:
	var lobes := [Vector2(-22, 4), Vector2(-8, -8), Vector2(10, -10), Vector2(24, 2), Vector2(0, 6)]
	var radii := [12.0, 15.0, 16.0, 12.0, 14.0]
	if width > 0.0:
		for i in lobes.size():
			ci.draw_circle(at + lobes[i] * s, radii[i] * s + width, outline, true, -1.0, true)
	for i in lobes.size():
		ci.draw_circle(at + lobes[i] * s, radii[i] * s, fill, true, -1.0, true)
	ci.draw_circle(at + Vector2(-6, -10) * s, 5.0 * s, Color(1, 1, 1, 0.8), true, -1.0, true)


## Five-point star centred on `at`.
static func star(r: float, at := Vector2.ZERO, inner := 0.45) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 10:
		var a := -PI / 2 + PI * i / 5.0
		var rr := r if i % 2 == 0 else r * inner
		out.append(at + Vector2(cos(a), sin(a)) * rr)
	return out
