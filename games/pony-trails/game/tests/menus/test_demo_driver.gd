extends GutTest
## Demo driver: scripted input for all three seats on every screen, its own wall.

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
	Game.day_scale = 1.0
	Game.new_day()
	Game.wall.reset()


func test_stage_start_seats_three_with_riders_and_a_short_day() -> void:
	dd.start("trail")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_lt(Game.day_scale, 0.5)
	assert_eq(Game.mare_coat, "bay")
	assert_eq(Game.foal_coat, "palomino")


func test_party_start_fakes_the_day_and_seeds_earlier_days() -> void:
	dd.start("party")
	assert_eq(Game.day.rosettes.size(), 5)
	assert_eq(Game.wall.day_count(), 3, "three earlier days on the (test) wall")
	assert_ne(Game.wall.path, Game.WALL_PATH)


func test_toddler_presses_every_two_seconds_on_the_trail() -> void:
	dd.start("trail")
	var presses := 0
	var t := 0.0
	while t < 8.0:
		dd.drive("trail", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			presses += 1
		t += DT
	assert_eq(presses, 4)


func test_select_script_ends_on_the_stable_with_default_coats() -> void:
	dd.start("select")
	var sel = load("res://scripts/screens/select.gd").new()
	sel.auto_goto = false
	add_child_autofree(sel)
	sel.set_process(false)
	var t := 0.0
	while t < 9.0 and sel.next_screen == "":
		dd.drive("select", t)
		Players.poll()
		sel.step(DT)
		t += DT
	assert_eq(sel.next_screen, "stable")
	assert_eq(Game.mare_coat, "bay")
	assert_eq(Game.foal_coat, "palomino")
