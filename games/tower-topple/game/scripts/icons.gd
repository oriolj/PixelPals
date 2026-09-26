extends RefCounted
## Vector icons for the menus (no text, no PNGs): the three seat roles, the
## device kinds, arrows, the ready tick and the trophy.

const Vec := preload("res://scripts/play/vec.gd")
const Block := preload("res://scripts/play/block.gd")


## Draws icon `icon` centred on `at`, about `s` px tall, in colour `col`.
static func draw(ci: CanvasItem, icon: String, at: Vector2, s: float, col: Color) -> void:
	var k := s / 32.0
	match icon:
		"hook":  # the Builder: a crane hook on a rope
			ci.draw_line(at + Vector2(0, -16) * k, at + Vector2(0, -2) * k, Vec.INK, 6.0 * k, true)
			ci.draw_line(at + Vector2(0, -16) * k, at + Vector2(0, -2) * k, col, 3.0 * k, true)
			var pts := PackedVector2Array([at + Vector2(0, -4) * k])
			for i in 11:
				var a := -PI * 0.05 + PI * 1.2 * i / 10.0
				pts.append(at + (Vector2(-1, 6) + Vector2(cos(a), sin(a)) * 8.0) * k)
			ci.draw_polyline(pts, Vec.INK, 7.0 * k, true)
			ci.draw_polyline(pts, col, 3.5 * k, true)
			Vec.draw_disc(ci, at + Vector2(0, -16) * k, 3.5 * k, col, Vec.INK, 2.0 * k)
		"drop":  # the Dropper: a block falling (speed lines above, an arrow below)
			for dx in [-7.0, 0.0, 7.0]:
				var h := 7.0 if dx == 0.0 else 4.0
				ci.draw_line(at + Vector2(dx, -17) * k, at + Vector2(dx, -17 + h) * k, col, 3.0 * k, true)
			Block.draw_mini(ci, "square", at + Vector2(0, -1) * k, 16.0 * k)
			var arrow := PackedVector2Array([Vector2(-4, 9), Vector2(4, 9), Vector2(4, 12), Vector2(9, 12),
				Vector2(0, 19), Vector2(-9, 12), Vector2(-4, 12)])
			Vec.draw_shape(ci, Vec.translated(Vec.scaled(arrow, Vector2(k, k)), at), col, Vec.INK, 2.0 * k)
		"button":  # the Toppler: the big red button
			var base := Vec.translated(Vec.scaled(Vec.rounded_rect(30, 9, 3), Vector2(k, k)), at + Vector2(0, 9) * k)
			Vec.draw_shape(ci, base, Color("#333c57"), Vec.INK, 2.0 * k)
			var dome := PackedVector2Array()
			for i in 13:
				var a := PI + PI * i / 12.0
				dome.append(at + Vector2(cos(a) * 11.0, 5.0 + sin(a) * 11.0) * k)
			Vec.draw_shape(ci, dome, Color("#ff5a5a"), Vec.INK, 2.0 * k)
			ci.draw_arc(at + Vector2(-2, 5) * k, 7.0 * k, PI + 0.5, PI + 1.3, 6, Color(1, 1, 1, 0.7), 2.0 * k, true)
			ci.draw_rect(Rect2(at + Vector2(-10, 12) * k, Vector2(20, 2.5) * k), col)
		"pad":
			var body := Vec.rounded(PackedVector2Array([Vector2(-14, -7), Vector2(14, -7), Vector2(15, 7), Vector2(9, 10),
				Vector2(4, 5), Vector2(-4, 5), Vector2(-9, 10), Vector2(-15, 7)]), 4.0, 3)
			Vec.draw_shape(ci, Vec.translated(Vec.scaled(body, Vector2(k, k)), at), col, Vec.INK, 2.0 * k)
			ci.draw_rect(Rect2(at + Vector2(-10, -2) * k, Vector2(7, 2) * k), Vec.INK)
			ci.draw_rect(Rect2(at + Vector2(-7.5, -4.5) * k, Vector2(2, 7) * k), Vec.INK)
			ci.draw_circle(at + Vector2(7, -3) * k, 1.8 * k, Vec.RED, true, -1.0, true)
			ci.draw_circle(at + Vector2(10, 0) * k, 1.8 * k, Vec.GREEN, true, -1.0, true)
		"kb":
			var body := Vec.rounded_rect(30, 16, 3)
			Vec.draw_shape(ci, Vec.translated(Vec.scaled(body, Vector2(k, k)), at), col, Vec.INK, 2.0 * k)
			for row in 2:
				for i in 5:
					ci.draw_rect(Rect2(at + Vector2(-12 + i * 5, -5 + row * 5) * k, Vector2(3.5, 3) * k), Vec.INK)
			ci.draw_rect(Rect2(at + Vector2(-8, 5) * k, Vector2(16, 2.5) * k), Vec.INK)
		"left", "right":
			var d := -1.0 if icon == "left" else 1.0
			var tri := PackedVector2Array([at + Vector2(-6 * d, -9) * k, at + Vector2(8 * d, 0) * k, at + Vector2(-6 * d, 9) * k])
			Vec.draw_shape(ci, tri, col, Vec.INK, 2.5 * k)
		"check":
			var pts := PackedVector2Array([at + Vector2(-10, 0) * k, at + Vector2(-3, 8) * k, at + Vector2(11, -8) * k])
			ci.draw_polyline(pts, Vec.INK, 9.0 * k, true)
			ci.draw_polyline(pts, col, 5.0 * k, true)
		"trophy":
			var cup := Vec.rounded(PackedVector2Array([Vector2(-12, -12), Vector2(12, -12), Vector2(9, 2), Vector2(0, 7),
				Vector2(-9, 2)]), 4.0, 3)
			for side in [-1.0, 1.0]:
				ci.draw_arc(at + Vector2(12 * side, -5) * k, 6.0 * k, -PI / 2 if side > 0 else PI / 2,
					PI / 2 if side > 0 else PI * 1.5, 8, Vec.INK, 4.5 * k, true)
				ci.draw_arc(at + Vector2(12 * side, -5) * k, 6.0 * k, -PI / 2 if side > 0 else PI / 2,
					PI / 2 if side > 0 else PI * 1.5, 8, col, 2.0 * k, true)
			ci.draw_rect(Rect2(at + Vector2(-3, 6) * k, Vector2(6, 6) * k), Vec.INK)
			var foot := Vec.translated(Vec.scaled(Vec.rounded_rect(20, 6, 2), Vector2(k, k)), at + Vector2(0, 14) * k)
			Vec.draw_shape(ci, foot, col.darkened(0.2), Vec.INK, 2.0 * k)
			Vec.draw_shape(ci, Vec.translated(Vec.scaled(cup, Vector2(k, k)), at), col, Vec.INK, 2.5 * k)
			ci.draw_colored_polygon(Vec.star(5.0 * k, at + Vector2(0, -4) * k), Vec.WHITE)
