extends Node2D
## Stage 2, the Mars landing ("seven minutes of fun"): a short entry through the
## glowing sky, then three beats, one per seat, none of which can fail:
##   1. PARACHUTE (Camera): any press pops the big parachute.
##   2. SITE (Arm): left/right picks one of four glowing spots (dunes, crater,
##      ice, rocks: all safe), A confirms.
##   3. CRANE (Pilot): holding down lowers the rover on its cables; a soft
##      touchdown puffs dust and the sky crane flies away with a wave.
## Each beat completes itself 5 s after it starts. Logic in step(dt).

const Beats := preload("res://scripts/logic/landing_beats.gd")
const Terrain := preload("res://scripts/logic/terrain.gd")
const MarsSky := preload("res://scripts/view/mars_sky.gd")
const PauseView := preload("res://scripts/view/pause.gd")
const Tex := preload("res://scripts/view/tex.gd")

enum Phase { ENTRY, BEATS, OUTRO, DONE }

const ENTRY_TIME := 3.0
const OUTRO_TIME := 2.0
const GROUND_Y := 150.0
const SITE_X: Array[float] = [52.0, 124.0, 196.0, 268.0]
const CRANE_Y := 70.0
const CRANE_BOTTOM := 8.0      # the cable hangs from the crane's centre + this

var auto_goto := true
var next_screen := ""

var phase := Phase.ENTRY
var beats: Beats
var t := 0.0                   # time in the current phase
var total_t := 0.0
var shell := Vector2(160, 56)
var chute_open := false
var chute_gone := 0.0          # the backshell and chute drifting away
var crane := Vector2(160, CRANE_Y)
var crane_gone := 0.0
var landed := false
var ground_y := 240.0          # the ground rises into view
var events: Array[String] = []
var presses := 0               # Camera presses (they only make the capsule wobble)

var _sky: Node2D
var _view: Node2D
var _pause: Node2D
var _sfx_cd := {}
var _streaks: Array[Vector2] = []
var _puffs: Array[Dictionary] = []


func _ready() -> void:
	beats = Beats.new()
	beats.empty[Beats.Beat.PARACHUTE] = not Players.is_seated(Players.Seat.HONKER)
	beats.empty[Beats.Beat.SITE] = Game.arm_auto()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	for i in 24:
		_streaks.append(Vector2(rng.randi_range(4, 316), rng.randi_range(0, 179)))
	_sky = MarsSky.new()
	add_child(_sky)
	_view = View.new()
	_view.landing = self
	add_child(_view)
	_pause = PauseView.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	Sfx.music("music_mars")
	Sfx.play("quindar_in")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	events.clear()
	if _pause.check():
		return
	t += dt
	total_t += dt
	for k in _sfx_cd:
		_sfx_cd[k] = maxf(0.0, _sfx_cd[k] - dt)
	for p in _puffs:
		p.t += dt
	_puffs = _puffs.filter(func(p): return p.t < 0.6)
	var cam := Game.camera_pressed()
	match phase:
		Phase.ENTRY:
			shell.y = lerpf(-20.0, 56.0, clampf(t / 1.5, 0.0, 1.0))
			if cam:
				presses += 1
			if t >= ENTRY_TIME:
				phase = Phase.BEATS
				t = 0.0
		Phase.BEATS:
			_beats_step(dt, cam)
		Phase.OUTRO:
			crane_gone += dt
			if t >= OUTRO_TIME:
				_finish()
	_view.queue_redraw()


func _beats_step(dt: float, cam: bool) -> void:
	var g := Players.Seat.GUNNER
	var flick := Players.dir4_just_pressed(g).x if Players.is_seated(g) else 0
	var input := {
		"camera": cam,
		"arm_dir": flick,
		"arm_a": Players.is_seated(g) and Players.just_pressed(g, "a"),
		"down": maxf(Players.move(Players.Seat.DRIVER).y, 0.0),
	}
	if cam and (beats.beat != Beats.Beat.PARACHUTE or beats.done_beat):
		presses += 1  # an extra press: a little wobble, nothing else
	var ev := beats.step(dt, input)
	if ev != "":
		events.append(ev)
	match ev:
		"pop":
			chute_open = true
			Sfx.play("parachute_pop")
		"pick":
			Sfx.play("select", 1.0 + 0.1 * beats.site)
		"site":
			Sfx.play("ready")
		"lower":
			_sound("crane_lower", 0.9)
		"touchdown":
			landed = true
			Sfx.play("touchdown")
			for dx in [-13, 0, 13]:
				_puffs.append({"pos": Vector2(crane.x + dx, GROUND_Y - 2), "t": 0.0})
		"next":
			if beats.beat == Beats.Beat.CRANE:
				crane = Vector2(SITE_X[beats.site], CRANE_Y)
		"done":
			phase = Phase.OUTRO
			t = 0.0
			Sfx.play("crane_bye")
	# Where things are, per beat.
	match beats.beat:
		Beats.Beat.PARACHUTE:
			var k := clampf(beats.outro_t / Beats.OUTRO[0], 0.0, 1.0) if beats.done_beat else 0.0
			ground_y = lerpf(240.0, 200.0, k)
		Beats.Beat.SITE:
			ground_y = move_toward(ground_y, GROUND_Y, 60.0 * dt)
			shell.x = move_toward(shell.x, SITE_X[beats.site], 90.0 * dt)
			if beats.done_beat:
				shell.y = move_toward(shell.y, 64.0, 20.0 * dt)
		Beats.Beat.CRANE:
			ground_y = GROUND_Y
			chute_gone += dt


