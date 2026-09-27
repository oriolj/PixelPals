# Pillow Fort

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below from
this folder (`games/pillow-fort/`), or from the root with `make start G=pillow-fort`.
The design and its history are in [PLAN.md](PLAN.md); how to play is in
[README.md](README.md).

A cosy bedtime hide-and-seek in a pillow fort at dusk:

- **Seat 1, Flashlight** (the adult): moves a warm light over the bedroom.
- **Seat 2, Seeker** (the 5-year-old): hops a yellow paw between the 14
  hiding spots with 4 directions and lifts pillows, blankets and box lids.
- **Seat 3, Peekaboo** (the 2-year-old, optional): any button makes a soft
  friend pop out near the light, cover its eyes and say "peekaboo!".

Eight toys hide each round. No text, no timer shown, no game over: an empty
spot always gives a small surprise, a glow hints after 45 s, and at 6 minutes
the last toys walk out on their own. Then the lamp fades on and the party
ends with a yawn. Personal (oriolj) scope. Load the **video-games** skill
(`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`) for the house rules.

## Rules

- **Godot 4.7 only** (the shared binary at the repo root `.tools/godot`). No
  Godot 3 APIs: no `yield`, `export var`, `onready var`, `instance()`, and in
  shaders no `SCREEN_TEXTURE` or `hint_color` (4.x: `hint_screen_texture`,
  `source_color`). Use GDScript with static types where cheap.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are scripts in `game/scripts/screens/<name>.gd`. The light shader is a
  `.gdshader` text file loaded in code; no hand-written `.tres`.
- **Pixel-perfect**: 320x180, integer scaling, nearest filtering, Sweetie 16.
- **It must not be scary** (hard rule, checked in every frame review): the
  dusk is plum/indigo at most 60% (`LightMask.MAX_STRENGTH`, clamped in the
  shader too), the nightlight, moon and fairy lights always glow, nothing
  appears or moves fast unless a player pressed (the one exception: with no
  toddler seated, a friend peeks every ~25 s, slowly, only inside the
  light), pop-outs ease in over 0.4 s, SFX sit at -18 LUFS with soft
  attacks, the music is a 72 BPM major-pentatonic music box, the round ends
  with the lamp fading on over 2 s. No teeth, no glowing eyes in the dark,
  no black: "under the bed" is warm plum.
- **Keyboard-only must always be playable**, with 1, 2 or 3 seats, pads and
  keyboard mixed. **No text in the UI.** The toddler seat can never pause,
  lift, or lose anything.
- **Third-party characters** (the private pack riders, copied from PixelPals)
  live in `game/private_pack/` and `art_src/private/`; they are gitignored and kept only on the family's machine (never committed). Never publish them; `make export-linux`
  excludes the pack.
