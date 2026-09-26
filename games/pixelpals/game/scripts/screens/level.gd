extends Node2D
## The run: a flying bathtub scrolls through the sky for about three minutes.
## Driver steers, gunner fires (with aim assist), honker honks. No game over:
## a bump only costs a few stars. Everything is built in code.
##
## All logic lives in step(dt) so tests can drive it frame by frame with
## set_process(false) and scripted devices.

const Aim := preload("res://scripts/level/aim.gd")
const Rules := preload("res://scripts/level/rules.gd")

const W := 320
const H := 180
const GROUND_Y := 164           # top of the ground tile row
const TOP_Y := 12               # below the progress bar
const DRIVER := 0               # Players.Seat.DRIVER
const GUNNER := 1               # Players.Seat.GUNNER
const HONKER := 2               # Players.Seat.HONKER

const TUB_SPEED := 90.0
const TUB_HIT := Vector2(40, 18)
const CLOUD_HIT := Vector2(20, 12)
const BULLET_SPEED := 170.0
const FIRE_COOLDOWN := 0.2
const AUTO_FIRE_EVERY := 1.1     # no gunner: the turret helps a solo driver
const TURN_RATE := 5.0           # aim assist, radians per second
const HONK_COOLDOWN := 0.35
const SCARED_SECONDS := 2.0
const BLOOM_SECONDS := 3.0
const INVULN_SECONDS := 1.5
const BIG_STAR_FIRST := 20.0
const BIG_STAR_EVERY := 25.0
const BIG_STAR_VALUE := 10
const CELEBRATE_SECONDS := 2.5

# Sweetie 16, for placeholders and drawn UI.
const C_INK := Color("#1a1c2c")
const C_RED := Color("#b13e53")
const C_ORANGE := Color("#ef7d57")
const C_YELLOW := Color("#ffcd75")
const C_LIME := Color("#a7f070")
const C_GREEN := Color("#38b764")
const C_TEAL := Color("#257179")
const C_BLUE := Color("#41a6f6")
const C_CYAN := Color("#73eff7")
const C_WHITE := Color("#f4f4f4")
const C_GREY := Color("#94b0c2")
const C_SLATE := Color("#566c86")
const C_NAVY := Color("#333c57")
const CONFETTI_TINTS := [C_RED, C_ORANGE, C_YELLOW, C_LIME, C_CYAN, C_WHITE]

enum State { RUN, CELEBRATE, DONE }

var state := State.RUN
var paused := false
var time := 0.0
var run_len := Rules.DEFAULT_RUN_SECONDS
var stars := 0
## Stars already popped and flying to the tub (counted at the end anyway).
var pending := 0

var tub_pos := Vector2(80, 90)
var knock := Vector2.ZERO
var invuln := 0.0
var aim_dir := Vector2i.RIGHT
var fire_cd := 0.0
var honk_cd := 0.0
var bloom_t := 0.0
var shake_t := 0.0
var spawn_t := 1.5
var big_t := BIG_STAR_FIRST
var celebrate_t := 0.0
var confetti_t := 0.0
var scroll := 0.0

## {node, kind: "balloon"|"cloud", pos, vel, base_y, phase, scared}
var targets: Array[Dictionary] = []
## {node, pos, vel, dir0}
var bullets: Array[Dictionary] = []
## Collectible stars homing on the tub: {node, pos, vel, delay, age}
var floaters: Array[Dictionary] = []
## Decorative particles: {node, pos, vel, grav, life, max_life}
var fx: Array[Dictionary] = []
## The big moment, or {} when none is on screen: {node, glow, pos, t, collecting}
var big_star := {}

var rng := RandomNumberGenerator.new()

var world: Node2D
var bg_layer: Node2D
var ground_layer: Node2D
var mid_layer: Node2D
var fx_layer: Node2D
var tub: Node2D
var tub_sprite: AnimatedSprite2D
var turret: AnimatedSprite2D
var hills: Array[AnimatedSprite2D] = []
var ground_tiles: Array[AnimatedSprite2D] = []
var flowers: Array[AnimatedSprite2D] = []
var bg_clouds: Array[Dictionary] = []
var hud: Hud
var pause_overlay: PauseOverlay


