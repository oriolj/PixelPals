extends Node2D
## The dive: a yellow submarine explores a 4x2-screen reef for 6 minutes.
## Pilot swims and pings the sonar, Camera points the viewfinder and snaps
## photos into the album, Lights flashes the sub's lights. No game over:
## rocks only boing, an empty snap photographs a bonus subject.
##
## All logic lives in step(dt) so tests drive it frame by frame with
## set_process(false) and scripted devices. Built entirely in code.

const Species := preload("res://scripts/level/species.gd")
const ReefMap := preload("res://scripts/level/reef.gd")
const Creatures := preload("res://scripts/level/creatures.gd")
const Viewfinder := preload("res://scripts/level/viewfinder.gd")
const SubMotion := preload("res://scripts/level/sub_motion.gd")
const Lights := preload("res://scripts/level/lights.gd")
const Rules := preload("res://scripts/level/rules.gd")
const AudioLoop := preload("res://scripts/audio_loop.gd")

const W := 320
const H := 180
const STRIP_H := 22
const VIEW := Vector2(320, 158)       # the world shows above the album strip
const DRIVER := 0
const GUNNER := 1
const HONKER := 2

const SONAR_COOLDOWN := 1.2
const SONAR_SECONDS := 1.0
const SONAR_RADIUS := 170.0
const REVEAL_SECONDS := 3.0
const SNAP_COOLDOWN := 0.35
const AUTO_SNAP_SECONDS := 1.0
const AIM_IDLE_RETURN := 3.0
const BUMP_SPEED := 22.0
const BUMP_COOLDOWN := 0.5
const SPIN_SECONDS := 0.4
const SHY_NEAR := 68.0                # 3 tiles from the sub's side
const FLASH_SECONDS := 0.09           # 3 frames at 30 fps: TV comfort
const SCREEN_FLASH_SECONDS := 0.067   # 2 frames
const POLAROID_POP := 0.25
const POLAROID_FLY := 0.6
const END_BUBBLES := 1.2
const END_SUNSET := 3.2

# Endesga 32 colours for drawn things.
const C_INK := Color("#181425")
const C_NAVY := Color("#262b44")
const C_SLATE := Color("#3a4466")
const C_DEEP := Color("#124e89")
const C_BLUE := Color("#0099db")
const C_CYAN := Color("#2ce8f5")
const C_WHITE := Color("#ffffff")
const C_PALE := Color("#c0cbdc")
const C_YELLOW := Color("#feae34")
const C_LEMON := Color("#fee761")
const C_PINK := Color("#f6757a")
const C_ORANGE := Color("#f77622")
const C_RED := Color("#e43b44")
const C_PURPLE := Color("#68386c")
const C_GREEN := Color("#63c74d")

enum State { RUN, END_BUBBLES, SUNSET, DONE }

var state := State.RUN
var paused := false
var time := 0.0
var run_len := Rules.RUN_SECONDS
var end_t := 0.0

var reef: ReefMap
var creatures: Array = []           # Creatures.Creature, page species then the whale
var by_id := {}
var whale

var sub_pos := Vector2(90, 64)
var sub_vel := Vector2.ZERO
var facing := 1
var spin_t := 0.0
var bump_cd := 0.0
var bumps := 0
var _was_moving := false

var view_dir := Vector2i.RIGHT
var frame_off := Vector2(52, 0)
var frame_pos := Vector2.ZERO
var locked := false
var aim_idle := 0.0
var snap_cd := 0.0
var in_frame_t := 0.0
var snaps := 0
var bonus_n := 0

var lights := Lights.State.new()
var flashes := 0
var sonar_cd := 0.0
var sonar_rings: Array[Dictionary] = []   # {pos, t}
var reveal_t := 0.0
var glow_rings: Array[Dictionary] = []    # {pos, t, color}
var last_new_t := 0.0
var trail_target := ""

var flash_t := 0.0
var screen_flash_t := 0.0
var cam := Vector2.ZERO
var polaroids: Array[Dictionary] = []     # {node, from, to, t, id, is_new}
var revealed := {}                          # species shown in colour on the strip
var fx_bubbles: Array[Dictionary] = []    # {pos, vel, life}
var rng := RandomNumberGenerator.new()

# nodes
var world: Node2D
var ambient: CanvasModulate
var bg: WaterBg
var tiles: ReefTiles
var decor_layer: Node2D
var creature_layer: Node2D
var fx_draw: FxDraw
var sub_node: Node2D
var sub_sprite: AnimatedSprite2D
var head_light: PointLight2D
var glow_light: PointLight2D
var bubbles: CPUParticles2D
var viewfinder: AnimatedSprite2D
var flash_sprite: AnimatedSprite2D
var bonus_sprite: AnimatedSprite2D
var bonus_t := 0.0
var pearls: Array[AnimatedSprite2D] = []
var sprites := {}                           # id -> AnimatedSprite2D
var hud: Hud
var pause_layer: CanvasLayer
var music: AudioStreamPlayer
var hum: AudioStreamPlayer

static var _unshaded: CanvasItemMaterial
static var _additive: CanvasItemMaterial
static var _radial_tex: ImageTexture
static var _cone_tex: ImageTexture


