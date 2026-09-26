extends GutTest
## The kitchen screen driven frame by frame with scripted devices.

const Rules := preload("res://scripts/kitchen/rules.gd")
const Kitchen := preload("res://scripts/screens/kitchen.gd")
const DT := 1.0 / 30.0

var k: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.round_customers = 6
	Game.round_limit = 420.0


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func _open(seats: int) -> void:
	for i in seats:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.CHEFS[i]
	Players.poll()
	k = Kitchen.new()
	k.auto_goto = false
	add_child_autofree(k)
	k.set_process(false)
	k.rules.rng.seed = 11


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	k.step(DT)


func _press(d: String, state: Dictionary) -> void:
	_step({d: state})
	_step({d: {}})


func _wait_in_pan() -> void:
	for i in 60:
		_step()
		if k.rules.can_flip():
			return


func _all_nodes(n: Node) -> Array:
	var out := [n]
	for c in n.get_children():
		out.append_array(_all_nodes(c))
	return out


func test_no_label_nodes_in_the_kitchen_screen() -> void:
	_open(3)
	for i in 30:
		_step()
	for n in _all_nodes(k):
		assert_false(n is Label or n is RichTextLabel or n is Button or n is LineEdit,
			"no text node: %s" % n.get_class())


func test_the_flipper_flips_with_any_button() -> void:
	_open(3)
	_wait_in_pan()
	_press("demo:2", {"b": true})
	assert_true(k.rules.in_air(), "even the back button flips")


func test_one_seat_cook_flips_with_a_and_serves_with_b() -> void:
	_open(1)
	_wait_in_pan()
	_press("demo:0", {"a": true})
	assert_true(k.rules.in_air(), "with no flipper, the cook's a flips")
	# Plate full, customer waiting: b serves.
	for i in 60:
		_step()
	k.rules.stack.assign([{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}])
	k.rules.pancake = null
	_press("demo:0", {"b": true})
	assert_eq(k.rules.stack.size(), 0, "served")
	assert_true(k.rules.self_sprinkle, "no topper: the customer sprinkles")


func test_cook_a_serves_when_there_is_nothing_to_flip() -> void:
	_open(3)
	for i in 60:
		_step()
	k.rules.stack.assign([{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}])
	k.rules.pancake = null
	_press("demo:0", {"a": true})
	assert_eq(k.rules.customer.stack.size(), 3)


func test_the_cook_slides_the_pan() -> void:
	_open(1)
	var x0: float = k.rules.pan_x
	for i in 10:
		_step({"demo:0": {"move": Vector2(1, 0)}})
	assert_gt(k.rules.pan_x, x0)
	for i in 60:
		_step({"demo:0": {"move": Vector2(-1, 0)}})
	assert_eq(k.rules.pan_x, Rules.PAN_MIN_X, "clamped to the stove")


func test_the_topper_picks_a_jar_and_drops_it() -> void:
	_open(2)
	_step({"demo:1": {"move": Vector2(1, 0)}})
	assert_eq(Rules.TOPPINGS[k.rules.jar], "chocolate", "right = chocolate chips")
	_step({"demo:1": {"move": Vector2(0, 1)}})
	assert_eq(Rules.TOPPINGS[k.rules.jar], "banana", "down = banana")
	_step({"demo:1": {"move": Vector2(-1, 0)}})
	assert_eq(Rules.TOPPINGS[k.rules.jar], "cream", "left = cream")
	_step({"demo:1": {"move": Vector2(0, -1)}})
	assert_eq(Rules.TOPPINGS[k.rules.jar], "strawberry", "up = strawberry")
	_press("demo:1", {"a": true})
	for i in 20:
		_step()
	assert_eq(k.rules.toppings.size(), 1)
	assert_eq(k.rules.toppings[0].kind, "strawberry")


func test_toddler_mashing_never_hurts_the_run() -> void:
	_open(3)
	for i in int(40.0 / DT):
		_step({"demo:2": {"a": i % 2 == 0, "b": i % 3 == 0, "start": i % 5 == 0}})
		assert_false(k.paused, "only the cook pauses")
	assert_eq(k.next_screen, "")
	assert_not_null(k.rules)
	assert_gt(k.rules.stack.size() + k.rules.served, 0, "mashing even makes pancakes")


func test_cook_start_pauses_and_b_goes_back_to_join() -> void:
	_open(2)
	_press("demo:0", {"start": true})
	assert_true(k.paused)
	var t: float = k.rules.time
	for i in 10:
		_step()
	assert_eq(k.rules.time, t, "the round stands still")
	_press("demo:0", {"start": true})
	assert_false(k.paused)
	_press("demo:0", {"start": true})
	_press("demo:0", {"b": true})
	assert_eq(k.next_screen, "join")


func test_round_over_goes_to_the_party_with_the_plates() -> void:
	Game.round_customers = 2
	Game.round_limit = 5.0
	_open(1)
	for i in int(10.0 / DT):
		_step()
	assert_true(k.rules.finale)
	assert_eq(k.next_screen, "party")
	assert_eq(Game.plates.size(), 2)
