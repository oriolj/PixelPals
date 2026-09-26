extends RefCounted
## Everything on the farm that is not a crop, drawn in code, side-on
## picture-book style. Each function paints at the item's origin, which is
## the object's ground point (where its wheels or feet touch the ground);
## vehicles and animals face RIGHT (flip the node's scale.x to face left).

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Crops := preload("res://scripts/draw/crop_art.gd")

## Where a rider sprite sits (its centre), relative to the vehicle origin.
const TRACTOR_SEAT := Vector2(-26, -70)
const TRAILER_SEAT := Vector2(-26, -58)


# ---------------------------------------------------------------- tractor

## The tractor, facing right, ~120 x 100. `spin` turns the wheel spokes.
## Draws everything behind the driver; call tractor_front() after the rider.
static func tractor(ci: CanvasItem, spin: float) -> void:
	# Cab: posts and a roof, a pale window behind the driver.
	S.box(ci, Rect2(-56, -98, 58, 10), 4, P.TRACTOR_LIGHT)
	S.box(ci, Rect2(-54, -90, 6, 50), 2, P.TRACTOR)
	S.box(ci, Rect2(-6, -90, 6, 50), 2, P.TRACTOR)
	ci.draw_rect(Rect2(-48, -88, 42, 40), Color(P.SKY_LOW, 0.55))
	# Exhaust pipe with a cap.
	S.box(ci, Rect2(26, -80, 7, 30), 2, P.METAL)
	S.box(ci, Rect2(24, -84, 11, 6), 2, P.TYRE)


static func tractor_front(ci: CanvasItem, spin: float) -> void:
	# Hood and body.
	var body := S.rrect(Rect2(-4, -58, 64, 34), 9)
	S.fill_ink(ci, body, P.TRACTOR)
	S.line(ci, Vector2(4, -52), Vector2(50, -52), Color(1, 1, 1, 0.35), 3.0)
	for i in 3:
		S.line(ci, Vector2(50 - i * 7, -44), Vector2(50 - i * 7, -30), P.INK, 2.0)
	S.disc(ci, Vector2(58, -44), 6, P.WHEEL_RIM)
	# Cab bottom (hides the driver's legs) and the seat side.
	S.box(ci, Rect2(-60, -52, 64, 28), 6, P.TRACTOR_LIGHT)
	S.box(ci, Rect2(-54, -46, 10, 8), 2, P.WHEEL_RIM)
	# Big back wheel with its fender, small front wheel.
	_wheel(ci, Vector2(-30, -30), 30, spin)
	S.fill_ink(ci, _arc_band(Vector2(-30, -30), 30, 38, PI * 1.05, PI * 1.95), P.TRACTOR)
	_wheel(ci, Vector2(38, -17), 17, spin * 1.7)


static func _wheel(ci: CanvasItem, c: Vector2, r: float, spin: float) -> void:
	S.disc(ci, c, r, P.TYRE)
	# Tread bumps.
	for i in 12:
		var a := spin + TAU * i / 12.0
		S.line(ci, c + Vector2(cos(a), sin(a)) * (r - 5), c + Vector2(cos(a), sin(a)) * (r - 1), P.INK, 3.0)
	S.disc(ci, c, r * 0.58, P.WHEEL_RIM)
	for i in 4:
		var a := spin + TAU * i / 4.0
		S.line(ci, c, c + Vector2(cos(a), sin(a)) * r * 0.5, P.WOOD_DARK, 3.0)
	S.disc(ci, c, r * 0.2, P.TRACTOR)


static func _arc_band(c: Vector2, r0: float, r1: float, a0: float, a1: float, n := 14) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n + 1:
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r1)
	for i in range(n, -1, -1):
		var a := lerpf(a0, a1, float(i) / n)
		pts.append(c + Vector2(cos(a), sin(a)) * r0)
	return pts


# ---------------------------------------------------------------- planter

