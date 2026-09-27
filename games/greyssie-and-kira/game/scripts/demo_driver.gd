extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and feeds
## them input every frame for whatever screen is current, following
## Game.screen_changed, so --demo=join plays join -> select -> house (a whole
## day: four rounds) -> party -> select ...
##
## Screens: join, select, house (the day from the morning), night (the day
## from the night round), party.
##
## House script (the plan's): the toddler shakes the treats every 3 s; the
## walker goes to the room the meow bubble lit and opens its spots nearest
## first (empty ones show funny finds); the laser moves to a cat peeking from
## a spot (shy Kira, or anyone up high) and wiggles until it pounces out;
## the walker picks up every cat that came out (both on the shoulders when he
## can) and carries them to the bowls. The first round (and the night demo's)
## places the cats so the capture shows every beat quickly.

const House := preload("res://scripts/screens/house.gd")
const Cat := preload("res://scripts/house/cat.gd")
const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const DEMO_RIDER := "penguin"
const SHAKE_EVERY := 3.0
## Forced hiding places per round when those spots and cats exist.
const PLACEMENTS := {
	0: {"greyssie": "tv_box", "kira": "sofa"},
	3: {"greyssie": "kids_bed", "kira": "toy_box"},
}

var use_goto := true
var screen := ""
var t := 0.0
var _applied := {}
var _a_prev := false
var _laser_a_prev := false
var _last_round := -1


func _init() -> void:
	process_priority = -200


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	var target := start_screen
	if start_screen == "night":
		target = "house"
	if not Game.SCREENS.has(target):
		target = "join"
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	if target in ["select", "house", "party"]:
		seat_three()
		Players.riders[Game.WALKER] = DEMO_RIDER
	Game.start_round = 3 if start_screen == "night" else 0
	screen = target
	t = 0.0
	if use_goto:
		Game.goto(target)
	else:
		_on_screen_changed(target)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_applied.clear()
	_last_round = -1
	for d in DEVICES:
		Players.set_scripted(d, {})


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
		"house":
			var lvl := Game.current
			if lvl and lvl.has_method("walker_action"):
				_drive_house(lvl, time, st)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_house(lvl: Node, time: float, st: Array[Dictionary]) -> void:
	# Forced placements while the cats slip away.
	if lvl.state == House.State.INTRO and not _applied.has(Game.round_index):
		_applied[Game.round_index] = true
		var want: Dictionary = PLACEMENTS.get(Game.round_index, {})
		var ok := not want.is_empty()
		for id in want:
			if not lvl.house.spots.has(want[id]) or lvl._cat(id) == null:
				ok = false
		if ok:
			lvl.placement = want.duplicate()
	# Toddler: a shake every 3 s.
	st[2]["a"] = fmod(time, SHAKE_EVERY) < 0.1 and time > 1.0
	st[0] = walker_brain(lvl)
	st[1] = laser_brain(lvl)


