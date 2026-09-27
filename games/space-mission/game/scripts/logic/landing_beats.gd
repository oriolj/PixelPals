extends RefCounted
## The Mars landing in three beats, one per seat, none of which can fail:
##   PARACHUTE (Camera): any press pops the big parachute.
##   SITE (Arm): left/right picks one of four glowing spots, A confirms.
##   CRANE (Pilot): holding down lowers the rover on its cables to a soft touchdown.
## Each beat completes itself AUTO seconds after it starts (sooner when its seat
## is empty), then plays a short outro before the next beat.

enum Beat { PARACHUTE, SITE, CRANE, DONE }

const AUTO := 5.0
const AUTO_EMPTY := 2.0      # the seat is empty: do not make anyone wait long
const OUTRO := {0: 1.4, 1: 1.2, 2: 1.8}
const CABLE_FULL := 44.0     # px of cable until the wheels touch the ground
const LOWER_SPEED := 22.0    # px/s while the Pilot holds down
const AUTO_LOWER := 48.0     # px/s once the beat lowers itself
const SAFE_TOUCHDOWN := 50.0 # the fastest touchdown the crane allows (always soft)

var beat := Beat.PARACHUTE
var t := 0.0                 # time in the current beat
var done_beat := false       # the beat's action happened; its outro is playing
var outro_t := 0.0
var site := 1                # 0..3, Terrain.SITES order
var cable := 0.0
var touchdown_speed := 0.0
var auto_completed: Array[bool] = [false, false, false]
## Which seats are empty (their beats auto-complete sooner).
var empty := {Beat.PARACHUTE: false, Beat.SITE: false, Beat.CRANE: false}


func auto_after(b: int) -> float:
	return AUTO_EMPTY if empty.get(b, false) else AUTO


## One step. input: {"camera": bool, "arm_dir": int (-1, 0, 1 flick), "arm_a": bool,
## "down": float 0..1 (Pilot holding down)}. Returns the event this frame:
## "pop", "pick" (the choice moved), "site", "lower", "touchdown", "next", "done" or "".
func step(dt: float, input: Dictionary) -> String:
	if beat == Beat.DONE:
		return ""
	t += dt
	if done_beat:
		outro_t += dt
		if outro_t >= OUTRO[beat]:
			beat += 1
			t = 0.0
			done_beat = false
			outro_t = 0.0
			return "done" if beat == Beat.DONE else "next"
		return ""
	match beat:
		Beat.PARACHUTE:
			var auto := t >= auto_after(beat)
			if input.get("camera", false) or auto:
				auto_completed[0] = auto and not input.get("camera", false)
				done_beat = true
				return "pop"
		Beat.SITE:
			var d: int = input.get("arm_dir", 0)
			var ev := ""
			if d != 0:
				site = posmod(site + d, 4)
				ev = "pick"
			var auto := t >= auto_after(beat)
			if input.get("arm_a", false) or auto:
				auto_completed[1] = auto and not input.get("arm_a", false)
				done_beat = true
				return "site"
			return ev
		Beat.CRANE:
			var auto := t >= auto_after(beat)
			var speed := 0.0
			if auto:
				speed = AUTO_LOWER
			elif float(input.get("down", 0.0)) > 0.3:
				speed = LOWER_SPEED
			if speed > 0.0:
				cable = minf(CABLE_FULL, cable + speed * dt)
				if cable >= CABLE_FULL:
					touchdown_speed = speed
					auto_completed[2] = auto
					done_beat = true
					return "touchdown"
				return "lower"
	return ""
