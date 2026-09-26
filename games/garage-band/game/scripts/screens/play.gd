extends Node2D
## The song: the band on the garage stage, the Lead's highway (left), the
## Drummer's pads (top right) and the Crasher's instrument (bottom right).
##
## Every frame: advance the song clock from game time, read each seat's
## input and turn presses into quantised band events (visual answer the same
## frame), let the band schedule its backing, then render the synth ahead of
## the clock. Everything that pulses reads the band clock, not wall time.
##
## - Lead (seat 0): up/down steps the lane, left/right picks the octave,
##   A strums (held = one note per eighth), B crashes when no Crasher sits,
##   start pauses (A/start resumes, B stops the song -> select).
## - Drummer (seat 1): a direction hits that pad, A is the kick.
## - Crasher (seat 2): any button crashes. It can never pause or stop.
## The song always plays to its end, then goes to the party.

const Band := preload("res://scripts/music/band.gd")
const SynthPlayer := preload("res://scripts/music/synth_player.gd")
const Songs := preload("res://scripts/music/songs.gd")
const Draw := preload("res://scripts/view/draw.gd")
const Garage := preload("res://scripts/view/garage.gd")
const Stage := preload("res://scripts/view/stage.gd")
const Highway := preload("res://scripts/view/highway.gd")
const DrumPads := preload("res://scripts/view/drum_pads.gd")
const CrashPad := preload("res://scripts/view/crash_pad.gd")
const TopHud := preload("res://scripts/view/top_hud.gd")
const Fx := preload("res://scripts/view/fx.gd")

const LEAD := 0
const DRUMMER := 1
const CRASHER := 2
const REPEAT_DELAY := 0.3
const REPEAT_EVERY := 0.12

const VIGNETTE_SHADER := """
shader_type canvas_item;
uniform float pulse = 0.0;
uniform vec4 glow : source_color = vec4(1.0, 0.8, 0.46, 1.0);
void fragment() {
	vec2 d = (UV - 0.5) * vec2(1.0, 0.62);
	float v = smoothstep(0.18, 0.62, length(d));
	vec3 c = mix(vec3(0.02, 0.02, 0.06), glow.rgb, pulse * 0.55);
	COLOR = vec4(c, v * (0.62 - 0.25 * pulse));
}
"""

var auto_goto := true
var next_screen := ""

var band: Band
var player: SynthPlayer
var now := 0
var lead_lane := 2
var lead_octave := 0
var paused := false
var finished := false
var live_drummer := false
var live_crasher := false

var garage: Node2D
var stage: Node2D
var highway: Node2D
var pads: Node2D
var crash_pad: Node2D
var hud: Node2D
var fx: Node2D
var vignette: ColorRect
var pause_overlay: Node2D
var _panels: Node2D
var _hold_dir := 0
var _hold_t := 0.0
var _seen_drums := 0


func _ready() -> void:
	live_drummer = Players.is_seated(DRUMMER)
	live_crasher = Players.is_seated(CRASHER)
	band = Band.new(Game.song_index, live_drummer, live_crasher)
	player = SynthPlayer.new(band.synth)
	add_child(player)
	Sfx.stop_music()
	_build()


func _build() -> void:
	garage = Garage.new()
	add_child(garage)
	stage = Stage.new()
	add_child(stage)
	stage.setup(_rider_ids())
	vignette = ColorRect.new()
	vignette.size = Vector2(640, 360)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = VIGNETTE_SHADER
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vignette.material = mat
	add_child(vignette)
	_panels = Panels.new()
	_panels.screen = self
	add_child(_panels)
	highway = Highway.new()
	highway.band = band
	add_child(highway)
	pads = DrumPads.new()
	pads.band = band
	pads.ghost = not live_drummer
	add_child(pads)
	crash_pad = CrashPad.new()
	crash_pad.band = band
	crash_pad.ghost = not live_crasher
	add_child(crash_pad)
	hud = TopHud.new()
	hud.band = band
	add_child(hud)
	fx = Fx.new()
	add_child(fx)
	_panels.add_minis()
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	add_child(pause_overlay)
	_sync_views()


