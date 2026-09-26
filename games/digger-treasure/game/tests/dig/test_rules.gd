extends GutTest
## Pure rules and the level layout.

const Rules := preload("res://scripts/dig/rules.gd")
const Layout := preload("res://scripts/dig/layout.gd")
const Grid := preload("res://scripts/dig/terrain_grid.gd")

const FOUR: Array[Vector2i] = [Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN]


func test_scoop_direction_is_one_of_four() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var keep := Vector2i.DOWN
	for i in 500:
		var v := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
		keep = Rules.snap4(v, keep)
		assert_has(FOUR, keep, "stick %s" % v)
	assert_eq(Rules.snap4(Vector2(0.05, 0.1), Vector2i.LEFT), Vector2i.LEFT, "idle keeps the aim")
	assert_eq(Rules.snap4(Vector2(0.7, 0.7), Vector2i.UP), Vector2i.RIGHT, "a perfect diagonal picks x")


func test_scoop_rect_is_a_square_right_next_to_the_body() -> void:
	var body := Rect2i(20, 10, 6, 5)
	assert_eq(Rules.scoop_rect(body, Vector2i.RIGHT, 5), Rect2i(26, 10, 5, 5))
	assert_eq(Rules.scoop_rect(body, Vector2i.LEFT, 5), Rect2i(15, 10, 5, 5))
	assert_eq(Rules.scoop_rect(body, Vector2i.DOWN, 5), Rect2i(21, 15, 5, 5))
	assert_eq(Rules.scoop_rect(body, Vector2i.UP, 5), Rect2i(21, 5, 5, 5))
	assert_eq(Rules.scoop_rect(body, Vector2i.RIGHT, 3), Rect2i(26, 11, 3, 3))


func test_truck_frame_empty_half_full() -> void:
	assert_eq(Rules.truck_frame(0), 0)
	assert_eq(Rules.truck_frame(1), 1)
	assert_eq(Rules.truck_frame(6), 1)
	assert_eq(Rules.truck_frame(7), 2)
	assert_eq(Rules.truck_frame(12), 2)


func test_run_length_defaults_to_five_minutes() -> void:
	assert_eq(Rules.run_length(0.0), 300.0)
	assert_eq(Rules.run_length(20.0), 20.0)


func test_layout_gives_twelve_treasures_on_distinct_fixed_spots() -> void:
	for seed in [1, 2, 3]:
		var rng := RandomNumberGenerator.new()
		rng.seed = seed
		for demo in [false, true]:
			var ts := Layout.treasures(rng, demo)
			assert_eq(ts.size(), 12)
			var seen := {}
			var kinds := {}
			for t in ts:
				assert_false(seen.has(t.cell))
				seen[t.cell] = true
				assert_has(Layout.DEMO_SPOTS if demo else Layout.TREASURE_SPOTS, t.cell)
				kinds[t.kind] = kinds.get(t.kind, 0) + 1
			assert_eq(kinds.size(), 6, "all six kinds, twice each")


func test_carving_leaves_every_buried_thing_covered() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 9
	var g := Grid.new()
	var buried: Array[Rect2i] = []
	for t in Layout.treasures(rng):
		buried.append(Rect2i(t.cell, Vector2i(4, 4)))
	for f in Layout.finds(rng):
		buried.append(Rect2i(f.cell, Vector2i(3, 3)))
	Layout.carve(g, buried)
	for r in buried:
		assert_false(g.exposed(Layout.cells_of(r.position, r.size.x)), "%s starts buried" % r)
	assert_eq(g.get_cell(Layout.START_POCKET.position), Grid.AIR, "the start pocket is open")
	var caves_open := 0
	for cave in Layout.CAVES:
		if g.get_cell(cave[0]) == Grid.AIR:
			caves_open += 1
	assert_eq(caves_open, Layout.CAVES.size())
