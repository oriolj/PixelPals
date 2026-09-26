# Digger Treasure

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below from
this folder (`games/digger-treasure/`), or from the root with `make start G=digger-treasure`.
The plan and its history are in [PLAN.md](PLAN.md).

Dad drives a little yellow digger through a side-view slice of dirt, the
5-year-old swings the scoop arm to dig where they choose, and the
2-year-old's any-button "boom" blasts a round hole that pops buried treasure
up into the air. Every treasure flies into the dump truck; a full truck (or
the five-minute fountain) ends the run in a party. Personal (oriolj) scope.
Load the **video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (shared binary at the repo root `.tools/godot`). No Godot 3
  APIs: no `yield`, `Image.lock()`, instance `ImageTexture.create_from_image`,
  CanvasItem `update()` (use `queue_redraw()`), `export var`, `onready var`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  scripts in `game/scripts/screens/<name>.gd` that build their children in `_ready()`.
- **Pixel-perfect.** 320x180 canvas, integer scaling, nearest filtering. Round
  node positions; scale sprites only by whole numbers; rotate only by 90 degrees.
- **Keyboard-only must always be playable**, with 1, 2 or 3 seats, pads and keys mixed.
- **No text in the game UI, no game over.** The boomer (seat 3) can never hurt
  the run: a boom only ever clears dirt, never moves the digger or costs time.
