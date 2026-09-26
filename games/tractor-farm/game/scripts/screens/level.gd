extends Node2D
## The farm: one screen, no scrolling. Dad drives the tractor (plough under
## it, planter behind, trailer at the back), the 5-year-old picks seeds, the
## 2-year-old is the rain cloud. Rules live in field_rules.gd; this screen
## turns input into rules calls and rules events into pictures and sounds.
##
## Seats: DRIVER steers (stick/WASD), "a" = horn, or tip at the barn;
## "start" pauses (then "a" resumes, "b" goes back to join).
## GUNNER: a 4-way flick picks a seed (up carrot, right pumpkin, down
## sunflower, left strawberry), "a" toggles the planter.
## HONKER: any press rains under the cloud (cooldown), 5 quick presses make a
## rainbow. Empty seats are played by the game: seeds cycle each row, the
## cloud rains by itself every 4 s (1 seat) or 6 s (2 seats).

const FieldRules := preload("res://scripts/field_rules.gd")
const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Crops := preload("res://scripts/draw/crop_art.gd")
const Farm := preload("res://scripts/draw/farm_art.gd")
const Painter := preload("res://scripts/draw/painter.gd")

const DRIVER := 0
const GUNNER := 1
const HONKER := 2
const Tile := FieldRules.Tile
const T := FieldRules.TILE

const FIELD_POS := Vector2(40, 128)
const FIELD_SIZE := Vector2(FieldRules.W * T, FieldRules.H * T)
const YARD_X := 1064.0
const BARN_POS := Vector2(1172, 262)
const CRATE_X: Array[float] = [1097.0, 1147.0, 1197.0, 1247.0]
const CRATE_Y := 318.0
const TIP_ZONE := Rect2(1070, 336, 206, 170)
const PICKER_POS := Vector2(1172, 614)
const BOUNDS := Rect2(34, 168, 1216, 534)
const YARD_Y := Vector2(360, 500)

const MAX_SPEED := 230.0
const ACCEL := 520.0
const TURN_RATE := 3.4
const HITCH_BACK := 64.0
const PLANTER_GAP := 40.0
const TRAILER_GAP := 62.0
const PLOUGH_BACK := 30.0

const RAIN_SECONDS := 1.2
const RAIN_COOLDOWN := 0.8
const RAINBOW_PRESSES := 5
const RAINBOW_WINDOW := 3.0
const RAINBOW_SECONDS := 4.5
const AUTO_RAIN_1 := 4.0
const AUTO_RAIN_2 := 6.0
const PARK_TIP := 2.0
const VISITOR_TIMES: Array[float] = [70.0, 160.0, 250.0]
const VISITORS: Array[String] = ["bunny", "pig", "hen"]
const ANIMAL_SOUND := {"bunny": "bunny_boing", "pig": "oink", "hen": "cluck", "duck": "quack", "frog": "ribbit"}
const GIANT_STEPS := [[1, 2.2], [2, 3.2], [3, 4.2], [3, 5.2], [3, 6.0]]
const GIANT_EVERY := 1.4

enum State { RUN, FINALE, CARRY, EXIT, DONE }

var field := FieldRules.new()
var state := State.RUN
var paused := false
var t := 0.0

# Tractor chain (ground points, screen space).
var tractor_pos := Vector2(300, FIELD_POS.y + 32)
var heading := 0.0
var speed := 0.0
var facing := 1.0
var planter_pos := Vector2()
var planter_dir := Vector2.RIGHT
var trailer_pos := Vector2()
var trailer_dir := Vector2.RIGHT
var spin := 0.0
var hop := 0.0
var bump := 0.0
var _last_wheel_cells := {}

# Seeds.
var seed_crop := 0
var planter_on := true
var pick_bump := 0.0
var _facing_since := 0.0

# Cloud.
var cloud_ground := Vector2()
var rain_t := 0.0
var rain_cd := 0.0
var _rain_hit := {}
var auto_rain_t := 0.0
var press_times: Array[float] = []
var rainbow_t := 0.0
var cloud_happy := 0.0
var cloud_squash := 0.0
var rain_presses := 0

# Barn.
var park_t := 0.0
var tipping: Array[Dictionary] = []
var display_barn: Array[int] = [0, 0, 0, 0]
var barn_open := 0.0

# Finale.
var giant_crop := 0
var giant_step := -1
var giant_t := 0.0
var giant_pos := Vector2()
var giant_scale := 0.0
var giant_on_trailer := 0.0
var finale_t := 0.0

# Visitors and puddle critters: {node, kind, pos, target, phase, t, cell, dir}.
var animals: Array[Dictionary] = []
var _next_visitor := 0
var _visitor_retry := 0.0

var sun_beam := 0.0
var plough_t := 0.0
var _sound_frame := {}

# Nodes.
var world: Node2D
var field_layer: Node2D
var crop_nodes := {}
var tractor_node: Node2D
var tractor_back: Node2D
var tractor_front: Node2D
var planter_node: Node2D
var trailer_node: Node2D
var cloud_node: Node2D
var cloud_shadow: Node2D
var rain_fx: CPUParticles2D
var dirt_fx: CPUParticles2D
var smoke_fx: CPUParticles2D
var rainbow_node: Node2D
var giant_node: Node2D
var picker: Node2D
var fx_layer: Node2D
var crates_node: Node2D
var barn_node: Node2D
var arrow_node: Node2D
var sun_node: Node2D
var pause_overlay: Node2D
var fx: Array[Dictionary] = []
var sway: ShaderMaterial
var loops := {}

var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 7
	field.end_seconds = Game.run_limit
	_build()
	var h := Vector2.from_angle(heading)
	planter_pos = tractor_pos - h * (HITCH_BACK + PLANTER_GAP)
	trailer_pos = planter_pos - h * (34.0 + TRAILER_GAP)
	cloud_ground = planter_pos
	if not Players.is_seated(GUNNER):
		planter_on = true
	if Game.level_preset == "finale":
		Game.level_preset = ""
		_preset_finale()
	Sfx.music("music_farm")


# ================================================================= build