func _rider_ids() -> Array:
	var ids := []
	for seat in 3:
		var r: String = Players.riders[seat]
		if Players.is_seated(seat) and r == "":
			r = Game.roster[seat % Game.roster.size()]
		ids.append(r if Players.is_seated(seat) else "")
	return ids


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	if finished:
		return
	if _pause_input():
		return
	player.advance(delta)
	now = player.now
	_lead_input(delta)
	if live_drummer:
		_drummer_input()
	if live_crasher and Players.just_pressed(CRASHER, "any"):
		_crash()
	band.update(now)
	player.render()
	_sync_views()
	if band.is_finished(now):
		_finish()


# ---------------------------------------------------------------- input

func _lead_input(delta: float) -> void:
	var d := Players.dir4_just_pressed(LEAD)
	var held := Players.dir4(LEAD)
	if d.y != 0:
		_step_lane(-d.y)
		_hold_dir = -d.y
		_hold_t = 0.0
	elif held.y != 0 and -held.y == _hold_dir:
		_hold_t += delta
		if _hold_t >= REPEAT_DELAY:
			_hold_t -= REPEAT_EVERY
			_step_lane(_hold_dir)
	else:
		_hold_dir = 0
	if d.x > 0:
		lead_octave = 1
	elif d.x < 0:
		lead_octave = 0
	if Players.just_pressed(LEAD, "a"):
		_strum(false)
	elif Players.pressed(LEAD, "a"):
		_strum(true)
	if Players.just_pressed(LEAD, "b") and not live_crasher:
		_crash()


func _step_lane(dir: int) -> void:
	lead_lane = clampi(lead_lane + dir, 0, 4)


func _strum(repeat: bool) -> void:
	var r := band.strum(now, lead_lane, lead_octave, repeat)
	if not r.sounded:
		return
	highway.lane_flash[lead_lane] = 1.0
	stage.strum = 1.0
	if r.gem:
		fx.burst(highway.lane_pos(lead_lane, 0.0), Draw.LANE_COLORS[lead_lane], 10)
		_gem_feedback()


func _drummer_input() -> void:
	var d := Players.dir4_just_pressed(DRUMMER)
	var pad := -1
	if d == Vector2i(0, -1):
		pad = Songs.PAD_HAT
	elif d == Vector2i(-1, 0):
		pad = Songs.PAD_SNARE
	elif d == Vector2i(1, 0):
		pad = Songs.PAD_TOM
	elif d == Vector2i(0, 1):
		pad = Songs.PAD_KICK
	if pad >= 0:
		_drum(pad)
	if Players.just_pressed(DRUMMER, "a"):
		_drum(Songs.PAD_KICK)


func _drum(pad: int) -> void:
	pads.bounce[pad] = 1.0   # the visual answer is always immediate
	var r := band.drum(now, pad)
	if r.sounded and r.gem:
		fx.burst(pads.pad_pos(pad), Draw.PAD_COLORS[pad], 12, 140.0, 6.0)
		_gem_feedback()


func _crash() -> void:
	crash_pad.wobble = 1.0
	stage.crash_wobble = 1.0
	var r := band.crash(now)
	if r.sounded:
		fx.burst(crash_pad.CENTER + Vector2(0, -10), Draw.YELLOW, 14, 170.0, 6.0)
		if r.gem:
			_gem_feedback()


func _gem_feedback() -> void:
	hud.star_pulse = 1.0
	Sfx.play("gem_burst", 1.0 + randf() * 0.1, -8.0)


## Pause belongs to the Lead. Returns true while paused.
func _pause_input() -> bool:
	if Players.just_pressed(LEAD, "start"):
		_set_paused(not paused)
		return paused
	if paused:
		if Players.just_pressed(LEAD, "a"):
			_set_paused(false)
		elif Players.just_pressed(LEAD, "b"):
			_stop()
		return true   # the resuming press does not also strum
	return false


func _set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	player.player.stream_paused = on


func _stop() -> void:
	finished = true
	player.stop()
	Sfx.play("select")
	next_screen = "select"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("select")


