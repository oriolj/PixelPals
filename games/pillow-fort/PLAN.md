# Pillow Fort Hide and Seek

A cosy bedtime pillow fort glowing with fairy lights: dad moves a warm
flashlight, the 5-year-old lifts pillows and blankets to find the hidden
toys, and the 2-year-old makes friends pop out and say "peekaboo".

Status: plan (2026-09-26)

## Why it fits our family

- **2-year-old**: peekaboo is exactly their stage: hide, wait, reveal,
  giggle. Any button makes a friend pop out from behind the nearest pillow,
  slowly and smiling, always because THEY pressed, so it is a game they
  control, never a surprise done to them.
- **5-year-old**: a search they lead. They hop a pointer between hiding
  spots with 4 directions and lift the one they choose; toys found jump into
  the toy basket. Hints come from the light: toys peek out a little when lit.
- **Adult**: sweeps the flashlight, and sets the mood (slow, calm).

## It must not be scary

Hard rules, checked in every milestone:

- The "dark" is a **warm dusk**, never black: a plum/indigo overlay at most
  60% strength, with a nightlight and fairy lights always glowing. The room
  is fully readable even outside the flashlight.
- **No jump scares**: nothing appears, moves fast or makes a loud sound
  unless a player pressed a button. Pop-outs ease in over 0.4 s with a soft
  "peekaboo" chime, capped volume.
- Every character is a soft toy or a smiling friend (teddy, bunny, duck,
  sleepy cat); nothing with teeth, glowing eyes in the dark, shadows that
  move by themselves, or monsters "under the bed".
- The music is a lullaby-tempo loop; no drones, no minor-key stings.
- The round ends with the lamp turning on softly, not with a flash.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | Flashlight (adult) | left stick moves the light (analog, smoothed); "a" = lift the spot under the light when seat 2 is empty; start = pause | kb:0 WASD moves, Shift lifts, Esc pauses |
| 2 | Seeker (5-year-old) | 4 directions hop the paw pointer to the next hiding spot in that direction; "a" lifts the pillow/blanket/box lid | kb:1 arrows hop, Enter lifts |
| 3 | Peekaboo (2-year-old) | any button: a friend pops out near the flashlight and says peekaboo (1 s cooldown; extra presses make fairy lights twinkle) | kb:2 Space or any other key |

- **1 seat**: holding the flashlight on a hiding spot for 1.5 s lifts it by
  itself (the "dwell" reveal); "a" lifts instantly.
- **2 seats**: no peekaboo seat; a friend peeks out on its own every ~25 s,
  slowly and only inside the flashlight.
- **3 seats**: as the table. Keyboard-only on one keyboard works.
- The paw pointer is the seeker's yellow; the light itself stays warm white
  with a thin blue rim for the adult; peekaboo sparkles are green.

## Core loop

1. One bedroom screen: a pillow fort in the middle, a bed, a toy shelf, a
   laundry basket, a window with the moon, about 14 hiding spots (pillows,
   blanket folds, boxes, under the bed, behind the curtain).
2. Eight toys are hidden in random spots each round. A hidden toy shows a
   tiny tip (an ear, a tail) only while the flashlight is on its spot, and
   its spot wiggles gently.
3. The seeker hops the paw to a spot and lifts it. A toy: it hops out with a
   happy sound and flies into the toy basket, which fills up. Empty: there
   is still something small and sweet (a sock, a sleepy mouse who waves, a
   cookie).
4. The peekaboo friend pops out anywhere near the light, covers its eyes,
   then "peekaboo!", then ducks back. If it pops out from a spot that hides
   a toy, the toy peeks out too (a free hint the toddler gave).
5. When all eight toys are found (or at 6 minutes), the lamp fades on over
   2 s, every toy does a little dance, and it goes to the party.

**No-fail rules**

- Lifting an empty spot is never a miss: there is always a small surprise.
- No timer shown, no limit on lifts, nothing gets lost again.
- After 45 s without a find, the nearest toy's spot starts glowing softly,
  lit or not.
- At 6 minutes the remaining toys walk out on their own and wave.
- A round lasts about 5 minutes.

## Screens and flow

`join` → `select` → `fort` → `party` → `select`, as PixelPals.

