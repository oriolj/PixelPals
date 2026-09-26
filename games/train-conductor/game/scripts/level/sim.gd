extends RefCounted
## The rules of a run, with no drawing: throttle and brakes, the points,
## platforms (dock, perfect stop, roll-back), passengers, carriages, the cow
## on the track, the run's end. The level screen feeds it one input dict per
## frame and turns its events into pictures and sounds; the tests drive it
## directly.
##
## Input dict (all optional): up, down (driver held), horn (driver pressed),
## points (Vector2i flick of the points seat), doors (points seat pressed),
## whistle (whistle seat pressed).
##
## Events (signal `event(kind, data)`): points, points_locked, points_same,
## took_branch, docked, perfect, rollback, doors, bell, boarded, delivered,
## coupled, exchange_done, depart, whistle, horn, cow_aside, cow_back,
## tunnel, wheee, spawned, run_end.

signal event(kind: String, data: Dictionary)

const Track := preload("res://scripts/track/track.gd")
const Train := preload("res://scripts/track/train.gd")

# Driving
const V_MAX := 300.0
const ACCEL := 120.0
const BRAKE := 340.0
const COAST := 50.0
const THROTTLE_UP := 0.9     # lever per second while held
const THROTTLE_DOWN := 1.6
# Points
const LOCK_TIME := 1.0       # the next junction locks this long before the engine reaches it
const LOCK_MIN := 50.0       # ...or this close, whatever the speed
# Platforms: arc offsets of the nose relative to the station mark
const ZONE_BACK := 300.0     # stopped up to this far short still docks (passengers walk further)
const ZONE_FRONT := 60.0     # ...or this far past the mark
const PERFECT := 35.0        # within this of the mark: sparkle (about half of the stops; tuned by simulation, 2026-09-27)
const OVERSHOOT := 360.0     # stopped past the zone but within this: roll back on its own
const ROLLBACK_SPEED := 90.0
const ROLLBACK_WAIT := 0.8
# Doors and passengers
const HOP_EVERY := 0.55
const HOP_FAST := 0.22
const DOORS_AUTO_SOLO := 1.0
const DOORS_AUTO := 5.0
const WAITING_MAX := 10
const SPAWN_EVERY := 12.0
# Run
const DELIVERIES_TO_WIN := 12
const RUN_SECONDS := 360.0
# The cow on the track
const COW_PATIENCE := 2.0
const COW_SEE := 460.0
const COW_STOP_GAP := 130.0
const COW_RETURN := 40.0
# Curves
const WOBBLE_LATERAL := 330.0

var track
var train
var time := 0.0
var run_len := RUN_SECONDS
var throttle := 0.0
var mode := "run"  # run | rollback | docked | finale
var ended := false
## junction node -> chosen branch (0/1)
var choices := {}
## junction node -> branch the train last took (for the tour rule's alternation)
var last_taken := {}
var target_junction := -1
var target_distance := INF
var locked := false
## One seat: the tour rule throws the points and the doors open by themselves.
var solo := false
## No whistle seat: the whistle toots by itself at tunnels and stations.
var auto_whistle := false

var passengers: Array[Dictionary] = []  # {id, colour, state: waiting|aboard|home, station, seat, born}
var deliveries: Array[int] = []
var perfect_stops := 0
var dock_station := -1
var doors_open := false
var dock_t := 0.0
var hop_t := 0.0
var fast_hops := false
var exchange_done := false
var rollback_t := 0.0
var rollback_station := -1
var cow := {}
var wobble := 0.0
var in_tunnel := false
var tunnel_range := Vector2.ZERO
var rng := RandomNumberGenerator.new()
var _spawn_t := 0.0
var _next_id := 0
var _rested := true
var _wheee_cool := 0.0
var _cow_cap := INF


