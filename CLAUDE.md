# PixelPals

A couch co-op pixel-art game for Oriol and his kids (5 and 2). Everyone shares
one flying bathtub that scrolls on its own through the sky:

- **Seat 1, Driver** (dad): steers the tub with the stick or WASD.
- **Seat 2, Gunner** (the 5-year-old): aims in 4 directions and fires. Aim
  assist is generous.
- **Seat 3, Honker** (the 2-year-old, optional): ANY button honks. It always
  does something delightful and never hurts the run.

There is no game over, no lives, no text on screen, and a run lasts about 3
minutes. Personal (oriolj) scope. Load the **video-games** skill
(`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`) for the house rules.
Write every new lesson there, or in its `references/field-notes.md`.

## Rules

- **Godot 4.7 only** (pinned in the Makefile, binary at `.tools/godot`). No
  Godot 3 APIs: no `yield`, `KinematicBody2D`, `export var`, `onready var`,
  `instance()`. Use GDScript with static types where cheap.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are scripts in `game/scripts/screens/<name>.gd` that extend `Node2D` and
  build their children in `_ready()`. Do not hand-write scene files.
- **Pixel-perfect.** The canvas is 320x180, integer-scaled with nearest
  filtering. Keep positions integer when drawn (snap is on in project
  settings). Scale sprites only by whole numbers; rotate only by multiples of
  90 degrees.
- **Keyboard-only must always be playable.** Every feature works with the
  three keyboard blocks, and with pads and keyboard mixed.
- **No text in the game UI.** Use icons, colours and characters. (Debug
  overlays are fine behind a flag.)
- **Never let a child's input end or hurt the run.**
- **Third-party characters** (Sonic, Knuckles, Robotnik, Minions) live only
  in gitignored `game/private_pack/` and `art_src/private/`. Never commit
  them, never show them in anything published. The committed cast is
  penguin, monkey, fox, frog and robot.
- **Verify before claiming.** Run `make test` for logic and `make shot
  SHOT_SCREEN=<screen>` for visuals, then look at `shots/<screen>/sheet.png`
  (it is upscaled for inspection).

## Commands

`make setup` · `make start` (play) · `make demo` (plays itself) · `make test` ·
`make sprites` · `make sfx` · `make assets` · `make shot SHOT_SCREEN=level` ·
`make shots` · `make editor` · `make export-linux` · `make tmux` / `tmux-d` /
`tmux-n`. Run `make help` for the full list.

## Architecture: the contracts

Autoloads (`game/autoload/`):

- **Players** (`players.gd`): seats and input. Always ask per SEAT:
  - `Players.move(seat)` returns an analog `Vector2`.
  - `Players.dir4(seat)` returns a `Vector2i` in 4 directions.
  - `Players.pressed(seat, b)` / `Players.just_pressed(seat, b)`, with `b` in
    `"a"`, `"b"`, `"start"` or `"any"`.
  - Constants and state: `Players.Seat.DRIVER/GUNNER/HONKER`,
    `Players.SEAT_COLORS`, `Players.riders[seat]`.
  - Devices: `pad:<id>`, `kb:0` (WASD + Shift/Tab, Q back, Esc start),
    `kb:1` (arrows + Enter/Ctrl, Backspace back, P start), `kb:2` (Space
    and every unowned key), and `demo:<n>` (scripted with
    `Players.set_scripted`).
- **Game** (`game_state.gd`):
  - `Game.goto("join"|"select"|"level"|"party")` switches screens.
  - It holds `Game.roster` (rider ids, original set plus the private pack's
    `riders.json`), and `Game.stars` / `Game.run_seconds` for the results.
  - Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`.
- **Art** (`art.gd`):
  - `Art.sprite(name, tint, fallback_size)` returns a playing
    `AnimatedSprite2D`. `Art.frames(...)` returns the `SpriteFrames`, and
    `Art.size_of(name)` the frame size.
  - When no PNG exists yet it returns a solid placeholder rectangle, so code
    never waits for art.
  - The PNGs are horizontal frame strips in `game/art/`, described by
    `game/art/manifest.json`.
- **Sfx** (`sfx.gd`): `Sfx.play(name, pitch, volume_db)`, `Sfx.music(name)`.
  Files are `game/audio/<name>.wav` or variants `<name>_1.wav`,
  `<name>_2.wav`… A missing file is a no-op.

### Asset names (the art and audio contract)

Sprites (w x h, frames). They are generated from `art_src/*.txt` by
`tools/sprites.py` in the Sweetie 16 palette:

| name | size | frames | use |
|---|---|---|---|
| tub | 48x24 | 2 | the flying bathtub (bobbing) |
| penguin, monkey, fox, frog, robot | 16x16 | 2 | riders (idle bounce), face right |
| turret | 8x8 | 1 | cannon pointing right (rotated by 90-degree steps in code) |
| bullet | 6x6 | 2 | gunner shot |
| balloon | 16x24 | 2 | harmless target, pops into stars |
| cloud_grump | 24x16 | 2 | grumpy cloud, bumps the tub, pops when shot |
| cloud_scared | 24x16 | 2 | the same cloud startled by a honk (harmless while scared) |
| bird | 8x8 | 2 | flies up when the honker honks |
| flower | 8x8 | 2 | frame 0 closed, frame 1 open (blooms on honk) |
| star | 8x8 | 4 | collectible (spinning) |
| big_star | 24x24 | 4 | the "big moment" a honk collects |
| heart | 8x8 | 1 | hit feedback |
| confetti | 4x4 | 6 | one colour per frame |
| hills | 320x48 | 1 | parallax far background strip, tiles horizontally |
| ground | 16x16 | 1 | ground tile |
| cloud_bg | 32x16 | 1 | decorative background cloud |
| seat_driver, seat_gunner, seat_honker | 16x16 | 1 | seat role icons (wheel, cannon, horn) |
| icon_pad, icon_kb | 16x16 | 1 | device icons on the join screen |
| arrow_left, arrow_right | 8x8 | 1 | selection arrows |
| check | 8x8 | 1 | ready tick |
| trophy | 24x24 | 2 | party screen |

The private pack is `sonic`, `knuckles`, `robotnik`, `minion_tall` and
`minion_short`, each 16x16 with 2 frames. Its files are
`game/private_pack/art/` plus its own `manifest.json`, and
`game/private_pack/riders.json`.

Sounds: `honk_1`…`honk_4`, `shoot`, `pop`, `star`, `hit`, `join`, `select`,
`ready`, `bigstar`, `party`, `whoosh`, `music_menu`, `music_level`.

### Screen flow

`join` → `select` → `level` → `party` → `select`.

- **join:** any device presses to take the next seat. The driver (seat 1)
  presses start, or holds "a" for 1 s, to go on.
- **select:** each seat picks a rider with left/right and presses "a" to be
  ready. For the honker, any press cycles.
- **level:** the driver's start pauses; in pause, the driver's "b" goes back
  to join.
- **party:** shows the stars collected.
