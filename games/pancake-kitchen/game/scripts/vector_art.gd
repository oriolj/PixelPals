extends RefCounted
## Flat vector art for Pancake Kitchen, drawn in code (no image files).
##
## Every function draws onto a CanvasItem `ci` from its `_draw()`. Shapes are
## round, filled, and get a thick dark outline drawn last as an antialiased
## polyline (which also hides the polygon fill's jagged edge). Functions that
## take `xf: Transform2D` draw in local coordinates (origin and size noted per
## function) and reset the canvas transform when done.

const Pal := preload("res://scripts/kitchen/palette.gd")
const OUT := Pal.OUTLINE
const W := 5.0   ## outline width at scale 1


# =================================================================== basics

static func ellipse_pts(c: Vector2, rx: float, ry: float, n := 36, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	ry = maxf(ry, 0.8)
	rx = maxf(rx, 0.8)
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * rx, sin(a) * ry).rotated(rot))
	return pts


static func closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	out.append(pts[0])
	return out


## Filled polygon with the house outline.
static func shape(ci: CanvasItem, pts: PackedVector2Array, fill: Color, w := W, line := OUT) -> void:
	ci.draw_colored_polygon(pts, fill)
	if w > 0.0:
		ci.draw_polyline(closed(pts), line, w, true)


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, fill: Color, w := W, rot := 0.0) -> void:
	shape(ci, ellipse_pts(c, rx, ry, 40, rot), fill, w)


static func circle(ci: CanvasItem, c: Vector2, r: float, fill: Color, w := W) -> void:
	if w > 0.0:
		ci.draw_circle(c, r + w * 0.5, OUT, true, -1.0, true)
	ci.draw_circle(c, maxf(r - w * 0.5, 0.5), fill, true, -1.0, true)


static func dot(ci: CanvasItem, c: Vector2, r: float, fill: Color) -> void:
	ci.draw_circle(c, r, fill, true, -1.0, true)


static func rrect_pts(r: Rect2, radius: float, n := 6) -> PackedVector2Array:
	var pts := PackedVector2Array()
	radius = minf(radius, minf(r.size.x, r.size.y) * 0.5)
	var corners := [
		[r.position + Vector2(r.size.x - radius, radius), -PI / 2],
		[r.position + r.size - Vector2(radius, radius), 0.0],
		[r.position + Vector2(radius, r.size.y - radius), PI / 2],
		[r.position + Vector2(radius, radius), PI],
	]
	for c in corners:
		for i in n + 1:
			var a: float = c[1] + (PI / 2) * i / n
			pts.append(c[0] + Vector2(cos(a), sin(a)) * radius)
	return pts


static func rrect(ci: CanvasItem, r: Rect2, radius: float, fill: Color, w := W) -> void:
	shape(ci, rrect_pts(r, radius), fill, w)


static func arc(ci: CanvasItem, c: Vector2, r: float, a0: float, a1: float, w := W, col := OUT) -> void:
	ci.draw_arc(c, r, a0, a1, 18, col, w, true)


static func line(ci: CanvasItem, a: Vector2, b: Vector2, w := W, col := OUT) -> void:
	ci.draw_line(a, b, col, w, true)


static func star_pts(c: Vector2, r_out: float, r_in: float, points := 5, rot := -PI / 2) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var r := r_out if i % 2 == 0 else r_in
		var a := rot + PI * i / points
		pts.append(c + Vector2(cos(a), sin(a)) * r)
	return pts


static func star(ci: CanvasItem, c: Vector2, r: float, fill := Color("#ffd23f"), rot := 0.0, w := 4.0) -> void:
	shape(ci, star_pts(c, r, r * 0.48, 5, -PI / 2 + rot), fill, w, Color(OUT, fill.a))


## Four-point twinkle (no outline: it is light).
static func sparkle(ci: CanvasItem, c: Vector2, r: float, fill: Color, rot := 0.0) -> void:
	ci.draw_colored_polygon(star_pts(c, r, r * 0.28, 4, rot), fill)
	dot(ci, c, r * 0.22, Color.WHITE)


