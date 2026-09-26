extends GutTest
## The dig screen driven frame by frame with scripted devices.

const Grid := preload("res://scripts/dig/terrain_grid.gd")
const Rules := preload("res://scripts/dig/rules.gd")
const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.run_seconds = 0.0
	Game.demo = false
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	Game.current = null


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.run_seconds = 0.0
	Game.found.clear()
	Players.reset()
	Players.clear_scripted()


func _seat(n: int, devices := ["demo:0", "demo:1", "demo:2"]) -> void:
	for i in n:
		Players.set_scripted(devices[i], {})
		Players.join(devices[i])
		Players.riders[i] = Game.roster[i]


func _dig() -> Node:
	Game.goto("dig")
	var d: Node = Game.current
	d.set_process(false)
	return d


func _frame(d: Node, states := {}) -> void:
	for dev in states:
		Players.set_scripted(dev, states[dev])
	Players.poll()
	d.step(DT)


func _run(d: Node, seconds: float, states := {}) -> void:
	for i in int(seconds / DT):
		_frame(d, states)


func _tap(d: Node, dev: String, button := "a") -> void:
	_frame(d, {dev: {button: true}})
	_frame(d, {dev: {}})


func test_boom_from_the_toddler_never_moves_or_hurts_the_digger() -> void:
	_seat(3)
	var d := _dig()
	_run(d, 0.2)
	var pos: Vector2 = d.body.pos
	var t0: float = d.time
	for i in 12:
		_tap(d, "demo:2")
		_run(d, Rules.BOOM_COOLDOWN)
	assert_gt(d.booms, 5, "real booms went off")
	assert_eq(d.body.pos, pos, "the digger never moved")
	assert_eq(d.state, d.State.RUN, "the run goes on")
	assert_false(d.paused)
	assert_almost_eq(d.time - t0, 12 * (Rules.BOOM_COOLDOWN + 2 * DT), 0.5, "no time was lost or added")
	assert_true(d.grid.free_around(d.body.cells(d.grid)), "it only ever opens space")


func test_a_boom_clears_a_round_hole_around_the_digger() -> void:
	_seat(3)
	var d := _dig()
	d.body.pos = Vector2(500, 200)
	_tap(d, "demo:2")
	var c := Grid.cell_of(Vector2(500, 200))
	assert_eq(d.grid.get_cell(c + Vector2i(7, 0)), Grid.AIR, "radius 7 cells")
	assert_eq(d.grid.get_cell(c + Vector2i(0, -7)), Grid.AIR)
	assert_ne(d.grid.get_cell(c + Vector2i(9, 0)), Grid.AIR, "not beyond")
	assert_ne(d.grid.get_cell(c + Vector2i(6, 6)), Grid.AIR, "round, not square")


func test_boom_cooldown_still_answers_every_press_with_a_puff() -> void:
	_seat(3)
	var d := _dig()
	for i in 6:
		_tap(d, "demo:2")  # six presses within about 0.4 s
	assert_eq(d.booms, 1, "one real boom per cooldown")
	assert_eq(d.puffs, 5, "every other press got a puff")
	_run(d, Rules.BOOM_COOLDOWN)
	_tap(d, "demo:2")
	assert_eq(d.booms, 2, "after the cooldown, a boom again")


func test_auto_boom_runs_when_seat_three_is_empty() -> void:
	_seat(1)
	var d := _dig()
	_run(d, Rules.AUTO_BOOM_EVERY + 1.0)
	assert_eq(d.auto_booms, 1, "one surprise boom after 20 s")
	_run(d, Rules.AUTO_BOOM_EVERY)
	assert_eq(d.auto_booms, 2)


func test_two_seats_get_the_auto_boom_too_and_three_do_not() -> void:
	_seat(2)
	var d := _dig()
	_run(d, Rules.AUTO_BOOM_EVERY + 1.0)
	assert_eq(d.auto_booms, 1)
	root.remove_child(d)
	d.free()
	Players.reset()
	_seat(3)
	var d3 := _dig()
	_run(d3, Rules.AUTO_BOOM_EVERY + 1.0)
	assert_eq(d3.booms, 0, "the toddler owns the boom")


