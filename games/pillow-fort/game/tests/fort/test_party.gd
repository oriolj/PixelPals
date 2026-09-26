extends GutTest
## Party: toys and riders dance, then a sleepy bedtime ending, then select.

const PartyScreen := preload("res://scripts/screens/party.gd")
const DT := 1.0 / 30.0

var saved_root: Node
var root: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for i in 3:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]
	Players.poll()
	Game.toys_found.assign(Game.TOYS)
	saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game.set_root(null)


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game.set_root(saved_root)
	Game.current_name = ""
	Players.reset()
	Players.clear_scripted()


func _party() -> Node2D:
	var p: Node2D = PartyScreen.new()
	root.add_child(p)
	p.set_process(false)
	return p


func test_all_eight_toys_and_the_riders_dance() -> void:
	var p := _party()
	assert_eq(p.dancers.size(), 8 + 3)
	var y0: Array = p.dancers.map(func(d): return d.position.y)
	for i in 10:
		p.step(DT)
	var moved := false
	for i in p.dancers.size():
		if p.dancers[i].position.y != y0[i]:
			moved = true
	assert_true(moved)


func test_bedtime_ending_dims_softly_and_goes_to_select() -> void:
	var p := _party()
	var last_a := 0.0
	for i in int(20.0 / DT):
		p.step(DT)
		assert_true(p.veil.color.a <= 0.35 + 0.001, "a soft dim, never dark")
		assert_true(p.veil.color.a - last_a < 0.05, "and never sudden")
		last_a = p.veil.color.a
		if p.done:
			break
	assert_true(p.yawned)
	assert_true(p.done)
	await get_tree().process_frame
	assert_eq(Game.current_name, "select")


func test_flashlight_a_skips_after_the_guard() -> void:
	var p := _party()
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_false(p.done, "an a held from the fort does not skip")
	Players.set_scripted("demo:0", {})
	for i in int(2.0 / DT):
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_true(p.done)


func test_no_label_nodes_in_the_party() -> void:
	var p := _party()
	for n in p.find_children("*", "Label", true, false):
		fail_test("label %s" % n.name)
	pass_test("no labels")
