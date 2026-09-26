extends GutTest
## The party table and the gallery review screen.

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
	Game.plates = []
	Players.reset()
	Players.clear_scripted()


func _party(plates: Array[Dictionary]) -> Node:
	Game.plates = plates
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_every_customer_sits_at_the_table() -> void:
	var p := _party(load("res://scripts/demo_driver.gd").sample_plates())
	for i in 90:
		p.step(DT)
	assert_eq(p._arrived, 6)
	assert_gt(p.confetti.size(), 0, "confetti falls after the giant flip starts")


func test_an_empty_round_still_has_a_guest() -> void:
	var p := _party([])
	assert_eq(p.plates.size(), 1)


func test_goes_to_select_after_the_stay() -> void:
	var p := _party(load("res://scripts/demo_driver.gd").sample_plates())
	for i in int(13.0 / DT):
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_cook_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party(load("res://scripts/demo_driver.gd").sample_plates())
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "party", "an a held from the kitchen is ignored")
	Players.set_scripted("demo:0", {})
	for i in 50:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "select")


func test_gallery_pages_through_every_asset() -> void:
	Game.goto("gallery")
	var g: Node = Game.current
	var pages := {}
	for i in int(10.5 / DT):
		g._process(DT)
		pages[g.page] = true
	assert_eq(pages.size(), 4)
