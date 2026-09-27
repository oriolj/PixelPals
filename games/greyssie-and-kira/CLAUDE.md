# Where Are Greyssie and Kira?

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/greyssie-and-kira/`), or from the root with
`make start G=greyssie-and-kira`. The design and its history are in
[PLAN.md](PLAN.md); how to play is in [README.md](README.md). Load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

Find the family's two grey cats hiding around a three-storey dollhouse, coax
them out with treats and a laser dot, and carry them to their dinner bowls.
A game is one day: morning, afternoon, evening and night (four rounds, ~8 min).

- **Seat 1, Walker** (adult): walks, climbs the stairs, opens spots, picks up
  cats (one per shoulder), puts them down at the bowls.
- **Seat 2, Laser** (5-year-old): moves the red dot in 4 directions; "a"
  wiggles it. Shy or high-up cats stalk and pounce onto it.
- **Seat 3, Treats** (2-year-old, optional): any press shakes the treat bag;
  the nearest cat meows back, a bubble in its collar colour pops in its room
  and the mini house view lights that room for 2 s.

Personal (oriolj) scope. Greyssie and Kira are real cats; see "Privacy".

## Rules

- **Godot 4.7 only** (`../../.tools/godot`, `gl_compatibility`). No Godot 3
  APIs (`yield`, `export var`, `onready var`, `instance()`, `KinematicBody2D`).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`; screens are
  scripts in `game/scripts/screens/<name>.gd`.
- **Pixel-perfect**: 320x180, integer scaling, nearest, Sweetie 16. Every
  colour drawn by code is a Sweetie 16 colour.
- **The house and the cats are data, never code**: `game/data/house.json` and
  `game/data/cats.json` (below). A new house needs no code and no
  regeneration; new cat looks need `make sprites`, new voices `make sfx`.
- **The two grey cats must stay distinguishable at 1x and in silhouette.**
  After any change to their looks, open `art_src/cats_compare.png`.
- **The night is warm, never dark**: amber CanvasModulate (luminance >= 0.75,
  `test_night_is_warm_not_dark`), lamps on with glow pools, a plum (not navy)
  sky.
- **No text, no game over, no timer on screen.** At 60 s a hidden cat's tail
  pokes out further; at 90 s it walks out to the walker and meows.
- **The toddler seat can never hurt the run**: it only makes sounds, bubbles
  and tail twitches (`test_toddler_input_never_hurts`); only the walker pauses.
- **Keyboard-only with 1, 2 or 3 seats**, pads and keyboard mixed.
- **Private pack**: the fan-art riders in `game/private_pack/` and
  `art_src/private/` are committed only because the repo is private;
  `make export-linux` excludes them.