func _ready() -> void:
	rng.seed = 7
	run_len = Rules.run_length(Game.run_seconds)
	Game.new_session()
	reef = ReefMap.new()
	reef.load_file(ReefMap.PATH)
	sub_pos = reef.sub_start
	for id in Species.PAGE:
		var c = Creatures.make(id, reef.homes.get(id, Vector2(640, 180)))
		creatures.append(c)
		by_id[id] = c
		if Game.album.has(id):
			revealed[id] = true
	whale = Creatures.make(Species.WHALE, Vector2(-100, Creatures.WHALE_Y))
	creatures.append(whale)
	by_id[Species.WHALE] = whale
	if Game.album.has(Species.WHALE):
		revealed[Species.WHALE] = true
	_build()
	frame_pos = sub_pos + frame_off
	_update_camera(1.0, true)
	_place_nodes()
	Sfx.stop_music()
	music = AudioLoop.looping(self, "music_reef", -8.0, AudioLoop.MUSIC_BUS if AudioLoop.music_bus() >= 0 else "Master")
	hum = AudioLoop.looping(self, "sub_hum_loop", -22.0)


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

static func materials() -> void:
	if _unshaded == null:
		_unshaded = CanvasItemMaterial.new()
		_unshaded.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive = CanvasItemMaterial.new()
		_additive.light_mode = CanvasItemMaterial.LIGHT_MODE_UNSHADED
		_additive.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
		_radial_tex = ImageTexture.create_from_image(Lights.radial_image(56))
		_cone_tex = ImageTexture.create_from_image(Lights.cone_image(112, 36))


func _build() -> void:
	materials()
	ambient = CanvasModulate.new()
	add_child(ambient)
	world = Node2D.new()
	add_child(world)
	bg = WaterBg.new()
	bg.level = self
	world.add_child(bg)
	tiles = ReefTiles.new()
	tiles.reef = reef
	world.add_child(tiles)
	decor_layer = Node2D.new()
	world.add_child(decor_layer)
	_build_decor()
	creature_layer = Node2D.new()
	world.add_child(creature_layer)
	for c in creatures:
		var s := _spr(c.id, Species.tint(c.id), Species.size_of(c.id), creature_layer)
		s.visible = c.shown > 0.05
		sprites[c.id] = s
	for i in 6:
		var p := _spr("pearl", C_PALE, Vector2i(6, 6), world)
		p.material = _unshaded
		p.visible = false
		pearls.append(p)

	sub_node = Node2D.new()
	world.add_child(sub_node)
	bubbles = CPUParticles2D.new()
	bubbles.texture = Art.frames("bubble_small", C_PALE, Vector2i(4, 4)).get_frame_texture("default", 0)
	bubbles.amount = 12
	bubbles.lifetime = 1.6
	bubbles.local_coords = false
	bubbles.direction = Vector2(-1, -0.3)
	bubbles.spread = 25.0
	bubbles.initial_velocity_min = 10.0
	bubbles.initial_velocity_max = 22.0
	bubbles.gravity = Vector2(0, -26)
	bubbles.emitting = false
	bubbles.material = _unshaded
	sub_node.add_child(bubbles)
	sub_sprite = _spr("sub", C_YELLOW, Vector2i(40, 24), sub_node)
	sub_sprite.material = _unshaded  # the sub carries its own lights: always readable
	head_light = PointLight2D.new()
	head_light.texture = _cone_tex
	head_light.offset = Vector2(56, 0)
	head_light.energy = 1.1
	head_light.color = Color("#fff4d0")
	head_light.position = Vector2(14, 1)
	sub_node.add_child(head_light)
	glow_light = PointLight2D.new()
	glow_light.texture = _radial_tex
	glow_light.energy = 0.7
	glow_light.color = Lights.COLORS[0]
	sub_node.add_child(glow_light)

	fx_draw = FxDraw.new()
	fx_draw.level = self
	fx_draw.material = _unshaded
	world.add_child(fx_draw)
	viewfinder = _spr("viewfinder", C_WHITE, Vector2i(48, 40), world)
	viewfinder.stop()
	viewfinder.material = _unshaded
	flash_sprite = _spr("flash", C_WHITE, Vector2i(64, 64), world)
	flash_sprite.stop()
	flash_sprite.material = _additive
	flash_sprite.visible = false
	bonus_sprite = _spr("bubble", C_PALE, Vector2i(8, 8), world)
	bonus_sprite.material = _unshaded
	bonus_sprite.visible = false

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 1
	add_child(hud_layer)
	hud = Hud.new()
	hud.level = self
	hud_layer.add_child(hud)
	pause_layer = CanvasLayer.new()
	pause_layer.layer = 2
	pause_layer.visible = false
	add_child(pause_layer)
	pause_layer.add_child(PauseOverlay.new())


