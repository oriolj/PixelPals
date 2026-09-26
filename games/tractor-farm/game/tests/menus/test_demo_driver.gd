extends GutTest
## Demo driver: scripted input for all three seats on every screen.

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
	Game.level_preset = ""
	Game.run_limit = 360.0


func test_level_start_seats_three_with_riders() -> void:
	dd.start("level")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.run_limit, dd.DEMO_RUN_LIMIT)


func test_finale_start_is_the_level_with_a_preset() -> void:
	dd.start("finale")
	assert_eq(dd.screen, "level")
	assert_eq(Game.level_preset, "finale")


func test_party_start_sets_the_barn() -> void:
	dd.start("party")
	assert_eq(Game.barn, [9, 7, 8, 6] as Array[int])
	assert_eq(Players.seated_count(), 3)


func test_cloud_presses_every_one_and_a_half_seconds() -> void:
	dd.start("level")
	var presses := 0
	var t := 0.0
	while t < 6.0:
		dd.drive("level", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			presses += 1
		t += 1.0 / 30.0
	assert_eq(presses, 4)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	var joined := {}
	var t := 0.0
	while t < 3.5:
		dd.drive("join", t)
		Players.poll()
		for d in Players.unseated_devices_just_pressed("a"):
			joined[d] = true
		t += 1.0 / 30.0
	assert_eq(joined.size(), 3)
