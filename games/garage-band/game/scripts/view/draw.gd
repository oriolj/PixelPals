extends RefCounted
## Vector drawing helpers shared by every screen: the Sweetie 16 palette and
## the instruments, icons and album covers, drawn with CanvasItem draw calls
## (no textures, no text). Call them from a node's _draw(): Draw.star(self, ...).

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
const DARK := Color("#333c57")
## Derived shades (still Sweetie 16 hues).
const WOOD := Color("#834530")   # ORANGE darkened 45 %
const PINK := Color("#dca8b2")   # RED lightened 55 %

## The Lead's lanes, low to high.
const LANE_COLORS: Array[Color] = [RED, ORANGE, YELLOW, LIME, CYAN]
## Drum pads: hat (up), snare (left), tom (right), kick (down).
const PAD_COLORS: Array[Color] = [YELLOW, SKY, LIME, RED]
const PAD_DIRS: Array[Vector2] = [Vector2(0, -1), Vector2(-1, 0), Vector2(1, 0), Vector2(0, 1)]
## Stage-light colour sets, one per crash.
const LIGHT_SETS := [
	[YELLOW, CYAN, RED, LIME],
	[CYAN, RED, LIME, YELLOW],
	[RED, LIME, YELLOW, CYAN],
	[LIME, YELLOW, CYAN, RED],
]


static func circle_pts(c: Vector2, r: float, n := 24, sx := 1.0, sy := 1.0, rot := 0.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in n:
		var a := TAU * i / n
		pts.append(c + Vector2(cos(a) * r * sx, sin(a) * r * sy).rotated(rot))
	return pts


static func ellipse(ci: CanvasItem, c: Vector2, rx: float, ry: float, col: Color, rot := 0.0) -> void:
	ci.draw_colored_polygon(circle_pts(c, 1.0, 28, rx, ry, rot), col)


static func ngon(ci: CanvasItem, c: Vector2, r: float, n: int, col: Color, rot := 0.0) -> void:
	ci.draw_colored_polygon(circle_pts(c, r, n, 1.0, 1.0, rot), col)


static func star_pts(c: Vector2, r: float, rot := 0.0, inner := 0.45, points := 5) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in points * 2:
		var a := rot - PI / 2 + PI * i / points
		var rr := r if i % 2 == 0 else r * inner
		pts.append(c + Vector2(cos(a), sin(a)) * rr)
	return pts


static func star(ci: CanvasItem, c: Vector2, r: float, col: Color, rot := 0.0) -> void:
	ci.draw_colored_polygon(star_pts(c, r, rot), col)


## A rounded rectangle as one polygon (so translucent fills do not double up).
static func round_rect(ci: CanvasItem, r: Rect2, rad: float, col: Color) -> void:
	if r.size.x < 1.0 or r.size.y < 1.0:
		return
	# Too small to round (corners would coincide and fail to triangulate).
	if minf(r.size.x, r.size.y) < 2.0 * rad + 2.0:
		rad = minf(r.size.x, r.size.y) / 2.0 - 1.0
		if rad < 1.0:
			ci.draw_rect(r, col)
			return
	ci.draw_colored_polygon(round_rect_pts(r, rad), col)


static func round_rect_pts(r: Rect2, rad: float) -> PackedVector2Array:
	rad = minf(rad, minf(r.size.x, r.size.y) / 2.0)
	var pts := PackedVector2Array()
	var corners := [[r.end - Vector2(rad, rad), 0.0], [Vector2(r.position.x + rad, r.end.y - rad), PI / 2],
		[r.position + Vector2(rad, rad), PI], [Vector2(r.end.x - rad, r.position.y + rad), PI * 1.5]]
	for c in corners:
		for k in 7:
			var a: float = c[1] + PI / 2 * k / 6.0
			pts.append(c[0] + Vector2(cos(a), sin(a)) * rad)
	return pts


## A seat-coloured panel: a rounded frame with a dark translucent inside.
static func panel(ci: CanvasItem, r: Rect2, col: Color, lit := true) -> void:
	round_rect(ci, r, 10, col if lit else col.darkened(0.45))
	round_rect(ci, r.grow(-3), 8, Color(INK, 0.82))


# ---------------------------------------------------------------- instruments

## Electric guitar: body, neck, headstock and strings. `c` is the body centre.
static func guitar(ci: CanvasItem, c: Vector2, s: float, rot: float, body := ORANGE) -> void:
	var t := Transform2D(rot, c)
	ci.draw_set_transform_matrix(t)
	# Neck and headstock.
	ci.draw_rect(Rect2(Vector2(4, -2.5) * s, Vector2(26, 5) * s), WOOD)
	for k in 4:
		ci.draw_rect(Rect2(Vector2(9 + k * 5, -2.5) * s, Vector2(0.8, 5) * s), YELLOW)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(29, -4) * s, Vector2(37, -5) * s,
		Vector2(37, 5) * s, Vector2(29, 4) * s]), DARK)
	# Body: two lobes and a waist.
	ci.draw_circle(Vector2(-7, 0) * s, 9 * s, body)
	ci.draw_circle(Vector2(2, 0) * s, 7 * s, body)
	ci.draw_circle(Vector2(-7, 0) * s, 9 * s, body.darkened(0.25), false, 1.2 * s)
	ci.draw_rect(Rect2(Vector2(-11, -1.6) * s, Vector2(5, 3.2) * s), INK)
	ci.draw_circle(Vector2(0, 0) * s, 3 * s, INK)
	for k in 3:
		ci.draw_line(Vector2(-12, -1 + k) * s, Vector2(34, -1 + k) * s, Color(WHITE, 0.7), 0.4 * s)
	ci.draw_set_transform_matrix(Transform2D())


