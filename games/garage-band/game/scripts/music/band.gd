extends RefCounted
## The band conductor: turns seat presses into quantised synth events, plays
## the backing (bass, chords, auto-drummer, auto-crash), tracks the gems and
## keeps the log the party screen replays.
##
## Everything takes `now`, the song clock in samples (what the players hear
## and see). The play screen advances `now` from game time and asks the
## synth to render up to now + LEAD, so the audio never depends on the
## device's hunger (deterministic under --write-movie --fixed-fps).
##
## Sample 0 is the start of the count-in; bar 0 beat 1 is `origin`.

const Rules := preload("res://scripts/music/music_rules.gd")
const Songs := preload("res://scripts/music/songs.gd")
const Synth := preload("res://scripts/music/band_synth.gd")

const RATE := 22050
const COUNT_IN_BEATS := 4
## How far ahead the backing is scheduled (seconds).
const HORIZON := 0.3
const CRASH_SOUNDS: Array[String] = ["crash", "gong", "cowbell", "whoosh"]
const CRASH_GAIN: Array[float] = [0.6, 0.7, 0.5, 0.65]
const DRUM_GAIN: Array[float] = [0.42, 0.75, 0.8, 0.95]   # hat snare tom kick
const DRUM_PAN: Array[float] = [0.35, -0.1, -0.35, 0.0]
const AUTO_DRUM := 0.5     # the auto-drummer plays softer than a live one
const AUTO_CRASH := 0.55
const FINAL_BARS := 2      # the big shared chord rings this long

var synth: Synth
var song: Dictionary
var bpm := 96.0
var spb := 0.0          # samples per beat
var bar_len := 0.0
var origin := 0
var end_sample := 0     # where the final chord lands
var done_sample := 0    # when the song is over (go to party)
var bars := 40

var live_drummer := false
var live_crasher := false

var stars := 0
var crash_index := 0
## Gems: {step, sample, hit, ...}. Lead gems add lane/octave/note, drum gems pad.
var gems_lead: Array[Dictionary] = []
var gems_drum: Array[Dictionary] = []
var gems_crash: Array[Dictionary] = []
## Every gem hit, for the party screen: {s: sample, kind: "lead"|"drum"|"crash", i: lane/pad}.
var hits_log: Array[Dictionary] = []
## Visual cues read by the stage (sample of each event, in order).
var bass_times: Array[int] = []
var crash_times: Array[Array] = []   # [sample, sound index]
var drum_times: Array[Array] = []    # [sample, pad, live]

var _next16 := -COUNT_IN_BEATS * 4
var _used := {}
var _live_last := {}    # pad -> sample of the last live hit


func _init(song_index := 0, drummer := false, crasher := false, a_synth: Synth = null) -> void:
	synth = a_synth if a_synth else Synth.new()
	song = Songs.get_song(song_index)
	bpm = song.bpm
	bars = song.bars
	spb = Rules.samples_per_beat(bpm)
	bar_len = spb * 4.0
	origin = int(round(spb * COUNT_IN_BEATS))
	end_sample = sample_at_beat(bars * 4)
	done_sample = end_sample + int(bar_len * FINAL_BARS)
	live_drummer = drummer
	live_crasher = crasher
	for g in song.lead:
		var idx: int = g.note
		gems_lead.append({"step": g.step, "sample": sample_at_eighth(g.step), "note": idx,
			"lane": idx % Rules.LANES, "octave": idx / Rules.LANES, "hit": false})
	for g in song.drums:
		gems_drum.append({"step": g.step, "sample": sample_at_sixteenth(g.step), "pad": g.pad, "hit": false})
	for b in song.crashes:
		gems_crash.append({"step": b * 4, "sample": sample_at_beat(b * 4), "bar": b, "hit": false})


# ---------------------------------------------------------------- time

func sample_at_beat(beat: float) -> int:
	return origin + int(round(beat * spb))


func sample_at_eighth(step: int) -> int:
	return origin + int(round(step * spb / 2.0))


func sample_at_sixteenth(step: int) -> int:
	return origin + int(round(step * spb / 4.0))


## Beats since bar 0 beat 1 (negative during the count-in).
func beat_at(now: int) -> float:
	return (now - origin) / spb