func _build_decor() -> void:
	var wr: Array = reef.decor.get("wreck", [96, 272])
	var wreck := _spr("wreck", C_SLATE, Vector2i(96, 48), decor_layer)
	wreck.centered = false
	wreck.position = Vector2(wr[0], wr[1])
	for a in reef.decor.get("anemone", []):
		var an := _spr("anemone", C_PINK, Vector2i(16, 16), decor_layer)
		an.position = Vector2(a[0] * 16 + 8, a[1] * 16 + 8)
	for k in reef.decor.get("kelp", []):
		var n := int(k[2])
		for i in n:
			var name := "kelp_top" if i == n - 1 else "kelp"
			var s := _spr(name, C_GREEN, Vector2i(16, 16), decor_layer)
			s.position = Vector2(k[0] * 16 + 8, (k[1] - i) * 16 + 8)
			s.frame = (i + int(k[0])) % 2
			s.speed_scale = 0.8 + 0.1 * (int(k[0]) % 3)


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
	Lights.step(lights, dt)
	sonar_cd = maxf(0.0, sonar_cd - dt)
	snap_cd = maxf(0.0, snap_cd - dt)
	bump_cd = maxf(0.0, bump_cd - dt)
	spin_t = maxf(0.0, spin_t - dt)
	reveal_t = maxf(0.0, reveal_t - dt)
	flash_t = maxf(0.0, flash_t - dt)
	screen_flash_t = maxf(0.0, screen_flash_t - dt)
	bonus_t = maxf(0.0, bonus_t - dt)
	match state:
		State.RUN:
			_drive(dt)
			_camera_seat(dt)
			_lights_seat(dt)
			_whale_check()
			_trail()
			if Rules.should_end(time, run_len, Game.session.seen.size()):
				_start_end()
		State.END_BUBBLES, State.SUNSET:
			_ending(dt)
	for c in creatures:
		Creatures.step(c, dt, lights.lights_on())
	_puffer_near()
	_update_fx(dt)
	_update_polaroids(dt)
	_update_camera(dt)
	_update_audio()
	_place_nodes()
	hud.queue_redraw()
	fx_draw.queue_redraw()


## Pause belongs to the driver. Returns true while paused.
func _pause_input() -> bool:
	if Players.just_pressed(DRIVER, "start") and state == State.RUN:
		set_paused(not paused)
		return true
	if paused and Players.just_pressed(DRIVER, "b"):
		set_paused(false)
		Sfx.play("select")
		state = State.DONE
		Game.goto.call_deferred("join")
		return true
	return paused


func set_paused(on: bool) -> void:
	paused = on
	pause_layer.visible = on
	Sfx.play("select")


# ================================================================ pilot

func _drive(dt: float) -> void:
	var input := Players.move(DRIVER)
	var moving := input.length() > 0.3
	if moving and not _was_moving:
		Sfx.play("propeller", 1.0 + rng.randf_range(-0.05, 0.05), -6.0)
	_was_moving = moving
	sub_vel = SubMotion.accelerate(sub_vel, input, dt)
	move_sub(dt)
	if Players.just_pressed(DRIVER, "a"):
		sonar()


## Moves the sub by its velocity plus the current; a rock bounces it.
func move_sub(dt: float) -> void:
	sub_vel += SubMotion.current(sub_pos) * dt
	var next := sub_pos + sub_vel * dt
	if reef.rect_hits(next, SubMotion.HIT):
		var speed := sub_vel.length()
		if speed >= BUMP_SPEED and bump_cd <= 0.0:
			bump()
		else:
			# Slow contact: slide along the rock.
			var nx := Vector2(next.x, sub_pos.y)
			var ny := Vector2(sub_pos.x, next.y)
			if not reef.rect_hits(nx, SubMotion.HIT):
				sub_pos = nx
				sub_vel.y = 0.0
			elif not reef.rect_hits(ny, SubMotion.HIT):
				sub_pos = ny
				sub_vel.x = 0.0
			else:
				sub_vel = sub_vel * 0.5
	else:
		sub_pos = next
	sub_pos = SubMotion.clamp_outer(sub_pos)
	if sub_vel.x > 8.0:
		facing = 1
	elif sub_vel.x < -8.0:
		facing = -1


## A rock bump: boing, a spin in quarter turns and bubbles. Nothing is lost.
func bump() -> void:
	sub_vel = SubMotion.bounce(sub_vel)
	bump_cd = BUMP_COOLDOWN
	spin_t = SPIN_SECONDS
	bumps += 1
	Sfx.play("boing", rng.randf_range(0.95, 1.05))
	_burst_bubbles(sub_pos, 8)


func sonar() -> void:
	if sonar_cd > 0.0:
		return
	sonar_cd = SONAR_COOLDOWN
	sonar_rings.append({"pos": sub_pos, "t": 0.0})
	reveal_t = REVEAL_SECONDS
	Sfx.play("sonar")
	for id in Creatures.sonar(creatures, sub_pos):
		if id == "eel":
			Sfx.play("eel_peek")
		else:
			Sfx.play("bubble", 1.2)


# ================================================================ camera seat

func _camera_seat(dt: float) -> void:
	var has_gunner := Players.is_seated(GUNNER)
	if has_gunner:
		var d := Players.dir4(GUNNER)
		if d != Vector2i.ZERO:
			view_dir = d
			aim_idle = 0.0
		else:
			aim_idle += dt
			# Left alone for a while, the frame follows the sub's nose.
			if aim_idle >= AIM_IDLE_RETURN and view_dir.y == 0:
				view_dir = Vector2i(facing, 0)
	else:
		view_dir = _auto_dir()
	var targets := photo_targets()
	var base := Viewfinder.base_center(sub_pos, view_dir)
	var goal := Viewfinder.goal(base, targets)
	frame_off = Viewfinder.slide(sub_pos + frame_off, goal, dt) - sub_pos
	frame_pos = sub_pos + frame_off
	var subject = subject_in_frame()
	locked = subject != null
	if has_gunner:
		if Players.just_pressed(GUNNER, "a"):
			snap()
	else:
		# One-seat helper: a new subject held in the frame for 1 s is snapped.
		if subject != null and not Game.session.seen.has(subject.id) and not (subject.id == Species.WHALE and Game.session.whale):
			in_frame_t += dt
			if in_frame_t >= AUTO_SNAP_SECONDS:
				in_frame_t = 0.0
				snap()
		else:
			in_frame_t = 0.0


