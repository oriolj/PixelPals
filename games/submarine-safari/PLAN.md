# Submarine Safari

A little yellow submarine explores a dark, glowing reef: dad steers, the
5-year-old takes photos of every creature for the family album, the 2-year-old
flashes the sub's lights and makes the sea dance.

Status: plan (2026-09-26)

## Why it fits our family

- **5-year-old (Camera):** collecting without any shooting. A viewfinder
  sits on the side of the sub they point at; a press snaps a photo with a
  flash, and the creature's card flies into the album strip at the bottom.
  Twelve species start as dark silhouettes; filling the album is a goal that
  carries over between sessions ("we still need the octopus!").
- **2-year-old (Lights):** any press makes the sub's lights flash in a new
  colour; nearby fish glow, jellyfish pulse, and the shy ones come out to
  dance. Some creatures only appear when the lights are on, so the toddler's
  press is what makes the rare photos possible.
- **Adult (Pilot):** free steering in a small cave-and-reef world, finding
  where creatures hide and holding the sub steady for a good shot.

## Roles and controls

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 `Seat.DRIVER` | Pilot (adult) | left stick: swim in 8 directions (with inertia); A: sonar ping (reveals hiding spots on screen as rings); start: pause | kb:0: WASD swim, Shift sonar, Esc pause |
| 2 `Seat.GUNNER` | Camera (5 y) | stick or d-pad: point the viewfinder up/right/down/left; A: snap | kb:1: arrows point, Enter snap |
| 3 `Seat.HONKER` | Lights (2 y) | any button | kb:2: Space or any unowned key |

- **1 seat:** the camera auto-snaps a new species when it sits inside the
  viewfinder for 1 s; lights flash by themselves every 8 s.
- **2 seats:** lights flash on their own every 8 s and whenever a shy
  creature is within 3 tiles, so every species stays catchable.

## Core loop

1. The world is 4x2 screens of reef, caves and a shipwreck; the camera
   follows the sub. Creatures have homes and simple behaviours:
   - **Easy (free swimmers):** clownfish, blue tang, pufferfish, turtle,
     seahorse.
   - **Hiders:** crab (under rocks), octopus (in the wreck), eel (in a
     hole) come out after a sonar ping or a light flash nearby.
   - **Light-lovers (dark zone only):** jellyfish, anglerfish, glowing
     squid, lantern fish appear only while the lights are flashing.
   - **Big friend:** a whale that passes once per run near the surface (the
     "big moment"; a photo of it fills a double page).
2. The kid points the viewfinder (a rounded frame 48x40 px beside the sub).
   Aim assist: if any creature is within 24 px of the frame, the frame
   slides to centre it.
3. Snap: white flash, shutter sound, a polaroid pops up and flies to the
   album strip. A new species fills its silhouette slot with colour and a
   chime; a repeat photo gives a star.
4. Toddler lights: colour cycle (warm white, pink, green, blue), a ring of
   glow, fish within 3 tiles glow and wiggle; after 3 quick presses a "disco"
   burst makes every fish on screen spin.

### No-fail rules

- **Empty photo:** there is always something: a snap with no creature
  photographs a bubble, a shell or a smiling rock, which go to a "bonus"
  row of the album. The kid is never told "missed".
- **Blurry/fleeing fish:** does not exist. A creature inside the frame is
  photographed, whatever its motion.
- **Bumping rocks:** the sub boings, spins once and bubbles; nothing is lost.
- **No oxygen, no depth limit, no enemies.** The anglerfish and eel are
  drawn cute (big eyes, smiles), never jump at the sub, and the eel only peeks.
- **Getting lost:** a gentle current nudges the sub back when it leaves the
  4x2 area; a glowing pearl trail leads to the nearest unphotographed
  species after 40 s without a new photo.
- **End of run:** at 6 minutes, or when all 12 species of the album page
  are found, bubbles rise, the sub surfaces into a sunset, and the party
  shows this session's photos. Target session: 5-7 minutes.
- **Persistence:** the album is saved in `user://album.json` (species found,
  best photo per species), never anything personal. A parent-only combo on
  the join screen (hold start + B for 3 s) resets it.

## Screens and flow

`join` → `select` → `level` → `album` → `select`.

- **join / select:** shared screens; seat icons are the helm wheel, a camera
  and a light bulb. Riders appear in round portholes of the sub.
