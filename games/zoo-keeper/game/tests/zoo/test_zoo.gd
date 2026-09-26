extends GutTest
## The zoo screen driven frame by frame with scripted devices.

const Rules := preload("res://scripts/zoo/rules.gd")
const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.run_seconds = 0.0
	Game.stars = 0
	Game.meals = 0
	Game.first_hungry.clear()
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
	Game.run_seconds = 0.0
	Players.reset()
	Players.clear_scripted()


func _seat(n: int) -> void:
	for i in n:
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]


func _zoo() -> Node:
	Game.goto("zoo")
	var z: Node = Game.current
	z.set_process(false)
	z.auto_goto = false
	z.rng.seed = 1
	z.gap_t = 999.0     # no random hunger unless a test asks
	z.call_t = 999.0
	return z


func _hungry(z: Node, kind: String) -> Node:
	var a: Node = z.animals[kind]
	a.make_hungry()
	z.hungry_ids.append(kind)
	return a


func _step(z: Node, states := {}, frames := 1) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	for i in frames:
		Players.poll()
		z.step(DT)


func _settle(z: Node, seconds := 2.0) -> void:
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
	_step(z, {}, int(seconds / DT))


func _stand_at(z: Node, kind: String) -> void:
	z.keeper_pos = z.animals[kind].spot
	_step(z)


# ---------------------------------------------------------------- the plan's tests

func test_wrong_food_costs_nothing_and_bounces_back() -> void:
	_seat(2)
	var z := _zoo()
	var monkey := _hungry(z, "monkey")
	_stand_at(z, "monkey")
	assert_true(z.throw_food("hay"))
	_settle(z, 2.2)
	assert_eq(z.stars, 0, "no star lost or won")
	assert_eq(z.meals, 0)
	assert_true(monkey.hungry, "still hungry, never sad")
	assert_eq(monkey.wrong_tries, 1)
	assert_eq(z.bounced_back, 1, "the food bounced back into the cart")
	assert_false(z.throw_lock, "the cart is ready for the next try")
	assert_true(z.hungry_ids.has("monkey"))


func test_hint_ladder_wiggles_then_glows_then_always_succeeds() -> void:
	_seat(2)
	var z := _zoo()
	var monkey := _hungry(z, "monkey")
	_stand_at(z, "monkey")
	assert_eq(z.wheel.hint, Rules.Hint.NONE)
	z.throw_food("hay")
	_settle(z, 2.2)
	assert_eq(z.wheel.hint, Rules.Hint.WIGGLE, "one wrong try: the right food wiggles")
	assert_eq(z.wheel.hint_food, "banana")
	z.throw_food("fish")
	_settle(z, 2.2)
	assert_eq(z.wheel.hint, Rules.Hint.GLOW, "two wrong tries: it glows")
	assert_true(monkey.bubble.get_node("hint").visible, "the bubble shows the food faintly")
	assert_true(z.throw_food("carrot"))
	_settle(z, 1.0)
	assert_eq(z.meals, 1, "the third try always succeeds")
	assert_eq(z.stars, 1)
	assert_false(monkey.hungry)


func test_wheel_opens_only_at_a_feeding_spot() -> void:
	_seat(2)
	var z := _zoo()
	_hungry(z, "penguin")
	z.keeper_pos = Vector2(1200, 380)
	_step(z)
	assert_false(z.wheel.is_open, "closed on the open path")
	_stand_at(z, "rabbit")
	assert_false(z.wheel.is_open, "closed at a spot whose animal is not hungry")
	_stand_at(z, "penguin")
	assert_true(z.wheel.is_open, "open at the hungry penguin's spot")
	assert_eq(z.at_animal, "penguin")
	z.keeper_pos += Vector2(0, 150)
	_step(z)
	assert_false(z.wheel.is_open, "closes when the keeper walks away")
	assert_false(z.throw_food("fish"), "nothing to throw at")


func test_singer_press_picks_the_nearest_animal() -> void:
	_seat(3)
	var z := _zoo()
	for kind in ["elephant", "monkey", "seal"]:
		_stand_at(z, kind)
		_settle(z, 2.2)
		assert_eq(z.nearest_animal(z.keeper_pos).kind, kind)
		_step(z, {"demo:2": {"a": true}})
		assert_eq(z.animals[kind].action, "sing", "%s sings" % kind)
		_step(z, {"demo:2": {}})


func test_singer_never_changes_hunger_or_stars() -> void:
	_seat(3)
	var z := _zoo()
	var monkey := _hungry(z, "monkey")
	_stand_at(z, "monkey")
	for i in 40:
		_step(z, {"demo:2": {"a": i % 2 == 0}})
	assert_true(monkey.hungry)
	assert_eq(monkey.wrong_tries, 0)
	assert_eq(z.stars, 0)
	assert_eq(z.meals, 0)
	assert_eq(z.hungry_ids, ["monkey"] as Array[String])
	# Presses in the cooldown still answer: music notes float up.
	assert_gt(z.fx.size(), 3)


func test_singing_never_blocks_the_feeder() -> void:
	_seat(3)
	var z := _zoo()
	var penguin := _hungry(z, "penguin")
	_stand_at(z, "penguin")
	_step(z, {"demo:2": {"a": true}})
	assert_eq(penguin.action, "sing")
	assert_true(z.throw_food("fish"), "a singing animal still takes food")
	_settle(z, 1.0)
	assert_eq(z.meals, 1)


