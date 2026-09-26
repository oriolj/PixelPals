extends RefCounted
## Flat vector UI pieces, drawn with a CanvasItem's draw_* calls: paint pots,
## the easel, the gold frame, role and device icons, menu icons, sparkles and
## confetti. Every function takes the CanvasItem to draw on (`ci`) first.
## Sizes are in the 640x360 screen space.

const Palette := preload("res://scripts/paint/palette.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")

const WOOD := Color("#a0673c")
const WOOD_DARK := Color("#6e4526")
const WOOD_LIGHT := Color("#c98a55")
const FLOOR := Color("#333c57")
const WALL := Color("#f6ecd6")
const WALL_STRIPE := Color("#efe0c2")
const GOLD := Color("#f2c14e")
const GOLD_LIGHT := Color("#fff0a8")
const GOLD_DARK := Color("#a8741a")
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")
const GLASS := Color("#dfe9f0")


# ---------------------------------------------------------------- basics

static func ring(ci: CanvasItem, c: Vector2, r: float, col: Color, width := 2.0) -> void:
	ci.draw_arc(c, r, 0, TAU, maxi(24, int(r * 1.5)), col, width, true)


static func disc(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c, r, col, true, -1.0, true)


static func poly(ci: CanvasItem, pts: PackedVector2Array, col: Color) -> void:
	ci.draw_colored_polygon(pts, col)
	var loop := pts.duplicate()
	loop.append(pts[0])
	ci.draw_polyline(loop, col, 1.0, true)


static func rrect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	poly(ci, Shapes.rounded_rect(r, rad), col)


## Filled shape parts from Shapes (stamps, splats) scaled into screen space.
static func parts(ci: CanvasItem, list: Array, offset := Vector2.ZERO, scale := 1.0) -> void:
	for p in list:
		if p.has("pts"):
			var pts := PackedVector2Array()
			for v in p.pts:
				pts.append(offset + v * scale)
			poly(ci, pts, p.col)
		elif p.has("line"):
			var pts := PackedVector2Array()
			for v in p.line:
				pts.append(offset + v * scale)
			ci.draw_polyline(pts, p.col, maxf(1.0, p.width * scale), true)


# ---------------------------------------------------------------- room

static func wall(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, WALL)
	var x := r.position.x
	while x < r.end.x:
		ci.draw_rect(Rect2(x, r.position.y, 10, r.size.y), WALL_STRIPE)
		x += 28


static func floor_strip(ci: CanvasItem, r: Rect2) -> void:
	ci.draw_rect(r, FLOOR)
	ci.draw_rect(Rect2(r.position, Vector2(r.size.x, 3)), FLOOR.lightened(0.15))
	# a round rug in the middle
	var c := Vector2(r.get_center().x, r.position.y + r.size.y * 0.6)
	var rug := Shapes.ellipse(c, r.size.x * 0.34, r.size.y * 0.42, 48)
	poly(ci, rug, Color("#b13e53").darkened(0.2))
	poly(ci, Shapes.ellipse(c, r.size.x * 0.3, r.size.y * 0.3, 48), Color("#ef7d57").darkened(0.15))


## The easel: legs, a ledge and a wooden border around `canvas` (the paper).
static func easel(ci: CanvasItem, canvas: Rect2, floor_y: float) -> void:
	var b := canvas.grow(6)
	# legs behind the board
	for side in [-1.0, 1.0]:
		var top := Vector2(canvas.get_center().x + side * canvas.size.x * 0.3, b.position.y + 20)
		var foot := Vector2(canvas.get_center().x + side * canvas.size.x * 0.42, floor_y + 18)
		ci.draw_line(top, foot, WOOD_DARK, 9.0, true)
		ci.draw_line(top, foot, WOOD, 6.0, true)
	var back_top := Vector2(canvas.get_center().x, b.position.y - 8)
	ci.draw_line(back_top, Vector2(canvas.get_center().x, floor_y + 10), WOOD_DARK, 7.0, true)
	rrect(ci, b.grow(1), 4, WOOD_DARK)
	rrect(ci, b, 4, WOOD)
	ci.draw_rect(Rect2(b.position + Vector2(3, 2), Vector2(b.size.x - 6, 2)), WOOD_LIGHT)
	# the ledge under the paper, with a few brushes lying on it
	var ledge := Rect2(b.position.x - 6, b.end.y - 2, b.size.x + 12, 8)
	rrect(ci, ledge.grow(1), 3, WOOD_DARK)
	rrect(ci, ledge, 3, WOOD_LIGHT)
	for i in 3:
		var x := ledge.position.x + 40 + i * 22
		ci.draw_line(Vector2(x, ledge.position.y + 1), Vector2(x + 16, ledge.position.y - 1), WOOD_DARK, 2.0, true)
		disc(ci, Vector2(x + 17, ledge.position.y - 1), 2.2, Palette.COLORS[i * 4 + 1])
	# the clip holding the paper
	rrect(ci, Rect2(canvas.get_center().x - 14, b.position.y - 5, 28, 9), 3, Color("#94b0c2"))
	rrect(ci, Rect2(canvas.get_center().x - 10, b.position.y - 3, 20, 3), 1, WHITE)


