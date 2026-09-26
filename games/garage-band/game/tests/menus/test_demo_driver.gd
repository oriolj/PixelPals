extends GutTest
## Demo driver: scripted input for all three seats, following the screens.

const DemoDriver := preload("res://scripts/demo_driver.gd")

var dd: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func test_play_start_seats_three_with_riders() -> void:
	dd.start("play")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.song_index, 0)


func test_party_start_makes_a_recording() -> void:
	dd.start("party")
	assert_gt(Game.recording.size(), 50, "a performance to replay")
	assert_gt(Game.hits_log.size(), 10, "the demo band hits gems")
	assert_eq(Game.stars, Game.hits_log.size())
	assert_gt(Game.song_samples, 0)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	var presses := {}
	var t := 0.0
	while t < 3.5:
		dd.drive("join", t)
		Players.poll()
		for d in ["demo:0", "demo:1", "demo:2"]:
			if Players.device_just_pressed(d, "a"):
				presses[d] = t
		t += 1.0 / 30.0
	assert_eq(presses.size(), 3)
	assert_lt(presses["demo:0"], presses["demo:1"])
	assert_lt(presses["demo:1"], presses["demo:2"])


func test_play_script_follows_the_gems_then_jams() -> void:
	Sfx.muted = true
	dd.start("play")
	var screen: Node2D = load("res://scripts/screens/play.gd").new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)
	var old = Game.current
	Game.current = screen
	var dt := 1.0 / 30.0
	var t := 0.0
	while t < 26.0:
		t += dt
		dd.drive("play", t)
		Players.poll()
		screen.step(dt)
	Game.current = old
	Sfx.muted = false
	var band = screen.band
	var lead_hits := 0
	var early_lead := 0
	for g in band.gems_lead:
		if g.hit:
			lead_hits += 1
	for g in band.gems_lead:
		if band.bar_at(int(g.sample)) < 8 and int(g.sample) < screen.now - 3000:
			early_lead += 1
	assert_gte(lead_hits, early_lead - 2, "the Lead hits (nearly) every gem of the first 8 bars")
	var drum_hits := 0
	for g in band.gems_drum:
		if g.hit:
			drum_hits += 1
	assert_gt(drum_hits, 20, "the Drummer follows the pads")
	assert_gte(band.crash_times.size(), 10, "the Crasher presses every 1.7 s")