## The plough + planter hitch, facing right, ~64 x 44. Four seed bags sit on
## top; `pick` lifts and glows (glow colour `glow`) when the planter is on.
static func planter(ci: CanvasItem, pick: int, on: bool, glow: Color, t: float) -> void:
	# Plough shares at the front, cutting the soil.
	for i in 2:
		var x := 18 + i * 10
		S.fill_ink(ci, PackedVector2Array([Vector2(x - 4, -18), Vector2(x + 3, -18), Vector2(x + 6, 0),
			Vector2(x - 2, -2)]), P.METAL)
	# Frame, hitch bar, wheel.
	S.line(ci, Vector2(28, -22), Vector2(46, -24), P.INK, 4.0)
	S.box(ci, Rect2(-32, -26, 62, 10), 3, P.BARN)
	_wheel(ci, Vector2(-18, -10), 10, t * 6.0)
	# Seed bags.
	for i in 4:
		var bx := -24 + i * 16
		var lift := 0.0
		if on and i == pick:
			lift = 8.0 + sin(t * 8.0) * 1.5
			ci.draw_circle(Vector2(bx, -40 - lift), 13, Color(glow, 0.45), true, -1.0, true)
		_bag(ci, Vector2(bx, -26 - lift), i, on and i == pick)


## A small seed bag standing on `base`, with its crop painted on it.
static func _bag(ci: CanvasItem, base: Vector2, crop: int, open: bool) -> void:
	var r := Rect2(base + Vector2(-7, -20), Vector2(14, 20))
	S.box(ci, r, 4, P.BAG)
	if open:
		S.oval(ci, base + Vector2(0, -20), 7, 2.5, P.SOIL, P.INK, 1.5)
	else:
		S.line(ci, base + Vector2(-5, -20), base + Vector2(5, -20), P.INK, 2.5)
	Crops.icon(ci, crop, 11.0, base + Vector2(0, -9))


## A bigger seed bag icon (join/select seat icon, the planter HUD).
static func seed_bag(ci: CanvasItem, c: Vector2, size: float, crop: int, open := true) -> void:
	var k := size / 40.0
	var top := c + Vector2(0, -16 * k)
	var pts := PackedVector2Array([top + Vector2(-12, 0) * k, top + Vector2(12, 0) * k,
		c + Vector2(16, 18) * k, c + Vector2(-16, 18) * k])
	S.fill_ink(ci, Crops._round_poly(pts), P.BAG)
	S.box(ci, Rect2(top + Vector2(-13, -6) * k, Vector2(26, 7) * k), 3 * k, P.BAG_DARK)
	if open:
		for i in 3:
			ci.draw_circle(top + Vector2(-6 + i * 6, -8 - (i % 2) * 3) * k, 2.4 * k, P.CROP_COLORS[crop].darkened(0.1), true, -1.0, true)
	Crops.icon(ci, crop, 18.0 * k, c + Vector2(0, 5 * k))


# ---------------------------------------------------------------- trailer

## The trailer, facing right, ~96 x 50, with `crops` piled inside
## (up to FieldRules.TRAILER_CAP) and an optional `tilt` when tipping.
static func trailer(ci: CanvasItem, crops: Array, spin: float) -> void:
	S.line(ci, Vector2(44, -18), Vector2(60, -22), P.INK, 4.0)
	# Pile of crops: rows of 5 from the floor up, heaped towards the front
	# (the farmhand sits at the back), drawn behind the front wall.
	var n := crops.size()
	for i in n:
		var row := i / 5
		var col := i % 5
		var x := -12 + col * 13 + (row % 2) * 6
		var y := -40 - row * 10
		Crops.icon(ci, crops[i], 19.0, Vector2(x, y))
	# Wooden box.
	S.box(ci, Rect2(-48, -40, 96, 26), 4, P.WOOD)
	for i in 2:
		S.line(ci, Vector2(-44, -32 + i * 8), Vector2(44, -32 + i * 8), P.WOOD_DARK, 2.0)
	S.box(ci, Rect2(-50, -44, 100, 7), 3, P.BARN)
	_wheel(ci, Vector2(-26, -13), 13, spin)
	_wheel(ci, Vector2(26, -13), 13, spin)


# ---------------------------------------------------------------- cloud

enum Face { IDLE, RAIN, HAPPY }

const CLOUD_PUFFS := [[Vector2(-38, 6), 24.0], [Vector2(38, 6), 24.0], [Vector2(-16, -10), 30.0],
	[Vector2(18, -14), 28.0], [Vector2(0, 10), 26.0]]