func _build() -> void:
	sway = ShaderMaterial.new()
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
// Wind sway for grown plants: vertices bend by height above the soil
// (the node origin), phase-shifted by the plant's position in the field.
uniform float strength = 0.07;
void vertex() {
	float wx = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).x;
	float h = max(-VERTEX.y, 0.0);
	VERTEX.x += sin(TIME * 1.7 + wx * 0.011) * h * strength;
}
"""
	sway.shader = sh

	var backdrop := Painter.new(_draw_backdrop)
	backdrop.z_index = -20
	add_child(backdrop)
	sun_node = Painter.new(func(ci): Farm.sun(ci, 30, t, sun_beam))
	sun_node.position = Vector2(64, 50)
	sun_node.z_index = -19
	add_child(sun_node)
	for tr in [[Vector2(250, 118), 70.0], [Vector2(470, 112), 58.0], [Vector2(1010, 118), 66.0], [Vector2(150, 112), 48.0]]:
		var tn := Painter.new(func(ci): Farm.tree(ci, tr[1], t))
		tn.position = tr[0]
		tn.z_index = -18
		add_child(tn)
	var pond := Painter.new(func(ci): Farm.pond(ci, 70, 13, t))
	pond.position = Vector2(760, 110)
	pond.z_index = -18
	add_child(pond)

	field_layer = Painter.new(_draw_field)
	field_layer.position = FIELD_POS
	field_layer.z_index = -10
	add_child(field_layer)

	cloud_shadow = Painter.new(_draw_cloud_shadow)
	cloud_shadow.z_index = -9
	add_child(cloud_shadow)

	world = Node2D.new()
	world.y_sort_enabled = true
	add_child(world)

	barn_node = Painter.new(func(ci): Farm.barn(ci, barn_open))
	barn_node.position = BARN_POS
	world.add_child(barn_node)
	crates_node = Painter.new(_draw_crates)
	crates_node.position = Vector2(0, CRATE_Y)
	world.add_child(crates_node)

	trailer_node = Painter.new(func(ci): Farm.trailer(ci, field.trailer, spin))
	world.add_child(trailer_node)
	if Players.is_seated(GUNNER):
		var r := Game.rider_sprite(Players.riders[GUNNER])
		r.position = Vector2(-30, -64)
		trailer_node.add_child(r)
	planter_node = Painter.new(func(ci): Farm.planter(ci, seed_crop, planter_on, Players.SEAT_COLORS[GUNNER], t))
	world.add_child(planter_node)
	tractor_node = Node2D.new()
	world.add_child(tractor_node)
	tractor_back = Painter.new(func(ci): Farm.tractor(ci, spin))
	tractor_node.add_child(tractor_back)
	var dr := Game.rider_sprite(Players.riders[DRIVER] if Players.riders[DRIVER] != "" else "penguin")
	dr.position = Farm.TRACTOR_SEAT
	tractor_node.add_child(dr)
	tractor_front = Painter.new(func(ci): Farm.tractor_front(ci, spin))
	tractor_node.add_child(tractor_front)
	smoke_fx = _particles(_puff_texture(), 10, 1.2)
	smoke_fx.position = Vector2(30, -86)
	smoke_fx.direction = Vector2(-0.3, -1)
	smoke_fx.spread = 18.0
	smoke_fx.initial_velocity_min = 30.0
	smoke_fx.initial_velocity_max = 50.0
	smoke_fx.scale_amount_min = 0.6
	smoke_fx.scale_amount_max = 1.2
	smoke_fx.color = Color(1, 1, 1, 0.7)
	smoke_fx.gravity = Vector2(0, -30)
	smoke_fx.emitting = true
	smoke_fx.local_coords = false
	tractor_node.add_child(smoke_fx)

	var fence_front := Painter.new(func(ci): Farm.fence(ci, Vector2(24, 718), Vector2(1280, 718)))
	fence_front.z_index = 5
	add_child(fence_front)

	dirt_fx = _particles(_dot_texture(P.SOIL.darkened(0.1), 5), 24, 0.5)
	dirt_fx.direction = Vector2(0, -1)
	dirt_fx.spread = 70.0
	dirt_fx.gravity = Vector2(0, 500)
	dirt_fx.initial_velocity_min = 80.0
	dirt_fx.initial_velocity_max = 150.0
	dirt_fx.local_coords = false
	dirt_fx.one_shot = true
	dirt_fx.explosiveness = 0.8
	dirt_fx.z_index = 6
	add_child(dirt_fx)

	fx_layer = Node2D.new()
	fx_layer.z_index = 8
	add_child(fx_layer)

	giant_node = Painter.new(_draw_giant)
	giant_node.z_index = 11
	giant_node.visible = false
	add_child(giant_node)

	rainbow_node = Painter.new(func(ci): Farm.rainbow(ci, 300, 22, clampf(minf(rainbow_t, RAINBOW_SECONDS - rainbow_t) * 2.0, 0.0, 0.85)))
	rainbow_node.position = FIELD_POS + Vector2(FIELD_SIZE.x * 0.5, 440)
	rainbow_node.z_index = 10
	rainbow_node.visible = false
	add_child(rainbow_node)

	rain_fx = _particles(_drop_texture(), 70, 0.4)
	rain_fx.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	rain_fx.emission_rect_extents = Vector2(52, 4)
	rain_fx.direction = Vector2(0, 1)
	rain_fx.spread = 3.0
	rain_fx.initial_velocity_min = 520.0
	rain_fx.initial_velocity_max = 600.0
	rain_fx.local_coords = false
	rain_fx.gravity = Vector2.ZERO
	rain_fx.z_index = 19
	add_child(rain_fx)

	cloud_node = Painter.new(_draw_cloud)
	cloud_node.z_index = 20
	add_child(cloud_node)
	if Players.is_seated(HONKER):
		var hr := Game.rider_sprite(Players.riders[HONKER])
		hr.position = Vector2(0, -52)
		cloud_node.add_child(hr)

	arrow_node = Painter.new(_draw_barn_arrow)
	arrow_node.z_index = 21
	arrow_node.visible = false
	add_child(arrow_node)

	picker = Painter.new(_draw_picker)
	picker.position = PICKER_POS
	picker.z_index = 30
	add_child(picker)

	pause_overlay = Painter.new(_draw_pause)
	pause_overlay.z_index = 100
	pause_overlay.visible = false
	add_child(pause_overlay)

	if not Sfx.muted:
		for n in ["engine_loop", "plough", "rain_loop"]:
			var p := _loop_player(n)
			if p:
				loops[n] = p


func _particles(tex: Texture2D, amount: int, life: float) -> CPUParticles2D:
	var p := CPUParticles2D.new()
	p.texture = tex
	p.amount = amount
	p.lifetime = life
	p.emitting = false
	return p


func _drop_texture() -> Texture2D:
	var img := Image.create(6, 16, false, Image.FORMAT_RGBA8)
	for y in 16:
		for x in 6:
			var w := 1.0 + 2.0 * (y / 15.0)
			var d := absf(x - 2.5)
			if d <= w * 0.5 + 0.3:
				img.set_pixel(x, y, Color(0.72, 0.88, 1.0, 0.35 + 0.6 * y / 15.0))
	return ImageTexture.create_from_image(img)


func _dot_texture(col: Color, r: int) -> Texture2D:
	var n := r * 2 + 1
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var d := Vector2(x - r, y - r).length()
			if d <= r:
				img.set_pixel(x, y, Color(col, clampf(r + 0.5 - d, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


func _puff_texture() -> Texture2D:
	return _dot_texture(Color(0.92, 0.92, 0.95), 9)


func _loop_player(sound: String) -> AudioStreamPlayer:
	var path := "res://audio/%s.wav" % sound
	var s: AudioStream = null
	if OS.has_feature("template"):
		s = load(path) if ResourceLoader.exists(path) else null
	elif FileAccess.file_exists(path):
		s = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if s == null:
		return null
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.volume_db = -60.0
	add_child(p)
	p.play()
	return p


# ================================================================= frame

func _process(delta: float) -> void:
	step(delta)


## One frame of the level (tests call it directly with a fixed dt).
func step(dt: float) -> void:
	if state == State.DONE:
		return
	if _pause_input():
		_redraw()
		return
	t += dt
	_sound_frame.clear()
	match state:
		State.RUN:
			field.tick(dt)
			_drive(dt, Players.move(DRIVER))
			_seeds(dt)
			_driver_buttons(dt)
			_cloud(dt, true)
			_visitors(dt)
			if field.run_over() and tipping.is_empty() and t > 1.0:
				_start_finale()
		State.FINALE, State.CARRY, State.EXIT:
			_finale(dt)
			_cloud(dt, false)
	_events()
	_update_fx(dt)
	_update_animals(dt)
	_update_loops(dt)
	_place()
	_redraw()


# ================================================================= tractor

func _drive(dt: float, stick: Vector2) -> void:
	var target_speed := 0.0
	if stick.length() > 0.2:
		var diff := wrapf(stick.angle() - heading, -PI, PI)
		heading = wrapf(heading + clampf(diff, -TURN_RATE * dt, TURN_RATE * dt), -PI, PI)
		target_speed = MAX_SPEED * minf(stick.length(), 1.0) * lerpf(1.0, 0.3, absf(diff) / PI)
	speed = move_toward(speed, target_speed, ACCEL * dt)
	var h := Vector2.from_angle(heading)
	var np := tractor_pos + h * speed * dt
	var clamped := _clamp_to_farm(np)
	if clamped.distance_to(np) > 0.5 and state == State.RUN:
		# A fence: bounce softly, never stop dead or tip.
		if bump <= 0.0:
			bump = 0.25
			_sound("fence", "crate", 0.8, -10.0)
		speed *= 0.5
	tractor_pos = clamped if state == State.RUN else np
	_follow_chain()
	spin += speed * dt / 30.0
	if absf(h.x) > 0.25:
		var f := signf(h.x)
		if f != facing:
			facing = f
			_on_turned()
	_footprint()


func _clamp_to_farm(p: Vector2) -> Vector2:
	p.x = clampf(p.x, BOUNDS.position.x, BOUNDS.end.x)
	p.y = clampf(p.y, BOUNDS.position.y, BOUNDS.end.y)
	if p.y < YARD_Y.x - 10.0:
		p.x = minf(p.x, YARD_X - 16.0)
	if p.x > YARD_X + 20.0:
		p.y = clampf(p.y, YARD_Y.x, YARD_Y.y)
	return p


func _follow_chain() -> void:
	var h := Vector2.from_angle(heading)
	var hitch := tractor_pos - h * HITCH_BACK
	var d := planter_pos - hitch
	if d.length() < 0.01:
		d = -h
	planter_pos = hitch + d.normalized() * PLANTER_GAP
	planter_dir = (hitch - planter_pos).normalized()
	var rear := planter_pos - planter_dir * 34.0
	var d2 := trailer_pos - rear
	if d2.length() < 0.01:
		d2 = -planter_dir
	trailer_pos = rear + d2.normalized() * TRAILER_GAP
	trailer_dir = (rear - trailer_pos).normalized()


func plough_point() -> Vector2:
	return tractor_pos - Vector2.from_angle(heading) * PLOUGH_BACK


func seed_point() -> Vector2:
	return planter_pos


func _local(p: Vector2) -> Vector2:
	return p - FIELD_POS


## The tractor's footprint mapped to cells: plough, wheels (harvest / wobble)
## and the planter.
func _footprint() -> void:
	var pc := FieldRules.cell_at(_local(plough_point()))
	if field.plough(pc):
		plough_t = 0.35
		dirt_fx.global_position = plough_point()
		dirt_fx.restart()
	var h := Vector2.from_angle(heading)
	var wheels := {}
	for p in [tractor_pos + h * 30.0, tractor_pos, tractor_pos - h * 30.0]:
		var c := FieldRules.cell_at(_local(p))
		if FieldRules.in_bounds(c):
			wheels[c] = true
	for c in wheels:
		if not _last_wheel_cells.has(c):
			field.drive_over(c)
	_last_wheel_cells = wheels
	if planter_on and state == State.RUN:
		field.plant(FieldRules.cell_at(_local(seed_point())), seed_crop)


## The tractor turned round at a headland: with no seed kid, the next seed.
func _on_turned() -> void:
	if t - _facing_since > 1.5 and not Players.is_seated(GUNNER):
		seed_crop = (seed_crop + 1) % FieldRules.CROP_COUNT
		pick_bump = 0.3
	_facing_since = t


func _driver_buttons(dt: float) -> void:
	var in_zone := TIP_ZONE.has_point(tractor_pos) or TIP_ZONE.has_point(trailer_pos)
	if in_zone and not field.trailer.is_empty() and speed < 15.0:
		park_t += dt
	else:
		park_t = 0.0
	if Players.just_pressed(DRIVER, "a"):
		if in_zone and not field.trailer.is_empty():
			tip()
		else:
			horn()
	elif park_t >= PARK_TIP:
		tip()


func horn() -> void:
	Sfx.play("horn")
	bump = 0.2
	smoke_fx.restart()
	cloud_happy = 0.5
	for a in animals:
		if a.pos.distance_to(tractor_pos) < 300.0:
			a.hop = 0.4


## Tip the trailer into the barn crates (the rules move the counts now; the
## crops fly one by one).
func tip() -> void:
	park_t = 0.0
	var crops := field.tip()
	if crops.is_empty():
		return
	Sfx.play("trailer_tip")
	for i in crops.size():
		var c: int = crops[i]
		tipping.append({"crop": c, "delay": 0.08 * i, "t": 0.0,
			"from": trailer_pos + Vector2(0, -40), "to": Vector2(CRATE_X[c], CRATE_Y - 24)})


# ================================================================= seeds

func _seeds(dt: float) -> void:
	pick_bump = maxf(0.0, pick_bump - dt)
	if not Players.is_seated(GUNNER):
		planter_on = true
		return
	var d := Players.dir4_just_pressed(GUNNER)
	if d != Vector2i.ZERO:
		pick_seed(FieldRules.seed_for_dir(d))
	if Players.just_pressed(GUNNER, "a"):
		planter_on = not planter_on
		Sfx.play("select", 1.2 if planter_on else 0.8)


func pick_seed(c: int) -> void:
	if c < 0:
		return
	seed_crop = c
	pick_bump = 0.3
	Sfx.play("seed_pick_%d" % (c + 1))


# ================================================================= cloud

func _cloud(dt: float, can_grow: bool) -> void:
	rain_cd = maxf(0.0, rain_cd - dt)
	cloud_happy = maxf(0.0, cloud_happy - dt)
	cloud_squash = maxf(0.0, cloud_squash - dt)
	var target := planter_pos if state == State.RUN else giant_pos + Vector2(0, 40)
	cloud_ground = cloud_ground.lerp(target, 1.0 - exp(-2.2 * dt))
	cloud_ground.x = clampf(cloud_ground.x, 70.0, 1210.0)
	if rainbow_t > 0.0:
		rainbow_t = maxf(0.0, rainbow_t - dt)
	for i in range(press_times.size() - 1, -1, -1):
		if t - press_times[i] > RAINBOW_WINDOW:
			press_times.remove_at(i)
	if Players.just_pressed(HONKER, "any"):
		cloud_press()
	elif not Players.is_seated(HONKER) and can_grow:
		auto_rain_t += dt
		var every := AUTO_RAIN_1 if Players.seated_count() <= 1 else AUTO_RAIN_2
		if auto_rain_t >= every and field.has_growing_near(cloud_ground - FIELD_POS):
			auto_rain_t = 0.0
			start_rain()
	if rain_t > 0.0:
		rain_t = maxf(0.0, rain_t - dt)
		if can_grow:
			field.rain(cloud_ground - FIELD_POS, _rain_hit)


## The toddler's press: rain (after the cooldown), always a reaction.
func cloud_press() -> void:
	press_times.append(t)
	cloud_squash = 0.25
	if state != State.RUN:
		giant_press()
	if press_times.size() >= RAINBOW_PRESSES and rainbow_t <= 0.0:
		press_times.clear()
		start_rainbow()
	if rain_cd <= 0.0:
		start_rain()
	else:
		cloud_happy = 0.4
		Sfx.play("plant", 1.3 + rng.randf() * 0.3, -4.0)
		_burst(cloud_ground + Vector2(rng.randf_range(-30, 30), -40), P.WATER, 4)


func start_rain() -> void:
	rain_presses += 1
	rain_t = RAIN_SECONDS
	rain_cd = RAIN_COOLDOWN
	_rain_hit = {}
	Sfx.play("rain_start")
	if state == State.RUN:
		field.rain(cloud_ground - FIELD_POS, _rain_hit)


func start_rainbow() -> void:
	rainbow_t = RAINBOW_SECONDS
	cloud_happy = 1.5
	Sfx.play("rainbow")
	for c in field.cells_in(Tile.RIPE):
		_sparkle(FIELD_POS + FieldRules.cell_center(c) + Vector2(0, -10))


func raining() -> bool:
	return rain_t > 0.0


# ================================================================= events

func _events() -> void:
	for e in field.drain_events():
		var c: Vector2i = e.cell
		var at := FIELD_POS + FieldRules.cell_center(c)
		match e.type:
			"plough":
				pass
			"plant":
				_crop_node(c)
				_seed_hop(at, e.crop)
				_sound("plant", "plant", 1.0 + rng.randf() * 0.2, -6.0)
			"grow":
				var n = _crop_node(c)
				n.set_stage(e.stage)
				if e.get("sun", false):
					sun_beam = 1.0
				if e.stage == Tile.RIPE:
					_sound("ripe", "ripe")
					_sparkle(at + Vector2(0, -10))
				else:
					_sound("grow", "grow_%d" % clampi(e.stage - 2, 1, 3), 1.0, -2.0 if not e.get("sun", false) else -10.0)
			"sparkle":
				_sparkle(at + Vector2(0, -12))
			"puddle":
				_maybe_critter(c)
			"wobble":
				if crop_nodes.has(c):
					crop_nodes[c].wobble = 0.45
				hop = 0.2
			"harvest":
				_remove_crop(c)
				_sound("harvest", "harvest_pop")
				_fly(at + Vector2(0, -10), trailer_pos + Vector2(0, -50), e.crop, 0.45)
			"nibble":
				_remove_crop(c)
			"tip":
				pass


func _crop_node(c: Vector2i) -> Node2D:
	if crop_nodes.has(c):
		return crop_nodes[c]
	var n := CropNode.new()
	n.crop = field.crop_of(c)
	n.stage = field.tile(c)
	n.sway = sway
	n.position = FIELD_POS + FieldRules.cell_center(c) + Vector2(0, 18)
	world.add_child(n)
	crop_nodes[c] = n
	n.pop()
	return n


func _remove_crop(c: Vector2i) -> void:
	if crop_nodes.has(c):
		crop_nodes[c].queue_free()
		crop_nodes.erase(c)


## Plays a sound at most once per frame per key (a shower grows many tiles).
func _sound(key: String, sound: String, pitch := 1.0, vol := 0.0) -> void:
	if _sound_frame.has(key):
		return
	_sound_frame[key] = true
	Sfx.play(sound, pitch, vol)


# ================================================================= finale

func _start_finale() -> void:
	state = State.FINALE
	giant_crop = field.most_planted()
	giant_pos = FIELD_POS + Vector2(FIELD_SIZE.x * 0.5, 380)
	giant_step = -1
	giant_t = 0.9
	finale_t = 0.0
	giant_node.visible = true
	speed = 0.0
	Sfx.play("giant_grow")
	for a in animals:
		a.phase = "leave"


func giant_press() -> void:
	if state == State.FINALE and giant_step < GIANT_STEPS.size() - 1 and giant_t < GIANT_EVERY - 0.35:
		giant_t = GIANT_EVERY


func _finale(dt: float) -> void:
	finale_t += dt
	match state:
		State.FINALE:
			_drive(dt, Vector2.ZERO)
			giant_t += dt
			if giant_t >= GIANT_EVERY and giant_step < GIANT_STEPS.size() - 1:
				giant_t = 0.0
				giant_step += 1
				Sfx.play("grow_%d" % mini(3, giant_step + 1), 0.7 + giant_step * 0.08)
				for i in 6:
					_sparkle(giant_pos + Vector2.from_angle(TAU * i / 6.0) * (40.0 + giant_step * 30.0) + Vector2(0, -60))
				if giant_step == GIANT_STEPS.size() - 1:
					Sfx.play("ripe")
					start_rainbow()
			elif giant_step == GIANT_STEPS.size() - 1 and giant_t >= 1.6:
				state = State.CARRY
		State.CARRY:
			var target := giant_pos + Vector2(-90, 60)
			_drive(dt, autopilot(target))
			if tractor_pos.distance_to(target) < 50.0 or finale_t > 30.0:
				state = State.EXIT
				Sfx.play("harvest_pop", 0.7)
		State.EXIT:
			giant_on_trailer = minf(1.0, giant_on_trailer + dt * 1.6)
			_drive(dt, autopilot(Vector2(2000, tractor_pos.y)) if giant_on_trailer >= 1.0 else Vector2.ZERO)
			if trailer_pos.x > 1380.0 or finale_t > 45.0:
				_finish()
	if state != State.EXIT:
		var k: float = GIANT_STEPS[maxi(giant_step, 0)][1] if giant_step >= 0 else 0.6
		giant_scale = lerpf(giant_scale, k, 1.0 - exp(-10.0 * dt))


func _finish() -> void:
	state = State.DONE
	Game.barn = field.barn.duplicate()
	Game.giant_crop = giant_crop
	Game.run_seconds = field.elapsed
	Sfx.play("ready")
	Game.goto.call_deferred("party")


## A stick vector that steers the tractor toward `target` (finale, demo).
func autopilot(target: Vector2) -> Vector2:
	var d := target - tractor_pos
	if d.length() < 8.0:
		return Vector2.ZERO
	return d.normalized() * clampf(d.length() / 60.0, 0.4, 1.0)


func _preset_finale() -> void:
	# The demo/test start: a full, colourful field and a barn at 30.
	for y in FieldRules.H:
		for x in FieldRules.W:
			var c := Vector2i(x, y)
			field.plough(c)
			if (x + y) % 5 != 0:
				field.plant(c, (x / 4) % 4)
				for k in (3 if (x + y) % 3 != 0 else 2):
					field.advance(c)
	field.barn.assign([9, 8, 7, 6])
	display_barn = field.barn.duplicate()
	field.planted[1] += 20
	field.drain_events()
	for i in field.state.size():
		var c := Vector2i(i % FieldRules.W, i / FieldRules.W)
		if field.tile(c) >= Tile.SEEDED:
			var n = _crop_node(c)
			n.set_stage(field.tile(c), false)
	tractor_pos = Vector2(300, 520)
	heading = 0.0
	_follow_chain()


# ================================================================= animals

func _visitors(dt: float) -> void:
	if _next_visitor >= VISITOR_TIMES.size() or field.elapsed < VISITOR_TIMES[_next_visitor]:
		return
	_visitor_retry -= dt
	if _visitor_retry > 0.0:
		return
	var ripe := field.cells_in(Tile.RIPE)
	if ripe.is_empty():
		_visitor_retry = 8.0
		return
	var cell: Vector2i = ripe[rng.randi() % ripe.size()]
	var kind := VISITORS[_next_visitor]
	_next_visitor += 1
	var at := FIELD_POS + FieldRules.cell_center(cell) + Vector2(0, 20)
	var from := Vector2(-40 if at.x < 640 else 1320, at.y)
	_add_animal(kind, from, at, "walk", cell)
	Sfx.play(ANIMAL_SOUND[kind])


func _maybe_critter(c: Vector2i) -> void:
	var n := 0
	for a in animals:
		if a.kind == "duck" or a.kind == "frog":
			n += 1
	if n >= 2 or rng.randf() > 0.45:
		return
	var kind := "duck" if rng.randf() < 0.5 else "frog"
	var at := FIELD_POS + FieldRules.cell_center(c) + Vector2(0, 16)
	_add_animal(kind, at + Vector2(-90, -60), at, "jump", c)
	Sfx.play(ANIMAL_SOUND[kind])


func _add_animal(kind: String, from: Vector2, to: Vector2, phase: String, cell: Vector2i) -> void:
	var node := Painter.new()
	var a := {"node": node, "kind": kind, "pos": from, "start": from, "target": to, "phase": phase,
		"t": 0.0, "cell": cell, "pose": 0, "hop": 0.0, "dir": 1.0 if to.x >= from.x else -1.0}
	node.fn = func(ci): Farm.animal(ci, kind, a.pose)
	world.add_child(node)
	animals.append(a)


func _update_animals(dt: float) -> void:
	for i in range(animals.size() - 1, -1, -1):
		var a: Dictionary = animals[i]
		a.t += dt
		a.hop = maxf(0.0, a.hop - dt)
		var node: Node2D = a.node
		var pose := 0
		match a.phase:
			"walk":
				a.pos = a.pos.move_toward(a.target, 120.0 * dt)
				pose = int(a.t * 7.0) % 2
				if a.pos.distance_to(a.target) < 2.0:
					a.phase = "nibble"
					a.t = 0.0
			"nibble":
				pose = int(a.t * 10.0) % 2
				if a.t > 0.6 and field.tile(a.cell) == Tile.RIPE:
					field.nibble(a.cell)
					Sfx.play("harvest_pop", 1.3, -4.0)
				if a.t > 0.7:
					a.phase = "dance"
					a.t = 0.0
					_heart(a.pos + Vector2(0, -50))
					Sfx.play(ANIMAL_SOUND[a.kind], 1.1)
			"dance":
				pose = int(a.t * 6.0) % 2
				a.dir = 1.0 if int(a.t * 3.0) % 2 == 0 else -1.0
				if a.t > 1.8:
					a.phase = "leave"
					a.t = 0.0
			"jump":
				var k := minf(1.0, a.t / 0.5)
				a.pos = a.start.lerp(a.target, k) + Vector2(0, -sin(k * PI) * 50.0)
				pose = 1
				if k >= 1.0:
					a.phase = "splash"
					a.t = 0.0
					_burst(a.pos, P.WATER, 6)
			"splash":
				pose = int(a.t * 2.5) % 2
				var i2 := FieldRules.idx(a.cell)
				if a.t > 9.0 or (a.t > 3.0 and field.wet[i2] <= 0.0):
					a.phase = "leave"
					a.t = 0.0
			"leave":
				var exit := Vector2(-80 if a.pos.x < 640 else 1360, a.pos.y)
				a.dir = signf(exit.x - a.pos.x)
				a.pos = a.pos.move_toward(exit, 170.0 * dt)
				pose = int(a.t * 8.0) % 2
				if a.pos.distance_to(exit) < 4.0:
					a.phase = "gone"
		if a.phase == "gone":
			node.queue_free()
			animals.remove_at(i)
			continue
		if a.phase == "walk" or a.phase == "nibble":
			a.dir = signf(a.target.x - a.start.x) if a.target.x != a.start.x else 1.0
		a.pose = 1 if a.hop > 0.0 else pose
		node.position = a.pos + Vector2(0, -12.0 if a.hop > 0.2 else 0.0)
		node.scale = Vector2(a.dir * 1.3, 1.3)
		node.queue_redraw()


# ================================================================= fx

## Adds a short-lived effect. `d` is filled in place, so the draw callable
## (a lambda that captured `d`) sees its live time.
func _fx_node(d: Dictionary, fn: Callable, at: Vector2, life: float, vel := Vector2.ZERO, extra := {}) -> void:
	var n := Painter.new(fn)
	n.position = at
	fx_layer.add_child(n)
	d.merge({"node": n, "t": 0.0, "life": life, "vel": vel, "from": at}, true)
	d.merge(extra, true)
	fx.append(d)


func _sparkle(at: Vector2) -> void:
	var d := {}
	_fx_node(d, func(ci): _draw_sparkle(ci, d), at + Vector2(rng.randf_range(-10, 10), rng.randf_range(-10, 6)),
		0.7, Vector2(0, -30))


func _draw_sparkle(ci: CanvasItem, d: Dictionary) -> void:
	var k: float = d.t / d.life
	var r := 12.0 * sin(k * PI)
	S.fill_ink(ci, S.star(Vector2.ZERO, r, r * 0.4, 4, k * 2.0), Color(1, 1, 0.75, 1.0 - k * 0.5), P.INK, 0.0)


func _heart(at: Vector2) -> void:
	var d := {}
	_fx_node(d, func(ci): S.fill_ink(ci, S.heart(Vector2.ZERO, 26), Color(P.STRAWBERRY, 1.0 - d.t / d.life)),
		at, 1.6, Vector2(0, -40))


func _burst(at: Vector2, col: Color, n: int) -> void:
	for i in n:
		var d := {}
		var v := Vector2.from_angle(-PI / 2 + rng.randf_range(-1.2, 1.2)) * rng.randf_range(80, 160)
		_fx_node(d, func(ci): ci.draw_circle(Vector2.ZERO, 5.0 * (1.0 - d.t / d.life), col, true, -1.0, true),
			at, 0.5, v, {"g": 400.0})


func _seed_hop(at: Vector2, crop: int) -> void:
	var d := {}
	_fx_node(d, func(ci): Farm.seed_bag(ci, Vector2.ZERO, 22, crop), planter_pos + Vector2(0, -50), 0.35, Vector2.ZERO,
		{"arc_to": at + Vector2(0, 8), "arc_h": 30.0})


func _fly(from: Vector2, to: Vector2, crop: int, life: float) -> void:
	var d := {}
	_fx_node(d, func(ci): Crops.icon(ci, crop, 30.0), from, life, Vector2.ZERO,
		{"arc_to": to, "arc_h": 90.0, "follow_trailer": true})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var d: Dictionary = fx[i]
		d.t += dt
		var n: Node2D = d.node
		if d.t >= d.life:
			n.queue_free()
			fx.remove_at(i)
			continue
		if d.has("arc_to"):
			var k: float = d.t / d.life
			var to: Vector2 = d.arc_to
			if d.get("follow_trailer", false):
				to = trailer_pos + Vector2(0, -50)
			n.position = d.from.lerp(to, k) + Vector2(0, -sin(k * PI) * d.arc_h)
		else:
			if d.has("g"):
				d.vel.y += d.g * dt
			n.position += d.vel * dt
		n.queue_redraw()
	# Crops flying from the trailer into the crates.
	var done := 0
	for tp in tipping:
		if tp.get("landed", false):
			done += 1
			continue
		tp.delay -= dt
		if tp.delay > 0.0:
			continue
		if not tp.has("node"):
			var c: int = tp.crop
			tp.node = Painter.new(func(ci): Crops.icon(ci, c, 30.0))
			fx_layer.add_child(tp.node)
		tp.t += dt
		var k := minf(1.0, tp.t / 0.5)
		tp.node.position = tp.from.lerp(tp.to, k) + Vector2(0, -sin(k * PI) * 110.0)
		if k >= 1.0 and not tp.get("landed", false):
			tp.landed = true
			tp.node.queue_free()
			display_barn[tp.crop] += 1
			_sound("crate", "crate", 0.9 + 0.05 * (display_barn[tp.crop] % 6), -3.0)
			done += 1
	if done == tipping.size() and done > 0:
		tipping.clear()
	barn_open = move_toward(barn_open, 1.0 if not tipping.is_empty() else 0.0, dt * 3.0)
	sun_beam = maxf(0.0, sun_beam - dt * 1.5)
	hop = maxf(0.0, hop - dt)
	plough_t = maxf(0.0, plough_t - dt)
	bump = maxf(0.0, bump - dt)


func _update_loops(dt: float) -> void:
	if loops.is_empty():
		return
	var eng: AudioStreamPlayer = loops.get("engine_loop")
	if eng:
		eng.volume_db = lerpf(eng.volume_db, -14.0 + 8.0 * speed / MAX_SPEED, 1.0 - exp(-6.0 * dt))
		eng.pitch_scale = 0.85 + 0.45 * speed / MAX_SPEED
	var pl: AudioStreamPlayer = loops.get("plough")
	if pl:
		var on := plough_t > 0.0
		pl.volume_db = lerpf(pl.volume_db, -8.0 if on else -60.0, 1.0 - exp(-8.0 * dt))
	var rn: AudioStreamPlayer = loops.get("rain_loop")
	if rn:
		rn.volume_db = lerpf(rn.volume_db, -6.0 if raining() else -60.0, 1.0 - exp(-10.0 * dt))


# ================================================================= place + draw

func _place() -> void:
	var h := Vector2.from_angle(heading)
	tractor_node.position = tractor_pos + Vector2(0, -absf(sin(hop * 16.0)) * 5.0 if hop > 0.0 else 0.0)
	var sq := 1.0 + sin(bump * 25.0) * 0.06 * (bump / 0.25)
	tractor_node.scale = Vector2(facing * sq, 1.0 / sq)
	tractor_node.rotation = facing * h.y * 0.22
	planter_node.position = planter_pos
	planter_node.scale = Vector2(1.0 if planter_dir.x >= -0.1 else -1.0, 1.0)
	planter_node.rotation = planter_node.scale.x * planter_dir.y * 0.2
	trailer_node.position = trailer_pos
	trailer_node.scale = Vector2(1.0 if trailer_dir.x >= -0.1 else -1.0, 1.0)
	trailer_node.rotation = trailer_node.scale.x * trailer_dir.y * 0.2
	var cy := maxf(cloud_ground.y - 190.0, 84.0) if state == State.RUN else 84.0
	var sq2 := 1.0 + sin(cloud_squash * 30.0) * 0.08 * (cloud_squash / 0.25)
	cloud_node.position = Vector2(cloud_ground.x, cy + sin(t * 2.0) * 4.0)
	cloud_node.scale = Vector2(sq2, 1.0 / sq2)
	rain_fx.global_position = Vector2(cloud_ground.x, cy + 30.0)
	var life := snappedf(maxf(0.1, (cloud_ground.y - cy - 30.0) / 560.0), 0.05)
	if not is_equal_approx(life, rain_fx.lifetime):
		rain_fx.lifetime = life
	rain_fx.emitting = raining()
	cloud_shadow.position = cloud_ground
	rainbow_node.visible = rainbow_t > 0.0
	arrow_node.visible = field.trailer_full() and state == State.RUN
	if giant_node.visible:
		if state == State.EXIT:
			var k := giant_on_trailer
			var onto := trailer_pos + Vector2(0, -60)
			giant_node.position = giant_pos.lerp(onto, k) + Vector2(0, -sin(k * PI) * 160.0)
			giant_node.scale = Vector2.ONE * lerpf(giant_scale, 1.6, k)
		else:
			giant_node.position = giant_pos
			giant_node.scale = Vector2.ONE * giant_scale


func _redraw() -> void:
	for n in [field_layer, cloud_shadow, tractor_back, tractor_front, planter_node, trailer_node, cloud_node,
			rainbow_node, picker, crates_node, barn_node, arrow_node, sun_node, giant_node, pause_overlay]:
		n.queue_redraw()


func _draw_backdrop(ci: CanvasItem) -> void:
	# The sky is the only gradient.
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 110), Vector2(0, 110)]),
		PackedColorArray([P.SKY_TOP, P.SKY_TOP, P.SKY_LOW, P.SKY_LOW]))
	for b in [[Vector2(120, 118), 210.0, 40.0], [Vector2(560, 124), 300.0, 44.0], [Vector2(1000, 120), 260.0, 42.0]]:
		S.oval(ci, b[0], b[1], b[2], P.GRASS_LIGHT, P.INK, 0.0)
	ci.draw_rect(Rect2(0, 104, 1280, 616), P.GRASS)
	# Yard: a trodden patch in front of the barn.
	S.box(ci, Rect2(YARD_X + 10, 300, 204, 214), 30, P.GRASS.lerp(P.BAG, 0.45), P.INK, 0.0)
	for i in 5:
		S.oval(ci, Vector2(YARD_X + 40 + (i * 53) % 170, 330 + i * 38), 7, 3, P.BAG_DARK, P.INK, 0.0)
	for f in [[Vector2(28, 126), Vector2(1280, 126)]]:
		Farm.fence(ci, f[0], f[1])


func _draw_field(ci: CanvasItem) -> void:
	for y in FieldRules.H:
		for x in FieldRules.W:
			var c := Vector2i(x, y)
			var i := FieldRules.idx(c)
			var r := Rect2(x * T, y * T, T, T)
			var s := field.state[i]
			if s == Tile.GRASS:
				ci.draw_rect(r, P.GRASS if (x + y) % 2 == 0 else P.GRASS_DARK.lerp(P.GRASS, 0.55))
				var hsh := (x * 7 + y * 13) % 5
				for k in 2:
					var p := r.position + Vector2(14 + ((hsh + k * 3) % 5) * 8, 18 + k * 26)
					S.path(ci, PackedVector2Array([p + Vector2(-5, 0), p + Vector2(-2, -8), p, p + Vector2(3, -9), p + Vector2(5, 0)]),
						P.GRASS_LIGHT, 2.5)
			else:
				ci.draw_rect(r, P.SOIL)
				for k in 3:
					var yy := r.position.y + 12 + k * 20
					S.line(ci, Vector2(r.position.x + 3, yy), Vector2(r.end.x - 3, yy), P.FURROW, 7.0)
					S.line(ci, Vector2(r.position.x + 3, yy + 5), Vector2(r.end.x - 3, yy + 5), P.SOIL.lightened(0.12), 2.0)
			var w := field.wet[i]
			if w > 0.0:
				var a := clampf(w / 2.0, 0.0, 1.0)
				if s >= Tile.PLOUGHED:
					ci.draw_rect(r, Color(P.SOIL_WET, 0.45 * a))
				var hsh2 := (x * 5 + y * 11) % 7
				if s < Tile.SEEDED and (s == Tile.PLOUGHED or hsh2 % 2 == 0):
					# Puddles vary in size and place, so a shower never lays a neat row.
					var pc := r.get_center() + Vector2(-10 + hsh2 * 3, 2 + (hsh2 % 3) * 6)
					var k := (0.6 + 0.4 * a) * (0.7 + 0.1 * (hsh2 % 4))
					S.oval(ci, pc, 24 * k, 10 * k, Color(P.WATER, 0.9 * a), Color(P.WATER_DEEP, a), 2.0)
					S.oval(ci, pc + Vector2(-8, -2) * k, 6 * k, 2 * k, Color(1, 1, 1, 0.7 * a), P.INK, 0.0)
	# Rain wets the soil under the cloud while it falls.
	if raining() and state == State.RUN:
		ci.draw_circle(cloud_ground - FIELD_POS, FieldRules.RAIN_RADIUS * T, Color(P.WATER_DEEP, 0.18), true, -1.0, true)


func _draw_cloud_shadow(ci: CanvasItem) -> void:
	S.oval(ci, Vector2.ZERO, 70, 20, Color(P.INK, 0.14), P.INK, 0.0)


func _draw_cloud(ci: CanvasItem) -> void:
	var face := Farm.Face.IDLE
	if raining():
		face = Farm.Face.RAIN
	if cloud_happy > 0.0 or rainbow_t > 0.0:
		face = Farm.Face.HAPPY
	var blink := fmod(t, 3.3) < 0.14
	Farm.cloud(ci, face, blink, t, Color(0.93, 0.95, 1.0) if raining() else Color.WHITE)


func _draw_crates(ci: CanvasItem) -> void:
	for c in 4:
		S.xform(ci, Vector2(CRATE_X[c], 0), 0.0, Vector2.ONE)
		Farm.crate(ci, c, display_barn[c])
	S.reset(ci)


func _draw_barn_arrow(ci: CanvasItem) -> void:
	var y := 380.0 + absf(sin(t * 5.0)) * -18.0
	var x := 1172.0
	S.fill_ink(ci, PackedVector2Array([Vector2(x - 14, y - 40), Vector2(x + 14, y - 40), Vector2(x + 14, y - 16),
		Vector2(x + 28, y - 16), Vector2(x, y + 10), Vector2(x - 28, y - 16), Vector2(x - 14, y - 16)]), P.SUNFLOWER, P.INK, 3.0)


func _draw_giant(ci: CanvasItem) -> void:
	if giant_step < 0:
		return
	var st: int = GIANT_STEPS[giant_step][0]
	ci.draw_circle(Vector2(0, -30), 34, Color(1, 1, 0.7, 0.25 + 0.1 * sin(t * 6.0)), true, -1.0, true)
	S.aa = giant_scale < 2.5
	Crops.draw(ci, giant_crop, st)
	S.aa = true
	if st == 3:
		for i in 3:
			var a := t * 2.0 + TAU * i / 3.0
			S.fill_ink(ci, S.star(Vector2(cos(a) * 30, -30 + sin(a) * 26), 5, 2, 4), Color(1, 1, 0.8), P.INK, 0.0)


func _draw_picker(ci: CanvasItem) -> void:
	var col: Color = Players.SEAT_COLORS[GUNNER]
	var seated := Players.is_seated(GUNNER)
	# Plus-shaped board.
	S.box(ci, Rect2(-28, -84, 56, 168), 18, Color(col.darkened(0.45), 0.85), P.INK, 3.0)
	S.box(ci, Rect2(-84, -28, 168, 56), 18, Color(col.darkened(0.45), 0.85), P.INK, 3.0)
	ci.draw_rect(Rect2(-26, -26, 52, 52), Color(col.darkened(0.45), 0.85))
	for c in 4:
		var d := Vector2(FieldRules.dir_for_seed(c)) * 54.0
		var chosen := c == seed_crop
		var k := 1.0 + (pick_bump / 0.3 * 0.25 if chosen else 0.0)
		var r := Rect2(d - Vector2(23, 23) * k, Vector2(46, 46) * k)
		S.box(ci, r, 10, col.lightened(0.35) if chosen else P.CREAM, P.INK, 4.0 if chosen else 2.0)
		Crops.icon(ci, c, 34.0 * k, d)
		if chosen:
			ci.draw_arc(d, 30 * k, 0, TAU, 32, P.WHITE, 3.0, true)
	# Centre: the planter, open (seeds falling) or closed.
	var bag_col := P.CREAM if planter_on else Color(0.6, 0.6, 0.6)
	S.disc(ci, Vector2.ZERO, 22, bag_col)
	Farm.seed_bag(ci, Vector2(0, -2), 26, seed_crop, planter_on)
	if planter_on:
		for i in 3:
			var ph := fmod(t * 1.5 + i / 3.0, 1.0)
			ci.draw_circle(Vector2(-6 + i * 6, 14 + ph * 10), 2.2, Color(P.CROP_COLORS[seed_crop], 1.0 - ph), true, -1.0, true)
	if not seated:
		# Nobody on seeds: the game picks, shown by a turning ring.
		ci.draw_arc(Vector2.ZERO, 26, t * 3.0, t * 3.0 + PI * 1.2, 20, P.WHITE, 3.0, true)


func _draw_pause(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, 1280, 720), Color(P.INK, 0.6))
	S.disc(ci, Vector2(440, 360), 88, P.STRAWBERRY, P.INK, 4.0)
	S.fill_ink(ci, PackedVector2Array([Vector2(392, 360), Vector2(440, 312), Vector2(440, 340), Vector2(484, 340),
		Vector2(484, 380), Vector2(440, 380), Vector2(440, 408)]), P.WHITE, P.INK, 3.0)
	S.disc(ci, Vector2(840, 360), 104, P.LEAF_BRIGHT, P.INK, 4.0)
	S.fill_ink(ci, PackedVector2Array([Vector2(808, 304), Vector2(888, 360), Vector2(808, 416)]), P.WHITE, P.INK, 3.0)


# ================================================================= pause

func _pause_input() -> bool:
	if state != State.RUN:
		return false
	if Players.just_pressed(DRIVER, "start"):
		_set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(DRIVER, "a"):
			_set_paused(false)
		elif Players.just_pressed(DRIVER, "b"):
			_back_to_join()
	return paused


func _set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	Sfx.play("select")
	for n in loops:
		loops[n].stream_paused = on


func _back_to_join() -> void:
	state = State.DONE
	Players.reset()
	Game.goto("join")


# ================================================================= crop node

## One plant, drawn at its soil point. Pops when it grows, wobbles when
## wheels roll over it, sways in the wind once it is big.
class CropNode extends Node2D:
	const CropsArt := preload("res://scripts/draw/crop_art.gd")
	var crop := 0
	var stage := 2
	var wobble := 0.0
	var sway: ShaderMaterial
	var _pop := 1.0

	func set_stage(s: int, animate := true) -> void:
		stage = s
		material = sway if s >= 4 else null
		queue_redraw()
		if animate:
			pop()

	func pop() -> void:
		_pop = 0.0

	func _process(dt: float) -> void:
		wobble = maxf(0.0, wobble - dt)
		rotation = sin(wobble * 40.0) * wobble * 0.6
		if _pop < 1.0:
			_pop = minf(1.0, _pop + dt / 0.4)
			var k := _pop
			var sx := 1.0 + sin(k * PI * 2.5) * 0.35 * (1.0 - k)
			scale = Vector2(sx, 1.0 / sx)
		else:
			scale = Vector2.ONE

	func _draw() -> void:
		CropsArt.draw(self, crop, stage - 2)