## Nobody on the camera: point at the nearest subject not yet photographed.
func _auto_dir() -> Vector2i:
	var best := Vector2i(facing, 0)
	var best_d := 110.0
	for c in creatures:
		if not c.photographable() or Game.session.seen.has(c.id):
			continue
		var d: float = c.pos.distance_to(sub_pos)
		if d < best_d:
			best_d = d
			var v: Vector2 = c.pos - sub_pos
			best = Vector2i(int(signf(v.x)), 0) if absf(v.x) >= absf(v.y) else Vector2i(0, int(signf(v.y)))
	return best


func photo_targets() -> Array:
	var out := []
	for c in creatures:
		if c.photographable():
			out.append(c.pos)
	return out


func frame_rect() -> Rect2:
	return Viewfinder.rect_at(frame_pos)


## The creature a snap would photograph now (null if none): one not yet seen
## this run first, then the best centred.
func subject_in_frame():
	var r := frame_rect()
	var best = null
	var best_key := -1.0
	for c in creatures:
		if not c.photographable() or not Viewfinder.contains(r, c.rect()):
			continue
		var key: float = Viewfinder.score(r, c.rect()) + (2.0 if not Game.session.seen.has(c.id) else 0.0)
		if key > best_key:
			best_key = key
			best = c
	return best


## Snap: flash and shutter at once; the subject (or a bonus) becomes a polaroid.
func snap() -> void:
	if snap_cd > 0.0 or state != State.RUN:
		return
	snap_cd = SNAP_COOLDOWN
	snaps += 1
	flash_t = FLASH_SECONDS
	screen_flash_t = SCREEN_FLASH_SECONDS
	flash_sprite.frame = 0
	Sfx.play("shutter")
	var subject = subject_in_frame()
	if subject != null:
		photograph(subject)
	else:
		photograph_bonus()


func photograph(c) -> void:
	var r := frame_rect()
	var score := Viewfinder.score(r, c.rect())
	var is_new: bool = Game.album.record(c.id, score, sprites[c.id].frame)
	var s: Dictionary = Game.session
	if c.id == Species.WHALE:
		s.whale = true
		if not is_new:
			s.repeats[c.id] = int(s.repeats.get(c.id, 0)) + 1
	elif is_new:
		s.new.append(c.id)
	else:
		s.repeats[c.id] = int(s.repeats.get(c.id, 0)) + 1
	if not s.seen.has(c.id) and c.id != Species.WHALE:
		s.seen.append(c.id)
		last_new_t = time
	c.glow = 1.0
	Game.album.save()
	_launch_polaroid(c.id, is_new)


func photograph_bonus() -> void:
	var kind := Rules.bonus_subject(reef.near_rock(frame_pos), reef.near_sand(frame_pos), bonus_n)
	bonus_n += 1
	Game.album.add_bonus(kind)
	Game.session.bonus[kind] = int(Game.session.bonus.get(kind, 0)) + 1
	Game.album.save()
	bonus_sprite.sprite_frames = Art.frames(kind, C_PALE, Vector2i(12, 12))
	bonus_sprite.play("default")
	bonus_sprite.position = frame_pos.round()
	bonus_t = 1.0
	_launch_polaroid(kind, false)


# ================================================================ lights seat

func _lights_seat(dt: float) -> void:
	if Players.is_seated(HONKER):
		if Players.just_pressed(HONKER, "any"):
			press_lights()
	else:
		if Lights.auto_tick(lights, dt, _shy_near()):
			_flash_effects(false)


func _shy_near() -> bool:
	for c in creatures:
		if Species.is_shy(c.id) and not c.photographable() and c.home.distance_to(sub_pos) <= SHY_NEAR:
			return true
		if Species.kind(c.id) == Species.Kind.LIGHT and c.home.distance_to(sub_pos) <= SHY_NEAR:
			return true
	return false


## The toddler's press: a flash in the next colour (with a short cooldown);
## a press inside the cooldown still blows a few bubbles.
func press_lights() -> void:
	var res := Lights.press(lights)
	if not res.flashed:
		_burst_bubbles(sub_pos + Vector2(-facing * 16, 0), 3)
		return
	_flash_effects(res.disco)


func _flash_effects(disco: bool) -> void:
	flashes += 1
	var col: Color = Lights.COLORS[maxi(lights.color, 0)]
	glow_light.color = col
	glow_rings.append({"pos": sub_pos, "t": 0.0, "color": col})
	Sfx.play("lights_%d" % (maxi(lights.color, 0) + 1))
	for id in Creatures.flash(creatures, sub_pos):
		if id == "eel":
			Sfx.play("eel_peek")
	if disco:
		Creatures.disco(creatures, Rect2(cam.round(), VIEW))
		Sfx.play("disco")
		_burst_bubbles(sub_pos, 16)


