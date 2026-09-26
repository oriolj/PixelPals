# Rocket to the Moon

Count down, blast off and fly a rocket through the stars to the Moon, grabbing fuel and planets on the way.

Status: plan (2026-09-26)

## Why it fits our family

- **The 2-year-old** owns the launch: pressing the big button starts the
  countdown lights, the rumble and the blast-off. Rituals delight
  toddlers, and this one repeats at every stage of the trip. In flight,
  any press fires the booster: flames, speed lines, a whoosh.
- **The 5-year-old** runs the grabber arm in 4 directions and catches fuel
  cans and little planets for the collection, with a generous aim assist.
- **The adult** pilots the rocket through the starfield and lands it on
  the Moon.

## Roles and controls

Seats fill in join order; the keyboard column is the suggested block. The
Grabber needs directions, so not kb:2.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Pilot** (adult): steers the rocket in the scrolling sky, lands it | left stick, Start pauses (B = back, in pause only) | kb:0: WASD, Esc pauses, Q back |
| 2 | **Grabber** (5-year-old): shoots the claw arm in 4 directions | d-pad / stick picks the direction, A shoots the claw | kb:1: arrows aim, Enter shoots |
| 3 | **Launcher** (2-year-old): launch button on the pad, booster in flight, flag on the Moon | any button | kb:2: Space or any unowned key |

Fewer seats:

- **1 seat:** the Pilot's A launches and boosts; pickups are collected by
  flying through them (a magnet pulls nearby fuel).
- **2 seats:** Pilot plus Grabber; the Grabber's A launches, and the
  booster fires by itself at every stage change.
- Every stage transition waits for the Launcher if seated, and times out
  after 8 s with an automatic press so nobody is stuck.

## Core loop

The run is one trip in four stages, about 5 minutes:

1. **Launch pad (about 20 s).** The rocket on its gantry, the riders in
   helmets at the windows. The big button pulses. The Launcher presses:
   five lights go out one by one with beeps (each further press makes
   the rocket shake and puff steam, but cannot skip the count), then
   ignition, smoke clouds, a rumble, and lift-off.
2. **Sky (about 60 s).** Vertical scroll through clouds and birds; fuel
   cans and balloons to grab.
3. **Space (about 150 s).** Stars, comets, little planets to collect (8
   kinds, one album page), soft grumpy asteroids to avoid. At the halfway
   point, a second countdown: stage separation, the Launcher's big moment
   again.
4. **The Moon (about 40 s).** The Moon grows; the Pilot lines up with the
   landing pad (a wide target with arrows). Landing puffs dust, then the
   Launcher's press plants the flag, and the party begins on the Moon.

### No-fail rules

- **Asteroids are soft.** A bump makes the rocket wobble and spin one full
  turn, drops two fuel cans that float nearby (they can be grabbed back),
  and gives 1.5 s of blinking invulnerability. Nothing breaks.
- **Fuel only changes the flame.** An empty tank makes the flame small
  and the scroll 30 % slower; the riders pedal, the rocket never stops.
- **The screen edges are soft walls**; the rocket cannot leave.
- **Landing cannot crash.** Off-pad landings bounce gently back up for
  another go; after three tries the pad slides under the rocket.
- **The booster (toddler)** gives 1 s of speed and flames, cleans up
  asteroids in its path into stars, and has a 1.2 s cooldown. It cannot
  push the rocket into anything.
- **The trip always ends at the Moon** after about 5 minutes, whatever
  happened.

## Screens and flow

`join` → `select` → `launch` → `flight` → `party` → `select`. `select`
puts each rider in a helmet. `launch` and `flight` could be one screen
with stages; they are separate screens so `make shot` can capture the
countdown alone. `party` is on the Moon: flag, dancing riders in helmets,
the collected planets shown as an album page (collected ones in colour,
missing ones as grey silhouettes), and the fuel count in the PixelPals
digit glyphs.

## Art direction

**Pixel art, 320x180, the PixelPals pipeline unchanged.** Rockets, stars
and planets are iconic in pixel art, nothing needs free rotation (the
wobble uses 8 pre-drawn frames, the claw turns in 90-degree steps), and it
is the cheapest reuse: `sprites.py` grids, Sweetie 16, the lint, the
contact sheet. Vertical scrolling in a 16:9 frame is fine because the
rocket sits in the lower third and the scroll is slow.

Every sprite is a palette-indexed text grid in `art_src/*.txt` rendered
by our script; round bodies (planets, Moon) come from a small generator
that writes grids (a disc with shading bands and crater circles), then
the same renderer and lint.

| Sprite | Size | Frames | How |
|---|---|---|---|
| rocket | 24x40 | 2 (idle rumble) + 8 (wobble spin) | grid; spin frames drawn as grids |
| flame | 8x12 | 4 (big) + 4 (small) | grid |
| smoke | 16x16 | 4 | grid |
| gantry | 16x64 | 1 | grid |
| launch_pad | 64x16 | 1 | grid |
| countdown_light | 12x12 | 2 (off, on) | grid |
| big_button | 24x16 | 2 (idle, pressed) | grid |
| claw | 8x8 | 2 (open, closed), rotated in 90-degree steps | grid |
| arm_link | 4x4 | 1 | grid, repeated along the arm |
| fuel | 8x12 | 2 | grid |
| planet_1…planet_8 | 16x16 | 2 | generator (disc, bands, rings) |
| asteroid | 16x16 | 2 (grumpy, blink) | grid |
| comet | 16x8 | 2 | grid |
| moon | 96x96 | 1 | generator (disc, craters) |
| moon_ground | 320x32 | 1 | generator strip, tiles |
| flag | 16x16 | 2 | grid, tinted with seat colours |
| helmet | 20x20 | 1 | grid, drawn over the 16x16 riders |
| earth_ground | 320x48 | 1 | grid |
| sky_band, star_far, star_near | procedural | — | `_draw()`: gradient bands, 1-2 px stars in 3 parallax layers |
| album_frame, silhouette | 16x16 | 1 | grid; silhouettes are the planet grids filled with one colour by the generator |