func _finish() -> void:
	phase = Phase.DONE
	Game.site = Terrain.SITES[beats.site]
	Sfx.play("quindar_out")
	next_screen = Game.next_after("landing")
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


func _sound(sound: String, gap: float) -> void:
	if _sfx_cd.get(sound, 0.0) > 0.0:
		return
	_sfx_cd[sound] = gap
	Sfx.play(sound, 1.0, -4.0)


## Draws the descent: streaks, the ground and sites, the capsule and chute, the
## sky crane with the rover on its cable.
class View extends Node2D:
	var landing: Node2D

	func _tex(n: String, i := 0, fb := Vector2i(16, 16)) -> Texture2D:
		return Tex.frame(n, i, Color("#c28569"), fb)

	func _center(tex: Texture2D, p: Vector2) -> void:
		draw_texture(tex, (p - tex.get_size() / 2.0).round())

	func _draw() -> void:
		var L = landing
		var time: float = L.total_t
		var f := int(time * 8.0)
		# Speed streaks while falling (they slow as the chute opens).
		var falling: bool = L.phase == L.Phase.ENTRY or (L.beats.beat == Beats.Beat.PARACHUTE)
		if falling:
			var speed := 160.0 if not L.chute_open else 60.0
			for s in L._streaks:
				var y := fposmod(s.y - time * speed, 180.0)
				draw_rect(Rect2(s.x, floorf(y), 1, 6), Color("#ead4aa"))
		# The ground: far mountains, dunes, then the soil with the four sites.
		var gy: float = roundf(L.ground_y)
		if gy < 180.0:
			draw_texture(_tex("mars_far", 0, Vector2i(320, 60)), Vector2(0, gy - 78))
			draw_texture(_tex("mars_mid", 0, Vector2i(320, 48)), Vector2(0, gy - 44))
			var tile := _tex("mars_ground", 0)
			var x := 0
			while x < 320:
				var y := gy
				while y < 180:
					draw_texture(tile, Vector2(x, y))
					y += 16
				x += 16
			draw_rect(Rect2(0, gy, 320, 1), Color("#e4a672"))
			for i in 4:
				var names := ["site_dunes", "site_crater", "site_ice", "site_rocks"]
				var p := Vector2(L.SITE_X[i], gy + 8)
				_center(_tex(names[i], 0, Vector2i(32, 16)), p)
				var chosen: bool = i == L.beats.site
				var choosing: bool = L.beats.beat == Beats.Beat.SITE and not L.beats.done_beat
				if (choosing and (chosen or int(time * 2.0 + i) % 2 == 0)) or (chosen and L.beats.beat != Beats.Beat.PARACHUTE):
					var col := Color("#fee761") if chosen else Color("#ffffff")
					var r := Rect2(p - Vector2(19, 11), Vector2(38, 22))
					if chosen and choosing and int(time * 4.0) % 2 == 0:
						r = r.grow(1)
					draw_rect(r, col, false, 1.0)
		# The capsule under its parachute (it drifts off when the crane takes over).
		var sh: Vector2 = L.shell
		var gone: float = L.chute_gone
		if gone < 3.0:
			var off := Vector2(-gone * 50.0, -gone * 40.0)
			var wob := Vector2(sin(time * 3.0 + L.presses) * (2.0 if L.chute_open else 0.0), 0)
			if L.chute_open:
				_center(_tex("parachute", f / 3, Vector2i(48, 32)), sh + off + wob + Vector2(0, -30))
			var glow := 0 if L.chute_open else f % 2
			_center(_tex("lander_shell", glow, Vector2i(32, 32)), sh + off + wob)
		# The sky crane and the rover on its cable.
		if L.beats.beat >= Beats.Beat.CRANE:
			var c: Vector2 = L.crane
			var away: float = L.crane_gone
			var cp := c + Vector2(away * 70.0, -away * 45.0)
			var rover_top: float = c.y + L.CRANE_BOTTOM + L.beats.cable
			if not L.landed:
				var cable := _tex("cable", 0, Vector2i(1, 8))
				for dx in [-8, 8]:
					var y: float = c.y + L.CRANE_BOTTOM
					while y < rover_top:
						draw_texture_rect_region(cable, Rect2(c.x + dx, y, 1, minf(8.0, rover_top - y)),
							Rect2(0, 0, 1, minf(8.0, rover_top - y)))
						y += 8
			var rover_c := Vector2(c.x, rover_top + 12)
			_center(_tex("rover", 0, Vector2i(40, 24)), rover_c)
			for dx in [-13, 0, 13]:
				_center(_tex("wheel", 0, Vector2i(8, 8)), rover_c + Vector2(dx, 8))
			_center(_tex("sky_crane", f % 2, Vector2i(32, 16)), cp)
			if away > 0.2 and away < 1.6:
				# The crane's little wave: a waggle of its thrusters' light.
				draw_rect(Rect2(cp + Vector2(14, -10 - (f % 2) * 2), Vector2(2, 4)), Color("#fee761"))
		for p in L._puffs:
			var k := clampi(int(p.t / 0.15), 0, 3)
			_center(_tex("dust_puff", k, Vector2i(8, 8)), p.pos)