- **level:** the reef, with the album strip (12 slots) as a thin HUD bar.
- **album** (the party screen for this game): a two-page book; today's new
  species slide in one by one with their chime, then stars for repeats,
  confetti bubbles. The driver's A turns back to select. This screen is also
  reachable from the join screen with the gunner's B, to browse the album.

## Art direction

**Pixel art, dark underwater with 2D lighting.** Pixel keeps the reuse of
our sprite pipeline (and it is the style the fish album cards look best in:
small, iconic, collectible), while Godot 2D lights make it distinct from
PixelPals: a dark sea where the sub's headlights and the toddler's colours
paint the scene.

- **Canvas:** 320x180, integer scaled, nearest, pixel snap on, like PixelPals.
- **Palette:** Endesga 32 (more blues and glow colours than Sweetie 16):
  deep water `#0e0f19`/`#181425`/`#262b44`, mid `#3a4466`/`#124e89`,
  shallows `#0099db`/`#2ce8f5`, sub yellow `#feae34`, coral `#e43b44`/
  `#f77622`, glow `#63c74d`/`#b55088`/`#fee761`.
- **Lighting:** `CanvasModulate` darkens by depth (lighter near the surface,
  near black in the dark zone); the sub carries a `PointLight2D` headlight
  cone and a round glow light that the toddler recolours. Light textures are
  generated in code (`GradientTexture2D`) with a banding shader (4 steps,
  ordered dither) so lights stay pixel-true instead of smooth gradients.
- **How it is made:** sprites as palette-indexed text grids rendered by
  `sprites.py` (moved to shared) and linted; the reef background by a seeded
  generator script (rock silhouettes, kelp columns) writing grid files that
  go through the same renderer; bubbles and caustics procedurally.

Asset list (w x h, frames):

| Asset | Size | Frames | Notes |
|---|---|---|---|
| sub (yellow, 3 portholes, propeller) | 40x24 | 4 | propeller spin; faces right, flipped horizontally |
| viewfinder frame | 48x40 | 2 | corners only; frame 1 = locked-on |
| flash | 64x64 | 3 | white burst, drawn additive |
| clownfish, blue tang, pufferfish (+ puffed), seahorse, lantern fish | 16x16 | 2-4 | idle swim |
| turtle, octopus, eel (peek), crab, squid, anglerfish | 24x24 | 2-4 | behaviour poses |
| jellyfish | 16x24 | 4 | pulse |
| whale | 128x48 | 2 | the big moment |
| bonus: bubble, shell, smiling rock, starfish | 8x8-16x16 | 1-2 | empty-photo subjects |
| album slot + silhouette | 20x20 | 1 | silhouettes generated from each sprite (solid fill) |
| polaroid card | 24x28 | 1 | sprite inset drawn in code |
| reef tiles (rock, sand, coral, kelp) | 16x16 | 1-2 | tiles, generator-made |
| wreck | 96x48 | 1 | background prop |
| pearl (trail) | 6x6 | 4 | |
| bubbles, caustic streaks | 2-6 px | procedural | `_draw` + CPUParticles2D |
| seat icons (wheel, camera, bulb), trophy, confetti | 16x16 | 1-6 | reuse where possible |

## Audio

Synthesized by the shared synth:

- `sub_hum_loop` (low sine + slow LFO), `propeller` blips on speed changes.
- `sonar`: classic ping (sine with long decay and a soft echo).
- `shutter`: click + noise; `new_species_1..12`: each species gets its own
  4-note motif on a marimba-like pluck, so the album page "plays" at the
  party; `repeat_star`.
- `lights_1..4`: soft rising glass tones, one per colour; `disco`: sparkly
  arpeggio.
- `bubble_1..3`, `boing` (rock bump), `whale_song` (slow sine glides),
  `eel_peek`, `puff` (pufferfish), `surface` (splash + seagull-ish chirp).
- Music: `music_reef` (slow 80 bpm, pads + plucked bass, calm, with a filter
  opening as you go deeper), `music_album` for the book screen.

## Reuse

- **From shared/:** `players.gd`, `art.gd` (all sprites, unchanged contract),
  `sfx.gd`, `shots.py`.
- **From PixelPals:** `sprites.py` pipeline and lint, the aim-assist idea
  (`scripts/level/aim.gd`, adapted to snap the viewfinder), the demo driver,
  join/select screens, the synth; the party screen becomes the album screen.