## A gold frame around `inner` (the picture), `t` px thick, with a bevel made
## of vertex-colour gradients (light top-left, dark bottom-right).
static func gold_frame(ci: CanvasItem, inner: Rect2, t: float) -> void:
	var o := inner.grow(t)
	var i := inner
	var sides := [
		[o.position, Vector2(o.end.x, o.position.y), Vector2(i.end.x, i.position.y), i.position, GOLD_LIGHT],
		[Vector2(o.end.x, o.position.y), o.end, i.end, Vector2(i.end.x, i.position.y), GOLD],
		[o.end, Vector2(o.position.x, o.end.y), Vector2(i.position.x, i.end.y), i.end, GOLD_DARK],
		[Vector2(o.position.x, o.end.y), o.position, i.position, Vector2(i.position.x, i.end.y), GOLD.lerp(GOLD_LIGHT, 0.5)],
	]
	for s in sides:
		var outer_col: Color = s[4]
		var inner_col := outer_col.darkened(0.25)
		ci.draw_polygon(PackedVector2Array([s[0], s[1], s[2], s[3]]),
			PackedColorArray([outer_col, outer_col, inner_col, inner_col]))
	# a raised middle bead and a thin inner lip
	var mid := inner.grow(t * 0.5)
	ci.draw_rect(mid, GOLD_LIGHT.lerp(GOLD, 0.4), false, maxf(1.0, t * 0.16), true)
	ci.draw_rect(inner.grow(1), GOLD_DARK.darkened(0.3), false, 2.0, true)
	ci.draw_rect(o, GOLD_DARK.darkened(0.2), false, 1.5, true)
	# corner rosettes
	for p in [o.position, Vector2(o.end.x, o.position.y), o.end, Vector2(o.position.x, o.end.y)]:
		var q: Vector2 = p + (inner.get_center() - p).normalized() * t * 0.75
		disc(ci, q, t * 0.34, GOLD_LIGHT)
		disc(ci, q, t * 0.18, GOLD_DARK)


# ---------------------------------------------------------------- pots

## A paint pot: a glass jar with paint inside and a blob on the rim.
## `s` = scale (1 = about 28x30 px).
static func pot(ci: CanvasItem, c: Vector2, col: Color, s := 1.0) -> void:
	var w := 26.0 * s
	var h := 26.0 * s
	var body := Rect2(c.x - w / 2, c.y - h / 2 + 3 * s, w, h)
	# shadow
	poly(ci, Shapes.ellipse(Vector2(c.x, body.end.y + 1), w * 0.55, 3.5 * s, 20), Color(0, 0, 0, 0.18))
	rrect(ci, body.grow(1.5), 6 * s, INK.lerp(col, 0.25))
	rrect(ci, body, 6 * s, GLASS)
	var paint := Rect2(body.position.x, body.position.y + h * 0.28, w, h * 0.72)
	rrect(ci, paint, 6 * s, col)
	# shine
	ci.draw_line(Vector2(body.position.x + 5 * s, body.position.y + 6 * s),
		Vector2(body.position.x + 5 * s, body.end.y - 7 * s), Color(1, 1, 1, 0.55), 2.5 * s, true)
	# rim
	var rim := Rect2(body.position.x - 2 * s, body.position.y - 3 * s, w + 4 * s, 6 * s)
	rrect(ci, rim.grow(1), 3 * s, INK.lerp(col, 0.25))
	rrect(ci, rim, 3 * s, Color("#94b0c2"))
	# paint blob spilling over the rim
	disc(ci, Vector2(c.x + 4 * s, rim.position.y + 2 * s), 5 * s, col)
	disc(ci, Vector2(c.x - 3 * s, rim.position.y + 3 * s), 4 * s, col)
	var drip := Vector2(rim.end.x - 3 * s, rim.end.y)
	ci.draw_line(drip, drip + Vector2(0, 7 * s), col, 3.5 * s, true)
	disc(ci, drip + Vector2(0, 7 * s), 2.3 * s, col)


