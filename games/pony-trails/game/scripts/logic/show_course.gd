extends RefCounted
## The horse show, node-free. Rounds: the bell, the mare's course (6 jumps on
## an automatic path around the ring), the bell again, the foal's mini course
## (4 tiny jumps, then 4 pick-the-colour poles), the rosettes. Every round
## finishes: a refused jump is a comedic stop, a snort and a lap back, and the
## second approach always clears; every wait for one seat ends after 5 s.
##
## The ring is seen from the side: the front straight (y 160, going right),
## a turn at the right end, the back straight (y 118, going left). Positions
## along the loop are `s` in px; pos(s) maps them to the screen.

enum Phase { BELL_MARE, MARE, BELL_FOAL, FOAL, PICKS, ROSETTES, DONE }
enum MState { RUN, JUMP, REFUSE, BACK, TURN, FINISH }

const FRONT_Y := 160.0
const BACK_Y := 118.0
const LEFT_X := 30.0
const RIGHT_X := 270.0
const STRAIGHT := RIGHT_X - LEFT_X            # 260
const TURN_R := (FRONT_Y - BACK_Y) * 0.5      # 21
const TURN_LEN := PI * TURN_R
const MARE_JUMPS: Array[float] = [60.0, 120.0, 180.0, 366.0, 426.0, 486.0]
const MARE_FINISH := 534.0
const MARE_SPEED := 70.0
const TURN_SPEED := 52.0
const WINDOW := 0.4
const TAKEOFF := 16.0
const JUMP_W := 12.0
const JUMP_TIME := 0.6
const JUMP_HEIGHT := 16.0
const REFUSE_TIME := 1.0
const BACK_DIST := 56.0
const BACK_TIME := 1.4
const TURN_TIME := 0.5

const FOAL_Y := 174.0
const FOAL_JUMPS: Array[float] = [70.0, 120.0, 170.0, 220.0]
const FOAL_SPEED := 46.0
const FOAL_WINDOW := 0.8
const FOAL_HOP_TIME := 0.5
const POLES: Array[float] = [240.0, 180.0, 120.0, 60.0]
const POLE_Y := 124.0
const CONE_COLOURS: Array[String] = ["red", "blue", "yellow", "green"]

const BELL_WAIT := 5.0
const BELL_WAIT_NO_TODDLER := 1.2
const PICK_WAIT := 5.0
const PICK_WAIT_AUTO := 1.5
const ROSETTE_EACH := 1.3
const CARROT_TIME := 2.0

var phase := Phase.BELL_MARE
var phase_t := 0.0
var toddler := true
var foal_auto := false

# The mare.
var s := 0.0
var mstate := MState.RUN
var mstate_t := 0.0
var jump_i := 0                 # the next jump
var refused: Array[bool] = [false, false, false, false, false, false]
var clean: Array[bool] = [false, false, false, false, false, false]
var refusals := 0
var _scheduled := false
var _jump_from := 0.0
var _jump_to := 0.0
var mare_y := 0.0               # jump height (<= 0 is up)

# The foal.
var foal_x := 0.0
var foal_hop_t := -1.0
var foal_i := 0
var foal_clean: Array[bool] = [false, false, false, false]
var _foal_scheduled := false
var pole_i := 0
var pole_colour: Array[int] = [0, 1, 2, 3]
var cone_order: Array = []      # per pole: 4 colour indices for up, right, down, left
var picks: Array[int] = []      # the direction index picked at each pole
var picked_t := -1.0

# The rosettes.
var rosettes: Array[Dictionary] = []
var rosette_shown := 0
var carrot_given := false
var rng := RandomNumberGenerator.new()


func _init(has_toddler := true, auto_foal := false, seed_ := 3) -> void:
	toddler = has_toddler
	foal_auto = auto_foal
	rng.seed = seed_
	for k in POLES.size():
		pole_colour[k] = rng.randi() % 4
		var order := [0, 1, 2, 3]
		for i in range(3, 0, -1):
			var j := rng.randi() % (i + 1)
			var tmp = order[i]
			order[i] = order[j]
			order[j] = tmp
		cone_order.append(order)


# ---------------------------------------------------------------- the path

## Screen position of loop parameter s (the mare's path).
static func pos(sv: float) -> Vector2:
	if sv <= STRAIGHT:
		return Vector2(LEFT_X + sv, FRONT_Y)
	if sv <= STRAIGHT + TURN_LEN:
		var th := (sv - STRAIGHT) / TURN_R
		return Vector2(RIGHT_X + TURN_R * sin(th), BACK_Y + TURN_R + TURN_R * cos(th))
	var back := sv - STRAIGHT - TURN_LEN
	return Vector2(RIGHT_X - back, BACK_Y)