- **Extract into shared/ because of this game:** `sprites.py` to
  `shared/tools/` with a `--palette` argument (Endesga 32 support) and a
  `--silhouette` output; a small `shared/godot/save.gd` (versioned JSON in
  `user://`, safe on corrupt files) that later games (Paint Party) will need.

## New tech this game needs

- **2D lighting in pixel art** (CanvasModulate, PointLight2D, banding shader)
  and checking that it survives integer scaling.
- **Free-roaming camera** in a bounded world (Camera2D limits, smoothing
  with pixel snap, which can jitter: snap the camera, not only sprites).
- **Creature AI:** small state machines (wander, hide, peek, attracted to
  light, flee-lite) in a node-free `creatures.gd` for testability.
- **Persistence** of the album between runs.
- **Risks for Claude-built Godot:** Godot 3 drift (`Light2D` was split into
  `PointLight2D`/`DirectionalLight2D`, `Light2D.mode` is gone, `yield`,
  `rand_range` is now `randf_range`); lights in `gl_compatibility` have limits
  (max lights per item; test the dark zone with 10+ glowing fish); `.tscn`
  edits (build in code); headless renders nothing and 2D lights only show in
  xvfb captures, so the lighting can only be verified from frames.

## MVP scope

One reef (4x2 screens: shallows, reef, wreck, dark trench), 12 species, the
whale pass, album persistence. About 5-6 minutes.

### M1 grey-box

- [ ] Shared `sprites.py` with palettes, `save.gd`, screens extracted.
- [ ] Sub movement with inertia, bumps, current at the edges.
- [ ] Viewfinder aim + assist + snap; album data model and strip with coloured squares.
- [ ] Creature behaviours as coloured squares (hiders, light-lovers, whale).
- [ ] Lights with any press; auto modes for fewer seats; pearl trail.
- [ ] Run end, album screen, persistence and parent reset.
- [ ] Demo driver finds at least 8 species in 60 s; couch test in grey.

### M2 art/audio

- [ ] All sprite grids, silhouettes, reef generator; lint and contact sheet.
- [ ] Lighting with banding shader; depth-based darkness.
- [ ] 12 species motifs and all SFX; music with depth filter.

### M3 polish/couch test

- [ ] Every flash and snap answered within 2 frames; no creature scary at 1x.
- [ ] The dark zone is dark but readable on the TV; tune CanvasModulate.
- [ ] Three couch sessions across days to see the album motivate return.
- [ ] Export and clean-clone run (album saved outside the repo).

## Tests and verification

GUT tests:

- `test_snap_with_creature_in_frame_records_species`
- `test_empty_snap_records_a_bonus_subject_never_nothing`
- `test_viewfinder_assist_snaps_to_creature_within_24px`
- `test_light_lovers_appear_only_while_lights_are_on`
- `test_hiders_come_out_after_sonar_or_nearby_flash`
- `test_rock_bump_never_loses_photos`
- `test_current_returns_sub_inside_world_bounds`
- `test_lights_any_button_only_lights_seat_with_cooldown`
- `test_one_seat_auto_snap_after_one_second_in_frame`
- `test_album_saves_and_loads_and_survives_corrupt_file`
- `test_parent_reset_combo_clears_album`
- `test_run_ends_at_six_minutes_or_full_page`

Demo driver (`--demo=level`): the pilot follows a waypoint loop through the
four zones, pausing 2 s at each creature home; the camera seat points `dir4`
toward the nearest unphotographed creature and presses A when it is in frame;
the lights seat presses every 2 s in the trench. Start with an empty album
(`--album=reset` user arg, demo only). `make shot SHOT_SCREEN=level
SHOT_SECONDS=60` and `make shot SHOT_SCREEN=album`.

In the frames, look at: lights are banded, not smooth (crop and upscale 8x);
the sub reads against dark water; creatures readable in the trench only when
lit; the album strip fills over time; the flash never whites out more than
3 frames (TV comfort); silhouettes match their sprites.

## Open questions for Oriol

1. Pixel art with lighting (plan), or a smooth vector sea like the other two
   2D games?
2. Keep the album between sessions (plan), and one album per family or per
   kid?
3. Real species (clownfish, turtle...) so it doubles as learning, or made-up
   fantasy creatures? A mix?
4. Is a dark trench OK for the 2-year-old, or keep everything bright?
5. Should printing the album page (a PNG for the fridge) come in M3?
