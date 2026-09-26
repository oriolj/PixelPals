extends RefCounted
## Vector icons for the menus: the seat roles (throttle lever, junction sign,
## whistle), the devices (pad, keyboard), arrows and the ready tick.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")

const ROLES := ["lever", "sign", "whistle"]


static func role(ci: CanvasItem, seat: int, c: Vector2, s: float, col: Color) -> void:
	match seat:
		0:
			lever(ci, c, s, col)
		1:
			junction_sign(ci, c, s, col)
		_:
			whistle(ci, c, s, col)


## Throttle lever: a base box and a handle with a red knob.
static func lever(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(c + Vector2(-26, 8) * s, Vector2(52, 22) * s), 7 * s), col, 3.0)
	var tip := c + Vector2(16, -26) * s
	ci.draw_line(c + Vector2(-4, 12) * s, tip, Palette.INK, 9.0 * s)
	ci.draw_line(c + Vector2(-4, 12) * s, tip, Palette.ROCK, 5.0 * s)
	Shapes.fill_outline(ci, Shapes.circle(tip, 9 * s, 18), Palette.STATION[0], 3.0)


## Junction sign: a round board with a bent arrow on a post.
static func junction_sign(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_line(c + Vector2(0, 10) * s, c + Vector2(0, 34) * s, Palette.INK, 8.0 * s)
	ci.draw_line(c + Vector2(0, 10) * s, c + Vector2(0, 34) * s, Palette.TRACK, 4.0 * s)
	Shapes.fill_outline(ci, Shapes.circle(c + Vector2(0, -6) * s, 24 * s, 28), col, 3.0)
	var arrow := Shapes.xform(Shapes.arrow(34 * s, 9 * s, 20 * s), Transform2D(-0.6, c + Vector2(0, -6) * s))
	Shapes.fill_outline(ci, arrow, Palette.BLACK, 2.0)


## Steam whistle: a brass body with a puff.
static func whistle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	c += Vector2(0, 8) * s
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(c + Vector2(-10, -14) * s, Vector2(20, 40) * s), 6 * s), col, 3.0)
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(c + Vector2(-16, 20) * s, Vector2(32, 10) * s), 4 * s), Palette.STATION[2], 3.0)
	ci.draw_line(c + Vector2(-10, 0) * s, c + Vector2(10, 0) * s, Palette.INK, 3.0 * s)
	for k in 3:
		Shapes.fill_outline(ci, Shapes.circle(c + Vector2(-8 + k * 10, -28 - k * 6) * s, (7 + k * 2) * s, 16), Palette.WHITE, 2.0)


static func pad(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(c + Vector2(-30, -16) * s, Vector2(60, 32) * s), 14 * s), col, 3.0)
	ci.draw_line(c + Vector2(-20, 0) * s, c + Vector2(-8, 0) * s, Palette.INK, 4.0 * s)
	ci.draw_line(c + Vector2(-14, -6) * s, c + Vector2(-14, 6) * s, Palette.INK, 4.0 * s)
	ci.draw_circle(c + Vector2(12, -4) * s, 4 * s, Palette.STATION[0])
	ci.draw_circle(c + Vector2(20, 4) * s, 4 * s, Palette.STATION[3])


static func keyboard(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	Shapes.fill_outline(ci, Shapes.rounded_rect(Rect2(c + Vector2(-32, -16) * s, Vector2(64, 32) * s), 5 * s), col, 3.0)
	for row in 2:
		for k in 5:
			ci.draw_rect(Rect2(c + Vector2(-26 + k * 11, -10 + row * 10) * s, Vector2(8, 7) * s), Palette.INK)
	ci.draw_rect(Rect2(c + Vector2(-18, 10) * s, Vector2(36, 4) * s), Palette.INK)


## Left/right arrow (dir = -1 or 1).
static func side_arrow(ci: CanvasItem, c: Vector2, s: float, dir: int, col: Color) -> void:
	var tri := PackedVector2Array([c + Vector2(-10 * dir, -16) * s, c + Vector2(14 * dir, 0) * s, c + Vector2(-10 * dir, 16) * s])
	Shapes.fill_outline(ci, tri, col, 3.0)


static func check(ci: CanvasItem, c: Vector2, s: float) -> void:
	Shapes.fill_outline(ci, Shapes.circle(c, 22 * s, 24), Palette.STATION[3], 3.0)
	ci.draw_polyline(PackedVector2Array([c + Vector2(-11, 0) * s, c + Vector2(-3, 9) * s, c + Vector2(12, -9) * s]), Palette.WHITE, 6.0 * s)


## Sky, far hills, grass and a straight wooden track: the menus' backdrop.
static func backdrop(ci: CanvasItem, t: float, clouds := true) -> void:
	ci.draw_rect(Rect2(0, 0, 1280, 720), Palette.SKY)
	ci.draw_rect(Rect2(0, 0, 1280, 160), Palette.SKY.lightened(0.15))
	if clouds:
		for i in 5:
			var x := fposmod(i * 300.0 - t * (12.0 + i * 3.0), 1500.0) - 150.0
			var y := 60.0 + (i * 53) % 150
			for k in 3:
				ci.draw_circle(Vector2(x + k * 34, y - (12 if k == 1 else 0)), 30.0 if k == 1 else 24.0, Color(Palette.WHITE, 0.9))
	for i in 7:
		var cx := i * 220.0 - 40.0
		ci.draw_colored_polygon(Shapes.ellipse(Vector2(cx, 560), 190, 110, 32), Palette.GRASS_DARK if i % 2 == 0 else Palette.GRASS_DARK.lightened(0.1))
	ci.draw_rect(Rect2(0, 540, 1280, 180), Palette.GRASS)
	for i in 40:
		var p := Vector2((i * 97) % 1280, 560 + (i * 41) % 150)
		ci.draw_circle(p, 3.0, [Palette.PINK, Palette.WHITE, Palette.GLOW][i % 3])
