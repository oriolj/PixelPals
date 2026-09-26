extends Node2D
## The garage: back wall, roll-up door, shelves with boxes and paint cans, a
## bike on the wall, a starry window, string lights, the floor and the stage
## rug. Drawn once from point lists (no textures). `beat` (0..1, set by the
## screen) makes the string-light bulbs twinkle on the beat.

const Draw := preload("res://scripts/view/draw.gd")
const FLOOR_Y := 262.0
const RUG := Vector2(320, 300)

var beat := 0.0:
	set(v):
		beat = v
		if _bulbs:
			_bulbs.queue_redraw()
var _bulbs: Node2D


func _ready() -> void:
	_bulbs = Bulbs.new()
	_bulbs.garage = self
	add_child(_bulbs)


func _draw() -> void:
	# Wall with planks.
	draw_rect(Rect2(0, 0, 640, FLOOR_Y), Draw.DARK)
	for x in range(0, 640, 32):
		draw_rect(Rect2(x, 0, 2, FLOOR_Y), Color(Draw.INK, 0.35))
	draw_rect(Rect2(0, 0, 640, 10), Draw.INK)
	# Roll-up garage door behind the band.
	draw_rect(Rect2(214, 64, 212, FLOOR_Y - 64), Draw.WOOD)
	draw_rect(Rect2(220, 70, 200, FLOOR_Y - 70), Draw.SLATE)
	for y in range(84, int(FLOOR_Y), 16):
		draw_rect(Rect2(220, y, 200, 3), Color(Draw.DARK, 0.7))
		draw_rect(Rect2(220, y + 3, 200, 1), Color(Draw.GREY, 0.25))
	draw_rect(Rect2(305, 232, 30, 6), Draw.GREY)
	# Left wall: two shelves with boxes, cans and a plant.
	for sy in [112.0, 172.0]:
		draw_rect(Rect2(18, sy, 160, 6), Draw.WOOD)
		draw_rect(Rect2(30, sy + 6, 4, 10), Draw.WOOD)
		draw_rect(Rect2(160, sy + 6, 4, 10), Draw.WOOD)
	_box(Rect2(26, 78, 40, 34))
	_box(Rect2(70, 90, 30, 22))
	_can(Vector2(118, 112), Draw.SKY)
	_can(Vector2(140, 112), Draw.RED)
	_plant(Vector2(162, 112))
	_can(Vector2(36, 172), Draw.LIME)
	_box(Rect2(56, 140, 50, 32))
	_box(Rect2(112, 150, 26, 22))
	# Soccer ball and a stack of boxes on the floor.
	_box(Rect2(24, 214, 56, 48))
	_box(Rect2(34, 184, 40, 30))
	draw_circle(Vector2(104, 250), 12, Draw.WHITE)
	Draw.ngon(self, Vector2(104, 250), 4.5, 5, Draw.INK)
	for k in 5:
		var a := TAU * k / 5 - PI / 2
		draw_line(Vector2(104, 250) + Vector2(cos(a), sin(a)) * 4.5, Vector2(104, 250) + Vector2(cos(a), sin(a)) * 11, Draw.INK, 1.2)
	# Right wall: a bike and a starry window.
	_bike(Vector2(560, 110))
	draw_rect(Rect2(478, 168, 124, 70), Draw.WOOD)
	draw_rect(Rect2(482, 172, 116, 62), Draw.NAVY)
	draw_circle(Vector2(576, 188), 10, Draw.YELLOW)
	draw_circle(Vector2(582, 184), 9, Draw.NAVY)
	for k in 6:
		Draw.star(self, Vector2(492 + k * 17, 180 + (k * 23) % 44), 2.5 + k % 2, Draw.WHITE, k)
	draw_rect(Rect2(538, 172, 4, 62), Draw.WOOD)
	draw_rect(Rect2(482, 201, 116, 4), Draw.WOOD)
	# Floor and the stage rug.
	draw_rect(Rect2(0, FLOOR_Y, 640, 360 - FLOOR_Y), Draw.INK)
	for x in range(-400, 1040, 56):
		draw_line(Vector2(320 + (x - 320) * 0.55, FLOOR_Y), Vector2(x, 360), Color(Draw.NAVY, 0.8), 2.0)
	draw_line(Vector2(0, FLOOR_Y), Vector2(640, FLOOR_Y), Draw.SLATE, 2.0)
	Draw.ellipse(self, RUG, 176, 44, Draw.RED)
	Draw.ellipse(self, RUG, 168, 39, Draw.PLUM)
	for k in 12:
		var a := TAU * k / 12
		Draw.star(self, RUG + Vector2(cos(a) * 150, sin(a) * 32), 3, Color(Draw.YELLOW, 0.6), a)


