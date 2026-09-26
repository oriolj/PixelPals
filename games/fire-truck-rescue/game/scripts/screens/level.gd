extends Node2D
## The run: a low-poly toy town rendered in a 480x270 SubViewport, the pixel
## HUD on top. Dad drives the truck, the hose seat puts fires out, the siren
## seat runs the siren, the lights and the ladder that rescues the cats.
## No game over: bumps bounce, fires never spread, the truck unsticks
## itself, and at the end (all done, or 6 minutes) the sky turns to sunset
## and an arrow leads home; parking in the station starts the party.
##
## All logic lives in step(dt), so tests drive it frame by frame with
## set_process(false) and scripted devices.

const TownMap := preload("res://scripts/level/town_map.gd")
const TownGen := preload("res://scripts/level/town_gen.gd")
const TruckModel := preload("res://scripts/level/truck_model.gd")
const TruckView := preload("res://scripts/level/truck_view.gd")
const FireState := preload("res://scripts/level/fire_state.gd")
const FireView := preload("res://scripts/level/fire_view.gd")
const WaterArc := preload("res://scripts/level/water_arc.gd")
const Cars := preload("res://scripts/level/cars.gd")
const Hud := preload("res://scripts/level/hud.gd")
const Loops := preload("res://scripts/level/loops.gd")
const Rules := preload("res://scripts/level/rules.gd")
const Low := preload("res://scripts/level/low.gd")

const W := 480
const H := 270
const DRIVER := 0            # Players.Seat.DRIVER
const HOSE := 1              # Players.Seat.GUNNER (the hose)
const SIREN := 2             # Players.Seat.HONKER (the siren)
const CAT_AFTER := [1, 3, 5] # a cat gets stuck after the 2nd, 4th and 6th fire
const CAM_PITCH := deg_to_rad(55.0)
const CAM_DIST := 17.0
const CAM_DIST_SPRAY := 21.0
const SKY_DAY := Color("#73c6f6")
const SKY_SUNSET := Color("#ef7d57")
const GIGGLE_EVERY := 1.2
const RESCUE_RAISE := 1.0
const RESCUE_HOP := 1.5
const RESCUE_DOWN := 3.0
const RESCUE_END := 4.0

enum State { RUN, HOMEWARD, PARKED }

## Tests: record next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var state := State.RUN
var paused := false
var time := 0.0
var run_len := Rules.RUN_SECONDS
var stars := 0
var shown_stars := 0
var cats_saved := 0
var bucket_bounce := 0.0

var map: TownMap
var truck: TruckModel
var fires: Array = []
var order: Array[int] = []
var order_i := -1
var next_fire_t := Rules.FIRST_FIRE_DELAY
## [{tree: Vector2, perch: Vector3, facing, park: Vector2i, waiting, rescued, gone, sprite, meow_t, shake, pop}]
var cats: Array[Dictionary] = []
## order position -> cat index
var cat_after := {}
## {} or {cat: int, t: float, solve: Dictionary}
var rescue := {}
var parked_t := 0.0
var park_t := 0.0

var siren_t := 0.0
var siren_cd := 0.0
var siren_count := 0
var bark_count := 0
var horn_count := 0
var lights_t := 0.0
## Game time of the last answered press per seat (tests: "within 2 frames").
var answered := [-1.0, -1.0, -1.0]

var aim_dir := Vector2i(0, -1)
var spraying := false
var spray_fire := -1
var spray_point := Vector2.ZERO
var super_t := 0.0
var super_count := 0
var hydrant_cd: Array[float] = []
var giggles := 0
var _giggle_cd := 0.0

var left_station := false
var inside_station := true
var door_open := 1.0
var sunset := 0.0
var cam_yaw := 0.0
var cam_dist := CAM_DIST
var cam_focus := Vector2.ZERO

var vp: SubViewport
var world: Node3D
var cam: Camera3D
var sun: DirectionalLight3D
var env: Environment
var view: Sprite2D
var tview: TruckView
var fire_views: Array = []
var arc: WaterArc
var cars: Cars
var hud: Hud
var loops: Loops
var town := {}
var ground_arrow: Node3D
var home_marker: Node3D
var fx: Array[Dictionary] = []
var flyers: Array[Dictionary] = []
var thankers: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 2026
	map = TownMap.new()
	truck = TruckModel.new()
	_build()
	_start_state()
	var preset := Game.level_preset
	Game.level_preset = ""
	if preset != "":
		apply_preset(preset)
	cam_yaw = truck.yaw
	cam_focus = truck.pos
	Sfx.music("music_town")


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

