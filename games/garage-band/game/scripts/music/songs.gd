extends RefCounted
## The three songs: chords, the Lead's melody gems, the Drummer's pad gems,
## the Crasher's suggested bars, and the backing style. All in C major
## pentatonic; every gem on a strong beat is a chord tone, so a Lead who
## follows the gems hears exactly the gem notes.
##
## Timing units: lead gems in eighths from the song start, drum gems in
## sixteenths, crashes in bars. Pads: 0 hat (up), 1 snare (left), 2 tom
## (right), 3 kick (down).

const BARS := 40
const PAD_HAT := 0
const PAD_SNARE := 1
const PAD_TOM := 2
const PAD_KICK := 3
const PAD_NAMES: Array[String] = ["hat", "snare", "tom", "kick"]

const IDS: Array[String] = ["sun", "rocket", "cat"]


static func count() -> int:
	return IDS.size()


static func get_song(i: int) -> Dictionary:
	match IDS[posmod(i, IDS.size())]:
		"rocket":
			return _rocket()
		"cat":
			return _cat()
	return _sun()


## The main song: I-vi-IV-V at 96 BPM, bouncy.
static func _sun() -> Dictionary:
	var a := [[2, -1, 3, -1, 2, -1, 0, -1], [4, -1, 5, -1, 4, -1, 2, -1],
		[5, -1, 4, -1, 5, -1, -1, -1], [3, -1, 1, -1, 3, -1, -1, -1]]
	var b := [[7, -1, 8, -1, 7, -1, 5, -1], [9, -1, 7, -1, 5, -1, 4, -1],
		[5, -1, 5, -1, 4, -1, 5, -1], [3, -1, 6, -1, 8, -1, -1, -1]]
	return _build("sun", 96.0, ["C", "Am", "F", "G"], a, b, "sun",
		"AABAABBABA", Color("#ffcd75"))


## The fast one: vi-IV-I-V at 120 BPM, driving eighth-note bass.
static func _rocket() -> Dictionary:
	var a := [[4, -1, 4, 5, 4, -1, 2, -1], [5, -1, 5, 6, 5, -1, 4, -1],
		[7, -1, 7, 6, 5, -1, 2, -1], [6, -1, 6, 5, 3, -1, -1, -1]]
	var b := [[9, -1, 7, -1, 9, -1, 7, -1], [5, -1, 9, -1, 5, -1, -1, -1],
		[7, -1, 8, -1, 7, -1, 5, -1], [8, -1, 6, -1, 3, -1, -1, -1]]
	return _build("rocket", 120.0, ["Am", "F", "C", "G"], a, b, "rocket",
		"ABABAABBAB", Color("#73eff7"))


## The slow one: a lullaby, I-IV-I-V at 80 BPM, half notes.
static func _cat() -> Dictionary:
	var a := [[2, -1, -1, -1, 0, -1, -1, -1], [4, -1, -1, -1, 5, -1, -1, -1],
		[3, -1, -1, -1, 2, -1, -1, -1], [1, -1, -1, -1, 3, -1, -1, -1]]
	var b := [[5, -1, -1, 3, 2, -1, -1, -1], [4, -1, 5, -1, 4, -1, -1, -1],
		[2, -1, -1, -1, 0, -1, -1, -1], [1, -1, 3, -1, 1, -1, -1, -1]]
	return _build("cat", 80.0, ["C", "F", "C", "G"], a, b, "cat",
		"AABAABABBA", Color("#b13e53"))


static func _build(id: String, bpm: float, progression: Array, phrase_a: Array,
		phrase_b: Array, style: String, form: String, color: Color) -> Dictionary:
	var chords: Array[String] = []
	var lead: Array[Dictionary] = []
	var drums: Array[Dictionary] = []
	var crashes: Array[int] = []
	for bar in BARS:
		chords.append(progression[bar % 4])
		var phrase: Array = phrase_a if form[(bar / 4) % form.length()] == "A" else phrase_b
		var notes: Array = phrase[bar % 4]
		for e in 8:
			if notes[e] >= 0:
				lead.append({"step": bar * 8 + e, "note": int(notes[e])})
		for g in _drum_bar(style, bar):
			drums.append({"step": bar * 16 + int(g[0]), "pad": int(g[1])})
		if bar % 4 == 0:
			crashes.append(bar)
	return {"id": id, "bpm": bpm, "bars": BARS, "chords": chords, "lead": lead,
		"drums": drums, "crashes": crashes, "style": style, "color": color}


## Suggested drum pads for one bar: [sixteenth, pad] pairs, at most one per beat.
static func _drum_bar(style: String, bar: int) -> Array:
	var fill := bar % 4 == 3
	var hats := bar >= 16 and bar < 24
	var first := PAD_HAT if hats else PAD_KICK
	if style == "cat":
		if fill:
			return [[0, PAD_KICK], [8, PAD_TOM], [12, PAD_TOM]]
		return [[0, first], [8, PAD_SNARE]]
	if fill:
		return [[0, PAD_KICK], [4, PAD_SNARE], [8, PAD_TOM], [12, PAD_TOM]]
	return [[0, first], [4, PAD_SNARE], [8, first], [12, PAD_SNARE]]


## The backing groove the auto-drummer plays: {pad: [sixteenths in the bar]}.
static func groove(style: String) -> Dictionary:
	match style:
		"rocket":
			return {PAD_KICK: [0, 6, 8], PAD_SNARE: [4, 12], PAD_HAT: [0, 2, 4, 6, 8, 10, 12, 14]}
		"cat":
			return {PAD_KICK: [0], PAD_SNARE: [8], PAD_HAT: [0, 4, 8, 12]}
	return {PAD_KICK: [0, 8, 10], PAD_SNARE: [4, 12], PAD_HAT: [0, 2, 4, 6, 8, 10, 12, 14]}


## Bass line for one bar: [eighth, "root"|"fifth", length in eighths].
static func bass_bar(style: String) -> Array:
	match style:
		"rocket":
			return [[0, "root", 1], [1, "root", 1], [2, "root", 1], [3, "root", 1],
				[4, "fifth", 1], [5, "root", 1], [6, "root", 1], [7, "fifth", 1]]
		"cat":
			return [[0, "root", 6], [6, "fifth", 2]]
	return [[0, "root", 3], [3, "fifth", 1], [4, "root", 2], [6, "fifth", 2]]


## Chord strikes in a bar: eighths where the pad chord (re)starts.
static func chord_hits(style: String) -> Array:
	if style == "rocket":
		return [0, 4]
	return [0]


const FIFTHS := {"C": 43, "Am": 40, "F": 48, "G": 38}