func _ready() -> void:
	rng.randomize()
	run_len = Rules.run_length(Game.run_seconds)
	_build()
	Sfx.music("music_level")


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

func _build() -> void:
	world = Node2D.new()
	add_child(world)
	var sky := ColorRect.new()
	sky.size = Vector2(W + 8, 110)
	sky.position = Vector2(-4, -4)
	sky.color = C_BLUE
	world.add_child(sky)
	var sky_low := ColorRect.new()
	sky_low.size = Vector2(W + 8, H - 106)
	sky_low.position = Vector2(-4, 106)
	sky_low.color = C_CYAN
	world.add_child(sky_low)

	bg_layer = Node2D.new()
	world.add_child(bg_layer)
	for i in 5:
		var c := _spr("cloud_bg", C_WHITE, Vector2i(32, 16), bg_layer)
		c.modulate.a = 0.9
		bg_clouds.append({"node": c, "pos": Vector2(i * 72 + rng.randi_range(0, 30), rng.randi_range(22, 96)),
			"speed": rng.randf_range(10.0, 18.0)})
	var hw := Art.size_of("hills", Vector2i(320, 48))
	for i in 2:
		hills.append(_spr("hills", C_GREEN, Vector2i(320, 48), bg_layer))
	for h in hills:
		h.position.y = GROUND_Y - hw.y / 2

	ground_layer = Node2D.new()
	world.add_child(ground_layer)
	for i in W / 16 + 2:
		var g := _spr("ground", C_TEAL, Vector2i(16, 16), ground_layer)
		g.position.y = GROUND_Y + 8
		ground_tiles.append(g)
	for i in 12:
		var f := _spr("flower", C_ORANGE, Vector2i(8, 8), ground_layer)
		f.stop()
		f.frame = 0
		f.position = Vector2(i * 28 + rng.randi_range(0, 12), GROUND_Y - 4)
		flowers.append(f)

	mid_layer = Node2D.new()
	world.add_child(mid_layer)

	tub = Node2D.new()
	world.add_child(tub)
	var offsets := {HONKER: -14, GUNNER: 0, DRIVER: 14}
	for seat in [HONKER, GUNNER, DRIVER]:
		if not Players.is_seated(seat):
			continue
		var rider: String = Players.riders[seat]
		if rider == "":
			rider = Game.roster[seat % Game.roster.size()] if not Game.roster.is_empty() else "penguin"
		var r := Art.sprite(rider, Game.rider_color(rider), Vector2i(16, 16))
		r.position = Vector2(offsets[seat], -12)
		r.name = "Rider%d" % seat
		tub.add_child(r)
	tub_sprite = _spr("tub", C_WHITE, Vector2i(48, 24), tub)
	turret = _spr("turret", C_SLATE, Vector2i(8, 8), tub)
	turret.position = Vector2(27, -3)

	fx_layer = Node2D.new()
	world.add_child(fx_layer)

	hud = Hud.new()
	add_child(hud)
	var hud_star := _spr("star", C_YELLOW, Vector2i(8, 8), hud)
	hud_star.stop()
	hud_star.frame = 0
	hud_star.position = Vector2(10, 6)
	hud.star = hud_star

	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	add_child(pause_overlay)
	_place_nodes()


func _spr(sprite_name: String, tint: Color, size: Vector2i, parent: Node) -> AnimatedSprite2D:
	var s := Art.sprite(sprite_name, tint, size)
	parent.add_child(s)
	return s


# ================================================================ frame

