extends RefCounted
## The Grabber's claw arm: shoot in one of 4 directions, the aim cone snaps to
## the nearest pickup, the claw extends (tracking it), grabs it and carries it
## back. Pickups are Dictionaries with at least "pos" (Vector2) and "grabbed".
##
## The claw sprite only ever turns in quarter turns (rotation()); the arm
## links follow the true direction.

const Aim := preload("res://scripts/logic/aim.gd")

enum Phase { IDLE, OUT, BACK }

const SPEED_OUT := 240.0
const SPEED_BACK := 260.0
const MAX_LEN := 100.0
const GRAB_RADIUS := 11.0
const CONE_DEG := 70.0
const AIM_DIST := 130.0

var phase := Phase.IDLE
## The direction the Grabber picked (4-way); kept while idle.
var aim := Vector2i.UP
## The true direction of the arm while out.
var dir := Vector2.UP
var length := 0.0
var target = null
var carried = null


func idle() -> bool:
	return phase == Phase.IDLE


## Starts a shot from `origin`. Returns false if the arm is still out.
func shoot(origin: Vector2, pickups: Array) -> bool:
	if phase != Phase.IDLE:
		return false
	var free := pickups.filter(func(p): return not p.get("grabbed", false))
	var positions := free.map(func(p): return p.pos)
	var pick := Aim.pick_target(origin, Vector2(aim), positions, CONE_DEG, AIM_DIST)
	target = free[pick] if pick != -1 else null
	dir = (target.pos - origin).normalized() if target != null else Vector2(aim)
	length = 0.0
	carried = null
	phase = Phase.OUT
	return true


## Advances the arm. Returns {"grabbed": p} the frame it closes on a pickup,
## {"delivered": p} the frame it brings one home, {"missed": true} when it comes
## back empty, else {}.
func step(dt: float, origin: Vector2, pickups: Array) -> Dictionary:
	match phase:
		Phase.OUT:
			if target != null and (target.get("grabbed", false) or not pickups.any(func(p): return is_same(p, target))):
				target = null
			if target != null:
				var to: Vector2 = target.pos - origin
				if to.length() > 1.0:
					dir = to.normalized()
			length = minf(length + SPEED_OUT * dt, MAX_LEN)
			var tip := tip_pos(origin)
			for p in pickups:
				if not p.get("grabbed", false) and tip.distance_to(p.pos) <= GRAB_RADIUS:
					carried = p
					p.grabbed = true
					phase = Phase.BACK
					target = null
					return {"grabbed": p}
			if length >= MAX_LEN:
				phase = Phase.BACK
				target = null
		Phase.BACK:
			length = maxf(length - SPEED_BACK * dt, 0.0)
			if carried != null:
				carried.pos = tip_pos(origin)
			if length <= 0.0:
				phase = Phase.IDLE
				var c = carried
				carried = null
				if c != null:
					return {"delivered": c}
				return {"missed": true}
	return {}


func tip_pos(origin: Vector2) -> Vector2:
	return origin + dir * length


## Claw sprite rotation (drawn pointing right): always a multiple of 90 degrees.
func rotation() -> float:
	if phase == Phase.IDLE:
		return Aim.angle_of(aim)
	return Aim.angle_of(Aim.snap4(dir))
