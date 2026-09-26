# Train Conductor

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/train-conductor/`), or from the root with
`make start G=train-conductor`. The design and its history are in
[PLAN.md](PLAN.md); how to play is in [README.md](README.md).

A wooden toy railway seen from above. Everyone shares one train:

- **Seat 1, Engine** (dad): throttle and brakes; stops the engine at the
  platforms (a perfect stop sparkles); the horn.
- **Seat 2, Points** (the 5-year-old): throws the next junction's points
  toward the branch they want (the beacons show which station lies that
  way) and opens the doors at stations.
- **Seat 3, Whistle** (the 2-year-old, optional): ANY button toots the
  whistle: steam rings, animals answer, the cow steps off the track, and at
  a station the bell rings and everybody hops on faster.

Passengers wear the colour and hat shape of the station they want (red
circle, blue square, yellow triangle, green star). 12 deliveries or 6
minutes end the run: night falls, the houses light up, fireworks, party.
No game over, no text, no timer on anybody. Personal (oriolj) scope. Load
the **video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (the shared binary at the repo root `.tools/godot`). No
  Godot 3 APIs: no `yield`, `update()` (use `queue_redraw()`),
  `interpolate_baked` (use `sample_baked`), `export var`, `onready var`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are scripts in `game/scripts/screens/<name>.gd`.
- **Flat vector, not pixel art.** 1280x720, `stretch/mode="canvas_items"`,
  aspect keep, Compatibility renderer. Godot 4.7 has no 2D MSAA in the
  Compatibility renderer (it only warns), so smooth edges come from the
  antialiased outline polylines. Every colour comes from
  `scripts/palette.gd`; every shape has the 2 px ink outline
  (`Shapes.fill_outline`). The only pixel art is the riders (PixelPals's
  cast, 16x16 at x3, nearest filter per node) in round windows.
- **Rules live in `Sim`, pictures in the views.** `scripts/level/sim.gd`
  has no drawing; tests drive it directly. Views only animate what they see
  in the Sim or its events.
- **Keyboard-only must always be playable**, with 1, 2 or 3 seats.
- **The whistle seat can never hurt the run** (it has no path to speed,
  points or doors; `test_the_whistle_seat_can_never_hurt_the_run`).
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`, and
  `level.gd load_stream()` for the chuff loop), never through the import
  cache; every run/test target depends on `ensure-import`.
- **Verify before claiming**: `make test`, then `make shots` and look at
  every `shots/<screen>/sheet.png` (frames are native 1280x720).

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=level` · `make test` ·
`make sprites` · `make sfx` · `make sfx-check` · `make assets` ·
`make shot SHOT_SCREEN=level SHOT_SECONDS=45` · `make shots` ·
`make editor` · `make setup-export` · `make export-linux`. `make help`
lists them. Shot screens: `join`, `select`, `level`, `finale` (the level a
few seconds before night, demo only) and `party`.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only here).
`game_state.gd` is this game's:

- `Game.goto("join"|"select"|"level"|"party")`; `Game.roster`;
  `Game.train_riders()` (seated riders by seat).
- Run results for the party: `Game.deliveries` (station colour per
  delivered passenger), `Game.perfect_stops`, `Game.stars` (= both).
- `Game.run_seconds` (360), `Game.seed_value` (0 = random),
  `Game.level_setup` (`{"deliveries": n, "time_left": s}`, demo captures).
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`.

Track and train (`scripts/track/`):

- `track.gd` (TrackGraph): the map as data. `NODES` (position + heading),
  `EDGES` (from, to, via points -> one `Curve2D` each, tangents matched at
  nodes), `STATIONS`, `TUNNEL`, `BRIDGE`, pond, farm, meadow, `START`.
  Queries: `sample/tangent/closest`, `out_edges/in_edges`, `junctions`,
  `branch_dir`, `branch_for_flick(node, dir)` (0/1, or -1 = toggle),
  `beacon(edge)` (station colours that lie that way),
  `strongly_connected()`, `min_radius()`.
- `train.gd`: the engine's NOSE is `(edge, dist)`; cars hang behind at
  fixed arc lengths, sampled back through `history` (no PathFollow2D).
  `advance(delta, next_edge_callable)`, `car_transforms()` (centre between
  the two bogies), `past(edge, d)`, `place(edge, d)`, `capacity()`
  (2 seats per carriage, 1..5 carriages).