## A drum seen from the front-top: shell plus an elliptical head. squash 0..1.
static func drum(ci: CanvasItem, c: Vector2, w: float, h: float, shell: Color, squash := 0.0) -> void:
	var sy := 1.0 - 0.1 * squash
	var sx := 1.0 + 0.06 * squash
	var hw := w * 0.5 * sx
	var top := c.y - h * 0.5 * sy
	ci.draw_rect(Rect2(c.x - hw, top, hw * 2, h * sy), shell)
	ellipse(ci, Vector2(c.x, c.y + h * 0.5 * sy), hw, w * 0.16, shell.darkened(0.3))
	ci.draw_rect(Rect2(c.x - hw, top + h * sy * 0.45, hw * 2, 2), Color(WHITE, 0.5))
	ellipse(ci, Vector2(c.x, top), hw, w * 0.18, WHITE.darkened(0.08))
	ellipse(ci, Vector2(c.x, top), hw * 0.8, w * 0.13, WHITE)


## Kick drum from the front: a big round head with a coloured ring.
static func kick_drum(ci: CanvasItem, c: Vector2, r: float, ring: Color, squash := 0.0) -> void:
	var sx := 1.0 + 0.1 * squash
	var sy := 1.0 - 0.1 * squash
	ellipse(ci, c, r * sx, r * sy, ring)
	ellipse(ci, c, r * 0.84 * sx, r * 0.84 * sy, WHITE)
	star(ci, c, r * 0.45, ring)
	# Little feet.
	ci.draw_line(c + Vector2(-r * 0.7, r * 0.6), c + Vector2(-r, r * 1.05), GREY, 2.0)
	ci.draw_line(c + Vector2(r * 0.7, r * 0.6), c + Vector2(r, r * 1.05), GREY, 2.0)


## A cymbal on a stand. tilt wobbles it.
static func cymbal(ci: CanvasItem, top: Vector2, r: float, tilt: float, col := YELLOW, stand_h := 40.0) -> void:
	ci.draw_line(top, top + Vector2(0, stand_h), GREY, 2.0)
	ci.draw_line(top + Vector2(0, stand_h), top + Vector2(-8, stand_h + 6), GREY, 2.0)
	ci.draw_line(top + Vector2(0, stand_h), top + Vector2(8, stand_h + 6), GREY, 2.0)
	ellipse(ci, top, r, r * 0.28, col.darkened(0.2), tilt)
	ellipse(ci, top + Vector2(0, -1), r * 0.92, r * 0.2, col, tilt)
	ellipse(ci, top + Vector2(0, -1), r * 0.25, r * 0.1, col.lightened(0.4), tilt)


