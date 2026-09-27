extends Node2D
## Stage 3, the Mars surface: explore.
##
## - Driver: left/right drives, A brakes. Nothing hurts the rover; bumps only
##   wobble it. Idle for 5 s, it rolls on by itself.
## - Arm: sparkling science rocks come within reach; a direction picks one and
##   A drills it (rumble, then a sample capsule of the rock's colour pops into
##   the rover's tray). A drill with nothing in reach just pokes the ground.
##   A rock left in reach for 5 s (1 s with no Arm seat) is drilled for you.
## - Camera: any press launches the helicopter, which scouts ahead and shines a
##   spotlight on the next rock (then rests 3 s); presses while it flies make it
##   loop. With no Camera seat it launches itself now and then.
## At the end of the world: the blue Mars sunset, the rover phones home (a beam
## to a tiny Earth), then the party. Logic in step(dt).

const Terrain := preload("res://scripts/logic/terrain.gd")
const Rover := preload("res://scripts/logic/rover.gd")
const Heli := preload("res://scripts/logic/helicopter.gd")
const ArmIK := preload("res://scripts/logic/arm_ik.gd")
const Aim := preload("res://scripts/logic/aim.gd")
const MarsSky := preload("res://scripts/view/mars_sky.gd")
const ArmView := preload("res://scripts/view/arm_view.gd")
const PauseView := preload("res://scripts/view/pause.gd")
const LoopAudio := preload("res://scripts/view/loop_audio.gd")
const Tex := preload("res://scripts/view/tex.gd")

enum Phase { EXPLORE, SUNSET, PHONE, DONE }

const WORLD_W := 3600
const MIN_WORLD := 900
const AUTO := 5.0
const AUTO_EMPTY := 1.0
const DRILL_RANGE := 34.0
const DRILL_TIME := 1.3
const POKE_TIME := 0.5
const ARM_REACH := 13.0          # each of the rover arm's two bones
const ARM_SHOULDER := Vector2(16, -4)
const TOOL_OFF := 20.0           # the rover's reach point ahead of its centre
const HELI_EVERY := 9.0
const SUNSET_TIME := 4.0
const PHONE_TIME := 5.0
const SUNSET_MARGIN := 150.0
const EARTH_DOT := Vector2(62, 26)
const CAM_LEAD := 110.0

var auto_goto := true
var next_screen := ""

var phase := Phase.EXPLORE
var terrain: Terrain
var rover: Rover
var heli: Heli
var targets: Array[Dictionary] = []
var world_w := WORLD_W
var cam_x := 0.0
var t := 0.0
var stage_t := 0.0
## Drilling: the target index being drilled (-1 none), its timer; a poke timer.
var drilling := -1
var drill_t := 0.0
var poke_t := 0.0
var in_range_t := 0.0
var heli_auto_t := 0.0
var events: Array[String] = []
var tray: Array[String] = []     # samples in this rover's tray (this stage)
var popping: Array[Dictionary] = []
var sparks: Array[Dictionary] = []

var _sky: Node2D
var _world: Node2D
var _ground: Polygon2D
var _view: Node2D
var _arm: Node2D
var _hud: Node2D
var _pause: Node2D
var _hum: AudioStreamPlayer
var _buzz: AudioStreamPlayer
var _sfx_cd := {}


func _ready() -> void:
	world_w = maxi(MIN_WORLD, int(WORLD_W * Game.mission_scale))
	var site := Game.site if Game.site != "" else "dunes"
	terrain = Terrain.new(world_w, site)
	targets = terrain.targets()
	rover = Rover.new()
	rover.max_x = world_w - 20.0
	rover.place(Terrain.LAND_X, terrain)
	heli = Heli.new()
	heli.pos = heli_home()
	_build()
	Sfx.music("music_mars")
	Sfx.play("quindar_in")


func _process(delta: float) -> void:
	step(delta)


# ---------------------------------------------------------------- the frame