Rules (`scripts/level/sim.gd`): `step(dt, input)` with input keys `up`,
`down`, `horn`, `points` (Vector2i flick), `doors`, `whistle`. Modes
`run | rollback | docked | finale`. Tuning constants at the top (speeds,
lock time, platform window, perfect window, hop times, cow patience).
Signal `event(kind, data)`: points, points_locked, points_same,
took_branch, docked, perfect, rollback, doors, bell, boarded, delivered,
coupled, exchange_done, depart, whistle, horn, cow_aside, cow_back, tunnel,
wheee, spawned, run_end. `solo` (no points seat: tour rule, doors open by
themselves after 1 s) and `auto_whistle` (no whistle seat) are set by the
level from the seats.

Level screen (`scripts/screens/level.gd`): builds the views under a
`World` node (z order: ground 0, track 1, stations 2, points 3, animals 4,
train 5, people 7, tunnel cover 9, fx 10), a `CanvasModulate` for the
night, a glow `CanvasLayer` (follows the camera, outside the night tint)
and the HUD layer. `read_input()` (static) is the only seat-to-role map.

Views (`scripts/level/`): `ground_view`, `track_view`, `station_view`,
`points_view`, `animal_view`, `train_view`, `people_view`, `cover_view`,
`fx_view`, `glow_view`, `hud`; recipes in `draw.gd` (passenger, head,
house, tree, fence, token); shapes in `scripts/vector/shapes.gd`
(proposed for `shared/godot/vector/`). Menus: `join`, `select`, `party`,
with `icons.gd` and `menu_train.gd` (the real TrainView on a straight).

### Asset names (the art and audio contract)

Everything but the riders is drawn in code. Sizes at 1280x720, world px:

| asset | made in | size |
|---|---|---|
| track (straight, curve, junction, farm crossing) | `track_view.gd` from each Curve2D: ink band, wood, sleepers every 24 px, grooves at ±11 px | 48 wide |
| points blade + sign | `points_view.gd` (blade swings between branches; round sign, arrow tweens) | sign r=40 |
| branch beacons | `points_view.gd` (station shapes, pulsing when next) | r=17 |
| engine (face, chimney, dome, cab, 2 piston frames) | `train_view.gd` | 112x52 |
| tender (the kids' windows) / carriages (5 colours, 2 windows) | `train_view.gd` | 100x52 / 72x48 |
| passengers (4 colours x hat shape) | `draw.gd passenger()`, `head()` | ~26x44 |
| stations + platforms, stop post, clock | `station_view.gd` | 180x96, platform 430 long |
| houses (5 per station hill, windows light up) | `draw.gd house()` | 42x42 |
| tunnel, bridge, pond, trees, fences, farm, meadow | `cover_view`, `track_view`, `ground_view` | various |
| cow, duck, sheep (2 poses) | `animal_view.gd` | ~70 |
| steam (CPUParticles2D), rings, sparkles, hearts, fireworks | `fx_view`, `glow_view` | 12-95 |
| HUD: 12 delivery pips, sun/moon, throttle lever, speed dial, pause | `hud.gd` | pip r=17 |
| riders `penguin monkey fox frog robot` (+ private pack) | `art_src/riders.txt` -> `make sprites` | 16x16 x2 frames, shown x3 |

Sounds (`make sfx`, `tools/sfx.py`, all synthesized, `game/audio/`):
`whistle_1..3`, `whistle_long`, `chuff_loop` (rate follows speed),
`brake_squeal`, `beep_beep`, `horn`, `points_clack`, `doors_open`, `bell`,
`hop_1..3`, `deliver_red|blue|yellow|green` (C, E, G, A), `moo`, `quack`,
`baa`, `couple`, `perfect_stop`, `wheee`, `firework`; menus `join`,
`select`, `ready`, `whoosh`, `party`; music `music_rails` (160 BPM),
`music_night` (finale and party), `music_menu`.

### Screen flow

`join` → `select` → `level` → `party` → `select`. Join and select keep
PixelPals's logic (copied, redrawn; its tests are copied too). Level: the
driver's start pauses; in pause, "b" goes back to join and "a"/start
resumes. Party: 12 s, or the driver's "a" after 1.5 s.

## Local copies (diverging from shared/)

- `tools/sfx.py` copies PixelPals's synth core; `tools/sprites.py` copies
  its grid renderer (generators removed). Both are candidates for
  `shared/tools/`.
- `scripts/vector/shapes.gd` is the proposed `shared/godot/vector/shapes.gd`.
- `level.gd load_stream()` duplicates `Sfx._load`, because a speed-driven
  loop needs its own `AudioStreamPlayer` (the shared `Sfx` has no handle).
- The private pack (`game/private_pack/`, `art_src/private/`) is PixelPals's
  fan riders, committed only because the repo is private; export excludes it.
