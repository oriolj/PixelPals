# Rocket to the Moon

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below from
this folder (`games/rocket-to-the-moon/`), or from the root with `make start G=rocket-to-the-moon`.
The design and its history are in [PLAN.md](PLAN.md); how to play is in [README.md](README.md).

Count down, blast off and fly a rocket through the sky and space to the Moon:

- **Seat 1, Pilot** (the adult): steers the rocket in the lower third of the screen and lands it.
- **Seat 2, Grabber** (the 5-year-old): aims the claw arm in 4 directions and shoots it with A.
  The aim cone snaps to the nearest pickup.
- **Seat 3, Launcher** (the 2-year-old): ANY button presses the big launch button at every
  stage change, and fires the booster in flight. It can never hurt the run.

No game over, no text, one trip of about 4.5 minutes plus the launch. Personal (oriolj) scope.
Load the **video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (the repo-root `.tools/godot`). No Godot 3 APIs: no `yield`,
  `KinematicBody2D`, `export var`, `onready var`, `instance()`, `Tween` nodes.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are scripts in
  `game/scripts/screens/<name>.gd`; all their logic is in `step(dt)` so tests drive them
  frame by frame.
- **Pixel-perfect**: 320x180, integer scaling, nearest filtering, whole-pixel positions.
  Sprites scale by whole numbers (the Moon grows 1x -> 2x -> 3x) and turn only in 90-degree
  steps (the claw; the wobble spin is 8 pre-drawn roll frames).
- **Keyboard-only must always work**, with 1, 2 or 3 seats and pads mixed in.
- **No text in the UI.** Digits are drawn as 3x5 pixel glyphs (countdown, fuel count).
- **The Launcher can never hurt the run.** Its presses only boost, puff or press the
  button; the booster makes the rocket invulnerable and never moves it.
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`); every run/test target depends
  on `ensure-import`. The data file `game/data/timeline.json` is read with `FileAccess`.
- **Third-party riders** (Sonic, Minions, Mario...) are in `game/private_pack/` and
  `art_src/private/` (copied from PixelPals), gitignored and kept only on the family's machine (never committed);
  `make export-linux` excludes them.
- **Verify before claiming**: `make test`, then `make shots` and look at `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=flight` · `make test` · `make sprites` ·
`make sfx` · `make assets` · `make shot SHOT_SCREEN=launch` · `make shots` · `make editor` ·
`make export-linux`. `make help` lists them all; the tmux targets live in the root Makefile.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are **symlinks into
`../../shared/godot/autoload/`** (read-only here). `game_state.gd` belongs to this game.

- **Players** (shared): ask per seat. `Seat.DRIVER/GUNNER/HONKER` = Pilot/Grabber/Launcher.
- **Game** (`game_state.gd`):
  - `Game.goto("join"|"select"|"launch"|"flight"|"party")`.
  - Trip results: `Game.fuel` (cans), `Game.trip_planets` (kinds 1-8 found this trip).
  - The album: `Game.album`, saved to `Game.album_path` (`user://album.json`; the demo uses
    `user://album_demo.json`, tests their own file) by `Game.found_planet(kind)` at once.
  - `Game.trip_scale` multiplies the stage lengths (demo: 0.2).
  - `Game.press_seat()` / `Game.launch_pressed()`: the fold-down. The big button belongs to the
    Launcher (any button), else the Grabber ("a"), else the Pilot ("a").
- **Logic** (`game/scripts/logic/`, pure and unit tested): `countdown.gd` (the WAIT -> COUNT ->
  IGNITION -> DONE ritual, 8 s auto press, presses only shake), `claw.gd` (shoot, snap, carry
  back, quarter-turn sprite), `timeline.gd` (expands `data/timeline.json`), `rules.gd` (speeds,
  refills, bumps, landing), `album.gd` (the JSON file), `aim.gd` (copied from PixelPals).
- **Views** (`game/scripts/view/`): `sky.gd` (palette bands by altitude + 3 parallax star
  layers), `crew.gd` (helmeted portraits), `lights.gd`, `big_button.gd`, `digits.gd`,
  `pause_overlay.gd`.

### Screen flow