# ---------------------------------------------------------------- icons

## A paintbrush pointing up-right, bristles dipped in `col`.
static func icon_brush(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var d := Vector2(1, -1).normalized()
	var n := Vector2(-d.y, d.x)
	var tail := c - d * s * 0.5
	var ferrule := c + d * s * 0.1
	var tip := c + d * s * 0.5
	ci.draw_line(tail, ferrule, WOOD_DARK, s * 0.2, true)
	ci.draw_line(tail, ferrule, WOOD, s * 0.13, true)
	poly(ci, PackedVector2Array([ferrule + n * s * 0.1, ferrule - n * s * 0.1,
		ferrule + d * s * 0.14 - n * s * 0.11, ferrule + d * s * 0.14 + n * s * 0.11]), Color("#94b0c2"))
	var base := ferrule + d * s * 0.13
	poly(ci, PackedVector2Array([base + n * s * 0.12, base - n * s * 0.12, tip]), col)


## An artist's palette with four blobs.
static func icon_palette(ci: CanvasItem, c: Vector2, s: float) -> void:
	var pts := Shapes.ellipse(c, s * 0.5, s * 0.38, 36)
	poly(ci, Shapes.ellipse(c + Vector2(1, 1.5), s * 0.5, s * 0.38, 36), WOOD_DARK)
	poly(ci, pts, WOOD_LIGHT)
	disc(ci, c + Vector2(s * 0.2, s * 0.12), s * 0.09, WOOD_DARK)  # thumb hole
	var cols := [Palette.COLORS[1], Palette.COLORS[2], Palette.COLORS[0], Palette.COLORS[3]]
	for i in 4:
		var a := PI + 0.35 + i * 0.62
		disc(ci, c + Vector2(cos(a) * s * 0.3, sin(a) * s * 0.22) + Vector2(s * 0.04, 0), s * 0.1, cols[i])


static func icon_splat(ci: CanvasItem, c: Vector2, s: float, col: Color, seed_value := 7) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var parts_list := Shapes.splat(c, s * 0.3, [col], rng)
	parts(ci, parts_list)


static func icon_pad(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	rrect(ci, Rect2(c - Vector2(s * 0.5, s * 0.28), Vector2(s, s * 0.56)), s * 0.24, col)
	var dark := col.darkened(0.55)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.34, -s * 0.04), Vector2(s * 0.2, s * 0.07)), dark)
	ci.draw_rect(Rect2(c + Vector2(-s * 0.275, -s * 0.11), Vector2(s * 0.07, s * 0.21)), dark)
	disc(ci, c + Vector2(s * 0.22, -s * 0.07), s * 0.06, Palette.COLORS[1])
	disc(ci, c + Vector2(s * 0.33, s * 0.04), s * 0.06, Palette.COLORS[3])


