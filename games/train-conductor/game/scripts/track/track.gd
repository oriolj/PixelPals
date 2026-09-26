extends RefCounted
## The track graph: nodes, directed edges (each a Curve2D), junctions,
## stations and the scenery spots that live on the track.
##
## The map is data (the constants below). Every edge runs from one node to
## another and every node has a heading, so all edges meeting at a node leave
## or arrive with the same tangent and the rails join smoothly. A node with
## two outgoing edges is a junction (the points), one with two incoming edges
## is a merge. Travel is one-way (clockwise overall); the train only reverses
## for the short roll-back into a platform.
##
## Map: 3x3 screens (3840x2160). 4 stations, 3 junctions, a tunnel on the
## left, a bridge over the pond in the middle, 3 animal spots.

const WORLD := Vector2(3840, 2160)
const TRACK_WIDTH := 48.0
const BAKE := 4.0

## name -> [position, heading]
const NODES := {
	"J1": [Vector2(620, 560), Vector2(1, 0)],
	"M1": [Vector2(2250, 560), Vector2(1, 0)],
	"M4": [Vector2(2750, 560), Vector2(1, 0)],
	"J2": [Vector2(3250, 800), Vector2(0.6, 0.8)],
	"M2": [Vector2(2900, 1850), Vector2(-1, 0)],
	"J3": [Vector2(2350, 1850), Vector2(-1, 0)],
}

## [name, from, to, via points]
const EDGES := [
	["red", "J1", "M1", [Vector2(950, 420), Vector2(1300, 360), Vector2(1600, 360), Vector2(1950, 420)]],
	["blue", "J1", "M1", [Vector2(950, 700), Vector2(1300, 780), Vector2(1600, 780), Vector2(1950, 700)]],
	["main1", "M1", "M4", []],
	["main2", "M4", "J2", [Vector2(3050, 590)]],
	["yellow", "J2", "M2", [Vector2(3470, 1020), Vector2(3570, 1250), Vector2(3570, 1450), Vector2(3460, 1720), Vector2(3200, 1865)]],
	["green", "J2", "M2", [Vector2(3290, 1030), Vector2(3200, 1250), Vector2(3200, 1450), Vector2(3120, 1710)]],
	["bottom", "M2", "J3", []],
	["west", "J3", "J1", [Vector2(2000, 1910), Vector2(1500, 1930), Vector2(900, 1910), Vector2(480, 1810),
		Vector2(330, 1500), Vector2(320, 1150), Vector2(390, 850)]],
	["pond", "J3", "M4", [Vector2(2130, 1690), Vector2(2040, 1400), Vector2(2080, 1100), Vector2(2250, 850), Vector2(2500, 660)]],
]

## Stations: colour index (Palette RED..GREEN), edge, platform centre, side
## (+1 = right of travel, -1 = left), and the hill with its houses.
const STATIONS := [
	{"colour": 0, "edge": "red", "at": Vector2(1450, 360), "side": -1, "hill": Vector2(1850, 190)},
	{"colour": 1, "edge": "blue", "at": Vector2(1450, 780), "side": 1, "hill": Vector2(1790, 965)},
	{"colour": 2, "edge": "yellow", "at": Vector2(3570, 1340), "side": -1, "hill": Vector2(3680, 1770)},
	{"colour": 3, "edge": "green", "at": Vector2(3200, 1340), "side": 1, "hill": Vector2(2840, 1250)},
]

## Scenery that sits on the track: [edge, from point, to point].
const TUNNEL := ["west", Vector2(330, 1560), Vector2(330, 1030)]
const BRIDGE := ["pond", Vector2(2045, 1480), Vector2(2050, 1180)]
const POND_CENTRE := Vector2(1900, 1330)
const POND_SIZE := Vector2(330, 190)
## The cow that likes to stand on the track, and where the animals live.
const COW_ON_TRACK := ["west", Vector2(1450, 1930)]
const FARM := Vector2(1450, 2060)
const MEADOW := Vector2(700, 1480)

## Where the train starts: edge and a point near the nose.
const START := ["west", Vector2(390, 860)]

var node_names: Array[String] = []
var node_pos: Array[Vector2] = []
var node_dir: Array[Vector2] = []
var edge_names: Array[String] = []
var edge_from: Array[int] = []
var edge_to: Array[int] = []
var curves: Array[Curve2D] = []
var lengths: Array[float] = []
## node -> Array[int] of edges
var out_edges: Array = []
var in_edges: Array = []
## Junction nodes (two outgoing edges), in map order.
var junctions: Array[int] = []
## Stations resolved to {colour, edge, mark (arc length), pos, side, hill}.
var stations: Array[Dictionary] = []