## Audio

Our own synth script (`tools/sfx.py`, on the shared synth):
`beep_1`…`beep_5` (countdown, rising), `ignition` (noise swell),
`rumble` (low filtered noise loop), `liftoff` (big whoosh plus chord),
`booster_1`…`booster_3`, `claw_shoot`, `claw_grab`, `fuel`, `planet`
(a sparkle, one pentatonic note per planet kind), `bump` (soft boing),
`separation` (clank plus whoosh), `landing` (dust thud), `flag` (fanfare),
`join`, `select`, `ready`, `party`. Music: `music_space` (a floaty 100
BPM loop) and `music_menu` (reused).

## Reuse

- **From shared/:** `players.gd`, `art.gd`, `sfx.gd`, `tools/shots.py`.
- **From PixelPals:** `tools/sprites.py` and the palette, the demo driver
  pattern, join/select/party, the digit glyphs, and above all
  `level/aim.gd` (the cone aim assist and the 90-degree turret rotation
  are exactly the claw's needs), the soft-bump rules from `level/rules.gd`.
- **Extract into shared/ first:** `aim.gd` (to `shared/godot/`), the
  sprite renderer and lint (`shared/tools/sprites.py` with a per-game
  palette and `art_src`), the shared screen router and screens, and
  `shared/tools/synth.py`.

## New tech this game needs

- **Vertical scrolling with stage scripting:** a timeline of spawn
  events per stage (a data file, not code), with a stage clock.
- **The countdown ritual** as a small state machine that input cannot
  skip or break.
- **A grabber arm:** extend-and-retract along a direction with the aim
  cone snapping to the nearest pickup; it carries the pickup back.
- **A collection album** kept across runs in `user://album.json` (the
  planets found so far).
- **Risks for Claude-built Godot:** Godot 3 drift (`AnimatedSprite2D`,
  not `AnimatedSprite`; `Tween` is `create_tween()`, not a node);
  `.tscn` breakage, so every screen is built in code; headless runs render
  nothing, so the countdown and grabber are tested as logic, and the look
  of launch and flight comes from `make shot` under xvfb.

## MVP scope

One trip (launch, sky, space, Moon) with the four stages above, 8
planets, about 5 minutes.

### M1 grey-box

- [ ] Skeleton (pixel settings from PixelPals, Makefile, CLAUDE.md +
  AGENTS.md, shared autoload symlinks).
- [ ] Launch countdown state machine with placeholder rectangles.
- [ ] Scrolling flight, spawn timeline, fuel, asteroids with soft bumps.
- [ ] Grabber arm with aim assist; booster.
- [ ] Moon landing with retries and the sliding pad.
- [ ] Fold-down for 1 and 2 seats, the 8 s auto-press.
- [ ] Couch test: is the countdown too long for the 2-year-old? Can the
  5-year-old catch planets?

### M2 art and audio

- [ ] All grids and generators; `make sprites` passes the lint; contact
  sheet reviewed at 8x, rocket and planets checked as silhouettes.
- [ ] Every sound above; loudness report.

### M3 polish and couch test

- [ ] Screen shake on lift-off, parallax stars, stage separation.
- [ ] Album page on the party screen, saved across runs.
- [ ] Clean-clone run; tuning from couch notes.

## Tests and verification

GUT tests (`game/tests/`):

- `test_countdown_cannot_be_skipped_by_presses`
- `test_countdown_auto_presses_after_eight_seconds`
- `test_asteroid_bump_never_stops_the_rocket`
- `test_empty_fuel_slows_but_never_stops`
- `test_dropped_fuel_can_be_grabbed_back`
- `test_claw_snaps_to_nearest_pickup_in_cone`
- `test_claw_rotates_in_quarter_turns`
- `test_booster_cooldown`
- `test_booster_turns_asteroids_into_stars`
- `test_offpad_landing_bounces_and_pad_slides_after_three`
- `test_trip_always_reaches_the_moon`
- `test_album_persists_new_planets`
- `test_one_seat_pilot_launches_and_boosts`

Demo driver: "launch" has the Launcher press at 1 s and mash during the
count (showing it cannot skip); "flight" has the Pilot weave on a sine
and dodge, the Grabber cycle directions and shoot every second, the
Launcher boost every 3 s, with stage lengths shortened so one capture
reaches the Moon and the landing.

Look at in the frames (`shots/launch/sheet.png`, `shots/flight/sheet.png`,
3x): the lights go out in order; smoke frames are clean; the rocket stays
in the lower third; the claw points the right way; planets are readable as
different kinds; the Moon landing and flag show; no sub-pixel jitter on
the scrolling stars.

## Open questions for Oriol

1. Countdown: lights only, or also big pixel numbers 5 to 1 (digits as
   shapes, which the 5-year-old is learning)?
2. Should the Launcher's booster be a separate "launch button" object on
   screen, or a flame on the toddler's rider?
3. Which planets and space things do the kids know (Saturn, Mars, a UFO,
   a space whale)? The album should match their favourites.
4. Is a single 5-minute trip right, or should there be a shorter "just
   the launch" mode for the 2-year-old alone?
