# Space Mission

Fly the Space Shuttle to build a space station in Earth orbit, land on Mars
with a sky crane, then drive a rover across the red planet: one crew, three
jobs. A couch co-op game for a grown-up and two small kids; a mission lasts
about 9 minutes and ends with a party at Mission Control.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Pilot / Driver (blue) | the grown-up | flies the Shuttle, lowers the sky crane, drives the rover | left stick / d-pad moves, A = boost (orbit) or brake (rover), Start pauses, B in the pause goes back | WASD moves, Shift = boost/brake, Esc pauses, Q in the pause goes back |
| 2 Arm operator (yellow) | a 5-year-old | moves the robot arm and grabs, picks the landing site, drills rocks | d-pad / stick (4 ways), A = grab / let go / drill | arrow keys, Enter |
| 3 Camera (green) | a 2-year-old | takes photos of Earth, pops the parachute, launches the Mars helicopter | any button | Space or any other key |

- **Orbit:** each cargo module drifts in from the left; the arm grabs it (it
  snaps on from close by) and carries it to the glowing port of its colour,
  where it clicks in. Five modules build the station; then the Shuttle docks
  and the crew float out and flip. A sunrise every 20 seconds (count the
  little suns). Photos taken during a hurricane, the aurora or a sunrise are
  golden.
- **Landing:** the Camera pops the parachute, the Arm picks one of four
  landing spots (all safe), the Pilot holds down to lower the rover.
- **Mars:** drive right, drill the sparkling rocks (each gives a sample of
  its colour; ice and a pretty shell are rare), and send the helicopter to
  find the next one. At the end: the blue Mars sunset and a beam home.
- **Nobody can lose.** Bumps only boing; a missed cargo comes round again; a
  missed drill just tries again. Anything waiting for a seat does itself
  after 5 seconds.
- **Fewer players:** with two, the Pilot's B takes photos; with one, the arm
  works by itself and the Pilot's A is the camera too.
- On the select screen, the Pilot's up/down picks where the mission starts:
  Earth orbit, the Mars landing or the Mars surface.
- Photos stay in memory for the party; nothing is saved.

## Run it

```
make setup    # once: the pinned Godot + GUT, Python deps via uv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=orbit|landing|mars|party|join|select)
make help     # tests, art and sound generation, frame captures, export
```

Art comes from generators and text grids (`make sprites`) and sound from our
own synth (`make sfx`). See [CLAUDE.md](CLAUDE.md) for the architecture and
contracts.
