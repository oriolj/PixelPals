extends GutTest
## The digger's box against the grid: auto-dig, rock, field edges, never stuck.

const Grid := preload("res://scripts/dig/terrain_grid.gd")
const Body := preload("res://scripts/dig/digger_body.gd")
const DT := 1.0 / 30.0

var g: Grid
var b: Body


func before_each() -> void:
	g = Grid.new()
	b = Body.new()
	b.pos = Vector2(400, 150)
	g.dig_rect(g.cells_of_rect(b.rect()))


func _drive(v: Vector2, seconds: float) -> Dictionary:
	var total := {"moved": 0.0, "dug": 0, "rock": false}
	for i in int(seconds / DT):
		var r := b.drive(v, DT, g)
		total.moved += r.moved
		total.dug += r.dug
		total.rock = total.rock or r.rock
	return total


func test_driving_into_dirt_digs_a_tunnel_slowly() -> void:
	var r := _drive(Vector2.RIGHT, 1.0)
	assert_gt(r.dug, 0)
	assert_almost_eq(r.moved, Body.DIG_SPEED, float(Grid.CELL), "dig speed through dirt (to a cell)")
	for c in _cells(g.cells_of_rect(b.rect())):
		assert_eq(g.get_cell(c), Grid.AIR, "the box stands in its own tunnel")
	var back := _drive(Vector2.LEFT, 0.3)
	assert_almost_eq(back.moved, Body.DRIVE_SPEED * 0.3, 2.0, "open tunnel: full speed")


func test_digger_cannot_leave_the_field() -> void:
	var field := Body.field_rect(g)
	for v in [Vector2.LEFT, Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2(-1, -1).normalized()]:
		b.pos = Vector2(400, 150)
		# Clear a long corridor so it drives at full speed to every edge.
		g.dig_rect(Rect2i(0, 0, Grid.W, Grid.H))
		_drive(v, 20.0)
		var r := b.rect()
		assert_true(field.encloses(r), "%s: %s inside %s" % [v, r, field])
		for c in _cells(g.cells_of_rect(r)):
			assert_ne(g.get_cell(c), Grid.ROCK, "never inside rock")


func test_rock_stops_it_and_reports_a_bump() -> void:
	b.pos = Vector2(40, 150)
	g.dig_rect(Rect2i(0, 30, 20, 20))
	var r := _drive(Vector2.LEFT, 2.0)
	assert_true(r.rock)
	assert_eq(b.rect().position.x, float(Grid.BORDER * Grid.CELL), "flush against the rock border")


func test_stuck_digger_gets_a_free_space_after_two_seconds() -> void:
	# Bury the digger completely: box and ring all dirt.
	g = Grid.new()
	b.pos = Vector2(400, 150)
	var box := g.cells_of_rect(b.rect())
	assert_false(g.free_around(box))
	var freed_at := -1.0
	var t := 0.0
	while t < 3.0:
		t += DT
		if b.stuck_step(DT, g):
			freed_at = t
			break
	assert_almost_eq(freed_at, Body.STUCK_SECONDS, DT * 1.5, "freed after two seconds")
	for c in _cells(box.grow(1)):
		assert_eq(g.get_cell(c), Grid.AIR, "a pocket around the digger")
	assert_true(g.free_around(box))
	assert_false(b.stuck_step(DT, g), "not stuck any more")


func test_facing_follows_the_dominant_stick_axis() -> void:
	b.drive(Vector2(0.3, -0.9), DT, g)
	assert_eq(b.facing, Vector2i.UP)
	b.drive(Vector2(-0.8, 0.2), DT, g)
	assert_eq(b.facing, Vector2i.LEFT)
	b.drive(Vector2(0.1, 0.1), DT, g)
	assert_eq(b.facing, Vector2i.LEFT, "the deadzone keeps the last facing")


func _cells(r: Rect2i) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			out.append(Vector2i(x, y))
	return out
