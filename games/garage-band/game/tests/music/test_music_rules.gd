extends GutTest
## The music rules: scale, chord-tone nudge, quantisation, density caps.

const Rules := preload("res://scripts/music/music_rules.gd")
const Band := preload("res://scripts/music/band.gd")
const Songs := preload("res://scripts/music/songs.gd")


func test_every_lead_note_is_in_the_pentatonic_scale() -> void:
	for oct in Rules.OCTAVES:
		for lane in Rules.LANES:
			var idx := Rules.lead_note(lane, oct)
			assert_true(Rules.in_scale(Rules.lead_midi(idx)), "lane %d oct %d" % [lane, oct])
			# And whatever the chord and beat, the note that sounds stays in the scale.
			for chord in Rules.CHORDS:
				for e in 8:
					assert_true(Rules.in_scale(Rules.lead_midi(Rules.melody_note(idx, chord, e))))
	assert_eq(Rules.LEAD_NOTES[0], 60, "C4 is the lowest")
	assert_eq(Rules.LEAD_NOTES[9], 81, "A5 is the highest")


func test_strong_beat_nudges_to_a_chord_tone() -> void:
	for chord in Rules.CHORDS:
		for idx in Rules.LEAD_NOTES.size():
			for e in [0, 4]:
				var n := Rules.melody_note(idx, chord, e)
				assert_lte(absi(n - idx), 1, "at most one scale step")
				if Rules.is_chord_tone(Rules.lead_midi(idx), chord):
					assert_eq(n, idx, "a chord tone stays")
				elif n == idx:
					# Kept only when no neighbour within one step is a chord tone
					# (E over F: D and G are not in F, and E is still in the scale).
					for nb in [idx - 1, idx + 1]:
						if nb >= 0 and nb < Rules.LEAD_NOTES.size():
							assert_false(Rules.is_chord_tone(Rules.lead_midi(nb), chord))
				else:
					assert_true(Rules.is_chord_tone(Rules.lead_midi(n), chord), "moved onto a chord tone")
	# Worked examples: E over G becomes D; C over G becomes D; A over G becomes G.
	assert_eq(Rules.nudge_to_chord(2, "G"), 1)
	assert_eq(Rules.nudge_to_chord(0, "G"), 1)
	assert_eq(Rules.nudge_to_chord(4, "G"), 3)
	assert_eq(Rules.nudge_to_chord(1, "C"), 0, "D over C: C and E are equally close, the lower wins")


func test_offbeat_keeps_the_chosen_note() -> void:
	for chord in Rules.CHORDS:
		for idx in Rules.LEAD_NOTES.size():
			for e in [1, 2, 3, 5, 6, 7]:
				assert_eq(Rules.melody_note(idx, chord, e), idx)


func test_early_press_sounds_now() -> void:
	var step := 1000.0
	for into in [0, 100, 349, 350]:
		var q := Rules.quantise(5000 + into, step)
		assert_eq(q[0], 5000 + into, "press %d into the step sounds at once" % into)
		assert_eq(q[1], 5)


func test_late_press_waits_for_next_step() -> void:
	var step := 1000.0
	for into in [351, 600, 999]:
		var q := Rules.quantise(5000 + into, step)
		assert_eq(q[0], 6000)
		assert_eq(q[1], 6)
	# The worst waits at 96 BPM: eighth notes about 110 ms at most... for drums
	# the sixteenth grid gives at most 55 ms late on an early press.
	var spb := Rules.samples_per_beat(96.0)
	var sixteenth := spb / 4.0
	assert_lt(Rules.EARLY_WINDOW * sixteenth / Rules.RATE, 0.056)
	assert_lt((1.0 - Rules.EARLY_WINDOW) * sixteenth / Rules.RATE, 0.11)


func test_drum_quantises_to_sixteenths() -> void:
	var band := Band.new(0, true, true)
	var six := band.spb / 4.0
	# A press 40 % into sixteenth 10 lands on the start of sixteenth 11.
	var r := band.drum(band.origin + int(10.4 * six), Songs.PAD_SNARE)
	assert_true(r.sounded)
	assert_eq(r.sample, band.sample_at_sixteenth(11))
	# An early one sounds when pressed.
	var p := band.origin + int(20.1 * six)
	r = band.drum(p, Songs.PAD_KICK)
	assert_eq(r.sample, p)
	assert_eq(r.step, 20)


func test_crash_quantises_to_beats() -> void:
	var band := Band.new(0, true, true)
	var r := band.crash(band.origin + int(band.spb * 6.5))
	assert_eq(r.sample, band.sample_at_beat(7))
	assert_eq(r.step, 7)
	var p := band.origin + int(band.spb * 9.2)
	r = band.crash(p)
	assert_eq(r.sample, p)
	# The crashes cycle through the four sounds.
	for k in 4:
		band.crash(band.origin + int(band.spb * (12 + k * 2)))
	var sounds := []
	for c in band.crash_times:
		sounds.append(c[1])
	assert_eq(sounds.slice(0, 4), [0, 1, 2, 3])


func test_one_hit_per_drum_per_step() -> void:
	var band := Band.new(0, true, true)
	var six := band.spb / 4.0
	var base := band.origin + int(8 * six)
	assert_true(band.drum(base, Songs.PAD_SNARE).sounded)
	assert_false(band.drum(base + 10, Songs.PAD_SNARE).sounded, "same drum, same sixteenth")
	assert_true(band.drum(base + 10, Songs.PAD_KICK).sounded, "another drum may share the step")
	assert_true(band.drum(base + int(six), Songs.PAD_SNARE).sounded, "next sixteenth is fine")
	# One melody note per eighth, one crash per beat.
	var e := band.origin + int(band.spb * 3)
	assert_true(band.strum(e, 0, 0).sounded)
	assert_false(band.strum(e + 5, 3, 0).sounded)
	assert_true(band.crash(e).sounded)
	assert_false(band.crash(e + 50).sounded)


func test_song_gems_on_strong_beats_are_chord_tones() -> void:
	for i in Songs.count():
		var s := Songs.get_song(i)
		assert_eq(s.chords.size(), 40)
		for g in s.lead:
			var e: int = g.step % 8
			if Rules.is_strong_eighth(e):
				var chord: String = s.chords[g.step / 8]
				assert_true(Rules.is_chord_tone(Rules.lead_midi(g.note), chord),
					"%s bar %d: note %d on %s" % [s.id, g.step / 8, g.note, chord])
		# The Drummer gets at most one suggestion per beat.
		var beats := {}
		for g in s.drums:
			var b: int = g.step / 4
			assert_false(beats.has(b), "%s: two drum gems in beat %d" % [s.id, b])
			beats[b] = true
