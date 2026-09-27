# Space Mission

Fly the Space Shuttle to build the ISS in Earth orbit, land on Mars with a
sky crane, then drive a rover across the red planet: one crew, three jobs.

Status: playable (2026-09-27)

## Why it fits our family

- **The 5-year-old** runs the "robot arm" in every stage: the Shuttle's
  arm catches cargo and fits it onto the ISS, and on Mars the rover's arm
  drills rock samples. It is 4 directions plus one grab button, with a
  magnetic assist, so every grab succeeds within a second or two. They see
  the station grow module by module because of them.
- **The 2-year-old** has the camera and the fun buttons. In orbit, any
  press takes a photo of Earth (a flash, then the photo drops into an album)
  and makes the ISS lights blink. At the big moments, a press fires the
  parachute or launches the little Mars helicopter. It never hurts the run,
  and if nobody presses, the moment happens on its own after a few seconds.
- **The adult** does the flying and driving: RCS thrusters in orbit, the
  sky crane descent, the rover over the dunes.
- **Real space, gently.** No text, but true things shown on screen:
  - The ISS circles Earth fast, so sunrises come every ~20 seconds of play
    (really every 90 minutes).
  - Mars is red, and its sunsets are blue.
  - The rover's photos travel home and appear on a screen on Earth at the
    end.

**How it differs from Rocket to the Moon.** Rocket is a fast arcade
launch-and-collect run. Space Mission is a slower "real hardware" mission:
building, docking, landing and exploring, in two worlds.

## Roles and controls

Seats fill in join order. The 5-year-old's seat needs directions (kb:0,
kb:1 or a pad); kb:2 has none.

| Seat | Role | Pad | Keyboard |
|---|---|---|---|
| 1 | **Pilot / Driver** (adult): flies the Shuttle, steers the sky crane, drives the rover | left stick / d-pad moves, A = boost (orbit) or brake (rover), Start pauses, B = back (pause only) | kb:0: WASD, Shift = boost/brake, Esc pauses, Q back (pause only) |
| 2 | **Arm operator** (5-year-old): moves the arm tip in 4 directions, grabs and releases, chooses the landing site | d-pad / stick (4-way), A = grab/release | kb:1: arrows, Enter = grab/release |
| 3 | **Camera and buttons** (2-year-old): photo flash, ISS lights, parachute, helicopter | any button | kb:2: Space or any unowned key |

With fewer seats:
- **1 seat:** the arm auto-grabs the nearest cargo when the Shuttle is
  close, the adult's A fires the camera, and big moments trigger on
  their own.
- **2 seats:** the Pilot's B, outside pause, takes photos.

## Stages and core loop

A mission is 3 stages and about 9 minutes. On the select screen you can
start at any stage by picking a planet icon: Earth, the Mars landing, or
the Mars surface.

### Stage 1: Earth orbit (about 4 minutes), "build the station"

- **The scene:** a big rotating Earth fills the lower third, with day and
  night sweeping across it and city lights on the night side. A starfield
  sits behind, and the ISS is on the right, growing.
- **Pilot:** flies the Shuttle in smooth, damped 2D space motion. There is
  no gravity, and it stabilizes itself when idle. A floating cargo module
  (coloured: lab, solar panel, habitat, robot) drifts in from the left.
- **Arm operator:** moves the Canadarm tip in 4 directions, and A grabs.
  The assist snaps to cargo within 12 px. The station shows a glowing port
  in the matching colour and shape; the arm operator brings the module
  there, where it clicks in with a "clunk" and sparkle. The ISS visibly
  gains that module and its solar wings unfold.
- **Camera:** any press gives a flash, a photo of the current view (a
  snapshot of what is on screen, scaled into a Polaroid) and blinking ISS
  lights. Now and then, "Earth moments" drift by (a hurricane swirl, the
  aurora, a sunrise line). A photo taken during one is golden in the
  album.
- **Big moment, docking:** after 5 modules the Shuttle docks. The Pilot
  aligns it with the dock ring (a strong assist, so it is always done
  within a few seconds). Then the astronauts (the chosen riders in
  helmets) float out and do zero-g flips while the toddler's presses
  make them wave.
- **Sunrises:** one every ~20 s, as a golden line across Earth with a soft
  chime. It is a counting game for the 5-year-old.

### Stage 2: Mars landing (about 1 minute), "seven minutes of fun"

(As built: about 20-30 s, a 3 s entry plus the three beats.)

This is a vertical descent in three beats, each a job for one seat. It
cannot fail: every beat auto-completes after 5 s.

1. **Parachute (2-year-old):** any press pops the big parachute.
2. **Landing site (5-year-old):** chooses one of 4 glowing spots with
   the arrows. All of them are safe, each with a different flavour: dunes,
   crater, ice or rocks.