static func gong(ci: CanvasItem, c: Vector2, r: float, tilt: float) -> void:
	# Frame, cords, then the gong swinging.
	ci.draw_line(c + Vector2(-r - 8, r + 14), c + Vector2(-r - 8, -r - 10), WOOD, 3.0)
	ci.draw_line(c + Vector2(r + 8, r + 14), c + Vector2(r + 8, -r - 10), WOOD, 3.0)
	ci.draw_line(c + Vector2(-r - 10, -r - 10), c + Vector2(r + 10, -r - 10), WOOD, 3.0)
	var g := c + Vector2(sin(tilt) * 4.0, 0)
	ci.draw_line(c + Vector2(-r * 0.5, -r - 10), g + Vector2(-r * 0.4, -r * 0.9), GREY, 1.0)
	ci.draw_line(c + Vector2(r * 0.5, -r - 10), g + Vector2(r * 0.4, -r * 0.9), GREY, 1.0)
	ci.draw_circle(g, r, ORANGE.darkened(0.15))
	ci.draw_circle(g, r * 0.82, ORANGE)
	ci.draw_circle(g, r * 0.35, YELLOW)
	ci.draw_circle(g, r * 0.82, Color(YELLOW, 0.6), false, 1.0)


static func cowbell(ci: CanvasItem, c: Vector2, s: float, tilt: float) -> void:
	var t := Transform2D(tilt, c)
	ci.draw_set_transform_matrix(t)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-6, -10) * s, Vector2(6, -10) * s,
		Vector2(11, 10) * s, Vector2(-11, 10) * s]), GREY)
	ci.draw_colored_polygon(PackedVector2Array([Vector2(-3, -9) * s, Vector2(0, -9) * s,
		Vector2(1, 9) * s, Vector2(-6, 9) * s]), WHITE)
	ci.draw_rect(Rect2(Vector2(-11, 8) * s, Vector2(22, 3) * s), SLATE)
	ci.draw_line(Vector2(0, -10) * s, Vector2(0, -16) * s, SLATE, 2.0 * s)
	ci.draw_set_transform_matrix(Transform2D())


## The whoosh: a swirl of wind with three chime bars.
static func whoosh(ci: CanvasItem, c: Vector2, s: float, phase: float) -> void:
	for k in 3:
		var y := (k - 1) * 8.0 * s
		var pts := PackedVector2Array()
		for i in 13:
			var x := (i - 6) * 3.0 * s
			pts.append(c + Vector2(x, y + sin(i * 0.7 + phase + k) * 3.0 * s))
		ci.draw_polyline(pts, [CYAN, WHITE, SKY][k], 2.5 * s)
	for k in 3:
		ci.draw_rect(Rect2(c + Vector2(-8 + k * 7, 14) * s, Vector2(4, 10 + k * 4) * s), [YELLOW, LIME, CYAN][k])


## The crash instrument by sound index: 0 cymbal, 1 gong, 2 cowbell, 3 whoosh.
static func crash_instrument(ci: CanvasItem, idx: int, c: Vector2, s: float, wobble: float, t: float) -> void:
	match idx:
		0:
			cymbal(ci, c + Vector2(0, -10 * s), 22 * s, wobble * 0.5, YELLOW, 34 * s)
		1:
			gong(ci, c, 18 * s, wobble * 3.0)
		2:
			cowbell(ci, c, 1.4 * s, wobble * 0.6)
		_:
			whoosh(ci, c + Vector2(0, -6 * s), s, t * 6.0 + wobble * 4.0)


## Two crossed drumsticks (count-in, drummer icon).
static func sticks(ci: CanvasItem, c: Vector2, s: float, col := YELLOW) -> void:
	for sgn in [-1.0, 1.0]:
		var a := c + Vector2(-10 * sgn, 10) * s
		var b := c + Vector2(10 * sgn, -10) * s
		ci.draw_line(a, b, col.darkened(0.3), 4.0 * s)
		ci.draw_line(a, b, col, 2.4 * s)
		ci.draw_circle(b, 2.6 * s, WHITE)


## A music note (eighth note).
static func note(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ellipse(ci, c, 5 * s, 3.8 * s, col, -0.35)
	ci.draw_rect(Rect2(c + Vector2(3.2, -16) * s, Vector2(2, 16) * s), col)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(5.2, -16) * s, c + Vector2(11, -11) * s,
		c + Vector2(10, -8) * s, c + Vector2(5.2, -12) * s]), col)


