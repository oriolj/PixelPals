extends GutTest
## The run's end, the town map, and a whole demo run through the town.

const Rig := preload("res://tests/helpers/level_rig.gd")
const TownMap := preload("res://scripts/level/town_map.gd")
const Rules := preload("res://scripts/level/rules.gd")
const DemoDriver := preload("res://scripts/demo_driver.gd")


func after_each() -> void:
	Rig.cleanup()
	Game.current = null


func test_run_ends_after_all_done_or_six_minutes() -> void:
	Rig.seat(3)
	var lvl := Rig.make_level(self)
	Rig.step(lvl)
	assert_eq(lvl.state, lvl.State.RUN)
	# Everything done -> home.
	for f in lvl.fires:
		f.activate()
		f.out = true
	for c in lvl.cats:
		c.rescued = true
	Rig.step(lvl)
	assert_eq(lvl.state, lvl.State.HOMEWARD, "all done: sunset and home")
	# Park in the station -> party.
	lvl.truck.place(lvl.map.station.bay, PI)
	Rig.run(lvl, Rules.PARTY_DELAY + 0.2)
	assert_eq(lvl.next_screen, "party")
	assert_eq(Game.cats, 3)

	# A fresh run: at 6 minutes it heads home even with fires left.
	var lvl2 := Rig.make_level(self)
	Rig.activate(lvl2, lvl2.order[0])
	lvl2.time = Rules.RUN_SECONDS - 0.05
	Rig.step(lvl2)
	Rig.step(lvl2)
	assert_eq(lvl2.state, lvl2.State.HOMEWARD, "time is up")
	assert_false(lvl2.fires[lvl2.order[0]].lit(), "the leftover fire fizzles out, no fuss")
	assert_eq(lvl2.next_screen, "", "the party waits for the truck to park")


func test_home_needs_parking_inside() -> void:
	Rig.seat(1)
	var lvl := Rig.make_level(self)
	lvl.go_home()
	lvl.truck.place(lvl.map.cell_center(Vector2i(4, 1)), 0.0)
	Rig.run(lvl, 2.0)
	assert_eq(lvl.next_screen, "", "not parked yet")
	assert_true(lvl.objective().kind == "home", "the arrow points home")


func test_town_map_has_every_spot_on_a_reachable_road() -> void:
	var m := TownMap.new()
	assert_eq(m.fires.size(), 6)
	assert_eq(m.cats.size(), 3)
	assert_eq(m.hydrants.size(), 2)
	assert_false(m.station.is_empty())
	var door: Vector2i = m.station.door_cell
	assert_true(m.is_road(door))
	for f in m.fires:
		assert_true(m.is_road(f.park), "fire %s parks on a road" % f.cell)
		assert_gt(m.road_distance(door, f.park), -1, "reachable")
		assert_lt(m.cell_center(f.park).distance_to(f.pos), Rules.HOSE_RANGE, "in hose range from the road centre")
	for c in m.cats:
		assert_true(m.is_road(c.park))
		assert_gt(m.road_distance(door, c.park), -1)
		assert_lt(m.cell_center(c.park).distance_to(c.pos), Rules.LADDER_RANGE, "ladder reaches from the road centre")
	for h in m.hydrants:
		assert_true(m.is_road(h.cell))
	var order := m.fire_order()
	assert_eq(order.size(), 6)
	assert_eq(order.duplicate().size(), 6)
	for r in m.rows:
		assert_eq(m.MAP[r].length(), m.cols, "row %d is %d wide" % [r, m.cols])


func test_demo_route_clears_town() -> void:
	# The demo driver plays a whole run: every fire, every cat, home, party.
	var dd: Node = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)
	dd.start("level")
	var lvl := Rig.make_level(self)
	lvl.next_fire_t = Rules.FIRST_FIRE_DELAY
	Game.current = lvl
	var t := 0.0
	var dt := Rig.DT
	while t < Rules.RUN_SECONDS + 60.0 and lvl.next_screen == "":
		dd.drive("level", t, dt)
		Players.poll()
		lvl.step(dt)
		t += dt
	assert_eq(lvl.next_screen, "party", "reached the party (after %.0f s)" % t)
	assert_eq(lvl.stars, 18, "all 6 fires put out")
	assert_eq(lvl.cats_saved, 3, "all 3 cats rescued")
	assert_lt(lvl.time, Rules.RUN_SECONDS, "before the clock ran out")
	gut.p("demo run: %.0f s, %d bumps, %d unsticks" % [lvl.time, lvl.truck.bumps, lvl.truck.unsticks])
