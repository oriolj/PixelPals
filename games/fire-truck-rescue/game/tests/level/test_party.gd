extends GutTest
## The party screen: stars rain into the bucket, badges line up, back to select.

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
	Game.cats = 0
	Players.reset()
	Players.clear_scripted()


func _party(stars: int, cats: int) -> Node:
	Game.stars = stars
	Game.cats = cats
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_every_star_lands_in_the_bucket_and_badges_line_up() -> void:
	var p := _party(18, 3)
	for i in 240:
		p.step(DT)
	assert_eq(p.shown, 18)
	assert_eq(p.landed.size(), 18)
	assert_eq(p.badges.size(), 3)


func test_zero_is_fine() -> void:
	var p := _party(0, 0)
	for i in 60:
		p.step(DT)
	assert_eq(p.shown, 0)
	assert_eq(p.badges.size(), 0)
	assert_eq(p.riders.size(), 3, "falls back to the roster so the stage is never empty")


func test_goes_to_select_after_the_stay() -> void:
	var p := _party(5, 1)
	for i in 320:
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_driver_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party(5, 0)
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
