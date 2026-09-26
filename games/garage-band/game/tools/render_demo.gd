extends SceneTree
## Renders the synth output of the play demo to a WAV, headless.
##
## godot --headless --path game -s tools/render_demo.gd -- --out=<abs path.wav> [--seconds=40]
##
## It runs the real play screen with the real demo driver (same scripted
## Lead, Drummer and Crasher as `make shot SHOT_SCREEN=play`), stepping game
## time at a fixed 30 fps, and captures every frame the synth renders. The
## result is measured by `tools/sfx.py --measure` (make audio-check).

const RATE := 22050


func _initialize() -> void:
	var out := ""
	var seconds := 40.0
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
		elif a.begins_with("--seconds="):
			seconds = float(a.substr(10))
	if out == "":
		push_error("render_demo: pass -- --out=<file.wav>")
		quit(1)
		return
	_run.call_deferred(out, seconds)


func _run(out: String, seconds: float) -> void:
	var sfx: Node = root.get_node("Sfx")
	sfx.muted = true   # no device needed: the synth is captured, not played
	var holder := Node2D.new()
	root.add_child(holder)
	var game: Node = root.get_node("Game")
	game.set_root(holder)
	# load(), not preload(): the scripts name autoloads, which a -s script
	# only has once the tree is running.
	var dd: Node = load("res://scripts/demo_driver.gd").new()
	holder.add_child(dd)
	dd.start("play")
	var screen: Node = game.current
	screen.set_process(false)
	dd.set_process(false)
	var players: Node = root.get_node("Players")
	players.set_process(false)
	screen.band.synth.capturing = true
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < seconds and not screen.finished:
		t += dt
		dd.t = t
		# The driver predicts the clock from the frame delta; give it ours.
		dd.drive("play", t)
		players.poll()
		screen.step(dt)
	var buf: PackedFloat32Array = screen.band.synth.capture
	_write_wav(out, buf)
	print("render_demo: %.1f s of audio, %d stars -> %s" % [buf.size() / float(RATE), screen.band.stars, out])
	game.set_root(null)
	holder.queue_free()
	quit(0)


func _write_wav(path: String, buf: PackedFloat32Array) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	var n := buf.size()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(36 + n * 2)
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(16)
	f.store_16(1)
	f.store_16(1)
	f.store_32(RATE)
	f.store_32(RATE * 2)
	f.store_16(2)
	f.store_16(16)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(n * 2)
	var pcm := PackedByteArray()
	pcm.resize(n * 2)
	for i in n:
		pcm.encode_s16(i * 2, int(clampf(buf[i], -1.0, 1.0) * 32767.0))
	f.store_buffer(pcm)
	f.close()