## Facing right at s? (the front straight and the first half of the turn)
static func faces_right(sv: float) -> bool:
	return sv <= STRAIGHT + TURN_LEN * 0.5


static func jump_pos(i: int) -> Vector2:
	return pos(MARE_JUMPS[i])


# ---------------------------------------------------------------- per frame

## input: {"bell": bool, "jump": bool (Rider A), "hop": bool (Foal A), "dir": Vector2i (Foal flick)}
func step(dt: float, input: Dictionary) -> Array[String]:
	var ev: Array[String] = []
	phase_t += dt
	match phase:
		Phase.BELL_MARE, Phase.BELL_FOAL:
			var wait := BELL_WAIT if toddler else BELL_WAIT_NO_TODDLER
			if input.get("bell", false) or phase_t >= wait:
				ev.append("bell")
				_next_phase()
		Phase.MARE:
			ev.append_array(_mare(dt, input.get("jump", false)))
		Phase.FOAL:
			ev.append_array(_foal(dt, input.get("hop", false)))
		Phase.PICKS:
			ev.append_array(_picks(dt, input.get("dir", Vector2i.ZERO)))
		Phase.ROSETTES:
			ev.append_array(_rosettes(dt))
	return ev


func _next_phase() -> void:
	phase = (phase + 1) as Phase
	phase_t = 0.0
	if phase == Phase.FOAL:
		foal_x = 0.0
		foal_i = 0


func done() -> bool:
	return phase == Phase.DONE


# ---------------------------------------------------------------- the mare's course

func mare_pos() -> Vector2:
	return pos(s) + Vector2(0, mare_y)


## Which way she looks: right on the front straight, left on the back; backing
## off from a refusal she turns around.
func mare_faces_right() -> bool:
	var r := faces_right(s)
	if mstate == MState.BACK:
		return not r
	return r


func _mare(dt: float, jump_pressed: bool) -> Array[String]:
	var ev: Array[String] = []
	mstate_t += dt
	match mstate:
		MState.JUMP:
			var k := clampf(mstate_t / JUMP_TIME, 0.0, 1.0)
			s = lerpf(_jump_from, _jump_to, k)
			mare_y = -JUMP_HEIGHT * sin(PI * k)
			if k >= 1.0:
				mare_y = 0.0
				mstate = MState.RUN
				ev.append("land")
			return ev
		MState.REFUSE:
			if mstate_t >= REFUSE_TIME:
				mstate = MState.BACK
				mstate_t = 0.0
			return ev
		MState.BACK:
			s -= BACK_DIST / BACK_TIME * dt
			mare_y = -1.0 if fmod(mstate_t, 0.4) < 0.2 else 0.0
			if mstate_t >= BACK_TIME:
				mstate = MState.TURN
				mstate_t = 0.0
				mare_y = 0.0
			return ev
		MState.TURN:
			if mstate_t >= TURN_TIME:
				mstate = MState.RUN
				mstate_t = 0.0
			return ev
		MState.FINISH:
			if mstate_t >= 1.2:
				_next_phase()
			return ev
	# Running around the ring.
	var on_turn := s > STRAIGHT and s < STRAIGHT + TURN_LEN
	var sp := TURN_SPEED if on_turn else MARE_SPEED
	if jump_i < MARE_JUMPS.size():
		var takeoff := MARE_JUMPS[jump_i] - TAKEOFF
		if jump_pressed and not _scheduled and absf((takeoff - s) / sp) <= WINDOW:
			_scheduled = true
			ev.append("scheduled")
		s += sp * dt
		if s >= takeoff and (_scheduled or refused[jump_i]):
			# A clean jump (or the second approach after a refusal: she knows it now).
			clean[jump_i] = _scheduled and not refused[jump_i]
			_scheduled = false
			mstate = MState.JUMP
			mstate_t = 0.0
			_jump_from = s
			_jump_to = MARE_JUMPS[jump_i] + JUMP_W + 14.0
			jump_i += 1
			ev.append("jump_clean" if clean[jump_i - 1] else "jump")
		elif s >= MARE_JUMPS[jump_i] - 6.0:
			# A refusal: the comedic stop, a snort, back off and go around again.
			refused[jump_i] = true
			refusals += 1
			s = MARE_JUMPS[jump_i] - 6.0
			mstate = MState.REFUSE
			mstate_t = 0.0
			ev.append("refuse")
	else:
		s += sp * dt
		if s >= MARE_FINISH:
			s = MARE_FINISH
			mstate = MState.FINISH
			mstate_t = 0.0
			ev.append("finish")
	return ev


func clean_count() -> int:
	var n := 0
	for c in clean:
		if c:
			n += 1
	return n


# ---------------------------------------------------------------- the foal's mini course

