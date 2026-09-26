extends GutTest
## Demo driver: scripted input for all three seats on every screen.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const DT := 1.0 / 30.0

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
	Game.trip_scale = 1.0
	Game.new_trip()


func test_flight_start_seats_three_with_riders_and_a_short_trip() -> void:
	dd.start("flight")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_lt(Game.trip_scale, 0.5, "the demo trip reaches the Moon in one capture")


func test_launch_script_presses_once_then_mashes() -> void:
	dd.start("launch")
	var presses: Array[float] = []
	var t := 0.0
	while t < 8.0:
		dd.drive("launch", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			presses.append(t)
		t += DT
	assert_almost_eq(presses[0], 1.0, DT * 1.5, "the first press at 1 s")
	assert_gt(presses.size(), 10, "then mashing during the count")


func test_flight_script_drives_three_seats() -> void:
	dd.start("flight")
	var xs := []
	var dirs := {}
	var shots := 0
	var boosts := 0
	var t := 0.0
	while t < 9.0:
		dd.drive("flight", t)
		Players.poll()
		xs.append(Players.move(Players.Seat.DRIVER).x)
		dirs[Players.dir4(Players.Seat.GUNNER)] = true
		if Players.just_pressed(Players.Seat.GUNNER, "a"):
			shots += 1
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			boosts += 1
		t += DT
	assert_gt(xs.max(), 0.5, "the pilot weaves right")
	assert_lt(xs.min(), -0.5, "and left")
	assert_eq(dirs.size(), 4, "the grabber cycles the four directions")
	assert_between(shots, 8, 10, "a shot every second")
	assert_eq(boosts, 3, "a boost every 3 s")


func test_party_start_sets_results() -> void:
	dd.start("party")
	assert_eq(Game.fuel, 23)
	assert_eq(Game.trip_planets.size(), 3)
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
		t += DT
	assert_eq(joined, ["demo:0", "demo:1", "demo:2"] as Array[String])
