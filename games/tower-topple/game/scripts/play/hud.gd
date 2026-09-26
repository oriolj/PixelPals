extends RefCounted
## Screen-fixed pieces of the play screen, drawn in code: the crane, the
## Dropper's shape tray, the Toppler's big red button, the tower counter and
## the pause overlay, and the world effects particles.

const Vec := preload("res://scripts/play/vec.gd")
const Block := preload("res://scripts/play/block.gd")

const HOOK_Y := 58.0
const RAIL_Y := 16.0
const BUTTON_AT := Vector2(588, 318)
const TRAY_AT := Vector2(58, 90)
## Tray slots in d-pad order: up, right, down, left.
const SLOT_OFFSETS: Array[Vector2] = [Vector2(0, -32), Vector2(32, 0), Vector2(0, 32), Vector2(-32, 0)]


class Crane extends Node2D:
	var hook_x := 320.0
	var parked := false
	var time := 0.0
	var tint := Color("#41a6f6")
	var builder_on := true

	func _draw() -> void:
		# The rail: a yellow girder with a zigzag truss.
		draw_rect(Rect2(-10, RAIL_Y - 12, 660, 20), Vec.YELLOW)
		var x := -10.0
		var up := true
		var pts := PackedVector2Array()
		while x <= 660.0:
			pts.append(Vector2(x, RAIL_Y - 10 if up else RAIL_Y + 6))
			up = not up
			x += 16.0
		draw_polyline(pts, Color("#ef7d57"), 3.0, true)
		draw_line(Vector2(-10, RAIL_Y - 12), Vector2(660, RAIL_Y - 12), Vec.INK, 3.0, true)
		draw_line(Vector2(-10, RAIL_Y + 8), Vector2(660, RAIL_Y + 8), Vec.INK, 3.0, true)
		# The trolley (the Builder's colour) with wheels.
		var tx := hook_x
		var trolley := Vec.translated(Vec.rounded_rect(40, 18, 5), Vector2(tx, RAIL_Y + 12))
		Vec.draw_shape(self, trolley, tint if builder_on else Vec.GREY)
		for dx in [-12.0, 12.0]:
			Vec.draw_disc(self, Vector2(tx + dx, RAIL_Y + 2), 4.0, Vec.SLATE, Vec.INK, 2.0)
		draw_circle(Vector2(tx - 8, RAIL_Y + 9), 2.5, Color(1, 1, 1, 0.6), true, -1.0, true)
		# Rope and hook.
		var hy := HOOK_Y - (22.0 if parked else 0.0)
		draw_line(Vector2(tx, RAIL_Y + 20), Vector2(tx, hy - 6), Vec.INK, 4.0, true)
		draw_line(Vector2(tx, RAIL_Y + 20), Vector2(tx, hy - 6), Color("#94b0c2"), 2.0, true)
		var hook := PackedVector2Array()
		for i in 11:
			var a := -PI * 0.1 + PI * 1.25 * i / 10.0
			hook.append(Vector2(tx, hy + 2) + Vector2(cos(a), sin(a)) * 6.0)
		hook.insert(0, Vector2(tx + 6, hy - 6))
		draw_polyline(hook, Vec.INK, 6.0, true)
		draw_polyline(hook, Color("#94b0c2"), 3.0, true)


