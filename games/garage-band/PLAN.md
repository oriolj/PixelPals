# Garage Band

A three-piece band in the garage where every note lands on the beat and in key, so whatever anyone plays sounds good.

Status: plan (2026-09-26)

## Why it fits our family

- **The 5-year-old** plays drums on four big pads, one per direction.
  Their hits snap to the beat, so they sound like a real drummer; hitting
  the pads the song suggests lights stars.
- **The 2-year-old** crashes the cymbal. Any press is a big, satisfying
  crash that changes the stage lights; it always lands on a beat, so it
  sounds right every time.
- **The adult** plays the melody on a lane highway, a light rhythm
  challenge, and can also just jam: the scale has no wrong notes.
- It teaches beat and taking turns, and it ends with the band hearing its
  own song played back.

## Roles and controls

Seats fill in join order. The keyboard column is the suggested block; the
Drummer needs directions, so not kb:2.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Lead** (adult): picks a note on a 5-lane highway (pentatonic, 2 octaves) and strums | stick / d-pad up-down steps the note, left-right shifts an octave, A strums (hold = repeat on eighths), Start pauses | kb:0: W/S note, A/D octave, Shift strums, Esc pauses |
| 2 | **Drummer** (5-year-old): four pads | d-pad or stick: up = hi-hat, left = snare, right = tom, down = kick; A = kick too | kb:1: arrows = pads, Enter = kick |
| 3 | **Crasher** (2-year-old): cymbal crash, cycling through crash, gong, cowbell, whoosh | any button | kb:2: Space or any unowned key |

Fewer seats:

- **1 seat:** the Lead plays; a soft auto-drummer keeps a basic groove, and
  the Lead's B is the crash.
- **2 seats:** Lead plus Drummer; the auto-crash lands on every 8th bar.
- A missing Drummer never leaves silence: the backing groove is always
  there, and a live Drummer's hits replace its parts, they do not stack.

## Core loop

1. Pick a song (the adult, left/right on three album covers).
2. Four clicks of the drumsticks count in (icons, no numbers needed).
3. The song plays: a backing loop (bass plus soft chords) over a chord
   progression. Note gems scroll toward the hit line on the Lead's 5
   lanes and toward the Drummer's 4 pads; the Crasher's cymbal glows on
   the bars where a crash is suggested.
4. Every input sounds, snapped to the grid. Hitting a suggested gem makes
   it burst into stars; anything else still plays in key and in time.
5. After 40 bars the song ends on a big shared chord; the party screen
   plays the band's recording back while the band bows.

### The music rules (why nothing sounds wrong)

- **Scale:** C major pentatonic (C D E G A), two octaves on the Lead's
  lanes (C4 to A5). No semitone neighbours, so no clashes.
- **Harmony:** I–vi–IV–V (C, Am, F, G), one chord per bar, 96 BPM, 4/4.
  On the strong beats (1 and 3) the Lead's note is nudged to the nearest
  chord tone within one scale step (B would be the only clash, and it is
  not in the scale anyway); off-beats keep the chosen note.
- **Quantisation:** the grid is sixteenths for drums, eighths for the
  melody, beats for crashes. A press within the first 35 % of a grid step
  sounds at once (at most about 55 ms late, under what a child notices);
  a later press is scheduled to the next step (at most about 110 ms
  later). The **visual** answer is always immediate (the pad bounces the
  same frame), so every press feels answered.
- **Density caps:** at most one hit per drum per sixteenth, one melody note
  per eighth, one crash per beat; extra presses only animate.
- **Mix:** crashes duck the backing by 3 dB for half a beat; drums are
  panned and levelled so the kit never drowns the melody.

### No-fail rules

- No score can go down; missed gems simply pass. There is no
  "boo", no meter that empties, no song that stops early.
- A song always runs to its end; the adult can stop it from the pause menu.
- Session: a song is 40 bars at 96 BPM (2.5 s per bar), about 1:40; two
  or three songs plus the party replays make about 5 minutes.

## Screens and flow

