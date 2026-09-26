# Zoo Keeper

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/zoo-keeper/`), or from the root with
`make start G=zoo-keeper`. The plan and its history are in [PLAN.md](PLAN.md).

Dad walks the keeper and the food cart around a tiny zoo. The 5-year-old picks
which food each hungry animal wants from four pictures on a cross-shaped
wheel. The 2-year-old's any button makes the nearest animal sing and dance.

- **Seat 1, Keeper** (adult): walks (analog), chooses the order of visits.
- **Seat 2, Feeder** (5-year-old): 4 directions pick a food, "a" throws it.
- **Seat 3, Singer** (2-year-old, optional): any button, an animal sings.

No game over, no text, no timer on screen. A run is 12 meals (every animal
eats twice, about 5 minutes) or 7 minutes, when the keeper rings the bell.
Load the **video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (`../../.tools/godot`). No Godot 3 APIs (`yield`,
  `update()`, `KinematicBody2D`, `export var`, `onready var`, `instance()`,
  `PoolVector2Array`, Tween nodes).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  scripts in `game/scripts/screens/<name>.gd` that build their children.
- **Flat vector look, not pixel art** (a deliberate exception to the skill's
  pixel-art default; see PLAN.md "Art direction"): 1280x720 canvas,
  `canvas_items` stretch, aspect `keep`, 2D MSAA plus antialiased
  `Polygon2D`/`Line2D`. There are **no image files**: every asset is a
  `Node2D` tree built by code in `game/scripts/vector/`.
- **Keyboard-only must always be playable**, with 1, 2 or 3 seats, pads and
  keyboard mixed.
- **No text in the game UI.** `test_no_label_nodes_in_the_zoo_screen` walks
  the tree.
- **The singer can never hurt the run**: a press never changes hunger, stars
  or meals, and a singing animal still takes food
  (`test_singing_never_blocks_the_feeder`).
- **Animal voices are synthesized** (`tools/sfx.py`); no recordings until
  Oriol decides otherwise.
- **Verify before claiming.** `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png` and single frames (`shots/<screen>/fNNNNNNNN.png`,
  native 1280x720, so no upscaling is needed).

## Commands

`make start` · `make demo` (`SHOT_SCREEN=join` plays the whole flow) ·
`make test` · `make sfx` · `make assets` · `make gallery` ·
`make shot SHOT_SCREEN=zoo` · `make shots` · `make editor` ·
`make export-linux` · `make tmux|tmux-d|tmux-n`. `make help` lists them all.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only here).
`game_state.gd` (`Game`) belongs to this game:

- `Game.goto("join"|"select"|"zoo"|"party"|"gallery")`.
- Seat aliases `Game.KEEPER/FEEDER/SINGER` = `Players.Seat.DRIVER/GUNNER/HONKER`.
- `Game.roster` (the six buddies), `Game.HATS` + `Game.hats[seat]` +
  `Game.hat_color(seat)`; `Players.riders[seat]` holds the seat's buddy.
- Results: `Game.stars`, `Game.meals`. `Game.run_seconds` overrides the 7 min
  (the demo uses 90 s). `Game.first_hungry` pins the first hungry animals.
- **Music ducking lives here** (`Game.voice(animal)`, `Game.duck(seconds)`),
  a local helper because shared `sfx.gd` has none; it lowers `Sfx._music`.

Game code (`game/scripts/`):

| file | what |
|---|---|
| `zoo/rules.gd` | right food per animal, wheel directions, hint ladder, pacing constants (pure, tested) |
| `zoo/scheduler.gd` | hunger order: 2 rounds of all six, no food three times in a row |
| `zoo/animal.gd` | one animal: state machine (idle, hungry, eat, sniff, shake, sing, dance), wandering, thought bubble |
| `zoo/food_wheel.gd` | the cross wheel: selection ring in the feeder's colour, wiggle and glow hints |
| `screens/zoo.gd` | the level; all logic in `step(dt)` (tests drive it with `set_process(false)`) |
| `screens/join.gd`, `select.gd`, `party.gd`, `gallery.gd` | menus, party, the asset contact sheet |
| `vector/vector_art.gd` | primitives: outlined shape, circle, ellipse, arc, rounded rect, Catmull-Rom blob and curve, limb, eye, leaf, shadow |
| `vector/palette.gd` | the 12 core colours plus animal/prop shades; food colours appear nowhere else |
| `vector/animals.gd` | `build(kind)`, `pose(rig, name, t, frame, look)`, `add_hat` |
| `vector/props.gd` | keeper, cart, foods, bubble, enclosures, particles, icons |
| `demo_driver.gd` | scripted seats `demo:0..2` for every screen (the plan's zoo route, then an autopilot) |

### Zoo rules in one screen

- Food: monkey banana, penguin fish, seal fish, rabbit carrot, elephant hay,
  giraffe hay. Wheel: up banana, right fish, down carrot, left hay.
- The wheel opens only while the keeper stands on a **hungry** animal's
  feeding spot (paw mat by the gate; it glows while that animal is hungry).
- Wrong food: sniff, head shake with a raspberry, the food bounces back into
  the cart. 1 wrong try: the right slot wiggles; 2: it glows and the bubble
  shows it faintly; the 3rd throw always succeeds (the food changes in mid-air).
- Solo (no feeder seated): stop at the spot, flick the stick to pick, "a"
  throws; hold the stick ~0.5 s to walk on. With a feeder, the keeper's "a"
  rings the cart's little bell.
- Singer: nearest animal (by its feeding spot) sings and dances; 0.8 s
  cooldown, extra presses float green notes. No singer: idle animals call
  out every 7-11 s.
- 6 meals = a round: "feeding done" dance, then round two. 12 meals = the end
  dance, then the party. 7 minutes = the bell: every animal gets a snack.

### Asset names (the art and audio contract)

Art is code, not files. Builders and poses:

| asset | builder | size at 1280x720 | poses / parts |
|---|---|---|---|
| monkey, penguin, giraffe, rabbit, elephant, seal | `Animals.build(kind)` | 130-200 px | idle, hungry, munch (frames 0/1), dance (0/1/2), shake, sing, sniff; eyes look left/right |
| keeper | `Props.keeper(hat)` | 90 px | walk frames 0-3, standing, `keeper_cheer` |
| buddy hat | `Animals.add_hat(rig, color)` | | seat colour |
| food_cart | `Props.cart()` | 130x80 | wheels roll, star bucket (`cart_stars`) |
| banana, fish, carrot, hay | `Props.food(kind)` | 64 px (0.62x when thrown) | |
| food_wheel | `FoodWheel` | 224 px | selection ring, wiggle, glow |
| thought_bubble + bowl | `Props.bubble()` | 90 px | `bubble_hint` |
| enclosures | `Props.enclosure(kind, size, gate_top)` | 330x215 | fence, pool (penguin, seal), tree (monkey, giraffe), burrow, mud |
| star, heart, note, confetti, bell, plate | `Props.star()` ... | 24-48 px | |
| seat and device icons | `Props.role_icon(seat)`, `icon_pad`, `icon_kb`, `arrow`, `check` | 64 px | |

Sounds (`game/audio/`, made by `make sfx`, measured in its report):
`monkey_1..3`, `penguin_1..3`, `seal_1..3`, `rabbit_1..3`, `elephant_1..3`,
`giraffe_1..2`, `throw`, `munch_1..3`, `nope`, `wiggle`, `star`,
`bubble_pop`, `bell`, `footstep_1..2`, `join`, `select`, `ready`, `party`,
`whoosh`, `music_menu`, `music_zoo` (100 BPM G major marimba; dances use its
playback position as the beat clock).

### Screen flow

`join` → `select` → `zoo` → `party` → `select`. `gallery` is demo-only.

- **join**: PixelPals's logic. The keeper continues with start or by holding "a".
- **select**: left/right buddy, up/down hat colour, "a" ready; the singer
  cycles on any press and auto-readies.
- **zoo**: the keeper's start pauses; in pause "b" goes back to join.
- **party**: the animals sing in turn in a spotlight, stars rain from the bucket.
