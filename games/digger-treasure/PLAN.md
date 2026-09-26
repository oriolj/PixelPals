# Digger Treasure

Dad drives a little yellow digger through a side-view slice of dirt, the
5-year-old swings the scoop to dig where they choose, and the 2-year-old's
"boom" blasts dirt everywhere and pops buried treasure up into the air.

Status: plan (2026-09-26)

## Why it fits our family

- **5-year-old**: agency and surprise. They pick the spot (4 directions) and
  every scoop takes a visible bite out of the ground; buried things glint
  through the dirt, so "I think it's there!" is a real, rewarded guess. A
  wrong guess still finds something: a worm, a bone, a snail.
- **2-year-old**: the biggest cause-and-effect in the whole list. Any button
  makes a round "boom" of flying dirt around the digger, and whatever treasure
  sits inside the blast pops up with a sparkle. Nothing it can do goes wrong.
- **Adult**: the steering, and the pacing: driving toward the glints so the
  kids' presses land near treasure.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | Driver (adult) | left stick drives in any direction; "a" = small scoop in the driving direction; start = pause | kb:0 WASD drives, Shift scoops, Esc pauses |
| 2 | Scooper (5-year-old) | d-pad/stick picks the scoop direction (4 dirs, arm turns); "a" = big scoop (5x5 cells) | kb:1 arrows aim, Enter scoops |
| 3 | Boomer (2-year-old) | any button = boom (radius 7 cells, 1.2 s cooldown, extra presses give a little dirt puff) | kb:2 Space or any other key |

- **1 seat**: the driver alone. Driving into dirt digs automatically (slowly,
  one digger-width tunnel); "a" scoops forward; the boom fires by itself
  every 20 s as a "surprise".
- **2 seats**: no boomer; same auto-boom every 20 s so the treasure pops still
  happen.
- **3 seats**: as the table. Keyboard-only works on one shared keyboard.
- Seats keep the PixelPals colours: blue driver, yellow scooper, green boomer.
  The scoop arm and the boom ring are drawn in the owning seat's colour.

## Core loop

1. The level is one wide dirt field (960x320 world pixels, 3 screens wide,
   2 tall) under a grass strip with the dump truck parked on the left.
2. Twelve treasures are buried at fixed-but-shuffled spots (chest, crown,
   dinosaur egg, gem cluster, gold coin pile, toy robot...). Each one glints
   every ~2 s through up to 12 cells of dirt, brighter as the digger nears.
3. The digger drives through open tunnels; driving into dirt digs slowly. The
   scooper's big scoop clears a 5x5 bite in the aimed direction; the boom
   clears a circle.
4. When a treasure is uncovered (any of its cells exposed), it pops up,
   spins, and flies in an arc to the dump truck's bed, which fills up
   visibly. Counter = the truck, no numbers.
5. Small finds everywhere: worms wriggle away, bones, fossils, a snail, a
   mole that waves. They only delight; they are never a "miss".

**No-fail rules**

- No damage, no fuel, no timer that can run out, no falling rocks, no
  collapsing dirt in the MVP (so nothing can trap or crush the digger).
- Hard rock cells exist only as the level's border; bumping them makes a
  "donk" and a wobble.
- The digger cannot get stuck: if it has no free cell around it for 2 s, a
  friendly puff clears a 3x3 space.
- A scoop into empty air still animates and plays its sound.
- The run ends when all 12 treasures are in the truck, or at 5 minutes, when
  the remaining treasures burst up on their own in a final fountain (the
  kids still "find" them all). Target session: 4-6 minutes.

## Screens and flow

`join` → `select` → `dig` → `party` → `select`, as in PixelPals.

- **join / select**: reused. Select picks a digger colour per driver and a
  helmet-wearing rider for each seat (penguin, monkey, fox, frog, robot, plus
  the private pack when present). Riders sit in the cab and on the arm.
- **dig**: the level. The camera follows the digger, clamped to the field.
- **party**: the dump truck drives on screen, tips its load and every treasure
  bounces out in a row, with confetti and the riders dancing.

## Art direction

- **Pixel art**, 320x180 canvas, 16 px tiles, integer scale, Sweetie 16
  palette (the house default for small kids, already rendered and linted by
  our pipeline). Why pixel: the dirt grid IS pixels; destroying it cell by
  cell looks right at low resolution and costs nothing to render.
