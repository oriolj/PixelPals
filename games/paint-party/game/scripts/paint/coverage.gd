extends RefCounted
## How much of the canvas is painted, per cell of a 16x9 grid, tracked from
## the dab/stamp/splat positions (no GPU readback needed).
##
## Internally a 64x36 grid of fine cells (30x30 canvas px) is marked painted
## when a disc reaches its centre, so overlapping strokes are not counted
## twice. A coarse cell (120x120) = 4x4 fine cells; its coverage is the
## painted fraction of those 16.

const CANVAS := Vector2(1920, 1080)
const COLS := 16
const ROWS := 9
const FINE := 4                     # fine cells per coarse cell, per axis
const FCOLS := COLS * FINE
const FROWS := ROWS * FINE
const FINE_PX := 30.0               # CANVAS.x / FCOLS
const CELL_PX := 120.0

var _fine := PackedByteArray()


func _init() -> void:
	clear()


func clear() -> void:
	_fine.resize(FCOLS * FROWS)
	_fine.fill(0)


## Marks every fine cell whose centre lies within the disc (at least the cell
## under the centre, so thin brushes count too).
func mark_disc(center: Vector2, radius: float) -> void:
	var reach := radius + FINE_PX * 0.25
	var x0 := clampi(int((center.x - reach) / FINE_PX), 0, FCOLS - 1)
	var x1 := clampi(int((center.x + reach) / FINE_PX), 0, FCOLS - 1)
	var y0 := clampi(int((center.y - reach) / FINE_PX), 0, FROWS - 1)
	var y1 := clampi(int((center.y + reach) / FINE_PX), 0, FROWS - 1)
	for fy in range(y0, y1 + 1):
		for fx in range(x0, x1 + 1):
			var c := Vector2((fx + 0.5) * FINE_PX, (fy + 0.5) * FINE_PX)
			if c.distance_to(center) <= reach:
				_fine[fy * FCOLS + fx] = 1
	var cx := clampi(int(center.x / FINE_PX), 0, FCOLS - 1)
	var cy := clampi(int(center.y / FINE_PX), 0, FROWS - 1)
	_fine[cy * FCOLS + cx] = 1


## Painted fraction (0..1) of coarse cell (col, row).
func cell(col: int, row: int) -> float:
	var n := 0
	for fy in range(row * FINE, row * FINE + FINE):
		for fx in range(col * FINE, col * FINE + FINE):
			n += _fine[fy * FCOLS + fx]
	return float(n) / float(FINE * FINE)


## Painted fraction of the whole canvas.
func total() -> float:
	var n := 0
	for v in _fine:
		n += v
	return float(n) / float(_fine.size())


## Average coverage of the up to 8 neighbours of a cell.
func neighbours(col: int, row: int) -> float:
	var sum := 0.0
	var k := 0
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var c := col + dx
			var r := row + dy
			if c < 0 or r < 0 or c >= COLS or r >= ROWS:
				continue
			sum += cell(c, r)
			k += 1
	return sum / float(maxi(k, 1))


## The coarse cell with the lowest coverage; ties are broken at random, but
## cells nearer the middle of the canvas win over the border ones a little.
func least_covered(rng: RandomNumberGenerator) -> Vector2i:
	var best := INF
	var picks: Array[Vector2i] = []
	for row in ROWS:
		for col in COLS:
			var v := cell(col, row)
			if v < best - 0.001:
				best = v
				picks = [Vector2i(col, row)]
			elif absf(v - best) <= 0.001:
				picks.append(Vector2i(col, row))
	# Prefer inner cells among ties (a splat half off the paper is a waste).
	var inner: Array[Vector2i] = []
	for p in picks:
		if p.x > 0 and p.y > 0 and p.x < COLS - 1 and p.y < ROWS - 1:
			inner.append(p)
	var pool := inner if not inner.is_empty() else picks
	return pool[rng.randi() % pool.size()]


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * CELL_PX, (c.y + 0.5) * CELL_PX)


static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(clampi(int(p.x / CELL_PX), 0, COLS - 1), clampi(int(p.y / CELL_PX), 0, ROWS - 1))
