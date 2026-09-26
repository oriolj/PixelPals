# Submarine Safari

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first, and load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).
Run every `make` below from this folder (`games/submarine-safari/`), or from
the root with `make start G=submarine-safari`. The plan and its decisions are
in [PLAN.md](PLAN.md); how to play is in [README.md](README.md).

A little yellow submarine explores a dark, glowing reef for 6 minutes:

- **Seat 1, Pilot** (dad): swims with inertia, pings the sonar.
- **Seat 2, Camera** (the 5-year-old): points the viewfinder in 4
  directions and snaps; the aim assist slides the frame onto a creature
  within 24 px. Every photo goes into the family album.
- **Seat 3, Lights** (the 2-year-old): ANY button flashes the sub's lights
  in the next colour; the trench's shy creatures only come out while they
  shine; three quick presses make a disco.

No game over, no text, no oxygen, no enemies. An empty snap photographs a
bubble, a shell, a smiling rock or a starfish. Personal (oriolj) scope.

## Rules

- **Godot 4.7 only** (the shared binary is `../../.tools/godot`). No Godot 3
  APIs (`yield`, `Light2D`, `export var`, `onready var`, `rand_range`...).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are `game/scripts/screens/<name>.gd` scripts that build their children.
- **Pixel-perfect.** 320x180, integer scaling, nearest filtering, snap on.
  Rotate only by 90-degree steps (the bump spin and the disco spin do).
  The camera is a rounded offset of the `world` node, not a Camera2D:
  snap the camera itself, and nothing is left behind on the next screen.
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`, and
  `scripts/audio_loop.gd` for the two loops); the map is read with
  `FileAccess`. Every run/test target depends on `ensure-import`.
- **Keyboard-only must always work**, with 1, 2 or 3 seats; the toddler
  seat can never hurt the run.
- **The family album is sacred**: the demo and the tests never touch
  `user://album.json` (they use `user://album_demo.json` and `user://test_*`).
- **Verify before claiming**: `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo` · `make test` · `make reef` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=level
SHOT_SECONDS=60` · `make shots` · `make editor` · `make export-linux`
(after `make setup-export`). `make help` lists them.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only from here).
`game_state.gd` is this game's:

- `Game.goto("join"|"select"|"level"|"album")`; flow `join -> select ->
  level -> album -> select`, and `join -> album -> join` to browse.
- `Game.album` (`scripts/album.gd`): the persistent album. `record(id,
  score, frame) -> is_new`, `has`, `count`, `add_bonus`, `bonus`, `save`,
  `reset`. Stored with `scripts/save.gd` as versioned JSON in `user://`,
  safe on corrupt files (kept aside as `.bad`).
- `Game.session`: this run's `new`, `repeats`, `seen`, `bonus`, `whale`.
- `Game.run_seconds` (0 = 6 minutes), `Game.album_browse`, demo flags
  `--demo[=screen]`, `--album=reset` (demo album only), `--mute`.

Level logic (`game/scripts/level/`), node-free and unit tested:

| file | what |
|---|---|
| `species.gd` | the 12 page species (order = album slots = motif numbers), the whale, the bonus subjects |
| `reef.gd` | loads `data/reef.json`: tiles, collision, zones, homes, demo route, decor; `ambient_at()` (the CanvasModulate by depth) |
| `creatures.gd` | the state machines: EASY wander, HIDER hidden/out (sonar within 170 px, flash within 80 px), LIGHT shown only while the lights are on, WHALE wait/pass/gone; glow, disco spin, puff |
| `viewfinder.gd` | frame offsets per direction, the 24 px assist, `contains()`, `score()` |
| `sub_motion.gd` | inertia, the current outside the world, the bounce |
| `lights.gd` | the toddler's presses (cooldown 0.25 s, 4 colours, 3 quick = disco), auto flashes, the banded light textures |
| `rules.gd` | run length, end condition (6 min or all 12 this run), pearl-trail target, bonus subject, whale timing |

`scripts/screens/level.gd` owns the nodes and runs everything from
`step(dt)`: tests drive it frame by frame with scripted seats. Seats:
DRIVER `move` + `a` sonar + `start` pause (pause `b` = back to join),
GUNNER `dir4` + `a` snap, HONKER `any` lights. An empty GUNNER seat
auto-snaps a subject not yet photographed this run after 1 s in the frame;
an empty HONKER seat flashes every 8 s and near shy creatures.

