extends Node
## Demo mode: scripted players for `make demo` / `make shot`.
##
## Game.boot adds this node and calls start(screen) when the game runs with
## `-- --demo[=screen]`. It seats three scripted devices (demo:0..2) and
## feeds them input every frame for whatever screen is current, following
## Game.screen_changed, so --demo=join flows join -> select -> play -> party.
##
## On the play screen (the plan's script):
## - the Lead follows the gems exactly for 8 bars, then plays random scale
##   notes on the beat;
## - the Drummer hits the suggested pads with a random 0-120 ms error;
## - the Crasher presses every 1.7 s, off the beat on purpose (quantised).

const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const RIDERS: Array[String] = ["penguin", "monkey", "fox"]
const Band := preload("res://scripts/music/band.gd")

var use_goto := true
var screen := ""
var t := 0.0
## Length of the current frame (the play screen advances its clock by it
## before reading input, so the driver predicts the clock with it).
var frame_dt := 1.0 / 30.0
var rng := RandomNumberGenerator.new()

# Play-screen state.
var _prev_move: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _prev_a: Array[bool] = [false, false, false]
var _drum_plan: Array[Array] = []   # [press sample, pad]
var _lead_done := {}
var _random_target := Vector2i(2, 0)
var _random_step := -1


func _init() -> void:
	process_priority = -200   # before Players polls (-100)
	rng.seed = 42


func _ready() -> void:
	Game.screen_changed.connect(_on_screen_changed)


func start(start_screen: String) -> void:
	if not Game.SCREENS.has(start_screen):
		start_screen = "join"
	Players.reset()
	Players.clear_scripted()
	for d in DEVICES:
		Players.set_scripted(d, {})
	match start_screen:
		"select":
			seat_three()
		"play":
			seat_three()
			_set_riders()
			Game.song_index = 0
		"party":
			seat_three()
			_set_riders()
			Game.song_index = 0
			make_party_recording()
	screen = start_screen
	t = 0.0
	if use_goto:
		Game.goto(start_screen)


func seat_three() -> void:
	for d in DEVICES:
		if Players.seat_of(d) == -1:
			Players.join(d)


func _set_riders() -> void:
	for s in 3:
		Players.riders[s] = RIDERS[s]


## A short recorded performance for the party screen: 10 bars of the demo
## band (Lead on the gems, Drummer on the pads, crashes every 1.7 s).
func make_party_recording(bars := 10) -> void:
	var band := Band.new(0, true, true)
	var frame := 735
	var now := 0
	var until := band.sample_at_beat(bars * 4)
	var next_crash := int(1.7 * 22050)
	var li := 0
	var di := 0
	while now < until:
		now += frame
		while li < band.gems_lead.size() and int(band.gems_lead[li].sample) <= now:
			var g: Dictionary = band.gems_lead[li]
			band.strum(int(g.sample), int(g.lane), int(g.octave))
			li += 1
		while di < band.gems_drum.size() and int(band.gems_drum[di].sample) <= now:
			var g2: Dictionary = band.gems_drum[di]
			band.drum(int(g2.sample) + rng.randi_range(0, 2646), int(g2.pad))
			di += 1
		if now >= next_crash:
			band.crash(now)
			next_crash += int(1.7 * 22050)
		band.update(now)
		band.synth.fill(now + 1300 - band.synth.clock)
	Game.recording = band.synth.recording.duplicate(true)
	Game.hits_log = band.hits_log.duplicate(true)
	Game.stars = band.stars
	Game.song_samples = until


func _on_screen_changed(screen_name: String) -> void:
	screen = screen_name
	t = 0.0
	_drum_plan.clear()
	_lead_done.clear()
	_random_step = -1
	for d in DEVICES:
		Players.set_scripted(d, {})


func _process(delta: float) -> void:
	frame_dt = delta
	t += delta
	drive(screen, t)


