extends Node2D
## The trip: sky, space (with the stage separation halfway), the Moon and the
## landing. The world scrolls down past the rocket, which the Pilot steers in
## the lower part of the screen. The Grabber shoots the claw arm, the Launcher
## fires the booster and owns every stage transition. No game over: asteroids
## are soft, fuel only changes the flame, the landing cannot crash, and the
## trip always ends at the Moon.
##
## All logic lives in step(dt) so tests drive it frame by frame with
## set_process(false) and scripted devices.

const Rules := preload("res://scripts/logic/rules.gd")
const Claw := preload("res://scripts/logic/claw.gd")
const Countdown := preload("res://scripts/logic/countdown.gd")
const Timeline := preload("res://scripts/logic/timeline.gd")
const SkyView := preload("res://scripts/view/sky.gd")
const Crew := preload("res://scripts/view/crew.gd")
const Lights := preload("res://scripts/view/lights.gd")
const BigButton := preload("res://scripts/view/big_button.gd")
const PauseOverlay := preload("res://scripts/view/pause_overlay.gd")

const W := 320
const H := 180
const PILOT := 0                # Players.Seat.DRIVER
const GRABBER := 1              # Players.Seat.GUNNER
const LAUNCHER := 2             # Players.Seat.HONKER

const PILOT_SPEED := 110.0
const X_MIN := 16.0
const X_MAX := 304.0
## The rocket centre stays in the lower third of the screen.
const Y_MIN := 112.0
const Y_MAX := 136.0
const Y_HOME := 128.0
const ROCKET_HIT := Vector2(16, 34)
const STAGE_HIT := Vector2(18, 12)
const ASTEROID_HIT := Vector2(12, 12)
const MAGNET_RADIUS := 48.0
const PICK_RADIUS := 15.0
const BOOST_LANE := 30.0
const SEPARATION_LIGHTS := 3
const AWAIT_SPACE := "space"
const AWAIT_FLAG := "flag"
## The Moon approach takes this share of the moon stage; the landing follows.
const APPROACH_SHARE := 0.6
const GROUND_Y := 156.0          # the Moon's surface
const PAD_DECK := 150.0          # top of the landing pad
const DESCENT := 26.0
const BOUNCE_VY := -72.0
const PAD_SLIDE := 90.0
const FLAG_SECONDS := 4.0

# Sweetie 16.
const C_INK := Color("#1a1c2c")
const C_RED := Color("#b13e53")
const C_ORANGE := Color("#ef7d57")
const C_YELLOW := Color("#ffcd75")
const C_LIME := Color("#a7f070")
const C_GREEN := Color("#38b764")
const C_BLUE := Color("#41a6f6")
const C_CYAN := Color("#73eff7")
const C_WHITE := Color("#f4f4f4")
const C_GREY := Color("#94b0c2")
const C_SLATE := Color("#566c86")
const CONFETTI_TINTS := [C_RED, C_ORANGE, C_YELLOW, C_LIME, C_CYAN, C_WHITE]

enum Stage { SKY, SPACE, MOON, LANDING, LANDED, DONE }

var stage := Stage.SKY
## Seconds into the current stage (sky, space, moon approach).
var stage_t := 0.0
## Seconds since the trip started (never stops: the trip always ends).
var trip_t := 0.0
var paused := false
## "" or the transition the press seat is waited for: AWAIT_SPACE, AWAIT_FLAG.
var awaiting := ""
var await_t := 0.0
## The stage separation countdown (null when not running).
var separation = null
var separated := false

var data := {}
var lengths := {}
var spawns: Array[Dictionary] = []
var spawn_i := 0

var rocket_pos := Vector2(160, 220)
var rocket_vy := 0.0             # landing only
## Rising in from below the screen at the start (just after lift-off).
var entering := true
var _entry_y := 220.0
var knock := 0.0                 # sideways push after a bump
var invuln := 0.0
var wobble_t := 0.0
var tank := 1.0
var fuel_count := 0
var boost_t := 0.0
var boost_cd := 0.0
var scroll := 0.0                # accumulated world scroll, px
var speed := 0.0                 # current scroll speed, px/s
var shake_t := 0.0
var flash_t := 0.0
var sky_level := 0.0

## Landing.
var pad_x := 240.0
var tries := 0
var pad_sliding := false
var landed_t := 0.0
var flags_planted := false
var flag_t := 0.0

var claw := Claw.new()

## Grabbable: {node, kind: "fuel"|"planet"|"balloon", planet, pos, vel, dropped, grabbed, age}
var pickups: Array[Dictionary] = []
## {node, pos, vel, dazed}
var asteroids: Array[Dictionary] = []
## Decoration that scrolls: {node, pos, vel, factor}
var decor: Array[Dictionary] = []
## Short-lived particles: {node, pos, vel, grav, life, max_life, frames, home}
var fx: Array[Dictionary] = []

var rng := RandomNumberGenerator.new()

