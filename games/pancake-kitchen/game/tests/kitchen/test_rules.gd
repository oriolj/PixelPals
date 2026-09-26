extends GutTest
## The kitchen rules, pure logic (PLAN.md "Tests and verification").

const Rules := preload("res://scripts/kitchen/rules.gd")
const DT := 1.0 / 30.0

var r: Rules


func before_each() -> void:
	r = Rules.new(42)
	r.start()


func _run(seconds: float, pan_follow := false) -> void:
	var n := int(seconds / DT)
	for i in n:
		if pan_follow and r.in_air():
			r.pan_x = clampf(r.predict_landing_x(), Rules.PAN_MIN_X, Rules.PAN_MAX_X)
		r.step(DT)


func _cook_ready() -> void:
	# Past the pour, sitting in the pan.
	_run(Rules.POUR_TIME + 0.1)
	assert_eq(r.pancake.state, Rules.P.IN_PAN)


func test_flip_only_starts_when_the_pancake_is_in_the_pan() -> void:
	assert_eq(r.pancake.state, Rules.P.POURING)
	assert_false(r.try_flip(), "no flip while the batter pours")
	assert_eq(r.pancake.state, Rules.P.POURING)
	_cook_ready()
	assert_true(r.try_flip())
	assert_eq(r.pancake.state, Rules.P.FLYING)
	assert_false(r.try_flip(), "a second press in the air is not a flip")
	r.pancake = null
	assert_false(r.try_flip(), "no pancake, no flip (and no crash)")


func test_flip_arc_lands_where_the_math_says() -> void:
	_cook_ready()
	r.pan_x = 300.0
	r.next_flip_vx = 70.0
	r.try_flip()
	var v: Vector2 = r.pancake.launch_vel
	assert_eq(v.x, 70.0)
	# Closed form: back at pan height after 2*vy/g, at x0 + vx * T.
	var t_land := -2.0 * v.y / Rules.GRAVITY
	var want_x := 300.0 + 70.0 * t_land
	assert_almost_eq(r.predict_landing_x(), want_x, 0.01)
	assert_almost_eq(r.time_to_y(Rules.PAN_Y), t_land, 0.0001)
	# The stepped flight passes through the same points.
	r.pan_x = Rules.PAN_MAX_X  # away, so nothing catches it early
	for i in 20:
		r.step(DT)
	var t: float = r.pancake.t
	var expect := Vector2(300.0 + 70.0 * t, Rules.PAN_Y + v.y * t + 0.5 * Rules.GRAVITY * t * t)
	assert_almost_eq(r.pancake.pos.x, expect.x, 0.01)
	assert_almost_eq(r.pancake.pos.y, expect.y, 0.01)
	var peak := Rules.PAN_Y - v.y * v.y / (2.0 * Rules.GRAVITY)
	assert_between(peak, 20.0, 160.0, "the flip peaks high but on screen")


func _flip_with_pan_offset(offset: float) -> Rules.Pancake:
	_cook_ready()
	r.pan_x = 380.0
	r.next_flip_vx = 40.0
	r.try_flip()
	var land := r.predict_landing_x()
	r.pan_x = land + offset
	var p := r.pancake
	var caught := false
	for i in 120:
		r.step(DT)
		if p.state == Rules.P.CATCHING:
			caught = true
		if p.state == Rules.P.GAG or p.state == Rules.P.IN_PAN:
			break
	return p


func test_pan_within_magnet_radius_catches() -> void:
	var p := _flip_with_pan_offset(55.0)
	assert_eq(p.state, Rules.P.IN_PAN, "55 px off is still a catch")
	assert_eq(p.flips, 1)
	assert_true(r.drain_events().has("catch"))


func test_pan_outside_magnet_radius_misses() -> void:
	var p := _flip_with_pan_offset(-Rules.MAGNET - 40.0)
	assert_eq(p.state, Rules.P.GAG)


