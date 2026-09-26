extends GutTest
## The band conductor: backing, auto parts, gems, recording, the song's end.

const Band := preload("res://scripts/music/band.gd")
const Synth := preload("res://scripts/music/band_synth.gd")
const Songs := preload("res://scripts/music/songs.gd")

const FRAME := 735   # 1/30 s at 22050 Hz


## Runs the band to `until` (samples) like the play screen does, calling
## `each(now)` every frame for input.
func _run(band: Band, until: int, each := Callable()) -> PackedVector2Array:
	var out := PackedVector2Array()
	var now := 0
	while now < until:
		now += FRAME
		if each.is_valid():
			each.call(now)
		band.update(now)
		out.append_array(band.synth.fill(now + 1300 - band.synth.clock))
	return out


func _shots(band: Band, name: String, from: int, to: int) -> Array:
	var out := []
	for ev in band.synth.recording:
		if int(ev.k) == Synth.SHOT and ev.n == name and int(ev.s) >= from and int(ev.s) < to:
			out.append(ev)
	return out


func test_count_in_is_four_stick_clicks() -> void:
	var band := Band.new(0, false, false)
	_run(band, band.origin + 100)
	assert_eq(_shots(band, "sticks", 0, band.origin).size(), 4)


func test_one_seat_gets_auto_drummer() -> void:
	var band := Band.new(0, false, false)
	var bar := int(band.bar_len)
	_run(band, band.origin + bar * 2 + 2000)
	var o := band.origin
	assert_gte(_shots(band, "kick", o, o + bar).size(), 2, "auto kicks in bar 1")
	assert_eq(_shots(band, "snare", o, o + bar).size(), 2, "auto snares on 2 and 4")
	assert_eq(_shots(band, "hat", o, o + bar).size(), 8, "auto hats on the eighths")
	assert_eq(_shots(band, "crash", o, o + 10).size(), 1, "auto crash on bar 1 without a Crasher")
	var backing := 0
	for ev in band.synth.recording:
		if int(ev.k) == Synth.BASS or int(ev.k) == Synth.CHORD:
			backing += 1
	assert_gt(backing, 4, "bass and chords play")


func test_live_drummer_replaces_auto_parts() -> void:
	var band := Band.new(0, true, true)
	var bar := int(band.bar_len)
	var o := band.origin
	# The Drummer plays kicks on every beat of bars 1 and 2 (0-based) only.
	var beats := []
	for b in 8:
		beats.append(o + bar + int(band.spb * b) + 20)
	var hit := func(now: int) -> void:
		for t in beats:
			if now >= t and now - FRAME < t:
				band.drum(now, Songs.PAD_KICK)
	_run(band, o + bar * 5, hit)
	# The very first live hit may meet an auto kick already sounding; from
	# then on only the live kicks play (they replace, they do not stack).
	var kicks := _shots(band, "kick", o + bar + 2000, o + bar * 3)
	assert_eq(kicks.size(), 7, "only the live kicks while the Drummer plays")
	for ev in kicks:
		assert_eq(ev.g, Band.DRUM_GAIN[Songs.PAD_KICK], "live gain, not the soft auto one")
	assert_eq(_shots(band, "hat", o + bar, o + bar * 3).size(), 16, "the other parts keep playing")
	assert_gte(_shots(band, "kick", o + bar * 4, o + bar * 5).size(), 2, "auto kicks come back after a bar")


func test_two_seats_auto_crash_every_eighth_bar() -> void:
	var band := Band.new(0, true, false)
	_run(band, band.origin + int(band.bar_len * 17))
	var crashes := []
	for c in band.crash_times:
		crashes.append(band.bar_at(int(c[0])))
	assert_eq(crashes, [0, 8, 16])
	var band3 := Band.new(0, true, true)
	_run(band3, band3.origin + int(band3.bar_len * 9))
	assert_eq(band3.crash_times.size(), 0, "a live Crasher owns the crashes")


func test_recording_replays_the_same_events() -> void:
	var band := Band.new(1, true, true)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var press := func(now: int) -> void:
		if rng.randf() < 0.3:
			band.strum(now, rng.randi() % 5, rng.randi() % 2)
		if rng.randf() < 0.3:
			band.drum(now, rng.randi() % 4)
		if rng.randf() < 0.05:
			band.crash(now)
	var heard := _run(band, band.origin + int(band.bar_len * 3), press)
	var rec := band.synth.recording.duplicate(true)
	assert_gt(rec.size(), 30)
	var replay := Synth.new()
	replay.load_recording(rec)
	var again := replay.fill(heard.size())
	assert_eq(replay.recording.size(), rec.size(), "the same events fire")
	var same := true
	for i in heard.size():
		if not heard[i].is_equal_approx(again[i]):
			same = false
			break
	assert_true(same, "the replay renders exactly what was heard")


func test_song_always_reaches_the_end() -> void:
	# Nobody plays: the song still runs to its final chord and finishes.
	for i in Songs.count():
		var band := Band.new(i, false, false)
		var now := 0
		var guard := 0
		while not band.is_finished(now) and guard < 100000:
			now += 22050
			band.update(now)
			guard += 1
		assert_true(band.is_finished(now), "%s finishes" % band.song.id)
		var secs := band.end_sample / 22050.0
		assert_between(secs, 60.0, 130.0, "%s lasts about 1-2 minutes" % band.song.id)
	# Mashing every button never stops it early nor extends it.
	var band := Band.new(0, true, true)
	var now := 0
	while now < band.done_sample - 1:
		now += FRAME
		band.strum(now, 2, 1)
		band.drum(now, now % 4)
		band.crash(now)
		band.update(now)
		assert_false(band.is_finished(now) and now < band.done_sample)
	assert_true(band.is_finished(band.done_sample))


func test_following_the_gems_lights_stars() -> void:
	var band := Band.new(0, true, true)
	var start_stars := band.stars
	for g in band.gems_lead.slice(0, 8):
		var r := band.strum(int(g.sample) + 30, int(g.lane), int(g.octave))
		assert_true(r.gem, "gem at step %d" % g.step)
	for g in band.gems_drum.slice(0, 8):
		assert_true(band.drum(int(g.sample) + 30, int(g.pad)).gem)
	assert_true(band.crash(int(band.gems_crash[1].sample)).gem)
	assert_eq(band.stars - start_stars, 17)
	assert_eq(band.hits_log.size(), 17)
	# A wrong pad still sounds, just no star, and never loses one.
	var before := band.stars
	var r := band.drum(int(band.gems_drum[20].sample), (int(band.gems_drum[20].pad) + 1) % 4)
	assert_true(r.sounded)
	assert_eq(band.stars, before)
