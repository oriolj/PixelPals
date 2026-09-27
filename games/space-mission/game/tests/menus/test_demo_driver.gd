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
	Game.mission_scale = 1.0
	Game.new_mission()


func test_stage_start_seats_three_with_riders_and_a_short_mission() -> void:
	dd.start("orbit")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_lt(Game.mission_scale, 0.5)


func test_party_start_fakes_results() -> void:
	dd.start("party")
	assert_eq(Game.modules.size(), 5)
	assert_eq(Game.photos.size(), 4)
	assert_gt(Game.samples.size(), 0)


func test_camera_presses_every_two_seconds_in_orbit() -> void:
	dd.start("orbit")
	var presses := 0
	var t := 0.0
	while t < 8.0:
		dd.drive("orbit", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			presses += 1
		t += DT
	assert_eq(presses, 4)


func test_select_script_ends_on_the_earth_stage_and_readies() -> void:
	dd.start("select")
	var sel = load("res://scripts/screens/select.gd").new()
	sel.auto_goto = false
	add_child_autofree(sel)
	sel.set_process(false)
	var t := 0.0
	while t < 7.0 and sel.next_screen == "":
		dd.drive("select", t)
		Players.poll()
		sel._process(DT)
		t += DT
	assert_eq(sel.next_screen, "orbit")
