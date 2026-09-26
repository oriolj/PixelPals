# Train Conductor

A couch co-op wooden toy railway for a parent and small kids. Everyone runs
one train: coloured passengers wait on the platforms, and you carry each one
home to the station of their colour.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Engine (blue) | the grown-up | faster, slower/brake, horn; stop at the platforms | stick/d-pad up = faster, down or B = slower/brake, A = horn, Start = pause | W faster, S slower/brake, Shift horn, Esc pause |
| 2 Points (yellow) | a 5-year-old | throws the next junction toward the way they want; opens the doors at a station | stick/d-pad toward the branch (any other direction flips it), A = doors | arrow keys, Enter = doors |
| 3 Whistle (green) | a 2-year-old | toots: steam rings, animals answer, the cow steps aside, the bell hurries boarding | any button | Space or any other key |

- Passengers wear the colour and the hat of the station they want: red
  circle, blue square, yellow triangle, green star. Each junction has a
  beacon on each branch showing which stations lie that way.
- Stop the engine's nose by the platform's round post. Stopping short is
  fine; overshooting a little makes the train say "beep beep" and roll back
  by itself. A stop right on the post sparkles.
- A full train couples on a new carriage (up to five).
- Nobody can lose: no crashes, no dead ends, no timer on anyone. 12
  deliveries or 6 minutes end the run with a night-time party.
- With one player, the points follow a tour rule and the doors open by
  themselves; with no whistle player, the whistle toots on its own.
- In pause, the driver's B (Q) goes back to joining; A (Shift) resumes.
- Join: every device presses a button to take the next seat; the driver
  holds A (Shift) or presses Start (Esc) to go on.

## Run it

```
make setup    # once: shared Godot 4.7.2 + GUT, Python deps via uv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=level|finale|party...)
make help     # tests, assets, frame captures, export
```

Tested pads are Xbox-style and 8BitDo in X-input mode. The right trigger
counts as the A button (horn) on pads, because the shared input layer folds
it into A. Art is drawn in code, riders come from `art_src/` (`make
sprites`), sounds from `make sfx`. See [CLAUDE.md](CLAUDE.md) for the
architecture and [PLAN.md](PLAN.md) for the design.
