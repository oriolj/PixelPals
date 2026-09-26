extends GutTest
## Demo driver: scripted input for all three seats, and the zoo script.

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
	Game.first_hungry.clear()
	Game.run_seconds = 0.0


func test_zoo_start_seats_three_with_buddies() -> void:
	dd.start("zoo")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["monkey", "penguin", "elephant"] as Array[String])
	assert_eq(Game.first_hungry, ["monkey", "penguin"] as Array[String], "the scripted route's animals get hungry first")
	assert_eq(Game.run_seconds, 90.0)


func test_join_script_seats_everyone_then_continues() -> void:
	dd.start("join")
	var joins := 0
	var starts := 0
	var t := 0.0
	while t < 6.0:
		dd.drive("join", t)
		Players.poll()
		for d in dd.DEVICES:
			if Players.device_just_pressed(d, "a"):
				joins += 1
		if Players.device_just_pressed("demo:0", "start"):
			starts += 1
		t += 1.0 / 30.0
	assert_gte(joins, 3)
	assert_eq(starts, 1)


func test_zoo_script_plays_the_plan_route() -> void:
	# The plan's demo: hay for the monkey (refused, wiggle), then banana, then
	# fish for the penguin; the singer presses at 3, 4 and 9 s.
	var saved: Node = Game._root
	var root := Node2D.new()
	add_child(root)
	Game._root = root
	dd.use_goto = true
	dd.start("zoo")
	var zoo: Node = Game.current
	zoo.set_process(false)
	zoo.call_t = 999.0
	var sings := 0
	var saw_wiggle := false
	var t := 0.0
	while t < 12.4:
		dd.drive("zoo", t)
		Players.poll()
		if Players.just_pressed(2, "any"):
			sings += 1
		zoo.step(1.0 / 30.0)
		if zoo.wheel.hint == 1 and zoo.at_animal == "monkey":
			saw_wiggle = true
		t += 1.0 / 30.0
	assert_eq(sings, 3, "the singer pressed three times")
	assert_true(saw_wiggle, "the wrong hay made banana wiggle")
	assert_eq(zoo.animals["monkey"].meals, 1, "the monkey ate")
	assert_eq(zoo.animals["penguin"].meals, 1, "the penguin ate")
	assert_eq(zoo.bounced_back, 1, "one refusal bounced back")
	assert_eq(zoo.stars, 2)
	root.free()
	Game._root = saved
	Game.current = null
	Game.current_name = ""