- Dirt layers by depth: topsoil `#ef7d57` over `#b13e53`, deep clay `#5d275d`,
  border rock `#333c57`; tunnels show the dark `#1a1c2c` background with
  roots. Grass `#38b764`/`#a7f070`, sky `#73eff7`.
- **Dirt cells are 4x4 px** (field 240x80 cells). Each cell's look is picked
  procedurally from its depth band plus a hashed 4x4 texture pattern (pebble,
  crumb, plain), with a 1 px darker edge where a cell borders a tunnel.

Assets (all text grids in `art_src/` rendered by `tools/sprites.py`, unless
noted):

| name | size | frames | how |
|---|---|---|---|
| digger | 32x24 | 4 | grid: drive bob x2, dig shake x2 |
| scoop_arm | 16x8 | 1 | grid; rotated by 90-degree steps in code |
| dump_truck | 48x24 | 3 | grid: empty, half, full |
| treasure_chest, crown, dino_egg, gems, coins, toy_robot | 16x16 | 2 | grid: idle, glint |
| worm, snail, bone, fossil, mole | 16x16 | 2 | grid |
| glint | 8x8 | 4 | grid |
| dirt_chunk | 4x4 | 4 | grid, one colour band per frame (particles) |
| boom_ring | 64x64 | 5 | generator script (circles in the grid format), then renderer |
| grass_strip | 320x16 | 1 | grid, tiles horizontally |
| sky_hills | 320x48 | 1 | reuse PixelPals `hills` recoloured |
| dirt textures | 4x4 | 6 | grid; stamped into the terrain Image in code |
| riders, icons, confetti, trophy, check, arrows | as PixelPals | | copied from PixelPals |

Everything is drawn by us: the model writes grids and generators, the
renderer and lint guarantee the palette. No external art tool is needed;
Pixelorama (10k stars) is fine for hand touch-ups if the grid is updated too.

## Audio

Synthesized by our synth (`tools/sfx.py` pattern, seeded, -15 LUFS SFX):
`dig_1..3` (crunchy filtered noise bursts), `scoop` (noise + low thump),
`boom` (sub-bass drop + noise tail, soft attack so it is big but not
startling), `puff`, `donk`, `glint` (tiny sine arpeggio), `treasure_pop`
(rising square arp), `truck_clunk`, `worm_squeak`, `mole_hello`, `join`,
`select`, `ready`, `party`. Music: `music_menu` and `music_dig`, a bouncy
loop in C major around 110 BPM; the dig loop ducks by 4 dB during a boom.

## Reuse

