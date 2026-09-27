# Pony Trails

A horse day in three stages: groom the mare in the stable, ride the
countryside trail with her foal trotting beside her, and finish at the horse
show, where everyone wins a rosette. A couch co-op game for a grown-up and
two small kids. A day lasts about 8 minutes and ends at the rosette wall,
which is kept between sessions.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Rider (blue) | the grown-up | picks the hooves and saddles up; rides the mare (walk, trot, canter, jumps); rides the show course | left stick / d-pad (a hand in the stable, faster/slower on the trail), A = jump / use the tool, Start pauses, B in the pause goes back | WASD, Shift = jump / tool, Esc pauses, Q in the pause goes back |
| 2 Foal and brush (yellow) | a 5-year-old | scrubs the mud off and picks the braid ribbon; steers the foal between three lanes and hops for apples; the foal's mini course | d-pad / stick (4 ways), A = scrub (hold) / hop | arrow keys, Enter |
| 3 NEIGH (green) | a 2-year-old | a big happy neigh: carrots, gates, the animals, the wild herd, the show bell | any button | Space or any other key |

- **Stable:** the mare is muddy after a night in the paddock. The brush hops
  to the nearest mud patch in the direction pressed, and holding A scrubs it
  away (about 2 seconds each). The hand points at each hoof and A picks it
  (a pebble pops out, the shoe glints); with all four done, A on the saddle
  rack puts the saddle and bridle on. Once she is clean, a direction picks the
  ribbon for her mane (up red, right blue, down yellow, left purple). Any
  NEIGH press gives her a carrot, and every third one the foal steals it.
  After 90 seconds the stable cat helps with whatever is left.
- **Trail:** right speeds the mare up, left slows her down. A jumps logs,
  hay bales and streams, and the jump starts at the right moment if you
  press within 0.4 seconds. A missed jump is a slower step-over with a
  funny "hup!". The foal is tied to the mare by an invisible tether. It
  changes lanes with up/down; flowers are picked by trotting through them,
  and apples and the rare lucky horseshoes need a hop. A neigh opens the gate
  at the end of each field (it opens by itself after 5 seconds) and makes the
  nearest animal answer. There is a warm shower, then the wild herd gallops
  on the hill, then a rainbow, then golden light at the show grounds.
- **Show:** the NEIGH rings the bell to start each round. The mare runs the
  six jumps by herself and A jumps them, with the same assist. A refused jump
  is a snort and a lap back, and the second try always clears. The foal's
  mini course is four tiny jumps, then four poles where any cone you pick
  gets a cheer. Everybody wins a rosette.
- **Party:** back in the stable at dusk. The rosettes go on the wall next to
  those from every earlier day, and the lucky horseshoes hang over the door.
- **Nobody can lose.** Anything that waits for one seat does itself after 5
  seconds.
- **Fewer players:** with no 5-year-old, the brush scrubs by itself and the
  foal steers by itself. With no toddler, the Rider's B neighs, the gates
  open as she arrives and the mare neighs on her own.
- **Select screen:** left/right picks a rider (each wears a riding helmet in
  the seat's colour). The Rider's up/down picks the mare's coat and the Foal
  seat's up/down picks the foal's coat: bay, chestnut, palomino, grey, black,
  pinto, and appaloosa for the foal. Once the Rider is ready, their
  left/right picks where the day starts: the stable, the trail or the show.
- The rosette wall is saved in `user://rosette_wall.json`. The demo and the
  tests use their own files and never touch it.

## Run it

```
make setup    # once: the pinned Godot + GUT, Python deps via uv
make start    # play
make demo     # watch it play itself (SHOT_SCREEN=stable|trail|show|party|join|select)
make help     # tests, art and sound generation, frame captures, export
```

The art comes from generators and text grids (`make sprites`), and the sound
from our own synth (`make sfx`). See [CLAUDE.md](CLAUDE.md) for the
architecture and contracts, and [PLAN.md](PLAN.md) for the plan and its
decisions.