func test_run_ends_after_twelve_meals_or_the_bell() -> void:
	# Twelve meals, through the real scheduler (rounds, gaps, the break).
	_seat(2)
	var z := _zoo()
	z.gap_t = 0.0
	var guard := 0
	while z.meals < 12 and guard < 6000:
		guard += 1
		if not z.hungry_ids.is_empty() and not z.throw_lock:
			var kind: String = z.hungry_ids[0]
			if z.at_animal != kind:
				_stand_at(z, kind)
			if not z.animals[kind].busy():
				z.throw_food(Rules.right_food(kind))
		_step(z)
	assert_eq(z.meals, 12)
	for kind in z.animals:
		assert_eq(z.animals[kind].meals, 2, "%s ate twice" % kind)
	assert_eq(z.phase, z.Phase.FINISH)
	_settle(z, Rules.FINISH_SECONDS + 0.2)
	assert_eq(z.next_screen, "party")
	assert_eq(Game.stars, 12)
	root.free()
	root = Node2D.new()
	add_child(root)
	Game._root = root
	# The bell: time runs out, every animal gets a snack at once, then the party.
	var z2 := _zoo()
	z2.run_len = 2.0
	_hungry(z2, "seal")
	_settle(z2, 2.1)
	assert_eq(z2.phase, z2.Phase.BELL)
	assert_eq(z2.flights.filter(func(f): return f.kind == "snack").size(), 6, "a snack for every animal")
	_settle(z2, 4.6)
	assert_eq(z2.next_screen, "party")
	assert_false(z2.animals["seal"].hungry)


func test_solo_keeper_can_pick_and_throw() -> void:
	_seat(1)
	var z := _zoo()
	assert_true(z.solo())
	_hungry(z, "rabbit")
	_stand_at(z, "rabbit")
	_step(z, {"demo:0": {}}, 2)
	assert_true(z.wheel.is_open)
	var at: Vector2 = z.keeper_pos
	_step(z, {"demo:0": {"move": Vector2.DOWN}})
	_step(z, {"demo:0": {}})
	assert_eq(z.wheel.selected, "carrot", "the keeper's own flick picks")
	assert_eq(z.keeper_pos, at, "a flick picks, it does not walk away")
	_step(z, {"demo:0": {"a": true}})
	_step(z, {"demo:0": {}})
	_settle(z, 1.0)
	assert_eq(z.meals, 1, "the keeper's a throws")
	# Holding the stick walks away again.
	_hungry(z, "elephant")
	_stand_at(z, "elephant")
	_step(z, {"demo:0": {}}, 2)
	_step(z, {"demo:0": {"move": Vector2.RIGHT}}, 30)
	assert_gt(z.keeper_pos.x, z.animals["elephant"].spot.x + 40.0)


func test_no_label_nodes_in_the_zoo_screen() -> void:
	_seat(3)
	var z := _zoo()
	_hungry(z, "giraffe")
	_stand_at(z, "giraffe")
	z.throw_food("banana")
	_settle(z, 1.0)
	var stack: Array[Node] = [z]
	var count := 0
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		count += 1
		assert_false(n is Label or n is RichTextLabel, "text node %s" % n.get_path())
		for c in n.get_children():
			stack.append(c)
	assert_gt(count, 300, "walked the whole tree")


# ---------------------------------------------------------------- more

func test_feeder_picks_with_dir4_and_throws_with_a() -> void:
	_seat(2)
	var z := _zoo()
	_hungry(z, "penguin")
	_stand_at(z, "penguin")
	_step(z, {"demo:1": {"move": Vector2.RIGHT}})
	assert_eq(z.wheel.selected, "fish")
	_step(z, {"demo:1": {"move": Vector2.ZERO, "a": true}})
	assert_eq(z.throws, 1)
	_settle(z, 1.0)
	assert_eq(z.meals, 1)
	assert_eq(z.stars, 1)


func test_a_with_nothing_picked_throws_nothing() -> void:
	_seat(2)
	var z := _zoo()
	_hungry(z, "seal")
	_stand_at(z, "seal")
	_step(z, {"demo:1": {"a": true}})
	assert_eq(z.throws, 0)


func test_round_break_after_six_meals() -> void:
	_seat(2)
	var z := _zoo()
	z.meals = 5
	_hungry(z, "monkey")
	_stand_at(z, "monkey")
	z.throw_food("banana")
	_settle(z, 0.8)
	assert_eq(z.phase, z.Phase.ROUND_BREAK)
	assert_false(z.throw_food("banana"), "no throwing in the dance")
	_settle(z, Rules.ROUND_BREAK + 0.2)
	assert_eq(z.phase, z.Phase.RUN)


func test_keeper_pauses_and_can_go_back_to_join() -> void:
	_seat(3)
	var z := _zoo()
	_step(z, {"demo:2": {"start": true}})
	assert_false(z.paused, "only the keeper pauses")
	_step(z, {"demo:2": {}, "demo:0": {"start": true}})
	assert_true(z.paused)
	var t: float = z.time
	_step(z, {"demo:0": {}}, 10)
	assert_eq(z.time, t, "time stands still")
	_step(z, {"demo:0": {"b": true}})
	assert_eq(z.next_screen, "join")
	assert_eq(Players.seated_count(), 0)


func test_idle_animals_call_out_without_a_singer() -> void:
	_seat(2)
	var z := _zoo()
	z.call_t = 0.1
	_step(z, {}, 6)
	var singing := 0
	for kind in z.animals:
		if z.animals[kind].action == "sing":
			singing += 1
	assert_eq(singing, 1)


func test_buddies_follow_the_keeper() -> void:
	_seat(3)
	var z := _zoo()
	assert_eq(z.buddies.size(), 3)
	_step(z, {"demo:0": {"move": Vector2.RIGHT}}, 60)
	for b in z.buddies:
		assert_lt(b.node.position.distance_to(z.keeper_pos), 260.0)
