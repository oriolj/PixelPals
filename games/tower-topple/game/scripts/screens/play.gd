extends Node2D
## The building site. Builder moves the crane hook and rotates the hanging
## block, Dropper drops it and picks the next shape, Toppler presses the big
## button once it lights. Three towers per run, then the party.
##
## Game logic runs in step(dt) (and physics_step(dt) for the landing assist),
## so tests can drive it frame by frame with set_process(false).

const Vec := preload("res://scripts/play/vec.gd")
const Rules := preload("res://scripts/play/rules.gd")
const BlockScript := preload("res://scripts/play/block.gd")
const WreckerScript := preload("res://scripts/play/wrecker.gd")
const Scenery := preload("res://scripts/play/scenery.gd")
const Hud := preload("res://scripts/play/hud.gd")

enum Phase { BUILD, TOPPLE, CHEER, CLEAR, DONE }

const BUILDER := 0
const DROPPER := 1
const TOPPLER := 2
const HOOK_SPEED := 190.0
const HOOK_MIN := 150.0
const HOOK_MAX := 490.0
const RESPAWN := 0.7
const DROP_READY := 0.25
const CHEER_SECONDS := 3.0
const CLEAR_SECONDS := 1.2
const RECYCLE_AFTER := 1.4
const LIT_CHIME_EVERY := 2.4
const SHAKE_MAX := 6.0
const KIND_WEIGHTS := {"square": 3, "plank": 2, "tall": 2, "roof": 1, "arch": 2, "ball": 1}

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var phase := Phase.BUILD
var phase_t := 0.0
var paused := false
var time := 0.0
var tower_index := 0
var build_t := 0.0
var drops := 0
var lit := false
var lit_t := 0.0
var collapsed := false
var height := 0.0
var peak := 0.0
var flags := 0
var stars := 0
var fallen := 0
var heights: Array[int] = []
## Impulses applied to blocks (the toddler's early presses must never add any).
var impulses := 0
var giggles := 0
var ball_used := false
var hit_done := false
var roles := {}

var blocks: Array = []
var hanging: RigidBody2D = null
var hook_x := 320.0
var hang_rot := 0
var respawn_t := 0.0
var hang_age := 0.0
var tray: Array[String] = ["square", "plank", "tall", "arch"]
var tray_sel := 0

var rng := RandomNumberGenerator.new()
var _serial := 0
var _chime_t := 0.0
var _wobble_cd := 0.0
var _shake_t := 0.0
var _shake_amp := 0.0
var _cam_top := 0.0
var _toddler_seen := false

var world: Node2D
var camera: Camera2D
var block_layer: Node2D
var fx: Node2D
var pole: Node2D
var cloud_line: Node2D
var sky: Node2D
var wrecker: Node2D = null
var riders: Array[AnimatedSprite2D] = []
var _rider_hop: Array[float] = []
var platform_body: StaticBody2D
var pit_body: StaticBody2D
var hud: CanvasLayer
var crane: Node2D
var tray_view: Node2D
var button_view: Node2D
var progress_view: Node2D
var pause_overlay: Node2D
var confetti_tex: Texture2D


func _ready() -> void:
	rng.randomize()
	_build()
	_refill_tray_all()
	respawn_t = 0.3
	Sfx.music("music_build")


func _exit_tree() -> void:
	PhysicsServer2D.set_active(true)


func _process(delta: float) -> void:
	step(delta)


func _physics_process(delta: float) -> void:
	physics_step(delta)


# ================================================================ build

