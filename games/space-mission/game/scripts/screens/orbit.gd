extends Node2D
## Stage 1, Earth orbit: build the station.
##
## - Pilot: flies the Shuttle (damped, stops itself). A = boost. Bumping the
##   station is a soft "boing". Idle for AUTO seconds, the autopilot takes over.
## - Arm: moves the arm tip in 4 directions, A grabs (snap within SNAP_R) and
##   lets go. Near its own port a held module is pulled in and clicks. Idle for
##   AUTO seconds (or no Arm seat), the arm works by itself.
## - Camera: any press flashes, photographs the view (golden during an Earth
##   moment) and blinks the station's lights. With no Camera seat, the Pilot's
##   B takes photos (and the Pilot's A when playing alone).
## After 5 modules the Shuttle docks (a strong assist, done within 5 s), the
## astronauts float out and flip, then the Mars landing starts.
## All logic runs in step(dt), so tests drive it frame by frame.

const Flight := preload("res://scripts/logic/space_flight.gd")
const Station := preload("res://scripts/logic/station.gd")
const ArmIK := preload("res://scripts/logic/arm_ik.gd")
const Photos := preload("res://scripts/logic/photos.gd")
const Earth := preload("res://scripts/view/earth.gd")
const Starfield := preload("res://scripts/view/starfield.gd")
const ArmView := preload("res://scripts/view/arm_view.gd")
const PauseView := preload("res://scripts/view/pause.gd")
const Tex := preload("res://scripts/view/tex.gd")

enum Phase { BUILD, DOCKING, CELEBRATE, DONE }

const AUTO := 5.0
const START := Vector2(84, 74)
const BOUNDS := Rect2(28, 20, 264, 94)
const SHOULDER := Vector2(-4, -6)     # the arm's shoulder, from the Shuttle's centre
const ARM_L1 := 23.0
const ARM_L2 := 23.0
const ARM_MIN := 8.0
const ARM_REST := Vector2(18, -10)    # tip relative to the shoulder when stowed
const ARM_SPEED := 44.0
const SNAP_R := 12.0
const HAND_MAGNET_R := 20.0
const MAGNET_SPEED := 36.0
const RESPAWN := 1.5
const DOCK_RING := Vector2(-42, 0)    # from the core: the ring on the lab's end
const DOCK_OFFSET := Vector2(-28, 0)  # the Shuttle's centre when docked, from the ring
const CELEBRATE_TIME := 9.0
const PHOTO_GAP := 0.25
const MOMENT_EVERY := 11.0
const MOMENT_LEN := 4.5
const MOMENT_FIRST := 6.0
const GLEAM_TIME := 2.0

## Tests: record next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var phase := Phase.BUILD
var flight: Flight
var station: Station
## The floating (or held) cargo: {kind, pos, held, loops}; empty when none.
var cargo := {}
var holding := false
## Arm tip relative to the shoulder.
var tip_rel := ARM_REST
var pilot_idle := 0.0
var arm_idle := 0.0
var autopilot := false
var arm_autorun := false
var respawn_t := 0.0
var dock_t := 0.0
var celebrate_t := 0.0
var stage_t := 0.0
var photo_cd := 0.0
var flash_t := 0.0
var lights_t := 0.0
var bump_t := 0.0
var clack_t := 0.0
var sunrise_count := 0
var gleam_t := 0.0
var waves := 0
var events: Array[String] = []   # this frame's events (tests read them)
## Photos: returns an Image of the view. Tests replace it with a fake.
var capture_source: Callable
## Per-slot unfold timers (solar wings animate open after clicking in).
var unfold := [0.0, 0.0, 0.0, 0.0, 0.0]
var astronauts: Array[Dictionary] = []
var fx: Array[Dictionary] = []    # {name, pos, t, len}
var flying_photos: Array[Dictionary] = []

var _stars: Node2D
var _earth: Node2D
var _world: Node2D
var _shuttle: AnimatedSprite2D
var _cargo_sprite: AnimatedSprite2D
var _arm: Node2D
var _hud: Node2D
var _pause: Node2D
var _modules: Array[AnimatedSprite2D] = []
var _ports: Array[AnimatedSprite2D] = []
var _core: AnimatedSprite2D
var _ring: AnimatedSprite2D
var _sfx_cd := {}
var _scale := 1.0


