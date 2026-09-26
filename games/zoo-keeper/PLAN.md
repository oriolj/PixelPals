# Zoo Keeper

Dad walks the zookeeper and the food cart around a tiny zoo, the 5-year-old
picks which food each hungry animal wants from four pictures, and the
2-year-old makes the animals sing and dance with any button.

Status: playable (2026-09-26). Built in one pass; see [CLAUDE.md](CLAUDE.md) for the contracts.

## Why it fits our family

- **5-year-old**: a real, gentle quiz. Each animal wants one of four foods,
  shown only as pictures (banana, fish, carrot, hay). Getting it right is
  a happy munch; getting it wrong is a funny "no thanks" and a hint. They
  learn which animal eats what, by seeing and hearing.
- **2-year-old**: animal sounds on demand. Any button makes the nearest
  animal say its sound and dance, which is exactly the "what does the cow
  say" stage. It never affects the feeding.
- **Adult**: walks the keeper, chooses the order of visits, and paces the
  quiz.
- **No text anywhere**: no words, no numbers, no letters. Foods, animals,
  hunger and progress are all pictures, sounds and motion.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | Keeper (adult) | left stick walks (analog); "a" = open the gate / serve when the kid is absent; start = pause | kb:0 WASD walks, Shift serves, Esc pauses |
| 2 | Feeder (5-year-old) | 4 directions pick one of four foods on a cross-shaped food wheel (up banana, right fish, down carrot, left hay); "a" throws it | kb:1 arrows pick, Enter throws |
| 3 | Singer (2-year-old) | any button: the nearest animal makes its sound and dances (0.8 s cooldown; extra presses make music notes float up) | kb:2 Space or any other key |

- **1 seat**: when the keeper stops at an enclosure, the food wheel opens and
  the keeper's own stick picks, "a" throws. Animals make their sound on
  their own when fed.
- **2 seats**: no singer; animals sing after every correct meal and idle
  animals call out now and then.
- **3 seats**: as the table. Keyboard-only on one keyboard works.
- The food wheel sits above the keeper, drawn in the feeder's yellow; the
  music notes are the singer's green.

## Core loop

1. One screen-and-a-half zoo seen from above at a slight tilt: a path loop
   with six enclosures (monkey, penguin, rabbit, elephant, giraffe, seal).
2. Animals get hungry one or two at a time: a thought bubble shows an empty
   bowl and the animal looks at the keeper, bouncing. No food picture in the
   bubble, so the kid has to know (or guess).
3. The keeper walks to a hungry animal; standing at its feeding spot opens
   the food wheel.
4. The feeder picks a food and throws it. Right food: the animal catches it,
   munches, makes its sound, hearts float, a star drops into the keeper's
   bucket. Wrong food: the animal sniffs it, shakes its head with a silly
   "pfff", and the food bounces back into the cart.
5. After 5-6 meals per animal round, the zoo gets a "feeding done" moment
   and the next hunger wave begins with a new pair.

Food mapping for the MVP: monkey banana, penguin fish, seal fish, rabbit
carrot, elephant hay, giraffe hay (leaves drawn into the hay picture).
Two animals per food keeps the four-food wheel honest.

**No-fail rules**

- A wrong food costs nothing: no stars lost, no timer, no angry animal.
- **Hint ladder**: after one wrong try the right food on the wheel wiggles;
  after two, it glows and the animal's bubble shows it faintly. A third try
  always succeeds.
- Hungry animals never get sad or sick; they just keep bouncing.
- The run ends after every animal has eaten twice (12 meals, about 5
  minutes), or at 7 minutes, when the keeper rings a bell and every animal
  gets a snack at once. Then the party.

## Screens and flow

`join` → `select` → `zoo` → `party` → `select`.

- **join**: reused from PixelPals, with the vector look.
- **select**: each seat picks a keeper hat colour and an animal buddy that
  follows the keeper (monkey, penguin...). The singer cycles on any press.
- **zoo**: the level.
- **party**: every animal in a row on a stage, dancing, each doing its sound
  in turn; the stars from the bucket rain as confetti.

## Art direction

- **Flat vector**: big friendly shapes, thick dark outlines, no gradients
  except a soft ground shadow. Why: animals and foods must be instantly
  recognisable at couch distance, and round, smooth shapes read better than
  16x16 pixel animals (the PixelPals monkey read as a duck until redrawn).
- Canvas **1280x720**, stretch mode `canvas_items`, aspect `keep`, 2D
  antialiasing on; scales to 1080p and 4K.
- Palette: bright but warm, 12 fixed colours in `palette.gd`: grass
  `#7cc36b`, path `#f1d6a0`, water `#5fb8e8`, fences `#b0764a`, outline
  `#2b2438`, plus one strong colour per food (banana `#ffd23f`, fish
  `#6aa8ff`, carrot `#ff8a3d`, hay `#c9b04a`) that never appears elsewhere,
  so the food colour itself is a cue.
