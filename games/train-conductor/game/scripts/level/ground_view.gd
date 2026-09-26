extends Node2D
## The landscape under the track, drawn once: grass, station hills, the pond,
## the farm field, the sheep meadow, trees and flowers. Everything is placed
## from Track data plus a seeded scatter that keeps clear of the rails.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")
const Track := preload("res://scripts/track/track.gd")

var track
var trees: Array[Vector3] = []   # x, y, radius
var flowers: Array[Vector3] = []  # x, y, colour index
var patches: Array[Vector3] = []  # darker grass blobs
var _track_pts := PackedVector2Array()
var _keep_out: Array[Vector3] = []


func setup(graph) -> void:
	track = graph
	for e in track.curves.size():
		_track_pts.append_array(track.polyline(e, 16.0))
	for st in track.stations:
		var n: Vector2 = _normal(st.edge, st.mark) * st.side
		_keep_out.append(Vector3(st.pos.x + n.x * 120, st.pos.y + n.y * 120, 150))
		_keep_out.append(Vector3(st.hill.x, st.hill.y, 170))
	_keep_out.append(Vector3(Track.POND_CENTRE.x, Track.POND_CENTRE.y, 280))
	_keep_out.append(Vector3(Track.FARM.x, Track.FARM.y, 260))
	_keep_out.append(Vector3(Track.MEADOW.x, Track.MEADOW.y, 190))
	for n in track.junctions:
		_keep_out.append(Vector3(track.node_pos[n].x, track.node_pos[n].y, 170))
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	var tries := 0
	while trees.size() < 70 and tries < 4000:
		tries += 1
		var p := Vector2(rng.randf_range(40, Track.WORLD.x - 40), rng.randf_range(40, Track.WORLD.y - 40))
		var r := rng.randf_range(26, 44)
		if _clear(p, r + 58.0) and _far_from_trees(p, r + 30.0):
			trees.append(Vector3(p.x, p.y, r))
	tries = 0
	while flowers.size() < 260 and tries < 6000:
		tries += 1
		var p := Vector2(rng.randf_range(20, Track.WORLD.x - 20), rng.randf_range(20, Track.WORLD.y - 20))
		if _clear(p, 40.0):
			flowers.append(Vector3(p.x, p.y, rng.randi() % 3))
	for i in 60:
		patches.append(Vector3(rng.randf_range(0, Track.WORLD.x), rng.randf_range(0, Track.WORLD.y), rng.randf_range(60, 160)))
	queue_redraw()


func _normal(e: int, d: float) -> Vector2:
	var t: Vector2 = track.tangent(e, d)
	return Vector2(-t.y, t.x)


func dist_to_track(p: Vector2) -> float:
	var best := INF
	for q in _track_pts:
		best = minf(best, p.distance_squared_to(q))
	return sqrt(best)


func _clear(p: Vector2, margin: float) -> bool:
	for k in _keep_out:
		if p.distance_to(Vector2(k.x, k.y)) < k.z:
			return false
	return dist_to_track(p) > margin


func _far_from_trees(p: Vector2, margin: float) -> bool:
	for t in trees:
		if p.distance_to(Vector2(t.x, t.y)) < t.z + margin:
			return false
	return true


func _draw() -> void:
	var w := Track.WORLD
	draw_rect(Rect2(Vector2(-800, -800), w + Vector2(1600, 1600)), Palette.GRASS)
	for pch in patches:
		draw_colored_polygon(Shapes.ellipse(Vector2(pch.x, pch.y), pch.z, pch.z * 0.6, 24), Color(Palette.GRASS_DARK, 0.35))
	# Station hills (their houses are drawn by the station view).
	for st in track.stations:
		var h: Vector2 = st.hill
		draw_colored_polygon(Shapes.ellipse(h + Vector2(8, 12), 150, 105, 36), Color(Palette.GRASS_DARK, 0.7))
		draw_colored_polygon(Shapes.ellipse(h, 146, 100, 36), Palette.GRASS.lightened(0.18))
		draw_colored_polygon(Shapes.ellipse(h + Vector2(-20, -18), 100, 62, 30), Palette.GRASS.lightened(0.3))
	_draw_pond()
	_draw_farm()
	_draw_meadow()
	for f in flowers:
		var c: Color = [Palette.PINK, Palette.WHITE, Palette.GLOW][int(f.z)]
		var p := Vector2(f.x, f.y)
		for k in 5:
			draw_circle(p + Vector2.from_angle(TAU * k / 5.0) * 4.0, 3.0, c)
		draw_circle(p, 2.2, Palette.STATION[2])
	for t in trees:
		Draw.tree(self, Vector2(t.x, t.y), t.z, fmod(t.x * 0.013, 1.0) * 0.5)