func _ready() -> void:
	_scale = Game.mission_scale
	flight = Flight.new(START)
	flight.bounds = BOUNDS
	station = Station.new()
	capture_source = func() -> Image: return Photos.grab(get_viewport())
	_build()
	Sfx.music("music_orbit")
	Sfx.play("quindar_in")
	_spawn_cargo()


func _process(delta: float) -> void:
	step(delta)


# ---------------------------------------------------------------- the frame

func step(dt: float) -> void:
	events.clear()
	if _pause.check():
		return
	stage_t += dt
	for k in _sfx_cd:
		_sfx_cd[k] = maxf(0.0, _sfx_cd[k] - dt)
	photo_cd = maxf(0.0, photo_cd - dt)
	flash_t = maxf(0.0, flash_t - dt)
	lights_t = maxf(0.0, lights_t - dt)
	bump_t = maxf(0.0, bump_t - dt)
	clack_t = maxf(0.0, clack_t - dt)
	gleam_t = maxf(0.0, gleam_t - dt)
	_earth.gleam = clampf(gleam_t / GLEAM_TIME * 2.0, 0.0, 1.0)
	_earth.tick(dt)
	_stars.tick(dt)
	_sunrise_check()
	if Game.camera_pressed():
		take_photo()
	match phase:
		Phase.BUILD:
			_fly(dt)
			_arm_step(dt)
			_cargo_step(dt)
		Phase.DOCKING:
			_dock_step(dt)
			_stow_arm(dt)
		Phase.CELEBRATE:
			_celebrate_step(dt)
			_stow_arm(dt)
	for i in unfold.size():
		if station.fitted[i]:
			unfold[i] += dt
	_fx_step(dt)
	_layout()


# ---------------------------------------------------------------- the Shuttle

func pilot_goal() -> Vector2:
	if phase != Phase.BUILD:
		return dock_pos()
	if holding:
		var slot := station.target_slot(cargo.kind, cargo.pos)
		if slot != -1:
			return station.core + Station.SLOTS[slot].approach
	if not cargo.is_empty():
		return _clamp_bounds(cargo.pos + Vector2(-20, 26))
	return _clamp_bounds(station.core + Vector2(-90, 10))


func dock_pos() -> Vector2:
	return station.core + DOCK_RING + DOCK_OFFSET


func _clamp_bounds(p: Vector2) -> Vector2:
	return Vector2(clampf(p.x, BOUNDS.position.x, BOUNDS.end.x), clampf(p.y, BOUNDS.position.y, BOUNDS.end.y))


func _fly(dt: float) -> void:
	var stick := Players.move(Players.Seat.DRIVER)
	var boost := Players.pressed(Players.Seat.DRIVER, "a")
	if stick.length() > 0.2 or boost:
		pilot_idle = 0.0
	else:
		pilot_idle += dt
	autopilot = pilot_idle >= AUTO
	if autopilot:
		stick = Flight.stick_toward(flight.pos, flight.vel, pilot_goal())
		boost = false
	var fired := flight.step(dt, stick, boost)
	if fired and not autopilot:
		_sound("thruster", 0.4, 0.9 + randf() * 0.2, -4.0)
	if flight.push_out(station.bounds()):
		bump_t = 0.3
		events.append("boing")
		_sound("boing", 0.3)


# ---------------------------------------------------------------- the arm

func shoulder() -> Vector2:
	return flight.pos + SHOULDER


func tip() -> Vector2:
	return shoulder() + tip_rel


## Where the arm is heading: the cargo, or the held module's port.
func arm_goal() -> Vector2:
	if holding:
		var slot := station.target_slot(cargo.kind, cargo.pos)
		return station.port_pos(slot) if slot != -1 else tip()
	if not cargo.is_empty():
		return cargo.pos
	return shoulder() + ARM_REST