func step(dt: float) -> void:
	events.clear()
	if _pause.check():
		return
	t += dt
	stage_t += dt
	for k in _sfx_cd:
		_sfx_cd[k] = maxf(0.0, _sfx_cd[k] - dt)
	_helicopter(dt)
	match phase:
		Phase.EXPLORE:
			_drive(dt)
			_arm_step(dt)
			if rover.x >= world_w - SUNSET_MARGIN:
				phase = Phase.SUNSET
				t = 0.0
				events.append("sunset")
		Phase.SUNSET:
			rover.step(dt, terrain, 0.0, true)
			_arm_step(dt)
			_sky.blend = clampf(t / SUNSET_TIME, 0.0, 1.0)
			_sky.sun = Vector2(236, roundf(lerpf(44.0, 70.0, _sky.blend)))
			if t >= SUNSET_TIME:
				phase = Phase.PHONE
				t = 0.0
				Game.phoned_home = true
				events.append("phone_home")
				Sfx.play("phone_home")
		Phase.PHONE:
			rover.step(dt, terrain, 0.0, true)
			if t >= PHONE_TIME:
				_finish()
	for p in popping:
		p.t += dt
	popping = popping.filter(func(p): return p.t < 0.7)
	for s in sparks:
		s.t += dt
	sparks = sparks.filter(func(s): return s.t < 0.5)
	cam_x = clampf(rover.x - CAM_LEAD, 0.0, float(world_w - 320))
	LoopAudio.set_on(_hum, absf(rover.speed) > 2.0)
	if _hum:
		_hum.volume_db = -16.0 + 8.0 * clampf(absf(rover.speed) / Rover.MAX_SPEED, 0.0, 1.0)
	LoopAudio.set_on(_buzz, heli.flying())
	_layout()


func _drive(dt: float) -> void:
	var d := Players.Seat.DRIVER
	var drive := Players.move(d).x
	var brake := Players.pressed(d, "a") and Players.seated_count() > 1
	rover.step(dt, terrain, drive, brake, drilling != -1 or poke_t > 0.0)


# ---------------------------------------------------------------- drilling

func reach_point() -> Vector2:
	return Vector2(rover.x + TOOL_OFF, terrain.height_at(rover.x + TOOL_OFF))


## Undrilled targets within the arm's reach, nearest first.
func in_range() -> Array[int]:
	var out: Array[int] = []
	var rp := rover.x + TOOL_OFF
	for i in targets.size():
		if not targets[i].drilled and absf(targets[i].x - rp) <= DRILL_RANGE:
			out.append(i)
	out.sort_custom(func(a, b): return absf(targets[a].x - rp) < absf(targets[b].x - rp))
	return out


func target_pos(i: int) -> Vector2:
	var x: float = targets[i].x
	return Vector2(x, terrain.height_at(x) - 5.0)


## The target the Arm's direction picks (the aim cone), or the nearest in reach.
func pick(dir: Vector2i) -> int:
	var near := in_range()
	if near.is_empty():
		return -1
	if dir == Vector2i.ZERO or dir == Vector2i.DOWN or dir == Vector2i.UP:
		return near[0]
	var origin := Vector2(rover.x + 10.0, rover.body_y())
	var pts := []
	for i in near:
		pts.append(target_pos(i))
	var k := Aim.pick_target(origin, Vector2(dir), pts, 160.0, 80.0)
	return near[k] if k != -1 else near[0]


