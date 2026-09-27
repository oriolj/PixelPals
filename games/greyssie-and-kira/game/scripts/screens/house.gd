extends Node2D
## The level: one day in the house, four rounds (morning, afternoon, evening,
## night). All logic runs in step(dt); tests drive it with set_process(false).
##
## Seats: Game.WALKER walks (left/right, up/down on stairs) and presses "a"
## to open or close a spot, pick up a cat that came out, or put the cats
## down at their bowls. Game.LASER moves the red dot in 4 directions inside
## the walker's floor; "a" wiggles it. Game.TREATS: any press shakes the
## treat bag and the nearest cat meows back (bubble + mini view).
## Fallbacks: no toddler -> the bag shakes itself every 12 s; walker alone ->
## holding "a" shakes the treats and the dot follows the walker; no laser
## seat -> a coaxed cat comes out on its own after 3 s.
## No-fail: at 60 s a hidden cat's tail pokes further, at 90 s it walks out.

const HouseData := preload("res://scripts/house/house_data.gd")
const HideDirector := preload("res://scripts/house/hide_director.gd")
const Cat := preload("res://scripts/house/cat.gd")
const HouseView := preload("res://scripts/house/house_view.gd")
const MiniView := preload("res://scripts/house/mini_view.gd")

enum State { INTRO, SEARCH, DINNER, DONE }

const WALK_SPEED := 72.0
const CLIMB_TIME := 0.9
const LASER_SPEED := 110.0
const REACH := 18.0
const BOWL_REACH := 26.0
const MEOW_COOLDOWN := 1.0
const SECOND_MEOW_AFTER := 0.55
const BUBBLE_TIME := 2.0
const MINI_TIME := 2.0
const AUTO_SHAKE_EVERY := 12.0
const HOLD_SHAKE := 0.45
const HOLD_REPEAT := 1.5
const INTRO_TIME := 2.2
const DINNER_TIME := 3.5
const FIND_SHOW := 1.6
const WIGGLE_TIME := 0.8
const FUNNY_FINDS: Array[String] = ["toy_mouse", "sock", "wool_ball", "dust_bunny"]
## CanvasModulate per part of the day: warm, and the night is amber, never dark.
const TINTS: Array[Color] = [Color(1, 1, 1), Color(1.0, 0.96, 0.88), Color(1.0, 0.88, 0.78), Color(0.95, 0.82, 0.72)]
const SHOULDER: Array[Vector2] = [Vector2(-7, -19), Vector2(7, -19)]

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var house: RefCounted
var rng := RandomNumberGenerator.new()
var state := State.INTRO
var state_t := 0.0
var round_t := 0.0
var time := 0.0
var paused := false

var cats: Array = []  # Cat nodes, cats.json order
var walker_floor := 0
var walker_x := 0.0
var facing := 1
var climbing := false
var climb_t := 0.0
var climb_from := Vector2.ZERO
var climb_to := Vector2.ZERO
var climb_floor := 0
## cat id per shoulder slot ("" = free)
var carrying: Array[String] = ["", ""]
var hold_a := 0.0
var _hold_fired := false

var laser_pos := Vector2.ZERO
var wiggle_t := 0.0
var laser_still_t := 0.0

var spot_open := {}   # spot id -> bool
var spot_nodes := {}  # spot id -> AnimatedSprite2D
var tell_nodes := {}  # cat id -> AnimatedSprite2D (tail tip or eyes)
var last_spots := {}
var placement := {}

var meow_cooldown := 0.0
var queued: Array[Dictionary] = []  # [{"cat", "at"}]
var meows := {}  # cat id -> count
var shakes := 0
var auto_shake_t := 0.0
var last_meow_cat := ""
var last_meow_room := ""
var bubble_t := 0.0
var mini_t := 0.0
var funny_bag: Array[String] = []
var funny_shown: Array[String] = []
var gags := 0
var cups := []  # [{"x", "floor", "node", "fallen", "t", "vy", "y"}]
var fx: Array[Dictionary] = []  # floating hearts, stars, finds, zzz

var cam := Vector2.ZERO
var world: Node2D
var view: Node2D
var spots_layer: Node2D
var actors: Node2D
var fx_layer: Node2D
var walker_spr: AnimatedSprite2D
var laser_spr: AnimatedSprite2D
var laser_ring: Node2D
var bubble: AnimatedSprite2D
var bowl_nodes := {}
var tint: CanvasModulate
var hud: CanvasLayer
var hud_draw: Node2D
var mini: Node2D
var bag_spr: AnimatedSprite2D
var bag_t := 0.0
var pause_overlay: Node2D
var lamp_nodes: Array[AnimatedSprite2D] = []
var glow: Node2D
var _walker_anim := ""
var _climb_step_t := 0.0
var _cam_ready := false


