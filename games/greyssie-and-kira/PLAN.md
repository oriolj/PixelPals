# Where Are Greyssie and Kira?

Find our two grey cats hiding around our three-storey home, coax them out
with treats and a laser dot, and bring them both to their dinner bowls.

Status: playable (2026-09-27)

## Why it fits our family

It is the kids' own world: their house, their stairs, their cats. Unlike
Pillow Fort (static toys under pillows), **the cats are alive**:
- They wander, nap in sunny spots and change hiding places.
- They answer to treats and chase the laser dot.
- They get the zoomies up the stairs.

Finding them is a small story each time, not a lookup.

- **The 5-year-old** holds the laser pointer: the red dot moves in 4
  directions, and the cats cannot resist it. Luring a cat out of a box, or
  down from the wardrobe, is their job and their triumph.
- **The 2-year-old** shakes the treat bag. ANY button makes "psst psst" and
  a rattle, and the nearest cat meows back. A meow bubble pops out of the
  wall of the room it is in, and the house view flashes that room. This is
  the toddler's real superpower: every find starts with their shake.
- **The adult** walks the family character through the house (stairs, doors),
  opens cupboards, and picks the cats up for cuddles once they come out.
- **Real-life match.** Afterwards the kids can go and find the real
  Greyssie and Kira in the same places.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Walker** (adult): walks the character left/right, up/down stairs, opens and closes hiding spots, picks up a cat that came out | left stick / d-pad, A = open / pick up / put down, Start pauses, B = back (pause only) | kb:0: WASD, Shift = open / pick up, Esc pauses, Q back |
| 2 | **Laser** (5-year-old): moves the red dot in 4 directions inside the current room; a cat that sees it follows and pounces | d-pad / stick 4-way, A = "wiggle" (the dot dances: cats pounce faster) | kb:1: arrows, Enter = wiggle |
| 3 | **Treats** (2-year-old): any press shakes the treat bag, and the nearest cat meows back and shows where it is | any button | kb:2: Space or any other key |

With fewer seats:
- **1 seat:** holding A near a hiding spot shakes the treats, and the dot
  follows the walker.
- **2 seats (no toddler):** the treat bag shakes by itself every 12 s.
- **2 seats (no 5-year-old):** cats that have been called come out on their
  own after 3 s.

## The house

A cutaway dollhouse: three floors seen from the side, stairs on one side
and rooms side by side. The camera frames one floor at 320x180 and slides
up and down with the stairs. When the toddler's meow rings out, a
**whole-house mini view** (all three floors, tiny) flashes for 2 s at the top
with the meowing room lit, so the kids learn the house map.

**Default layout until Oriol gives the real one** (3 floors, 3–4 rooms each):

- **Ground floor:** entrance, living room (sofa, TV, plant, sunny window),
  kitchen (the cats' bowls = the goal), laundry corner.
- **First floor:** the kids' bedroom (toy box, beds), bathroom (bathtub,
  laundry basket), parents' bedroom (wardrobe, bed).
- **Top floor:** study or attic (boxes, desk, bookshelf), terrace door
  (plant pots, a sunny cushion).

The layout is data in `data/house.json`: rooms per floor, furniture, hiding
spots and sunny spots. Swapping in the real house is an edit to one file,
with no code changes.

**Hiding spots** (about 20; each has an "occupied" look: a tail tip, ears
or glowing eyes):
- under the sofa or a bed;
- inside a box, the laundry basket, the toy box, a wardrobe or a cupboard;
- on top of the wardrobe or bookshelf;
- behind the curtain;
- in the bathtub or the sink;
- in a sunny window;
- in a plant pot (a cat classic);
- on the warm TV box.

## Core loop

A game is **one day in the house**: morning, afternoon, evening and night.
That is 3–4 rounds and about 8 minutes, and the light through the windows
changes with each round.

1. **Round start:** both cats slip away to hiding spots. There is a whoosh,
   a tail vanishing around a door, and a little giggle sound.
2. **Search:**
   - The walker explores floor by floor.
   - The toddler shakes the treats: the nearest cat meows (the bubble shows
     its room in the house view), and the cat, still hidden, twitches its
     tail tip so it is visible up close.
   - The walker opens the hiding spot: the cat is there, eyes wide,
     "mrrp?".
