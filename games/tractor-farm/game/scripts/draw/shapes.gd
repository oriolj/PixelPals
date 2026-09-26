extends RefCounted
## Flat-vector drawing helpers: soft shapes with a 2 px ink outline.
##
## Every function draws on the CanvasItem it is given, in that item's local
## space, from its _draw(). Point builders (ellipse, rrect, leaf, heart, star)
## return a PackedVector2Array for fill_ink(). Keep polygons simple (not
## self-intersecting) so Godot can triangulate them.
##
## Candidate for shared/godot/vector/shapes.gd once a second vector game
## exists (see the game's CLAUDE.md).

const INK := Color("#222034")
const W := 2.0

## The canvas transform set by xform(): drawings that place themselves with
## local() (crop icons, animals) compose onto it instead of replacing it.
static var base := Transform2D.IDENTITY
## Antialiased strokes. The AA feather is one LOCAL unit wide, so a drawing
## scaled up 5x (the giant vegetable) turns it into a blur: switch it off
## around big scaled drawings.
static var aa := true


## Set the canvas transform for the drawings that follow (use this, not
## draw_set_transform, around anything that draws crop icons).
static func xform(ci: CanvasItem, pos: Vector2, rot := 0.0, scl := Vector2.ONE) -> void:
	base = Transform2D(rot, scl, 0.0, pos)
	ci.draw_set_transform_matrix(base)


static func reset(ci: CanvasItem) -> void:
	base = Transform2D.IDENTITY
	ci.draw_set_transform_matrix(base)


## A nested transform on top of `base`; undo it with unlocal().
static func local(ci: CanvasItem, pos: Vector2, scl := Vector2.ONE) -> void:
	ci.draw_set_transform_matrix(base * Transform2D(0.0, scl, 0.0, pos))


static func unlocal(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(base)


static func ellipse(c: Vector2, rx: float, ry: float, rot := 0.0, n := 28) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var cr := cos(rot)
	var sr := sin(rot)
	for i in n:
		var a := TAU * i / n
		var p := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(c + Vector2(p.x * cr - p.y * sr, p.x * sr + p.y * cr))
	return pts


static func rrect(r: Rect2, rad: float, n := 5) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) * 0.45)
	var pts := PackedVector2Array()
	var corners := [
		[r.position + Vector2(r.size.x - rad, rad), -PI / 2],
		[r.end - Vector2(rad, rad), 0.0],
		[Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[r.position + Vector2(rad, rad), PI],
	]
	for cc in corners:
		for i in n + 1:
			var a: float = cc[1] + (PI / 2) * i / n
			pts.append(cc[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


## A pointed leaf from `base`, `length` long, pointing along `angle`.
static func leaf(base: Vector2, length: float, width: float, angle: float, n := 8) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var d := Vector2(cos(angle), sin(angle))
	var nrm := Vector2(-d.y, d.x)
	for i in n + 1:
		var t := float(i) / n
		pts.append(base + d * length * t + nrm * sin(t * PI) * width * 0.5)
	for i in range(n - 1, 0, -1):
		var t := float(i) / n
		pts.append(base + d * length * t - nrm * sin(t * PI) * width * 0.5)
	return pts


## A heart centred on `c`, `s` across.
static func heart(c: Vector2, s: float, n := 24) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var t := TAU * i / n
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * (s / 34.0))
	return pts


static func star(c: Vector2, r_out: float, r_in: float, points := 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


## Fill a polygon and outline it in ink.
static func fill_ink(ci: CanvasItem, pts: PackedVector2Array, fill: Color, ink := INK, w := W) -> void:
	ci.draw_colored_polygon(pts, fill)
	if w > 0.0:
		var closed := pts.duplicate()
		closed.append(pts[0])
		ci.draw_polyline(closed, ink, w, aa)


## A filled disc with an ink ring.
static func disc(ci: CanvasItem, c: Vector2, r: float, fill: Color, ink := INK, w := W) -> void:
	ci.draw_circle(c, r, fill, true, -1.0, aa)
	if w > 0.0:
		ci.draw_arc(c, r, 0.0, TAU, maxi(16, int(r * 1.5)), ink, w, aa)


static func oval(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, ink := INK, w := W, rot := 0.0) -> void:
	fill_ink(ci, ellipse(c, rx, ry, rot, maxi(20, int((rx + ry) * 0.8))), fill, ink, w)


static func box(ci: CanvasItem, r: Rect2, rad: float, fill: Color, ink := INK, w := W) -> void:
	fill_ink(ci, rrect(r, rad), fill, ink, w)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, col := INK, w := W) -> void:
	ci.draw_line(a, b, col, w, aa)


## A soft polyline through points (for stems, vines, smiles).
static func path(ci: CanvasItem, pts: PackedVector2Array, col := INK, w := W) -> void:
	ci.draw_polyline(pts, col, w, aa)


## Points on a quadratic curve a -> b bending through control point k.
static func curve(a: Vector2, k: Vector2, b: Vector2, n := 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var t := float(i) / n
		pts.append(a.lerp(k, t).lerp(k.lerp(b, t), t))
	return pts


## A smile arc under `c` (a friendly face mouth).
static func smile(ci: CanvasItem, c: Vector2, w: float, depth: float, col := INK, lw := W) -> void:
	path(ci, curve(c + Vector2(-w * 0.5, 0), c + Vector2(0, depth * 2.0), c + Vector2(w * 0.5, 0)), col, lw)


## Two eyes with a white glint.
static func eyes(ci: CanvasItem, c: Vector2, gap: float, r: float, closed := false) -> void:
	for sx in [-1.0, 1.0]:
		var e := c + Vector2(sx * gap * 0.5, 0)
		if closed:
			path(ci, curve(e + Vector2(-r, 0), e + Vector2(0, -r * 1.6), e + Vector2(r, 0), 6), INK, maxf(2.0, r * 0.6))
		else:
			ci.draw_circle(e, r, INK, true, -1.0, aa)
			ci.draw_circle(e + Vector2(-r * 0.3, -r * 0.35), r * 0.38, Color.WHITE, true, -1.0, aa)