var world: Node2D
var sky: Node2D
var back_layer: Node2D
var moon_sprite: AnimatedSprite2D
var ground: Node2D
var pad_sprite: AnimatedSprite2D
var pad_arrows: Node2D
var mid_layer: Node2D
var rocket: Node2D
var rocket_sprite: AnimatedSprite2D
var stage_sprite: AnimatedSprite2D
var flame: AnimatedSprite2D
var arm: Node2D
var claw_sprite: AnimatedSprite2D
var fx_layer: Node2D
var hud: Hud
var crew: Node2D
var lights: Node2D
var button: Node2D
var flash: ColorRect
var pause_overlay: Node2D


func _ready() -> void:
	rng.randomize()
	data = Timeline.load_data()
	for s in ["sky", "space", "moon"]:
		lengths[s] = Timeline.stage_length(data, s, Game.trip_scale)
	_build()
	_load_stage("sky")
	Sfx.music("music_space")


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

func _build() -> void:
	world = Node2D.new()
	add_child(world)
	sky = SkyView.new()
	world.add_child(sky)
	back_layer = Node2D.new()
	world.add_child(back_layer)
	# Just lifted off: the launch site slides away below.
	var earth := _spr("earth_ground", C_GREEN, Vector2i(320, 48), back_layer)
	decor.append({"node": earth, "pos": Vector2(160, H - 24), "vel": Vector2.ZERO, "factor": 1.0})
	for i in 5:
		_spawn_cloud(Vector2(rng.randi_range(0, W), rng.randi_range(-10, 150)))

	moon_sprite = _spr("moon", C_GREY, Vector2i(96, 96), back_layer)
	moon_sprite.visible = false
	ground = Node2D.new()
	ground.visible = false
	back_layer.add_child(ground)
	var g := _spr("moon_ground", C_SLATE, Vector2i(320, 32), ground)
	g.position = Vector2(160, H - 16)
	pad_sprite = _spr("launch_pad", C_GREY, Vector2i(64, 16), ground)
	pad_arrows = Arrows.new()
	ground.add_child(pad_arrows)

	mid_layer = Node2D.new()
	world.add_child(mid_layer)

	rocket = Node2D.new()
	world.add_child(rocket)
	flame = _spr("flame", C_YELLOW, Vector2i(8, 12), rocket)
	flame.stop()
	stage_sprite = _spr("rocket_stage", C_GREY, Vector2i(24, 16), rocket)
	stage_sprite.position = Vector2(0, 28)
	rocket_sprite = _spr("rocket", C_WHITE, Vector2i(24, 40), rocket)
	rocket_sprite.stop()

	arm = ArmView.new()
	arm.link_tex = Art.frames("arm_link", C_GREY, Vector2i(4, 4)).get_frame_texture("default", 0)
	world.add_child(arm)
	claw_sprite = _spr("claw", C_YELLOW, Vector2i(8, 8), world)
	claw_sprite.stop()
	claw_sprite.visible = Players.is_seated(GRABBER)

	fx_layer = Node2D.new()
	world.add_child(fx_layer)

	flash = ColorRect.new()
	flash.size = Vector2(W, H)
	flash.color = Color(1, 1, 1, 0)
	add_child(flash)

	hud = Hud.new()
	add_child(hud)
	hud.can = _spr("fuel", C_RED, Vector2i(8, 12), hud)
	hud.can.stop()
	hud.can.position = Vector2(W - 60, 10)
	crew = Crew.new()
	crew.position = Vector2(2, 1)
	add_child(crew)
	hud.left = 2 + crew.width() + 4
	lights = Lights.new()
	lights.count = SEPARATION_LIGHTS
	lights.position = Vector2(160, 36)
	lights.visible = false
	add_child(lights)
	button = BigButton.new()
	button.color = Players.SEAT_COLORS[Game.press_seat()]
	button.position = Vector2(160, 62)
	button.visible = false
	add_child(button)

	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	add_child(pause_overlay)
	_place_nodes(0.0)


func _spr(sprite_name: String, tint: Color, size: Vector2i, parent: Node) -> AnimatedSprite2D:
	var s := Art.sprite(sprite_name, tint, size)
	parent.add_child(s)
	return s


func _load_stage(stage_name: String) -> void:
	spawns = Timeline.expand(data, stage_name, Game.trip_scale, stage_name.hash())
	spawn_i = 0
	stage_t = 0.0


# ================================================================ frame

func step(dt: float) -> void:
	if stage == Stage.DONE:
		return
	if _pause_input():
		return
	trip_t += dt
	invuln = maxf(0.0, invuln - dt)
	wobble_t = maxf(0.0, wobble_t - dt)
	boost_t = maxf(0.0, boost_t - dt)
	boost_cd = maxf(0.0, boost_cd - dt)
	shake_t = maxf(0.0, shake_t - dt)
	flash_t = maxf(0.0, flash_t - dt)

	_stage_clock(dt)
	if stage == Stage.DONE:
		return
	_launcher_input()
	_move_rocket(dt)
	_grabber(dt)
	_spawner()
	_update_pickups(dt)
	_update_asteroids(dt)
	_update_decor(dt)
	_update_fx(dt)
	_place_nodes(dt)


