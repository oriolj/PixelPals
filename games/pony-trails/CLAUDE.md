# Pony Trails

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first, and load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).
Run every `make` below from this folder (`games/pony-trails/`), or from the
root with `make start G=pony-trails`. The plan, its decisions and its
deviations are in [PLAN.md](PLAN.md); how to play is in [README.md](README.md).

A horse day in three stages: groom the mare in the stable, ride the
countryside trail with her foal trotting beside her, and finish at the horse
show where everyone wins a rosette. The rosettes go on a wall that is kept
between sessions.

- **Seat 1, Rider** (the adult): picks the hooves and saddles up in the
  stable; rides the mare on the trail (walk, trot, canter, jumps with an
  assist); rides the show-jumping course.
- **Seat 2, Foal and brush** (the 5-year-old): scrubs the mud off with the
  brush and picks the braid ribbon; steers the tethered foal between three
  lanes and hops for apples; rides the foal's mini course.
- **Seat 3, Neigh** (the 2-year-old): ANY button is a big happy NEIGH. It
  gives the mare a carrot, opens the gates, makes the animals answer, rings
  the show bell. It can never hurt the run.

No game over, no text, no timers that end anything. Every step that waits
for one seat completes itself after 5 s. Personal (oriolj) scope.

## Rules

- **Godot 4.7 only** (the shared binary `../../.tools/godot`, renderer
  `gl_compatibility`). No Godot 3 APIs: no `yield`, `KinematicBody2D`,
  `export var`, `onready var`, `instance()`, `rand_range`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  scripts in `game/scripts/screens/<name>.gd`; the stage screens keep their
  logic in `step(dt)` so tests drive them frame by frame. The rules live in
  node-free scripts in `game/scripts/logic/`, unit tested.
- **Pixel-perfect.** 320x180, integer scaling, nearest filtering, snap on.
  Sprites scale by whole numbers only and are never rotated (flipped is fine).
- **Keyboard-only must always work**, with 1, 2 or 3 seats, pads mixed in.
- **No text in the UI.** Counts are drawn as icons.
- **The Neigh seat can never hurt the run.** Its presses only add things.
- **Assets load from source bytes** (shared `art.gd`/`sfx.gd`, plus
  `scripts/view/tex.gd` for single frames and animation ranges and
  `scripts/view/loop_audio.gd` for the loops). Every run/test target depends
  on `ensure-import`.
- **The family rosette wall is sacred**: the demo and the tests never touch
  `user://rosette_wall.json`. The demo uses `user://rosette_wall_demo.json`,
  the tests `user://test_rosette_wall*.json`.
- **Third-party riders** (Sonic, Mario and the rest) are in
  `game/private_pack/` and `art_src/private/`, copied from PixelPals and
  committed only because the repo is private. `make export-linux` excludes
  them. Never publish them.
- **Verify before claiming**: `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=trail` · `make test` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=show` ·
`make shots` · `make editor` · `make export-linux` (after `make setup-export`).
`make help` lists them; the tmux targets live in the root Makefile.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only from here).
`game_state.gd` is this game's:

- `Game.goto("join"|"select"|"stable"|"trail"|"show"|"party")`.
  Flow: `join -> select -> stable -> trail -> show -> party -> select`.
  `Game.start_stage` (0 stable, 1 trail, 2 show) is picked on the select
  screen; `Game.STAGES` maps it to a screen, `Game.next_after(screen)`.
- `Game.mare_coat` (default `bay`), `Game.foal_coat` (default `palomino`),
  `Game.MARE_COATS` (bay, chestnut, palomino, grey, black, pinto),
  `Game.FOAL_COATS` (the same plus appaloosa).
- The day (`Game.day`): ribbon colour, carrots, apples, flowers, lucky
  horseshoes, clean jumps, foal jumps, and the rosettes won. `Game.new_day()`.
- `Game.wall` (`scripts/logic/rosette_wall.gd`): the persistent rosette wall
  and lucky horseshoes, stored with `scripts/save.gd` (versioned JSON).
- `Game.day_scale` shortens the stages (the demo uses about 0.4).
- Seat fall-backs: `Game.neigh_pressed()` (the Neigh seat's any button; with
  no Neigh seat, the Rider's B), `Game.foal_auto()` (no Foal seat: the brush
  scrubs by itself and the foal follows by itself), `Game.has_toddler()`.
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`; `--mute`.
  A `--demo=stable` run plays the whole day: stable -> trail -> show ->
  party -> select.

