extends GutTest
## The house screen driven frame by frame with scripted seats: every test the
## plan names, plus the no-fail timers, gags and the real-meow hook.

const Cat := preload("res://scripts/house/cat.gd")
const HideDirector := preload("res://scripts/house/hide_director.gd")
const DT := 1.0 / 30.0
## Greyssie on the TV box (bold, comes out alone), Kira under the sofa (shy):
## both in the living room, where the walker starts.
const LIVING := {"greyssie": "tv_box", "kira": "sofa"}

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.load_data(Game.HOUSE_PATH, Game.CATS_PATH)
	Game.finds.clear()
	Game.start_round = 0
	Sfx.muted = true
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
	Game.start_round = 0
	Players.reset()
	Players.clear_scripted()
	Game.load_data(Game.HOUSE_PATH, Game.CATS_PATH)


# ---------------------------------------------------------------- helpers

func _seat(seats: Array) -> void:
	for s in seats:
		Players.set_scripted("demo:%d" % s, {})
		Players.join_seat("demo:%d" % s, s)
	Players.riders[Game.WALKER] = "penguin"


func _level(seats := [0, 1, 2], placement := LIVING) -> Node:
	_seat(seats)
	Game.goto("house")
	var l: Node = Game.current
	l.set_process(false)
	l.auto_goto = false
	l.rng.seed = 5
	l.start_round(0, placement, true)
	return l


func _set_in(seat: int, state: Dictionary) -> void:
	Players.set_scripted("demo:%d" % seat, state)


func _run(l: Node, seconds: float) -> void:
	var n := int(roundf(seconds / DT))
	for i in n:
		Players.poll()
		l.step(DT)


func _tap(l: Node, seat: int, button := "a") -> void:
	_set_in(seat, {button: true})
	_run(l, DT)
	_set_in(seat, {})
	_run(l, DT)


func _cat(l: Node, id: String) -> Node:
	return l._cat(id)


func _stand_at_spot(l: Node, sid: String) -> void:
	var s: Dictionary = l.house.spots[sid]
	l.walker_floor = s.floor
	l.walker_x = float(s.x)


func _free_near_walker(l: Node, id: String, dx: float) -> Node:
	var c: Node = _cat(l, id)
	c.floor_i = l.walker_floor
	c.x = l.walker_x + dx
	c.elev = 0.0
	c.spot = ""
	c.found = true
	c.visible = true
	c.zoomed = true
	c._become_free(false)
	return c


# ---------------------------------------------------------------- the house

func test_house_graph_connects_every_room() -> void:
	var h: RefCounted = Game.house
	assert_eq(h.errors, [] as Array[String], "the default house.json parses cleanly")
	assert_true(h.connected())
	var from: String = h.start.room
	for rid in h.rooms:
		assert_false(h.path_rooms(from, rid).is_empty(), "%s is reachable from %s" % [rid, from])
	assert_eq(h.floor_count(), 3, "three floors")
	assert_gte(h.spots.size(), 20, "about 20 hiding spots")


func test_stairs_move_between_floors() -> void:
	var l := _level()
	var h: RefCounted = l.house
	l.walker_floor = 0
	l.walker_x = h.room_center("living")
	_set_in(0, {"move": Vector2(0, -1)})
	_run(l, 1.2)
	assert_eq(l.walker_floor, 0, "no stairs in the living room: up does nothing")
	l.walker_x = h.room_center("stairs_ground")
	_run(l, 1.2)
	assert_eq(l.walker_floor, 1, "up the stairs to the first floor")
	_run(l, 1.2)
	assert_eq(l.walker_floor, 2, "and on to the top floor")
	_run(l, 1.2)
	assert_eq(l.walker_floor, 2, "nothing above the top floor")
	_set_in(0, {"move": Vector2(0, 1)})
	_run(l, 1.2)
	assert_eq(l.walker_floor, 1, "back down")
	assert_eq(l.walker_room(), "stairs_first")


func test_camera_frames_the_walkers_floor() -> void:
	var l := _level()
	l.walker_floor = 2
	l.walker_x = 60.0
	_run(l, 2.0)
	assert_almost_eq(l.cam.y, float(l.house.band_top(2)), 1.0)
	assert_true(l.laser_pos.y > l.house.band_top(2) and l.laser_pos.y <= l.house.floor_y(2), "the dot is on the walker's floor")


# ---------------------------------------------------------------- hiding