## The rain cloud with a face, ~130 x 80, centred on the origin.
static func cloud(ci: CanvasItem, face: int, blink: bool, t: float, tint := Color.WHITE) -> void:
	for p in CLOUD_PUFFS:
		ci.draw_circle(p[0], p[1] + 3.0, P.INK, true, -1.0, true)
	var body := P.WHITE * tint
	for p in CLOUD_PUFFS:
		ci.draw_circle(p[0], p[1], body, true, -1.0, true)
	# Soft blue belly.
	ci.draw_circle(Vector2(0, 16), 20, Color(P.SKY_LOW, 0.8), true, -1.0, true)
	ci.draw_circle(Vector2(-28, 14), 14, Color(P.SKY_LOW, 0.6), true, -1.0, true)
	ci.draw_circle(Vector2(28, 14), 14, Color(P.SKY_LOW, 0.6), true, -1.0, true)
	# Face.
	var fc := Vector2(0, 0)
	S.oval(ci, fc + Vector2(-26, 8), 7, 4.5, Color(P.BLUSH, 0.75), P.INK, 0.0)
	S.oval(ci, fc + Vector2(26, 8), 7, 4.5, Color(P.BLUSH, 0.75), P.INK, 0.0)
	match face:
		Face.IDLE:
			S.eyes(ci, fc + Vector2(0, -2), 30, 5, blink)
			S.smile(ci, fc + Vector2(0, 8), 14, 3.5, P.INK, 3.0)
		Face.RAIN:
			S.eyes(ci, fc + Vector2(0, -2), 30, 5, true)
			S.oval(ci, fc + Vector2(0, 12), 5, 6 + sin(t * 14.0) * 1.5, P.INK.lightened(0.15), P.INK, 2.0)
		Face.HAPPY:
			S.eyes(ci, fc + Vector2(0, -3), 30, 5, true)
			var mouth := PackedVector2Array()
			for i in 13:
				var a := PI * i / 12.0
				mouth.append(fc + Vector2(cos(a) * 10, 6 + sin(a) * 10))
			S.fill_ink(ci, mouth, Color("#8f2e3f"))


# ---------------------------------------------------------------- rainbow

## Rainbow bands centred on the origin (the arc's centre), `r` outer radius.
static func rainbow(ci: CanvasItem, r: float, band: float, alpha: float) -> void:
	for i in P.RAINBOW.size():
		var rr := r - band * (i + 0.5)
		ci.draw_arc(Vector2.ZERO, rr, PI, TAU, 64, Color(P.RAINBOW[i], alpha), band + 1.0, true)


# ---------------------------------------------------------------- scenery

## A red barn, ground-centred, ~180 x 190, with its big door `open` (0..1).
static func barn(ci: CanvasItem, open: float) -> void:
	var w := 90.0
	var body := PackedVector2Array([Vector2(-w, 0), Vector2(-w, -110), Vector2(-w + 30, -150),
		Vector2(0, -178), Vector2(w - 30, -150), Vector2(w, -110), Vector2(w, 0)])
	S.fill_ink(ci, body, P.BARN, P.INK, 3.0)
	for i in 9:
		var x := -w + 12 + i * 20.5
		S.line(ci, Vector2(x, -104 - absf(x) * -0.0), Vector2(x, -4), P.BARN_DARK, 2.0)
	# Roof edge.
	var roof := PackedVector2Array([Vector2(-w - 10, -106), Vector2(-w + 28, -156), Vector2(0, -188),
		Vector2(w - 28, -156), Vector2(w + 10, -106)])
	S.path(ci, roof, P.INK, 16.0)
	S.path(ci, roof, P.ROOF, 11.0)
	# Hayloft window.
	S.box(ci, Rect2(-18, -142, 36, 28), 3, P.CREAM)
	S.box(ci, Rect2(-13, -137, 26, 18), 2, Color("#e9c46a"))
	# Big door with an X brace; it slides aside when open.
	var door := Rect2(-44, -92, 88, 92)
	S.box(ci, door, 3, Color("#3a1f1f"))
	var slide := open * 40.0
	for side in [-1.0, 1.0]:
		var dr := Rect2(Vector2(-44 if side < 0 else 0, -92) + Vector2(side * slide, 0), Vector2(44, 92))
		S.box(ci, dr, 3, P.BARN_DARK)
		S.path(ci, PackedVector2Array([dr.position + Vector2(4, 4), dr.end - Vector2(4, 4)]), P.CREAM, 5.0)
		S.path(ci, PackedVector2Array([Vector2(dr.position.x + 4, dr.end.y - 4), Vector2(dr.end.x - 4, dr.position.y + 4)]), P.CREAM, 5.0)
		ci.draw_rect(dr.grow(-2), P.CREAM, false, 4.0)


