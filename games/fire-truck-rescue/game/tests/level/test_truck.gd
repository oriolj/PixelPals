extends GutTest
## The arcade truck: bumps are soft and free, it never gets stuck, the road pulls it straight.

const Rig := preload("res://tests/helpers/level_rig.gd")
const TownMap := preload("res://scripts/level/town_map.gd")
const TruckModel := preload("res://scripts/level/truck_model.gd")
const DT := 1.0 / 30.0


func after_each() -> void:
	Rig.cleanup()


func test_truck_bump_never_damages_or_costs_stars() -> void:
	Rig.seat(3)
	var lvl := Rig.make_level(self)
	# Drive south off the top road straight into the house at (2, 2).
	lvl.truck.place(lvl.map.cell_center(Vector2i(2, 1)), PI)
	lvl.cam_yaw = PI
	lvl.left_station = true
	Rig.activate(lvl, lvl.order[0])
	lvl.stars = 5
	lvl.shown_stars = 5
	var sizes := []
	for f in lvl.fires:
		sizes.append(f.size)
	Rig.run(lvl, 2.5, {"demo:0": {"move": Vector2(0, -1)}})
	assert_gt(lvl.truck.bumps, 0, "it hit the house")
	assert_eq(lvl.stars, 5, "no stars lost")
	assert_eq(lvl.state, lvl.State.RUN, "the run goes on")
	for i in lvl.fires.size():
		assert_true(lvl.fires[i].size >= sizes[i] or lvl.fires[i].size == sizes[i], "fires untouched by a bump")
	assert_almost_eq(lvl.time, 2.5, 0.05, "no time penalty")
	assert_false("damage" in lvl.truck, "the truck has no damage at all")


func test_bump_bounces_back_softly() -> void:
	var map := TownMap.new()
	var t := TruckModel.new()
	t.place(map.cell_center(Vector2i(2, 1)), PI)
	var bumped := false
	for i in 90:
		var ev := t.step(DT, t.fwd(), map)
		if ev.bump != "":
			bumped = true
			assert_lt(t.speed, 0.0, "bounces backwards")
			assert_gt(t.wobble, 0.0, "wobbles")
			break
	assert_true(bumped)


func test_truck_unsticks_after_three_seconds() -> void:
	var map := TownMap.new()
	var house: Dictionary = {}
	for h in map.houses:
		if h.cell == Vector2i(2, 2):
			house = h
	var front: float = house.pos.y - house.d / 2.0
	var t := TruckModel.new()
	# Nose already touching the house: throttle held, nowhere to go.
	t.place(Vector2(house.pos.x, front - TruckModel.RADIUS - TruckModel.HALF_LEN - 0.02), PI)
	var time := 0.0
	var unstuck_at := -1.0
	while time < 4.0:
		var ev := t.step(DT, t.fwd(), map)
		time += DT
		if ev.unstuck:
			unstuck_at = time
			break
	assert_between(unstuck_at, 2.9, 3.3, "unsticks after about 3 s")
	assert_eq(t.unsticks, 1)
	assert_true(map.is_road(map.cell_of(t.pos)), "set down on a road")
	var c: Vector2 = map.cell_center(map.cell_of(t.pos))
	assert_lt(t.pos.distance_to(c), 3.5, "near the road centre")
	var f := t.fwd()
	assert_almost_eq(absf(f.x) + absf(f.y), 1.0, 0.02, "facing along the road")


func test_no_throttle_never_unsticks() -> void:
	var map := TownMap.new()
	var t := TruckModel.new()
	t.place(map.cell_center(Vector2i(4, 4)), 0.0)
	for i in 200:
		t.step(DT, Vector2.ZERO, map)
	assert_eq(t.unsticks, 0, "parked on purpose is not stuck")


func test_road_magnet_centres_the_truck() -> void:
	var map := TownMap.new()
	var t := TruckModel.new()
	# On the top road, 2.5 m off centre, stick roughly east.
	var c: Vector2 = map.cell_center(Vector2i(2, 1))
	t.place(c + Vector2(0, 2.5), TruckModel.yaw_of(Vector2.RIGHT))
	for i in 60:
		t.step(DT, Vector2(1, 0.15).normalized(), map)
	assert_lt(absf(t.pos.y - c.y), 1.0, "pulled toward the centre line")
	assert_gt(t.pos.x, c.x + 10.0, "and kept driving east")


func test_stick_back_reverses() -> void:
	var map := TownMap.new()
	var t := TruckModel.new()
	t.place(map.cell_center(Vector2i(3, 1)), TruckModel.yaw_of(Vector2.RIGHT))
	for i in 20:
		t.step(DT, Vector2.LEFT, map)
	assert_lt(t.speed, 0.0)