func _build() -> void:
	var sky_layer := CanvasLayer.new()
	sky_layer.layer = -10
	add_child(sky_layer)
	sky = Scenery.SkyView.new()
	sky_layer.add_child(sky)

	world = Node2D.new()
	add_child(world)
	camera = Camera2D.new()
	camera.position = Vector2(320, 180)
	world.add_child(camera)
	camera.make_current()
	world.add_child(Scenery.Hills.new())
	cloud_line = Scenery.CloudLine.new()
	world.add_child(cloud_line)
	world.add_child(Scenery.Site.new())
	pole = Scenery.Pole.new()
	world.add_child(pole)
	var ids := crowd()
	for i in ids.size():
		var r := Art.sprite(ids[i], Game.rider_color(ids[i]), Vector2i(16, 16))
		r.scale = Vector2(2, 2)
		r.position = Vector2(34 + i * 36, Rules.PIT_TOP - 26.0)
		world.add_child(r)
		riders.append(r)
		_rider_hop.append(0.0)
	block_layer = Node2D.new()
	world.add_child(block_layer)
	world.add_child(Scenery.PitFront.new())
	fx = Hud.Fx.new()
	world.add_child(fx)
	_build_bodies()

	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	confetti_tex = ImageTexture.create_from_image(img)

	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	crane = Hud.Crane.new()
	hud.add_child(crane)
	tray_view = Hud.Tray.new()
	tray_view.position = Hud.TRAY_AT
	hud.add_child(tray_view)
	progress_view = Hud.Progress.new()
	progress_view.position = Vector2(576, 60)
	hud.add_child(progress_view)
	button_view = Hud.BigButton.new()
	button_view.position = Hud.BUTTON_AT
	hud.add_child(button_view)
	pause_overlay = Hud.PauseOverlay.new()
	pause_overlay.visible = false
	var pause_layer := CanvasLayer.new()
	pause_layer.layer = 20
	add_child(pause_layer)
	pause_layer.add_child(pause_overlay)
	_update_views(0.0)


func _build_bodies() -> void:
	platform_body = StaticBody2D.new()
	var pm := PhysicsMaterial.new()
	pm.friction = 1.0
	pm.bounce = 0.0
	platform_body.physics_material_override = pm
	var ps := CollisionShape2D.new()
	var pr := RectangleShape2D.new()
	pr.size = Vector2(Rules.PLATFORM_HALF * 2.0 + 16.0, 100)
	ps.shape = pr
	ps.position = Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP + 50.0)
	platform_body.add_child(ps)
	world.add_child(platform_body)

	pit_body = StaticBody2D.new()
	var bm := PhysicsMaterial.new()
	bm.friction = 0.6
	bm.bounce = 0.55
	pit_body.physics_material_override = bm
	var cs := CollisionShape2D.new()
	var floor_shape := RectangleShape2D.new()
	floor_shape.size = Vector2(Scenery.WORLD_R - Scenery.WORLD_L, 200)
	cs.shape = floor_shape
	cs.position = Vector2((Scenery.WORLD_L + Scenery.WORLD_R) * 0.5, Rules.PIT_TOP + 100.0)
	pit_body.add_child(cs)
	# Soft invisible walls keep flying blocks near the site.
	for x in [-60.0, 700.0]:
		var ws := CollisionShape2D.new()
		var wr := RectangleShape2D.new()
		wr.size = Vector2(40, 3000)
		ws.shape = wr
		ws.position = Vector2(x, Rules.PIT_TOP - 1500.0)
		pit_body.add_child(ws)
	world.add_child(pit_body)


## Rider ids for the cheering crowd: the seated riders, else the first of the roster.
func crowd() -> Array[String]:
	var out: Array[String] = []
	for s in Players.SEAT_COUNT:
		var r: String = Players.riders[s]
		if r == "" and Players.is_seated(s) and not Game.roster.is_empty():
			r = Game.roster[s % Game.roster.size()]
		if r != "":
			out.append(r)
	if out.is_empty():
		for i in mini(3, Game.roster.size()):
			out.append(Game.roster[i])
	return out


# ================================================================ frame

func step(dt: float) -> void:
	if next_screen != "":
		return
	if _pause_input():
		return
	time += dt
	roles = Rules.roles(Players.is_seated(BUILDER), Players.is_seated(DROPPER), Players.is_seated(TOPPLER))
	var consumed := {}
	match phase:
		Phase.BUILD:
			consumed = _build_step(dt)
		Phase.TOPPLE:
			_topple_step(dt)
		Phase.CHEER:
			phase_t += dt
			if phase_t >= CHEER_SECONDS:
				_start_clear()
		Phase.CLEAR:
			phase_t += dt
			if phase_t >= CLEAR_SECONDS:
				_next_tower()
				if next_screen != "":
					return
	# The toddler: any press that did not topple is a giggle (cosmetic only).
	if Players.is_seated(TOPPLER) and Players.just_pressed(TOPPLER, "any") and not consumed.has(TOPPLER):
		giggle_all()
	track_blocks(dt)
	_update_views(dt)