func test_each_cat_hides_in_a_valid_spot_per_round() -> void:
	var l := _level()
	for seed in 12:
		l.rng.seed = seed
		for r in Game.DAY.size():
			l.start_round(r, {}, true)
			for c in l.cats:
				assert_true(l.house.spots.has(c.spot), "%s hides in a real spot (%s)" % [c.id, c.spot])
				assert_eq(c.state, Cat.State.HIDDEN)
				assert_eq(c.floor_i, l.house.spots[c.spot].floor)
				assert_false(c.visible, "a hidden cat shows only its tell")


func test_cats_never_share_a_spot() -> void:
	var rng := RandomNumberGenerator.new()
	for seed in 300:
		rng.seed = seed
		var p: Dictionary = HideDirector.choose(Game.house, Game.cat_data.cats, seed % 4 == 3, rng)
		assert_eq(p.size(), 2)
		assert_ne(p.greyssie, p.kira)


func test_the_round_intro_hides_both_cats() -> void:
	var l := _level()
	l.start_round(1)
	assert_eq(l.state, l.State.INTRO)
	_run(l, 2.5)
	assert_eq(l.state, l.State.SEARCH)
	for c in l.cats:
		assert_eq(c.state, Cat.State.HIDDEN)
	assert_eq(l.placement.size(), 2, "both cats got a spot")


func test_night_cats_prefer_cosy_spots() -> void:
	var rng := RandomNumberGenerator.new()
	var cosy := [0, 0]
	for night in 2:
		for seed in 400:
			rng.seed = seed
			var p: Dictionary = HideDirector.choose(Game.house, Game.cat_data.cats, night == 1, rng)
			for id in p:
				cosy[night] += int(Game.house.spots[p[id]].cosy)
	assert_gt(cosy[1], cosy[0] + 150, "sleepy cats pick cosy spots at night")


func test_personalities_show_in_hiding_tastes() -> void:
	var rng := RandomNumberGenerator.new()
	var high := {"greyssie": 0, "kira": 0}
	for seed in 400:
		rng.seed = seed
		var p: Dictionary = HideDirector.choose(Game.house, Game.cat_data.cats, false, rng)
		for id in p:
			high[id] += int(Game.house.spots[p[id]].tags.has("high"))
	assert_gt(high.greyssie, high.kira * 3, "Greyssie likes high places, Kira does not")


func test_hiding_cats_show_a_tell_and_the_tail_pokes_further_at_60s() -> void:
	var l := _level([0, 1, 2], {"greyssie": "tv_box", "kira": "kids_bed"})
	_run(l, 1.0)
	var tail: AnimatedSprite2D = l.tell_nodes["greyssie"]
	var eyes: AnimatedSprite2D = l.tell_nodes["kira"]
	assert_true(tail.visible, "Greyssie's tail tip pokes out of the blanket on the TV")
	assert_eq(tail.get_meta("name"), "greyssie_tail_tip")
	assert_eq(eyes.get_meta("name"), "kira_peek_eyes", "under the bed: eyes")
	assert_eq(tail.frame, 0)
	_run(l, 60.0)
	assert_eq(tail.frame, 1, "at 60 s the tail pokes out further")


# ---------------------------------------------------------------- treats + meows

func test_treat_shake_makes_nearest_cat_meow() -> void:
	var l := _level([0, 1, 2], {"greyssie": "tv_box", "kira": "kids_bed"})
	l.walker_floor = 0
	l.walker_x = l.house.room_center("living")
	_tap(l, 2)
	assert_eq(l.shakes, 1)
	assert_eq(l.meows.greyssie, 1, "Greyssie is nearest (same room)")
	assert_eq(l.meows.kira, 0)
	_run(l, 0.7)
	assert_eq(l.meows.greyssie, 2, "chatty Greyssie meows back twice")
	l.walker_floor = 1
	l.walker_x = l.house.room_center("kids")
	_run(l, 1.0)
	_tap(l, 2)
	assert_eq(l.meows.kira, 1, "upstairs, Kira is nearest")
	_run(l, 1.0)
	assert_eq(l.meows.kira, 1, "quiet Kira meows once")


