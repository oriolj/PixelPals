extends GutTest
## The stable's rules: mud, the brush's hops, carrots, hooves and saddle, the cat.

const Grooming := preload("res://scripts/logic/grooming.gd")
const DT := 1.0 / 30.0


func _groom() -> Grooming:
	# head (right, up), back (middle, up), legs (middle, low), tail (left).
	var patches: Array[Vector2] = [Vector2(190, 94), Vector2(146, 108), Vector2(160, 126), Vector2(126, 104)]
	var hooves: Array[Vector2] = [Vector2(175, 146), Vector2(168, 146), Vector2(140, 146), Vector2(134, 146)]
	return Grooming.new(patches, hooves, Vector2(64, 102), Vector2(158, 164))


func test_mud_patch_clears_after_scrubbing() -> void:
	var g := _groom()
	g.brush = 1
	assert_eq(g.fade_stage(1), 0, "starts muddy")
	var t := 0.0
	var stages: Array[int] = []
	while not g.is_clean(1) and t < 5.0:
		g.scrub(DT)
		t += DT
		if not stages.has(g.fade_stage(1)):
			stages.append(g.fade_stage(1))
	assert_almost_eq(t, Grooming.SCRUB_TIME, 0.1, "a patch fades in about 2 s")
	assert_eq(stages, [0, 1, 2, 3, 4] as Array[int], "through the four fade stages, then gone")
	assert_false(g.scrub(DT), "a clean patch stays clean")
	assert_eq(g.dirty_count(), 3, "the other patches keep their mud")
	# The self-scrubbing brush is slower.
	g.brush = 0
	var t2 := 0.0
	while not g.is_clean(0) and t2 < 10.0:
		g.scrub(DT, Grooming.SLOW_SCRUB)
		t2 += DT
	assert_gt(t2, 4.0)


func test_brush_snaps_to_nearest_patch_in_direction() -> void:
	var g := _groom()
	g.brush = 1  # back
	assert_eq(g.nearest_in(Vector2i.RIGHT), 0, "right of the back is the head")
	assert_eq(g.nearest_in(Vector2i.LEFT), 3, "left of the back is the tail")
	assert_eq(g.nearest_in(Vector2i.DOWN), 2, "below the back are the legs")
	g.brush = 2  # legs
	assert_eq(g.nearest_in(Vector2i.UP), 1, "above the legs is the back")
	g.brush = 0  # head: nothing further right, it stays put
	assert_eq(g.move_brush(Vector2i.RIGHT), 0)
	# From the rest spot under her, any direction lands on a patch.
	g.brush = -1
	assert_ne(g.move_brush(Vector2i.UP), -1)
	# The brush snaps: it is always exactly on its patch.
	assert_eq(g.brush_pos(), g.patch_pos[g.brush])


func test_every_third_carrot_goes_to_the_foal() -> void:
	var g := _groom()
	var who: Array[String] = []
	for i in 9:
		who.append(g.give_carrot())
	assert_eq(who, ["mare", "mare", "foal", "mare", "mare", "foal", "mare", "mare", "foal"] as Array[String])


func test_saddle_needs_all_four_hooves() -> void:
	var g := _groom()
	assert_false(g.put_saddle(), "no saddle before the hooves")
	for i in 3:
		assert_true(g.pick_hoof(i))
		assert_false(g.put_saddle(), "not with %d hooves" % (i + 1))
	assert_false(g.pick_hoof(0), "a picked hoof stays picked")
	assert_true(g.pick_hoof(3))
	assert_true(g.can_saddle())
	assert_true(g.put_saddle())
	assert_true(g.saddled)
	# The hand's hotspots: a hoof under the hand, then the rack.
	var g2 := _groom()
	assert_eq(g2.hotspot_at(Vector2(176, 144)).kind, "hoof")
	assert_eq(g2.hotspot_at(Vector2(66, 104)).kind, "saddle")
	assert_true(g2.hotspot_at(Vector2(260, 40)).is_empty())
