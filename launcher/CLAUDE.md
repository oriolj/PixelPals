# Couch Games launcher

The TV front end of the couch co-op monorepo. The repo-wide rules are in
[../CLAUDE.md](../CLAUDE.md), so read that first, and load the
**video-games** skill (`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`).
Run every `make` below from this folder (`launcher/`), or from the root with
`make launcher` / `make launcher-window` / `make covers`.

A horizontal carousel of big game cards on an animated night sky. Any pad or
keyboard block moves left/right and presses A (Enter/Space) to launch; the
game runs as its own Godot process; when it quits, the launcher zooms back,
chimes "welcome back" and keeps the same card selected. There are no seats
here: any device drives it. How to use it: [README.md](README.md).

## Rules

- **Godot 4.7 only**, GDScript, Compatibility renderer (captures run under
  xvfb). No Godot 3 APIs.
- **Build nodes in code.** The only `.tscn` is `game/scenes/main.tscn`.
- **1920x1080 base, `canvas_items` stretch, aspect keep.** It is not pixel
  art; covers of pixel games are pre-scaled by a whole factor with nearest
  filtering, then drawn with mipmapped linear filtering (exactly 2x for a
  320x180 cover on the focused card).
- **No `window_width_override` in `project.godot`**: it beats `--resolution`,
  and the 1080p captures came out 1280x720. `make window` passes the size.
- **Assets from source bytes**: covers, the icon (`Image.load_png_from_buffer`)
  and sounds (shared `sfx.gd`) never go through the import cache. No
  `class_name` in the launcher's scripts (preload by path), so it runs with no
  `game/.godot/` at all (tested: fresh-clone run, launch and return).
- **Fonts**: a `SystemFont` list (Fredoka, Nunito, … Adwaita Sans, DejaVu Sans)
  at weight 800. **No MSDF, no big outlines**: the variable system fonts have
  overlapping contours, which MSDF renders with holes and a thick outline
  shows as ghost strokes inside the letters. Use a drop shadow on big text.
- **Keyboard-only must work.** Confirm on the keyboard is Enter/Space only
  (not kb:1's Ctrl, which is half of Ctrl+Q, nor kb:2's every-other-key).
- **Art and sound from our code**: `tools/sfx.py` (the PixelPals synth
  engine, launcher sounds), `tools/icon.py` (the icon), placeholder covers
  drawn in `card.gd`.

## Commands

`make start` (fullscreen) · `make window` (1280x720, games windowed) ·
`make test` · `make shot SHOT_DEMO=browse|soon|power [SHOT_ARGS="--root=…"]` ·
`make shots` · `make launch-test` (a real launch of PixelPals under xvfb) ·
`make sfx` · `make icon` · `make help`.

## Architecture

`game/autoload/players.gd` and `sfx.gd` are symlinks into
`../../../shared/godot/autoload/` (edit them there; `make test` at the root
tests every game). Scripts in `game/scripts/`:

| file | role |
|---|---|
| `catalog.gd` | Discovery, pure: every `games/<slug>/` with `game/project.godot` is playable, one with only a `PLAN.md` is "coming soon" (greyed), anything else is skipped. Title = README.md's `# ` heading, else PLAN.md's, else the slug. Pitch = the first non-generic sentence of the paragraph under it. Cover = `games/<slug>/cover.png` or "" (placeholder). `order()`: recently played first, then by title, then coming soon. Root = two levels above `res://`. |
| `carousel.gd` | Selection and positions, pure: wraps both ways; `target` moves by whole steps, `scroll` eases to it; `offset(i)` is the wrapped distance of card i. |
| `runner.gd` | One game at a time: `IDLE -> [IMPORTING] -> RUNNING -> IDLE`. `request_launch()` is refused unless IDLE (no double launch). Missing `game/.godot/global_script_class_cache.cfg` runs `godot --headless --path <game> --import` first (spinner). Launch = `OS.create_process(<root>/.tools/godot, ["--path", <abs game>, "--fullscreen", "--", <game args>])`, polled with `OS.is_process_running` every 0.25 s. `spawn`/`is_alive` are callables so the tests fake the processes. |
| `card.gd` | One card: rounded frame (StyleBoxFlat whose shadow is the glow), cover through a rounded-corner shader (also greys coming-soon cards), title, badges ("Last played", "Coming soon"), the power card's symbol and hold ring, the import spinner. `focus` 0..1 drives glow, border, brightness. |
| `background.gd` | Night sky: gradient, twinkling stars, moon, clouds (opaque, tinted from the sky so overlaps never show), three hill layers, fireflies; each layer shifts with the scroll (parallax). |
| `bubbles.gd` | "Who is here": a coloured bubble per connected pad (hot-plug via `joy_connection_changed`) and per keyboard block once used; hops on each press. |
| `main.gd` | The screen: builds everything, reads input from every `Players` device (flick + hold-to-repeat), launches, waits underneath the game (music off, low-processor mode, input ignored, quit combo off), restores. Command-line flags are listed at its top. |
| `demo.gd` | Scripted `demo:0` device for captures and the launch test (`--demo=browse|soon|power`, `--autolaunch=<slug>`). |
| `palette.gd` | Sweetie 16. |

While a game runs the launcher stays underneath (not minimised: restoring a
minimised window is not reliable across X11/Wayland window managers). On
return it calls `window_move_to_foreground()`, and it ignores input until
every button is released, so the Back+Start that closed the game cannot
leak into the launcher.

### The quit combo (shared `players.gd`, additive)

Hold **Back/Select + Start** on any pad for 1.5 s, or press **Ctrl+Q**, and
the game quits. A watcher node with `PROCESS_MODE_ALWAYS` checks it (works
in paused games); a tiny corner ring appears only while the combo is held.
A hold that began before the app started or before the combo was re-enabled
only arms after a release. `Players.quit_combo_enabled` (the launcher turns it
off while a game runs), `Players.quit_action` (tests swap it),
`Players.quit_requested`. Tests: `games/pixelpals/game/tests/test_players.gd`.
In the launcher the same combo quits the launcher; the parent-only way is the
"Turn off" card at the end (hold A for 2 s).

### Covers

`tools/covers.py` (`make covers` at the root) runs each committed game's own
`make shot`, takes the frame chosen by looking at the capture sheets
(`PICKS`), and writes `games/<slug>/cover.png` at the capture's native size
(320x180, 480x270 or 1280x720), 16:9. The demos are not fully deterministic,
so LOOK at `launcher/shots/covers.png` after a run. A new game without a
pick gets the most colourful frame of its default screen: look at it and add
a pick. Games whose Makefile is not committed yet are left alone.

### Sounds (`tools/sfx.py`, `game/audio/`)

`move`, `bonk` (coming soon), `launch` (whoosh + sparkle run), `welcome`
(chime), `power_tick`, `power_off`, `music_menu` (84 BPM cosy loop, 8 bars,
seamless).

### Tests (`game/tests/`, GUT)

Discovery against a fixture tree (playable, planned-only, missing cover,
title fallbacks, pitch, order, the real repo), carousel wrap and offsets,
runner command building, import-then-launch, exit detection and the
no-double-launch guard, cover loading and placeholders.
