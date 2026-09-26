extends GutTest
## Pure rules: food mapping, the wheel's directions, the hint ladder and the
## hunger scheduler.

const Rules := preload("res://scripts/zoo/rules.gd")
const Scheduler := preload("res://scripts/zoo/scheduler.gd")
const FoodWheel := preload("res://scripts/zoo/food_wheel.gd")


func test_each_animal_has_exactly_one_right_food() -> void:
	assert_eq(Rules.ANIMALS.size(), 6)
	var per_food := {}
	for a in Rules.ANIMALS:
		var right := 0
		for f in Rules.FOODS:
			if Rules.accepts(a, f):
				right += 1
		assert_eq(right, 1, "%s eats exactly one food" % a)
		per_food[Rules.right_food(a)] = per_food.get(Rules.right_food(a), 0) + 1
	assert_eq(Rules.right_food("monkey"), "banana")
	assert_eq(Rules.right_food("penguin"), "fish")
	assert_eq(Rules.right_food("seal"), "fish")
	assert_eq(Rules.right_food("rabbit"), "carrot")
	assert_eq(Rules.right_food("elephant"), "hay")
	assert_eq(Rules.right_food("giraffe"), "hay")
	for f in Rules.FOODS:
		assert_true(per_food.get(f, 0) >= 1, "%s is somebody's food" % f)


func test_wheel_maps_dir4_to_the_four_foods() -> void:
	assert_eq(Rules.food_for_dir(Vector2i.UP), "banana")
	assert_eq(Rules.food_for_dir(Vector2i.RIGHT), "fish")
	assert_eq(Rules.food_for_dir(Vector2i.DOWN), "carrot")
	assert_eq(Rules.food_for_dir(Vector2i.LEFT), "hay")
	assert_eq(Rules.food_for_dir(Vector2i.ZERO), "")
	var w: Node2D = FoodWheel.new()
	add_child_autofree(w)
	w.open(true)
	for d in [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]:
		assert_true(w.select_dir(d))
		assert_eq(w.selected, Rules.food_for_dir(d))
		assert_eq(Rules.dir_for_food(w.selected), d)
	assert_false(w.select_dir(Vector2i.ZERO), "no direction keeps the pick")
	assert_eq(w.selected, "hay")


func test_hint_ladder_levels() -> void:
	assert_eq(Rules.hint_for(0), Rules.Hint.NONE)
	assert_eq(Rules.hint_for(1), Rules.Hint.WIGGLE)
	assert_eq(Rules.hint_for(2), Rules.Hint.GLOW)
	assert_false(Rules.throw_succeeds("monkey", "hay", 0))
	assert_false(Rules.throw_succeeds("monkey", "hay", 1))
	assert_true(Rules.throw_succeeds("monkey", "hay", 2), "the third try always works")
	assert_true(Rules.throw_succeeds("monkey", "banana", 0))


func test_scheduler_feeds_every_animal_twice() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 200:
		rng.seed = s
		var sch := Scheduler.new()
		var order := sch.build(rng)
		assert_eq(order.size(), 12)
		var counts := {}
		for a in order:
			counts[a] = counts.get(a, 0) + 1
		for a in Rules.ANIMALS:
			assert_eq(counts.get(a, 0), 2, "seed %d: %s twice" % [s, a])
		# Every animal once per round.
		var first_round := {}
		for i in 6:
			first_round[order[i]] = true
		assert_eq(first_round.size(), 6, "seed %d: round one has all six" % s)


func test_scheduler_never_asks_one_food_three_times_in_a_row() -> void:
	var rng := RandomNumberGenerator.new()
	for s in 300:
		rng.seed = s
		var sch := Scheduler.new()
		var first: Array[String] = []
		if s % 2 == 0:
			first.assign(["monkey", "penguin"])
		var order := sch.build(rng, first)
		for i in range(2, order.size()):
			var f := Rules.right_food(order[i])
			var run := f == Rules.right_food(order[i - 1]) and f == Rules.right_food(order[i - 2])
			assert_false(run, "seed %d: %s three times at %d" % [s, f, i])
		if s % 2 == 0:
			assert_eq(order.slice(0, 2), ["monkey", "penguin"] as Array[String], "pinned start for the demo")


func test_scheduler_hands_out_in_order() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var sch := Scheduler.new()
	var order := sch.build(rng)
	var got: Array[String] = []
	while sch.has_next():
		got.append(sch.take())
	assert_eq(got, order)
	assert_eq(sch.take(), "")
	assert_eq(sch.taken(), 12)
