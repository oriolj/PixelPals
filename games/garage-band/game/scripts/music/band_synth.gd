extends RefCounted
## The live band synth and the musical clock.
##
## `clock` is the next sample to render: the song position, in samples at
## RATE. Nothing here reads wall time or an audio device; `fill(n)` renders
## the next n frames and advances the clock, so it is testable headless and
## deterministic under --write-movie --fixed-fps.
##
## Scheduler: `schedule(ev)` inserts an event dictionary into a list sorted by
## its sample `s`; `fill` splits its block at every event and fires it
## exactly on its sample. Every fired event is appended to `recording`, so
## replaying the recording through a fresh synth gives the same audio.
##
## Event kinds (`k`):
##   LEAD  {m: midi, d: hold samples}          pulse wave, ADSR, vibrato (4 voices)
##   BASS  {m, d}                              triangle
##   CHORD {ms: [midi...], d}                  two detuned saws per note, low-passed
##   SHOT  {n: name, g: gain, p: pan, dk: duck samples (0 = none)}
##         a pre-rendered one-shot (drums, crashes, sticks) mixed in at `s`

const RATE := 22050
const CHUNK := 32
const LEAD_VOICES := 4
const DUCK_GAIN := 0.708          # -3 dB
const MASTER := 0.8
const KIT_DIR := "res://audio/kit"
const KIT := ["kick", "snare", "hat", "tom", "crash", "gong", "cowbell", "whoosh", "sticks"]

enum { LEAD, BASS, CHORD, SHOT }

var clock := 0
var events: Array[Dictionary] = []
var voices: Array = []   # Tone
var shots: Array = []    # Shot
var recording: Array[Dictionary] = []
var record := true
## Optional: every rendered frame's left channel is appended here when set
## (tools/render_demo.gd writes it to a WAV).
var capture: PackedFloat32Array
var capturing := false

var _duck_until := -1
var _duck_start := 0
var _m := PackedFloat32Array()
var _l := PackedFloat32Array()
var _r := PackedFloat32Array()

static var _kit_cache := {}


func _init() -> void:
	load_kit()


# ---------------------------------------------------------------- kit

## Loads the one-shots from res://audio/kit/<name>.wav (16-bit mono at RATE)
## by their bytes, not through the import cache. A missing file gets a tiny
## procedural stand-in so the band always makes sound.
static func load_kit() -> void:
	if not _kit_cache.is_empty():
		return
	for n in KIT:
		var buf := read_wav_mono("%s/%s.wav" % [KIT_DIR, n])
		if buf.is_empty():
			buf = _fallback_shot(n)
		_kit_cache[n] = buf


static func kit(n: String) -> PackedFloat32Array:
	load_kit()
	return _kit_cache.get(n, PackedFloat32Array())


## Parses a PCM16 WAV file (any channel count; the first channel is kept).
static func read_wav_mono(path: String) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	if not FileAccess.file_exists(path):
		return out
	var b := FileAccess.get_file_as_bytes(path)
	if b.size() < 44 or b.slice(0, 4).get_string_from_ascii() != "RIFF":
		return out
	var pos := 12
	var channels := 1
	var bits := 16
	while pos + 8 <= b.size():
		var id := b.slice(pos, pos + 4).get_string_from_ascii()
		var size := b.decode_u32(pos + 4)
		if id == "fmt ":
			channels = b.decode_u16(pos + 10)
			bits = b.decode_u16(pos + 22)
		elif id == "data":
			if bits != 16:
				return out
			var frames := size / (2 * channels)
			out.resize(frames)
			var p := pos + 8
			var stride := 2 * channels
			for i in frames:
				out[i] = b.decode_s16(p) / 32768.0
				p += stride
			return out
		pos += 8 + size + (size & 1)
	return out


static func _fallback_shot(n: String) -> PackedFloat32Array:
	var len := int(RATE * (0.6 if n in ["crash", "gong", "whoosh"] else 0.2))
	var out := PackedFloat32Array()
	out.resize(len)
	var rng := RandomNumberGenerator.new()
	rng.seed = n.hash()
	var ph := 0.0
	for i in len:
		var e := exp(-float(i) / (RATE * 0.06))
		if n in ["kick", "tom", "gong", "cowbell"]:
			ph += (55.0 if n == "kick" else 160.0) * (1.0 + 2.0 * e) / RATE
			out[i] = sin(TAU * ph) * e * 0.8
		else:
			out[i] = rng.randf_range(-1.0, 1.0) * e * 0.5
	return out


# ---------------------------------------------------------------- scheduling

func schedule(ev: Dictionary) -> void:
	if int(ev.s) < clock:
		ev.s = clock  # late: sounds as soon as possible
	var i := events.bsearch_custom(ev, _before, false)
	events.insert(i, ev)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	return int(a.s) < int(b.s)


