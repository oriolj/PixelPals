extends RefCounted
## One fire's logic. Fires never spread and never destroy anything: water
## shrinks a fire one size per SPRAY_INTERVAL seconds of spray, and an
## unattended fire only grows, slowly, up to MAX_SIZE.

const SPRAY_INTERVAL := 1.5
const GROW_EVERY := 20.0
const START_SIZE := 2
const MAX_SIZE := 3

var index := 0
var pos := Vector2.ZERO
var kind := "house"
var size := START_SIZE
var water := 0.0
var grow_t := 0.0
var active := false
var out := false
## Seconds since the last water hit (the view squints the face while wet).
var dry_t := 99.0


func lit() -> bool:
	return active and not out


func activate() -> void:
	active = true
	out = false
	size = START_SIZE
	water = 0.0
	grow_t = 0.0


## Put out without stars (the run ended before anyone got here).
func fizzle() -> void:
	if lit():
		out = true
		size = 0


## One frame. `rate` is the spray strength this frame (0 = not watered,
## 1 = normal hose, more during a super spray). Returns "", "shrink",
## "out" or "grow".
func step(dt: float, rate: float) -> String:
	if not lit():
		return ""
	if rate > 0.0:
		dry_t = 0.0
		grow_t = 0.0
		water += dt * rate
		if water >= SPRAY_INTERVAL:
			water -= SPRAY_INTERVAL
			size -= 1
			if size <= 0:
				size = 0
				out = true
				return "out"
			return "shrink"
		return ""
	dry_t += dt
	grow_t += dt
	if grow_t >= GROW_EVERY:
		grow_t = 0.0
		if size < MAX_SIZE:
			size += 1
			return "grow"
	return ""
