extends GutTest
## Party: the stacks match the barn counts, then back to select.

const PartyScreen := preload("res://scripts/screens/party.gd")
const DT := 1.0 / 30.0

var party
var _saved_root: Node
var root: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for i in 3:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]
	Players.poll()
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = null  # goto only records the screen name


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current_name = ""
	Players.reset()
	Players.clear_scripted()


func _open(barn: Array[int]) -> void:
	Game.barn = barn
	Game.giant_crop = 2
	party = PartyScreen.new()
	root.add_child(party)
	party.set_process(false)


func _step(states := {}) -> void:
	for i in 3:
		Players.set_scripted("demo:%d" % i, states.get(i, {}))
	Players.poll()
	party.step(DT)


func test_stacks_match_the_barn_counts() -> void:
	_open([9, 7, 8, 6] as Array[int])
	for k in 30 * 5:
		_step()
	assert_eq(party.shown, [9, 7, 8, 6] as Array[int])
	assert_eq(party.giant, 2)


func test_stacks_grow_together() -> void:
	_open([3, 3, 3, 3] as Array[int])
	for k in int((party.FIRST_POP + party.POP_EVERY * 3.5) / DT):
		_step()
	assert_eq(party.shown, [1, 1, 1, 1] as Array[int], "round-robin, one per stack")


func test_empty_barn_is_still_a_party() -> void:
	_open([0, 0, 0, 0] as Array[int])
	for k in 60:
		_step({2: {"a": k % 4 == 0}})
	assert_eq(party.shown, [0, 0, 0, 0] as Array[int])
	assert_gt(party.confetti.size(), 0)


func test_goes_to_select_after_the_stay() -> void:
	_open([1, 1, 1, 1] as Array[int])
	for k in int(party.STAY_SECONDS / DT) + 2:
		_step()
	assert_true(party.done)
	assert_eq(Game.current_name, "select")


func test_driver_a_skips_after_the_guard() -> void:
	_open([1, 1, 1, 1] as Array[int])
	_step({0: {"a": true}})
	assert_false(party.done, "an A still held from the level does not skip")
	for k in 40:
		_step()
	_step({0: {"a": true}})
	assert_true(party.done)