static func heart_pts(c: Vector2, r: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var t := TAU * i / 40
		var x := 16.0 * pow(sin(t), 3)
		var y := -(13.0 * cos(t) - 5.0 * cos(2 * t) - 2.0 * cos(3 * t) - cos(4 * t))
		pts.append(c + Vector2(x, y) * r / 16.0)
	return pts


static func heart(ci: CanvasItem, c: Vector2, r: float, fill := Pal.STRAWBERRY, w := 4.0) -> void:
	shape(ci, heart_pts(c, r), fill, w, Color(OUT, fill.a))
	dot(ci, c + Vector2(-r * 0.4, -r * 0.35), r * 0.18, Color(1, 1, 1, 0.8 * fill.a))


## Transforms compose: push() a transform, draw any art (whose own with_xf
## calls are relative to it), then pop(). Always pop what you push.
static var base := Transform2D.IDENTITY
static var _saved: Array[Transform2D] = []


static func push(ci: CanvasItem, xf: Transform2D) -> void:
	_saved.append(base)
	base = base * xf
	ci.draw_set_transform_matrix(base)


static func pop(ci: CanvasItem) -> void:
	base = _saved.pop_back() if not _saved.is_empty() else Transform2D.IDENTITY
	ci.draw_set_transform_matrix(base)


static func with_xf(ci: CanvasItem, xf: Transform2D) -> void:
	ci.draw_set_transform_matrix(base * xf)


static func reset(ci: CanvasItem) -> void:
	ci.draw_set_transform_matrix(base)


# =================================================================== pancake

## A pancake centred at `c`: a 160x36 disc with thickness. `face` is the cook
## of the face on top, `under` of the face underneath. `yscale` is cos(spin):
## it thins through 0 as it flips and shows the other face when negative.
## `squash` (0..1) flattens it after a landing. `bubbles` (0..1) pops little
## holes on a pale face while the underside cooks. `spread` grows the batter.
static func pancake(ci: CanvasItem, c: Vector2, face: float, under: float, yscale := 1.0,
		squash := 0.0, bubbles := 0.0, spread := 1.0, seed_value := 0, rot := 0.0) -> void:
	var showing := face if yscale >= 0.0 else under
	var ys := maxf(absf(yscale), 0.1)
	var sx := (1.0 + 0.22 * squash) * spread
	var sy := (1.0 - 0.3 * squash) * spread
	var a := 80.0 * sx
	var b := 18.0 * sy * ys
	var thick := 11.0 * sy * lerpf(1.0, 0.55, 1.0 - ys) if spread > 0.3 else 3.0
	var col := Pal.cook_color(showing)
	var edge := Pal.cook_color(maxf(face, under)).darkened(0.18)
	if spread < 0.05:
		return
	var xf := Transform2D(rot, c)
	with_xf(ci, xf)
	# Underside band (the thickness), then the top face.
	var band := PackedVector2Array()
	for i in 21:
		var t := PI * i / 20.0
		band.append(Vector2(cos(t) * a, sin(t) * b + thick))
	for i in 21:
		var t := PI - PI * i / 20.0
		band.append(Vector2(cos(t) * a, sin(t) * b))
	ci.draw_colored_polygon(band, edge)
	var top := ellipse_pts(Vector2.ZERO, a, b, 44)
	ci.draw_colored_polygon(top, col)
	# Cooked faces get a darker golden ring and a shine.
	if showing > 0.35:
		var ring := Pal.GOLDEN_EDGE
		ring.a = clampf((showing - 0.35) * 1.3, 0.0, 0.8)
		ci.draw_polyline(closed(ellipse_pts(Vector2.ZERO, a * 0.82, b * 0.72, 40)), ring, 4.0 * ys + 1.0, true)
	ci.draw_colored_polygon(ellipse_pts(Vector2(-a * 0.35, -b * 0.3), a * 0.28, b * 0.22, 20),
		Color(1, 1, 1, 0.35))
	# Bubbles on a pale face.
	if bubbles > 0.02 and yscale > 0.5:
		var r := RandomNumberGenerator.new()
		r.seed = 1234 + seed_value
		var n := int(bubbles * 9.0)
		for i in n:
			var bx := r.randf_range(-0.7, 0.7) * a
			var by := r.randf_range(-0.5, 0.5) * b
			var br := r.randf_range(3.0, 6.0) * ys
			ci.draw_circle(Vector2(bx, by), br, Pal.GOLDEN.lerp(Pal.BATTER, 0.4), true, -1.0, true)
			ci.draw_circle(Vector2(bx - br * 0.3, by - br * 0.3), br * 0.35, Color(1, 1, 1, 0.7), true, -1.0, true)
	# Outline: the whole silhouette (top ellipse + band).
	var sil := PackedVector2Array()
	for i in 23:
		var t := PI + PI * i / 22.0
		sil.append(Vector2(cos(t) * a, sin(t) * b))
	for i in 23:
		var t := PI * i / 22.0
		sil.append(Vector2(cos(-t) * a, -sin(-t) * b + thick))
	ci.draw_polyline(closed(sil), OUT, 4.5, true)
	reset(ci)


# =================================================================== toppings

## One topping centred at `c`, about 24-48 px. `s` scales it.
static func topping(ci: CanvasItem, kind: String, c: Vector2, rot := 0.0, s := 1.0) -> void:
	with_xf(ci, Transform2D(rot, Vector2(s, s), 0.0, c))
	match kind:
		"strawberry":
			# A strawberry slice: heart-ish red with a pale inside and seeds.
			var pts := PackedVector2Array()
			for i in 30:
				var t := TAU * i / 30
				var r := 1.0 - 0.28 * pow(maxf(0.0, cos(t - PI / 2)), 4)
				pts.append(Vector2(cos(t) * 17 * r, sin(t) * 19 * r + (sin(t) * 3.0)))
			shape(ci, pts, Pal.STRAWBERRY, 3.5)
			ci.draw_colored_polygon(ellipse_pts(Vector2(0, 1), 9, 11, 20), Color("#ff8a9b"))
			for p in [Vector2(-9, -5), Vector2(8, -6), Vector2(-5, 10), Vector2(6, 9), Vector2(0, -12), Vector2(11, 3), Vector2(-12, 3)]:
				ci.draw_colored_polygon(ellipse_pts(p, 1.6, 2.6, 8), Color("#ffe6a0"))
			var leaf := PackedVector2Array([Vector2(-9, -18), Vector2(0, -13), Vector2(9, -18), Vector2(4, -23), Vector2(0, -19), Vector2(-4, -23)])
			shape(ci, leaf, Pal.LEAF, 3.0)
		"chocolate":
			# A chocolate chip: a little kiss drop.
			var pts := PackedVector2Array()
			for i in 26:
				var t := TAU * i / 26
				var x := cos(t) * 13.0
				var y := sin(t) * 9.0
				if y < 0.0:
					x *= 1.0 + y / 14.0
					y *= 1.9
				pts.append(Vector2(x, y + 3))
			shape(ci, pts, Pal.CHOCOLATE, 3.5)
			ci.draw_colored_polygon(ellipse_pts(Vector2(-4, -2), 3, 5, 10, 0.4), Color(1, 1, 1, 0.35))
		"banana":
			circle(ci, Vector2.ZERO, 17, Pal.BANANA, 3.5)
			ci.draw_arc(Vector2.ZERO, 11, 0, TAU, 24, Color("#f3cf45"), 3.0, true)
			for i in 6:
				var a := TAU * i / 6 + 0.3
				dot(ci, Vector2(cos(a), sin(a)) * 5.5, 1.6, Color("#8a6a3a"))
		"cream":
			# A dollop: overlapping circles along a spiral, rising to a peak.
			var blobs := [[Vector2(-14, 6), 11.0], [Vector2(14, 6), 11.0], [Vector2(0, 8), 12.0],
				[Vector2(-7, -4), 10.0], [Vector2(8, -4), 10.0], [Vector2(0, -13), 8.0], [Vector2(2, -21), 5.0]]
			for bl in blobs:
				ci.draw_circle(bl[0], bl[1] + 3.0, OUT, true, -1.0, true)
			for bl in blobs:
				ci.draw_circle(bl[0], bl[1], Pal.CREAM, true, -1.0, true)
			ci.draw_arc(Vector2(0, 2), 9, 0.3, PI - 0.3, 10, Color("#e4e8f2"), 2.5, true)
			ci.draw_arc(Vector2(0, -8), 6, 0.3, PI - 0.3, 10, Color("#e4e8f2"), 2.5, true)
			dot(ci, Vector2(-6, -8), 2.5, Color(1, 1, 1))
	reset(ci)


## A jar of toppings, 80 px tall, centred at `c`. `selected` rings it in the
## topper's colour; `bump` (0..1) wobbles it after a drop.
static func jar(ci: CanvasItem, kind: String, c: Vector2, selected: bool, ring: Color, bump := 0.0, t := 0.0) -> void:
	var s := 1.0 + 0.12 * bump
	if selected:
		var glow := ring
		glow.a = 0.35 + 0.15 * sin(t * 6.0)
		ci.draw_circle(c, 56 * s, glow, true, -1.0, true)
		ci.draw_arc(c, 52 * s, 0, TAU, 48, ring, 7.0, true)
	with_xf(ci, Transform2D(sin(t * 20.0) * 0.12 * bump, Vector2(s, s), 0.0, c))
	var body := Rect2(-28, -24, 56, 58)
	rrect(ci, body, 16, Color(0.9, 0.97, 1.0, 0.95), 4.5)
	# The contents behind the glass.
	var tint: Color = Pal.TOPPING_COLORS[kind]
	var fill := tint if kind != "cream" else Color("#f3f5fb")
	ci.draw_colored_polygon(rrect_pts(Rect2(-23, -6, 46, 36), 12), fill.lerp(Color.WHITE, 0.15))
	push(ci, Transform2D(sin(t * 20.0) * 0.12 * bump, Vector2(s, s), 0.0, c))
	for i in 3:
		topping(ci, kind, Vector2(-12 + i * 12, 10 + (i % 2) * 6), 0.3 * i, 0.5)
	pop(ci)
	with_xf(ci, Transform2D(sin(t * 20.0) * 0.12 * bump, Vector2(s, s), 0.0, c))
	ci.draw_colored_polygon(rrect_pts(Rect2(-22, -18, 7, 40), 3), Color(1, 1, 1, 0.55))
	# Lid in the topping's colour.
	var lid_col := tint if kind != "cream" else Color("#8fd3ff")
	rrect(ci, Rect2(-31, -38, 62, 18), 7, lid_col, 4.5)
	ci.draw_line(Vector2(-22, -33), Vector2(18, -33), Color(1, 1, 1, 0.45), 3.0, true)
	reset(ci)


# =================================================================== kitchen

## The pan: a 200x50 dish whose rim is at `c` (the pancake rests just above
## it), with the handle to the left in the cook's colour.
static func pan(ci: CanvasItem, c: Vector2, handle: Color, tilt := 0.0) -> void:
	with_xf(ci, Transform2D(tilt, c))
	# Handle.
	rrect(ci, Rect2(-190, -8, 96, 18), 9, Pal.PAN, 4.5)
	rrect(ci, Rect2(-196, -12, 64, 26), 12, handle, 4.5)
	ci.draw_line(Vector2(-186, -5), Vector2(-146, -5), Color(1, 1, 1, 0.45), 4.0, true)
	# Dish.
	var dish := PackedVector2Array([Vector2(-104, 0), Vector2(104, 0), Vector2(86, 32), Vector2(-86, 32)])
	var round_dish := PackedVector2Array()
	for p in dish:
		round_dish.append(p)
	shape(ci, rrect_pts(Rect2(-102, -4, 204, 38), 16), Pal.PAN, 5.0)
	ci.draw_line(Vector2(-82, 6), Vector2(40, 6), Pal.PAN_SHINE, 5.0, true)
	shape(ci, ellipse_pts(Vector2(0, -4), 102, 10, 36), Pal.PAN_SHINE.darkened(0.2), 5.0)
	reset(ci)


## The stove from x0 to x1 with its top at y: a long hob with knobs and a flame
## under the pan.
static func stove(ci: CanvasItem, x0: float, x1: float, y: float, bottom: float, flame_x: float, t: float) -> void:
	rrect(ci, Rect2(x0, y, x1 - x0, bottom - y), 14, Pal.STOVE, 5.0)
	ci.draw_rect(Rect2(x0 + 14, y + 12, x1 - x0 - 28, 8), Pal.STOVE_DARK)
	# Oven door window.
	rrect(ci, Rect2(x0 + 50, y + 60, x1 - x0 - 100, bottom - y - 90), 16, Color("#2e3140"), 5.0)
	ci.draw_colored_polygon(rrect_pts(Rect2(x0 + 66, y + 74, 90, 14), 7), Color(1, 1, 1, 0.18))
	ci.draw_colored_polygon(rrect_pts(Rect2(x0 + 70, bottom - 64, x1 - x0 - 140, 20), 10), Color("#ffb347").darkened(0.2))
	# Knobs.
	for i in 4:
		var kx := x0 + 60 + i * (x1 - x0 - 120) / 3.0
		circle(ci, Vector2(kx, y + 38), 11, Color("#ff7a59"), 4.0)
		ci.draw_line(Vector2(kx, y + 38), Vector2(kx, y + 30), OUT, 3.5, true)
	# Flame under the pan (it follows the pan).
	for i in 5:
		var fx := flame_x - 60 + i * 30
		var h := 14.0 + 5.0 * sin(t * 13.0 + i * 1.7)
		var pts := PackedVector2Array([Vector2(fx - 9, y), Vector2(fx, y - h), Vector2(fx + 9, y)])
		ci.draw_colored_polygon(pts, Pal.FLAME)
		var inner := PackedVector2Array([Vector2(fx - 4, y), Vector2(fx, y - h * 0.5), Vector2(fx + 4, y)])
		ci.draw_colored_polygon(inner, Color("#dff3ff"))


## Plate at `c` (its centre, 180 px wide). `glow` pulses when it is ready.
static func plate(ci: CanvasItem, c: Vector2, glow := 0.0, t := 0.0) -> void:
	if glow > 0.0:
		var g := Pal.GLOW
		g.a = glow * (0.45 + 0.2 * sin(t * 7.0))
		ci.draw_colored_polygon(ellipse_pts(c + Vector2(0, -30), 150, 90, 40), g)
		for i in 6:
			var a := t * 1.5 + TAU * i / 6.0
			sparkle(ci, c + Vector2(cos(a) * 130, -40 + sin(a) * 70), 10 + 3 * sin(t * 5 + i), Color(1, 0.95, 0.5, glow))
	shape(ci, ellipse_pts(c + Vector2(0, 6), 92, 18, 40), Pal.PLATE_RIM, 5.0)
	ci.draw_colored_polygon(ellipse_pts(c + Vector2(0, 2), 84, 14, 40), Pal.PLATE)
	ci.draw_colored_polygon(ellipse_pts(c + Vector2(0, 3), 56, 8, 30), Color("#eef6fc"))


## A plate with a stack of `n` pancakes and its toppings (the rules' layout:
## pancake i is centred at base + (0, -16 - i * 24); toppings have "level",
## "pos", "lift", "rot"), scaled by `s`.
static func stack(ci: CanvasItem, base_pos: Vector2, n: int, tops: Array, glow := 0.0, t := 0.0, s := 1.0) -> void:
	push(ci, Transform2D(0.0, Vector2(s, s), 0.0, base_pos))
	plate(ci, Vector2.ZERO, glow, t)
	_level_toppings(ci, tops, -1)
	for i in n:
		_pancake_local(ci, Vector2(0, -16 - i * 24.0))
		_level_toppings(ci, tops, i)
	pop(ci)


static func _pancake_local(ci: CanvasItem, c: Vector2) -> void:
	# The same look as pancake() but in the current canvas transform (no reset).
	var a := 80.0
	var b := 18.0
	var band := PackedVector2Array()
	for i in 21:
		var t := PI * i / 20.0
		band.append(c + Vector2(cos(t) * a, sin(t) * b + 11))
	for i in 21:
		var t := PI - PI * i / 20.0
		band.append(c + Vector2(cos(t) * a, sin(t) * b))
	ci.draw_colored_polygon(band, Pal.GOLDEN.darkened(0.18))
	ci.draw_colored_polygon(ellipse_pts(c, a, b, 44), Pal.GOLDEN)
	ci.draw_polyline(closed(ellipse_pts(c, a * 0.82, b * 0.72, 40)), Color(Pal.GOLDEN_EDGE, 0.8), 5.0, true)
	ci.draw_colored_polygon(ellipse_pts(c + Vector2(-28, -5), 22, 4, 20), Color(1, 1, 1, 0.35))
	var sil := PackedVector2Array()
	for i in 23:
		var t := PI + PI * i / 22.0
		sil.append(c + Vector2(cos(t) * a, sin(t) * b))
	for i in 23:
		var t := PI * i / 22.0
		sil.append(c + Vector2(cos(-t) * a, -sin(-t) * b + 11))
	ci.draw_polyline(closed(sil), OUT, 4.5, true)


static func _level_toppings(ci: CanvasItem, tops: Array, level: int) -> void:
	for tp in tops:
		if int(tp.level) != level:
			continue
		var center := Vector2(0, -6) if level < 0 else Vector2(0, -16 - level * 24.0)
		var p: Vector2 = center + tp.pos + Vector2(0, -float(tp.get("lift", 0.0)))
		var age: float = tp.get("age", 1.0)
		var pop_s := 1.0 + 0.35 * maxf(0.0, 1.0 - age / 0.2)
		topping(ci, tp.kind, p, tp.rot, pop_s)


# =================================================================== creatures

const CREATURES := {
	"bear": {"body": Color("#b77a4b"), "belly": Color("#ecc9a0"), "ears": "round", "muzzle": Color("#ecc9a0")},
	"cat": {"body": Color("#f7a34b"), "belly": Color("#fff0d9"), "ears": "cat", "muzzle": Color("#fff0d9"), "stripes": true},
	"penguin": {"body": Color("#35456b"), "belly": Color("#ffffff"), "ears": "none", "beak": true},
	"frog": {"body": Color("#7ccf5a"), "belly": Color("#d7f5a0"), "ears": "frog"},
	"robot": {"body": Color("#b8c4d6"), "belly": Color("#8fd3ff"), "ears": "robot"},
	"bunny": {"body": Color("#f6efe9"), "belly": Color("#ffffff"), "ears": "bunny", "muzzle": Color("#ffffff")},
	"pig": {"body": Color("#ffb3c6"), "belly": Color("#ffd3de"), "ears": "pig", "snout": true},
	"mouse": {"body": Color("#b7b3c9"), "belly": Color("#e9e6f2"), "ears": "mouse", "muzzle": Color("#e9e6f2")},
	"fox": {"body": Color("#f08a3c"), "belly": Color("#fff4e6"), "ears": "fox", "muzzle": Color("#fff4e6")},
	"duck": {"body": Color("#ffd84d"), "belly": Color("#fff2a8"), "ears": "tuft", "bill": true},
}


## A creature standing on `xf.origin` (feet), about 230 px tall at scale 1.
## o: look (Vector2), mouth ("smile" | "open" | "chew" | "grin" | "o"),
##    eyes ("open" | "happy" | "wide"), arms (0 down .. 1 up), hat (Color,
##    omit for none), blush (bool), holding (Color: a paw raised holding it),
##    squish (0..1 hop squash).
static func creature(ci: CanvasItem, xf: Transform2D, kind: String, o := {}) -> void:
	var spec: Dictionary = CREATURES.get(kind, CREATURES.bear)
	var body: Color = spec.body
	var belly: Color = spec.belly
	var look: Vector2 = o.get("look", Vector2.ZERO)
	var arms: float = o.get("arms", 0.0)
	var squish: float = o.get("squish", 0.0)
	var local := xf * Transform2D(0.0, Vector2(1.0 + 0.12 * squish, 1.0 - 0.12 * squish), 0.0, Vector2.ZERO)
	with_xf(ci, local)
	var hc := Vector2(look.x * 4.0, -168)
	var robot := kind == "robot"
	# Feet.
	var feet_col := Color("#ff9f43") if kind in ["penguin", "duck"] else body.darkened(0.12)
	ellipse(ci, Vector2(-30, -6), 26, 13, feet_col)
	ellipse(ci, Vector2(30, -6), 26, 13, feet_col)
	# Arms behind the body when down; drawn after it when raised.
	var arm_l := Vector2(-58, -108)
	var arm_r := Vector2(58, -108)
	var up := arms > 0.5
	if not up:
		_arm(ci, arm_l, arms, -1, body, robot)
		_arm(ci, arm_r, arms, 1, body, robot)
	# Body.
	if robot:
		rrect(ci, Rect2(-60, -140, 120, 132), 26, body)
		rrect(ci, Rect2(-36, -112, 72, 56), 12, Color("#e7eef8"), 4.0)
		for i in 3:
			circle(ci, Vector2(-18 + i * 18, -84), 7, [Color("#ff6b6b"), Color("#ffd23f"), Color("#6cc36c")][i], 3.0)
	else:
		shape(ci, _egg(Vector2(0, -74), 64, 76), body)
		ci.draw_colored_polygon(ellipse_pts(Vector2(0, -62), 40, 50, 30), belly)
	if up:
		_arm(ci, arm_l, arms, -1, body, robot)
		_arm(ci, arm_r, arms, 1, body, robot)
	if o.has("holding"):
		_holding(ci, arm_r + Vector2(10, -30), o.holding, body)
	# Ears behind the head.
	_ears(ci, hc, spec.ears, body, true)
	# Head.
	if robot:
		ci.draw_line(hc + Vector2(0, -60), hc + Vector2(0, -88), OUT, 5.0, true)
		circle(ci, hc + Vector2(0, -92), 11, Color("#ff6b6b"), 4.5)
		rrect(ci, Rect2(hc.x - 66, hc.y - 60, 132, 116), 28, body)
		rrect(ci, Rect2(hc.x - 50, hc.y - 40, 100, 74), 20, Color("#2e3a52"), 4.0)
		ellipse(ci, hc + Vector2(-70, 0), 9, 20, Color("#8fd3ff"), 4.0)
		ellipse(ci, hc + Vector2(70, 0), 9, 20, Color("#8fd3ff"), 4.0)
	else:
		circle(ci, hc, 66, body)
		if kind == "penguin":
			var mask := PackedVector2Array()
			for i in 36:
				var a := TAU * i / 36
				var r := 50.0 + 8.0 * cos(2 * a)
				mask.append(hc + Vector2(cos(a) * r * 0.95, sin(a) * r * 0.8 + 10))
			ci.draw_colored_polygon(mask, Color.WHITE)
		if spec.get("stripes", false):
			for i in 3:
				var sx := -14 + i * 14
				ci.draw_line(hc + Vector2(sx, -64), hc + Vector2(sx * 0.8, -46), body.darkened(0.25), 6.0, true)
		if spec.has("muzzle"):
			ci.draw_colored_polygon(ellipse_pts(hc + Vector2(0, 22), 32, 22, 30), spec.muzzle)
	_ears(ci, hc, spec.ears, body, false)
	_face(ci, hc, kind, spec, o, look)
	if o.has("hat"):
		_hat(ci, hc, o.hat)
		if kind == "bunny":
			_ears(ci, hc, "bunny_front", body, false)
	reset(ci)


static func _egg(c: Vector2, rx: float, ry: float) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in 40:
		var a := TAU * i / 40
		var y := sin(a)
		var widen := 1.0 + 0.12 * y
		pts.append(c + Vector2(cos(a) * rx * widen, y * ry))
	return pts


static func _arm(ci: CanvasItem, shoulder: Vector2, up: float, side: int, col: Color, robot: bool) -> void:
	var ang := lerpf(0.35, -2.5, up) * side
	var dir := Vector2(0, 1).rotated(-ang)
	var hand := shoulder + dir * 58.0
	var arm_col := col.darkened(0.06)
	ci.draw_line(shoulder, hand, OUT, 32.0, true)
	ci.draw_line(shoulder, hand, arm_col, 22.0, true)
	if robot:
		circle(ci, hand, 14, Color("#8fd3ff"), 4.5)
	else:
		circle(ci, hand, 15, arm_col, 4.5)


static func _holding(ci: CanvasItem, at: Vector2, col: Color, _body: Color) -> void:
	circle(ci, at, 16, col, 4.0)


static func _ears(ci: CanvasItem, hc: Vector2, style: String, col: Color, behind: bool) -> void:
	var inner := Color("#ffa9c0")
	match style:
		"round":
			if behind:
				for s in [-1, 1]:
					circle(ci, hc + Vector2(48 * s, -46), 24, col)
					ci.draw_circle(hc + Vector2(48 * s, -46), 12, inner, true, -1.0, true)
		"mouse":
			if behind:
				for s in [-1, 1]:
					circle(ci, hc + Vector2(58 * s, -44), 36, col)
					ci.draw_circle(hc + Vector2(58 * s, -44), 22, inner, true, -1.0, true)
		"cat", "fox":
			if behind:
				for s in [-1, 1]:
					var tall := 92.0 if style == "fox" else 84.0
					var pts := PackedVector2Array([hc + Vector2(18 * s, -58), hc + Vector2(58 * s, -tall), hc + Vector2(62 * s, -30)])
					shape(ci, pts, col)
					var inn := PackedVector2Array([hc + Vector2(28 * s, -56), hc + Vector2(54 * s, -tall + 14), hc + Vector2(56 * s, -40)])
					ci.draw_colored_polygon(inn, inner if style == "cat" else Color("#3a2a2a"))
		"pig":
			if not behind:
				for s in [-1, 1]:
					var pts := PackedVector2Array([hc + Vector2(24 * s, -58), hc + Vector2(64 * s, -72), hc + Vector2(56 * s, -34)])
					shape(ci, pts, col.darkened(0.05))
		"bunny", "bunny_front":
			if (behind and style == "bunny") or style == "bunny_front":
				for s in [-1, 1]:
					var c := hc + Vector2(28 * s, -110)
					shape(ci, ellipse_pts(c, 18, 52, 30, 0.18 * s), col)
					ci.draw_colored_polygon(ellipse_pts(c + Vector2(0, 6), 8, 36, 24, 0.18 * s), inner)
		"frog":
			if behind:
				for s in [-1, 1]:
					circle(ci, hc + Vector2(32 * s, -54), 28, col)
		"tuft":
			if behind:
				for i in 3:
					var a := -PI / 2 + (i - 1) * 0.45
					var base := hc + Vector2(0, -60)
					var tip := base + Vector2(cos(a), sin(a)) * 34
					shape(ci, PackedVector2Array([base + Vector2(-7, 4), tip, base + Vector2(7, 4)]), col)


static func _face(ci: CanvasItem, hc: Vector2, kind: String, spec: Dictionary, o: Dictionary, look: Vector2) -> void:
	var eyes: String = o.get("eyes", "open")
	var mouth: String = o.get("mouth", "smile")
	var blush: bool = o.get("blush", true)
	var eye_y := -8.0
	var eye_dx := 24.0
	if kind == "frog":
		eye_y = -54.0
		eye_dx = 32.0
	if kind == "robot":
		# LED eyes on the screen.
		for s in [-1, 1]:
			var ec := hc + Vector2(22 * s, -10) + look * 4.0
			if eyes == "happy":
				arc(ci, ec, 10, PI + 0.2, TAU - 0.2, 6.0, Color("#8fffc1"))
			else:
				ci.draw_circle(ec, 11 if eyes == "wide" else 9, Color("#8fffc1"), true, -1.0, true)
		match mouth:
			"open", "grin", "o":
				ci.draw_colored_polygon(rrect_pts(Rect2(hc.x - 18, hc.y + 12, 36, 14), 6), Color("#8fffc1"))
			"chew":
				for i in 4:
					ci.draw_rect(Rect2(hc.x - 18 + i * 10, hc.y + 16 + (i % 2) * 4, 6, 5), Color("#8fffc1"))
			_:
				arc(ci, hc + Vector2(0, 8), 14, 0.4, PI - 0.4, 5.0, Color("#8fffc1"))
		return
	for s in [-1, 1]:
		var ec := hc + Vector2(eye_dx * s, eye_y)
		match eyes:
			"happy":
				arc(ci, ec + Vector2(0, 5), 11, PI + 0.25, TAU - 0.25, 5.5)
			_:
				var r := 15.0 if eyes == "wide" else 13.0
				circle(ci, ec, r, Color.WHITE, 4.0)
				var pc := ec + look.limit_length(1.0) * r * 0.42
				dot(ci, pc, r * 0.55, OUT)
				dot(ci, pc + Vector2(-2.5, -3), r * 0.2, Color.WHITE)
	if blush:
		for s in [-1, 1]:
			ci.draw_circle(hc + Vector2(44 * s, 18), 10 if mouth != "chew" else 13, Color(1, 0.45, 0.55, 0.45), true, -1.0, true)
	var mc := hc + Vector2(0, 26)
	if spec.get("beak", false) or spec.get("bill", false):
		var bill := Color("#ff9f43")
		var open := mouth in ["open", "grin", "o"]
		if open:
			shape(ci, PackedVector2Array([mc + Vector2(-20, -10), mc + Vector2(20, -10), mc + Vector2(0, -2)]), bill, 4.0)
			shape(ci, ellipse_pts(mc + Vector2(0, 8), 14, 10, 20), Color("#b8324a"), 4.0)
			shape(ci, PackedVector2Array([mc + Vector2(-16, 14), mc + Vector2(16, 14), mc + Vector2(0, 22)]), bill, 4.0)
		else:
			shape(ci, ellipse_pts(mc + Vector2(0, -4), 22, 11, 24), bill, 4.0)
			line(ci, mc + Vector2(-16, -3), mc + Vector2(16, -3), 3.0)
		return
	if kind == "pig" or spec.get("snout", false):
		ellipse(ci, hc + Vector2(0, 16), 24, 17, Color("#ff9ab2"), 4.0)
		for s in [-1, 1]:
			ci.draw_colored_polygon(ellipse_pts(hc + Vector2(8 * s, 16), 4, 6, 10), Color("#b8567a"))
		mc = hc + Vector2(0, 42)
	elif kind != "frog":
		# Nose.
		var nose := Color("#3a2a2a") if kind != "bunny" and kind != "mouse" else Color("#ff7a9a")
		ci.draw_colored_polygon(ellipse_pts(hc + Vector2(0, 12), 9, 6, 16), nose)
		if kind in ["cat", "mouse", "fox"]:
			for s in [-1, 1]:
				for k in 2:
					ci.draw_line(hc + Vector2(26 * s, 20 + k * 8), hc + Vector2(58 * s, 14 + k * 12), OUT, 2.5, true)
	match mouth:
		"open":
			shape(ci, ellipse_pts(mc + Vector2(0, 4), 17, 14, 24), Color("#8a2240"), 4.0)
			ci.draw_colored_polygon(ellipse_pts(mc + Vector2(0, 11), 10, 5, 16), Color("#ff7a9a"))
		"o":
			shape(ci, ellipse_pts(mc + Vector2(0, 2), 9, 10, 20), Color("#8a2240"), 4.0)
		"grin":
			var pts := PackedVector2Array()
			for i in 17:
				var a := PI * i / 16.0
				pts.append(mc + Vector2(cos(a) * 26, sin(a) * 22 - 4))
			shape(ci, pts, Color("#8a2240"), 4.0)
			ci.draw_colored_polygon(ellipse_pts(mc + Vector2(0, 12), 13, 5, 16), Color("#ff7a9a"))
		"chew":
			var pts := PackedVector2Array()
			for i in 9:
				pts.append(mc + Vector2(-16 + i * 4, 4 + (3.0 if i % 2 == 0 else -3.0)))
			ci.draw_polyline(pts, OUT, 4.0, true)
		_:
			var w := 18.0 if kind != "frog" else 34.0
			arc(ci, mc + Vector2(0, -8), w, 0.45, PI - 0.45, 5.0)


static func _hat(ci: CanvasItem, hc: Vector2, col: Color) -> void:
	var puffs := [[Vector2(-30, -92), 28.0], [Vector2(30, -92), 28.0], [Vector2(0, -108), 34.0]]
	for p in puffs:
		ci.draw_circle(hc + p[0], p[1] + 3.0, OUT, true, -1.0, true)
	for p in puffs:
		ci.draw_circle(hc + p[0], p[1] - 2.0, col, true, -1.0, true)
	rrect(ci, Rect2(hc.x - 46, hc.y - 84, 92, 30), 8, col, 5.0)
	ci.draw_line(hc + Vector2(-34, -70), hc + Vector2(34, -70), col.darkened(0.12), 4.0, true)
	dot(ci, hc + Vector2(-14, -116), 7, Color(1, 1, 1, 0.6))


# =================================================================== gag animals

## The kitchen dog, sitting, feet at `xf.origin`, about 130 px tall.
## `happy` wags and shows the tongue; `look` turns the eyes.
static func dog(ci: CanvasItem, xf: Transform2D, t: float, happy := 0.0, look := Vector2.ZERO) -> void:
	with_xf(ci, xf)
	var fur := Color("#fff6ea")
	var patch := Color("#e0a35f")
	var ear := Color("#8b5a3c")
	# Tail wag.
	var wag := sin(t * (18.0 if happy > 0.1 else 5.0)) * (0.6 if happy > 0.1 else 0.25)
	var tail_base := Vector2(34, -24)
	var tail_tip := tail_base + Vector2(34, -26).rotated(wag)
	ci.draw_line(tail_base, tail_tip, OUT, 16, true)
	ci.draw_line(tail_base, tail_tip, patch, 8, true)
	# Body and legs.
	shape(ci, _egg(Vector2(0, -38), 42, 40), fur)
	ci.draw_colored_polygon(ellipse_pts(Vector2(16, -44), 20, 22, 20), patch)
	ellipse(ci, Vector2(-18, -4), 16, 10, fur)
	ellipse(ci, Vector2(18, -4), 16, 10, fur)
	# Collar.
	rrect(ci, Rect2(-28, -84, 56, 12), 6, Pal.STRAWBERRY, 4.0)
	circle(ci, Vector2(0, -70), 7, Color("#ffd23f"), 3.5)
	# Head.
	var hc := Vector2(0, -112)
	circle(ci, hc, 38, fur)
	ci.draw_colored_polygon(ellipse_pts(hc + Vector2(-16, -12), 16, 15, 20), patch)
	for s in [-1, 1]:
		var e := hc + Vector2(34 * s, -8)
		shape(ci, ellipse_pts(e + Vector2(4 * s, 20), 13, 28, 24, -0.25 * s + wag * 0.1), ear, 4.5)
	ellipse(ci, hc + Vector2(0, 16), 22, 15, Color.WHITE, 4.0)
	ci.draw_colored_polygon(ellipse_pts(hc + Vector2(0, 8), 9, 6, 16), OUT)
	if happy > 0.1:
		shape(ci, ellipse_pts(hc + Vector2(6, 32), 8, 11, 16), Color("#ff7a9a"), 3.5)
	arc(ci, hc + Vector2(-7, 16), 7, 0.2, PI - 0.4, 3.5)
	arc(ci, hc + Vector2(7, 16), 7, 0.4, PI - 0.2, 3.5)
	for s in [-1, 1]:
		var ec := hc + Vector2(14 * s, -10)
		if happy > 0.5:
			arc(ci, ec + Vector2(0, 4), 7, PI + 0.3, TAU - 0.3, 4.0)
		else:
			dot(ci, ec + look * 2.0, 6.5, OUT)
			dot(ci, ec + look * 2.0 + Vector2(-2, -2), 2.2, Color.WHITE)
	reset(ci)


## The shelf cat, lying on the shelf, belly on `xf.origin`, about 120 px wide.
## `surprise` (0..1) widens the eyes (the pancake just landed on its head).
static func shelf_cat(ci: CanvasItem, xf: Transform2D, t: float, surprise := 0.0) -> void:
	with_xf(ci, xf)
	var fur := Color("#a9b1c7")
	var dark := Color("#7d86a0")
	# Tail hanging over the shelf edge.
	var sway := sin(t * 2.0) * 10.0
	var tail := PackedVector2Array([Vector2(46, -8), Vector2(62, 10), Vector2(58 + sway, 40), Vector2(64 + sway, 58)])
	ci.draw_polyline(tail, OUT, 16, true)
	ci.draw_polyline(tail, fur, 8, true)
	# Loaf body.
	shape(ci, rrect_pts(Rect2(-56, -44, 112, 46), 22), fur)
	for i in 3:
		ci.draw_line(Vector2(-4 + i * 16, -42), Vector2(-8 + i * 16, -24), dark, 5.0, true)
	ellipse(ci, Vector2(-40, -2), 14, 8, fur, 4.0)
	# Head.
	var hc := Vector2(-40, -56)
	for s in [-1, 1]:
		var pts := PackedVector2Array([hc + Vector2(8 * s, -26), hc + Vector2(26 * s, -48), hc + Vector2(32 * s, -14)])
		shape(ci, pts, fur, 4.5)
		ci.draw_colored_polygon(PackedVector2Array([hc + Vector2(13 * s, -26), hc + Vector2(24 * s, -40), hc + Vector2(27 * s, -18)]), Color("#ffa9c0"))
	circle(ci, hc, 32, fur)
	for i in 3:
		ci.draw_line(hc + Vector2(-10 + i * 10, -30), hc + Vector2(-8 + i * 8, -20), dark, 4.0, true)
	for s in [-1, 1]:
		var ec := hc + Vector2(12 * s, -2)
		if surprise > 0.5:
			circle(ci, ec, 8, Color.WHITE, 3.0)
			dot(ci, ec, 4, OUT)
		elif surprise > 0.0:
			arc(ci, ec + Vector2(0, 3), 6, PI + 0.3, TAU - 0.3, 3.5)
		else:
			# Sleepy half-closed eyes.
			arc(ci, ec, 6, 0.3, PI - 0.3, 3.5)
	ci.draw_colored_polygon(ellipse_pts(hc + Vector2(0, 8), 5, 3.5, 12), Color("#ff7a9a"))
	arc(ci, hc + Vector2(-4, 12), 4, 0.2, PI - 0.3, 3.0)
	arc(ci, hc + Vector2(4, 12), 4, 0.3, PI - 0.2, 3.0)
	for s in [-1, 1]:
		ci.draw_line(hc + Vector2(14 * s, 10), hc + Vector2(34 * s, 6), OUT, 2.0, true)
	reset(ci)


# =================================================================== effects

## A wisp of steam rising from `c`; `phase` 0..1 is its age.
static func steam(ci: CanvasItem, c: Vector2, phase: float, scale := 1.0) -> void:
	var a := sin(phase * PI) * 0.7
	var pts := PackedVector2Array()
	for i in 10:
		var u := i / 9.0
		pts.append(c + Vector2(sin(u * 5.0 + phase * 6.0) * 9.0 * scale, -u * 60.0 * scale - phase * 40.0))
	ci.draw_polyline(pts, Color(1, 1, 1, a), 7.0 * scale, true)


static func confetti(ci: CanvasItem, c: Vector2, col: Color, rot: float, kind: int) -> void:
	if kind % 3 == 0:
		ci.draw_colored_polygon(ellipse_pts(c, 7, 4, 12, rot), col)
	elif kind % 3 == 1:
		var r := Rect2(-8, -4, 16, 8)
		var pts := PackedVector2Array()
		for p in [r.position, r.position + Vector2(r.size.x, 0), r.end, r.position + Vector2(0, r.size.y)]:
			pts.append(c + p.rotated(rot))
		ci.draw_colored_polygon(pts, col)
	else:
		ci.draw_colored_polygon(star_pts(c, 8, 4, 5, rot), col)


# =================================================================== icons

## Seat role icons, 64 px, centred at c: 0 cook (a pan), 1 topper (a jar), 2
## flipper (a flying pancake with a sparkle).
static func role_icon(ci: CanvasItem, seat: int, c: Vector2, col: Color, s := 1.0) -> void:
	match seat:
		0:
			push(ci, Transform2D(0.0, Vector2(s * 0.3, s * 0.3), 0.0, c + Vector2(24, 10) * s))
			pan(ci, Vector2.ZERO, col)
			_pancake_local(ci, Vector2(0, -16))
			pop(ci)
		1:
			push(ci, Transform2D(0.0, Vector2(s * 0.62, s * 0.62), 0.0, c + Vector2(0, 6) * s))
			jar(ci, "strawberry", Vector2.ZERO, false, col)
			pop(ci)
		2:
			push(ci, Transform2D(-0.35, Vector2(s * 0.34, s * 0.34), 0.0, c + Vector2(-2, 8) * s))
			_pancake_local(ci, Vector2.ZERO)
			pop(ci)
			for i in 3:
				var a := -2.4 + i * 0.35
				arc(ci, c + Vector2(0, 8) * s, (26 + i * 7) * s, a, a + 0.5, 3.5 * s, col)
			sparkle(ci, c + Vector2(22, -22) * s, 13 * s, col)


## Device icons, about 64x40 at s = 1: a pad or a keyboard.
static func device_icon(ci: CanvasItem, pad: bool, c: Vector2, col: Color, s := 1.0) -> void:
	with_xf(ci, Transform2D(0.0, Vector2(s, s), 0.0, c))
	if pad:
		var pts := PackedVector2Array()
		for p in rrect_pts(Rect2(-32, -16, 64, 30), 14):
			pts.append(p)
		shape(ci, pts, col, 4.0)
		ellipse(ci, Vector2(-22, 12), 12, 12, col, 4.0)
		ellipse(ci, Vector2(22, 12), 12, 12, col, 4.0)
		ci.draw_colored_polygon(pts, col)
		ci.draw_rect(Rect2(-24, -4, 14, 4), OUT)
		ci.draw_rect(Rect2(-19, -9, 4, 14), OUT)
		dot(ci, Vector2(16, -5), 3.5, OUT)
		dot(ci, Vector2(22, 1), 3.5, OUT)
	else:
		rrect(ci, Rect2(-34, -18, 68, 36), 7, col, 4.0)
		for row in 3:
			for k in 5:
				ci.draw_rect(Rect2(-27 + k * 11, -12 + row * 9, 8, 6), OUT)
	reset(ci)
