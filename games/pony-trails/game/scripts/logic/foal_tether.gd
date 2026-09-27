extends RefCounted
## The foal, node-free: its x is spring-bound to the mare's (an invisible
## tether it can never leave, +-MAX_GAP px), it runs in one of three lanes
## (0 near path, 1 middle, 2 meadow edge) with eased lane changes, and it
## hops to grab things. It hops its own small logs.

const LANE_Y: Array[float] = [170.0, 157.0, 143.0]
const OFFSET := -22.0      # its favourite spot: a little behind the mare
const MAX_GAP := 40.0
const K := 14.0            # spring
const DAMP := 7.0
const LANE_SPEED := 70.0   # px/s of the eased lane change
const HOP_TIME := 0.45
const HOP_HEIGHT := 9.0

var x := 0.0
var vx := 0.0
var lane := 1
var y := LANE_Y[1]         # the eased lane position (feet)
var hop_t := -1.0          # < 0 = on the ground
var hops := 0


func place(mare_x: float) -> void:
	x = mare_x + OFFSET
	vx = 0.0
	y = LANE_Y[lane]


func change_lane(d: int) -> bool:
	var to := clampi(lane + d, 0, 2)
	if to == lane:
		return false
	lane = to
	return true


func set_lane(l: int) -> void:
	lane = clampi(l, 0, 2)


func hopping() -> bool:
	return hop_t >= 0.0


func hop() -> bool:
	if hopping():
		return false
	hop_t = 0.0
	hops += 1
	return true


func hop_height() -> float:
	if not hopping():
		return 0.0
	return HOP_HEIGHT * sin(PI * clampf(hop_t / HOP_TIME, 0.0, 1.0))


## True while it is still easing toward its lane.
func changing_lane() -> bool:
	return absf(y - LANE_Y[lane]) > 0.5


func step(mare_x: float, mare_speed: float, dt: float) -> void:
	var target := mare_x + OFFSET
	var ax := K * (target - x) - DAMP * (vx - mare_speed)
	vx += ax * dt
	x += vx * dt
	# The tether: it can never be further than MAX_GAP from the mare.
	if x > mare_x + MAX_GAP:
		x = mare_x + MAX_GAP
		vx = minf(vx, mare_speed)
	elif x < mare_x - MAX_GAP:
		x = mare_x - MAX_GAP
		vx = maxf(vx, mare_speed)
	y = move_toward(y, LANE_Y[lane], LANE_SPEED * dt)
	if hopping():
		hop_t += dt
		if hop_t >= HOP_TIME:
			hop_t = -1.0


## The 1-seat / no-5-year-old foal: the lane of the nearest thing worth
## grabbing ahead, and a hop when it is close. `items` are course items.
func auto_steer(items: Array) -> Dictionary:
	var best: Dictionary = {}
	var best_d := 110.0
	for it in items:
		if it.taken or not it.get("want", true):
			continue
		var d: float = float(it.x) - x
		if d < -4.0 or d > best_d:
			continue
		best_d = d
		best = it
	if best.is_empty():
		return {}
	if int(best.lane) != lane:
		lane += signi(int(best.lane) - lane)
	elif best_d < 12.0 and not changing_lane():
		hop()
	return best
