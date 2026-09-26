extends Node2D
## The level: one scrolling toy-railway map (3x3 screens). Builds the world
## views around a Sim, turns the three seats' input into the Sim's input,
## plays the sounds and effects for its events, follows the engine with the
## camera, and runs the night finale before the party.
##
## Seats: DRIVER = engine (up faster, down/b brake, a horn, start pause),
## GUNNER = points (any direction flick, a opens the doors),
## HONKER = whistle (any button). Missing seats are covered: no points seat
## -> tour rule and doors open by themselves; no whistle seat -> the whistle
## toots by itself at tunnels and stations.

const Palette := preload("res://scripts/palette.gd")
const Sim := preload("res://scripts/level/sim.gd")
const Track := preload("res://scripts/track/track.gd")
const GroundView := preload("res://scripts/level/ground_view.gd")
const TrackView := preload("res://scripts/level/track_view.gd")
const StationView := preload("res://scripts/level/station_view.gd")
const PointsView := preload("res://scripts/level/points_view.gd")
const AnimalView := preload("res://scripts/level/animal_view.gd")
const TrainView := preload("res://scripts/level/train_view.gd")
const PeopleView := preload("res://scripts/level/people_view.gd")
const CoverView := preload("res://scripts/level/cover_view.gd")
const FxView := preload("res://scripts/level/fx_view.gd")
const GlowView := preload("res://scripts/level/glow_view.gd")
const Hud := preload("res://scripts/level/hud.gd")

const NIGHT_TINT := Color(0.34, 0.38, 0.66)
const FINALE_SECONDS := 11.0
const WHISTLE_COOLDOWN := 0.22
## Each station colour has its own chime (red C, blue E, yellow G, green A).
const DELIVER_SOUNDS: Array[String] = ["deliver_red", "deliver_blue", "deliver_yellow", "deliver_green"]

## Tests: false keeps the screen from switching (next_screen records it).
var auto_goto := true
var next_screen := ""

var sim
var world: Node2D
var camera: Camera2D
var night_mod: CanvasModulate
var ground: Node2D
var track_view: Node2D
var stations: Node2D
var points: Node2D
var animals: Node2D
var train_view: Node2D
var people: Node2D
var cover: Node2D
var fx: Node2D
var glow: Node2D
var hud: Node2D
var chuff: AudioStreamPlayer

var paused := false
var night := 0.0
var finale_t := -1.0
var time := 0.0
var _whistle_cool := 0.0
var _brake_squealed := false
var _hops := 0
var _toots_done := 0
var _firework_t := 0.0


func _ready() -> void:
	var gunner := Players.is_seated(Players.Seat.GUNNER)
	var honker := Players.is_seated(Players.Seat.HONKER)
	sim = Sim.new(Game.seed_value)
	sim.solo = not gunner
	sim.auto_whistle = not honker
	sim.run_len = Game.run_seconds
	sim.event.connect(_on_event)
	_build()
	_apply_setup()
	Sfx.music("music_rails")
	_start_chuff()


func _build() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	night_mod = CanvasModulate.new()
	night_mod.color = Color.WHITE
	add_child(night_mod)
	var track = sim.track
	ground = _add(GroundView.new(), 0)
	ground.setup(track)
	track_view = _add(TrackView.new(), 1)
	track_view.setup(track)
	stations = _add(StationView.new(), 2)
	stations.setup(track, sim)
	points = _add(PointsView.new(), 3)
	points.setup(track, sim)
	animals = _add(AnimalView.new(), 4)
	animals.setup(sim)
	train_view = _add(TrainView.new(), 5)
	train_view.setup(sim, Game.train_riders())
	people = _add(PeopleView.new(), 7)
	people.setup(sim, stations, train_view)
	people.arrived_home.connect(_on_arrived_home)
	cover = _add(CoverView.new(), 9)
	cover.setup(track, sim.tunnel_range)
	fx = _add(FxView.new(), 10)
	camera = Camera2D.new()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(Track.WORLD.x)
	camera.limit_bottom = int(Track.WORLD.y)
	world.add_child(camera)
	camera.make_current()
	_follow(10.0)  # start on the train, not sliding over from a corner
	var glow_layer := CanvasLayer.new()
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	glow = GlowView.new()
	glow.setup(stations, train_view)
	glow_layer.add_child(glow)
	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Hud.new()
	hud.setup(sim)
	hud_layer.add_child(hud)