func _arm_step(dt: float) -> void:
	if drilling != -1:
		drill_t += dt
		if int(drill_t * 20.0) % 3 == 0:
			sparks.append({"pos": target_pos(drilling) + Vector2(randf_range(-3, 3), randf_range(-3, 1)), "t": 0.0})
		if drill_t >= DRILL_TIME:
			_collect(drilling)
		return
	if poke_t > 0.0:
		poke_t = maxf(0.0, poke_t - dt)
		return
	if phase != Phase.EXPLORE:
		return
	var g := Players.Seat.GUNNER
	var seated := Players.is_seated(g)
	var dir := Players.dir4(g) if seated else Vector2i.ZERO
	var a := seated and Players.just_pressed(g, "a")
	var near := in_range()
	if near.is_empty():
		in_range_t = 0.0
	else:
		in_range_t += dt
	if a:
		var i := pick(dir)
		if i != -1:
			start_drill(i)
		else:
			poke_t = POKE_TIME   # a miss just pokes the ground; try again
			events.append("poke")
			_sound("drill", 0.4, 1.5)
			for k in 3:
				sparks.append({"pos": reach_point() + Vector2(k * 2 - 2, -1), "t": 0.0})
		return
	var wait := AUTO_EMPTY if Game.arm_auto() else AUTO
	if not near.is_empty() and in_range_t >= wait:
		start_drill(near[0])


func start_drill(i: int) -> void:
	drilling = i
	drill_t = 0.0
	in_range_t = 0.0
	events.append("drill")
	Sfx.play("drill")


func _collect(i: int) -> void:
	var kind: String = targets[i].kind
	targets[i].drilled = true
	Game.samples.append(kind)
	tray.append(kind)
	drilling = -1
	drill_t = 0.0
	events.append("sample")
	popping.append({"kind": kind, "from": target_pos(i), "t": 0.0})
	Sfx.play("sample_pop", 1.2 if kind in ["ice", "shell"] else 1.0)


# ---------------------------------------------------------------- the helicopter

func heli_home() -> Vector2:
	return Vector2(rover.x - 8.0, rover.body_y() - 14.0)


## The next undrilled target ahead of the rover (the helicopter scouts it).
func next_target() -> int:
	for i in targets.size():
		if not targets[i].drilled and targets[i].x > rover.x + TOOL_OFF + 6.0:
			return i
	return -1


func _helicopter(dt: float) -> void:
	var pressed := Game.camera_pressed()
	if not Players.is_seated(Players.Seat.HONKER):
		heli_auto_t += dt
		if heli_auto_t >= HELI_EVERY and heli.can_launch():
			pressed = true
			heli_auto_t = 0.0
	if pressed:
		if heli.can_launch():
			if heli.launch(next_target()):
				events.append("heli_up")
				Sfx.play("whoosh", 1.3, -4.0)
		elif heli.press():
			events.append("heli_loop")
			Sfx.play("heli_loop")
	var tp := target_pos(heli.target) if heli.target != -1 else Vector2.ZERO
	var ev := heli.step(dt, heli_home(), tp)
	if ev == "revealed":
		targets[heli.target].revealed = true
		events.append("revealed")
		Sfx.play("sample_pop", 1.6, -6.0)


func _finish() -> void:
	phase = Phase.DONE
	Sfx.play("quindar_out")
	LoopAudio.set_on(_hum, false)
	LoopAudio.set_on(_buzz, false)
	next_screen = "party"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("party")


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _sound(sound: String, gap: float, pitch := 1.0) -> void:
	if _sfx_cd.get(sound, 0.0) > 0.0:
		return
	_sfx_cd[sound] = gap
	Sfx.play(sound, pitch, -6.0)


# ---------------------------------------------------------------- view

func _build() -> void:
	_sky = MarsSky.new()
	add_child(_sky)
	var far := Parallax.new()
	far.sprite = "mars_far"
	far.y = 66
	far.factor = 0.12
	far.mars = self
	add_child(far)
	var mid := Parallax.new()
	mid.sprite = "mars_mid"
	mid.y = 94
	mid.factor = 0.35
	mid.mars = self
	add_child(mid)
	_world = Node2D.new()
	add_child(_world)
	_ground = Polygon2D.new()
	_ground.texture = Tex.texture("mars_ground", Vector2i(16, 16), Color("#b86f50"))
	_ground.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	var pts := PackedVector2Array()
	var x := 0
	while x <= world_w:
		pts.append(Vector2(x, terrain.heights[x]))
		x += 4
	if (x - 4) != world_w:
		pts.append(Vector2(world_w, terrain.heights[world_w]))
	pts.append(Vector2(world_w, 200))
	pts.append(Vector2(0, 200))
	_ground.polygon = pts
	_world.add_child(_ground)
	_view = WorldView.new()
	_view.mars = self
	_world.add_child(_view)
	_arm = ArmView.new()
	_arm.tool = "drill"
	_world.add_child(_arm)
	_hud = Hud.new()
	_hud.mars = self
	add_child(_hud)
	_pause = PauseView.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	_hum = LoopAudio.looping(self, "rover_hum", -14.0, false)
	_buzz = LoopAudio.looping(self, "heli_buzz", -10.0, false)
	_layout()