static func icon_kb(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	rrect(ci, Rect2(c - Vector2(s * 0.52, s * 0.3), Vector2(s * 1.04, s * 0.6)), s * 0.08, col.darkened(0.45))
	for row in 3:
		for k in 5:
			var w := s * 0.14
			var x := c.x - s * 0.44 + k * s * 0.18
			var y := c.y - s * 0.22 + row * s * 0.16
			if row == 2 and k > 0:
				if k == 1:
					ci.draw_rect(Rect2(x, y, s * 0.68, s * 0.11), col)
				continue
			ci.draw_rect(Rect2(x, y, w, s * 0.11), col)


static func icon_check(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array([c + Vector2(-0.35, 0.0) * s, c + Vector2(-0.1, 0.25) * s, c + Vector2(0.38, -0.28) * s])
	ci.draw_polyline(pts, col.darkened(0.4), s * 0.22, true)
	ci.draw_polyline(pts, col, s * 0.14, true)


static func arrow(ci: CanvasItem, c: Vector2, s: float, dir: Vector2, col: Color) -> void:
	var d := dir.normalized()
	var n := Vector2(-d.y, d.x)
	poly(ci, PackedVector2Array([c + d * s * 0.5, c - d * s * 0.3 + n * s * 0.45, c - d * s * 0.3 - n * s * 0.45]), col)


## Undo: a curved arrow turning back to the left.
static func icon_undo(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 17:
		var a := lerpf(-PI * 0.95, PI * 0.35, i / 16.0)
		pts.append(c + Vector2(cos(a), sin(a)) * s * 0.3 + Vector2(s * 0.05, s * 0.05))
	ci.draw_polyline(pts, col.darkened(0.35), s * 0.17, true)
	ci.draw_polyline(pts, col, s * 0.11, true)
	var tip := pts[0]
	arrow(ci, tip + Vector2(0, s * 0.04), s * 0.34, Vector2(0.15, 1), col)


static func icon_play(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	poly(ci, PackedVector2Array([c + Vector2(-0.25, -0.33) * s, c + Vector2(0.36, 0) * s, c + Vector2(-0.25, 0.33) * s]),
		col.darkened(0.3))
	poly(ci, PackedVector2Array([c + Vector2(-0.2, -0.26) * s, c + Vector2(0.28, 0) * s, c + Vector2(-0.2, 0.26) * s]), col)


## Back to join: a door with an arrow going out to the left.
static func icon_back(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	rrect(ci, Rect2(c + Vector2(-0.02, -0.4) * s, Vector2(0.4, 0.8) * s), s * 0.05, WOOD_DARK)
	rrect(ci, Rect2(c + Vector2(0.03, -0.35) * s, Vector2(0.3, 0.7) * s), s * 0.04, WOOD)
	disc(ci, c + Vector2(0.09, 0.02) * s, s * 0.035, GOLD)
	ci.draw_line(c + Vector2(0.0, 0.0) * s, c + Vector2(-0.3, 0.0) * s, col, s * 0.12, true)
	arrow(ci, c + Vector2(-0.34, 0) * s, s * 0.34, Vector2.LEFT, col)


## A tiny framed picture (the "frame it" button).
static func icon_frame(ci: CanvasItem, c: Vector2, s: float) -> void:
	var inner := Rect2(c - Vector2(s * 0.34, s * 0.24), Vector2(s * 0.68, s * 0.48))
	ci.draw_rect(inner, Palette.PAPER)
	# a tiny landscape: sun, hill, house
	poly(ci, Shapes.ellipse(Vector2(inner.get_center().x, inner.end.y + s * 0.08), s * 0.42, s * 0.2, 24), Palette.COLORS[3])
	disc(ci, inner.position + Vector2(s * 0.14, s * 0.13), s * 0.08, Palette.COLORS[2])
	ci.draw_rect(Rect2(inner.position + Vector2(s * 0.36, s * 0.2), Vector2(s * 0.16, s * 0.14)), Palette.COLORS[1])
	poly(ci, PackedVector2Array([inner.position + Vector2(s * 0.33, s * 0.21), inner.position + Vector2(s * 0.44, s * 0.1),
		inner.position + Vector2(s * 0.55, s * 0.21)]), Palette.COLORS[0])
	gold_frame(ci, inner, maxf(3.0, s * 0.12))


## A four-point twinkle.
static func sparkle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	poly(ci, PackedVector2Array([c + Vector2(0, -s), c + Vector2(s * 0.22, -s * 0.22), c + Vector2(s, 0),
		c + Vector2(s * 0.22, s * 0.22), c + Vector2(0, s), c + Vector2(-s * 0.22, s * 0.22), c + Vector2(-s, 0),
		c + Vector2(-s * 0.22, -s * 0.22)]), col)


## The brush-size dot: three sizes, the current one ringed.
static func size_dots(ci: CanvasItem, c: Vector2, current: int, col: Color) -> void:
	var radii := [2.5, 4.5, 7.0]
	for i in 3:
		var p := c + Vector2((i - 1) * 18, 0)
		disc(ci, p, radii[i], col if i == current else col.lerp(WALL, 0.6))
		if i == current:
			ring(ci, p, radii[i] + 3.0, INK, 1.5)
