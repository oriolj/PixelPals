# Tractor Farm

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/tractor-farm/`), or from the root with
`make start G=tractor-farm`. Load the **video-games** skill
(`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`) for the house rules.
The design and its history are in [PLAN.md](PLAN.md); how to play is in
[README.md](README.md).

Plough, plant, rain and harvest one sunny field together:

- **Seat 1, Driver** (dad): drives the tractor. The plough under it turns
  grass into furrows, the planter behind sows, driving over ripe crops
  harvests them into the trailer; tip the trailer at the barn.
- **Seat 2, Seeds** (the 5-year-old): picks one of four seeds with a
  direction (up carrot, right pumpkin, down sunflower, left strawberry); A
  switches the planter on and off.
- **Seat 3, Rain cloud** (the 2-year-old): ANY button rains; plants under
  the cloud grow a stage with a boing. Five quick presses make a rainbow.

No text, no game over, nothing wilts, and a run ends after 30 crops in the
barn or 6 minutes with a giant vegetable and a village fair.

## Rules

- **Godot 4.7 only** (the shared binary at the repo root `.tools/godot`). No
  Godot 3 APIs: no `yield`, `update()`, `export var`, `onready var`,
  `instance()`, `WORLD_MATRIX`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are `game/scripts/screens/<name>.gd` (Node2D, children built in `_ready`).
- **Flat vector, not pixel art.** 1280x720 base canvas, `canvas_items`
  stretch, `gl_compatibility`. Every shape is drawn in code from
  `scripts/draw/`; there are no image files except the rider sprites.
  Deviation from the plan: no MSAA 2D (Godot's Compatibility renderer does
  not support it and warns); the antialiased 2 px ink outlines smooth the
  edges instead.
- **Crop icons compose onto `S.base`.** `Crops.icon()` and `Farm.animal()`
  set their own canvas transform on top of `shapes.gd`'s `S.base`. Around
  anything that draws them, set the outer transform with `S.xform()` and
  undo it with `S.reset()`; never `draw_set_transform()` directly (it would
  be overwritten). Lambdas capture locals by value: a dict an effect's
  lambda reads must exist before the lambda (see `_fx_node`).
- **Big scaled drawings switch AA off** (`S.aa = false`): the stroke feather
  is one LOCAL unit, so a 5x-scaled vegetable would blur.
- **Riders are pixel art on a vector canvas**: always create them with
  `Game.rider_sprite(id, k)` (nearest filter, whole-number scale).
- **Keyboard-only must always be playable**; pads and keyboard mix.
- **Never let a child's input end or hurt the run.** The rain cloud only
  grows, sparkles or makes puddles; the seed seat can only choose; nothing
  a kid presses removes a crop or a counter.
- **Third-party characters** (Sonic, Shadow, Knuckles, Robotnik, the
  Minions, Mario, Luigi) come from PixelPals's `game/private_pack/`, copied
  here. The pack is gitignored (local only); never publish or export it
  (`make export-linux` excludes it).
- **Verify before claiming.** `make test`, then `make shots` and look at
  every `shots/<screen>/sheet.png`; `make contact` for the art.

## Commands

`make start` · `make demo SHOT_SCREEN=level` · `make test` · `make sfx` ·
`make contact` · `make shot SHOT_SCREEN=level SHOT_SECONDS=60 SHOT_FPS=10` ·
`make shots` · `make export-linux`. `make help` lists everything.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only here; see
PixelPals's CLAUDE.md for their API). `game_state.gd` is this game's:

- `Game.goto("join"|"select"|"level"|"party"|"crops")`; `crops` is the
  developer contact sheet, outside the flow.
- Results for the party: `Game.barn` (crops per crate: carrot, pumpkin,
  sunflower, strawberry), `Game.giant_crop`, `Game.run_seconds`.
- `Game.run_limit` (360 s; the demo uses 150 s), `Game.level_preset`
  (`"finale"` starts the level with a full barn).
- Demo: `-- --demo=<join|select|level|finale|party|crops>` runs
  `scripts/demo_driver.gd`; `--mute` silences it.
- `Game.rider_sprite(id, k)`: a crisp rider sprite.

Scripts (`game/scripts/`):

| file | owns |
|---|---|
| `field_rules.gd` | all farm rules, no nodes: 16x9 tiles in `PackedInt32Array` (grass, ploughed, seeded, sprout, growing, ripe) + crop, sun timers, puddles, trailer (cap 24), barn, run end (30 crops or `end_seconds`), `most_planted()`, `nibble()`; it queues `events` the level drains |
| `screens/level.gd` | input -> rules, tractor steering (turn toward the stick, max turn rate, soft fences), the hitch chain (plough under the tractor, planter 1 tile behind, trailer), cloud follow + rain footprint, auto-seed/auto-rain for empty seats, tip at the barn, visitors and puddle critters, the finale (giant vegetable, carry it off), effects, loops, pause |
| `screens/join.gd`, `select.gd` | PixelPals's join/select logic, redrawn for the farm |
| `screens/party.gd` | the fair: 4 vegetable stacks = the barn counts, the giant on a podium |
| `screens/crops.gd` | contact sheet: 16 crop stages at 1x and 2x, silhouettes, every prop |
| `draw/shapes.gd` | vector helpers (outlined polygons, discs, leaves, hearts, stars, faces), `S.xform/local`, `S.aa`. Candidate for `shared/godot/vector/` |
| `draw/pal.gd` | the palette |
| `draw/crop_art.gd` | `draw(ci, crop, stage)` and `icon(ci, crop, size, at)` |
| `draw/farm_art.gd` | tractor, planter, trailer, cloud faces, rainbow, barn, crates, fence, tree, pond, sun, animals, seat and device icons |
| `draw/painter.gd` | a Node2D that draws with a callable |
| `demo_driver.gd` | scripted seats; level: boustrophedon 90 s, then sweep + tip; seeds change every row; the cloud presses every 1.5 s |

Wind sway: a `canvas_item` shader on grown `CropNode`s (vertex x offset by
`sin(TIME + world_x)` times height above the soil point).

### Asset names (the art and audio contract)

Art is drawn in code at run time (table = function in `draw/`):

| asset | drawn by | size (px) |
|---|---|---|
| field tiles (grass, furrows, wet, puddle) | `level._draw_field` | 64 |
| crops x4, stages seed/sprout/growing/ripe | `crop_art.draw` | 16-75 |
| crop icon (bags, picker, crates, trailer, party) | `crop_art.icon` | any |
| tractor (cab, big back wheel, exhaust) | `farm_art.tractor` + `tractor_front` | 120x100 |
| plough + planter with 4 seed bags | `farm_art.planter` | 64x44 |
| trailer with its pile | `farm_art.trailer` | 100x50 |
| rain cloud, faces IDLE/RAIN/HAPPY | `farm_art.cloud` | 130x80 |
| rainbow | `farm_art.rainbow` | 600 |
| barn, crate, fence, tree, pond, sun | `farm_art.*` | various |
| bunny, pig, hen, duck, frog (2 poses) | `farm_art.animal` | 40-56 (x1.3) |
| seed picker (plus shape) | `level._draw_picker` | 168 |
| giant vegetable | ripe `crop_art.draw` x6 | ~330 |
| seat icons (wheel, seed bag, cloud), pad, keyboard | `farm_art.*` | 60-150 |

Pixel sprites (`game/art/`, copied from PixelPals): `penguin`, `monkey`,
`fox`, `frog`, `robot` (16x16, 2 frames), plus the private pack.

Sounds (`game/audio/*.wav`, `make sfx`, levels printed by the tool):
`horn`, `plant`, `seed_pick_1`..`seed_pick_4` (carrot, pumpkin, sunflower,
strawberry), `rain_start`, `grow_1`..`grow_3`, `ripe`, `harvest_pop`,
`trailer_tip`, `crate`, `quack`, `ribbit`, `oink`, `cluck`, `bunny_boing`,
`rainbow`, `giant_grow`, `join`, `select`, `ready`; loops played by the level
itself (`_loop_player`, from source bytes): `engine_loop` (pitch by speed),
`plough`, `rain_loop`; music `music_farm` (98 BPM) and `music_fair`.

### Screen flow

`join` -> `select` -> `level` -> `party` -> `select`.

- **level:** driver start pauses (A resumes, B goes back to join). The run
  ends (30 crops in the barn, or 6 minutes) with the giant vegetable: it
  grows on its own every 1.4 s, a cloud press grows it at once; then the
  tractor drives to it, it hops on the trailer and they drive off to the fair.
- **party:** 14 s, or the driver's A after 1 s.
