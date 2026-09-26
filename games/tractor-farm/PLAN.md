# Tractor Farm

Plough, plant, rain and harvest one sunny field together: dad drives the
tractor, the 5-year-old picks the seeds, the 2-year-old is the rain cloud that
makes everything grow while you watch.

Status: plan (2026-09-26)

## Why it fits our family

- **2-year-old (Rain cloud):** pure cause and effect. Any press makes the
  smiling cloud above the tractor rain, and the plants under it pop up one
  size with a boing. Nothing planted underneath? Puddles appear and a duck or
  a frog jumps in. It is the most visible power in the game.
- **5-year-old (Seeds):** choosing. Four big seed bags (carrot, pumpkin,
  sunflower, strawberry) sit on the planter behind the tractor; a direction
  picks one, and that crop is sown along the path. Kids get to design the
  field ("all pumpkins!", "a rainbow row") and learn the vegetables.
- **Adult (Tractor):** driving neat rows, turning at the headlands, then
  harvesting and delivering to the barn. Easy to play relaxed, satisfying to
  play tidy.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 `Seat.DRIVER` | Tractor (adult) | left stick: drive (tractor turns toward the stick direction); A: horn / tip the trailer at the barn; start: pause | kb:0: WASD drive, Shift horn/tip, Esc pause |
| 2 `Seat.GUNNER` | Seeds (5 y) | d-pad or stick: up carrot, right pumpkin, down sunflower, left strawberry; A: toggle planter on/off | kb:1: arrows pick seed, Enter planter on/off |
| 3 `Seat.HONKER` | Rain cloud (2 y) | any button | kb:2: Space or any unowned key |

- **1 seat:** the planter cycles seeds by itself each row, and the cloud
  rains on its own every 4 s over planted soil.
- **2 seats:** the cloud rains by itself more slowly (every 6 s) so crops
  still grow.
- The four seed directions are shown as a plus-shaped picker with the vegetable
  drawn in each arm, so the mapping is visible, not memorised.

## Core loop

The field is a 16x9 grid of 64 px tiles. Each tile goes:

`grass → ploughed → seeded(crop) → sprout → growing → ripe → (harvested) → ploughed`

1. **Plough:** the tractor's plough turns any grass tile it crosses into
   furrows (automatic, no button).
2. **Plant:** when the planter is on, ploughed tiles it crosses get the kid's
   current seed; a tiny seed-bag icon hops off onto the soil.
3. **Rain:** each toddler press rains for 1.2 s in a circle of radius 1.5
   tiles under the cloud; every seeded or growing tile under it advances one
   stage. The cloud hovers over the tractor, slightly behind, so dad's route
   decides where the rain lands.
4. **Sun:** plants also grow one stage every 20 s on their own, so a field
   is never stuck without the toddler.
5. **Harvest:** driving over a ripe tile pops the crop into the trailer (it
   bounces in; the trailer visibly fills, 24 crops max). Tip it at the barn
   (A, or just park 2 s): crops tumble into the barn's crates by type.
6. A few times per run an animal visitor arrives (bunny, pig, hen): it
   nibbles one ripe crop, does a happy dance and leaves a heart. It is a
   visitor, not a thief: no loss counters.

### No-fail rules

- Driving over sprouts never crushes them: the tractor's wheels hop, the
  sprout wobbles and springs back.
- Planting over a seeded tile replaces nothing (the first seed stays), so
  a jittery kid cannot undo work.
- Rain on empty ground makes puddles and a duck; rain on ripe crops makes
  them sparkle. There is no over-watering.
- The tractor cannot leave the farm (fences bounce softly) and cannot tip.
- There is no clock the kids can see; nothing wilts.
- **End of run:** when the barn has 30 crops, or at 6 minutes, a giant
  vegetable grows in the middle of the field (of the most-planted type) with
  a big rain press or automatically, and the tractor carries it to the fair:
  party. Target session: 5-6 minutes.

## Screens and flow

`join` → `select` → `level` → `party` → `select`.

- **join / select:** shared screens; seat icons are steering wheel, seed bag,
  cloud. The chosen riders appear as the tractor driver and two farmhands
  riding on the trailer.
