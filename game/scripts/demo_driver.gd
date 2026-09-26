extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> level
## -> party -> select ...

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const DEMO_RUN_SECONDS := 20.0

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
	Game.run_seconds = DEMO_RUN_SECONDS
	match start_screen:
		"select":
			seat_three()
		"level":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
		"party":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			Game.stars = 37
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
		Game.run_seconds = DEMO_RUN_SECONDS  # the next level ends quickly too


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
		"level":
			# Driver: weave on a sine, plus a sideways dodge now and then.
			var dodge := 0.0
			var ph := fmod(time, 3.0)
			if ph > 2.2 and ph < 2.7:
				dodge = 1.0 if int(time / 3.0) % 2 == 0 else -1.0
			st[0]["move"] = Vector2(dodge + 0.2 * sin(time * 0.7), sin(time * 1.6)).limit_length(1.0)
			# Gunner: rotate through the four directions every 1.5 s, firing.
			var dirs := [Vector2.RIGHT, Vector2.UP, Vector2.LEFT, Vector2.DOWN]
			st[1]["move"] = dirs[int(time / 1.5) % 4]
			st[1]["a"] = true
			# Honker: a press every two seconds.
			st[2]["a"] = fmod(time, 2.0) < 0.15
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 5.0)
			st[0]["start"] = _pulse(time, 5.6)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