func flying() -> bool:
	return stage == Stage.SKY or stage == Stage.SPACE or stage == Stage.MOON


## Advances the stage clock and the transitions between stages.
func _stage_clock(dt: float) -> void:
	if flying():
		if stage != Stage.MOON:
			tank = maxf(0.0, tank - Rules.DRAIN * dt)
		speed = Rules.scroll_speed(tank, boost_t > 0.0)
		if stage == Stage.MOON:
			speed *= lerpf(1.0, 0.3, clampf(stage_t / approach_len(), 0.0, 1.0))
		scroll += speed * dt
		stage_t += dt
	else:
		speed = 0.0
	match stage:
		Stage.SKY:
			sky_level = clampf(stage_t / lengths.sky * 3.0, 0.0, 2.0)
			if stage_t >= lengths.sky and awaiting == "":
				_await(AWAIT_SPACE)
		Stage.SPACE:
			sky_level = minf(sky_level + dt * 1.5, 5.0)
			if not separated and separation == null and stage_t >= lengths.space * 0.5:
				_start_separation()
			if separation != null:
				_separation_step(dt)
			if stage_t >= lengths.space and separation == null:
				_go_moon()
		Stage.MOON:
			if stage_t >= approach_len():
				_go_landing()
		Stage.LANDED:
			landed_t += dt
			if landed_t >= 1.0 and not flags_planted and awaiting == "":
				_await(AWAIT_FLAG)
			if flags_planted:
				flag_t += dt
				if flag_t >= FLAG_SECONDS:
					_finish()
					return
	if awaiting != "":
		await_t += dt
		if Game.launch_pressed():
			_transition_press(false)
		elif await_t >= Countdown.AUTO_PRESS:
			_transition_press(true)


func approach_len() -> float:
	return lengths.moon * APPROACH_SHARE


func _await(what: String) -> void:
	awaiting = what
	await_t = 0.0


func _transition_press(_auto: bool) -> void:
	button.press()
	crew.hop(Game.press_seat())
	var what := awaiting
	awaiting = ""
	match what:
		AWAIT_SPACE:
			_go_space()
		AWAIT_FLAG:
			_plant_flags()


func _go_space() -> void:
	stage = Stage.SPACE
	_load_stage("space")
	Sfx.play("liftoff", 1.1)
	shake_t = maxf(shake_t, 0.6)
	_auto_boost()
	# The last clouds leave; the stars come out.
	for d in decor:
		d.factor = maxf(d.factor, 1.6)


func _start_separation() -> void:
	separation = Countdown.new(SEPARATION_LIGHTS, 0.8, 0.5)


func _separation_step(dt: float) -> void:
	var press := Game.launch_pressed()
	if press:
		button.press()
		crew.hop(Game.press_seat())
	for ev in separation.step(dt, press):
		match ev:
			"start":
				Sfx.play("select")
			"light":
				Sfx.play("beep_%d" % (2 + separation.out))
			"shake":
				shake_t = maxf(shake_t, 0.15)
				_puff(rocket_pos + Vector2(0, 30))
			"ignite":
				Sfx.play("ignition", 1.2, -4.0)
			"done":
				_separate()
				separation = null
				return


## The lower stage falls away tumbling, with a clank and a big boost.
func _separate() -> void:
	separated = true
	stage_sprite.visible = false
	var s := _spr("rocket_stage", C_GREY, Vector2i(24, 16), fx_layer)
	s.stop()
	fx.append({"node": s, "pos": rocket_pos + Vector2(0, 28), "vel": Vector2(rng.randf_range(-20, 20), 40),
		"grav": 60.0, "life": 3.0, "max_life": 3.0, "spin": 1.0})
	Sfx.play("separation")
	shake_t = maxf(shake_t, 0.4)
	for i in 6:
		_puff(rocket_pos + Vector2(rng.randf_range(-10, 10), 24))
	_auto_boost()


func _go_moon() -> void:
	stage = Stage.MOON
	_load_stage("moon")
	moon_sprite.visible = true
	_auto_boost()


## The approach is over: a flash, and we are above the Moon's surface.
func _go_landing() -> void:
	stage = Stage.LANDING
	flash_t = 0.5
	moon_sprite.visible = false
	ground.visible = true
	Sfx.play("separation", 0.7, -6.0)
	rocket_pos.y = 50.0
	rocket_vy = 0.0
	# The pad starts away from the rocket, so the Pilot has something to do.
	pad_x = 250.0 if rocket_pos.x < 160.0 else 70.0
	tries = 0
	pad_sliding = false
	for p in pickups:
		p.node.queue_free()
	pickups.clear()
	for a in asteroids:
		a.node.queue_free()
	asteroids.clear()
	if claw.carried != null:
		claw.carried = null
	claw.phase = Claw.Phase.IDLE
	claw.length = 0.0


func _finish() -> void:
	stage = Stage.DONE
	Game.fuel = fuel_count
	Game.goto("party")


