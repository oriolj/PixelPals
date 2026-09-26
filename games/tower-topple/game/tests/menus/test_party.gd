extends GutTest
## Party: towers rebuilt block by block, trophy on the tallest, back to select.

const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	Game.current = null


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.reset_results()
	Players.reset()
	Players.clear_scripted()


func _party(heights: Array[int], stars: int) -> Node:
	Game.tower_heights = heights
	Game.stars = stars
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_towers_stack_up_and_the_tallest_wins() -> void:
	var p := _party([2, 6, 0] as Array[int], 8)
	assert_eq(p.heights, [2, 6, 1] as Array[int], "an empty tower still shows one block")
	assert_eq(p.tallest, 6)
	for i in 150:
		p.step(DT)
	assert_true(p.all_shown())


func test_missing_results_are_fine() -> void:
	var p := _party([] as Array[int], 0)
	for i in 60:
		p.step(DT)
	assert_eq(p.heights.size(), 3)
	assert_eq(p.riders.size(), 3, "falls back to the roster so the stage is never empty")


func test_goes_to_select_after_the_stay() -> void:
	var p := _party([1, 2, 3] as Array[int], 6)
	for i in 320:
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_builder_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party([1, 2, 3] as Array[int], 6)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "party", "an A held from play is ignored")
	Players.set_scripted("demo:0", {})
	for i in 40:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "select")