func _add(node: Node2D, z: int) -> Node2D:
	node.z_index = z
	world.add_child(node)
	return node


## Demo captures: start near the end of a run.
func _apply_setup() -> void:
	var setup: Dictionary = Game.level_setup
	if setup.is_empty():
		return
	var n: int = setup.get("deliveries", 0)
	for i in n:
		var c := i % 4
		sim.deliveries.append(c)
		stations.lit[c] += 1
	if setup.has("time_left"):
		sim.run_len = sim.time + float(setup.time_left)


func _start_chuff() -> void:
	chuff = AudioStreamPlayer.new()
	chuff.volume_db = -60.0
	add_child(chuff)
	var s := load_stream("res://audio/chuff_loop.wav")
	if s == null or Sfx.muted:
		return
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = int(s.get_length() * s.mix_rate)
	chuff.stream = s
	chuff.play()


## Same rule as the shared Sfx: from source read the file bytes (no import
## cache needed); an exported build goes through the ResourceLoader.
static func load_stream(path: String) -> AudioStreamWAV:
	if OS.has_feature("template"):
		return load(path) if ResourceLoader.exists(path) else null
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		return null
	return AudioStreamWAV.load_from_file(abs)


# ---------------------------------------------------------------- input

## This frame's Sim input, read per seat. Only the points seat throws the
## points and opens the doors; only the whistle seat whistles.
static func read_input() -> Dictionary:
	var driver := Players.Seat.DRIVER
	var mv := Players.move(driver)
	return {
		"up": mv.y < -0.4,
		"down": mv.y > 0.4 or Players.pressed(driver, "b"),
		"horn": Players.just_pressed(driver, "a"),
		"points": Players.dir4_just_pressed(Players.Seat.GUNNER),
		"doors": Players.just_pressed(Players.Seat.GUNNER, "a"),
		"whistle": Players.just_pressed(Players.Seat.HONKER, "any"),
	}


func _process(delta: float) -> void:
	if next_screen != "":
		return
	if _pause_input():
		return
	step(delta)


func step(delta: float) -> void:
	time += delta
	_whistle_cool = maxf(0.0, _whistle_cool - delta)
	var input := read_input()
	if sim.ended:
		input = {}
	if input.get("down", false) and sim.train.speed > 140.0 and not _brake_squealed:
		_brake_squealed = true
		Sfx.play("brake_squeal", 1.0, -4.0)
		fx.dust(train_view.nose_position())
	if not input.get("down", false):
		_brake_squealed = false
	sim.step(delta, input)
	_follow(delta)
	fx.chimney(train_view.chimney_position(), absf(sim.train.speed))
	_audio(delta)
	if sim.ended:
		_finale(delta)


func _pause_input() -> bool:
	if sim.ended:
		return false
	var driver := Players.Seat.DRIVER
	if Players.just_pressed(driver, "start"):
		_set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(driver, "a"):
			_set_paused(false)
		elif Players.just_pressed(driver, "b"):
			_leave("join")
	return paused


func _set_paused(on: bool) -> void:
	paused = on
	hud.paused = on
	Sfx.play("select")
	if chuff:
		chuff.stream_paused = on


func _leave(screen_name: String) -> void:
	next_screen = screen_name
	set_process(false)
	if chuff:
		chuff.stop()
	if auto_goto:
		Game.goto.call_deferred(screen_name)


# ---------------------------------------------------------------- camera

func _follow(delta: float) -> void:
	var nose: Vector2 = train_view.nose_position()
	var ahead: Vector2 = sim.train.heading() * clampf(sim.train.speed, 0.0, 300.0) * 0.7
	var target: Vector2 = nose + ahead - sim.train.heading() * 120.0
	camera.position = camera.position.lerp(target, minf(1.0, delta * 2.5))
	var z := lerpf(0.9, 0.72, (sim.train.cars - 1) / 4.0)
	if sim.ended:
		z = 0.66
	var cz := lerpf(camera.zoom.x, z, minf(1.0, delta * 1.5))
	camera.zoom = Vector2(cz, cz)


# ---------------------------------------------------------------- events