func _finish() -> void:
	finished = true
	Game.recording = band.synth.recording.duplicate(true)
	Game.hits_log = band.hits_log.duplicate(true)
	Game.stars = band.stars
	Game.song_samples = band.done_sample
	next_screen = "party"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("party")


# ---------------------------------------------------------------- views

func _sync_views() -> void:
	var beat := band.beat_at(now)
	var in_song := beat >= 0.0
	stage.beat_phase = fposmod(beat, 1.0)
	stage.bar_phase = fposmod(beat / 4.0, 1.0)
	stage.bass_pulse = exp(-Band.since_last(band.bass_times, now) * 9.0)
	stage.strum = maxf(0.0, stage.strum - 0.12)
	stage.crash_wobble = maxf(0.0, stage.crash_wobble - 0.05)
	var crashes := band.crash_count_until(now)
	stage.light_set = crashes
	stage.light_flash = exp(-Band.since_last(band.crash_times, now) * 3.0) if crashes > 0 else 0.0
	var since_crash := Band.since_last(band.crash_times, now)
	var shown := band.crash_index % Band.CRASH_SOUNDS.size()
	if since_crash < 0.7 and band.last_crash_sound(now) >= 0:
		shown = band.last_crash_sound(now)
	stage.crash_sound = shown
	crash_pad.sound = shown
	# Drum squash and the pads' auto glow from the drums actually sounding.
	for i in 4:
		stage.drum_squash[i] = maxf(0.0, stage.drum_squash[i] - 0.12)
	for j in range(band.drum_times.size() - 1, maxi(-1, band.drum_times.size() - 40), -1):
		var dt: Array = band.drum_times[j]
		var age := now - int(dt[0])
		if age < 0 or age > 2200:
			continue
		var k := 1.0 - float(age) / 2200.0
		stage.drum_squash[int(dt[1])] = maxf(stage.drum_squash[int(dt[1])], k)
		if not dt[2]:
			pads.auto_glow[int(dt[1])] = maxf(pads.auto_glow[int(dt[1])], k)
	garage.beat = 1.0 - stage.beat_phase if in_song else 0.0
	var pulse := 0.0
	if in_song and beat < band.bars * 4:
		pulse = pow(maxf(0.0, 1.0 - stage.bar_phase * 4.0), 2.0)
	(vignette.material as ShaderMaterial).set_shader_parameter("pulse", pulse)
	highway.now = now
	highway.lane = lead_lane
	highway.octave = lead_octave
	pads.now = now
	crash_pad.now = now
	hud.now = now


## The three seat panels, each with its rider's mini portrait in the corner.
class Panels extends Node2D:
	var screen: Node2D
	const RECTS := [Rect2(8, 64, 188, 288), Rect2(444, 64, 188, 152), Rect2(444, 224, 188, 128)]

	func add_minis() -> void:
		var ids: Array = screen._rider_ids()
		for seat in 3:
			if ids[seat] == "":
				continue
			var s: AnimatedSprite2D = Game.rider_sprite(ids[seat], 2)
			var r: Rect2 = RECTS[seat]
			s.position = r.position + Vector2(20, 20)
			screen.add_child(s)

	func _draw() -> void:
		for seat in 3:
			var live := Players.is_seated(seat)
			Draw.panel(self, RECTS[seat], Players.SEAT_COLORS[seat], live)
			if not live:
				var r: Rect2 = RECTS[seat]
				Draw.round_rect(self, r.grow(-3), 8, Color(Draw.INK, 0.4))


## Dimmed pause screen: a back arrow (Lead "b") and a play triangle ("a"/start).
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 640, 360), Color(Draw.INK, 0.72))
		Draw.round_rect(self, Rect2(200, 130, 100, 100), 16, Draw.SLATE)
		Draw.back_arrow(self, Vector2(250, 180), 2.4, Draw.WHITE)
		Draw.round_rect(self, Rect2(340, 130, 100, 100), 16, Draw.GREEN)
		Draw.play_triangle(self, Vector2(392, 180), 2.4, Draw.WHITE)
