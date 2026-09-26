# Next games: couch co-op for an adult, a 5-year-old and a 2-year-old

Ideas list, started 2026-09-26. Every idea keeps the PixelPals formula:

- **Adult**: the hard input (steering, timing).
- **5-year-old**: 1-2 buttons and at most 4 directions, with assists.
- **2-year-old**: "any button makes something delightful happen", and can
  never hurt the run.
- No game over, no text, sessions of 3-10 minutes.

Not tied to pixel art: some ideas suit low-poly 3D or flat vector better.
Every idea now has a plan in `games/<slug>/PLAN.md` (status: plan). The first game,
[PixelPals](../games/pixelpals/README.md), is playable.

| # | Idea | Adult | 5-year-old | 2-year-old | Style | Why the kids would like it |
|---|---|---|---|---|---|---|
| 1 | **[Fire Truck Rescue](../games/fire-truck-rescue/PLAN.md)** | drives the truck through town | aims the hose (4 directions) at fires, cats in trees | siren and flashing lights; the ladder goes up | low-poly 3D | trucks, water, sirens |
| 2 | **[Train Conductor](../games/train-conductor/PLAN.md)** | speed and stops at stations | picks left/right at each junction, so the route is theirs | toots the whistle; passengers wave and hop on | low-poly 3D or vector | choices that matter and cannot go wrong |
| 3 | **[Tractor Farm](../games/tractor-farm/PLAN.md)** | drives the tractor over fields | chooses what to plant (4 vegetables) | the rain cloud: any press rains, so crops grow instantly | vector | cause and effect the toddler can see |
| 4 | **[Submarine Safari](../games/submarine-safari/PLAN.md)** | steers the sub | points the camera and snaps fish into an album (collect them all) | sub lights flash and fish glow and dance | 2D, deep blue | no shooting at all, collecting |
| 5 | **[Tower Topple](../games/tower-topple/PLAN.md)** | positions blocks | drops them | knocks the tower down, with a big celebration | 2D physics | toddlers LOVE knocking towers over |
| 6 | **[Band in the Garage](../games/garage-band/PLAN.md)** | plays melody lanes (easy rhythm) | 4 drum pads | cymbal crash | vector | a pentatonic scale, so nothing sounds wrong |
| 7 | **[Paint Party](../games/paint-party/PLAN.md)** | moves the big brush | picks colours and stamps | splat: a random paint explosion | vector, the canvas saved as a PNG | the result is a picture to print for the fridge |
| 8 | **[Rocket to the Moon](../games/rocket-to-the-moon/PLAN.md)** | pilots through stars | grabs fuel and planets (4 directions) | the launch button: countdown and blast-off | pixel or vector | the countdown ritual |
| 9 | **[Digger Treasure](../games/digger-treasure/PLAN.md)** | drives the digger | chooses where to dig (arrows) | "boom": dirt flies and treasure pops | pixel | digging and surprises |
| 10 | **[Zoo Keeper](../games/zoo-keeper/PLAN.md)** | walks the keeper around | picks which food each animal wants (4 foods) | the animal makes its sound and dances | vector | animal sounds, learning foods |
| 11 | **[Pancake Kitchen](../games/pancake-kitchen/PLAN.md)** | moves the pan and catches | adds toppings | flips the pancake (boing) | vector | silly food, no wrong answers |
| 12 | **[Pillow Fort Hide and Seek](../games/pillow-fort/PLAN.md)** | moves the flashlight | finds the hidden toys (4 directions) | "peekaboo": characters pop out | 2D | toddler peekaboo stage |
| 13 | **[Space Mission](../games/space-mission/PLAN.md)** | flies the Shuttle, sky crane, drives the Mars rover | robot arm: builds the ISS module by module, drills Mars rocks | Earth photos, parachute, Mars helicopter | pixel (Endesga 32) | real space: ISS, Shuttle, Mars landing, rover, blue Mars sunset |

## A path toward independence

When the 5-year-old gets better, give them their own character with a tether
to the adult: they cannot get lost and respawn instantly in a bubble. Kirby,
Yoshi and Mario Galaxy Co-Star are the references. A good second game is
PixelPals with a "Gunner steers" mode, where the 5-year-old takes the wheel
and the adult takes the turret.

## Reuse from PixelPals

The same `Players` seat/input autoload, the keyboard blocks, the demo driver
and frame captures, the art pipeline (grids or generators plus lint) and the
synthesized audio all carry over. Most ideas above are the "shared vehicle"
pattern with a different vehicle.

## Roadmap: shared work before the second game

The 12 plans (written 2026-09-26) all ask for the same extractions from
PixelPals into `shared/`. Do them once, as the first step of whichever game
is built next, and keep PixelPals green (`make test` at the root):

- [ ] **Screens**: the join, select and party screens and the screen router
  (`Game.goto`), made generic. Seat names become neutral (seat 1/2/3 with
  a per-game role icon) instead of DRIVER/GUNNER/HONKER.
- [ ] **Input helpers**: `Players.dir4_just_pressed(seat)` (menus and
  junction choices) and `aim.gd` (aim assist).
- [ ] **Asset tools**: the `sprites.py` engine (grids, generators, lint,
  contact sheet) and the `sfx.py` synth, split into a shared engine plus
  per-game content.
- [ ] **Vector helpers**: a small helper for drawing flat vector shapes
  (Polygon2D, rounded rectangles, outlines) for the non-pixel games.
- [ ] **Demo driver**: a base class so each game only scripts its own
  inputs.

## Open questions (all games)

- **Dad plus toddler only.** With two pads, the second pad takes seat 2, not
  the toddler's seat 3. On the keyboard, kb:2 already takes seat 3 when it
  is free. Proposal: on the join screen, pressing a seat's icon direction
  (or holding) picks that seat explicitly.
- **kb:2 has no directions**, so the 5-year-old's roles need kb:1 or a pad.
- **Real recordings** (e.g. CC0 animal sounds for Zoo Keeper) if the
  synthesized ones do not sound right. This is Oriol's call.
- **Which game next?** The recommended order is Tower Topple (a small scope
  and the toddler's favourite), then Submarine Safari, then Fire Truck
  Rescue.