func physics_step(_dt: float) -> void:
	if phase != Phase.BUILD:
		return
	for b in blocks:
		if is_instance_valid(b) and b.state == BlockScript.State.FALLING:
			apply_assist(b)


func _build_step(dt: float) -> Dictionary:
	var consumed := {}
	build_t += dt
	# Hook.
	var mv := 0.0
	if roles.move >= 0:
		mv = Players.move(roles.move).x
	else:
		mv = clampf((tower_com_x() - hook_x) / 40.0, -0.6, 0.6)
	hook_x = clampf(hook_x + mv * HOOK_SPEED * dt, HOOK_MIN, HOOK_MAX)
	if hanging == null:
		respawn_t -= dt
		if respawn_t <= 0.0:
			spawn_hanging()
	else:
		hang_age += dt
		_place_hanging(dt)
	# Rotate.
	if not roles.rotate.is_empty() and Players.just_pressed(roles.rotate[0], roles.rotate[1]):
		rotate_hanging()
	# Pick the next shape (the Dropper's d-pad).
	if roles.pick >= 0:
		var d := Players.dir4_just_pressed(roles.pick)
		if d != Vector2i.ZERO:
			pick_slot([Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT].find(d))
	# Topple (only when lit; the grace hands join after TODDLER_GRACE).
	var hands: Array = roles.topple.duplicate()
	if lit and lit_t >= Rules.TODDLER_GRACE:
		hands.append_array(roles.grace)
	for h in hands:
		if Players.just_pressed(h[0], h[1]):
			if try_topple():
				consumed[h[0]] = true
				return consumed
	# Drop.
	if not roles.drop.is_empty():
		if Players.just_pressed(roles.drop[0], roles.drop[1]) and not consumed.has(roles.drop[0]):
			drop()
	elif hanging != null and hang_age > 1.5 and absf(hook_x - tower_com_x()) < 6.0:
		drop()  # nobody can drop: the crane does it by itself
	# Light the button.
	if not lit and Rules.should_light(height, drops, build_t, Game.tower_seconds):
		light()
	if lit:
		lit_t += dt
		_chime_t -= dt
		if _chime_t <= 0.0:
			_chime_t = LIT_CHIME_EVERY
			Sfx.play("button_lit", 1.0, -4.0)
	return consumed


# ================================================================ the hook

func pick_kind() -> String:
	if roles.get("pick", -1) >= 0:
		return tray[tray_sel]
	return random_kind()


func random_kind(exclude := "") -> String:
	var pool: Array[String] = []
	for k in KIND_WEIGHTS:
		if k == exclude:
			continue
		if k == "ball" and (ball_used or tray.has("ball") or (hanging != null and hanging.kind == "ball")):
			continue
		for i in KIND_WEIGHTS[k]:
			pool.append(k)
	return pool[rng.randi() % pool.size()]


func spawn_hanging(kind := "") -> RigidBody2D:
	enforce_budget()
	if kind == "":
		kind = pick_kind()
	var b := BlockScript.make(kind)
	_serial += 1
	b.serial = _serial
	b.hang()
	b.rotation = hang_rot * PI / 2.0
	block_layer.add_child(b)
	b.body_entered.connect(_on_block_contact.bind(b))
	blocks.append(b)
	hanging = b
	hang_age = 0.0
	_place_hanging(1.0)
	return b


func _place_hanging(dt: float) -> void:
	if hanging == null:
		return
	var target := hang_rot * PI / 2.0
	hanging.rotation = lerp_angle(hanging.rotation, target, minf(1.0, dt * 16.0))
	var top := 0.0
	for p in hanging.poly:
		top = minf(top, p.rotated(hanging.rotation).y)
	var at := screen_to_world(Vector2(hook_x, Hud.HOOK_Y + 6.0))
	hanging.global_position = Vector2(at.x, at.y - top + sin(time * 3.0) * 1.0)