3. **Coax out:** some cats come out alone when the spot opens. Shy ones and
   high places (top of the wardrobe) need the laser. The 5-year-old moves
   the dot near the cat, and it wiggles, stalks, pounces and lands on the
   floor.
4. **Carry:**
   - The walker picks the cat up. It purrs, with hearts, and rides on the
     character's shoulder.
   - Carrying a cat, the walker can still search for the other.
   - Carrying both is allowed and very funny: one on each shoulder.
5. **Dinner:** put both cats down at their bowls in the kitchen. The bowls
   fill, the cats eat, there are purrs, and the round's star appears. Then
   the next part of the day starts.
6. **Night round (last):** the cats are sleepy and hide in cosy spots, and
   the lights are warm and dim, as in Pillow Fort (never dark).
7. **The end:** everyone goes to bed, and the two cats curl up at the
   kids' feet.

**Cat personalities** (defaults; they must match the real cats, see the
open questions):
- **Greyssie:** confident, likes high places and sunny windows, comes out
  easily, very chatty (meows back twice).
- **Kira:** shy, likes boxes and under-things, needs the laser, a quiet
  "mew".

Their two different hiding tastes teach the kids where each one goes.

**Surprises that are never bad:**
- **Zoomies:** a freed cat sometimes runs up or down the stairs, and the
  laser brings it back.
- A cat knocks a cup off a table: boing, the cup bounces, and nothing
  breaks.
- A cat sits in a box that is too small for it.
- A cat "helps" by sitting on the laundry.

### No-fail rules

- A cat never truly escapes. If the walker takes more than 60 s to find a
  cat, its tail pokes out further, and at 90 s it walks out and meows at
  the walker.
- Opening an empty spot shows a funny find: a toy mouse, a sock, a ball of
  wool, or dust bunnies with faces.
- Nothing breaks, nobody gets scratched, no time runs out.

## Screens and flow

join → select → house → party → select, copied from PixelPals and adapted.

- **join:** role icons: shoes for the walker, the laser pointer, the treat
  bag.
- **select:** the family character to walk around as, with the riders plus
  the private pack, and later maybe the family itself (see the open
  questions). The laser and treat seats pick a hat colour.
- **house:** the level.
- **party:** "dinner time" in the kitchen: both cats eating, then a group
  cuddle on the sofa. A photo-strip of the day's finds shows each cat in the
  spot where it was found.

## Art direction

Pixel art at 320x180, integer scaled, Sweetie 16. Its greys (`#94b0c2`,
`#566c86`, `#333c57`) are exactly what two grey cats need, and they have
to stay distinct from each other; see below. The pipeline is PixelPals's
`tools/sprites.py` (grids and generators, linted, contact sheet).

**Telling two grey cats apart** is the key art problem. Default until Oriol
describes them:
- **Greyssie:** light grey (`#94b0c2`) and fluffy, with a round silhouette,
  big tail and a pink collar.
- **Kira:** dark grey (`#566c86`) and sleek, with a slim silhouette, long
  tail, green eyes and a teal collar.

They are always shown with their collar colour, and both the meow bubble
and the HUD badge use that colour.

| Asset | Size | Frames | Notes |
|---|---|---|---|
| greyssie_*, kira_*: idle, walk, sit, sleep, stalk, pounce, eat, carried, zoomies, tail-tip, peek-eyes | 16x12 – 20x16 | 2–4 each | grids, one set per cat |
| walker (per rider) | 16x16 | walk 4, climb 2, carry 2 | the rider grids plus arms (generator) |
| laser_dot | 3x3 | 2 | red, a glow ring |
| treat_bag | 12x14 | 3 (shake) | toddler HUD |
| meow_bubble | 20x14 | 2 | collar-coloured |
| house_mini | 64x40 | 1 | the whole-house outline, rooms lit by code |
| rooms: walls, floors, stairs, windows (day/afternoon/evening/night tints) | 16x16 tiles | 1 | generator from `house.json` |
| furniture: sofa, beds, wardrobe, bookshelf, bathtub, basket, boxes, toy box, plant pots, curtains, cupboards, desk, TV, table, cushion | 16x16 – 64x40 | 1–2 (open/closed) | grids |
| funny finds: toy mouse, sock, wool ball, dust bunny, cup | 8x8 | 2 | grids |
| bowls (empty/full), hearts, zzz, star, confetti | 8x8 – 12x8 | 1–3 | grids |
| seat icons: shoes, laser, treat bag; icon_pad, icon_kb | 16x16 | 1 | grids |