func test_missed_pancake_always_returns_to_the_pan() -> void:
	# Many seeds, the pan always parked far from the landing, and a pan that
	# keeps moving during the gag: every flight ends back in the pan.
	for seed_value in range(1, 41):
		r = Rules.new(seed_value)
		r.start()
		_run(Rules.POUR_TIME + 0.1)
		r.pan_x = [Rules.PAN_MIN_X, Rules.PAN_MAX_X, 380.0][seed_value % 3]
		r.try_flip()
		var land := r.predict_landing_x()
		r.pan_x = Rules.PAN_MAX_X if land < 380.0 else Rules.PAN_MIN_X
		var gags := {}
		var back := false
		for i in int(6.0 / DT):
			r.move_pan(sin(i * 0.05), DT)
			r.step(DT)
			if r.pancake.state == Rules.P.GAG:
				gags[r.pancake.gag] = true
			if r.pancake.state == Rules.P.IN_PAN or r.pancake.state == Rules.P.SETTLING:
				back = true
				break
		assert_true(back, "seed %d: back in the pan" % seed_value)
		assert_eq(r.pancake.flips, 1, "a gag landing counts as the flip")


func test_every_gag_kind_returns_to_the_pan() -> void:
	for kind in ["dog", "cat", "bounce"]:
		r = Rules.new(3)
		r.start()
		_run(Rules.POUR_TIME + 0.1)
		r.try_flip()
		r.pancake.pos = Vector2(200, Rules.MISS_LINE)
		r._start_gag(r.pancake, kind)
		_run(4.0)
		assert_eq(r.pancake.state, Rules.P.IN_PAN, kind)


func test_misses_pick_the_dog_left_and_the_counter_right() -> void:
	_cook_ready()
	r.pan_x = Rules.PAN_MIN_X
	r.next_flip_vx = -60.0
	r.try_flip()
	r.pan_x = Rules.PAN_MAX_X
	_run(2.0)
	assert_eq(r.pancake.gag, "dog")
	r = Rules.new(5)
	r.start()
	_cook_ready()
	r.pan_x = 420.0
	r.next_flip_vx = 60.0
	r.try_flip()
	r.pan_x = Rules.PAN_MIN_X
	_run(1.6)
	assert_eq(r.pancake.gag, "bounce")


func test_pancake_never_burns() -> void:
	_cook_ready()
	_run(120.0)
	assert_eq(r.pancake.state, Rules.P.IN_PAN, "it just waits in the pan")
	assert_eq(r.pancake.cook_bottom, 1.0, "golden, not past it")
	var Pal := preload("res://scripts/kitchen/palette.gd")
	assert_true(Pal.cook_color(5.0).is_equal_approx(Pal.GOLDEN), "past golden stays golden")


func test_flipping_an_uncooked_pancake_still_flips() -> void:
	_cook_ready()
	assert_lt(r.pancake.cook_bottom, 0.1)
	assert_true(r.try_flip())
	_run(3.0, true)
	assert_eq(r.pancake.flips, 1)


func test_two_flips_move_the_pancake_to_the_plate() -> void:
	_cook_ready()
	r.try_flip()
	_run(2.0, true)
	assert_eq(r.pancake.flips, 1)
	assert_eq(r.pancake.state, Rules.P.IN_PAN)
	assert_eq(r.stack.size(), 0)
	r.try_flip()
	_run(2.0, true)
	_run(Rules.SETTLE_TIME + Rules.HOP_TIME + 0.1)
	assert_eq(r.stack.size(), 1, "it hopped onto the plate")
	assert_eq(r.pancake.state, Rules.P.POURING, "and the next one pours")


func test_toppings_stick_inside_the_pancake_ellipse() -> void:
	r.stack = [{"cook": 1.0}, {"cook": 1.0}]
	for i in 40:
		r.jar = i % 4
		r.drop_topping()
		r.step(0.05)
	_run(1.0)
	assert_eq(r.toppings.size(), 40)
	for tp in r.toppings:
		assert_eq(tp.level, 1, "on the top pancake")
		var v: Vector2 = tp.pos
		var k := pow(v.x / Rules.PANCAKE_A, 2) + pow(v.y / Rules.PANCAKE_B, 2)
		assert_lte(k, 1.0, "inside the ellipse: %s" % v)
	# Clamp: a point far outside is pulled onto the pancake.
	var c := Rules.clamp_to_ellipse(Vector2(300, 90))
	assert_lte(pow(c.x / Rules.PANCAKE_A, 2) + pow(c.y / Rules.PANCAKE_B, 2), 1.0)


func test_topping_on_an_empty_plate_lands_on_the_plate() -> void:
	r.drop_topping("banana")
	_run(1.0)
	assert_eq(r.toppings.size(), 1)
	assert_eq(r.toppings[0].level, -1)


