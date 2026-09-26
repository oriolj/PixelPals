extends GutTest
## The party screen: stars pop in, then back to select.

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
	Game.stars = 0
	Players.reset()
	Players.clear_scripted()


func _party(stars: int) -> Node:
	Game.stars = stars
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_icons_cap_at_fifty_then_a_big_star() -> void:
	var p := _party(73)
	for i in 240:
		p.step(DT)
	assert_eq(p.icons.size(), 50)
	assert_not_null(p.big_star)
	assert_eq(p.shown, 73)


func test_zero_stars_is_fine() -> void:
	var p := _party(0)
	for i in 60:
		p.step(DT)
	assert_eq(p.icons.size(), 0)
	assert_eq(p.riders.size(), 3, "falls back to the roster so the stage is never empty")


func test_goes_to_select_after_the_stay() -> void:
	var p := _party(5)
	for i in 320:
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_driver_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party(5)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "party", "a held from the level is ignored")
	Players.set_scripted("demo:0", {})
	for i in 40:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "select")