func test_meow_reveals_the_room_in_mini_view() -> void:
	var l := _level([0, 1, 2], {"greyssie": "wardrobe_top", "kira": "toy_box"})
	l.walker_floor = 0
	l.walker_x = l.house.room_center("living")
	_tap(l, 2)
	var c: Node = _cat(l, l.last_meow_cat)
	assert_true(l.mini.visible, "the whole-house view flashes")
	assert_eq(l.mini.lit_room, l.house.spots[c.spot].room)
	assert_eq(l.mini.lit_color, c.info.collar, "lit in the cat's collar colour")
	assert_true(l.bubble.visible, "a meow bubble")
	var rr: Rect2i = l.mini.room_rect(l.mini.lit_room)
	assert_true(Rect2i(0, 0, 64, 40).encloses(rr), "the lit room is inside the mini view")
	_run(l, 2.5)
	assert_false(l.mini.visible, "gone after 2 s")
	assert_false(l.bubble.visible)


func test_mini_view_rooms_do_not_overlap() -> void:
	var l := _level()
	var rects := []
	for rid in l.house.rooms:
		rects.append(l.mini.room_rect(rid))
	for i in rects.size():
		for j in range(i + 1, rects.size()):
			assert_false(rects[i].intersects(rects[j]), "mini rooms %d and %d overlap" % [i, j])


# ---------------------------------------------------------------- coaxing

func test_bold_cat_comes_out_when_its_spot_opens() -> void:
	var l := _level()
	_stand_at_spot(l, "tv_box")
	assert_eq(l.walker_action(), "open")
	var g: Node = _cat(l, "greyssie")
	assert_eq(g.state, Cat.State.ALERT, "eyes wide: mrrp?")
	_run(l, 1.5)
	assert_true(g.pickable(), "Greyssie hops out on her own")
	assert_eq(g.elev, 0.0)


func test_laser_lures_shy_cat_out() -> void:
	var l := _level()
	_stand_at_spot(l, "sofa")
	l.walker_x += 10.0
	assert_eq(l.open_spot("sofa"), {"cat": "kira"})
	var k: Node = _cat(l, "kira")
	_run(l, 4.0)
	assert_eq(k.state, Cat.State.PEEK, "shy Kira stays in (a laser seat is here)")
	l.laser_pos = Vector2(k.x - 30.0, l.house.floor_y(0) - 4)
	_set_in(1, {"move": Vector2(1, 0)})
	_run(l, 0.1)
	_set_in(1, {"a": true})
	_run(l, 0.1)
	_set_in(1, {})
	var lured := false
	for i in 60:
		_run(l, DT)
		if k.state == Cat.State.STALK:
			lured = true
	assert_true(lured, "the dot makes her stalk")
	_run(l, 1.0)
	assert_true(k.pickable() or k.state == Cat.State.HOP, "she pounced out onto the floor")
	assert_almost_eq(k.x, l.laser_pos.x, 12.0, "she landed on the dot")
	assert_eq(k.elev, 0.0)


func test_laser_brings_a_high_cat_down() -> void:
	var l := _level([0, 1, 2], {"greyssie": "wardrobe_top", "kira": "toy_box"})
	_stand_at_spot(l, "wardrobe_top")
	l.walker_x += 12.0
	l.open_spot("wardrobe_top")
	var g: Node = _cat(l, "greyssie")
	_run(l, 2.0)
	assert_eq(g.state, Cat.State.PEEK, "bold, but up high: she needs coaxing")
	assert_gt(g.elev, 40.0)
	l.laser_pos = Vector2(g.x + 25.0, l.house.floor_y(1) - 4)
	_set_in(1, {"a": true})
	_run(l, 2.0)
	assert_eq(g.elev, 0.0, "down on the floor")
	assert_true(g.pickable())


func test_shy_cat_comes_out_anyway_after_12s() -> void:
	var l := _level()
	_stand_at_spot(l, "sofa")
	l.open_spot("sofa")
	_run(l, 14.0)
	assert_true(_cat(l, "kira").pickable(), "nobody used the laser: she comes out anyway")


# ---------------------------------------------------------------- no-fail

func test_cat_walks_out_after_90s() -> void:
	var l := _level([0, 1], {"greyssie": "tv_box", "kira": "bookshelf_top"})
	l.walker_floor = 0
	l.walker_x = l.house.room_center("kitchen")
	var k: Node = _cat(l, "kira")
	_run(l, 89.0)
	assert_eq(k.state, Cat.State.HIDDEN, "still hidden at 89 s")
	_run(l, 1.5)
	assert_true(k.state in [Cat.State.WALKOUT, Cat.State.FREE, Cat.State.CHASE], "at 90 s she walks out")
	assert_eq(k.floor_i, l.walker_floor, "down the stairs to the walker's floor")
	_run(l, 8.0)
	assert_lt(absf(k.x - l.walker_x), 24.0, "and comes to the walker")
	assert_true(k.pickable())
	var found_ids := []
	for f in Game.finds:
		found_ids.append(f.cat)
	assert_true(found_ids.has("kira"), "the walk-out counts as a find")