- **Verify before claiming**: `make test` (a test file that fails to parse
  fails the run), `make shots` and look at `shots/<screen>/sheet.png`,
  `make demo-day` (a whole headless day: 4 rounds, then the party).

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=house` (`join` plays a
whole day) · `make demo-day` · `make test` · `make sprites` · `make sfx`
(`make sfx-check` for spectrograms) · `make assets` · `make shot
SHOT_SCREEN=join|select|house|night|party` · `make shots` · `make editor` ·
`make export-linux` (`make setup-export` once) · `make tmux|tmux-d|tmux-n`.

## Making it our real house and cats

Everything below is placeholder until Oriol sends the real details (see
PLAN.md "Decisions taken (pending Oriol)"). Nothing here needs code.

**The house: `game/data/house.json`** (no regeneration needed; restart the game).
- `floors`: bottom to top; each has `rooms`, left to right. A room has `id`,
  `w` (pixels; a screen is 320 wide), `wall` and `floor` (tile names:
  `wall_wood`, `wall_orange_stripes`, `wall_yellow_dots`, `wall_white_tiles`,
  `wall_cyan_plain`, `wall_blue_stars`, `wall_green_flowers`; `floor_wood`,
  `floor_tiles`, `floor_carpet`), optional `window` `{x, y}`, `sunny` (x of
  sun patches), `furniture` `[{kind, x, y, cup}]` (`furn_*` names in
  `game/art/manifest.json`; `"cup": true` puts the knock-off cup on a table)
  and `spots` `[{id, kind, x, y}]`. `x` is from the room's left wall, `y` the
  height above the floor.
- A stairs room has `"kind": "stairs"`; `stairs` pairs link stairs rooms on
  adjacent floors. `bowls` and `start` name a room and an x.
- `spot_kinds`: each hiding-spot kind's sprite, `tags` (matched against the
  cats' `likes`), `tell` (`tail` or `eyes`), `tell_at` (pixel offset of the
  tell), `high` (needs coaxing down).
- Check it: `make test` (graph connected, every test also runs a second house
  from `game/tests/fixtures/house_flat.json`), then `make shot SHOT_SCREEN=house`.

**The cats: `game/data/cats.json`**, then `make sprites sfx` and look at
`art_src/cats_compare.png`.
- `look`: Sweetie 16 indices for `fur`, `fur_dark`, `fur_light`, `eyes`,
  `nose`, `collar`, `collar_tag`; `build` `fluffy` or `sleek`; `ears` `round`
  or `tall`; `patches` `[{where: chest|socks|face_blaze|tail_tip|belly,
  colour}]`. The collar colour is also the meow bubble, bowl and HUD colour.
- `personality`: `shy` (>= 0.5 needs the laser), `chatty` (>= 0.5 meows twice),
  `zoomies` (chance per round), `likes` (tag weights for hiding);
  `favourite_spots` (spot kinds, x3); `voice` (`pitch`, `parts`, `bright`,
  `length`, `vowels`) feeds the formant synth.
- More or fewer cats work (the tests run a three-cat fixture).

**Real meows**: drop phone recordings (mono or stereo WAV, any rate) at
`game/audio/real/meow_greyssie_*.wav` and `game/audio/real/meow_kira_*.wav`.
At start the game loads them instead of the synthesized voices
(`Game.install_real_voices()`; `test_real_meow_recordings_replace_the_synth`).
They are gitignored and never committed. Trim each to one meow, ~0.3–1.5 s.

**Privacy**: never commit family photos, the address, recordings or the real
room names beyond a plain list. Photos Oriol drops in `~/tmp/` are read
locally to derive palettes and markings, then left there.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are symlinks
into `../../shared/godot/autoload/` (read-only here). `game_state.gd` (`Game`):
- `Game.goto("join"|"select"|"house"|"party")`; flow join → select → house →
  party → select.
- Seats `Game.WALKER/LASER/TREATS` = 0/1/2; `Game.roster` (riders + private
  pack), `Game.HATS`, `Game.hats[seat]`, `Game.hat_color(seat)`.
- Data: `Game.house` (`house_data.gd`), `Game.cat_data` (`cat_data.gd`),
  `Game.load_data(house_path, cats_path)` (tests load fixtures).
- The day: `Game.DAY`, `round_index`, `start_round` (the night demo sets 3),
  `finds` (`{cat, kind, spot, round}` for the photo strip), `stars`,
  `days_played` (saved in `user://greyssie_and_kira.json` via `scripts/save.gd`,
  copied from Submarine Safari).
- `install_real_voices(dir)`: the real-meow hook (overrides `Sfx._streams`).

Game code (`game/scripts/`):

| file | what |
|---|---|
| `house/house_data.gd` | house.json → rooms, spots, stairs, world coordinates (floors stacked in 180 px bands), room graph (`path_rooms`, `connected`, `distance`) |
| `house/cat_data.gd` | cats.json → ids, collar colours, personalities; the Sweetie 16 table |
| `house/hide_director.gd` | where the cats hide: likes × favourites × night-cosy weights, never shared, not last round's spot |
| `house/cat.gd` | one cat: state machine (hidden, alert, peek, stalk, hop, free, chase, zoomies, walk-out, carried, eating, gag) and its sprite |
| `house/house_view.gd` | draws the dollhouse from the data: outside, roof/ceiling, wallpaper, floors, slab, doorways, stairs, windows per time of day, sun patches |
| `house/mini_view.gd` | the 64x40 whole-house view; lights the meowing room in the collar colour |
| `screens/house.gd` | the level: `step(dt)`, walker, stairs, spots, treats, laser, carrying, bowls, rounds, gags (cup boing, box too small), camera lean, HUD, pause |
| `screens/join.gd`, `select.gd`, `party.gd` | menus (copied from Pillow Fort and adapted) and the dinner → cuddle → bedtime party with the photo strip |
| `hat.gd` | the kids' seat hats |
| `demo_driver.gd` | scripted seats and the autopilot (follow the meow, open spots, laser the peeking cat, carry both to the bowls) |