func _ready() -> void:
	rng.randomize()
	house = Game.house
	_build()
	Game.new_day()
	start_round(Game.round_index)


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

func _build() -> void:
	world = Node2D.new()
	add_child(world)
	view = HouseView.new()
	view.house = house
	world.add_child(view)
	glow = Glow.new()
	glow.level = self
	world.add_child(glow)
	spots_layer = Node2D.new()
	world.add_child(spots_layer)
	# Furniture (behind the spots) and the cups.
	for rid in house.rooms:
		for fu in house.rooms[rid].furniture:
			var s := _bottom_sprite(fu.kind, Color("#b13e53"), Vector2i(20, 20))
			s.position = Vector2(fu.x, house.floor_y(house.rooms[rid].floor) - fu.y)
			s.stop()
			spots_layer.add_child(s)
			if fu.kind == "furn_lamp":
				lamp_nodes.append(s)
			if fu.cup:
				var c := _bottom_sprite("cup", Color("#f4f4f4"), Vector2i(8, 8))
				c.stop()
				spots_layer.add_child(c)
				var top := Art.size_of(fu.kind, Vector2i(20, 20)).y
				cups.append({"x": float(fu.x) + 6.0, "floor": house.rooms[rid].floor, "node": c, "fallen": false,
					"t": 0.0, "vy": 0.0, "y": float(top + fu.y), "table_y": float(top + fu.y)})
	for sid in house.spot_order:
		var s: Dictionary = house.spots[sid]
		var n := _bottom_sprite(s.sprite, Color("#ef7d57"), Vector2i(20, 16))
		n.stop()
		n.position = Vector2(s.x, house.floor_y(s.floor) - s.y)
		spots_layer.add_child(n)
		spot_nodes[sid] = n
		spot_open[sid] = false
	# Bowls, one per cat, side by side.
	var cat_list: Array = Game.cat_data.cats
	for i in cat_list.size():
		var id: String = cat_list[i].id
		var b := _bottom_sprite("bowl_" + id, cat_list[i].collar, Vector2i(12, 8))
		b.stop()
		b.position = Vector2(bowl_x(i), house.floor_y(house.bowls.floor))
		spots_layer.add_child(b)
		bowl_nodes[id] = b
	actors = Node2D.new()
	world.add_child(actors)
	for info in cat_list:
		var tell := _bottom_sprite(info.id + "_tail_tip", info.collar, Vector2i(8, 12))
		tell.visible = false
		actors.add_child(tell)
		tell_nodes[info.id] = tell
	for info in cat_list:
		var c := Cat.new()
		c.setup(info, self)
		actors.add_child(c)
		cats.append(c)
		meows[info.id] = 0
	walker_spr = AnimatedSprite2D.new()
	walker_spr.centered = false
	actors.add_child(walker_spr)
	_set_walker_anim("walk")
	fx_layer = Node2D.new()
	world.add_child(fx_layer)
	laser_spr = _bottom_sprite("laser_dot", Color("#b13e53"), Vector2i(5, 5))
	laser_spr.offset = Vector2(-2, -2)
	laser_spr.z_index = 21
	world.add_child(laser_spr)
	laser_ring = LaserRing.new()
	laser_ring.z_index = 20
	world.add_child(laser_ring)
	bubble = _bottom_sprite("meow_bubble_" + cat_list[0].id, Color.WHITE, Vector2i(20, 14))
	bubble.visible = false
	bubble.z_index = 30
	world.add_child(bubble)
	tint = CanvasModulate.new()
	add_child(tint)
	# HUD on its own canvas layer (not tinted by the time of day).
	hud = CanvasLayer.new()
	hud.layer = 10
	add_child(hud)
	hud_draw = Hud.new()
	hud_draw.level = self
	hud.add_child(hud_draw)
	bag_spr = _bottom_sprite("treat_bag", Game.hat_color(Game.TREATS), Vector2i(12, 14))
	bag_spr.stop()
	bag_spr.position = Vector2(306, 20)
	hud.add_child(bag_spr)
	mini = MiniView.new()
	mini.house = house
	mini.position = Vector2(128, 1)
	mini.visible = false
	hud.add_child(mini)
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	hud.add_child(pause_overlay)


func _bottom_sprite(name: String, tint_c: Color, size: Vector2i) -> AnimatedSprite2D:
	var s := Art.sprite(name, tint_c, size)
	s.centered = false
	var sz := Art.size_of(name, size)
	s.offset = Vector2(-sz.x / 2, -sz.y)
	return s


func bowl_x(i: int) -> float:
	var n: int = Game.cat_data.cats.size()
	return house.bowls.x + (i - (n - 1) / 2.0) * 14.0


# ================================================================ rounds