func _build() -> void:
	vp = SubViewport.new()
	vp.size = Vector2i(W, H)
	vp.own_world_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(vp)
	world = Node3D.new()
	vp.add_child(world)
	env = Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = SKY_DAY
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#fff4e8")
	env.ambient_light_energy = 0.32
	env.fog_enabled = true
	env.fog_light_color = SKY_DAY
	env.fog_density = 0.0015
	var we := WorldEnvironment.new()
	we.environment = env
	world.add_child(we)
	sun = DirectionalLight3D.new()
	sun.rotation = Vector3(deg_to_rad(-52.0), deg_to_rad(-35.0), 0)
	sun.light_energy = 0.72
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 70.0
	world.add_child(sun)
	cam = Camera3D.new()
	cam.fov = 48.0
	cam.near = 0.3
	cam.far = 500.0
	world.add_child(cam)
	cam.current = true

	var cast: Array[String] = []
	cast.assign(Game.roster)
	town = TownGen.new().build(world, map, cast)
	for i in map.cats.size():
		town.cat_trees[i].rotation.y = TruckModel.yaw_of(Vector2(map.cats[i].facing))

	tview = TruckView.new()
	world.add_child(tview)
	var riders: Array[String] = []
	var seated: Array[bool] = []
	for s in 3:
		var r: String = Players.riders[s]
		if r == "" and not Game.roster.is_empty():
			r = Game.roster[s % Game.roster.size()]
		riders.append(r)
		seated.append(Players.is_seated(s))
	tview.set_crew(riders, seated)

	for i in map.fires.size():
		var f := FireState.new()
		f.index = i
		f.pos = map.fires[i].pos
		f.kind = map.fires[i].kind
		fires.append(f)
		var fv := FireView.new()
		fv.setup(f.pos, f.kind, Vector2(map.fires[i].facing))
		world.add_child(fv)
		fire_views.append(fv)
	for i in map.cats.size():
		var c: Dictionary = map.cats[i]
		var perch := Vector3(c.pos.x, 3.95, c.pos.y) + Vector3(c.facing.x, 0, c.facing.y) * 2.35
		var spr := Low.billboard(world, "cat", Low.ORANGE, perch, 1.5 / 16.0)
		spr.visible = false
		var icon := Low.billboard(world, "cat_icon", Low.WHITE, Vector3(c.pos.x, 9.0, c.pos.y), 0.15)
		icon.visible = false
		cats.append({"tree": c.pos, "perch": perch, "facing": c.facing, "park": c.park, "waiting": false,
			"rescued": false, "gone": false, "sprite": spr, "icon": icon, "meow_t": 1.0, "shake": 0.0, "pop": 0.0})
	for h in map.hydrants:
		hydrant_cd.append(0.0)

	arc = WaterArc.new()
	world.add_child(arc)
	cars = Cars.new()
	world.add_child(cars)
	cars.setup(map)
	_build_markers()

	view = Sprite2D.new()
	view.centered = false
	view.texture = vp.get_texture()
	add_child(view)
	hud = Hud.new()
	hud.level = self
	add_child(hud)
	loops = Loops.new()
	add_child(loops)


func _build_markers() -> void:
	ground_arrow = Node3D.new()
	world.add_child(ground_arrow)
	var head := Low.prism(ground_arrow, Vector3(1.8, 1.6, 0.2), Low.YELLOW, Vector3(0, 0, -0.6))
	head.rotation.x = -PI / 2.0
	head.material_override = Low.mat(Low.YELLOW, true)
	var shaft := Low.box(ground_arrow, Vector3(0.7, 0.2, 1.2), Low.YELLOW, Vector3(0, 0, 0.6), true)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	head.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	ground_arrow.visible = false
	home_marker = Node3D.new()
	world.add_child(home_marker)
	var cone := Low.cyl(home_marker, 0.0, 1.6, 2.2, Low.YELLOW, Vector3(0, 0, 0), 8)
	cone.rotation.x = PI
	cone.material_override = Low.mat(Low.YELLOW, true)
	var stem := Low.box(home_marker, Vector3(1.1, 2.4, 1.1), Low.YELLOW, Vector3(0, 2.2, 0), true)
	stem.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var bay: Vector2 = map.station.bay
	home_marker.position = Vector3(bay.x, 12.0, bay.y - 6.0)
	home_marker.visible = false


func _start_state() -> void:
	order = map.fire_order()
	for k in CAT_AFTER.size():
		if k >= cats.size() or CAT_AFTER[k] >= order.size():
			break
		var fire_pos: Vector2 = fires[order[CAT_AFTER[k]]].pos
		var best := -1
		var best_d := INF
		for c in cats.size():
			if cat_after.values().has(c):
				continue
			var d := fire_pos.distance_to(cats[c].tree)
			if d < best_d:
				best_d = d
				best = c
		cat_after[CAT_AFTER[k]] = best
	truck.place(map.station.bay, 0.0)


