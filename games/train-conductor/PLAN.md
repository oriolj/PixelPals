# Train Conductor

A wooden toy railway seen from above: dad runs the engine, the 5-year-old
throws the points at every junction, the 2-year-old toots the whistle, and
coloured passengers ride home to their matching coloured stations.

Status: playable (2026-09-26)

## Why it fits our family

- **5-year-old (Points):** the route is theirs. At each junction a big
  two-way sign glows ahead of the train; left or right flips the points and
  the track visibly swings over. Every branch leads somewhere fun (a tunnel, a
  bridge over a pond, a farm with cows), and every loop comes back, so there is
  no wrong choice, only different adventures. Later, matching colours to
  stations turns it into a gentle planning game.
- **2-year-old (Whistle):** any press toots the whistle and puffs a steam
  ring. Animals by the track look up and answer (cow moo, duck quack, sheep
  baa), and at a station a press rings the bell and everybody hops on faster.
- **Adult (Engine):** speed and braking. Stopping with the engine inside the
  platform is a small, satisfying timing skill; a perfect stop earns a
  sparkle.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 `Seat.DRIVER` | Engine (adult) | stick up/down or right trigger: throttle; stick down / B: brake; A: horn; start: pause (*built:* stick/d-pad only; the shared `players.gd` folds the right trigger into A, so RT is the horn) | kb:0: W faster, S slower/brake, Shift horn, Esc pause |
| 2 `Seat.GUNNER` | Points (5 y) | stick or d-pad left/right: set next junction; A: open the doors at a station | kb:1: Left/Right points, Enter doors |
| 3 `Seat.HONKER` | Whistle (2 y) | any button | kb:2: Space or any unowned key |

