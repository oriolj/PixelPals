extends Node
## Fire-and-forget sounds: Sfx.play("pop"). Missing files are silently skipped,
## so gameplay never waits for audio. Files: res://audio/<name>.wav (or .ogg).
## Variants: Sfx.play("honk") picks among honk_1.wav, honk_2.wav... if "honk.wav" is absent.

const POOL_SIZE := 12

var _players: Array[AudioStreamPlayer] = []
var _next := 0
var _streams := {}
var _music: AudioStreamPlayer
var muted := false


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)
	_music = AudioStreamPlayer.new()
	_music.volume_db = -8.0
	add_child(_music)


func _load(path: String) -> AudioStream:
	# Same rule as Art: from source read the file itself (no import cache
	# needed); an exported build only has the imported streams.
	if OS.has_feature("template"):
		return load(path) if ResourceLoader.exists(path) else null
	var abs := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(abs):
		return null
	if path.ends_with(".wav"):
		return AudioStreamWAV.load_from_file(abs)
	if path.ends_with(".ogg"):
		return AudioStreamOggVorbis.load_from_file(abs)
	return null


func _variants(sound: String) -> Array:
	if _streams.has(sound):
		return _streams[sound]
	var found := []
	for ext in ["wav", "ogg"]:
		var s := _load("res://audio/%s.%s" % [sound, ext])
		if s:
			found.append(s)
	if found.is_empty():
		for i in range(1, 10):
			var s := _load("res://audio/%s_%d.wav" % [sound, i])
			if s == null:
				break
			found.append(s)
	_streams[sound] = found
	return found


func play(sound: String, pitch := 1.0, volume_db := 0.0) -> void:
	if muted:
		return
	var v := _variants(sound)
	if v.is_empty():
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = v[randi() % v.size()]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()


func music(sound: String) -> void:
	var v := _variants(sound)
	if v.is_empty() or muted:
		_music.stop()
		return
	var s: AudioStream = v[0]
	if s is AudioStreamWAV:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	elif s is AudioStreamOggVorbis:
		s.loop = true
	if _music.stream == s and _music.playing:
		return
	_music.stream = s
	_music.play()


func stop_music() -> void:
	_music.stop()