func rotate_hanging() -> void:
	if hanging == null:
		return
	hang_rot = (hang_rot + 1) % 4
	Sfx.play("rotate")


func pick_slot(i: int) -> void:
	if i < 0 or i >= tray.size():
		return
	tray_sel = i
	tray_view.selected = i
	tray_view.bump = 0.2
	Sfx.play("select", 1.0 + 0.1 * i)
	if hanging != null and hanging.kind != tray[i]:
		var old := hanging
		blocks.erase(old)
		old.queue_free()
		hanging = null
		spawn_hanging(tray[i])
		hanging.set_mood(BlockScript.Mood.GIGGLE, 0.4)


func drop() -> void:
	if hanging == null or hang_age < DROP_READY:
		return
	var b := hanging
	hanging = null
	b.release(40.0)
	drops += 1
	respawn_t = RESPAWN
	if b.kind == "ball":
		ball_used = true
	if roles.get("pick", -1) >= 0:
		tray[tray_sel] = random_kind(b.kind)
		tray_view.slots = tray
	Sfx.play("drop")


func _refill_tray_all() -> void:
	var picked: Array[String] = []
	for i in tray.size():
		var k := random_kind()
		var guard := 0
		while picked.has(k) and guard < 10:
			k = random_kind()
			guard += 1
		tray[i] = k
		picked.append(k)
	tray_view.slots = tray


# ================================================================ physics bookkeeping

## Landing assist: see Rules.assist_vx.
func apply_assist(b: RigidBody2D) -> void:
	var top := Rules.PLATFORM_TOP - height
	var com := tower_com_x()
	var bottom: float = b.bottom_y()
	if Rules.in_assist(b.global_position.x, bottom, top, com):
		var v := b.linear_velocity
		v.x = Rules.assist_vx(b.global_position.x, bottom, top, com, v.x)
		v.y = minf(v.y, Rules.ASSIST_MAX_VY)
		b.linear_velocity = v


func _on_block_contact(other: Node, b: RigidBody2D) -> void:
	on_contact(b, other)


func on_contact(b: RigidBody2D, other: Node) -> void:
	if not is_instance_valid(b):
		return
	var S := BlockScript.State
	if b.state == S.FALLING:
		if other == pit_body or (other is RigidBody2D and other.get("state") == S.PIT):
			to_pit(b)
		elif other == platform_body or (other is RigidBody2D and other.get("state") in [S.SETTLING, S.SETTLED]):
			land(b)
	elif b.state in [S.SETTLING, S.SETTLED] and other == pit_body:
		to_pit(b)


func land(b: RigidBody2D) -> void:
	b.begin_settling()
	Sfx.play("land", rng.randf_range(0.9, 1.15))
	var tw := b.create_tween()
	b.visual.scale = Vector2(1.12, 0.88)
	tw.tween_property(b.visual, "scale", Vector2.ONE, 0.25).set_trans(Tween.TRANS_BACK)


func to_pit(b: RigidBody2D) -> void:
	var S := BlockScript.State
	if b.state == S.PIT or b.state == S.CLEARING:
		return
	if phase == Phase.BUILD and b.was_on_tower:
		fallen += 1
	if b.buried:
		b.bury(false)
	b.state = S.PIT
	b.pit_t = 0.0
	b.end_settling()
	b.state = S.PIT
	if phase == Phase.BUILD:
		b.set_mood(BlockScript.Mood.WHEE, 1.0)
		Sfx.play("pit_boing", rng.randf_range(0.9, 1.2))
		fx.burst(b.global_position, 6, "star", 120.0)