## Pause belongs to the pilot only. Returns true while paused.
func _pause_input() -> bool:
	if Players.just_pressed(PILOT, "start"):
		paused = not paused
		pause_overlay.visible = paused
		Sfx.play("select")
		return true
	if paused:
		if Players.just_pressed(PILOT, "a"):
			paused = false
			pause_overlay.visible = false
		elif Players.just_pressed(PILOT, "b"):
			stage = Stage.DONE
			Players.reset()
			Game.goto("join")
	return paused


# ================================================================ roles

## Booster: the Launcher's any button, or the Pilot's "a" when flying alone.
## (A pending transition takes the press instead.)
func _launcher_input() -> void:
	if awaiting != "" or separation != null or not flying():
		if stage == Stage.LANDING and Players.just_pressed(LAUNCHER, "any"):
			_puff(rocket_pos + Vector2(0, 24))  # a harmless puff while landing
		return
	var pressed := false
	if Players.is_seated(LAUNCHER):
		pressed = Players.just_pressed(LAUNCHER, "any")
		if pressed:
			crew.hop(LAUNCHER)
	elif Players.seated_count() == 1:
		pressed = Players.just_pressed(PILOT, "a")
	if pressed:
		fire_booster()


## Returns true if the booster fired (false: cooling down, just a puff).
func fire_booster() -> bool:
	if boost_cd > 0.0:
		_puff(rocket_pos + Vector2(rng.randf_range(-6, 6), 30 if not separated else 20))
		Sfx.play("puff", rng.randf_range(1.0, 1.3), -8.0)
		return false
	boost_t = Rules.BOOST_SECONDS
	boost_cd = Rules.BOOST_COOLDOWN
	shake_t = maxf(shake_t, 0.2)
	Sfx.play("booster")
	return true


## With no Launcher seated, the booster fires by itself at every stage change.
func _auto_boost() -> void:
	if not Players.is_seated(LAUNCHER):
		boost_cd = 0.0
		fire_booster()


func _move_rocket(dt: float) -> void:
	var mv := Players.move(PILOT)
	if stage == Stage.LANDING:
		rocket_pos.x += mv.x * PILOT_SPEED * 0.8 * dt
		var want := DESCENT + mv.y * 14.0
		rocket_vy = move_toward(rocket_vy, want, 70.0 * dt)
		rocket_pos.y += rocket_vy * dt
		rocket_pos.y = maxf(rocket_pos.y, 30.0)
		rocket_pos.x = clampf(rocket_pos.x, X_MIN, X_MAX)
		if pad_sliding:
			pad_x = move_toward(pad_x, rocket_pos.x, PAD_SLIDE * dt)
		_touchdown()
		return
	if stage == Stage.LANDED:
		return
	rocket_pos += mv * PILOT_SPEED * dt
	rocket_pos.x += knock * dt
	knock = move_toward(knock, 0.0, 300.0 * dt)
	# Rising in from the bottom at the start of the flight.
	if entering:
		rocket_pos.y = minf(rocket_pos.y, _entry_y)
		rocket_pos.y = move_toward(rocket_pos.y, Y_HOME, 70.0 * dt)
		_entry_y = rocket_pos.y
		entering = rocket_pos.y > Y_MAX
	else:
		rocket_pos.y = clampf(rocket_pos.y, Y_MIN, Y_MAX)
	# Soft walls: the rocket slides along the edges, it never leaves.
	rocket_pos.x = clampf(rocket_pos.x, X_MIN, X_MAX)
	_check_bumps()


func _rocket_bottom() -> float:
	return rocket_pos.y + 20.0 + (16.0 if not separated else 0.0)


func _touchdown() -> void:
	var on := Rules.on_pad(rocket_pos.x, pad_x)
	var floor_y := PAD_DECK if on else GROUND_Y
	if _rocket_bottom() < floor_y or rocket_vy < 0.0:
		return
	rocket_pos.y = floor_y - (_rocket_bottom() - rocket_pos.y)
	for i in 5:
		_dust(Vector2(rocket_pos.x + rng.randf_range(-14, 14), floor_y))
	if on:
		stage = Stage.LANDED
		landed_t = 0.0
		rocket_vy = 0.0
		Sfx.play("landing")
		shake_t = maxf(shake_t, 0.3)
	else:
		tries += 1
		rocket_vy = BOUNCE_VY
		Sfx.play("bump", 0.9)
		if tries >= Rules.LANDING_TRIES:
			pad_sliding = true


func _plant_flags() -> void:
	flags_planted = true
	flag_t = 0.0
	Sfx.play("flag")
	var offsets := [-26, 26, -42]
	var i := 0
	for seat in Players.SEAT_COUNT:
		if not Players.is_seated(seat):
			continue
		var f := _spr("flag", Players.SEAT_COLORS[seat], Vector2i(16, 16), ground)
		f.modulate = Players.SEAT_COLORS[seat].lightened(0.25)
		f.position = Vector2(clampf(rocket_pos.x + offsets[i], 10, W - 10), PAD_DECK - 8)
		i += 1
	_confetti(Vector2(rocket_pos.x, 110), 30)