## Audio (our synth)

| Sounds |
|---|
| `treat_shake_1..3` (a rattle), `psst` (a filtered noise burst) |
| `meow_greyssie_1..3` (brighter, two-part), `meow_kira_1..3` (soft, short), `mrrp`, `purr` (loop), `hiss_free` (no hisses: it is a playful "prrt" instead) |
| `pounce`, `zoomies` (pitter-patter loop), `cup_boing`, `open_door`, `open_box`, `stairs_step`, `bowl_fill`, `eat_crunch` |
| `find_star`, `funny_find`, `day_chime` (a new part of the day), `goodnight` |
| music: `music_house` (cosy, 90 BPM), `music_night` (music box, as in Pillow Fort), `music_menu` |

Cat voices are formant-synthesized like Zoo Keeper's animals. **Better:**
if Oriol records ~10 s of real meows from each cat on his phone, those
become the voices. That would be the one exception to "sound from our
code", and it is his call.

## Reuse

- **shared:** `players.gd`, `art.gd`, `sfx.gd` and `shots.py`.
- **From PixelPals:** the join/select/party screens and the demo driver.
- **From Pillow Fort:** the warm-night lighting rules, the "hiding spot
  lifts" state machine and the funny-find idea.
- **From Zoo Keeper:** the formant voice synth for the meows.
- **From Digger Treasure:** the camera leaning toward targets.

## New tech

- **House graph from JSON:** floors, rooms, doors and stairs as nodes.
  Walking is 1D along a floor, and the stairs switch floors.
- **Cat AI:** a small state machine (hide → alert → peek → come out /
  stalk → pounce → carried → eat), with personality weights per cat.
- **Laser lure:** the cat steers toward the dot when it is within its sight
  cone. `wiggle` raises its pounce chance.
- **Camera:** one floor framed at a time, sliding up or down on the stairs,
  plus the whole-house mini view on a meow.
- **Risks:** Godot 3 drift; hand-made `.tscn` files (build in code);
  headless runs render nothing (frames via the demo driver); two grey cats
  can be too alike (check it in frames at 1x and in silhouette).

## MVP and milestones

**M1: grey box**
- [x] Skeleton from PixelPals: Makefile, project, join/select/party, demo
  driver, symlinked shared autoloads.
- [x] `house.json` with the default layout, walking, stairs, floor camera.
- [x] Hiding spots that open and close, and two cats that hide each round.
- [x] Treat shake → meow, bubble, mini view; the laser lure; pick up,
  carry and bowls; four rounds of the day.
- [x] Fallbacks for 1 and 2 seats; the 60 s / 90 s no-fail timers.

**M2: art and audio**
- [x] Both cats' full animation sets, clearly distinct at 1x and in
  silhouette (`art_src/cats_compare.png`; looks are placeholder, pending Oriol).
- [x] Rooms, furniture and time-of-day tints; the night is warm, never dark.
- [x] All sounds; meows are synthesized, or real recordings if Oriol
  provides them (the drop-in hook works; recordings placeholder, pending Oriol).

**M3: polish and couch test**
- [x] Personalities tuned (placeholder, pending Oriol); zoomies, cup boing and box-too-small gags.
- [x] Party photo-strip with the find spots.
- [x] The real house layout and the real cats' looks, once Oriol describes
  them: placeholder, pending Oriol. Both are data only (`data/house.json`,
  `data/cats.json`; see CLAUDE.md "Making it our real house and cats").
- [x] Couch test: placeholder, pending Oriol (only a real couch session can
  tick it; the headless `make demo-day` plays a whole day).

## Tests and verification

GUT:
- `test_house_graph_connects_every_room`
- `test_stairs_move_between_floors`
- `test_each_cat_hides_in_a_valid_spot_per_round`
- `test_cats_never_share_a_spot`
- `test_treat_shake_makes_nearest_cat_meow`
- `test_meow_reveals_the_room_in_mini_view`
- `test_laser_lures_shy_cat_out`
- `test_cat_walks_out_after_90s`
- `test_empty_spot_gives_a_funny_find`
- `test_carry_both_cats`
- `test_dinner_needs_both_cats_at_bowls`
- `test_day_has_four_rounds_then_party`
- `test_toddler_input_never_hurts`
- `test_one_and_two_seat_fallbacks`
- `test_pause_only_by_walker`

