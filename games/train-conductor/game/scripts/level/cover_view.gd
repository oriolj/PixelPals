extends Node2D
## The tunnel hill, drawn above the train and a little see-through, so the
## train dims as it runs under it and pops out the other side. Stone portals
## mark both ends.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")
const Track := preload("res://scripts/track/track.gd")

const HALF_W := 92.0

var track
var edge := 0
var from := 0.0
var to := 0.0
var mound := PackedVector2Array()


func setup(graph, tunnel_range: Vector2) -> void:
	track = graph
	edge = track.edge(Track.TUNNEL[0])
	from = tunnel_range.x
	to = tunnel_range.y
	var centre := PackedVector2Array()
	var d := from + 20.0
	while d <= to - 20.0:
		centre.append(track.sample(edge, d))
		d += 10.0
	var left := Shapes.offset_polyline(centre, -HALF_W)
	var right := Shapes.offset_polyline(centre, HALF_W)
	right.reverse()
	mound = left
	# Round the two ends.
	var end_c := centre[centre.size() - 1]
	var end_t: Vector2 = (centre[centre.size() - 1] - centre[centre.size() - 2]).normalized()
	for i in range(1, 10):
		var a := end_t.angle() - PI / 2 + PI * i / 10.0
		mound.append(end_c + Vector2.from_angle(a) * HALF_W)
	mound.append_array(right)
	var start_c := centre[0]
	var start_t: Vector2 = (centre[1] - centre[0]).normalized()
	for i in range(1, 10):
		var a := start_t.angle() + PI / 2 + PI * i / 10.0
		mound.append(start_c + Vector2.from_angle(a) * HALF_W)
	modulate = Color(1, 1, 1, 0.86)
	queue_redraw()


func _draw() -> void:
	Shapes.fill_outline(self, mound, Palette.GRASS_DARK, 3.0)
	var c: Vector2 = track.sample(edge, (from + to) * 0.5)
	draw_colored_polygon(Shapes.ellipse(c + Vector2(-10, -20), 60, 110, 24), Palette.GRASS_DARK.lightened(0.15))
	for k in [[Vector2(30, -120), 20.0], [Vector2(-40, 90), 16.0], [Vector2(40, 60), 12.0], [Vector2(-30, -60), 14.0]]:
		Shapes.fill_outline(self, Shapes.ellipse(c + k[0], k[1] * 1.3, k[1], 16), Palette.ROCK, 2.0)
	Draw.tree(self, c + Vector2(10, 10), 30)
	for d in [from + 20.0, to - 20.0]:
		_portal(d)


func _portal(d: float) -> void:
	var p: Vector2 = track.sample(edge, d)
	var t: Vector2 = track.tangent(edge, d)
	var n := Vector2(-t.y, t.x)
	# Stone ring across the track, a dark mouth.
	var ring := PackedVector2Array()
	for i in 13:
		var k := -1.0 + 2.0 * i / 12.0
		ring.append(p + n * k * 44.0 + t * (1.0 - k * k) * 10.0 * (1.0 if d > (from + to) * 0.5 else -1.0))
	draw_polyline(ring, Palette.INK, 22.0)
	draw_polyline(ring, Palette.ROCK, 16.0)
	for i in range(0, 13, 3):
		draw_circle(ring[i], 5.0, Palette.ROCK.darkened(0.2))
