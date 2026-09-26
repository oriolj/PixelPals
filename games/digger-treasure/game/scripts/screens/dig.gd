extends Node2D
## The dig: a side-view dirt field three screens wide and two tall. The
## driver steers the digger (driving into dirt digs it), the scooper aims
## the arm four ways and takes big 5x5 bites, the boomer's ANY button blasts
## a round hole. Uncovered treasures pop up and fly into the dump truck.
## No game over: the run ends when all twelve are in the truck, or at the
## time limit, when the rest burst up by themselves (the final fountain).
##
## All logic lives in step(dt) so tests drive it frame by frame with
## set_process(false) and scripted devices.

const Grid := preload("res://scripts/dig/terrain_grid.gd")
const Body := preload("res://scripts/dig/digger_body.gd")
const Rules := preload("res://scripts/dig/rules.gd")
const Layout := preload("res://scripts/dig/layout.gd")
const TerrainView := preload("res://scripts/dig/terrain_view.gd")
const RiderView := preload("res://scripts/rider_view.gd")

const W := 320
const H := 180
const WORLD_TOP := -64             # sky and grass above the field
const DRIVER := 0                  # Players.Seat.DRIVER
const SCOOPER := 1                 # Players.Seat.GUNNER
const BOOMER := 2                  # Players.Seat.HONKER
const ARM_BASE := 8.0              # the arm pivots this far out from the digger's centre
const ARM_REACH := 7.0             # extra reach while a scoop animates
const ARM_TIME := 0.25
const POP_TIME := 0.6
const FLY_TIME := 0.9
const FIND_TIME := 3.2
const CELEBRATE_SECONDS := 2.5
const HUD_TRUCK := Vector2(30, 15)
const HUD_BED := Vector2(20, 12)
const MUSIC_DB := -8.0
const DUCK_DB := 4.0

const C_SKY := Color("#41a6f6")
const C_SKY_LOW := Color("#73eff7")
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

enum State { RUN, FOUNTAIN, CELEBRATE, DONE }

var state := State.RUN
var paused := false
var time := 0.0
var run_len := Rules.RUN_SECONDS
var rng := RandomNumberGenerator.new()

var grid: Grid
var body: Body
var view: TerrainView
## {kind, cell, cells, rect, state: "buried"|"pop"|"fly"|"truck", node, t, from, glint_t}
var treasures: Array[Dictionary] = []
## {kind, cell, cells, rect, state: "buried"|"out"|"gone", node, t, dir}
var finds: Array[Dictionary] = []
## Decorations: {node, t, life, kind, ...}
var fx: Array[Dictionary] = []
var in_truck := 0

## Counters (tests and balancing).
var booms := 0
var auto_booms := 0
var puffs := 0
var stuck_puffs := 0
var scoops := 0
var donks := 0
## Pads that were rumbled, in order (tests read it).
var rumble_log: Array[int] = []

var aim := Vector2i.DOWN
var boom_cd := 0.0
var auto_boom_t := 0.0
var scoop_cd := 0.0
var driver_scoop_cd := 0.0
var arm_t := 0.0
var driver_arm_t := 0.0
var donk_cd := 0.0
var wobble_t := 0.0
var shake_t := 0.0
var duck_t := 0.0
var dig_sound_t := 0.0
var digging_t := 0.0
var moving := false
var fountain_t := 0.0
var celebrate_t := 0.0
var confetti_t := 0.0
var cam := Vector2.ZERO
var _anim_t := 0.0
var _flip := false

var world: Node2D
var terrain_layer: Node2D
var things_layer: Node2D
var rig: Node2D
var fx_layer: Node2D
var hud: Node2D
var world_truck: AnimatedSprite2D
var hud_truck: AnimatedSprite2D
var digger: AnimatedSprite2D
var arm: AnimatedSprite2D
var driver_arm: AnimatedSprite2D
var riders: Array = [null, null, null]
var bursts: DirtBursts
var pause_overlay: PauseOverlay
var _hud_bounce := 0.0


func _ready() -> void:
	rng.randomize()
	run_len = Rules.run_length(Game.run_seconds)
	Game.found.clear()
	_build()
	Sfx.music("music_dig")
	_set_music_db(MUSIC_DB)


func _process(delta: float) -> void:
	step(delta)


func _exit_tree() -> void:
	_set_music_db(MUSIC_DB)


