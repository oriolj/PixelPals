extends Node2D
## The wooden track, drawn once from the edges' Curve2D: an ink outline, the
## beechwood band, sleepers every 24 px, two grooves (the rails, offset from
## the centre line) and a highlight. Layers go across ALL edges before the next
## layer, so junctions and merges blend into one piece of wood. Also the
## bridge over the pond and the farm road's level crossing.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Track := preload("res://scripts/track/track.gd")

const HALF := Track.TRACK_WIDTH * 0.5
const GROOVE_OFFSET := 11.0
const SLEEPER_EVERY := 24.0
const STEP := 6.0

var track
var lines: Array[PackedVector2Array] = []
## The farm road crossing: [edge, arc].
var crossing := []


func setup(graph) -> void:
	track = graph
	for e in track.curves.size():
		lines.append(track.polyline(e, STEP))
	var we: int = track.edge("west")
	crossing = [we, track.closest(we, Vector2(1800, 1920))]
	queue_redraw()


## Rails (groove centre lines) of an edge: [left, right] offset polylines.
static func rails(pts: PackedVector2Array) -> Array[PackedVector2Array]:
	return [Shapes.offset_polyline(pts, -GROOVE_OFFSET), Shapes.offset_polyline(pts, GROOVE_OFFSET)]


func _draw() -> void:
	_draw_road()
	_draw_bridge_deck()
	for pts in lines:
		draw_polyline(pts, Palette.INK, Track.TRACK_WIDTH + 5.0, true)
	for pts in lines:
		draw_polyline(pts, Palette.TRACK, Track.TRACK_WIDTH)
	for pts in lines:
		draw_polyline(Shapes.offset_polyline(pts, -HALF + 5.0), Palette.TRACK_LIGHT, 3.0)
	for e in lines.size():
		_draw_sleepers(e)
	_draw_crossing_boards()
	for pts in lines:
		for r in rails(pts):
			draw_polyline(r, Palette.GROOVE, 6.0, true)
	_draw_bridge_rails()


func _draw_sleepers(e: int) -> void:
	var d := SLEEPER_EVERY * 0.5
	var col := Palette.TRACK.darkened(0.12)
	while d < track.lengths[e]:
		var p: Vector2 = track.sample(e, d)
		var t: Vector2 = track.tangent(e, d)
		var n := Vector2(-t.y, t.x)
		draw_line(p - n * (HALF - 4.0), p + n * (HALF - 4.0), col, 4.0)
		d += SLEEPER_EVERY


func _draw_road() -> void:
	var e: int = crossing[0]
	var p: Vector2 = track.sample(e, crossing[1])
	var road := PackedVector2Array([Vector2(1785, 2060), p + Vector2(0, 70), p, p + Vector2(-10, -120), Vector2(1700, 1560)])
	draw_polyline(road, Palette.SOIL.darkened(0.1), 62.0)
	draw_polyline(road, Palette.SOIL, 54.0)


func _draw_crossing_boards() -> void:
	var e: int = crossing[0]
	for k in range(-2, 3):
		var d: float = crossing[1] + k * 12.0
		var p: Vector2 = track.sample(e, d)
		var t: Vector2 = track.tangent(e, d)
		var n := Vector2(-t.y, t.x)
		draw_line(p - n * (HALF - 3.0), p + n * (HALF - 3.0), Palette.TRACK_LIGHT, 9.0)
	# Striped barrier posts on both sides.
	var p0: Vector2 = track.sample(e, crossing[1] - 40.0)
	var t0: Vector2 = track.tangent(e, crossing[1])
	var n0 := Vector2(-t0.y, t0.x)
	for side in [-1, 1]:
		var base: Vector2 = p0 + n0 * side * (HALF + 26.0)
		Shapes.fill_outline(self, Shapes.circle(base, 9, 16), Palette.WHITE)
		draw_circle(base, 4, Palette.STATION[0])


func _bridge_range() -> Vector3:
	var e: int = track.edge(Track.BRIDGE[0])
	var a: float = track.closest(e, Track.BRIDGE[1])
	var b: float = track.closest(e, Track.BRIDGE[2])
	return Vector3(e, minf(a, b), maxf(a, b))


func _bridge_side(side: float, off: float) -> PackedVector2Array:
	var r := _bridge_range()
	var out := PackedVector2Array()
	var d := r.y
	while d <= r.z:
		var p: Vector2 = track.sample(int(r.x), d)
		var t: Vector2 = track.tangent(int(r.x), d)
		out.append(p + Vector2(-t.y, t.x) * side * off)
		d += 8.0
	return out


func _draw_bridge_deck() -> void:
	var r := _bridge_range()
	var e := int(r.x)
	# Pillars in the water, then the plank deck.
	var d := r.y + 30.0
	while d < r.z - 20.0:
		var p: Vector2 = track.sample(e, d)
		Shapes.fill_outline(self, Shapes.ellipse(p + Vector2(0, 10), 50, 16, 20), Palette.ROCK)
		d += 110.0
	var left := _bridge_side(-1, 44.0)
	var right := _bridge_side(1, 44.0)
	var deck := left.duplicate()
	var rr := right.duplicate()
	rr.reverse()
	deck.append_array(rr)
	Shapes.fill_outline(self, deck, Palette.TRACK.darkened(0.25), 3.0)
	d = r.y + 8.0
	while d < r.z:
		var p: Vector2 = track.sample(e, d)
		var t: Vector2 = track.tangent(e, d)
		var n := Vector2(-t.y, t.x)
		draw_line(p - n * 42.0, p + n * 42.0, Palette.TRACK.darkened(0.38), 2.0)
		d += 16.0


func _draw_bridge_rails() -> void:
	for side in [-1.0, 1.0]:
		var line := _bridge_side(side, 38.0)
		draw_polyline(line, Palette.INK, 9.0)
		draw_polyline(line, Palette.STATION[1].lightened(0.25), 5.0)
		for i in range(0, line.size(), 6):
			Shapes.fill_outline(self, Shapes.circle(line[i], 6, 12), Palette.STATION[1].lightened(0.25))
