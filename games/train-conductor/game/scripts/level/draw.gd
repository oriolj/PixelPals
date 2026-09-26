extends RefCounted
## Drawing recipes shared by the level, select and party screens: passengers,
## houses, trees, station tokens. All vector, all with the 2 px ink outline.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const INK := Palette.INK


## A station token: the colour's shape in the colour, outlined.
static func token(ci: CanvasItem, colour: int, c: Vector2, r: float, fill := Color(), width := 2.0) -> void:
	var col: Color = Palette.station(colour) if fill == Color() else fill
	Shapes.fill_outline(ci, Shapes.token(Palette.SHAPES[colour], c, r), col, width)


## A passenger, front view, feet at `feet`: body in the colour of the station
## they want, a cream face with dot eyes, and a hat in that station's shape.
## `hop` lifts them, `wave` raises an arm.
static func passenger(ci: CanvasItem, feet: Vector2, colour: int, s := 1.0, hop := 0.0, wave := 0.0, happy := false) -> void:
	var col: Color = Palette.station(colour)
	var p := feet + Vector2(0, -hop)
	# Shadow stays on the ground.
	ci.draw_colored_polygon(Shapes.ellipse(feet + Vector2(0, 1) * s, 10 * s, 4 * s, 14), Color(INK, 0.22))
	# Legs.
	ci.draw_line(p + Vector2(-4, -8) * s, p + Vector2(-4, -1) * s, INK, 3.0 * s)
	ci.draw_line(p + Vector2(4, -8) * s, p + Vector2(4, -1) * s, INK, 3.0 * s)
	# Arms (one waves).
	var arm_l := p + Vector2(-13, -12 - 8 * wave) * s
	ci.draw_line(p + Vector2(-8, -17) * s, arm_l, INK, 3.0 * s)
	ci.draw_line(p + Vector2(8, -17) * s, p + Vector2(12, -9) * s, INK, 3.0 * s)
	# Body.
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(p + Vector2(-9, -24) * s, Vector2(18, 17) * s), 7 * s), col, 2.0)
	# Head.
	var head := p + Vector2(0, -31) * s
	Shapes.fill_outline(ci, Shapes.circle(head, 8.5 * s, 20), Palette.CREAM, 2.0)
	ci.draw_circle(head + Vector2(-3, -0.5) * s, 1.5 * s, INK)
	ci.draw_circle(head + Vector2(3, -0.5) * s, 1.5 * s, INK)
	if happy:
		ci.draw_arc(head + Vector2(0, 1.5) * s, 3.5 * s, 0.3, PI - 0.3, 8, INK, 1.5 * s)
	else:
		ci.draw_arc(head + Vector2(0, 2) * s, 2.5 * s, 0.4, PI - 0.4, 6, INK, 1.2 * s)
	# Hat in the station's shape.
	hat(ci, colour, head + Vector2(0, -9.5) * s, 7.5 * s)


static func hat(ci: CanvasItem, colour: int, c: Vector2, r: float) -> void:
	token(ci, colour, c, r)


## A passenger head seen in a round window (aboard a carriage).
static func head(ci: CanvasItem, c: Vector2, colour: int, s := 1.0) -> void:
	Shapes.fill_outline(ci, Shapes.circle(c + Vector2(0, 3) * s, 8 * s, 18), Palette.CREAM, 1.5)
	ci.draw_circle(c + Vector2(-2.8, 2.5) * s, 1.4 * s, INK)
	ci.draw_circle(c + Vector2(2.8, 2.5) * s, 1.4 * s, INK)
	token(ci, colour, c + Vector2(0, -6) * s, 6.5 * s, Color(), 1.5)


## A little house: body, roof in the station colour, a window that lights up.
static func house(ci: CanvasItem, c: Vector2, colour: int, lit: bool, s := 1.0) -> void:
	var col: Color = Palette.station(colour)
	var body := Rect2(c + Vector2(-16, -10) * s, Vector2(32, 26) * s)
	ci.draw_colored_polygon(Shapes.ellipse(c + Vector2(3, 17) * s, 20 * s, 5 * s, 16), Color(INK, 0.2))
	Shapes.fill_outline(ci, Shapes.rounded_rect(body, 3 * s), Palette.CREAM)
	var roof := PackedVector2Array([c + Vector2(-21, -8) * s, c + Vector2(0, -26) * s, c + Vector2(21, -8) * s])
	Shapes.fill_outline(ci, roof, col)
	var win := Rect2(c + Vector2(-11, -3) * s, Vector2(10, 9) * s)
	Shapes.fill_outline(ci, Shapes.rounded_rect(win, 2 * s), Palette.GLOW if lit else Palette.BLACK.lightened(0.25), 1.5)
	var door := Rect2(c + Vector2(3, 1) * s, Vector2(8, 15) * s)
	Shapes.fill_outline(ci, Shapes.rounded_rect(door, 2 * s), col.darkened(0.25), 1.5)


## A round tree seen from above, with its shadow.
static func tree(ci: CanvasItem, c: Vector2, r: float, tint := 0.0) -> void:
	ci.draw_colored_polygon(Shapes.circle(c + Vector2(r * 0.35, r * 0.45), r, 20), Color(INK, 0.18))
	var leaf: Color = Palette.LEAF.lerp(Palette.GRASS_DARK, tint)
	Shapes.fill_outline(ci, Shapes.circle(c, r, 22), leaf)
	ci.draw_colored_polygon(Shapes.circle(c + Vector2(-r * 0.25, -r * 0.3), r * 0.55, 16), Palette.LEAF_LIGHT.lerp(leaf, 0.3))
	ci.draw_circle(c + Vector2(-r * 0.35, -r * 0.4), r * 0.18, Color(Palette.WHITE, 0.35))


## A wooden fence run between two points.
static func fence(ci: CanvasItem, a: Vector2, b: Vector2) -> void:
	var n := maxi(1, int(a.distance_to(b) / 28.0))
	ci.draw_line(a + Vector2(0, -6), b + Vector2(0, -6), INK, 6.0)
	ci.draw_line(a + Vector2(0, -6), b + Vector2(0, -6), Palette.TRACK_LIGHT, 3.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(p + Vector2(-4, -14), Vector2(8, 16)), 2), Palette.TRACK)