# ================================================================ build

func _build() -> void:
	grid = Grid.new()
	body = Body.new()
	body.pos = Layout.START_POS
	var buried: Array[Rect2i] = []
	for t in Layout.treasures(rng, Game.demo):
		var r := Rect2i(t.cell, Vector2i.ONE * Layout.TREASURE_CELLS)
		treasures.append({"kind": t.kind, "cell": t.cell, "rect": r,
			"cells": Layout.cells_of(t.cell, Layout.TREASURE_CELLS), "state": "buried", "node": null,
			"t": 0.0, "from": Vector2.ZERO, "glint_t": rng.randf_range(0.2, Rules.GLINT_EVERY)})
		buried.append(r)
	for f in Layout.finds(rng):
		var r := Rect2i(f.cell, Vector2i.ONE * Layout.FIND_CELLS)
		var overlaps := false
		for b in buried:
			if b.grow(1).intersects(r):
				overlaps = true
		if overlaps:
			continue
		finds.append({"kind": f.kind, "cell": f.cell, "rect": r,
			"cells": Layout.cells_of(f.cell, Layout.FIND_CELLS), "state": "buried", "node": null, "t": 0.0,
			"dir": 1.0, "home": Vector2.ZERO})
		buried.append(r)
	Layout.carve(grid, buried)

	world = Node2D.new()
	add_child(world)
	var sky := ColorRect.new()
	sky.position = Vector2(-8, WORLD_TOP - 8)
	sky.size = Vector2(grid.w * Grid.CELL + 16, 34)
	sky.color = C_SKY
	world.add_child(sky)
	var sky_low := ColorRect.new()
	sky_low.position = Vector2(-8, WORLD_TOP + 26)
	sky_low.size = Vector2(grid.w * Grid.CELL + 16, 40)
	sky_low.color = C_SKY_LOW
	world.add_child(sky_low)
	var span := grid.w * Grid.CELL
	for i in ceili(span / 320.0):
		var hills := Art.sprite("sky_hills", Color("#257179"), Vector2i(320, 48))
		hills.position = Vector2(160 + i * 320, WORLD_TOP + 24)
		world.add_child(hills)
	for i in 3:
		var c := Art.sprite("cloud_bg", Color("#f4f4f4"), Vector2i(32, 16))
		c.position = Vector2(200 + i * 290, WORLD_TOP + 12 + (i % 2) * 8)
		world.add_child(c)
	world_truck = Art.sprite("dump_truck", Color("#b13e53"), Vector2i(48, 24))
	world_truck.stop()
	world_truck.position = Vector2(44, -16)
	world.add_child(world_truck)
	for i in ceili(span / 320.0):
		var g := Art.sprite("grass_strip", Color("#38b764"), Vector2i(320, 16))
		g.position = Vector2(160 + i * 320, -8)
		world.add_child(g)

	terrain_layer = Node2D.new()
	world.add_child(terrain_layer)
	view = TerrainView.new()
	view.setup(grid)
	terrain_layer.add_child(view)

	things_layer = Node2D.new()
	world.add_child(things_layer)

	rig = Node2D.new()
	world.add_child(rig)
	arm = Art.sprite("scoop_arm", Players.SEAT_COLORS[SCOOPER], Vector2i(16, 8))
	arm.offset = Vector2(8, 0)
	arm.visible = Players.is_seated(SCOOPER)
	rig.add_child(arm)
	driver_arm = Art.sprite("scoop_arm_driver", Players.SEAT_COLORS[DRIVER], Vector2i(16, 8))
	driver_arm.offset = Vector2(8, 0)
	driver_arm.visible = false
	rig.add_child(driver_arm)
	# The boomer peeks over the engine hood and the scooper over the arm
	# mount (both behind the body); the driver sits in the seat, in front.
	riders[BOOMER] = _rider(BOOMER)
	riders[SCOOPER] = _rider(SCOOPER)
	digger = Art.sprite(Game.digger_sprite(), Color("#ffcd75"), Vector2i(32, 24))
	digger.stop()
	rig.add_child(digger)
	riders[DRIVER] = _rider(DRIVER)

	fx_layer = Node2D.new()
	world.add_child(fx_layer)
	bursts = DirtBursts.new()
	fx_layer.add_child(bursts)

	hud = Node2D.new()
	add_child(hud)
	hud_truck = Art.sprite("dump_truck", Color("#b13e53"), Vector2i(48, 24))
	hud_truck.stop()
	hud_truck.position = HUD_TRUCK
	hud.add_child(hud_truck)
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	add_child(pause_overlay)

	_update_camera(0.0, true)
	_place_nodes()
	view.flush()