func step(dt: float) -> void:
	if state == State.DONE:
		return
	if _pause_input():
		return
	time += dt
	scroll += dt
	fire_cd = maxf(0.0, fire_cd - dt)
	honk_cd = maxf(0.0, honk_cd - dt)
	invuln = maxf(0.0, invuln - dt)
	shake_t = maxf(0.0, shake_t - dt)
	bloom_t = maxf(0.0, bloom_t - dt)

	_move_tub(dt)
	_gunner(dt)
	if Players.just_pressed(HONKER, "any") and honk_cd <= 0.0:
		honk()

	if state == State.RUN:
		_spawner(dt)
		_big_star_timer(dt)
		if time >= run_len:
			_start_celebration()
	else:
		celebrate_t -= dt
		confetti_t -= dt
		if confetti_t <= 0.0:
			confetti_t = 0.15
			_confetti(Vector2(rng.randi_range(20, W - 20), rng.randi_range(20, 120)), 8)
		if celebrate_t <= 0.0:
			_finish()
			return

	_update_targets(dt)
	_update_bullets(dt)
	_update_big_star(dt)
	_update_floaters(dt)
	_update_fx(dt)
	_place_nodes()


## Pause belongs to the driver only. Returns true while paused.
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


func _back_to_join() -> void:
	state = State.DONE
	Players.reset()
	Game.goto("join")


func _move_tub(dt: float) -> void:
	tub_pos += Players.move(DRIVER) * TUB_SPEED * dt + knock * dt
	knock = knock.move_toward(Vector2.ZERO, 360.0 * dt)
	tub_pos.x = clampf(tub_pos.x, 26.0, W - 26.0)
	tub_pos.y = clampf(tub_pos.y, TOP_Y + 14.0, GROUND_Y - 14.0)
	for t in targets:
		if t.kind == "cloud" and t.scared <= 0.0 and invuln <= 0.0 \
				and Rules.overlap(tub_pos + Vector2(0, 2), TUB_HIT, t.pos, CLOUD_HIT):
			hit_tub(t)
	if big_star and not big_star.collecting and not Players.is_seated(HONKER) \
			and tub_pos.distance_to(big_star.pos) < 22.0:
		_collect_big_star()


func _gunner(_dt: float) -> void:
	if Players.is_seated(GUNNER):
		var d := Players.dir4(GUNNER)
		if d != Vector2i.ZERO:
			aim_dir = d
		if Players.pressed(GUNNER, "a") and fire_cd <= 0.0:
			fire()
	elif state == State.RUN and fire_cd <= 0.0:
		# Solo driver: the turret picks the nearest target and fires slowly.
		var best := -1
		var best_d := 200.0
		for i in targets.size():
			var dd := tub_pos.distance_to(_center(targets[i]))
			if dd < best_d and targets[i].pos.x < W - 8:
				best = i
				best_d = dd
		if best != -1:
			aim_dir = Aim.snap4(_center(targets[best]) - _muzzle_base())
			fire()
			fire_cd = AUTO_FIRE_EVERY


func _muzzle_base() -> Vector2:
	return tub_pos + turret.position


func fire() -> void:
	fire_cd = FIRE_COOLDOWN
	var d := Vector2(aim_dir)
	var b := _spr("bullet", C_YELLOW, Vector2i(6, 6), fx_layer)
	bullets.append({"node": b, "pos": _muzzle_base() + d * 6.0, "vel": d * BULLET_SPEED, "dir0": d})
	Sfx.play("shoot", rng.randf_range(0.95, 1.1), -4.0)


