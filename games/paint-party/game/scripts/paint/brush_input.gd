extends RefCounted
## The Brush's "a" button as a small state machine.
##
## Normal mode: press = the stroke begins, held = it paints, release = it ends.
## Tap mode (the Brush alone, or with no Colourist): a quick tap under
## TAP_TIME seconds without moving stamps instead; holding longer, or moving
## while held, paints (the stroke starts where the press began).

const TAP_TIME := 0.2

enum State { IDLE, PENDING, PAINTING }

var state := State.IDLE
var held := 0.0


## Returns "", "begin", "paint", "end" or "tap".
func update(dt: float, a_down: bool, moving: bool, tap_mode: bool) -> String:
	match state:
		State.IDLE:
			if not a_down:
				return ""
			held = 0.0
			if tap_mode:
				state = State.PENDING
				return ""
			state = State.PAINTING
			return "begin"
		State.PENDING:
			if not a_down:
				state = State.IDLE
				return "tap"
			held += dt
			if moving or held >= TAP_TIME:
				state = State.PAINTING
				return "begin"
			return ""
		_:
			if not a_down:
				state = State.IDLE
				return "end"
			return "paint"


func reset() -> void:
	state = State.IDLE
	held = 0.0
