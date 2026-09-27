extends RefCounted
## The mare on the trail, node-free: the gaits the stick picks, the jump assist
## and the step-over. She can never fall: a missed jump is a slower step-over
## with a funny "hup!", and she only ever stops at a closed gate.
##
## x is her centre in world pixels, y the jump height (<= 0 is up).
## step() returns the events of the frame ("jump", "land", "step_over",
## "hop", "gait:<n>") so the screen plays sounds and tests read outcomes.

enum Gait { WALK, TROT, CANTER }
enum State { RUN, JUMP, STEP, HOP }

const SPEEDS: Array[float] = [26.0, 48.0, 74.0]
const THROTTLE_UP := 1.1        # gait levels per second while the stick is right
const THROTTLE_DOWN := 1.4      # ... while it is left
const ACCEL := 70.0             # px/s^2 toward the gait's speed
const WINDOW := 0.4             # the jump assist: +-0.4 s around the takeoff moment
const TAKEOFF := 16.0           # takeoff this many px before the obstacle starts
const NOSE := 14.0              # her chest is this far ahead of her centre
const JUMP_TIME := 0.62
const JUMP_HEIGHT := 14.0
const JUMP_CLEAR := 22.0        # she lands this far past the obstacle's end
const STEP_TIME := 1.0          # the step-over
const STEP_SPEED := 0.6         # ... at this fraction of the walk's speed
const HOP_TIME := 0.4           # a happy hop with nothing to jump
const HOP_HEIGHT := 4.0

var x := 0.0
var y := 0.0
var speed := 0.0
## 0..2: walk .. canter. The stick moves it; releasing keeps the gait.
var throttle := 1.0
var state := State.RUN
var state_t := 0.0
## Obstacles ahead: [{"x": start, "w": width, "kind": String, "done": bool, "clean": bool}]
var obstacles: Array[Dictionary] = []
## A world x she must stop before (a closed gate), or INF.
var stop_x := INF
var clean_jumps := 0
var step_overs := 0
var _scheduled: Dictionary = {}
var _jump_from := 0.0
var _jump_to := 0.0
var _last_gait := -1


func gait() -> int:
	if throttle < 0.67:
		return Gait.WALK
	if throttle < 1.34:
		return Gait.TROT
	return Gait.CANTER


func target_speed() -> float:
	return SPEEDS[gait()]


## The stick (x in -1..1) moves the gait up or down.
func steer(stick_x: float, dt: float) -> void:
	if stick_x > 0.3:
		throttle = minf(2.0, throttle + THROTTLE_UP * dt)
	elif stick_x < -0.3:
		throttle = maxf(0.0, throttle - THROTTLE_DOWN * dt)


## The next obstacle not yet passed.
func next_obstacle() -> Dictionary:
	var best: Dictionary = {}
	for ob in obstacles:
		if ob.done:
			continue
		if best.is_empty() or ob.x < best.x:
			best = ob
	return best


## Seconds until she reaches the takeoff point of `ob` at her current pace
## (negative once past it).
func time_to_takeoff(ob: Dictionary) -> float:
	var pace := maxf(speed, SPEEDS[Gait.WALK])
	return (float(ob.x) - TAKEOFF - x) / pace


## The jump button. Within the window the jump is scheduled to start at the
## right moment ("jump"); with nothing to jump it is a happy hop ("hop").
func press_jump() -> String:
	if state == State.JUMP or state == State.STEP:
		return "none"
	var ob := next_obstacle()
	if not ob.is_empty():
		var tt := time_to_takeoff(ob)
		if absf(tt) <= WINDOW:
			_scheduled = ob
			return "scheduled"
		if tt < 0.0:
			return "none"   # too late: she is already at it, the step-over follows
	if state == State.RUN:
		state = State.HOP
		state_t = 0.0
		return "hop"
	return "none"


func is_airborne() -> bool:
	return state == State.JUMP or state == State.HOP


func step(dt: float) -> Array[String]:
	var ev: Array[String] = []
	var g := gait()
	if g != _last_gait:
		ev.append("gait:%d" % g)
		_last_gait = g
	match state:
		State.JUMP:
			state_t += dt
			var k := clampf(state_t / JUMP_TIME, 0.0, 1.0)
			x = lerpf(_jump_from, _jump_to, k)
			y = -JUMP_HEIGHT * sin(PI * k)
			if k >= 1.0:
				y = 0.0
				state = State.RUN
				ev.append("land")
			return ev
		State.STEP:
			state_t += dt
			speed = SPEEDS[Gait.WALK] * STEP_SPEED
			x += speed * dt
			y = -1.0 if fmod(state_t, 0.5) < 0.25 else 0.0
			if state_t >= STEP_TIME:
				state = State.RUN
				y = 0.0
			return ev
		State.HOP:
			state_t += dt
			var kh := clampf(state_t / HOP_TIME, 0.0, 1.0)
			y = -HOP_HEIGHT * sin(PI * kh)
			if kh >= 1.0:
				y = 0.0
				state = State.RUN
	# Running (and hopping): approach the gait's speed, brake for a closed gate.
	var want := target_speed()
	if stop_x != INF:
		var room := stop_x - x
		want = clampf(minf(want, room * 1.6), 0.0, want)
	speed = move_toward(speed, want, ACCEL * dt)
	if stop_x != INF and x + speed * dt > stop_x:
		x = maxf(x, stop_x)
		speed = 0.0
	else:
		x += speed * dt
	# The scheduled jump starts exactly at the takeoff point.
	if not _scheduled.is_empty() and state != State.JUMP:
		var ob := _scheduled
		if x >= float(ob.x) - TAKEOFF:
			_scheduled = {}
			ob.done = true
			ob.clean = true
			clean_jumps += 1
			state = State.JUMP
			state_t = 0.0
			_jump_from = x
			_jump_to = float(ob.x) + float(ob.w) + JUMP_CLEAR
			y = 0.0
			ev.append("jump")
			return ev
	# Reaching an obstacle without a jump: she steps over it, slower, "hup!".
	var nx := next_obstacle()
	if not nx.is_empty() and x + NOSE >= float(nx.x):
		nx.done = true
		nx.clean = false
		_scheduled = {}
		step_overs += 1
		state = State.STEP
		state_t = 0.0
		y = 0.0
		ev.append("step_over")
	return ev
