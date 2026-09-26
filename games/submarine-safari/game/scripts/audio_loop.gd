extends RefCounted
## Looping players the shared Sfx autoload does not cover: the sub's hum and
## the reef music on its own bus (with a low-pass whose cutoff follows the
## depth). Loads WAVs from source bytes like sfx.gd (no import cache).

const MUSIC_BUS := "Reef"


static func load_wav(sound: String) -> AudioStream:
	var path := "res://audio/%s.wav" % sound
	if OS.has_feature("template"):
		return load(path) if ResourceLoader.exists(path) else null
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	return AudioStreamWAV.load_from_file(abs_path)


## An AudioStreamPlayer looping `sound`, already playing (unless muted or missing).
static func looping(parent: Node, sound: String, volume_db: float, bus := "Master") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = bus
	p.volume_db = volume_db
	parent.add_child(p)
	var s := load_wav(sound)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	if s and not Sfx.muted:
		p.stream = s
		p.play()
	return p


## The music bus with its low-pass filter (created once per run of the game).
static func music_bus() -> int:
	var idx := AudioServer.get_bus_index(MUSIC_BUS)
	if idx == -1:
		AudioServer.add_bus()
		idx = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, MUSIC_BUS)
		AudioServer.set_bus_send(idx, "Master")
		var lp := AudioEffectLowPassFilter.new()
		lp.cutoff_hz = 2000.0
		AudioServer.add_bus_effect(idx, lp)
	return idx


static func set_music_cutoff(hz: float) -> void:
	var idx := music_bus()
	var fx := AudioServer.get_bus_effect(idx, 0)
	if fx is AudioEffectLowPassFilter:
		fx.cutoff_hz = hz
