# Fire Truck Rescue

A chunky low-poly toy town where the family crews one fire truck: dad drives, the
5-year-old sprays the hose, the 2-year-old runs the siren and the big ladder.

Status: plan (2026-09-26)

## Why it fits our family

- **5-year-old (Hose):** a real job with visible results. Point the hose (4
  directions), hold the button, and a fire shrinks, hisses and turns into a
  puff of white steam and a thank-you wave. Aim assist bends the water arc onto
  the nearest fire in the chosen quadrant, so "roughly right" always works.
- **2-year-old (Siren):** the loudest, most toy-like job. Any press starts the
  siren and the roof lights, cars pull over, a dog barks along, and when the
  truck is parked by a tree the ladder rises and a cat climbs down into the
  cab. The toddler is the one who rescues the cats, which is the big moment.
- **Adult (Driver):** real steering in a small town with corners, a roundabout
  and a bridge. The challenge is parking the truck where both kids can do
  their part, which is a nice cooperative puzzle for a grown-up.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 `Seat.DRIVER` | Driver (adult) | left stick: steer and throttle (up = forward relative to the camera); A: horn; start: pause | kb:0: WASD steer, Shift horn, Esc pause |
| 2 `Seat.GUNNER` | Hose (5 y) | stick or d-pad: aim hose in 4 screen directions; hold A: spray | kb:1: arrows aim, hold Enter spray |
| 3 `Seat.HONKER` | Siren (2 y) | any button | kb:2: Space or any unowned key |

- **1 seat:** the hose auto-aims and auto-sprays whenever a fire is within
  range and the truck is slow; the ladder rises by itself when parked near a
  cat tree. Dad can finish the town alone.
- **2 seats:** the siren plays by itself when the truck leaves the station and
  the ladder auto-rises; the kid still owns the hose.
- **Keyboard only:** one keyboard covers all three seats with the shared
  blocks; nothing needs a pad.

## Core loop

1. A fire appears (a house, a bin, a haystack at the edge of town). A big
   floating flame icon and a pulsing ring on the minimap-free ground arrow
   show where it is; smoke rises high enough to be seen from anywhere.
2. The driver drives there. The siren seat sounds the siren on the way (cars
   slide to the kerb, pedestrians wave).
3. Within about 6 m and below walking speed, the hose is live. The kid aims
   and sprays; each fire has 3 sizes and shrinks one size per ~1.5 s of water.
4. Out: steam puff, a townsperson pops out and waves, 3 stars fly into the
   truck's star bucket. A cat stuck in a nearby tree meows; park under it and
   the toddler's press raises the ladder: the cat rides down, +1 cat badge.
5. Next fire. The MVP town has 6 fires and 3 cats.

### No-fail rules

- Fires never spread and never destroy anything. An unattended fire only gets
  a bit bigger (to size 3 at most) and more cartoonishly smoky.
- The hose never runs dry. A hydrant at each block gives a 5-second
  "super spray" (wider arc, rainbow in the mist) if the truck brushes it.
- Crashing into walls, trees or cars: soft bounce, a "boing", a wobble, a
  leaf or two fall. No damage, no stars lost, no timer penalty.
- The truck can never get stuck: if it has not moved 1 m in 3 s while
  pressing throttle, it gently lifts (little puff) and re-sets on the nearest
  road centre facing along the road.
- Spraying people, cars or the station gives a giggle and a sparkle, not a
  scolding. Spraying the toddler's cat tree makes the cat shake off water.
- **End of run:** when every fire is out and every cat is down (or at 6
  minutes, whichever first), the sky goes sunset orange, the station doors
  open and a big arrow leads home. Parking inside the station starts the
  party. Target session: 4-6 minutes.

## Screens and flow

`join` → `select` → `level` → `party` → `select`, the same as PixelPals.

- **join / select:** reused (after extraction, see Reuse). Seat icons become
  steering wheel, hose nozzle, siren light. Riders are the shared cast
  (penguin, monkey, fox, frog, robot, plus the private pack) wearing a helmet.
- **level:** the town. A small 3D "Hud" CanvasLayer shows only icons: star
  bucket with a pip counter, cat badges, and remaining fires as flame pips.
- **party:** reused; the truck parks in the station, the crew stands on the
  bumper, stars rain in, cat badges line up, a trophy helmet spins.

## Art direction

**Low-poly 3D, flat-shaded, toy-like** (think wooden toy town / Lego Duplo),
because fire trucks, ladders and water arcs read far better in 3D and a
chase camera makes steering intuitive for dad. It is also our first 3D game,
which is a useful technical step for the monorepo.

