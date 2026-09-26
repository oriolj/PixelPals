# Pancake Kitchen

The 2-year-old flips pancakes sky-high with any button, dad slides the pan
to catch them, and the 5-year-old piles on toppings for a queue of hungry
animal customers who love every silly combination.

Status: plan (2026-09-26)

## Why it fits our family

- **2-year-old**: the flip is the star moment of the game. Any button sends
  the pancake spinning up with a "boing", and it always comes back down
  somewhere fun. They start every pancake's big moment.
- **5-year-old**: creative choice with no wrong answers. Four toppings on
  four directions, stacked however they like. Customers react with joy to
  everything (bigger joy for bigger piles).
- **Adult**: the timing and catching, with a generous magnet so it stays
  relaxed and the kids get to watch.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | Cook (adult) | left stick slides the pan left/right (analog); "a" = serve the plate / flip when seat 3 is empty; start = pause | kb:0 A/D slide, Shift serves, Esc pauses |
| 2 | Topper (5-year-old) | 4 directions pick a topping from four jars (up strawberry, right chocolate chips, down banana slices, left whipped cream); "a" drops it on the top pancake of the plate | kb:1 arrows pick, Enter drops |
| 3 | Flipper (2-year-old) | any button = flip (if the pancake is in the pan); any press while it is in the air adds a spin and a sparkle | kb:2 Space or any other key |

- **1 seat**: the cook flips with "a" and serves with "b"; the customer
  sprinkles their own toppings when the plate is served.
- **2 seats**: the cook flips; the topper as in the table.
- **3 seats**: as the table. Keyboard-only works on one keyboard.
- The pan handle wears the cook's blue, the topping jar ring the topper's
  yellow, and flips leave a green sparkle trail for the flipper.

## Core loop

1. A side-on kitchen counter: stove on the left, the plate in the middle,
   the counter window on the right where a customer waits (bear, cat,
   penguin, frog, robot).
2. Batter pours into the pan by itself; the pancake cooks from pale to
   golden in 3 s (a colour change, and little bubbles).
3. The flipper flips: the pancake flies up (height randomised a little),
   spins, and falls. The cook slides the pan under it; within the magnet
   radius (60 px) it snaps in with a "flop".
4. Two flips and the pancake is done: it hops from the pan onto the plate
   stack by itself.
5. The topper drops toppings on the top pancake at any time; toppings land
   and stick, piling up visibly.
6. When the stack has 3 pancakes, the plate glows; the cook serves ("a"),
   the plate slides to the window, the customer eats with a big silly
   reaction and leaves; the next one comes in.
7. Six customers served ends the round (about 5 minutes).

**No-fail rules**

- A missed catch is a gag, not a loss: the pancake lands on the dog's head,
  on the cat on the shelf, or bounces on the counter with a "boing" and hops
  back into the pan. Nothing is thrown away, nothing burns.
- Pancakes never burn: past golden they just stay golden.
- Every topping combination makes the customer happy; more toppings make the
  reaction bigger (three reaction sizes).
- Flipping an uncooked pancake still flips; it just keeps cooking.
- The round ends after six customers, or at 7 minutes when every waiting
  customer gets a pancake at once. No timer is ever shown.

## Screens and flow

`join` → `select` → `kitchen` → `party` → `select`.

- **join / select**: reused from PixelPals (vector look). Select picks a chef
  hat colour and an animal chef per seat.
- **kitchen**: the level, a single fixed screen (no camera movement, which is
  calmer and makes catching readable).
- **party**: all six customers at a long table with their pancake towers,
  then a giant pancake flips over the whole screen as confetti falls.

## Art direction

- **Flat vector**, same look and library as Zoo Keeper: round shapes, thick
  dark outlines, warm kitchen colours. Why: food wants soft round shapes, and
  toppings must stack and overlap smoothly, which pixel art at 320x180 would
  make tiny.
- Canvas **1280x720**, stretch mode `canvas_items`, aspect `keep`.
- Palette (`palette.gd`): wall `#fff1d6`, tiles `#f6c89f`, counter `#9b5e3c`,
  pan `#3a3a4a`, batter `#fbe7a8`, golden `#e8a13a`, outline `#2b2438`;
  toppings each own one colour: strawberry `#e8435a`, chocolate `#5a3525`,
  banana `#ffe066`, cream `#ffffff`.
- How assets are made: **procedural Godot drawing** with the shared
  `vector_art.gd` (from Zoo Keeper). The pancake is an ellipse whose
  squash, colour and bubbles are driven by code (cook amount, spin, squash
  on landing). Cream is a blob built from overlapping circles along a
  spiral. No image files, no external tool.

| asset | size on 1280x720 | notes |
|---|---|---|
| pancake | 160x36 ellipse | cook colour lerp, bubbles, spin by y-scale flip, squash on land |
| pan | 200x50 + handle | seat tint on handle |
| stove, counter, shelf, window | fixed scenery | built once at load |
| plate + stack | 180 px | stack offset per pancake |
| strawberry, chocolate_chip, banana_slice, cream_swirl | 24-48 px | stick where they land, small random rotation |
| topping jars | 80 px each | 4, in a cross above the plate, highlight in yellow |
| customers: bear, cat, penguin, frog, robot | 220 px tall | walk in, wait, eat (3 poses), 3 joy sizes, leave |
| dog (catch gag), shelf cat (catch gag) | 120 px | |
| steam, sparkle, star, confetti | 16-40 px | |
| seat and device icons | 64 px | shared vector icons |

A `gallery` demo screen draws every asset and state (raw, golden, each
topping, each customer pose) for review, and in silhouette.

