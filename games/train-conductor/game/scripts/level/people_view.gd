extends Node2D
## Passengers: waiting in a row on their platform (they wave when the train
## is in), hopping into a carriage window, riding (a head with its hat in the
## window), hopping off at their colour and dancing up the hill into a house,
## whose window then lights up.
##
## The rules live in Sim; this view only animates the changes it sees.

signal arrived_home(station: int, colour: int)

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")

const HOP_TIME := 0.45
const WALK_SPEED := 190.0
const SLOT_GAP := 36.0
const SCALE := 1.25

var sim
var stations  # StationView
var train_view  # TrainView
var time := 0.0
## passenger id -> {mode, pos, from, t, house, station, colour, seat, pop}
var recs := {}
## station -> houses already promised to walkers
var _promised: Array[int] = [0, 0, 0, 0]


func setup(run_sim, station_view, train_v) -> void:
	sim = run_sim
	stations = station_view
	train_view = train_v


func _slot(p: Dictionary) -> Vector2:
	var k := 0
	for q in sim.waiting_at(p.station):
		if q.id == p.id:
			break
		k += 1
	# Stopped short? The queue shuffles toward the train's carriages.
	var shift := 0.0
	if sim.mode == "docked" and sim.dock_station == p.station:
		shift = -30.0
	return stations.platform_point(p.station, -80.0 - k * SLOT_GAP + shift, 20.0)


func _process(delta: float) -> void:
	time += delta
	for p in sim.passengers:
		var r: Dictionary = recs.get(p.id, {})
		if r.is_empty():
			if p.state != "waiting":
				continue
			r = {"mode": "wait", "pos": _slot(p), "from": Vector2.ZERO, "t": 0.0, "house": 0,
				"station": p.station, "colour": p.colour, "seat": -1, "pop": 0.4}
			recs[p.id] = r
		r.pop = maxf(0.0, r.pop - delta)
		match r.mode:
			"wait":
				if p.state == "aboard":
					_start(r, "hop_on")
					r.seat = p.seat
				else:
					r.pos = r.pos.move_toward(_slot(p), delta * 120.0)
			"hop_on":
				r.t += delta
				if p.state == "home":
					_start(r, "hop_off")
				elif r.t >= HOP_TIME:
					r.mode = "ride"
			"ride":
				r.seat = p.seat
				r.pos = train_view.seat_position(r.seat)
				if p.state == "home":
					_start(r, "hop_off")
					r.station = p.station
			"hop_off":
				r.t += delta
				if r.t >= HOP_TIME:
					r.mode = "walk"
					r.house = mini(_promised[r.station], stations.HOUSES - 1)
					_promised[r.station] += 1
					r.from = r.pos
			"walk":
				var goal: Vector2 = stations.house_pos(r.station, r.house) + Vector2(0, 14)
				r.pos = r.pos.move_toward(goal, delta * WALK_SPEED)
				if r.pos.distance_to(goal) < 2.0:
					r.mode = "home"
					arrived_home.emit(r.station, r.colour)
	queue_redraw()


func _start(r: Dictionary, mode: String) -> void:
	r.mode = mode
	r.t = 0.0
	r.from = r.pos


func _hop_pos(r: Dictionary) -> Vector2:
	var k := clampf(r.t / HOP_TIME, 0.0, 1.0)
	var goal: Vector2
	if r.mode == "hop_on":
		goal = train_view.seat_position(r.seat)
	else:
		goal = stations.platform_point(r.station, -40.0, 22.0)
	return r.from.lerp(goal, k) + Vector2(0, -sin(k * PI) * 46.0)


func _draw() -> void:
	for id in recs:
		var r: Dictionary = recs[id]
		match r.mode:
			"wait":
				var excited: bool = sim.mode == "docked" and sim.dock_station == r.station
				var bob := absf(sin(time * (7.0 if excited else 2.5) + id)) * (7.0 if excited else 2.0)
				var s := SCALE
				if r.pop > 0.0:
					s = SCALE * (1.0 + 0.4 * sin(r.pop / 0.4 * PI))
				Draw.passenger(self, r.pos, r.colour, s, bob, 1.0 if excited else 0.0, excited)
			"hop_on", "hop_off":
				Draw.passenger(self, _hop_pos(r), r.colour, SCALE * 0.95, 0.0, 1.0, true)
			"ride":
				Draw.head(self, r.pos, r.colour, 1.25)
			"walk":
				var dance := absf(sin(time * 9.0 + id)) * 9.0
				Draw.passenger(self, r.pos, r.colour, SCALE, dance, 1.0 if int(time * 4.0) % 2 == 0 else 0.3, true)
