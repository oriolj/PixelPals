extends RefCounted
## The destructible dirt field as pure logic (no nodes, tested headless).
##
## A PackedByteArray of W x H cells, each CELL x CELL world pixels:
##   AIR (0) tunnel, TOPSOIL/CLAY/DEEP (1-3) dirt bands by depth, ROCK (9)
##   the level border, which is never dug.
## Row 0 is the top of the field, just under the grass; everything above the
## field (y < 0) counts as open sky. Every change widens `dirty` (in cells) so
## the view repaints only what was touched.
## Candidate for shared/ later (Paint Party could paint on it).

const W := 240
const H := 80
const CELL := 4
const AIR := 0
const TOPSOIL := 1
const CLAY := 2
const DEEP := 3
const ROCK := 9
const BORDER := 2          # rock cells on the left, right and bottom edges

var w := W
var h := H
var cells := PackedByteArray()
## Cells changed since the last take_dirty(); size zero when clean.
var dirty := Rect2i()
## Dirt cells dug since creation (for tests and the stress check).
var dug_total := 0


func _init(width := W, height := H) -> void:
	w = width
	h = height
	cells.resize(w * h)
	fill_default()


## Depth bands with gently wavy boundaries, rock on the border.
func fill_default() -> void:
	for y in h:
		for x in w:
			cells[y * w + x] = band_at(x, y)
	dirty = Rect2i(0, 0, w, h)


func band_at(x: int, y: int) -> int:
	if x < BORDER or x >= w - BORDER or y >= h - BORDER:
		return ROCK
	var wave1 := int(roundf(2.0 * sin(x * 0.11) + 1.5 * sin(x * 0.037 + 1.0)))
	var wave2 := int(roundf(2.5 * sin(x * 0.07 + 2.0) + 1.2 * sin(x * 0.19)))
	if y < roundi(h * 0.27) + wave1:
		return TOPSOIL
	if y < roundi(h * 0.6) + wave2:
		return CLAY
	return DEEP


# ---------------------------------------------------------------- queries

func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h


## Cell value; above the field is AIR (sky), beside or below it is ROCK.
func get_cell(c: Vector2i) -> int:
	if c.y < 0 and c.x >= 0 and c.x < w:
		return AIR
	if not in_bounds(c):
		return ROCK
	return cells[c.y * w + c.x]


func is_solid(c: Vector2i) -> bool:
	return get_cell(c) != AIR


func is_rock(c: Vector2i) -> bool:
	return get_cell(c) == ROCK


func is_dirt(c: Vector2i) -> bool:
	var v := get_cell(c)
	return v != AIR and v != ROCK


## The cell under a world position.
static func cell_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / CELL), floori(p.y / CELL))


## Centre of a cell in world pixels.
static func center_of(c: Vector2i) -> Vector2:
	return Vector2(c.x * CELL + CELL * 0.5, c.y * CELL + CELL * 0.5)


## The cells a world rectangle overlaps (edges exactly on a cell line do not count).
static func cells_of_rect(r: Rect2) -> Rect2i:
	var x0 := floori(r.position.x / CELL)
	var y0 := floori(r.position.y / CELL)
	var x1 := ceili(r.end.x / CELL) - 1
	var y1 := ceili(r.end.y / CELL) - 1
	return Rect2i(x0, y0, x1 - x0 + 1, y1 - y0 + 1)


func any_rock_in(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if get_cell(Vector2i(x, y)) == ROCK:
				return true
	return false


func any_dirt_in(r: Rect2i) -> bool:
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if is_dirt(Vector2i(x, y)):
				return true
	return false


## True if any cell of the one-cell ring around `r` is open.
func free_around(r: Rect2i) -> bool:
	var g := r.grow(1)
	for y in range(g.position.y, g.end.y):
		for x in range(g.position.x, g.end.x):
			if r.has_point(Vector2i(x, y)):
				continue
			if get_cell(Vector2i(x, y)) == AIR:
				return true
	return false


## True when any of `list` is open (a buried thing is found once any of its cells is).
func exposed(list: Array) -> bool:
	for c in list:
		if get_cell(c) == AIR:
			return true
	return false


## How many cells of dirt lie between `c` and the nearest open cell, looking
## at most `max_r` cells away (Chebyshev rings). Returns max_r + 1 when none.
func dirt_depth(c: Vector2i, max_r: int) -> int:
	if get_cell(c) == AIR:
		return 0
	for r in range(1, max_r + 1):
		for dx in range(-r, r + 1):
			if get_cell(c + Vector2i(dx, -r)) == AIR or get_cell(c + Vector2i(dx, r)) == AIR:
				return r
		for dy in range(-r + 1, r):
			if get_cell(c + Vector2i(-r, dy)) == AIR or get_cell(c + Vector2i(r, dy)) == AIR:
				return r
	return max_r + 1


# ---------------------------------------------------------------- digging

func set_cell(c: Vector2i, v: int) -> void:
	if not in_bounds(c):
		return
	var i := c.y * w + c.x
	if cells[i] == v:
		return
	cells[i] = v
	_mark(Rect2i(c, Vector2i.ONE))


## Clears one dirt cell. Rock and air are left alone. Returns true if dug.
func dig_cell(c: Vector2i) -> bool:
	if not in_bounds(c):
		return false
	var i := c.y * w + c.x
	var v := cells[i]
	if v == AIR or v == ROCK:
		return false
	cells[i] = AIR
	dug_total += 1
	_mark(Rect2i(c, Vector2i.ONE))
	return true


## Clears every dirt cell whose distance to `center` is at most `r` cells.
## Returns how many cells were dug.
func dig_circle(center: Vector2i, r: float) -> int:
	var n := 0
	var ri := ceili(r)
	var r2 := r * r
	for dy in range(-ri, ri + 1):
		for dx in range(-ri, ri + 1):
			if dx * dx + dy * dy <= r2 and dig_cell(center + Vector2i(dx, dy)):
				n += 1
	return n


func dig_rect(r: Rect2i) -> int:
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if dig_cell(Vector2i(x, y)):
				n += 1
	return n


## Hand the dirty rectangle to the view and start a new batch.
func take_dirty() -> Rect2i:
	var d := dirty
	dirty = Rect2i()
	return d


func _mark(r: Rect2i) -> void:
	dirty = r if dirty.size == Vector2i.ZERO else dirty.merge(r)