Logic (`game/scripts/logic/`, node-free, unit tested):

| file | what |
|---|---|
| `grooming.gd` | the four mud patches (2 s of scrubbing each, 4 fade stages), the brush's spot-graph hop to the nearest patch in a direction (Pillow Fort's hotspot pattern), carrots (every third to the foal), hooves, the saddle that needs all four, the ribbon, the stable cat after 90 s |
| `mare_ride.gd` | gaits from the stick (walk 26, trot 48, canter 74 px/s), the jump assist (+-0.4 s around the takeoff point, the jump then starts exactly there), the slower step-over, the happy hop, stopping at a closed gate |
| `foal_tether.gd` | the spring-bound x (never more than 40 px from the mare), 3 eased lanes, the hop, the self-steering foal |
| `trail_course.gd` | the seeded course (six fields, five gates, obstacles, lanes of apples and flowers, two lucky horseshoes, twigs, animals, puddles, props), the neigh (gate, nearest animal, herd), gate clocks (5 s, 1 s with no toddler), the weather keys |
| `show_course.gd` | the rounds (bell, 6 jumps around the ring with one refusal then an automatic clear, bell, 4 mini jumps, 4 colour poles, rosettes), `award()` |
| `rosette_wall.gd` | the persistent wall (last 12 days, the horseshoes) |

Screens (`game/scripts/screens/`): `join`, `select` (rider, coat, stage row),
`stable`, `trail`, `show`, `party`; each stage runs from `step(dt)` and has
the Rider-only pause (`scripts/view/pause.gd`). Views: `tex.gd` (frames,
`anims.json` ranges, `points.json` anchors), `anim_sprite.gd`,
`confetti.gd`, `backdrop.gd` (menus), `loop_audio.gd` (hoof and rain loops).

Tests (`game/tests/`, 51, GUT): `logic/` (grooming, ride, course: every
rule the plan names), `stages/` (the cat at 90 s, the toddler never hurting,
the 1- and 2-seat fall-backs, the pause, the stage select, the show and the
party end to end), `menus/` (join, select, demo driver), `test_players`.
`tests/helpers.gd` drives a screen frame by frame with scripted seats.

### Art (the contract between `tools/` and the game)

Palette: **Endesga 32** (`art_src/palettes/endesga32.hex`; chars `0-9a-v`).
`tools/sprites.py` (Submarine Safari's renderer with Space Mission's
`REMAP_OVERRIDES` and a riding-helmet overlay) renders the grids in
`art_src/*.txt` and the procedural sprites of `tools/art_gen.py` to
horizontal strips in `game/art/<name>.png` + `game/art/manifest.json`, lints
them (palette, alpha, sizes, every coat in the palette) and writes contact
sheets in `art_src/`. It also writes two more JSON files the game reads:

- `game/art/anims.json`: named frame ranges per sprite family:
  `{"mare": {"stand": [first, count, fps], "walk": [...], ...}, "foal": {...},
  "mare_big": {...}}`. Every `mare_<coat>` shares the `mare` ranges, and so on.
- `game/art/points.json`: anchor points in sprite pixels (top-left origin):
  - `mare.rider`: a list, one `[x, y]` per frame: where the rider's feet
    centre sits (the saddle), so the rider bobs with the gait;
    `mare.passenger`: the same for the passenger behind the saddle;
    `mare.braid`: per-frame `[x, y]` of the mane bow.
  - `foal.hat`: per-frame `[x, y]` of the top of the foal's head (the hat).
  - `mare_big.patches`: `{"head": [x, y], "back": ..., "legs": ...,
    "tail": ...}` the top-left of each mud sprite on the 80x64 mare;
    `mare_big.hooves`: four `[x, y]` (the ground point of each hoof, in the
    order of the hoof-lift frames: front near, front far, hind near, hind
    far); `mare_big.braid`, `mare_big.mouth`, `mare_big.saddle`: `[x, y]`.

Sprites (frames left to right; horses face right; the feet stand on the
bottom row of the frame):