## Demo/test presets: "cat" = parked under the first stuck cat,
## "home" = everything done, driving home at sunset.
func apply_preset(preset: String) -> void:
	match preset:
		"cat":
			var upto: int = CAT_AFTER[0]
			for k in upto + 1:
				_force_out(order[k])
			order_i = upto
			var c: int = cat_after[upto]
			cats[c].waiting = true
			var park: Vector2i = cats[c].park
			truck.place(map.cell_center(park), _road_yaw(park, TruckModel.fwd_of(0.0)))
			_left_station_silently()
			time = 70.0
		"home":
			for k in order.size():
				_force_out(order[k])
			order_i = order.size() - 1
			for c in cats.size():
				cats[c].rescued = true
				cats_saved += 1
			var start := Vector2i(map.station.door_cell.x - 5, map.station.door_cell.y)
			truck.place(map.cell_center(start), TruckModel.yaw_of(Vector2.RIGHT))
			_left_station_silently()
			time = 300.0
			go_home()
			sunset = 1.0


func _force_out(i: int) -> void:
	fires[i].activate()
	fires[i].out = true
	fires[i].size = 0
	stars += Rules.STARS_PER_FIRE
	shown_stars = stars


func _left_station_silently() -> void:
	left_station = true
	inside_station = false
	door_open = 0.0


func _road_yaw(cell: Vector2i, prefer: Vector2) -> float:
	var best := prefer
	var best_dot := -INF
	for d in map.road_dirs(cell):
		if Vector2(d).dot(prefer) > best_dot:
			best_dot = Vector2(d).dot(prefer)
			best = Vector2(d)
	return TruckModel.yaw_of(best)


# ================================================================ frame

func step(dt: float) -> void:
	if _pause_input():
		hud.paused = true
		return
	hud.paused = false
	time += dt
	_drive(dt)
	_siren(dt)
	_hose(dt)
	_update_fires(dt)
	_update_cats(dt)
	_hydrants(dt)
	_station(dt)
	_end_check(dt)
	cars.step(dt, truck.pos, siren_t > 0.0)
	_camera(dt)
	_update_views(dt)


## Pause belongs to the driver only. Returns true while paused.
func _pause_input() -> bool:
	if next_screen != "":
		return true
	if Players.just_pressed(DRIVER, "start"):
		paused = not paused
		Sfx.play("select")
		if paused:
			loops.stop_all()
		return paused
	if paused:
		if Players.just_pressed(DRIVER, "a"):
			paused = false
		elif Players.just_pressed(DRIVER, "b"):
			_leave("join")
	return paused


func _leave(screen: String) -> void:
	loops.stop_all()
	next_screen = screen
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(screen)


# ---------------------------------------------------------------- driver

func _drive(dt: float) -> void:
	var mv := Players.move(DRIVER)
	var locked: bool = state == State.PARKED or (not rescue.is_empty() and rescue.t < RESCUE_DOWN)
	if locked:
		mv = Vector2.ZERO
	var desired := TruckModel.fwd_of(cam_yaw) * -mv.y + TruckModel.right_of(cam_yaw) * mv.x
	var extra := cars.solids()
	if door_open < 0.5 and not inside_station and state == State.RUN:
		var dx: Vector2 = map.station.door_x
		extra.append({"kind": "box", "rect": Rect2(dx.x, map.station.rect.position.y, dx.y - dx.x, 1.6), "tag": "door"})
	var ev := truck.step(dt, desired, map, extra)
	if ev.bump != "":
		_on_bump(ev.bump)
	if ev.unstuck:
		Sfx.play("whoosh")
		_puffs(Vector3(truck.pos.x, 0.3, truck.pos.y), Low.WHITE, 8, 2.0)
	# Homeward: a gentle funnel lines the truck up with the station door.
	if state == State.HOMEWARD and truck.speed > 0.3:
		var door_c: float = (map.station.door_x.x + map.station.door_x.y) / 2.0
		var dz: float = truck.pos.y - map.station.rect.position.y
		if dz > -9.0 and dz < 3.0 and absf(truck.pos.x - door_c) < 7.0 and truck.fwd().y > 0.4:
			truck.pos.x = move_toward(truck.pos.x, door_c, dt * 2.5)
			truck.yaw = lerp_angle(truck.yaw, PI, 1.0 - exp(-dt * 2.0))
	if Players.just_pressed(DRIVER, "a") and state != State.PARKED:
		horn()


func horn() -> void:
	horn_count += 1
	answered[DRIVER] = time
	Sfx.play("horn")
	_wave_folk(22.0)


func _on_bump(tag: String) -> void:
	Sfx.play("boing", rng.randf_range(0.9, 1.15))
	var at := truck.pos + truck.fwd() * 2.0 * signf(-truck.speed if truck.speed != 0.0 else 1.0)
	if tag == "tree":
		for k in 3:
			_add_fx(Low.sphere(world, 0.22, Low.LIME if k % 2 == 0 else Low.GREEN, Vector3.ZERO, 5, 3),
				Vector3(at.x + rng.randf_range(-1, 1), 3.6, at.y + rng.randf_range(-1, 1)),
				Vector3(rng.randf_range(-0.6, 0.6), -0.2, rng.randf_range(-0.6, 0.6)), -1.2, 2.5)
	else:
		_puffs(Vector3(at.x, 0.8, at.y), Low.WHITE, 4, 1.5)


