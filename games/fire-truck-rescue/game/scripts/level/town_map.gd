extends RefCounted
## The town as diffable text, and everything derived from it: cell lookups,
## fire and cat spots, hydrants, the station, the solids the truck bumps
## into, and road paths (for the demo driver and the unstick reset).
##
## Ground coordinates are Vector2(x, z) in metres; cell (c, r) spans
## [c * CELL, (c + 1) * CELL) on x and [r * CELL, (r + 1) * CELL) on z.
##
## Legend:
##   #  road            =  bridge (road over water)   y  road with a hydrant on its kerb
##   ~  river           o  roundabout island          .  grass
##   h  house           t  tree                        S  fire station (door on its road side)
##   F  house on fire   B  bin on fire                 H  haystack on fire
##   C  cat tree (a cat gets stuck there during the run)

const CELL := 8.0

const MAP: Array[String] = [
	"tth.Bht.hh.thht",
	".#############.",
	"h#hFht.#.SS.h#h",
	"t#tt..C#.SS.t#t",
	"h#h...t#t..hh#h",
	"t#hH.t###.hFh#t",
	".###y##o######.",
	"h#hh.t###t.C.#h",
	"t#.t.t...t.t.#t",
	"~=~~~~~~~~~~~=~",
	"h#tt.hh.t.hh.#h",
	"t#hBh.th.C.hF#t",
	".#####y#######.",
	"tth.hh.t.hht.tt",
]

## Order to try when a spot has several road neighbours: N, S, W, E.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
const FIRE_OFFSET := {"house": 3.3, "bin": 2.2, "hay": 2.0}
const CAT_TREE_OFFSET := 2.0
const HYDRANT_OFFSET := 3.3
const TREE_R := 0.9
const ISLAND_R := 3.2

var cols := 0
var rows := 0
var size := Vector2.ZERO
## [{cell, kind, facing: Vector2i, pos: Vector2, park: Vector2i}]
var fires: Array[Dictionary] = []
## [{cell, facing, pos, park}]
var cats: Array[Dictionary] = []
## [{cell, pos}]
var hydrants: Array[Dictionary] = []
## {cells: Rect2i, rect: Rect2 (ground), door_cell: Vector2i, bay: Vector2, bay_rect: Rect2, door_x: Vector2}
var station := {}
## Houses (h and F): [{cell, pos, w, d, height, seed}]
var houses: Array[Dictionary] = []
## Trees (t and C): [{cell, pos, pine: bool, seed, cat: bool}]
var trees: Array[Dictionary] = []
var islands: Array[Vector2] = []
## Grass cells next to a road, where townsfolk stand: [{cell, pos, facing}]
var kerbs: Array[Dictionary] = []

## Solids: {kind: "circle"|"box", pos: Vector2 (circle), r: float, rect: Rect2 (box), tag: String}
var solids: Array[Dictionary] = []
## cell -> Array[int] indices into solids (each solid listed in every cell it touches)
var _solid_grid := {}


func _init(lines: Array[String] = MAP) -> void:
	rows = lines.size()
	cols = lines[0].length()
	_lines = lines
	size = Vector2(cols, rows) * CELL
	_parse()


var _lines: Array[String] = []


# ---------------------------------------------------------------- cells

func char_at(c: Vector2i) -> String:
	if c.x < 0 or c.y < 0 or c.x >= cols or c.y >= rows:
		return ""
	return _lines[c.y][c.x]


func is_road(c: Vector2i) -> bool:
	return char_at(c) in ["#", "=", "y"]


func cell_center(c: Vector2i) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * CELL


func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


func in_bounds(p: Vector2) -> bool:
	return p.x >= 0.0 and p.y >= 0.0 and p.x < size.x and p.y < size.y


func road_neighbour(c: Vector2i) -> Vector2i:
	for d in DIRS:
		if is_road(c + d):
			return d
	return Vector2i.ZERO