func _puffer_near() -> void:
	var p = by_id.get("pufferfish")
	if p and p.puffed <= 0.0 and p.pos.distance_to(sub_pos) < 36.0:
		p.puffed = Creatures.PUFF_SECONDS
		Sfx.play("puff")
	elif p and p.puffed > Creatures.PUFF_SECONDS - 0.02:
		pass


# ================================================================ whale, trail, end

func _whale_check() -> void:
	if whale.state == Creatures.State.WAIT and Rules.whale_due(time, run_len, sub_pos.y):
		Creatures.start_whale(whale, sub_pos.x)
		Sfx.play("whale_song")


func _trail() -> void:
	trail_target = ""
	if time - last_new_t >= Rules.PEARL_AFTER:
		trail_target = Rules.trail_target(sub_pos, reef.homes, Game.session.seen)


func _start_end() -> void:
	state = State.END_BUBBLES
	end_t = 0.0
	sub_vel = Vector2.ZERO
	Sfx.play("bubble", 0.8)


func _ending(dt: float) -> void:
	end_t += dt
	if state == State.END_BUBBLES:
		if end_t >= END_BUBBLES * 0.5 and sub_pos.y > 40.0:
			# Behind the bubble curtain the sub pops up to the surface.
			sub_pos = Vector2(clampf(sub_pos.x, 40.0, 1240.0), 30.0)
			_update_camera(1.0, true)
		if end_t >= END_BUBBLES:
			state = State.SUNSET
			end_t = 0.0
		return
	# SUNSET: rise and bob at the surface, then the album.
	var before := sub_pos.y
	sub_pos.y = maxf(2.0, sub_pos.y - 16.0 * dt)
	if before > 8.0 and sub_pos.y <= 8.0:
		Sfx.play("surface")
		_burst_bubbles(sub_pos + Vector2(0, -6), 10)
	if end_t >= END_SUNSET:
		state = State.DONE
		Game.goto.call_deferred("album")


func sunset() -> float:
	if state == State.SUNSET:
		return clampf(end_t / 1.2, 0.0, 1.0)
	return 1.0 if state == State.DONE else 0.0


# ================================================================ fx

func _burst_bubbles(at: Vector2, n: int) -> void:
	for i in n:
		fx_bubbles.append({"pos": at + Vector2(rng.randf_range(-10, 10), rng.randf_range(-6, 6)),
			"vel": Vector2(rng.randf_range(-12, 12), rng.randf_range(-40, -18)), "life": rng.randf_range(0.8, 1.6)})


func _update_fx(dt: float) -> void:
	for i in range(sonar_rings.size() - 1, -1, -1):
		sonar_rings[i].t += dt
		if sonar_rings[i].t >= SONAR_SECONDS:
			sonar_rings.remove_at(i)
	for i in range(glow_rings.size() - 1, -1, -1):
		glow_rings[i].t += dt
		if glow_rings[i].t >= 0.6:
			glow_rings.remove_at(i)
	for i in range(fx_bubbles.size() - 1, -1, -1):
		var b := fx_bubbles[i]
		b.life -= dt
		b.pos += b.vel * dt
		b.vel.x *= 0.96
		if b.life <= 0.0 or b.pos.y < -4.0:
			fx_bubbles.remove_at(i)


func _launch_polaroid(id: String, is_new: bool) -> void:
	var card := Polaroid.new()
	card.subject = id
	hud.add_child(card)
	var from := (frame_pos - cam.round()).round()
	polaroids.append({"node": card, "from": from, "to": hud.slot_pos(id), "t": 0.0, "id": id, "is_new": is_new})
	card.position = from


func _update_polaroids(dt: float) -> void:
	for i in range(polaroids.size() - 1, -1, -1):
		var p := polaroids[i]
		p.t += dt
		var node: Node2D = p.node
		if p.t < POLAROID_POP:
			node.position = p.from + Vector2(0, -roundf(12.0 * sin(p.t / POLAROID_POP * PI * 0.5)))
		else:
			var k := clampf((p.t - POLAROID_POP) / POLAROID_FLY, 0.0, 1.0)
			var e := k * k * (3.0 - 2.0 * k)
			var start: Vector2 = p.from + Vector2(0, -12)
			node.position = start.lerp(p.to, e).round()
		if p.t >= POLAROID_POP + POLAROID_FLY:
			_land(p)
			node.queue_free()
			polaroids.remove_at(i)


func _land(p: Dictionary) -> void:
	var id: String = p.id
	hud.slot_flash[id] = 0.5
	if p.is_new:
		revealed[id] = true
		if id == Species.WHALE:
			Sfx.play("whale_song", 1.1)
		else:
			Sfx.play("new_species_%d" % Species.motif(id))
	elif Species.PAGE.has(id) or id == Species.WHALE:
		Sfx.play("repeat_star")
	else:
		Sfx.play("bubble", 1.3)


# ================================================================ camera + nodes

