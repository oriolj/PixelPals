extends GutTest
## The live synth, tested by computing buffers directly (no audio device).

const Synth := preload("res://scripts/music/band_synth.gd")


func _busy_synth() -> Synth:
	var syn := Synth.new()
	for m in [60, 64, 67, 72]:
		syn.schedule({"s": 0, "k": Synth.LEAD, "m": m, "d": 30000})
	syn.schedule({"s": 0, "k": Synth.BASS, "m": 36, "d": 30000})
	syn.schedule({"s": 0, "k": Synth.CHORD, "ms": [60, 64, 67], "d": 30000})
	for i in 8:
		syn.schedule({"s": i * 2756, "k": Synth.SHOT, "n": ["kick", "snare", "hat", "crash"][i % 4], "g": 1.0, "p": 0.3})
	return syn


func test_kit_loads_from_source_bytes() -> void:
	for n in Synth.KIT:
		var buf := Synth.read_wav_mono("res://audio/kit/%s.wav" % n)
		assert_gt(buf.size(), 1000, "%s.wav read from bytes" % n)


func test_synth_fill_has_no_nan_and_stays_under_full_scale() -> void:
	var syn := _busy_synth()
	# Pile on more: every crash sound at once, the loudest case a toddler can make.
	for n in ["crash", "gong", "cowbell", "whoosh", "kick", "tom"]:
		syn.schedule({"s": 5000, "k": Synth.SHOT, "n": n, "g": 1.0, "p": 0.0, "dk": 3000})
	var peak := 0.0
	var energy := 0.0
	for block in 20:
		var buf := syn.fill(1103)
		for f in buf:
			assert_false(is_nan(f.x) or is_nan(f.y), "no NaN")
			peak = maxf(peak, maxf(absf(f.x), absf(f.y)))
			energy += f.x * f.x
	assert_lt(peak, 1.0, "under full scale")
	assert_gt(energy, 100.0, "and it makes sound")


func test_synth_fill_one_second_under_budget() -> void:
	var syn := _busy_synth()
	syn.record = false
	syn.fill(1)
	assert_gte(syn.active_voices(), 8, "8 active voices")
	var t0 := Time.get_ticks_usec()
	var total := 0
	while total < Synth.RATE:
		total += syn.fill(2205).size()   # the 0.1 s blocks of the real game
	var ms := (Time.get_ticks_usec() - t0) / 1000.0
	gut.p("1 s of audio with %d voices took %.1f ms" % [syn.active_voices(), ms])
	assert_lt(ms, 150.0)


func test_events_fire_on_their_exact_sample() -> void:
	var syn := Synth.new()
	syn.schedule({"s": 1234, "k": Synth.SHOT, "n": "kick", "g": 1.0, "p": 0.0})
	var buf := syn.fill(2000)
	for i in 1234:
		assert_eq(buf[i], Vector2.ZERO)
	assert_ne(buf[1234 + 60], Vector2.ZERO, "sound starts at the scheduled sample")
	assert_eq(syn.recording.size(), 1)
	assert_eq(syn.recording[0].s, 1234)


func test_late_event_sounds_at_once() -> void:
	var syn := Synth.new()
	syn.fill(1000)
	syn.schedule({"s": 10, "k": Synth.SHOT, "n": "kick", "g": 1.0, "p": 0.0})
	assert_eq(int(syn.events[0].s), 1000)


func test_crash_ducks_the_backing() -> void:
	var a := Synth.new()
	var b := Synth.new()
	for syn in [a, b]:
		syn.schedule({"s": 0, "k": Synth.CHORD, "ms": [60, 64, 67], "d": 40000})
	b.schedule({"s": 0, "k": Synth.SHOT, "n": "sticks", "g": 0.0, "p": 0.0, "dk": 8000})
	var ea := 0.0
	var eb := 0.0
	var ba := a.fill(8000)
	var bb := b.fill(8000)
	for i in range(2000, 8000):
		ea += ba[i].x * ba[i].x
		eb += bb[i].x * bb[i].x
	var ratio_db := 10.0 * log(eb / ea) / log(10.0)
	assert_almost_eq(ratio_db, -3.0, 0.4, "backing ducked by 3 dB")