- **Verify before claiming**: `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png`. `make shot` (fort) also runs `make light-check`.

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=fort` · `make test` ·
`make sprites` · `make sfx` (`make sfx-check` for spectrograms) · `make assets` ·
`make shot SHOT_SCREEN=fort` · `make shots` · `make light-check` · `make editor` ·
`make export-linux` · `make tmux` / `tmux-d` / `tmux-n`. `make help` lists everything.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are **symlinks
into `../../shared/godot/autoload/`** (read-only here; see the root CLAUDE.md
and PixelPals's CLAUDE.md for their API). `game_state.gd` belongs to this game:

- `Game.goto("join"|"select"|"fort"|"party")`; flow `join → select → fort →
  party → select`.
- `Game.ADULT/KID/TODDLER` = seats 0/1/2 (the shared enum still says
  DRIVER/GUNNER/HONKER). `Game.TOYS` (the eight toys, basket order),
  `Game.round_seconds` (360; the demo uses 20), `Game.toys_found`,
  `Game.round_time`, demo flags (`--demo[=screen]`, `--lightcheck`, `--mute`).

Fort pieces (`game/scripts/fort/`, preloaded, no `class_name`):

- `light_mask.gd` — the **GDScript mirror** of `shaders/fort_light.gdshader`.
  A light is `{"pos": Vector2, "r": float}`; positions are floored to whole
  pixels, radii rounded. `level()` = 1 in the core, 2/3 and 1/3 in two edge
  bands (band = `floor(max(2, r/12))` px, squared-integer distances so GPU and
  CPU agree exactly), 0 outside. `lit_pixel()` applies the Bayer 4x4 dither;
  `light_amount()` is what gameplay uses. `uniforms()` builds the 8-slot
  arrays. `make light-check` renders the shader's calibration output
  (`debug_mode = 1`) under xvfb and compares all 57,600 pixels with the mirror.
- The 8 light slots: 0 flashlight (r 36), 1 nightlight, 2 moon, 3–4 fairy
  lights (twinkle bigger), 5 the paw, 6 the newest peekaboo friend, 7 the hint.
- `spot_graph.gd` — each spot's nearest neighbour per direction (cone first,
  then anything ahead); `hop()`, `reachable()`.
- `peekaboo_director.gd` — `press()` pops a friend at the free spot nearest
  the light (1 s cooldown; presses inside it return a twinkle),
  `auto_step()` (no toddler: every 25 s, inside the light only), `step()`
  returns friends reaching "peekaboo!" (the chime). Frames by time:
  0 peek 0–0.4 s (eased rise), 1 eyes covered to 1.0, 2 peekaboo to 1.9,
  3 duck back to 2.3.
- `room_layout.gd` — spot kinds and centres, fort/lamp/basket/nightlight/moon/
  fairy/rider positions. **`tools/sprites.py` draws `room_bg` with the same
  coordinates**; move both together.
- `screens/fort.gd` — the round: `step(dt)`, `lift(i)` (→ `{"toy"}` or
  `{"surprise"}`), `hide_toys(placement)`, `spot_under_light()`,
  `mask_strength()`, states RUN → WALKOUT (time up) → LAMP → DONE, pause for
  seat 0 only (b in pause goes to join). Constants: DWELL 1.5 s (solo only),
  HINT_AFTER 45 s, LAMP_FADE 2 s.
- `scripts/nightcap.gd` — the seat-coloured nightcap drawn on riders (the
  "pyjama colour").
- `scripts/demo_driver.gd` — scripted seats for every screen (see its header
  for the fort script).

### Asset names (the art and audio contract)

Sprites: `tools/sprites.py` (generators) plus `art_src/*.txt` grids, Sweetie 16,
1 px dark outline, rendered to `game/art/` with `manifest.json`, linted.

| name | size | frames | use |
|---|---|---|---|
| room_bg | 320x180 | 1 | the bedroom (walls, window + moon, shelf, nightstand, laundry basket, bed, rug, nightlight, bunting) |
| fort | 96x64 | 2 | blanket fort; frame 1 = fairy lights twinkle |
| pillow_a, blanket_fold | 24x16 | 3 | hiding spots: rest, wiggle, lifted |
| pillow_b | 20x16 | 3 | hiding spot |
| box | 16x16 | 3 | hiding spot (lid) |
| curtain | 16x24 | 3 | hiding spot (the hem of the right curtain) |
| bed_edge | 32x16 | 3 | hiding spot (bed skirt; lifted shows warm plum under the bed) |
| teddy, bunny, duck, ball, blocks, dino, car, doll | 16x16 | 2 | toys: idle, happy hop |
| tip_<toy> | 8x8 | 1 | what peeks out of a spot, cut from the toy by the generator |
| teddy_big, bunny_big, sleepy_cat | 24x24 | 4 | peekaboo friends: peek, eyes covered, peekaboo, duck back |
| sock, cookie | 8x8 | 2 | empty-spot surprises |
| sleepy_mouse | 16x16 | 2 | empty-spot surprise (waves) |
| paw_pointer | 16x16 | 2 | the seeker's paw, white, tinted with the seat colour |
| toy_basket | 32x24 | 3 | empty, half, full |
| lamp | 16x32 | 2 | off, on |
| sparkle | 8x8 | 3 | white, tinted in code (green for peekaboo) |
| heart, check, arrow_left, arrow_right, icon_pad, icon_kb | as PixelPals | 1 | copied grids |
| confetti | 4x4 | 6 | one colour per frame |
| seat_flashlight, seat_seeker, seat_peekaboo | 16x16 | 1 | seat role icons |
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (copied from PixelPals) |

Private pack (copied from PixelPals): `sonic`, `shadow`, `knuckles`,
`robotnik`, `minion_tall`, `minion_short`, `minion_bob`, `mario`, `luigi`.

Sounds (`tools/sfx.py`, 24 kHz mono, SFX -18 LUFS, music -17 LUFS, loops seamless):
`peekaboo_1..3`, `giggle`, `lift`, `toy_found`, `basket_plop`, `mouse_squeak`,
`surprise`, `twinkle_1..3`, `hint_glow`, `lamp_on`, `join`, `select`, `ready`,
`hop`, `party`, `yawn`; music `music_menu` (80 BPM), `music_fort` (72 BPM
music-box lullaby, C major pentatonic), `music_party` (96 BPM, brighter).

### Local divergences from shared code

None of the shared files is copied. `join.gd`, `select.gd`, `demo_driver.gd`,
`tools/sprites.py` and `tools/sfx.py` are copies of PixelPals's, changed for
this game (role icons, warm dusk colours, nightcaps, the fort flow, new
generators and voices).
