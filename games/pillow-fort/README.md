# Pillow Fort

A cosy bedtime hide-and-seek for a grown-up and small kids. The bedroom is at
warm dusk, the fairy lights on the pillow fort glow, and eight toys are hiding
under pillows, blankets, box lids, the curtain and the bed.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Flashlight (blue rim) | the grown-up | moves the warm light; toys peek out a little where it shines | left stick / d-pad; A lifts the spot under the light when nobody is seeking; Start pauses | WASD; Shift lifts; Esc pauses |
| 2 Seeker (yellow paw) | a 5-year-old | hops the paw to the next spot and lifts it | d-pad / stick (4 directions); A or X lifts | arrow keys; Enter lifts |
| 3 Peekaboo (green) | a 2-year-old | any button: a friend pops out near the light and says "peekaboo!"; quick extra presses twinkle the fairy lights | any button | Space or any other key |

- **1 seat**: rest the light on a spot for a moment (a ring fills) and it
  lifts by itself, or press A / Shift.
- **2 seats**: a friend peeks out on its own now and then, only inside the light.
- Lifting an empty spot always gives a surprise (a sock, a cookie, a sleepy
  mouse). After a while without a find, the nearest toy's spot glows.
- When all eight toys are in the basket (or after 6 minutes, when the last
  ones walk out by themselves) the lamp turns on softly and there is a little
  party, then everyone yawns.
- Pause: the flashlight's Start (Esc). In the pause, B (Q) goes back to joining.

Seats fill in the order devices press a button; pads and keyboard can be
mixed, and one keyboard is enough for all three seats.

## Run it

```
make setup    # once: shared Godot + GUT, Python deps via uv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=fort by default)
make help     # tests, assets, frame captures, light check, export, tmux
```

Art comes from `make sprites` and sound from `make sfx`, both our own code.
See [CLAUDE.md](CLAUDE.md) for the architecture and contracts.