| name | size | frames | use |
|---|---|---|---|
| `mare_<coat>` | 40x32 | 25: stand 2, walk 4, trot 4, canter 4, jump 3 (takeoff, air, land), neigh 2, munch 2, hoof 4 | the trail and show mare, saddled and bridled; six coats |
| `foal_<coat>` | 24x20 | 13: stand 2, trot 4, hop 3, neigh 2, sleep 2 | the foal; seven coats |
| `mare_big_<coat>` | 80x64 | 10: idle 2, munch 2, ear 2, hoof 4 (one per hoof) | the stable view, no tack |
| `mare_big_tack` | 80x64 | 10 | saddle and bridle overlay, aligned to every `mare_big` frame |
| `mud_head`, `mud_back`, `mud_legs`, `mud_tail` | 12-20 px | 4 | fade stages 0 (muddy) to 3 (faint) |
| `coat_<coat>` | 16x16 | 1 | coat swatch (a horse head) for the select screen |
| `brush` | 16x12 | 2 | bristles wiggle |
| `hoof_pick` | 12x12 | 1 | the adult's tool |
| `hand` | 12x12 | 2 | open, pointing |
| `carrot` | 12x8 | 1 | |
| `saddle` | 24x16 | 1 | on the saddle rack |
| `bridle` | 16x16 | 1 | on its hook |
| `horseshoe` | 8x8 | 2 | shiny shoe glint (frame 1 = glint) |
| `pebble` | 4x4 | 1 | pops out of a hoof |
| `ribbon_red`, `ribbon_blue`, `ribbon_yellow`, `ribbon_purple` | 8x8 | 1 | the braid bow |
| `heart` | 8x8 | 1 | carrot love |
| `sparkle` | 8x8 | 4 | bristles, clean coat, pickups |
| `stall_wall`, `stall_floor` | 16x16 | 1 | stable tiles (planks, straw) |
| `stall_door` | 32x48 | 3 | closed, half open, open |
| `half_door` | 32x24 | 1 | the foal peeks over it |
| `hay_rack` | 24x16 | 1 | |
| `saddle_rack` | 24x24 | 1 | the saddle is drawn on it |
| `water_trough` | 32x12 | 1 | |
| `lantern` | 8x12 | 2 | flicker (party at dusk) |
| `stable_cat` | 16x12 | 4 | walk 2, sit 2 |
| `sky_morning`, `sky_rain`, `sky_afternoon`, `sky_golden` | 320x60 | 1 | the four times of day |
| `hills_far` | 320x60 | 1 | far hills with the windmill; transparent sky; seamless |
| `trees_mid` | 320x48 | 1 | mid trees and hedges; seamless |
| `grass`, `path` | 16x16 | 1 | ground tiles |
| `fence` | 16x16 | 1 | near fence tile |
| `gate` | 32x24 | 3 | closed, half, open |
| `barn`, `tree`, `bush`, `reeds` | 48x40, 24x32, 16x12, 16x16 | 1 | trail props (additions) |
| `log`, `stream`, `hay_bale` | 20x8, 32x10, 16x12 | 1, 2, 1 | the mare's obstacles (stream shimmers) |
| `twig_log` | 12x6 | 1 | the foal's small logs |
| `puddle`, `splash` | 16x4, 16x8 | 1, 3 | the rain |
| `apple` | 8x8 | 2 | sparkle |
| `flower_pink`, `flower_blue`, `flower_yellow` | 8x8 | 2 | wildflowers |
| `lucky_horseshoe` | 8x8 | 2 | the rare one |
| `rabbit` | 12x10 | 4 | hole, peek, up, ears wiggle |
| `sheep` | 16x12 | 4 | graze 2, run 2 |
| `duck` | 10x8 | 4 | swim 2, flap 2 |
| `cow` | 24x16 | 2 | idle, moo (head up) |
| `bird` | 8x6 | 2 | flap |
| `wild_horse_1`, `wild_horse_2`, `wild_horse_3` | 32x24 | 5 | gallop 4, whinny 1 |
| `rainbow` | 160x60 | 1 | |
| `show_fence` | 16x16 | 1 | white rail |
| `jump_1` .. `jump_6` | 24x24 | 1 | coloured poles on wings |
| `mini_jump` | 12x10 | 1 | the foal's jumps |
| `cone_red`, `cone_blue`, `cone_yellow`, `cone_green` | 8x10 | 1 | pick-the-colour cones |
| `pick_pole` | 8x24 | 1 | a pole with a white flag (the colour is drawn in code) |
| `flag` | 8x8 | 2 | bunting flag, waves |
| `grandstand` | 96x32 | 1 | the crowd's bench (riders sit on it) |
| `judge` | 24x32 | 2 | a friendly old horse in a hat; nod |
| `bell` | 16x16 | 2 | still, ringing |
| `rosette_blue`, `rosette_red`, `rosette_yellow`, `rosette_green`, `rosette_purple` | 12x16 | 1 | |
| `rosette_wall` | 320x180 | 1 | the party wall (planks, a board, the door) |
| `confetti` | 4x4 | 6 | one colour per frame |
| `seat_rider`, `seat_brush`, `seat_neigh` | 16x16 | 1 | role icons (horseshoe, brush, whinnying head) |
| `stage_stable`, `stage_trail`, `stage_show` | 16x16 | 1 | start-stage icons (horseshoe, tree, rosette) |
| `icon_pad`, `icon_kb`, `check`, `arrow_left`, `arrow_right`, `arrow_up`, `arrow_down` | 16x16 / 8x8 | 1 | menus |
| `penguin`, `monkey`, `fox`, `frog`, `robot` | 16x16 | 2 | riders (PixelPals grids) |
| `jockey_<rider>_<seat>` | 16x16 | 2 | derived: the rider in a riding helmet in the seat colour (seat 0 `0099db`, seat 1 `fee761` (the darker `feae34` read orange on the fox), seat 2 `63c74d`) |