- **Resolution:** render the 3D world in a `SubViewport` at 480x270, shown
  with nearest filtering and integer scaling (x4 to 1080p). The low-res
  render hides flat-shaded edges and keeps the look chunky and consistent
  with PixelPals. The HUD overlays at the same 480x270 in pixel art.
- **Renderer:** `gl_compatibility`, like PixelPals, so xvfb capture works.
- **Palette:** the Sweetie 16 hues applied as vertex colours / flat
  `StandardMaterial3D` (unshaded = false, roughness 1, no textures): truck red
  `#b13e53`, water blue `#41a6f6`, grass `#38b764`, roofs `#ef7d57`,
  walls `#f4f4f4`, road `#566c86`, shadows by a single directional light.
- **Camera:** fixed-pitch chase camera, 55 degrees down, lagging behind the
  truck; no player camera control. It pulls back slightly while spraying so
  the fire and the truck both fit.

Asset list (all built in GDScript from primitives, no model files, no `.tscn`):

| Asset | Made of | Size (m) |
|---|---|---|
| Truck body, cab, bumper, wheels | BoxMesh, CylinderMesh, grouped Node3D | 2.2 x 1.4 x 4.5 |
| Ladder (3 segments, telescopes) | thin BoxMesh rails + rungs, tweened | 1-6 long |
| Hose nozzle + water arc | CylinderMesh nozzle; arc = CPUParticles3D droplets + a curved `ImmediateMesh` ribbon | range 6 |
| Roof light bar (blue/red) | 2 small BoxMesh + OmniLight3D toggled | 0.3 |
| Houses (4 variants) | box body + prism roof (`PrismMesh`) + door/window boxes; seeded colour | 4-6 |
| Trees (round + pine) | cylinder trunk + sphere / cone canopy | 3-5 |
| Fire (3 sizes) | 3 stacked `PrismMesh` flames with a vertex-wobble shader, orange/yellow; face decals as a 16x16 pixel sprite | 0.8-2.5 |
| Smoke / steam | CPUParticles3D, billboard quads, soft grey / white | - |
| Cat | Sprite3D billboard, 16x16 pixel sprite from a grid (reused pipeline) | 0.6 |
| Townsfolk | Sprite3D billboards of the shared cast | 1 |
| Cars (2 colours) | box + 4 cylinders, follow a Path3D loop | 2 x 3.5 |
| Hydrant | cylinder + sphere cap | 0.8 |
| Road tiles, pavement, grass | PlaneMesh / BoxMesh strips on a 10 m grid | 10 x 10 |
| Station | big box with an animated door (BoxMesh sliding up) | 12 x 10 |
| HUD icons: star bucket, cat badge, flame pip, seat icons | text grids → `sprites.py` → PNG (Sweetie 16) | 16x16 |

A `town_gen.gd` places everything from a hand-written ASCII map in code
(`# = road`, `h = house`, `t = tree`, `F = fire spot`, `C = cat tree`,
`S = station`, `y = hydrant`), so the town layout is diffable text too.

## Audio

Synthesized with our own `sfx.py`-style synth (move the engine into shared
first, see Reuse):

- `siren_1..3`: two-tone wail variants (hi-lo, rising whoop, short yelp).
- `horn`: truck air horn (square + saw, short).
- `engine_loop`: low filtered saw hum, pitch driven by speed in code.
- `spray_loop`: filtered noise hiss; `hiss_out`: noise burst sliding down.
- `fire_crackle_loop`: sparse noise clicks (quiet, cosy, not scary).
- `ladder_up`, `ladder_down`: ratchet clicks rising / falling.
- `meow_1..3`, `purr`: pitched sine glides (cats).
- `boing`: bump; `star`, `badge`, `super_spray`, `ready`, `join`, `select`.
- `bark_1..2`: the dog that barks along with the siren.
- Music: `music_menu` (reuse), `music_town` (bouncy 110 bpm loop, brass-like
  saw lead), `music_party` (reuse `party`).

## Reuse

- **From shared/:** `players.gd` unchanged; `art.gd` for HUD icons and the
  Sprite3D billboards (cat, riders); `sfx.gd`; `shots.py`.
- **From PixelPals:** `game_state.gd` flow and demo args; the demo driver
  pattern (`demo:0..2` scripted seats); join, select and party screens;
  `tools/sprites.py` and the Sweetie 16 palette; `tools/sfx.py` synth.
- **Extract into shared/ first (this game is the second user):**
  - `shared/godot/screens/{join,select,party}.gd` with a per-game config
    (role icons, background builder, party props).
  - `shared/godot/autoload/game_state.gd` base (router, roster, demo args).
  - `shared/tools/synth.py` (the synth engine) with each game keeping only
    its sound list; `shared/tools/sprites.py` taking a game root argument.
  - `shared/make/godot.mk` with setup/ensure-import/test/shot targets.
  - Neutral seat names: add `Seat.ADULT/KID/TODDLER` aliases so games do not
    call the hose seat `GUNNER`.

