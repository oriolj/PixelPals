extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so a --demo=join run flows join -> select -> level
## -> album -> select ...
##
## In the level: the pilot follows the reef's waypoint loop (reef.json
## "route"), pausing 2 s at each creature home not yet photographed and
## pinging the sonar at the hiders' homes; the camera points toward the
## nearest subject not yet photographed and snaps when it is in the frame;
## the lights press every 2 s in the trench (every 6 s elsewhere).

const Species := preload("res://scripts/level/species.gd")
const ReefMap := preload("res://scripts/level/reef.gd")

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const LEVEL_RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const DEMO_RUN_SECONDS := 75.0
const STOP_SECONDS := 2.0
const HIDERS := ["crab", "octopus", "eel"]

## Set false in tests: set up state without switching screens.
var use_goto := true
var screen := ""
## Seconds since the current screen started.
var t := 0.0

var route_i := 0
var wait_t := 0.0
var _pinged := false
var _snap_pulse := false
var _last_snap := 0.0
var _light_t := 0.0


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
		"album":
			seat_three()
			for s in 3:
				Players.riders[s] = LEVEL_RIDERS[s]
			seed_album_session()
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


## A believable finished run for the album screen: some species known from
## earlier dives, seven new today, two repeats, the whale and some bonuses.
func seed_album_session() -> void:
	Game.album.reset()
	for id in ["pufferfish", "seahorse", "squid"]:
		Game.album.record(id, 0.8)
	Game.new_session()
	for id in ["clownfish", "blue_tang", "turtle", "crab", "eel", "jellyfish", "anglerfish"]:
		Game.album.record(id, 0.9)
		Game.session.new.append(id)
		Game.session.seen.append(id)
	for id in ["pufferfish", "seahorse"]:
		Game.album.record(id, 0.5)
		Game.session.repeats[id] = 2 if id == "pufferfish" else 1
		Game.session.seen.append(id)
	Game.album.record(Species.WHALE, 1.0)
	Game.session.whale = true
	for kind in ["bubble", "shell", "shell", "rock_smile", "starfish"]:
		Game.album.add_bonus(kind)
		Game.session.bonus[kind] = int(Game.session.bonus.get(kind, 0)) + 1
	Game.album.save()


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	route_i = 0
	wait_t = 0.0
	for d in DEVICES:
		Players.set_scripted(d, {})
	if screen_name == "select":
		Game.run_seconds = DEMO_RUN_SECONDS  # the next dive ends quickly too


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
			var level = Game.current
			if level != null and is_instance_valid(level) and "sub_pos" in level:
				_drive_level(level, st, time, dt)
		"album":
			st[2]["a"] = fmod(time, 1.4) < 0.1
			st[0]["a"] = _pulse(time, 18.0)
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_level(level, st: Array[Dictionary], time: float, dt: float) -> void:
	var route: Array = level.reef.route
	if route.is_empty():
		return
	var stop: Array = route[route_i % route.size()]
	var target := Vector2(stop[0], stop[1])
	var species: String = stop[2]
	# The big moment: when the whale passes nearby, go under it for a photo.
	var w = level.whale
	if w.photographable() and not Game.session.whale and w.pos.distance_to(level.sub_pos) < 260.0 and level.sub_pos.y < 180.0:
		target = w.pos + Vector2(0, 44)
		species = ""
	var to: Vector2 = target - level.sub_pos
	var seen: Array = Game.session.seen
	if to.length() < 12.0:
		var wants := species != "" and not seen.has(species)
		if wants and wait_t < STOP_SECONDS + (1.5 if HIDERS.has(species) else 0.0):
			wait_t += dt
			if HIDERS.has(species) and not _pinged:
				st[0]["a"] = true   # sonar ping at the hiding spot
				_pinged = true
			st[0]["move"] = Vector2.ZERO
		else:
			route_i += 1
			wait_t = 0.0
			_pinged = false
	else:
		# Steer the velocity, not the position: inertia would make it orbit.
		var want_vel := to.normalized() * minf(72.0, to.length() * 1.6 + 8.0)
		st[0]["move"] = ((want_vel - level.sub_vel) / 20.0).limit_length(1.0)
	# Camera: point toward the nearest subject not photographed yet; snap it.
	var best = null
	var best_d := 130.0
	for c in level.creatures:
		if not c.photographable() or seen.has(c.id) or (c.id == Species.WHALE and Game.session.whale):
			continue
		var d: float = c.pos.distance_to(level.sub_pos)
		if d < best_d:
			best_d = d
			best = c
	if best != null:
		var v: Vector2 = best.pos - level.sub_pos
		st[1]["move"] = Vector2(signf(v.x), 0) if absf(v.x) >= absf(v.y) else Vector2(0, signf(v.y))
	var subject = level.subject_in_frame()
	var want_snap: bool = subject != null and not seen.has(subject.id) and not (subject.id == Species.WHALE and Game.session.whale)
	# Now and then an empty snap, to show the bonus subjects.
	if not want_snap and subject == null and time - _last_snap > 11.0:
		want_snap = true
	if want_snap and not _snap_pulse:
		st[1]["a"] = true
		_last_snap = time
	_snap_pulse = st[1].get("a", false)
	# Lights: every 2 s in the trench, every 6 s elsewhere, one disco early on.
	_light_t += dt
	var every := 2.0 if ReefMap.zone_of(level.sub_pos) == "trench" else 6.0
	var press := false
	if _light_t >= every:
		_light_t = 0.0
		press = true
	if time > 12.0 and time < 13.0:
		press = fmod(time, 0.33) < dt
	st[2]["a"] = press


## True for a short press starting at `at`.
func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


## 1.0 for a short stick flick starting at `at`, else 0.
func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
