extends RefCounted
## The four crops in four stages each, drawn in code.
##
## draw(ci, crop, stage) paints at the item's origin, which is the point where
## the plant meets the soil; the plant grows upward (negative y) and stays
## within about 60 px across. Stages: 0 seed, 1 sprout, 2 growing, 3 ripe.
## Crops: 0 carrot, 1 pumpkin, 2 sunflower, 3 strawberry (FieldRules.Crop).
##
## Silhouettes are kept distinct on purpose: carrot = feathery fronds over an
## orange wedge, pumpkin = wide and round, sunflower = tall stick with a disc,
## strawberry = low bush with red drops.

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")

const SEED := 0
const SPROUT := 1
const GROWING := 2
const RIPE := 3


static func draw(ci: CanvasItem, crop: int, stage: int, ink := P.INK) -> void:
	match stage:
		SEED: _seed(ci, crop)
		_:
			match crop:
				0: _carrot(ci, stage)
				1: _pumpkin(ci, stage)
				2: _sunflower(ci, stage)
				3: _strawberry(ci, stage)


## A ripe crop as an icon (seed bags, picker, crates, trailer pile, party).
## Centred on `at`, about `size` px tall. It composes onto S.base, so an
## outer transform must be set with S.xform(), not draw_set_transform().
static func icon(ci: CanvasItem, crop: int, size := 40.0, at := Vector2.ZERO) -> void:
	var k := size / 48.0
	S.local(ci, at + Vector2(0, 24.0 * k), Vector2(k, k))
	match crop:
		0: _carrot_icon(ci)
		1: _pumpkin(ci, RIPE, false)
		2: _sunflower_head(ci, Vector2(0, -24), 20.0)
		3: _berry(ci, Vector2(0, -42), 38.0)
	S.unlocal(ci)


# ---------------------------------------------------------------- seed

static func _seed(ci: CanvasItem, crop: int) -> void:
	# A little mound of turned soil with three seeds in the crop's colour, so
	# the kid can see what was sown before it sprouts.
	S.oval(ci, Vector2(0, -3), 16, 7, P.SOIL.lightened(0.08), P.FURROW, 2.0)
	var col: Color = P.CROP_COLORS[crop]
	for i in 3:
		var p := Vector2(-8 + i * 8, -5 + (i % 2) * 2)
		S.oval(ci, p, 3.2, 2.4, col, P.INK, 1.5, 0.4)


# ---------------------------------------------------------------- carrot

static func _carrot(ci: CanvasItem, stage: int) -> void:
	match stage:
		SPROUT:
			_frond(ci, Vector2(0, 0), 16, -PI / 2 - 0.45, 5)
			_frond(ci, Vector2(0, 0), 18, -PI / 2 + 0.4, 5)
		GROWING:
			S.oval(ci, Vector2(0, -2), 9, 5, P.CARROT, P.INK, 2.0)
			for a in [-0.7, -0.25, 0.2, 0.65]:
				_frond(ci, Vector2(0, -4), 28, -PI / 2 + a, 7)
		RIPE:
			for a in [-0.85, -0.42, 0.0, 0.42, 0.85]:
				_frond(ci, Vector2(0, -16), 34 - absf(a) * 6.0, -PI / 2 + a, 9)
			var body := PackedVector2Array([Vector2(-15, -18), Vector2(15, -18), Vector2(13, -8),
				Vector2(6, 4), Vector2(-6, 4), Vector2(-13, -8)])
			S.fill_ink(ci, _round_poly(body), P.CARROT)
			S.line(ci, Vector2(-8, -10), Vector2(-2, -10), P.INK, 1.5)
			S.line(ci, Vector2(3, -4), Vector2(8, -4), P.INK, 1.5)
			S.line(ci, Vector2(-9, -15), Vector2(-5, -15), Color(1, 1, 1, 0.55), 2.5)
			# Soil lip in front, so the carrot sits IN the ground.
			S.oval(ci, Vector2(0, 2), 16, 4, P.FURROW, P.INK, 2.0)


static func _carrot_icon(ci: CanvasItem) -> void:
	for a in [-0.5, 0.0, 0.5]:
		_frond(ci, Vector2(0, -34), 16, -PI / 2 + a, 6)
	var body := PackedVector2Array([Vector2(-12, -36), Vector2(12, -36), Vector2(9, -20),
		Vector2(3, 0), Vector2(-3, 0), Vector2(-9, -20)])
	S.fill_ink(ci, _round_poly(body), P.CARROT)
	S.line(ci, Vector2(-6, -26), Vector2(0, -26), P.INK, 1.5)
	S.line(ci, Vector2(1, -16), Vector2(5, -16), P.INK, 1.5)


