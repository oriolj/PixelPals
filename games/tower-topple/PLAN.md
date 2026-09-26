# Tower Topple

Build a wobbly tower of silly blocks together, then the littlest one gets to knock it all down.

Status: playable (2026-09-26)

## Why it fits our family

- **The 5-year-old** drops every block. Timing the drop is a real skill,
  and a generous landing assist means the tower grows, and the praise with
  it. They also choose which shape comes next, so the tower is theirs.
- **The 2-year-old** owns the best moment of the game: the big red button
  that sends the wrecking ball through the tower. Toddlers love knocking
  towers down, and here it is the goal and never a mistake. Between
  knock-downs, every press makes the blocks giggle and bounce their eyes.
- **The adult** does the fiddly part: positioning and rotating the hanging
  block, so the tower gets tall enough for a big crash.

## Roles and controls

Seats fill in join order (`Players.Seat.DRIVER/GUNNER/HONKER`). The keyboard
column is the suggested block. The 5-year-old's seat needs a block with
directions (kb:0, kb:1 or a pad), because kb:2 has no directions.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Builder** (adult): moves the crane hook left/right, rotates the hanging block by 90 degrees | left stick / d-pad X moves the hook, A rotates, Start pauses (B = back, in pause only) | kb:0: A/D move, Shift rotates, Esc pauses, Q back (pause only) |
| 2 | **Dropper** (5-year-old): drops the block; up/down/left/right picks the next shape from a tray of 4 | A drops, d-pad picks the next shape | kb:1: Enter drops, arrows pick the next shape |
| 3 | **Toppler** (2-year-old): any press makes blocks giggle; when the big button is lit, the next press knocks the tower down | any button | kb:2: Space or any unowned key |

With fewer seats, roles fold onto the players who are there:

- **1 seat:** the Builder's A drops (rotation moves to B), and the Builder's
  A on a lit big button topples. The next shape is random.
- **2 seats:** Builder plus Dropper. The Dropper's A on a lit button topples.
- **Dad plus toddler only** is a real case: see the open questions (a way to
  seat a device straight into seat 3).

## Core loop

1. A crane at the top of the screen carries the next block on a hook. The
   Builder slides it over the tower and rotates it.
2. The Dropper presses A: the block falls under real 2D physics and lands.
3. A height line (a rope with little flags) rises with the settled top of
   the tower. Each new flag reached pops stars and plays a rising note.
4. When the tower reaches the cloud line, or after 14 blocks, or after
   100 s, the big button on the toddler's side lights up and pulses.
5. The Toppler presses: the wrecking ball swings in (then an elephant bum,
   a bouncing whale, a rocket boot, cycling per tower). Blocks fly, their
   faces go "whee", confetti bursts, and the crowd of riders cheers.
6. The blocks shrink into the ground; a new tower starts. A run is three
   towers, then the party screen.

### No-fail rules

- **A tower that falls on its own is not a failure.** It plays the same
  crash celebration (smaller), keeps every star already earned, and lights
  the big button at once so the toddler "finishes" it.
- **Missed drops** fall onto a soft ball-pit floor, bounce, sparkle and are
  recycled into the tray. Nothing is lost.
- **Landing assist:** within 20 px of the tower top, the falling block is
  nudged horizontally toward the tower's centre of mass; while settling,
  blocks get high friction (1.0), low bounce (0.05) and extra angular damp
  for 1.5 s. Blocks buried three layers deep freeze (`freeze = true`,
  static) so tall towers do not jitter apart; they unfreeze on the topple.
- **The toddler cannot topple early.** Before the button lights, a press
  is purely cosmetic: no impulse, no physics change.
- **Session:** three towers of about 90 s each plus 10 s of crash, 5-6
  minutes, then the party.

## Screens and flow

`join` → `select` → `play` → `party` → `select`, as in PixelPals.

- **join / select:** the PixelPals screens with new seat icons (hook,
  hand-dropping-block, big red button). Riders are the PixelPals cast plus
  the private pack; they stand on the grass and cheer during play.
