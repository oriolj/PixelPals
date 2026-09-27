# Tower Topple

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/tower-topple/`), or from the root with
`make start G=tower-topple`. The design and its history are in
[PLAN.md](PLAN.md); how to play is in [README.md](README.md).

The family builds a wobbly tower of silly blocks together, then the littlest
one knocks it all down:

- **Seat 1, Builder** (the adult) slides the crane hook and rotates the hanging block.
- **Seat 2, Dropper** (the 5-year-old) drops it and picks the next shape from a tray of 4.
- **Seat 3, Toppler** (the 2-year-old): any press makes the blocks giggle. Once
  the big button lights, the next press sends in the wrecker.

A run is three towers (about 5 minutes), then the party screen. There is no
game over and no text. Load the **video-games** skill
(`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`) for the house rules.

## Rules

- **Godot 4.7 only** (the shared binary at the repo root, `.tools/godot`). No
  Godot 3 APIs: RigidBody2D has no `mode` (use `freeze` + `freeze_mode`), and
  there is no `applied_force` (use `apply_central_force` / `apply_impulse`).
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens
  are scripts in `game/scripts/screens/<name>.gd` that build their children in
  `_ready()`.
- **Flat vector art, not pixel art.** Physics rotates blocks to any angle, so
  every shape is a polygon with a 3 px `#1a1c2c` outline, drawn in code in
  the Sweetie 16 palette. The canvas is 640x360 with `canvas_items` stretch,
  MSAA 2D 4x and no pixel snap. The only PNGs are the riders, reused from
  PixelPals and drawn at integer scales (x2 in play, x3/x4 in menus) with
  nearest filtering.
- **Keyboard-only must always work**, with 1, 2 or 3 seats, pads and keyboard mixed.
- **No text in the UI.** **Never let a child's input end or hurt the run.**
  The Toppler's press before the button lights is purely cosmetic: faces
  giggle, and no impulse or physics property changes (a test guards this).