## A feathery carrot frond: a stalk with small leaflets.
static func _frond(ci: CanvasItem, base: Vector2, length: float, angle: float, leaflets: int) -> void:
	var d := Vector2(cos(angle), sin(angle))
	var tip := base + d * length
	S.line(ci, base, tip, P.LEAF, 3.0)
	for i in leaflets:
		var t := 0.35 + 0.65 * float(i) / maxf(1.0, leaflets - 1)
		var p := base + d * length * t
		var side := 1.0 if i % 2 == 0 else -1.0
		S.fill_ink(ci, S.leaf(p, 8.0 - t * 2.0, 5.0, angle + side * 0.9, 5), P.LEAF_BRIGHT, P.INK, 1.5)
	S.fill_ink(ci, S.leaf(tip - d * 2.0, 9.0, 6.0, angle, 5), P.LEAF_BRIGHT, P.INK, 1.5)


# ---------------------------------------------------------------- pumpkin

static func _pumpkin(ci: CanvasItem, stage: int, with_leaves := true) -> void:
	match stage:
		SPROUT:
			S.line(ci, Vector2(0, 0), Vector2(0, -10), P.LEAF, 3.0)
			S.oval(ci, Vector2(-7, -13), 8, 5, P.LEAF_BRIGHT, P.INK, 2.0, -0.3)
			S.oval(ci, Vector2(7, -13), 8, 5, P.LEAF_BRIGHT, P.INK, 2.0, 0.3)
		GROWING:
			S.path(ci, S.curve(Vector2(-22, -4), Vector2(0, -20), Vector2(22, -6)), P.LEAF, 3.0)
			_round_leaf(ci, Vector2(-14, -18), 12)
			_round_leaf(ci, Vector2(14, -20), 13)
			S.disc(ci, Vector2(2, -9), 9, P.LEAF_LIGHT)
			S.line(ci, Vector2(2, -17), Vector2(3, -21), P.LEAF, 3.0)
		RIPE:
			if with_leaves:
				_round_leaf(ci, Vector2(-22, -22), 12)
				_round_leaf(ci, Vector2(24, -26), 11)
			S.oval(ci, Vector2(-11, -16), 14, 16, P.PUMPKIN_SIDE)
			S.oval(ci, Vector2(11, -16), 14, 16, P.PUMPKIN_SIDE)
			S.oval(ci, Vector2(0, -16), 13, 17, P.PUMPKIN)
			S.path(ci, S.curve(Vector2(-4, -31), Vector2(-7, -16), Vector2(-4, -1), 8), P.PUMPKIN_SIDE, 2.0)
			S.path(ci, S.curve(Vector2(4, -31), Vector2(7, -16), Vector2(4, -1), 8), P.PUMPKIN_SIDE, 2.0)
			S.box(ci, Rect2(-3, -38, 6, 9), 2, P.LEAF)
			S.path(ci, S.curve(Vector2(2, -34), Vector2(12, -44), Vector2(14, -34), 8), P.LEAF, 2.0)
			S.line(ci, Vector2(-15, -24), Vector2(-13, -12), Color(1, 1, 1, 0.5), 3.0)


static func _round_leaf(ci: CanvasItem, c: Vector2, r: float) -> void:
	# Three overlapping lobes read as a big squash leaf.
	S.oval(ci, c + Vector2(-r * 0.45, 0), r * 0.62, r * 0.55, P.LEAF)
	S.oval(ci, c + Vector2(r * 0.45, 0), r * 0.62, r * 0.55, P.LEAF)
	S.oval(ci, c + Vector2(0, -r * 0.35), r * 0.62, r * 0.6, P.LEAF_LIGHT)


# ---------------------------------------------------------------- sunflower

static func _sunflower(ci: CanvasItem, stage: int) -> void:
	match stage:
		SPROUT:
			S.line(ci, Vector2(0, 0), Vector2(0, -16), P.LEAF, 3.0)
			S.fill_ink(ci, S.leaf(Vector2(0, -12), 12, 7, -PI + 0.5), P.LEAF_BRIGHT)
			S.fill_ink(ci, S.leaf(Vector2(0, -14), 12, 7, -0.5), P.LEAF_BRIGHT)
		GROWING:
			S.line(ci, Vector2(0, 0), Vector2(0, -36), P.LEAF, 4.0)
			S.fill_ink(ci, S.leaf(Vector2(0, -14), 16, 9, -PI + 0.35), P.LEAF_LIGHT)
			S.fill_ink(ci, S.leaf(Vector2(0, -22), 16, 9, -0.35), P.LEAF_LIGHT)
			for i in 6:
				var a := -PI / 2 + (i - 2.5) * 0.45
				S.fill_ink(ci, S.leaf(Vector2(0, -38), 9, 5, a, 5), P.SUNFLOWER, P.INK, 1.5)
			S.disc(ci, Vector2(0, -38), 7, P.LEAF_BRIGHT)
		RIPE:
			S.line(ci, Vector2(0, 0), Vector2(0, -50), P.LEAF, 4.5)
			S.fill_ink(ci, S.leaf(Vector2(0, -12), 20, 11, -PI + 0.3), P.LEAF_LIGHT)
			S.fill_ink(ci, S.leaf(Vector2(0, -24), 19, 11, -0.3), P.LEAF_LIGHT)
			_sunflower_head(ci, Vector2(0, -54), 21.0)