## Sets this frame's scripted input for every demo device.
func drive(screen_name: String, time: float) -> void:
	var st: Array[Dictionary] = [{}, {}, {}]
	match screen_name:
		"join":
			for i in 3:
				st[i]["a"] = _pulse(time, 0.8 + i * 1.0)
			st[0]["a"] = st[0]["a"] or (time >= 3.6 and time < 4.9)
			st[0]["start"] = _pulse(time, 5.2)
		"select":
			st[0]["move"] = Vector2(_flick(time, 0.6) + _flick(time, 1.3), 0)
			st[1]["move"] = Vector2(-_flick(time, 0.9), 0)
			for k in 3:
				st[2]["a"] = st[2].get("a", false) or _pulse(time, 0.5 + k * 0.45)
			st[0]["a"] = _pulse(time, 2.2)
			st[1]["a"] = _pulse(time, 2.8)
			# Song phase (after the crasher's auto-ready at ~4.4 s): browse, then play.
			st[0]["move"] += Vector2(_flick(time, 5.6) + _flick(time, 6.6) - _flick(time, 7.6) - _flick(time, 8.4), 0)
			st[1]["a"] = st[1]["a"] or _pulse(time, 6.0)
			st[2]["a"] = st[2]["a"] or _pulse(time, 7.0)
			st[0]["a"] = st[0]["a"] or _pulse(time, 9.2)
		"play":
			_drive_play(st)
		"party":
			st[2]["a"] = fmod(time, 1.2) < 0.1
	for i in 3:
		Players.set_scripted(DEVICES[i], st[i])


func _drive_play(st: Array[Dictionary]) -> void:
	var scr = Game.current
	if scr == null or not is_instance_valid(scr) or scr.get("band") == null:
		return
	var band: Band = scr.band
	# The clock the screen will reach this frame (it advances before reading input).
	var now: int = scr.now + int(frame_dt * 22050)
	var spb := band.spb
	# Lead: steer to the next gem's lane/octave, strum on its sample (first 8
	# bars), then random scale notes on every beat.
	var target := Vector2i(-1, -1)
	var press := false
	if band.bar_at(now) < 8:
		for g in band.gems_lead:
			if int(g.sample) < now - 1500 or _lead_done.has(g.step):
				continue
			target = Vector2i(int(g.lane), int(g.octave))
			if now >= int(g.sample):
				press = true
				_lead_done[g.step] = true
			break
	else:
		var b := int(floor(band.beat_at(now)))
		if b != _random_step:
			_random_step = b
			_random_target = Vector2i(rng.randi_range(0, 4), rng.randi_range(0, 1))
			press = true
		target = _random_target
	var mv := Vector2.ZERO
	if target.x >= 0:
		if scr.lead_octave != target.y:
			mv = Vector2(1 if target.y == 1 else -1, 0)
		elif scr.lead_lane != target.x:
			mv = Vector2(0, -1 if target.x > scr.lead_lane else 1)
	if _prev_move[0] != Vector2.ZERO:
		mv = Vector2.ZERO   # release between flicks, so each is a new press
	st[0]["move"] = mv
	st[0]["a"] = press and not _prev_a[0]
	# Drummer: plan one press per drum gem with a 0-120 ms error.
	if _drum_plan.is_empty():
		for g in band.gems_drum:
			_drum_plan.append([int(g.sample) + rng.randi_range(0, 2646), int(g.pad)])
	var dmove := Vector2.ZERO
	while not _drum_plan.is_empty() and _drum_plan[0][0] <= now:
		var p: Array = _drum_plan.pop_front()
		if now - int(p[0]) < 3000:
			dmove = [Vector2.UP, Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN][int(p[1])]
	if _prev_move[1] != Vector2.ZERO and dmove == _prev_move[1]:
		dmove = Vector2.ZERO
	st[1]["move"] = dmove
	# Crasher: every 1.7 s of song time.
	var secs := now / 22050.0
	st[2]["a"] = fmod(secs, 1.7) < 0.05 and secs > 0.5
	for i in 3:
		_prev_move[i] = st[i].get("move", Vector2.ZERO)
		_prev_a[i] = st[i].get("a", false)


func _pulse(time: float, at: float) -> bool:
	return time >= at and time < at + 0.12


func _flick(time: float, at: float) -> float:
	return 1.0 if time >= at and time < at + 0.1 else 0.0