## Audio

Synthesized by our own synth: `pour` (filtered noise glide), `sizzle`
(looping band-passed noise, quiet), `boing_1..4` (pitch-bent sine, one per
flip), `spin` (rising whistle), `flop` (low thump), `plop_1..3` (toppings),
`splat_soft` (cream), `ding` (stack ready), `slide` (plate to window),
`yum_1..3` and `giggle` (formant voice from the Zoo Keeper synth),
`dog_woof`, `join`, `select`, `ready`, `party`. Music: `music_menu`,
`music_kitchen` (swingy loop in F major, 96 BPM, xylophone and bass).

## Reuse

- **shared/**: `players.gd`, `sfx.gd`, `tools/shots.py`.
- **From Zoo Keeper** (via shared): `vector_art.gd`, the gallery screen, the
  formant voice in `shared/tools/synth.py`. If Pancake Kitchen is built
  before Zoo Keeper, this game does those extractions instead.
- **From PixelPals**: `game_state.gd`, join/select/party screens (the shared
  versions with an icon callback), `demo_driver.gd`, the Makefile.
- **Extract to shared first**: generic seat aliases (`ADULT/KID/TODDLER`)
  and the join/select/party screens, if no earlier game has done it.

## New tech this game needs

- **Flip physics without a physics engine**: the pancake's flight is a
  scripted parabola (initial velocity plus gravity in code), spin as an
  animated y-scale, so the landing point is predictable and testable.
  Rigid bodies would make it chaotic and hard to test.
- **Catch magnet**: when falling within 60 px horizontally of the pan and
  below a height line, the pancake eases into the pan.
- **Miss gags**: a table of landing zones (dog, shelf cat, counter bounce)
  chosen by where the pancake lands; every one ends with the pancake back in
  the pan.
- **Toppings that stick**: each topping becomes a child of the top pancake
  at its landing point, clamped to the pancake's ellipse.
- **Customer queue** with a small state machine.
- **Risks for Claude-built Godot**:
  - Godot 3 drift: `Tween` nodes and `interpolate_property` (4.x is
    `create_tween().tween_property`), `update()` vs `queue_redraw()`,
    `yield` vs `await`.
  - `.tscn` breakage: one `main.tscn`; every object built in code.
  - Headless renders nothing: flip arcs and catches are pure math, so they
    are tested headless; the look only in `make shot` frames under xvfb.
  - Fixed-FPS captures: the flight must use `delta` consistently so
    `--fixed-fps 30` captures match live play.

## MVP scope

One kitchen, five customer types, six customers per round, four toppings,
about 5 minutes.

**M1 grey box**
- [ ] Scaffold (Makefile with start, demo, test, shot, shots, sfx, tmux trio;
      1280x720 `canvas_items`).
- [ ] Pancake as an ellipse, pan as a rectangle, toppings as coloured dots,
      customers as coloured capsules.
- [ ] Flip, magnet catch, miss gags (as coloured boxes), two-flip doneness,
      stack of three, serve, six customers; 1-, 2-, 3-seat play.
- [ ] Couch test: is the magnet generous enough for relaxed catching? does
      the 2-year-old flip too often (flip only works when the pancake is in
      the pan, so spam is harmless)?

**M2 art and audio**
- [ ] Kitchen, pancake states, toppings, jars, customers, dog and cat in
      `vector_art.gd`; gallery reviewed.
- [ ] All SFX and both loops synthesized and measured.
- [ ] Party table screen.

**M3 polish and couch test**
- [ ] Squash and stretch on landings, steam, customer eye-tracking of the
      flying pancake.
- [ ] Balance flip height and the customer patience animation (they never
      leave unhappy).
- [ ] Couch session; lessons into the skill's field notes.

## Tests and verification

GUT:
- `test_flip_only_starts_when_the_pancake_is_in_the_pan`
- `test_flip_arc_lands_where_the_math_says`
- `test_pan_within_magnet_radius_catches`
- `test_missed_pancake_always_returns_to_the_pan`
- `test_pancake_never_burns`
- `test_two_flips_move_the_pancake_to_the_plate`
- `test_toppings_stick_inside_the_pancake_ellipse`
- `test_every_topping_combo_makes_the_customer_happy`
- `test_reaction_size_grows_with_topping_count`
- `test_stack_of_three_can_be_served`
- `test_round_ends_after_six_customers_or_at_seven_minutes`
- `test_toddler_spam_in_the_air_only_adds_spin`
- `test_no_label_nodes_in_the_kitchen_screen`

Demo driver (`make shot SHOT_SCREEN=kitchen`): the flipper presses whenever
the pancake is golden; the cook tracks the landing point but deliberately
misses once at 6 s (to show the dog gag); the topper cycles through all four
toppings, one drop every 1.2 s; the cook serves as soon as the plate glows.
`DEMO_RUN_SECONDS := 25` with two customers. `make shot SHOT_SCREEN=gallery`
for assets.

In the frames: pancake colour visibly moves from pale to golden, spin reads
as a flip (the pancake thins then widens), toppings sit on the pancake not
floating beside it, the dog gag ends with the pancake back in the pan, the
customer's reaction size differs between a plain and a loaded stack, no
text anywhere.

## Open questions for Oriol

- Which toppings do the kids actually ask for (Nutella, sugar, syrup)? Four
  is the limit for the dir4 picker.
- Should customers show a wish (a picture of a topping in a bubble) as an
  optional "order" mode for when the 5-year-old wants a challenge?
- Is a dog in the kitchen OK, or another gag animal?
- A "print the menu" idea: save the party table as a PNG like Paint Party's
  fridge picture?