## Starts round `index` of the day. `forced` = {cat id: spot id} (tests, demo).
func start_round(index: int, forced := {}, skip_intro := false) -> void:
	Game.round_index = index
	state = State.INTRO
	state_t = 0.0
	round_t = 0.0
	for sid in spot_open:
		spot_open[sid] = false
	for c in cups:
		c.fallen = false
		c.y = c.table_y
	funny_bag.assign(FUNNY_FINDS)
	_shuffle(funny_bag)
	funny_shown.clear()
	carrying = ["", ""]
	if index == 0 or house.start.is_empty():
		walker_floor = house.start.floor
		walker_x = house.start.x
	climbing = false
	var night := Game.is_night()
	placement = forced if not forced.is_empty() else HideDirector.choose(house, Game.cat_data.cats, night, rng, last_spots)
	last_spots = placement.duplicate()
	for i in cats.size():
		var c: Cat = cats[i]
		c.state = Cat.State.SLIPPING
		c.state_t = 0.0
		c.floor_i = walker_floor
		c.x = walker_x + (10.0 if i % 2 == 0 else -10.0)
		c.elev = 0.0
		c.visible = true
		c.facing = 1 if i % 2 == 0 else -1
	laser_pos = Vector2(walker_x + 30.0, house.floor_y(walker_floor) - 6)
	laser_still_t = 99.0  # a dot nobody moved yet lures nobody
	view.set_day_part(Game.day_part(), index)
	tint.color = TINTS[clampi(index, 0, TINTS.size() - 1)]
	for l in lamp_nodes:
		l.frame = 1 if index >= 2 else 0
	for id in bowl_nodes:
		bowl_nodes[id].frame = 0
	Sfx.music("music_night" if night else "music_house")
	if Game.demo:
		print("DAY round %d %s %s" % [index, Game.day_part(), str(placement)])
	if index > 0:
		Sfx.play("day_chime")
	Sfx.play("whoosh")
	Sfx.play("giggle")
	if skip_intro:
		_hide_cats()


func _hide_cats() -> void:
	state = State.SEARCH
	state_t = 0.0
	round_t = 0.0
	for c in cats:
		if placement.has(c.id):
			c.hide_in(placement[c.id])
		else:
			c.hide_in(house.spot_order[0])


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


func is_night() -> bool:
	return Game.is_night()


# ================================================================ step

func step(dt: float) -> void:
	if state == State.DONE:
		return
	time += dt
	if _pause_input():
		_update_view(0.0)
		return
	state_t += dt
	_toddler(dt)
	_laser(dt)
	match state:
		State.INTRO:
			for c in cats:
				c.x += c.facing * 150.0 * dt
			if state_t >= INTRO_TIME:
				_hide_cats()
		State.SEARCH:
			round_t += dt
			_walker(dt)
			for c in cats:
				c.step(dt)
			_auto_shake(dt)
			if all_eating():
				state = State.DINNER
				state_t = 0.0
				Sfx.play("find_star")
				_add_fx("star", Vector2(house.bowls.x, house.floor_y(house.bowls.floor) - 34), 3.0, 0.0)
		State.DINNER:
			_walker(dt)
			if state_t >= DINNER_TIME:
				_end_round()
	for q in queued.duplicate():
		q.at -= dt
		if q.at <= 0.0:
			queued.erase(q)
			_meow_now(_cat(q.cat))
	meow_cooldown = maxf(0.0, meow_cooldown - dt)
	bubble_t = maxf(0.0, bubble_t - dt)
	mini_t = maxf(0.0, mini_t - dt)
	wiggle_t = maxf(0.0, wiggle_t - dt)
	bag_t = maxf(0.0, bag_t - dt)
	_step_cups(dt)
	_update_view(dt)


func _end_round() -> void:
	Game.stars += 1
	if Game.round_index >= Game.DAY.size() - 1:
		state = State.DONE
		if Game.demo:
			print("DAY done after %d finds, %d gags, %d shakes" % [Game.finds.size(), gags, shakes])
		Game.finish_day()
		Sfx.play("goodnight")
		next_screen = "party"
		if auto_goto:
			Game.goto.call_deferred("party")
	else:
		start_round(Game.round_index + 1)


func all_eating() -> bool:
	for c in cats:
		if c.state != Cat.State.EATING:
			return false
	return not cats.is_empty()


func _cat(id: String) -> Cat:
	for c in cats:
		if c.id == id:
			return c
	return null


# ================================================================ walker