func _arm_step(dt: float) -> void:
	var g := Players.Seat.GUNNER
	var dir := Vector2(Players.dir4(g)) if Players.is_seated(g) else Vector2.ZERO
	var a_pressed := Players.is_seated(g) and Players.just_pressed(g, "a")
	if dir != Vector2.ZERO or a_pressed:
		arm_idle = 0.0
	else:
		arm_idle += dt
	arm_autorun = Game.arm_auto() or arm_idle >= AUTO
	if dir != Vector2.ZERO:
		tip_rel += dir * ARM_SPEED * dt
		_sound("arm_move", 0.35, 1.0, -6.0)
	var goal := arm_goal()
	var goal_rel := goal - shoulder()
	var reachable := ArmIK.in_reach(Vector2.ZERO, goal_rel, ARM_L1, ARM_L2, ARM_MIN)
	if arm_autorun and dir == Vector2.ZERO and (holding or not cargo.is_empty()) and reachable:
		tip_rel = tip_rel.move_toward(goal_rel, ARM_SPEED * dt)
	# Magnets: the hand is pulled onto a nearby cargo, a held module onto its port.
	if not holding and not cargo.is_empty() and tip().distance_to(cargo.pos) <= HAND_MAGNET_R:
		tip_rel = tip_rel.move_toward(cargo.pos - shoulder(), MAGNET_SPEED * dt)
	if holding:
		var slot := station.target_slot(cargo.kind, tip())
		if slot != -1 and tip().distance_to(station.port_pos(slot)) <= Station.MAGNET_R:
			tip_rel = tip_rel.move_toward(station.port_pos(slot) - shoulder(), MAGNET_SPEED * dt)
	tip_rel = ArmIK.clamp_reach(Vector2.ZERO, tip_rel, ARM_L1, ARM_L2, ARM_MIN)
	if holding:
		cargo.pos = tip()
		var fit_slot := station.can_dock(cargo.kind, tip())
		if fit_slot != -1:
			_fit(fit_slot)
			return
		if a_pressed:
			_let_go()
		return
	var near := not cargo.is_empty() and tip().distance_to(cargo.pos) <= SNAP_R
	if near and (a_pressed or arm_autorun):
		grab()
	elif a_pressed:
		clack_t = 0.25
		_sound("grab", 0.2, 1.4, -8.0)


func grab() -> void:
	holding = true
	cargo.held = true
	cargo.pos = tip()
	events.append("grab")
	Sfx.play("grab")


func _let_go() -> void:
	var wrong := station.wrong_port_near(cargo.kind, tip(), Station.MAGNET_R)
	if wrong != -1:
		# A module never fits another kind's port: a soft boing, still held.
		events.append("wrong_port")
		_sound("boing", 0.3, 1.3)
		return
	holding = false
	cargo.held = false
	events.append("let_go")
	_sound("whoosh", 0.3, 1.4, -6.0)


func _fit(slot: int) -> void:
	station.fit(slot)
	Game.modules.append(station.kind_of(slot))
	events.append("fit")
	unfold[slot] = 0.0
	_add_fx("sparkle", station.port_pos(slot), 0.6)
	Sfx.play("clunk")
	if station.kind_of(slot) == "solar":
		Sfx.play("solar_unfold", 1.0, -3.0)
	holding = false
	cargo = {}
	respawn_t = RESPAWN * _scale
	if station.done():
		phase = Phase.DOCKING
		dock_t = 0.0
		Sfx.play("quindar_in", 1.0, -4.0)


func _stow_arm(dt: float) -> void:
	tip_rel = tip_rel.move_toward(ARM_REST, ARM_SPEED * dt)


# ---------------------------------------------------------------- cargo

func _spawn_cargo() -> void:
	var kind := station.next_kind()
	if kind == "":
		return
	cargo = Station.new_cargo(kind)
	_cargo_sprite.sprite_frames = Art.frames("cargo_" + kind, Station.COLORS[kind], Vector2i(16, 16))
	_cargo_sprite.play("default")


func _cargo_step(dt: float) -> void:
	if cargo.is_empty():
		respawn_t -= dt
		if respawn_t <= 0.0:
			_spawn_cargo()
		return
	if not holding and Station.drift(cargo, dt):
		events.append("loop")