class Tray extends Node2D:
	var slots: Array[String] = ["square", "plank", "tall", "arch"]
	var selected := 0
	var bump := 0.0
	var flash := 0.0
	var time := 0.0

	func _draw() -> void:
		var panel := Vec.rounded(PackedVector2Array([Vector2(-20, -54), Vector2(20, -54), Vector2(20, -20), Vector2(54, -20),
			Vector2(54, 20), Vector2(20, 20), Vector2(20, 54), Vector2(-20, 54), Vector2(-20, 20), Vector2(-54, 20),
			Vector2(-54, -20), Vector2(-20, -20)]), 12.0, 4)
		Vec.draw_shape(self, panel, Color(Color("#ffcd75"), 0.9))
		Vec.draw_disc(self, Vector2.ZERO, 7.0, Color("#ef7d57"), Vec.INK, 2.0)
		for i in 4:
			var at: Vector2 = SLOT_OFFSETS[i]
			var sel := i == selected
			var s := 24.0 + (4.0 * bump / 0.2 if sel and bump > 0.0 else 0.0)
			if sel:
				var ring := Vec.translated(Vec.rounded_rect(32, 32, 8), at)
				Vec.draw_shape(self, ring, Vec.WHITE, Vec.INK, 3.0)
				# A little arrow toward the slot (the d-pad direction).
				var dir := at.normalized()
				var side := Vector2(-dir.y, dir.x)
				var tip := dir * 14.0
				draw_colored_polygon(PackedVector2Array([tip, dir * 8.0 + side * 4.0, dir * 8.0 - side * 4.0]), Vec.INK)
			Block.draw_mini(self, slots[i], at, s if sel else 20.0)
		if flash > 0.0:
			draw_circle(Vector2.ZERO, 60.0 * (1.0 - flash), Color(1, 1, 1, flash), false, 4.0, true)


class BigButton extends Node2D:
	var lit := false
	var time := 0.0
	var press := 0.0
	var toddler_on := true

	func _draw() -> void:
		var pulse := 0.5 + 0.5 * sin(time * 7.0)
		if lit:
			# Glow: layered translucent copies (additive look) and turning rays.
			for i in 8:
				var a := time * 1.2 + TAU * i / 8.0
				var d := Vector2(cos(a), sin(a))
				var side := Vector2(-d.y, d.x)
				var r0 := 40.0
				var r1 := 70.0 + 8.0 * pulse
				draw_colored_polygon(PackedVector2Array([d * r0 + side * 7.0 + Vector2(0, -8), d * r1 + Vector2(0, -8),
					d * r0 - side * 7.0 + Vector2(0, -8)]), Color(1, 0.95, 0.55, 0.55))
			for k in 4:
				draw_circle(Vector2(0, -8), 44.0 + k * 6.0 + pulse * 6.0, Color(1.0, 0.85, 0.4, 0.14), true, -1.0, true)
		var squash := press / 0.25
		var dome_h := (26.0 if lit else 18.0) * (1.0 - 0.45 * squash)
		var base := Vec.translated(Vec.rounded_rect(84, 24, 7), Vector2(0, 14))
		Vec.draw_shape(self, base, Color("#333c57"))
		draw_line(Vector2(-34, 8), Vector2(34, 8), Color(1, 1, 1, 0.25), 2.0, true)
		if toddler_on:
			draw_rect(Rect2(-30, 18, 60, 5), Color("#a7f070"))
		var dome := PackedVector2Array()
		for i in 17:
			var a := PI + PI * i / 16.0
			dome.append(Vector2(cos(a) * 32.0, 4.0 + sin(a) * dome_h))
		var red := Color("#ff5a5a").lerp(Color("#b13e53"), 0.35 * (1.0 - pulse)) if lit else Color("#8a3a52")
		Vec.draw_shape(self, dome, red)
		# Shine.
		draw_arc(Vector2(-4, 4), 20.0, PI + 0.4, PI + 1.3, 8, Color(1, 1, 1, 0.7 if lit else 0.3), 4.0, true)
		if lit:
			# A bouncing arrow above says "press me" without words.
			var y := -54.0 - 8.0 * absf(sin(time * 5.0))
			var arrow := PackedVector2Array([Vector2(-12, y), Vector2(12, y), Vector2(12, y + 10), Vector2(20, y + 10),
				Vector2(0, y + 26), Vector2(-20, y + 10), Vector2(-12, y + 10)])
			Vec.draw_shape(self, arrow, Vec.WHITE)