func _walker(dt: float) -> void:
	if climbing:
		climb_t += dt
		_climb_step_t -= dt
		if _climb_step_t <= 0.0:
			_climb_step_t = 0.2
			Sfx.play("stairs_step", 1.0 + rng.randf_range(-0.05, 0.05), -6.0)
		if climb_t >= CLIMB_TIME:
			climbing = false
			walker_floor = climb_floor
			walker_x = climb_to.x
			laser_pos.y = house.floor_y(walker_floor) - 6
			laser_pos.x = walker_x + facing * 30.0
		return
	var mv := Players.move(Game.WALKER)
	if absf(mv.x) > 0.2:
		facing = 1 if mv.x > 0.0 else -1
		walker_x = clampf(walker_x + mv.x * WALK_SPEED * dt, 6.0, house.width(walker_floor) - 6.0)
	var d := Players.dir4(Game.WALKER)
	if d.y != 0:
		try_climb(-d.y)
	# "a": tap acts; with the walker alone, holding it shakes the treats.
	var solo := not Players.is_seated(Game.TREATS) and not Players.is_seated(Game.LASER)
	if solo:
		if Players.pressed(Game.WALKER, "a"):
			hold_a += dt
			if hold_a >= HOLD_SHAKE and (not _hold_fired or hold_a >= HOLD_SHAKE + HOLD_REPEAT):
				if _hold_fired:
					hold_a = HOLD_SHAKE
				_hold_fired = true
				shake()
		else:
			if hold_a > 0.0 and not _hold_fired:
				walker_action()
			hold_a = 0.0
			_hold_fired = false
	elif Players.just_pressed(Game.WALKER, "a"):
		walker_action()


func walker_room() -> String:
	return house.room_at(walker_floor, walker_x)


## Climb up (dir 1) or down (-1) when standing in a stairs room. True if started.
func try_climb(dir: int) -> bool:
	if climbing:
		return false
	var link: String = house.stair_link(walker_room(), dir)
	if link == "":
		return false
	climbing = true
	climb_t = 0.0
	_climb_step_t = 0.0
	climb_floor = house.rooms[link].floor
	climb_from = Vector2(walker_x, house.floor_y(walker_floor))
	climb_to = Vector2(house.room_center(link), house.floor_y(climb_floor))
	return true


## The walker's "a": put down at the bowls, pick up a cat, or open/close a spot.
func walker_action() -> String:
	if state != State.SEARCH and state != State.DINNER:
		return ""
	if climbing:
		return ""
	if carried_count() > 0 and walker_floor == house.bowls.floor and absf(walker_x - house.bowls.x) <= BOWL_REACH:
		put_down_at_bowls()
		return "bowls"
	var near := _nearest_pickable()
	if near and _free_slot() != -1:
		pick_up(near)
		return "pick"
	var sid := nearest_spot()
	if sid != "":
		if spot_open[sid]:
			close_spot(sid)
			return "close"
		open_spot(sid)
		return "open"
	return ""


func carried_count() -> int:
	return carrying.count("") * -1 + 2


func _free_slot() -> int:
	return carrying.find("")


func _nearest_pickable() -> Cat:
	var best: Cat = null
	var bd := REACH
	for c in cats:
		if c.pickable() and c.floor_i == walker_floor and absf(c.x - walker_x) <= bd:
			best = c
			bd = absf(c.x - walker_x)
	return best


func pick_up(c: Cat) -> bool:
	var s := _free_slot()
	if s == -1 or not c.pickable():
		return false
	carrying[s] = c.id
	c.carry(s)
	for k in 3:
		_add_fx("heart", Vector2(walker_x + (k - 1) * 6, house.floor_y(walker_floor) - 30), 1.2, k * 0.15)
	return true


func put_down_at_bowls() -> int:
	var n := 0
	var cat_list: Array = Game.cat_data.cats
	for s in 2:
		var id := carrying[s]
		if id == "":
			continue
		var c := _cat(id)
		var i := 0
		for k in cat_list.size():
			if cat_list[k].id == id:
				i = k
		c.eat_at(bowl_x(i) - 6.0, house.bowls.floor)
		bowl_nodes[id].frame = 1
		carrying[s] = ""
		n += 1
	if n > 0:
		Sfx.play("bowl_fill")
		Sfx.play("eat_crunch", 1.0, -3.0)
	return n


func nearest_spot() -> String:
	var best := ""
	var bd := REACH
	for sid in house.spot_order:
		var s: Dictionary = house.spots[sid]
		if s.floor != walker_floor:
			continue
		var d := absf(float(s.x) - walker_x)
		if d <= bd:
			best = sid
			bd = d
	return best


func spot_has_cat(sid: String) -> bool:
	for c in cats:
		if c.spot == sid and c.state in [Cat.State.HIDDEN, Cat.State.ALERT, Cat.State.PEEK, Cat.State.STALK, Cat.State.GAG]:
			return true
	return false


func spot_is_open(sid: String) -> bool:
	return spot_open.get(sid, false)


