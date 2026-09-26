# Zoo Keeper

A couch co-op zoo for a grown-up and small kids. The keeper walks the food
cart around six enclosures; hungry animals show an empty bowl; the feeder
picks the right food from four pictures and throws it. Right food: a happy
munch, a song, hearts and a star. Wrong food: a funny "no thanks" and a hint.
Nobody can lose, and there is no text anywhere.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Keeper (blue) | the grown-up | walks the keeper and the cart | left stick / d-pad; A rings the cart bell (or throws, alone); Start pauses | WASD; Shift; Esc pauses |
| 2 Feeder (yellow) | a 5-year-old | picks a food: up banana, right fish, down carrot, left hay; throws it | d-pad / stick + A | arrow keys + Enter |
| 3 Singer (green) | a 2-year-old | the nearest animal sings and dances | any button | Space or any other key |

- Seats fill in the order devices press a button; pads and keyboard mix.
- Playing alone: stop at an animal, flick the stick to pick a food, A
  (Shift) throws, hold the stick to walk on.
- Paused: Start/Esc or A resumes; the keeper's B (Q) goes back to joining.
- The run ends after every animal has eaten twice (about 5 minutes) or at 7
  minutes, when the keeper rings the bell. Then the party.

## Run it

```
make setup    # once: shared Godot + GUT + Python venv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=join for the whole flow)
make help     # tests, sounds, frame captures, export, tmux
```

Everything you see is drawn by code (`game/scripts/vector/`), and every sound
is synthesized by `make sfx`. See [CLAUDE.md](CLAUDE.md) for the architecture.