func _init() -> void:
	for n in NODES:
		node_names.append(n)
		node_pos.append(NODES[n][0])
		node_dir.append((NODES[n][1] as Vector2).normalized())
		out_edges.append([])
		in_edges.append([])
	for e in EDGES:
		var i := edge_names.size()
		var a := node_names.find(e[1])
		var b := node_names.find(e[2])
		edge_names.append(e[0])
		edge_from.append(a)
		edge_to.append(b)
		var c := _build_curve(a, b, e[3])
		curves.append(c)
		lengths.append(c.get_baked_length())
		out_edges[a].append(i)
		in_edges[b].append(i)
	for n in node_names.size():
		if out_edges[n].size() >= 2:
			junctions.append(n)
	for s in STATIONS:
		var e := edge(s.edge)
		stations.append({"colour": s.colour, "edge": e, "mark": closest(e, s.at),
			"pos": sample(e, closest(e, s.at)), "side": s.side, "hill": s.hill})


func _build_curve(a: int, b: int, via: Array) -> Curve2D:
	var pts: Array[Vector2] = [node_pos[a]]
	for v in via:
		pts.append(v)
	pts.append(node_pos[b])
	var c := Curve2D.new()
	c.bake_interval = BAKE
	var n := pts.size()
	for i in n:
		var t: Vector2
		if i == 0:
			t = node_dir[a]
		elif i == n - 1:
			t = node_dir[b]
		else:
			t = (pts[i + 1] - pts[i - 1]).normalized()
		var h_in := 0.0 if i == 0 else pts[i].distance_to(pts[i - 1]) / 3.0
		var h_out := 0.0 if i == n - 1 else pts[i].distance_to(pts[i + 1]) / 3.0
		c.add_point(pts[i], -t * h_in, t * h_out)
	return c


# ---------------------------------------------------------------- queries

func edge(edge_name: String) -> int:
	return edge_names.find(edge_name)


func node(node_name: String) -> int:
	return node_names.find(node_name)


func sample(e: int, d: float) -> Vector2:
	return curves[e].sample_baked(clampf(d, 0.0, lengths[e]), true)


## Unit tangent at arc length d.
func tangent(e: int, d: float) -> Vector2:
	var a := sample(e, d - 3.0)
	var b := sample(e, d + 3.0)
	if a.is_equal_approx(b):
		return Vector2.RIGHT
	return (b - a).normalized()


func closest(e: int, p: Vector2) -> float:
	return curves[e].get_closest_offset(p)


## Points along an edge every `step` px (including both ends).
func polyline(e: int, step := 8.0) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := maxi(2, int(ceil(lengths[e] / step)) + 1)
	for i in n:
		out.append(sample(e, lengths[e] * i / (n - 1)))
	return out


func is_junction(n: int) -> bool:
	return out_edges[n].size() >= 2


## Branch index (0/1) of edge e at its start junction, or -1.
func branch_index(e: int) -> int:
	return (out_edges[edge_from[e]] as Array).find(e)


## Unit direction on screen toward where branch b of junction n goes (a point
## ~260 px along it, from the node).
func branch_dir(n: int, b: int) -> Vector2:
	var e: int = out_edges[n][b]
	return (sample(e, minf(260.0, lengths[e])) - node_pos[n]).normalized()


## Given a flick direction on screen, which branch it asks for: the branch
## lying in that direction, or -1 when the flick is across both (toggle).
func branch_for_flick(n: int, flick: Vector2) -> int:
	var d0 := branch_dir(n, 0)
	var d1 := branch_dir(n, 1)
	var axis := (d0 - d1).normalized()
	var p := flick.normalized().dot(axis)
	if p > 0.35:
		return 0
	if p < -0.35:
		return 1
	return -1


## Station colours that lie ahead on a branch: the stations on that edge, or
## else what the next node leads to (both branches of a junction).
func beacon(e: int, depth := 3) -> Array[int]:
	var out: Array[int] = []
	for s in stations:
		if s.edge == e and not out.has(s.colour):
			out.append(s.colour)
	if not out.is_empty() or depth <= 0:
		return out
	for nxt in out_edges[edge_to[e]]:
		for c in beacon(nxt, depth - 1):
			if not out.has(c):
				out.append(c)
	out.sort()
	return out


## Station index on edge e, or -1.
func station_on(e: int) -> int:
	for i in stations.size():
		if stations[i].edge == e:
			return i
	return -1


## Every node reachable from `from` following directed edges.
func reachable(from: int) -> Dictionary:
	var seen := {from: true}
	var stack: Array[int] = [from]
	while not stack.is_empty():
		var n: int = stack.pop_back()
		for e in out_edges[n]:
			var m := edge_to[e]
			if not seen.has(m):
				seen[m] = true
				stack.append(m)
	return seen


## True if every node reaches every node (no dead ends, no traps).
func strongly_connected() -> bool:
	for n in node_names.size():
		if out_edges[n].is_empty():
			return false
		if reachable(n).size() != node_names.size():
			return false
	return true


## Smallest radius of curvature over every edge (px), sampled every 4 px.
func min_radius() -> float:
	var best := INF
	for e in curves.size():
		var d := 6.0
		while d < lengths[e] - 6.0:
			var a := sample(e, d - 6.0)
			var b := sample(e, d)
			var c := sample(e, d + 6.0)
			var turn := absf((b - a).angle_to(c - b))
			if turn > 1e-4:
				best = minf(best, b.distance_to(a) / turn)
			d += 4.0
	return best