## Rest timers, settling windows, pit detection, recycling, freezing, height.
func track_blocks(dt: float) -> void:
	var S := BlockScript.State
	_wobble_cd = maxf(0.0, _wobble_cd - dt)
	var look := _look_point()
	for b in blocks.duplicate():
		if not is_instance_valid(b):
			blocks.erase(b)
			continue
		b.look_at_point = look
		if b.state == S.HANGING or b.state == S.CLEARING:
			continue
		if b.freeze or b.linear_velocity.length() < Rules.REST_SPEED:
			b.rest_t += dt
		else:
			b.rest_t = 0.0
		var off_platform := absf(b.global_position.x - Rules.PLATFORM_X) > Rules.PLATFORM_HALF + 6.0
		match b.state:
			S.FALLING:
				if off_platform and b.bottom_y() > Rules.PIT_TOP - 4.0:
					to_pit(b)
				elif b.rest_t > 0.3:
					land(b)  # came to rest without a reported contact
			S.SETTLING, S.SETTLED:
				if b.state == S.SETTLING:
					b.settle_t += dt
					if b.settle_t >= Rules.SETTLE_TIME:
						b.end_settling()
				if off_platform and b.global_position.y > Rules.PIT_TOP - 10.0:
					to_pit(b)
				elif b.rest_t >= Rules.REST_TIME:
					b.was_on_tower = true
				if phase == Phase.BUILD and b.state == S.SETTLED and absf(b.angular_velocity) > 1.5 and _wobble_cd <= 0.0:
					_wobble_cd = 1.6
					Sfx.play("wobble", rng.randf_range(0.9, 1.1), -3.0)
					b.set_mood(BlockScript.Mood.OOPS, 0.8)
			S.PIT:
				b.pit_t += dt
				if phase == Phase.BUILD and b.pit_t >= RECYCLE_AFTER:
					recycle(b)
	if phase == Phase.BUILD:
		update_height(measure_height())
		update_burying()
		if not collapsed and Rules.is_collapse(fallen, tower_blocks().size()):
			collapse()


func tower_blocks() -> Array:
	var S := BlockScript.State
	var out := []
	for b in blocks:
		if is_instance_valid(b) and (b.state == S.SETTLING or b.state == S.SETTLED):
			out.append(b)
	return out


func _rested_tower() -> Array:
	var out := []
	for b in tower_blocks():
		if b.rest_t >= Rules.REST_TIME:
			out.append(b)
	return out


## Settled height: the highest top of tower blocks resting for REST_TIME.
func measure_height() -> float:
	var top := Rules.PLATFORM_TOP
	for b in _rested_tower():
		top = minf(top, b.top_y())
	return maxf(0.0, Rules.PLATFORM_TOP - top)


func tower_com_x() -> float:
	var m := 0.0
	var x := 0.0
	for b in _rested_tower():
		m += b.mass
		x += b.global_position.x * b.mass
	return x / m if m > 0.0 else Rules.PLATFORM_X


## Blocks with BURY_LAYERS resting blocks above them freeze (static).
func update_burying() -> void:
	var rested := _rested_tower()
	for b in rested:
		if b.buried:
			continue
		var r: Rect2 = b.world_rect()
		var above := 0
		for c in rested:
			if c == b:
				continue
			var q: Rect2 = c.world_rect()
			var overlap := minf(r.end.x, q.end.x) - maxf(r.position.x, q.position.x)
			if overlap >= 4.0 and q.end.y <= r.position.y + 8.0:
				above += 1
		if above >= Rules.BURY_LAYERS:
			b.bury(true)
			b.set_mood(BlockScript.Mood.SLEEP, 9999.0)


func update_height(h: float) -> void:
	height = h
	peak = maxf(peak, h)
	var nf := Rules.flags_for(peak)
	while flags < nf:
		flags += 1
		flag_reached(flags)
	if peak >= Rules.CLOUD_HEIGHT:
		cloud_line.reached = true


func flag_reached(f: int) -> void:
	stars += 1
	Sfx.play("flag_%d" % clampi(f, 1, 8))
	var at := Vector2(Scenery.POLE_X - 16.0, pole.flag_y(f - 1))
	fx.burst(at, 10, "star", 180.0, Color("#ffcd75"))
	pole.pop[f - 1] = 0.5
	for i in _rider_hop.size():
		_rider_hop[i] = 0.5


func enforce_budget() -> void:
	var S := BlockScript.State
	while _live_count() >= Rules.BODY_BUDGET:
		var oldest: RigidBody2D = null
		for b in blocks:
			if is_instance_valid(b) and b.state == S.PIT and (oldest == null or b.serial < oldest.serial):
				oldest = b
		if oldest == null:
			return
		blocks.erase(oldest)
		oldest.queue_free()