- How assets are made: every shape is **procedural Godot drawing** from
  code, `Polygon2D`/`Line2D` built from point lists and a few primitives
  (circle, rounded rectangle, blob, eye, leaf) in a small `vector_art.gd`
  library. Each asset is a script function `draw_monkey(pose)` that returns
  a `Node2D` tree, so poses animate by moving parts (head bob, ear flap,
  trunk swing). No external tool, no image files.

| asset | size on 1280x720 | parts / poses |
|---|---|---|
| monkey, penguin, seal, rabbit, elephant, giraffe | 120-200 px tall | idle, hungry bounce, munch (2 frames), dance (3 poses), head shake |
| keeper | 90 px | walk cycle 4 poses, hat tinted by seat |
| food_cart | 110x80 | wheels turn |
| banana, fish, carrot, hay | 64 px on the wheel, 40 px thrown | one shape each, strong silhouette |
| food_wheel | 220 px cross | 4 slots, highlight ring in seat colour |
| thought_bubble + empty bowl | 90 px | pops in and out |
| enclosures | 6 panels ~300x200 | fence, pool (penguin, seal), tree (monkey, giraffe) |
| star, heart, music_note, confetti | 24-40 px | |
| seat and device icons | 64 px | vector redraws of PixelPals icons |

A `gallery` demo screen draws every asset in every pose on a checkerboard,
plus a solid-silhouette row, for the contact-sheet review.

## Audio

All synthesized by our code (a `tools/sfx.py`-style synth):

- **Animal sounds** (the hard part): monkey "ooh-ooh-aah" (formant-filtered
  saw with vowel shifts), penguin honk (square with nasal band-pass),
  seal bark (short noisy bursts), rabbit (a soft nose-twitch "pip-pip"
  since rabbits are nearly silent), elephant trumpet (saw with pitch rise
  and growl), giraffe (a soft hum). 2-3 variants each.
- SFX: `throw` (whoosh), `munch_1..3`, `nope` (a raspberry "pfff"), `wiggle`,
  `star`, `bubble_pop`, `bell`, `footstep_1..2`, `join`, `select`, `ready`,
  `party`.
- Music: `music_menu`, `music_zoo` (a sunny marimba-like loop, 100 BPM, in
  G major) that ducks under every animal sound so the sound is heard.
- Formant synthesis is new for us; if the animal sounds do not read, see the
  open questions.

## Reuse