func _layout() -> void:
	_world.position = Vector2(-roundf(cam_x), 0)
	var sh := Vector2(rover.x, rover.body_y()) + ARM_SHOULDER
	var goal := sh + Vector2(10, 6)
	if drilling != -1:
		goal = target_pos(drilling)
	elif poke_t > 0.0:
		goal = reach_point()
	var solved := ArmIK.solve(sh.round(), goal.round(), ARM_REACH, ARM_REACH, -1.0)
	_arm.spin = int(stage_t * 12.0) % 2 if (drilling != -1 or poke_t > 0.0) else 0
	_arm.set_pose(sh.round(), solved.elbow, solved.tip)
	_view.queue_redraw()
	_hud.queue_redraw()


## A tiled parallax strip (mars_far, mars_mid).
class Parallax extends Node2D:
	var sprite := ""
	var y := 0
	var factor := 0.2
	var mars: Node2D
	var _tex: Texture2D

	func _ready() -> void:
		_tex = Tex.frame(sprite, 0, Color("#733e39"), Vector2i(320, 48))

	func _process(_d: float) -> void:
		queue_redraw()

	func _draw() -> void:
		var w := _tex.get_width()
		var off := -fposmod(floorf(mars.cam_x * factor), float(w))
		var x := off
		while x < 320:
			draw_texture(_tex, Vector2(x, y))
			x += w