# ================================================================ grabber

func claw_origin() -> Vector2:
	return rocket_pos + Vector2(0, -2)


func _grabber(dt: float) -> void:
	if not flying():
		return
	if Players.is_seated(GRABBER):
		var d := Players.dir4(GRABBER)
		if d != Vector2i.ZERO and claw.idle():
			claw.aim = d
		if Players.just_pressed(GRABBER, "a") or (Players.pressed(GRABBER, "a") and claw.idle()):
			if claw.shoot(claw_origin(), pickups):
				Sfx.play("claw_shoot", rng.randf_range(0.95, 1.08), -2.0)
				crew.hop(GRABBER)
	var ev := claw.step(dt, claw_origin(), pickups)
	if ev.has("grabbed"):
		Sfx.play("claw_grab")
	elif ev.has("delivered"):
		collect(ev.delivered)


## Something reached the rocket (by claw, magnet or fly-through).
func collect(p: Dictionary) -> void:
	match p.kind:
		"fuel":
			fuel_count += 1
			tank = minf(1.0, tank + Rules.FUEL_REFILL)
			hud.bump = 0.15
			Sfx.play("fuel", 1.0 + 0.04 * (fuel_count % 8))
		"planet":
			var fresh := Game.found_planet(p.planet)
			Sfx.play("planet_%d" % p.planet)
			_sparkles(p.pos, 10 if fresh else 5)
		"balloon":
			tank = minf(1.0, tank + Rules.BALLOON_REFILL)
			Sfx.play("pop")
			_confetti(p.pos, 12)
	p.node.queue_free()
	pickups.erase(p)


# ================================================================ spawning

func _spawner() -> void:
	while spawn_i < spawns.size() and spawns[spawn_i].t <= stage_t:
		var e: Dictionary = spawns[spawn_i]
		spawn_i += 1
		spawn(e.kind, Vector2(e.x, -14), e.planet)


func spawn(kind: String, at: Vector2, planet := 0) -> Dictionary:
	match kind:
		"fuel":
			return spawn_pickup("fuel", at)
		"balloon":
			return spawn_pickup("balloon", at)
		"planet":
			return spawn_pickup("planet", at, clampi(planet, 1, 8))
		"asteroid":
			return spawn_asteroid(at)
		"bird":
			var b := _spr("bird", C_INK, Vector2i(8, 8), back_layer)
			var dir := 1.0 if at.x < W / 2 else -1.0
			b.flip_h = dir < 0.0
			var d := {"node": b, "pos": Vector2(-8 if dir > 0 else W + 8, at.y + rng.randf_range(20, 80)),
				"vel": Vector2(dir * rng.randf_range(24, 36), 0), "factor": 0.6}
			decor.append(d)
			return d
		"comet":
			var c := _spr("comet", C_CYAN, Vector2i(16, 8), back_layer)
			var d := {"node": c, "pos": Vector2(at.x + 60, -10), "vel": Vector2(-50, 10), "factor": 0.5}
			decor.append(d)
			return d
	return {}


func spawn_pickup(kind: String, at: Vector2, planet := 0) -> Dictionary:
	var n: AnimatedSprite2D
	match kind:
		"fuel":
			n = _spr("fuel", C_RED, Vector2i(8, 12), mid_layer)
		"balloon":
			var tints := [C_RED, C_ORANGE, C_LIME, C_CYAN]
			n = _spr("balloon", tints[rng.randi() % tints.size()], Vector2i(16, 24), mid_layer)
		_:
			n = _spr("planet_%d" % planet, C_ORANGE, Vector2i(16, 16), mid_layer)
	var p := {"node": n, "kind": kind, "planet": planet, "pos": at, "vel": Vector2(rng.randf_range(-6, 6), 0),
		"dropped": false, "grabbed": false, "age": 0.0}
	pickups.append(p)
	return p


func spawn_asteroid(at: Vector2) -> Dictionary:
	var n := _spr("asteroid", C_SLATE, Vector2i(16, 16), mid_layer)
	var a := {"node": n, "pos": at, "vel": Vector2(rng.randf_range(-10, 10), rng.randf_range(8, 18)), "dazed": false}
	asteroids.append(a)
	return a


func _spawn_cloud(at: Vector2) -> void:
	var c := _spr("cloud", C_WHITE, Vector2i(32, 16), back_layer)
	decor.append({"node": c, "pos": at, "vel": Vector2(rng.randf_range(-4, 4), 0), "factor": rng.randf_range(0.5, 0.9),
		"cloud": true})


# ================================================================ bumps

## A soft grumpy asteroid bumped the rocket: a wobble spin, two cans float
## out (grab them back), 1.5 s of blinking. The rocket never stops.
func _check_bumps() -> void:
	if invuln > 0.0 or boost_t > 0.0:
		return
	for a in asteroids:
		if a.dazed:
			continue
		var hit := Rules.overlap(rocket_pos, ROCKET_HIT, a.pos, ASTEROID_HIT)
		if not separated:
			hit = hit or Rules.overlap(rocket_pos + Vector2(0, 28), STAGE_HIT, a.pos, ASTEROID_HIT)
		if hit:
			bump(a)
			return


