extends GutTest
## The play screen: seat input to band events, fold-down for 1-2 seats,
## pause, the toddler seat's safety and the trip to the party.

const PlayScreen := preload("res://scripts/screens/play.gd")
const Songs := preload("res://scripts/music/songs.gd")
const Synth := preload("res://scripts/music/band_synth.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Sfx.muted = true
	Players.reset()
	Players.clear_scripted()
	Game.song_index = 0


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Sfx.muted = false


func _seat(n: int) -> void:
	for i in n:
		var d := "demo:%d" % i
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()


func _open() -> void:
	screen = PlayScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	screen.step(DT)


func _press(d: String, state: Dictionary) -> void:
	_step({d: state})
	_step({d: {}})


func _shots(name: String) -> int:
	var n := 0
	for ev in screen.band.synth.recording:
		if int(ev.k) == Synth.SHOT and ev.n == name:
			n += 1
	return n


func test_one_seat_folds_down() -> void:
	_seat(1)
	_open()
	assert_false(screen.live_drummer)
	assert_false(screen.live_crasher)
	assert_true(screen.pads.ghost, "the pads show the auto-drummer")
	for i in 90:
		_step()
	assert_gt(_shots("kick"), 0, "the auto-drummer plays")
	# The Lead's B is the crash when nobody sits in the Crasher seat.
	var before: int = screen.band.crash_times.size()
	_press("demo:0", {"b": true})
	for i in 30:
		_step()
	assert_gt(screen.band.crash_times.size(), before)


func test_lead_steps_lanes_octaves_and_strums() -> void:
	_seat(1)
	_open()
	assert_eq(screen.lead_lane, 2)
	_press("demo:0", {"move": Vector2.UP})
	assert_eq(screen.lead_lane, 3)
	_press("demo:0", {"move": Vector2.DOWN})
	_press("demo:0", {"move": Vector2.DOWN})
	assert_eq(screen.lead_lane, 1)
	_press("demo:0", {"move": Vector2.RIGHT})
	assert_eq(screen.lead_octave, 1)
	for i in 5:
		_press("demo:0", {"move": Vector2.UP})
	assert_eq(screen.lead_lane, 4, "clamped at the top lane")
	_press("demo:0", {"a": true})
	assert_eq(screen.highway.lane_flash[4], 1.0 - 0.0, "the lane lights the same frame")
	var leads := 0
	for i in 20:
		_step()
	for ev in screen.band.synth.recording:
		if int(ev.k) == Synth.LEAD:
			leads += 1
	assert_eq(leads, 1)


func test_holding_a_repeats_on_eighths() -> void:
	_seat(1)
	_open()
	var eighth: float = screen.band.spb / 2.0 / 22050.0
	var frames := int(eighth * 8 / DT)
	_step({"demo:0": {"a": true}})
	for i in frames:
		_step({"demo:0": {"a": true}})
	var leads := 0
	for ev in screen.band.synth.events + screen.band.synth.recording:
		if int(ev.k) == Synth.LEAD:
			leads += 1
	assert_between(leads, 8, 10, "one note per eighth while held")


func test_drummer_pads_and_kick() -> void:
	_seat(2)
	_open()
	assert_true(screen.live_drummer)
	_press("demo:1", {"move": Vector2.LEFT})
	assert_eq(screen.pads.bounce[Songs.PAD_SNARE], 1.0, "the pad answers the same frame")
	_press("demo:1", {"move": Vector2.UP})
	_press("demo:1", {"a": true})
	for i in 10:
		_step()
	var live := {}
	for d in screen.band.drum_times:
		if d[2]:
			live[int(d[1])] = true
	assert_true(live.has(Songs.PAD_SNARE))
	assert_true(live.has(Songs.PAD_HAT))
	assert_true(live.has(Songs.PAD_KICK))


func test_toddler_mashing_never_hurts_the_run() -> void:
	_seat(3)
	_open()
	for i in 200:
		var down := i % 2 == 0
		var st := {"a": down, "b": down and i % 3 == 0, "start": down and i % 5 == 0, "any": down}
		_step({"demo:2": st})
		assert_false(screen.paused, "the Crasher cannot pause")
		assert_false(screen.finished, "nor stop the song")
	assert_gt(screen.band.crash_times.size(), 3, "every press can crash (once per beat)")
	assert_almost_eq(screen.now, int(200 * DT * 22050), 2, "the song clock kept going")


func test_pause_freezes_the_clock_and_b_stops() -> void:
	_seat(2)
	_open()
	for i in 10:
		_step()
	var t: int = screen.now
	_press("demo:0", {"start": true})
	assert_true(screen.paused)
	for i in 10:
		_step()
	assert_eq(screen.now, t, "paused: no time passes")
	_press("demo:0", {"a": true})
	assert_false(screen.paused)
	_press("demo:0", {"start": true})
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "select")


func test_song_ends_at_the_party_with_the_recording() -> void:
	_seat(3)
	Game.song_index = 1   # the fast one: 40 bars at 120 BPM
	_open()
	var guard := 0
	while not screen.finished and guard < 4000:
		_step()
		guard += 1
	assert_eq(screen.next_screen, "party")
	assert_gt(Game.recording.size(), 400)
	assert_eq(Game.song_samples, screen.band.done_sample)