## A wooden crate, ground-centred, 44 x 30, with `n` crops of `crop` heaped
## on top (drawn up to 12, the heap grows in rows of 3).
static func crate(ci: CanvasItem, crop: int, n: int) -> void:
	for i in mini(n, 12):
		var row := i / 3
		var col := i % 3
		Crops.icon(ci, crop, 15.0, Vector2(-13 + col * 13 + (row % 2) * 6, -34 - row * 10))
	S.box(ci, Rect2(-22, -30, 44, 30), 3, P.WOOD)
	S.line(ci, Vector2(-20, -15), Vector2(20, -15), P.WOOD_DARK, 2.0)
	ci.draw_circle(Vector2(0, -15), 10, P.CREAM, true, -1.0, true)
	Crops.icon(ci, crop, 16.0, Vector2(0, -15))


static func tree(ci: CanvasItem, size: float, t: float) -> void:
	var k := size / 100.0
	S.box(ci, Rect2(Vector2(-8, -40) * k, Vector2(16, 42) * k), 3, P.WOOD_DARK)
	var sway := sin(t * 0.8) * 2.0
	for b in [[Vector2(-24, -62), 28.0], [Vector2(24, -64), 28.0], [Vector2(0, -86), 34.0], [Vector2(0, -58), 30.0]]:
		ci.draw_circle((b[0] + Vector2(sway, 0)) * k, (b[1] + 3.0) * k, P.INK, true, -1.0, true)
	for b in [[Vector2(-24, -62), 28.0], [Vector2(24, -64), 28.0], [Vector2(0, -86), 34.0], [Vector2(0, -58), 30.0]]:
		ci.draw_circle((b[0] + Vector2(sway, 0)) * k, b[1] * k, P.LEAF, true, -1.0, true)
	ci.draw_circle((Vector2(-12, -92) + Vector2(sway, 0)) * k, 12 * k, P.LEAF_LIGHT, true, -1.0, true)
	for a in [Vector2(-22, -66), Vector2(18, -74), Vector2(4, -56)]:
		S.disc(ci, (a + Vector2(sway, 0)) * k, 5 * k, P.STRAWBERRY, P.INK, 1.5)


