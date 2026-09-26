extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> level ->
## party -> select ...
##
## On the level (PLAN.md "Demo driver"): the tractor drives a boustrophedon
## (row by row, turning at the fence) for the first 90 s, then sweeps for
## ripe tiles and tips at the barn; the seed seat changes seed every row
## (carrot, pumpkin, sunflower, strawberry); the cloud presses every 1.5 s.

const FieldRules := preload("res://scripts/field_rules.gd")
const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
## The demo's level ends by time sooner than the real 6 minutes.
const DEMO_RUN_LIMIT := 150.0
const PLOUGH_SECONDS := 90.0
const CLOUD_EVERY := 1.5
const TIP_AT := 14

var use_goto := true
var screen := ""
var t := 0.0

# Level plan state.
var row := 0
var row_dir := 1.0
var mode := "rows"
var _flick_t := -1.0
var _flick_dir := Vector2.ZERO
var _sweep_seed_t := 0.0
var _press_a_t := -1.0
var _no_ripe_t := 0.0


func _init() -> void:
	process_priority = -200  # before Players polls (-100)


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	if not Game.DEMO_STARTS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	Game.run_limit = DEMO_RUN_LIMIT
	Game.level_preset = ""
	var go := start_screen
	match start_screen:
		"select":
			seat_three()
		"level", "finale", "party", "crops":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
	if start_screen == "finale":
		Game.level_preset = "finale"
		go = "level"
	if start_screen == "party":
		Game.barn.assign([9, 7, 8, 6])
		Game.giant_crop = 1
	screen = go
	_reset_level_plan()
	if use_goto:
		Game.goto(go)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_reset_level_plan()
	for d in DEVICES:
		Players.set_scripted(d, {})


func _reset_level_plan() -> void:
	t = 0.0
	row = 0
	row_dir = 1.0
	mode = "rows"
	_flick_t = -1.0
	_sweep_seed_t = 0.0
	_press_a_t = -1.0
	_no_ripe_t = 0.0


func _process(delta: float) -> void:
	t += delta
	drive(screen, t, delta)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float, dt := 1.0 / 30.0) -> void:
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
			_level(st, time, dt)
		"party":
			st[2]["a"] = fmod(time, 2.5) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _level(st: Array[Dictionary], time: float, dt: float) -> void:
	st[2]["a"] = fmod(time, CLOUD_EVERY) < 0.1
	var lv = Game.current if Game.current != null and is_instance_valid(Game.current) \
		and Game.current.has_method("autopilot") else null
	if lv == null:
		# No level to look at (tests): drive right and cycle seeds.
		st[0]["move"] = Vector2.RIGHT
		st[1]["move"] = Vector2(FieldRules.dir_for_seed(int(time / 4.0) % 4))  if fmod(time, 4.0) < 0.1 else Vector2.ZERO
		return
	var target := _level_target(lv, time, dt)
	st[0]["move"] = lv.autopilot(target)
	if _press_a_t >= 0.0:
		st[0]["a"] = true
		_press_a_t -= dt
	if _flick_t > 0.0:
		st[1]["move"] = _flick_dir
		_flick_t -= dt


func _level_target(lv, time: float, dt: float) -> Vector2:
	var fp: Vector2 = lv.FIELD_POS
	var fs: Vector2 = lv.FIELD_SIZE
	var pos: Vector2 = lv.tractor_pos
	if mode == "rows":
		var y := fp.y + row * FieldRules.TILE + 32.0
		var x_end := fp.x + fs.x - 24.0 if row_dir > 0.0 else fp.x + 30.0
		if (row_dir > 0.0 and pos.x >= x_end - 10.0) or (row_dir < 0.0 and pos.x <= x_end + 10.0):
			if absf(pos.y - y) < 40.0:
				row += 1
				row_dir = -row_dir
				_pick(row % 4)
				if row >= FieldRules.H:
					mode = "sweep"
		if time >= PLOUGH_SECONDS:
			mode = "sweep"
		return Vector2(x_end, y)
	# Sweep: harvest ripe tiles, tip at the barn when the trailer is heavy.
	_sweep_seed_t += dt
	if _sweep_seed_t > 8.0:
		_sweep_seed_t = 0.0
		_pick((lv.seed_crop + 1) % 4)
	var field = lv.field
	var ripe: Array[Vector2i] = field.cells_in(FieldRules.Tile.RIPE)
	_no_ripe_t = _no_ripe_t + dt if ripe.is_empty() else 0.0
	var trailer_n: int = field.trailer.size()
	if trailer_n >= TIP_AT or (trailer_n > 0 and (_no_ripe_t > 2.0 or field.trailer_full())):
		var barn := Vector2(1150, 430)
		if lv.TIP_ZONE.has_point(pos):
			if _press_a_t < 0.0 and lv.park_t > 0.3:
				_press_a_t = 0.1
			return pos
		return barn
	if ripe.is_empty():
		if _no_ripe_t > 4.0:
			mode = "rows"
			row = 0
			row_dir = 1.0 if pos.x < 560.0 else -1.0
		return pos
	var best := Vector2.ZERO
	var best_d := INF
	for c in ripe:
		var p: Vector2 = fp + FieldRules.cell_center(c)
		# Prefer tiles ahead of the tractor (fewer loops).
		var d := p.distance_to(pos) + (0.0 if (p - pos).dot(Vector2.from_angle(lv.heading)) > 0.0 else 120.0)
		if d < best_d:
			best_d = d
			best = p
	return best


func _pick(crop: int) -> void:
	_flick_dir = Vector2(FieldRules.dir_for_seed(crop))
	_flick_t = 0.12


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
