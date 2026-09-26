# Pancake Kitchen

A couch co-op cooking game for a grown-up, a 5-year-old and a 2-year-old.
The little one flips pancakes sky-high, the grown-up slides the pan to catch
them, and the 5-year-old piles toppings on for hungry animal customers.
Nothing burns, nothing is lost, and every customer loves every pancake.

Run it with `make start` (from this folder), or `make start G=pancake-kitchen`
at the repo root. First time: `make setup` at the repo root.

## Controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | Cook (grown-up) | left stick / d-pad slides the pan; "A" serves the plate (and flips when nobody is the flipper); "B" serves; Start pauses | A / D slide, Shift serves, Q serves, Esc pauses |
| 2 | Topper (5-year-old) | d-pad / stick picks a jar (up strawberry, right chocolate chips, down banana, left whipped cream); "A" drops it | arrows pick, Enter drops |
| 3 | Flipper (2-year-old) | any button flips; in the air it adds a spin | Space or any other key |

- **Joining**: press any button (or key block) on the first screen; the
  cook holds "A" for a second (or presses Start) to go on.
- **Chef select**: left/right picks the animal chef, up/down the hat colour,
  "A" is ready. The flipper's presses cycle chefs and it gets ready by itself.
- **Pause**: the cook's Start. In pause, "A" or Start goes back to the
  kitchen and "B" goes back to the join screen.
- **One player**: the cook flips with "A" and serves with "B"; customers
  sprinkle their own toppings.

## How a round goes

Batter pours into the pan and cooks from pale to golden. Flip it (it spins up
and falls); slide the pan under it and it snaps in. Missed? The dog, the
shelf cat or a bouncy counter sends it back to the pan. Two flips and it hops
onto the plate. Three on the plate and the plate glows: serve it, and the
customer eats and cheers (the more toppings, the bigger the cheer). Six
customers, then a party.

`make demo SHOT_SCREEN=kitchen` watches it play itself.