func bump(a: Dictionary) -> void:
	invuln = Rules.INVULN_SECONDS
	wobble_t = Rules.WOBBLE_SECONDS
	var away := signf(rocket_pos.x - a.pos.x)
	if away == 0.0:
		away = 1.0
	knock = away * 110.0
	a.dazed = true
	a.vel = Vector2(-away * 40.0, -30.0)
	shake_t = maxf(shake_t, 0.25)
	Sfx.play("bump")
	var n := Rules.bump_drop(fuel_count)
	fuel_count -= n
	for i in n:
		var side := -1.0 if i % 2 == 0 else 1.0
		var p := spawn_pickup("fuel", rocket_pos + Vector2(side * 10, -8))
		p.dropped = true
		p.vel = Vector2(side * rng.randf_range(40, 60), -rng.randf_range(30, 45))


# ================================================================ updates

func _update_pickups(dt: float) -> void:
	var magnet := not Players.is_seated(GRABBER)
	for i in range(pickups.size() - 1, -1, -1):
		var p := pickups[i]
		if p.grabbed:
			continue  # the claw carries it
		p.age += dt
		if p.dropped:
			# Dropped cans float near the rocket for a while, easy to grab back.
			p.vel = p.vel.move_toward(Vector2(0, 10), 60.0 * dt)
		else:
			p.vel.y = speed * (0.8 if p.kind == "balloon" else 1.0)
		if magnet and flying():
			var to: Vector2 = rocket_pos - p.pos
			if to.length() < MAGNET_RADIUS:
				p.vel = p.vel.lerp(to.normalized() * 140.0, minf(1.0, 6.0 * dt))
			if to.length() < PICK_RADIUS:
				collect(p)
				continue
		p.pos += p.vel * dt
		if p.kind == "balloon":
			p.pos.x += sin(p.age * 2.0) * 6.0 * dt
		if p.pos.y > H + 20 or p.pos.x < -24 or p.pos.x > W + 24:
			p.node.queue_free()
			pickups.remove_at(i)


func _update_asteroids(dt: float) -> void:
	for i in range(asteroids.size() - 1, -1, -1):
		var a := asteroids[i]
		# The booster cleans up the lane above the rocket: asteroids become stars.
		if boost_t > 0.0 and absf(a.pos.x - rocket_pos.x) < BOOST_LANE and a.pos.y < rocket_pos.y + 10 \
				and a.pos.y > -16:
			starify(a)
			continue
		if a.dazed:
			a.vel = a.vel.move_toward(Vector2(a.vel.x, speed), 80.0 * dt)
			a.pos += a.vel * dt
		else:
			a.pos += Vector2(a.vel.x, a.vel.y + speed) * dt
		if a.pos.y > H + 20 or a.pos.x < -24 or a.pos.x > W + 24:
			a.node.queue_free()
			asteroids.remove_at(i)


## An asteroid turns into sparkling stars that fly into the tank.
func starify(a: Dictionary) -> void:
	for k in 3:
		var s := _spr("sparkle", C_YELLOW, Vector2i(8, 8), fx_layer)
		fx.append({"node": s, "pos": a.pos, "vel": Vector2.from_angle(rng.randf() * TAU) * 50.0, "grav": 0.0,
			"life": 1.2, "max_life": 1.2, "home": true})
	Sfx.play("pop", 1.3, -6.0)
	a.node.queue_free()
	asteroids.erase(a)


func _update_decor(dt: float) -> void:
	var clouds := 0
	for i in range(decor.size() - 1, -1, -1):
		var d := decor[i]
		d.pos += (d.vel + Vector2(0, speed * d.factor)) * dt
		if d.has("cloud"):
			clouds += 1
		if d.pos.y > H + 40 or d.pos.x < -40 or d.pos.x > W + 40:
			d.node.queue_free()
			decor.remove_at(i)
			if d.has("cloud"):
				clouds -= 1
	# Keep clouds coming while we are in the sky.
	if stage == Stage.SKY and clouds < 5 and awaiting == "":
		_spawn_cloud(Vector2(rng.randi_range(0, W), -12))


func _puff(at: Vector2) -> void:
	var s := _spr("smoke", C_WHITE, Vector2i(16, 16), fx_layer)
	s.stop()
	fx.append({"node": s, "pos": at, "vel": Vector2(rng.randf_range(-20, 20), rng.randf_range(10, 30)), "grav": 0.0,
		"life": 0.6, "max_life": 0.6, "frames": true})


func _dust(at: Vector2) -> void:
	var s := _spr("smoke", C_GREY, Vector2i(16, 16), fx_layer)
	s.stop()
	fx.append({"node": s, "pos": at, "vel": Vector2(rng.randf_range(-50, 50), -rng.randf_range(4, 16)), "grav": 0.0,
		"life": 0.9, "max_life": 0.9, "frames": true})


