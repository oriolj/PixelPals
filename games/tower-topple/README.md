# Tower Topple

Build a wobbly tower of silly blocks together, then the littlest one gets
to knock it all down. A couch co-op game for a grown-up and small kids.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Builder (blue) | the grown-up | slides the crane hook and rotates the hanging block | left stick / d-pad moves, A rotates, Start pauses | A/D move, Shift rotates, Esc pauses |
| 2 Dropper (yellow) | a 5-year-old | drops the block, and picks the next shape from the tray of 4 | A drops, d-pad picks | Enter drops, arrow keys pick |
| 3 Toppler (green) | a 2-year-old | makes the blocks giggle; when the big button lights up, knocks the tower down | any button | Space or any other key |

- **The big button** lights up when the tower reaches the clouds, after 14
  blocks, after about 100 seconds, or straight away if the tower falls down
  by itself.
- **The wrecker** changes each tower: a wrecking ball, an elephant bum, a
  bouncing whale and a rocket boot.
- **Nobody can lose.** Missed blocks bounce in the ball pit and come back to
  the tray. A tower that falls by itself gets a smaller party and keeps its
  stars.
- A run is three towers, about 5 minutes, and ends with the party screen.
- **Fewer players:**
  - **Alone:** A drops, B rotates, and A on the lit button topples.
  - **Two players:** the Dropper's A topples.
  - **Grown-up and toddler:** the Space bar joins straight into seat 3. On
    two pads, the grown-up presses **down** on the join screen to move the
    second pad to seat 3.
- **Pause:** the Builder's Start (Esc). In the pause, A (Shift) resumes and B
  (Q) goes back to joining.

## Run it

```
make setup    # once: shared Godot 4.7.2 + venv at the repo root, GUT here
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=join|select|play|party)
make help     # everything else (tests, sounds, frame captures, export, tmux)
```

Blocks, crane, button and wreckers are flat vector art drawn in code; the
riders come from PixelPals. Sounds are synthesized by `make sfx`. See
[CLAUDE.md](CLAUDE.md) for the architecture and [PLAN.md](PLAN.md) for the
design.
