extends GutTest
## Demo driver: scripted input for all three seats, and the fort's demo setup.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const DT := 1.0 / 30.0

var dd: Node
var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
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
	Game.round_seconds = Game.ROUND_SECONDS
	Players.reset()
	Players.clear_scripted()


func test_fort_start_seats_three_with_riders_and_a_short_round() -> void:
	dd.start("fort")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "fox", "frog"] as Array[String])
	assert_eq(Game.round_seconds, 20.0)
	assert_eq(Game.current_name, "fort")


func test_fort_demo_places_toys_on_the_sweep_and_the_seek_path() -> void:
	dd.start("fort")
	var f: Node = Game.current
	f.set_process(false)
	var n := 0
	for s in f.spots:
		n += int(s.toy != "")
	assert_eq(n, 8)
	assert_eq(f.spots[dd.seek_path[0]].toy, "", "the first hop lands on the mouse")
	assert_ne(f.spots[dd.seek_path[1]].toy, "", "the second on a toy")
	var on_path := 0
	for i in dd.SWEEP_SPOTS:
		on_path += int(f.spots[i].toy != "")
	assert_eq(on_path, 2)


func test_fort_script_finds_a_toy_meets_the_mouse_and_pops_friends() -> void:
	dd.start("fort")
	var f: Node = Game.current
	f.set_process(false)
	f.auto_goto = false
	var t := 0.0
	var mouse := false
	while t < 14.0:
		dd.drive("fort", t)
		Players.poll()
		f.step(DT)
		for s in f.surprises:
			if s.node.sprite_frames == Art.frames("sleepy_mouse", Color("#ffcd75"), Vector2i(8, 8)):
				mouse = true
		t += DT
	assert_true(mouse, "the first empty lift shows the sleepy mouse")
	assert_true(f.found.has("teddy"), "the seeker's second lift finds the teddy")
	assert_eq(f.director.pops, 3, "presses at 3, 7 and 12 s")
	assert_eq(f.director.twinkles, 1, "the extra press at 7.4 s twinkles")
	assert_ne(f.light_pos, Vector2(160, 92), "the light swept")


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