## The honker's button: always something delightful, never harmful.
func honk() -> void:
	honk_cd = HONK_COOLDOWN
	Sfx.play("honk", rng.randf_range(0.92, 1.1))
	shake_t = maxf(shake_t, 0.15)
	for i in rng.randi_range(4, 6):
		var bird := _spr("bird", C_NAVY, Vector2i(8, 8), fx_layer)
		bird.flip_h = rng.randf() < 0.5
		_add_fx(bird, Vector2(rng.randi_range(10, W - 10), GROUND_Y - 2),
			Vector2(rng.randf_range(-30, 30), rng.randf_range(-80, -50)), -10.0, 2.5)
	bloom_t = BLOOM_SECONDS
	for t in targets:
		if t.kind == "cloud":
			scare(t)
	if rng.randf() < 0.5:
		var heart := _spr("heart", C_RED, Vector2i(8, 8), fx_layer)
		_add_fx(heart, tub_pos + Vector2(-14, -22), Vector2(rng.randf_range(-8, 8), -30), 0.0, 1.0)
	else:
		var note := Note.new()
		note.color = [C_WHITE, C_YELLOW, C_LIME][rng.randi() % 3]
		fx_layer.add_child(note)
		_add_fx(note, tub_pos + Vector2(-14, -22), Vector2(rng.randf_range(-12, 12), -30), 0.0, 1.0)
	if big_star and not big_star.collecting and big_star.pos.x < W + 4 and big_star.pos.x > -4:
		_collect_big_star()


func scare(t: Dictionary) -> void:
	if t.scared <= 0.0:
		t.node.sprite_frames = Art.frames("cloud_scared", C_GREY, Vector2i(24, 16))
		t.node.play("default")
	t.scared = SCARED_SECONDS
	t.vel = Vector2(rng.randf_range(28, 40), rng.randf_range(-22, -12))


func _unscare(t: Dictionary) -> void:
	t.node.sprite_frames = Art.frames("cloud_grump", C_SLATE, Vector2i(24, 16))
	t.node.play("default")
	t.vel = Vector2(-rng.randf_range(16, 26), 0)


## A grumpy cloud bumped the tub: bounce, flash, a heart, lose up to 3 stars.
func hit_tub(cloud: Dictionary) -> void:
	if invuln > 0.0:
		return
	var lost := stars - Rules.stars_after_hit(stars)
	stars -= lost
	invuln = INVULN_SECONDS
	var away := signf(tub_pos.x - cloud.pos.x)
	knock = Vector2((away if away != 0.0 else -1.0) * 150.0, signf(tub_pos.y - cloud.pos.y) * 60.0)
	cloud.vel = Vector2(-away * 30.0, 0) if away != 0.0 else cloud.vel
	shake_t = maxf(shake_t, 0.25)
	var heart := _spr("heart", C_RED, Vector2i(8, 8), fx_layer)
	_add_fx(heart, tub_pos + Vector2(0, -20), Vector2(0, -40), 0.0, 0.9)
	for i in lost:
		var s := _spr("star", C_YELLOW, Vector2i(8, 8), fx_layer)
		_add_fx(s, tub_pos, Vector2(rng.randf_range(-50, 50), rng.randf_range(-110, -70)), 320.0, 1.0)
	Sfx.play("hit")


# ================================================================ spawning

func _spawner(dt: float) -> void:
	spawn_t -= dt
	if spawn_t > 0.0:
		return
	spawn_t = Rules.spawn_interval(time, run_len) * rng.randf_range(0.8, 1.2)
	var y := rng.randf_range(TOP_Y + 20.0, GROUND_Y - 26.0)
	if rng.randf() < Rules.cloud_chance(time, run_len):
		spawn_cloud(Vector2(W + 20, y))
	else:
		spawn_balloon(Vector2(W + 16, y))


func spawn_cloud(at: Vector2) -> Dictionary:
	var n := _spr("cloud_grump", C_SLATE, Vector2i(24, 16), mid_layer)
	var t := {"node": n, "kind": "cloud", "pos": at, "vel": Vector2(-rng.randf_range(16, 26), 0),
		"base_y": at.y, "phase": rng.randf() * TAU, "scared": 0.0}
	targets.append(t)
	return t


func spawn_balloon(at: Vector2) -> Dictionary:
	var tints := [C_RED, C_ORANGE, C_LIME, C_CYAN]
	var n := _spr("balloon", tints[rng.randi() % tints.size()], Vector2i(16, 24), mid_layer)
	var t := {"node": n, "kind": "balloon", "pos": at, "vel": Vector2(-rng.randf_range(22, 34), 0),
		"base_y": at.y, "phase": rng.randf() * TAU, "scared": 0.0}
	targets.append(t)
	return t


