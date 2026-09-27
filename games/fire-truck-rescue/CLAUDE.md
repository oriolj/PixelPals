# Fire Truck Rescue

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/fire-truck-rescue/`), or from the root with
`make start G=fire-truck-rescue`. The design and its history are in
[PLAN.md](PLAN.md); how to play is in [README.md](README.md).

A chunky low-poly toy town (3D rendered at 480x270, integer-scaled) where the
family crews one fire truck:

- **Seat 1, Driver** (dad): drives the truck, camera-relative (stick up =
  away from the camera); A = horn.
- **Seat 2, Hose** (the 5-year-old): aims the hose in 4 screen directions,
  holds A to spray. Aim assist bends the water onto the nearest burning fire
  within 60 degrees of the chosen direction.
- **Seat 3, Siren** (the 2-year-old): ANY button = siren and lights (cars pull
  over, the dog barks); when the truck is parked by a stuck cat, the press
  raises the ladder and the cat rides down.

6 fires, 3 cats, 2 hydrants, a roundabout, a river with two bridges. No game
over, no text, 4-6 minute runs. Personal (oriolj) scope. Load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (the shared binary at the repo root `.tools/godot`). No
  Godot 3 APIs (`Spatial`, `KinematicBody`, `translation`, `yield`, `export var`).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Every 3D
  thing is built from Godot primitives in `scripts/level/` (no model files).
- **3D in a SubViewport.** The level renders its world in a 480x270
  `SubViewport` shown by a `Sprite2D`; the pixel HUD draws on top at the same
  resolution. Renderer `gl_compatibility` (xvfb captures work). Only
  `CPUParticles3D`, never GPU particles. Every `Sprite3D`/`AnimatedSprite3D`
  goes through `Low.billboard()` (nearest filter, alpha-cut, unshaded).
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`, and the local
  `loops.gd`), never through the import cache. Run/test targets depend on
  `ensure-import`.
- **Keyboard-only must work**, 1, 2 or 3 seats. Empty seats are automatic:
  no hose seat = auto hose; no siren seat = auto siren on leaving the station
  and auto ladder when parked by a cat.
- **No text in the UI. Never let a child's input end or hurt the run.** The
  siren seat can only make noise, lights and rescues.
- **Third-party characters** live in `game/private_pack/` and
  `art_src/private/` (gitignored and kept only on the family's machine (never committed); see the root
  CLAUDE.md). `make export-linux` excludes the pack.
- **Verify before claiming**: `make test`, then `make shots` and look at every
  `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=level` · `make test` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=<join|select|level|cat|home|party>` ·
`make shots` · `make editor` · `make setup-export` · `make export-linux`.
`make help` lists them all.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are **symlinks
into `../../shared/godot/autoload/`** (read-only for this game).
`game_state.gd` is this game's:

- `Game.goto("join"|"select"|"level"|"party")`; `Game.roster`;
  `Game.stars`, `Game.cats`, `Game.run_seconds` (results for the party).
- `Game.level_preset` ("" | "cat" | "home"): the next level starts from a
  preset (used by the demo driver for captures; consumed by the level).
- `Game.helmet_sprite(rider)` -> `h_<rider>` (the rider in a fire helmet).
- Demo mode: `-- --demo=<join|select|level|cat|home|party>`.

Seats: `Players.Seat.DRIVER/GUNNER/HONKER` = driver / hose / siren (the level
names them `DRIVER`, `HOSE`, `SIREN`).

Screens (`game/scripts/screens/`): `join.gd`, `select.gd` (PixelPals's,
relaid for 480x270 with this game's role icons; they diverge only in layout),
`level.gd`, `party.gd` (new: pixel-art station party).

Level modules (`game/scripts/level/`), pure logic first:

| file | what |
|---|---|
| `town_map.gd` | the ASCII town map and everything derived: cells, fire/cat/hydrant spots, station, solids, BFS road paths, fire order |
| `truck_model.gd` | arcade truck on the ground plane: camera-relative steering, reverse, soft bounces, road magnetism, unstick after 3 s |
| `fire_state.gd` | one fire: sizes 0-3, 1.5 s of water per size, grows to 3 when unattended, never spreads |
| `rules.gd` | tuning + pure decisions: hose live, aim assist, screen<->world, ladder reach, run end |
| `low.gd` | low-poly helpers: flat-shaded primitives, one material per colour, billboards, SurfaceTool boxes |
| `town_gen.gd` | builds the 3D town from the map (ground mesh, houses, trees, station, bridge, roundabout, folk, ducks) |
| `truck_view.gd` | the 3D truck (open cab, crew, light bar, telescoping ladder, water monitor, dalmatian) |
| `fire_view.gd` | flames (cones + wobble shader), fire face, smoke/steam particles, floating icon, ring |
| `water_arc.gd` | the water parabola ribbon (ImmediateMesh), splash, super-spray rainbow |
| `cars.gd` | two cars on looping Path3D routes; wait for the truck; pull over for the siren |
| `hud.gd` | pixel HUD: star bucket + pips, flame pips, cat badges, edge arrow, pause |
| `loops.gd` | looping sounds with live pitch/volume (local; proposed as `Sfx.loop()` for shared) |

`level.gd` owns the run: `step(dt)` does input -> truck -> siren -> hose ->
fires -> cats -> hydrants -> station -> end check -> cars -> camera -> views,
so tests drive it frame by frame. Run flow: fires appear one at a time in
`fire_order()`; after the 2nd, 4th and 6th fire a cat gets stuck in the
nearest cat tree and the next fire waits for its rescue; at all-done or
6 minutes the state goes `RUN -> HOMEWARD` (sunset, door opens, leftover
fires fizzle out, stuck cats hop down) and parking in the bay goes
`PARKED -> party`.

The town map legend (in `town_map.gd`): `#` road, `=` bridge, `y` road with
a hydrant, `~` river, `o` roundabout island, `.` grass, `h` house, `t` tree,
`S` station, `F`/`B`/`H` house/bin/haystack on fire, `C` cat tree. One cell
is 8 m.

