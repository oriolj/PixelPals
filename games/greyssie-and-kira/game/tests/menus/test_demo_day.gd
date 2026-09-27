extends GutTest
## The demo driver's autopilot plays a whole day: four rounds, then the party.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const DT := 1.0 / 30.0

var dd: Node
var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.load_data(Game.HOUSE_PATH, Game.CATS_PATH)
	Game.finds.clear()
	Sfx.muted = true
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	dd = DemoDriver.new()
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.start_round = 0
	Players.reset()
	Players.clear_scripted()
	Game.load_data(Game.HOUSE_PATH, Game.CATS_PATH)


func _play_day(start: String) -> Node:
	dd.start(start)
	var l: Node = Game.current
	l.set_process(false)
	l.auto_goto = false
	l.rng.seed = 11
	var t := 0.0
	while l.state != l.State.DONE and t < 900.0:
		dd.drive("house", t)
		Players.poll()
		l.step(DT)
		t += DT
	return l


func test_demo_day_runs_four_rounds_then_party() -> void:
	var l := _play_day("house")
	assert_eq(l.next_screen, "party", "the day ends in the party")
	assert_eq(Game.stars, 4, "four rounds, four stars")
	assert_eq(Game.finds.size(), 8, "each cat found once per round")
	var rounds := {}
	for f in Game.finds:
		rounds[f.round] = true
	assert_eq(rounds.size(), 4)


func test_night_demo_starts_at_the_night_round() -> void:
	dd.start("night")
	assert_eq(Game.round_index, 3)
	assert_true(Game.is_night())


func test_the_day_also_works_in_another_house() -> void:
	Game.load_data("res://tests/fixtures/house_flat.json", "res://tests/fixtures/cats_three.json")
	var l := _play_day("house")
	assert_eq(l.next_screen, "party")
	assert_eq(Game.finds.size(), 12, "three cats, four rounds")


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	var seen := {}
	var t := 0.0
	while t < 4.0:
		dd.drive("join", t)
		Players.poll()
		for i in 3:
			if Players.device_just_pressed("demo:%d" % i, "a"):
				seen[i] = true
		t += DT
	assert_eq(seen.size(), 3)