func _big_star_timer(dt: float) -> void:
	big_t -= dt
	if big_t > 0.0 or big_star:
		return
	big_t = BIG_STAR_EVERY
	spawn_big_star()


func spawn_big_star() -> void:
	var glow := Glow.new()
	mid_layer.add_child(glow)
	var n := _spr("big_star", C_YELLOW, Vector2i(24, 24), mid_layer)
	big_star = {"node": n, "glow": glow, "pos": Vector2(W + 20, 56), "t": 0.0, "collecting": false}
	Sfx.play("whoosh", 1.2, -6.0)


func _collect_big_star() -> void:
	big_star.collecting = true
	Sfx.play("star", 1.5)


# ================================================================ updates

func _center(t: Dictionary) -> Vector2:
	return t.pos + (Vector2(0, -4) if t.kind == "balloon" else Vector2.ZERO)


func _update_targets(dt: float) -> void:
	for i in range(targets.size() - 1, -1, -1):
		var t := targets[i]
		t.phase += dt
		if t.kind == "balloon":
			t.base_y += t.vel.y * dt
			t.pos = Vector2(t.pos.x + t.vel.x * dt, t.base_y + sin(t.phase * 2.0) * 6.0)
		else:
			if t.scared > 0.0:
				t.scared -= dt
				if t.scared <= 0.0 and state == State.RUN:
					_unscare(t)
			else:
				t.vel.y = clampf(tub_pos.y - t.pos.y, -8.0, 8.0)
			t.pos += t.vel * dt
		if t.pos.x < -30 or t.pos.x > W + 40 or t.pos.y < -30 or t.pos.y > H + 20:
			t.node.queue_free()
			targets.remove_at(i)


func _update_bullets(dt: float) -> void:
	for i in range(bullets.size() - 1, -1, -1):
		var b := bullets[i]
		var centers := []
		for t in targets:
			centers.append(_center(t))
		var pick := Aim.pick_target(b.pos, b.dir0, centers)
		if pick != -1:
			b.vel = Aim.steer(b.vel, b.pos, centers[pick], TURN_RATE * dt)
		b.pos += b.vel * dt
		var hit := -1
		for j in targets.size():
			var r := 10.0 if targets[j].kind == "balloon" else 12.0
			if b.pos.distance_to(centers[j]) < r:
				hit = j
				break
		if hit != -1:
			pop(targets[hit])
			b.node.queue_free()
			bullets.remove_at(i)
		elif b.pos.x < -8 or b.pos.x > W + 8 or b.pos.y < -8 or b.pos.y > H + 8:
			b.node.queue_free()
			bullets.remove_at(i)


## A balloon or a cloud pops: confetti plus 1-3 stars flying to the tub.
func pop(t: Dictionary) -> void:
	var at := _center(t)
	Sfx.play("pop", rng.randf_range(0.9, 1.15))
	_confetti(at, 10)
	for k in rng.randi_range(1, 3):
		spawn_star(at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(40, 70))
	t.node.queue_free()
	targets.erase(t)


func spawn_star(at: Vector2, burst: Vector2, delay := 0.35) -> void:
	var n := _spr("star", C_YELLOW, Vector2i(8, 8), fx_layer)
	floaters.append({"node": n, "pos": at, "vel": burst, "delay": delay, "age": 0.0})
	pending += 1


func _update_floaters(dt: float) -> void:
	for i in range(floaters.size() - 1, -1, -1):
		var f := floaters[i]
		f.age += dt
		if f.delay > 0.0:
			f.delay -= dt
			f.vel *= pow(0.02, dt)
		else:
			var to: Vector2 = tub_pos + Vector2(0, -6) - f.pos
			var speed := minf(80.0 + f.age * 240.0, 320.0)
			f.vel = f.vel.lerp(to.normalized() * speed, minf(1.0, 8.0 * dt))
			if to.length() < 10.0:
				stars += 1
				pending -= 1
				hud.bump = 0.12
				Sfx.play("star", 1.0 + 0.06 * (stars % 8), -4.0)
				f.node.queue_free()
				floaters.remove_at(i)
				continue
		f.pos += f.vel * dt


