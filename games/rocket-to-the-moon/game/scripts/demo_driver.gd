extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> launch
## -> flight -> party -> select ... The trip is shortened (Game.trip_scale) so
## one capture reaches the Moon and the landing.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const DEMO_TRIP_SCALE := 0.2

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0


func _init() -> void:
	# Run before Players polls (-100), so scripted input lands the same frame.
	process_priority = -200


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	if not Game.SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	Game.trip_scale = DEMO_TRIP_SCALE
	Game.album.clear()
	Game.new_trip()
	match start_screen:
		"select":
			seat_three()
		"launch", "flight":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
		"party":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			Game.fuel = 23
			Game.album.assign([1, 3, 4])
			Game.trip_planets.assign([2, 5, 7])
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "select":
		Game.trip_scale = DEMO_TRIP_SCALE  # the next trip is short too


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	match screen_name:
		"join":
			# One device joins per second, then the driver holds "a" (the
			# ring fills) and, as a fallback, presses start.
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
		"launch":
			# The Launcher presses at 1 s, then mashes during the count: it
			# only shakes the rocket, the count keeps its pace.
			st[2]["a"] = _pulse(time, 1.0) or (time > 1.6 and time < 6.5 and fmod(time, 0.3) < 0.1)
		"flight":
			# Pilot: weave on a sine, with a sideways dodge now and then.
			var dodge := 0.0
			var ph := fmod(time, 3.0)
			if ph > 2.2 and ph < 2.6:
				dodge = 1.0 if int(time / 3.0) % 2 == 0 else -1.0
			st[0]["move"] = Vector2(0.8 * sin(time * 0.9) + dodge, 0.4 * sin(time * 1.7)).limit_length(1.0)
			# Grabber: a new direction every second, and a shot every second.
			var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
			st[1]["move"] = dirs[int(time) % dirs.size()]
			st[1]["a"] = fmod(time, 1.0) > 0.3 and fmod(time, 1.0) < 0.4
			# Launcher: a press every 3 s (booster, or the pending transition).
			st[2]["a"] = fmod(time, 3.0) < 0.1
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 9.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
