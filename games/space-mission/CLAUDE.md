# Space Mission

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first, and load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).
Run every `make` below from this folder (`games/space-mission/`), or from the
root with `make start G=space-mission`. The plan, its decisions and its
deviations are in [PLAN.md](PLAN.md); how to play is in [README.md](README.md).

Fly the Space Shuttle to build the space station in Earth orbit, land on Mars
with a sky crane, then drive a rover across the red planet: one crew, three jobs.

- **Seat 1, Pilot / Driver** (the adult): flies the Shuttle (damped, no
  gravity, it stops itself), steers the sky crane down, drives the rover.
- **Seat 2, Arm operator** (the 5-year-old): moves the robot-arm tip in 4
  directions and grabs with A (the cargo snaps within 12 px); on Mars picks
  the landing site and drills rocks.
- **Seat 3, Camera and buttons** (the 2-year-old): ANY button takes a photo
  of Earth (and blinks the station's lights), pops the parachute, launches
  the little Mars helicopter. It never changes the mission's outcome.

No game over, no text, no timers that run out. Every beat that waits for a
seat completes itself after 5 s. Personal (oriolj) scope.

## Rules

- **Godot 4.7 only** (the shared binary `../../.tools/godot`, renderer
  `gl_compatibility`). No Godot 3 APIs: no `yield`, `KinematicBody2D`,
  `export var`, `onready var`, `instance()`, `rand_range`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  scripts in `game/scripts/screens/<name>.gd`; the stage screens keep all their
  logic in `step(dt)` so tests drive them frame by frame.
- **Pixel-perfect.** 320x180, integer scaling, nearest filtering, snap on.
  Sprites scale by whole numbers and turn only in 90-degree steps (the
  astronauts' zero-g flips). The robot arm is rasterised pixel by pixel from
  the `arm_segment` pattern, never a rotated sprite. The Earth globe is a
  shader that only uses `texelFetch` and a precomputed pixel-circle mask, and
  outputs palette colours only (an ordered dither at the terminator).
- **Keyboard-only must always work**, with 1, 2 or 3 seats, pads mixed in.
- **No text in the UI.** Counts are drawn as icons (little suns for sunrises).
- **The camera seat can never hurt the run**: its presses make photos, blink
  lights, pop the parachute early, fly the helicopter (a spotlight only).
- **Photos stay in memory** (`Game.photos`, thumbnails for the party screen);
  nothing is written to disk.
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`, plus
  `scripts/view/tex.gd` for the Earth textures and `scripts/view/loop_audio.gd`
  for the two sound loops). Every run/test target depends on `ensure-import`.
- **Third-party riders** (Sonic, Mario and the rest) are in
  `game/private_pack/` and `art_src/private/`, copied from PixelPals and
  committed only because the repo is private. `make export-linux` excludes
  them. Never publish them.
- **Verify before claiming**: `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=orbit` · `make test` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=mars` ·
`make shots` · `make editor` · `make export-linux` (after `make setup-export`).
`make help` lists them; the tmux targets live in the root Makefile.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only from here).
`game_state.gd` is this game's:

- `Game.goto("join"|"select"|"orbit"|"landing"|"mars"|"party")`.
  Flow: `join -> select -> orbit -> landing -> mars -> party -> select`.
  `Game.start_stage` (0 orbit, 1 landing, 2 mars) is picked on the select
  screen's planet row; `Game.STAGES` maps it to a screen.
- Mission results for the party: `Game.photos` (`[{tex, golden}]`, in memory
  only), `Game.modules` (the station modules fitted), `Game.samples` (rock
  kinds drilled), `Game.site` (landing site), `Game.sunrises`, `Game.docked`.
  `Game.new_mission()` clears them.
- `Game.mission_scale` shortens stage lengths (the demo uses 0.35).
- Seat fall-backs (`Game.camera_pressed()`, `Game.arm_auto()`): the Camera
  seat's any button; with no Camera seat, the Pilot's B (2 seats) and also
  the Pilot's A when alone. With no Arm seat the arm runs itself.
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`; `--mute`.
  A `--demo=orbit` run plays the whole mission: orbit -> landing -> mars ->
  party -> select. Headless runs take no photos (the dummy renderer has no
  pixels); tests inject `capture_source`.

Tests (`game/tests/`, 67, GUT): `logic/` (IK, flight, station, terrain,
rover, helicopter, landing beats, photos), `stages/` (orbit, mars, the flow:
stage select, seat fall-backs, the Pilot-only pause, the toddler never
changing the outcome), `menus/` (join, select, demo driver), `test_players`.
`tests/helpers.gd` drives a screen frame by frame with scripted seats.

Logic (`game/scripts/logic/`, node-free, unit tested):

| file | what |
|---|---|
| `arm_ik.gd` | analytic 2-bone IK: `solve(base, target, l1, l2, bend)` -> elbow and reachable tip; `clamp_reach` |
| `aim.gd` | copied from PixelPals: the cone pick used for the rover's drill direction |
| `space_flight.gd` | damped 2D flight with auto-stabilise, soft "boing" push-back from a rect |
| `station.gd` | the 5 module slots (kind, offset, port), `can_dock(kind, pos)`, `fit()`, cargo spawn/loop lane |
| `terrain.gd` | the Mars heightmap (seeded sines), `height_at(x)`, target placement per landing site |
| `rover.gd` | spring-follow wheels, clamped tilt (it cannot flip), drive/brake, auto-creep |
| `helicopter.gd` | the heli state machine: DOCKED -> UP -> SCOUT -> BACK -> COOLDOWN, loops on presses |
| `landing_beats.gd` | PARACHUTE -> SITE -> CRANE -> DONE, each auto-completing after 5 s |
| `photos.gd` | capture (viewport image or an injected fake) -> 64x36 thumbnail |

Views (`game/scripts/view/`): `earth.gd` (the globe: a ColorRect with the
shader, mask baked at start), `starfield.gd`, `mars_sky.gd` (the day
gradient and the blue sunset), `arm_view.gd` (pixel-rasterised arm),
`pause.gd` (the Pilot-only pause and its overlay), `tex.gd` (textures from
source bytes), `loop_audio.gd`, `confetti.gd`.

### Screen flow

- **join / select**: copied from PixelPals / Rocket to the Moon. The select
  screen shows the riders in their helmets; the Pilot's up/down moves the
  highlight on the planet row (Earth, Mars landing, Mars surface).
- **orbit**: fly the Shuttle, grab each cargo module with the arm, fit it in
  its glowing port (5 modules), then dock with the station (strong assist);
  the astronauts float out and flip. Sunrise every 20 s; Earth moments make
  golden photos.
- **landing**: parachute (Camera), landing site (Arm), sky crane (Pilot).
- **mars**: drive, drill the sparkling rocks, the helicopter scouts ahead;
  the blue sunset and the beam home at the end.
- **party**: Mission Control: the big screen plays the photos, the station
  and the samples; the mission patch with the crew; confetti. 14 s or the
  Pilot's A -> select.
- **pause** (stages only): the Pilot's start. In pause the Pilot's B goes
  back to join, A or start resumes. No other seat can pause.

### Asset names (the art and audio contract)

Sprites: `tools/art_gen.py` (procedural, Endesga 32) and the text grids in
`art_src/*.txt` (the riders and menu icons, Sweetie 16 remapped), rendered
and linted by `tools/sprites.py`, which also derives `astronaut_<rider>` for
every rider. Contact sheets: `art_src/contact_sheet*.png`,
`art_src/astronaut_sheet.png`.

| name | size | frames | use |
|---|---|---|---|
| shuttle | 48x20 | 2 (engine glow) | faces right; arm shoulder at pixel (20, 4) |
| iss_core | 32x16 | 2 (lights off/on) | the station's heart |
| iss_lab, iss_habitat, iss_robot | 16x16 | 2 (window/lamp blink) | fitted modules |
| iss_solar | 32x16 | 4 (unfold: folded -> open) | the solar wings (fitted twice) |
| iss_port | 16x16 | 2 (glow pulse) | white dashed outline, tinted per module colour in code |
| cargo_lab, cargo_solar, cargo_habitat, cargo_robot | 16x16 | 2 (bob) | floating cargo, with a grapple pin |
| arm_segment | 24x4 | 1 | the arm's pattern (rows = cross-section, columns = stripes) |
| arm_hand | 8x8 | 2 (open, closed) | the grapple, faces right |
| drill | 8x8 | 2 (spin) | the rover arm's drill head (addition) |
| dock_ring | 16x16 | 2 | the Shuttle's docking target (addition) |
| earth, earth_night, earth_clouds | 768x96 | 1 | the globe textures, horizontally seamless (deviation: 768 wide so the globe is never magnified) |
| stars_far, stars_near | 320x180 | 1 | parallax star layers, transparent, seamless both ways |
| aurora | 48x16 | 4 | Earth moment: a green curtain at the limb |
| hurricane | 16x16 | 4 | Earth moment: a white swirl |
| sunrise_line | 320x4 | 4 | the golden gleam along the limb at sunrise |
| astronaut_<rider> | 24x24 | 2 | derived: rider + bubble helmet + collar (deviation: 24x24 so every rider fits) |
| lander_shell | 32x32 | 2 (heat glow) | the aeroshell |
| parachute | 48x32 | 2 (billow) | orange and white canopy with lines |
| sky_crane | 32x16 | 2 (thrusters) | the rocket platform |
| cable | 1x8 | 1 | tiled vertically |
| site_dunes, site_crater, site_ice, site_rocks | 32x16 | 1 | the four landing spots (addition) |
| rover | 40x24 | 2 (mast turns) | body; wheels drawn separately at x 7, 20, 33 |
| wheel | 8x8 | 4 (spin) | rover wheel |
| helicopter | 12x8 | 2 (rotor) | the little Mars helicopter |
| mars_far, mars_mid | 320x60, 320x48 | 1 | parallax mountains and dunes, seamless horizontally |
| mars_ground | 16x16 | 1 | tile for the terrain polygon |
| rock_red, rock_grey, rock_white, ice, shell | 12x10 | 2 (sparkle) | science targets |
| sample_red, sample_grey, sample_white, sample_ice, sample_shell | 6x8 | 1 | sample capsules |
| dust_puff | 8x8 | 4 | touchdown and wheels |
| drill_sparks | 8x8 | 4 | drilling |
| sparkle | 8x8 | 4 | module clicks in, sample pops (addition) |
| mission_control | 320x180 | 1 | party room |
| big_screen | 160x90 | 1 | the room's big screen (content drawn in code) |
| patch | 48x48 | 1 | the mission patch (crew drawn in code) |
| confetti | 4x4 | 6 | one colour per frame |
| sun_icon | 8x8 | 1 | the sunrise counter (addition) |
| seat_pilot, seat_arm, seat_camera | 16x16 | 1 | role icons |
| planet_earth, planet_mars_landing, planet_mars | 16x16 | 1 | start-stage icons |
| icon_pad, icon_kb, check, arrow_left, arrow_right | 16x16 / 8x8 | 1 | menus (PixelPals grids) |
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (PixelPals grids) |

Sounds (`tools/sfx.py`, own synth, -15 LUFS SFX, -14 LUFS loops, 44.1 kHz
mono): `quindar_in`, `quindar_out`, `thruster`, `arm_move`, `grab`, `clunk`,
`solar_unfold`, `camera_1..3`, `sunrise_chime`, `photo_golden`,
`parachute_pop`, `crane_lower`, `touchdown`, `crane_bye`, `drill`,
`sample_pop`, `heli_loop`, `phone_home`, `party`, `boing`, `wave`, `dock`,
`join`, `select`, `ready`, `whoosh`; loops `rover_hum`, `heli_buzz`,
`music_orbit` (72 bpm), `music_mars` (100 bpm), `music_menu` (90 bpm).

## Local copies instead of shared changes

`shared/` is read-only for this game; proposed extractions are in PLAN.md:

- `tools/sprites.py`: Submarine Safari's renderer, plus the helmet overlay
  (any rider -> astronaut) with a fit lint, and `REMAP_OVERRIDES` for the
  Sweetie 16 -> Endesga 32 remap (the nearest colour turned blue into grey,
  light green into beige and orange into pink).
- `scripts/logic/arm_ik.gd`: the 2-bone IK (Digger Treasure could use it).
- `scripts/view/tex.gd`, `scripts/view/loop_audio.gd`: texture and loop
  loaders from source bytes (the shared `Art`/`Sfx` return frames and
  one-shots only).
