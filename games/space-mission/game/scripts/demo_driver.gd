extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=orbit run flows orbit -> landing -> mars
## -> party -> select ... The mission is shortened (Game.mission_scale).
##
## The scripted seats play like the family would: the Pilot flies toward the
## cargo and then the port, the Arm tracks the cargo and grabs, the Camera
## presses every 2 s; the landing beats are pressed at 1, 2 and 3 s into each
## beat; the rover drives right while the Arm drills each rock in reach.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const DEMO_SCALE := 0.35
const Flight := preload("res://scripts/logic/space_flight.gd")

var use_goto := true
var screen := ""
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
	Game.mission_scale = DEMO_SCALE
	Game.new_mission()
	if start_screen != "join":
		seat_three()
		if start_screen != "select":
			for s in 3:
				Players.riders[s] = RIDERS[s]
	match start_screen:
		"mars":
			Game.site = "crater"
		"party":
			fake_results()
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


## Results for a party started directly: a finished station, samples, photos.
func fake_results() -> void:
	Game.modules.assign(["lab", "solar", "habitat", "solar", "robot"])
	Game.docked = true
	Game.sunrises = 4
	Game.site = "ice"
	Game.samples.assign(["red", "grey", "ice", "shell", "white", "ice"])
	var cols := [Color("#0099db"), Color("#63c74d"), Color("#feae34"), Color("#2ce8f5")]
	for i in 4:
		var img := Image.create(64, 36, false, Image.FORMAT_RGBA8)
		img.fill(Color("#124e89"))
		img.fill_rect(Rect2i(0, 24, 64, 12), cols[i])
		img.fill_rect(Rect2i(8 + i * 10, 6, 10, 10), Color("#ffffff"))
		Game.photos.append({"tex": ImageTexture.create_from_image(img), "golden": i == 2})


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "select":
		Game.mission_scale = DEMO_SCALE


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	var cur: Node = Game.current
	match screen_name:
		"join":
			for i in 3:
				st[i]["a"] = _pulse(time, 0.8 + i * 1.0)
			st[0]["a"] = st[0]["a"] or (time >= 3.6 and time < 4.9)
			st[0]["start"] = _pulse(time, 5.2)
		"select":
			st[0]["move"] = Vector2(_flick(time, 0.6) + _flick(time, 1.3), _flick(time, 2.0) - _flick(time, 2.6) + _flick(time, 3.2) - _flick(time, 3.8) - _flick(time, 4.4))
			st[1]["move"] = Vector2(-_flick(time, 0.9), 0)
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 4.8)
			st[1]["a"] = _pulse(time, 2.8)
		"orbit":
			if cur and cur.has_method("pilot_goal"):
				st[0]["move"] = Flight.stick_toward(cur.flight.pos, cur.flight.vel, cur.pilot_goal())
				var to: Vector2 = cur.arm_goal() - cur.tip()
				if to.length() > 2.0:
					st[1]["move"] = _dir4(to)
				st[1]["a"] = fmod(time, 0.5) < 0.05 and not cur.holding and not cur.cargo.is_empty() \
					and cur.tip().distance_to(cur.cargo.pos) < 12.0
			st[2]["a"] = fmod(time, 2.0) < 0.05
		"landing":
			if cur and "beats" in cur and cur.phase == cur.Phase.BEATS:
				var bt: float = cur.beats.t
				match cur.beats.beat:
					0:
						st[2]["a"] = _pulse(bt, 1.0)
					1:
						st[1]["move"] = Vector2(_flick(bt, 0.6) + _flick(bt, 1.2), 0)
						st[1]["a"] = _pulse(bt, 2.0)
					2:
						st[0]["move"] = Vector2(0, 1) if bt >= 1.0 and bt < 4.0 and fmod(bt, 1.0) < 0.8 else Vector2.ZERO
		"mars":
			st[0]["move"] = Vector2(1, 0)
			if cur and cur.has_method("in_range"):
				if not cur.in_range().is_empty() and cur.drilling == -1:
					st[0]["move"] = Vector2.ZERO
					st[0]["a"] = true
					st[1]["move"] = Vector2(1, 0)
					st[1]["a"] = fmod(time, 0.6) < 0.05
			st[2]["a"] = fmod(time, 2.0) < 0.05
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 12.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


static func _dir4(v: Vector2) -> Vector2:
	if absf(v.x) >= absf(v.y):
		return Vector2(signf(v.x), 0)
	return Vector2(0, signf(v.y))


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
