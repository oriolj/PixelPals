extends GutTest
## The party screen: the truck tips out every treasure, then back to select.

const DT := 1.0 / 30.0
const TWELVE: Array[String] = ["treasure_chest", "crown", "dino_egg", "gems", "coins", "toy_robot",
	"crown", "gems", "treasure_chest", "coins", "toy_robot", "dino_egg"]

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
	Game.found.clear()
	Players.reset()
	Players.clear_scripted()


func _party(found: Array[String]) -> Node:
	Game.found.assign(found)
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_every_treasure_bounces_out_into_one_row() -> void:
	var p := _party(TWELVE)
	for i in int(9.0 / DT):
		p.step(DT)
	assert_true(p.tipped, "the truck tipped its load")
	assert_eq(p.truck.frame, 3)
	assert_eq(p.items.size(), 12)
	var xs := []
	for it in p.items:
		assert_true(it.landed)
		assert_eq(it.node.position.x, it.slot.x)
		assert_between(it.node.position.x, 8.0, 312.0, "on screen")
		xs.append(it.slot.x)
	for i in range(1, xs.size()):
		assert_gt(xs[i], xs[i - 1], "a row, left to right")
	assert_true(p.trophy.visible, "the trophy pops up at the end")


func test_an_empty_truck_is_still_a_party() -> void:
	var p := _party([] as Array[String])
	for i in 120:
		p.step(DT)
	assert_eq(p.items.size(), 0)
	assert_eq(p.dancers.size(), 3, "falls back to the roster so the stage is never empty")


func test_goes_to_select_after_the_stay() -> void:
	var p := _party(TWELVE)
	for i in int(14.0 / DT):
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_driver_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party(TWELVE)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "party", "an a held from the dig is ignored")
	Players.set_scripted("demo:0", {})
	for i in 50:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(Game.current_name, "select")


func test_dancers_wear_helmets_in_their_seat_colours() -> void:
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.join(d)
	Players.riders = ["fox", "frog", "robot"] as Array[String]
	var p := _party(TWELVE)
	var helmets := []
	for rv in p.dancers:
		helmets.append(rv.helmet.sprite_frames == Art.frames(rv.HELMETS[rv.seat], rv.HELMET_TINTS[rv.seat], Vector2i(12, 6)))
	assert_eq(helmets, [true, true, true])
	assert_eq(p.dancers[0].seat, 0)
	assert_eq(p.dancers[2].seat, 2)
