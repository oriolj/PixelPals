extends Node
## Looping sounds with live volume and pitch (engine, spray, crackle).
## Shared Sfx only does one-shots and music, so this is a local helper that
## loads the WAV the same way (from the source bytes, or through the
## ResourceLoader in an exported build). Proposed for shared/ as Sfx.loop().

var _players := {}


func set_loop(sound: String, on: bool, volume_db := 0.0, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = _players.get(sound)
	if p == null:
		if not on:
			return
		p = AudioStreamPlayer.new()
		p.stream = _load(sound)
		add_child(p)
		_players[sound] = p
	if p.stream == null or Sfx.muted:
		return
	p.volume_db = volume_db
	p.pitch_scale = maxf(pitch, 0.05)
	if on and not p.playing:
		p.play()
	elif not on and p.playing:
		p.stop()


func is_on(sound: String) -> bool:
	var p: AudioStreamPlayer = _players.get(sound)
	return p != null and p.playing


func stop_all() -> void:
	for p in _players.values():
		p.stop()


func _load(sound: String) -> AudioStream:
	var path := "res://audio/%s.wav" % sound
	var s: AudioStream = null
	if OS.has_feature("template"):
		s = load(path) if ResourceLoader.exists(path) else null
	else:
		var abs := ProjectSettings.globalize_path(path)
		if FileAccess.file_exists(abs):
			s = AudioStreamWAV.load_from_file(abs)
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s