# ---------------------------------------------------------------- siren

func _siren(dt: float) -> void:
	siren_t = maxf(0.0, siren_t - dt)
	siren_cd = maxf(0.0, siren_cd - dt)
	lights_t = maxf(0.0, lights_t - dt)
	if Players.is_seated(SIREN) and Players.just_pressed(SIREN, "any"):
		siren_press()


## The siren seat's any-button: siren + lights, cars pull over, the dog
## barks along; during the cooldown a bark and a light flash instead; and
## when the truck is parked by a stuck cat, the ladder goes up.
func siren_press() -> void:
	answered[SIREN] = time
	if siren_cd <= 0.0:
		siren_count += 1
		siren_t = Rules.SIREN_SECONDS
		siren_cd = Rules.SIREN_COOLDOWN
		Sfx.play("siren", 1.0, -3.0)
		_wave_folk(30.0)
	else:
		bark_count += 1
		lights_t = 0.5
		tview.dog_hop = 0.3
		Sfx.play("bark", rng.randf_range(0.95, 1.1))
	if rescue.is_empty():
		var c := _cat_in_reach()
		if c != -1:
			start_rescue(c)


func _wave_folk(radius: float) -> void:
	for f in town.folk:
		if f.pos.distance_to(truck.pos) < radius:
			f.hop = 0.6
	for t in thankers:
		if Vector2(t.node.position.x, t.node.position.z).distance_to(truck.pos) < radius:
			t.hop = 0.6


# ---------------------------------------------------------------- hose

func _hose(dt: float) -> void:
	_giggle_cd = maxf(0.0, _giggle_cd - dt)
	super_t = maxf(0.0, super_t - dt)
	var was := spraying
	spraying = false
	spray_fire = -1
	var live := Rules.hose_live(truck.speed) and state != State.PARKED
	var cone := Rules.SUPER_CONE if super_t > 0.0 else Rules.AIM_CONE
	if Players.is_seated(HOSE):
		var d := Players.dir4(HOSE)
		if d != Vector2i.ZERO:
			aim_dir = d
		if Players.just_pressed(HOSE, "a"):
			answered[HOSE] = time
			if not live:
				Sfx.play("drip")
				var tip := tview.nozzle_tip_global()
				_puffs(tip, Low.CYAN, 3, 0.6)
		if Players.pressed(HOSE, "a") and live:
			spraying = true
			var aim_w := Rules.screen_to_world(aim_dir, cam_yaw)
			spray_fire = Rules.pick_fire(truck.pos, aim_w, fires, cone)
			if spray_fire == -1:
				spray_point = truck.pos + aim_w * Rules.HOSE_RANGE * 0.7
				_fun_targets(spray_point)
	elif live and state == State.RUN:
		spray_fire = Rules.nearest_fire(truck.pos, fires)
		spraying = spray_fire != -1
	if spray_fire != -1:
		spray_point = fires[spray_fire].pos
	if spraying and not was:
		Sfx.play("spray_start", 1.0, -4.0)


## Water on something that is not a fire: a giggle and a sparkle.
func _fun_targets(p: Vector2) -> void:
	if _giggle_cd > 0.0:
		return
	var hit := false
	for f in town.folk:
		if f.pos.distance_to(p) < 2.2:
			f.hop = 0.6
			hit = true
	for c in cars.cars:
		if c.pos.distance_to(p) < 2.6:
			hit = true
	if map.station.rect.grow(1.0).has_point(p):
		hit = true
	for c in cats:
		if c.waiting and c.tree.distance_to(p) < 3.0:
			c.shake = 0.6
			Sfx.play("meow", 1.2)
			hit = true
	if hit:
		giggles += 1
		_giggle_cd = GIGGLE_EVERY
		Sfx.play("giggle", rng.randf_range(0.95, 1.1))
		_puffs(Vector3(p.x, 1.5, p.y), Low.YELLOW, 5, 2.0)


# ---------------------------------------------------------------- fires

func _update_fires(dt: float) -> void:
	var rate := Rules.SUPER_RATE if super_t > 0.0 else 1.0
	for i in fires.size():
		var ev: String = fires[i].step(dt, rate if i == spray_fire else 0.0)
		match ev:
			"shrink":
				fire_views[i].puff()
				Sfx.play("hiss_out", 1.2, -4.0)
			"out":
				_fire_out(i)
	if state != State.RUN:
		return
	var current_done: bool = order_i < 0 or not fires[order[order_i]].lit()
	if current_done and not _cat_waiting() and rescue.is_empty() and order_i + 1 < order.size():
		next_fire_t -= dt
		if next_fire_t <= 0.0:
			order_i += 1
			fires[order[order_i]].activate()
			next_fire_t = Rules.NEXT_FIRE_DELAY
			Sfx.play("fire_start")


