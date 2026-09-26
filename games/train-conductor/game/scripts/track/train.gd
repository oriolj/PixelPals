extends RefCounted
## The train on the track graph: the engine's NOSE is at (edge, dist); every
## car hangs behind it at fixed arc-length gaps, sampled back through the
## history of edges travelled (no PathFollow2D: it cannot cross edges).
##
## Car layout, front to back: engine, tender, then 1..MAX_CARS carriages.

const ENGINE_LEN := 112.0
const TENDER_LEN := 100.0
const CAR_LEN := 72.0
const GAP := 10.0
const MAX_CARS := 5
const SEATS_PER_CAR := 2
## Bogies sit this far in from each end of a car.
const BOGIE_INSET := 12.0

var track  # TrackGraph (track.gd)
var edge := 0
var dist := 0.0
## Signed speed along the track, px/s (negative only while rolling back).
var speed := 0.0
var cars := 1
## Edges travelled, oldest first; the last one is `edge`.
var history: Array[int] = []
## Total distance the nose has moved (drives wheels and pistons).
var odometer := 0.0


func _init(graph, start_edge := 0, start_dist := 0.0) -> void:
	track = graph
	edge = start_edge
	dist = start_dist
	history = [start_edge]
	_extend_history_back()


## Prepend predecessor edges until the history is long enough to hold the
## longest train behind the nose (so a fresh train has a tail).
func _extend_history_back() -> void:
	var need := max_length() + 400.0
	var have := dist
	for i in range(history.size() - 2, -1, -1):
		have += track.lengths[history[i]]
	var guard := 0
	while have < need and guard < 20:
		var first: int = history[0]
		var ins: Array = track.in_edges[track.edge_from[first]]
		var prev: int = ins[0]
		history.push_front(prev)
		have += track.lengths[prev]
		guard += 1


## Put the nose somewhere new (menus, tests), rebuilding the tail.
func place(e: int, d: float) -> void:
	edge = e
	dist = d
	history = [e]
	_extend_history_back()


static func max_length() -> float:
	return ENGINE_LEN + TENDER_LEN + MAX_CARS * CAR_LEN + (MAX_CARS + 1) * GAP


func length() -> float:
	return ENGINE_LEN + TENDER_LEN + cars * CAR_LEN + (cars + 1) * GAP


func capacity() -> int:
	return cars * SEATS_PER_CAR


## Move the nose by `delta` px along the track. Forward crosses into the next
## edge chosen by `next_edge.call(node) -> int`; backward walks the history.
func advance(delta: float, next_edge: Callable) -> void:
	odometer += absf(delta)
	dist += delta
	var guard := 0
	while dist > track.lengths[edge] and guard < 16:
		dist -= track.lengths[edge]
		edge = next_edge.call(track.edge_to[edge])
		history.append(edge)
		guard += 1
	while dist < 0.0 and history.size() > 1 and guard < 32:
		history.pop_back()
		edge = history[-1]
		dist += track.lengths[edge]
		guard += 1
	dist = maxf(dist, 0.0)
	_trim_history()
	_extend_history_back()


func _trim_history() -> void:
	# Keep enough edges behind the nose for the whole train plus a roll-back.
	var need := max_length() + 600.0
	var have := dist
	var keep := 1
	for i in range(history.size() - 2, -1, -1):
		if have >= need:
			break
		have += track.lengths[history[i]]
		keep += 1
	if keep < history.size():
		history = history.slice(history.size() - keep)


## Where the track point `back` px behind the nose is: [edge, dist].
func locate_back(back: float) -> Array:
	var i := history.size() - 1
	var d := dist - back
	while d < 0.0 and i > 0:
		i -= 1
		d += track.lengths[history[i]]
	return [history[i], maxf(d, 0.0)]


func point_back(back: float) -> Vector2:
	var at := locate_back(back)
	return track.sample(at[0], at[1])


## Offsets (behind the nose) of each car's front and back bogie and its
## length. Index 0 = engine, 1 = tender, 2.. = carriages.
func car_spans() -> Array[Vector3]:
	var out: Array[Vector3] = []
	var at := 0.0
	var lens: Array[float] = [ENGINE_LEN, TENDER_LEN]
	for i in cars:
		lens.append(CAR_LEN)
	for l in lens:
		out.append(Vector3(at + BOGIE_INSET, at + l - BOGIE_INSET, l))
		at += l + GAP
	return out


## Transform of every car: centre between its two bogies, rotated along them.
func car_transforms() -> Array[Transform2D]:
	var out: Array[Transform2D] = []
	for span in car_spans():
		var f := point_back(span.x)
		var b := point_back(span.y)
		var dir := f - b
		var rot := dir.angle() if dir.length() > 0.01 else 0.0
		out.append(Transform2D(rot, (f + b) * 0.5))
	return out


func nose_position() -> Vector2:
	return track.sample(edge, dist)


func heading() -> Vector2:
	return track.tangent(edge, dist)


## Signed distance along the track from a point (edge e, arc d) to the nose:
## positive when the nose is past it, looking back through the history.
## Returns NAN if the point is not on the nose's current or recent edges.
func past(e: int, d: float) -> float:
	if e == edge:
		return dist - d
	var acc := dist
	for i in range(history.size() - 2, -1, -1):
		var h: int = history[i]
		if h == e:
			return acc + track.lengths[h] - d
		acc += track.lengths[h]
		if acc > 2000.0:
			break
	return NAN