`tools/horses.py` draws the horses: one posed skeleton with 2-bone IK legs
per frame, recoloured per coat; pinto patches, the appaloosa blanket and
grey dapples are overlay masks. `points.json` also carries `mare.mouth`,
`foal.mouth`, `mare_big.patch_sizes` and `rosette_wall` (`board`, `door`).
The hooves stand on the row above the bottom one (the ink outline). Review
sheets: `art_src/gait_sheet.png` (every gait at 1x, 4x and in silhouette,
every coat), `art_src/contact_sheet*.png`, `art_src/jockey_sheet.png`.

Coats: `bay`, `chestnut`, `palomino`, `grey`, `black`, `pinto` (mare and
foal) and `appaloosa` (foal only).

### Audio

`tools/sfx.py` (Zoo Keeper's synth with its formant voice), 44.1 kHz mono
16-bit, SFX about -15 LUFS, loops -14 LUFS, no peak above -1 dBFS:

- voices: `neigh_1..4` (the mare), `foal_neigh_1..2` (higher), `snort`, `nicker`;
- hooves: `walk_loop`, `trot_loop`, `canter_loop` (the clip-clop of one
  gait, loop length a whole number of stride cycles: walk 1.0 s per cycle,
  four beats; trot 0.5 s, two beats; canter 0.6 s, three beats and a
  pause; the animations use the same cycle), `jump_hup`, `step_hup`
  (the funny step-over), `land_thud`;
- stable: `brush_scrub`, `mud_poof`, `munch_1..3`, `hoof_pick_ping`,
  `horseshoe_clink`, `saddle_creak`, `door_creak`, `stable_cat_meow`;
- trail: `gate_open`, `apple_pop`, `flower_pick`, `lucky_chime`, `splash`,
  `rain_loop`, `rainbow`, `baa`, `quack`, `moo`, `bunny_boing`, `birds`,
  `wild_herd`;
- show: `bell_ding`, `crowd_clap`, `crowd_ooh`, `confetti`, `rosette_fanfare`;
- menus: `join`, `select`, `ready`, `whoosh`;
- music: `music_stable` (84 BPM), `music_trail` (126 BPM, 6/8), `music_show`
  (105 BPM), `music_menu` (90 BPM); every beat is a whole number of samples.

## Local copies instead of shared changes

`shared/` is read-only for this game; these are proposed extractions:

- `tools/sprites.py`: Space Mission's renderer (palette remap with
  `REMAP_OVERRIDES`) with the riding-helmet overlay, the coat lint and the
  `anims.json`/`points.json` outputs.
- `game/scripts/save.gd`: Submarine Safari's versioned JSON saver (the
  proposed `shared/godot/save.gd`).
- `game/scripts/view/tex.gd`, `anim_sprite.gd`: named animation ranges and
  anchor points on top of the shared `Art`, which only knows one looping
  "default" animation per strip.
- `game/scripts/view/loop_audio.gd`: looping players (the shared `Sfx` has
  one-shots and one music player only).