func test_treasure_is_found_when_any_cell_is_exposed() -> void:
	_seat(1)
	var d := _dig()
	var t: Dictionary = d.treasures[0]
	assert_eq(t.state, "buried")
	_run(d, 0.1)
	assert_eq(t.state, "buried", "nothing is found by itself")
	d.grid.dig_cell(t.cell + Vector2i(3, 3))  # just one corner cell
	_frame(d)
	assert_eq(t.state, "pop", "one open cell is enough")
	assert_not_null(t.node)
	_run(d, 2.0)
	assert_eq(t.state, "truck")
	assert_eq(d.in_truck, 1)
	assert_eq(Game.found, [t.kind] as Array[String])


func test_run_ends_with_every_treasure_in_the_truck() -> void:
	_seat(2)
	var d := _dig()
	for t in d.treasures:
		d.grid.dig_rect(t.rect)
	_run(d, 2.0)
	assert_eq(d.in_truck, 12)
	assert_eq(d.state, d.State.CELEBRATE)
	_run(d, 3.0)
	assert_eq(Game.current_name, "party")
	assert_eq(Game.found.size(), 12)


func test_run_ends_with_every_treasure_in_the_truck_via_the_fountain() -> void:
	Game.run_seconds = 3.0
	_seat(1)
	var d := _dig()
	_run(d, 3.1)
	assert_eq(d.state, d.State.FOUNTAIN, "time is up: the fountain starts")
	_run(d, 12 * Rules.FOUNTAIN_EVERY + 3.0)
	assert_eq(d.in_truck, 12, "every treasure burst up and reached the truck")
	_run(d, 3.0)
	assert_eq(Game.current_name, "party")
	assert_eq(Game.found.size(), 12)


func test_scoop_direction_follows_the_scooper_in_four_directions() -> void:
	_seat(2)
	var d := _dig()
	d.body.pos = Vector2(500, 200)
	d.grid.dig_rect(d.body.cells(d.grid))
	for v in [Vector2(0.9, 0.3), Vector2(-0.2, -0.8), Vector2(-1, 0.1), Vector2(0.3, 0.9)]:
		_frame(d, {"demo:1": {"move": v}})
		assert_has([Vector2i.RIGHT, Vector2i.LEFT, Vector2i.UP, Vector2i.DOWN], d.aim)
		assert_eq(d.arm.rotation, Vector2(d.aim).angle(), "the arm points the aimed way")
	assert_eq(d.aim, Vector2i.DOWN)
	_run(d, 0.5)
	var bite: Rect2i = Rules.scoop_rect(d.body.cells(d.grid), Vector2i.DOWN, Rules.BIG_SCOOP)
	_tap(d, "demo:1")
	for y in range(bite.position.y, bite.end.y):
		for x in range(bite.position.x, bite.end.x):
			assert_eq(d.grid.get_cell(Vector2i(x, y)), Grid.AIR, "5x5 bite below")


func test_a_scoop_into_empty_air_still_animates() -> void:
	_seat(2)
	var d := _dig()
	d.body.pos = Vector2(500, 200)
	d.grid.dig_rect(Rect2i(110, 40, 30, 20))
	_frame(d, {"demo:1": {"move": Vector2.RIGHT}})
	_tap(d, "demo:1")
	assert_eq(d.scoops, 1)
	assert_gt(d.arm_t, 0.0, "the arm reaches out")


func test_driver_scoop_bites_in_the_driving_direction() -> void:
	_seat(1)
	var d := _dig()
	d.body.pos = Vector2(500, 200)
	d.grid.dig_rect(d.body.cells(d.grid))
	_run(d, 0.1, {"demo:0": {"move": Vector2.LEFT}})
	_frame(d, {"demo:0": {"a": true}})
	var bite: Rect2i = Rules.scoop_rect(d.body.cells(d.grid), Vector2i.LEFT, Rules.SMALL_SCOOP)
	assert_eq(d.grid.get_cell(bite.get_center()), Grid.AIR)
	assert_true(d.driver_arm.visible)


