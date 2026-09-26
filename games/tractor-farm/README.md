# Tractor Farm

Plough, plant, rain and harvest one sunny field together. Dad drives the
tractor, a 5-year-old picks the seeds, a 2-year-old is the rain cloud that
makes everything grow. Nobody can lose: nothing wilts, wheels never crush a
plant, and after 30 crops in the barn (or 6 minutes) a giant vegetable grows
and everyone goes to the village fair.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Tractor (blue) | the grown-up | drives: the plough makes furrows, the planter sows, driving over ripe crops harvests them | left stick / d-pad drives (the tractor turns toward the stick); A: horn, or tip the trailer at the barn; Start: pause | WASD drive; Shift: horn / tip; Esc: pause |
| 2 Seeds (yellow) | a 5-year-old | picks the seed the planter sows | d-pad or stick: up carrot, right pumpkin, down sunflower, left strawberry; A: planter on/off | arrow keys pick; Enter: planter on/off |
| 3 Rain cloud (green) | a 2-year-old | rains: plants under the cloud grow with a boing, five quick presses make a rainbow | any button | Space or any other key |

- Seats fill in the order devices press a button; pads and keyboard mix.
- With nobody on seeds, the seed changes by itself at every turn; with
  nobody on the cloud, it rains by itself (every 4 s alone, 6 s with two).
- Tip the trailer by pressing A in front of the barn, or just park there
  for 2 seconds. A yellow arrow over the barn means the trailer is full.
- In the pause, A resumes and B (Q on the keyboard) goes back to joining.
- Animal visitors (bunny, pig, hen) nibble a ripe crop and leave a heart;
  rain on bare ground makes puddles where a duck or a frog jumps in.

## Run it

```
make setup    # once (at the repo root it fetches the pinned Godot 4.7.2 and the Python venv)
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=level|finale|party...)
make help     # everything else (tests, sounds, frame captures, export)
```

Everything is drawn in code (`game/scripts/draw/`); the sounds come from
`make sfx`. See [CLAUDE.md](CLAUDE.md) for the architecture and
[PLAN.md](PLAN.md) for the design.
