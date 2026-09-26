extends RefCounted
## The music rules, as pure functions: why nothing anyone plays sounds wrong.
##
## - Scale: C major pentatonic, two octaves on the Lead's 5 lanes (C4..A5).
## - Harmony: one chord per bar; on the strong beats (1 and 3) a Lead note is
##   nudged to the nearest chord tone within one scale step.
## - Quantisation: a press in the first EARLY_WINDOW of a grid step sounds at
##   once; a later press waits for the next step.
## Everything works in samples of the synth clock (RATE per second).

const RATE := 22050

## C D E G A, C D E G A (MIDI). Lead note index = octave * 5 + lane.
const LEAD_NOTES: Array[int] = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81]
const LANES := 5
const OCTAVES := 2
## Pitch classes of the pentatonic scale.
const SCALE_PCS: Array[int] = [0, 2, 4, 7, 9]

## Chords by id: C, Am, F, G (MIDI triads in a comfy middle register).
const CHORDS := {
	"C": [60, 64, 67],
	"Am": [57, 60, 64],
	"F": [53, 57, 60],
	"G": [55, 59, 62],
}
## Bass roots (one octave under the chords).
const ROOTS := {"C": 36, "Am": 33, "F": 41, "G": 43}

const EARLY_WINDOW := 0.35

## Grids, in steps per beat.
const GRID_DRUM := 4    # sixteenths
const GRID_LEAD := 2    # eighths
const GRID_CRASH := 1   # beats


static func samples_per_beat(bpm: float) -> float:
	return RATE * 60.0 / bpm


static func lead_note(lane: int, octave: int) -> int:
	return clampi(octave, 0, OCTAVES - 1) * LANES + clampi(lane, 0, LANES - 1)


static func lead_midi(index: int) -> int:
	return LEAD_NOTES[clampi(index, 0, LEAD_NOTES.size() - 1)]


static func in_scale(midi: int) -> bool:
	return SCALE_PCS.has(posmod(midi, 12))


static func is_chord_tone(midi: int, chord: String) -> bool:
	for m in CHORDS[chord]:
		if posmod(m, 12) == posmod(midi, 12):
			return true
	return false


## Strong beats are beats 1 and 3: eighth steps 0 and 4 of the bar.
static func is_strong_eighth(eighth_in_bar: int) -> bool:
	return posmod(eighth_in_bar, 8) == 0 or posmod(eighth_in_bar, 8) == 4


## Nudge a Lead note index to the nearest chord tone within one scale step.
## A chord tone stays; otherwise the closer (in semitones) neighbour that is a
## chord tone wins, the lower one on a tie; with neither, the note stays.
static func nudge_to_chord(index: int, chord: String) -> int:
	if is_chord_tone(lead_midi(index), chord):
		return index
	var best := index
	var best_dist := 99
	for n in [index - 1, index + 1]:
		if n < 0 or n >= LEAD_NOTES.size():
			continue
		if not is_chord_tone(LEAD_NOTES[n], chord):
			continue
		var dist := absi(LEAD_NOTES[n] - LEAD_NOTES[index])
		if dist < best_dist:
			best = n
			best_dist = dist
	return best


## The note that sounds: nudged on strong beats, kept on off-beats.
static func melody_note(index: int, chord: String, eighth_in_bar: int) -> int:
	if is_strong_eighth(eighth_in_bar):
		return nudge_to_chord(index, chord)
	return index


## Quantise a press at sample `press` to a grid of `step` samples whose step 0
## starts at `origin`. Returns [sound_sample, step_index]: a press within the
## first EARLY_WINDOW of its step sounds at once (in that step), a later one
## waits for the start of the next step.
static func quantise(press: int, step: float, origin := 0) -> Array:
	var rel := float(press - origin)
	var idx := int(floor(rel / step))
	var into := rel - idx * step
	if into <= EARLY_WINDOW * step:
		return [press, idx]
	return [origin + int(round((idx + 1) * step)), idx + 1]


## Sample where grid step `idx` starts.
static func step_sample(idx: int, step: float, origin := 0) -> int:
	return origin + int(round(idx * step))