- **level:** the whole field fits one screen (no scrolling), so the toddler
  always sees the cloud and every plant.
- **party:** the village fair: the barn crates as a bar chart made of real
  vegetables (4 stacks), the giant vegetable on a podium with a rosette,
  confetti, the animals dancing.

## Art direction

**Flat vector, picture-book farm** (soft shapes, 2 px ink outlines, no
gradients except the sky). Vector because growing plants read best as smooth
scale-and-squash tweens, and the field benefits from crisp big shapes on a TV.
It shares its helpers with Train Conductor.

- **Canvas:** 1280x720 base, `canvas_items` stretch, MSAA 2D x4.
- **Palette:** soil `#8f563b` / furrows `#663931`, grass `#6abe30`, sky
  `#cbdbfc` → `#5fcde4`, carrot `#df7126`, pumpkin `#fbb23b`, sunflower
  `#fbf236` with `#663931` centre, strawberry `#d95763`, leaves `#37946e`,
  tractor green `#4b692f` with yellow `#fbf236` wheels, ink `#222034`.
- **How it is made:** procedural drawing in code: `Polygon2D` shapes from
  `shared/godot/vector/shapes.gd`, the field tiles drawn in one `_draw()`
  pass (fast, no TileMap resources), a CanvasItem shader for the wind sway of
  grown plants (vertex offset by `sin(TIME + world_x)` weighted by height),
  CPUParticles2D for rain and dirt.

Asset list:

| Asset | Made of | Size (px) |
|---|---|---|
| Field tile states (grass, furrows, seeded, wet) | `_draw` rects + furrow lines; wet = darker soil overlay | 64x64 |
| Crops x4, 4 stages each (seed, sprout, growing, ripe) | polygons: leaves, carrot top + orange tip, pumpkin ellipses, sunflower petals ring, strawberry heart with seed dots | 16-64 |
| Tractor (body, cab, big back wheels, exhaust) | Polygon2D + rotating wheel spokes | 120x80 |
| Plough + planter hitch with 4 seed bags | polygons; the chosen bag lifts and glows | 64x40 |
| Trailer with fill level | rect + stacked mini crops | 80x48 |
| Rain cloud with face (idle, raining, happy) | overlapping circles + eyes; raindrop CPUParticles2D | 120x72 |
| Rainbow (after 5 quick presses) | arc bands via `draw_arc` | 400 wide |
| Barn + crates, fence, trees, pond | polygons | various |
| Animals: bunny, pig, hen, duck, frog | circle-based characters, 2-pose hop | 40-56 |
| Seed picker (plus shape, 4 vegetables) | HUD CanvasLayer, same crop drawings | 160x160 |
| Giant vegetable (party) | ripe crop drawing scaled x6 with shine | 384 |
| Riders | shared cast PNGs, x3 nearest, in the cab / on the trailer | 48 |

## Audio

Synthesized by the shared synth:

- `engine_loop`: putt-putt tractor (low square pulses, pitch by speed).
- `plough`: soft dirt crunch noise loop while ploughing.
- `seed_pick_1..4`: one pitched blip per vegetable (the kid hears their pick).
- `plant`: tiny "pip" when a seed drops.
- `rain_loop` (filtered noise) and `rain_start` (pitter-patter swell).
- `grow_1..3`: rising boings with bright plucks (each stage higher).
- `ripe`: sparkle; `harvest_pop`; `trailer_tip` (tumbling thuds); `crate`.
- `quack`, `ribbit`, `oink`, `cluck`, `bunny_boing`.
- `rainbow`: harp-like upward glissando; `giant_grow`: long rising swell.
- `horn` (tractor honk), `join`, `select`, `ready`.
- Music: `music_farm` (relaxed 96 bpm, plucked triangle + "fiddle" saw lead),
  `music_fair` for the party.

## Reuse

- **From shared/:** `players.gd`, `sfx.gd`, `art.gd` (riders only), `shots.py`.
- **From PixelPals:** flow/demo args, demo driver pattern, the three screens,
  the synth.
- **From Train Conductor (or extracted by whichever vector game is first):**
  `shared/godot/vector/shapes.gd` and a `vector_palette.gd` pattern.
