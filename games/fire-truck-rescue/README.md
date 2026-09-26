# Fire Truck Rescue

A couch co-op fire-truck game for a parent and small kids, in a chunky
low-poly toy town. Everyone crews one fire truck: put out 6 fires, rescue 3
cats stuck in trees, then drive home to the station at sunset for a party.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Driver (blue) | the grown-up | drives the truck (stick up = away from the camera, back = reverse) | left stick / d-pad; A = horn; Start = pause | WASD; Shift = horn; Esc = pause |
| 2 Hose (yellow) | a 5-year-old | aims the hose left/right/up/down, holds A to spray | stick or d-pad + hold A | arrow keys + hold Enter |
| 3 Siren (green) | a 2-year-old | siren and lights; raises the ladder when the truck is parked by a cat | any button | Space or any other key |

How a run goes:

1. A fire appears; a big flame floats over it and a yellow arrow points the
   way. Drive there and stop next to it.
2. Spray: the fire shrinks, hisses, turns to steam, someone waves thank you
   and 3 stars fly into the bucket.
3. After some fires a cat gets stuck up a tree. Park under it and press the
   siren: the ladder goes up and the cat rides down.
4. Brush past a yellow hydrant for a 5-second super spray (with a rainbow).
5. When everything is done (or after 6 minutes) the sky turns to sunset:
   follow the arrow home and park inside the station.

Nobody can lose: bumps just bounce, fires never spread, and a truck that is
stuck for 3 seconds hops back onto the road. With fewer players the empty
jobs happen by themselves (the hose sprays when parked by a fire, the ladder
rises when parked by a cat).

- In the pause (driver's Start / Esc), the driver's B (Q) goes back to joining.
- Everything works on one keyboard; pads and keyboard can be mixed.

## Run it

```
make setup    # once: Godot + GUT (shared at the repo root), then an import
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=join|select|level|cat|home|party)
make help     # everything else (tests, assets, captures, export)
```

Art is generated from text grids and generators by `make sprites` (Sweetie 16,
linted) and the sounds by `make sfx`. See [CLAUDE.md](CLAUDE.md) for the
architecture and [PLAN.md](PLAN.md) for the design.