func _rider(seat: int) -> Node2D:
	var id: String = Players.riders[seat]
	if not Players.is_seated(seat):
		return null
	if id == "":
		id = Game.roster[seat % Game.roster.size()]
	var rv := RiderView.new()
	rv.setup(id, seat)
	rig.add_child(rv)
	return rv


# ================================================================ frame

func step(dt: float) -> void:
	if state == State.DONE:
		return
	if _pause_input():
		return
	time += dt
	_anim_t += dt
	boom_cd = maxf(0.0, boom_cd - dt)
	scoop_cd = maxf(0.0, scoop_cd - dt)
	driver_scoop_cd = maxf(0.0, driver_scoop_cd - dt)
	arm_t = maxf(0.0, arm_t - dt)
	driver_arm_t = maxf(0.0, driver_arm_t - dt)
	donk_cd = maxf(0.0, donk_cd - dt)
	wobble_t = maxf(0.0, wobble_t - dt)
	shake_t = maxf(0.0, shake_t - dt)
	dig_sound_t = maxf(0.0, dig_sound_t - dt)
	digging_t = maxf(0.0, digging_t - dt)
	_hud_bounce = maxf(0.0, _hud_bounce - dt)
	if duck_t > 0.0:
		duck_t -= dt
		if duck_t <= 0.0:
			_set_music_db(MUSIC_DB)

	_drive(dt)
	_scoops()
	_boomer(dt)
	if body.stuck_step(dt, grid):
		stuck_puffs += 1
		Sfx.play("puff")
		bursts.burst(body.pos, _band_at(body.pos), 14)

	match state:
		State.RUN:
			if time >= run_len:
				state = State.FOUNTAIN
				fountain_t = 0.0
		State.FOUNTAIN:
			_fountain(dt)
		State.CELEBRATE:
			celebrate_t -= dt
			confetti_t -= dt
			if confetti_t <= 0.0:
				confetti_t = 0.12
				_confetti(body.pos + Vector2(rng.randi_range(-60, 60), rng.randi_range(-60, -10)), 6)
			if celebrate_t <= 0.0:
				_finish()
				return

	_check_exposed()
	_update_treasures(dt)
	_update_finds(dt)
	_update_glints(dt)
	_update_fx(dt)
	if state != State.CELEBRATE and in_truck >= treasures.size():
		_start_celebration()
	_update_camera(dt)
	_place_nodes()
	view.flush()


## Pause belongs to the driver only. Returns true while paused.
func _pause_input() -> bool:
	if state == State.CELEBRATE:
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


# ================================================================ the crew

func _drive(dt: float) -> void:
	var before := body.pos
	var res := body.drive(Players.move(DRIVER), dt, grid)
	moving = res.moved > 0.0
	if body.facing.x != 0:
		_flip = body.facing.x < 0
	if res.dug > 0:
		digging_t = 0.15
		if dig_sound_t <= 0.0:
			dig_sound_t = 0.16
			Sfx.play("dig", rng.randf_range(0.9, 1.1), -4.0)
		var lead := body.pos + Vector2(body.facing) * (Body.SIZE * 0.5 + Vector2(2, 2))
		bursts.burst(lead, _band_at(lead), 3)
	if res.rock and donk_cd <= 0.0 and body.pos.distance_to(before) < 0.5:
		donk_cd = 0.5
		wobble_t = 0.3
		donks += 1
		Sfx.play("donk")


func _scoops() -> void:
	if Players.is_seated(SCOOPER):
		aim = Rules.snap4(Players.move(SCOOPER), aim)
		if Players.just_pressed(SCOOPER, "a") and scoop_cd <= 0.0:
			scoop_cd = Rules.SCOOP_COOLDOWN
			arm_t = ARM_TIME
			scoop(aim, Rules.BIG_SCOOP)
	if Players.just_pressed(DRIVER, "a") and driver_scoop_cd <= 0.0:
		driver_scoop_cd = Rules.SCOOP_COOLDOWN
		driver_arm_t = ARM_TIME
		scoop(body.facing, Rules.SMALL_SCOOP)