Lighting: a `CanvasModulate` from `ReefMap.ambient_at(sub)`, a headlight
cone and a round glow `PointLight2D` on the sub, both with textures baked
by `lights.gd` into 4 dithered bands. Glowing and light-loving creatures,
the sub, the viewfinder, rings and pearls use an unshaded material (so the
gl_compatibility per-item light limit never matters). The HUD is on a
CanvasLayer, out of the darkness.

The map is designed in `tools/reef.py` (80 x 23 tiles of 16 px; shallows,
reef, wreck, trench; seeded dunes, ragged shelf, kelp, coral); it fails if
a home is in rock or the demo route scrapes rock.

### Asset names (the art and audio contract)

Sprites: generated by `tools/art_gen.py` (Endesga 32) and grids in
`art_src/*.txt`, rendered and linted by `tools/sprites.py`.

| name | size | frames | use |
|---|---|---|---|
| sub | 40x24 | 4 | the yellow sub, propeller spin, faces right (flipped) |
| viewfinder | 48x40 | 2 | corners; frame 1 = locked on |
| flash | 64x64 | 3 | snap burst, additive, 3 frames max |
| clownfish, blue_tang, pufferfish, pufferfish_puffed, seahorse, lantern_fish | 16x16 | 2 | easy fish / light-lover |
| turtle, crab, octopus, squid, anglerfish | 24x24 | 2 | creatures |
| eel | 24x24 | 4 | peek loop, faces right out of a hole on the left |
| jellyfish | 16x24 | 4 | pulse |
| whale | 128x48 | 2 | the big friend (tail up/down) |
| bubble 8x8 (2), shell 12x12, starfish 12x12, rock_smile 16x16 | | 1-2 | bonus subjects |
| mini_bubble, mini_shell, mini_rock_smile, mini_starfish | 8x8 | 1 | HUD bonus row |
| icon_<subject>, sil_<subject> | 20x20 | 1 | album icons and silhouettes (derived from frame 0; icon_whale is drawn) |
| sil_whale_big | 128x48 | 1 | whale silhouette |
| album_slot | 20x20 | 1 | strip/page slot |
| polaroid | 24x28 | 1 | flying photo card (subject drawn inside) |
| rock, rock_top, sand, sand_top | 16x16 | 1 | reef tiles |
| coral | 16x16 | 2 | two variants (branching, brain), picked per tile |
| kelp, kelp_top, anemone | 16x16 | 2 | swaying decor |
| wreck | 96x48 | 1 | sunken ship (the octopus's door) |
| pearl | 6x6 | 4 | the trail |
| bubble_small | 4x4 | 1 | particles |
| star | 8x8 | 1 | repeat photo |
| seat_driver (helm), seat_gunner (camera), seat_honker (bulb), icon_album | 16x16 | 1 | menu icons |
| icon_pad, icon_kb, check, arrow_left, arrow_right | | 1 | PixelPals's (Sweetie 16 grid, remapped) |
| penguin, monkey, fox, frog, robot (+ private pack) | 16x16 | 2 | riders (PixelPals grids, remapped) |

Sounds (`tools/sfx.py`, `game/audio/`): `sonar`, `shutter`, `propeller`,
`boing`, `repeat_star`, `disco`, `whale_song`, `eel_peek`, `puff`,
`surface`, `join`, `select`, `ready`, `whoosh`, `new_species_1..12` (one
4-note marimba motif per species, page order), `lights_1..4`,
`bubble_1..3`; loops `music_reef` (80 bpm, on the `Reef` bus whose
low-pass opens as you go deeper), `music_album` (96 bpm, menus and album),
`sub_hum_loop` (volume follows the speed).

## Local copies instead of shared changes

The plan asked to move these into `shared/`; agents may not edit it, so they
live here and are proposed to the coordinator:

- `tools/sprites.py`: PixelPals's renderer + `--palette` (32-char indices
  `0-9a-v`), a `; palette: <name>` file directive that remaps grids from
  another palette, and the album icon/silhouette outputs.
- `game/scripts/save.gd`: versioned JSON in `user://`, atomic writes,
  corrupt files set aside. Proposed as `shared/godot/save.gd`.