# ---------------------------------------------------------------- icons

## Role icons for the three seats: guitar, drum, cymbal.
static func role_icon(ci: CanvasItem, seat: int, c: Vector2, s: float, t := 0.0) -> void:
	match seat:
		0:
			guitar(ci, c + Vector2(-4, 4) * s, s * 0.9, -0.6)
		1:
			drum(ci, c + Vector2(0, 4) * s, 26 * s, 14 * s, RED)
			sticks(ci, c + Vector2(0, -10) * s, s * 0.6)
		_:
			cymbal(ci, c + Vector2(0, -6) * s, 16 * s, sin(t * 3.0) * 0.15, YELLOW, 20 * s)


static func gamepad(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	round_rect(ci, Rect2(c + Vector2(-14, -8) * s, Vector2(28, 16) * s), 7 * s, col)
	ci.draw_circle(c + Vector2(-12, 6) * s, 5 * s, col)
	ci.draw_circle(c + Vector2(12, 6) * s, 5 * s, col)
	ci.draw_rect(Rect2(c + Vector2(-10, -1.5) * s, Vector2(8, 3) * s), INK)
	ci.draw_rect(Rect2(c + Vector2(-7.5, -4) * s, Vector2(3, 8) * s), INK)
	ci.draw_circle(c + Vector2(7, -2) * s, 1.8 * s, INK)
	ci.draw_circle(c + Vector2(10.5, 1.5) * s, 1.8 * s, INK)


static func keyboard(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	round_rect(ci, Rect2(c + Vector2(-16, -9) * s, Vector2(32, 18) * s), 3 * s, col)
	for row in 3:
		for k in 6 - row:
			ci.draw_rect(Rect2(c + Vector2(-13 + k * 4.4 + row * 2, -6 + row * 4.5) * s, Vector2(3.2, 3.2) * s), INK)


static func arrow(ci: CanvasItem, c: Vector2, s: float, dir: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-5 * dir, -8) * s, c + Vector2(6 * dir, 0) * s,
		c + Vector2(-5 * dir, 8) * s]), col)


static func check(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_polyline(PackedVector2Array([c + Vector2(-7, 0) * s, c + Vector2(-2, 5) * s, c + Vector2(8, -6) * s]),
		col, 3.5 * s)


static func play_triangle(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -11) * s, c + Vector2(11, 0) * s,
		c + Vector2(-8, 11) * s]), col)


static func back_arrow(ci: CanvasItem, c: Vector2, s: float, col: Color) -> void:
	ci.draw_arc(c + Vector2(2, 2) * s, 8 * s, -PI * 0.9, PI * 0.5, 16, col, 3.5 * s)
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-12, -2) * s, c + Vector2(-2, -8) * s,
		c + Vector2(-3, 4) * s]), col)


# ---------------------------------------------------------------- covers

