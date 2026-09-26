extends RefCounted
## Aim assist maths for the gunner (pure static functions, unit tested).

## Full opening angle of the assist cone, in degrees.
const CONE_DEG := 60.0
## Targets farther than this are ignored by the assist.
const MAX_DIST := 220.0


## Index of the nearest target position inside the cone around `dir`
## (a cone `cone_deg` wide in total, centred on `dir`), or -1 if none.
static func pick_target(origin: Vector2, dir: Vector2, targets: Array, cone_deg := CONE_DEG,
		max_dist := MAX_DIST) -> int:
	if dir == Vector2.ZERO:
		return -1
	var half := deg_to_rad(cone_deg * 0.5)
	var best := -1
	var best_dist := max_dist
	for i in targets.size():
		var to: Vector2 = targets[i] - origin
		var dist := to.length()
		if dist < 0.001 or dist > best_dist:
			continue
		if absf(dir.angle_to(to)) > half:
			continue
		best = i
		best_dist = dist
	return best


## Rotate `vel` toward `target` by at most `max_turn` radians, keeping its speed.
static func steer(vel: Vector2, origin: Vector2, target: Vector2, max_turn: float) -> Vector2:
	var to := target - origin
	if to == Vector2.ZERO or vel == Vector2.ZERO:
		return vel
	return vel.rotated(clampf(vel.angle_to(to), -max_turn, max_turn))


## Snap any vector to the dominant of the 4 directions (ZERO stays ZERO).
static func snap4(v: Vector2) -> Vector2i:
	if v == Vector2.ZERO:
		return Vector2i.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


## Rotation (a multiple of 90 degrees) for a sprite drawn pointing right.
static func angle_of(dir: Vector2i) -> float:
	if dir == Vector2i.DOWN:
		return PI * 0.5
	if dir == Vector2i.LEFT:
		return PI
	if dir == Vector2i.UP:
		return -PI * 0.5
	return 0.0
