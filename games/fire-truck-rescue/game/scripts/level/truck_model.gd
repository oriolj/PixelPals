extends RefCounted
## The arcade fire truck on the ground plane: our own speed and steering
## model (no physics engine), soft bounces, road magnetism and the unstick
## reset. Pure logic, so tests drive it frame by frame.
##
## Heading `yaw` is Godot's rotation.y: forward is (-sin yaw, -cos yaw) on
## the (x, z) ground plane. The input is a desired world direction whose
## length is the throttle (0..1), already converted from the stick through
## the camera by the level (up on the stick = away from the camera).

const TownMap := preload("res://scripts/level/town_map.gd")

const MAX_SPEED := 11.0
const REV_SPEED := 4.5
const ACCEL := 7.0
const BRAKE := 16.0
const COAST := 7.0
const TURN_RATE := 2.3            # rad/s at cruising speed
const STEER_GAIN := 4.0
const REVERSE_ANGLE := 2.0        # rad (~115 deg): a stick further back than this reverses
const HALF_LEN := 1.25            # the body is two circles, fore and aft
const RADIUS := 1.15
const BUMP_MIN_SPEED := 1.2
const BUMP_BOUNCE := 0.3
const UNSTICK_SECONDS := 3.0
const UNSTICK_DIST := 1.0
const MAGNET_ANGLE := 0.4         # rad: a stick within this of a road's axis drives down its centre
const MAGNET_GAIN := 0.14

var pos := Vector2.ZERO
var yaw := 0.0
var speed := 0.0
## Soft bounces so far (never costs anything; the tests check that).
var bumps := 0
var last_bump_tag := ""
var wobble := 0.0
var lift := 0.0
var unsticks := 0
var stuck_t := 0.0
var _anchor := Vector2.ZERO
var _bump_cd := 0.0


static func fwd_of(y: float) -> Vector2:
	return Vector2(-sin(y), -cos(y))


static func right_of(y: float) -> Vector2:
	return Vector2(cos(y), -sin(y))


static func yaw_of(dir: Vector2) -> float:
	return atan2(-dir.x, -dir.y)


func fwd() -> Vector2:
	return fwd_of(yaw)


func place(at: Vector2, heading: float) -> void:
	pos = at
	yaw = heading
	speed = 0.0
	_anchor = at
	stuck_t = 0.0


## One frame. `extra` are dynamic solids (cars, the closed station door).
## Returns {"bump": tag or "", "unstuck": bool}.
func step(dt: float, desired: Vector2, map, extra: Array = []) -> Dictionary:
	var ev := {"bump": "", "unstuck": false}
	wobble = maxf(0.0, wobble - dt)
	lift = maxf(0.0, lift - dt)
	_bump_cd = maxf(0.0, _bump_cd - dt)
	var throttle := minf(desired.length(), 1.0)
	var target := 0.0
	if throttle > 0.05:
		var raw_delta := wrapf(yaw_of(desired) - yaw, -PI, PI)
		var want := desired
		if map != null and absf(raw_delta) <= REVERSE_ANGLE:
			want = _magnet(desired, map)
		var delta := wrapf(yaw_of(want) - yaw, -PI, PI)
		var max_turn := TURN_RATE * clampf(0.35 + absf(speed) / 5.0, 0.35, 1.0)
		if absf(raw_delta) > REVERSE_ANGLE:
			var back_delta := wrapf(yaw_of(desired) - (yaw + PI), -PI, PI)
			yaw += clampf(back_delta * STEER_GAIN, -max_turn, max_turn) * dt * 0.7
			target = -REV_SPEED * throttle
		else:
			yaw += clampf(delta * STEER_GAIN, -max_turn, max_turn) * dt
			target = MAX_SPEED * throttle * (1.0 - 0.45 * clampf(absf(delta) / 1.5, 0.0, 1.0))
		yaw = wrapf(yaw, -PI, PI)
	var rate := COAST
	if throttle > 0.05:
		rate = ACCEL if (signf(target) == signf(speed) or is_zero_approx(speed)) and absf(target) > absf(speed) else BRAKE
	speed = move_toward(speed, target, rate * dt)
	pos += fwd() * speed * dt
	var hit := _collide(map, extra)
	if hit != "":
		if absf(speed) > BUMP_MIN_SPEED and _bump_cd <= 0.0:
			speed = -speed * BUMP_BOUNCE
			wobble = 0.45
			bumps += 1
			last_bump_tag = hit
			_bump_cd = 0.3
			ev.bump = hit
		else:
			speed *= 0.5
	# Unstick: throttle held but the truck has not moved 1 m in 3 s.
	if throttle > 0.3:
		if pos.distance_to(_anchor) > UNSTICK_DIST:
			_anchor = pos
			stuck_t = 0.0
		else:
			stuck_t += dt
			if stuck_t >= UNSTICK_SECONDS and map != null:
				unstick(map)
				ev.unstuck = true
	else:
		_anchor = pos
		stuck_t = 0.0
	return ev


## Lift gently and set down on the nearest road centre, facing along the road.
func unstick(map) -> void:
	var cell: Vector2i = map.nearest_road_cell(pos)
	var dirs: Array[Vector2i] = map.road_dirs(cell)
	var best := fwd()
	var best_dot := -INF
	for d in dirs:
		var dv := Vector2(d)
		if dv.dot(fwd()) > best_dot:
			best_dot = dv.dot(fwd())
			best = dv
	place(map.cell_center(cell), yaw_of(best))
	lift = 0.7
	unsticks += 1


## Road magnetism: a stick roughly along the road the truck is on becomes
## "down the middle of this road", with a gentle pull toward its centre line.
func _magnet(desired: Vector2, map) -> Vector2:
	var cell: Vector2i = map.cell_of(pos)
	if not map.is_road(cell):
		return desired
	var n := desired.normalized()
	var axis := Vector2(signf(n.x), 0) if absf(n.x) >= absf(n.y) else Vector2(0, signf(n.y))
	if absf(n.angle_to(axis)) > MAGNET_ANGLE:
		return desired
	var ahead := cell + Vector2i(axis)
	if not map.is_road(ahead):
		return desired
	var centre: Vector2 = map.cell_center(cell)
	var perp := Vector2(-axis.y, axis.x)
	var off := (pos - centre).dot(perp)
	var corr := clampf(-off * MAGNET_GAIN, -0.35, 0.35)
	return (axis + perp * corr).normalized() * desired.length()


func _collide(map, extra: Array) -> String:
	var tag := ""
	for _pass in 2:
		for k in [-1.0, 1.0]:
			var c: Vector2 = pos + fwd() * HALF_LEN * k
			var near: Array = extra.duplicate()
			if map != null:
				near.append_array(map.solids_near(c, RADIUS))
			for s in near:
				var push: Vector2 = TownMap.push_out(c, RADIUS, s)
				if push != Vector2.ZERO:
					pos += push
					c += push
					tag = s.tag
	if map != null:
		var lo := Vector2(RADIUS, RADIUS)
		var hi: Vector2 = map.size - lo
		var clamped := pos.clamp(lo, hi)
		if clamped != pos:
			pos = clamped
			tag = "edge"
	return tag

