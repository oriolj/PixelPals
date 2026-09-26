extends GutTest
## The peekaboo director, alone and inside the fort.

const Director := preload("res://scripts/fort/peekaboo_director.gd")
const Layout := preload("res://scripts/fort/room_layout.gd")
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


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Players.reset()
	Players.clear_scripted()


func _spots() -> Array:
	var out := []
	for s in Layout.SPOTS:
		out.append({"pos": s.pos, "open": 0.0})
	return out


func _fort(seats: int) -> Node:
	for i in seats:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
	Game.goto("fort")
	var f: Node = Game.current
	f.set_process(false)
	f.auto_goto = false
	return f


func _step(f: Node, toddler_a := false) -> void:
	if Players.is_seated(2):
		Players.set_scripted("demo:2", {"a": toddler_a})
	Players.poll()
	f.step(DT)


func test_pop_picks_the_free_spot_nearest_the_light() -> void:
	var d := Director.new()
	var spots := _spots()
	var r := d.press(spots, Vector2(296, 76))
	assert_eq(r.pop.spot, 7)
	# That spot is now busy, so the next pop (after the cooldown) goes elsewhere.
	for i in 40:
		d.step(DT)
	var r2 := d.press(spots, Vector2(296, 76))
	assert_true(r2.has("pop"))
	assert_ne(r2.pop.spot, 7)
	# An open (lifted) spot is skipped too.
	spots[6].open = 1.0
	for i in 40:
		d.step(DT)
	var r3 := d.press(spots, Vector2(262, 82))
	assert_ne(r3.pop.spot, 6)


func test_a_friend_eases_in_covers_its_eyes_then_says_peekaboo() -> void:
	assert_eq(Director.frame_at(0.1), 0)
	assert_eq(Director.frame_at(0.6), 1)
	assert_eq(Director.frame_at(1.2), 2)
	assert_eq(Director.frame_at(2.0), 3)
	# Rising takes the full 0.4 s, smoothly, and never jumps.
	var last := 0.0
	var t := 0.0
	while t < Director.DONE:
		var r := Director.rise_at(t)
		assert_true(absf(r - last) < 0.2, "no sudden jump at %.2f" % t)
		last = r
		t += DT
	assert_almost_eq(Director.rise_at(0.2), 0.5, 0.01)
	var d := Director.new()
	d.press(_spots(), Vector2(160, 90))
	var chimes := 0
	for i in int(Director.DONE / DT) + 2:
		chimes += d.step(DT).size()
	assert_eq(chimes, 1, "one peekaboo chime per friend")
	assert_true(d.friends.is_empty(), "then it ducks back and is gone")


func test_peekaboo_happens_only_after_a_press_when_seat_three_is_seated() -> void:
	var f := _fort(3)
	for i in int(90.0 / DT):
		_step(f)
	assert_eq(f.director.pops, 0, "a whole minute and a half: nothing pops by itself")
	_step(f, true)
	assert_eq(f.director.pops, 1)
	assert_eq(f.director.friends.size(), 1)
	# Near the light.
	var near: int = f.director.friends[0].spot
	for i in f.spots.size():
		assert_true(f.light_pos.distance_to(Vector2(f.spots[i].pos)) >= f.light_pos.distance_to(Vector2(f.spots[near].pos)) - 0.01)


func test_peekaboo_cooldown_still_twinkles_on_every_press() -> void:
	var f := _fort(3)
	_step(f, true)
	_step(f, false)
	assert_eq(f.director.pops, 1)
	for i in 4:           # four more presses inside the one-second cooldown
		_step(f, true)
		_step(f, false)
	assert_eq(f.director.pops, 1)
	assert_eq(f.director.twinkles, 4, "every press answered: the fairy lights twinkle")
	assert_gt(f.twinkle_t, 0.0)
	for i in int(1.0 / DT):
		_step(f)
	_step(f, true)
	assert_eq(f.director.pops, 2, "after the cooldown a friend pops again")


func test_without_a_toddler_a_friend_peeks_slowly_and_only_inside_the_light() -> void:
	var f := _fort(2)
	f.light_pos = Vector2(160, 20)  # over the wall, far from every spot
	for i in int(40.0 / DT):
		_step(f)
	assert_eq(f.director.pops, 0, "never outside the light")
	f.light_pos = Vector2(f.spots[3].pos)
	_step(f)
	assert_eq(f.director.pops, 1)
	assert_eq(f.director.friends[0].spot, 3)
	for i in int(20.0 / DT):
		_step(f)
	assert_eq(f.director.pops, 1, "about 25 s between peeks")
	for i in int(6.0 / DT):
		_step(f)
	assert_eq(f.director.pops, 2)


func test_a_friend_over_a_hidden_toy_shows_its_tip() -> void:
	var f := _fort(3)
	f.hide_toys({7: "bunny"})
	f.light_pos = Vector2(296, 60)   # nearest spot: 7, but the light is just off it
	_step(f, true)
	assert_eq(f.director.friends[0].spot, 7)
	_step(f)
	assert_true(f.tip_nodes[7].visible, "the toddler's free hint")