- **join / select**: reused; select picks pyjama colours and a rider per seat
  (the riders sit in the fort as the seekers' avatars).
- **fort**: the level, one fixed screen.
- **party**: lights on, the eight toys and the riders have a pillow-fort
  party with confetti, then everyone yawns and the lamp dims (a bedtime
  ending).

## Art direction

- **Pixel art**, 320x180, 16 px tiles, integer scaling, Sweetie 16 palette.
  Why: the palette is soft and warm, our grid pipeline and lint already
  work, and a pixel light mask with dithered edges looks cosy (think
  old storybook games) where a smooth vector gradient would look clinical.
- The light is a **shader over the whole screen**: darkness colour
  `#29366f` blended toward `#5d275d` at 55-60% strength, a flashlight
  circle (radius 36 px) with a 2-band ordered-dither (Bayer 4x4) edge,
  snapped to whole pixels so it stays pixel-perfect, plus small permanent
  light pools for the nightlight, the window moon and each fairy light.
  Light colour tints warm `#ffcd75`.

Assets (text grids in `art_src/`, rendered and linted by `tools/sprites.py`):

| name | size | frames | how |
|---|---|---|---|
| room_bg | 320x180 | 1 | generator script (walls, floor boards, window) writing a grid, then renderer |
| fort | 96x64 | 2 | grid; frame 1 = fairy lights twinkle |
| pillow_a, pillow_b, blanket_fold, box, curtain, bed_edge | 16x16 to 32x24 | 3 | grid: rest, wiggle, lifted |
| teddy, bunny, duck, ball, blocks, dino, car, doll | 16x16 | 2 | grid: idle, happy hop |
| toy tips (ear, tail, wheel...) | 8x8 | 1 | cut from the toy grids by a generator |
| peekaboo friends: teddy_big, bunny_big, sleepy_cat | 24x24 | 4 | grid: hidden, eyes covered, peekaboo, duck back |
| sock, sleepy_mouse, cookie | 8x8 to 16x16 | 2 | grid |
| paw_pointer | 16x16 | 2 | grid, tinted by seat colour |
| toy_basket | 32x24 | 3 | grid: empty, half, full |
| lamp | 16x32 | 2 | grid: off, on |
| sparkle, heart, confetti, icons | as PixelPals | | copied or reused |
| light mask | shader | | `fort_light.gdshader`, uniforms for up to 8 light positions and radii |

## Audio

Synthesized by our synth, all soft (SFX at -18 LUFS instead of -15, no
sharp attacks): `peekaboo_1..3` (a rising two-note chime plus a formant
"boo"), `giggle`, `lift` (fabric swish noise), `toy_found` (music-box arp),
`basket_plop`, `mouse_squeak`, `twinkle_1..3`, `hint_glow` (soft pad),
`lamp_on` (warm swell), `join`, `select`, `ready`, `party`, `yawn`.
Music: `music_menu`, `music_fort` (music-box lullaby, 72 BPM, C major,
pentatonic melody) and `music_party` (the same theme, brighter).

## Reuse

- **shared/**: `players.gd`, `art.gd`, `sfx.gd`, `tools/shots.py`.
- **From PixelPals**: `game_state.gd`, join/select/party screens,
  `demo_driver.gd`, `tools/sprites.py`, `tools/sfx.py`, the Makefile, and
  the icons/confetti/riders art.
- **Extract to shared first** (unless an earlier game did): `sprites.py` →
  `shared/tools/`, the synth core → `shared/tools/synth.py`, the menu screens
  → `shared/godot/screens/`, seat aliases `ADULT/KID/TODDLER`.
- **New and shareable**: the light-mask shader plus its GDScript mirror
  (`light_mask.gd`), which Submarine Safari (idea 4) would reuse for the sub
  lights in the deep.

## New tech this game needs

- **Flashlight light mask**: a `ColorRect` covering the screen with a
  `canvas_item` shader that outputs the darkness colour with
  alpha = strength x (1 - light), so it needs no screen read at all;
  light positions and radii as a uniform array, `floor()` on coordinates for pixel snapping, Bayer
  dithering on the edge band. A pure GDScript mirror `light_amount(pos)`
  implements the same maths so gameplay (which spots are lit) and tests do
  not depend on the GPU.
- **Spot graph** for the seeker: each hiding spot links to its nearest
  neighbour in each of the 4 directions (precomputed from positions), so
  the paw never gets stuck and every spot is reachable.
- **Peekaboo director**: picks the pop-out spot nearest the light that is
  not already busy, runs the 4-step animation, enforces the cooldown.
- **Risks for Claude-built Godot**:
  - Godot 3 drift: `SCREEN_TEXTURE` and `hint_color` are Godot 3 shader
    syntax (4.x: `hint_screen_texture`, `source_color`); `Light2D` and
    `CanvasModulate` behave differently in 4.x, which is one reason to use
    our own shader instead.
  - `.tscn` breakage: the shader is a `.gdshader` text file loaded in code;
    no material `.tres` files written by hand.
  - Headless renders nothing: the light only exists in `make shot` frames
    under xvfb; gameplay uses the GDScript mirror, which IS tested headless.
    A test compares the mirror against a few pixels read back from a
    captured frame (run in the shot target, not in GUT).
  - Shader precision on old GPUs: keep it simple (no loops over more than 8
    lights).

## MVP scope

One bedroom, 14 hiding spots, 8 toys, 3 peekaboo friends, about 5 minutes.

**M1 grey box**
- [ ] Scaffold (Makefile with start, demo, test, shot, shots, sprites, sfx,
      tmux trio; `project.godot` pixel-perfect).
- [ ] Spots as rectangles, toys as coloured squares, the light mask shader
      with plain edges, the paw as a yellow square.
- [ ] Spot graph, lift, basket counter, peekaboo director, dwell reveal,
      45 s hint, end at 8 toys or 6 minutes; 1-, 2-, 3-seat play.
- [ ] Couch test at bedtime light levels: is anything scary? can the
      2-year-old tell that their press caused the pop-out?

**M2 art and audio**
- [ ] Room generator, fort, spots, toys, friends as grids, lint clean,
      contact sheet reviewed at 8x.
- [ ] Dithered light edge, fairy light pools, the lamp-on ending.
- [ ] Soft SFX and lullaby loops synthesized and measured at the lower
      target.

**M3 polish and couch test**
- [ ] Toy-tip peeking tuned so the 5-year-old spots them without the glow.
- [ ] Friends' pop-out timing tuned with the 2-year-old watching.
- [ ] Couch session; lessons into the skill's field notes.

## Tests and verification

GUT:
- `test_light_amount_is_full_at_the_centre_and_zero_outside`
- `test_light_mirror_snaps_to_whole_pixels`
- `test_every_spot_is_reachable_through_the_spot_graph`
- `test_dir4_hop_moves_to_the_nearest_spot_in_that_direction`
- `test_lifting_an_empty_spot_always_gives_a_small_surprise`
- `test_found_toy_goes_to_the_basket_and_never_hides_again`
- `test_peekaboo_happens_only_after_a_press_when_seat_three_is_seated`
- `test_peekaboo_cooldown_still_twinkles_on_every_press`
- `test_dwell_reveal_lifts_after_one_and_a_half_seconds_solo`
- `test_hint_glow_starts_after_forty_five_seconds_without_a_find`
- `test_round_ends_at_eight_toys_or_six_minutes`
- `test_darkness_strength_never_exceeds_sixty_percent`
- `test_no_label_nodes_in_the_fort_screen`

Demo driver (`make shot SHOT_SCREEN=fort`): the flashlight sweeps a scripted
path over four spots; the seeker hops right twice and lifts (one empty spot
with the mouse, then a toy); the peekaboo seat presses at 3 s, 7 s and 12 s;
demo places two toys on the sweep path. `DEMO_RUN_SECONDS := 20`.

In the frames (upscaled): the room is readable outside the light, the
darkness is purple-blue not black, the light edge is a crisp 2-band dither
aligned to the pixel grid, the paw is yellow and on a spot, the peekaboo
sequence shows eyes covered then open across frames, the basket sprite
fills, the final frames show the lamp warming the room. Look specifically
for anything that could read as scary (eyes glowing in the dark, dark
silhouettes) and fix it.

## Open questions for Oriol

- Which toys should hide (the kids' own favourites as generic versions, or
  fan characters in the private pack)?
- Is "bedtime" framing welcome (a game to play before sleep, calm ending),
  or should it be an afternoon fort with daylight through a window?
- Should the seeker move a character that walks around the fort instead of
  a hopping pointer (more fun, harder to steer)?
- Softer SFX target (-18 LUFS) OK, or match the other games?