func _fire_out(i: int) -> void:
	fire_views[i].puff()
	Sfx.play("hiss_out")
	stars += Rules.STARS_PER_FIRE
	var f = fires[i]
	var from := Vector3(f.pos.x, 2.0, f.pos.y)
	for k in Rules.STARS_PER_FIRE:
		var s := Low.billboard(world, "star", Low.YELLOW, from, 0.1, Vector2i(8, 8))
		flyers.append({"node": s, "from": from + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)), "t": -0.25 * k})
	# A thank-you: someone pops out of the house and waves.
	var facing: Vector2 = Vector2(map.fires[i].facing)
	var at: Vector2 = f.pos + facing * 1.6 + Vector2(-facing.y, facing.x) * 1.2
	var who: String = Game.roster[(i + 2) % Game.roster.size()] if not Game.roster.is_empty() else "penguin"
	var spr := Low.billboard(world, who, Low.WHITE, Vector3(at.x, 0.6, at.y), 1.2 / 16.0)
	thankers.append({"node": spr, "base": 0.6, "hop": 1.2, "t": 0.0})
	Sfx.play("thanks")
	var pos_in_order := order.find(i)
	if cat_after.has(pos_in_order) and state == State.RUN:
		var c: int = cat_after[pos_in_order]
		cats[c].waiting = true
		cats[c].meow_t = 0.8


# ---------------------------------------------------------------- cats

func _cat_waiting() -> bool:
	for c in cats:
		if c.waiting:
			return true
	return false


func _cat_in_reach() -> int:
	for i in cats.size():
		if cats[i].waiting and Rules.ladder_ok(truck.pos, truck.speed, cats[i].tree):
			return i
	return -1


func start_rescue(c: int) -> void:
	cats[c].waiting = false
	var solve := tview.ladder_solve(cats[c].perch)
	rescue = {"cat": c, "t": 0.0, "solve": solve}
	Sfx.play("ladder_up")


func _update_cats(dt: float) -> void:
	for c in cats:
		c.shake = maxf(0.0, c.shake - dt)
		c.pop = maxf(0.0, c.pop - dt)
		if c.waiting:
			c.meow_t -= dt
			if c.meow_t <= 0.0:
				c.meow_t = rng.randf_range(2.5, 4.0)
				var d: float = truck.pos.distance_to(c.tree)
				Sfx.play("meow", rng.randf_range(0.95, 1.1), clampf(-2.0 - d * 0.25, -22.0, -2.0))
	# Auto ladder when nobody is on the siren seat.
	if rescue.is_empty() and not Players.is_seated(SIREN) and _cat_in_reach() != -1:
		parked_t += dt
		if parked_t >= Rules.AUTO_LADDER_PARKED:
			parked_t = 0.0
			start_rescue(_cat_in_reach())
	else:
		parked_t = 0.0
	if rescue.is_empty():
		return
	var before: float = rescue.t
	rescue.t += dt
	if before < RESCUE_DOWN and rescue.t >= RESCUE_DOWN:
		var c: int = rescue.cat
		cats[c].rescued = true
		cats[c].pop = 0.8
		cats_saved += 1
		Sfx.play("badge")
		Sfx.play("purr", 1.0, -4.0)
		Sfx.play("ladder_down", 1.0, -3.0)
	if rescue.t >= RESCUE_END:
		rescue = {}


# ---------------------------------------------------------------- hydrants

func _hydrants(dt: float) -> void:
	for i in hydrant_cd.size():
		hydrant_cd[i] = maxf(0.0, hydrant_cd[i] - dt)
		var hp: Vector2 = map.hydrants[i].pos
		if hydrant_cd[i] <= 0.0 and truck.pos.distance_to(hp) < Rules.HYDRANT_RADIUS + 1.1:
			hydrant_cd[i] = Rules.HYDRANT_COOLDOWN
			super_t = Rules.SUPER_SECONDS
			super_count += 1
			Sfx.play("super_spray")
			_puffs(Vector3(hp.x, 1.2, hp.y), Low.CYAN, 10, 3.5)


# ---------------------------------------------------------------- station / end

func _station(_dt: float) -> void:
	var inside: bool = map.station.rect.has_point(truck.pos)
	inside_station = inside
	if not left_station and not inside:
		left_station = true
		if not Players.is_seated(SIREN):
			siren_press()


