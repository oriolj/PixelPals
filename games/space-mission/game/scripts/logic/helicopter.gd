extends RefCounted
## The little Mars helicopter. A Camera press launches it from the rover: it
## buzzes up, flies ahead to the next science target and shines a spotlight on
## it (a reveal: purely a hint, it changes nothing), comes back, lands on the
## rover and rests for COOLDOWN seconds. Presses while it flies make it loop.

enum State { DOCKED, UP, SCOUT, HOVER, BACK, COOLDOWN }

const UP_TIME := 0.8
const CRUISE_H := 40.0
const SPEED := 95.0
const HOVER_TIME := 1.6
const COOLDOWN := 3.0
const LOOP_TIME := 0.6
const LOOP_R := 6.0

var state := State.DOCKED
var pos := Vector2.ZERO
var t := 0.0
var loop_t := 0.0
var loops := 0
var launches := 0
## Index of the target it is scouting (-1: none ahead, it just looks around).
var target := -1


func flying() -> bool:
	return state in [State.UP, State.SCOUT, State.HOVER, State.BACK]


func can_launch() -> bool:
	return state == State.DOCKED


## Launch toward target index `to` (-1 for none). False when it is flying or resting.
func launch(to: int) -> bool:
	if not can_launch():
		return false
	state = State.UP
	t = 0.0
	target = to
	launches += 1
	return true


## A press while it flies: a loop-the-loop. True if it looped.
func press() -> bool:
	if not flying() or loop_t > 0.0:
		return false
	loop_t = LOOP_TIME
	loops += 1
	return true


## One step. home = its landing spot on the rover, target_pos = where the target
## is on the ground (ignored when target is -1). Returns "revealed" on the frame
## the spotlight lands on the target, "landed" when it touches the rover, else "".
func step(dt: float, home: Vector2, target_pos: Vector2) -> String:
	t += dt
	loop_t = maxf(0.0, loop_t - dt)
	var event := ""
	match state:
		State.DOCKED, State.COOLDOWN:
			pos = home
			if state == State.COOLDOWN and t >= COOLDOWN:
				state = State.DOCKED
				t = 0.0
		State.UP:
			pos = home.lerp(home + Vector2(0, -CRUISE_H), clampf(t / UP_TIME, 0.0, 1.0))
			if t >= UP_TIME:
				state = State.SCOUT
				t = 0.0
		State.SCOUT:
			var goal := (target_pos if target != -1 else home + Vector2(70, 0)) + Vector2(0, -CRUISE_H)
			pos = pos.move_toward(goal, SPEED * dt)
			if pos.distance_to(goal) < 1.0 or t > 4.0:
				state = State.HOVER
				t = 0.0
				if target != -1:
					event = "revealed"
		State.HOVER:
			if t >= HOVER_TIME:
				state = State.BACK
				t = 0.0
		State.BACK:
			var above := home + Vector2(0, -12)
			if pos.distance_to(above) > 2.0 and t < 4.0:
				pos = pos.move_toward(above, SPEED * dt)
			else:
				pos = pos.move_toward(home, 30.0 * dt)
				if pos.distance_to(home) < 0.5 or t > 5.0:
					pos = home
					state = State.COOLDOWN
					t = 0.0
					event = "landed"
	return event


## Where to draw it: its position plus the loop's circle.
func draw_pos() -> Vector2:
	if loop_t <= 0.0:
		return pos
	var a := (1.0 - loop_t / LOOP_TIME) * TAU
	return pos + Vector2(sin(a), -1.0 + cos(a)) * LOOP_R
