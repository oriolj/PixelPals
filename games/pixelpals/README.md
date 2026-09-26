# PixelPals

A couch co-op pixel-art game for a parent and small kids. Everyone rides one
flying bathtub:

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Driver (blue) | the grown-up | steers the tub | left stick / d-pad | WASD |
| 2 Gunner (yellow) | a 5-year-old | aims in 4 directions and fires | d-pad + A/X/RT | arrow keys + Enter |
| 3 Honker (green) | a 2-year-old | honks: birds fly, flowers bloom, clouds get scared | any button | Space or any other key |

Nobody can lose. Getting bumped costs a few stars, and a run lasts about 3
minutes before the party screen. Seats fill in the order devices press a
button, and pads and keyboard can be mixed (dad on a pad, the toddler on the
space bar).

- Driver's Start (Esc on the keyboard) pauses.
- In the pause, the driver's B (Q on the keyboard) goes back to joining.

## Run it

```
make setup    # once: pinned Godot 4.7.2 + GUT into .tools/, Python deps via uv
make start    # play
make demo     # watch it play itself
make help     # everything else (tests, assets, frame captures, export, tmux)
```

Tested pads are Xbox-style and 8BitDo in X-input mode. If an 8BitDo pad
misbehaves, switch it to X-input (hold X while powering on) or add an SDL
mapping.

Art is generated from text grids in `art_src/` by `make sprites` (Sweetie 16
palette, linted), and sounds by `make sfx`. See [CLAUDE.md](CLAUDE.md) for
the architecture and contracts.
