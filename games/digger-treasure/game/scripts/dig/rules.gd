extends RefCounted
## Dig rules as constants and pure static functions (unit tested). No game
## over, ever: the run ends when every treasure is in the truck, and at the
## time limit the rest burst up by themselves.

const RUN_SECONDS := 300.0          # then the final fountain
const TREASURE_COUNT := 12
const BOOM_RADIUS := 7.0            # cells
const BOOM_COOLDOWN := 1.2
const AUTO_BOOM_EVERY := 20.0       # when nobody sits in seat 3
const BIG_SCOOP := 5                # cells, the scooper's bite
const SMALL_SCOOP := 3              # cells, the driver's bite
const SCOOP_COOLDOWN := 0.3
const FOUNTAIN_EVERY := 0.3         # seconds between treasures in the final fountain
const GLINT_REVEAL_CELLS := 12      # a treasure glints through this much dirt
const GLINT_NEAR_PX := 110.0        # ...or when the digger is this close
const GLINT_EVERY := 2.0
const CAMERA_LEAD_PX := 36.0


## Run length: Game.run_seconds when set (> 0), else five minutes.
static func run_length(override_seconds: float) -> float:
	return override_seconds if override_seconds > 0.0 else RUN_SECONDS


## A stick reading snapped to exactly one of the four directions, or `keep`
## when the stick is idle. The scooper's arm only ever points one of four ways.
static func snap4(v: Vector2, keep: Vector2i) -> Vector2i:
	if v.length() < 0.3:
		return keep
	if absf(v.x) >= absf(v.y):
		return Vector2i(1 if v.x > 0.0 else -1, 0)
	return Vector2i(0, 1 if v.y > 0.0 else -1)


## The square bite of `size` cells right next to the digger's cells `body`,
## in direction `dir` (one of four), centred on the body's side.
static func scoop_rect(body: Rect2i, dir: Vector2i, size: int) -> Rect2i:
	var c := body.position + body.size / 2
	var half := size / 2
	var at := Vector2i.ZERO
	if dir.x > 0:
		at = Vector2i(body.end.x, c.y - half)
	elif dir.x < 0:
		at = Vector2i(body.position.x - size, c.y - half)
	elif dir.y > 0:
		at = Vector2i(c.x - half, body.end.y)
	else:
		at = Vector2i(c.x - half, body.position.y - size)
	return Rect2i(at, Vector2i(size, size))


## Truck sprite frame for how many treasures are in it: empty, half, full.
static func truck_frame(in_truck: int, total := TREASURE_COUNT) -> int:
	if in_truck <= 0:
		return 0
	return 1 if in_truck * 2 <= total else 2