func _live_count() -> int:
	var n := 0
	for b in blocks:
		if is_instance_valid(b) and not b.is_queued_for_deletion() and b.state != BlockScript.State.CLEARING:
			n += 1
	return n


## A missed block shrinks away and a sparkle flies back to the tray.
func recycle(b: RigidBody2D) -> void:
	clear_block(b, 0.35)
	var to := world_point_of_screen(Hud.TRAY_AT) if roles.get("pick", -1) >= 0 else screen_to_world(Vector2(hook_x, Hud.HOOK_Y))
	fx.fly(b.global_position, to)
	Sfx.play("sparkle", rng.randf_range(0.95, 1.1), -2.0)
	tray_view.flash = 0.6


func clear_block(b: RigidBody2D, seconds: float) -> void:
	if not is_instance_valid(b):
		return
	b.state = BlockScript.State.CLEARING
	b.bury(false)
	b.set_deferred("freeze", true)
	b.collision_layer = 0
	b.collision_mask = 0
	var tw := b.create_tween()
	tw.tween_property(b.visual, "scale", Vector2(0.01, 0.01), seconds).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		blocks.erase(b)
		b.queue_free())


# ================================================================ button and topple

func light() -> void:
	if lit:
		return
	lit = true
	lit_t = 0.0
	_chime_t = LIT_CHIME_EVERY
	Sfx.play("button_lit")


## The tower fell on its own: a smaller crash party, stars kept, button lit.
func collapse() -> void:
	collapsed = true
	Sfx.play("crash", 1.15, -8.0)
	Sfx.play("whee", 1.1, -4.0)
	for b in blocks:
		if is_instance_valid(b) and b.state != BlockScript.State.HANGING:
			b.set_mood(BlockScript.Mood.WHEE, 1.5)
	_confetti(Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP - 40.0), 40)
	shake(3.0)
	light()


## Called for a toppler press. Only a lit button knocks the tower down.
func try_topple() -> bool:
	if not lit or phase != Phase.BUILD:
		return false
	phase = Phase.TOPPLE
	phase_t = 0.0
	hit_done = false
	heights.append(flags)
	if Game.demo:
		print("demo: tower %d peak %.0f px, %d flags, %d drops, collapsed %s" % [tower_index + 1, peak, flags, drops, collapsed])
	button_view.press = 0.25
	if hanging != null:
		var h := hanging
		hanging = null
		clear_block(h, 0.3)
	var kinds: Array = WreckerScript.KINDS
	var kind: String = kinds[Game.wrecker_index % kinds.size()]
	Game.wrecker_index += 1
	wrecker = WreckerScript.new()
	var view := _topple_view()
	wrecker.setup(kind, Rules.PLATFORM_TOP - maxf(height, peak * 0.5), view.position.x, view.end.x)
	world.add_child(wrecker)
	Sfx.play("swing")
	return true


func _topple_step(dt: float) -> void:
	phase_t += dt
	if wrecker:
		wrecker.advance(dt)
		if not hit_done and wrecker.t >= wrecker.hit_time:
			hit(wrecker.contact_point(), wrecker.push_dir)
		if wrecker.t >= wrecker.duration:
			phase = Phase.CHEER
			phase_t = 0.0


## The big crash: every block unfreezes and flies from the contact point.
func hit(point: Vector2, push: Vector2) -> void:
	hit_done = true
	var S := BlockScript.State
	for b in blocks:
		if not is_instance_valid(b) or b.state == S.CLEARING or b.state == S.HANGING:
			continue
		b.bury(false)
		b.freeze = false
		b.end_settling()
		b.state = S.PIT
		b.pit_t = 0.0
		var away: Vector2 = b.global_position - point
		var d := away.normalized() if away.length() > 1.0 else push
		d = (d + push.normalized() * 1.2 + Vector2(0, -0.9)).normalized()
		var mag: float = b.mass * rng.randf_range(260.0, 420.0)
		b.apply_impulse(d * mag, (point - b.global_position).limit_length(10.0))
		b.angular_velocity += rng.randf_range(-6.0, 6.0)
		b.set_mood(BlockScript.Mood.WHEE, 4.0)
		impulses += 1
	Sfx.play("crash")
	Sfx.play("whee", rng.randf_range(0.95, 1.1))
	get_tree().create_timer(0.5).timeout.connect(func(): Sfx.play("cheer"))
	_confetti(point, 120)
	_confetti(Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP - 120.0), 80)
	shake(SHAKE_MAX)
	for i in _rider_hop.size():
		_rider_hop[i] = 3.0