func _update_camera(dt: float, snap_now := false) -> void:
	var look := Vector2(facing * 24.0, 0.0)
	var target := sub_pos + look - VIEW * 0.5
	var top := -70.0 if state != State.RUN else -40.0
	target.x = clampf(target.x, 0.0, 1280.0 - VIEW.x)
	target.y = clampf(target.y, top, 360.0 - VIEW.y)
	if snap_now:
		cam = target
	else:
		cam = cam.lerp(target, 1.0 - exp(-dt * 5.0))
	# Snap the camera itself, not only the sprites: no shimmer at integer scale.
	world.position = -cam.round()
	ambient.color = ReefMap.ambient_at(sub_pos).lerp(Color(1.0, 0.86, 0.78), sunset() * 0.6)


func view_rect() -> Rect2:
	return Rect2(cam.round(), VIEW)


func _update_audio() -> void:
	var depth := clampf(sub_pos.y / 360.0, 0.0, 1.0)
	AudioLoop.set_music_cutoff(lerpf(900.0, 6000.0, depth))
	if hum:
		hum.volume_db = lerpf(-26.0, -14.0, clampf(sub_vel.length() / SubMotion.MAX_SPEED, 0.0, 1.0))


func _place_nodes() -> void:
	sub_node.position = sub_pos.round()
	var flip := facing < 0
	sub_sprite.flip_h = flip
	sub_sprite.speed_scale = 0.4 + sub_vel.length() / 30.0
	# Spin once in quarter turns (pixel art never rotates by less).
	sub_sprite.rotation = floorf((1.0 - spin_t / SPIN_SECONDS) * 4.0) * PI * 0.5 if spin_t > 0.0 else 0.0
	head_light.scale.x = -1.0 if flip else 1.0
	head_light.position.x = -14.0 if flip else 14.0
	glow_light.energy = 0.55 + lights.pulse * 1.3
	glow_light.texture_scale = 1.0 + lights.pulse * 0.4
	bubbles.position = Vector2(20 if flip else -20, 2)
	bubbles.direction = Vector2(1 if flip else -1, -0.3)
	bubbles.emitting = sub_vel.length() > 12.0 and state == State.RUN

	for c in creatures:
		var s: AnimatedSprite2D = sprites[c.id]
		s.visible = c.shown > 0.05
		if not s.visible:
			continue
		var wiggle := (1.0 if int(time * 12.0) % 2 == 0 else -1.0) if c.glow > 0.0 else 0.0
		s.position = (c.pos + Vector2(wiggle, 0)).round()
		s.flip_h = c.facing < 0
		s.modulate.a = clampf(c.shown, 0.0, 1.0)
		var lit: bool = c.glow > 0.0 or Species.kind(c.id) == Species.Kind.LIGHT
		s.material = _unshaded if lit else null
		s.rotation = floorf(fmod(c.spin * 8.0, 4.0)) * PI * 0.5 if c.spin > 0.0 else 0.0
		if c.id == "pufferfish":
			var want := "pufferfish_puffed" if c.puffed > 0.0 else "pufferfish"
			var sf := Art.frames(want, Species.tint(c.id), Vector2i(16, 16))
			if s.sprite_frames != sf:
				s.sprite_frames = sf
				s.play("default")

	viewfinder.position = frame_pos.round()
	viewfinder.frame = 1 if locked else 0
	viewfinder.visible = state == State.RUN
	flash_sprite.visible = flash_t > 0.0
	if flash_sprite.visible:
		flash_sprite.position = frame_pos.round()
		flash_sprite.frame = clampi(int((1.0 - flash_t / FLASH_SECONDS) * 3.0), 0, 2)
	bonus_sprite.visible = bonus_t > 0.0
	if bonus_sprite.visible:
		bonus_sprite.position.y -= 0.3
	_place_pearls()


func _place_pearls() -> void:
	var target := trail_target
	var show := target != "" and state == State.RUN
	var home: Vector2 = reef.homes.get(target, sub_pos) if show else sub_pos
	var to := home - sub_pos
	var dist := to.length()
	var dir := to / dist if dist > 0.0 else Vector2.RIGHT
	for i in pearls.size():
		var p := pearls[i]
		var along := 34.0 + i * 24.0
		p.visible = show and along < dist - 8.0
		if p.visible:
			var bob := Vector2(0, roundf(sin(time * 3.0 + i * 0.9) * 2.0))
			p.position = (sub_pos + dir * along + bob).round()


# ================================================================ drawing classes