func test_driving_digs_and_one_seat_is_playable() -> void:
	_seat(1)
	var d := _dig()
	var x0: float = d.body.pos.x
	_run(d, 2.0, {"demo:0": {"move": Vector2.DOWN}})
	assert_gt(d.body.pos.y, 30.0, "drove down into the dirt")
	assert_gt(d.grid.dug_total, 0)
	assert_eq(d.body.pos.x, x0)


func test_bumping_rock_donks_without_harm() -> void:
	_seat(1)
	var d := _dig()
	d.body.pos = Vector2(22, 200)
	d.grid.dig_rect(Rect2i(0, 40, 20, 20))
	_run(d, 1.0, {"demo:0": {"move": Vector2.LEFT}})
	assert_gt(d.donks, 0)
	assert_eq(d.state, d.State.RUN)


func test_boom_rumbles_every_seated_pad() -> void:
	_seat(3, ["pad:5", "demo:1", "pad:7"])
	var d := _dig()
	Players.set_scripted("pad:7", {"a": true})
	Players.poll()
	d.step(DT)
	assert_eq(d.rumble_log, [5, 7] as Array[int])


func test_pause_is_the_drivers_and_b_goes_back_to_join() -> void:
	_seat(3)
	var d := _dig()
	_tap(d, "demo:1", "start")
	assert_false(d.paused, "only the driver pauses")
	_tap(d, "demo:0", "start")
	assert_true(d.paused)
	var t: float = d.time
	_tap(d, "demo:2")
	assert_eq(d.time, t, "paused: nothing moves")
	_tap(d, "demo:0", "b")
	assert_eq(Game.current_name, "join")


func test_camera_leads_toward_the_nearest_buried_treasure() -> void:
	_seat(1)
	var d := _dig()
	d.body.pos = Vector2(480, 160)
	_run(d, 3.0)
	var near: Dictionary = d.nearest_buried()
	var to: Vector2 = d.treasure_center(near) - d.body.pos
	var view_center: Vector2 = d.cam + Vector2(160, 100)
	var lead: Vector2 = view_center - d.body.pos
	assert_gt(lead.dot(to.normalized()), 5.0, "the view is pushed toward the treasure")
	assert_lt(lead.length(), Rules.CAMERA_LEAD_PX + 2.0)


func test_glints_show_through_thin_dirt_only() -> void:
	_seat(1)
	var d := _dig()
	d.body.pos = Vector2(900, 300)
	var shallow := 0
	for t in d.treasures:
		t.glint_t = 0.0
	_frame(d)
	for e in d.fx:
		if e.kind == "glint":
			shallow += 1
	var expected := 0
	for t in d.treasures:
		if d.grid.dirt_depth(t.cell + Vector2i(2, 2), Rules.GLINT_REVEAL_CELLS) <= Rules.GLINT_REVEAL_CELLS \
				or d.body.pos.distance_to(d.treasure_center(t)) <= Rules.GLINT_NEAR_PX:
			expected += 1
	assert_eq(shallow, expected)
	assert_gt(expected, 0, "some treasures are shallow enough to glint from the start")
	assert_lt(expected, 12, "deep ones stay hidden")


func test_small_finds_delight_and_go_home() -> void:
	_seat(1)
	var d := _dig()
	var f: Dictionary = d.finds[0]
	d.grid.dig_cell(f.cell)
	_frame(d)
	assert_eq(f.state, "out")
	_run(d, 4.0)
	assert_eq(f.state, "gone")
	assert_eq(d.in_truck, 0, "finds are not treasures")


func test_stress_a_boom_every_frame_repaints_only_dirty_cells() -> void:
	_seat(3)
	var d := _dig()
	d.boom_cd = 0.0
	var start := Time.get_ticks_msec()
	for i in 60:
		d.body.pos = Vector2(60 + i * 14, 60 + (i % 5) * 50)
		d.boom_cd = 0.0
		d.boom()
		d.view.flush()
		assert_lt(d.view.painted_last, 20 * 20, "frame %d: one boom's cells, not the whole field" % i)
	var ms := Time.get_ticks_msec() - start
	gut.p("60 booms + repaints: %d ms" % ms)
	assert_lt(ms, 3000, "no stutter-sized repaint")