- **Extract into shared/ because of this game:** a small `grid_field.gd`
  (tile states + `_draw`) could serve Digger Treasure and Paint Party later;
  keep it in the game until a second user exists.

## New tech this game needs

- **Tile state machine** with timers and per-tile growth, stored as a
  `PackedInt32Array` for speed and easy testing (logic separate from drawing:
  `field_rules.gd` with no nodes).
- **Tractor steering:** turn-toward-stick with a max turn rate, and a
  footprint polygon (plough width = 1 tile, planter trailing 1 tile behind)
  mapped to grid cells each frame.
- **Cloud follow** with lag and a rain footprint circle to cells.
- **Wind sway shader** (CanvasItem `shader_type canvas_item;`).
- **Risks for Claude-built Godot:** Godot 3 drift (`update()`, `yield`,
  `export var`, old shader keywords like `WORLD_MATRIX`); TileMap/TileSet
  `.tres` resources are brittle to author by hand, hence our own `_draw`
  grid; particle `emitting` restarts differ from Godot 3; headless renders
  nothing (capture under xvfb, `gl_compatibility`).

## MVP scope

One field (16x9 tiles), 4 crops, barn, 3 animal visitors, the rain cloud,
the giant-vegetable finale. About 5-6 minutes.

### M1 grey-box

- [ ] Shared screens/synth/vector helpers available.
- [ ] `field_rules.gd` with states, growth timers, rain, harvest; tested headless.
- [ ] Tractor as a rectangle ploughing and planting coloured squares.
- [ ] Cloud rains on any press; auto-rain for fewer seats.
- [ ] Trailer, barn tip, run end, party with 4 coloured stacks.
- [ ] Demo driver runs a whole season; couch test in grey.

### M2 art/audio

- [ ] Crop drawings for all 16 stages checked on a contact sheet at 1x and 2x.
- [ ] Tractor, cloud faces, animals, barn, rainbow; sway shader.
- [ ] All sounds and both music loops, levels measured.

### M3 polish/couch test

- [ ] Growth pop timing: every rain press shows a change within 3 frames.
- [ ] Check the seed picker is understood by the 5-year-old without words.
- [ ] Three couch sessions; export and clean-clone run.

## Tests and verification

GUT tests:

- `test_plough_turns_grass_to_furrows_under_footprint`
- `test_planter_seeds_only_ploughed_tiles_with_current_seed`
- `test_replanting_a_seeded_tile_keeps_the_first_seed`
- `test_rain_advances_tiles_in_radius_by_one_stage`
- `test_rain_on_empty_soil_makes_a_puddle_never_harm`
- `test_sun_growth_advances_without_rain`
- `test_driving_over_sprouts_never_destroys_them`
- `test_harvest_moves_ripe_crop_to_trailer_and_resets_tile`
- `test_trailer_caps_at_24_and_tips_at_barn`
- `test_seed_directions_map_to_four_crops`
- `test_only_cloud_seat_rains_with_cooldown`
- `test_run_ends_at_thirty_crops_or_six_minutes`

Demo driver (`--demo=level`): the tractor drives a boustrophedon pattern (row
by row, turning at the fence) for the first 90 s, then sweeps for ripe tiles
and tips at the barn; the seed seat changes seed every row (carrot, pumpkin,
sunflower, strawberry); the cloud seat presses every 1.5 s. `make shot
SHOT_SCREEN=level SHOT_SECONDS=60`.

In the frames, look at: furrows follow the tractor path exactly; four crops
distinct at 1x and in silhouette; plants under the cloud are visibly taller
than the rest after a press; the trailer fill level rises; no plant is drawn
over the tractor wrongly (z-order); the party stacks match the barn counts.

## Open questions for Oriol

1. Which four crops? Kids may prefer what they eat (tomato, apple tree,
   corn...).
2. Should the field persist between sessions (a farm that grows over a week)?
3. Top-down (plan) or 3/4 view with a bit of height?
4. Animal visitors: fine as friendly nibblers, or would the 5-year-old be
   upset seeing a crop eaten? (Alternative: they only eat what falls off.)
5. Should the 2-year-old also get a sun button (alternating rain and sun)?