func bar_at(now: int) -> int:
	return int(floor(beat_at(now) / 4.0))


func chord_at_bar(bar: int) -> String:
	if bar >= bars:
		return "C"
	return song.chords[clampi(bar, 0, bars - 1)]


func is_finished(now: int) -> bool:
	return now >= done_sample


## 0..1 through the song (for the progress track).
func progress(now: int) -> float:
	return clampf(float(now - origin) / float(end_sample - origin), 0.0, 1.0)


# ---------------------------------------------------------------- backing

## Schedules backing and auto parts up to now + HORIZON.
func update(now: int) -> void:
	var until := now + int(HORIZON * RATE)
	var last := bars * 16
	while _next16 <= last and sample_at_sixteenth(_next16) < until:
		_schedule_step(_next16)
		_next16 += 1


func _schedule_step(i: int) -> void:
	var s := sample_at_sixteenth(i)
	if i < 0:
		if posmod(i, 4) == 0:
			synth.schedule({"s": s, "k": Synth.SHOT, "n": "sticks", "g": 0.8, "p": 0.0})
		return
	var bar := i / 16
	var s16 := i % 16
	if bar >= bars:
		_final_chord(s)
		return
	var chord := chord_at_bar(bar)
	if s16 % 2 == 0:
		var e := s16 / 2
		for b in Songs.bass_bar(song.style):
			if int(b[0]) == e:
				var m: int = Rules.ROOTS[chord] if b[1] == "root" else Songs.FIFTHS[chord]
				synth.schedule({"s": s, "k": Synth.BASS, "m": m, "d": int(spb / 2.0 * int(b[2]) * 0.92)})
				bass_times.append(s)
		if Songs.chord_hits(song.style).has(e):
			var left := 8 - e
			synth.schedule({"s": s, "k": Synth.CHORD, "ms": Rules.CHORDS[chord].duplicate(),
				"d": int(spb / 2.0 * left * 0.95)})
	var groove := Songs.groove(song.style)
	for pad in groove:
		if (groove[pad] as Array).has(s16) and not is_replaced(pad, s):
			synth.schedule({"s": s, "k": Synth.SHOT, "n": Songs.PAD_NAMES[pad],
				"g": DRUM_GAIN[pad] * AUTO_DRUM, "p": DRUM_PAN[pad], "auto": true})
			drum_times.append([s, pad, false])
	if not live_crasher and bar % 8 == 0 and s16 == 0:
		_crash_at(s, AUTO_CRASH)


func _final_chord(s: int) -> void:
	var hold := int(bar_len * FINAL_BARS * 0.8)
	synth.schedule({"s": s, "k": Synth.CHORD, "ms": [48, 55, 60, 64, 67], "d": hold})
	synth.schedule({"s": s, "k": Synth.BASS, "m": 36, "d": hold})
	for m in [72, 76, 79]:
		synth.schedule({"s": s, "k": Synth.LEAD, "m": m, "d": hold})
	synth.schedule({"s": s, "k": Synth.SHOT, "n": "kick", "g": DRUM_GAIN[3], "p": 0.0})
	crash_index = 0
	_crash_at(s, 0.8)


## A live Drummer's hits replace the auto part of the same drum for a bar.
func is_replaced(pad: int, s: int) -> bool:
	return _live_last.has(pad) and s - int(_live_last[pad]) < int(bar_len)


func _crash_at(s: int, gain: float) -> void:
	var i := crash_index % CRASH_SOUNDS.size()
	crash_index += 1
	synth.schedule({"s": s, "k": Synth.SHOT, "n": CRASH_SOUNDS[i], "g": CRASH_GAIN[i] * gain,
		"p": 0.0, "dk": int(spb / 2.0)})
	crash_times.append([s, i])


# ---------------------------------------------------------------- live input