## A fence run from a to b (posts every ~48 px, two rails).
static func fence(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	var n := maxi(1, int(a.distance_to(b) / 48.0))
	for rail in [-26.0, -12.0]:
		S.line(ci, a + Vector2(0, rail), b + Vector2(0, rail), P.INK, 8.0)
		S.line(ci, a + Vector2(0, rail), b + Vector2(0, rail), P.WOOD, 5.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		S.box(ci, Rect2(p + Vector2(-5, -36), Vector2(10, 38)), 3, P.WOOD)


static func pond(ci: CanvasItem, rx: float, ry: float, t: float) -> void:
	S.oval(ci, Vector2.ZERO, rx + 6, ry + 4, P.GRASS_DARK, P.INK, 0.0)
	S.oval(ci, Vector2.ZERO, rx, ry, P.WATER, P.INK, 2.0)
	for i in 2:
		var ph := fmod(t * 0.5 + i * 0.5, 1.0)
		S.oval(ci, Vector2(-rx * 0.2 + i * rx * 0.4, 0), rx * 0.2 + ph * rx * 0.3, ry * 0.2 + ph * ry * 0.3,
			Color(0, 0, 0, 0), Color(1, 1, 1, 0.5 * (1.0 - ph)), 2.0)
	for x in [-rx * 0.8, -rx * 0.65, rx * 0.75]:
		S.line(ci, Vector2(x, -ry * 0.1), Vector2(x + 2, -ry * 0.1 - 22), P.LEAF, 3.0)
		S.oval(ci, Vector2(x + 2, -ry * 0.1 - 22), 3, 7, P.WOOD_DARK, P.INK, 1.5)


static func sun(ci: CanvasItem, r: float, t: float, beam: float) -> void:
	for i in 12:
		var a := TAU * i / 12.0 + t * 0.2
		var ray := r * (0.45 + 0.15 * sin(t * 3.0 + i)) + beam * 12.0
		S.line(ci, Vector2(cos(a), sin(a)) * (r + 6), Vector2(cos(a), sin(a)) * (r + 6 + ray), P.SUNFLOWER, 6.0)
	S.disc(ci, Vector2.ZERO, r + beam * 4.0, P.SUNFLOWER, P.INK, 3.0)
	S.oval(ci, Vector2(-r * 0.45, r * 0.2), r * 0.16, r * 0.1, Color(P.BLUSH, 0.8), P.INK, 0.0)
	S.oval(ci, Vector2(r * 0.45, r * 0.2), r * 0.16, r * 0.1, Color(P.BLUSH, 0.8), P.INK, 0.0)
	S.eyes(ci, Vector2(0, -r * 0.12), r * 0.6, r * 0.1, true)
	S.smile(ci, Vector2(0, r * 0.22), r * 0.45, r * 0.12, P.INK, 3.0)


# ---------------------------------------------------------------- animals

## pose 0/1 is the two-pose hop; every animal is ground-centred, facing right.
static func animal(ci: CanvasItem, kind: String, pose: int) -> void:
	var lift := -6.0 if pose == 1 else 0.0
	S.local(ci, Vector2(0, lift))
	S.oval(ci, Vector2(0, -lift), 16, 4, Color(0, 0, 0, 0.18), P.INK, 0.0)
	match kind:
		"bunny": _bunny(ci, pose)
		"pig": _pig(ci, pose)
		"hen": _hen(ci, pose)
		"duck": _duck(ci, pose)
		"frog": _frog(ci, pose)
	S.unlocal(ci)


static func _bunny(ci: CanvasItem, pose: int) -> void:
	var fur := Color("#f1ece4")
	S.disc(ci, Vector2(-14, -14), 6, P.WHITE)
	S.oval(ci, Vector2(-3, -14), 14, 12, fur)
	S.oval(ci, Vector2(-8, -4), 6, 4, fur)
	var ear := -0.25 if pose == 0 else -0.05
	for e in [Vector2(4, -34), Vector2(12, -34)]:
		S.oval(ci, e, 4.5, 12, fur, P.INK, 2.0, ear)
		S.oval(ci, e + Vector2(0, 2), 2, 8, P.PINK, P.INK, 0.0, ear)
	S.disc(ci, Vector2(10, -22), 11, fur)
	S.eyes(ci, Vector2(14, -24), 0, 2.6)
	ci.draw_circle(Vector2(20, -20), 2.4, P.PINK_DARK, true, -1.0, true)
	S.oval(ci, Vector2(12, -16), 3, 2, Color(P.BLUSH, 0.8), P.INK, 0.0)


static func _pig(ci: CanvasItem, pose: int) -> void:
	for x in [-12.0, -4.0, 6.0, 12.0]:
		S.box(ci, Rect2(x - 3, -10 + (2.0 if pose == 1 and int(x) % 2 == 0 else 0.0), 6, 10), 2, P.PINK_DARK)
	S.oval(ci, Vector2(-1, -18), 20, 13, P.PINK)
	S.path(ci, S.curve(Vector2(-20, -20), Vector2(-30, -30), Vector2(-24, -18), 8), P.PINK_DARK, 3.0)
	S.disc(ci, Vector2(15, -24), 11, P.PINK)
	S.fill_ink(ci, PackedVector2Array([Vector2(8, -32), Vector2(12, -42), Vector2(17, -33)]), P.PINK_DARK)
	S.oval(ci, Vector2(24, -21), 5, 6, P.PINK_DARK)
	ci.draw_circle(Vector2(23, -23), 1.3, P.INK, true, -1.0, true)
	ci.draw_circle(Vector2(25, -19), 1.3, P.INK, true, -1.0, true)
	S.eyes(ci, Vector2(15, -28), 0, 2.4)


static func _hen(ci: CanvasItem, pose: int) -> void:
	S.line(ci, Vector2(-3, -8), Vector2(-4, 0), Color("#f39a2d"), 3.0)
	S.line(ci, Vector2(4, -8), Vector2(5, 0), Color("#f39a2d"), 3.0)
	S.fill_ink(ci, PackedVector2Array([Vector2(-14, -20), Vector2(-24, -34), Vector2(-18, -18)]), P.WHITE)
	S.oval(ci, Vector2(-2, -17), 15, 12, P.WHITE)
	S.oval(ci, Vector2(-4, -17), 8, 5, Color("#e9e2d6"), P.INK, 1.5, 0.3 if pose == 0 else -0.2)
	S.disc(ci, Vector2(10, -30), 9, P.WHITE)
	for i in 3:
		S.disc(ci, Vector2(6 + i * 4, -40 + absf(i - 1) * 2), 3.2, P.STRAWBERRY, P.INK, 1.5)
	S.fill_ink(ci, PackedVector2Array([Vector2(17, -32), Vector2(24, -29), Vector2(17, -26)]), Color("#f39a2d"))
	S.oval(ci, Vector2(16, -23), 2.5, 3.5, P.STRAWBERRY, P.INK, 1.2)
	S.eyes(ci, Vector2(12, -32), 0, 2.2)


static func _duck(ci: CanvasItem, pose: int) -> void:
	var y := Color("#ffe14d")
	S.oval(ci, Vector2(-2, -12), 15, 10, y)
	S.fill_ink(ci, PackedVector2Array([Vector2(-14, -16), Vector2(-22, -22), Vector2(-15, -10)]), y)
	S.oval(ci, Vector2(-3, -13), 7, 4, Color("#f5c83a"), P.INK, 1.5, 0.3 if pose == 0 else -0.3)
	S.disc(ci, Vector2(9, -24), 9, y)
	S.oval(ci, Vector2(19, -22), 6, 3, Color("#f39a2d"), P.INK, 1.5)
	S.eyes(ci, Vector2(11, -27), 0, 2.2)


static func _frog(ci: CanvasItem, pose: int) -> void:
	var g := P.LEAF_BRIGHT
	S.oval(ci, Vector2(-10, -4), 8, 4, g)
	S.oval(ci, Vector2(10, -4), 8, 4, g)
	S.oval(ci, Vector2(0, -13), 17, 12, g)
	S.oval(ci, Vector2(0, -9), 10, 6, Color("#c8e89a"), P.INK, 0.0)
	for x in [-8.0, 8.0]:
		S.disc(ci, Vector2(x, -25), 6.5, g)
		ci.draw_circle(Vector2(x, -25), 4.2, P.WHITE, true, -1.0, true)
		ci.draw_circle(Vector2(x + 1, -25), 2.4, P.INK, true, -1.0, true)
	S.smile(ci, Vector2(0, -14), 16, 2.5 if pose == 0 else 4.0, P.INK, 2.0)


# ---------------------------------------------------------------- seat icons

## Steering wheel (driver seat), centred, `r` radius.
static func steering_wheel(ci: CanvasItem, r: float, col: Color) -> void:
	ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, P.INK, r * 0.34, true)
	ci.draw_arc(Vector2.ZERO, r, 0, TAU, 40, col, r * 0.22, true)
	for a in [PI / 2, PI / 2 + 2.1, PI / 2 - 2.1]:
		S.line(ci, Vector2.ZERO, Vector2(cos(a), sin(a)) * r, P.INK, r * 0.24)
		S.line(ci, Vector2.ZERO, Vector2(cos(a), sin(a)) * r, col, r * 0.12)
	S.disc(ci, Vector2.ZERO, r * 0.28, col, P.INK, 3.0)


## Gamepad icon, centred, ~`w` wide.
static func pad_icon(ci: CanvasItem, w: float, col: Color) -> void:
	var k := w / 60.0
	S.fill_ink(ci, S.rrect(Rect2(Vector2(-30, -16) * k, Vector2(60, 30) * k), 14 * k), col, P.INK, 3.0)
	S.disc(ci, Vector2(-26, 8) * k, 10 * k, col, P.INK, 3.0)
	S.disc(ci, Vector2(26, 8) * k, 10 * k, col, P.INK, 3.0)
	ci.draw_rect(Rect2(Vector2(-20, -4) * k, Vector2(12, 4) * k), P.INK)
	ci.draw_rect(Rect2(Vector2(-16, -8) * k, Vector2(4, 12) * k), P.INK)
	ci.draw_circle(Vector2(14, -4) * k, 3.5 * k, P.STRAWBERRY, true, -1.0, true)
	ci.draw_circle(Vector2(21, 1) * k, 3.5 * k, P.LEAF_BRIGHT, true, -1.0, true)


## Keyboard icon, centred, ~`w` wide.
static func kb_icon(ci: CanvasItem, w: float, col: Color) -> void:
	var k := w / 60.0
	S.fill_ink(ci, S.rrect(Rect2(Vector2(-30, -16) * k, Vector2(60, 32) * k), 5 * k), col, P.INK, 3.0)
	for row in 3:
		for i in 6 - (1 if row == 2 else 0):
			ci.draw_rect(Rect2(Vector2(-25 + i * 9 + row * 2, -11 + row * 8) * k, Vector2(6, 5) * k), P.INK.lightened(0.2))
	ci.draw_rect(Rect2(Vector2(-14, 12) * k, Vector2(28, 3) * k), P.INK.lightened(0.2))
