# Garage Band

A three-piece couch band for a parent and small kids. Every note lands on
the beat and in key, so whatever anyone plays sounds good. Play a song
(about 1.5 minutes), then the party screen replays the band's own
recording while the band bows.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Lead (blue) | the grown-up | plays the melody on a 5-lane highway | stick / d-pad up-down = note, left-right = low/high octave, A = strum (hold = one note per eighth), B = crash when there is no Crasher, Start = pause | W/S = note, A/D = octave, Shift = strum, Q = crash, Esc = pause |
| 2 Drummer (yellow) | a 5-year-old | four drum pads | up = hi-hat, left = snare, right = tom, down = kick, A = kick | arrows = pads, Enter = kick |
| 3 Crasher (green) | a 2-year-old | cymbal, gong, cowbell, whoosh (cycles) | any button | Space or any other key |

- Seats fill in the order devices press a button; pads and keyboard mix.
  On the join screen the Lead holds A (or presses Start) to go on.
- Select: everyone picks a rider (left/right, A to be ready; the Crasher
  cycles with any press). Then the Lead picks the song: the sun (medium),
  the rocket (fast) or the cat (slow lullaby), and presses A.
- Gems slide toward the Lead's hit line and the Drummer's pads, and the
  Crasher's instrument glows when a crash would fit. Hitting a gem bursts
  it into stars; anything else still sounds, in time and in key.
- With 1 seat a soft auto-drummer keeps the groove and the Lead's B
  crashes; with 1 or 2 seats an auto-crash lands every 8 bars.
- Pause (Lead's Start / Esc): A resumes, B stops the song. Nobody else can
  pause, and nothing can end the song early by accident.

## Run it

```
make setup    # once: pinned Godot + GUT + Python deps (shared at the repo root)
make start    # play
make demo SHOT_SCREEN=play   # watch the band play itself
make help     # everything else (tests, sounds, frame captures, audio check, export)
```

See [CLAUDE.md](CLAUDE.md) for the architecture and contracts.