func _end_check(dt: float) -> void:
	match state:
		State.RUN:
			var fires_left := 0
			for f in fires:
				if not f.out:
					fires_left += 1
			var cats_left := 0
			for c in cats:
				if not c.rescued:
					cats_left += 1
			if not rescue.is_empty():
				cats_left = maxi(cats_left, 1)
			if Rules.run_over(time, fires_left, cats_left, run_len):
				go_home()
		State.HOMEWARD:
			if map.station.bay_rect.has_point(truck.pos) and absf(truck.speed) < Rules.PARK_SPEED:
				state = State.PARKED
				park_t = 0.0
				Sfx.play("ready")
		State.PARKED:
			park_t += dt
			if park_t >= Rules.PARTY_DELAY:
				finish()


## Time to go home: leftover fires fizzle out on their own, stuck cats hop
## down by themselves, the sky turns to sunset and the station opens.
func go_home() -> void:
	if state != State.RUN:
		return
	state = State.HOMEWARD
	for i in fires.size():
		if fires[i].lit():
			fires[i].fizzle()
			fire_views[i].puff()
	for c in cats:
		if c.waiting:
			c.waiting = false
			c.gone = true
	Sfx.play("ready")


func finish() -> void:
	Game.stars = stars
	var rescued := 0
	for c in cats:
		if c.rescued:
			rescued += 1
	Game.cats = rescued
	Game.run_seconds = time
	_leave("party")


# ================================================================ camera + views

func _camera(dt: float) -> void:
	cam_yaw = lerp_angle(cam_yaw, truck.yaw, 1.0 - exp(-dt * 2.2))
	var focus := truck.pos + truck.fwd() * 2.5
	var dist := CAM_DIST
	if spraying:
		focus = truck.pos.lerp(spray_point, 0.45)
		dist = CAM_DIST_SPRAY
	elif not rescue.is_empty():
		focus = truck.pos.lerp(cats[rescue.cat].tree, 0.4)
		dist = CAM_DIST_SPRAY
	var k := 1.0 - exp(-dt * 3.0)
	cam_focus = cam_focus.lerp(focus, k)
	cam_dist = lerpf(cam_dist, dist, 1.0 - exp(-dt * 1.5))
	var f3 := Vector3(cam_focus.x, 0.8, cam_focus.y)
	var back := -TruckModel.fwd_of(cam_yaw)
	var pos := f3 + Vector3(back.x, 0, back.y) * cos(CAM_PITCH) * cam_dist + Vector3.UP * sin(CAM_PITCH) * cam_dist
	cam.look_at_from_position(pos, f3, Vector3.UP)