func _init(seed_value := 0, start_passengers := true) -> void:
	rng.seed = seed_value if seed_value != 0 else randi()
	track = Track.new()
	var se: int = track.edge(Track.START[0])
	train = Train.new(track, se, track.closest(se, Track.START[1]))
	for n in track.junctions:
		choices[n] = 0
	var ce: int = track.edge(Track.COW_ON_TRACK[0])
	cow = {"edge": ce, "d": track.closest(ce, Track.COW_ON_TRACK[1]), "state": "on", "patience": 0.0, "away": 0.0}
	var te: int = track.edge(Track.TUNNEL[0])
	var a: float = track.closest(te, Track.TUNNEL[1])
	var b: float = track.closest(te, Track.TUNNEL[2])
	tunnel_range = Vector2(minf(a, b), maxf(a, b))
	if start_passengers:
		seed_passengers()


# ---------------------------------------------------------------- passengers

## The opening crowd: 2-3 at every station, wanting the other colours.
func seed_passengers() -> void:
	var counts := [3, 3, 2, 2]
	for s in track.stations.size():
		for k in counts[s]:
			spawn(s)


func spawn(station: int, colour := -1) -> Dictionary:
	var here: int = track.stations[station].colour
	if colour < 0:
		# Prefer the colour fewest people want right now, never this station's.
		var want := [0, 0, 0, 0]
		for p in passengers:
			if p.state != "home":
				want[p.colour] += 1
		var options: Array[int] = []
		var best := 99
		for c in 4:
			if c == here:
				continue
			if want[c] < best:
				best = want[c]
				options = [c]
			elif want[c] == best:
				options.append(c)
		colour = options[rng.randi() % options.size()]
	var p := {"id": _next_id, "colour": colour, "state": "waiting", "station": station, "seat": -1, "born": time}
	_next_id += 1
	passengers.append(p)
	event.emit("spawned", {"passenger": p})
	return p


