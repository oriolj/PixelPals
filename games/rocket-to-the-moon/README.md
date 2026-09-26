# Rocket to the Moon

Count down, blast off and fly a rocket through the sky and the stars to the Moon, grabbing
fuel cans and planets on the way. A couch co-op game for a grown-up and two small kids.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Pilot (blue) | the grown-up | steers the rocket, lands it on the Moon | left stick / d-pad (Start pauses; B in the pause goes back) | WASD (Esc pauses; Q in the pause goes back) |
| 2 Grabber (yellow) | a 5-year-old | aims the claw arm in 4 directions and shoots it | d-pad / stick aims, A shoots | arrow keys aim, Enter shoots |
| 3 Launcher (green) | a 2-year-old | presses the big launch button, fires the booster | any button | Space or any other key |

- Nobody can lose. Asteroids are soft: a bump spins the rocket and two cans float out (grab
  them back). An empty tank only makes the flame small. Missing the landing pad just bounces;
  after three tries the pad slides under the rocket.
- The big button waits for the Launcher at every stage (launch, into space, stage
  separation, the flag on the Moon) and presses itself after 8 seconds.
- **Two players:** the Grabber's A presses the big button and the booster fires by itself.
  **One player:** the Pilot's A launches and boosts, and a magnet collects the pickups.
- The planets you find stay in the album (the party screen) from one trip to the next.
- Seats fill in the order devices press a button; pads and keyboard can be mixed.

## Run it

```
make setup    # once: the pinned Godot + GUT, Python deps via uv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=launch|flight|party...)
make help     # tests, art and sound generation, frame captures, export
```

Art comes from text grids and generators (`make sprites`) and sound from our own synth
(`make sfx`). See [CLAUDE.md](CLAUDE.md) for the architecture and contracts.