- **Third-party characters** stay in `game/private_pack/` and
  `art_src/private/` (gitignored and kept only on the family's machine (never committed)). `make
  export-linux` excludes the pack.
- **Verify before claiming.** Run `make test`, then `make shots`, and look at
  `shots/<screen>/sheet.png` (2x). Physics is not bit-deterministic: tests
  assert outcomes and ranges, never exact positions.

## Commands

`make start` · `make demo SHOT_SCREEN=play` · `make test` · `make shot SHOT_SCREEN=play` ·
`make shots` · `make sprites` · `make sfx` · `make assets` · `make editor` ·
`make export-linux` (after `make setup-export`) · `make tmux` / `tmux-d` / `tmux-n`.
Run `make help` for the full list.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd` and `sfx.gd` are
**symlinks into `../../shared/godot/autoload/`** (read-only from this game).
`game_state.gd` belongs to this game:

- `Game.goto("join"|"select"|"play"|"party")` switches screens.
- `Game.roster` holds the rider ids (the original five plus the private pack).
- Results for the party: `Game.tower_heights` (flags per tower, 0..8) and `Game.stars`.
- `Game.tower_seconds` (100 s; the demo sets 14 s) is the build time before the button lights.
- `Game.wrecker_index` makes the wreckers cycle across towers and runs: ball, elephant, whale, boot.
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`.

Seats: `Players.Seat.DRIVER/GUNNER/HONKER` are Builder / Dropper / Toppler.

### Play screen (`scripts/screens/play.gd`)

All logic runs in `step(dt)`, and the landing assist in `physics_step(dt)`,
so tests drive it frame by frame with `set_process(false)`.

- **Phases:** `BUILD` → (lit button pressed) `TOPPLE` (the wrecker comes in,
  and at `hit_time` every block is unfrozen and gets `apply_impulse` from the
  contact point) → `CHEER` (3 s) → `CLEAR` (the blocks shrink away) → the next
  tower. After three towers it writes the results and goes to the party.
- **Roles and fold-downs:** `Rules.roles(builder, dropper, toppler)`. With
  1 seat, the Builder's A drops, B rotates and A on a lit button topples;
  the shape is random and the tray is hidden. With 2 seats, the Dropper's A
  topples. With the Builder plus the Toppler, the Builder drops and the
  toddler topples. With the Toppler seated, the others' A also topples after
  `TODDLER_GRACE` (20 s lit). With no Builder, the crane drives and drops by
  itself.
- **Block states** (`scripts/play/block.gd`): `HANGING` (frozen kinematic,
  no collision) → `FALLING` → `SETTLING` (1.5 s: friction 1.0, bounce 0.05,
  angular damp 8) → `SETTLED`; or `PIT` (touched the ball-pit floor) →
  recycled after 1.4 s while building; `CLEARING` (shrinking, then freed).
- **Height:** the highest top of tower blocks slower than 5 px/s for 0.5 s.
  There is one flag every 36 px, 8 flags, and the 8th is the cloud line
  (288 px). Each new flag gives a star.
- **The button lights** at the cloud line, after 14 drops, after
  `Game.tower_seconds`, or at once on a self-collapse (3 blocks that had
  rested on the tower are now in the pit, or 2 when that is half the
  tower). The collapse plays a small crash and keeps the stars.
- **Landing assist:** a falling block whose bottom is within 20 px above the
  tower top and whose centre is within 44 px of the tower's centre of mass
  is steered toward that centre, and its fall is capped at 220 px/s.
- **Freezing:** a rested block with 3 rested blocks above it (overlapping
  horizontally) freezes static and closes its eyes. It unfreezes on the topple.
- **Body budget:** at most 40 live blocks. Spawning removes the oldest `PIT`
  blocks first.
- **Camera:** it rises so the settled top stays about 200 px below the top of
  the screen, and zooms out (down to 0.55) to show the whole tower for the
  topple. Screen shake is capped at 6 px.

Other files: `scripts/play/rules.gd` (pure rules and constants),
`vec.gd` (the flat vector helper), `wrecker.gd`, `scenery.gd` (sky, hills,
platform, pit, pole, cloud line), `hud.gd` (crane, tray, big button, tower
counter, pause, star effects), `scripts/icons.gd` (menu icons).

### Asset names (the art and audio contract)

Vector shapes (drawn in code, no files):

| name | size (px) | how |
|---|---|---|
| square | 32x32 | rounded rect (r 7), red, face in the middle |
| plank | 96x24 | rounded rect, orange, face at one end, wood grain |
| tall | 24x64 | rounded rect, green, face in the upper half |
| roof | 64x32 | rounded triangle, blue |
| arch | 64x40 | rect with a 16-segment half-circle cut, yellow |
| ball | 32 diameter | 24-gon (a circle collider), lime, at most 1 per tower |
| crane + hook | 660x20 rail, 40x18 trolley | HUD polygons, rope and J-hook polylines |
| big_button | 84x24 base + 64x26 dome | HUD, glow = translucent copies + rays + bouncing arrow |
| wreckers | ~60 to 170 px | ball on a chain, elephant (bum first), whale, rocket boot |
| height pole + flags | 8 flags 28x12 | line + triangles, rainbow order |
| ball pit | world-wide | 150 back balls + a front row, drawn once |
| cloud line | 4 clouds | cloud discs with faces that cheer when reached |
| confetti | 4x4 | generated white texture, `CPUParticles2D` colour ramp |

Sprites (PNG, `game/art/`, rendered by `make sprites` from `art_src/riders.txt`):
`penguin`, `monkey`, `fox`, `frog` and `robot`, 16x16 with 2 frames, plus the
private pack's nine riders.

Sounds (`game/audio/*.wav`, `make sfx`, about -15 LUFS, peaks under -1 dBFS):
`drop_1`…`drop_3`, `land_1`…`land_4`, `rotate`, `flag_1`…`flag_8` (a
C-major-pentatonic bell each), `wobble`, `giggle_1`…`giggle_4`, `button_lit`,
`swing`, `crash`, `whee`, `pit_boing`, `sparkle` (an extra one: a missed block
going back to the tray), `cheer`, `join`, `select`, `ready`, `party`. The
music loops are `music_build` (90 BPM, 16 bars) and `music_menu` (the
PixelPals menu tune, rendered by our copy of the synth).

### Screen flow

`join` → `select` → `play` → `party` → `select`.

- **join:** any device takes the next seat, and `b` leaves. kb:2 goes
  straight to the Toppler seat. The Builder's **down** moves the Dropper
  seat's pad to an empty Toppler seat (dad plus toddler on two pads), and
  **up** moves it back. The Builder continues with start, or by holding A for 1 s.
- **select:** the PixelPals rider select. The Toppler's presses cycle, and it
  auto-readies.
- **play:** the Builder's start pauses (physics server off, no
  `SceneTree.paused`, so input still polls). In pause, A resumes and B goes
  back to join.
- **party:** the three towers are rebuilt as stacks of mini blocks, the
  tallest gets a trophy, and the stars show in digits. It leaves after 10 s
  or on the Builder's A.

## Local copies instead of shared code

`tools/sfx.py` is a copy of PixelPals's synth with this game's sounds, and
`tools/sprites.py` a trimmed copy that renders only the riders. The
join/select/party screens are adapted copies. The plan wants these extracted
into `shared/` (a `game_state` router, the menu screens, `shared/tools/synth.py`
and `shared/godot/vector.gd`, of which `scripts/play/vec.gd` is the
candidate). That is a coordinator job, because this game's agent may not
edit `shared/`.