- **1 seat:** points follow a "tour" rule (alternate, prefer the branch with
  a waiting passenger's colour); doors open by themselves 1 s after a stop.
- **2 seats:** the whistle toots by itself at tunnels and stations.
- The train never needs more than these inputs; everything works on one keyboard.

## Core loop

1. The train runs on a looped track graph with 4 stations: red (circle
   hats), blue (square), yellow (triangle), green (star). Colours are paired
   with shapes so they also read for colour-blind players.
2. Passengers wait on platforms wearing the colour of the station they want.
3. The adult brings the train into a platform. Stopped inside the zone:
   doors open (the kid's A, or automatically), passengers for this colour hop
   off and dance into their house; waiting ones hop on. A new carriage couples
   on when the train is full, so the train grows during the run (max 5
   carriages).
4. At junctions the kid picks the branch. A small coloured beacon over each
   branch shows which station lies that way (the next station's colour), so
   a 5-year-old can deliver "the red ones" on purpose.
5. Delivering a passenger: +1 star and a little house on that station's hill
   lights up. Deliver 12 passengers and the town lights up for the finale.

### No-fail rules

- **Overshooting a platform:** the train stops, gives a friendly "beep beep"
  and rolls back into the platform on its own. No penalty.
- **Stopping short:** passengers just walk further along the platform.
- **Wrong branch:** there are no dead ends; the graph is strongly connected
  and every branch rejoins within one screen. The worst case is scenery.
- **No collisions exist:** there is one train. Cows on the track step aside
  on a whistle, or on their own after 2 s; the train only slows down.
- **Too fast into a curve:** the carriages wobble and the passengers go
  "wheee"; nothing derails.
- **Passengers never leave or get angry.** No timer on any passenger.
- **End of run:** 12 deliveries or 6 minutes. Then night falls, every house
  lights up, fireworks over the station, and the train pulls into the depot:
  party. Target session: 4-6 minutes.

## Screens and flow

`join` → `select` → `level` → `party` → `select`.

- **join / select:** shared screens with this game's seat icons: throttle
  lever, junction sign, whistle. Riders sit in the cab (the adult's) and on the
  tender (the kids') and wave.
- **level:** one scrolling map about 3x3 screens; the camera follows the
  engine and zooms out slightly as the train grows.
- **party:** the station at night; each delivered passenger stands on its
  house porch and waves; stars fill the sky; the train toots three times.

## Art direction

**Flat vector, top-down "wooden toy railway"** (Brio-like): rounded
beechwood-coloured track pieces with grooves, chunky painted carriages,
pastel landscape. Vector suits smooth curves, rotation at any angle and a
zooming camera, which pixel art at 320x180 would fight (no free rotation).

- **Canvas:** 1280x720 base, `stretch/mode = "canvas_items"`, aspect keep,
  2D MSAA x4 so Polygon2D edges stay smooth at 1080p and 4K.
  *Deviation:* Godot 4.7 has no 2D MSAA in the Compatibility renderer (it
  warns and ignores it); edges are smoothed with antialiased outline
  polylines instead, and the shapes are `draw_*` calls rather than Polygon2D nodes.
- **Palette (fixed list in `palette.gd`):** track wood `#d9a066`, groove
  `#8f563b`, grass `#99e550`/`#6abe30`, water `#5fcde4`, station colours red
  `#e43b44`, blue `#3978a8`, yellow `#feae34`, green `#3e8948`, ink outline
  `#2a2135` (2 px on every shape, for a toy look).
- **How it is made:** everything is procedural Godot drawing in code. Track
  pieces are generated by offsetting the `Curve2D` of each edge to two rails
  plus sleepers; shapes are `Polygon2D` built from helper functions
  (`rounded_rect`, `circle`, `star`) and `_draw()` for dynamic bits. No
  external art at all.

Asset list:

| Asset | Made of | Size (px at 1280x720) |
|---|---|---|
| Track (straight, curve, junction, crossing) | rails from `Curve2D` offsets, sleepers every 24 px, `_draw` | 48 wide |
| Points lever + sign | rounded rect + big arrow polygon, tweened swing | 64x64 |
| Branch beacons | circle/square/triangle/star shapes in the station colour, pulsing | 28 |
| Engine (red, with chimney, cab, face) | Polygon2D stack, 2 frames of piston offsets | 96x56 |
| Carriages (4 colours) + tender | rounded rect body, windows showing riders | 72x48 |
| Passengers (4 colours x hat shape) | circle body + hat polygon + dot eyes; hop tween | 20x28 |
| Stations (4) + platform | roof polygon, coloured awning stripes, clock face without numbers | 160x96 |
| Houses on the hills | square + triangle roof, window lights toggle | 40x40 |
| Tunnel, bridge, pond, trees, fences | polygons; tunnel dims the train with a CanvasModulate zone | various |
| Animals: cow, duck, sheep | circles and ellipses, 2-pose look-up animation | 48 |
| Steam puffs and rings | circles with alpha fade, CPUParticles2D | 12-40 |
| Riders on the train | shared cast PNGs (pixel) scaled x3 nearest, framed in a round window | 48 |

*Deviations:* the map has no track-on-track crossing, so "crossing" is the
farm road's level crossing; the engine is 112x52 and the tender 100 long so
the x3 riders fit; passengers are drawn front-on (~26x44) so kids read them.
| HUD icons (stars, delivery pips) | same vector helpers | 32 |

## Audio

Synthesized by the shared synth (`shared/tools/synth.py` once extracted):

- `whistle_1..3`: two-note steam whistle (sine + noise breath, different
  intervals); `whistle_long` for tunnels.
- `chuff_loop`: filtered noise pulses; the loop's playback rate follows speed.
- `brake_squeal`, `beep_beep` (roll back), `horn`.
- `points_clack`: wooden clack when the points swing (the kid's feedback).
- `doors_open`, `bell` (ding-ding), `hop_1..3` (boarding blips, rising).
- `deliver`: happy three-note arpeggio in the station's own key
  (red C, blue E, yellow G, green A), so each colour has its sound.
- `moo`, `quack`, `baa`: formant-ish synth glides (cute, not realistic).
- `couple`: carriage coupling clunk; `perfect_stop` sparkle.
- Music: `music_rails` (160 bpm "chugga" rhythm on noise + ukulele-like
  plucked triangle), `music_night` for the finale.

## Reuse

- **From shared/:** `players.gd`, `sfx.gd`, `art.gd` (only for the rider PNGs
  and the private pack), `shots.py`.
- **From PixelPals:** the flow and demo arguments of `game_state.gd`, the demo
  driver pattern, join/select/party screens, the synth.
- **Extract into shared/ first:** the screens and synth (see Fire Truck
  Rescue's list, whichever game starts first does it); plus a new
  `shared/godot/vector/shapes.gd` (rounded rect, star, outline helpers) that
  Tractor Farm will also use.

## New tech this game needs

- **Track graph and path following:** a data file (`track.gd` constant) of
  nodes and edges; each edge is a `Curve2D`; the engine keeps
  `(edge, distance)` and advances by speed; carriages sample the same path at
  fixed arc-length gaps behind, crossing edge boundaries through the history of
  edges travelled. No `PathFollow2D` (it cannot cross edges on its own).
- **Junction logic:** each junction stores a `choice` flipped by the kid; the
  choice for the *next* junction ahead is the one shown and changed; it locks
  1 s before the engine reaches it (the sign flashes to show it is locked).
- **Station stop detection** with a tolerance window and auto roll-back.
- **Camera:** Camera2D following with look-ahead and zoom driven by train
  length.
- **Risks for Claude-built Godot:** Godot 3 APIs (`update()` instead of
  `queue_redraw()`, `Curve2D.interpolate_baked` is now `sample_baked`),
  Polygon2D winding and self-intersecting offsets on tight curves (test the
  generator), `.tscn` hand edits (build in code), headless renders nothing
  (capture under xvfb with `gl_compatibility`; MSAA 2D must be enabled in that
  renderer too).

## MVP scope

One map (about 3x3 screens) with 4 stations, 3 junctions, a tunnel, a
bridge, 3 animal spots; 12 passengers over the run. About 5 minutes.

### M1 grey-box

- [x] Shared extraction done (or reuse Fire Truck's if it came first).
      *Deviation:* agents could not edit `shared/` while 11 games were being
      built, so the screens, synth (`tools/sfx.py`), sprite renderer and
      `scripts/vector/shapes.gd` are local copies; the proposed shared diff
      is in the build report and CLAUDE.md "Local copies".
- [x] Track graph with plain lines; engine and 3 carriages following it.
      (Went straight to the wooden track; carriages 1..5.)
- [x] Throttle/brake, platform zone, roll-back on overshoot.
- [x] Junction choice + lock + visible sign; tour rule for 1 seat.
      The points seat flicks toward the branch *on screen* (any direction
      across both branches toggles), so "left" never means train-relative left.
- [x] Passenger boarding/delivery by colour, carriage coupling.
      2 seats per carriage, starting with 1 carriage, max 5.
- [x] Whistle, animals stepping aside; run end and party.
- [x] Demo driver plays a full run; couch test with plain shapes.
      Demo verified by test and captures; the couch test itself is pending
      Oriol (no grey-box phase was built: the art came in the first pass).

### M2 art/audio

- [x] Wooden track generator with sleepers and grooves; stations, houses,
      scenery; engine face and carriage windows with riders.
- [x] Night finale lighting (CanvasModulate + house window lights).
      Lights and fireworks sit on a camera-following CanvasLayer outside the
      night tint. The train rolls into the next platform (no separate depot).
- [x] All sounds and both music loops; per-station delivery chimes.
      Plus `music_menu`, `wheee`, `firework` and the menu blips. Needs a human listen.

### M3 polish/couch test

- [x] Check the kid can predict which way the train will go (sign readability).
      Checked in captures: the next sign glows and grows, its arrow points
      along the chosen branch, the blade swings, beacons pulse. A real
      5-year-old check is pending Oriol.
- [x] Tune the platform zone width until dad hits perfect stops about half the time.
      Tuned by simulation: docking window -300..+60 px, perfect ±35 px gives
      ~55% perfect stops for a ±0.3 s braking error. Confirm on the couch.
- [x] Three couch sessions; export and clean-clone run.
      Export (`make export-linux`) and the clean-clone test + capture pass.
      The three couch sessions are Oriol's to run (pending).

## Tests and verification

GUT tests:

- `test_engine_advances_along_edge_by_speed`
- `test_carriages_follow_across_junction_edges`
- `test_track_graph_is_strongly_connected_no_dead_ends`
- `test_points_flip_only_by_points_seat_and_lock_before_junction`
- `test_overshoot_rolls_back_into_platform`
- `test_passenger_boards_and_leaves_at_matching_colour_only`
- `test_train_grows_to_max_five_carriages`
- `test_cow_steps_aside_on_whistle_and_train_never_stops_forever`
- `test_one_seat_tour_rule_prefers_waiting_colour`
- `test_run_ends_at_twelve_deliveries_or_six_minutes`
- `test_polygon_offsets_do_not_self_intersect_on_tightest_curve`

Demo driver (`--demo=level`): the engine throttles to cruise and brakes when
the distance to the next platform drops below the braking curve; the points
seat flips toward the beacon colour matching the oldest passenger aboard; the
whistle seat presses every 3 s and at every station. `make shot
SHOT_SCREEN=level SHOT_SECONDS=45`.

In the frames, look at: the points sign flips before the train reaches the
junction and the train then takes that branch; carriages stay on the rails
through curves (no cutting corners); passenger colours and hat shapes are
distinct at 1x; the train grows; nothing text-like appears; the night finale
is not too dark to read.

## Open questions for Oriol

1. Top-down wooden railway (plan), or a side view like a picture book?
2. Should the kid's choice be one junction ahead (plan), or every junction on
   the map toggleable by moving a cursor (harder, more planning)?
3. Real station names or colours only? (Plan: colours + shapes, no text.)
4. Carriages carrying the riders from the select screen, or does each kid
   pick "their" carriage colour?
5. Later: a 2-player mode where the 5-year-old drives and dad throws points?

## Decisions taken (pending Oriol)

Defaults chosen while building (2026-09-26); change any of them on the couch.

1. **View:** top-down wooden railway, as planned.
2. **Points:** one junction ahead only (the next one glows; it locks 1 s
   before the engine). The kid flicks toward the branch as seen on screen.
3. **Station names:** colours + shapes only, no text.
4. **Riders:** the select-screen riders ride the train (driver in the cab,
   kids on the tender); carriages have fixed colours and carry passengers.
5. **Later 2-player swap (kid drives):** not built; the seats map to roles
   in one place (`level.gd read_input()`), so a swap is a small change.
6. Tuning: 2 passengers per carriage, 1 to 5 carriages, max speed 300 px/s,
   up to 10 waiting passengers, one new every 12 s; the cow waits 2 s.
7. Right trigger: horn (shared input folds it into A), throttle is the stick.
8. The finale ends at the next platform instead of a separate depot.