func test_empty_spot_gives_a_funny_find() -> void:
	var l := _level()
	var seen := {}
	for sid in ["shoe_box", "living_plant", "kitchen_cupboard", "laundry_corner"]:
		var r: Dictionary = l.open_spot(sid)
		assert_true(r.has("find"), "%s is empty: a funny find" % sid)
		assert_true(l.FUNNY_FINDS.has(r.find))
		seen[r.find] = true
	assert_eq(seen.size(), 4, "a different find each time")
	var shown := false
	for f in l.fx:
		shown = shown or l.FUNNY_FINDS.has(f.name)
	assert_true(shown, "the find pops out of the spot")
	for c in l.cats:
		assert_eq(c.state, Cat.State.HIDDEN, "opening empty spots never disturbs the cats")


func test_spots_open_and_close() -> void:
	var l := _level()
	_stand_at_spot(l, "shoe_box")
	assert_eq(l.walker_action(), "open")
	assert_true(l.spot_is_open("shoe_box"))
	assert_eq(l.walker_action(), "close")
	assert_false(l.spot_is_open("shoe_box"))


# ---------------------------------------------------------------- carry + dinner

func test_carry_both_cats() -> void:
	var l := _level()
	l.walker_floor = 0
	l.walker_x = 150.0
	var g := _free_near_walker(l, "greyssie", 6.0)
	var k := _free_near_walker(l, "kira", -6.0)
	assert_eq(l.walker_action(), "pick")
	assert_eq(l.walker_action(), "pick")
	assert_eq(l.carried_count(), 2, "one cat on each shoulder")
	assert_eq(g.state, Cat.State.CARRIED)
	assert_eq(k.state, Cat.State.CARRIED)
	assert_ne(g.slot, k.slot)
	_set_in(0, {"move": Vector2(1, 0)})
	_run(l, 0.5)
	var feet: int = l.house.floor_y(0)
	assert_lt(g.position.y, feet - 8, "riding high on the shoulders")
	assert_lt(absf(g.position.x - l.walker_x), 12.0, "and moving with the walker")
	assert_lt(absf(k.position.x - l.walker_x), 12.0)
	assert_ne(g.position.x, k.position.x, "left and right shoulder")


func test_dinner_needs_both_cats_at_bowls() -> void:
	var l := _level()
	var b: Dictionary = l.house.bowls
	l.walker_floor = b.floor
	l.walker_x = b.x
	_free_near_walker(l, "greyssie", 4.0)
	l.walker_action()
	assert_eq(l.walker_action(), "bowls", "at the bowls, a puts the cat down")
	assert_eq(_cat(l, "greyssie").state, Cat.State.EATING)
	_run(l, 1.0)
	assert_eq(l.state, l.State.SEARCH, "one cat eating is not dinner yet")
	l.walker_x = b.x - 80.0
	_free_near_walker(l, "kira", 4.0)
	l.walker_action()
	assert_ne(l.walker_action(), "bowls", "away from the bowls nothing is put down")
	assert_eq(_cat(l, "kira").state, Cat.State.CARRIED)
	l.walker_x = b.x
	assert_eq(l.walker_action(), "bowls")
	_run(l, DT * 2)
	assert_eq(l.state, l.State.DINNER, "both at their bowls: dinner")
	assert_eq(l.bowl_nodes.kira.frame, 1, "the bowls are full")
	_run(l, l.DINNER_TIME + 0.2)
	assert_eq(Game.round_index, 1, "then the afternoon starts")
	assert_eq(Game.stars, 1, "with the morning's star")


func test_day_has_four_rounds_then_party() -> void:
	var l := _level()
	var parts := []
	for r in Game.DAY.size():
		parts.append(Game.day_part())
		_run(l, 3.0)  # the intro
		for i in l.cats.size():
			l.cats[i].eat_at(l.bowl_x(i), l.house.bowls.floor)
		_run(l, l.DINNER_TIME + 0.2)
	assert_eq(parts, ["morning", "afternoon", "evening", "night"])
	assert_eq(l.state, l.State.DONE)
	assert_eq(l.next_screen, "party")
	assert_eq(Game.stars, 4)


