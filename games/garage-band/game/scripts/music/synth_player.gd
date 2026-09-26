extends Node
## Feeds a BandSynth into an AudioStreamGenerator.
##
## The song clock comes from game time (`advance(delta)`), never from how
## much the audio device asks for: each call renders the synth up to
## now + LEAD and pushes what fits in the generator's ring buffer. When the
## device cannot take it (no device, dummy driver, a stall), the rendered
## frames are dropped rather than the clock slowing down, so visuals and
## music stay locked together and a --fixed-fps capture never drifts.

const Synth := preload("res://scripts/music/band_synth.gd")
const RATE := 22050
const LEAD := 0.06        # seconds rendered ahead of the song clock
const BUFFER := 0.1

var synth: Synth
var player: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback
## Song clock in samples (what is being heard / seen now).
var now := 0
var _time := 0.0
var dropped := 0


func _init(a_synth: Synth = null) -> void:
	synth = a_synth if a_synth else Synth.new()


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = BUFFER
	player = AudioStreamPlayer.new()
	player.stream = gen
	player.volume_db = -2.0
	add_child(player)
	if not Sfx.muted:
		player.play()
		playback = player.get_stream_playback() as AudioStreamGeneratorPlayback


## Moves the song clock by delta seconds (call render() after scheduling).
func advance(delta: float) -> void:
	_time += delta
	now = int(_time * RATE)


## Renders the synth up to now + LEAD and pushes it to the device.
func render() -> void:
	render_to(now + int(LEAD * RATE))


func render_to(target: int) -> void:
	var n := target - synth.clock
	if n <= 0:
		return
	var frames := synth.fill(n)
	if playback == null:
		return
	var room := playback.get_frames_available()
	if room >= n:
		playback.push_buffer(frames)
	elif room > 0:
		playback.push_buffer(frames.slice(0, room))
		dropped += n - room
	else:
		dropped += n


func stop() -> void:
	if player:
		player.stop()