- **shared/**: `players.gd` (seats, blocks, `demo:<n>`), `art.gd` (sprites
  with placeholder fallback), `sfx.gd`, `tools/shots.py`.
- **From PixelPals**: `game_state.gd` screen router, join/select/party
  screens, `demo_driver.gd`, `tools/sprites.py`, `tools/sfx.py`, the Makefile.
- **Extract to shared first** (whichever of the next games is built first
  does it): `tools/sprites.py` → `shared/tools/sprites.py` taking the game
  root as an argument; the synth core of `tools/sfx.py` →
  `shared/tools/synth.py`; the join/select/party screens → `shared/godot/
  screens/` parametrised by role icons; generic seat names (`Seat.ADULT`,
  `Seat.KID`, `Seat.TODDLER` aliases of the current `DRIVER/GUNNER/HONKER`).
- **New and later shareable**: `terrain_grid.gd` (useful again for any
  digging or painting game, e.g. Paint Party).

## New tech this game needs

- **Destructible dirt grid**: `PackedByteArray` of 240x80 cells (0 = air,
  1-3 = dirt bands, 9 = rock), pure logic in `terrain_grid.gd` with
  `dig_circle(center, r)`, `dig_rect`, `is_solid(cell)`,
  `exposed(cells) -> bool`. Rendering: one `Image` (960x320, FORMAT_RGBA8)
  shown through an `ImageTexture`; a dig repaints only the touched cells and
  calls `texture.update(image)` once per frame (dirty-rect batching).
- **Digger movement against the grid**: a simple AABB-vs-cell sweep in code,
  not physics bodies (no collision shapes to rebuild on every dig).
- **Treasure glint** through dirt: distance-based brightness plus a sparkle
  sprite drawn above the terrain.
- **Particles**: `CPUParticles2D` with the `dirt_chunk` texture (GPU particles
  are pointless at this size).
- **Risks for Claude-built Godot**:
  - Godot 3 drift: `Image.lock()/unlock()` and `ImageTexture.create_from_image`
    as an instance method are Godot 3; in 4.x use `ImageTexture.create_from_image`
    (static) plus `ImageTexture.update(image)`. For custom `_draw` redraws,
    CanvasItem `update()` is Godot 3; 4.x uses `queue_redraw()`.
  - `.tscn` breakage: keep the single `main.tscn` shell, build everything in
    code.
  - Headless renders nothing: the grid logic is tested headless; the terrain
    look is only verified through `make shot` frames under xvfb.
  - Performance: repainting the whole Image per dig would stutter; test the
    dirty-rect path with a boom every frame in a stress test.

## MVP scope

One field (3x2 screens), 12 treasures, 5 small-find types, one digger, about
5 minutes. No level select, no extra fields.

**M1 grey box**
- [ ] `games/digger-treasure/` scaffold: Makefile (start, demo, test, shot,
      shots, sprites, sfx, tmux trio), `project.godot` pixel-perfect,
      symlinked shared autoloads.
- [ ] `terrain_grid.gd` with tests; terrain drawn as flat band colours.
- [ ] Digger as a rectangle driving and auto-digging; scoop and boom as
      circles in seat colours; treasures as coloured squares that fly to a
      rectangle truck.
- [ ] 1-, 2- and 3-seat play including auto-boom; run end at 12 or 5 min.
- [ ] Couch test with the kids on the grey box: is the scoop direction
      understood? is 1.2 s boom cooldown too long for the 2-year-old?

**M2 art and audio**
- [ ] All sprites above as grids, lint clean, contact sheet reviewed at 8x.
- [ ] Textured dirt cells and tunnel edges; glint; particles.
- [ ] All SFX and both loops synthesized and measured.
- [ ] Party screen with the truck tipping out the treasures.

**M3 polish and couch test**
- [ ] Camera leads slightly toward the nearest unfound treasure.
- [ ] Rumble on pads for boom (weak motor, 150 ms).
- [ ] Balance the glint radius after watching the 5-year-old play.
- [ ] Second couch session; record lessons in the skill's field notes.

## Tests and verification

GUT (`game/tests/`):
- `test_dig_circle_clears_only_cells_inside_the_radius`
- `test_rock_cells_are_never_dug`
- `test_digger_cannot_leave_the_field`
- `test_stuck_digger_gets_a_free_space_after_two_seconds`
- `test_treasure_is_found_when_any_cell_is_exposed`
- `test_boom_from_the_toddler_never_moves_or_hurts_the_digger`
- `test_boom_cooldown_still_answers_every_press_with_a_puff`
- `test_auto_boom_runs_when_seat_three_is_empty`
- `test_run_ends_with_every_treasure_in_the_truck` (including the 5 min
  fountain path)
- `test_scoop_direction_is_one_of_four`
- plus the reused `test_players`, `test_join`, `test_select`, `test_party`.

Demo driver (`scripts/demo_driver.gd`, `make shot SHOT_SCREEN=dig`): seat
three `demo:` devices; the driver follows a scripted path toward the three
nearest glints; the scooper aims down then right and scoops every 1.5 s; the
boomer presses at 2 s, 5 s and 6 s. `DEMO_RUN_SECONDS := 20`, treasures
placed near the start in demo so pops happen on camera.

In the frames (`shots/dig/sheet.png`, upscaled): tunnel edges are crisp 4 px
steps (no half cells), dirt bands read at a glance, the scoop arm points the
aimed way, the boom ring is round and in green, treasures arc to the truck
and the truck sprite changes fill, no placeholder magenta remains.

## Open questions for Oriol

- Should dirt fall (sand-style) in a later version? It is fun but adds a
  "crushed" feeling; the MVP says no.
- Which treasures do the kids want (dinosaurs? their fan characters as
  buried toys in the private pack)?
- Side view (as planned) or top-down? Side view gives depth bands and "down
  is deeper"; top-down is easier to steer.
- Is an auto-boom every 20 s right when the toddler is absent, or should the
  scooper get it?
