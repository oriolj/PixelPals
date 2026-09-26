extends Node2D
## The launch pad: the rocket on its gantry, the big button pulsing. The press
## seat (Launcher, else Grabber, else Pilot) presses: five lights go out one
## by one with rising beeps and a big pixel digit, then ignition, smoke, a
## rumble and lift-off. Presses during the count only shake the rocket and
## puff steam; they can never skip it. After 8 s without a press the button
## presses itself.
##
## All logic is in step(dt) so tests drive it frame by frame.

const Countdown := preload("res://scripts/logic/countdown.gd")
const SkyView := preload("res://scripts/view/sky.gd")
const Digits := preload("res://scripts/view/digits.gd")
const Crew := preload("res://scripts/view/crew.gd")
const Lights := preload("res://scripts/view/lights.gd")
const BigButton := preload("res://scripts/view/big_button.gd")
const PauseOverlay := preload("res://scripts/view/pause_overlay.gd")

const DRIVER := 0
const PAD_TOP := 140          # the deck of the launch pad
const ROCKET_X := 160
const LIFTOFF_ACCEL := 70.0

enum Phase { COUNTDOWN, LIFTOFF, DONE }

var phase := Phase.COUNTDOWN
var countdown := Countdown.new(5, 1.0, 1.6)
var paused := false
var time := 0.0
## Rocket bottom (of the lower stage), moves up during lift-off.
var rocket_bottom := float(PAD_TOP)
var rocket_vy := 0.0
var shake_t := 0.0
var rocket_shake_t := 0.0
var presses_during_count := 0
## Auto-advance to the flight (false in tests that only check the countdown).
var auto_goto := true

var rng := RandomNumberGenerator.new()
var world: Node2D
var sky: Node2D
var rocket: Node2D
var rocket_sprite: AnimatedSprite2D
var stage_sprite: AnimatedSprite2D
var flame: AnimatedSprite2D
var fx_layer: Node2D
var lights: Node2D
var digit: Node2D
var button: Node2D
var crew: Node2D
var pause_overlay: Node2D
## Smoke puffs and steam: {node, pos, vel, life, max_life}
var fx: Array[Dictionary] = []


func _ready() -> void:
	rng.randomize()
	Game.new_trip()
	_build()
	Sfx.stop_music()


func _process(delta: float) -> void:
	step(delta)


func _build() -> void:
	world = Node2D.new()
	add_child(world)
	sky = SkyView.new()
	world.add_child(sky)
	# Distant clouds, still: it is a calm morning.
	for c in [[40, 30], [250, 22], [120, 52], [290, 70], [20, 84]]:
		var cl := _spr("cloud", Color("#f4f4f4"), Vector2i(32, 16), world)
		cl.position = Vector2(c[0], c[1])
	var ground := _spr("earth_ground", Color("#38b764"), Vector2i(320, 48), world)
	ground.position = Vector2(160, 180 - 24)
	var pad := _spr("launch_pad", Color("#566c86"), Vector2i(64, 16), world)
	pad.position = Vector2(ROCKET_X, PAD_TOP + 8)
	var gantry := _spr("gantry", Color("#b13e53"), Vector2i(16, 64), world)
	gantry.position = Vector2(ROCKET_X - 26, PAD_TOP - 32)

	rocket = Node2D.new()
	world.add_child(rocket)
	flame = _spr("flame", Color("#ffcd75"), Vector2i(8, 12), rocket)
	flame.stop()
	flame.visible = false
	flame.position = Vector2(0, 6)
	stage_sprite = _spr("rocket_stage", Color("#94b0c2"), Vector2i(24, 16), rocket)
	stage_sprite.position = Vector2(0, -8)
	rocket_sprite = _spr("rocket", Color("#f4f4f4"), Vector2i(24, 40), rocket)
	rocket_sprite.stop()
	rocket_sprite.position = Vector2(0, -16 - 20)

	fx_layer = Node2D.new()
	world.add_child(fx_layer)

	lights = Lights.new()
	lights.count = countdown.lights
	lights.position = Vector2(160, 14)
	add_child(lights)
	digit = Digits.new()
	digit.px = 5
	digit.color = Color("#ffcd75")
	digit.position = Vector2(160, 28)
	add_child(digit)
	button = BigButton.new()
	button.color = Players.SEAT_COLORS[Game.press_seat()]
	button.position = Vector2(266, 150)
	add_child(button)
	crew = Crew.new()
	crew.position = Vector2(2, 2)
	add_child(crew)
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	add_child(pause_overlay)
	_place(0.0)


func _spr(sprite_name: String, tint: Color, size: Vector2i, parent: Node) -> AnimatedSprite2D:
	var s := Art.sprite(sprite_name, tint, size)
	parent.add_child(s)
	return s


# ================================================================ frame