func test_every_topping_combo_makes_the_customer_happy() -> void:
	# Every multiset of up to 4 toppings from the 4 jars.
	var combos: Array = [[]]
	for depth in 4:
		var next: Array = []
		for c in combos:
			for kind in Rules.TOPPINGS:
				next.append(c + [kind])
		combos.append_array(next)
		combos = combos.filter(func(x): return true)
	var checked := 0
	for c in combos:
		assert_true(Rules.happy(c))
		assert_gte(Rules.reaction_size(c.size()), 1)
		checked += 1
	assert_gt(checked, 300)


func test_reaction_size_grows_with_topping_count() -> void:
	var last := 0
	var sizes := {}
	for n in 30:
		var s := Rules.reaction_size(n)
		assert_gte(s, last, "never smaller with more toppings")
		assert_between(s, 1, 3)
		sizes[s] = true
		last = s
	assert_eq(sizes.size(), 3, "three reaction sizes")
	assert_eq(Rules.reaction_size(0), 1, "a plain stack still makes them happy")


func _wait_customer() -> void:
	_run(Rules.WALK_TIME + 0.1)
	assert_true(r.customer_waiting())


func test_stack_of_three_can_be_served() -> void:
	_wait_customer()
	r.stack = [{"cook": 1.0}, {"cook": 1.0}]
	assert_false(r.can_serve())
	assert_false(r.serve(), "two is not enough")
	r.stack.append({"cook": 1.0})
	assert_true(r.plate_ready())
	assert_true(r.serve())
	assert_eq(r.stack.size(), 0, "a fresh plate")
	assert_eq(r.customer.stack.size(), 3)
	_run(Rules.SLIDE_TIME + Rules.EAT_TIME + 0.2)
	assert_eq(r.customer.state, Rules.C.HAPPY)
	_run(Rules.HAPPY_TIME + 0.1)
	assert_eq(r.served, 1)


func test_customers_sprinkle_their_own_without_a_topper() -> void:
	r.self_sprinkle = true
	_wait_customer()
	r.stack = [{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}]
	r.serve()
	_run(Rules.SLIDE_TIME + Rules.SPRINKLE_TIME + 0.1)
	assert_between(r.customer.toppings.size(), 2, 5)


func _serve_one() -> void:
	while not r.customer_waiting():
		r.step(DT)
	r.stack = [{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}]
	assert_true(r.serve())
	while r.customer != null and r.customer.state != Rules.C.LEAVE:
		r.step(DT)
	_run(Rules.LEAVE_TIME + 0.1)


func test_round_ends_after_six_customers_or_at_seven_minutes() -> void:
	for i in 6:
		assert_false(r.round_over)
		_serve_one()
	assert_true(r.round_over)
	assert_eq(r.served, 6)
	assert_eq(r.plates.size(), 6)
	assert_false(r.finale)
	# Seven minutes with nobody serving: everyone gets a pancake at once.
	r = Rules.new(9)
	r.start()
	_run(Rules.ROUND_LIMIT - 1.0)
	assert_false(r.round_over, "no timer runs out early")
	_run(2.0)
	assert_true(r.round_over)
	assert_true(r.finale)
	assert_eq(r.plates.size(), 6, "every customer got a plate")
	for pl in r.plates:
		assert_eq(pl.stack.size(), 3)


func test_toddler_spam_in_the_air_only_adds_spin() -> void:
	_cook_ready()
	r.next_flip_vx = 50.0
	r.try_flip()
	var twin := Rules.new(42)
	twin.start()
	twin.pancake.state = Rules.P.IN_PAN
	twin.pan_x = r.pan_x
	twin.next_flip_vx = 50.0
	twin.launch(r.pancake.launch_vel)
	for i in 25:
		for k in 3:
			r.try_flip()       # the toddler mashes
		r.step(DT)
		twin.step(DT)
		assert_almost_eq(r.pancake.pos.x, twin.pancake.pos.x, 0.001)
		assert_almost_eq(r.pancake.pos.y, twin.pancake.pos.y, 0.001)
	assert_eq(r.pancake.extra_spins, Rules.MAX_EXTRA_SPINS)
	assert_gt(r.pancake.spin, twin.pancake.spin, "only the spin changed")
	assert_true(r.drain_events().has("spin"))


func test_toddler_press_with_nothing_to_flip_is_still_fun() -> void:
	r.drain_events()
	assert_false(r.try_flip())  # pouring
	assert_eq(r.drain_events(), ["toddler_fun"] as Array[String])
