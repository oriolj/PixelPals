# Garage Band

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below from
this folder (`games/garage-band/`), or from the root with `make start G=garage-band`.
The plan (now history, with the decisions taken) is [PLAN.md](PLAN.md); how to
play is in [README.md](README.md).

A three-piece band in a garage where every note lands on the beat and in
key, so whatever anyone plays sounds good:

- **Seat 1, Lead** (the adult): picks a note on a 5-lane highway (C major
  pentatonic, two octaves) and strums; B crashes when nobody is the Crasher.
- **Seat 2, Drummer** (the 5-year-old): four pads on the d-pad, A = kick.
- **Seat 3, Crasher** (the 2-year-old): any button is a crash, gong, cowbell
  or whoosh, always on a beat. It can never pause, stop or spoil the song.

No game over, no text, a song is 40 bars (about 1:20 to 2:00), then the
party screen replays the band's own recording while the band bows. Personal
(oriolj) scope. Load the **video-games** skill before working here.

## Rules

- **Godot 4.7 only** (the root `.tools/godot`). No Godot 3 APIs. GDScript
  with static types where cheap; `:=` needs a typed right-hand side (values
  read from untyped `stage.x` / `band.x` need `var v: float =`).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are `game/scripts/screens/<name>.gd`, views `game/scripts/view/*.gd`.
- **Flat vector art, drawn in code** at 640x360 (`canvas_items` stretch, so
  the vectors are drawn at window resolution). No PNGs except the reused
  16x16 riders, drawn at x3 (x4 on select, x2 as panel portraits) with
  nearest filtering (`Game.rider_sprite`). Sweetie 16 colours only
  (`view/draw.gd`, plus two derived shades, WOOD and PINK).
- **No 2D MSAA**: the plan asked for 4x, but the Compatibility renderer
  (the one that renders under xvfb for `make shot`) does not support it,
  and Vulkan does not start under xvfb. Keep `gl_compatibility`.
- **The music never depends on the audio device.** The song clock is game
  time; `SynthPlayer` renders the synth to `now + LEAD` and pushes what fits
  into the generator, dropping the rest. Test the synth by calling `fill()`
  on buffers, never through a device (headless = dummy driver).
- **Rendering is partition-invariant.** Envelopes interpolate on a 32-sample
  grid of each voice's age, the duck on an absolute 32-sample grid, and done
  voices are purged before every event, so a replay renders bit-for-bit what
  was heard however the frames were cut. Keep it that way
  (`test_recording_replays_the_same_events`).
- **Assets load from source bytes**: kit WAVs through
  `BandSynth.read_wav_mono` (FileAccess), menu sounds through the shared
  `sfx.gd`, riders through the shared `art.gd`. The Makefile's run/test
  targets depend on `ensure-import`.
- **A `-s` script must `load()`, not `preload()`, anything naming an
  autoload** (`tools/render_demo.gd`): preloads compile before the autoloads
  exist. And a `-s` script that errors never quits: guard with `timeout`.
