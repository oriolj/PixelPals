extends RefCounted
## The digger as an axis-aligned box swept against the terrain grid, one
## pixel at a time per axis (no physics bodies: nothing to rebuild per dig).
##
## Driving into dirt digs it (slowly: DIG_SPEED instead of DRIVE_SPEED);
## rock stops it (a "donk"); the field's edges clamp it. It can never get
## stuck: stuck_step() clears a pocket after STUCK_SECONDS boxed in.

const Grid := preload("res://scripts/dig/terrain_grid.gd")

const SIZE := Vector2(24, 20)
const DRIVE_SPEED := 70.0
const DIG_SPEED := 26.0
const STUCK_SECONDS := 2.0
const DEADZONE := 0.25
const DIG_PIXEL_COST := Grid.CELL / DIG_SPEED - (Grid.CELL - 1) / DRIVE_SPEED

var pos := Vector2(100, 12)
## Last 4-direction the digger drove in (the driver's small scoop goes this way).
var facing := Vector2i.RIGHT
var stuck_t := 0.0
## Time saved up toward the next digging pixel, per axis (a chomp waits until paid).
var _carry := [0.0, 0.0]
var _carry_sign := [0.0, 0.0]


func rect_at(p: Vector2) -> Rect2:
	return Rect2(p - SIZE * 0.5, SIZE)


func rect() -> Rect2:
	return rect_at(pos)


func cells(grid: Grid) -> Rect2i:
	return grid.cells_of_rect(rect())


## The box may go anywhere inside the rock border, from the grass line down.
static func field_rect(grid: Grid) -> Rect2:
	var b := float(Grid.BORDER * Grid.CELL)
	return Rect2(b, 0.0, grid.w * Grid.CELL - 2.0 * b, grid.h * Grid.CELL - b)


func clamp_pos(p: Vector2, grid: Grid) -> Vector2:
	var f := field_rect(grid)
	return Vector2(clampf(p.x, f.position.x + SIZE.x * 0.5, f.end.x - SIZE.x * 0.5),
		clampf(p.y, f.position.y + SIZE.y * 0.5, f.end.y - SIZE.y * 0.5))


## Drive with an analog stick for dt seconds.
## Returns {"moved": px, "dug": cells, "digging": bool, "rock": bool}.
func drive(input: Vector2, dt: float, grid: Grid) -> Dictionary:
	var res := {"moved": 0.0, "dug": 0, "digging": false, "rock": false}
	if input.length() < DEADZONE:
		_carry = [0.0, 0.0]
		return res
	input = input.limit_length(1.0)
	if absf(input.x) >= absf(input.y):
		facing = Vector2i(int(signf(input.x)), 0)
	else:
		facing = Vector2i(0, int(signf(input.y)))
	for axis in 2:
		var d: float = input[axis]
		if absf(d) < 0.05:
			_carry[axis] = 0.0
			continue
		if signf(d) != _carry_sign[axis]:
			_carry[axis] = 0.0  # turning round: the saved-up chomp was for the other way
		_carry_sign[axis] = signf(d)
		var budget: float = absf(d) * dt + _carry[axis]
		_carry[axis] = 0.0
		_axis_move(axis, signf(d), budget, grid, res)
	return res


## Moves one pixel at a time on one axis, spending `budget` seconds: a pixel
## of open tunnel costs 1/DRIVE_SPEED, a pixel that digs costs 1/DIG_SPEED.
## Rock, and the field's sides and bottom (which are rock), stop it.
func _axis_move(axis: int, sgn: float, budget: float, grid: Grid, res: Dictionary) -> void:
	while budget > 0.00001:
		var t := pos
		t[axis] += sgn
		t = clamp_pos(t, grid)
		if t.is_equal_approx(pos):
			# Against the field's edge: the sides and bottom are rock, the top is the grass.
			if not (axis == 1 and sgn < 0.0):
				res.rock = true
			return
		var r := grid.cells_of_rect(rect_at(t))
		if grid.any_rock_in(r):
			res.rock = true
			return
		var digs := grid.any_dirt_in(r)
		# The pixel that digs clears a whole cell column; charge it for the
		# cell so the average speed through dirt is DIG_SPEED (a chomp per cell).
		var cost := DIG_PIXEL_COST if digs else 1.0 / DRIVE_SPEED
		var step := pos.distance_to(t)
		if budget < cost * step:
			if digs:
				# Save up for the chomp; the cell opens once it is paid for.
				_carry[axis] = budget
				res.digging = true
				return
			# Not enough time for the whole pixel: a partial step.
			t = pos + (t - pos) * (budget / (cost * step))
			r = grid.cells_of_rect(rect_at(t))
			budget = 0.0
		else:
			budget -= cost * step
		if digs:
			res.digging = true
			res.dug += grid.dig_rect(r)
		res.moved += pos.distance_to(t)
		pos = t


## Call every frame. When the box has had no open cell around it for
## STUCK_SECONDS, clears the box plus a one-cell ring and returns true.
func stuck_step(dt: float, grid: Grid) -> bool:
	var r := cells(grid)
	if grid.free_around(r):
		stuck_t = 0.0
		return false
	stuck_t += dt
	if stuck_t < STUCK_SECONDS:
		return false
	stuck_t = 0.0
	grid.dig_rect(r.grow(1))
	return true
