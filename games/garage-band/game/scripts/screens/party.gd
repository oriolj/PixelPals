extends Node2D
## Party: the band hears its own song. The recording (every synth event that
## was heard) is replayed through a fresh synth, so the playback is exactly
## the performance; the stage animates from the same events (strums, drum
## squashes, bass pulses, light changes on crashes), the band bows every
## couple of bars, and each gem the band hit flies over the stage as a star
## at the moment it was hit. The star count shows as big vector digits.
## At the end (or the Lead's "a" after a short guard) it goes back to select.

const Synth := preload("res://scripts/music/band_synth.gd")
const SynthPlayer := preload("res://scripts/music/synth_player.gd")
const Band := preload("res://scripts/music/band.gd")
const Songs := preload("res://scripts/music/songs.gd")
const Draw := preload("res://scripts/view/draw.gd")
const Garage := preload("res://scripts/view/garage.gd")
const Stage := preload("res://scripts/view/stage.gd")
const Fx := preload("res://scripts/view/fx.gd")

const SKIP_GUARD := 2.0
const TAIL := 1.5
const EMPTY_STAY := 6.0
const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]

var auto_goto := true
var next_screen := ""
var time := 0.0
var now := 0
var done := false
var shown_stars := 0
var player: SynthPlayer
var stage: Node2D
var garage: Node2D
var fx: Node2D
var bpm := 96.0
var spb := 0.0
var end_sample := 0

var _lead_times: Array[int] = []
var _bass_times: Array[int] = []
var _crash_times: Array = []
var _drum_times: Array = []    # [sample, pad]
var _hits: Array[Dictionary] = []
var _next_hit := 0
var _last_bar := -99
var _front: Node2D


func _ready() -> void:
	var song := Songs.get_song(Game.song_index)
	bpm = song.bpm
	spb = 22050.0 * 60.0 / bpm
	var syn := Synth.new()
	syn.record = false
	syn.load_recording(Game.recording)
	end_sample = Game.song_samples if not Game.recording.is_empty() else int(EMPTY_STAY * 22050)
	_index_cues()
	_hits = Game.hits_log.duplicate()
	_hits.sort_custom(func(a, b): return int(a.s) < int(b.s))
	player = SynthPlayer.new(syn)
	add_child(player)
	garage = Garage.new()
	add_child(garage)
	stage = Stage.new()
	add_child(stage)
	var ids := []
	for seat in 3:
		var r: String = Players.riders[seat]
		if r == "" and Players.is_seated(seat):
			r = Game.roster[seat % Game.roster.size()]
		ids.append(r)
	if ids == ["", "", ""]:
		ids = [Game.roster[0], Game.roster[1], Game.roster[2]]
	stage.setup(ids)
	# The band takes the whole stage for its bow: 1.5x around the rug.
	stage.scale = Vector2(1.5, 1.5)
	stage.position = Vector2(320, 304) - Vector2(320, 284) * 1.5
	fx = Fx.new()
	add_child(fx)
	_front = Front.new()
	_front.screen = self
	add_child(_front)
	Sfx.stop_music()
	Sfx.play("party", 1.0, -6.0)


func _index_cues() -> void:
	for ev in Game.recording:
		var s := int(ev.s)
		match int(ev.k):
			Synth.LEAD:
				_lead_times.append(s)
			Synth.BASS:
				_bass_times.append(s)
			Synth.SHOT:
				var n := str(ev.n)
				var ci := Band.CRASH_SOUNDS.find(n)
				if ci >= 0:
					_crash_times.append([s, ci])
				var pi := Songs.PAD_NAMES.find(n)
				if pi >= 0:
					_drum_times.append([s, pi])
	_lead_times.sort()
	_bass_times.sort()
	_crash_times.sort_custom(func(a, b): return a[0] < b[0])
	_drum_times.sort_custom(func(a, b): return a[0] < b[0])


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if done:
		return
	time += delta
	player.advance(delta)
	now = player.now
	player.render()
	var bar := int(floor((now - 4 * spb) / (spb * 4)))
	if bar != _last_bar:
		_last_bar = bar
		for k in 3:
			fx.burst(Vector2(fx.rng.randf_range(60, 580), fx.rng.randf_range(40, 140)),
				Draw.LANE_COLORS[fx.rng.randi() % 5], 10, 110.0, 5.0)
	_animate()
	while _next_hit < _hits.size() and int(_hits[_next_hit].s) <= now:
		var h: Dictionary = _hits[_next_hit]
		var x: float = [stage.X_LEAD, stage.X_DRUM, stage.X_CRASH][["lead", "drum", "crash"].find(h.kind)]
		var from := stage.position + Vector2(x, 240) * stage.scale
		var col: Color = Draw.YELLOW
		if h.kind == "lead":
			col = Draw.LANE_COLORS[int(h.i)]
		elif h.kind == "drum":
			col = Draw.PAD_COLORS[int(h.i)]
		fx.fly(from, col)
		shown_stars += 1
		_next_hit += 1
	_front.queue_redraw()
	var over := now >= end_sample + int(TAIL * 22050)
	if over or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		_leave()


