# Paint Party

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first, and load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).
Run every `make` below from this folder (`games/paint-party/`), or from the
root with `make start G=paint-party`. The plan and its decisions are in
[PLAN.md](PLAN.md); how to play is in [README.md](README.md).

The family paints one big picture together on an easel, then frames it and
hangs it in a gallery; the PNG is saved for printing.

- **Seat 1, Brush** (adult): moves the round brush, paints while "a" is held,
  "b" cycles 3 sizes, "start" opens the menu (undo, frame it, keep painting,
  surprise splats, back to join).
- **Seat 2, Colourist** (5-year-old): each d-pad direction picks one of 4
  pots, "a" stamps the next shape at the brush, "b" turns the palette page.
- **Seat 3, Splatter** (2-year-old): any button throws a splat onto the least
  painted part of the canvas.

## Rules

- **Godot 4.7 only** (`../../.tools/godot`). No Godot 3 APIs (`yield`,
  `export var`, `onready var`, `VisualServer`...). GDScript, static types
  where cheap. Scripts reference each other with `preload` consts, not
  `class_name`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  scripts in `game/scripts/screens/<name>.gd` extending `Node2D`.
- **Vector art, not pixel art** (the one exception to the house pixel rule,
  decided in the plan): 640x360 base, `canvas_items` stretch, linear
  filtering, window 1280x720. Edges are smoothed with anti-aliased draw calls
  (`draw_polyline(..., true)`, `draw_circle(..., antialiased=true)`), because
  the Compatibility renderer has no 2D MSAA. The riders are the only pixel
  art: PixelPals's 16x16 sprites at x3 with `TEXTURE_FILTER_NEAREST`.
- **Keyboard-only, and 1, 2 or 3 seats.** No text in the UI, no game over,
  no timer. Only the Brush can undo; nothing a kid presses can hurt the picture.
- **Paintings never go in the repo.** They are family material: user://
  (`~/.local/share/godot/app_userdata/Paint Party/paintings/`) and
  `~/Pictures/PaintParty/`. Demo runs save to `shots/gallery/` (gitignored)
  and never copy to Pictures; tests use `OS.get_temp_dir()`.
- **Assets load from source bytes** (shared `art.gd` / `sfx.gd`, and the
  brush loop in `paint.gd` the same way); every run/test target depends on
  `ensure-import`.
- **Third-party riders** (`game/private_pack/`, `art_src/private/`) are
  PixelPals's private pack, committed only because the repo is private.
  `make export-linux` excludes it.
- **Verify before claiming**: `make test` (logic headless + render under
  xvfb), then `make shots` and look at `shots/<screen>/sheet.png` and
  `shots/paint/painting.png`.

## Commands

`make setup` · `make start` · `make demo` · `make test` (= `test-logic` +
`test-render`) · `make sprites` · `make sfx` · `make assets` ·
`make shot SHOT_SCREEN=paint SHOT_SECONDS=32` · `make shots` · `make editor` ·
`make export-linux` · `make setup-export`. `make help` lists them.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are symlinks
into `../../shared/godot/autoload/` (read-only here; edit them in `shared/`).
`game_state.gd` (Game) is this game's:

- `Game.goto("join"|"select"|"paint"|"party")`; flow join → select → paint →
  party → select.
- `Game.roster`, `Game.rider_color()` as in PixelPals.
- `Game.paint_dir` (default `user://paintings`), `Game.pictures_dir`
  (default `~/Pictures/PaintParty`, "" = no copy), `Game.shot_dir` (demo:
  also writes `painting.png`). Command line: `-- --demo[=screen]`,
  `--save-dir=`, `--shot-dir=`, `--mute`, `--quit-after-seconds=`.
- `Game.gallery(n)`: framed pictures, newest first. `Game.load_png(path)`
  reads a PNG by bytes. `Game.last_painting` (Image) / `last_painting_path`.
- `Game.surprise_splats`: the menu option for games without a Splatter.