`join` → `select` → `play` → `party` → `select`, as in PixelPals. `select`
adds the song picker for seat 1 after the riders are ready. The riders
become the band: each rider holds its instrument on the garage stage.
`party` replays the recording with the band bowing and the gems of
their hits flying over the stage as stars.

## Art direction

**Flat vector, drawn in code**, 640x360, `canvas_items` stretch, MSAA 4x.
Instruments and pulsing speakers read best as clean shapes, and things
scale and bounce on the beat, which pixel art does badly.

- Palette: Sweetie 16 fills; the garage is dark (`#1a1c2c`, `#333c57`)
  so the stage lights (`#ffcd75`, `#73eff7`, `#b13e53`, `#a7f070`) pop.
- How it is made: `Polygon2D`, `_draw()` and a small shader; no PNGs
  except the reused 16x16 riders (drawn at x3).

| Asset | Size (px) | How |
|---|---|---|
| garage (door, shelves, bike, boxes) | 640x360 | polygons from point lists, drawn once |
| stage lights (4 cones) | 80x200 each | Polygon2D with additive blend, colour on crash |
| amp + speaker cones | 64x80 | circles in `_draw()`, cone scale pulses on each bass note |
| guitar, drum kit (4 drums), cymbal, gong, cowbell | 32-64 each | polygons; drums squash 10 % on a hit |
| lane highway | 5 lanes, 200x160 | a perspective quad per lane, lit on strum |
| note gems | 16x16 | a 6-gon, lane colour, bursts into star particles |
| drum pad icons | 40x40 | 4 coloured discs in a d-pad cross at seat 2's corner |
| song covers | 64x64 x3 | procedural: sun, rocket, cat, from polygons |
| beat pulse | full screen | a vignette shader brightening on beat 1 |

## Audio

Two layers:

1. **Live synthesis in Godot:** an `AudioStreamGenerator` (mix rate
   22050 Hz, mono, buffer 0.1 s) driven by `band_synth.gd`. It owns the
   **musical clock**: the sample counter is the song position, so
   quantisation is sample-accurate. Voices: the Lead (pulse wave with
   ADSR and slight vibrato, 4 voices), the bass (triangle), the chords
   (two detuned saws, low-passed).
2. **Pre-rendered one-shots mixed into the same generator:** drums and
   crashes from our `tools/sfx.py`-style script, loaded as float arrays at
   start and added into the buffer at their scheduled sample. Files:
   `kick`, `snare`, `hat`, `tom`, `crash`, `gong`, `cowbell`, `whoosh`,
   `sticks` (count-in).

Plus ordinary `Sfx.play` sounds for menus: `join`, `select`, `ready`,
`party`, `gem_burst` (a tiny sparkle, not quantised). Music for menus:
`music_menu` (reused).

**Performance budget:** GDScript fills about 2205 samples per 0.1 s. The
M1 benchmark must show that filling 1 s of audio with 8 active voices
takes under 150 ms of CPU. **Fallback** if it does not: keep the generator
as the clock but play the melody as pre-rendered notes (one WAV per scale
note per instrument, 10 x 3) through an `AudioStreamPolyphonic`, scheduled
with `AudioServer.get_time_to_next_mix()` and `get_output_latency()`.

## Reuse

- **From shared/:** `players.gd`, `art.gd` (riders), `sfx.gd` (menus),
  `tools/shots.py`.
- **From PixelPals:** the demo driver pattern, join/select/party screens,
  the Makefile targets, the synth in `tools/sfx.py` (for the one-shots).
