extends Node2D
## The animals: cows at the farm (one likes standing on the track), ducks on
## the pond, sheep in the meadow. Two poses each: grazing/swimming, and
## looking up with an open mouth when the whistle toots nearby. The track cow
## trots aside when Sim says so.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Track := preload("res://scripts/track/track.gd")

const HEAR := 1300.0
const LOOK_TIME := 1.4

var sim
var track
var time := 0.0
## {kind, home, pos, look, phase}
var animals: Array[Dictionary] = []
var cow_aside := 0.0  # 0 = on the track, 1 = stepped aside (tweened)
var _cow_track_pos := Vector2.ZERO
var _cow_side_pos := Vector2.ZERO


func setup(run_sim) -> void:
	sim = run_sim
	track = sim.track
	var f := Track.FARM
	for p in [f + Vector2(-260, 60), f + Vector2(-60, 90)]:
		animals.append({"kind": "cow", "home": p, "pos": p, "look": 0.0, "phase": p.x})
	var c := Track.POND_CENTRE
	for i in 3:
		var p := c + Vector2(-150 + i * 60, 40 - i * 30)
		animals.append({"kind": "duck", "home": p, "pos": p, "look": 0.0, "phase": i * 2.1})
	var m := Track.MEADOW
	for p in [m + Vector2(-80, -20), m + Vector2(40, 30), m + Vector2(90, -50)]:
		animals.append({"kind": "sheep", "home": p, "pos": p, "look": 0.0, "phase": p.y})
	var e: int = sim.cow.edge
	var d: float = sim.cow.d
	var t: Vector2 = track.tangent(e, d)
	_cow_track_pos = track.sample(e, d)
	_cow_side_pos = _cow_track_pos + Vector2(-t.y, t.x) * 95.0
	cow_aside = 0.0 if sim.cow.state == "on" else 1.0


## The whistle tooted at `from`: animals in earshot look up. Returns the kind
## of the nearest one that answers ("" if nobody heard).
func whistle(from: Vector2) -> String:
	var best := ""
	var best_d := HEAR
	for a in animals:
		var d: float = from.distance_to(a.pos)
		if d < HEAR:
			a.look = LOOK_TIME
			if d < best_d:
				best_d = d
				best = a.kind
	var dc := from.distance_to(track_cow_pos())
	if dc < HEAR:
		_track_cow_look = LOOK_TIME
		if dc < best_d:
			best = "cow"
	return best


var _track_cow_look := 0.0


func track_cow_pos() -> Vector2:
	return _cow_track_pos.lerp(_cow_side_pos, cow_aside)


func _process(delta: float) -> void:
	time += delta
	var want := 0.0 if sim.cow.state == "on" else 1.0
	cow_aside = move_toward(cow_aside, want, delta * 1.6)
	_track_cow_look = maxf(0.0, _track_cow_look - delta)
	for a in animals:
		a.look = maxf(0.0, a.look - delta)
		if a.kind == "duck":
			var ph: float = a.phase
			a.pos = a.home + Vector2(cos(time * 0.4 + ph) * 60.0, sin(time * 0.4 + ph) * 25.0)
	queue_redraw()


func _draw() -> void:
	for a in animals:
		match a.kind:
			"cow":
				_cow(a.pos, a.look > 0.0, a.phase)
			"duck":
				_duck(a.pos, a.look > 0.0, a.phase)
			"sheep":
				_sheep(a.pos, a.look > 0.0, a.phase)
	var trot := absf(sin(time * 14.0)) * 5.0 if cow_aside > 0.0 and cow_aside < 1.0 else 0.0
	var worried: bool = sim.cow.state == "on" and sim.cow.patience > 0.0
	_cow(track_cow_pos() + Vector2(0, -trot), _track_cow_look > 0.0 or worried, 1.0)


