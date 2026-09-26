extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> paint ->
## party -> select ...
##
## Paint: the Brush follows scripted paths (a big wavy line, a sun, a house
## outline) by steering the stick toward a moving target; the Colourist
## switches pots every 3 s and stamps 6 times; the Splatter presses every
## 2.5 s; at 25 s the Brush opens the menu and frames the picture.

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const FRAME_AT := 25.0

var use_goto := true
var screen := ""
var t := 0.0
## The paint screen being driven (set by the router, or by tests).
var paint: Node = null
var _path: Array = []          # [{t0, t1, from: Callable -> Vector2, paint, size}]


func _init() -> void:
	process_priority = -200  # before Players polls (-100)
	_path = build_path()


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	if not Game.SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	if start_screen != "join":
		seat_three()
		for s in 3:
			Players.riders[s] = RIDERS[s]
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
	paint = Game.current if screen_name == "paint" else null
	for d in DEVICES:
		Players.set_scripted(d, {})


func _process(delta: float) -> void:
	t += delta
	drive(screen, t)


# ---------------------------------------------------------------- the painting path

## The Brush's route, as segments of time with a target position function.
## Canvas is 1920x1080.
static func build_path() -> Array:
	var p: Array = []
	var at := 0.3
	# 1. the wavy line along the bottom, medium brush
	p.append({"t0": at, "t1": at + 0.6, "pos": func(_k): return Vector2(170, 880), "paint": false})
	at += 0.7
	p.append({"t0": at, "t1": at + 4.2, "pos": func(k): return Vector2(170 + 1580 * k, 880 + 70 * sin(k * TAU * 3.0)), "paint": true})
	at += 4.4
	# 2. the sun, top right, big brush
	var sun := Vector2(1580, 250)
	p.append({"t0": at, "t1": at + 1.4, "pos": func(_k): return sun + Vector2(120, 0), "paint": false, "size": 2})
	at += 1.5
	p.append({"t0": at, "t1": at + 2.8, "pos": func(k): return sun + Vector2(cos(k * TAU), sin(k * TAU)) * 120.0, "paint": true})
	at += 2.9
	for i in 8:  # rays
		var a := TAU * i / 8.0
		var d := Vector2(cos(a), sin(a))
		p.append({"t0": at, "t1": at + 0.3, "pos": func(_k): return sun + d * 175.0, "paint": false, "size": 1 if i == 0 else -1})
		at += 0.4
		p.append({"t0": at, "t1": at + 0.3, "pos": func(k): return sun + d * (175.0 + 70.0 * k), "paint": true})
		at += 0.35
	# 3. the house outline, left of centre
	var corners := [Vector2(420, 700), Vector2(420, 420), Vector2(640, 250), Vector2(860, 420), Vector2(860, 700), Vector2(420, 700)]
	p.append({"t0": at, "t1": at + 1.9, "pos": func(_k): return corners[0], "paint": false})
	at += 2.1
	for i in corners.size() - 1:
		var a2: Vector2 = corners[i]
		var b2: Vector2 = corners[i + 1]
		p.append({"t0": at, "t1": at + 0.8, "pos": func(k): return a2.lerp(b2, k), "paint": true})
		at += 0.85
	# door
	p.append({"t0": at, "t1": at + 0.4, "pos": func(_k): return Vector2(580, 700), "paint": false})
	at += 0.5
	var door := [Vector2(580, 700), Vector2(580, 560), Vector2(680, 560), Vector2(680, 700)]
	for i in door.size() - 1:
		var a3: Vector2 = door[i]
		var b3: Vector2 = door[i + 1]
		p.append({"t0": at, "t1": at + 0.5, "pos": func(k): return a3.lerp(b3, k), "paint": true})
		at += 0.55
	# 4. park the brush in the middle of the sky for the last stamps
	p.append({"t0": at, "t1": at + 1.0, "pos": func(_k): return Vector2(1150, 330), "paint": false})
	return p


## Where the Brush should be at time `time`, whether "a" is held, and the size
## index wanted (-1 = no change).
static func path_at(path: Array, time: float) -> Dictionary:
	var last: Dictionary = path[path.size() - 1]
	for seg in path:
		if time < seg.t0:
			return {"pos": seg.pos.call(0.0), "paint": false, "size": seg.get("size", -1)}
		if time <= seg.t1:
			var k: float = clampf((time - seg.t0) / (seg.t1 - seg.t0), 0.0, 1.0)
			return {"pos": seg.pos.call(k), "paint": seg.paint, "size": seg.get("size", -1)}
	return {"pos": last.pos.call(1.0), "paint": false, "size": -1}


# ---------------------------------------------------------------- per screen

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
		"paint":
			_drive_paint(st, time)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_paint(st: Array[Dictionary], time: float) -> void:
	# Colourist: a new pot every 3 s (clockwise), a page turn now and then,
	# and 6 stamps spread over the run.
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	var k := int(time / 3.0)
	if fmod(time, 3.0) < 0.12:
		st[1]["move"] = dirs[(k + 1) % 4]
	st[1]["b"] = _pulse(time, 9.2) or _pulse(time, 18.2)
	for at in [4.0, 8.5, 13.0, 17.5, 21.0, 23.5]:
		st[1]["a"] = st[1].get("a", false) or _pulse(time, at)
	# Splatter: a press every 2.5 s, plus a double press (the second giggles).
	st[2]["a"] = fmod(time, 2.5) < 0.1 or _pulse(time, 7.72)
	# Brush.
	if time >= FRAME_AT:
		# Start opens the menu (it opens on "keep painting"), left = frame it, a.
		st[0]["start"] = _pulse(time, FRAME_AT)
		st[0]["move"] = Vector2.LEFT if _pulse(time, FRAME_AT + 0.5) else Vector2.ZERO
		st[0]["a"] = _pulse(time, FRAME_AT + 1.0)
		return
	var want := path_at(_path, time)
	if paint != null and is_instance_valid(paint):
		var to: Vector2 = want.pos - paint.brush
		st[0]["move"] = (to / (paint.BRUSH_SPEED * 0.08)).limit_length(1.0)
		st[0]["a"] = want.paint
		var sz: int = want.size
		st[0]["b"] = sz >= 0 and paint.size_idx != sz and not paint.stroke.active and fmod(time, 0.2) < 0.05
	else:
		st[0]["a"] = want.paint


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