3. **Sky crane (adult):** the rocket platform lowers the rover on cables.
   Holding down lowers it, and a soft touchdown gives a dust puff. The crane
   flies away to the side with a little wave.

### Stage 3: Mars surface (about 4 minutes), "explore"

- **The scene:** side-scrolling Mars (butterscotch sky, red dunes, rocks,
  far mountains in parallax) on a gentle generated terrain. The rover
  cannot flip; its wheels follow the ground with springs.
- **Driver:** drives left and right, and A brakes. Nothing hurts the
  rover: bumps just wobble it.
- **Arm operator:** science targets appear, coloured rocks with a
  sparkle. The arm operator picks the target direction, and A drills, with
  a rumble and a sample capsule popping into the rover's tray (colour =
  rock type). There are hidden fossils-that-are-just-pretty-shells and
  water ice (blue) as rare finds.
- **Camera / helicopter (2-year-old):** any press launches the little
  helicopter. It buzzes up, circles, and reveals the next target with a
  spotlight, then lands back on the rover (a 3 s cooldown). While it flies,
  more presses make it do loops.
- **Big moment, sunset:** at the end the sky shifts to the real Mars
  sunset, which is BLUE around the sun. The rover "phones home": a beam to
  a tiny Earth dot. Then comes the party.

### No-fail rules

- No damage, lives or timers that can run out. A missed cargo drifts back
  in a loop, and a missed drill just tries again.
- Every beat that needs a specific seat auto-completes after 5 s, so a
  missing or distracted child never blocks the mission.
- Collisions in orbit are a soft "boing" plus a small push-back.

### Party screen: Mission Control

A mission-control room with a big screen that plays the mission's
highlights: the toddler's Earth photos, the finished ISS silhouette and the
rock samples in a tray. A mission patch is made from the three chosen
riders in helmets. Confetti, and the "party" fanfare.

## Screens and flow

join → select → stage 1 → stage 2 → stage 3 → party → select, all copied
from PixelPals and adapted.
- **join:** role icons: a Shuttle for the pilot, the arm for the operator,
  a camera for the toddler.
- **select:**
  - The riders appear in space helmets: penguin, monkey, fox, frog, robot,
    plus the private pack (Sonic, Mario and the rest, local only, gitignored).
  - A second row has 3 planet icons for the starting stage (default:
    stage 1).
- **pause:** as in PixelPals, driven by the Pilot only.

## Art direction

Pixel art at 320x180, integer scaled, using the **Endesga 32** palette.
Sweetie 16 has no browns or oranges for Mars and too few blues for Earth.
Everything uses the PixelPals pipeline: text grids and Python generators go
through `tools/sprites.py` (copied), are linted and put on a contact sheet.

| Asset | Size | Frames | How it is made |
|---|---|---|---|
| shuttle | 48x20 | 2 (engine glow) | grid, outline |
| iss_core, iss_lab, iss_solar, iss_habitat, iss_robot | 16x16 – 32x16 | 1-2 | grids; solar wings get an unfold animation (4 frames) |
| iss_port | 16x16 | 2 | glowing outline per module colour (code-tinted) |
| cargo_* | 16x16 | 2 | same shapes as the modules, with a floating bob |
| arm_segment, arm_hand | 24x4, 8x8 | 1, 2 (open/closed) | grids; a 2-segment IK in code |
| earth | 320x96 strip | 1 | generator: continents from noise, clouds as a second layer. It rotates by UV scroll inside a circle mask shader, with a day/night terminator and city lights |
| stars_far, stars_near | 320x180 | 1 | generator, parallax |
| aurora, hurricane, sunrise_line | 48x16 – 320x4 | 4 | generators |
| astronaut_<rider> | 16x16 | 2 | the rider grids plus a helmet overlay generator (bubble + visor), so every rider (private pack included) gets one automatically |
| lander_shell, parachute, sky_crane, cable | 32x32, 48x32, 32x16, 1x8 | 1-2 | grids |
| rover | 40x24 | 2 (wheel turn) | grid; wheels separate (8x8, 4 frames) |
| helicopter | 12x8 | 2 (rotor) | grid |
| mars_far, mars_mid | 320x60, 320x48 | 1 | generators (mountains, dunes) |
| mars_ground | 16x16 tiles | 1 | generator; the terrain surface is drawn with Polygon2D from a heightmap |
| rock_red, rock_grey, rock_white, ice, shell | 12x10 | 2 (sparkle) | grids |
| sample_capsule | 6x8 | 1 per colour | grid, recoloured |
| dust_puff, drill_sparks | 8x8 | 4 | generators |
| mission_control, big_screen, patch | 320x180, 160x90, 48x48 | 1 | generators and grids |
| icons: seat_pilot, seat_arm, seat_camera, planet_earth, planet_mars_landing, planet_mars | 16x16 | 1 | grids |