## Water, sky, far rock silhouettes and the surface light (static except caustics).
class WaterBg extends Node2D:
	var level
	var t := 0.0

	func _process(delta: float) -> void:
		t += delta
		if int(t * 8.0) != int((t - delta) * 8.0):
			queue_redraw()

	func _draw() -> void:
		var sun: float = level.sunset() if level else 0.0
		# Sky above the surface: day blue, turning to sunset at the end.
		var sky_top := Color("#0099db").lerp(Color("#b55088"), sun)
		var sky_low := Color("#2ce8f5").lerp(Color("#feae34"), sun)
		var bands := 8
		for i in bands:
			var y := -100.0 + i * 12.5
			draw_rect(Rect2(-8, roundf(y), 1296, 13), sky_top.lerp(sky_low, float(i) / (bands - 1)))
		if sun > 0.0:
			draw_circle(Vector2(roundf(level.sub_pos.x + 70.0), roundf(-18.0 + 20.0 * (1.0 - sun))), 14, Color("#fee761"))
		# Water: bands from bright shallows to the dark deep, the trench darkest.
		var cols := [Color("#0099db"), Color("#0f7fc2"), Color("#124e89"), Color("#1b3f78"), Color("#262b44"), Color("#1d2038"), Color("#181425")]
		var band_h := 360.0 / cols.size()
		for i in cols.size():
			var y0 := roundf(i * band_h)
			draw_rect(Rect2(-8, y0, 1296, ceilf(band_h) + 1), cols[i])
			if i + 1 < cols.size():
				# A dithered seam between bands (checker rows), pixel-art style.
				for x in range(-8, 1288, 2):
					draw_rect(Rect2(x + (0 if i % 2 == 0 else 1), y0 + ceilf(band_h) - 1, 1, 1), cols[i + 1])
		var trench := Rect2(640, 180, 648, 188)
		draw_rect(trench, Color(Color("#181425"), 0.55))
		# Far rock silhouettes (dark, no outline) give depth.
		var far := Color("#262b44")
		for k in 18:
			var x := k * 76.0 - 20.0
			var hgt := 30.0 + float((k * 37) % 5) * 12.0
			var pts := PackedVector2Array([Vector2(x, 364), Vector2(x + 14, 364 - hgt), Vector2(x + 30, 364 - hgt - 10),
				Vector2(x + 52, 364 - hgt + 6), Vector2(x + 70, 364)])
			draw_colored_polygon(pts, Color(far, 0.8))
		# The surface line, with little waves.
		for x in range(-8, 1288, 8):
			var wy := 1.0 if (x / 8 + int(t * 4.0)) % 2 == 0 else 0.0
			draw_rect(Rect2(x, wy, 8, 1), Color("#c0cbdc"))
			draw_rect(Rect2(x, wy + 1, 8, 1), Color("#2ce8f5"))
		# Light shafts in the shallows (drawn faint; the CanvasModulate keeps them soft).
		for k in 14:
			var sx := float(k) * 96.0 + fmod(t * 3.0 + k * 13.0, 30.0)
			var shaft := PackedVector2Array([Vector2(sx, 2), Vector2(sx + 10, 2), Vector2(sx + 44, 130), Vector2(sx + 30, 130)])
			draw_colored_polygon(shaft, Color(1, 1, 1, 0.07 if k % 2 == 0 else 0.045))


## The solid tiles, drawn once.
class ReefTiles extends Node2D:
	var reef

	func _draw() -> void:
		var tex := {}
		for n in ["rock", "rock_top", "sand", "sand_top"]:
			tex[n] = Art.frames(n, Color("#5a6988") if n.begins_with("rock") else Color("#e4a672"), Vector2i(16, 16)).get_frame_texture("default", 0)
		var coral := Art.frames("coral", Color("#e43b44"), Vector2i(16, 16))
		for ty in reef.h:
			for tx in reef.w:
				var ch: String = reef.tile(tx, ty)
				if ch == ".":
					continue
				var open_above: bool = reef.tile(tx, ty - 1) == "." or reef.tile(tx, ty - 1) == "c"
				var at := Vector2(tx * 16, ty * 16)
				match ch:
					"#":
						draw_texture(tex["rock_top"] if open_above else tex["rock"], at)
					"s":
						draw_texture(tex["sand_top"] if open_above else tex["sand"], at)
					"c":
						var n := coral.get_frame_count("default")
						draw_texture(coral.get_frame_texture("default", (tx * 7 + ty) % maxi(n, 1)), at)


## Rings, glows and bubbles drawn over the world (unshaded).
class FxDraw extends Node2D:
	var level

	func _draw() -> void:
		var L = level
		for r in L.sonar_rings:
			var k: float = r.t / SONAR_SECONDS
			var rad := roundf(k * SONAR_RADIUS)
			draw_arc(r.pos.round(), rad, 0, TAU, 48, Color(0.17, 0.91, 0.96, 1.0 - k), 1.0)
			if rad > 10:
				draw_arc(r.pos.round(), rad - 6, 0, TAU, 48, Color(0.17, 0.91, 0.96, (1.0 - k) * 0.4), 1.0)
		# Sonar reveal: rings on every hiding spot (hidden hiders) on screen.
		if L.reveal_t > 0.0:
			var pulse := 6.0 + 3.0 * float(int(L.time * 6.0) % 2)
			for c in L.creatures:
				if c.kind == Species.Kind.HIDER and not c.photographable():
					draw_arc(c.home.round(), pulse + 6, 0, TAU, 24, Color(0.17, 0.91, 0.96, 0.9), 1.0)
					draw_arc(c.home.round(), pulse, 0, TAU, 24, Color(1, 1, 1, 0.7), 1.0)
		for g in L.glow_rings:
			var k: float = g.t / 0.6
			draw_arc(g.pos.round(), roundf(12.0 + k * 40.0), 0, TAU, 40, Color(g.color, 1.0 - k), 2.0)
		# Halos behind glowing and light-loving creatures.
		for c in L.creatures:
			if c.shown > 0.3 and (c.glow > 0.0 or c.kind == Species.Kind.LIGHT):
				var col: Color = Species.tint(c.id)
				draw_circle(c.pos.round(), 13, Color(col, 0.16 * c.shown))
				draw_circle(c.pos.round(), 9, Color(col, 0.18 * c.shown))
		var tex := Art.frames("bubble_small", Color("#c0cbdc"), Vector2i(4, 4)).get_frame_texture("default", 0)
		for b in L.fx_bubbles:
			draw_texture(tex, (b.pos - Vector2(2, 2)).round())


