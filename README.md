# Couch co-op games

Games for a grown-up plus a 5-year-old and a 2-year-old on one screen.
Nobody can lose, there is no text, and the toddler's any-button is always a
good thing.

## Play on the TV

```
make launcher         # the game picker, fullscreen: any pad or the keyboard drives it
```

- **Choose** with the d-pad or stick (arrows or A/D on the keyboard), **play** with
  A (Enter or Space). The last game played comes first.
- **Leave a game** from the sofa: hold **Back/Select + Start** on any pad for
  1.5 s, or press **Ctrl+Q**. You land back in the launcher on the same card.
- **Switch off**: the "Turn off" card at the end, hold A for 2 s.
- `make install-desktop` adds "Couch Games" to the desktop menu. Details:
  [launcher/README.md](launcher/README.md).

## Everything else

```
make setup            # once: Godot 4.7.2 + Python venv, then each playable game
make list             # every game: playable or plan
make start            # the TV launcher (or one game: make start G=<slug>)
make demo             # watch it play itself
make test             # tests of every playable game
```

| Game | Status |
|---|---|
| [PixelPals](games/pixelpals/README.md): the flying bathtub | playable |
| [Fire Truck Rescue](games/fire-truck-rescue/README.md) | playable |
| [Train Conductor](games/train-conductor/README.md) | playable |
| [Tractor Farm](games/tractor-farm/README.md) | playable |
| [Submarine Safari](games/submarine-safari/README.md) | playable |
| [Tower Topple](games/tower-topple/README.md) | playable |
| [Garage Band](games/garage-band/README.md) | playable |
| [Paint Party](games/paint-party/README.md) | playable |
| [Rocket to the Moon](games/rocket-to-the-moon/README.md) | playable |
| [Digger Treasure](games/digger-treasure/README.md) | playable |
| [Zoo Keeper](games/zoo-keeper/README.md) | playable |
| [Pancake Kitchen](games/pancake-kitchen/README.md) | playable |
| [Pillow Fort Hide and Seek](games/pillow-fort/README.md) | playable |
| [Space Mission](games/space-mission/README.md): ISS, Shuttle, Mars landing and rover | playable |
| [Where Are Greyssie and Kira?](games/greyssie-and-kira/PLAN.md): find our two grey cats around the house | plan |
| [Pony Trails](games/pony-trails/PLAN.md): groom, ride the trail with a foal, horse show | plan |

The ideas and the reasoning behind them are in [docs/ideas.md](docs/ideas.md).
Contributor and agent rules are in [CLAUDE.md](CLAUDE.md).
