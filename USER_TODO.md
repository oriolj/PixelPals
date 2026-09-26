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