func _start_clear() -> void:
	phase = Phase.CLEAR
	phase_t = 0.0
	for b in blocks.duplicate():
		clear_block(b, 0.6 + rng.randf_range(0.0, 0.4))
	if wrecker:
		var tw := wrecker.create_tween()
		tw.tween_property(wrecker, "modulate:a", 0.0, 0.6)


func _next_tower() -> void:
	tower_index += 1
	if wrecker:
		wrecker.queue_free()
		wrecker = null
	for b in blocks:
		if is_instance_valid(b):
			b.queue_free()
	blocks.clear()
	hanging = null
	if tower_index >= Game.TOWERS_PER_RUN:
		_finish()
		return
	phase = Phase.BUILD
	phase_t = 0.0
	build_t = 0.0
	drops = 0
	lit = false
	lit_t = 0.0
	collapsed = false
	height = 0.0
	peak = 0.0
	flags = 0
	fallen = 0
	ball_used = false
	hang_rot = 0
	respawn_t = 0.4
	cloud_line.reached = false
	_cam_top = 0.0
	camera.position = Vector2(320, 180)
	_refill_tray_all()


func _finish() -> void:
	phase = Phase.DONE
	Game.tower_heights = heights.duplicate()
	Game.stars = stars
	next_screen = "party"
	if auto_goto:
		Game.goto.call_deferred("party")


## The toddler's press before the button lights: giggles and bouncing eyes.
## Purely cosmetic: no impulse, no physics property changes.
func giggle_all() -> void:
	giggles += 1
	button_view.press = 0.25
	Sfx.play("giggle", rng.randf_range(0.95, 1.1))
	for b in blocks:
		if is_instance_valid(b) and b.state != BlockScript.State.CLEARING:
			if b.mood != BlockScript.Mood.SLEEP or rng.randf() < 0.5:
				b.giggle()
	fx.burst(world_point_of_screen(Hud.BUTTON_AT + Vector2(0, -20)), 5, "star", 120.0)


func _confetti(at: Vector2, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.texture = confetti_tex
	p.amount = amount
	p.one_shot = true
	p.explosiveness = 0.9
	p.lifetime = 2.2
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 180.0
	p.initial_velocity_max = 380.0
	p.gravity = Vector2(0, 360)
	p.damping_min = 20.0
	p.damping_max = 60.0
	p.angular_velocity_min = -360.0
	p.angular_velocity_max = 360.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.2
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Vec.RED, Vec.YELLOW, Vec.LIME, Vec.SKY, Vec.ORANGE, Vec.WHITE])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	p.color_initial_ramp = g
	p.position = at
	world.add_child(p)
	p.emitting = true
	get_tree().create_timer(3.0).timeout.connect(p.queue_free)


func shake(amount: float) -> void:
	_shake_amp = minf(SHAKE_MAX, maxf(_shake_amp, amount))
	_shake_t = 0.6


# ================================================================ pause

## Pause belongs to the Builder only. Returns true while paused.
func _pause_input() -> bool:
	if phase == Phase.DONE:
		return false
	if Players.just_pressed(BUILDER, "start"):
		_set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(BUILDER, "a"):
			_set_paused(false)
		elif Players.just_pressed(BUILDER, "b"):
			_back_to_join()
	return paused


func _set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	# Not SceneTree.paused: that would also stop the Players autoload polling.
	world.process_mode = Node.PROCESS_MODE_DISABLED if on else Node.PROCESS_MODE_INHERIT
	PhysicsServer2D.set_active(not on)
	Sfx.play("select")