# ---------------------------------------------------------------- docking

func _dock_step(dt: float) -> void:
	dock_t += dt
	var stick := Players.move(Players.Seat.DRIVER)
	flight.step(dt, stick * 0.5)
	var goal := dock_pos()
	var pull := 20.0 + 50.0 * dock_t
	flight.pos = flight.pos.move_toward(goal, pull * dt)
	flight.vel *= 0.8
	if flight.pos.distance_to(goal) < 1.0:
		flight.pos = goal
		flight.vel = Vector2.ZERO
		Game.docked = true
		phase = Phase.CELEBRATE
		celebrate_t = 0.0
		events.append("docked")
		Sfx.play("dock")
		_spawn_astronauts()


# ---------------------------------------------------------------- the astronauts

func _spawn_astronauts() -> void:
	var i := 0
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s):
			continue
		var rider := Game.rider_of(s)
		var spr := Art.sprite("astronaut_" + rider, Game.rider_color(rider), Vector2i(24, 24))
		_world.add_child(spr)
		var a := {"seat": s, "sprite": spr, "pos": flight.pos + Vector2(4, -10),
			"vel": Vector2(-14.0 + 14.0 * i, -16.0 - 4.0 * i), "flip": 0.0, "rot": 0, "hop": 0.0}
		astronauts.append(a)
		i += 1


func _celebrate_step(dt: float) -> void:
	celebrate_t += dt
	var waved := Game.camera_pressed() or (Players.is_seated(Players.Seat.GUNNER) and Players.just_pressed(Players.Seat.GUNNER, "a"))
	if waved:
		waves += 1
		_sound("wave", 0.15)
	for a in astronauts:
		a.vel *= exp(-0.5 * dt)
		a.pos += a.vel * dt
		a.pos.x = clampf(a.pos.x, 16, 304)
		a.pos.y = clampf(a.pos.y, 34, 116)
		a.flip += dt
		if a.flip >= 0.45:   # zero-g flips: a quarter turn at a time
			a.flip = 0.0
			a.rot = (a.rot + 1) % 4
		if waved:
			a.hop = 0.3
		a.hop = maxf(0.0, a.hop - dt)
	if celebrate_t >= CELEBRATE_TIME * _scale:
		_finish()


func _finish() -> void:
	phase = Phase.DONE
	Sfx.play("quindar_out")
	next_screen = Game.next_after("orbit")
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


# ---------------------------------------------------------------- the camera

## An Earth moment (a hurricane, the aurora) or a sunrise gleam is on screen.
func moment() -> String:
	if gleam_t > 0.0:
		return "sunrise"
	if stage_t < MOMENT_FIRST:
		return ""
	var k := int((stage_t - MOMENT_FIRST) / MOMENT_EVERY)
	var into := fmod(stage_t - MOMENT_FIRST, MOMENT_EVERY)
	if into > MOMENT_LEN:
		return ""
	return ["hurricane", "aurora"][k % 2]


func take_photo() -> void:
	flash_t = 0.3
	lights_t = 1.5
	_sound("camera", 0.08)
	events.append("flash")
	if photo_cd > 0.0:
		return
	photo_cd = PHOTO_GAP
	var golden := moment() != ""
	var img: Image = capture_source.call() if capture_source.is_valid() else null
	var entry := Photos.store(Game.photos, img, golden)
	if entry.is_empty():
		return
	events.append("photo")
	if golden:
		Sfx.play("photo_golden", 1.0, -3.0)
	flying_photos.append({"tex": entry.tex, "golden": golden, "t": 0.0})


func _sunrise_check() -> void:
	var n := int(_earth.time / Earth.SUNRISE_EVERY)
	if n > sunrise_count:
		sunrise_count = n
		Game.sunrises += 1
		gleam_t = GLEAM_TIME
		events.append("sunrise")
		Sfx.play("sunrise_chime")


# ---------------------------------------------------------------- effects

func _add_fx(sprite_name: String, pos: Vector2, length: float) -> void:
	var s := Art.sprite(sprite_name, Color("#fee761"), Vector2i(8, 8))
	s.position = pos.round()
	_world.add_child(s)
	fx.append({"sprite": s, "t": 0.0, "len": length})


