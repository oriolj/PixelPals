extends Node2D
## Stage 2, the trail ride. Side-scrolling countryside in parallax (meadow,
## farm, woods, stream, hill with the windmill, lake) from morning sun through
## a short warm shower to golden afternoon light at the show grounds.
##
## - Rider: right on the stick speeds the mare up (walk, trot, canter), left
##   slows her down; A jumps (the assist starts the jump at the right moment
##   within +-0.4 s); a missed jump is a slower step-over with a funny "hup!".
## - Foal seat: up/down moves the foal between three lanes; A hops to grab
##   apples and the lucky horseshoes (flowers are picked by trotting through).
##   The foal is tethered: it never leaves the mare by more than 40 px.
## - NEIGH seat: both horses whinny; the nearest animal answers; a close gate
##   opens; the wild herd on the hill answers and the rainbow comes out.
## A gate opens by itself after 5 s (1 s with no toddler); the foal steers
## itself with no 5-year-old (or after 5 s idle).

const MareRide := preload("res://scripts/logic/mare_ride.gd")
const FoalTether := preload("res://scripts/logic/foal_tether.gd")
const TrailCourse := preload("res://scripts/logic/trail_course.gd")
const Tex := preload("res://scripts/view/tex.gd")
const Pause := preload("res://scripts/view/pause.gd")
const LoopAudio := preload("res://scripts/view/loop_audio.gd")

const MARE_SCREEN_X := 120.0
const MARE_Y := 150.0
const NEIGH_COOLDOWN := 0.35
const NEIGH_TIME := 0.6
const IDLE_ASSIST := 5.0
const WIPE_TIME := 0.9
const HOOF_LOOPS: Array[String] = ["walk_loop", "trot_loop", "canter_loop"]
const ANIMAL_Y := {"rabbit": 136.0, "sheep": 134.0, "cow": 132.0, "duck": 128.0, "bird": 104.0}
const ANIMAL_SIZE := {"rabbit": Vector2i(12, 10), "sheep": Vector2i(16, 12), "cow": Vector2i(24, 16),
	"duck": Vector2i(10, 8), "bird": Vector2i(8, 6)}
const ANIMAL_SOUND := {"rabbit": "bunny_boing", "sheep": "baa", "cow": "moo", "duck": "quack", "bird": "birds"}
const PROP_SIZE := {"barn": Vector2i(48, 40), "tree": Vector2i(24, 32), "bush": Vector2i(16, 12), "reeds": Vector2i(16, 16)}
const PROP_Y := {"barn": 132.0, "tree": 134.0, "bush": 138.0, "reeds": 138.0}

var auto_goto := true
var next_screen := ""
var time := 0.0
var mare: MareRide
var foal: FoalTether
var course: TrailCourse
var cam_x := 0.0
var neigh_t := -1.0             # the horses' whinny animation
var foal_idle := 0.0
var finish_t := -1.0
var splashes: Array[Dictionary] = []   # {x, y, t}
var sparks: Array[Dictionary] = []     # {pos (screen), t}
var drops: Array[Vector2] = []
var bird_fly: Dictionary = {}          # animal index -> fly time
var events_log: Array[String] = []     # what happened (tests read it)
var _neigh_cool := 0.0
var _last_puddle_x := -100.0
var _last_foal_puddle := -100.0
var _loops: Array[AudioStreamPlayer] = []
var _rain_loop: AudioStreamPlayer
var _world: Node2D
var _pause: Node2D
var _mare_anim_t := 0.0
var _foal_anim_t := 0.0