- **play:** the building site. Start (Builder only) pauses; in pause, B
  returns to join.
- **party:** the three towers' heights as stacked block icons, the tallest
  one with a trophy; confetti; the riders dance. After 10 s or Builder A it
  goes to select.

## Art direction

**Flat vector, drawn in code.** Physics rotates blocks to any angle, and
rotated pixel art shimmers and breaks the PixelPals "90-degree rotations
only" rule. Flat shapes with thick outlines stay crisp at any angle.

- Canvas 640x360, `stretch/mode="canvas_items"`, `aspect="keep"`,
  `msaa_2d=4x`, no pixel snap. Unit = 32 px.
- Palette: Sweetie 16 hex values used as flat fills (the family colours of
  PixelPals), outline `#1a1c2c` 3 px, sky `#73eff7` to `#41a6f6` gradient.
- How it is made: no PNGs at all except the riders (reused from PixelPals).
  Blocks are `Polygon2D` with a `Line2D` outline; faces (two eyes, a mouth)
  are drawn in `_draw()` and track the wrecking ball. Clouds, crane and
  hills are polygons from point lists in code. Confetti is a
  `CPUParticles2D` with a 4x4 generated texture.

| Asset | Size (px) | How |
|---|---|---|
| block_square | 32x32 | Polygon2D rounded rect (8-point corners), face |
| block_plank | 96x24 | same, 2 eyes at one end |
| block_tall | 24x64 | same |
| block_roof | 64x32 triangle | Polygon2D, eyes in the middle |
| block_arch | 64x40 | polygon with a half-circle cut (16 segments) |
| block_ball | 32 diameter | 24-gon, rolls, only 1 per tower |
| crane + hook | 640x40 rail, 16x24 hook | polygons + Line2D rope |
| big_button | 48x32 | red dome + base, glow = scaled additive copy |
| wrecker_ball, elephant, whale, boot | about 64x64 each | polygon compositions in code |
| height_rope + flags | 8x12 flags | Line2D + triangle polygons |
| ball_pit floor | 640x40 | 60 random circles drawn once in `_draw()` |
| riders | 16x16 x2 frames | reused PixelPals PNGs, scaled x2 (integer) |

## Audio

Synthesized by our own code, a PixelPals `tools/sfx.py`-style script
(`games/tower-topple/tools/sfx.py`, built on the shared synth, see Reuse):

- `drop_1`…`drop_3` (short whistle down), `land_1`…`land_4` (wooden
  clunk, noise burst plus a pitched triangle), `rotate` (click),
  `flag_1`…`flag_8` (a rising C-major-pentatonic bell per height flag),
  `wobble` (creak), `giggle_1`…`giggle_4` (fast vibrato squeaks for the
  toddler's cosmetic press), `button_lit` (a rising chime loop), `swing`
  (whoosh), `crash` (layered thuds plus noise, 1.5 s), `whee` (a slide up),
  `pit_boing`, `cheer` (party horns plus claps), `join`, `select`, `ready`,
  `party`.
- Music: `music_build` (a calm 90 BPM loop, 16 bars) and `music_menu`
  (reused from PixelPals).
- Loudness: the PixelPals targets (SFX about -15 LUFS, peaks under -1 dBFS).

## Reuse

- **From shared/:** `players.gd` (seats, blocks, scripted devices),
  `art.gd` (riders and any PNG), `sfx.gd`, `tools/shots.py`.
- **From PixelPals:** the demo driver pattern (`demo:<n>` devices, a
  `drive(screen, t)` per screen), the join and select screens, the party
  screen's confetti and digit glyphs, the Makefile targets (`ensure-import`,
  `test`, `shot`, `shots`).