func _back_to_join() -> void:
	phase = Phase.DONE
	paused = false
	PhysicsServer2D.set_active(true)
	next_screen = "join"
	Players.reset()
	if auto_goto:
		Game.goto.call_deferred("join")


# ================================================================ camera and views

func screen_to_world(p: Vector2) -> Vector2:
	return camera.position + (p - Vector2(320, 180)) / camera.zoom.x


func world_point_of_screen(p: Vector2) -> Vector2:
	return screen_to_world(p)


func _topple_view() -> Rect2:
	var top := minf(_cam_top, Rules.PLATFORM_TOP - maxf(height, peak) - 90.0)
	var span := (Rules.PIT_TOP + 40.0) - top
	var z := clampf(360.0 / span, 0.55, 1.0)
	var size := Vector2(640, 360) / z
	return Rect2(Vector2(320 - size.x / 2, Rules.PIT_TOP + 40.0 - size.y), size)


func _look_point() -> Vector2:
	if wrecker != null and phase == Phase.TOPPLE:
		return wrecker.position
	if lit:
		return world_point_of_screen(Hud.BUTTON_AT)
	if hanging != null:
		return hanging.global_position
	return screen_to_world(Vector2(hook_x, Hud.HOOK_Y))


func _update_views(dt: float) -> void:
	# Camera: rise with the tower while building, zoom out for the topple.
	var target_zoom := 1.0
	var target_pos: Vector2
	if phase == Phase.TOPPLE or phase == Phase.CHEER or phase == Phase.CLEAR:
		var v := _topple_view()
		target_zoom = 640.0 / v.size.x
		target_pos = v.get_center()
	else:
		var want := minf(0.0, Rules.PLATFORM_TOP - height - 200.0)
		_cam_top = lerpf(_cam_top, want, minf(1.0, dt * 1.5))
		target_pos = Vector2(320, _cam_top + 180.0)
	var k := minf(1.0, dt * 2.5)
	var z := lerpf(camera.zoom.x, target_zoom, k)
	camera.zoom = Vector2(z, z)
	camera.position = camera.position.lerp(target_pos, k) if phase != Phase.BUILD else target_pos
	if _shake_t > 0.0:
		_shake_t = maxf(0.0, _shake_t - dt)
		var a := _shake_amp * (_shake_t / 0.6)
		camera.offset = Vector2(rng.randf_range(-a, a), rng.randf_range(-a, a))
	else:
		camera.offset = Vector2.ZERO
	sky.rise = clampf(-_cam_top / 400.0, 0.0, 1.0)
	sky.cam_y = _cam_top
	sky.drift += dt
	sky.queue_redraw()
	pole.reached = flags
	pole.height = height
	pole.step(dt)
	cloud_line.step(dt)
	fx.step(dt)
	# Riders hop on flags, and bounce the whole time after a crash.
	for i in riders.size():
		_rider_hop[i] = maxf(0.0, _rider_hop[i] - dt)
		var hop := absf(sin(time * 9.0 + i * 1.3)) * 10.0 if _rider_hop[i] > 0.0 else absf(sin(time * 2.0 + i)) * 2.0
		riders[i].position.y = Rules.PIT_TOP - 26.0 - hop
	# HUD.
	crane.hook_x = hook_x
	crane.parked = phase != Phase.BUILD
	crane.builder_on = Players.is_seated(BUILDER)
	crane.time = time
	crane.queue_redraw()
	tray_view.visible = roles.get("pick", -1) >= 0
	tray_view.slots = tray
	tray_view.selected = tray_sel
	tray_view.bump = maxf(0.0, tray_view.bump - dt)
	tray_view.flash = maxf(0.0, tray_view.flash - dt)
	tray_view.queue_redraw()
	button_view.lit = lit and phase == Phase.BUILD
	button_view.time = time
	button_view.press = maxf(0.0, button_view.press - dt)
	button_view.toddler_on = Players.is_seated(TOPPLER)
	button_view.queue_redraw()
	progress_view.done = tower_index + (1 if phase in [Phase.TOPPLE, Phase.CHEER, Phase.CLEAR] else 0)
	progress_view.current = tower_index
	progress_view.time = time
	progress_view.queue_redraw()
