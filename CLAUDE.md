# Couch co-op games (monorepo)

Games that Oriol plays on the couch with his kids, aged 5 and 2. They run on a
Linux PC on the TV with up to 3 pads, or keyboard only. The repo is
[oriolj/PixelPals](https://github.com/oriolj/PixelPals) (**private**), named
after its first game. It is personal (oriolj) scope.

Load the **video-games** skill
(`~/git/oriolj/LLM_SKILLS/skills/video-games/SKILL.md`) before working here.
It holds the house rules, the Claude + Godot traps and the field notes. Write
every new lesson back into it in the same turn.

## Layout

```
Makefile              shared tools + forwarding: make start (launcher) / make start G=<slug>, make test (all), make list
.tools/               pinned Godot binary (gitignored; make setup-tools)
pyproject.toml        one uv venv for every game's Python tools (Pillow, numpy)
shared/
  godot/autoload/     players.gd (seats + input + the Back+Start quit combo), art.gd (sprite loader), sfx.gd (sound)
  tools/shots.py      frame-capture inspection sheet
games/<slug>/         one game each
  PLAN.md             the plan (every game has one; built games keep it as history)
  CLAUDE.md, AGENTS.md -> CLAUDE.md, README.md, Makefile   (built games)
  game/               the Godot project (project.godot at its root)
  cover.png           the launcher's card image (made by make covers; committed)
  art_src/, tools/    the game's own art sources and generators
launcher/             the TV game picker (Godot, 1080p): make launcher; see launcher/CLAUDE.md
  tools/covers.py     make covers: each committed game's cover.png from its demo capture
docs/ideas.md         index of every game idea and its status
USER_TODO.md          what only Oriol can do (playtests, listening, pads)
```

To see which games are playable and which are plans, run `make list`.

## Rules for every game

- **The PixelPals formula.** The adult has the hard input. The 5-year-old
  gets 1–2 buttons and at most 4 directions, with assists. The 2-year-old's
  ANY button always does something delightful and never hurts the run.
  There is no game over, no text in the UI, and a session lasts 3–10 minutes.
- **Keyboard-only must always be playable**, with pads and keyboard mixable.
  Use the shared blocks: kb:0 = WASD + Shift, kb:1 = arrows + Enter, kb:2 =
  Space and every other key.
- **Godot 4.7 with GDScript**, pinned in the root Makefile. No Godot 3 APIs.
  Build nodes in code, and keep `.tscn` files to tiny shells.
- **Shared code lives in `shared/` and is symlinked into each game** (Godot
  follows symlinks, and `res://autoload/players.gd` is a link). Edit the
  canonical file in `shared/`, and after changing it run `make test` at the
  root, which tests every game. Copy a file into a game only when it
  genuinely needs to diverge, and say so in that game's CLAUDE.md.
- **Assets load from source bytes, not the import cache.** A fresh clone has
  no `game/.godot/`; `shared/godot/autoload/art.gd` and `sfx.gd` handle it,
  and every game's run/test targets depend on `ensure-import`. Before saying
  something runs on another machine, test it on a clean clone.
- **Art and sound come from our code.** The model outputs no images or
  audio. Use text grids or generators plus our renderer and linter, or
  procedural drawing, and synthesize the sound. Any third-party tool needs
  more than 1k GitHub stars.
- **Third-party characters** (Sonic, Shadow, Knuckles, Robotnik, the three
  Minions, Mario, Luigi) are fan art for private family use. They live in
  each game's `private_pack/` and are committed ONLY because this repo is
  private. **Never make this repo public, fork it publicly, export a private
  pack, or show one in anything published.**
- **Every game quits from a pad.** The shared `players.gd` quits on
  Back/Select + Start held 1.5 s on any pad, or Ctrl+Q (back to the
  launcher). Never bind Back+Start (or Ctrl+Q) to anything else, and do not
  disable it; `Players.quit_combo_enabled` is for the launcher only.
- **Every playable game has a `cover.png`** for the launcher (16:9, native
  capture size). Make it with `make covers` at the root once the game is
  committed, LOOK at `launcher/shots/covers.png`, and add the chosen frame to
  `PICKS` in `launcher/tools/covers.py`. The launcher finds games by
  themselves: `game/project.godot` = playable, a lone `PLAN.md` = "coming
  soon"; the card title is README.md's `# ` heading and the pitch the first
  paragraph under it, so keep those meaningful.
- **Verify before claiming.** Run `make test`, then `make shot` in the game
  and look at `shots/<screen>/sheet.png` (upscaled for inspection).

## Starting a game from its plan

1. Read `games/<slug>/PLAN.md` and confirm the open questions with Oriol.
2. Copy the PixelPals skeleton: Makefile, `project.godot` pixel settings,
   `scenes/main.tscn`, the GUT addon via `make setup`, and a `game_state.gd`.
   Symlink the shared autoloads.
3. Write the contracts first (seats, screens, asset names in the game's
   CLAUDE.md). Then split the work across parallel agents by path ownership,
   as PixelPals did (see the skill's field notes).
4. Add the game to `docs/ideas.md` and to hq `docs/projects.md` when it
   becomes playable.
