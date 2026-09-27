extends RefCounted
## Analytic two-bone IK for the robot arms (the Shuttle's and the rover's).
## Pure static functions, unit tested. Proposed for shared/ (Digger Treasure
## could use it): see the game's CLAUDE.md.

## The closest reachable point to `target` for bones l1 and l2 from `base`:
## never farther than l1 + l2, never nearer than max(|l1 - l2|, min_r).
static func clamp_reach(base: Vector2, target: Vector2, l1: float, l2: float, min_r := 2.0) -> Vector2:
	var to := target - base
	var d := to.length()
	var lo := maxf(absf(l1 - l2), min_r)
	var hi := l1 + l2 - 0.001
	if d < 0.0001:
		return base + Vector2(lo, 0)
	return base + to / d * clampf(d, lo, hi)


## Solves the arm: returns {"elbow": Vector2, "tip": Vector2, "reached": bool}.
## bend = +1 or -1 picks which side the elbow bends to (screen space, y down:
## +1 bends the elbow counter-clockwise of the base->tip line, i.e. "up" for
## an arm reaching right).
static func solve(base: Vector2, target: Vector2, l1: float, l2: float, bend := 1.0) -> Dictionary:
	var tip := clamp_reach(base, target, l1, l2)
	var to := tip - base
	var d := to.length()
	var cos_a := clampf((l1 * l1 + d * d - l2 * l2) / (2.0 * l1 * d), -1.0, 1.0)
	var a := acos(cos_a)
	var elbow := base + to.normalized().rotated(-a * signf(bend)) * l1
	return {"elbow": elbow, "tip": tip, "reached": tip.distance_to(target) < 0.01}


## True if `target` is inside the arm's reach from `base`.
static func in_reach(base: Vector2, target: Vector2, l1: float, l2: float, min_r := 2.0) -> bool:
	var d := base.distance_to(target)
	return d <= l1 + l2 - 0.001 and d >= maxf(absf(l1 - l2), min_r)
