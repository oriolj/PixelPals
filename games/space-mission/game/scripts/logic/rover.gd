extends RefCounted
## The Mars rover: drive left/right, A brakes, nothing hurts it. Three wheels
## follow the ground on springs; the body rides on their average and its tilt
## is clamped, so it can never flip. No physics engine: deterministic.

const MAX_SPEED := 34.0
const ACCEL := 40.0
const BRAKE := 120.0
const DRAG := 0.9
const WHEEL_X := [-13.0, 0.0, 13.0]
const WHEEL_R := 4.0
const SPRING := 90.0
const DAMP := 14.0
const MAX_TILT := 0.3        # radians; the body never tips further
const AUTO_AFTER := 5.0      # idle seconds before it creeps on by itself
const CREEP := 0.45

var x := 70.0
var speed := 0.0
var wheel_y: Array[float] = [0.0, 0.0, 0.0]
var wheel_v: Array[float] = [0.0, 0.0, 0.0]
var tilt := 0.0
var idle := 0.0
var min_x := 20.0
var max_x := 3580.0
## Wheel spin, in px rolled (the wheel frames follow it).
var rolled := 0.0


func place(at_x: float, terrain) -> void:
	x = at_x
	speed = 0.0
	for i in 3:
		wheel_y[i] = terrain.height_at(x + WHEEL_X[i]) - WHEEL_R
		wheel_v[i] = 0.0
	tilt = 0.0


## One step. `drive` in -1..1 (the stick's x), `brake` = A held, `hold` = the
## arm is drilling (the rover waits).
func step(dt: float, terrain, drive: float, brake := false, hold := false) -> void:
	if absf(drive) > 0.2 or brake:
		idle = 0.0
	else:
		idle += dt
		if idle >= AUTO_AFTER:
			drive = CREEP     # nobody driving: roll on gently
	var want := clampf(drive, -1.0, 1.0) * MAX_SPEED
	if hold:
		speed = move_toward(speed, 0.0, BRAKE * dt)
	elif brake:
		speed = move_toward(speed, 0.0, BRAKE * dt)
	elif absf(drive) > 0.05:
		speed = move_toward(speed, want, ACCEL * dt)
	else:
		speed *= exp(-DRAG * dt)
	x = clampf(x + speed * dt, min_x, max_x)
	if x == min_x or x == max_x:
		speed = 0.0
	rolled += speed * dt
	for i in 3:
		var ground: float = terrain.height_at(x + WHEEL_X[i]) - WHEEL_R
		wheel_v[i] += ((ground - wheel_y[i]) * SPRING - wheel_v[i] * DAMP) * dt
		wheel_y[i] += wheel_v[i] * dt
		if wheel_y[i] > ground:      # a wheel never sinks into the ground
			wheel_y[i] = ground
			wheel_v[i] = minf(wheel_v[i], 0.0)
	tilt = clampf(atan2(wheel_y[2] - wheel_y[0], WHEEL_X[2] - WHEEL_X[0]), -MAX_TILT, MAX_TILT)


## The body's centre y (its wheels sit at local y 20 of the 40x24 sprite).
func body_y() -> float:
	return (wheel_y[0] + wheel_y[1] + wheel_y[2]) / 3.0 - 8.0


## Upright means the tilt is inside the clamp and the body is above the ground.
func upright(terrain) -> bool:
	return absf(tilt) <= MAX_TILT + 0.0001 and body_y() < terrain.height_at(x)