## The world: the surface edge, rocks, the rover, samples, the helicopter,
## the spotlight, the sunset beam home.
class WorldView extends Node2D:
	var mars: Node2D

	func _t(n: String, i := 0, fb := Vector2i(12, 10)) -> Texture2D:
		return Tex.frame(n, i, Color("#be4a2f"), fb)

	func _center(tex: Texture2D, p: Vector2, mod := Color.WHITE) -> void:
		draw_texture(tex, (p - tex.get_size() / 2.0).round(), mod)

	func _draw() -> void:
		var M = mars
		var tr: RefCounted = M.terrain
		var x0 := int(M.cam_x) - 2
		var time: float = M.stage_t
		# The lit edge of the ground.
		for x in range(maxi(0, x0), mini(M.world_w, x0 + 324)):
			draw_rect(Rect2(x, tr.heights[x], 1, 1), Color("#e4a672"))
		# Science targets.
		for i in M.targets.size():
			var tg: Dictionary = M.targets[i]
			if tg.x < M.cam_x - 20 or tg.x > M.cam_x + 340:
				continue
			var p: Vector2 = M.target_pos(i)
			var kind: String = tg.kind
			var name := kind if kind in ["ice", "shell"] else "rock_" + kind
			var fr := 0 if tg.drilled else int(time * 3.0 + i) % 2
			_center(_t(name, fr), p, Color(0.55, 0.5, 0.5) if tg.drilled else Color.WHITE)
		# The spotlight from the hovering helicopter.
		var H = M.heli
		if H.state == H.State.HOVER and H.target != -1:
			var tp: Vector2 = M.target_pos(H.target)
			var hp: Vector2 = H.draw_pos()
			for y in range(int(hp.y) + 4, int(tp.y) + 6):
				var k := (y - hp.y) / maxf(1.0, tp.y - hp.y)
				var half := int(2 + k * 10)
				for x in range(int(tp.x) - half, int(tp.x) + half + 1):
					if (x + y) % 2 == 0:
						draw_rect(Rect2(x, y, 1, 1), Color("#fee761"))
		# The rover: wheels, body, the tray of samples.
		var R = M.rover
		var body := Vector2(R.x, R.body_y())
		var wf := int(posmod(int(R.rolled / 3.0), 4))
		for k in 3:
			_center(_t("wheel", wf, Vector2i(8, 8)), Vector2(R.x + R.WHEEL_X[k], R.wheel_y[k]))
		_center(_t("rover", int(time * 1.5) % 2, Vector2i(40, 24)), body)
		for k in mini(M.tray.size(), 5):
			_center(_t("sample_" + M.tray[M.tray.size() - 1 - k], 0, Vector2i(6, 8)), body + Vector2(-14 + k * 4, -8))
		# The helicopter.
		_center(_t("helicopter", int(time * 16.0) % 2, Vector2i(12, 8)), H.draw_pos())
		# Drill sparks and popping samples.
		for s in M.sparks:
			_center(_t("drill_sparks", clampi(int(s.t / 0.125), 0, 3), Vector2i(8, 8)), s.pos)
		for pp in M.popping:
			var k: float = pp.t / 0.7
			var to := body + Vector2(-8, -10)
			var p: Vector2 = pp.from.lerp(to, k) + Vector2(0, -sin(k * PI) * 22.0)
			_center(_t("sample_" + pp.kind, 0, Vector2i(6, 8)), p)
			if k < 0.4:
				_center(_t("sparkle", int(k * 10.0), Vector2i(8, 8)), pp.from)
		# The beam home at the end: dots climbing from the mast to the Earth dot.
		if M.phase == M.Phase.PHONE:
			var from := body + Vector2(10, -12)
			var to: Vector2 = M.EARTH_DOT + Vector2(M.cam_x, 0)
			var n := 26
			for k in n:
				var f := float(k) / n
				if int(f * n + M.t * 12.0) % 3 == 0:
					draw_rect(Rect2(from.lerp(to, f).round(), Vector2(2, 2)), Color("#2ce8f5"))


## The HUD: the tiny Earth at sunset, the samples row, the journey track.
class Hud extends Node2D:
	var mars: Node2D

	func _draw() -> void:
		var M = mars
		if M.phase == M.Phase.SUNSET or M.phase == M.Phase.PHONE:
			var e: Vector2 = M.EARTH_DOT
			if M._sky.blend > 0.5:
				draw_rect(Rect2(e - Vector2(2, 1), Vector2(5, 3)), Color("#0099db"))
				draw_rect(Rect2(e - Vector2(1, 2), Vector2(3, 5)), Color("#0099db"))
				draw_rect(Rect2(e + Vector2(0, -1), Vector2(2, 2)), Color("#63c74d"))
				draw_rect(Rect2(e - Vector2(1, 1), Vector2(1, 1)), Color("#ffffff"))
		# The journey: a line from the landing spot to the sunset, the rover's dot on it.
		var x0 := 110.0
		var w := 100.0
		draw_rect(Rect2(x0, 6, w, 1), Color("#733e39"))
		var k: float = clampf(M.rover.x / maxf(1.0, M.world_w - M.SUNSET_MARGIN), 0.0, 1.0)
		draw_rect(Rect2(x0 + w - 1, 3, 3, 7), Color("#ffffff"))
		draw_rect(Rect2(roundf(x0 + k * w) - 2, 4, 5, 5), Color("#ffffff"))
		draw_rect(Rect2(roundf(x0 + k * w) - 1, 5, 3, 3), Color("#f77622"))
		# Samples so far (the whole mission), top left.
		for i in mini(Game.samples.size(), 24):
			var tex := Tex.frame("sample_" + Game.samples[i], 0, Color("#be4a2f"), Vector2i(6, 8))
			draw_texture(tex, Vector2(4 + i * 7, 3))