func _ready() -> void:
	course = TrailCourse.new(Game.day_scale)
	mare = MareRide.new()
	mare.x = 40.0
	mare.obstacles = course.obstacles
	foal = FoalTether.new()
	foal.place(mare.x)
	for i in 70:
		drops.append(Vector2((i * 47) % 320, (i * 71) % 180))
	_world = World.new()
	_world.screen = self
	add_child(_world)
	for n in HOOF_LOOPS:
		_loops.append(LoopAudio.looping(self, n, -8.0, false))
	_rain_loop = LoopAudio.looping(self, "rain_loop", -10.0, false)
	_pause = Pause.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	Sfx.music("music_trail")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if _pause.check():
		for p in _loops:
			LoopAudio.set_on(p, false)
		return
	time += dt
	if finish_t >= 0.0:
		finish_t += dt
		mare.stop_x = INF
		mare.step(dt)
		foal.step(mare.x, mare.speed, dt)
		_mare_anim_t += dt
		_foal_anim_t += dt
		_update_cam()
		_world.queue_redraw()
		if finish_t >= WIPE_TIME and next_screen == "":
			_finish()
		return
	_neigh_input(dt)
	_rider(dt)
	_foal_seat(dt)
	var ev := course.update(mare.x, dt, Game.has_toddler())
	for e in ev:
		_course_event(e)
	mare.stop_x = course.stop_x_for(mare.x)
	for e in mare.step(dt):
		_mare_event(e)
	foal.step(mare.x, mare.speed, dt)
	var tw := course.twig_ahead(foal.x, foal.lane)
	if not tw.is_empty() and foal.hop():
		tw.hopped = true
	if not foal.changing_lane():
		for it in course.grab(foal.x, foal.lane, foal.hop_height()):
			_grabbed(it)
	_puddles()
	_tick_fx(dt)
	_update_cam()
	_sound()
	_world.queue_redraw()
	if mare.x >= course.length:
		finish_t = 0.0
		Sfx.play("neigh", 1.0, -2.0)


func _update_cam() -> void:
	cam_x = maxf(0.0, mare.x - MARE_SCREEN_X)


# ---------------------------------------------------------------- the toddler: the neigh

func _neigh_input(dt: float) -> void:
	_neigh_cool = maxf(0.0, _neigh_cool - dt)
	if Game.neigh_pressed() and _neigh_cool <= 0.0:
		do_neigh()


## Both horses whinny with a mane toss, and the world answers.
func do_neigh() -> Dictionary:
	_neigh_cool = NEIGH_COOLDOWN
	neigh_t = 0.0
	Sfx.play("neigh", randf_range(0.95, 1.05))
	Sfx.play("foal_neigh", 1.0, -3.0)
	var out := course.neigh(mare.x)
	if out.gate:
		events_log.append("gate_neigh")
	if out.animal != -1:
		var an: Dictionary = course.animals[out.animal]
		Sfx.play(ANIMAL_SOUND.get(an.kind, "baa"), randf_range(0.95, 1.1))
		if an.kind == "bird":
			bird_fly[out.animal] = 0.0
		events_log.append("animal:" + str(an.kind))
	if out.herd:
		_herd_answers()
	return out


func _herd_answers() -> void:
	Sfx.play("wild_herd", 1.1)
	Sfx.play("rainbow")
	events_log.append("rainbow")


# ---------------------------------------------------------------- the adult: the mare

func _rider(dt: float) -> void:
	mare.steer(Players.move(Players.Seat.DRIVER).x, dt)
	if Players.just_pressed(Players.Seat.DRIVER, "a"):
		var r := mare.press_jump()
		if r == "hop":
			Sfx.play("jump_hup", 1.2, -6.0)


func _mare_event(e: String) -> void:
	events_log.append(e)
	match e:
		"jump":
			Sfx.play("jump_hup")
			Game.day.clean_jumps = int(Game.day.clean_jumps) + 1
		"land":
			Sfx.play("land_thud")
			for k in 3:
				sparks.append({"pos": Vector2(mare.x - cam_x + k * 6 - 6, MARE_Y - 2), "t": 0.0, "kind": "dust"})
		"step_over":
			Sfx.play("step_hup")
			Sfx.play("snort", 1.1, -6.0)


# ---------------------------------------------------------------- the 5-year-old: the foal

func _foal_seat(dt: float) -> void:
	var seated := not Game.foal_auto()
	var flick := Players.dir4_just_pressed(Players.Seat.GUNNER) if seated else Vector2i.ZERO
	var hop_pressed := seated and Players.just_pressed(Players.Seat.GUNNER, "a")
	if flick != Vector2i.ZERO or hop_pressed:
		foal_idle = 0.0
	else:
		foal_idle += dt
	if flick.y != 0:
		if foal.change_lane(-flick.y):
			Sfx.play("whoosh", 1.8, -12.0)
	if hop_pressed and foal.hop():
		Sfx.play("jump_hup", 1.5, -8.0)
	if not seated or foal_idle >= IDLE_ASSIST:
		var before := foal.hopping()
		foal.auto_steer(course.items)
		if foal.hopping() and not before:
			Sfx.play("jump_hup", 1.5, -10.0)


