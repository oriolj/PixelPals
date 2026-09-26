extends GutTest
## The fort screen driven frame by frame with scripted devices.

const DT := 1.0 / 30.0
const Layout := preload("res://scripts/fort/room_layout.gd")
const LightMask := preload("res://scripts/fort/light_mask.gd")

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.round_seconds = Game.ROUND_SECONDS
	Game.toys_found.clear()
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
	Game.round_seconds = Game.ROUND_SECONDS
	Players.reset()
	Players.clear_scripted()


func _seat(n: int) -> void:
	for i in n:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]


func _fort(seats := 3) -> Node:
	_seat(seats)
	Game.goto("fort")
	var f: Node = Game.current
	f.set_process(false)
	f.auto_goto = false
	f.rng.seed = 7
	f.hide_toys()
	return f


func _drive(seat: int, state: Dictionary, f: Node) -> void:
	Players.set_scripted("demo:%d" % seat, state)
	Players.poll()
	f.step(DT)


func _tap(seat: int, button: String, f: Node) -> void:
	_drive(seat, {button: true}, f)
	_drive(seat, {}, f)


func _idle(f: Node, seconds: float) -> void:
	for i in int(round(seconds / DT)):
		Players.poll()
		f.step(DT)


func _first(f: Node, with_toy: bool) -> int:
	for i in f.spots.size():
		if (f.spots[i].toy != "") == with_toy:
			return i
	return -1


func _light_on(f: Node, spot: int) -> void:
	f.light_pos = Vector2(f.spots[spot].pos)
	f.light_vel = Vector2.ZERO


func test_eight_toys_hide_in_eight_distinct_spots() -> void:
	var f := _fort()
	var toys := []
	for s in f.spots:
		if s.toy != "":
			assert_false(toys.has(s.toy))
			toys.append(s.toy)
	assert_eq(toys.size(), 8)


func test_lifting_an_empty_spot_always_gives_a_small_surprise() -> void:
	var f := _fort()
	var empty := _first(f, false)
	var kinds := {}
	for i in 9:
		var r: Dictionary = f.lift(empty)
		assert_true(r.has("surprise"), "lift %d: %s" % [i, r])
		assert_true(["sock", "sleepy_mouse", "cookie"].has(r.surprise))
		kinds[r.surprise] = true
		_idle(f, f.OPEN_TIME + 0.1)
	assert_eq(kinds.size(), 3, "all three surprises come round")
	assert_eq(f.found.size(), 0)


func test_found_toy_goes_to_the_basket_and_never_hides_again() -> void:
	var f := _fort()
	var spot := _first(f, true)
	var toy: String = f.spots[spot].toy
	var r: Dictionary = f.lift(spot)
	assert_eq(r.get("toy"), toy)
	assert_eq(f.found, [toy] as Array[String])
	assert_eq(f.basket.size(), 0, "flying first")
	_idle(f, 1.2)
	assert_eq(f.basket, [toy] as Array[String])
	assert_eq(f.basket_spr.frame, 1, "the basket sprite fills")
	# The spot is empty for good, and the toy is nowhere else.
	_idle(f, f.OPEN_TIME)
	for i in 5:
		assert_true(f.lift(spot).has("surprise"))
		_idle(f, f.OPEN_TIME + 0.1)
	for s in f.spots:
		assert_ne(s.toy, toy)
	assert_eq(f.found.count(toy), 1)


func test_seeker_hops_the_paw_and_lifts_with_a() -> void:
	var f := _fort()
	var start: int = f.paw_spot
	_drive(1, {"move": Vector2.RIGHT}, f)
	_drive(1, {}, f)
	var after: int = f.paw_spot
	assert_eq(after, f.graph.hop(start, Vector2i.RIGHT))
	var lifts: int = f.lift_count
	_tap(1, "a", f)
	assert_eq(f.lift_count, lifts + 1)
	assert_gt(f.spots[after].open, 0.0)


func test_flashlight_a_lifts_only_when_the_seeker_seat_is_empty() -> void:
	var f := _fort(3)
	_light_on(f, 7)
	_tap(0, "a", f)
	assert_eq(f.lift_count, 0, "the seeker does the lifting when seated")
	root.free()
	Players.reset()
	root = Node2D.new()
	add_child(root)
	Game._root = root
	var solo := _fort(1)
	_light_on(solo, 7)
	_tap(0, "a", solo)
	assert_eq(solo.lift_count, 1)


func test_dwell_reveal_lifts_after_one_and_a_half_seconds_solo() -> void:
	var f := _fort(1)
	_light_on(f, 9)
	_idle(f, 1.4)
	assert_eq(f.lift_count, 0)
	_idle(f, 0.2)
	assert_eq(f.lift_count, 1)
	# Resting on the same spot does not keep lifting it.
	_idle(f, 5.0)
	assert_eq(f.lift_count, 1)
	# With a seeker seated, the light never lifts by itself.
	root.free()
	Players.reset()
	root = Node2D.new()
	add_child(root)
	Game._root = root
	var duo := _fort(2)
	_light_on(duo, 9)
	_idle(duo, 3.0)
	assert_eq(duo.lift_count, 0)


