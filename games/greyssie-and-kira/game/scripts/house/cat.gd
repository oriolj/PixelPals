extends Node2D
## One cat: its state machine and its sprite. The house screen owns it and
## calls step(dt); the cat asks the level (walker, laser, house) what it needs.
##
## HIDDEN --spot opened--> ALERT --easy spot, bold cat--> HOP --> FREE
##                                --shy or high--> PEEK --laser near--> STALK --> HOP
##                                                      --no laser seat 3 s, or 12 s--> HOP
## HIDDEN --90 s--> WALKOUT (walks to the walker and meows) --> FREE
## FREE --dot near--> CHASE (stalk, pounce on the dot) --> FREE
## FREE --just freed, zoomies--> ZOOMIES (a lap up the stairs and back) --> FREE
## FREE --idle near an open box or basket--> GAG (too small / on the laundry)
## FREE / GAG --walker A--> CARRIED --walker A at the bowls--> EATING

enum State { SLIPPING, HIDDEN, ALERT, PEEK, STALK, HOP, FREE, CHASE, ZOOMIES, WALKOUT, CARRIED, EATING, GAG }

const TAIL_FURTHER_AT := 60.0
const WALK_OUT_AT := 90.0
const ALERT_TIME := 0.8
const PEEK_ALONE_NO_LASER := 3.0
const PEEK_ALONE_ANYWAY := 12.0
const SIGHT := 90.0
const STALK_TIME := 0.7
const STALK_TIME_WIGGLE := 0.25
const HOP_TIME := 0.45
const WALK_SPEED := 38.0
const ZOOM_SPEED := 150.0
const CHASE_SPEED := 45.0
const FREE_FOLLOW_AFTER := 25.0
const GAG_AFTER := 4.0

var id := ""
var info := {}
var level: Node
var state := State.HIDDEN
var floor_i := 0
var x := 0.0
## Height above the floor (hiding high, mid-hop).
var elev := 0.0
var facing := 1
var spot := ""
var hidden_t := 0.0
var state_t := 0.0
var free_t := 0.0
var idle_t := 0.0
var twitch_t := 0.0
var zoomed := false
var gagged := false
var slot := -1
var found := false
## A hop: from (x, elev) to (hop_x, 0) on hop_floor.
var hop_from := Vector2.ZERO
var hop_to_x := 0.0
var zoom_phase := 0
var zoom_home := 0.0
var spr: AnimatedSprite2D
var _anim := ""


func setup(cat_info: Dictionary, lvl: Node) -> void:
	info = cat_info
	id = cat_info.id
	level = lvl
	spr = AnimatedSprite2D.new()
	spr.centered = false
	add_child(spr)
	_set_anim("sit")


func needs_coaxing() -> bool:
	if info.get("needs_coaxing", false):
		return true
	return spot != "" and level.house.spots.has(spot) and level.house.spots[spot].high


func is_found() -> bool:
	return state not in [State.SLIPPING, State.HIDDEN]


## Can the walker pick it up now?
func pickable() -> bool:
	return state in [State.FREE, State.CHASE, State.GAG]


func hide_in(spot_id: String) -> void:
	var s: Dictionary = level.house.spots[spot_id]
	spot = spot_id
	floor_i = s.floor
	x = s.x
	elev = s.y
	state = State.HIDDEN
	hidden_t = 0.0
	state_t = 0.0
	found = false
	zoomed = false
	gagged = false
	slot = -1
	visible = false


func _go(s: State) -> void:
	state = s
	state_t = 0.0


## The walker opened the cat's spot.
func discovered() -> void:
	if state != State.HIDDEN:
		return
	found = true
	visible = true
	facing = -1 if level.walker_x < x else 1
	_go(State.ALERT)
	Sfx.play("mrrp", _pitch())


func _pitch() -> float:
	return 1.15 if info.get("needs_coaxing", false) else 1.0


func _hop_to(to_x: float) -> void:
	hop_from = Vector2(x, elev)
	hop_to_x = clampf(to_x, 4.0, level.house.width(floor_i) - 4.0)
	facing = 1 if hop_to_x >= x else -1
	_go(State.HOP)
	Sfx.play("pounce")