Seats: `Players.Seat.DRIVER/GUNNER/HONKER` = Brush / Colourist / Splatter
(`paint.gd` names them `BRUSH`, `COLOURIST`, `SPLATTER`). The Colourist uses
the shared `Players.dir4_just_pressed(seat)`.

Paint logic (`game/scripts/paint/`, plain `RefCounted` data, tested headless):

| file | what |
|---|---|
| `palette.gd` | 12 colours on 3 pages of 4 pots; pot order up/right/down/left (`DIRS`, `pot_for_dir`) |
| `stroke.gd` | dabs every radius/4 between frame positions, the leftover carried over |
| `coverage.gd` | 16x9 coverage grid (64x36 fine cells), `least_covered()`, `neighbours()` |
| `splatter.gd` | 0.5 s cooldown, every 5th splat rainbow, placement on the least covered cell, radius shrinks with painted neighbours, area ≤ 8 % |
| `shapes.gd` | stamp polygons (star, heart, flower, fish, sun, cat, car, house), splat blob + drips + droplets, soft dab image |
| `undo_ring.gd` | last 10 snapshots |
| `autosave.gd` | 30 s clock, saves only when the picture changed |
| `brush_input.gd` | "a" state machine: paint, or tap (< 0.2 s, not moving) = stamp in tap mode |
| `painter.gd` | the 1920x1080 SubViewport (`CLEAR_MODE_NEVER`, `UPDATE_ONCE` per batch of ops), `snapshot()`, `save_png()`, `restore()` |

Painter trap: the SubViewport needs `transparent_bg = true` in the
Compatibility renderer, otherwise its texture's alpha stays 0 and the
painting shows as see-through on screen; and the first render can be dropped
when the game boots straight into the paint screen, so the paper is laid
again during the first frames until something else is drawn.

UI: `game/scripts/ui/draw_kit.gd` draws the pots, easel, gold frame (bevel by
vertex-colour gradients), wall, floor, and the role/device/menu icons.

Undo: each action (a stroke, a stamp, a splat) pushes
`{img: painter.snapshot(), cov: coverage copy}` BEFORE it draws; actions in
the same frame share one snapshot. Headless the image is null (the ring still
counts), which is why pixel tests live in `game/tests_render/`.

### Asset names

Sprites (`game/art/`, from `art_src/riders.txt` by `tools/sprites.py`, Sweetie 16):

| name | size | frames | use |
|---|---|---|---|
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (shown at x3, nearest) |
| private pack: sonic, shadow, knuckles, robotnik, minion_tall, minion_short, minion_bob, mario, luigi | 16x16 | 2 | private riders |

Everything else is drawn in code: pots, easel, gold frame, gallery wall,
icons (`draw_kit.gd`); stamps, splats and the brush dab (`shapes.gd`).

Sounds (`game/audio/`, from `tools/sfx.py`, about -15 LUFS, peaks ≤ -1 dBFS):

| name | use |
|---|---|
| `brush_loop` | seamless 2 s swish, looped while painting, pitch and volume follow brush speed |
| `stamp_1`…`stamp_4` | rubber thunk + bell (random variant) |
| `splat_1`…`splat_4` | wet noise burst + low drop + droplets |
| `rainbow` | the rainbow splat: splat + pentatonic run up |
| `pot_pick_1`…`pot_pick_4` | one pentatonic note per pot (C D E G) |
| `page_turn`, `undo`, `frame_it`, `clap`, `giggle` | page, undo (reverse whoosh), ta-da, crowd claps, toddler cooldown |
| `join`, `select`, `ready`, `party`, `whoosh` | menus (PixelPals's) |
| `music_paint` | 80 BPM G major loop, 3 dB under the menu music |
| `music_menu` | PixelPals's menu loop |

## Tests

- `game/tests/` (headless, `make test-logic`): players, join, select, party,
  demo driver (a full 30 s scripted paint run), paint logic, paint screen.
- `game/tests_render/` (xvfb, `make test-render`): saved PNG is 1920x1080 and
  not blank, undo restores pixels, the stamp lands at the brush (catches a
  flipped readback), frame-it saves to the paint dir and the Pictures copy.