func _update_big_star(dt: float) -> void:
	if not big_star:
		return
	big_star.t += dt
	if big_star.collecting:
		var to: Vector2 = tub_pos + Vector2(0, -8) - big_star.pos
		big_star.pos += to.normalized() * minf(to.length(), 220.0 * dt)
		if to.length() < 6.0:
			var at: Vector2 = big_star.pos
			Sfx.play("bigstar")
			shake_t = maxf(shake_t, 0.3)
			_confetti(at, 24)
			for k in BIG_STAR_VALUE:
				spawn_star(at, Vector2.from_angle(TAU * k / BIG_STAR_VALUE) * 90.0, 0.4)
			_drop_big_star()
			return
	else:
		big_star.pos = Vector2(big_star.pos.x - 24.0 * dt, 56.0 + sin(big_star.t * 1.6) * 12.0)
		if big_star.pos.x < -24:
			_drop_big_star()
			return
	big_star.glow.pulse = big_star.t


func _drop_big_star() -> void:
	big_star.node.queue_free()
	big_star.glow.queue_free()
	big_star = {}


func _confetti(at: Vector2, count: int) -> void:
	for i in count:
		var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
		var c := _spr("confetti", tint, Vector2i(4, 4), fx_layer)
		c.stop()
		c.frame = rng.randi() % 6
		_add_fx(c, at, Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(30, 90) + Vector2(0, -30),
			160.0, rng.randf_range(0.7, 1.2))


func _add_fx(node: Node2D, at: Vector2, vel: Vector2, grav: float, life: float) -> void:
	fx.append({"node": node, "pos": at, "vel": vel, "grav": grav, "life": life, "max_life": life})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var p := fx[i]
		p.life -= dt
		p.vel.y += p.grav * dt
		p.pos += p.vel * dt
		if p.life <= 0.0 or p.pos.y > H + 10 or p.pos.y < -20:
			p.node.queue_free()
			fx.remove_at(i)
		elif p.life < 0.3:
			p.node.visible = int(p.life * 20.0) % 2 == 0


func _start_celebration() -> void:
	state = State.CELEBRATE
	celebrate_t = CELEBRATE_SECONDS
	Sfx.play("whoosh")
	for t in targets.duplicate():
		if t.kind == "balloon":
			pop(t)
		else:
			scare(t)
			t.scared = 99.0
	if big_star and not big_star.collecting:
		_collect_big_star()


func _finish() -> void:
	state = State.DONE
	Game.stars = stars + pending + (BIG_STAR_VALUE if big_star else 0)
	Game.goto("party")


# ================================================================ drawing

func _place_nodes() -> void:
	world.position = Vector2(rng.randi_range(-2, 2), rng.randi_range(-1, 1)) if shake_t > 0.0 else Vector2.ZERO
	# Parallax: hills slow, clouds medium, ground fast.
	var hw := float(Art.size_of("hills", Vector2i(320, 48)).x)
	var hx := fmod(scroll * 8.0, hw)
	for i in hills.size():
		hills[i].position.x = roundf(i * hw - hx + hw * 0.5)
	var gx := fmod(scroll * 40.0, 16.0)
	for i in ground_tiles.size():
		ground_tiles[i].position.x = roundf(i * 16 - gx + 8)
	var span := 12 * 28.0
	for i in flowers.size():
		var fl := flowers[i]
		var base := float(i * 28 + (i * 7) % 12)
		fl.position.x = roundf(fposmod(base - scroll * 40.0, span) - 8.0)
		var open := bloom_t > 0.0
		fl.frame = 1 if open else 0
		fl.position.y = GROUND_Y - 4 - (1 if open else 0)
		if fl.sprite_frames.get_frame_count("default") < 2:
			fl.modulate = Color(1.6, 1.4, 0.6) if open else Color.WHITE
	for c in bg_clouds:
		var cx := fposmod(c.pos.x - scroll * c.speed + 40.0, W + 80.0) - 40.0
		c.node.position = Vector2(roundf(cx), c.pos.y)

	var bob := 1.0 if fmod(time, 0.8) < 0.4 else 0.0
	tub.position = (tub_pos + Vector2(0, bob)).round()
	tub.visible = invuln <= 0.0 or int(invuln * 10.0) % 2 == 0
	turret.rotation = Aim.angle_of(aim_dir)
	for t in targets:
		t.node.position = t.pos.round()
	for b in bullets:
		b.node.position = b.pos.round()
	for f in floaters:
		f.node.position = f.pos.round()
	for p in fx:
		p.node.position = p.pos.round()
	if big_star:
		big_star.node.position = big_star.pos.round()
		big_star.glow.position = big_star.pos.round()
	hud.progress = clampf(time / run_len, 0.0, 1.0)
	hud.tick(get_process_delta_time())