Demo driver: `--demo=house|night|party|join|select`. Scripted seats: the
toddler shakes every 3 s, the walker follows the meow bubble's room and
opens the spot, the laser points at a shy cat, and the walker carries both
cats to the bowls.

Look at the frames for:
- the two cats are distinguishable;
- the laser dot is visible;
- the mini view lights the right room;
- the night is warm;
- nothing is off-screen.

## Open questions for Oriol

1. **How do Greyssie and Kira look?** Fur shade (light, dark, silver,
   blue-grey), fluffy or sleek, eye colour, any white patches, collars,
   size. **Best:** drop a couple of photos of each in `~/tmp/`. I can look
   at them and derive the sprite palettes and markings. The photos stay
   local and never go into the repo.
2. **Their personalities and real favourite hiding spots?** (Who is shy,
   who is chatty, who sleeps where.)
3. **The house:** which rooms are on each of the three floors, and where are
   the stairs and the cats' bowls? A rough list is enough. It stays in this
   public repo: no address or photos of the house.
4. **Real meow recordings** from your phone as their voices, or
   synthesized?
5. **Should the family appear as the walker** (pixel versions of you and
   the kids), or keep the animal riders?

## Decisions taken (pending Oriol)

Taken on 2026-09-27 so the game could be built before the real details
arrived. Each one is data or a drop-in file; none needs code.

1. **The cats' looks** (`game/data/cats.json` `look`): Greyssie light grey
   (Sweetie 13), fluffy and round, round ears, amber eyes, raspberry collar
   (Sweetie has no pink); Kira dark grey (14), sleek, tall ears, lime-green
   eyes, cyan collar (Sweetie's teal was too dark on grey fur). No patches.
   **Send:** two or three photos of each cat in `~/tmp/` (side view and
   face), or a description: fur shade, fluffy or sleek, eye colour, white
   patches, collars, size. The photos are read locally, never committed;
   then it is one JSON edit, `make sprites` and a look at the comparison sheet.
2. **Personalities and hiding tastes** (`personality`, `favourite_spots`):
   Greyssie bold, chatty (meows twice), likes high places and sun; Kira shy
   (always needs the laser or 3 s alone), quiet, likes boxes and
   under-things. **Send:** who is shy, who is chatty, where each one really
   sleeps and hides, and whether either gets the zoomies.
3. **The house** (`game/data/house.json`): the plan's default layout, three
   floors, stairs on the left, bowls in the kitchen, 21 hiding spots.
   **Send:** a rough list of the rooms on each floor, which side the stairs
   are on, where the bowls are, and the real hiding places. No address, no
   photos of the house.
4. **Voices**: meows are formant-synthesized from each cat's `voice` block
   (Greyssie bright and two-part, Kira a soft short mew). **Send (optional):**
   ~10 s of real meows of each cat from the phone. Trimmed clips go in
   `game/audio/real/meow_greyssie_*.wav` / `meow_kira_*.wav`, which the game
   prefers automatically; they are gitignored and stay on this machine
   unless Oriol asks otherwise.
5. **The walker** is one of the animal riders (or the private-pack
   characters); the laser and treat seats pick a hat colour. **Decide:**
   whether the family should appear as pixel versions of themselves (that
   would be new rider grids, drawn from a description, not from photos).
6. **Small calls:** the plan's `hiss_free` sound is named `prrt`; the party
   music is 105 BPM (96 BPM has no whole-sample eighth notes); the night
   round's outside sky is plum, not navy, to stay warm; a cat that has been
   free for 25 s without being picked up walks to the walker; zoomies are a
   lap up the stairs and back, so no cat is ever stranded on another floor.

Proposed shared change (not applied; `shared/` is read-only for this build):
`Sfx.override(sound: String, streams: Array)` in `shared/godot/autoload/sfx.gd`,
so a game can swap a sound's variants (the real-meow hook) without writing
`Sfx._streams`:

```gdscript
## Replace a sound's variants (e.g. real recordings instead of the synth).
func override(sound: String, streams: Array) -> void:
	_streams[sound] = streams
```