func _grabbed(it: Dictionary) -> void:
	var p := Vector2(float(it.x) - cam_x, FoalTether.LANE_Y[int(it.lane)] - 10.0)
	sparks.append({"pos": p, "t": 0.0, "kind": "sparkle"})
	events_log.append("grab:" + str(it.kind))
	match str(it.kind):
		"apple":
			Game.day.apples = int(Game.day.apples) + 1
			Sfx.play("apple_pop")
		"lucky_horseshoe":
			Game.day.lucky = int(Game.day.lucky) + 1
			Sfx.play("lucky_chime")
		_:
			Game.day.flowers = int(Game.day.flowers) + 1
			Sfx.play("flower_pick")


# ---------------------------------------------------------------- the world

func _course_event(e: String) -> void:
	events_log.append(e)
	match e:
		"gate_open":
			Sfx.play("gate_open")
			if not Game.has_toddler():
				neigh_t = 0.0
				Sfx.play("neigh", 1.0, -3.0)
		"herd_start":
			Sfx.play("wild_herd")
		"rainbow":
			# The herd was not answered in 5 s: the mare answers on her own.
			neigh_t = 0.0
			Sfx.play("neigh")
			_herd_answers()


func _puddles() -> void:
	if course.puddle_at(mare.x) and absf(mare.x - _last_puddle_x) > 20.0 and not mare.is_airborne():
		_last_puddle_x = mare.x
		splashes.append({"x": mare.x, "y": MARE_Y, "t": 0.0})
		Sfx.play("splash", 1.0, -4.0)
	if course.puddle_at(foal.x) and absf(foal.x - _last_foal_puddle) > 20.0 and not foal.hopping():
		_last_foal_puddle = foal.x
		splashes.append({"x": foal.x, "y": foal.y, "t": 0.0})
		Sfx.play("splash", 1.3, -6.0)


func _tick_fx(dt: float) -> void:
	_mare_anim_t += dt
	_foal_anim_t += dt
	if neigh_t >= 0.0:
		neigh_t += dt
		if neigh_t >= NEIGH_TIME:
			neigh_t = -1.0
	for s in splashes:
		s.t += dt
	splashes = splashes.filter(func(s): return s.t < 0.45)
	for s in sparks:
		s.t += dt
		s.pos.y -= 10.0 * dt
	sparks = sparks.filter(func(s): return s.t < 0.6)
	for k in bird_fly.keys():
		bird_fly[k] += dt
	var rain: float = weather().rain
	if rain > 0.0:
		for i in drops.size():
			drops[i] += Vector2(-18.0, 70.0) * dt
			if drops[i].y > 180.0:
				drops[i] = Vector2(fposmod(drops[i].x + 37.0 * i, 340.0), -4.0)


func weather() -> Dictionary:
	return TrailCourse.weather(course.progress(mare.x))


func _sound() -> void:
	var g := mare.gait()
	var moving := mare.speed > 3.0 and not mare.is_airborne()
	for i in _loops.size():
		LoopAudio.set_on(_loops[i], moving and i == g)
	var rain: float = weather().rain
	LoopAudio.set_on(_rain_loop, rain > 0.05)
	if _rain_loop and _rain_loop.stream:
		_rain_loop.volume_db = lerpf(-30.0, -10.0, rain)


