extends Node2D
## The points: at each junction a switch blade (the first stretch of track
## swings over to the chosen branch), a big two-way sign before it whose
## arrow points where the train will go, and a coloured beacon on each branch
## showing which station lies that way. The next junction ahead glows; its
## sign flashes when it has locked.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")
const Track := preload("res://scripts/track/track.gd")

const BLADE_LEN := 130.0
const SIGN_BACK := 110.0
const SIGN_OUT := 100.0

var track
var sim
var time := 0.0
## junction node -> {blade, angle, sign_pos, beacons: [[pos, colours]], wiggle, pop}
var junctions := {}


func setup(graph, run_sim) -> void:
	track = graph
	sim = run_sim
	for n in track.junctions:
		var pos: Vector2 = track.node_pos[n]
		var dir: Vector2 = track.node_dir[n]
		var nrm := Vector2(-dir.y, dir.x)
		var d0: Vector2 = track.branch_dir(n, 0)
		var d1: Vector2 = track.branch_dir(n, 1)
		var lateral := nrm.dot((d0 + d1) * 0.5)
		var side := -1.0 if lateral >= -0.05 else 1.0
		var beacons := []
		for b in 2:
			var e: int = track.out_edges[n][b]
			var at := 230.0
			var p: Vector2 = track.sample(e, at)
			var t: Vector2 = track.tangent(e, at)
			var bn := Vector2(-t.y, t.x)
			var other: Vector2 = track.sample(track.out_edges[n][1 - b], at)
			var away := -1.0 if bn.dot(other - p) > 0.0 else 1.0
			beacons.append([p + bn * away * 62.0, track.beacon(e)])
		var choice: int = sim.choices[n]
		junctions[n] = {"blade": float(choice), "angle": _branch_angle(n, choice),
			"sign_pos": pos - dir * SIGN_BACK + nrm * side * SIGN_OUT, "beacons": beacons,
			"wiggle": 0.0, "pop": 0.0, "blade_pts": [track.polyline(track.out_edges[n][0], 6.0),
			track.polyline(track.out_edges[n][1], 6.0)]}


func _branch_angle(n: int, b: int) -> float:
	return track.branch_dir(n, b).angle()


func on_event(kind: String, data: Dictionary) -> void:
	if not data.has("junction") or not junctions.has(data.junction):
		return
	var j: Dictionary = junctions[data.junction]
	match kind:
		"points":
			j.pop = 1.0
		"points_same", "points_locked":
			j.wiggle = 1.0


func _process(delta: float) -> void:
	time += delta
	for n in junctions:
		var j: Dictionary = junctions[n]
		var want: int = sim.choices[n]
		j.blade = move_toward(j.blade, float(want), delta * 5.0)
		j.angle = lerp_angle(j.angle, _branch_angle(n, want), minf(1.0, delta * 12.0))
		j.wiggle = maxf(0.0, j.wiggle - delta * 3.0)
		j.pop = maxf(0.0, j.pop - delta * 3.0)
	queue_redraw()


func _draw() -> void:
	for n in junctions:
		_draw_blade(n)
	for n in junctions:
		for bc in junctions[n].beacons:
			_draw_beacon(bc[0], bc[1], n)
	for n in junctions:
		_draw_sign(n)


func _draw_blade(n: int) -> void:
	var j: Dictionary = junctions[n]
	var a: PackedVector2Array = j.blade_pts[0]
	var b: PackedVector2Array = j.blade_pts[1]
	var count := mini(int(BLADE_LEN / 6.0), mini(a.size(), b.size()))
	var t: float = j.blade
	var pts := PackedVector2Array()
	for i in count:
		pts.append(a[i].lerp(b[i], t))
	draw_polyline(pts, Palette.TRACK, Track.TRACK_WIDTH - 4.0)
	for off in [-11.0, 11.0]:
		draw_polyline(Shapes.offset_polyline(pts, off), Palette.GROOVE, 6.0)
	# The blade's pivot pin.
	Shapes.fill_outline(self, Shapes.circle(track.node_pos[n], 7, 14), Palette.GROOVE.darkened(0.2))


func _draw_beacon(p: Vector2, colours: Array, n: int) -> void:
	var active: bool = n == sim.target_junction
	var pulse := 1.0 + (0.12 * sin(time * 5.0) if active else 0.0)
	var r := 17.0 * pulse
	var w := colours.size() * (r * 2.0 + 6.0)
	var x0 := p.x - w * 0.5 + r + 3.0
	draw_line(p + Vector2(0, 8), p + Vector2(0, 34), Palette.INK, 6.0)
	draw_line(p + Vector2(0, 8), p + Vector2(0, 34), Palette.TRACK_LIGHT, 3.0)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(p.x - w * 0.5, p.y - r - 5.0, w, r * 2.0 + 10.0), 10), Palette.WHITE, 2.0)
	for i in colours.size():
		Draw.token(self, colours[i], Vector2(x0 + i * (r * 2.0 + 6.0), p.y), r)


func _draw_sign(n: int) -> void:
	var j: Dictionary = junctions[n]
	var active: bool = n == sim.target_junction
	var p: Vector2 = j.sign_pos
	var s := 1.0 if active else 0.72
	s *= 1.0 + 0.25 * j.pop
	var shake: float = sin(time * 40.0) * 6.0 * j.wiggle
	p.x += shake
	# Post and base.
	draw_line(p + Vector2(0, 20 * s), p + Vector2(0, 60 * s), Palette.INK, 9.0)
	draw_line(p + Vector2(0, 20 * s), p + Vector2(0, 60 * s), Palette.TRACK, 5.0)
	if active:
		var glow := Palette.GLOW
		if sim.locked and int(time * 8.0) % 2 == 0:
			glow = Palette.WHITE
		draw_colored_polygon(Shapes.circle(p, 54 * s, 32), Color(glow, 0.45 + 0.15 * sin(time * 6.0)))
	var board := Palette.WHITE
	if active and sim.locked:
		board = Palette.CREAM if int(time * 8.0) % 2 == 0 else Palette.GLOW
	Shapes.fill_outline(self, Shapes.circle(p, 40 * s, 32), board, 3.0)
	# The two possible ways as faint arrows, the chosen one bold.
	for b in 2:
		var ang := _branch_angle(n, b)
		var ghost := Shapes.xform(Shapes.arrow(56 * s, 12 * s, 26 * s), Transform2D(ang, p))
		draw_colored_polygon(ghost, Color(Palette.INK, 0.12))
	var arrow := Shapes.xform(Shapes.arrow(66 * s, 18 * s, 38 * s), Transform2D(j.angle, p))
	var chosen: int = sim.choices[n]
	var col := Palette.BLACK
	Shapes.fill_outline(self, arrow, col, 3.0)
	# Tiny beacon tokens of the chosen branch at the arrow's tail.
	var colours: Array = j.beacons[chosen][1]
	for i in colours.size():
		var at := p - Vector2.from_angle(j.angle) * 26.0 * s + Vector2(0, 30 * s) + Vector2((i - (colours.size() - 1) * 0.5) * 20.0 * s, 0)
		Draw.token(self, colours[i], at, 9.0 * s, Color(), 1.5)