func _sparkles(at: Vector2, count: int) -> void:
	for i in count:
		var s := _spr("sparkle", C_YELLOW, Vector2i(8, 8), fx_layer)
		fx.append({"node": s, "pos": at, "vel": Vector2.from_angle(TAU * i / count) * 70.0, "grav": 0.0,
			"life": 0.7, "max_life": 0.7})


func _confetti(at: Vector2, count: int) -> void:
	for i in count:
		var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
		var c := _spr("confetti", tint, Vector2i(4, 4), fx_layer)
		c.stop()
		c.frame = rng.randi() % maxi(1, c.sprite_frames.get_frame_count("default"))
		fx.append({"node": c, "pos": at, "vel": Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 90)
			+ Vector2(0, -40), "grav": 140.0, "life": rng.randf_range(0.9, 1.5), "max_life": 1.5})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var p := fx[i]
		p.life -= dt
		if p.get("home", false) and p.life < p.max_life - 0.35:
			var to: Vector2 = rocket_pos - p.pos
			p.vel = p.vel.lerp(to.normalized() * 220.0, minf(1.0, 8.0 * dt))
			if to.length() < 10.0:
				tank = minf(1.0, tank + Rules.SPARKLE_REFILL)
				hud.bump = 0.1
				p.node.queue_free()
				fx.remove_at(i)
				continue
		p.vel.y += p.grav * dt
		p.pos += p.vel * dt
		var n: AnimatedSprite2D = p.node
		if p.get("frames", false):
			var k := n.sprite_frames.get_frame_count("default")
			n.frame = clampi(int((1.0 - p.life / p.max_life) * k), 0, k - 1)
		if p.has("spin"):
			p.spin += dt
			n.rotation = PI * 0.5 * (int(p.spin * 4.0) % 4)
		if p.life <= 0.0 or p.pos.y > H + 30:
			n.queue_free()
			fx.remove_at(i)


# ================================================================ drawing

func _place_nodes(dt: float) -> void:
	var sh := Vector2(rng.randi_range(-2, 2), rng.randi_range(-1, 1)) if shake_t > 0.0 else Vector2.ZERO
	world.position = sh
	sky.level = int(sky_level)
	sky.scroll = scroll
	sky.time = trip_t

	# Rocket: rumble frames, the wobble spin after a bump, the flame by fuel.
	rocket.position = rocket_pos.round()
	var nf := rocket_sprite.sprite_frames.get_frame_count("default")
	var fr := int(trip_t * 8.0) % 2
	if wobble_t > 0.0 and nf >= 10:
		fr = 2 + clampi(int((1.0 - wobble_t / Rules.WOBBLE_SECONDS) * 8.0), 0, 7)
	rocket_sprite.frame = mini(fr, nf - 1)
	rocket.visible = invuln <= 0.0 or int(invuln * 12.0) % 2 == 0 or wobble_t > 0.0
	var burning := stage != Stage.LANDED
	flame.visible = burning
	var fnf := flame.sprite_frames.get_frame_count("default")
	var small := tank <= 0.0 or stage == Stage.LANDING
	var base := 4 if small and fnf >= 8 else 0
	flame.frame = mini(base + int(trip_t * 14.0) % 4, fnf - 1)
	flame.scale = Vector2(2, 2) if boost_t > 0.0 else Vector2.ONE
	var flame_top := 20.0 + (16.0 if not separated else 0.0)
	flame.position = Vector2(0, flame_top + 6.0 * flame.scale.y)

	# Claw and arm.
	var o := claw_origin()
	arm.origin = o.round()
	arm.tip = claw.tip_pos(o).round()
	arm.out = not claw.idle()
	arm.queue_redraw()
	if claw.idle():
		claw_sprite.position = (o + Vector2(claw.aim) * 16.0).round()
	else:
		claw_sprite.position = claw.tip_pos(o).round()
	claw_sprite.rotation = claw.rotation()
	claw_sprite.frame = 1 if claw.carried != null else 0
	claw_sprite.visible = Players.is_seated(GRABBER) and flying()

	for p in pickups:
		p.node.position = p.pos.round()
	for a in asteroids:
		a.node.position = a.pos.round()
		var af: int = a.node.sprite_frames.get_frame_count("default")
		a.node.frame = mini(1 if a.dazed or int(trip_t * 2.0 + a.pos.x) % 6 == 0 else 0, af - 1)
	for d in decor:
		d.node.position = d.pos.round()
	for p in fx:
		p.node.position = p.pos.round()

	# The Moon grows in whole-pixel steps as we get close.
	if stage == Stage.MOON:
		var k := clampf(stage_t / approach_len(), 0.0, 1.0)
		var sc := 1 if k < 0.55 else (2 if k < 0.82 else 3)
		moon_sprite.scale = Vector2(sc, sc)
		moon_sprite.position = Vector2(160, roundf(lerpf(-40.0, 70.0, k) + (sc - 1) * 24.0))
	if ground.visible:
		pad_sprite.position = Vector2(roundf(pad_x), PAD_DECK + 6)
		pad_arrows.position = Vector2(roundf(pad_x), PAD_DECK - 30)
		pad_arrows.visible = stage == Stage.LANDING
		pad_arrows.time = trip_t
		pad_arrows.queue_redraw()
	flash.color.a = clampf(flash_t / 0.5, 0.0, 1.0)

	# HUD.
	lights.visible = separation != null
	if separation != null:
		lights.out = separation.out
	button.visible = awaiting != "" or (separation != null and separation.waiting())
	button.waiting = button.visible
	button.tick(dt)
	crew.tick(dt)
	hud.progress = trip_progress()
	hud.tank = tank
	hud.boost = boost_t > 0.0
	hud.tick(dt)