func _finish() -> void:
	next_screen = Game.next_after("trail")
	set_process(false)
	for p in _loops:
		LoopAudio.set_on(p, false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


# ---------------------------------------------------------------- drawing helpers

## The frame index of `anim` of a family at time t.
static func anim_frame(family: String, anim_name: String, t: float, hold := 0) -> int:
	var r := Tex.anim(family, anim_name)
	if float(r[2]) <= 0.0:
		return int(r[0]) + clampi(hold, 0, int(r[1]) - 1)
	return int(r[0]) + int(floor(t * float(r[2]))) % int(r[1])


## The mare's frame now.
func mare_frame() -> int:
	match mare.state:
		MareRide.State.JUMP:
			var k := clampf(mare.state_t / MareRide.JUMP_TIME, 0.0, 0.999)
			return anim_frame("mare", "jump", 0.0, 0 if k < 0.22 else (1 if k < 0.72 else 2))
		MareRide.State.HOP:
			return anim_frame("mare", "jump", 0.0, 1)
		MareRide.State.STEP:
			return anim_frame("mare", "walk", _mare_anim_t)
	if neigh_t >= 0.0:
		return anim_frame("mare", "neigh", neigh_t)
	if mare.speed < 3.0:
		return anim_frame("mare", "stand", _mare_anim_t)
	return anim_frame("mare", ["walk", "trot", "canter"][mare.gait()], _mare_anim_t)


func foal_frame() -> int:
	if foal.hopping():
		var k := clampf(foal.hop_t / FoalTether.HOP_TIME, 0.0, 0.999)
		return anim_frame("foal", "hop", 0.0, int(k * 3.0))
	if neigh_t >= 0.0:
		return anim_frame("foal", "neigh", neigh_t)
	if absf(foal.vx) < 3.0:
		return anim_frame("foal", "stand", _foal_anim_t)
	return anim_frame("foal", "trot", _foal_anim_t)


## Draws everything of the world, back to front: sky, far hills, mid trees,
## the ground and the path, then the props, animals, gates, obstacles, items,
## the mare with her riders and the foal sorted by their feet, then the rain.
class World extends Node2D:
	var screen: Node2D

	func _draw() -> void:
		var sc = screen
		var cx: float = sc.cam_x
		var w: Dictionary = sc.weather()
		# The sky: the two keyed skies crossfaded.
		var sa := Tex.frame(w.a, 0, Color("#2ce8f5"), Vector2i(320, 60))
		draw_texture_rect(sa, Rect2(0, 0, 320, 60), false)
		if w.mix > 0.0 and w.b != w.a:
			draw_texture_rect(Tex.frame(w.b, 0, Color("#8b9bb4"), Vector2i(320, 60)), Rect2(0, 0, 320, 60), false,
				Color(1, 1, 1, w.mix))
		draw_rect(Rect2(0, 60, 320, 60), _sky_bottom(w))
		var course = sc.course
		if course.rainbow_t >= 0.0:
			var a := clampf(course.rainbow_t / 1.5, 0.0, 1.0)
			draw_texture(Tex.frame("rainbow", 0, Color("#e43b44"), Vector2i(160, 60)), Vector2(150, 6), Color(1, 1, 1, a))
		draw_rect(Rect2(0, 96, 320, 32), Color("#63c74d"))
		_strip("hills_far", cx * 0.2, 44, Vector2i(320, 60))
		_herd()
		_strip("trees_mid", cx * 0.5, 82, Vector2i(320, 48))
		# The ground: grass, the lake in the lake field, the path under the mare.
		var grass := Tex.frame("grass", 0, Color("#63c74d"), Vector2i(16, 16))
		var path := Tex.frame("path", 0, Color("#b86f50"), Vector2i(16, 16))
		var off := -fposmod(cx, 16.0)
		for x in range(0, 21):
			for y in range(126, 180, 16):
				draw_texture(grass, Vector2(off + x * 16, y))
			draw_texture(path, Vector2(off + x * 16, 142))
		_lake(cx)
		# Depth-sorted things.
		var things: Array = []
		for p in course.props:
			var px: float = float(p.x) - cx
			if px > -60 and px < 380:
				var sz: Vector2i = PROP_SIZE.get(p.kind, Vector2i(16, 16))
				things.append([PROP_Y.get(p.kind, 136.0), Tex.frame(p.kind, 0, Color("#3e8948"), sz), Vector2(px - sz.x / 2.0, PROP_Y.get(p.kind, 136.0) - sz.y), false, Color.WHITE])
		for i in course.animals.size():
			var an: Dictionary = course.animals[i]
			var ax: float = float(an.x) - cx
			if ax < -40 or ax > 360:
				continue
			things.append(_animal(i, an, ax))
		# The near fence posts and the gates.
		for g in course.gates:
			var gx: float = float(g.x) - cx
			if gx > -40 and gx < 360:
				var fr: int = course.gate_frame(g)
				things.append([141.0, Tex.frame("gate", fr, Color("#b86f50"), Vector2i(32, 24)), Vector2(gx - 16, 141 - 24), false, Color.WHITE])
				for k in 3:
					things.append([128.0, Tex.frame("fence", 0, Color("#b86f50"), Vector2i(16, 16)), Vector2(gx - 40 + k * 16 + (48 if k > 0 else 0), 128 - 16), false, Color.WHITE])
				if int(g.state) == 0 and float(g.x) - sc.mare.x <= TrailCourse.GATE_REACH + 4 and Game.has_toddler():
					var bob := 1.0 if int(sc.time * 4.0) % 2 == 0 else 0.0
					things.append([200.0, Tex.frame("seat_neigh", 0, Players.SEAT_COLORS[2], Vector2i(16, 16)), Vector2(gx - 8, 94 - bob), false, Color.WHITE])
		for ob in course.obstacles:
			var ox: float = float(ob.x) - cx
			if ox < -40 or ox > 360:
				continue
			var sz2: Vector2i = {"log": Vector2i(20, 8), "stream": Vector2i(32, 10), "hay_bale": Vector2i(16, 12)}[ob.kind]
			var f2 := int(sc.time * 3.0) % 2 if ob.kind == "stream" else 0
			var oy := 151.0 if ob.kind != "stream" else 153.0
			things.append([oy - 0.5, Tex.frame(ob.kind, f2, Color("#733e39"), sz2), Vector2(ox, oy - sz2.y), false, Color.WHITE])
		for tw in course.twigs:
			var tx: float = float(tw.x) - cx
			if tx > -20 and tx < 340:
				var ty: float = FoalTether.LANE_Y[int(tw.lane)]
				things.append([ty - 0.5, Tex.frame("twig_log", 0, Color("#733e39"), Vector2i(12, 6)), Vector2(tx - 6, ty - 6), false, Color.WHITE])
		for it in course.items:
			if it.taken:
				continue
			var ix: float = float(it.x) - cx
			if ix < -10 or ix > 330:
				continue
			var iy: float = FoalTether.LANE_Y[int(it.lane)] - (9.0 if it.needs_hop else 1.0)
			var f3 := int(sc.time * 2.0 + float(it.x) * 0.01) % 2
			things.append([FoalTether.LANE_Y[int(it.lane)] - 0.2, Tex.frame(it.kind, f3, Color("#e43b44"), Vector2i(8, 8)), Vector2(ix - 4, iy - 8), false, Color.WHITE])
		for px2 in course.puddles:
			var ppx: float = px2 - cx
			if ppx > -20 and ppx < 340:
				things.append([146.0, Tex.frame("puddle", 0, Color("#0099db"), Vector2i(16, 4)), Vector2(ppx - 8, 148), false, Color.WHITE])
		# The show grounds' flags at the end of the trail.
		var endx: float = course.length - cx
		if endx < 360:
			for k in 6:
				things.append([128.0, Tex.frame("flag", int(sc.time * 3.0 + k) % 2, Color("#e43b44"), Vector2i(8, 8)), Vector2(endx + k * 12, 110 + (k % 2) * 3), false, Color.WHITE])
		# The mare with her riders, the foal with its hat.
		var mx: float = sc.mare.x - cx
		var my: float = MARE_Y + sc.mare.y
		var mf: int = sc.mare_frame()
		var mare_tex := Tex.frame("mare_" + Game.mare_coat, mf, Game.coat_color(Game.mare_coat), Vector2i(40, 32))
		things.append([MARE_Y, mare_tex, Vector2(roundf(mx) - 20, roundf(my) - 32), false, Color.WHITE, "mare", mf])
		var fx: float = sc.foal.x - cx
		var fy: float = sc.foal.y - sc.foal.hop_height()
		var ff: int = sc.foal_frame()
		things.append([sc.foal.y, Tex.frame("foal_" + Game.foal_coat, ff, Game.coat_color(Game.foal_coat), Vector2i(24, 20)),
			Vector2(roundf(fx) - 12, roundf(fy) - 20), false, Color.WHITE, "foal", ff])
		for s in sc.splashes:
			var sx: float = float(s.x) - cx
			things.append([float(s.y) + 0.5, Tex.frame("splash", int(s.t * 7.0), Color("#2ce8f5"), Vector2i(16, 8)), Vector2(sx - 8, float(s.y) - 8), false, Color.WHITE])
		things.sort_custom(func(a, b): return a[0] < b[0])
		for t in things:
			draw_texture(t[1], t[2], t[4])
			if t.size() > 5:
				if t[5] == "mare":
					_riders(t[2], t[6])
				else:
					_hat(t[2], t[6])
		for s in sc.sparks:
			draw_texture(Tex.frame("sparkle", int(s.t * 8.0), Color("#ffffff"), Vector2i(8, 8)), (s.pos - Vector2(4, 4)).round())
		_rain(w.rain)
		_hud()
		if sc.finish_t >= 0.0:
			var ww := clampf(sc.finish_t / WIPE_TIME, 0.0, 1.0) * 320.0
			draw_rect(Rect2(320 - roundf(ww), 0, roundf(ww), 180), Color("#feae34"))

	func _sky_bottom(w: Dictionary) -> Color:
		var cols := {"sky_morning": Color("#2ce8f5"), "sky_rain": Color("#8b9bb4"), "sky_afternoon": Color("#2ce8f5"),
			"sky_golden": Color("#feae34")}
		var a: Color = cols.get(w.a, Color("#2ce8f5"))
		var b: Color = cols.get(w.b, a)
		return a if w.mix < 0.5 else b

	func _strip(name: String, scroll: float, y: float, size: Vector2i) -> void:
		var tex := Tex.frame(name, 0, Color("#63c74d"), size)
		var off := -fposmod(roundf(scroll), float(size.x))
		draw_texture(tex, Vector2(off, y))
		draw_texture(tex, Vector2(off + size.x, y))

	func _lake(cx: float) -> void:
		var course = screen.course
		var b: Vector2 = course.section_bounds(5)
		var a := b.x + 60.0 - cx
		var e := b.y - 80.0 - cx
		if e < 0 or a > 320:
			return
		a = maxf(a, 0.0)
		e = minf(e, 320.0)
		draw_rect(Rect2(roundf(a), 124, roundf(e - a), 14), Color("#0099db"))
		draw_rect(Rect2(roundf(a), 124, roundf(e - a), 2), Color("#2ce8f5"))
		for x in range(int(a) + 6, int(e) - 6, 22):
			draw_rect(Rect2(x + int(screen.time * 4.0) % 3, 130, 6, 1), Color("#ffffff"))

	func _herd() -> void:
		var course = screen.course
		if course.herd_t < 0.0 or course.herd_t > TrailCourse.HERD_TIME + 2.0:
			return
		for k in 5:
			var x: float = -70.0 + course.herd_t * 34.0 - k * 26.0
			var y := 76.0 + (k % 2) * 5.0
			var whinny: bool = course.herd_answered and course.rainbow_t >= 0.0 and course.rainbow_t < 1.2
			var fr := 4 if whinny else int(course.herd_t * 8.0 + k) % 4
			draw_texture(Tex.frame("wild_horse_%d" % (k % 3 + 1), fr, Color("#8b9bb4"), Vector2i(32, 24)), Vector2(roundf(x), y))

	func _animal(i: int, an: Dictionary, ax: float) -> Array:
		var kind: String = an.kind
		var sz: Vector2i = ANIMAL_SIZE.get(kind, Vector2i(12, 12))
		var y: float = ANIMAL_Y.get(kind, 136.0) - (6.0 if an.depth == 1 else 0.0)
		var react: float = an.react
		var fr := 0
		var pos := Vector2(ax - sz.x / 2.0, y - sz.y)
		var t: float = screen.time
		match kind:
			"rabbit":
				fr = 0
				if react >= 0.0:
					fr = 1 if react < 0.2 else (2 if react < 1.2 else 3)
				elif int(t * 0.5 + i) % 5 == 0:
					fr = 1
			"sheep":
				fr = int(t * 2.0) % 2
				if react >= 0.0:
					fr = 2 + int(t * 8.0) % 2
					pos += Vector2(cos(react * 4.0) * 8.0, sin(react * 4.0) * 3.0)
			"duck":
				fr = int(t * 2.0) % 2
				if react >= 0.0:
					fr = 2 + int(t * 10.0) % 2
					pos.y -= 3.0 * sin(react * 6.0)
			"cow":
				fr = 1 if react >= 0.0 else 0
			"bird":
				fr = 0
				if screen.bird_fly.has(i):
					var ft: float = screen.bird_fly[i]
					fr = int(ft * 10.0) % 2
					pos += Vector2(ft * 30.0, -ft * 40.0)
		return [y, Tex.frame(kind, fr, Color("#ffffff"), sz), pos.round(), false, Color.WHITE]

	func _riders(at: Vector2, frame: int) -> void:
		var seat_pt := Tex.point("mare", "rider", frame, Vector2(18, 4))
		var jockey := Tex.frame(Game.jockey_of(0), int(screen.time * 3.0) % 2, Game.rider_color(Game.rider_of(0)), Vector2i(16, 16))
		if Game.has_toddler():
			var pp := Tex.point("mare", "passenger", frame, Vector2(10, 6))
			var j2 := Tex.frame(Game.jockey_of(2), 0, Game.rider_color(Game.rider_of(2)), Vector2i(16, 16))
			draw_texture(j2, at + pp - Vector2(8, 14))
		draw_texture(jockey, at + seat_pt - Vector2(8, 14))
		var rib := Game.ribbon_name()
		if rib != "":
			var bp := Tex.point("mare", "braid", frame, Vector2(30, 8))
			draw_texture(Tex.frame("ribbon_" + rib, 0, Color("#e43b44"), Vector2i(8, 8)), at + bp - Vector2(4, 4))

	func _hat(at: Vector2, frame: int) -> void:
		# The foal carries nobody, but wears the 5-year-old's hat colour.
		var hp := Tex.point("foal", "hat", frame, Vector2(17, 3))
		var c := Color("#feae34")
		var d := Color("#c28569")
		var p := (at + hp).round()
		draw_rect(Rect2(p.x - 3, p.y - 1, 6, 1), d)
		draw_rect(Rect2(p.x - 2, p.y - 3, 4, 2), c)

	func _rain(r: float) -> void:
		if r <= 0.0:
			return
		var n := int(screen.drops.size() * r * 0.8)
		for i in n:
			var p: Vector2 = screen.drops[i].round()
			draw_rect(Rect2(p.x, p.y, 1, 3), Color(0.75, 0.85, 1.0, 0.7))

	func _hud() -> void:
		# The day's pickups as icons: apples, flowers, lucky horseshoes.
		var x := 4
		for i in mini(int(Game.day.apples), 14):
			draw_texture(Tex.frame("apple", 0, Color("#e43b44"), Vector2i(8, 8)), Vector2(x + i * 6, 3))
		var fl := mini(int(Game.day.flowers), 14)
		for i in fl:
			draw_texture(Tex.frame(["flower_pink", "flower_blue", "flower_yellow"][i % 3], 0, Color("#f6757a"), Vector2i(8, 8)), Vector2(x + i * 6, 12))
		for i in mini(int(Game.day.lucky), 4):
			draw_texture(Tex.frame("lucky_horseshoe", 0, Color("#feae34"), Vector2i(8, 8)), Vector2(x + i * 9, 21))
		# The way to the show: a little track with the mare's head moving to the rosette.
		var p: float = screen.course.progress(screen.mare.x)
		draw_rect(Rect2(226, 7, 76, 2), Color("#ffffff", 0.7))
		draw_texture(Tex.frame("coat_" + Game.mare_coat, 0, Game.coat_color(Game.mare_coat), Vector2i(16, 16)), Vector2(roundf(218 + p * 76), 0))
		draw_texture(Tex.frame("rosette_blue", 0, Color("#0099db"), Vector2i(12, 16)), Vector2(304, 0))
