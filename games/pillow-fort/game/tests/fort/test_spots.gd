extends GutTest
## The seeker's spot graph over the real bedroom layout.

const SpotGraph := preload("res://scripts/fort/spot_graph.gd")
const Layout := preload("res://scripts/fort/room_layout.gd")

var graph: SpotGraph


func before_each() -> void:
	graph = SpotGraph.new()
	var pts := []
	for s in Layout.SPOTS:
		pts.append(s.pos)
	graph.build(pts)


func test_there_are_fourteen_spots_with_a_known_kind() -> void:
	assert_eq(Layout.SPOTS.size(), 14)
	for s in Layout.SPOTS:
		assert_true(["pillow_a", "pillow_b", "blanket_fold", "box", "curtain", "bed_edge"].has(s.kind))
		assert_true(s.pos.x > 0 and s.pos.x < 320 and s.pos.y > 0 and s.pos.y < 180)


func test_every_spot_is_reachable_through_the_spot_graph() -> void:
	for i in Layout.SPOTS.size():
		assert_eq(graph.reachable(i).size(), Layout.SPOTS.size(), "from spot %d" % i)


func test_dir4_hop_moves_to_the_nearest_spot_in_that_direction() -> void:
	var g := SpotGraph.new()
	# A plus shape with decoys: the nearer spot in the direction wins, a spot
	# far off to the side does not.
	g.build([Vector2(100, 100), Vector2(130, 100), Vector2(180, 100), Vector2(120, 160),
		Vector2(100, 70), Vector2(60, 104), Vector2(100, 140)])
	assert_eq(g.hop(0, Vector2i.RIGHT), 1)
	assert_eq(g.hop(1, Vector2i.RIGHT), 2)
	assert_eq(g.hop(0, Vector2i.UP), 4)
	assert_eq(g.hop(0, Vector2i.LEFT), 5)
	assert_eq(g.hop(0, Vector2i.DOWN), 6, "straight below beats the nearer-looking diagonal")
	assert_eq(g.hop(2, Vector2i.RIGHT), 2, "at the edge the paw stays put")
	assert_eq(g.hop(0, Vector2i.ZERO), 0)


func test_every_hop_in_the_room_goes_the_way_it_was_pushed() -> void:
	for i in Layout.SPOTS.size():
		for d in SpotGraph.DIRS:
			var j := graph.hop(i, d)
			if j == i:
				continue
			var delta := Vector2(Layout.SPOTS[j].pos - Layout.SPOTS[i].pos)
			assert_true(delta.dot(Vector2(d)) > 0.0, "spot %d -> %d going %s" % [i, j, d])


func test_no_spot_is_a_dead_end() -> void:
	for i in Layout.SPOTS.size():
		var exits := 0
		for d in SpotGraph.DIRS:
			if graph.hop(i, d) != i:
				exits += 1
		assert_true(exits >= 2, "spot %d has %d exits" % [i, exits])
