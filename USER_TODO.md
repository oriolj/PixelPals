# Waiting on Oriol

These need the couch, the kids, ears or real pads, which an agent cannot
provide. Nothing is blocked except the next round of tuning, which depends
on what the playtest shows.

- [ ] **Couch playtest.** Run `make start` (repo root) on the TV PC. Plug in the pads
  (8BitDo in X-input mode), or use the keyboard: WASD+Shift, the arrow keys
  + Enter, and Space. Afterwards, note in this file which role was too hard
  or too boring, whether the 3-minute run is too long, and whether the honks
  make the little one laugh. The next iteration is tuned from that.
- [ ] **Listen to the sounds.** The 4 honks and the two music loops were
  checked by measurement only. Say which to redo (`make -C games/pixelpals sfx` regenerates
  them).
- [ ] **Check that your 8BitDo pad's buttons map right** (A fires, Start
  pauses). If not, tell me the pad model and mode, and I'll add an SDL
  mapping.
- [ ] Optional: `make -C games/pixelpals setup-export` (1.3 GB download, keeps ~100 MB), then
  `make -C games/pixelpals export-linux` for a standalone binary.
