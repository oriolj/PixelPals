extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed. Extra entry points open the level with a preset:
## `cat` (parked under a stuck cat) and `home` (the sunset drive home).
##
## In the level the driver follows the road path to the current objective
## (steer toward the next cell centre, ease off near the end, stop), the
## hose seat aims its 4-way stick at the fire and holds A, and the siren
## seat presses every 2.5 s and once after each stop.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const TruckModel := preload("res://scripts/level/truck_model.gd")
const Rules := preload("res://scripts/level/rules.gd")

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0
var _parked_pressed := false
var _siren_t := 0.0


func _init() -> void:
	# Run before Players polls (-100), so scripted input lands the same frame.
	process_priority = -200


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	var preset := ""
	if Game.LEVEL_PRESETS.has(start_screen):
		preset = start_screen
		start_screen = "level"
	if not Game.SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	match start_screen:
		"select":
			seat_three()
		"level":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			Game.level_preset = preset
		"party":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			Game.stars = 18
			Game.cats = 3
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
			if lvl != null and lvl.has_method("demo_goal"):
				level_input(lvl, st, delta)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 6.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


## The level: drive the road path to the objective, spray, siren.
func level_input(lvl: Node, st: Array[Dictionary], delta: float) -> void:
	var truck = lvl.truck
	var goal: Dictionary = lvl.demo_goal()
	var stopped := absf(truck.speed) < 0.4
	_siren_t += delta
	if _siren_t >= 2.5:
		_siren_t = 0.0
		st[2]["a"] = true
	if goal.is_empty():
		_parked_pressed = false
		return
	var pts: Array = goal.points
	var target: Vector2 = truck.pos
	var last: Vector2 = pts[-1] if not pts.is_empty() else truck.pos
	# The waypoint after the furthest one already within reach (never back).
	var idx := 0
	for k in pts.size():
		if truck.pos.distance_to(pts[k]) <= 4.0:
			idx = k + 1
	if not pts.is_empty():
		target = pts[mini(idx, pts.size() - 1)]
	var to_final: float = truck.pos.distance_to(last)
	var move := Vector2.ZERO
	if to_final > 2.0:
		var want: Vector2 = (target - truck.pos).normalized()
		var fwd: Vector2 = truck.fwd()
		var ang := fwd.angle_to(want)
		# Never ask for reverse: a target behind becomes a tight forward turn.
		if absf(ang) > 1.8:
			want = fwd.rotated(signf(ang) * 1.8)
			ang = signf(ang) * 1.8
		var throttle := clampf(1.0 - absf(ang) / 1.6, 0.35, 0.9)
		if absf(ang) > 1.2:
			throttle = 0.1   # a crawl: the truck turns almost on the spot
		throttle = minf(throttle, clampf(to_final / 9.0, 0.3, 1.0))
		move = world_to_stick(want * throttle, lvl.cam_yaw)
		_parked_pressed = false
	elif stopped and not _parked_pressed:
		_parked_pressed = true
		st[2]["a"] = true   # siren (and the ladder, when a cat is in reach)
		_siren_t = 0.0
	st[0]["move"] = move
	# Hose: aim at the fire and hold A when it is close.
	if goal.kind == "fire":
		var look: Vector2 = goal.look
		if truck.pos.distance_to(look) < Rules.HOSE_RANGE + 3.0:
			st[1]["move"] = Vector2(Rules.world_to_screen4(look - truck.pos, lvl.cam_yaw))
			st[1]["a"] = true


## A world ground direction (length = throttle) as a camera-relative stick.
static func world_to_stick(v: Vector2, cam_yaw: float) -> Vector2:
	var f := TruckModel.fwd_of(cam_yaw)
	var r := TruckModel.right_of(cam_yaw)
	return Vector2(v.dot(r), -v.dot(f)).limit_length(1.0)


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
