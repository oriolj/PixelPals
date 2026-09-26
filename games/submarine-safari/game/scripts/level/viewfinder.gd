extends RefCounted
## The camera's viewfinder: where the frame sits beside the sub, the aim
## assist that slides it onto a creature, and what counts as "in the frame".
## Pure static functions, unit tested (the aim.gd idea from PixelPals).

const SIZE := Vector2(48, 40)
## Offset from the sub's centre to the frame's centre, per pointed direction.
const OFFSETS := {
	Vector2i.RIGHT: Vector2(52, 0),
	Vector2i.LEFT: Vector2(-52, 0),
	Vector2i.UP: Vector2(0, -40),
	Vector2i.DOWN: Vector2(0, 40),
}
## A creature this close to the frame (px, from the frame's edge) pulls it.
const ASSIST := 24.0
## How far the assist may slide the frame from its resting place.
const MAX_SLIDE := 48.0
const SLIDE_SPEED := 260.0


static func base_center(sub_pos: Vector2, dir: Vector2i) -> Vector2:
	return sub_pos + OFFSETS.get(dir, OFFSETS[Vector2i.RIGHT])


static func rect_at(center: Vector2) -> Rect2:
	return Rect2(center - SIZE * 0.5, SIZE)


## Distance from a point to a rectangle (0 inside).
static func dist_to_rect(p: Vector2, r: Rect2) -> float:
	var dx := maxf(maxf(r.position.x - p.x, 0.0), p.x - r.end.x)
	var dy := maxf(maxf(r.position.y - p.y, 0.0), p.y - r.end.y)
	return Vector2(dx, dy).length()


## Index of the target the assist locks onto: the nearest point within
## ASSIST px of the frame at `center` (inside counts as 0), or -1.
static func assist_pick(center: Vector2, targets: Array) -> int:
	var r := rect_at(center)
	var best := -1
	var best_d := INF
	for i in targets.size():
		var p: Vector2 = targets[i]
		var d := dist_to_rect(p, r)
		if d > ASSIST:
			continue
		var dc := p.distance_to(center)
		if dc < best_d:
			best_d = dc
			best = i
	return best


## Where the frame wants to be: centred on the assisted target (capped to
## MAX_SLIDE from the resting place), else at rest.
static func goal(base: Vector2, targets: Array) -> Vector2:
	var i := assist_pick(base, targets)
	if i == -1:
		return base
	var p: Vector2 = targets[i]
	return base + (p - base).limit_length(MAX_SLIDE)


static func slide(current: Vector2, goal_pos: Vector2, dt: float) -> Vector2:
	return current.move_toward(goal_pos, SLIDE_SPEED * dt)


## A creature is photographed when its centre is inside the frame (a small
## grace margin), or, for big ones, when it overlaps the frame a lot.
static func contains(frame: Rect2, creature: Rect2) -> bool:
	if frame.grow(4.0).has_point(creature.get_center()):
		return true
	if creature.size.x > SIZE.x:
		var inter := frame.intersection(creature)
		return inter.get_area() >= frame.get_area() * 0.4
	return false


## 0..1: how centred the subject is (the album keeps the best photo).
static func score(frame: Rect2, creature: Rect2) -> float:
	var d := frame.get_center().distance_to(creature.get_center())
	return clampf(1.0 - d / 30.0, 0.0, 1.0)