## One bite of `size` cells next to the digger. Into empty air it still
## animates and makes its sound. Returns the cells dug.
func scoop(dir: Vector2i, size: int) -> int:
	scoops += 1
	var r := Rules.scoop_rect(body.cells(grid), dir, size)
	var n := grid.dig_rect(r)
	Sfx.play("scoop", 1.0 if size >= Rules.BIG_SCOOP else 1.25)
	if n > 0:
		Sfx.play("dig", rng.randf_range(0.85, 1.0))
		var c := Grid.center_of(r.position) + Vector2(r.size - Vector2i.ONE) * Grid.CELL * 0.5
		bursts.burst(c, _band_at(c), 6 + n / 3)
	return n


func _boomer(dt: float) -> void:
	if Players.is_seated(BOOMER):
		auto_boom_t = 0.0
		if Players.just_pressed(BOOMER, "any"):
			boom()
	else:
		auto_boom_t += dt
		if auto_boom_t >= Rules.AUTO_BOOM_EVERY:
			auto_boom_t = 0.0
			if boom():
				auto_booms += 1


## The toddler's button. Off cooldown: a round blast that clears dirt around
## the digger (never moves it, never hurts anything). On cooldown: a little
## dirt puff, so every press is answered. Returns true for a real boom.
func boom() -> bool:
	if boom_cd > 0.0:
		puffs += 1
		Sfx.play("puff", rng.randf_range(0.9, 1.2))
		bursts.burst(body.pos + Vector2(rng.randi_range(-14, 14), rng.randi_range(-10, 4)), _band_at(body.pos), 5)
		_add_ring(body.pos, 0.25, true)
		return false
	boom_cd = Rules.BOOM_COOLDOWN
	booms += 1
	var c := Grid.cell_of(body.pos)
	grid.dig_circle(c, Rules.BOOM_RADIUS)
	for i in 8:
		var a := i * TAU / 8.0
		var p := body.pos + Vector2(cos(a), sin(a)) * Rules.BOOM_RADIUS * Grid.CELL * 0.8
		bursts.burst(p, _band_at(p), 6)
	_add_ring(body.pos, 0.45, false)
	shake_t = 0.3
	Sfx.play("boom")
	_duck()
	_rumble()
	return true


func _duck() -> void:
	duck_t = 0.9
	_set_music_db(MUSIC_DB - DUCK_DB)


## The dig loop's volume. Local helper: shared sfx.gd has no music-volume API.
func _set_music_db(db: float) -> void:
	var m = Sfx.get("_music")
	if m is AudioStreamPlayer:
		m.volume_db = db


## Every seated pad rumbles on a boom: weak motor, 150 ms.
func _rumble() -> void:
	for s in Players.SEAT_COUNT:
		var d := Players.device_of(s)
		if d.begins_with("pad:"):
			var id := int(d.substr(4))
			rumble_log.append(id)
			Input.start_joy_vibration(id, 0.6, 0.0, 0.15)


# ================================================================ treasures

func _check_exposed() -> void:
	var d := grid.dirty
	if d.size == Vector2i.ZERO:
		return
	var zone := d.grow(1)
	for t in treasures:
		if t.state == "buried" and zone.intersects(t.rect) and grid.exposed(t.cells):
			_uncover(t)
	for f in finds:
		if f.state == "buried" and zone.intersects(f.rect) and grid.exposed(f.cells):
			_uncover_find(f)


func _uncover(t: Dictionary) -> void:
	t.state = "pop"
	t.t = 0.0
	grid.dig_rect(t.rect)
	var at := _rect_center(t.rect)
	t.from = at
	var n := Art.sprite(t.kind, Color("#ffcd75"), Vector2i(16, 16))
	n.position = at
	things_layer.add_child(n)
	t.node = n
	Sfx.play("treasure_pop")
	_sparkles(at, 3)