### Asset names (the art and audio contract)

Art (`tools/sprites.py`, reads both JSON files; Sweetie 16, 1 px ink outline,
bottom-centre anchors, linted; `art_src/contact_sheet*.png`, `cats_compare.png`):

| name | size | frames |
|---|---|---|
| `<cat>_idle, _walk, _sit, _sleep, _stalk, _pounce, _eat, _carried, _zoomies, _alert` | 20x16 | 2 / 4 / 2 / 2 / 2 / 3 / 2 / 2 / 4 / 2 |
| `<cat>_tail_tip` (short, further out), `<cat>_peek_eyes`, `<cat>_face` | 8x12, 12x8, 12x12 | 2, 2, 1 |
| `meow_bubble_<cat>`, `bowl_<cat>` (empty, full) | 20x14, 12x8 | 2 |
| `walk_<rider>` 4, `climb_<rider>` 2, `carry_<rider>` 2 (private riders in the pack) | 16x20 | |
| `laser_dot` (plus a code-drawn ink ring and sparkle), `treat_bag`, `house_mini` | 5x5, 12x14, 64x40 | 2, 3, 1 |
| spots (closed, open): `sofa, bed, desk, wardrobe, cupboard, box, boxes, toy_box, laundry_basket, bathtub, sink, curtain, plant_pot, tv_box, cushion, sunny_window, wardrobe_top, bookshelf_top` | 18x10 – 56x64 | 2 |
| `furn_door, furn_coat_rack, furn_picture, furn_rug, furn_tv, furn_lamp (off/on), furn_fridge, furn_table, furn_washing_machine, furn_mirror, furn_bookshelf, furn_plant_small, furn_terrace_door (4 skies)`, `window` (morning, afternoon, evening, night) | | |
| tiles: `wall_*` 16x16, `floor_*` 16x8, `slab`, `ceiling`, `roof`, `stairs` 48x128, `banister`, `doorway` | | 1 |
| `toy_mouse, sock, wool_ball, dust_bunny, cup` | 8x8 | 2 |
| `heart, zzz, star, confetti, sparkle, seat_shoes, seat_laser, seat_treats, icon_pad, icon_kb, check, arrow_left, arrow_right` | | |

Audio (`tools/sfx.py`, reads cats.json for the meows; 44.1 kHz mono, SFX
-16 LUFS, voices -14, music -17, loops seamless): `treat_shake_1..3`, `psst`,
`meow_<cat>_1..3`, `mrrp`, `purr`, `prrt` (the plan's `hiss_free`: a playful
chirp, never a hiss), `pounce`, `zoomies`, `cup_boing`, `open_door`,
`open_box`, `stairs_step`, `bowl_fill`, `eat_crunch`, `find_star`,
`funny_find`, `day_chime`, `goodnight`, `giggle`, `whoosh`, `join`, `select`,
`ready`, `heart`; music `music_house` (90 BPM), `music_night` (72 BPM music
box), `music_menu` (100 BPM), `music_party` (105 BPM).

### Local divergences from shared code

No shared file is copied. `join.gd`, `select.gd` (Pillow Fort), `save.gd`
(Submarine Safari), `tools/sprites.py` (Pillow Fort's renderer plus cat,
house and walker generators) and `tools/sfx.py` (Zoo Keeper's formant synth)
are local copies, changed for this game. Proposed shared change: a
`Sfx.override(sound, streams)` API so the real-meow hook need not write
`Sfx._streams` (see PLAN.md).
