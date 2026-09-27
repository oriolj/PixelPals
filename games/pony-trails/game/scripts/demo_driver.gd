extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=stable run plays the whole day: stable ->
## trail -> show -> party -> select. The stages are shortened (Game.day_scale).
## The demo uses its own rosette wall file (never the family's) and seeds it
## with three earlier days so the party shows a wall that grows.
##
## The scripted seats: the brush sweeps each patch in turn and picks the blue
## ribbon; the toddler presses every 2 s; the adult points at each hoof, then
## saddles up, canters and jumps each obstacle (missing one now and then to
## show the step-over); the foal zig-zags the lanes toward the apples.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const DEMO_SCALE := 0.4
const FoalTether := preload("res://scripts/logic/foal_tether.gd")
const ShowCourse := preload("res://scripts/logic/show_course.gd")

var use_goto := true
var screen := ""
var t := 0.0
var _flick_cool := 0.0
var _jumped := {}


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
	Game.day_scale = DEMO_SCALE
	Game.mare_coat = "bay"
	Game.foal_coat = "palomino"
	Game.new_day()
	seed_wall()
	if start_screen != "join":
		seat_three()
		if start_screen != "select":
			for s in 3:
				Players.riders[s] = RIDERS[s]
	match start_screen:
		"trail":
			Game.day.ribbon = 1
		"show":
			fake_trail()
		"party":
			fake_trail()
			fake_show()
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


## The demo wall starts with three earlier days (the family wall is never touched).
func seed_wall() -> void:
	Game.wall.reset()
	Game.wall.add_day(["blue", "yellow", "green", "red"], 1)
	Game.wall.add_day(["red", "red", "purple", "blue", "yellow"], 0)
	Game.wall.add_day(["green", "blue", "blue"], 2)
	Game.wall.save()


func fake_trail() -> void:
	Game.day.ribbon = 1
	Game.day.carrots = 4
	Game.day.apples = 9
	Game.day.flowers = 6
	Game.day.lucky = 1
	Game.day.clean_jumps = 5


func fake_show() -> void:
	Game.day.rosettes = [{"who": "mare", "colour": "blue"}, {"who": "foal", "colour": "red"},
		{"who": "rider0", "colour": "yellow"}, {"who": "rider1", "colour": "green"}, {"who": "rider2", "colour": "purple"}]


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_jumped.clear()
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "select":
		Game.day_scale = DEMO_SCALE


func _process(delta: float) -> void:
	t += delta
	_flick_cool = maxf(0.0, _flick_cool - delta)
	drive(screen, t, delta)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float, dt := 1.0 / 30.0) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	var cur: Node = Game.current
	match screen_name:
		"join":
			for i in 3:
				st[i]["a"] = _pulse(time, 0.8 + i * 1.0)
			st[0]["a"] = st[0]["a"] or (time >= 3.6 and time < 4.9)
			st[0]["start"] = _pulse(time, 5.2)
		"select":
			st[0]["move"] = Vector2(_flick(time, 0.6) + _flick(time, 1.2) - _flick(time, 4.2) + _flick(time, 4.8) - _flick(time, 5.4),
				_flick(time, 1.8) - _flick(time, 2.4))
			st[1]["move"] = Vector2(-_flick(time, 0.9), _flick(time, 1.5) + _flick(time, 2.1) - _flick(time, 2.7) - _flick(time, 3.3))
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 3.6)
			st[1]["a"] = _pulse(time, 3.9)
		"stable":
			if cur and "groom" in cur and cur.groom != null:
				_drive_stable(cur, st, time)
			st[2]["a"] = fmod(time, 2.0) < 0.05
		"trail":
			if cur and "mare" in cur and cur.mare != null:
				_drive_trail(cur, st, time)
			st[2]["a"] = fmod(time, 2.0) < 0.05
		"show":
			if cur and "show" in cur and cur.show != null:
				_drive_show(cur, st, time)
			st[2]["a"] = fmod(time, 2.0) < 0.05
		"party":
			st[2]["a"] = fmod(time, 1.4) < 0.05
			st[0]["a"] = _pulse(time, 12.5)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_stable(cur: Node, st: Array[Dictionary], _time: float) -> void:
	var g = cur.groom
	# The brush: hop toward the next muddy patch, then scrub it; then the blue ribbon.
	if g.all_clean():
		if g.ribbon == -1 and _flick_cool <= 0.0:
			st[1]["move"] = Vector2(1, 0)
			_flick_cool = 0.5
	else:
		var target: int = g.next_dirty()
		if g.brush == target or (g.brush != -1 and not g.is_clean(g.brush)):
			st[1]["a"] = true
		elif _flick_cool <= 0.0:
			var to: Vector2 = g.patch_pos[target] - g.brush_pos()
			st[1]["move"] = _dir4(to)
			_flick_cool = 0.35
	# The hand: each hoof in turn, then the saddle rack.
	var tg: Dictionary = g.next_target()
	if not tg.is_empty():
		var to2: Vector2 = tg.pos - cur.hand
		if to2.length() > 3.0:
			st[0]["move"] = to2.normalized() * clampf(to2.length() / 12.0, 0.4, 1.0)
		else:
			st[0]["a"] = fmod(t, 0.5) < 0.05