func test_toy_tips_show_only_in_the_flashlight() -> void:
	var f := _fort(2)
	var spot := _first(f, true)
	f.light_pos = Vector2(5, 5)
	_idle(f, DT)
	assert_false(f.tip_nodes[spot].visible)
	_light_on(f, spot)
	_idle(f, DT)
	assert_true(f.tip_nodes[spot].visible)
	var empty := _first(f, false)
	_light_on(f, empty)
	_idle(f, DT)
	assert_false(f.tip_nodes[empty].visible)


func test_hint_glow_starts_after_forty_five_seconds_without_a_find() -> void:
	var f := _fort(2)
	f.light_pos = Vector2(5, 5)
	_idle(f, 44.5)
	assert_eq(f.hint_spot, -1)
	_idle(f, 1.0)
	assert_ne(f.hint_spot, -1)
	assert_ne(f.spots[f.hint_spot].toy, "", "the glow is on a spot that hides a toy")
	# The nearest one to the paw.
	var paw := Vector2(f.spots[f.paw_spot].pos)
	for i in f.spots.size():
		if f.spots[i].toy != "":
			assert_true(paw.distance_to(Vector2(f.spots[i].pos)) >= paw.distance_to(Vector2(f.spots[f.hint_spot].pos)))
	# It shows even outside the flashlight, and a find clears it.
	assert_true(f.tip_nodes[f.hint_spot].visible)
	f.lift(f.hint_spot)
	assert_eq(f.hint_spot, -1)
	assert_eq(f.since_find, 0.0)


func test_round_ends_at_eight_toys_or_six_minutes() -> void:
	# (a) all eight found
	var f := _fort()
	for i in f.spots.size():
		if f.spots[i].toy != "":
			f.lift(i)
	assert_true(f.round_over)
	_idle(f, 1.2)
	assert_eq(f.basket.size(), 8)
	_idle(f, f.LAMP_FADE)
	assert_almost_eq(f.mask_strength(), 0.0, 0.01, "the lamp is on: no dusk left")
	_idle(f, f.LAMP_STAY + 0.2)
	assert_eq(f.next_screen, "party")
	assert_eq(Game.toys_found.size(), 8)
	# (b) nothing found: at six minutes the toys walk out on their own
	root.free()
	Players.reset()
	root = Node2D.new()
	add_child(root)
	Game._root = root
	var g := _fort()
	assert_eq(Game.round_seconds, 360.0)
	_idle(g, 359.0)
	assert_false(g.round_over)
	_idle(g, 1.2)
	assert_true(g.round_over)
	_idle(g, 8.0 * g.WALK_EVERY + 3.0 + g.LAMP_FADE + g.LAMP_STAY)
	assert_eq(g.basket.size(), 8, "every toy walked into the basket")
	assert_eq(g.next_screen, "party")


func test_the_dusk_never_goes_past_sixty_percent_during_a_round() -> void:
	var f := _fort()
	var worst := 0.0
	for i in 200:
		_drive(2, {"a": i % 7 == 0}, f)
		worst = maxf(worst, f.mask_strength())
		worst = maxf(worst, f.mask_mat.get_shader_parameter("strength"))
	assert_true(worst <= 0.6)
	assert_true(worst >= 0.5, "still a dusk (the fort is at bedtime)")


func test_no_label_nodes_in_the_fort_screen() -> void:
	var f := _fort()
	_idle(f, 1.0)
	var stack: Array[Node] = [f]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		assert_false(n is Label or n is RichTextLabel or n is LineEdit or n is Button,
			"%s is a text node" % n.get_path())
		for c in n.get_children():
			stack.append(c)


func test_pause_is_the_flashlight_seat_only_and_b_goes_to_join() -> void:
	var f := _fort()
	_tap(1, "start", f)
	assert_false(f.paused)
	_tap(0, "start", f)
	assert_true(f.paused)
	var t: float = f.time
	_idle(f, 1.0)
	assert_eq(f.time, t, "time stands still in pause")
	_tap(0, "b", f)
	assert_eq(f.next_screen, "join")


func test_works_with_one_two_or_three_seats() -> void:
	for n in [1, 2, 3]:
		if is_instance_valid(root):
			root.free()
		Players.reset()
		root = Node2D.new()
		add_child(root)
		Game._root = root
		Game.round_seconds = 30.0
		var f := _fort(n)
		for i in int(46.0 / DT):
			var st := {"move": Vector2(sin(i * 0.05), cos(i * 0.03)), "a": i % 40 == 0}
			for s in n:
				Players.set_scripted("demo:%d" % s, st)
			Players.poll()
			f.step(DT)
		assert_eq(f.next_screen, "party", "%d seats" % n)
		assert_eq(f.basket.size(), 8)


func test_the_toddler_never_hurts_the_run() -> void:
	var f := _fort()
	var spot := _first(f, true)
	for i in 300:
		_drive(2, {"a": i % 2 == 0, "b": i % 3 == 0, "start": i % 5 == 0}, f)
	assert_false(f.paused, "the toddler cannot pause")
	assert_eq(f.found.size(), 0, "nor lift, nor lose anything")
	assert_ne(f.spots[spot].toy, "")
	assert_eq(f.next_screen, "")
