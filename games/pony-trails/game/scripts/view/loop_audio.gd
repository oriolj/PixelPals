extends RefCounted
## Looping sounds the shared Sfx autoload does not cover (the rover's hum, the
## helicopter's buzz): a player per loop, the WAV read from source bytes like
## sfx.gd. Muted runs (demo captures) and missing files give a silent player.

static func load_wav(sound: String) -> AudioStream:
	var path := "res://audio/%s.wav" % sound
	if OS.has_feature("template"):
		return load(path) if ResourceLoader.exists(path) else null
	var abs_path := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs_path):
		return null
	return AudioStreamWAV.load_from_file(abs_path)


## An AudioStreamPlayer looping `sound` at `volume_db`, playing unless muted.
static func looping(parent: Node, sound: String, volume_db := -12.0, playing := true) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.volume_db = volume_db
	parent.add_child(p)
	var s := load_wav(sound)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	if s and not Sfx.muted:
		p.stream = s
		if playing:
			p.play()
	return p


## Start or stop a loop player without restarting it every frame.
static func set_on(p: AudioStreamPlayer, on: bool) -> void:
	if p == null or p.stream == null:
		return
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()