## A flying photo: the card and the subject inside it.
class Polaroid extends Node2D:
	var subject := ""

	func _ready() -> void:
		var card := Art.sprite("polaroid", Color("#ffffff"), Vector2i(24, 28))
		card.centered = false
		add_child(card)
		var icon_name := "icon_" + subject
		var inner := Art.sprite(icon_name, Color("#8b9bb4"), Vector2i(20, 20))
		inner.stop()
		inner.centered = true
		inner.position = Vector2(12, 12)
		add_child(inner)


## The album strip (12 slots, the whale, the bonus row) and screen effects.
class Hud extends Node2D:
	var level
	var slot_flash := {}

	func slot_pos(id: String) -> Vector2:
		var i := Species.PAGE.find(id)
		if i >= 0:
			return Vector2(3 + i * 21, 159)
		if id == Species.WHALE:
			return Vector2(258, 159)
		var b := Species.BONUS.find(id)
		return Vector2(282 + (b % 2) * 18 - 8, 158 + (b / 2) * 10 - 10)

	func _draw() -> void:
		var L = level
		for k in slot_flash.keys():
			slot_flash[k] -= 1.0 / 30.0
			if slot_flash[k] <= 0.0:
				slot_flash.erase(k)
		var y0 := 180 - STRIP_H
		draw_rect(Rect2(0, y0, 320, STRIP_H), Color("#181425"))
		draw_rect(Rect2(0, y0, 320, 1), Color("#3a4466"))
		var slot_tex := Art.frames("album_slot", Color("#3a4466"), Vector2i(20, 20)).get_frame_texture("default", 0)
		var star_tex := Art.frames("star", Color("#fee761"), Vector2i(8, 8)).get_frame_texture("default", 0)
		for i in Species.PAGE.size():
			var id: String = Species.PAGE[i]
			_slot(slot_pos(id), id, slot_tex, star_tex)
		_slot(slot_pos(Species.WHALE), Species.WHALE, slot_tex, star_tex)
		# Bonus row: tiny icons with a count in pixel digits.
		for b in Species.BONUS.size():
			var kind: String = Species.BONUS[b]
			var p := Vector2(282 + (b % 2) * 18, 160 + (b / 2) * 10)
			var t := Art.frames("mini_" + kind, Color("#c0cbdc"), Vector2i(8, 8)).get_frame_texture("default", 0)
			draw_texture(t, p)
			var n: int = int(Game.session.bonus.get(kind, 0))
			if n > 0:
				_digits(p + Vector2(9, 2), mini(n, 99), Color("#c0cbdc"))
		# Screen flash (2 frames, soft) and the end's bubble curtain.
		if L.screen_flash_t > 0.0:
			draw_rect(Rect2(0, 0, 320, 180), Color(1, 1, 1, 0.2))
		if L.state == State.END_BUBBLES:
			var k: float = L.end_t / END_BUBBLES
			var rng := RandomNumberGenerator.new()
			rng.seed = 5
			for n in 90:
				var bx := rng.randf_range(0, 320)
				var by := 200.0 - k * 300.0 + rng.randf_range(0, 160)
				var r := rng.randf_range(2, 6)
				draw_circle(Vector2(roundf(bx), roundf(by)), r, Color("#c0cbdc"))
				draw_circle(Vector2(roundf(bx), roundf(by)), maxf(r - 1.0, 1.0), Color("#2ce8f5"))

	func _slot(p: Vector2, id: String, slot_tex: Texture2D, star_tex: Texture2D) -> void:
		var L = level
		draw_texture(slot_tex, p)
		var shown: bool = L.revealed.has(id)
		var name := ("icon_" if shown else "sil_") + id
		var tex := Art.frames(name, Species.tint(id) if shown else Color("#262b44"), Vector2i(20, 20)).get_frame_texture("default", 0)
		draw_texture(tex, p)
		if slot_flash.has(id):
			draw_rect(Rect2(p, Vector2(20, 20)), Color(1, 1, 1, 0.5 * slot_flash[id] / 0.5), false, 1.0)
		var reps: int = int(Game.session.repeats.get(id, 0))
		if reps > 0:
			draw_texture(star_tex, p + Vector2(13, -4))
			for k in mini(reps - 1, 3):
				draw_rect(Rect2(p + Vector2(10 - k * 3, -2), Vector2(2, 2)), Color("#fee761"))

	func _digits(p: Vector2, n: int, col: Color) -> void:
		var s := str(n)
		for k in s.length():
			var glyph: Array = DIGITS[int(s[k])]
			for row in 5:
				for c in 3:
					if glyph[row][c] == "#":
						draw_rect(Rect2(p.x + k * 4 + c, p.y + row, 1, 1), col)


class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.09, 0.08, 0.15, 0.72))
		# Driver's B: back (a red circle with a left arrow); start: play (green circle, triangle).
		draw_circle(Vector2(110, 90), 22, Color("#e43b44"))
		draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
			Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#ffffff"))
		draw_circle(Vector2(210, 90), 26, Color("#63c74d"))
		draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
			Color("#ffffff"))


## 3x5 digit glyphs, one string per row, "#" = lit.
const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]