- **Extract into shared/ first, because of this game:**
  - `game_state.gd` as a shared router with a per-game screen list and
    results dictionary (PixelPals has `stars` hard-coded).
  - The join/select/party screens, parameterised by seat icons and colours.
  - The synth building blocks of `tools/sfx.py` as `shared/tools/synth.py`.
  - A shared "vector look" helper (`shared/godot/vector.gd`: rounded-rect
    polygon, n-gon, outline) that Garage Band and Paint Party also need.

## New tech this game needs

- **Godot 2D physics:** `RigidBody2D` blocks with `CollisionPolygon2D`,
  `PhysicsMaterial`, contact monitoring for land sounds, sleeping and
  freezing for stability, an impulse for the topple
  (`apply_impulse` from the wrecker's contact point).
- **Tower height measurement:** the highest point of blocks that are
  asleep or slower than 5 px/s for 0.5 s.
- **Body budget:** at most 40 live bodies; the oldest resting ones in the
  ball pit are removed.
- **Risks for Claude-built Godot:** Godot 3 API drift (`RigidBody2D.mode`
  is gone in 4, use `freeze` and `freeze_mode`; `applied_force` became
  `apply_central_force`); `.tscn` breakage, so the blocks are built in code
  and only `main.tscn` exists; headless runs render nothing, so physics can
  be tested headless but every look check goes through `make shot` under
  xvfb. Physics is not bit-deterministic across machines: tests assert
  ranges and outcomes, not exact positions.

## MVP scope

One building site, one wrecker (the ball), four block shapes, three towers
per run, about 5 minutes, with all three seats and every fold-down.

### M1 grey-box

- [x] `games/tower-topple/` skeleton: project.godot (640x360 vector
  settings), Makefile with `start`, `demo`, `test`, `shot`, tmux targets,
  CLAUDE.md + AGENTS.md symlink, autoload symlinks to shared.
  *Done: `make test` also fails when any test script does not parse (GUT only warns).*
- [x] Crane, hook, drop, four block shapes as plain coloured polygons. *All six shapes shipped (square, plank, tall, roof, arch, ball).*
- [x] Landing assist, settle damping, freeze-when-buried. *Assist window:
  20 px above the top and within 44 px of the centre of mass horizontally;
  in it, the fall is also capped at 220 px/s so the nudge has frames to act.
  A block is "buried" when 3 rested blocks overlap it from above.*
- [x] Height line, cloud line, big button logic, topple impulse. *One flag
  every 36 px, 8 flags, and the 8th is the cloud line (288 px).*
- [x] Self-collapse detection lights the button. *Rule: 3 blocks that had
  rested on the tower fall into the pit (or 2 when that is half the tower).
  A height drop alone is not used, because a wobbling tower briefly has no
  "rested" blocks.*
- [x] Fold-down for 1 and 2 seats. *Also Builder plus Toppler, and a
  no-Builder autopilot crane.*
- [x] Demo driver plays three towers; `make shot SHOT_SCREEN=play`. *Demo
  towers last 14 s. The demo Dropper picks the best stacking shape from the
  tray, and a roof only as the tenth block.*
- [x] Couch test with rectangles: is dropping too hard for the
  5-year-old? Is the wait for the button too long for the 2-year-old?
  *Deviation: an agent cannot sit on the couch. It was replaced by
  headless demo runs, where towers reached 3 to 8 flags in 8 or 9 drops.
  The real couch test with the kids is still Oriol's to do.*

### M2 art and audio

- [x] Faces, outlines, sky, hills, ball pit, crane art, riders cheering.
  *Faces stay within 45 degrees of upright, and their pupils follow the
  hanging block, the lit button or the wrecker. Moods: happy, giggle,
  whee, oops, and asleep when frozen.*
- [x] Wrecker cycle: ball, elephant, whale, boot. *The cycle continues across runs.*
- [x] `tools/sfx.py` renders every sound above; level report printed.
  *Plus one extra, `sparkle` (a recycled block). The audio budget check was
  raised to 9 MB (7.5 MB total, of which the 43 s build loop is 3.8 MB).*
- [x] Confetti and "whee" faces during the topple.

### M3 polish and couch test

- [x] Camera slowly rises with the tower, zooms out on the topple.
- [x] Screen shake on the crash (capped, gentle). *Capped at 6 px, over 0.6 s.*
- [x] Tune assist, damping and the button timer from the couch notes.
  *Tuned from demo measurements, not couch notes: gravity scale 0.8,
  settling friction 1.0, bounce 0.05 and angular damp 8, and 100 s / 14
  drops for the button. Revisit them after the real couch test.*
- [x] Party screen with the three tower heights. *Stacks of mini blocks,
  one per flag, a trophy on the tallest (ties share it), and the stars
  shown in digits.*
- [x] Clean-clone run (`game/.godot` removed) before calling it done.

## Tests and verification

GUT tests (`game/tests/`):

- `test_drop_nudges_toward_tower_within_assist`
- `test_drop_far_from_tower_is_not_nudged`
- `test_toddler_press_before_lit_applies_no_impulse`
- `test_button_lights_at_cloud_line`
- `test_button_lights_after_fourteen_blocks`
- `test_button_lights_after_timer`
- `test_self_collapse_lights_button_and_keeps_stars`
- `test_topple_only_fires_when_lit`
- `test_buried_blocks_freeze_and_unfreeze_on_topple`
- `test_height_ignores_moving_blocks`
- `test_body_budget_removes_oldest_pit_block`
- `test_one_seat_builder_drops_and_topples`
- `test_two_seats_dropper_topples`
- `test_run_ends_after_three_towers`

Demo driver (`scripts/demo_driver.gd`, "play"): the Builder sweeps the hook
toward the tower's centre on a slow sine and rotates every third block;
the Dropper drops when the hook is within 8 px of the tower centre (plus
two deliberate misses); the Toppler presses every 2 s. Run seconds are
shortened so one capture holds two build phases and two topples.

Look at in the frames (`shots/play/sheet.png`, 2x): blocks stay outlined
and faces upright-readable at angles; the tower is visibly taller between
frames; the big button's lit state is obvious from across the room; the
topple frame shows blocks mid-air and confetti; nothing leaves the screen
except into the ball pit.

## Open questions for Oriol

1. Dad plus the 2-year-old only: should the join screen let a device go
   straight into seat 3 (for example, the adult holds B while the toddler
   presses)? This matters for every game in the monorepo.
2. The wreckers: ball, elephant bum, whale, rocket boot. Other favourites
   of the kids (a dinosaur, a fan character from the private pack)?
3. Is 14 blocks or 100 s the right wait before the big button? The
   toddler's patience decides.
4. Should blocks be building-toy shapes only, or also silly ones (a
   banana, a sleeping cat) that wobble more?

## Decisions taken (pending Oriol)

Defaults chosen while building (2026-09-26). Each is easy to change:

1. **Dad plus the 2-year-old.** kb:2 (the Space bar and every loose key)
   always goes straight to seat 3, as in PixelPals. For two pads, the
   Builder presses **down** on the join screen to move the pad in the
   Dropper seat to the empty Toppler seat (**up** moves it back). No hold
   gestures were added, because the Builder's B already means "leave".
2. **Wreckers:** ball, elephant bum, whale, rocket boot, as planned.
   Favourites such as a dinosaur or a private-pack character wait for the
   kids' answer.
3. **Wait before the button:** 14 drops or 100 s, as planned. Also, when the
   toddler is seated but does not press a lit button for 20 s, the Dropper's
   (or the Builder's) A can topple too, so a wandered-off toddler never
   blocks the run.
4. **Block shapes:** building-toy shapes only (square, plank, tall, roof,
   arch, one ball per tower). Silly shapes (a banana, a sleeping cat) wait
   for Oriol.
5. **Picking a shape changes the hanging block at once** (not only the next
   one). A 5-year-old sees the effect of the press immediately.
6. **A self-collapse** counts blocks that had rested on the tower and then
   fell into the pit (see M1), not a drop in height.