- **Extract into shared/ first:**
  - `Players.dir4_just_pressed(seat)`: an edge on a newly pressed
    direction (the drum pads need it; Paint Party's colour pots too).
  - `shared/tools/synth.py` (oscillators, envelopes, loudness report).
  - The shared screen router and screens (see Tower Topple's plan).
  - Later, `band_synth.gd` itself if another game wants live music.

## New tech this game needs

- `AudioStreamGenerator` + `AudioStreamGeneratorPlayback.push_buffer()`
  fed from `_process`, with a sample clock, a scheduler (a sorted event
  list of `{sample, voice, note}`) and a voice pool.
- A **recording mechanic:** every quantised event is appended to a list;
  the party screen replays it through the same synth, so the playback is
  exactly what was heard.
- Beat-synced visuals: everything that pulses reads the synth's clock,
  not `_process` time, so lights and gems stay on beat.
- **Risks for Claude-built Godot:** Godot 3 drift
  (`AudioStreamGeneratorPlayback` exists in 4 but method names changed;
  `get_frames_available()` and `push_buffer(PackedVector2Array)` are the
  4.x API); `.tscn` breakage, so everything is built in code; headless runs
  render nothing and use the dummy audio driver, so the synth is tested by
  calling its fill function directly on arrays, never through a real
  device. `--write-movie --fixed-fps` decouples game time from wall time:
  the generator must be fed by song position, not by the audio device's
  hunger, or the capture drifts.

## MVP scope

One song (I–vi–IV–V, 40 bars), the full three-seat band, the recording
playback on the party screen, about 5 minutes including two plays.

### M1 grey-box

- [ ] Skeleton (vector project settings, Makefile, CLAUDE.md + AGENTS.md,
  shared autoload symlinks).
- [ ] `band_synth.gd`: clock, scheduler, 3 voice types, one-shot mixing.
- [ ] Quantiser and chord-tone nudge as pure functions (`music_rules.gd`).
- [ ] Performance benchmark test; decide generator vs fallback.
- [ ] Grey stage: rectangles for pads, lanes, cymbal; gems scroll.
- [ ] Fold-down for 1 and 2 seats; recording and replay.
- [ ] Couch test: does the Drummer feel the delay? Is the Lead highway
  readable from the sofa?

### M2 art and audio

- [ ] Garage, band, lights, speakers, gems, covers in vector.
- [ ] One-shots rendered by `tools/sfx.py`; loudness report.
- [ ] Two more songs (a slow one, a fast one), same scale.

### M3 polish and couch test

- [ ] Beat vignette, speaker pulses, crash light changes.
- [ ] Tune the quantise window and the mix from the couch notes.
- [ ] Party replay with bows; clean-clone run.

## Tests and verification

GUT tests (`game/tests/`):

- `test_every_lead_note_is_in_the_pentatonic_scale`
- `test_strong_beat_nudges_to_a_chord_tone`
- `test_offbeat_keeps_the_chosen_note`
- `test_early_press_sounds_now`
- `test_late_press_waits_for_next_step`
- `test_drum_quantises_to_sixteenths`
- `test_crash_quantises_to_beats`
- `test_one_hit_per_drum_per_step`
- `test_synth_fill_has_no_nan_and_stays_under_full_scale`
- `test_synth_fill_one_second_under_budget`
- `test_recording_replays_the_same_events`
- `test_song_always_reaches_the_end`
- `test_one_seat_gets_auto_drummer`
- `test_live_drummer_replaces_auto_parts`

Demo driver ("play"): the Lead follows the gems exactly for 8 bars, then
plays random scale notes; the Drummer hits the suggested pads with a
random 0-120 ms error; the Crasher presses every 1.7 s (off the beat on
purpose, to show quantisation). A second tool, `tools/render_demo.gd`
run headless, writes the synth output of the same demo to
`shots/play/audio.wav` so its level and spectrogram can be measured by the
synth script's `--check` report.

Look at in the frames (`shots/play/sheet.png`, 2x): gems line up with the
hit line on the frames where they are hit; drums squash on hits; the
lights change colour after each crash; lanes are readable at a glance; the
party frames show the band bowing.

## Open questions for Oriol

1. Songs: original tunes only, or simple versions of songs the kids know
   (public-domain nursery tunes fit the pentatonic scale well)?
2. Is the Lead highway fun for you, or would you rather free-jam with the
   gems as gentle hints only?
3. Should the recording be saved (a WAV in `~/Music/GarageBand/`) so the
   kids can hear their song later? It is family material, so never in the
   repo.
4. Is 96 BPM right, or should the tempo follow the kids (slower for the
   2-year-old's crashes)?