func waiting_at(station: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in passengers:
		if p.state == "waiting" and p.station == station:
			out.append(p)
	return out


func aboard() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for p in passengers:
		if p.state == "aboard":
			out.append(p)
	return out


func waiting_count() -> int:
	var n := 0
	for p in passengers:
		if p.state == "waiting":
			n += 1
	return n


func oldest_aboard_colour() -> int:
	var a := aboard()
	return a[0].colour if not a.is_empty() else -1


func _free_seat() -> int:
	var used := {}
	for p in aboard():
		used[p.seat] = true
	for s in train.capacity():
		if not used.has(s):
			return s
	return -1


# ---------------------------------------------------------------- frame

func step(dt: float, input := {}) -> void:
	if ended:
		_finale(dt)
		return
	time += dt
	_wheee_cool = maxf(0.0, _wheee_cool - dt)
	if input.get("whistle", false):
		_whistle("kid")
	if input.get("horn", false):
		event.emit("horn", {})
		_scare_cow()
	_points(input.get("points", Vector2i.ZERO))
	_cow(dt)
	match mode:
		"run":
			_drive(dt, input)
		"rollback":
			_rollback(dt)
		"docked":
			_docked(dt, input)
	_tunnel()
	_curves()
	_spawn(dt)
	if deliveries.size() >= DELIVERIES_TO_WIN or time >= run_len:
		end_run()


func end_run() -> void:
	if ended:
		return
	ended = true
	if mode == "docked" or mode == "rollback":
		_finale_station = -2  # already at a platform: stay there
		train.speed = 0.0
	mode = "finale"
	doors_open = false
	event.emit("run_end", {"deliveries": deliveries.size()})


# ---------------------------------------------------------------- points

## The next junction ahead of the nose: [node, distance], following the
## single edges between (a junction's own edges are never followed).
func next_junction() -> Array:
	var node: int = track.edge_to[train.edge]
	var d: float = track.lengths[train.edge] - train.dist
	for i in 8:
		if track.is_junction(node):
			return [node, d]
		var e: int = track.out_edges[node][0]
		d += track.lengths[e]
		node = track.edge_to[e]
	return [-1, INF]


func _points(flick: Vector2i) -> void:
	var j := next_junction()
	target_junction = j[0]
	target_distance = j[1]
	locked = target_junction != -1 and target_distance <= maxf(absf(train.speed) * LOCK_TIME, LOCK_MIN)
	if target_junction == -1:
		return
	if solo and not locked:
		var want := tour_choice(target_junction)
		if want != choices[target_junction]:
			choices[target_junction] = want
			event.emit("points", {"junction": target_junction, "branch": want})
	if flick == Vector2i.ZERO:
		return
	if locked:
		event.emit("points_locked", {"junction": target_junction})
		return
	var b: int = track.branch_for_flick(target_junction, Vector2(flick))
	if b == -1:
		b = 1 - choices[target_junction]
	if b == choices[target_junction]:
		event.emit("points_same", {"junction": target_junction, "branch": b})
		return
	choices[target_junction] = b
	event.emit("points", {"junction": target_junction, "branch": b})


## Throw the points of the junction ahead (the points seat's action, also
## used by tests). Returns false when locked or when there is none.
func flip(flick: Vector2i) -> bool:
	var before: int = choices.get(target_junction, -1)
	_points(flick)
	return target_junction != -1 and choices[target_junction] != before


## One-seat tour rule: prefer the branch leading to the colour of a passenger
## aboard (the oldest counts most), then one with passengers waiting;
## otherwise alternate with the branch taken last time.
func tour_choice(n: int) -> int:
	var scores := [0.0, 0.0]
	var riding := aboard()
	for b in 2:
		var colours: Array[int] = track.beacon(track.out_edges[n][b])
		for i in riding.size():
			if colours.has(riding[i].colour):
				scores[b] += 3.0 + (1.0 if i == 0 else 0.0)
		for s in track.stations.size():
			if colours.has(track.stations[s].colour) and not waiting_at(s).is_empty():
				scores[b] += 1.0
	if scores[0] > scores[1]:
		return 0
	if scores[1] > scores[0]:
		return 1
	return 1 - int(last_taken.get(n, 1))


func _next_edge(node: int) -> int:
	if track.is_junction(node):
		var b: int = choices[node]
		last_taken[node] = b
		event.emit("took_branch", {"junction": node, "branch": b})
		return track.out_edges[node][b]
	return track.out_edges[node][0]


# ---------------------------------------------------------------- driving

func _drive(dt: float, input: Dictionary) -> void:
	var up: bool = input.get("up", false)
	var down: bool = input.get("down", false)
	if up:
		throttle = minf(1.0, throttle + THROTTLE_UP * dt)
	if down:
		throttle = maxf(0.0, throttle - THROTTLE_DOWN * dt)
	var target := minf(throttle * V_MAX, _cow_cap)
	if train.speed < target:
		train.speed = minf(target, train.speed + ACCEL * dt)
	else:
		var decel := BRAKE if down or _cow_cap < train.speed else COAST
		train.speed = maxf(target, train.speed - decel * dt)
	if train.speed > 0.0:
		train.advance(train.speed * dt, _next_edge)
		_rested = false
	if train.speed <= 0.5 and throttle <= 0.0:
		train.speed = 0.0
		if not _rested:
			_rested = true
			_check_stop()


## Where is the nose relative to each station mark? [station, offset] for the
## nearest one the nose is at or recently past, else [-1, NAN].
func station_offset() -> Array:
	var best := [-1, NAN]
	for s in track.stations.size():
		var st: Dictionary = track.stations[s]
		var p: float = train.past(st.edge, st.mark)
		if is_nan(p) or p < -ZONE_BACK - 400.0 or p > OVERSHOOT + 400.0:
			continue
		if best[0] == -1 or absf(p) < absf(best[1]):
			best = [s, p]
	return best


func _check_stop() -> void:
	var so := station_offset()
	if so[0] == -1:
		return
	var p: float = so[1]
	if p >= -ZONE_BACK and p <= ZONE_FRONT:
		_dock(so[0], absf(p) <= PERFECT)
	elif p > ZONE_FRONT and p <= OVERSHOOT:
		mode = "rollback"
		rollback_t = 0.0
		rollback_station = so[0]
		event.emit("rollback", {"station": so[0]})


func _rollback(dt: float) -> void:
	rollback_t += dt
	if rollback_t < ROLLBACK_WAIT:
		return
	var st: Dictionary = track.stations[rollback_station]
	var p: float = train.past(st.edge, st.mark)
	if is_nan(p) or p <= 0.0:
		train.speed = 0.0
		_dock(rollback_station, false)
		return
	var move := minf(ROLLBACK_SPEED * dt, p)
	train.speed = -ROLLBACK_SPEED
	train.advance(-move, _next_edge)


func _dock(station: int, perfect: bool) -> void:
	mode = "docked"
	train.speed = 0.0
	throttle = 0.0
	dock_station = station
	doors_open = false
	dock_t = 0.0
	hop_t = 0.0
	fast_hops = false
	exchange_done = false
	event.emit("docked", {"station": station, "perfect": perfect})
	if perfect:
		perfect_stops += 1
		event.emit("perfect", {"station": station})
	if auto_whistle:
		_whistle("auto")


func _docked(dt: float, input: Dictionary) -> void:
	train.speed = 0.0
	if input.get("up", false):
		mode = "run"
		doors_open = false
		_rested = false
		event.emit("depart", {"station": dock_station})
		dock_station = -1
		_drive(dt, input)
		return
	dock_t += dt
	if not doors_open:
		var auto := DOORS_AUTO_SOLO if solo else DOORS_AUTO
		if input.get("doors", false) or dock_t >= auto:
			doors_open = true
			hop_t = 0.3
			event.emit("doors", {"station": dock_station})
		return
	if exchange_done:
		return
	hop_t -= dt
	if hop_t <= 0.0:
		hop_t += HOP_FAST if fast_hops else HOP_EVERY
		_exchange_one()


## One passenger hops off (delivered) or on (boarding, coupling a new
## carriage when full). Deliveries first.
func _exchange_one() -> void:
	var st: Dictionary = track.stations[dock_station]
	for p in aboard():
		if p.colour == st.colour:
			p.state = "home"
			p.seat = -1
			p.station = dock_station
			deliveries.append(p.colour)
			event.emit("delivered", {"passenger": p, "station": dock_station, "count": deliveries.size()})
			return
	var queue := waiting_at(dock_station)
	if not queue.is_empty():
		var seat := _free_seat()
		if seat == -1 and train.cars < Train.MAX_CARS:
			train.cars += 1
			train._extend_history_back()
			event.emit("coupled", {"cars": train.cars})
			return
		if seat != -1:
			var p: Dictionary = queue[0]
			p.state = "aboard"
			p.seat = seat
			event.emit("boarded", {"passenger": p, "station": dock_station})
			return
	exchange_done = true
	event.emit("exchange_done", {"station": dock_station})


# ---------------------------------------------------------------- whistle, cow

func _whistle(by: String) -> void:
	event.emit("whistle", {"by": by, "station": dock_station if mode == "docked" else -1})
	if mode == "docked" and by == "kid":
		fast_hops = true
		event.emit("bell", {"station": dock_station})
	_scare_cow()


func _scare_cow() -> void:
	if cow.state == "on":
		cow.state = "aside"
		cow.away = 0.0
		cow.patience = 0.0
		event.emit("cow_aside", {"why": "whistle"})


## Distance along the track from the nose forward to (e, d), following the
## current choices; INF when not within a few edges.
func distance_ahead(e: int, d: float) -> float:
	if e == train.edge and d >= train.dist:
		return d - train.dist
	var acc: float = track.lengths[train.edge] - train.dist
	var node: int = track.edge_to[train.edge]
	for i in 8:
		var nxt: int = track.out_edges[node][choices[node]] if track.is_junction(node) else track.out_edges[node][0]
		if nxt == e:
			return acc + d
		acc += track.lengths[nxt]
		node = track.edge_to[nxt]
	return INF


func _cow(dt: float) -> void:
	_cow_cap = INF
	if cow.state == "on":
		var ahead := distance_ahead(cow.edge, cow.d)
		if ahead < COW_SEE:
			cow.patience += dt
			_cow_cap = maxf(0.0, ahead - COW_STOP_GAP) * 1.6
			if cow.patience >= COW_PATIENCE:
				cow.state = "aside"
				cow.away = 0.0
				cow.patience = 0.0
				event.emit("cow_aside", {"why": "patience"})
	else:
		cow.away += dt
		# Wanders back only while the train is far away (never in its face).
		var ahead := distance_ahead(cow.edge, cow.d)
		var behind: float = train.past(cow.edge, cow.d)
		var far := ahead > 1400.0 and (is_nan(behind) or behind > 900.0 or behind < 0.0)
		if cow.away >= COW_RETURN and far:
			cow.state = "on"
			cow.patience = 0.0
			event.emit("cow_back", {})


# ---------------------------------------------------------------- scenery

func _tunnel() -> void:
	var te: int = track.edge(Track.TUNNEL[0])
	var inside: bool = train.edge == te and train.dist >= tunnel_range.x and train.dist <= tunnel_range.y
	if inside and not in_tunnel:
		event.emit("tunnel", {})
		if auto_whistle:
			event.emit("whistle", {"by": "auto_long", "station": -1})
	in_tunnel = inside


func _curves() -> void:
	var e: int = train.edge
	var d: float = train.dist
	var a: Vector2 = track.tangent(e, d - 20.0)
	var b: Vector2 = track.tangent(e, d + 20.0)
	var k := absf(a.angle_to(b)) / 40.0
	var lateral: float = train.speed * train.speed * k
	wobble = clampf((lateral - WOBBLE_LATERAL) / 250.0, 0.0, 1.0)
	if wobble > 0.3 and _wheee_cool <= 0.0 and not aboard().is_empty():
		_wheee_cool = 5.0
		event.emit("wheee", {})


func _spawn(dt: float) -> void:
	_spawn_t += dt
	if _spawn_t < SPAWN_EVERY:
		return
	_spawn_t = 0.0
	if waiting_count() >= WAITING_MAX:
		return
	# The station with the fewest people waiting, never the one we stand at.
	var best := -1
	var fewest := 99
	for s in track.stations.size():
		if s == dock_station:
			continue
		var n := waiting_at(s).size()
		if n < fewest or (n == fewest and rng.randf() < 0.5):
			fewest = n
			best = s
	if best != -1:
		spawn(best)


# ---------------------------------------------------------------- finale

## Next station ahead of the nose: [station, distance to its mark].
func next_station_ahead() -> Array:
	var best := [-1, INF]
	for s in track.stations.size():
		var st: Dictionary = track.stations[s]
		var d := distance_ahead(st.edge, st.mark)
		if d < best[1]:
			best = [s, d]
	return best


## After the run: the train rolls gently into the next platform and stops.
var _finale_station := -1


func _finale(dt: float) -> void:
	time += dt
	if _finale_station == -2:
		return
	if _finale_station == -1:
		var ns := next_station_ahead()
		_finale_station = ns[0] if ns[0] != -1 else -3
	var cap := 140.0
	var room := INF  # never roll past the platform's stop post
	if _finale_station >= 0:
		var st: Dictionary = track.stations[_finale_station]
		var past: float = train.past(st.edge, st.mark)
		if not is_nan(past):
			if past >= -1.0:
				train.speed = 0.0
				_finale_station = -2
				return
			room = -past
		var d := distance_ahead(st.edge, st.mark)
		if d != INF:
			cap = minf(cap, maxf(20.0, sqrt(2.0 * 120.0 * d)))
	train.speed = move_toward(train.speed, cap, 160.0 * dt)
	train.advance(minf(train.speed * dt, room), _next_edge)