## Replay: queue a recording (as returned by `recording`) from sample 0.
func load_recording(rec: Array) -> void:
	for ev in rec:
		schedule(ev.duplicate(true))


func reset() -> void:
	clock = 0
	events.clear()
	voices.clear()
	shots.clear()
	recording.clear()
	_duck_until = -1
	_duck_start = 0


func active_voices() -> int:
	return voices.size() + shots.size()


# ---------------------------------------------------------------- rendering

## Renders the next n frames (stereo) and advances the clock.
func fill(n: int) -> PackedVector2Array:
	_m.resize(n)
	_m.fill(0.0)
	_l.resize(n)
	_l.fill(0.0)
	_r.resize(n)
	_r.fill(0.0)
	var end := clock + n
	var at := 0
	while not events.is_empty() and int(events[0].s) < end:
		var ev: Dictionary = events.pop_front()
		var es := maxi(int(ev.s), clock + at)
		if es > clock + at:
			_render(at, es - clock - at)
			at = es - clock
		_fire(ev, es)
	if at < n:
		_render(at, n - at)
	_purge()
	clock = end
	var out := PackedVector2Array()
	out.resize(n)
	for i in n:
		var a := _limit((_m[i] + _l[i]) * MASTER)
		var b := _limit((_m[i] + _r[i]) * MASTER)
		out[i] = Vector2(a, b)
	if capturing:
		for i in n:
			capture.append(out[i].x)
	return out


static func _limit(x: float) -> float:
	var ax := absf(x)
	if ax <= 0.8:
		return x
	return signf(x) * (0.8 + 0.18 * tanh((ax - 0.8) / 0.18))


func _fire(ev: Dictionary, at_sample: int) -> void:
	_purge()
	if record:
		var copy := ev.duplicate(true)
		copy.s = at_sample
		recording.append(copy)
	match int(ev.k):
		LEAD:
			var lead_count := 0
			for v in voices:
				if v.kind == Tone.PULSE:
					lead_count += 1
			if lead_count >= LEAD_VOICES:
				for i in voices.size():
					if voices[i].kind == Tone.PULSE:
						voices.remove_at(i)
						break
			voices.append(Tone.lead(int(ev.m), int(ev.d)))
		BASS:
			for v in voices:
				if v.kind == Tone.TRI:
					v.release_now()
			voices.append(Tone.bass(int(ev.m), int(ev.d)))
		CHORD:
			for v in voices:
				if v.kind == Tone.SAWS:
					v.release_now()
			for m in ev.ms:
				voices.append(Tone.chord(int(m), int(ev.d)))
		SHOT:
			var buf := kit(str(ev.n))
			if buf.is_empty():
				return
			var s := Shot.new()
			s.buf = buf
			s.name = str(ev.n)
			var g := float(ev.get("g", 1.0))
			var p := clampf(float(ev.get("p", 0.0)), -1.0, 1.0)
			s.gl = g * sqrt(0.5 * (1.0 - p))
			s.gr = g * sqrt(0.5 * (1.0 + p))
			# A new hit of the same drum chokes the old one (a real kit does).
			for o in shots:
				if o.name == s.name:
					o.choke()
			shots.append(s)
			var dk := int(ev.get("dk", 0))
			if dk > 0:
				if at_sample > _duck_until:
					_duck_start = at_sample
				_duck_until = maxi(_duck_until, at_sample + dk)


## Renders n frames at offset off. Tonal voices are split on a 32-sample
## grid (absolute for the duck, per voice age for the envelopes), so the
## output does not depend on how the frames were cut into fill() calls:
## a replay renders bit-for-bit what was heard.
func _render(off: int, n: int) -> void:
	if n <= 0:
		return
	var i := 0
	while i < n:
		var here := clock + off + i
		var k := mini(CHUNK - posmod(here, CHUNK), n - i)
		var g := _duck_at(here - posmod(here, CHUNK))
		for v in voices:
			v.render(_m, off + i, k, g if v.backing else 1.0)
		i += k
	for s in shots:
		s.render(_l, _r, off, n)


func _purge() -> void:
	for j in range(voices.size() - 1, -1, -1):
		if voices[j].done:
			voices.remove_at(j)
	for j in range(shots.size() - 1, -1, -1):
		if shots[j].done:
			shots.remove_at(j)


## Backing gain at sample s: -3 dB while a crash ducks, with short ramps.
func _duck_at(s: int) -> float:
	if _duck_until < 0:
		return 1.0
	var w_in := clampf(float(s - _duck_start) / 256.0, 0.0, 1.0)
	var w_out := clampf(float(_duck_until - s) / 512.0, 0.0, 1.0)
	return 1.0 - (1.0 - DUCK_GAIN) * minf(w_in, w_out)


# ---------------------------------------------------------------- voices