func _update_views(dt: float) -> void:
	# Truck.
	tview.position = Vector3(truck.pos.x, 0, truck.pos.y)
	tview.rotation.y = truck.yaw
	var lights_on := siren_t > 0.0 or lights_t > 0.0
	# Ladder: raise, hold while the cat comes down, lower.
	if not rescue.is_empty():
		# Solved against the truck as it stands now (it may have just been placed).
		if rescue.t < RESCUE_DOWN:
			rescue.solve = tview.ladder_solve(cats[rescue.cat].perch)
		var sv: Dictionary = rescue.solve
		var up := smoothstep(0.0, RESCUE_RAISE, rescue.t) * (1.0 - smoothstep(RESCUE_DOWN, RESCUE_END, rescue.t))
		tview.ladder_turn = sv.turn if up > 0.02 else 0.0
		tview.ladder_raise = sv.raise * up
		tview.ladder_ext = sv.ext * up
	else:
		tview.ladder_raise = 0.0
		tview.ladder_ext = 0.0
		tview.ladder_turn = 0.0
	tview.update(dt, truck.speed, truck.wobble, truck.lift, lights_on, time)
	# Hose.
	var target3 := Vector3(spray_point.x, 1.2, spray_point.y)
	if spray_fire != -1:
		target3.y = fire_views[spray_fire].base_y + 0.8
		tview.aim_nozzle(target3)
	elif Players.is_seated(HOSE):
		var aw := Rules.screen_to_world(aim_dir, cam_yaw)
		tview.aim_nozzle(Vector3(truck.pos.x + aw.x * 5.0, 1.0, truck.pos.y + aw.y * 5.0))
	arc.update(tview.nozzle_tip_global(), target3, cam.global_position, spraying, super_t > 0.0, time)
	# Fires.
	var obj := objective()
	for i in fire_views.size():
		fire_views[i].update(dt, fires[i], obj.get("fire", -1) == i, time, cam.global_position)
	# Cats.
	var riding := 0
	for i in cats.size():
		var c: Dictionary = cats[i]
		var spr: AnimatedSprite3D = c.sprite
		c.icon.visible = c.waiting
		c.icon.position.y = 9.0 + sin(time * 3.0 + i) * 0.4
		spr.visible = c.waiting or c.rescued or (not rescue.is_empty() and rescue.cat == i)
		if not rescue.is_empty() and rescue.cat == i:
			spr.position = _rescue_cat_pos(c)
		elif c.rescued:
			var slot := Vector3(0.15 + 0.35 * riding, 2.2, 0.9 + 0.3 * riding)
			spr.position = tview.to_global(slot)
			riding += 1
		elif c.waiting:
			var sh: float = sin(time * 40.0) * 0.12 if c.shake > 0.0 else 0.0
			spr.position = c.perch + Vector3(sh, absf(sin(time * 2.0)) * 0.08, 0)
		spr.frame = 1 if (c.waiting and fmod(c.meow_t, 3.0) > 2.5) else 0
	# Markers.
	_update_markers(obj)
	# Station: roof hidden while the truck is inside, the door slides.
	var want_open := inside_station or not left_station or state != State.RUN
	door_open = move_toward(door_open, 1.0 if want_open else 0.0, dt * 1.2)
	if town.has("door"):
		town.door.position.y = door_open * 4.4
		# Also while the chase camera hangs over the station, so it never blocks the view.
		var cam_ground := Vector2(cam.global_position.x, cam.global_position.z)
		var hide: bool = inside_station or map.station.rect.grow(3.0).has_point(cam_ground)
		town.roof.visible = not hide
		town.door.visible = not hide or door_open < 0.5
	# Sunset.
	if state != State.RUN:
		sunset = minf(1.0, sunset + dt / 3.0)
	var sky := SKY_DAY.lerp(SKY_SUNSET, sunset)
	env.background_color = sky
	env.fog_light_color = sky
	env.ambient_light_color = Color("#fff4e8").lerp(Color("#f0b890"), sunset)
	sun.light_color = Color.WHITE.lerp(Color("#ffb070"), sunset)
	# Folk, thankers, ducks.
	for f in town.folk:
		f.hop = maxf(0.0, f.hop - dt)
		f.node.position.y = f.base_y + absf(sin(f.hop * 10.0)) * 0.5 * clampf(f.hop / 0.6, 0.0, 1.0)
	for t in thankers:
		t.t += dt
		t.hop = maxf(0.0, t.hop - dt)
		if fmod(t.t, 2.5) < dt:
			t.hop = maxf(t.hop, 0.5)
		t.node.position.y = t.base + absf(sin(t.hop * 11.0)) * 0.6 * clampf(t.hop / 0.5, 0.0, 1.0)
	for i in town.ducks.size():
		var dk: Node3D = town.ducks[i]
		dk.position.x += sin(time * 0.3 + i) * dt * 0.8
		dk.position.y = -0.55 + sin(time * 2.0 + i) * 0.05
		dk.rotation.y = PI / 2.0 if cos(time * 0.3 + i) > 0.0 else -PI / 2.0
	# Stars flying into the bucket.
	for i in range(flyers.size() - 1, -1, -1):
		var fl: Dictionary = flyers[i]
		fl.t += dt
		var u := clampf(fl.t / 0.9, 0.0, 1.0)
		var to := tview.global_position + Vector3(0, 2.6, 0)
		fl.node.position = fl.from.lerp(to, u) + Vector3.UP * sin(u * PI) * 4.0
		fl.node.visible = fl.t > 0.0
		if u >= 1.0:
			fl.node.queue_free()
			flyers.remove_at(i)
			shown_stars = mini(shown_stars + 1, stars)
			bucket_bounce = 0.15
			Sfx.play("star", 1.0 + 0.05 * (shown_stars % 6), -3.0)
	if flyers.is_empty():
		shown_stars = stars
	bucket_bounce = maxf(0.0, bucket_bounce - dt)
	_update_fx(dt)
	# Sound loops.
	if not Sfx.muted:
		var sp := absf(truck.speed) / TruckModel.MAX_SPEED
		loops.set_loop("engine_loop", true, -14.0 + sp * 5.0, 0.7 + sp * 0.8)
		loops.set_loop("spray_loop", spraying, -6.0 if super_t <= 0.0 else -2.0, 1.0 if super_t <= 0.0 else 1.15)
		var nearest := INF
		for f in fires:
			if f.lit():
				nearest = minf(nearest, truck.pos.distance_to(f.pos))
		loops.set_loop("fire_crackle_loop", nearest < 45.0, clampf(-4.0 - nearest * 0.45, -26.0, -4.0))


func _rescue_cat_pos(c: Dictionary) -> Vector3:
	var t: float = rescue.t
	if t < RESCUE_RAISE:
		return c.perch
	var tip := tview.ladder_tip_global() + Vector3(0, 0.5, 0)
	var base := tview.ladder_base_global() + Vector3(0, 0.5, 0)
	if t < RESCUE_HOP:
		var u := (t - RESCUE_RAISE) / (RESCUE_HOP - RESCUE_RAISE)
		return c.perch.lerp(tip, u) + Vector3.UP * sin(u * PI) * 0.8
	if t < RESCUE_DOWN:
		var u2 := (t - RESCUE_HOP) / (RESCUE_DOWN - RESCUE_HOP)
		return tip.lerp(base, u2)
	return tview.to_global(Vector3(0.15, 2.2, 0.9))