func _drive_trail(cur: Node, st: Array[Dictionary], time: float) -> void:
	var mare = cur.mare
	# Canter after a trotting start; jump each obstacle in the window, missing every fourth.
	st[0]["move"] = Vector2(1, 0) if time > 3.0 and time < 5.0 else Vector2.ZERO
	var ob: Dictionary = mare.next_obstacle()
	if not ob.is_empty():
		var key := int(ob.x)
		var idx: int = cur.course.obstacles.find(ob)
		var tt: float = mare.time_to_takeoff(ob)
		if not _jumped.has(key) and idx % 4 != 2 and tt < 0.15 and tt > -0.1:
			st[0]["a"] = true
			_jumped[key] = true
	# The foal: zig-zag toward the apples ahead, hop when one is close.
	var foal = cur.foal
	var best: Dictionary = {}
	var best_d := 100.0
	for it in cur.course.items:
		if it.taken:
			continue
		var d: float = float(it.x) - foal.x
		if d > 0.0 and d < best_d:
			best_d = d
			best = it
	if not best.is_empty():
		if int(best.lane) != foal.lane and _flick_cool <= 0.0:
			st[1]["move"] = Vector2(0, -1 if int(best.lane) > foal.lane else 1)
			_flick_cool = 0.3
		elif int(best.lane) == foal.lane and best.needs_hop and best_d < 10.0 and not foal.hopping():
			st[1]["a"] = true


func _drive_show(cur: Node, st: Array[Dictionary], time: float) -> void:
	var sh = cur.show
	if sh.phase == ShowCourse.Phase.MARE and sh.jump_i < ShowCourse.MARE_JUMPS.size():
		var takeoff: float = ShowCourse.MARE_JUMPS[sh.jump_i] - ShowCourse.TAKEOFF
		var tt: float = (takeoff - sh.s) / ShowCourse.MARE_SPEED
		# Jump 2 is left to the mare the first time: the comedic refusal.
		if tt < 0.12 and tt > -0.05 and not (sh.jump_i == 1 and not sh.refused[1]) and sh.mstate == ShowCourse.MState.RUN:
			st[0]["a"] = fmod(time, 0.1) < 0.05
	if sh.phase == ShowCourse.Phase.FOAL and sh.foal_i < ShowCourse.FOAL_JUMPS.size():
		var ftt: float = (ShowCourse.FOAL_JUMPS[sh.foal_i] - 10.0 - sh.foal_x) / ShowCourse.FOAL_SPEED
		st[1]["a"] = ftt < 0.3 and ftt > 0.0 and fmod(time, 0.2) < 0.05
	if sh.phase == ShowCourse.Phase.PICKS and sh.picked_t < 0.0 and sh.phase_t > 1.0 and _flick_cool <= 0.0:
		st[1]["move"] = [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)][sh.pole_i % 4]
		_flick_cool = 0.6


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