func step(dt: float) -> void:
	state_t += dt
	twitch_t = maxf(0.0, twitch_t - dt)
	match state:
		State.HIDDEN:
			hidden_t += dt
			if hidden_t >= WALK_OUT_AT:
				_walk_out()
		State.ALERT:
			if state_t >= ALERT_TIME:
				if needs_coaxing():
					_go(State.PEEK)
				else:
					# Out of the spot, landing on the walker's side.
					_hop_to(x + (-14.0 if level.walker_x < x else 14.0))
		State.PEEK:
			var lured: bool = level.laser_active() and level.laser_floor() == floor_i \
				and level.laser_moving() and absf(level.laser_x() - x) < SIGHT
			if lured:
				_go(State.STALK)
			elif (not level.laser_seated() and state_t >= PEEK_ALONE_NO_LASER) or state_t >= PEEK_ALONE_ANYWAY:
				_hop_to(level.walker_x + (16.0 if x > level.walker_x else -16.0))
		State.STALK:
			facing = 1 if level.laser_x() >= x else -1
			var need := STALK_TIME_WIGGLE if level.laser_wiggling() else STALK_TIME
			if not level.laser_active() or level.laser_floor() != floor_i:
				_go(State.PEEK)
			elif state_t >= need:
				_hop_to(level.laser_x())
		State.HOP:
			var k := clampf(state_t / HOP_TIME, 0.0, 1.0)
			x = lerpf(hop_from.x, hop_to_x, k)
			elev = lerpf(hop_from.y, 0.0, k) + sin(k * PI) * 14.0
			if k >= 1.0:
				elev = 0.0
				spot = ""
				_become_free()
		State.FREE:
			free_t += dt
			idle_t += dt
			if _dot_calls():
				_go(State.CHASE)
			elif free_t >= FREE_FOLLOW_AFTER and (level.walker_floor != floor_i or absf(level.walker_x - x) > 40.0):
				_walk_out()
			elif idle_t >= GAG_AFTER and not gagged:
				_try_gag()
		State.CHASE:
			free_t = 0.0
			idle_t = 0.0
			if not _dot_calls():
				_go(State.FREE)
			else:
				var dx: float = level.laser_x() - x
				facing = 1 if dx >= 0.0 else -1
				if absf(dx) < 10.0 or (level.laser_wiggling() and absf(dx) < 24.0):
					_hop_to(level.laser_x())
					Sfx.play("prrt", _pitch())
				else:
					x += signf(dx) * minf(absf(dx), CHASE_SPEED * dt)
					level.cat_passes(self)
		State.ZOOMIES:
			_zoom(dt)
		State.WALKOUT:
			if level.walker_floor != floor_i:
				_arrive_on_walker_floor()
			var dx: float = level.walker_x - x
			facing = 1 if dx >= 0.0 else -1
			if absf(dx) <= 16.0:
				level.cat_meows(self)
				_become_free(false)
			else:
				x += signf(dx) * minf(absf(dx) - 16.0, WALK_SPEED * 1.4 * dt)
				level.cat_passes(self)
		State.GAG:
			pass
		State.CARRIED, State.EATING, State.SLIPPING:
			pass


func _become_free(allow_zoomies := true) -> void:
	_go(State.FREE)
	free_t = 0.0
	idle_t = 0.0
	if allow_zoomies and not zoomed and not level.is_night() and level.rng.randf() < float(info.get("zoomies", 0.3)):
		zoomed = true
		_start_zoomies()


func _dot_calls() -> bool:
	return level.laser_active() and level.laser_floor() == floor_i and level.laser_moving() \
		and absf(level.laser_x() - x) < SIGHT and absf(level.laser_x() - x) > 6.0


func _walk_out() -> void:
	if not found:
		found = true
		level.record_find(self)
	visible = true
	elev = 0.0
	spot = ""
	if level.walker_floor != floor_i:
		_arrive_on_walker_floor()
	_go(State.WALKOUT)
	level.cat_meows(self)


## A cat on another floor comes down (or up) the stairs to the walker's floor.
func _arrive_on_walker_floor() -> void:
	floor_i = level.walker_floor
	var stairs := ""
	for rid in level.house.floors[floor_i].rooms:
		if level.house.is_stairs(rid):
			stairs = rid
	if stairs != "":
		x = level.house.room_center(stairs)
	else:
		x = clampf(level.walker_x - 40.0, 4.0, level.house.width(floor_i) - 4.0)
	elev = 0.0