class Tone:
	enum { PULSE, TRI, SAWS }
	var kind := PULSE
	var inc := 0.0
	var inc2 := 0.0
	var ph := 0.0
	var ph2 := 0.37
	var gain := 0.2
	var age := 0
	var hold := 0
	var att := 1
	var dec := 1
	var sus := 0.7
	var rel := 1
	var lp := 1.0
	var y := 0.0
	var vib := 0.0
	var duty := 0.5
	var backing := false
	var done := false

	static func _hz(midi: int) -> float:
		return 440.0 * pow(2.0, (midi - 69) / 12.0)

	static func lead(midi: int, hold_samples: int) -> Tone:
		var t := Tone.new()
		t.kind = PULSE
		t.inc = _hz(midi) / RATE
		t.gain = 0.17
		t.hold = maxi(hold_samples, int(RATE * 0.06))
		t.att = int(RATE * 0.008)
		t.dec = int(RATE * 0.12)
		t.sus = 0.55
		t.rel = int(RATE * 0.2)
		t.lp = 0.45
		t.vib = 0.005
		t.duty = 0.3
		return t

	static func bass(midi: int, hold_samples: int) -> Tone:
		var t := Tone.new()
		t.kind = TRI
		t.inc = _hz(midi) / RATE
		t.gain = 0.3
		t.hold = hold_samples
		t.att = int(RATE * 0.004)
		t.dec = int(RATE * 0.1)
		t.sus = 0.75
		t.rel = int(RATE * 0.06)
		t.backing = true
		return t

	static func chord(midi: int, hold_samples: int) -> Tone:
		var t := Tone.new()
		t.kind = SAWS
		t.inc = _hz(midi) * 1.004 / RATE
		t.inc2 = _hz(midi) * 0.996 / RATE
		t.gain = 0.075
		t.hold = hold_samples
		t.att = int(RATE * 0.06)
		t.dec = int(RATE * 0.35)
		t.sus = 0.6
		t.rel = int(RATE * 0.3)
		t.lp = 0.14
		t.backing = true
		return t

	func release_now() -> void:
		if age < hold:
			hold = age

	func _pre(a: int) -> float:
		if a < att:
			return float(a) / att
		var x := a - att
		if x < dec:
			return 1.0 - (1.0 - sus) * float(x) / dec
		return sus

	func env(a: int) -> float:
		if a >= hold:
			var r := float(a - hold) / rel
			if r >= 1.0:
				return 0.0
			return _pre(hold) * (1.0 - r)
		return _pre(a)

	func render(buf: PackedFloat32Array, off: int, n: int, gmul: float) -> void:
		var j0 := 0
		while j0 < n:
			var node := age - age % CHUNK
			var k := mini(n - j0, node + CHUNK - age)
			var en0 := env(node) * gain
			var en1 := env(node + CHUNK) * gain
			var e := (en0 + (en1 - en0) * float(age - node) / CHUNK) * gmul
			var de := (en1 - en0) / CHUNK * gmul
			var f := inc
			if vib > 0.0 and node > 2600:
				f = inc * (1.0 + vib * sin(TAU * 5.5 * node / RATE))
			var o := off + j0
			match kind:
				PULSE:
					var dc := 2.0 * duty - 1.0   # a pulse's mean; removed so there is no DC offset
					for j in k:
						ph += f
						if ph >= 1.0:
							ph -= 1.0
						var x := (1.0 if ph < duty else -1.0) - dc
						y += lp * (x - y)
						buf[o + j] += y * e
						e += de
				TRI:
					for j in k:
						ph += f
						if ph >= 1.0:
							ph -= 1.0
						buf[o + j] += (4.0 * absf(ph - 0.5) - 1.0) * e
						e += de
				SAWS:
					var f2 := inc2
					for j in k:
						ph += f
						if ph >= 1.0:
							ph -= 1.0
						ph2 += f2
						if ph2 >= 1.0:
							ph2 -= 1.0
						y += lp * (ph + ph2 - 1.0 - y)
						buf[o + j] += y * e
						e += de
			age += k
			j0 += k
		if age >= hold + rel:
			done = true


class Shot:
	var buf: PackedFloat32Array
	var name := ""
	var pos := 0
	var gl := 0.7
	var gr := 0.7
	var fade := -1   # samples left of a choke fade, -1 = none
	var done := false

	func choke() -> void:
		if fade < 0:
			fade = 220

	func render(l: PackedFloat32Array, r: PackedFloat32Array, off: int, n: int) -> void:
		var k := mini(n, buf.size() - pos)
		if fade >= 0:
			k = mini(k, fade)
		for j in k:
			var v := buf[pos + j]
			if fade >= 0:
				v *= float(fade - j) / 220.0
			l[off + j] += v * gl
			r[off + j] += v * gr
		pos += k
		if fade >= 0:
			fade -= k
			if fade <= 0:
				done = true
		if pos >= buf.size():
			done = true