static func _sunflower_head(ci: CanvasItem, c: Vector2, r: float) -> void:
	for i in 12:
		var a := TAU * i / 12.0
		S.fill_ink(ci, S.leaf(c + Vector2(cos(a), sin(a)) * r * 0.35, r * 0.7, r * 0.42, a, 6),
			P.SUNFLOWER, P.INK, 1.5)
	S.disc(ci, c, r * 0.48, P.SUN_CENTRE)
	for i in 5:
		var a := TAU * i / 5.0 + 0.3
		ci.draw_circle(c + Vector2(cos(a), sin(a)) * r * 0.26, 1.6, P.SOIL.lightened(0.25), true, -1.0, S.aa)
	ci.draw_circle(c + Vector2(-r * 0.2, -r * 0.2), r * 0.1, Color(1, 1, 1, 0.5), true, -1.0, S.aa)


# ---------------------------------------------------------------- strawberry

static func _strawberry(ci: CanvasItem, stage: int) -> void:
	match stage:
		SPROUT:
			_trefoil(ci, Vector2(0, -8), 6.0)
		GROWING:
			_trefoil(ci, Vector2(-11, -8), 8.0)
			_trefoil(ci, Vector2(11, -9), 8.0)
			_trefoil(ci, Vector2(0, -16), 9.0)
			_blossom(ci, Vector2(-8, -24))
			_blossom(ci, Vector2(10, -20))
		RIPE:
			_trefoil(ci, Vector2(-14, -12), 9.0)
			_trefoil(ci, Vector2(14, -13), 9.0)
			_trefoil(ci, Vector2(0, -22), 10.0)
			_berry(ci, Vector2(-14, -6), 18.0)
			_berry(ci, Vector2(14, -7), 18.0)
			_berry(ci, Vector2(0, -2), 22.0)


## Three rounded leaflets around `c`.
static func _trefoil(ci: CanvasItem, c: Vector2, r: float) -> void:
	for a in [-PI / 2, -PI / 2 + 2.1, -PI / 2 - 2.1]:
		S.oval(ci, c + Vector2(cos(a), sin(a)) * r * 0.62, r * 0.62, r * 0.52, P.LEAF_LIGHT, P.INK, 1.5, a)


static func _blossom(ci: CanvasItem, c: Vector2) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		S.disc(ci, c + Vector2(cos(a), sin(a)) * 3.6, 3.4, P.WHITE, P.INK, 1.2)
	ci.draw_circle(c, 2.6, P.SUNFLOWER, true, -1.0, S.aa)


## A strawberry hanging from `top`, `h` px tall: a rounded drop with a green
## cap and pale seeds.
static func _berry(ci: CanvasItem, top: Vector2, h: float) -> void:
	var pts := PackedVector2Array()
	var n := 20
	for i in n:
		var t := TAU * i / n
		# Wide shoulders, pointed bottom.
		var x := sin(t) * (0.5 + 0.12 * cos(t)) * h * (0.75 + 0.25 * cos(t))
		var y := (0.5 - 0.5 * cos(t)) * h
		pts.append(top + Vector2(x, y))
	S.fill_ink(ci, pts, P.STRAWBERRY)
	for k in 5:
		var p := top + Vector2((-0.22 + 0.11 * k) * h * (1.0 if k % 2 == 0 else 0.9), (0.35 + 0.15 * (k % 2)) * h)
		ci.draw_circle(p, maxf(1.1, h * 0.05), P.SUNFLOWER, true, -1.0, S.aa)
	ci.draw_circle(top + Vector2(0, h * 0.72), maxf(1.1, h * 0.05), P.SUNFLOWER, true, -1.0, S.aa)
	for a in [-2.4, -1.57, -0.74]:
		S.fill_ink(ci, S.leaf(top + Vector2(0, 1), h * 0.34, h * 0.2, a + PI, 4), P.LEAF, P.INK, 1.2)
	S.line(ci, top + Vector2(-h * 0.2, h * 0.22), top + Vector2(-h * 0.14, h * 0.4), Color(1, 1, 1, 0.5), 2.0)


# ---------------------------------------------------------------- util

## Soften a polygon's corners (one Chaikin pass).
static func _round_poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := pts.size()
	for i in n:
		var a := pts[i]
		var b := pts[(i + 1) % n]
		out.append(a.lerp(b, 0.25))
		out.append(a.lerp(b, 0.75))
	return out
