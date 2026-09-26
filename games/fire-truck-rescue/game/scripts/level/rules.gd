extends RefCounted
## Tuning and the pure decisions of the run: when the hose is live, which
## fire the aim assist picks, screen <-> world directions, when the ladder
## can rescue, when the run ends.

const RUN_SECONDS := 360.0          # 6 minutes, then home anyway
const HOSE_RANGE := 8.0             # m from the truck centre (map cells are 8 m)
const HOSE_MAX_SPEED := 2.0         # m/s: "below walking speed"
const AIM_CONE := deg_to_rad(60.0)
const SUPER_CONE := deg_to_rad(90.0)
const SUPER_SECONDS := 5.0
const SUPER_RATE := 1.6
const HYDRANT_RADIUS := 3.2
const HYDRANT_COOLDOWN := 8.0
const LADDER_RANGE := 8.5
const LADDER_MAX_SPEED := 1.0
const SIREN_SECONDS := 3.0
const SIREN_COOLDOWN := 1.2
const NEXT_FIRE_DELAY := 2.5
const FIRST_FIRE_DELAY := 1.5
const STARS_PER_FIRE := 3
const PARK_SPEED := 1.5
const PARTY_DELAY := 1.2
const AUTO_LADDER_PARKED := 0.8

const TruckModel := preload("res://scripts/level/truck_model.gd")


static func hose_live(speed: float) -> bool:
	return absf(speed) < HOSE_MAX_SPEED


## World ground direction of a screen direction (up = away from the camera).
static func screen_to_world(dir: Vector2i, cam_yaw: float) -> Vector2:
	var f := TruckModel.fwd_of(cam_yaw)
	var r := TruckModel.right_of(cam_yaw)
	return (f * float(-dir.y) + r * float(dir.x)).normalized()


## The 4-way screen direction closest to a world ground direction.
static func world_to_screen4(v: Vector2, cam_yaw: float) -> Vector2i:
	var f := TruckModel.fwd_of(cam_yaw)
	var r := TruckModel.right_of(cam_yaw)
	var sx := v.dot(r)
	var sy := -v.dot(f)
	if absf(sx) >= absf(sy):
		return Vector2i(int(signf(sx)), 0)
	return Vector2i(0, int(signf(sy)))


## Aim assist: the nearest lit fire in range within `cone` of `aim` (a world
## direction). `fires` are fire_state objects. Returns its index in the
## array, or -1.
static func pick_fire(from: Vector2, aim: Vector2, fires: Array, cone := AIM_CONE, reach := HOSE_RANGE) -> int:
	var best := -1
	var best_d := INF
	for i in fires.size():
		var f = fires[i]
		if not f.lit():
			continue
		var to: Vector2 = f.pos - from
		var d := to.length()
		if d > reach:
			continue
		if d > 0.01 and absf(aim.angle_to(to)) > cone:
			continue
		if d < best_d:
			best_d = d
			best = i
	return best


## The nearest lit fire in range, any direction (the auto hose), or -1.
static func nearest_fire(from: Vector2, fires: Array, reach := HOSE_RANGE) -> int:
	return pick_fire(from, Vector2.UP, fires, TAU, reach)


static func ladder_ok(truck_pos: Vector2, speed: float, tree_pos: Vector2) -> bool:
	return absf(speed) <= LADDER_MAX_SPEED and truck_pos.distance_to(tree_pos) <= LADDER_RANGE


## The run heads home when everything is done or the clock has run out.
static func run_over(time: float, fires_left: int, cats_left: int, run_len := RUN_SECONDS) -> bool:
	return time >= run_len or (fires_left == 0 and cats_left == 0)
