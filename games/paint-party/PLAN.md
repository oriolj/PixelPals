# Paint Party

Paint one big picture together, with brush strokes, stamps and splats, and print it for the fridge.

Status: plan (2026-09-26)

## Why it fits our family

- **The 5-year-old** chooses every colour the big brush paints with and
  stamps shapes (stars, hearts, fish) onto the picture: real creative
  choices, and dad paints with *their* colour.
- **The 2-year-old** makes splats: any press throws a random paint
  explosion onto the canvas with a satisfying "splosh". Splats are part of
  the art, never a mess to clean.
- **The adult** moves the big brush with the stick, which is the fine
  control the kids cannot do yet.
- At the end there is a real object: a PNG the family prints and hangs.

## Roles and controls

Seats fill in join order; the keyboard column is the suggested block. The
Colourist needs directions, so not kb:2.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Brush** (adult): moves the big round brush, paints while held, changes brush size; undo lives in the pause menu | left stick / d-pad moves, A held paints, B cycles the size (3 sizes), Start = pause menu (undo, frame it, back) | kb:0: WASD moves, Shift or Tab paints, Q cycles the size, Esc pauses |
| 2 | **Colourist** (5-year-old): picks the colour from 4 pots, stamps at the brush | d-pad: each direction picks one pot; A stamps at the brush; B turns the palette page (3 pages of 4) | kb:1: arrows pick a pot, Enter stamps, Backspace turns the page |
| 3 | **Splatter** (2-year-old): a paint explosion in a random colour | any button | kb:2: Space or any unowned key |

Fewer seats:

- **1 seat:** the Brush also picks colours and stamps: B cycles the
  colour (the size stays medium), and a quick tap of A (under 0.2 s,
  without moving) stamps. No splats unless the adult's
  Start menu turns them on as "surprise splats" every 20 s.
- **2 seats:** Brush plus Colourist; the stamp cycles its shape per press.
- **Dad plus toddler:** see the open questions (seat 3 direct join).

## Core loop

1. A white sheet of paper on an easel fills the screen. The riders sit
   around it on the floor with paint pots.
2. The Brush paints strokes in the colour the Colourist picked; the brush
   cursor shows the current colour and size, and the chosen pot bounces.
3. The Colourist stamps: star, heart, flower, fish, sun, cat face, car,
   house, one after another, at the brush's spot.
4. The Splatter splats: a splat with drips lands on the least painted
   part of the canvas, so it fills gaps instead of covering drawings.
5. When the adult presses Start and picks the frame icon, the picture gets
   a gold frame, the riders clap, and the PNG is saved. Then the party
   screen hangs it in a little gallery.

### No-fail rules

- **Nothing on the canvas is a mistake.** The adult's undo (pause menu) covers
  the rare "oops"; the kids have no undo and do not need one.
- **Splats respect drawings:** the splat centre is the canvas cell (a 16x9
  grid) with the lowest paint coverage, jittered; its radius shrinks when
  the cell's neighbours are already painted, and it never covers more
  than 8 % of the canvas. Every 5th splat is a rainbow splat.
- **Toddler cooldown:** 0.5 s between splats; extra presses make the
  Splatter's rider jump and giggle.
- **No timer.** The adult decides when the picture is done; the game
  hints after 5 minutes by making the frame icon sparkle. Autosave every
  30 s means a crash or a pulled plug never loses the picture.
- Session: 3 to 8 minutes per picture.

## Screens and flow

`join` → `select` → `paint` → `party` → `select`, as in PixelPals.
`party` is the gallery: the new picture framed in the middle, the
previous two beside it, the riders dancing. Pause (Start) shows four
icons: undo (repeatable, last 10 actions), frame it (save), keep painting,
back to join (B).

## Art direction

**Flat vector UI around a real painted canvas.** Paint has to look like
paint (soft round dabs, smooth strokes, anti-aliased), and a printed
picture at fridge size needs far more than 320x180 pixels, so pixel art
does not fit.

- Screen 640x360, `canvas_items` stretch, MSAA 4x.
- **The painting is a separate 1920x1080 `SubViewport`** (A4 landscape at
  about 160 dpi), shown scaled into a 512x288 easel area. It never clears
  (`render_target_clear_mode = CLEAR_MODE_NEVER`), so each dab drawn into
  it accumulates: the standard Godot way to paint on the GPU.
- Palette: 12 paint colours, bright and print-friendly (Sweetie 16 minus
  the darks, plus pure `#ff5fa2` pink and `#8b5a2b` brown for dogs and
  trees), on `#fdfdf8` paper. UI: wood `#a0673c`, floor `#333c57`.

| Asset | Size (px) | How |
|---|---|---|
| brush dab | 8 / 24 / 64 diameter (canvas px) | a generated soft-edged radial `Image` (alpha falloff) tinted per colour, stamped along the stroke every 1/4 radius |
| stamps x8 | 96-160 on canvas | `Polygon2D` point lists from formulas (star = 10 points, heart = parametric curve, flower = 6 circles plus a centre) drawn into the SubViewport |
| splat | 120-260 on canvas | an irregular blob: a circle with 12-20 noise-offset radii, plus 3-6 drip polygons and droplets |
| easel, paint pots x4, palette page dots | 32-512 | polygons and circles in `_draw()` |
| brush cursor | size of the brush | ring in `_draw()` with the colour inside |
| gold frame | 544x320 | nested polygons with a bevel gradient shader |
| gallery wall | 640x360 | flat polygons |
| riders | 16x16 x2 frames | reused PixelPals PNGs at x2 |

## Audio