## Directions from road cell c that continue on road.
func road_dirs(c: Vector2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d in DIRS:
		if is_road(c + d):
			out.append(d)
	return out


# ---------------------------------------------------------------- parse

func _parse() -> void:
	var s_cells: Array[Vector2i] = []
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			var ch := char_at(cell)
			var rng := RandomNumberGenerator.new()
			rng.seed = hash(cell) + 17
			match ch:
				"h", "F":
					var facing := road_neighbour(cell)
					houses.append({"cell": cell, "pos": cell_center(cell), "w": rng.randf_range(4.6, 5.6),
						"d": rng.randf_range(4.6, 5.4), "height": rng.randf_range(2.6, 3.6),
						"seed": rng.randi(), "facing": facing})
					if ch == "F":
						_add_fire(cell, "house")
				"B":
					_add_fire(cell, "bin")
				"H":
					_add_fire(cell, "hay")
				"t":
					var off := Vector2(rng.randf_range(-1.4, 1.4), rng.randf_range(-1.4, 1.4))
					trees.append({"cell": cell, "pos": cell_center(cell) + off, "pine": rng.randf() < 0.4,
						"seed": rng.randi(), "cat": false})
				"C":
					var f := road_neighbour(cell)
					var pos := cell_center(cell) + Vector2(f) * CAT_TREE_OFFSET
					cats.append({"cell": cell, "facing": f, "pos": pos, "park": cell + f})
					trees.append({"cell": cell, "pos": pos, "pine": false, "seed": rng.randi(), "cat": true})
				"y":
					for d in DIRS:
						if not is_road(cell + d):
							hydrants.append({"cell": cell, "pos": cell_center(cell) + Vector2(d) * HYDRANT_OFFSET})
							break
				"o":
					islands.append(cell_center(cell))
				"S":
					s_cells.append(cell)
				".":
					var f2 := road_neighbour(cell)
					if f2 != Vector2i.ZERO:
						kerbs.append({"cell": cell, "facing": f2, "pos": cell_center(cell) + Vector2(f2) * 2.8})
	if not s_cells.is_empty():
		_parse_station(s_cells)
	_build_solids()


func _add_fire(cell: Vector2i, kind: String) -> void:
	var f := road_neighbour(cell)
	fires.append({"cell": cell, "kind": kind, "facing": f, "park": cell + f,
		"pos": cell_center(cell) + Vector2(f) * FIRE_OFFSET[kind]})


func _parse_station(cells: Array[Vector2i]) -> void:
	var lo := cells[0]
	var hi := cells[0]
	for c in cells:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	var rect := Rect2(Vector2(lo) * CELL, Vector2(hi - lo + Vector2i.ONE) * CELL)
	# The door faces the road above the station (the map keeps it that way).
	var door_cell := Vector2i((lo.x + hi.x + 1) / 2, lo.y - 1)
	var cx := rect.position.x + rect.size.x / 2.0
	var bay := Vector2(cx, rect.position.y + rect.size.y * 0.5)
	station = {
		"cells": Rect2i(lo, hi - lo + Vector2i.ONE), "rect": rect, "door_cell": door_cell,
		"bay": bay, "bay_rect": Rect2(cx - 4.0, rect.position.y + 2.0, 8.0, rect.size.y - 4.5),
		"door_x": Vector2(cx - 3.6, cx + 3.6), "door_z": rect.position.y + 0.9,
	}


# ---------------------------------------------------------------- solids

func _build_solids() -> void:
	for hs in houses:
		var r := Rect2(hs.pos - Vector2(hs.w, hs.d) / 2.0, Vector2(hs.w, hs.d))
		_add_box(r, "house")
	for tr in trees:
		_add_circle(tr.pos, TREE_R, "tree")
	for f in fires:
		if f.kind == "bin":
			_add_box(Rect2(f.pos - Vector2(0.6, 0.6), Vector2(1.2, 1.2)), "bin")
		elif f.kind == "hay":
			_add_circle(f.pos, 1.2, "hay")
	for p in islands:
		_add_circle(p, ISLAND_R, "island")
	for r in rows:
		for c in cols:
			if char_at(Vector2i(c, r)) == "~":
				_add_box(Rect2(Vector2(c, r) * CELL, Vector2(CELL, CELL)), "water")
	if not station.is_empty():
		var sr: Rect2 = station.rect
		var x0 := sr.position.x + 0.4
		var x1 := sr.end.x - 0.4
		var z0 := sr.position.y + 0.4
		var z1 := sr.end.y - 0.4
		var dx: Vector2 = station.door_x
		_add_box(Rect2(x0, z0, 2.4, z1 - z0), "station")            # west wall
		_add_box(Rect2(x1 - 2.4, z0, 2.4, z1 - z0), "station")      # east wall
		_add_box(Rect2(x0, z1 - 2.0, x1 - x0, 2.0), "station")      # back wall
		_add_box(Rect2(x0, z0, dx.x - x0, 1.2), "station")          # front wall, left of the door
		_add_box(Rect2(dx.y, z0, x1 - dx.y, 1.2), "station")        # front wall, right of the door


func _add_box(r: Rect2, tag: String) -> void:
	solids.append({"kind": "box", "rect": r, "tag": tag})
	_index(solids.size() - 1, r)


func _add_circle(p: Vector2, r: float, tag: String) -> void:
	solids.append({"kind": "circle", "pos": p, "r": r, "tag": tag})
	_index(solids.size() - 1, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0))