### Asset names (the art and audio contract)

Sprites: `tools/sprites.py` renders `art_src/*.txt` grids and its generators
(Sweetie 16, linted) to `game/art/` + `manifest.json`.

| name | size | frames | use |
|---|---|---|---|
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (from PixelPals), townsfolk |
| h_penguin ... h_robot (+ h_ for every private rider) | 16x20 | 2 | riders in a fire helmet (generated) |
| cat | 16x16 | 2 | stuck cat (frame 1 meows) |
| dog | 16x16 | 2 | the dalmatian on the truck (frame 1 barks) |
| fire_face | 16x16 | 3 | face on the flames: grin, sprayed, blink |
| flame_icon | 16x16 | 2 | floating icon over a fire; HUD edge arrow |
| cat_icon | 16x16 | 2 | floating bubble over a stuck cat; edge arrow |
| home_icon | 16x16 | 1 | edge arrow at the end of the run |
| bucket | 24x24 | 1 | star bucket (HUD, party) |
| pip_flame / pip_flame_out | 8x8 | 2 / 1 | fires to do / done (HUD) |
| badge_cat / badge_empty | 16x16 | 1 | rescued cat / empty slot |
| seat_driver, seat_hose, seat_siren | 16x16 | 1 | role icons (wheel, nozzle, siren light) |
| icon_pad, icon_kb, arrow_left, arrow_right, check, star, heart | | | menu icons (from PixelPals) |
| trophy_helmet | 24x24 | 4 | spinning gold helmet (party) |
| truck_side | 112x56 | 2 | the truck in pixel art (party) |
| station_front | 176x112 | 1 | station facade (party) |
| town_strip | 480x64 | 1 | menu backdrop |
| confetti, cloud_bg | | | party / menus |

Sounds: `tools/sfx.py` synthesizes `game/audio/*.wav` (SFX at -15 LUFS,
music at -14 LUFS, loops seamless): `siren_1..3`, `horn`, `engine_loop`,
`spray_loop`, `spray_start`, `hiss_out`, `fire_crackle_loop`, `fire_start`,
`ladder_up`, `ladder_down`, `meow_1..3`, `purr`, `boing`, `star`, `badge`,
`super_spray`, `ready`, `join`, `select`, `bark_1..2`, `giggle`, `thanks`,
`drip`, `whoosh`, `party`, `music_menu`, `music_town`.

## Tests

`game/tests/`: `test_players.gd`, `menus/` (join, select, demo driver),
`level/` (truck, hose, fire, siren+ladder, run, party). `tests/helpers/level_rig.gd`
builds a level and steps it with scripted devices. `test_demo_route_clears_town`
plays a whole run with the demo driver (every fire, every cat, home, party).

## Diverging from shared (proposals, not applied)

This game did not edit `shared/`; the PLAN's extraction step was replaced by
local copies (join/select/party screens, `sprites.py`, `sfx.py`). Proposed
shared additions: `Sfx.loop(name, on, volume_db, pitch)` (what `loops.gd`
does), and neutral seat aliases `Seat.ADULT/KID/TODDLER`.
