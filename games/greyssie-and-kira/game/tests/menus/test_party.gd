extends GutTest
## Party: dinner, cuddle, bedtime, a photo strip of the finds, then select.

const Party := preload("res://scripts/screens/party.gd")
const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for i in 3:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
	Players.riders[0] = "penguin"
	Game.finds.assign([{"cat": "greyssie", "kind": "wardrobe_top", "spot": "wardrobe_top", "round": 0},
		{"cat": "kira", "kind": "toy_box", "spot": "toy_box", "round": 0}])
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.finds.clear()
	Players.reset()
	Players.clear_scripted()


func test_party_runs_dinner_cuddle_bedtime_then_select() -> void:
	var p: Node2D = Party.new()
	root.add_child(p)
	p.set_process(false)
	assert_eq(p.strip.photos.size(), 2, "one photo per find")
	var phases := {}
	var t := 0.0
	while not p.done and t < 30.0:
		Players.poll()
		p.step(DT)
		phases[p.phase] = true
		t += DT
	assert_eq(phases.keys(), [0, 1, 2])
	assert_true(p.done)


func test_party_shows_both_cats_in_every_scene() -> void:
	var p: Node2D = Party.new()
	root.add_child(p)
	p.set_process(false)
	for row in p.cat_nodes:
		assert_eq(row.size(), 2)