## New tech this game needs

- **3D in Godot 4:** Camera3D, DirectionalLight3D, meshes built in code, a
  3D SubViewport shown in a 2D pixel canvas.
- **Arcade vehicle:** `CharacterBody3D` with our own speed/steer model (not
  `VehicleBody3D`, whose physics tuning is a time sink). Road "magnetism":
  a gentle steer toward the road centre when no input.
- **Water arc and hit test:** a sampled parabola from the nozzle; fires are
  `Area3D` spheres; aim assist picks the nearest fire within 60 degrees of the
  chosen screen direction (converted to world through the camera basis).
- **Risks for Claude-built Godot:** Godot 3 names (`Spatial`, `KinematicBody`,
  `translation`, `CSGBox` defaults changed); hand-written `.tscn` for 3D
  scenes (do not: build in code); headless renders nothing and Forward+ may
  not start under xvfb (keep `gl_compatibility`); CPUParticles3D only, because
  GPU particles can render blank in captures; Sprite3D needs
  `texture_filter = NEAREST` set per node.

## MVP scope

One town (a 6x6 block grid, about 60 x 60 m), 6 fires, 3 cats, 2 hydrants,
one looping car path, the station. About 5 minutes with three seats.

### M1 grey-box

- [ ] Monorepo extraction above done; PixelPals still passes `make test`.
- [ ] `games/fire-truck-rescue/` with Makefile, CLAUDE.md + AGENTS.md link,
      project.godot (480x270, integer, gl_compatibility).
- [ ] Town from the ASCII map in primitive boxes; truck drives, bounces, unstucks.
- [ ] Hose aim, spray, fire shrink/out; auto-hose with 1 seat.
- [ ] Siren + lights + ladder + cat rescue; auto versions with fewer seats.
- [ ] Run end at all-done or 6 minutes; station parking → party.
- [ ] Demo driver drives a scripted route through all 6 fires.
- [ ] Couch test the grey box: is the hose too easy/hard, does the toddler
      understand the ladder?

### M2 art/audio

- [ ] Houses, trees, truck, fire shader, smoke/steam particles, cars.
- [ ] Cat and HUD icons as grids through `sprites.py`; lint passes.
- [ ] All sounds and `music_town` synthesized; levels measured (-15 LUFS SFX).

### M3 polish/couch test

- [ ] Camera framing while spraying; readable fire arrow from anywhere.
- [ ] Every press answered within 2 frames (siren, hose start, horn).
- [ ] 3 couch sessions; note the toddler's reaction to the siren volume.
- [ ] Export Linux build; runs from a clean clone.

## Tests and verification

GUT tests (`game/tests/`):

- `test_truck_bump_never_damages_or_costs_stars`
- `test_truck_unsticks_after_three_seconds`
- `test_hose_only_live_when_slow_and_in_range`
- `test_aim_assist_picks_nearest_fire_in_quadrant`
- `test_fire_shrinks_one_size_per_spray_interval_and_goes_out`
- `test_unattended_fire_caps_at_size_three`
- `test_siren_any_button_and_cooldown_only_siren_seat`
- `test_ladder_rescues_cat_only_when_parked_near_tree`
- `test_one_seat_auto_hose_and_auto_ladder`
- `test_run_ends_after_all_done_or_six_minutes`
- `test_hydrant_super_spray_lasts_five_seconds`
- Reused: `test_players.gd`, join/select/party tests from the shared screens.

Demo driver (`--demo=level`): seats three `demo:` devices; the driver follows
a precomputed waypoint list to each fire (steer toward the next waypoint,
brake inside 5 m); the hose seat aims `dir4` toward the fire and holds A; the
siren seat presses every 2.5 s and after each park. `make shot
SHOT_SCREEN=level SHOT_SECONDS=40`.

In the frames, check: the truck reads as a fire truck at 480x270 (red, ladder,
light bar); the water arc visibly reaches the flame; the fire arrow is on
screen in every frame; the fire shrinks across frames; the cat descends the
ladder; no z-fighting on roads; no black frames (renderer failure under xvfb).

## Open questions for Oriol

1. Low-res 480x270 chunky 3D, or crisp native 1080p low-poly? (Plan: chunky.)
2. Should the 5-year-old later get the wheel ("kid drives" mode with an
   auto-assisted truck and dad on the hose)?
3. Are cats the right rescue, or should the kids choose (kittens, a duck, a
   Minion from the private pack stuck on a roof)?
4. Is a siren too loud for the 2-year-old? Add a softer "ding-ding" bell
   variant as the default?
5. OK to extract the shared screens and synth before starting (it touches
   PixelPals)?
