extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed. "finale" is a demo-only start: the level a few seconds
## before the run ends, to capture the night.
##
## Level script: the engine throttles to cruise and brakes when the distance
## to the next useful platform drops below its braking curve, then leaves once
## the passengers are done; the points seat flips toward the beacon colour of
## the oldest passenger aboard and opens the doors; the whistle seat presses
## every 3 s and at every station.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const CRUISE := 230.0
const DEMO_SEED := 7

var use_goto := true
var screen := ""
var t := 0.0
## Level bookkeeping.
var _flick_cool := 0.0
var _last_whistle := -10.0
var _docked_at := -1.0
var _was_docked := false


func _init() -> void:
	# Run before Players polls (-100), so scripted input lands the same frame.
	process_priority = -200


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	if not Game.DEMO_SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	Game.seed_value = DEMO_SEED
	Game.run_seconds = 360.0
	Game.level_setup = {}
	match start_screen:
		"select":
			seat_three()
		"level", "finale":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			if start_screen == "finale":
				Game.level_setup = {"deliveries": 11, "time_left": 6.0}
		"party":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			Game.deliveries.assign([0, 1, 2, 3, 0, 2, 1, 3, 2, 0, 1, 3])
			Game.perfect_stops = 3
			Game.stars = 15
	screen = "level" if start_screen == "finale" else start_screen
	t = 0.0
	if use_goto:
		Game.goto(screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_docked_at = -1.0
	_was_docked = false
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "select":
		Game.level_setup = {}


func _process(delta: float) -> void:
	t += delta
	drive(screen, t, delta)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float, delta := 1.0 / 30.0) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	match screen_name:
		"join":
			for i in 3:
				st[i]["a"] = _pulse(time, 0.8 + i * 1.0)
			st[0]["a"] = st[0]["a"] or (time >= 3.6 and time < 4.9)
			st[0]["start"] = _pulse(time, 5.2)
		"select":
			st[0]["move"] = Vector2(_flick(time, 0.6) + _flick(time, 1.3), 0)
			st[1]["move"] = Vector2(-_flick(time, 0.9), 0)
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 2.2)
			st[1]["a"] = _pulse(time, 2.8)
		"level":
			var lvl := Game.current
			if lvl != null and is_instance_valid(lvl) and lvl.get("sim") != null:
				_drive_level(lvl.sim, time, delta, st)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_level(sim, time: float, delta: float, st: Array[Dictionary]) -> void:
	_flick_cool = maxf(0.0, _flick_cool - delta)
	# Whistle: every 3 s, and once at every station.
	var docked: bool = sim.mode == "docked"
	if docked and not _was_docked:
		_docked_at = time
		st[2]["a"] = true
		_last_whistle = time
	elif time - _last_whistle >= 3.0:
		st[2]["a"] = true
		_last_whistle = time
	_was_docked = docked
	# Driver.
	match sim.mode:
		"docked":
			if time - _docked_at > 0.6 and time - _docked_at < 0.75:
				st[1]["a"] = true  # the points seat opens the doors
			if sim.exchange_done and time - _docked_at > 1.0:
				st[0]["move"] = Vector2(0, -1)
		"run":
			var ns: Array = sim.next_station_ahead()
			var v: float = sim.train.speed
			var brake_at: float = v * v / (2.0 * sim.BRAKE * 0.85) + v * 0.12 + 8.0
			if ns[0] != -1 and _worth_stopping(sim, ns[0]) and ns[1] <= brake_at:
				st[0]["move"] = Vector2(0, 1)
			elif v < CRUISE:
				st[0]["move"] = Vector2(0, -1)
	# Points: toward the oldest passenger's colour.
	var n: int = sim.target_junction
	if n != -1 and not sim.locked and _flick_cool <= 0.0:
		var want := _wanted_branch(sim, n)
		if want != -1 and want != sim.choices[n]:
			st[1]["move"] = Vector2(_flick_for(sim, n, want))
			_flick_cool = 0.5


func _worth_stopping(sim, station: int) -> bool:
	var colour: int = sim.track.stations[station].colour
	for p in sim.aboard():
		if p.colour == colour:
			return true
	return not sim.waiting_at(station).is_empty()


func _wanted_branch(sim, n: int) -> int:
	var colour: int = sim.oldest_aboard_colour()
	if colour != -1:
		for b in 2:
			if sim.track.beacon(sim.track.out_edges[n][b]).has(colour):
				return b
	return sim.tour_choice(n)


func _flick_for(sim, n: int, want: int) -> Vector2i:
	for v in [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]:
		if sim.track.branch_for_flick(n, Vector2(v)) == want:
			return v
	return Vector2i.RIGHT  # across both branches: toggles, and want is the other one


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