## The walker's autopilot: bowls when both are carried (or nobody is left to
## find), else pick up a cat that came out, else search the meowed room.
func walker_brain(lvl: Node) -> Dictionary:
	var out := {}
	if lvl.state != House.State.SEARCH or lvl.climbing:
		_a_prev = false
		return out
	var carried: int = lvl.carried_count()
	var left_to_find := 0
	var pickable: Array = []
	var coming_out := false
	for c in lvl.cats:
		if c.state in [Cat.State.HIDDEN, Cat.State.SLIPPING]:
			left_to_find += 1
		elif c.pickable() or c.state == Cat.State.WALKOUT or c.state == Cat.State.ZOOMIES:
			pickable.append(c)
		elif c.state in [Cat.State.ALERT, Cat.State.PEEK, Cat.State.STALK, Cat.State.HOP]:
			coming_out = true
	var tf := -1
	var tx := 0.0
	var press := false
	if carried > 0 and (carried == 2 or (left_to_find == 0 and pickable.is_empty() and not coming_out)):
		tf = lvl.house.bowls.floor
		tx = lvl.house.bowls.x
		press = lvl.walker_floor == tf and absf(lvl.walker_x - tx) < 8.0
	elif not pickable.is_empty() and lvl._free_slot() != -1:
		var c = _nearest(lvl, pickable)
		tf = c.floor_i
		tx = c.x
		press = c.pickable() and lvl.walker_floor == tf and absf(lvl.walker_x - tx) < 10.0
	elif coming_out:
		return out  # wait: the laser (or time) brings it out
	elif lvl.last_meow_room != "":
		var sid := _next_spot(lvl, lvl.last_meow_room)
		if sid != "":
			var s: Dictionary = lvl.house.spots[sid]
			tf = s.floor
			tx = s.x
			press = lvl.walker_floor == tf and absf(lvl.walker_x - tx) < 4.0 and lvl.nearest_spot() == sid
	if tf == -1:
		_a_prev = false
		return out
	out["move"] = move_toward_target(lvl, tf, tx)
	out["a"] = press and not _a_prev
	_a_prev = out["a"]
	return out


## The closed spot of a room nearest the walker, or "".
func _next_spot(lvl: Node, rid: String) -> String:
	var best := ""
	var bd := INF
	for sid in lvl.house.rooms[rid].spots:
		if lvl.spot_is_open(sid):
			continue
		var s: Dictionary = lvl.house.spots[sid]
		var d: float = lvl.house.distance(lvl.walker_floor, lvl.walker_x, s.floor, s.x)
		if d < bd:
			bd = d
			best = sid
	return best


func _nearest(lvl: Node, list: Array):
	var best = list[0]
	var bd := INF
	for c in list:
		var d: float = lvl.house.distance(lvl.walker_floor, lvl.walker_x, c.floor_i, c.x)
		if d < bd:
			bd = d
			best = c
	return best


## Stick direction toward (floor, x): along the floor, via the stairs.
func move_toward_target(lvl: Node, tf: int, tx: float) -> Vector2:
	if lvl.climbing:
		return Vector2.ZERO
	if lvl.walker_floor != tf:
		var dir := 1 if tf > lvl.walker_floor else -1
		var sx := -1.0
		for rid in lvl.house.floors[lvl.walker_floor].rooms:
			if lvl.house.stair_link(rid, dir) != "":
				sx = lvl.house.room_center(rid)
		if sx < 0.0:
			return Vector2.ZERO
		if absf(lvl.walker_x - sx) > 3.0:
			return Vector2(signf(sx - lvl.walker_x), 0)
		return Vector2(0, -dir)
	var dx: float = tx - lvl.walker_x
	if absf(dx) <= 1.5:
		return Vector2.ZERO
	return Vector2(signf(dx) * clampf(absf(dx) / 10.0, 0.35, 1.0), 0)


## The laser: steer to a cat peeking from a spot on the walker's floor, then
## wiggle until it pounces; otherwise stay put (a still dot bores the cats).
func laser_brain(lvl: Node) -> Dictionary:
	var out := {}
	var target = null
	for c in lvl.cats:
		if c.state in [Cat.State.PEEK, Cat.State.STALK] and c.floor_i == lvl.walker_floor:
			target = c
	if target == null:
		_laser_a_prev = false
		return out
	var goal := Vector2(target.x + (10.0 if target.x < lvl.walker_x else -10.0), lvl.house.floor_y(target.floor_i) - 4)
	var d: Vector2 = goal - lvl.laser_pos
	if absf(d.x) > 3.0:
		out["move"] = Vector2(signf(d.x), 0)
	elif absf(d.y) > 3.0:
		out["move"] = Vector2(0, signf(d.y))
	var near := absf(target.x - lvl.laser_pos.x) < 40.0
	out["a"] = near and not _laser_a_prev and fmod(t, 0.8) < 0.1
	_laser_a_prev = out["a"]
	return out


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
