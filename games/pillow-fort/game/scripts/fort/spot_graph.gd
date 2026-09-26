extends RefCounted
## The seeker's hop graph: each hiding spot links to its nearest neighbour in
## each of the 4 directions, precomputed from the spot positions, so the paw
## never gets stuck and every spot is reachable.
##
## Nearest "in a direction" = the smallest (along + 2 * across) among spots
## ahead of it inside a 60-degree-ish cone; when the cone is empty, any spot
## ahead counts, so a spot at the edge of a row still links onward.

const DIRS: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]

## links[i][dir] = index of the neighbour, or -1.
var links: Array[Dictionary] = []
var positions: Array[Vector2] = []


func build(points: Array) -> void:
	positions.clear()
	for p in points:
		positions.append(Vector2(p))
	links.clear()
	for i in positions.size():
		var row := {}
		for d in DIRS:
			row[d] = nearest(i, d)
		links.append(row)


## The nearest spot from spot `from` in direction `d` (or -1 at the edge).
func nearest(from: int, d: Vector2i) -> int:
	var best := -1
	var best_cost := INF
	var best_loose := -1
	var best_loose_cost := INF
	var dv := Vector2(d)
	for j in positions.size():
		if j == from:
			continue
		var delta := positions[j] - positions[from]
		var along := delta.dot(dv)
		if along <= 0.5:
			continue
		var across := absf(delta.dot(Vector2(dv.y, -dv.x)))
		var cost := along + 2.0 * across
		if across <= along * 1.2:
			if cost < best_cost:
				best_cost = cost
				best = j
		elif cost < best_loose_cost:
			best_loose_cost = cost
			best_loose = j
	return best if best != -1 else best_loose


## Where a hop from `from` in direction `d` lands (stays put at an edge).
func hop(from: int, d: Vector2i) -> int:
	if d == Vector2i.ZERO or from < 0 or from >= links.size():
		return from
	var to: int = links[from].get(d, -1)
	return from if to == -1 else to


## Spots reachable from `start` by hopping (breadth first).
func reachable(start: int) -> Array[int]:
	var seen: Array[int] = [start]
	var queue: Array[int] = [start]
	while not queue.is_empty():
		var i: int = queue.pop_front()
		for d in DIRS:
			var j: int = links[i][d]
			if j != -1 and not seen.has(j):
				seen.append(j)
				queue.append(j)
	return seen
