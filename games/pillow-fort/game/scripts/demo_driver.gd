extends Node
## Demo mode: scripted players for `make demo` / `make shot` / `make light-check`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> fort
## -> party -> select ...
##
## Fort script: the flashlight sweeps a path over four spots (two of them
## hide toys); the seeker hops right and lifts (an empty spot: the sleepy
## mouse), hops right again and lifts (a toy); the peekaboo seat presses at
## 3 s, 7 s (and again inside the cooldown: a twinkle) and 12 s. The round
## lasts DEMO_RUN_SECONDS, then the other toys walk out and the lamp fades on.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const DEMO_RIDERS: Array[String] = ["penguin", "fox", "frog"]
const DEMO_RUN_SECONDS := 20.0
## The flashlight's path: laundry, floor box, floor pillow, fort pillow, then home.
const SWEEP_SPOTS: Array[int] = [2, 10, 11, 4]
const SWEEP_TOYS := {10: "ball", 4: "duck"}
const PEEKABOO_AT: Array[float] = [3.0, 7.0, 7.4, 12.0]

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0
## Fort: the two spots the seeker hops to (computed from the spot graph).
var seek_path: Array[int] = []


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
	Game.round_seconds = DEMO_RUN_SECONDS
	match start_screen:
		"select":
			seat_three()
		"fort", "party":
			seat_three()
			for s in 3:
				Players.riders[s] = DEMO_RIDERS[s]
			Game.toys_found.assign(Game.TOYS)
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)
	else:
		_on_screen_changed(start_screen)


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
		Game.round_seconds = DEMO_RUN_SECONDS  # the next round ends quickly too
	if screen_name == "fort" and Game.current and Game.current.has_method("hide_toys"):
		setup_fort(Game.current)


## Places the toys the script needs: two on the sweep path, one where the
## seeker's second hop lands, none where the first lands (the mouse is there).
func setup_fort(fort: Node) -> void:
	var first: int = fort.graph.hop(fort.paw_spot, Vector2i.RIGHT)
	var second: int = fort.graph.hop(first, Vector2i.RIGHT)
	seek_path = [first, second]
	var placement := SWEEP_TOYS.duplicate()
	placement[second] = "teddy"
	var rest: Array = Game.TOYS.filter(func(x): return not placement.values().has(x))
	for i in fort.spots.size():
		if rest.is_empty():
			break
		if placement.has(i) or i == first or SWEEP_SPOTS.has(i):
			continue
		placement[i] = rest.pop_front()
	fort.hide_toys(placement)
	fort._surprise_bag.assign(["cookie", "sock", "sleepy_mouse"])  # the mouse comes first


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float) -> void:
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
		"fort":
			st[0]["move"] = _flashlight_move(time)
			# Seeker: hop right, lift (empty), hop right, lift (toy), then wander.
			var hop := Vector2.ZERO
			if _flick(time, 1.0) > 0.0 or _flick(time, 4.0) > 0.0:
				hop = Vector2.RIGHT
			elif _flick(time, 9.0) > 0.0 or _flick(time, 13.0) > 0.0:
				hop = Vector2.DOWN
			elif _flick(time, 10.0) > 0.0 or _flick(time, 15.0) > 0.0:
				hop = Vector2.LEFT
			st[1]["move"] = hop
			st[1]["a"] = _pulse(time, 1.8) or _pulse(time, 5.0) or _pulse(time, 11.0) or _pulse(time, 16.0)
			for at in PEEKABOO_AT:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, at)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


## Steers the light toward the current sweep waypoint (stick-like, analog).
func _flashlight_move(time: float) -> Vector2:
	var fort := Game.current
	if fort == null or not ("light_pos" in fort):
		return Vector2.ZERO
	var target := sweep_target(time, fort)
	var d: Vector2 = target - fort.light_pos
	if d.length() < 2.0:
		return Vector2.ZERO
	return d.normalized() * clampf(d.length() / 24.0, 0.35, 1.0)


## Each sweep spot gets 2.5 s (travel, then rest on it), then the light
## drifts back to the fort to watch the peekaboo friends.
func sweep_target(time: float, fort: Node) -> Vector2:
	var k := int(time / 2.5)
	if k < SWEEP_SPOTS.size():
		return Vector2(fort.spots[SWEEP_SPOTS[k]].pos)
	var loop := [Vector2(160, 80), Vector2(250, 96), Vector2(200, 120), Vector2(120, 60)]
	return loop[int((time - 10.0) / 2.5) % loop.size()]


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