class Progress extends Node2D:
	var done := 0
	var current := 0
	var time := 0.0
	var heights: Array[int] = []

	func _draw() -> void:
		var panel := Vec.rounded_rect(112, 44, 10)
		Vec.draw_shape(self, panel, Color(Vec.WHITE, 0.55), Color(Vec.INK, 0.6), 2.0)
		for i in 3:
			var x := -34.0 + i * 34.0
			var col: Color = [Color("#b13e53"), Color("#38b764"), Color("#3b5dc9")][i]
			for k in 3:
				var r := Vec.translated(Vec.rounded_rect(14, 10, 3), Vector2(x, 13 - k * 11))
				if i < done:
					Vec.draw_shape(self, r, col, Vec.INK, 2.0)
				elif i == current:
					var blink := 0.5 + 0.5 * sin(time * 5.0)
					Vec.draw_shape(self, r, Color(col, 0.25 + 0.4 * blink), Vec.INK, 2.0)
				else:
					Vec.draw_shape(self, r, Color(Vec.WHITE, 0.3), Color(Vec.INK, 0.35), 1.5)
			if i < done:
				draw_colored_polygon(Vec.star(6.0, Vector2(x, -24)), Vec.YELLOW)


## Dimmed pause screen: a back arrow (Builder "b") and a play triangle ("a"/start).
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 640, 360), Color(0.1, 0.11, 0.17, 0.7))
		Vec.draw_disc(self, Vector2(220, 180), 44, Color("#b13e53"))
		draw_colored_polygon(PackedVector2Array([Vector2(196, 180), Vector2(220, 156), Vector2(220, 170),
			Vector2(242, 170), Vector2(242, 190), Vector2(220, 190), Vector2(220, 204)]), Vec.WHITE)
		Vec.draw_disc(self, Vector2(420, 180), 52, Color("#38b764"))
		draw_colored_polygon(PackedVector2Array([Vector2(404, 152), Vector2(444, 180), Vector2(404, 208)]), Vec.WHITE)


## World effects: stars and sparkles as simple particles (no textures).
class Fx extends Node2D:
	var parts: Array[Dictionary] = []  # {pos, vel, life, max, kind, col, size, spin}

	func burst(at: Vector2, n: int, kind := "star", speed := 160.0, col := Color.WHITE) -> void:
		for i in n:
			var a := randf() * TAU
			var v := Vector2(cos(a), sin(a)) * randf_range(0.4, 1.0) * speed + Vector2(0, -speed * 0.4)
			var c := col
			if col == Color.WHITE:
				c = Vec.CONFETTI[randi() % Vec.CONFETTI.size()]
			parts.append({"pos": at, "vel": v, "life": 0.0, "max": randf_range(0.6, 1.1), "kind": kind,
				"col": c, "size": randf_range(4.0, 8.0), "spin": randf_range(-6, 6)})

	func fly(from: Vector2, to: Vector2, col := Color("#ffcd75")) -> void:
		parts.append({"pos": from, "vel": Vector2.ZERO, "life": 0.0, "max": 0.7, "kind": "fly",
			"col": col, "size": 8.0, "spin": 3.0, "from": from, "to": to})

	func step(dt: float) -> void:
		for i in range(parts.size() - 1, -1, -1):
			var p := parts[i]
			p.life += dt
			if p.life >= p.max:
				parts.remove_at(i)
				continue
			if p.kind == "fly":
				var u: float = p.life / p.max
				var arc := Vector2(0, -80.0 * sin(u * PI))
				p.pos = (p.from as Vector2).lerp(p.to, u * u * (3.0 - 2.0 * u)) + arc
			else:
				p.vel.y += 300.0 * dt
				p.pos += p.vel * dt
		queue_redraw()

	func _draw() -> void:
		for p in parts:
			var fade: float = 1.0 - p.life / p.max
			var c: Color = p.col
			c.a = clampf(fade * 1.5, 0.0, 1.0)
			var r: float = p.size * (0.6 + 0.4 * fade)
			var pts := Vec.star(r, Vector2.ZERO, 0.45)
			var rot: float = p.spin * p.life
			var out := PackedVector2Array()
			for q in pts:
				out.append(p.pos + q.rotated(rot))
			draw_colored_polygon(out, c)
			draw_polyline(Vec.closed(out), Color(Vec.INK, c.a), 1.5, true)
