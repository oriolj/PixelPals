extends RefCounted
## Flat vector primitives: outlined polygons (a Polygon2D fill plus a closed,
## round-jointed Line2D outline), circles, rounded rectangles, Catmull-Rom
## blobs, strokes, eyes and leaves. Every asset in the game is built from these
## as a Node2D tree, so poses animate by moving parts.
##
## Usage: const VA := preload("res://scripts/vector/vector_art.gd")
##        var head := VA.shape(parent, VA.circle(40), Pal.MONKEY)

const Pal := preload("res://scripts/vector/palette.gd")
const OUTLINE_W := 5.0


# ---------------------------------------------------------------- point lists

static func circle(r: float, c := Vector2.ZERO, n := 32) -> PackedVector2Array:
	return ellipse(r, r, c, n)


static func ellipse(rx: float, ry: float, c := Vector2.ZERO, n := 32) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## An arc of an ellipse from angle a0 to a1 (radians), inclusive.
static func arc(rx: float, ry: float, a0: float, a1: float, c := Vector2.ZERO, n := 16) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


static func rrect(r: Rect2, radius: float, seg := 6) -> PackedVector2Array:
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var out := PackedVector2Array()
	var corners := [
		[r.position + Vector2(r.size.x - radius, radius), -PI / 2],
		[r.end - Vector2(radius, radius), 0.0],
		[r.position + Vector2(radius, r.size.y - radius), PI / 2],
		[r.position + Vector2(radius, radius), PI],
	]
	for c in corners:
		for i in seg + 1:
			var a: float = c[1] + (PI / 2) * i / seg
			out.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	return out


## Closed Catmull-Rom spline through the control points.
static func blob(ctrl: Array, per_seg := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in n:
		var p0: Vector2 = ctrl[(i - 1 + n) % n]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[(i + 1) % n]
		var p3: Vector2 = ctrl[(i + 2) % n]
		for k in per_seg:
			out.append(_catmull(p0, p1, p2, p3, float(k) / per_seg))
	return out


## Open Catmull-Rom curve through the points (ends included).
static func curve(ctrl: Array, per_seg := 8) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := ctrl.size()
	for i in n - 1:
		var p0: Vector2 = ctrl[maxi(i - 1, 0)]
		var p1: Vector2 = ctrl[i]
		var p2: Vector2 = ctrl[i + 1]
		var p3: Vector2 = ctrl[mini(i + 2, n - 1)]
		for k in per_seg:
			out.append(_catmull(p0, p1, p2, p3, float(k) / per_seg))
	out.append(ctrl[n - 1])
	return out


static func _catmull(p0: Vector2, p1: Vector2, p2: Vector2, p3: Vector2, t: float) -> Vector2:
	var t2 := t * t
	var t3 := t2 * t
	return 0.5 * ((2.0 * p1) + (-p0 + p2) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


static func star_pts(r_out: float, r_in: float, points := 5, c := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in points * 2:
		var a := -PI / 2 + PI * i / points
		var r := r_out if i % 2 == 0 else r_in
		out.append(c + Vector2(cos(a), sin(a)) * r)
	return out


static func heart_pts(s: float, c := Vector2.ZERO) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40.0
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		out.append(c + Vector2(x, y) * s / 16.0)
	return out


static func offset(pts: PackedVector2Array, by: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	for p in pts:
		out.append(p + by)
	return out


static func mirror_x(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(pts.size() - 1, -1, -1):
		out.append(Vector2(-pts[i].x, pts[i].y))
	return out


# ---------------------------------------------------------------- nodes

## An empty pivot node, named so poses can find it.
static func part(parent: Node, part_name: String, pos := Vector2.ZERO) -> Node2D:
	var n := Node2D.new()
	n.name = part_name
	n.position = pos
	parent.add_child(n)
	return n


## An outlined filled shape. Returns the Polygon2D (its outline is a child).
static func shape(parent: Node, pts: PackedVector2Array, fill: Color, outline := Pal.OUTLINE,
		width := OUTLINE_W, shape_name := "") -> Polygon2D:
	var poly := Polygon2D.new()
	poly.polygon = pts
	poly.color = fill
	poly.antialiased = true
	if shape_name != "":
		poly.name = shape_name
	parent.add_child(poly)
	if width > 0.0:
		var line := Line2D.new()
		line.points = pts
		line.closed = true
		line.width = width
		line.default_color = outline
		line.joint_mode = Line2D.LINE_JOINT_ROUND
		line.begin_cap_mode = Line2D.LINE_CAP_ROUND
		line.end_cap_mode = Line2D.LINE_CAP_ROUND
		line.antialiased = true
		poly.add_child(line)
	return poly


## A filled shape with no outline (spots, highlights, shadows).
static func fill(parent: Node, pts: PackedVector2Array, color: Color, shape_name := "") -> Polygon2D:
	return shape(parent, pts, color, Pal.OUTLINE, 0.0, shape_name)


## A plain stroke (whiskers, mouths, hay strands).
static func stroke(parent: Node, pts: PackedVector2Array, color: Color, width: float, shape_name := "") -> Line2D:
	var line := Line2D.new()
	line.points = pts
	line.width = width
	line.default_color = color
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	if shape_name != "":
		line.name = shape_name
	parent.add_child(line)
	return line


## A thick outlined stroke (tails, trunks, necks): the outline is a wider
## dark line under the coloured one. Returns the holder node.
static func limb(parent: Node, pts: PackedVector2Array, color: Color, width: float, limb_name := "") -> Node2D:
	var holder := Node2D.new()
	if limb_name != "":
		holder.name = limb_name
	parent.add_child(holder)
	stroke(holder, pts, Pal.OUTLINE, width + OUTLINE_W * 2.0)
	stroke(holder, pts, color, width)
	return holder


## A cartoon eye: dark oval, a white glint. The "pupil" child can be moved to look.
static func eye(parent: Node, pos: Vector2, r: float, eye_name := "eye") -> Node2D:
	var e := part(parent, eye_name, pos)
	var pupil := part(e, "pupil")
	fill(pupil, ellipse(r * 0.9, r * 1.1), Pal.OUTLINE)
	fill(pupil, circle(r * 0.38, Vector2(r * 0.28, -r * 0.4), 12), Color.WHITE)
	fill(pupil, circle(r * 0.16, Vector2(-r * 0.3, r * 0.4), 8), Color(1, 1, 1, 0.8))
	return e


static func leaf(parent: Node, pos: Vector2, length: float, angle: float, color := Pal.LEAF) -> Polygon2D:
	var pts := PackedVector2Array()
	for i in 13:
		var t := float(i) / 12.0
		pts.append(Vector2(t * length, -sin(t * PI) * length * 0.32))
	for i in range(11, 0, -1):
		var t := float(i) / 12.0
		pts.append(Vector2(t * length, sin(t * PI) * length * 0.32))
	var p := shape(parent, pts, color, Pal.OUTLINE, 3.0)
	p.position = pos
	p.rotation = angle
	return p


## The soft ground shadow (the only non-flat element): three stacked ellipses.
static func shadow(parent: Node, rx: float, ry: float, c := Vector2.ZERO) -> Node2D:
	var s := part(parent, "shadow", c)
	for i in 3:
		var k := 1.0 - i * 0.18
		fill(s, ellipse(rx * k, ry * k), Color(Pal.SHADOW, 0.1 + 0.06 * i))
	return s


## Finds a named part anywhere under node (null if absent).
static func find(node: Node, part_name: String) -> Node2D:
	return node.find_child(part_name, true, false) as Node2D