- **Keyboard-only is always playable**, 1, 2 or 3 seats, pads mixed in.
- **Third-party characters** live in `game/private_pack/` (copied from
  PixelPals, gitignored and kept only on the family's machine (never committed)). `make
  export-linux` excludes it. Never publish it.

## Commands

`make start` · `make demo SHOT_SCREEN=play` · `make test` · `make sfx` ·
`make riders` · `make assets` · `make audio-check` · `make shot
SHOT_SCREEN=play` · `make shots` · `make editor` · `make export-linux`
(`make setup-export` once). `make help` lists them all.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only here).
`game_state.gd` belongs to this game:

- **Game**: `Game.goto("join"|"select"|"play"|"party")`, `Game.roster`,
  `Game.song_index`, the last performance (`Game.recording`,
  `Game.hits_log`, `Game.stars`, `Game.song_samples`), demo mode
  (`-- --demo[=screen]`), `Game.rider_sprite(id, scale)`.
- **Players** (shared): seats 0 Lead, 1 Drummer, 2 Crasher
  (`Players.Seat.DRIVER/GUNNER/HONKER`). The drum pads use the shared
  `Players.dir4_just_pressed(seat)`.

Music (`game/scripts/music/`), all RefCounted and testable headless:

| file | contract |
|---|---|
| `music_rules.gd` | pure functions: `LEAD_NOTES` (C4..A5), `lead_note(lane, octave)`, `nudge_to_chord`, `melody_note(idx, chord, eighth)` (nudge on eighths 0 and 4 only), `quantise(press, step, origin) -> [sample, step_index]` (first 35 % of a step sounds at once, later waits for the next step) |
| `songs.gd` | `Songs.get_song(i)`: `{id, bpm, bars: 40, chords, lead: [{step (eighths), note}], drums: [{step (16ths), pad}], crashes: [bar], style, color}`; `groove(style)`, `bass_bar(style)`, `chord_hits(style)`. Pads: 0 hat (up), 1 snare (left), 2 tom (right), 3 kick (down) |
| `band_synth.gd` | the synth and clock: `schedule(ev)`, `fill(n) -> PackedVector2Array`, `recording`, `load_recording(rec)`, `capture`/`capturing`. Events `{s, k: LEAD/BASS/CHORD/SHOT, ...}` |
| `band.gd` | the conductor: `update(now)` schedules backing, auto-drummer, auto-crash (every 8th bar without a live Crasher), count-in and final chord; `strum(now, lane, octave, repeat)`, `drum(now, pad)`, `crash(now)` return `{sounded, sample, gem, step}`; density caps; a live hit cancels that drum's pending auto hits for a bar; gems, `stars`, `hits_log`, visual cue lists |
| `synth_player.gd` | Node: `advance(delta)` moves `now`; `render()` renders to `now + LEAD` and feeds an `AudioStreamGenerator` (22050 Hz, 0.1 s buffer) |

Screens: `join` (PixelPals rules, vector icons) → `select` (riders, then
the Lead picks a song cover) → `play` → `party` → `select`.

### Asset names

Drawn in code (`view/draw.gd`, `view/*.gd`):

| asset | where |
|---|---|
| garage (wall, door, shelves, boxes, cans, plant, ball, bike, window, string lights, floor, rug) | `view/garage.gd` |
| stage lights (4 additive cones, colour set changes on each crash), light truss | `view/stage.gd` Lights/Back |
| amps + speaker cones (pulse on each bass note) | `view/stage.gd` Back |
| guitar, drum kit (hi-hat, snare, tom, kick; squash 10 % on a hit), cymbal, gong, cowbell, whoosh | `view/draw.gd`, placed by `view/stage.gd` Front |
| lane highway, note gems (6-gons; dot = low octave, star = high) | `view/highway.gd` |
| drum pad cross (hat yellow, snare blue, tom green, kick red) and pad gems | `view/drum_pads.gd` |
| Crasher's instrument corner (glows on suggested bars) | `view/crash_pad.gd` |
| count-in sticks, progress note, star meter | `view/top_hud.gd` |
| song covers `sun`, `rocket`, `cat` | `draw.gd` `cover()` |
| icons: gamepad, keyboard, arrows, check, play, back, sticks, note, role icons | `draw.gd` |
| star particles | `view/fx.gd` |
| beat vignette (brightens on beat 1) | shader in `screens/play.gd` |
| riders `penguin monkey fox frog robot` (+ private pack) | PNGs copied from PixelPals (`make riders`) |

Sounds (`tools/sfx.py`, `make sfx`, loudness report printed):

| file | use |
|---|---|
| `audio/kit/{kick,snare,hat,tom,crash,gong,cowbell,whoosh,sticks}.wav` | 22050 Hz one-shots mixed by the synth at their scheduled sample |
| `audio/{join,select,ready,party,gem_burst}.wav` | menu sounds through `Sfx.play` (join/select/ready/party are PixelPals's) |
| `audio/music_menu.wav` | menu loop (PixelPals's, reused) |

## Verification

`make test` (50 GUT tests: music rules, synth incl. the performance budget,
band, menus, play, party, demo driver). `make shots`, then look at
`shots/<screen>/sheet.png` (frames are 1280x720, the sheet at 1x). `make
audio-check` renders the play demo's synth output headless to
`shots/play/audio.wav` and reports peak/LUFS/clipping/silent seconds plus a
spectrogram.