func _update_treasures(dt: float) -> void:
	for t in treasures:
		match t.state:
			"pop":
				t.t += dt
				var u := clampf(t.t / POP_TIME, 0.0, 1.0)
				t.node.position = (t.from + Vector2(0, -22.0 * sin(u * PI * 0.5))).round()
				t.node.rotation = floorf(t.t * 10.0) * PI * 0.5
				if u >= 1.0:
					# Hand over to the HUD: fly in screen space to the truck.
					t.state = "fly"
					t.t = 0.0
					var screen_at: Vector2 = t.node.position - cam.round()
					t.node.reparent(hud, false)
					t.node.position = screen_at
					t.from = screen_at
					hud.move_child(t.node, hud.get_child_count() - 1)
			"fly":
				t.t += dt
				var u := clampf(t.t / FLY_TIME, 0.0, 1.0)
				var p: Vector2 = t.from.lerp(truck_bed_on_screen(), u) + Vector2(0, -44.0 * sin(u * PI))
				t.node.position = p.round()
				t.node.rotation = floorf(t.t * 8.0) * PI * 0.5
				if u >= 1.0:
					t.state = "truck"
					t.node.queue_free()
					t.node = null
					in_truck += 1
					Game.found.append(t.kind)
					_hud_bounce = 0.2
					Sfx.play("truck_clunk", 1.0 + 0.03 * in_truck)


func _fountain(dt: float) -> void:
	fountain_t -= dt
	if fountain_t > 0.0:
		return
	fountain_t = Rules.FOUNTAIN_EVERY
	for t in treasures:
		if t.state == "buried":
			var c: Vector2i = t.cell + Vector2i(2, 2)
			grid.dig_circle(c, 3.0)
			var at := _rect_center(t.rect)
			bursts.burst(at, _band_at(at), 10)
			return


## The unfound treasure nearest the digger, or {} (camera lead, demo driver).
func nearest_buried() -> Dictionary:
	var best := {}
	var best_d := INF
	for t in treasures:
		if t.state == "buried":
			var dd := body.pos.distance_squared_to(_rect_center(t.rect))
			if dd < best_d:
				best_d = dd
				best = t
	return best


func treasure_center(t: Dictionary) -> Vector2:
	return _rect_center(t.rect)


func _start_celebration() -> void:
	state = State.CELEBRATE
	celebrate_t = CELEBRATE_SECONDS
	Sfx.play("ready")


func _finish() -> void:
	state = State.DONE
	Game.last_run_time = time
	Game.goto("party")


# ================================================================ small finds

func _uncover_find(f: Dictionary) -> void:
	f.state = "out"
	f.t = 0.0
	grid.dig_rect(f.rect)
	var n := Art.sprite(f.kind, Color("#94b0c2"), Vector2i(16, 16))
	n.position = _rect_center(f.rect)
	things_layer.add_child(n)
	f.node = n
	f.home = n.position
	f.dir = -1.0 if body.pos.x > n.position.x else 1.0
	n.flip_h = f.dir < 0.0 and f.kind in ["worm", "snail"]
	match f.kind:
		"worm":
			Sfx.play("worm_squeak")
		"snail":
			Sfx.play("worm_squeak", 0.7)
		"mole":
			Sfx.play("mole_hello")
		_:
			Sfx.play("glint", 0.8)
			_sparkles(n.position, 1)


func _update_finds(dt: float) -> void:
	for f in finds:
		if f.state != "out":
			continue
		f.t += dt
		var n: AnimatedSprite2D = f.node
		var home: Vector2 = f.home
		match f.kind:
			"worm":
				n.position = (home + Vector2(f.dir * 12.0 * f.t, 0)).round()
			"snail":
				n.position = (home + Vector2(f.dir * 4.0 * f.t, 0)).round()
			"bone", "fossil":
				var hop := absf(sin(minf(f.t, 1.2) * PI * 2.0 / 1.2)) * (8.0 - 5.0 * minf(f.t, 1.2))
				n.position = (home + Vector2(0, -hop)).round()
		if f.t > FIND_TIME - 0.6:
			n.visible = int(f.t * 10.0) % 2 == 0
		if f.t >= FIND_TIME:
			f.state = "gone"
			n.queue_free()
			f.node = null


# ================================================================ glints and fx

