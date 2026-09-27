# Waiting on Oriol

These need the couch, the kids, ears or real pads, which an agent cannot
provide. Nothing is blocked; each playtest tunes the next iteration of
that game.

- [ ] **Couch playtests.** Run `make start G=<slug>` on the TV PC (`make list`
  shows the 13 playable games). Keyboard: WASD+Shift, arrows+Enter,
  Space/any other key. Pads: 8BitDo in X-input mode. For each game, note in
  this file which role was too hard or too boring and whether the run
  length is right. Start with PixelPals, Tower Topple, Submarine Safari.
- [ ] **Listen to the sounds.** Every game's sounds and music were checked
  by measurement only (levels, loops, spectrograms). Say which to redo
  (`make -C games/<slug> sfx` regenerates them). Zoo Keeper's synthesized
  animal voices most need an ear; say if CC0 recordings are wanted.
- [ ] **Check your 8BitDo pad** (A fires, Start pauses) in any game. If not,
  tell me the pad model and mode and I'll add an SDL mapping.
- [ ] **Answer the open questions.** Every game's `PLAN.md` ends with
  "Decisions taken (pending Oriol)": the default each agent chose. Change
  any you disagree with. Space Mission's plan has its own questions
  (Shuttle or capsule, Moon stop, saving the photos).
- [ ] Export templates are installed now (4.7.2, Linux only):
  `make -C games/<slug> export-linux` builds a standalone binary without
  the private pack.
- [ ] **Try the TV launcher with real pads** (`make launcher`, or "Couch Games"
  in the app menu after `make install-desktop`). Check on the TV: the cards
  read from the sofa, the pads' bubbles appear, A launches, and **holding
  Back/Select + Start for 1.5 s** quits a game back to the launcher on each
  pad (Xbox and 8BitDo; on an 8BitDo, Select is Back). Agents tested it only
  under xvfb with scripted input. Nothing is blocked; say what to change.
- [ ] **Decide on autostart** of the launcher at login (not set up):
  `cp ~/.local/share/applications/couch-games.desktop ~/.config/autostart/`
  on the TV PC. Your call: it only matters if that PC is used just for games.
- [ ] **Back up the fan-character packs** (Sonic, Minions, Mario...). Since
  the repo went public they exist only on this machine, in each game's
  `game/private_pack/` and `art_src/private/` (gitignored). They are also in
  the full pre-purge history bundle
  `~/git/oriolj/VideoGames/PixelPals-private-history-2026-09-27.bundle`
  (84 MB, outside the repo). Keep that bundle somewhere safe but private
  (not in any public place); a fresh clone of the public repo will not have
  the fan characters. To restore them on another machine: copy those folders
  over, or `git clone <bundle>` into a scratch dir and copy them out.