func test_night_is_warm_not_dark() -> void:
	var l := _level()
	l.start_round(3, LIVING, true)
	var c: Color = l.tint.color
	assert_gte(c.r, 0.9, "warm")
	assert_gt(c.r, c.b, "amber, not blue")
	assert_gte(c.get_luminance(), 0.75, "never dark")
	assert_eq(l.lamp_nodes[0].frame, 1, "the lamps are on")


# ---------------------------------------------------------------- seats

func test_toddler_input_never_hurts() -> void:
	var l := _level()
	l.walker_x = l.house.room_center("living") + 30.0
	var before := _snapshot(l)
	for i in 80:
		_set_in(2, {"a": i % 2 == 0, "start": i % 3 == 0, "b": i % 5 == 0})
		_run(l, 0.2)
	var after := _snapshot(l)
	assert_eq(after, before, "80 toddler presses change nothing but voices")
	assert_gt(l.shakes, 15)
	assert_false(l.paused, "the toddler cannot pause")


func _snapshot(l: Node) -> Dictionary:
	var cats := {}
	for c in l.cats:
		cats[c.id] = [c.state, c.spot, c.floor_i, c.x, c.elev]
	return {"cats": cats, "spots": l.spot_open.duplicate(), "walker": [l.walker_floor, l.walker_x],
		"carry": l.carrying.duplicate(), "round": Game.round_index, "stars": Game.stars, "finds": Game.finds.size(),
		"state": l.state}


func test_one_and_two_seat_fallbacks() -> void:
	# Walker alone: holding "a" shakes the treats, a tap opens, the dot follows.
	var l := _level([0])
	_stand_at_spot(l, "shoe_box")
	_set_in(0, {"a": true})
	_run(l, 0.6)
	assert_eq(l.shakes, 1, "hold a: shake the treats")
	assert_false(l.spot_is_open("shoe_box"), "a hold is not a tap")
	_set_in(0, {})
	_run(l, 0.1)
	_set_in(0, {"a": true})
	_run(l, 0.1)
	_set_in(0, {})
	_run(l, 0.1)
	assert_true(l.spot_is_open("shoe_box"), "a tap opens")
	_set_in(0, {"move": Vector2(1, 0)})
	_run(l, 2.0)
	_set_in(0, {})
	_run(l, 1.0)
	assert_almost_eq(l.laser_pos.x, l.walker_x + 20.0, 3.0, "the dot trots ahead of the walker")
	root.remove_child(l)
	l.free()
	Players.reset()
	# Two seats, no toddler: the bag shakes by itself every 12 s.
	l = _level([0, 1])
	l.walker_x = l.house.room_center("kitchen")
	_run(l, 11.5)
	assert_eq(l.shakes, 0)
	_run(l, 1.0)
	assert_eq(l.shakes, 1, "12 s: the bag shakes itself")
	assert_eq(l.meows.values().reduce(func(a, b): return a + b), 1, "and a cat answers")
	root.remove_child(l)
	l.free()
	Players.reset()
	# Two seats, no 5-year-old: a coaxed cat comes out after 3 s.
	l = _level([0, 2])
	_stand_at_spot(l, "sofa")
	l.open_spot("sofa")
	_run(l, 3.5)
	assert_true(_cat(l, "kira").state in [Cat.State.HOP, Cat.State.FREE, Cat.State.CHASE], "shy Kira comes out on her own")


func test_pause_only_by_walker() -> void:
	var l := _level()
	_tap(l, 2, "start")
	assert_false(l.paused, "not the toddler")
	_tap(l, 1, "start")
	assert_false(l.paused, "not the laser")
	_tap(l, 0, "start")
	assert_true(l.paused, "the walker's start pauses")
	var t: float = l.round_t
	_run(l, 1.0)
	assert_eq(l.round_t, t, "time stands still")
	_tap(l, 2)
	assert_true(l.paused, "a toddler press does not unpause")
	_tap(l, 0, "a")
	assert_false(l.paused, "the walker's a resumes")


# ---------------------------------------------------------------- gags