## A song's album cover, 1.0 = 64x64. `t` animates it gently.
static func cover(ci: CanvasItem, id: String, r: Rect2, t := 0.0) -> void:
	var c := r.get_center()
	var s := r.size.x / 64.0
	match id:
		"sun":
			round_rect(ci, r, 6 * s, SKY)
			ci.draw_rect(Rect2(r.position.x, r.end.y - 18 * s, r.size.x, 18 * s), GREEN)
			ellipse(ci, Vector2(r.position.x + 22 * s, r.end.y - 18 * s), 19 * s, 7 * s, LIME)
			for k in 12:
				var a := TAU * k / 12 + t * 0.5
				ci.draw_line(c + Vector2(0, -6 * s) + Vector2(cos(a), sin(a)) * 16 * s,
					c + Vector2(0, -6 * s) + Vector2(cos(a), sin(a)) * 23 * s, YELLOW, 3 * s)
			ci.draw_circle(c + Vector2(0, -6 * s), 13 * s, YELLOW)
			ci.draw_circle(c + Vector2(-4, -8) * s + Vector2(0, -6 * s) * 0, 1.8 * s, INK)
			ci.draw_circle(c + Vector2(4, -8) * s, 1.8 * s, INK)
			ci.draw_arc(c + Vector2(0, -5) * s, 5 * s, 0.3, PI - 0.3, 10, INK, 1.6 * s)
			ci.draw_circle(c + Vector2(-8, -3) * s, 2.2 * s, Color(ORANGE, 0.7))
			ci.draw_circle(c + Vector2(8, -3) * s, 2.2 * s, Color(ORANGE, 0.7))
		"rocket":
			round_rect(ci, r, 6 * s, NAVY)
			for k in 9:
				var p := r.position + Vector2(fposmod(k * 23.0 + 7, 60) + 2, fposmod(k * 17.0 + 5, 60) + 2) * s
				star(ci, p, (1.6 + (k % 3)) * s, WHITE if k % 2 else YELLOW, t + k)
			var rc := c + Vector2(0, sin(t * 3.0) * 2.0 * s)
			var body := PackedVector2Array([rc + Vector2(0, -22) * s, rc + Vector2(8, -8) * s, rc + Vector2(8, 12) * s,
				rc + Vector2(-8, 12) * s, rc + Vector2(-8, -8) * s])
			ci.draw_colored_polygon(PackedVector2Array([rc + Vector2(-8, 2) * s, rc + Vector2(-15, 16) * s, rc + Vector2(-8, 12) * s]), RED)
			ci.draw_colored_polygon(PackedVector2Array([rc + Vector2(8, 2) * s, rc + Vector2(15, 16) * s, rc + Vector2(8, 12) * s]), RED)
			ci.draw_colored_polygon(body, WHITE)
			ci.draw_colored_polygon(PackedVector2Array([rc + Vector2(0, -22) * s, rc + Vector2(6, -12) * s, rc + Vector2(-6, -12) * s]), RED)
			ci.draw_circle(rc + Vector2(0, -3) * s, 4.5 * s, SKY)
			ci.draw_circle(rc + Vector2(0, -3) * s, 4.5 * s, GREY, false, 1.5 * s)
			var flame := 1.0 + 0.25 * sin(t * 18.0)
			ci.draw_colored_polygon(PackedVector2Array([rc + Vector2(-6, 12) * s, rc + Vector2(6, 12) * s,
				rc + Vector2(0, 12 + 12 * flame) * s]), ORANGE)
			ci.draw_colored_polygon(PackedVector2Array([rc + Vector2(-3, 12) * s, rc + Vector2(3, 12) * s,
				rc + Vector2(0, 12 + 7 * flame) * s]), YELLOW)
		"cat":
			round_rect(ci, r, 6 * s, PLUM)
			ci.draw_circle(r.position + Vector2(50, 13) * s, 7 * s, YELLOW)
			ci.draw_circle(r.position + Vector2(53, 11) * s, 6 * s, PLUM)
			var h := c + Vector2(0, 6) * s
			ci.draw_colored_polygon(PackedVector2Array([h + Vector2(-18, -6) * s, h + Vector2(-15, -24) * s, h + Vector2(-4, -14) * s]), ORANGE)
			ci.draw_colored_polygon(PackedVector2Array([h + Vector2(18, -6) * s, h + Vector2(15, -24) * s, h + Vector2(4, -14) * s]), ORANGE)
			ellipse(ci, h, 19 * s, 15 * s, ORANGE)
			ci.draw_colored_polygon(PackedVector2Array([h + Vector2(-14, -9) * s, h + Vector2(-14, -19) * s, h + Vector2(-8, -13) * s]), PINK)
			ci.draw_colored_polygon(PackedVector2Array([h + Vector2(14, -9) * s, h + Vector2(14, -19) * s, h + Vector2(8, -13) * s]), PINK)
			var blink := 0.3 if fposmod(t, 3.0) < 0.15 else 1.0
			ellipse(ci, h + Vector2(-7, -2) * s, 3 * s, 3.5 * s * blink, INK)
			ellipse(ci, h + Vector2(7, -2) * s, 3 * s, 3.5 * s * blink, INK)
			ci.draw_colored_polygon(PackedVector2Array([h + Vector2(-2, 3) * s, h + Vector2(2, 3) * s, h + Vector2(0, 5) * s]), RED)
			for sgn in [-1.0, 1.0]:
				for k in 2:
					ci.draw_line(h + Vector2(6 * sgn, 5 + k * 3) * s, h + Vector2(22 * sgn, 3 + k * 5) * s, WHITE, 1.0 * s)
			note(ci, r.position + Vector2(12, 20) * s, s * 0.6, WHITE)
