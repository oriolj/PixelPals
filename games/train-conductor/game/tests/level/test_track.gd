extends GutTest
## The track graph, the train on it, and the rail generator.

const Track := preload("res://scripts/track/track.gd")
const Train := preload("res://scripts/track/train.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const TrackView := preload("res://scripts/level/track_view.gd")

var track


func before_all() -> void:
	track = Track.new()


func _first(node: int) -> int:
	return track.out_edges[node][0]


func _dist_to_track(p: Vector2, edges: Array) -> float:
	var best := INF
	for e in edges:
		best = minf(best, p.distance_to(track.curves[e].get_closest_point(p)))
	return best


func test_track_graph_is_strongly_connected_no_dead_ends() -> void:
	assert_true(track.strongly_connected(), "every node reaches every node")
	for n in track.node_names.size():
		assert_gt(track.out_edges[n].size(), 0, "%s has a way out" % track.node_names[n])
		assert_gt(track.in_edges[n].size(), 0, "%s has a way in" % track.node_names[n])
	assert_eq(track.junctions.size(), 3, "three junctions")
	assert_eq(track.stations.size(), 4, "four stations")
	# Every station is reachable from every junction branch within a lap.
	for n in track.junctions:
		for e in track.out_edges[n]:
			assert_false(track.beacon(e).is_empty(), "branch %s shows a beacon" % track.edge_names[e])


func test_every_branch_rejoins_the_main_line() -> void:
	# No dead ends: from any branch the train is back at a junction within 3 edges.
	for n in track.junctions:
		for e in track.out_edges[n]:
			var node: int = track.edge_to[e]
			var hops := 0
			while not track.is_junction(node) and hops < 3:
				node = track.edge_to[track.out_edges[node][0]]
				hops += 1
			assert_true(track.is_junction(node), "branch %s leads on to more choices" % track.edge_names[e])


func test_engine_advances_along_edge_by_speed() -> void:
	var e: int = track.edge("main1")
	var train := Train.new(track, e, 50.0)
	train.speed = 120.0
	var dt := 0.5
	train.advance(train.speed * dt, func(node): return _first(node))
	assert_eq(train.edge, e)
	assert_almost_eq(train.dist, 110.0, 0.001)
	assert_almost_eq(train.nose_position().x, track.node_pos[track.node("M1")].x + 110.0, 1.0, "main1 is straight")
	# Crossing the end of the edge carries the remainder into the next one.
	train.advance(track.lengths[e], func(node): return _first(node))
	assert_eq(train.edge, track.edge("main2"))
	assert_almost_eq(train.dist, 110.0, 0.01)


func test_carriages_follow_across_junction_edges() -> void:
	# Nose just past J1 on the red branch: the tail is still on the west edge.
	var west: int = track.edge("west")
	var red: int = track.edge("red")
	var train := Train.new(track, west, track.lengths[west] - 150.0)
	train.cars = 4
	train.advance(260.0, func(_node): return red)
	assert_eq(train.edge, red)
	var spans := train.car_spans()
	var last: Vector3 = spans[spans.size() - 1]
	assert_eq(train.locate_back(last.y)[0], west, "the last bogie is still on the west edge")
	for t in train.car_transforms():
		assert_lt(_dist_to_track(t.origin, [west, red]), 10.0, "car centre between its bogies, on the curve")
	for s in spans:
		for back in [s.x, s.y]:
			assert_lt(_dist_to_track(train.point_back(back), [west, red]), 0.8, "bogies ride the rails")
	# Keep going across the merge: still on the rails.
	train.advance(1800.0, func(node): return _first(node))
	for t in train.car_transforms():
		assert_lt(_dist_to_track(t.origin, range(track.curves.size())), 10.0)


func test_polygon_offsets_do_not_self_intersect_on_tightest_curve() -> void:
	var half := Track.TRACK_WIDTH * 0.5
	assert_gt(track.min_radius(), half + 40.0, "tightest curve is wider than the track")
	for e in track.curves.size():
		var pts: PackedVector2Array = track.polyline(e, TrackView.STEP)
		for off in [-half - 3.0, half + 3.0, -TrackView.GROOVE_OFFSET, TrackView.GROOVE_OFFSET]:
			var o := Shapes.offset_polyline(pts, off)
			assert_false(Shapes.self_intersects(o), "%s offset %s" % [track.edge_names[e], off])
		for r in TrackView.rails(pts):
			assert_eq(r.size(), pts.size())
	# The generator's check does catch a fold: offsetting a sharp V by more
	# than its tip allows makes the inner rail cross itself.
	var vee := PackedVector2Array()
	for i in 41:
		var x := -100.0 + i * 5.0
		vee.append(Vector2(x, -absf(x)))
	var folded := Shapes.self_intersects(Shapes.offset_polyline(vee, 30.0)) or Shapes.self_intersects(Shapes.offset_polyline(vee, -30.0))
	assert_true(folded, "a folded offset is detected")


func test_branch_for_flick_points_the_way_on_screen() -> void:
	var j1: int = track.node("J1")
	var red: int = track.edge("red")
	var up: int = track.branch_for_flick(j1, Vector2.UP)
	assert_eq(track.out_edges[j1][up], red, "up at J1 goes to the red (upper) branch")
	assert_eq(track.branch_for_flick(j1, Vector2.RIGHT), -1, "across both branches toggles")
	var j2: int = track.node("J2")
	assert_eq(track.out_edges[j2][track.branch_for_flick(j2, Vector2.RIGHT)], track.edge("yellow"))
	assert_eq(track.out_edges[j2][track.branch_for_flick(j2, Vector2.LEFT)], track.edge("green"))