## Opens a spot: {"cat": id} when a cat hides there, else {"find": name}.
func open_spot(sid: String) -> Dictionary:
	spot_open[sid] = true
	var kind: String = house.spots[sid].kind
	Sfx.play("open_door" if kind in ["wardrobe", "cupboard", "desk", "curtain", "sunny_window"] else "open_box")
	for c in cats:
		if c.spot == sid and c.state == Cat.State.HIDDEN:
			c.discovered()
			record_find(c)
			return {"cat": c.id}
	var find := funny_bag[funny_shown.size() % funny_bag.size()]
	funny_shown.append(find)
	Sfx.play("funny_find")
	var s: Dictionary = house.spots[sid]
	var sz := Art.size_of(s.sprite, Vector2i(20, 16))
	_add_fx(find, Vector2(s.x, house.floor_y(s.floor) - s.y - sz.y / 2), FIND_SHOW, 0.0, true)
	return {"find": find}


func close_spot(sid: String) -> bool:
	if spot_has_cat(sid):
		return false
	spot_open[sid] = false
	Sfx.play("open_box", 0.8, -4.0)
	return true


func record_find(c: Cat) -> void:
	var sid: String = c.spot
	var kind: String = house.spots[sid].kind if house.spots.has(sid) else "walkout"
	Game.finds.append({"cat": c.id, "kind": kind, "spot": sid, "round": Game.round_index})


# ================================================================ toddler + treats

func _toddler(_dt: float) -> void:
	if Players.just_pressed(Game.TREATS, "any"):
		shake()


func _auto_shake(dt: float) -> void:
	if Players.is_seated(Game.TREATS):
		auto_shake_t = 0.0
		return
	var any_hidden := false
	for c in cats:
		if not c.is_found():
			any_hidden = true
	if not any_hidden:
		return
	auto_shake_t += dt
	if auto_shake_t >= AUTO_SHAKE_EVERY:
		auto_shake_t = 0.0
		shake()


## Shake the treat bag: always a rattle; the nearest cat meows back (with a
## short cooldown, so mashing still rattles and wiggles the bag). Never
## changes anything but voices, bubbles and the tail twitch.
func shake() -> Cat:
	shakes += 1
	bag_t = 0.5
	Sfx.play("treat_shake")
	if shakes % 2 == 1:
		Sfx.play("psst", 1.0, -4.0)
	if meow_cooldown > 0.0 or state == State.DONE:
		return null
	var c := nearest_cat()
	if c == null:
		return null
	meow_cooldown = MEOW_COOLDOWN
	_meow_now(c)
	if float(c.info.get("chatty", 0.0)) >= 0.5:
		queued.append({"cat": c.id, "at": SECOND_MEOW_AFTER})
	return c


## The cat still to be found (or brought to dinner) nearest to the walker.
func nearest_cat() -> Cat:
	var best: Cat = null
	var bd := INF
	for c in cats:
		if c.state in [Cat.State.EATING, Cat.State.CARRIED, Cat.State.SLIPPING]:
			continue
		var d: float = house.distance(walker_floor, walker_x, c.floor_i, c.x)
		if d < bd:
			bd = d
			best = c
	return best


func _meow_now(c: Cat) -> void:
	if c == null:
		return
	meows[c.id] = int(meows.get(c.id, 0)) + 1
	Sfx.play("meow_" + c.id)
	c.twitch_t = 2.0
	last_meow_cat = c.id
	last_meow_room = house.room_at(c.floor_i, c.x)
	bubble_t = BUBBLE_TIME
	mini_t = MINI_TIME
	mini.lit_room = last_meow_room
	mini.lit_color = c.info.collar
	bubble.sprite_frames = Art.frames("meow_bubble_" + c.id, c.info.collar, Vector2i(20, 14))
	bubble.play("default")


## Called by a cat that walks out (or reaches the walker) to announce itself.
func cat_meows(c: Cat) -> void:
	_meow_now(c)


# ================================================================ laser

func laser_seated() -> bool:
	return Players.is_seated(Game.LASER)


## The dot shows during the search (auto-following the walker when nobody holds it).
func laser_active() -> bool:
	return state == State.SEARCH and not climbing


func laser_floor() -> int:
	return walker_floor


func laser_x() -> float:
	return laser_pos.x


func laser_wiggling() -> bool:
	return wiggle_t > 0.0


## Cats chase a dot that moved recently (or wiggles); a parked dot is boring.
func laser_moving() -> bool:
	return laser_still_t < 2.5 or wiggle_t > 0.0