## Progress bar (tub icon travelling to a flag) plus a star that pops on collect.
class Hud extends Node2D:
	var progress := 0.0
	var bump := 0.0
	var star: AnimatedSprite2D
	var _last := -1

	func tick(dt: float) -> void:
		bump = maxf(0.0, bump - dt)
		if star:
			star.position = Vector2(10, 6 - (2 if bump > 0.0 else 0))
		var px := int(roundf(progress * 244.0))
		if px != _last:
			_last = px
			queue_redraw()

	func _draw() -> void:
		var x0 := 30
		var x1 := 280
		draw_rect(Rect2(x0 - 1, 3, x1 - x0 + 2, 4), Color("#333c57"))
		draw_rect(Rect2(x0, 4, int(roundf(progress * (x1 - x0))), 2), Color("#ffcd75"))
		# flag at the end
		draw_rect(Rect2(x1 + 4, 1, 1, 9), Color("#f4f4f4"))
		draw_rect(Rect2(x1 + 5, 1, 5, 2), Color("#b13e53"))
		draw_rect(Rect2(x1 + 5, 3, 3, 2), Color("#b13e53"))
		# tiny tub
		var tx := x0 + int(roundf(progress * (x1 - x0))) - 4
		draw_rect(Rect2(tx, 3, 9, 4), Color("#f4f4f4"))
		draw_rect(Rect2(tx + 1, 7, 1, 1), Color("#f4f4f4"))
		draw_rect(Rect2(tx + 7, 7, 1, 1), Color("#f4f4f4"))
		draw_rect(Rect2(tx + 2, 2, 2, 1), Color("#41a6f6"))


## Dimmed pause screen: a back arrow (driver "b") and a play triangle ("a"/start).
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.1, 0.11, 0.17, 0.7))
		draw_circle(Vector2(110, 90), 22, Color("#b13e53"))
		draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
			Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#f4f4f4"))
		draw_circle(Vector2(210, 90), 26, Color("#38b764"))
		draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
			Color("#f4f4f4"))


## Soft pulsing glow behind the big star.
class Glow extends Node2D:
	var pulse := 0.0:
		set(v):
			pulse = v
			queue_redraw()

	func _draw() -> void:
		var r := 16 + (2 if fmod(pulse, 0.6) < 0.3 else 0)
		draw_circle(Vector2.ZERO, r + 4, Color(1.0, 0.95, 0.6, 0.18))
		draw_circle(Vector2.ZERO, r, Color(1.0, 0.95, 0.6, 0.35))


## A little music note (no sprite for it in the art contract).
class Note extends Node2D:
	var color := Color("#f4f4f4")

	func _draw() -> void:
		draw_rect(Rect2(-3, 1, 3, 3), color)
		draw_rect(Rect2(-1, -5, 1, 7), color)
		draw_rect(Rect2(0, -5, 3, 1), color)
		draw_rect(Rect2(2, -4, 1, 2), color)