func _fx_step(dt: float) -> void:
	for f in fx:
		f.t += dt
		if f.t >= f.len:
			f.sprite.queue_free()
	fx = fx.filter(func(f): return f.t < f.len)
	for p in flying_photos:
		p.t += dt
	flying_photos = flying_photos.filter(func(p): return p.t < 1.0)


func _sound(sound: String, gap: float, pitch := 1.0, db := 0.0) -> void:
	if _sfx_cd.get(sound, 0.0) > 0.0:
		return
	_sfx_cd[sound] = gap
	Sfx.play(sound, pitch, db)


# ---------------------------------------------------------------- view

func _build() -> void:
	_stars = Starfield.new()
	add_child(_stars)
	_earth = Earth.new()
	add_child(_earth)
	_world = Node2D.new()
	add_child(_world)
	var moments := Moments.new()
	moments.orbit = self
	_world.add_child(moments)
	_core = Art.sprite("iss_core", Color("#c0cbdc"), Vector2i(32, 16))
	_core.stop()
	_core.position = station.core
	_world.add_child(_core)
	for i in Station.SLOTS.size():
		var kind: String = Station.SLOTS[i].kind
		var port := Art.sprite("iss_port", Color.WHITE, Vector2i(16, 16))
		port.modulate = Station.COLORS[kind]
		port.position = station.port_pos(i)
		port.stop()
		_world.add_child(port)
		_ports.append(port)
		var size := Vector2i(32, 16) if kind == "solar" else Vector2i(16, 16)
		var m := Art.sprite("iss_" + kind, Station.COLORS[kind], size)
		m.stop()
		m.position = station.port_pos(i)
		m.visible = false
		_world.add_child(m)
		_modules.append(m)
	_ring = Art.sprite("dock_ring", Color("#feae34"), Vector2i(16, 16))
	_ring.position = station.core + DOCK_RING
	_ring.visible = false
	_world.add_child(_ring)
	_cargo_sprite = Art.sprite("cargo_lab", Color("#0099db"), Vector2i(16, 16))
	_world.add_child(_cargo_sprite)
	_shuttle = Art.sprite("shuttle", Color("#ffffff"), Vector2i(48, 20))
	_shuttle.stop()
	_world.add_child(_shuttle)
	_arm = ArmView.new()
	_world.add_child(_arm)
	_hud = Hud.new()
	_hud.orbit = self
	add_child(_hud)
	_pause = PauseView.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	_layout()


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _layout() -> void:
	_shuttle.position = flight.pos.round()
	_shuttle.frame = 1 if (flight.vel.length() > 3.0 and int(stage_t * 12.0) % 2 == 0) else 0
	if bump_t > 0.0:
		_shuttle.position.x += (1 if int(bump_t * 40.0) % 2 == 0 else -1)
	var solved := ArmIK.solve(shoulder(), tip(), ARM_L1, ARM_L2, 1.0)
	_arm.closed = holding or clack_t > 0.0
	_arm.set_pose(shoulder(), solved.elbow, solved.tip)
	_cargo_sprite.visible = not cargo.is_empty()
	if not cargo.is_empty():
		_cargo_sprite.position = cargo.pos.round()
	var lights_on := lights_t > 0.0 and int(lights_t * 7.0) % 2 == 0
	_core.frame = 1 if lights_on else 0
	var want_kind: String = cargo.get("kind", "")
	for i in _modules.size():
		var kind: String = Station.SLOTS[i].kind
		_modules[i].visible = station.fitted[i]
		if station.fitted[i]:
			if kind == "solar":
				_modules[i].frame = clampi(int(unfold[i] / 0.25), 0, 3)
			else:
				_modules[i].frame = 1 if lights_on else 0
		_ports[i].visible = not station.fitted[i]
		var glow := kind == want_kind and int(stage_t * 3.0) % 2 == 0
		_ports[i].frame = 1 if glow else 0
		_ports[i].modulate.a = 1.0 if kind == want_kind else 0.5
	_ring.visible = phase == Phase.DOCKING
	_ring.frame = int(stage_t * 4.0) % 2
	for a in astronauts:
		var spr: AnimatedSprite2D = a.sprite
		spr.position = (a.pos + Vector2(0, -3 if a.hop > 0.0 else 0)).round()
		spr.rotation = a.rot * PI * 0.5
	_hud.queue_redraw()