func _laser(dt: float) -> void:
	var moved := false
	var top: float = house.band_top(walker_floor) + HouseData.CEIL_Y + 4
	var bottom: float = house.floor_y(walker_floor) - 1
	if laser_seated():
		var d := Players.dir4(Game.LASER)
		laser_pos += Vector2(d) * LASER_SPEED * dt
		moved = d != Vector2i.ZERO
		if Players.just_pressed(Game.LASER, "a"):
			wiggle_t = WIGGLE_TIME
			Sfx.play("pounce", 1.6, -10.0)
	else:
		# Nobody holds the pointer: the dot trots ahead of the walker on the floor.
		var target := Vector2(walker_x + facing * 20.0, bottom - 3.0)
		moved = laser_pos.distance_to(target) > 0.5
		laser_pos = laser_pos.move_toward(target, 90.0 * dt)
	var w: float = house.width(walker_floor)
	laser_pos.x = clampf(laser_pos.x, maxf(cam.x + 3.0, 2.0), minf(cam.x + 317.0, w - 2.0))
	laser_pos.y = clampf(laser_pos.y, top, bottom)
	# Only a dot someone (or the walker) moves counts; being clamped does not.
	if moved:
		laser_still_t = 0.0
	else:
		laser_still_t += dt


# ================================================================ gags

## A cat passing a table knocks the cup off: boing, it bounces, nothing breaks.
func cat_passes(c: Cat) -> void:
	for cup in cups:
		if cup.fallen or cup.floor != c.floor_i:
			continue
		if absf(cup.x - c.x) < 6.0:
			cup.fallen = true
			cup.vy = -40.0
			cup.t = 0.0
			Sfx.play("cup_boing")


func _step_cups(dt: float) -> void:
	for cup in cups:
		if cup.fallen and cup.y > 0.0:
			cup.vy += 260.0 * dt
			cup.y -= cup.vy * dt
			if cup.y <= 0.0:
				cup.y = 0.0
				if absf(cup.vy) > 40.0:
					cup.vy = -cup.vy * 0.45
					cup.y = 0.1
					Sfx.play("cup_boing", 1.3, -6.0)
				else:
					cup.vy = 0.0
		var n: AnimatedSprite2D = cup.node
		n.frame = 1 if cup.fallen else 0
		n.position = Vector2(roundf(cup.x + (8.0 if cup.fallen else 0.0)), house.floor_y(cup.floor) - roundf(cup.y))


# ================================================================ fx

func _add_fx(name: String, at: Vector2, life: float, delay: float, rise := false) -> void:
	var s := Art.sprite(name, Color("#ffcd75"), Vector2i(8, 8))
	s.visible = delay <= 0.0
	fx_layer.add_child(s)
	fx.append({"node": s, "at": at, "life": life, "t": -delay, "rise": rise, "name": name})


func _step_fx(dt: float) -> void:
	for f in fx.duplicate():
		f.t += dt
		var n: AnimatedSprite2D = f.node
		n.visible = f.t >= 0.0
		var k := clampf(f.t / f.life, 0.0, 1.0)
		var lift := (minf(f.t, 0.3) / 0.3 * 12.0) if f.rise else k * 16.0
		n.position = (f.at - Vector2(0, lift)).round()
		if f.t >= f.life:
			n.queue_free()
			fx.erase(f)


# ================================================================ view

func _update_view(dt: float) -> void:
	_step_fx(dt)
	# Walker.
	var wpos := Vector2(walker_x, house.floor_y(walker_floor))
	if climbing:
		wpos = climb_from.lerp(climb_to, clampf(climb_t / CLIMB_TIME, 0.0, 1.0))
	var moving := absf(Players.move(Game.WALKER).x) > 0.2 and state != State.INTRO
	var anim := "climb" if climbing else ("carry" if carried_count() > 0 else "walk")
	_set_walker_anim(anim)
	if anim == "walk" and not moving:
		walker_spr.stop()
		walker_spr.frame = 0
	elif not walker_spr.is_playing():
		walker_spr.play("default")
	walker_spr.flip_h = facing < 0
	walker_spr.position = wpos.round()
	for s in 2:
		var id := carrying[s]
		if id != "":
			var c := _cat(id)
			c.position = (wpos + SHOULDER[s] + Vector2(0, 8)).round()
			c.spr.flip_h = s == 0
			c.update_view()
	# Cats and their tells.
	for c in cats:
		if c.state != Cat.State.CARRIED:
			c.update_view()
		_update_tell(c)
	# Spots: open/closed frames.
	for sid in spot_nodes:
		spot_nodes[sid].frame = 1 if spot_open[sid] else 0
	# Laser dot.
	laser_spr.visible = laser_active()
	var jig := Vector2.ZERO
	if wiggle_t > 0.0:
		jig = Vector2(roundf(sin(time * 40.0) * 2.0), roundf(cos(time * 33.0) * 1.0))
	laser_spr.position = (laser_pos + jig).round()
	laser_ring.visible = laser_spr.visible
	laser_ring.position = laser_spr.position
	laser_ring.set("t", time)
	laser_ring.queue_redraw()
	# Meow bubble on the wall of the meowing room.
	bubble.visible = bubble_t > 0.0
	if bubble.visible and last_meow_room != "":
		var r: Dictionary = house.rooms[last_meow_room]
		var c := _cat(last_meow_cat)
		var bx := clampf(c.x, r.x0 + 12.0, r.x0 + r.w - 12.0)
		var by: float = house.band_top(r.floor) + HouseData.CEIL_Y + 30 - (2.0 if int(time * 4.0) % 2 == 0 else 0.0)
		bubble.position = Vector2(bx, by).round()
		bubble.frame = 0 if bubble_t > BUBBLE_TIME - 0.15 else 1
		bubble.stop()
	mini.visible = mini_t > 0.0
	mini.walker_room = walker_room()
	bag_spr.frame = (int(time * 16.0) % 2) + 1 if bag_t > 0.0 else 0
	bag_spr.rotation = 0.0
	# Camera: follow the walker, lean toward the dot and the meow.
	_camera(dt, wpos)
	world.position = -cam.round()
	hud_draw.queue_redraw()
	glow.queue_redraw()


