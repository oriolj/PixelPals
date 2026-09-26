# Digger Treasure

A couch co-op digging game for a parent and small kids. Everyone rides one
little yellow digger through a side-view field of dirt, and every buried
treasure it uncovers flies into the dump truck.

| Seat | Who | Does | Pad | Keyboard |
|---|---|---|---|---|
| 1 Driver (blue) | the grown-up | drives (driving into dirt digs); small scoop forward | left stick / d-pad; A = scoop; Start = pause | WASD; Shift = scoop; Esc = pause |
| 2 Scooper (yellow) | a 5-year-old | points the arm up, down, left or right and takes a big bite | d-pad / stick aims; A = big scoop | arrow keys aim; Enter = big scoop |
| 3 Boomer (green) | a 2-year-old | BOOM: a round blast of dirt that pops nearby treasure up | any button | Space or any other key |

- Treasures glint through thin dirt, brighter as the digger gets close.
- Worms, snails, bones, fossils and a waving mole are hiding too. They are
  never a miss.
- Nobody can lose. There is no damage, no fuel and no game over. After five
  minutes the last treasures burst up by themselves. A full truck ends in a
  party.
- With 1 or 2 players a surprise boom goes off every 20 seconds.
- In the pause, the driver's B (Q on the keyboard) goes back to joining.
- On the select screen the driver's up/down picks the digger's colour.

## Run it

```
make setup    # once: shared Godot 4.7.2 + venv at the repo root, GUT here
make start    # play
make demo     # watch it dig by itself
make help     # everything else (tests, assets, frame captures, export, tmux)
```

See [CLAUDE.md](CLAUDE.md) for the architecture and the asset contract, and
[PLAN.md](PLAN.md) for the plan and the open decisions.
