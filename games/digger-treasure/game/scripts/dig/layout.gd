extends RefCounted
## Where things are buried. Fixed spots, shuffled per run: which twelve of
## the sixteen treasure spots are used and which treasure sits in each.
## Cells are top-left corners on the 240x80 grid.

const Grid := preload("res://scripts/dig/terrain_grid.gd")

const TREASURE_KINDS := ["treasure_chest", "crown", "dino_egg", "gems", "coins", "toy_robot"]
const FIND_KINDS := ["worm", "snail", "bone", "fossil", "mole"]
const TREASURE_CELLS := 4          # a treasure is 4x4 cells (its 16x16 sprite)
const FIND_CELLS := 3

## Sixteen candidate spots across the three screens and both depths.
const TREASURE_SPOTS: Array[Vector2i] = [
	Vector2i(38, 6), Vector2i(60, 16), Vector2i(84, 5), Vector2i(106, 22), Vector2i(130, 8),
	Vector2i(152, 30), Vector2i(178, 12), Vector2i(202, 24), Vector2i(222, 7), Vector2i(42, 38),
	Vector2i(88, 50), Vector2i(140, 62), Vector2i(190, 48), Vector2i(222, 64), Vector2i(58, 66),
	Vector2i(116, 40),
]
## Demo mode: all twelve within reach of the start, so pops happen on camera.
const DEMO_SPOTS: Array[Vector2i] = [
	Vector2i(38, 4), Vector2i(50, 9), Vector2i(34, 12), Vector2i(44, 16), Vector2i(58, 14),
	Vector2i(28, 18), Vector2i(66, 6), Vector2i(54, 20), Vector2i(40, 22), Vector2i(70, 16),
	Vector2i(24, 8), Vector2i(62, 24),
]
const FIND_SPOTS: Array[Vector2i] = [
	Vector2i(18, 10), Vector2i(48, 4), Vector2i(72, 12), Vector2i(96, 14), Vector2i(118, 4),
	Vector2i(142, 18), Vector2i(166, 6), Vector2i(188, 30), Vector2i(212, 16), Vector2i(30, 28),
	Vector2i(66, 34), Vector2i(100, 30), Vector2i(128, 46), Vector2i(160, 40), Vector2i(210, 40),
	Vector2i(20, 50), Vector2i(76, 60), Vector2i(104, 68), Vector2i(172, 64), Vector2i(200, 70),
	Vector2i(8, 70), Vector2i(150, 72), Vector2i(226, 30), Vector2i(48, 52),
]
## Little caves (centre cell, radius x, radius y): open pockets with roots
## that make the field look lived in and let glints peek through early.
const CAVES := [
	[Vector2i(72, 26), 5, 3], [Vector2i(160, 20), 6, 3], [Vector2i(30, 60), 5, 3],
	[Vector2i(120, 56), 7, 3], [Vector2i(206, 56), 5, 4], [Vector2i(96, 72), 4, 2],
]
## The pocket the digger starts in, just under the grass.
const START_POCKET := Rect2i(20, 0, 10, 6)
const START_POS := Vector2(100, 12)


## Twelve {kind, cell} treasures. `demo` puts them near the start.
static func treasures(rng: RandomNumberGenerator, demo := false) -> Array[Dictionary]:
	var spots: Array[Vector2i] = []
	spots.assign(DEMO_SPOTS if demo else TREASURE_SPOTS)
	_shuffle(spots, rng)
	var kinds: Array[String] = []
	for i in 12:
		kinds.append(TREASURE_KINDS[i % TREASURE_KINDS.size()])
	_shuffle(kinds, rng)
	var out: Array[Dictionary] = []
	for i in 12:
		out.append({"kind": kinds[i], "cell": spots[i]})
	return out


static func finds(rng: RandomNumberGenerator) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var kinds: Array[String] = []
	for i in FIND_SPOTS.size():
		kinds.append(FIND_KINDS[i % FIND_KINDS.size()])
	_shuffle(kinds, rng)
	for i in FIND_SPOTS.size():
		out.append({"kind": kinds[i], "cell": FIND_SPOTS[i]})
	return out


## Carves caves and the start pocket, then refills the cells of every
## buried thing (and a one-cell ring) so nothing starts exposed.
static func carve(grid: Grid, buried: Array[Rect2i]) -> void:
	for cave in CAVES:
		var c: Vector2i = cave[0]
		var rx: int = cave[1]
		var ry: int = cave[2]
		for dy in range(-ry, ry + 1):
			for dx in range(-rx, rx + 1):
				var e := float(dx * dx) / float(rx * rx) + float(dy * dy) / float(ry * ry)
				# ragged edges: a hashed wobble, deterministic
				if e <= 1.0 - 0.25 * float(absi(hash(Vector2i(c.x + dx, c.y + dy))) % 3) / 2.0:
					grid.dig_cell(c + Vector2i(dx, dy))
	grid.dig_rect(START_POCKET)
	for r in buried:
		var g := r.grow(1)
		for y in range(g.position.y, g.end.y):
			for x in range(g.position.x, g.end.x):
				var cell := Vector2i(x, y)
				if grid.in_bounds(cell) and grid.get_cell(cell) == Grid.AIR and not START_POCKET.has_point(cell):
					grid.set_cell(cell, grid.band_at(x, y))


static func cells_of(cell: Vector2i, size: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for dy in size:
		for dx in size:
			out.append(cell + Vector2i(dx, dy))
	return out


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