func step(dt: float) -> void:
	if phase == Phase.DONE:
		return
	if _pause_input():
		return
	time += dt
	shake_t = maxf(0.0, shake_t - dt)
	rocket_shake_t = maxf(0.0, rocket_shake_t - dt)
	var press := Game.launch_pressed()
	if press:
		button.press()
		crew.hop(Game.press_seat())
	if phase == Phase.COUNTDOWN:
		for ev in countdown.step(dt, press):
			_on_event(ev)
	else:
		rocket_vy -= LIFTOFF_ACCEL * dt
		rocket_bottom += rocket_vy * dt
		shake_t = maxf(shake_t, 0.1)
		if int(time * 20.0) % 2 == 0:
			_smoke(Vector2(ROCKET_X + rng.randf_range(-6, 6), minf(rocket_bottom + 6, PAD_TOP + 4)), 1.4)
		if press:
			_steam()
		if rocket_bottom < -20.0:
			_finish()
			return
	if countdown.state == Countdown.State.IGNITION and int(time * 15.0) % 2 == 0:
		_smoke(Vector2(ROCKET_X + rng.randf_range(-4, 4), PAD_TOP + 2), 1.0)
	_update_fx(dt)
	_place(dt)


func _on_event(ev: String) -> void:
	match ev:
		"start":
			Sfx.play("select")
			button.press()
		"light":
			Sfx.play("beep_%d" % countdown.out)
			shake_t = maxf(shake_t, 0.08)
		"shake":
			presses_during_count += 1
			rocket_shake_t = 0.25
			_steam()
		"ignite":
			Sfx.play("ignition")
			Sfx.play("rumble", 1.0, -3.0)
			shake_t = maxf(shake_t, 1.6)
			for i in 6:
				_smoke(Vector2(ROCKET_X + rng.randf_range(-10, 10), PAD_TOP), 1.2)
		"done":
			phase = Phase.LIFTOFF
			Sfx.play("liftoff")


func _finish() -> void:
	phase = Phase.DONE
	if auto_goto:
		Game.goto.call_deferred("flight")


## Pause belongs to the pilot only. Returns true while paused.
func _pause_input() -> bool:
	if Players.just_pressed(DRIVER, "start"):
		paused = not paused
		pause_overlay.visible = paused
		Sfx.play("select")
		return true
	if paused:
		if Players.just_pressed(DRIVER, "a"):
			paused = false
			pause_overlay.visible = false
		elif Players.just_pressed(DRIVER, "b"):
			phase = Phase.DONE
			Players.reset()
			Game.goto("join")
	return paused


# ================================================================ fx

func _steam() -> void:
	for side in [-1, 1]:
		var at := Vector2(ROCKET_X + side * 12, rocket_bottom - 6)
		_add_fx("smoke", Color("#f4f4f4"), at, Vector2(side * rng.randf_range(30, 50), -rng.randf_range(10, 25)), 0.6)
	Sfx.play("puff", rng.randf_range(0.9, 1.2), -4.0)


func _smoke(at: Vector2, life: float) -> void:
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	_add_fx("smoke", Color("#94b0c2"), at, Vector2(side * rng.randf_range(20, 70), -rng.randf_range(2, 14)), life)


func _add_fx(sprite_name: String, tint: Color, at: Vector2, vel: Vector2, life: float) -> void:
	var s := _spr(sprite_name, tint, Vector2i(16, 16), fx_layer)
	s.stop()
	s.frame = 0
	fx.append({"node": s, "pos": at, "vel": vel, "life": life, "max_life": life})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var p := fx[i]
		p.life -= dt
		p.vel *= pow(0.25, dt)
		p.pos += p.vel * dt
		var n: AnimatedSprite2D = p.node
		var k := n.sprite_frames.get_frame_count("default")
		n.frame = clampi(int((1.0 - p.life / p.max_life) * k), 0, k - 1)
		if p.life <= 0.0:
			n.queue_free()
			fx.remove_at(i)


# ================================================================ drawing

func _place(dt: float) -> void:
	world.position = Vector2(rng.randi_range(-2, 2), rng.randi_range(-1, 1)) if shake_t > 0.0 else Vector2.ZERO
	var jig := 0.0
	if rocket_shake_t > 0.0:
		jig = 1.0 if int(time * 30.0) % 2 == 0 else -1.0
	rocket.position = Vector2(ROCKET_X + jig, roundf(rocket_bottom))
	var idle_frame := int(time * 6.0) % 2 if countdown.state != Countdown.State.WAIT else 0
	rocket_sprite.frame = mini(idle_frame, rocket_sprite.sprite_frames.get_frame_count("default") - 1)
	var burning := countdown.state == Countdown.State.IGNITION or phase == Phase.LIFTOFF
	flame.visible = burning
	if burning:
		var nf := flame.sprite_frames.get_frame_count("default")
		flame.frame = int(time * 12.0) % mini(4, nf)
		flame.position = Vector2(0, 6)
	for p in fx:
		p.node.position = p.pos.round()
	lights.out = countdown.out
	digit.value = countdown.digit() if countdown.counting() else -1
	button.waiting = countdown.waiting()
	button.tick(dt)
	crew.tick(dt)
