extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> play
## -> party -> select ...
##
## play: the Builder sweeps the hook across the tower's centre on a slow sine
## and rotates every third block; the Dropper picks a shape per block and
## drops when the hook is within 8 px of the tower centre (two drops are
## deliberate misses into the ball pit); the Toppler presses every 2 s.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const PLAY_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
## Demo towers are short, so one capture holds two build phases and two topples.
const DEMO_TOWER_SECONDS := 14.0
const MISS_DROPS: Array[int] = [2, 7]
const DIRS: Array[Vector2] = [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0
var _rotated_for := -1
var _picked_for := -1


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
	Game.tower_seconds = DEMO_TOWER_SECONDS
	match start_screen:
		"select":
			seat_three()
		"play":
			seat_three()
			for s in 3:
				Players.riders[s] = PLAY_RIDERS[s]
		"party":
			seat_three()
			for s in 3:
				Players.riders[s] = PLAY_RIDERS[s]
			Game.tower_heights = [5, 8, 3] as Array[int]
			Game.stars = 16
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
	_rotated_for = -1
	_picked_for = -1
	for d in DEVICES:
		Players.set_scripted(d, {})
	Game.tower_seconds = DEMO_TOWER_SECONDS


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


## Where the Builder aims and the Dropper waits, for the play screen `p`.
static func play_targets(p: Node, time: float) -> Dictionary:
	var com: float = p.tower_com_x()
	var miss: bool = MISS_DROPS.has(p.drops)
	var drop_at := com + 150.0 if miss else com
	var sweep := drop_at + (0.0 if miss else 36.0 * sin(time * 1.8))
	return {"sweep": sweep, "drop_at": drop_at, "miss": miss}


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
		"play":
			var p: Node = Game.current if Game.current_name == "play" else null
			if p != null and is_instance_valid(p):
				_drive_play(p, time, st)
			st[2]["a"] = fmod(time, 2.0) < 0.1
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
			st[0]["a"] = _pulse(time, 7.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_play(p: Node, time: float, st: Array[Dictionary]) -> void:
	var tg := play_targets(p, time)
	var hook: float = p.hook_x
	st[0]["move"] = Vector2(clampf((tg.sweep - hook) / 25.0, -1.0, 1.0), 0)
	if p.hanging == null:
		return
	var n: int = p.drops
	var age: float = p.hang_age
	# Dropper picks the next shape once per block (shows off the tray): the
	# best stacker in the tray, a roof only as the tenth block.
	if _picked_for != n and age > 0.1:
		st[1]["move"] = DIRS[best_slot(p.tray, n)]
		_picked_for = n
	# Builder rotates every third block.
	if n % 3 == 2 and _rotated_for != n and age > 0.35:
		st[0]["a"] = true
		_rotated_for = n
	if age > 0.6 and absf(hook - tg.drop_at) < 8.0:
		st[1]["a"] = true


static func best_slot(tray: Array, n: int) -> int:
	var order := ["plank", "square", "arch", "tall", "roof", "ball"]
	if n >= 9:
		order = ["roof", "square", "plank", "arch", "tall", "ball"]
	var best := 0
	for i in tray.size():
		if order.find(tray[i]) < order.find(tray[best]):
			best = i
	return best


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
