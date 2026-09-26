extends GutTest
## Party: the recording replays through the same synth, stars fly at the
## hit times, the band bows, and it returns to select.

const PartyScreen := preload("res://scripts/screens/party.gd")
const DemoDriver := preload("res://scripts/demo_driver.gd")
const Synth := preload("res://scripts/music/band_synth.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Sfx.muted = true
	Players.reset()
	Players.clear_scripted()
	var dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)
	dd.start("party")   # seats three and records a short performance


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Sfx.muted = false


func _open() -> void:
	screen = PartyScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func test_party_replays_the_recording_exactly() -> void:
	var rec := Game.recording.duplicate(true)
	# What the band heard, rendered in one go from the same events...
	var heard := Synth.new()
	heard.load_recording(rec)
	var a := heard.fill(22050 * 4)
	_open()
	screen.player.synth.capturing = true
	for i in 120:
		screen.step(DT)
	var b: PackedFloat32Array = screen.player.synth.capture
	assert_gt(b.size(), 22050 * 4)
	var same := true
	for i in 22050 * 4:
		if absf(a[i].x - b[i]) > 1e-5:
			same = false
			break
	assert_true(same, "the party plays back exactly what was heard")


func test_stars_fly_and_the_band_bows() -> void:
	_open()
	var bowed := false
	while not screen.done and screen.time < 30.0:
		screen.step(DT)
		if screen.stage.bow > 0.5:
			bowed = true
	assert_eq(screen.shown_stars, Game.hits_log.size(), "one star per gem hit")
	assert_true(bowed, "the band bows")
	assert_eq(screen.next_screen, "select", "and back to the song picker")


func test_only_the_lead_skips_after_the_guard() -> void:
	_open()
	for i in 70:
		Players.set_scripted("demo:2", {"a": i % 2 == 0})
		Players.set_scripted("demo:0", {"a": i == 10})
		Players.poll()
		screen.step(DT)
	assert_false(screen.done, "the toddler and an early press cannot skip")
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	screen.step(DT)
	assert_true(screen.done)
