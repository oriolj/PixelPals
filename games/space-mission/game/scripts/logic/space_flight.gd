extends RefCounted
## Damped 2D space flight for the Shuttle: thrust from the stick (boost with A),
## drag, and an auto-stabiliser that stops it when the stick is released.
## No gravity. Soft collisions: a bump pushes the craft out and back ("boing").

const ACCEL := 150.0         # px/s^2 at full stick
const BOOST := 1.8           # thrust multiplier while A is held
const MAX_SPEED := 70.0
const MAX_BOOST_SPEED := 110.0
const DRAG := 0.6            # per second, always
const STABILISE := 3.2       # extra damping per second with the stick released
const BOUNCE := 0.6

var pos := Vector2.ZERO
var vel := Vector2.ZERO
var bounds := Rect2(0, 0, 320, 180)
## Half size of the craft's collision box.
var half := Vector2(22, 8)


func _init(start := Vector2.ZERO) -> void:
	pos = start


## One step. `stick` is the Pilot's move vector. Returns true if a thruster fired
## this frame (for the puff sound and the engine glow).
func step(dt: float, stick: Vector2, boost := false) -> bool:
	var thrust := stick.limit_length(1.0)
	if thrust.length() > 0.05:
		vel += thrust * ACCEL * (BOOST if boost else 1.0) * dt
	else:
		vel *= exp(-STABILISE * dt)
	vel *= exp(-DRAG * dt)
	vel = vel.limit_length(MAX_BOOST_SPEED if boost else MAX_SPEED)
	if vel.length() < 0.5 and thrust == Vector2.ZERO:
		vel = Vector2.ZERO
	pos += vel * dt
	_keep_in_bounds()
	return thrust.length() > 0.05


## Steers like a pilot toward `goal` (the autopilot and the demo use it): a stick
## vector that brakes on arrival.
static func stick_toward(from: Vector2, velocity: Vector2, goal: Vector2) -> Vector2:
	var to := goal - from
	var want := to.limit_length(40.0) / 40.0 * MAX_SPEED * 0.8
	var v := (want - velocity) / 30.0
	return v.limit_length(1.0) if to.length() > 1.5 or velocity.length() > 2.0 else Vector2.ZERO


func _keep_in_bounds() -> void:
	var lo := bounds.position
	var hi := bounds.end
	if pos.x < lo.x:
		pos.x = lo.x
		vel.x = absf(vel.x) * BOUNCE
	elif pos.x > hi.x:
		pos.x = hi.x
		vel.x = -absf(vel.x) * BOUNCE
	if pos.y < lo.y:
		pos.y = lo.y
		vel.y = absf(vel.y) * BOUNCE
	elif pos.y > hi.y:
		pos.y = hi.y
		vel.y = -absf(vel.y) * BOUNCE


func rect() -> Rect2:
	return Rect2(pos - half, half * 2.0)


## Soft collision with an obstacle rect: pushes the craft out along the shallow
## axis and bounces it back. Returns true on a bump.
func push_out(obstacle: Rect2) -> bool:
	var r := rect()
	if not r.intersects(obstacle):
		return false
	var dx_left := r.end.x - obstacle.position.x
	var dx_right := obstacle.end.x - r.position.x
	var dy_up := r.end.y - obstacle.position.y
	var dy_down := obstacle.end.y - r.position.y
	var m := minf(minf(dx_left, dx_right), minf(dy_up, dy_down))
	if m == dx_left:
		pos.x -= dx_left + 1.0
		vel.x = -maxf(absf(vel.x), 20.0) * BOUNCE
	elif m == dx_right:
		pos.x += dx_right + 1.0
		vel.x = maxf(absf(vel.x), 20.0) * BOUNCE
	elif m == dy_up:
		pos.y -= dy_up + 1.0
		vel.y = -maxf(absf(vel.y), 20.0) * BOUNCE
	else:
		pos.y += dy_down + 1.0
		vel.y = maxf(absf(vel.y), 20.0) * BOUNCE
	return true
