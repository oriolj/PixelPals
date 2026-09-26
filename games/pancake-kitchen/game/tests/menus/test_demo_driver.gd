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
	Game.round_customers = 6
	Game.round_limit = 420.0


func test_kitchen_start_seats_three_with_chefs_and_a_short_round() -> void:
	dd.start("kitchen")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["bunny", "fox", "duck"] as Array[String])
	assert_eq(Game.round_customers, 2)
	assert_eq(Game.round_limit, 25.0)


func test_party_start_has_six_plates_from_plain_to_loaded() -> void:
	dd.start("party")
	assert_eq(Game.plates.size(), 6)
	assert_eq(Game.plates[0].toppings.size(), 0)
	assert_gt(Game.plates[5].toppings.size(), 8)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
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


func test_demo_kitchen_round_serves_misses_once_and_ends() -> void:
	# Run the real kitchen under the demo script, headless, for the 25 s round.
	var root := Node2D.new()
	add_child_autofree(root)
	var saved = Game._root
	Game.set_root(root)
	dd.start("kitchen")
	Game.goto("kitchen")
	var k: Node = Game.current
	k.auto_goto = false
	k.set_process(false)
	dd._prefill_kitchen()
	var gags := {}
	var t := 0.0
	var dt := 1.0 / 30.0
	while t < 31.0 and k.next_screen == "":
		dd.drive("kitchen", t)
		Players.poll()
		k.step(dt)
		var p = k.rules.pancake
		if p != null and p.state == k.rules.P.GAG:
			gags[p.gag] = true
		t += dt
	Game.set_root(saved)
	Game.current = null
	assert_true(gags.has("dog"), "the deliberate miss lands on the dog")
	assert_gte(k.rules.plates.size(), 2)
	assert_eq(k.rules.plates[0].toppings.size(), 0, "the first stack is plain")
	assert_gt(k.rules.plates[0].joy, 0)
	assert_gt(k.rules.plates[1].joy, k.rules.plates[0].joy, "the loaded stack gets a bigger joy")
	assert_eq(k.next_screen, "party")
