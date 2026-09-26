extends RefCounted
## The submarine's movement: inertia, the rock bump and the gentle current
## that brings it back when it leaves the 4x2 world. Pure static functions.

const ACCEL := 190.0
const DRAG := 110.0
const MAX_SPEED := 78.0
const HIT := Vector2(32, 16)
## The sub may drift this far outside the world before the hard stop.
const MARGIN := 40.0
const CURRENT := 90.0
const BOUNCE := 0.6
## Top of the playable water: the sub's centre stays below this.
const TOP := 12.0
const WORLD := Vector2(1280, 360)


static func accelerate(vel: Vector2, input: Vector2, dt: float) -> Vector2:
	if input.length() > 0.1:
		vel += input.limit_length(1.0) * ACCEL * dt
	else:
		vel = vel.move_toward(Vector2.ZERO, DRAG * dt)
	return vel.limit_length(MAX_SPEED)


## The play area: the whole world below the surface.
static func bounds() -> Rect2:
	return Rect2(Vector2(16, TOP), WORLD - Vector2(32, TOP + 16))


## Acceleration the current adds at `pos`: zero inside, pointing back in
## (stronger the farther out) outside.
static func current(pos: Vector2) -> Vector2:
	var b := bounds()
	var push := Vector2.ZERO
	if pos.x < b.position.x:
		push.x = b.position.x - pos.x
	elif pos.x > b.end.x:
		push.x = b.end.x - pos.x
	if pos.y < b.position.y:
		push.y = b.position.y - pos.y
	elif pos.y > b.end.y:
		push.y = b.end.y - pos.y
	if push == Vector2.ZERO:
		return Vector2.ZERO
	return push.normalized() * (CURRENT + push.length() * 3.0)


## Hard stop MARGIN px outside the play area.
static func clamp_outer(pos: Vector2) -> Vector2:
	var b := bounds().grow(MARGIN)
	return Vector2(clampf(pos.x, b.position.x, b.end.x), clampf(pos.y, b.position.y, b.end.y))


## The bounce off a rock: back the way it came, a bit slower.
static func bounce(vel: Vector2) -> Vector2:
	var v := -vel * BOUNCE
	if v.length() < 20.0:
		v = v.normalized() * 20.0 if v != Vector2.ZERO else Vector2(0, -20)
	return v