- **shared/**: `players.gd`, `sfx.gd`, `tools/shots.py`. `art.gd` only for
  the fallback idea; vector assets do not load PNGs.
- **From PixelPals**: `game_state.gd`, join/select/party screen logic,
  `demo_driver.gd`, the Makefile, the synth core of `tools/sfx.py`.
- **Extract to shared first**: the synth core → `shared/tools/synth.py`
  (needed for the new formant voice anyway); join/select/party → shared
  screens that take a "draw icon" callback so pixel and vector games both
  use them; generic seat aliases (`ADULT/KID/TODDLER`).
- **New and shareable**: `shared/godot/vector/vector_art.gd` (primitives,
  outline, palette) and the gallery screen; Pancake Kitchen will reuse both.

## New tech this game needs

- `vector_art.gd`: outlined polygons (a `Polygon2D` fill plus a closed
  `Line2D` outline with round joints), circles as 32-point polygons, blob
  shapes from a few control points (Catmull-Rom to polygon).
- **Animal behaviour**: a tiny state machine per animal (idle, hungry,
  eating, singing, dancing, refusing), no pathfinding; animals wander inside
  their enclosure rectangle.
- **Hunger scheduler**: picks the next hungry pair so every animal is fed
  twice and no food is asked three times in a row.
- **Food wheel** with dir4 picking and hint ladder.
- **Risks for Claude-built Godot**:
  - Godot 3 drift: `update()` instead of `queue_redraw()`, `Polygon2D.polygon`
    as `PoolVector2Array` (now `PackedVector2Array`), `tween` as a node (4.x
    uses `create_tween()`).
  - `.tscn` breakage: build every animal in code; no scene per animal.
  - Headless renders nothing: the look of shapes and outlines only exists in
    `make shot` frames under xvfb; tests cover logic only.
  - Vision limits: a 1280x720 frame is readable, but judge animal
    recognisability on the gallery at 1x and in silhouette, not in gameplay.

## MVP scope

One zoo, six animals, four foods, 12 meals, about 5 minutes.

**M1 grey box**
- [x] Scaffold (Makefile with start, demo, test, shot, shots, sfx, tmux trio;
      `project.godot` at 1280x720 canvas_items). The Makefile also has
      `gallery`, `assets`, `setup`, `import`, `ensure-import`, `editor`,
      `export-linux`, `setup-export`.
- [x] Animals as coloured circles... *Deviation*: skipped the grey box; the
      vector art library went in first, so the logic was built and tested
      directly on the final rigs.
- [x] Food wheel, hint ladder, hunger scheduler, run end at 12 meals or 7
      minutes; 1-, 2-, 3-seat play (tested for each).
- [x] Couch test: *agent part only*. The rules a 5-year-old needs (wheel
      pictures, wiggle then glow, third try always works) and the singer's
      "nearest animal" pick are in place and tested. **The real couch session
      is pending Oriol** (it needs the kids).

**M2 art and audio**
- [x] `vector_art.gd`, six animals with all poses, keeper, foods, cart,
      enclosures, bubble, wheel; gallery reviewed in silhouette (the seal
      first read as a penguin in silhouette; it got a tail sweeping sideways).
- [x] Animal sounds (2-3 variants each: 17 voices), SFX, both loops,
      measured (`make sfx` report: peaks under -1 dBFS, voices -13 LUFS,
      rabbits -18 on purpose, SFX -15, music loops seamless, 6.4 MB total).
      Spectrograms checked; **a human listen is still pending**.
- [x] Party screen stage.

**M3 polish and couch test**
- [x] Animals turn to watch the keeper (eyes and head); dances use the
      music's playback position as the beat clock (100 BPM).
- [x] Balance: `rules.gd` pacing constants (first hunger 1.2 s, 2.5 s gap
      after a meal, 4 s round break, 4.5 s end dance). First guess; tune on
      the couch.
- [x] Couch session with both kids: **pending Oriol**. Lessons from the build
      (below) are ready for the skill's field notes.

## Tests and verification

GUT:
- `test_each_animal_has_exactly_one_right_food`
- `test_wrong_food_costs_nothing_and_bounces_back`
- `test_hint_ladder_wiggles_then_glows_then_always_succeeds`
- `test_wheel_maps_dir4_to_the_four_foods`
- `test_wheel_opens_only_at_a_feeding_spot`
- `test_singer_press_picks_the_nearest_animal`
- `test_singer_never_changes_hunger_or_stars`
- `test_scheduler_feeds_every_animal_twice`
- `test_scheduler_never_asks_one_food_three_times_in_a_row`
- `test_run_ends_after_twelve_meals_or_the_bell`
- `test_solo_keeper_can_pick_and_throw`
- `test_no_label_nodes_in_the_zoo_screen` (walks the tree: no `Label` or
  `RichTextLabel` outside the debug overlay)

All twelve exist in `game/tests/zoo/` (the run-end test covers both
endings; the scheduler tests run 200-300 seeds). Added: feeder dir4 + a,
nothing picked throws nothing, round break, pause, idle call-outs,
buddies follow, singing never blocks the feeder (a real bug the demo found:
the singer's press made the penguin dance and a dancing animal refused
food), art rigs and poses, gallery pages, join/select/party, and a demo
driver test that plays the plan's scripted route against a real zoo.

Demo driver (`make shot SHOT_SCREEN=zoo`): the keeper walks a scripted
route to the monkey then the penguin; the feeder picks hay first (wrong,
to show the refusal and wiggle), then banana; then fish for the penguin;
the singer presses at 3 s, 4 s and 9 s. `make shot SHOT_SCREEN=gallery`
captures every asset.

In the frames: every animal recognisable without text, foods distinct by
shape AND colour, outlines unbroken at 1x, the wheel's highlight in yellow,
the refusal head shake visible across two frames, no text anywhere.

## Open questions for Oriol

- If synthesized animal sounds do not read, may we use CC0 recordings
  (for example from Freesound's CC0 filter), kept with their licence file?
  That would break the "all sound from our code" rule, so it is your call.
- Which animals do the kids love most (the first six are a guess)?
- Should the foods ever be more than four (a second zoo with meat, seeds,
  bamboo, ice cream as a silly one)?
- Is a tilted top-down view right, or a side-on row of enclosures (simpler
  walking, left/right only)?

## Decisions taken (pending Oriol)

Defaults chosen during the build so it could be finished; each is easy to change.

- **Recordings**: none. All 17 animal voices are synthesized (formant
  voice). If they do not read on the couch, the CC0-recordings question is
  still yours.
- **Which six animals**: the plan's guess (monkey, penguin, giraffe on top;
  rabbit, elephant, seal below). Adding one is a builder in `animals.gd`, a
  `RIGHT_FOOD` entry and a voice in `sfx.py`.
- **Four foods only**; no second zoo.
- **View**: the tilted top-down zoo, one and a half screens wide (1920x720
  world, the camera follows the keeper sideways only).
- **Keeper "a" with a feeder present** rings the cart's little bell (plan:
  "open the gate"); it throws only when there is no feeder.
- **The wheel sits beside and above the keeper**, on the side away from the
  animal, and the keeper stands beside the gate: directly above him it covered
  the animal the child has to look at.
- **Select**: each seat picks a buddy animal (they trail the keeper) and a
  hat colour (up/down); the keeper wears seat 1's hat.
- **"Nearest animal"** for the singer is measured to each enclosure's feeding
  spot, so the pick is stable while animals wander.
- **The bell** gives every animal a snack but no extra stars.
- **Palette**: the plan's 12 core colours plus extra shades for animals and
  props (it named only nine). Star gold `#ffb938` differs from banana
  `#ffd23f`.
- **Shared code not extracted** (the plan's "extract to shared first"): this
  build could not touch `shared/`. Music ducking is a local helper in
  `game_state.gd`; `vector_art.gd` and the gallery are ready to move to
  `shared/godot/vector/` for Pancake Kitchen.
