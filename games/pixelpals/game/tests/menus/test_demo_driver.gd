extends GutTest
## Demo driver: scripted input for all three seats.

const DemoDriver := preload("res://scripts/demo_driver.gd")

var dd: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func test_level_start_seats_three_with_riders() -> void:
	dd.start("level")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.run_seconds, 20.0)


func test_demo_driver_sets_scripted_input_for_three_seats() -> void:
	dd.start("level")
	var driver_ys := []
	var gunner_dirs := {}
	var honks := 0
	var t := 0.0
	while t < 6.5:
		dd.drive("level", t)
		Players.poll()
		driver_ys.append(Players.move(Players.Seat.DRIVER).y)
		gunner_dirs[Players.dir4(Players.Seat.GUNNER)] = true
		assert_true(Players.pressed(Players.Seat.GUNNER, "a"), "gunner holds fire")
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			honks += 1
		t += 1.0 / 30.0
	assert_gt(driver_ys.max(), 0.5, "driver weaves down")
	assert_lt(driver_ys.min(), -0.5, "driver weaves up")
	assert_eq(gunner_dirs.size(), 4, "gunner rotates through 4 directions")
	assert_between(honks, 3, 4, "honker presses every 2 s")
	for d in ["demo:0", "demo:1", "demo:2"]:
		assert_true(Players._scripted.has(d))


func test_party_start_sets_the_stars() -> void:
	dd.start("party")
	assert_eq(Game.stars, 37)
	assert_eq(Players.seated_count(), 3)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	assert_eq(Players.seated_count(), 0)
	var joined: Array[String] = []
	var t := 0.0
	while t < 3.5:
		dd.drive("join", t)
		Players.poll()
		for d in Players.unseated_devices_just_pressed("any"):
			Players.join(d)
			joined.append(d)
		t += 1.0 / 30.0
	assert_eq(joined, ["demo:0", "demo:1", "demo:2"] as Array[String])