- **Assets load from source bytes**, never the import cache (shared `art.gd`,
  `sfx.gd`, and this game's `scripts/art_image.gd`). Run/test targets depend on
  `ensure-import`.
- **Third-party characters** live in `game/private_pack/` and `art_src/private/`
  (copied from PixelPals, committed only because the repo is private).
  `make export-linux` excludes the pack.
- **Verify before claiming:** `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png`.

## Commands

`make setup` · `make start` · `make demo` (SHOT_SCREEN=dig by default) · `make test` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=dig` · `make shots` ·
`make editor` · `make export-linux` · `make setup-export` · `make tmux|tmux-d|tmux-n`.
`make help` lists them all.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are **symlinks into
`../../shared/godot/autoload/`** (read-only here). `game_state.gd` is this game's:

- `Game.goto("join"|"select"|"dig"|"party")`; `Game.roster` (rider ids + private pack);
  `Game.digger_skin` / `Game.digger_sprite()` (the driver's paint job);
  `Game.found` (treasure kinds in arrival order, read by the party);
  `Game.run_seconds` (0 = 5 minutes; demo mode sets 20).
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`.

Seats (Players.Seat names from PixelPals): `DRIVER` = driver (blue), `GUNNER` =
scooper (yellow), `HONKER` = boomer (green).

Dig logic (`game/scripts/dig/`), pure and unit tested:

- `terrain_grid.gd`: 240x80 cells of 4x4 px (`PackedByteArray`, 0 air, 1-3 dirt
  bands, 9 rock border). `dig_circle`, `dig_rect`, `dig_cell`, `is_solid`,
  `exposed(cells)`, `dirt_depth`, `free_around`, and a `dirty` rect for the view.
  Above the field (y < 0) counts as open sky. Candidate for `shared/` later.
- `digger_body.gd`: the 24x20 box swept one pixel at a time per axis. A pixel
  that digs costs a whole cell of time (average DIG_SPEED through dirt, a chomp
  per cell); rock and the field edges stop it; `stuck_step` clears a pocket
  after 2 s boxed in.
- `rules.gd`: constants (run 300 s, boom radius 7 cells / cooldown 1.2 s,
  auto-boom 20 s, scoops 5x5 and 3x3, glint radius) plus `snap4`, `scoop_rect`,
  `truck_frame`.
- `layout.gd`: 16 fixed treasure spots (12 used, shuffled with the six kinds
  twice each), 24 small-find spots, 6 caves, the start pocket, the demo spots.
- `terrain_view.gd`: one 960x320 `Image` + `ImageTexture`; `flush()` repaints only
  the dirty cells (+1 margin for edges) and calls `texture.update()` once a frame.

Screens: `join.gd`, `select.gd` (copied from PixelPals; select adds the digger
paint on the driver's up/down and helmets), `dig.gd` (all logic in `step(dt)`
for tests), `party.gd`. `scripts/rider_view.gd` is a rider wearing a hard hat
in its seat colour (the helmet finds the top of the head from the rider's pixels,
so private-pack riders get one too).

Local helpers instead of shared changes (see "Proposed shared changes" below):
`scripts/art_image.gd` (raw Image of a sprite strip), `dig.gd::_set_music_db`
(ducks the music during a boom by reaching into `Sfx._music`).

### Asset names (the art and audio contract)

Sprites, Sweetie 16, from `art_src/*.txt` grids and the generators in
`tools/sprites.py` (lint + contact sheet in `art_src/contact_sheet*.png`):

| name | size | frames | use |
|---|---|---|---|
| digger (+ digger_red, digger_blue, digger_green) | 32x24 | 4 | 0-1 drive bob, 2-3 dig shake; faces right |
| scoop_arm / scoop_arm_driver | 16x8 | 1 | scooper's yellow arm / driver's blue arm; pivot at the left edge, rotated by 90 degrees |
| dump_truck | 48x24 | 4 | empty, half, full, tipping (party) |
| treasure_chest, crown, dino_egg, gems, coins, toy_robot | 16x16 | 2 | idle, glint |
| worm, snail, bone, fossil, mole | 16x16 | 2 | small finds (mole frame 1 waves) |
| glint | 8x8 | 4 | twinkle through the dirt (the code walks 0..top..0) |
| dirt_chunk | 4x4 | 4 | particles: topsoil, clay, deep clay, rock |
| boom_ring | 64x64 | 5 | flash, then a green ring growing to radius 7 cells |
| grass_strip | 320x16 | 1 | grass lip over the field, tiles horizontally |
| sky_hills | 320x48 | 1 | PixelPals hills recoloured |
| dirt_tex | 4x4 | 6 | cell textures (plain x2, crumb x2, pebble x2), recoloured per band in code |
| helmet, helmet_blue, helmet_green | 12x6 | 1 | hard hats in the seat colours |
| seat_driver, seat_scooper, seat_boomer | 16x16 | 1 | role icons (wheel, spade, boom) |
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (from PixelPals) |
| icon_pad, icon_kb, check, arrow_left, arrow_right, confetti, trophy, cloud_bg | as PixelPals | | menus and party |

Sounds (`tools/sfx.py`, 44.1 kHz mono, SFX at -15 LUFS): `dig_1..3`, `scoop`,
`boom`, `puff`, `donk`, `glint`, `treasure_pop`, `truck_clunk`, `worm_squeak`,
`mole_hello`, `join`, `select`, `ready`, `party`, `whoosh`; music `music_menu`
(F major 100 BPM) and `music_dig` (C major 108 BPM, 8 bars; ducks 4 dB during a boom).

### Screen flow

`join` → `select` → `dig` → `party` → `select`.

- **join:** any device takes the next seat; the driver's start (or holding "a") goes on.
- **select:** left/right picks a rider, "a" readies; the driver's up/down picks the
  digger paint; the boomer's any press cycles and auto-readies.
- **dig:** the driver's start pauses; in pause, "b" goes back to join. With no
  boomer seated, a surprise boom goes off every 20 s.
- **party:** the truck tips, the treasures bounce into a row, then select.

## Proposed shared changes (not made: shared/ is read-only for this game)

- `art.gd`: an `Art.image(name) -> Image` accessor (what `scripts/art_image.gd` does).
- `sfx.gd`: `Sfx.set_music_volume(db)` / `Sfx.duck(db, seconds)` instead of
  touching `Sfx._music`.