func _index(i: int, r: Rect2) -> void:
	var a := cell_of(r.position)
	var b := cell_of(r.end - Vector2(0.001, 0.001))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			var k := Vector2i(x, y)
			if not _solid_grid.has(k):
				_solid_grid[k] = []
			_solid_grid[k].append(i)


## Solids that may touch a circle at p with radius r.
func solids_near(p: Vector2, r: float) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var seen := {}
	var a := cell_of(p - Vector2(r, r))
	var b := cell_of(p + Vector2(r, r))
	for y in range(a.y, b.y + 1):
		for x in range(a.x, b.x + 1):
			for i in _solid_grid.get(Vector2i(x, y), []):
				if not seen.has(i):
					seen[i] = true
					out.append(solids[i])
	return out


## Push-out vector for a circle (p, r) against one solid; ZERO when apart.
static func push_out(p: Vector2, r: float, s: Dictionary) -> Vector2:
	if s.kind == "circle":
		var d: Vector2 = p - s.pos
		var min_d: float = r + s.r
		var len := d.length()
		if len >= min_d:
			return Vector2.ZERO
		if len < 0.0001:
			return Vector2(min_d, 0)
		return d / len * (min_d - len)
	var rect: Rect2 = s.rect
	var q := Vector2(clampf(p.x, rect.position.x, rect.end.x), clampf(p.y, rect.position.y, rect.end.y))
	var d2 := p - q
	var l2 := d2.length()
	if l2 > 0.0001:
		return Vector2.ZERO if l2 >= r else d2 / l2 * (r - l2)
	# Centre inside the box: leave through the nearest side.
	var outs := [
		Vector2(rect.position.x - r - p.x, 0), Vector2(rect.end.x + r - p.x, 0),
		Vector2(0, rect.position.y - r - p.y), Vector2(0, rect.end.y + r - p.y),
	]
	var best: Vector2 = outs[0]
	for o in outs:
		if o.length() < best.length():
			best = o
	return best


# ---------------------------------------------------------------- roads

## Breadth-first path over road cells, from the road cell nearest `from` to
## `to` (a road cell). Returns cell centres (the start cell excluded).
func path(from: Vector2, to: Vector2i) -> Array[Vector2]:
	var start := nearest_road_cell(from)
	var out: Array[Vector2] = []
	if start == to:
		out.append(cell_center(to))
		return out
	var prev := {start: start}
	var queue: Array[Vector2i] = [start]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == to:
			break
		for d in DIRS:
			var n := c + d
			if is_road(n) and not prev.has(n):
				prev[n] = c
				queue.append(n)
	if not prev.has(to):
		return out
	var c2 := to
	while c2 != start:
		out.push_front(cell_center(c2))
		c2 = prev[c2]
	return out


## Number of road steps between two road cells (-1 when unreachable).
func road_distance(a: Vector2i, b: Vector2i) -> int:
	var dist := {a: 0}
	var queue: Array[Vector2i] = [a]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		if c == b:
			return dist[c]
		for d in DIRS:
			var n := c + d
			if is_road(n) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return -1


func nearest_road_cell(p: Vector2) -> Vector2i:
	var here := cell_of(p)
	if is_road(here):
		return here
	var best := Vector2i(-1, -1)
	var best_d := INF
	for r in rows:
		for c in cols:
			var cell := Vector2i(c, r)
			if is_road(cell):
				var d := cell_center(cell).distance_squared_to(p)
				if d < best_d:
					best_d = d
					best = cell
	return best


## Fire order: greedy nearest by road distance, starting at the station door.
func fire_order() -> Array[int]:
	var order: Array[int] = []
	var left: Array[int] = []
	for i in fires.size():
		left.append(i)
	var at: Vector2i = station.door_cell if not station.is_empty() else nearest_road_cell(size / 2.0)
	while not left.is_empty():
		var best := left[0]
		var best_d := 1 << 30
		for i in left:
			var d := road_distance(at, fires[i].park)
			if d >= 0 and d < best_d:
				best_d = d
				best = i
		order.append(best)
		left.erase(best)
		at = fires[best].park
	return order