func _try_gag() -> void:
	idle_t = 0.0
	for sid in level.house.spots:
		var s: Dictionary = level.house.spots[sid]
		if s.floor != floor_i or s.y != 0 or absf(s.x - x) > 44.0:
			continue
		if not level.spot_is_open(sid) or level.spot_has_cat(sid):
			continue
		if s.tags.has("box"):
			gagged = true
			spot = sid
			hop_from = Vector2(x, elev)
			x = s.x
			elev = 6.0
			_go(State.GAG)
			Sfx.play("mrrp", _pitch())
			level.gags += 1
			return


func _start_zoomies() -> void:
	_go(State.ZOOMIES)
	zoom_phase = 0
	zoom_home = x
	Sfx.play("zoomies")


## A lap: run to the stairs, vanish up for a moment, run back to the dot (or
## the walker) on the same floor. Nobody is ever stranded on another floor.
func _zoom(dt: float) -> void:
	var stairs := ""
	for rid in level.house.floors[floor_i].rooms:
		if level.house.is_stairs(rid):
			stairs = rid
	match zoom_phase:
		0:
			var tx: float = level.house.room_center(stairs) if stairs != "" else 4.0
			var dx := tx - x
			facing = 1 if dx >= 0.0 else -1
			x += signf(dx) * minf(absf(dx), ZOOM_SPEED * dt)
			level.cat_passes(self)
			if absf(dx) < 2.0:
				zoom_phase = 1
				state_t = 0.0
				visible = false
				Sfx.play("zoomies")
		1:
			if state_t >= 1.2:
				zoom_phase = 2
				visible = true
		2:
			var tx: float = level.laser_x() if level.laser_active() and level.laser_floor() == floor_i else level.walker_x + 18.0
			var dx := tx - x
			facing = 1 if dx >= 0.0 else -1
			x += signf(dx) * minf(absf(dx), ZOOM_SPEED * dt)
			level.cat_passes(self)
			if absf(dx) < 2.0 or state_t > 6.0:
				visible = true
				_go(State.FREE)


func carry(s: int) -> void:
	slot = s
	spot = ""
	elev = 0.0
	_go(State.CARRIED)
	Sfx.play("purr", 1.0, -4.0)


func eat_at(bowl_x: float, bowl_floor: int) -> void:
	slot = -1
	floor_i = bowl_floor
	x = bowl_x
	elev = 0.0
	facing = 1
	visible = true
	_go(State.EATING)


# ---------------------------------------------------------------- view

func _set_anim(anim: String) -> void:
	if anim == _anim:
		return
	_anim = anim
	var name := "%s_%s" % [id, anim]
	var sf := Art.frames(name, info.get("fur", Color.GRAY), Vector2i(20, 16))
	spr.sprite_frames = sf
	spr.play("default")
	var sz := Art.size_of(name, Vector2i(20, 16))
	spr.offset = Vector2(-sz.x / 2, -sz.y)


func update_view() -> void:
	var a := "sit"
	match state:
		State.ALERT, State.PEEK:
			a = "alert"
		State.STALK:
			a = "stalk"
		State.HOP:
			a = "pounce"
		State.FREE:
			a = "sleep" if level.is_night() and idle_t > 3.0 else ("idle" if idle_t < 2.0 else "sit")
		State.CHASE:
			a = "stalk"
		State.ZOOMIES:
			a = "zoomies"
		State.WALKOUT:
			a = "walk"
		State.CARRIED:
			a = "carried"
		State.EATING:
			a = "eat"
		State.GAG:
			a = "sit"
		State.SLIPPING:
			a = "zoomies"
	_set_anim(a)
	z_index = 2 if state in [State.EATING, State.CARRIED] else 0  # never behind the walker at the bowls
	spr.flip_h = facing < 0
	if state == State.HOP:
		var k := clampf(state_t / HOP_TIME, 0.0, 1.0)
		spr.stop()
		spr.frame = 0 if k < 0.2 else (1 if k < 0.85 else 2)
	if state != State.CARRIED:
		position = Vector2(roundf(x), level.house.floor_y(floor_i) - roundf(elev))