## Earth moments drawn on the globe: the hurricane swirl, the aurora at the
## limb and the golden sunrise line.
class Moments extends Node2D:
	var orbit: Node2D
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var m: String = orbit.moment()
		var into: float = fmod(orbit.stage_t - orbit.MOMENT_FIRST, orbit.MOMENT_EVERY)
		var f := int(_t * 6.0)
		if m == "hurricane":
			var tex := Tex.frame("hurricane", f, Color("#ffffff"), Vector2i(16, 16))
			draw_texture(tex, Vector2(roundf(96 + into * 14.0), 148))
		elif m == "aurora":
			var tex := Tex.frame("aurora", f, Color("#63c74d"), Vector2i(48, 16))
			draw_texture(tex, Vector2(roundf(40 + into * 8.0), 120))
			draw_texture(tex, Vector2(roundf(88 + into * 8.0), 118))
		if orbit.gleam_t > 0.0:
			# The golden gleam hugs the curved limb: one column of the strip per x.
			var tex := Tex.frame("sunrise_line", f, Color("#feae34"), Vector2i(320, 4))
			var c: Vector2 = Earth.CENTER + Vector2(0, Earth.TOP)
			var r2: float = (Earth.RADIUS + 3.0) * (Earth.RADIUS + 3.0)
			for x in 320:
				var dx := x + 0.5 - c.x
				if dx * dx >= r2:
					continue
				var y := floorf(c.y - sqrt(r2 - dx * dx)) - 1.0
				draw_texture_rect_region(tex, Rect2(x, y, 1, 4), Rect2(x, 0, 1, 4))


## The HUD (no text): the module row, the sunrise suns, the photo stack, the
## flash, the flying polaroids.
class Hud extends Node2D:
	var orbit: Node2D

	func _draw() -> void:
		var st = orbit.station
		# The five modules to build: dim until fitted.
		for i in st.SLOTS.size():
			var kind: String = st.SLOTS[i].kind
			var tex := Tex.frame("cargo_" + kind, 0, st.COLORS[kind], Vector2i(16, 16))
			var p := Vector2(112 + i * 20, 2)
			draw_rect(Rect2(p - Vector2(1, 1), Vector2(18, 18)), Color("#262b44"))
			draw_texture(tex, p, Color.WHITE if st.fitted[i] else Color(0.35, 0.35, 0.45))
		# Sunrises so far: little suns, top right.
		var sun := Tex.frame("sun_icon", 0, Color("#feae34"), Vector2i(8, 8))
		for i in mini(Game.sunrises, 12):
			draw_texture(sun, Vector2(308 - i * 10, 3))
		# The photo stack, top left: the last few thumbnails as mini polaroids.
		var n: int = Game.photos.size()
		for k in mini(n, 4):
			var ph: Dictionary = Game.photos[n - 1 - k]
			var p := Vector2(4 + k * 3, 3 + k * 2)
			draw_rect(Rect2(p, Vector2(20, 14)), Color("#feae34") if ph.golden else Color("#ffffff"))
			draw_texture_rect(ph.tex, Rect2(p + Vector2(2, 2), Vector2(16, 9)), false)
		for fp in orbit.flying_photos:
			var t: float = fp.t
			var size := Vector2(64, 36).lerp(Vector2(16, 9), t)
			var pos := Vector2(128, 60).lerp(Vector2(6, 5), t * t).round()
			draw_rect(Rect2(pos - Vector2(3, 3), size.round() + Vector2(6, 9)),
				Color("#feae34") if fp.golden else Color("#ffffff"))
			draw_texture_rect(fp.tex, Rect2(pos, size.round()), false)
		if orbit.flash_t > 0.0:
			draw_rect(Rect2(0, 0, 320, 180), Color(1, 1, 1, clampf(orbit.flash_t / 0.3, 0.0, 1.0) * 0.45))
