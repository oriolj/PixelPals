extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> kitchen
## -> party -> select ...
##
## Kitchen script (PLAN.md): the flipper presses whenever the pancake is
## golden (and once mid-air for a spin); the cook tracks the landing point
## but deliberately misses the first flip (the dog gag); the topper waits for
## the first serve (a plain stack, a small reaction), then cycles the four
## toppings, one drop every 1.2 s; the cook serves as soon as the plate
## glows. Two customers and a 25 s round, so the 7-minute rule (here 25 s)
## serves the second one a loaded stack (the big reaction). The demo round
## starts with two pancakes on the plate so a 25 s capture reaches a serve.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const DEMO_CHEFS: Array[String] = ["bunny", "fox", "duck"]
const DEMO_RUN_SECONDS := 25.0
const DEMO_CUSTOMERS := 2
const DROP_EVERY := 1.2

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0
var _missed := false
var _miss_flight := false
var _spun := false
var _was_air := false
var _drops_from := -1.0
var _last_serves := 0


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
	Game.round_customers = DEMO_CUSTOMERS
	Game.round_limit = DEMO_RUN_SECONDS
	if start_screen != "join":
		seat_three()
		for s in 3:
			Players.riders[s] = DEMO_CHEFS[s]
		Game.hats = [0, 1, 2]
	if start_screen == "party":
		Game.plates = sample_plates()
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


## Six served plates for a party capture: plain to loaded.
static func sample_plates() -> Array[Dictionary]:
	var Rules = load("res://scripts/kitchen/rules.gd")
	var r = Rules.new(7)
	var out: Array[Dictionary] = []
	var animals := ["bear", "cat", "penguin", "frog", "robot", "bear"]
	for i in 6:
		out.append(r._gift_plate(animals[i], [0, 2, 4, 6, 9, 12][i]))
	return out


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_missed = false
	_miss_flight = false
	_spun = false
	_drops_from = -1.0
	_last_serves = 0
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "kitchen":
		_prefill_kitchen.call_deferred()


func _prefill_kitchen() -> void:
	var k := _kitchen()
	if k and k.rules.stack.is_empty() and k.rules.time < 0.5:
		k.rules.stack.append({"cook": 1.0})
		k.rules.stack.append({"cook": 1.0})


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


func _kitchen() -> Node:
	var c = Game.current
	if c != null and is_instance_valid(c) and Game.current_name == "kitchen" and c.get("rules") != null:
		return c
	return null


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	match screen_name:
		"join":
			# One device joins per second, then the cook holds "a" (the ring
			# fills) and, as a fallback, presses start.
			for i in 3:
				st[i]["a"] = _pulse(time, 0.8 + i * 1.0)
			st[0]["a"] = st[0]["a"] or (time >= 3.6 and time < 4.9)
			st[0]["start"] = _pulse(time, 5.2)
		"select":
			st[0]["move"] = Vector2(_flick(time, 0.6) + _flick(time, 1.3), -_flick(time, 1.8))
			st[1]["move"] = Vector2(-_flick(time, 0.9), _flick(time, 1.5))
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 2.4)
			st[1]["a"] = _pulse(time, 2.9)
		"kitchen":
			_drive_kitchen(st, time)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 11.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_kitchen(st: Array[Dictionary], time: float) -> void:
	var k := _kitchen()
	if k == null:
		return
	var r = k.rules
	var p = r.pancake
	var target: float = 380.0
	var air: bool = r.in_air()
	if air and not _was_air:
		_spun = false
		_miss_flight = not _missed and time > 3.0
		if _miss_flight:
			_missed = true
	_was_air = air
	if air:
		target = r.predict_landing_x()
		if _miss_flight:
			target = r.PAN_MAX_X   # look away: the dog gets this one
		elif not _spun and p.vel().y > -200.0:
			_spun = true
			st[2]["a"] = true      # one mid-air press: an extra spin
	elif p != null and r.can_flip():
		target = r.PAN_MIN_X if (not _missed and time > 2.0) else 380.0
		if p.cook_bottom >= 1.0 and absf(r.pan_x - target) < 12.0:
			if not _missed:
				r.next_flip_vx = -60.0
			st[2]["a"] = true
	st[0]["move"] = Vector2(clampf((target - r.pan_x) / 50.0, -1.0, 1.0), 0)
	if r.can_serve():
		st[0]["a"] = fmod(time, 0.2) < 0.1
	# Topper: idle until the first serve, then one topping every 1.2 s.
	if r.served > 0 or (r.customer != null and r.customer.state != r.C.WAIT and r.customer.state != r.C.WALK_IN):
		if _drops_from < 0.0:
			_drops_from = time
	if _drops_from >= 0.0:
		var since := time - _drops_from
		var n := int(since / DROP_EVERY)
		var ph := fmod(since, DROP_EVERY)
		st[1]["move"] = Vector2(r.JAR_DIRS[n % 4]) if ph < 0.3 else Vector2.ZERO
		st[1]["a"] = ph >= 0.2 and ph < 0.3
	# Keep the scripted "a" edges clean: release between presses.
	if st[2].get("a", false) and Players.device_pressed(DEVICES[2], "a"):
		st[2]["a"] = false


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