Our own synth script (`tools/sfx.py`, on the shared synth):
`brush_loop` (a soft filtered-noise swish, looped while painting, pitch
follows speed), `stamp_1`…`stamp_4` (a rubber "thunk" plus a bell),
`splat_1`…`splat_4` (wet noise burst plus a low pitch drop), `rainbow`
(an arpeggio up), `pot_pick_1`…`pot_pick_4` (one pentatonic note per pot),
`page_turn`, `undo` (a reverse whoosh), `frame_it` (a fanfare), `clap`,
`join`, `select`, `ready`, `party`. Music: `music_paint` (a gentle 80 BPM
loop, soft enough to talk over) and `music_menu` (reused).

## Reuse

- **From shared/:** `players.gd`, `art.gd` (riders), `sfx.gd`,
  `tools/shots.py`.
- **From PixelPals:** the demo driver pattern, join/select/party screens,
  the Makefile targets, the synth.
- **Extract into shared/ first:** `Players.dir4_just_pressed(seat)` (the
  pot picks; Garage Band needs it too), the shared screen router and
  screens, `shared/tools/synth.py`, and `shared/godot/vector.gd` (the
  polygon helpers Tower Topple and Garage Band also use).

## New tech this game needs

- **Painting into a never-clearing SubViewport**, with strokes as dabs
  interpolated between frames so fast moves leave no gaps.
- **Undo:** at the end of each action, `get_texture().get_image()` (a GPU
  readback, a few ms) is kept in a ring of 10 `Image`s (8 MB each, 80 MB
  max); undo draws the snapshot back as one full-size sprite.
- **Coverage map** for splat placement: a 16x9 array of painted
  fractions, updated from the dab positions (no readback needed).
- **Saving the PNG:** on "frame it" and every 30 s,
  `image.save_png()` to `user://paintings/paint-<UTC>.png`, and a copy on
  "frame it" to `~/Pictures/PaintParty/` (from
  `OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)`). The paintings are family
  material: never in the repo, gitignored if a path ever lands under it.
- **Risks for Claude-built Godot:** Godot 3 drift (`Viewport.get_texture()`
  flips and `render_target_update_mode` names changed in 4; there is no
  `VisualServer`, it is `RenderingServer`); `.tscn` breakage, so the
  SubViewport is built in code; headless runs use the dummy renderer, so
  **a headless readback returns no image**: every test that saves or
  inspects pixels must run under xvfb with a real renderer (a separate
  `make test-render` target), and the logic tests (coverage, placement,
  undo ring) run headless on plain data.

## MVP scope

One easel, 12 colours, 8 stamps, splats, undo, the frame-it save and a
gallery of the last three pictures; about 5 minutes per picture.

### M1 grey-box

- [ ] Skeleton (vector settings, Makefile with `test` and `test-render`,
  CLAUDE.md + AGENTS.md, shared autoload symlinks).
- [ ] SubViewport canvas, dab strokes, 4 colours, 3 sizes.
- [ ] Colour pots by direction, stamps as plain circles, splats as
  plain blobs, coverage-based placement.
- [ ] Undo ring, autosave, frame-it save to `user://`.
- [ ] Fold-down for 1 and 2 seats.
- [ ] Couch test: can the 5-year-old tell which pot is selected? Does
  the toddler enjoy splats that avoid drawings, or want them on top?

### M2 art and audio

- [ ] Soft brush texture, 8 stamp shapes, splats with drips, rainbow splat.
- [ ] Easel, pots, riders, gold frame, gallery wall.
- [ ] Every sound above; loudness report.

### M3 polish and couch test

- [ ] Print test: open a saved PNG and print it on the home printer;
  check colours on paper and the margins.
- [ ] The Pictures copy, gallery of the last three.
- [ ] Clean-clone run; tuning from couch notes.

## Tests and verification

GUT tests, headless (`game/tests/`):

- `test_dir4_just_pressed_picks_each_pot`
- `test_palette_page_cycles_three_pages`
- `test_splat_targets_the_least_covered_cell`
- `test_splat_never_exceeds_eight_percent`
- `test_splat_cooldown_ignores_fast_presses`
- `test_every_fifth_splat_is_rainbow`
- `test_stroke_interpolates_dabs_between_frames`
- `test_undo_ring_keeps_ten_and_drops_oldest`
- `test_kids_have_no_undo`
- `test_one_seat_tap_stamps_and_hold_paints`
- `test_one_seat_brush_picks_colours`
- `test_autosave_every_thirty_seconds`

Render tests, under xvfb (`make test-render`):

- `test_saved_png_is_1920x1080_and_not_blank`
- `test_undo_restores_the_previous_pixels`
- `test_stamp_lands_at_the_brush_position`

Demo driver ("paint"): the Brush draws a big wavy line, a circle (a sun)
and a house outline from scripted stick paths; the Colourist switches pots
every 3 s and stamps 6 times; the Splatter presses every 2.5 s; after 25 s
the Brush presses Start and frames the picture. The run saves the PNG to
`shots/paint/painting.png` as well as the frames.

Look at in the frames (`shots/paint/sheet.png`, 2x) and the saved PNG
(at 1x, 1920x1080): strokes continuous with no dotted gaps; splats in the
empty areas; stamps crisp; the selected pot obvious; the frame and
gallery render; the saved PNG matches the last frame's canvas.

## Open questions for Oriol

1. Print automatically on "frame it" through CUPS (`lp`), or only save
   and let you print? Which printer, and A4 landscape?
2. Should splats land on top of drawings sometimes, if the toddler finds
   "splat on dad's house" the funniest part?
3. Keep every painting in `~/Pictures/PaintParty/`, or also show all of
   them in an in-game gallery on the select screen?
4. Colouring-page outlines (a truck, a dinosaur) to paint inside, as an
   option for the 5-year-old later?