func test_zoomies_run_a_lap_and_come_back() -> void:
	var l := _level()
	l.walker_x = 200.0
	var g := _free_near_walker(l, "greyssie", 10.0)
	g._start_zoomies()
	var vanished := false
	for i in 300:
		_run(l, DT)
		vanished = vanished or not g.visible
	assert_true(vanished, "up the stairs and out of sight")
	assert_true(g.pickable() or g.state == Cat.State.ZOOMIES)
	_run(l, 4.0)
	assert_true(g.pickable(), "back on the walker's floor")
	assert_eq(g.floor_i, l.walker_floor)


func test_a_cat_knocks_the_cup_off_and_it_bounces() -> void:
	var l := _level()
	var cup: Dictionary = l.cups[0]
	var g := _free_near_walker(l, "greyssie", 0.0)
	g.floor_i = cup.floor
	g.x = cup.x
	l.cat_passes(g)
	assert_true(cup.fallen, "boing")
	_run(l, 3.0)
	assert_eq(cup.y, 0.0, "it lands on the floor; nothing breaks")


func test_a_free_cat_sits_in_a_box_too_small() -> void:
	var l := _level()
	_stand_at_spot(l, "shoe_box")
	l.open_spot("shoe_box")
	l.walker_x += 30.0
	var g := _free_near_walker(l, "greyssie", -20.0)
	l.laser_still_t = 99.0
	_run(l, 5.0)
	assert_eq(g.state, Cat.State.GAG, "she squeezes into the open box")
	assert_eq(g.spot, "shoe_box")
	assert_true(g.pickable(), "and can still be picked up")


# ---------------------------------------------------------------- data

func test_other_house_and_cats_load_without_code_changes() -> void:
	var errs := Game.load_data("res://tests/fixtures/house_flat.json", "res://tests/fixtures/cats_three.json")
	assert_eq(errs, [] as Array[String])
	assert_eq(Game.cat_data.ids(), ["tom", "mia", "pip"] as Array[String])
	var l := _level([0, 1, 2], {})
	l.start_round(0, {}, true)
	assert_eq(l.cats.size(), 3)
	var used := {}
	for c in l.cats:
		assert_true(l.house.spots.has(c.spot))
		used[c.spot] = true
	assert_eq(used.size(), 3, "three cats, three spots")
	assert_true(l.house.connected())
	# Stairs are on the right in this house.
	l.walker_floor = 0
	l.walker_x = l.house.room_center("stairs_down")
	assert_true(l.try_climb(1))
	_run(l, 1.2)
	assert_eq(l.walker_room(), "stairs_up")
	_tap(l, 2)
	assert_ne(l.last_meow_cat, "", "someone meows back")
	assert_true(l.house.rooms.has(l.mini.lit_room))
	_run(l, 95.0)
	for c in l.cats:
		assert_true(c.is_found(), "%s walked out by 90 s" % c.id)


func test_bad_house_data_is_reported_not_crashed() -> void:
	var HouseData = load("res://scripts/house/house_data.gd")
	var h = HouseData.new()
	h.parse({"floors": [{"rooms": [{"id": "a", "spots": [{"id": "s", "kind": "nope"}]}]}], "bowls": {"room": "zz"}})
	assert_gt(h.errors.size(), 0)


func test_real_meow_recordings_replace_the_synth() -> void:
	var dir := "user://real_meow_test"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var bytes := FileAccess.get_file_as_bytes("res://audio/meow_kira_1.wav")
	var f := FileAccess.open(dir.path_join("meow_kira_phone1.wav"), FileAccess.WRITE)
	f.store_buffer(bytes)
	f.close()
	var saved = Sfx._streams.get("meow_kira", null)
	var got: Dictionary = Game.install_real_voices(dir)
	assert_eq(got, {"kira": 1})
	assert_eq(Sfx._streams["meow_kira"].size(), 1, "Kira now meows with the recording")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir.path_join("meow_kira_phone1.wav")))
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))
	if saved == null:
		Sfx._streams.erase("meow_kira")
	else:
		Sfx._streams["meow_kira"] = saved


func test_cats_have_distinct_collars_and_sprites() -> void:
	var cats: Array = Game.cat_data.cats
	assert_ne(cats[0].collar, cats[1].collar)
	for anim in ["idle", "walk", "sit", "sleep", "stalk", "pounce", "eat", "carried", "zoomies", "tail_tip", "peek_eyes", "alert", "face"]:
		for c in cats:
			assert_true(Art.has("%s_%s" % [c.id, anim]), "%s_%s exists" % [c.id, anim])
	for c in cats:
		assert_true(Art.has("meow_bubble_" + c.id))
		assert_true(Art.has("bowl_" + c.id))
