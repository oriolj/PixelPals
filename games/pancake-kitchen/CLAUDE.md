# Pancake Kitchen

One game of the couch co-op monorepo. The repo-wide rules are in
[../../CLAUDE.md](../../CLAUDE.md), so read that first. Run every `make` below
from this folder (`games/pancake-kitchen/`), or from the root with
`make start G=pancake-kitchen`. The plan (and its decisions) is
[PLAN.md](PLAN.md); how to play is [README.md](README.md).

The 2-year-old flips pancakes sky-high with any button, dad slides the pan to
catch them, and the 5-year-old piles toppings on for a queue of animal
customers who love every combination. One fixed kitchen screen, six
customers, about 5 minutes. Personal (oriolj) scope. Load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).

## Rules

- **Godot 4.7 only** (the shared binary at the repo root, `../../.tools/godot`).
  No Godot 3 APIs: no `yield`, `Tween` nodes, `interpolate_property`,
  `update()`, `export var`, `onready var`, `instance()`.
- **Build nodes in code.** The only `.tscn` is `scenes/main.tscn`. Screens are
  `game/scripts/screens/<name>.gd` (`Node2D`) that build children in `_ready()`.
- **Flat vector art at 1280x720**, not pixel art: stretch mode `canvas_items`,
  aspect `keep`. Everything is drawn by `scripts/vector_art.gd` (no image
  files); round shapes, thick `#2b2438` outlines drawn last as antialiased
  polylines (2D MSAA is not supported by the Compatibility renderer, the AA
  outline hides the fill's jagged edge).
- **No text in the UI**, no game over, no visible timer. Every seat works with
  the shared keyboard blocks, pads, or both mixed; 1, 2 or 3 seats.
- **The flipper seat can never hurt the run**: any button flips when the
  pancake is in the pan, adds a spin when it is in the air, and otherwise
  makes a sparkle and a giggle.
- **Assets load from source bytes.** Audio goes through the shared `Sfx`
  (and the kitchen's sizzle loop reads the WAV with
  `AudioStreamWAV.load_from_file`, like `sfx.gd`); every run/test target
  depends on `ensure-import`.
- **Verify before claiming**: `make test`, then `make shots` and look at
  `shots/<screen>/sheet.png` (frames are 1280x720; the sheet is not upscaled).

## Commands

`make setup` · `make start` · `make demo SHOT_SCREEN=kitchen` · `make test` ·
`make sfx` · `make assets` · `make shot SHOT_SCREEN=<screen>` · `make shots`
· `make editor` · `make export-linux` (after `make setup-export`) · `make tmux`
/ `tmux-d` / `tmux-n`. `make help` lists them all.

## Architecture: the contracts

Autoloads (`game/autoload/`): `players.gd`, `art.gd`, `sfx.gd` are **symlinks
into `../../shared/godot/autoload/`** (read-only from here; `Art` is unused,
the art is vector code). `game_state.gd` is this game's:

- `Game.goto("join"|"select"|"kitchen"|"party"|"gallery")`; `Game.CHEFS`
  (the roster: bunny, pig, mouse, fox, duck), `Game.hats[seat]` (index into
  `Palette.HATS`), `Game.plates` (the round's served plates, for the party),
  `Game.round_customers` (6) and `Game.round_limit` (420 s).
- Demo mode: `-- --demo[=screen]` runs `scripts/demo_driver.gd`
  (`demo:0..2` scripted seats, the kitchen script from PLAN.md).

Seats (`Players`): 0 **cook** (blue, pan handle), 1 **topper** (yellow, jar
ring), 2 **flipper** (green, sparkle trail). `Players.riders[seat]` holds the
chef animal.

Kitchen (`scripts/kitchen/`):

- `rules.gd`: pure logic (`RefCounted`), no nodes, no input. Pancake states
  `POURING → IN_PAN → FLYING → (CATCHING | GAG → RETURNING) → IN_PAN …
  → SETTLING → HOPPING` onto the plate stack. The flight is the closed-form
  parabola `launch_pos + v t + ½ g t²` (so fixed-fps captures match live
  play); `predict_landing_x()` and `time_to_y()` are its math. Catch = falling,
  below `CATCH_LINE`, within `MAGNET` (60 px) of the pan. Miss gags by where
  it comes down: the shelf cat (crossing the shelf), the dog (left of
  `DOG_ZONE_X`), a counter bounce (elsewhere); every gag returns to the pan and
  counts as the flip. Two flips = done. Cook colour clamps at golden.
  Customers: `WALK_IN → WAIT → (SPRINKLE) → EAT → HAPPY → LEAVE`;
  `reaction_size(n)` 1/2/3 by topping count; 6 served, or the 7-minute
  finale (everyone gets a loaded stack). Everything that happens is appended
  to `events` for the screen.
- `palette.gd`: the colours (PLAN.md), topping colours, hat colours,
  `cook_color(cook)`.
- `screens/kitchen.gd`: feeds seat input into the rules, plays their events
  (sound + effects), draws with `vector_art.gd` through `draw_node.gd` layers
  (`_bg` static, `_world` every frame, `_front` the pause overlay). `step(dt)`
  is callable from tests.

### Asset names (the art and audio contract)

Art: functions of `scripts/vector_art.gd`, all drawn in code.

| function | size at 1280x720 | states |
|---|---|---|
| `pancake` | 160x36 disc | cook colour lerp per face, bubbles, flip by y-scale (`cos(spin)`), squash, pour spread |
| `pan` | 200x50 + handle | handle in the cook's colour, tilt |
| `stove`, backdrop in `kitchen.gd` | fixed scenery | flame follows the pan |
| `plate`, `stack` | 180 px | glow when ready, toppings by level |
| `topping` | 24-48 px | `strawberry`, `chocolate`, `banana`, `cream` |
| `jar` | 80 px | selected ring (topper yellow), bump |
| `creature` | about 230 px at scale 1 | customers `bear`, `cat`, `penguin`, `frog`, `robot`; chefs `bunny`, `pig`, `mouse`, `fox`, `duck` (+ `hat`); eyes open/happy/wide, mouths smile/open/chew/grin/o, arms 0..1 |
| `dog` | 130 px | idle, happy (gag) |
| `shelf_cat` | 120 px | sleepy, surprised |
| `steam`, `sparkle`, `star`, `heart`, `confetti` | 16-40 px | |
| `role_icon`, `device_icon` | 64 px | seat roles (pan, jar, flying pancake), pad / keyboard |

Sounds (`game/audio/`, made by `tools/sfx.py`, `make sfx`): `pour`,
`sizzle` (loop), `boing_1..4`, `spin`, `flop`, `plop_1..3`, `splat_soft`,
`ding`, `slide`, `yum_1..3`, `giggle`, `cheer`, `dog_woof`, `meow`,
`sparkle`, `whoosh`, `join`, `select`, `ready`, `party`, `music_menu`,
`music_kitchen` (96 BPM swing, F major).

### Screen flow

`join` → `select` → `kitchen` → `party` → `select`; `gallery` only via
`--demo=gallery`.

- **join**: any device takes the next seat (kb:2 prefers the flipper seat);
  the cook holds "a" 1 s or presses start.
- **select**: left/right chef, up/down hat colour, "a" ready; the flipper's
  any press cycles and it auto-readies after 3 s.
- **kitchen**: the cook's start pauses; in pause "a"/start resumes, "b" goes
  back to join.
- **party**: the six guests with their towers, the giant flip, confetti;
  12 s or the cook's "a".

## Local divergences from shared/

None: the shared autoloads are used as-is. The join/select screens are
copies of PixelPals's logic redrawn in vector art (the plan's "extract to
shared" is left for when a second vector game exists).