func _update_glints(dt: float) -> void:
	for t in treasures:
		if t.state != "buried":
			continue
		t.glint_t -= dt
		if t.glint_t > 0.0:
			continue
		t.glint_t = Rules.GLINT_EVERY + rng.randf_range(-0.3, 0.3)
		var at := _rect_center(t.rect)
		var dist := body.pos.distance_to(at)
		var depth := grid.dirt_depth(t.cell + Vector2i(2, 2), Rules.GLINT_REVEAL_CELLS)
		if depth > Rules.GLINT_REVEAL_CELLS and dist > Rules.GLINT_NEAR_PX:
			continue
		var top := 3 if dist < 60.0 else (2 if dist < 140.0 else 1)
		var g := Art.sprite("glint", Color("#f4f4f4"), Vector2i(8, 8))
		g.stop()
		g.position = (at + Vector2(rng.randi_range(-5, 5), rng.randi_range(-5, 5))).round()
		fx_layer.add_child(g)
		fx.append({"node": g, "t": 0.0, "life": 0.12 * (2 * top + 1), "kind": "glint", "top": top})
		if dist < 90.0 and _on_screen(at):
			Sfx.play("glint", 1.0 + 0.1 * (3 - top), -10.0 + 3.0 * top)


func _sparkles(at: Vector2, count: int) -> void:
	for i in count:
		var g := Art.sprite("glint", Color("#f4f4f4"), Vector2i(8, 8))
		g.stop()
		g.position = (at + Vector2(rng.randi_range(-10, 10), rng.randi_range(-10, 6))).round()
		fx_layer.add_child(g)
		fx.append({"node": g, "t": -0.08 * i, "life": 0.84, "kind": "glint", "top": 3})


func _add_ring(at: Vector2, life: float, small: bool) -> void:
	var r := Art.sprite("boom_ring", Players.SEAT_COLORS[BOOMER], Vector2i(64, 64))
	r.stop()
	r.position = at.round()
	fx_layer.add_child(r)
	fx.append({"node": r, "t": 0.0, "life": life, "kind": "ring_small" if small else "ring"})


func _confetti(at: Vector2, count: int) -> void:
	for i in count:
		var c := Art.sprite("confetti", CONFETTI_TINTS[i % CONFETTI_TINTS.size()], Vector2i(4, 4))
		c.stop()
		c.frame = rng.randi() % 6
		fx_layer.add_child(c)
		fx.append({"node": c, "t": 0.0, "life": 1.4, "kind": "confetti", "pos": at,
			"vel": Vector2(rng.randf_range(-50, 50), rng.randf_range(-90, -30))})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var e := fx[i]
		e.t += dt
		var n: AnimatedSprite2D = e.node
		var u := clampf(e.t / e.life, 0.0, 1.0)
		match e.kind:
			"glint":
				n.visible = e.t >= 0.0
				var top: int = e.top
				# 0 .. top .. 0: a twinkle that grows and fades back.
				var k := int(u * (2 * top + 1))
				n.frame = clampi(top - absi(k - top), 0, 3)
			"ring":
				n.frame = mini(4, int(u * 5.0))
			"ring_small":
				n.frame = mini(1, int(u * 2.0))
			"confetti":
				e.vel.y += 160.0 * dt
				e.pos += e.vel * dt
				n.position = e.pos.round()
		if e.t >= e.life:
			n.queue_free()
			fx.remove_at(i)


# ================================================================ camera and nodes

func _update_camera(dt: float, snap := false) -> void:
	var target := body.pos - Vector2(W / 2.0, H / 2.0 + 10.0)
	var near := nearest_buried()
	if not near.is_empty():
		var to := _rect_center(near.rect) - body.pos
		target += to.normalized() * minf(Rules.CAMERA_LEAD_PX, to.length() * 0.3)
	var max_x := float(grid.w * Grid.CELL - W)
	var max_y := float(grid.h * Grid.CELL - H)
	target = Vector2(clampf(target.x, 0.0, max_x), clampf(target.y, WORLD_TOP, max_y))
	cam = target if snap else cam.lerp(target, 1.0 - exp(-5.0 * dt))