## 0..1 along the whole trip (for the Earth-to-Moon bar).
func trip_progress() -> float:
	var total: float = lengths.sky + lengths.space + approach_len()
	var done := 0.0
	match stage:
		Stage.SKY:
			done = minf(stage_t, lengths.sky)
		Stage.SPACE:
			done = lengths.sky + minf(stage_t, lengths.space)
		Stage.MOON:
			done = lengths.sky + lengths.space + minf(stage_t, approach_len())
		_:
			done = total
	return clampf(done / maxf(total, 0.001), 0.0, 1.0)


## Top bar: an Earth-to-Moon track with a tiny rocket, and the fuel gauge.
class Hud extends Node2D:
	var progress := 0.0
	var tank := 1.0
	var boost := false
	var bump := 0.0
	var left := 60
	var can: AnimatedSprite2D

	func tick(dt: float) -> void:
		bump = maxf(0.0, bump - dt)
		if can:
			can.position = Vector2(262, 12 - (2 if bump > 0.0 else 0))
		queue_redraw()

	func _draw() -> void:
		var x0 := left + 8
		var x1 := 238
		var y := 11
		# Earth at the start, Moon at the end, dotted track between.
		draw_circle(Vector2(x0 - 4, y), 4, Color("#41a6f6"))
		draw_rect(Rect2(x0 - 6, y - 2, 3, 2), Color("#38b764"))
		draw_rect(Rect2(x0 - 3, y + 1, 2, 2), Color("#38b764"))
		draw_circle(Vector2(x1 + 5, y), 4, Color("#f4f4f4"))
		draw_rect(Rect2(x1 + 4, y - 2, 2, 2), Color("#94b0c2"))
		for x in range(x0 + 2, x1, 4):
			draw_rect(Rect2(x, y, 2, 1), Color("#566c86"))
		var px := x0 + int(roundf(progress * float(x1 - x0)))
		draw_rect(Rect2(x0 + 2, y, px - x0 - 2, 1), Color("#ffcd75"))
		# Tiny rocket pointing right along the track.
		draw_rect(Rect2(px - 4, y - 1, 7, 3), Color("#f4f4f4"))
		draw_rect(Rect2(px + 3, y, 1, 1), Color("#b13e53"))
		draw_rect(Rect2(px - 5, y - 2, 2, 5), Color("#b13e53"))
		draw_rect(Rect2(px - 7, y, 2, 1), Color("#ef7d57") if boost else Color("#ffcd75"))
		# Fuel gauge: a bar that empties, red when low.
		var gx := 270
		draw_rect(Rect2(gx, 6, 44, 10), Color("#1a1c2c"))
		draw_rect(Rect2(gx + 1, 7, 42, 8), Color("#333c57"))
		var w := int(roundf(clampf(tank, 0.0, 1.0) * 40.0))
		var col := Color("#a7f070") if tank > 0.3 else (Color("#ffcd75") if tank > 0.0 else Color("#b13e53"))
		draw_rect(Rect2(gx + 2, 8, w, 6), col)
		draw_rect(Rect2(gx + 2, 8, w, 1), col.lightened(0.4))


## The arm: links from the rocket to the claw.
class ArmView extends Node2D:
	var origin := Vector2.ZERO
	var tip := Vector2.ZERO
	var out := false
	var link_tex: Texture2D

	func _draw() -> void:
		if not out or link_tex == null:
			return
		var d := tip - origin
		var n := int(d.length() / 5.0)
		for i in range(1, n):
			var p := (origin + d * float(i) / float(n)).round() - Vector2(2, 2)
			draw_texture(link_tex, p)


## Big arrows pointing down at the landing pad.
class Arrows extends Node2D:
	var time := 0.0

	func _draw() -> void:
		var bob := 2 if int(time * 3.0) % 2 == 0 else 0
		for side in [-1, 1]:
			var x: float = side * 26
			var y := bob
			draw_colored_polygon(PackedVector2Array([Vector2(x - 6, y), Vector2(x + 6, y), Vector2(x, y + 8)]),
				Color("#ffcd75"))
			draw_rect(Rect2(x - 2, y - 6, 4, 6), Color("#ffcd75"))