func _draw_pond() -> void:
	var c := Track.POND_CENTRE
	var s := Track.POND_SIZE
	Shapes.fill_outline(self, Shapes.ellipse(c, s.x + 14, s.y + 14, 48), Palette.SOIL, 2.0)
	draw_colored_polygon(Shapes.ellipse(c, s.x, s.y, 48), Palette.WATER_DARK)
	draw_colored_polygon(Shapes.ellipse(c + Vector2(-10, -8), s.x - 18, s.y - 16, 48), Palette.WATER)
	for i in 5:
		var p := c + Vector2(-230 + i * 95, -80 + (i % 2) * 150)
		draw_arc(p, 18, 0.3, PI - 0.3, 10, Color(Palette.WHITE, 0.6), 3.0)
	for lp in [c + Vector2(-190, 60), c + Vector2(-240, -30), c + Vector2(210, 90), c + Vector2(250, -60)]:
		var pad := Shapes.circle(lp, 20, 18)
		Shapes.fill_outline(self, pad, Palette.LEAF_LIGHT, 2.0)
		draw_colored_polygon(PackedVector2Array([lp, lp + Vector2(22, -6), lp + Vector2(22, 8)]), Palette.WATER)
		draw_circle(lp + Vector2(-5, -4), 5, Palette.PINK)


func _draw_farm() -> void:
	var c := Track.FARM
	var field := Rect2(c + Vector2(-420, 0), Vector2(620, 150))
	Shapes.fill_outline(self, Shapes.rounded_rect(field, 18), Palette.SOIL, 2.0)
	for i in 7:
		var y := field.position.y + 14 + i * 20
		draw_line(Vector2(field.position.x + 16, y), Vector2(field.end.x - 16, y), Palette.SOIL.darkened(0.15), 6.0)
	for i in 12:
		var p := Vector2(field.position.x + 40 + i * 48, field.position.y + 30 + (i % 3) * 40)
		draw_circle(p, 8, Palette.LEAF_LIGHT)
		draw_circle(p + Vector2(-3, -3), 3, Palette.GRASS)
	# Barn.
	var barn := Rect2(c + Vector2(260, -10), Vector2(150, 110))
	Shapes.fill_outline(self, Shapes.rounded_rect(barn, 6), Palette.STATION[0])
	draw_colored_polygon(PackedVector2Array([barn.position + Vector2(0, 55), barn.position + Vector2(75, 10),
		barn.position + Vector2(150, 55)]), Palette.STATION[0].darkened(0.2))
	draw_line(barn.position + Vector2(75, 12), barn.position + Vector2(75, 108), Palette.WHITE, 4.0)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(barn.position + Vector2(50, 60), Vector2(50, 50)), 4), Palette.WHITE, 2.0)
	draw_line(barn.position + Vector2(52, 62), barn.position + Vector2(98, 108), Palette.STATION[0], 4.0)
	draw_line(barn.position + Vector2(98, 62), barn.position + Vector2(52, 108), Palette.STATION[0], 4.0)
	Draw.fence(self, c + Vector2(-440, -20), c + Vector2(220, -20))


func _draw_meadow() -> void:
	var c := Track.MEADOW
	draw_colored_polygon(Shapes.ellipse(c, 170, 120, 36), Palette.GRASS.lightened(0.12))
	Draw.fence(self, c + Vector2(-170, 110), c + Vector2(170, 110))
	for i in 9:
		var p := c + Vector2(-120 + (i % 3) * 110, -70 + (i / 3) * 60)
		for k in 5:
			draw_circle(p + Vector2.from_angle(TAU * k / 5.0) * 5.0, 3.5, Palette.WHITE)
		draw_circle(p, 3.0, Palette.STATION[2])
