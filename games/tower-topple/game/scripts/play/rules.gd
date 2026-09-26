extends RefCounted
## Pure rules of the building site: no nodes, so tests can check them directly.

## World layout (world units = canvas px at zoom 1). The tower stands on a
## platform in the middle; the ball pit is everywhere else.
const PLATFORM_TOP := 296.0
const PLATFORM_X := 320.0
const PLATFORM_HALF := 88.0
const PIT_TOP := 322.0
## One flag every FLAG_STEP px of settled height; the last flag is the cloud line.
const FLAG_STEP := 36.0
const FLAGS := 8
const CLOUD_HEIGHT := FLAG_STEP * FLAGS

## Landing assist: the falling block's bottom within ASSIST_Y px of the tower
## top and its centre within ASSIST_X px of the tower's centre of mass.
const ASSIST_Y := 20.0
const ASSIST_X := 44.0
const ASSIST_GAIN := 12.0
const ASSIST_MAX_VX := 300.0
const ASSIST_MAX_VY := 220.0

## Settling: high friction, low bounce and extra angular damp for SETTLE_TIME.
const SETTLE_TIME := 1.5
const SETTLE_FRICTION := 1.0
const SETTLE_BOUNCE := 0.05
const SETTLE_ANGULAR_DAMP := 8.0
## A block counts for the height once slower than REST_SPEED for REST_TIME.
const REST_SPEED := 5.0
const REST_TIME := 0.5
## Blocks with this many layers resting above them freeze (static).
const BURY_LAYERS := 3

## The big button lights at the cloud line, after MAX_DROPS drops, after the
## tower timer (Game.tower_seconds), or at once when the tower falls on its own.
const MAX_DROPS := 14
## Blocks fallen off the tower into the pit that count as a self-collapse.
const COLLAPSE_FALLEN := 3
## With the toddler seated, a lit button nobody pressed for this long also
## accepts the Dropper's / Builder's A (a wandered-off toddler never blocks the run).
const TODDLER_GRACE := 20.0

const BODY_BUDGET := 40
const SHAPES := ["square", "plank", "tall", "roof", "arch", "ball"]


## Horizontal velocity for a falling block: nudged toward the tower's centre of
## mass inside the assist window, otherwise unchanged.
static func assist_vx(block_x: float, block_bottom: float, tower_top: float, com_x: float, vx: float) -> float:
	if not in_assist(block_x, block_bottom, tower_top, com_x):
		return vx
	return clampf((com_x - block_x) * ASSIST_GAIN, -ASSIST_MAX_VX, ASSIST_MAX_VX)


static func in_assist(block_x: float, block_bottom: float, tower_top: float, com_x: float) -> bool:
	return block_bottom >= tower_top - ASSIST_Y and block_bottom <= tower_top + 6.0 \
		and absf(block_x - com_x) <= ASSIST_X


## Height in flags (0..FLAGS).
static func flags_for(height: float) -> int:
	return clampi(int(floor(height / FLAG_STEP)), 0, FLAGS)


static func should_light(height: float, drops: int, build_time: float, tower_seconds: float) -> bool:
	return height >= CLOUD_HEIGHT or drops >= MAX_DROPS or build_time >= tower_seconds


static func is_collapse(fallen_from_tower: int, tower_blocks: int) -> bool:
	if fallen_from_tower >= COLLAPSE_FALLEN:
		return true
	return fallen_from_tower >= 2 and fallen_from_tower * 2 >= tower_blocks + fallen_from_tower


## Who does what for the seats present (Builder 0, Dropper 1, Toppler 2).
## Returns {"move": seat or -1, "rotate": [seat, button] or [], "drop": [...],
## "pick": seat or -1, "topple": [[seat, button], ...], "grace": [[seat, button], ...]}.
static func roles(builder: bool, dropper: bool, toppler: bool) -> Dictionary:
	var r := {"move": -1, "rotate": [], "drop": [], "pick": -1, "topple": [], "grace": []}
	if builder:
		r.move = 0
	if dropper:
		r.drop = [1, "a"]
		r.pick = 1
		if builder:
			r.rotate = [0, "a"]
	elif builder:
		r.drop = [0, "a"]
		r.rotate = [0, "b"]
	var hands: Array = []
	if dropper:
		hands.append([1, "a"])
	elif builder:
		hands.append([0, "a"])
	if toppler:
		r.topple = [[2, "any"]]
		r.grace = hands
	else:
		r.topple = hands
	return r