`join` -> `select` -> `launch` -> `flight` -> `party` -> `select`.

- **join / select**: copied from PixelPals (role icons changed, riders get helmets).
- **launch**: the countdown, ignition, lift-off, then `flight`. Pilot's start pauses.
- **flight**: stages SKY (60 s) -> press -> SPACE (150 s; stage separation countdown halfway)
  -> MOON approach (24 s, the Moon grows) -> LANDING (off-pad bounces; after 3 tries the pad
  slides under) -> LANDED -> press plants a flag per seat -> `party`. Every press waits for the
  press seat and presses itself after 8 s. With no Launcher the booster fires by itself at each
  stage change; with no Grabber a magnet pulls pickups in.
- **party**: on the Moon: the album page (found planets in colour, this trip's pop in, missing
  ones as silhouettes), the fuel count, dancing riders. 12 s or the Pilot's A -> `select`.

### Asset names (the art and audio contract)

Sprites: generated by `tools/sprites.py` from `art_src/*.txt` (hand grids) and generators whose
grids are written to `art_src/generated/*.txt` (do not edit those). Sweetie 16, linted.

| name | size | frames | use |
|---|---|---|---|
| rocket | 24x40 | 2 idle rumble + 8 roll (wobble spin) | the upper stage |
| rocket_stage | 24x16 | 1 | the lower stage, drops at separation (addition) |
| flame | 8x12 | 4 big + 4 small | engine; small when the tank is empty |
| smoke | 16x16 | 4 | smoke, steam, Moon dust (tinted) |
| gantry | 16x64 | 1 | launch tower |
| launch_pad | 64x16 | 1 | launch pad, and the Moon landing pad |
| countdown_light | 12x12 | 2 (off, on) | countdown lights |
| big_button | 24x16 | 2 (idle, pressed) | the launch button |
| claw | 8x8 | 2 (open, closed) | points right, turned by 90s |
| arm_link | 4x4 | 1 | repeated along the arm |
| fuel | 8x12 | 2 | fuel can |
| planet_1..planet_8 | 16x16 | 2 | Mars, Saturn, Earth, Jupiter, Neptune, candy, green+moon, Pluto heart |
| silhouette_1..8 | 16x16 | 1 | missing album planets |
| asteroid | 16x16 | 2 (grumpy, blink) | soft hazard |
| comet | 16x8 | 2 | decoration |
| moon | 96x96 | 1 | the approach |
| moon_ground | 320x32 | 1 | the Moon's surface |
| earth_ground | 320x48 | 1 | the launch site |
| flag | 16x16 | 2 | tinted with seat colours |
| helmet | 20x20 | 1 | over the 16x16 riders |
| album_frame | 16x16 | 1 | album slot |
| sparkle | 8x8 | 4 | asteroid-to-star, planet sparkles (addition) |
| cloud, bird, balloon, confetti | 32x16, 8x8, 16x24, 4x4 | 1, 2, 2, 6 | sky stage and party (additions) |
| seat_pilot, seat_grabber, seat_launcher | 16x16 | 1 | role icons |
| icon_pad, icon_kb, arrow_left, arrow_right, check | 16/8 | 1 | menus |
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (PixelPals art) |

Sounds (`tools/sfx.py`, own synth, -15 LUFS SFX, -14 LUFS music loops): `beep_1`..`beep_5`,
`ignition`, `rumble`, `liftoff`, `booster_1`..`booster_3` (played as `booster`), `puff`,
`claw_shoot`, `claw_grab`, `fuel`, `planet_1`..`planet_8` (one pentatonic note per kind), `bump`,
`separation`, `landing`, `flag`, `join`, `select`, `ready`, `party`, `pop`, `whoosh`,
`music_space`, `music_menu`.

Sky, stars and the HUD (Earth-to-Moon track, fuel gauge) are drawn in code.

### Divergences from the shared code

None: the shared autoloads are used unchanged. `aim.gd`, the join/select screens, the demo
driver skeleton, `tools/sprites.py`'s renderer/lint and `tools/sfx.py`'s synth are copies of
PixelPals's (the plan's "extract into shared/ first" step was not done here; see PLAN.md).