func foal_pos() -> Vector2:
	var hop := 0.0
	if foal_hop_t >= 0.0:
		hop = -8.0 * sin(PI * clampf(foal_hop_t / FOAL_HOP_TIME, 0.0, 1.0))
	if phase == Phase.PICKS or phase == Phase.ROSETTES or phase == Phase.DONE:
		return Vector2(foal_x, POLE_Y + hop)
	return Vector2(foal_x, FOAL_Y + hop)


func _foal(dt: float, hop_pressed: bool) -> Array[String]:
	var ev: Array[String] = []
	if foal_hop_t >= 0.0:
		foal_hop_t += dt
		if foal_hop_t >= FOAL_HOP_TIME:
			foal_hop_t = -1.0
	foal_x += FOAL_SPEED * dt
	if foal_i < FOAL_JUMPS.size():
		var takeoff := FOAL_JUMPS[foal_i] - 10.0
		var tt := (takeoff - foal_x) / FOAL_SPEED
		var press := hop_pressed or (foal_auto and absf(tt) < 0.05)
		if press and not _foal_scheduled and absf(tt) <= FOAL_WINDOW:
			_foal_scheduled = true
		if foal_x >= takeoff:
			# The foal always hops its tiny jumps; a pressed one is a clean one.
			foal_clean[foal_i] = _foal_scheduled
			_foal_scheduled = false
			foal_hop_t = 0.0
			foal_i += 1
			ev.append("foal_jump_clean" if foal_clean[foal_i - 1] else "foal_jump")
	elif foal_x >= RIGHT_X:
		_next_phase()
		foal_x = POLES[0] + 22.0
		pole_i = 0
		picked_t = -1.0
		ev.append("poles")
	return ev


func foal_clean_count() -> int:
	var n := 0
	for c in foal_clean:
		if c:
			n += 1
	return n


## The cone colour index under direction slot k (0 up, 1 right, 2 down, 3 left) at the current pole.
func cone_at(k: int) -> int:
	return int(cone_order[clampi(pole_i, 0, POLES.size() - 1)][k])


static func dir_slot(d: Vector2i) -> int:
	match d:
		Vector2i.UP: return 0
		Vector2i.RIGHT: return 1
		Vector2i.DOWN: return 2
		Vector2i.LEFT: return 3
	return -1


func _picks(dt: float, d: Vector2i) -> Array[String]:
	var ev: Array[String] = []
	var target := POLES[pole_i]
	if foal_x > target + 0.5:
		foal_x = maxf(target, foal_x - FOAL_SPEED * dt)
		return ev
	if picked_t < 0.0:
		var slot := dir_slot(d)
		var wait := PICK_WAIT_AUTO if foal_auto else PICK_WAIT
		if slot == -1 and phase_t >= wait:
			slot = rng.randi() % 4
		if slot != -1:
			picks.append(slot)
			picked_t = 0.0
			ev.append("pick_match" if cone_at(slot) == pole_colour[pole_i] else "pick")
		return ev
	picked_t += dt
	if picked_t >= 1.0:
		pole_i += 1
		picked_t = -1.0
		phase_t = 0.0
		if pole_i >= POLES.size():
			pole_i = POLES.size() - 1
			phase = Phase.ROSETTES
			phase_t = 0.0
			ev.append("rosettes")
	return ev


# ---------------------------------------------------------------- the rosettes

## Everybody wins: one per horse and one per seated rider. The colour depends
## on the day, but every one gets the same fanfare.
func award(day: Dictionary, seated: Array) -> void:
	rosettes.clear()
	var cj := clean_count()
	rosettes.append({"who": "mare", "colour": _band(cj, [6, 5, 4, 2])})
	var apples := int(day.get("apples", 0)) + foal_clean_count() * 2
	rosettes.append({"who": "foal", "colour": _band(apples, [14, 9, 5, 1])})
	var scores := [int(day.get("clean_jumps", 0)) + cj, int(day.get("flowers", 0)), int(day.get("carrots", 0))]
	for seat in seated:
		rosettes.append({"who": "rider%d" % int(seat), "colour": _band(scores[int(seat) % 3], [8, 5, 3, 1])})


static func _band(v: int, cuts: Array) -> String:
	var colours := ["blue", "red", "yellow", "green", "purple"]
	for i in cuts.size():
		if v >= int(cuts[i]):
			return colours[i]
	return colours[4]


func _rosettes(dt: float) -> Array[String]:
	var ev: Array[String] = []
	if rosette_shown < rosettes.size():
		if phase_t >= ROSETTE_EACH * (rosette_shown + 1) - 0.8:
			rosette_shown += 1
			ev.append("rosette")
		return ev
	var t0 := ROSETTE_EACH * rosettes.size()
	if not carrot_given and phase_t >= t0:
		carrot_given = true
		ev.append("carrot")
	if phase_t >= t0 + CARROT_TIME:
		phase = Phase.DONE
		ev.append("done")
	return ev
