extends GutTest
## The terrain grid as pure logic.

const Grid := preload("res://scripts/dig/terrain_grid.gd")

var g: Grid


func before_each() -> void:
	g = Grid.new()


func test_field_has_depth_bands_and_a_rock_border() -> void:
	assert_eq(g.get_cell(Vector2i(100, 0)), Grid.TOPSOIL)
	assert_eq(g.get_cell(Vector2i(100, 35)), Grid.CLAY)
	assert_eq(g.get_cell(Vector2i(100, 70)), Grid.DEEP)
	assert_eq(g.get_cell(Vector2i(0, 40)), Grid.ROCK, "left edge")
	assert_eq(g.get_cell(Vector2i(Grid.W - 1, 40)), Grid.ROCK, "right edge")
	assert_eq(g.get_cell(Vector2i(100, Grid.H - 1)), Grid.ROCK, "bottom edge")
	assert_eq(g.get_cell(Vector2i(100, -1)), Grid.AIR, "the sky above the field is open")
	assert_eq(g.get_cell(Vector2i(-5, 10)), Grid.ROCK, "outside the sides is solid")


func test_dig_circle_clears_only_cells_inside_the_radius() -> void:
	var c := Vector2i(100, 40)
	var r := 7.0
	var n := g.dig_circle(c, r)
	var inside := 0
	for dy in range(-10, 11):
		for dx in range(-10, 11):
			var cell := c + Vector2i(dx, dy)
			var d2 := dx * dx + dy * dy
			if d2 <= r * r:
				inside += 1
				assert_eq(g.get_cell(cell), Grid.AIR, "inside %s" % cell)
			else:
				assert_ne(g.get_cell(cell), Grid.AIR, "outside %s stays dirt" % cell)
	assert_eq(n, inside, "counts exactly the dug cells")
	assert_eq(g.dig_circle(c, r), 0, "digging air again digs nothing")


func test_rock_cells_are_never_dug() -> void:
	var n := g.dig_circle(Vector2i(1, 40), 6.0)
	assert_gt(n, 0, "the dirt next to the border is dug")
	for y in range(34, 47):
		for x in 2:
			assert_eq(g.get_cell(Vector2i(x, y)), Grid.ROCK)
	g.dig_rect(Rect2i(0, Grid.H - 4, Grid.W, 4))
	for x in Grid.W:
		assert_eq(g.get_cell(Vector2i(x, Grid.H - 1)), Grid.ROCK)
	assert_false(g.dig_cell(Vector2i(0, 0)), "rock refuses a single dig too")


func test_dirty_rect_covers_only_what_changed() -> void:
	g.take_dirty()
	assert_eq(g.dirty.size, Vector2i.ZERO)
	g.dig_circle(Vector2i(50, 30), 3.0)
	var d := g.take_dirty()
	assert_eq(d, Rect2i(47, 27, 7, 7))
	g.dig_cell(Vector2i(10, 10))
	g.dig_cell(Vector2i(12, 14))
	assert_eq(g.take_dirty(), Rect2i(10, 10, 3, 5), "merged batch")


func test_treasure_is_found_when_any_cell_is_exposed() -> void:
	var cells: Array[Vector2i] = []
	for dy in 4:
		for dx in 4:
			cells.append(Vector2i(60 + dx, 30 + dy))
	assert_false(g.exposed(cells), "buried")
	g.dig_cell(Vector2i(59, 31))
	assert_false(g.exposed(cells), "a neighbour dug is not enough")
	g.dig_cell(Vector2i(63, 33))
	assert_true(g.exposed(cells), "one corner cell open is enough")


func test_dirt_depth_measures_dirt_to_the_nearest_tunnel() -> void:
	assert_eq(g.dirt_depth(Vector2i(100, 5), 12), 6, "5 rows of topsoil above, sky at y=-1")
	assert_eq(g.dirt_depth(Vector2i(100, 40), 12), 13, "deep and closed: over the limit")
	g.dig_cell(Vector2i(104, 40))
	assert_eq(g.dirt_depth(Vector2i(100, 40), 12), 4)


func test_cells_of_rect_ignores_edges_on_cell_lines() -> void:
	assert_eq(Grid.cells_of_rect(Rect2(8, 8, 8, 8)), Rect2i(2, 2, 2, 2))
	assert_eq(Grid.cells_of_rect(Rect2(8.5, 8, 8, 8)), Rect2i(2, 2, 3, 2))