func _animate() -> void:
	var beat := (now - 4 * spb) / spb
	stage.beat_phase = fposmod(beat, 1.0)
	stage.bar_phase = fposmod(beat / 4.0, 1.0)
	stage.bass_pulse = exp(-Band.since_last(_bass_times, now) * 9.0)
	stage.strum = exp(-Band.since_last(_lead_times, now) * 10.0)
	var crashes := 0
	var last_c := -1
	for c in _crash_times:
		if int(c[0]) <= now:
			crashes += 1
			last_c = int(c[1])
	stage.light_set = crashes
	stage.light_flash = exp(-Band.since_last(_crash_times, now) * 3.0) if crashes > 0 else 0.0
	stage.crash_wobble = exp(-Band.since_last(_crash_times, now) * 4.0) if crashes > 0 else 0.0
	stage.crash_sound = maxi(0, last_c)
	for i in 4:
		stage.drum_squash[i] = 0.0
	for j in range(_drum_times.size() - 1, -1, -1):
		var age := now - int(_drum_times[j][0])
		if age < 0:
			continue
		if age > 2200:
			break
		var p := int(_drum_times[j][1])
		stage.drum_squash[p] = maxf(stage.drum_squash[p], 1.0 - age / 2200.0)
	# Bows: a slow bow every two bars, and a deep one at the very end.
	var bars := beat / 4.0
	var bow := maxf(0.0, sin(bars * PI)) if fposmod(bars, 2.0) < 1.0 else 0.0
	bow = pow(bow, 3.0)
	if now >= end_sample - int(spb * 4):
		bow = minf(1.0, float(now - (end_sample - int(spb * 4))) / (spb * 2.0))
	if Game.recording.is_empty():
		bow = pow(maxf(0.0, sin(time * 1.6)), 3.0)
	stage.bow = bow
	garage.beat = 1.0 - stage.beat_phase


func _leave() -> void:
	done = true
	player.stop()
	next_screen = "select"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("select")


class Front extends Node2D:
	var screen: Node2D

	func _draw() -> void:
		# The star count: a big star and vector digits in a banner.
		var n: int = screen.shown_stars
		var s := str(n)
		var px := 6.0
		var w := s.length() * 4 * px - px
		var total_w := 44 + 12 + w
		var x0 := 320 - total_w / 2.0
		Draw.round_rect(self, Rect2(x0 - 16, 62, total_w + 32, 56), 14, Color(Draw.INK, 0.8))
		var pulse := 1.0 + 0.1 * sin(screen.time * 8.0)
		Draw.star(self, Vector2(x0 + 20, 90), 22 * pulse, Draw.INK)
		Draw.star(self, Vector2(x0 + 20, 90), 19 * pulse, Draw.YELLOW)
		var dx := x0 + 56
		for k in s.length():
			var glyph: Array = screen.DIGITS[int(s[k])]
			for row in 5:
				for col in 3:
					if glyph[row][col] == "#":
						draw_rect(Rect2(dx + (k * 4 + col) * px, 76 + row * px, px - 1, px - 1), Draw.WHITE)
		# Progress of the replay: the song's note walking along the line.
		var p := clampf(float(screen.now) / maxf(1.0, screen.end_sample), 0.0, 1.0)
		draw_line(Vector2(222, 342), Vector2(418, 342), Color(Draw.WHITE, 0.3), 3.0)
		draw_line(Vector2(222, 342), Vector2(lerpf(222, 418, p), 342), Draw.YELLOW, 3.0)
		Draw.note(self, Vector2(lerpf(222, 418, p), 340), 0.75, Draw.WHITE)