func _update_tell(c: Cat) -> void:
	var t: AnimatedSprite2D = tell_nodes[c.id]
	if c.state != Cat.State.HIDDEN or not house.spots.has(c.spot):
		t.visible = false
		return
	var s: Dictionary = house.spots[c.spot]
	var eyes: bool = s.tell == "eyes"
	var name: String = c.id + ("_peek_eyes" if eyes else "_tail_tip")
	if t.get_meta("name", "") != name:
		t.sprite_frames = Art.frames(name, c.info.collar, Vector2i(8, 12))
		t.set_meta("name", name)
		var sz := Art.size_of(name, Vector2i(8, 12))
		t.offset = Vector2(-sz.x / 2, -sz.y)
	t.visible = true
	t.stop()
	var ssz := Art.size_of(s.sprite, Vector2i(20, 16))
	var at: Vector2 = tell_offset(s, ssz, eyes)
	var further := c.hidden_t >= Cat.TAIL_FURTHER_AT
	if eyes:
		t.frame = 1 if int(time * 1.5) % 4 == 3 else 0
		if further:
			at.x += 4.0
	else:
		t.frame = 1 if further else 0
		if c.twitch_t > 0.0 and int(time * 8.0) % 2 == 0:
			at.x += 1.0
	t.position = Vector2(s.x, house.floor_y(s.floor) - s.y) + at


## Where a spot's tell sits relative to its bottom centre (house.json may say).
func tell_offset(s: Dictionary, ssz: Vector2i, eyes: bool) -> Vector2:
	var ta: Array = s.get("tell_at", [])
	if ta.size() == 2:
		return Vector2(float(ta[0]), float(ta[1]))
	if eyes:
		return Vector2(0, -2)
	return Vector2(ssz.x / 2 - 4, -ssz.y + 3)


func _camera(dt: float, wpos: Vector2) -> void:
	var w: float = house.width(walker_floor)
	var lean := 0.0
	if laser_seated() and laser_active():
		lean += (laser_pos.x - walker_x) * 0.35
	if bubble_t > 0.0 and last_meow_room != "" and house.rooms[last_meow_room].floor == walker_floor:
		lean += (house.room_center(last_meow_room) - walker_x) * 0.4
	var tx := walker_x - 160.0 + lean
	if climbing:
		tx = wpos.x - 160.0
	if w <= 320.0:
		tx = (w - 320.0) / 2.0
	else:
		tx = clampf(tx, 0.0, w - 320.0)
	var ty: float = wpos.y - HouseData.FLOOR_Y if climbing else float(house.band_top(walker_floor))
	var k := clampf(dt * 5.0, 0.0, 1.0)
	if not _cam_ready:
		_cam_ready = true
		cam = Vector2(tx, ty)
	cam.x = lerpf(cam.x, tx, k)
	cam.y = ty if climbing else lerpf(cam.y, ty, clampf(dt * 8.0, 0.0, 1.0))


func _set_walker_anim(anim: String) -> void:
	var rider: String = Players.riders[Game.WALKER]
	if rider == "":
		rider = Game.roster[0]
	var name := "%s_%s" % [anim, rider]
	if name == _walker_anim:
		return
	_walker_anim = name
	if not Art.has(name):
		name = rider  # a rider without a walker set still walks
	walker_spr.sprite_frames = Art.frames(name, Game.rider_color(rider), Vector2i(16, 20))
	walker_spr.play("default")
	var sz := Art.size_of(name, Vector2i(16, 20))
	walker_spr.offset = Vector2(-sz.x / 2, -sz.y)


# ================================================================ pause

