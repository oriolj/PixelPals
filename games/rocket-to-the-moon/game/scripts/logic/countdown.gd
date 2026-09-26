extends RefCounted
## The countdown ritual as a small state machine that input cannot skip or break.
##
## WAIT: the big button pulses until the press seat presses (or AUTO_PRESS
## seconds pass, so nobody is stuck). COUNT: `lights` lights go out one per
## `light_every` seconds; presses only shake the rocket. IGNITION: smoke and
## rumble for `ignition_time`. DONE: lift-off (or stage separation).
##
## step() returns this frame's events, in order:
##   "start", "auto" (the start came from the timeout), "light" (one went out;
##   see `out`), "shake" (a press during the count), "ignite", "done".

enum State { WAIT, COUNT, IGNITION, DONE }

const AUTO_PRESS := 8.0

var lights := 5
var light_every := 1.0
var ignition_time := 1.5

var state := State.WAIT
## Seconds spent in the current state.
var t := 0.0
## Lights already out (0..lights).
var out := 0


func _init(n_lights := 5, every := 1.0, ignition := 1.5) -> void:
	lights = n_lights
	light_every = every
	ignition_time = ignition


func step(dt: float, press: bool) -> Array[String]:
	var ev: Array[String] = []
	match state:
		State.WAIT:
			t += dt
			if press or t >= AUTO_PRESS:
				if not press:
					ev.append("auto")
				ev.append("start")
				state = State.COUNT
				t = 0.0
				out = 0
		State.COUNT:
			if press:
				ev.append("shake")
			t += dt
			while t >= light_every and out < lights:
				t -= light_every
				out += 1
				ev.append("light")
			if out >= lights:
				state = State.IGNITION
				t = 0.0
				ev.append("ignite")
		State.IGNITION:
			if press:
				ev.append("shake")
			t += dt
			if t >= ignition_time:
				state = State.DONE
				t = 0.0
				ev.append("done")
		State.DONE:
			pass
	return ev


## Seconds waited so far in WAIT (drives the pulsing button and the auto press).
func waiting() -> bool:
	return state == State.WAIT


func counting() -> bool:
	return state == State.COUNT


## The big digit to show during the count (lights still on), 0 otherwise.
func digit() -> int:
	return lights - out if state == State.COUNT else 0