**Sky colours:**
- Mars day sky: `#e4a672` → `#b86f50`.
- Mars sunset: a blue halo (`#8fd3ff`) around a white sun on a brown sky.

This is a code-driven gradient, checked in frames against the palette.

## Audio (our synth, `tools/sfx.py`)

Space is silent, so in orbit everything is "radio" and inside-the-cabin
sounds. That is a nice detail and it keeps everything soft.

| Sounds |
|---|
| `quindar_in`, `quindar_out`: the real Apollo/NASA radio beeps (2525 Hz / 2475 Hz tones) at the start and end of each stage |
| `thruster` (soft puff), `arm_move` (servo whirr), `grab`, `clunk` (module docks), `solar_unfold` |
| `camera_1..3` (shutter plus flash whine), `sunrise_chime`, `photo_golden` |
| `parachute_pop`, `crane_lower`, `touchdown` (dust whump), `crane_bye` |
| `rover_hum` (loop), `drill` (rumble), `sample_pop`, `heli_buzz` (loop), `heli_loop` |
| `phone_home` (a rising beam), `party` (fanfare) |
| music: `music_orbit` (slow, spacey arpeggios), `music_mars` (plucky, curious), `music_menu` |

## Reuse

- **From shared/:** `players.gd`, `art.gd` and `sfx.gd` (symlinked),
  `shots.py`.
- **From PixelPals:**
  - the join/select/party screens and the demo-driver pattern;
  - `tools/sprites.py` (engine unchanged, new content) and `tools/sfx.py`;
  - the rider grids, for the helmet overlays;
  - `aim.gd`, for the arm's snap assist.
- **From Rocket to the Moon** (being built in parallel): the starfield
  generator and parallax, if it lands first.
- **Worth extracting to shared/ because of this game:** the helmet overlay
  generator (any rider → astronaut) and a 2-segment arm IK helper, which
  Digger Treasure could use as well.

## New tech

- **The Earth globe:** a circle mask shader over a horizontally scrolling
  texture, plus a terminator (day/night) and city-light layers. Keep it
  pixel-exact: the shader samples with nearest filtering, and the mask edge
  is a precomputed pixel circle. It is tested in frames.
- **2-segment IK** for the arm (analytic, two bones).
- **Damped space flight:** velocity with drag, plus auto-stabilisation.
- **Heightmap terrain with a spring-follow rover:** no RigidBody, so it is
  deterministic for tests.
- **A multi-stage flow in one run,** with a stage-select shortcut.
- **Photo capture:** `get_viewport().get_texture().get_image()` → a
  thumbnail stored in memory for the party screen. Photos are not saved to
  disk; that is an open question.
- **Risks:**
  - The shader must not blur (texture filter nearest, integer UV steps).
  - The viewport grab in headless runs returns empty, so tests call a
    fake capture.
  - Godot 3 drift and hand-edited `.tscn` files, as always; build in code.

## MVP and milestones

**MVP:** all 3 stages in grey-box, playable end to end in about 9 minutes
with 1–3 seats.

**M1: grey-box**
- [x] Skeleton copied from PixelPals: Makefile, project (320x180,
  Endesga 32 palette file), join/select/party, demo driver, symlinked
  shared autoloads. (Join/select came from Rocket to the Moon, the
  renderer and synth from Submarine Safari.)