## The Lead strums lane/octave. `repeat` (A held) lands exactly on the next
## eighth. Returns {sounded, sample, note, gem}.
func strum(now: int, lane: int, octave: int, repeat := false) -> Dictionary:
	var step_len := spb / 2.0
	var q := Rules.quantise(now, step_len, origin)
	if repeat:
		var nxt := int(floor(float(now - origin) / step_len)) + 1
		q = [Rules.step_sample(nxt, step_len, origin), nxt]
	var step: int = q[1]
	var key := "l%d" % step
	if _used.has(key):
		return {"sounded": false}
	_used[key] = true
	var bar := int(floor(step / 8.0))
	var idx := Rules.lead_note(lane, octave)
	var note := Rules.melody_note(idx, chord_at_bar(bar), posmod(step, 8))
	synth.schedule({"s": q[0], "k": Synth.LEAD, "m": Rules.lead_midi(note), "d": int(step_len * 0.9)})
	var gem := _hit_gem(gems_lead, step, 1, func(g): return g.lane == lane)
	if gem:
		_log_hit(q[0], "lead", lane)
	return {"sounded": true, "sample": q[0], "note": note, "gem": gem, "step": step}


## The Drummer hits pad 0..3 (hat, snare, tom, kick).
func drum(now: int, pad: int) -> Dictionary:
	var q := Rules.quantise(now, spb / 4.0, origin)
	var step: int = q[1]
	var key := "d%d:%d" % [pad, step]
	if _used.has(key):
		return {"sounded": false}
	_used[key] = true
	_live_last[pad] = q[0]
	_cancel_auto(Songs.PAD_NAMES[pad], q[0] - int(spb / 8.0), q[0] + int(bar_len))
	synth.schedule({"s": q[0], "k": Synth.SHOT, "n": Songs.PAD_NAMES[pad], "g": DRUM_GAIN[pad], "p": DRUM_PAN[pad]})
	drum_times.append([q[0], pad, true])
	var gem := _hit_gem(gems_drum, step, 2, func(g): return g.pad == pad)
	if gem:
		_log_hit(q[0], "drum", pad)
	return {"sounded": true, "sample": q[0], "gem": gem, "step": step}


## The Crasher (or the Lead's B with one seat): crash, gong, cowbell, whoosh.
func crash(now: int) -> Dictionary:
	var q := Rules.quantise(now, spb, origin)
	var step: int = q[1]
	var key := "c%d" % step
	if _used.has(key):
		return {"sounded": false}
	_used[key] = true
	var sound := crash_index % CRASH_SOUNDS.size()
	_crash_at(q[0], 1.0)
	var gem := false
	for g in gems_crash:
		if not g.hit and step >= int(g.step) - 1 and step <= int(g.step) + 2:
			g.hit = true
			gem = true
			stars += 1
			break
	if gem:
		_log_hit(q[0], "crash", sound)
	return {"sounded": true, "sample": q[0], "gem": gem, "step": step, "sound": sound}


## Removes the auto-drummer's pending hits of one drum in [from, to).
func _cancel_auto(drum_name: String, from: int, to: int) -> void:
	for j in range(synth.events.size() - 1, -1, -1):
		var ev: Dictionary = synth.events[j]
		if ev.get("auto", false) and ev.n == drum_name and int(ev.s) >= from and int(ev.s) < to:
			synth.events.remove_at(j)


func _hit_gem(gems: Array[Dictionary], step: int, tolerance: int, matches: Callable) -> bool:
	for g in gems:
		if g.hit or absi(int(g.step) - step) > tolerance:
			continue
		if matches.call(g):
			g.hit = true
			stars += 1
			return true
	return false


func _log_hit(s: int, kind: String, i: int) -> void:
	hits_log.append({"s": s, "kind": kind, "i": i})


# ---------------------------------------------------------------- visuals

## Seconds since the last cue at or before now (big if none), from a sorted list.
static func since_last(times: Array, now: int, rate := RATE) -> float:
	for j in range(times.size() - 1, -1, -1):
		var t: int = times[j] if times[j] is int else int(times[j][0])
		if t <= now:
			return float(now - t) / rate
	return 99.0


## The sound index of the last crash at or before now (-1 before any).
func last_crash_sound(now: int) -> int:
	for j in range(crash_times.size() - 1, -1, -1):
		if int(crash_times[j][0]) <= now:
			return int(crash_times[j][1])
	return -1


func crash_count_until(now: int) -> int:
	var n := 0
	for c in crash_times:
		if int(c[0]) <= now:
			n += 1
	return n