func _cow(p: Vector2, look: bool, ph: float) -> void:
	draw_colored_polygon(Shapes.ellipse(p + Vector2(4, 22), 34, 9, 18), Color(Palette.INK, 0.2))
	for x in [-18.0, -8.0, 10.0, 20.0]:
		draw_line(p + Vector2(x, 6), p + Vector2(x, 22), Palette.INK, 5.0)
	Shapes.fill_outline(self, Shapes.ellipse(p, 32, 18, 24), Palette.WHITE, 2.0)
	draw_colored_polygon(Shapes.ellipse(p + Vector2(-10, -4), 9, 7, 14), Palette.BLACK)
	draw_colored_polygon(Shapes.ellipse(p + Vector2(12, 5), 7, 6, 14), Palette.BLACK)
	draw_line(p + Vector2(-32, -2), p + Vector2(-40, 10 + sin(time * 3.0 + ph) * 4.0), Palette.INK, 3.0)
	var head := p + (Vector2(32, -16) if look else Vector2(34, 8))
	Shapes.fill_outline(self, Shapes.ellipse(head, 15, 13, 20), Palette.WHITE, 2.0)
	for x in [-10.0, 10.0]:
		draw_line(head + Vector2(x * 0.6, -10), head + Vector2(x, -18), Palette.INK, 4.0)
		draw_line(head + Vector2(x * 0.6, -10), head + Vector2(x, -18), Palette.CREAM, 2.0)
	Shapes.fill_outline(self, Shapes.ellipse(head + Vector2(0, 7), 11, 7, 16), Palette.PINK, 2.0)
	draw_circle(head + Vector2(-5, -3), 2.2, Palette.INK)
	draw_circle(head + Vector2(5, -3), 2.2, Palette.INK)
	if look:
		draw_colored_polygon(Shapes.ellipse(head + Vector2(0, 9), 4, 3, 10), Palette.INK)


func _duck(p: Vector2, look: bool, ph: float) -> void:
	var face := 1.0 if sin(time * 0.4 + ph) < 0.0 else -1.0
	draw_colored_polygon(Shapes.ellipse(p + Vector2(0, 8), 24, 7, 16), Color(Palette.WATER_DARK, 0.8))
	Shapes.fill_outline(self, Shapes.ellipse(p, 20, 12, 20), Palette.WHITE, 2.0)
	draw_colored_polygon(Shapes.ellipse(p + Vector2(-4 * face, -2), 10, 6, 14), Palette.CREAM.darkened(0.08))
	var head := p + Vector2(15 * face, -14 if look else -9)
	Shapes.fill_outline(self, Shapes.circle(head, 9, 18), Palette.STATION[3].lightened(0.2), 2.0)
	draw_circle(head + Vector2(3 * face, -2), 1.8, Palette.INK)
	var bx := 9.0 * face
	var beak := PackedVector2Array([head + Vector2(bx * 0.6, -1), head + Vector2(bx * 1.6, 1 if not look else -3),
		head + Vector2(bx * 0.6, 4)])
	Shapes.fill_outline(self, beak, Palette.STATION[2], 1.5)
	if look:
		var beak2 := PackedVector2Array([head + Vector2(bx * 0.6, 3), head + Vector2(bx * 1.5, 7), head + Vector2(bx * 0.6, 5)])
		Shapes.fill_outline(self, beak2, Palette.STATION[2], 1.5)


func _sheep(p: Vector2, look: bool, ph: float) -> void:
	draw_colored_polygon(Shapes.ellipse(p + Vector2(4, 20), 30, 8, 16), Color(Palette.INK, 0.2))
	for x in [-12.0, 12.0]:
		draw_line(p + Vector2(x, 8), p + Vector2(x, 20), Palette.INK, 5.0)
	for k in 7:
		var q := p + Vector2(cos(k * 0.9) * 18.0, sin(k * 0.9) * 10.0)
		Shapes.fill_outline(self, Shapes.circle(q, 11, 16), Palette.WHITE, 2.0)
	draw_colored_polygon(Shapes.ellipse(p, 20, 12, 18), Palette.WHITE)
	var head := p + (Vector2(22, -14) if look else Vector2(24, 2))
	Shapes.fill_outline(self, Shapes.ellipse(head, 9, 11, 16), Palette.BLACK, 2.0)
	draw_circle(head + Vector2(-3, -2), 1.8, Palette.WHITE)
	draw_circle(head + Vector2(3, -2), 1.8, Palette.WHITE)
	Shapes.fill_outline(self, Shapes.circle(head + Vector2(0, -10), 6, 12), Palette.WHITE, 1.5)
	if look:
		draw_colored_polygon(Shapes.ellipse(head + Vector2(0, 6), 3, 2.5, 10), Palette.PINK)