## Pause belongs to the walker only. Returns true while paused.
func _pause_input() -> bool:
	if Players.just_pressed(Game.WALKER, "start"):
		set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(Game.WALKER, "a"):
			set_paused(false)
		elif Players.just_pressed(Game.WALKER, "b"):
			state = State.DONE
			Players.reset()
			next_screen = "join"
			if auto_goto:
				Game.goto.call_deferred("join")
	return paused


func set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	Sfx.play("select")


# ================================================================ inner nodes

## Warm lamp glows (evening and night): soft dithered pools of light.
class Glow extends Node2D:
	var level: Node

	func _draw() -> void:
		if level == null or Game.round_index < 2:
			return
		for l in level.lamp_nodes:
			var p: Vector2 = l.position - Vector2(0, 28)
			# Two dithered rings: a dense warm core and a sparse halo.
			for yy in range(-28, 29):
				for xx in range(-28, 29):
					var d2 := xx * xx + yy * yy
					var on := (xx + yy) % 2 == 0 and (d2 <= 14 * 14 or (d2 <= 28 * 28 and xx % 2 == 0 and yy % 2 == 0))
					if on:
						draw_rect(Rect2(p.x + xx, p.y + yy, 1, 1), Color("#ffcd75", 0.55))


## Behind the dot: an ink ring so it reads on any colour, and a pulsing
## yellow sparkle cross so small eyes find it.
class LaserRing extends Node2D:
	var t := 0.0

	func _draw() -> void:
		var ink := Color("#1a1c2c")
		draw_rect(Rect2(-3, -2, 7, 5), ink)
		draw_rect(Rect2(-2, -3, 5, 7), ink)
		var r := 5 + int(t * 6.0) % 2
		var y := Color("#ffcd75")
		for d in [Vector2(1, 0), Vector2(-1, 0), Vector2(0, 1), Vector2(0, -1)]:
			draw_rect(Rect2(d * r, Vector2(1, 1)), y)
			draw_rect(Rect2(d * (r + 1), Vector2(1, 1)), y)


## HUD: one badge per cat (found / carried / eating), the round stars, the
## part of the day, and the laser and treat seats' hat colours.
class Hud extends Node2D:
	var level: Node

	func _draw() -> void:
		if level == null:
			return
		var i := 0
		for c in level.cats:
			var p := Vector2(4 + i * 18, 3)
			var col: Color = c.info.collar
			draw_rect(Rect2(p, Vector2(16, 16)), col)
			draw_rect(Rect2(p + Vector2(1, 1), Vector2(14, 14)), Color("#1a1c2c") if not c.is_found() else col.lightened(0.45))
			var face: Texture2D = null
			if Art.has(c.id + "_face"):
				face = Art.frames(c.id + "_face").get_frame_texture("default", 0)
			if face:
				draw_texture(face, p + Vector2(2, 2), Color.WHITE if c.is_found() else Color(0.45, 0.45, 0.55))
			if c.state == 11:  # EATING
				draw_rect(Rect2(p + Vector2(12, 12), Vector2(4, 4)), Color("#38b764"))
			i += 1
		# Stars for the finished rounds, then the part of the day.
		for s in Game.DAY.size():
			var sp := Vector2(48 + s * 9, 6)
			var on := s < Game.stars
			draw_rect(Rect2(sp, Vector2(7, 7)), Color("#ffcd75") if on else Color("#333c57", 0.6))
			if s == Game.round_index:
				draw_rect(Rect2(sp + Vector2(0, 8), Vector2(7, 1)), Color("#f4f4f4"))
		var sun := Vector2(286, 9)
		match Game.round_index:
			0:
				draw_circle(sun, 4, Color("#ffcd75"))
			1:
				draw_circle(sun, 5, Color("#ffcd75"))
				draw_circle(sun, 3, Color("#f4f4f4"))
			2:
				draw_circle(sun, 5, Color("#ef7d57"))
			_:
				draw_circle(sun, 4, Color("#f4f4f4"))
				draw_circle(sun + Vector2(2, -1), 3, Color("#5d275d"))
		# Laser seat badge: a dot in the seat's hat colour ring.
		if level.laser_seated():
			draw_circle(Vector2(270, 9), 5, Game.hat_color(Game.LASER))
			draw_circle(Vector2(270, 9), 2, Color("#b13e53"))
		if Players.is_seated(Game.TREATS):
			draw_rect(Rect2(298, 1, 16, 3), Game.hat_color(Game.TREATS))


## Pause: a warm veil, a back arrow (walker "b") and a play triangle.
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.36, 0.15, 0.36, 0.55))
		draw_circle(Vector2(110, 90), 22, Color("#b13e53"))
		draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
			Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#f4f4f4"))
		draw_circle(Vector2(210, 90), 26, Color("#38b764"))
		draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
			Color("#f4f4f4"))
