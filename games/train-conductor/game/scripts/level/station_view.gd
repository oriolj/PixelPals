extends Node2D
## The four stations: platform along the track, the station building (roof in
## the station colour, awning stripes, a clock without numbers, the colour's
## big shape on the roof), the stop post, and the houses on the station's
## hill whose windows light up as passengers get home.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")
const Track := preload("res://scripts/track/track.gd")

const PLATFORM_BACK := 360.0   # platform runs from mark - BACK ...
const PLATFORM_FRONT := 70.0   # ... to mark + FRONT
const PLATFORM_W := 40.0
const HOUSES := 5
## House spots on a hill, relative to its centre.
const HOUSE_SPOTS: Array[Vector2] = [Vector2(-70, -30), Vector2(10, -52), Vector2(84, -18), Vector2(-40, 38), Vector2(50, 44)]

var track
var sim
## station -> houses lit
var lit: Array[int] = [0, 0, 0, 0]
## 0..1 night amount (the finale lights every house)
var night := 0.0
var time := 0.0
## station -> seconds of "just docked" glow
var flash: Array[float] = [0.0, 0.0, 0.0, 0.0]


func setup(graph, run_sim) -> void:
	track = graph
	sim = run_sim


func _process(delta: float) -> void:
	time += delta
	for i in flash.size():
		flash[i] = maxf(0.0, flash[i] - delta)
	queue_redraw()


func normal(e: int, d: float) -> Vector2:
	var t: Vector2 = track.tangent(e, d)
	return Vector2(-t.y, t.x)


## World position of a spot on the platform: arc offset `along` from the mark
## (negative = behind), `out` px from the platform's track edge.
func platform_point(station: int, along: float, out := 20.0) -> Vector2:
	var st: Dictionary = track.stations[station]
	var d: float = st.mark + along
	return track.sample(st.edge, d) + normal(st.edge, d) * st.side * (Track.TRACK_WIDTH * 0.5 + out)


func house_pos(station: int, i: int) -> Vector2:
	return track.stations[station].hill + HOUSE_SPOTS[i % HOUSE_SPOTS.size()]


func building_pos(station: int) -> Vector2:
	return platform_point(station, -150.0, PLATFORM_W + 62.0)


func _draw() -> void:
	for s in track.stations.size():
		_draw_platform(s)
		_draw_building(s)
		_draw_houses(s)


func _draw_platform(s: int) -> void:
	var st: Dictionary = track.stations[s]
	var col: Color = Palette.station(st.colour)
	var pts := PackedVector2Array()
	var d := -PLATFORM_BACK
	while d <= PLATFORM_FRONT:
		pts.append(platform_point(s, d, PLATFORM_W * 0.5 + 2.0))
		d += 10.0
	draw_polyline(pts, Palette.INK, PLATFORM_W + 4.0, true)
	draw_polyline(pts, Palette.CREAM, PLATFORM_W)
	# Tiles and the coloured edge line along the track.
	d = -PLATFORM_BACK + 20.0
	while d < PLATFORM_FRONT:
		var a := platform_point(s, d, 4.0)
		var b := platform_point(s, d, PLATFORM_W)
		draw_line(a, b, Palette.CREAM.darkened(0.08), 2.0)
		d += 30.0
	var edge := PackedVector2Array()
	d = -PLATFORM_BACK
	while d <= PLATFORM_FRONT:
		edge.append(platform_point(s, d, 6.0))
		d += 10.0
	var glow := flash[s] > 0.0 and int(time * 8.0) % 2 == 0
	draw_polyline(edge, Palette.WHITE if glow else col, 6.0)
	# Stop post at the mark: where the engine's nose should stop.
	var post := platform_point(s, 0.0, PLATFORM_W * 0.5 + 2.0)
	var pulse := 1.0 + 0.08 * sin(time * 4.0)
	Shapes.fill_outline(self, Shapes.circle(post, 15 * pulse, 20), Palette.WHITE)
	Draw.token(self, st.colour, post, 10 * pulse)


func _draw_building(s: int) -> void:
	var st: Dictionary = track.stations[s]
	var col: Color = Palette.station(st.colour)
	var c := building_pos(s)
	var d: float = st.mark - 150.0
	var ang: float = track.tangent(st.edge, d).angle()
	var side: float = st.side
	draw_set_transform(c, ang)
	draw_colored_polygon(Shapes.rounded_rect(Rect2(-86, -44, 180, 96), 12), Color(Palette.INK, 0.2))
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-90, -48, 180, 96), 12), Palette.CREAM, 3.0)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-82, -40, 164, 80), 10), col, 2.0)
	# Roof ridge.
	draw_line(Vector2(-70, 0), Vector2(70, 0), col.darkened(0.25), 6.0)
	# Awning stripes along the platform side.
	var y0 := -48.0 if side > 0 else 48.0
	var dir := -1.0 if side > 0 else 1.0
	for i in 9:
		var x := -90.0 + i * 20.0
		var stripe := Shapes.rounded_rect(Rect2(x, minf(y0, y0 + dir * 22), 20, 22), 4)
		Shapes.fill_outline(self, stripe, Palette.WHITE if i % 2 == 0 else col.lightened(0.15), 2.0)
	draw_set_transform(Vector2.ZERO, 0.0)
	# Clock (no numbers) and the station's big shape, both kept upright.
	var clock := c + Vector2.from_angle(ang) * -52.0
	Shapes.fill_outline(self, Shapes.circle(clock, 20, 24), Palette.WHITE, 3.0)
	var hr := time * 0.05
	draw_line(clock, clock + Vector2.from_angle(hr - PI / 2) * 10.0, Palette.INK, 3.0)
	draw_line(clock, clock + Vector2.from_angle(time * 0.6 - PI / 2) * 15.0, Palette.INK, 2.0)
	var sign_at := c + Vector2.from_angle(ang) * 40.0
	Shapes.fill_outline(self, Shapes.circle(sign_at, 32, 28), Palette.WHITE, 3.0)
	Draw.token(self, st.colour, sign_at, 23, Color(), 3.0)


func _draw_houses(s: int) -> void:
	var st: Dictionary = track.stations[s]
	for i in HOUSES:
		var on := i < lit[s] or night > 0.5
		Draw.house(self, house_pos(s, i), st.colour, on, 1.3)