func _update_markers(obj: Dictionary) -> void:
	home_marker.visible = state != State.RUN
	home_marker.position.y = 13.0 + sin(time * 3.0) * 0.8
	if obj.is_empty():
		ground_arrow.visible = false
		return
	var to: Vector2 = obj.pos - truck.pos
	ground_arrow.visible = to.length() > 9.0
	if ground_arrow.visible:
		var d := to.normalized()
		ground_arrow.position = Vector3(truck.pos.x + d.x * 4.6, 0.25, truck.pos.y + d.y * 4.6)
		ground_arrow.rotation.y = TruckModel.yaw_of(d)
		var s := 1.0 + 0.12 * sin(time * 8.0)
		ground_arrow.scale = Vector3(s, 1, s)


## The current objective: {kind, pos (ground), pos3, icon, fire (index)} or {}.
func objective() -> Dictionary:
	if state != State.RUN:
		var bay: Vector2 = map.station.bay
		return {"kind": "home", "pos": bay, "pos3": Vector3(bay.x, 3.0, bay.y), "icon": "home_icon"}
	for i in cats.size():
		if cats[i].waiting:
			return {"kind": "cat", "pos": cats[i].tree, "pos3": cats[i].perch, "icon": "cat_icon", "cat": i}
	if order_i >= 0 and fires[order[order_i]].lit():
		var fi := order[order_i]
		var p: Vector2 = fires[fi].pos
		return {"kind": "fire", "pos": p, "pos3": Vector3(p.x, 2.0, p.y), "icon": "flame_icon", "fire": fi}
	return {}


## Where the objective is on screen (for the HUD edge arrow).
func objective_screen() -> Dictionary:
	var obj := objective()
	if obj.is_empty() or cam == null or not cam.is_inside_tree():
		return {}
	var p3: Vector3 = obj.pos3
	var behind := cam.is_position_behind(p3)
	var sp := cam.unproject_position(p3)
	if behind:
		sp = Vector2(W, H) - sp
		sp.y = H * 2.0
	var on := not behind and sp.x > 12 and sp.x < W - 12 and sp.y > 30 and sp.y < H - 10
	return {"pos": sp, "on_screen": on, "icon": obj.icon}


## For the demo driver: where to park for the current objective, as ground
## waypoints after the road path. {} when there is nothing to do.
func demo_goal() -> Dictionary:
	var obj := objective()
	if obj.is_empty():
		return {}
	var g := _demo_goal(obj)
	# Out of the station first, straight through the door.
	if inside_station and obj.kind != "home":
		var door_c: float = (map.station.door_x.x + map.station.door_x.y) / 2.0
		g.points.push_front(Vector2(door_c, map.station.rect.position.y - 4.0))
	return g


func _demo_goal(obj: Dictionary) -> Dictionary:
	match obj.kind:
		"home":
			var door_c: float = (map.station.door_x.x + map.station.door_x.y) / 2.0
			var front := Vector2(door_c, map.station.rect.position.y - 5.0)
			var road: Vector2i = map.station.door_cell
			var pts := map.path(truck.pos, road)
			pts.append(front)
			pts.append(map.station.bay)
			return {"kind": "home", "points": pts, "look": map.station.bay}
		"cat":
			var c: Dictionary = cats[obj.cat]
			return {"kind": "cat", "points": map.path(truck.pos, c.park), "look": c.tree}
		_:
			var fi: int = obj.fire
			return {"kind": "fire", "points": map.path(truck.pos, map.fires[fi].park), "look": fires[fi].pos}


# ---------------------------------------------------------------- fx

func _add_fx(node: Node3D, at: Vector3, vel: Vector3, grav: float, life: float) -> void:
	node.position = at
	if node.get_parent() == null:
		world.add_child(node)
	fx.append({"node": node, "vel": vel, "grav": grav, "life": life, "max": life})


func _puffs(at: Vector3, c: Color, n: int, speed: float) -> void:
	for k in n:
		var p := Low.sphere(world, 0.25, c, Vector3.ZERO, 5, 3)
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var v := Vector3(rng.randf_range(-1, 1), rng.randf_range(0.5, 1.5), rng.randf_range(-1, 1)).normalized() * speed
		_add_fx(p, at, v, -2.0, 0.8)


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f.life -= dt
		f.vel.y += f.grav * dt
		f.node.position += f.vel * dt
		var s := clampf(f.life / f.max, 0.0, 1.0)
		f.node.scale = Vector3.ONE * (0.4 + 0.6 * s)
		if f.life <= 0.0:
			f.node.queue_free()
			fx.remove_at(i)