func _place_nodes() -> void:
	var shake := Vector2.ZERO
	if shake_t > 0.0:
		shake = Vector2(rng.randi_range(-2, 2), rng.randi_range(-1, 1))
	world.position = -cam.round() + shake
	var wob := Vector2(1 if int(wobble_t * 30.0) % 2 == 0 else -1, 0) if wobble_t > 0.0 else Vector2.ZERO
	rig.position = body.pos.round() + wob
	# Digger frames: 0-1 drive bob, 2-3 dig shake.
	if digging_t > 0.0:
		digger.frame = 2 + int(_anim_t * 14.0) % 2
	elif moving:
		digger.frame = int(_anim_t * 8.0) % 2
	else:
		digger.frame = int(_anim_t * 2.5) % 2
	digger.flip_h = _flip
	# Riders: the driver in the seat, the scooper at the front by the arm,
	# the boomer on the engine hood (those two behind the digger's body).
	var sx := -1.0 if _flip else 1.0
	var spots := [Vector2(0, -9), Vector2(11, -12), Vector2(-11, -13)]
	for s in 3:
		var rv: Node2D = riders[s]
		if rv:
			rv.position = Vector2(spots[s].x * sx, spots[s].y)
			rv.flip(_flip)
	# Arms: the scooper's rests pointing its way and reaches out on a scoop.
	_place_arm(arm, aim, arm_t)
	arm.visible = Players.is_seated(SCOOPER)
	driver_arm.visible = driver_arm_t > 0.0
	_place_arm(driver_arm, body.facing, driver_arm_t)
	# The HUD truck stands in for the real one only while it is off screen.
	hud_truck.visible = not _world_truck_visible()
	var frame := Rules.truck_frame(in_truck, treasures.size())
	world_truck.frame = frame
	hud_truck.frame = frame
	hud_truck.position = HUD_TRUCK + Vector2(0, -2 if _hud_bounce > 0.0 else 0)


func _place_arm(a: AnimatedSprite2D, dir: Vector2i, t: float) -> void:
	var reach := ARM_BASE + (ARM_REACH * sin(clampf(t / ARM_TIME, 0.0, 1.0) * PI) if t > 0.0 else 0.0)
	a.position = (Vector2(dir) * reach).round()
	a.rotation = Vector2(dir).angle()


func _world_truck_visible() -> bool:
	return Rect2(cam.round(), Vector2(W, H)).grow(-6).has_point(world_truck.position + Vector2(-14, 0))


## Where flying treasures land, in screen pixels: the real truck's bed when
## it is on screen, else the HUD truck in the corner.
func truck_bed_on_screen() -> Vector2:
	if _world_truck_visible():
		return world_truck.position + Vector2(-10, -6) - cam.round()
	return HUD_BED


func _rect_center(r: Rect2i) -> Vector2:
	return Vector2(r.position * Grid.CELL) + Vector2(r.size * Grid.CELL) * 0.5


func _band_at(p: Vector2) -> int:
	var v := grid.get_cell(Grid.cell_of(p))
	if v == Grid.AIR:
		v = grid.band_at(Grid.cell_of(p).x, maxi(0, Grid.cell_of(p).y))
	return clampi(v, 1, 3) - 1 if v != Grid.ROCK else 3


func _on_screen(p: Vector2) -> bool:
	return Rect2(cam, Vector2(W, H)).grow(8).has_point(p)


## Dirt chunks flying out of every dig: a small pool of one-shot
## CPUParticles2D, one texture per depth band (dirt_chunk frames).
class DirtBursts extends Node2D:
	const POOL := 16
	var _pool: Array[CPUParticles2D] = []
	var _next := 0
	var _tex: Array[Texture2D] = []

	func _ready() -> void:
		var sf := Art.frames("dirt_chunk", Color("#ef7d57"), Vector2i(4, 4))
		for i in 4:
			_tex.append(sf.get_frame_texture("default", mini(i, sf.get_frame_count("default") - 1)))
		for i in POOL:
			var p := CPUParticles2D.new()
			p.one_shot = true
			p.emitting = false
			p.amount = 8
			p.lifetime = 0.55
			p.explosiveness = 0.95
			p.direction = Vector2(0, -1)
			p.spread = 75.0
			p.gravity = Vector2(0, 320)
			p.initial_velocity_min = 40.0
			p.initial_velocity_max = 95.0
			p.emission_shape = CPUParticles2D.EMISSION_SHAPE_SPHERE
			p.emission_sphere_radius = 3.0
			add_child(p)
			_pool.append(p)

	## `band` 0..3 (topsoil, clay, deep, rock). `count` scales how many emitters fire.
	func burst(at: Vector2, band: int, count: int) -> void:
		for k in clampi(ceili(count / 8.0), 1, 3):
			var p := _pool[_next]
			_next = (_next + 1) % POOL
			p.texture = _tex[clampi(band, 0, _tex.size() - 1)] if not _tex.is_empty() else null
			p.position = at.round()
			p.restart()
			p.emitting = true


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
