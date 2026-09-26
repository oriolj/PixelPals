extends RefCounted
## Run rules as pure static functions (unit tested). No game over, ever.

const DEFAULT_RUN_SECONDS := 180.0
const HIT_PENALTY := 3


## Run length: Game.run_seconds when set (> 0), else about three minutes.
static func run_length(override_seconds: float) -> float:
	return override_seconds if override_seconds > 0.0 else DEFAULT_RUN_SECONDS


## Stars left after a bump: lose up to HIT_PENALTY, never below zero.
static func stars_after_hit(stars: int, penalty := HIT_PENALTY) -> int:
	return maxi(0, stars - penalty)


## Seconds between hazard spawns: gentle, ramping up slightly over the run.
static func spawn_interval(t: float, total: float) -> float:
	return lerpf(2.6, 1.5, clampf(t / maxf(total, 0.001), 0.0, 1.0))


## Chance that a spawn is a grumpy cloud rather than a balloon.
static func cloud_chance(t: float, total: float) -> float:
	return lerpf(0.35, 0.5, clampf(t / maxf(total, 0.001), 0.0, 1.0))


## Overlap of two centred rectangles.
static func overlap(a_pos: Vector2, a_size: Vector2, b_pos: Vector2, b_size: Vector2) -> bool:
	return absf(a_pos.x - b_pos.x) * 2.0 < a_size.x + b_size.x \
		and absf(a_pos.y - b_pos.y) * 2.0 < a_size.y + b_size.y