func _on_event(kind: String, data: Dictionary) -> void:
	points.on_event(kind, data)
	match kind:
		"points":
			Sfx.play("points_clack", 1.0 + 0.1 * data.branch)
		"points_same":
			Sfx.play("points_clack", 0.8, -8.0)
		"points_locked":
			Sfx.play("points_clack", 0.6, -10.0)
		"docked":
			stations.flash[data.station] = 1.2
			fx.dust(train_view.nose_position())
			_hops = 0
		"perfect":
			Sfx.play("perfect_stop")
			fx.sparkle(train_view.nose_position(), Palette.GLOW, 18)
		"rollback":
			Sfx.play("beep_beep")
		"doors":
			Sfx.play("doors_open")
		"bell":
			Sfx.play("bell")
		"boarded":
			_hops += 1
			Sfx.play("hop", 1.0 + 0.06 * mini(_hops, 8))
		"delivered":
			Sfx.play("hop", 0.85)
		"coupled":
			Sfx.play("couple")
			train_view.on_coupled()
			fx.sparkle(train_view.xforms[train_view.xforms.size() - 1].origin, Palette.WHITE, 10)
		"whistle":
			_whistle(data.by)
		"horn":
			Sfx.play("horn")
			train_view.toot = 0.5
			_animals_answer()
		"cow_aside":
			if data.why == "patience":
				Sfx.play("moo", 1.1, -3.0)
		"wheee":
			Sfx.play("wheee")
		"spawned":
			if time > 0.5:
				Sfx.play("hop", 1.4, -10.0)
		"run_end":
			finale_t = 0.0
			Sfx.music("music_night")


func _whistle(by: String) -> void:
	var at: Vector2 = train_view.chimney_position()
	train_view.toot = 0.6
	if by == "auto_long":
		Sfx.play("whistle_long")
		fx.ring(at, true)
		return
	fx.ring(at)
	if _whistle_cool > 0.0:
		return
	_whistle_cool = WHISTLE_COOLDOWN
	Sfx.play("whistle")
	if by == "kid":
		_animals_answer()


func _animals_answer() -> void:
	var kind: String = animals.whistle(train_view.nose_position())
	if kind == "":
		return
	var sound: String = {"cow": "moo", "duck": "quack", "sheep": "baa"}[kind]
	get_tree().create_timer(0.35).timeout.connect(func(): Sfx.play(sound, randf_range(0.9, 1.15)))
	for a in animals.animals:
		if a.look > animals.LOOK_TIME - 0.05 and a.kind == kind:
			fx.hearts(a.pos, 2)


func _on_arrived_home(station: int, colour: int) -> void:
	stations.lit[station] += 1
	Sfx.play(DELIVER_SOUNDS[colour])
	var h: Vector2 = stations.house_pos(station, mini(stations.lit[station] - 1, stations.HOUSES - 1))
	fx.sparkle(h, Palette.station(colour), 12)


# ---------------------------------------------------------------- audio

func _audio(_delta: float) -> void:
	if chuff == null or chuff.stream == null:
		return
	var v := absf(sim.train.speed)
	chuff.pitch_scale = clampf(0.55 + v / 260.0, 0.55, 1.8)
	var target := -60.0 if v < 5.0 else lerpf(-16.0, -6.0, clampf(v / 300.0, 0.0, 1.0))
	chuff.volume_db = move_toward(chuff.volume_db, target, 60.0 * _delta)


# ---------------------------------------------------------------- finale

func _finale(delta: float) -> void:
	finale_t += delta
	night = clampf(finale_t / 3.0, 0.0, 1.0)
	night_mod.color = Color.WHITE.lerp(NIGHT_TINT, night)
	stations.night = night
	glow.night = night
	hud.night = night
	if finale_t > 2.0:
		_firework_t -= delta
		if _firework_t <= 0.0:
			_firework_t = 0.45
			var c: Vector2 = camera.get_screen_center_position()
			glow.firework(c + Vector2(randf_range(-520, 520), randf_range(-330, 60)))
			Sfx.play("firework", randf_range(0.9, 1.2), -6.0)
	var toots := [7.0, 7.7, 8.4]
	if _toots_done < toots.size() and finale_t >= toots[_toots_done]:
		_toots_done += 1
		_whistle("auto")
	if finale_t >= FINALE_SECONDS:
		Game.deliveries.assign(sim.deliveries)
		Game.perfect_stops = sim.perfect_stops
		Game.stars = sim.deliveries.size() + sim.perfect_stops
		_leave("party")