func _box(r: Rect2) -> void:
	draw_rect(r, Draw.ORANGE.darkened(0.15))
	draw_rect(Rect2(r.position, Vector2(r.size.x, 5)), Draw.ORANGE)
	draw_rect(Rect2(r.position.x + r.size.x / 2 - 3, r.position.y, 6, r.size.y), Color(Draw.YELLOW, 0.8))


func _can(bottom: Vector2, col: Color) -> void:
	draw_rect(Rect2(bottom + Vector2(-9, -22), Vector2(18, 22)), col)
	Draw.ellipse(self, bottom + Vector2(0, -22), 9, 3, Draw.GREY)
	draw_rect(Rect2(bottom + Vector2(-9, -14), Vector2(18, 6)), Color(Draw.WHITE, 0.6))


func _plant(bottom: Vector2) -> void:
	draw_colored_polygon(PackedVector2Array([bottom + Vector2(-7, -14), bottom + Vector2(7, -14),
		bottom + Vector2(5, 0), bottom + Vector2(-5, 0)]), Draw.ORANGE)
	for k in 5:
		var a := -PI / 2 + (k - 2) * 0.45
		Draw.ellipse(self, bottom + Vector2(0, -16) + Vector2(cos(a), sin(a)) * 10, 7, 3, Draw.GREEN, a)


func _bike(c: Vector2) -> void:
	for sx in [-30.0, 30.0]:
		draw_circle(c + Vector2(sx, 16), 20, Draw.INK, false, 5.0)
		draw_circle(c + Vector2(sx, 16), 20, Draw.GREY, false, 2.0)
		for k in 6:
			var a := TAU * k / 6
			draw_line(c + Vector2(sx, 16), c + Vector2(sx, 16) + Vector2(cos(a), sin(a)) * 18, Color(Draw.GREY, 0.6), 1.0)
	var frame := [[Vector2(-30, 16), Vector2(-4, 16)], [Vector2(-4, 16), Vector2(18, -8)],
		[Vector2(-30, 16), Vector2(-14, -8)], [Vector2(-14, -8), Vector2(18, -8)],
		[Vector2(-14, -8), Vector2(-4, 16)], [Vector2(18, -8), Vector2(30, 16)]]
	for seg in frame:
		draw_line(c + seg[0], c + seg[1], Draw.RED, 3.5)
	draw_rect(Rect2(c + Vector2(-22, -14), Vector2(14, 5)), Draw.INK)
	draw_line(c + Vector2(18, -8), c + Vector2(16, -18), Draw.GREY, 3.0)
	draw_line(c + Vector2(10, -18), c + Vector2(24, -18), Draw.GREY, 3.0)
	# Hooks on the wall.
	draw_line(c + Vector2(-30, -4), c + Vector2(-30, -40), Draw.GREY, 1.5)
	draw_line(c + Vector2(30, -4), c + Vector2(30, -40), Draw.GREY, 1.5)


## String lights across the top, twinkling on the beat.
class Bulbs extends Node2D:
	var garage: Node2D

	func _draw() -> void:
		var pts := PackedVector2Array()
		for i in 81:
			var x := i * 8.0
			pts.append(Vector2(x, 14 + absf(sin(x / 160.0 * PI)) * 16))
		draw_polyline(pts, Draw.INK, 2.0)
		var b: float = garage.beat
		for i in 27:
			var x := 12 + i * 24.0
			var y := 14 + absf(sin(x / 160.0 * PI)) * 16
			var col: Color = Draw.LANE_COLORS[i % 5]
			var lit := 0.55 + 0.45 * (b if i % 2 == 0 else 1.0 - b)
			draw_circle(Vector2(x, y + 6), 7, Color(col, 0.18 * lit))
			draw_circle(Vector2(x, y + 5), 3.5, col.darkened(0.5 * (1.0 - lit)))
			draw_rect(Rect2(x - 1.5, y, 3, 2), Draw.SLATE)
