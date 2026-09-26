extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> zoo ->
## party -> select ...
##
## The zoo script (the plan's): the keeper walks to the monkey, the feeder
## picks hay first (wrong: the refusal and the wiggle), then banana; then the
## keeper walks to the penguin and the feeder throws fish. The singer presses
## at 3 s, 4 s and 9 s. After that an autopilot plays on.

const Rules := preload("res://scripts/zoo/rules.gd")

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const BUDDIES: Array[String] = ["monkey", "penguin", "elephant"]
const DEMO_RUN_SECONDS := 90.0
const SCRIPT_END := 12.5

var use_goto := true
var screen := ""
var t := 0.0
var _auto_pick_t := 0.0
var _auto_wrong := false
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	process_priority = -200


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)
	_rng.seed = 5


func start(start_screen: String) -> void:
	if not Game.SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	Game.run_seconds = DEMO_RUN_SECONDS
	Game.first_hungry.assign(["monkey", "penguin"])
	match start_screen:
		"select":
			seat_three()
		"zoo", "party", "gallery":
			seat_three()
			for s in 3:
				Players.riders[s] = BUDDIES[s]
			Game.hats.assign([1, 0, 4])
			Game.stars = 12
			Game.meals = 12
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
		Game.run_seconds = DEMO_RUN_SECONDS


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
			st[0]["move"] = Vector2(_flick(time, 0.5) + _flick(time, 1.0), -_flick(time, 1.5))
			st[1]["move"] = Vector2(-_flick(time, 0.8), _flick(time, 1.3))
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 2.2)
			st[1]["a"] = _pulse(time, 2.8)
		"zoo":
			_drive_zoo(time, st)
		"party":
			st[2]["a"] = fmod(time, 1.7) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_zoo(time: float, st: Array[Dictionary]) -> void:
	var zoo: Node = Game.current if Game.current_name == "zoo" else null
	if zoo == null or not is_instance_valid(zoo):
		return
	# Singer: the plan's presses at 3, 4 and 9 s, then every 3.5 s.
	st[2]["a"] = _pulse(time, 3.0) or _pulse(time, 4.0) or _pulse(time, 9.0) \
		or (time > SCRIPT_END and fmod(time, 3.5) < 0.1)
	if time < SCRIPT_END:
		var target := "monkey" if time < 6.2 else "penguin"
		st[0]["move"] = _walk_to(zoo, zoo.animals[target].spot)
		var pick := Vector2.ZERO
		if time >= 2.4 and time < 2.6:
			pick = Vector2.LEFT       # hay: wrong for the monkey
		elif time >= 4.9 and time < 5.1:
			pick = Vector2.UP         # banana
		elif time >= 8.9 and time < 9.1:
			pick = Vector2.RIGHT      # fish for the penguin
		st[1]["move"] = pick
		st[1]["a"] = _pulse(time, 2.7) or _pulse(time, 5.2) or _pulse(time, 9.2)
		return
	# Autopilot: walk to the nearest hungry animal, pick (sometimes wrong first), throw.
	var goal: Vector2 = zoo.KEEPER_START
	var best := INF
	for kind in zoo.hungry_ids:
		var d: float = zoo.keeper_pos.distance_to(zoo.animals[kind].spot)
		if d < best:
			best = d
			goal = zoo.animals[kind].spot
	st[0]["move"] = _walk_to(zoo, goal)
	if zoo.at_animal == "":
		_auto_pick_t = 0.0
		return
	_auto_pick_t += 1.0 / 30.0 if Engine.get_frames_per_second() <= 0 else get_process_delta_time()
	var right := Rules.right_food(zoo.at_animal)
	var food := right
	if _auto_pick_t < 0.05:
		_auto_wrong = _rng.randf() < 0.3
	if _auto_wrong and zoo.animals[zoo.at_animal].wrong_tries == 0:
		food = Rules.FOODS[(Rules.FOODS.find(right) + 1) % 4]
	if _auto_pick_t > 0.6 and _auto_pick_t < 0.8:
		st[1]["move"] = Vector2(Rules.dir_for_food(food))
	if _auto_pick_t > 1.0:
		st[1]["a"] = true
		_auto_pick_t = 0.2


func _walk_to(zoo: Node, goal: Vector2) -> Vector2:
	var d: Vector2 = goal - zoo.keeper_pos
	if d.length() < 10.0:
		return Vector2.ZERO
	return d.normalized() * minf(1.0, d.length() / 40.0 + 0.3)


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