- [x] Stage 1: shuttle flight, cargo spawn and loop, arm IK with snap
  grab, ports, 5 modules attach, docking assist. (Added: a magnet pulls the
  hand onto cargo within 20 px and a held module onto its port within 22 px;
  the Pilot's autopilot and the arm run themselves after 5 s idle.)
- [x] Stage 2: the parachute, site-pick and sky-crane beats, each with a
  5 s auto-complete (2 s when the beat's seat is empty).
- [x] Stage 3: heightmap terrain, spring rover, targets with a drill, the
  helicopter reveal, and the sunset end.
- [x] Stage select on the select screen (the Pilot's up/down on the
  planet row), and the solo and 2-seat fallbacks.

**M2: art and audio**
- [x] Every asset in the table, linted, on a contact sheet reviewed at 8x
  (`art_src/contact_sheet*.png`, `astronaut_sheet.png`). Deviations: `earth`
  is three 768x96 strips (`earth`, `earth_night`, `earth_clouds`) so the
  globe is never magnified; astronauts are 24x24 so every rider fits the
  bubble. Additions: `dock_ring`, `drill`, `wheel`, `site_*`, `sample_*` per
  colour, `sparkle`, `sun_icon`, `confetti`.
- [x] The Earth shader with day/night and city lights, and Mars skies with
  the blue sunset. Both shaders output palette colours only (ordered
  dither). Deviation: `#8fd3ff` is not in Endesga 32, so the halo is
  `#2ce8f5` inside and `#0099db` outside; the sunset sky is `#733e39` to
  `#b86f50`.
- [x] Every sound in the audio table, measured (peaks and loudness) like
  PixelPals (`make sfx` prints the table). Additions: `boing`, `wave`,
  `dock`, `join`, `select`, `ready`, `whoosh`. The Quindar tones are
  trimmed 3 dB under the other SFX on purpose.
- [x] Helmeted astronauts for every rider, private pack included (derived
  by `tools/sprites.py`, with a lint that fails if the glass cuts a rider).

**M3: polish and couch test**
- [x] Earth moments and golden photos, the album on the party screen.
- [x] The Mission Control party with highlights and the patch.
- [x] Sunrise counting chime, Quindar beeps, the "phone home" beam.
- [x] Couch test with the kids: tune the assists and each beat's
  auto-complete timing. (Prepared, not done: every assist and timing is a
  named constant (`AUTO`, `SNAP_R`, `MAGNET_R`, `DRILL_RANGE`...), and the
  real playtest needs Oriol and the kids.)

## Tests and verification

**GUT tests:**
- `test_arm_ik_reaches_every_point_in_range`
- `test_arm_snap_grabs_cargo_within_radius`
- `test_module_only_docks_in_matching_port`
- `test_missed_cargo_loops_back`
- `test_station_grows_after_each_module`
- `test_docking_assist_completes_within_5s`
- `test_every_landing_beat_autocompletes_without_input`
- `test_all_landing_sites_are_safe`
- `test_rover_never_flips_on_terrain`
- `test_drill_collects_sample_of_rock_colour`
- `test_helicopter_cooldown_and_reveal`
- `test_toddler_input_never_changes_mission_outcome`
- `test_stage_select_starts_at_chosen_stage`
- `test_one_seat_and_two_seat_fallbacks`
- `test_pause_only_by_pilot`
- `test_photo_capture_stores_thumbnail` (with a fake viewport)

All 16 are in `game/tests/` and pass (67 tests in all, with the menus,
the demo driver and the extra stage tests).

**Demo driver:** `--demo=orbit|landing|mars|party|join|select`. Scripted
seats fly toward the cargo, the arm tracks and grabs, the camera presses
every 2 s, the landing beats are pressed at 1 s, 2 s and 3 s, and the rover
drives right while the arm drills each target.

**What to look at in frames** (`make shots`, at 3x):
- the Earth circle is crisp and has no blur;
- the terminator moves;
- the ISS gains modules;
- the helmets sit right on every rider;
- the Mars sunset shows blue around the sun;
- no element is off-screen;
- nothing is dark or scary.

## Decisions taken (pending Oriol)

Taken as defaults on 2026-09-27 so the game could be built; each is easy to
change.

1. **The Space Shuttle**, as planned (no capsule option).
2. **Generic hardware**, no agency names or logos.
3. **Earth photos are kept in memory only** (the party shows them; nothing
   is written to disk).
4. **The landing stays its own mini-stage** (with its own start icon).
5. **No Moon stop**; the Moon stays Rocket to the Moon's.
6. **No text fact cards**; the true things are only shown (sunrise count,
   the blue sunset, the beam home).

## Proposed shared/ extractions

- The helmet overlay (any 16x16 rider -> a 24x24 astronaut, with the fit
  lint), now in `tools/sprites.py`, and the Sweetie 16 -> Endesga 32 remap
  overrides (the plain nearest colour turns blue into grey).
- `scripts/logic/arm_ik.gd` (analytic two-bone IK), for Digger Treasure.
- `scripts/view/tex.gd` (whole textures and Images from source bytes) and
  `scripts/view/loop_audio.gd` (looping players from source bytes): the
  shared `Art` returns SpriteFrames only and `Sfx` one-shots only.

## Open questions for Oriol (answered provisionally above)

1. **Shuttle or a modern capsule?** The Shuttle retired in 2011 but it is
   iconic. The alternative is a Dragon- or Orion-style capsule, or both, as
   selectable craft.
2. **Real names and logos?** The plan uses generic hardware (no agency
   logos); that could change, since it is private.
3. **Save the toddler's Earth photos** to `~/Pictures/SpaceMission/` for
   printing, the way Paint Party saves paintings?
4. **Stage 2 length:** keep the landing as its own mini-stage, or fold it
   into the start of stage 3?
5. **A Moon stop between Earth and Mars** (Artemis-style), or leave the
   Moon to Rocket to the Moon?
6. **Real facts on screen:** the plan shows them visually only (sunrise
   count, blue sunset). Should a grown-up "fact card" (text, optional,
   off by default) exist for the 5-year-old to have read aloud?
