extends GutTest
## The dive, driven frame by frame with scripted seats.

const LevelScreen := preload("res://scripts/screens/level.gd")
const AlbumModel := preload("res://scripts/album.gd")
const Creatures := preload("res://scripts/level/creatures.gd")
const SubMotion := preload("res://scripts/level/sub_motion.gd")
const Species := preload("res://scripts/level/species.gd")
const DT := 1.0 / 30.0
const TEST_ALBUM := "user://test_album_level.json"

var L
var _saved_album


func before_each() -> void:
	_saved_album = Game.album
	Game.album = AlbumModel.new(TEST_ALBUM)
	Game.album.reset()
	Game.run_seconds = 0.0


func after_each() -> void:
	Game.album.reset()
	Game.album = _saved_album
	Players.reset()
	Players.clear_scripted()


func _level(seats := 3):
	Players.reset()
	Players.clear_scripted()
	for i in seats:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
	Players.poll()
	L = LevelScreen.new()
	add_child_autofree(L)
	L.set_process(false)
	return L


func _step(states := {}, n := 1) -> void:
	for i in n:
		for d in states:
			Players.set_scripted(d, states[d])
		Players.poll()
		L.step(DT)


func _press(d: String, button := "a") -> void:
	_step({d: {button: true}})
	_step({d: {}})


## Moves every creature far away and freezes them (an empty sea).
func _empty_sea() -> void:
	for c in L.creatures:
		c.pos = Vector2(-2000, -2000)
		c.home = c.pos
		c.roam = 0.0
		c.speed = 0.0


func _hold_in_frame(id: String) -> void:
	var c = L.by_id[id]
	c.roam = 0.0
	c.speed = 0.0
	c.vel = Vector2.ZERO
	c.pos = L.sub_pos + Vector2(52, 0)
	c.home = c.pos


# ---------------------------------------------------------------- photos

func test_snap_with_creature_in_frame_records_species() -> void:
	_level()
	_empty_sea()
	_hold_in_frame("clownfish")
	_step({}, 10)
	assert_true(L.locked, "the frame locks on")
	_press("demo:1")
	assert_true(Game.album.has("clownfish"))
	assert_eq(Game.session.new, ["clownfish"])
	assert_eq(Game.session.seen, ["clownfish"])
	assert_eq(L.polaroids.size(), 1, "a polaroid flies to the strip")
	# A second photo of it is a repeat (a star), never a second "new".
	_step({}, 12)
	_press("demo:1")
	assert_eq(Game.album.count("clownfish"), 2)
	assert_eq(Game.session.repeats.get("clownfish", 0), 1)
	assert_eq(Game.session.new.size(), 1)


func test_empty_snap_records_a_bonus_subject_never_nothing() -> void:
	_level()
	_empty_sea()
	_step({}, 3)
	for i in 4:
		_press("demo:1")
		_step({}, 12)
	var total := 0
	for k in Game.session.bonus:
		total += int(Game.session.bonus[k])
		assert_true(Species.BONUS.has(k), "a known bonus subject")
	assert_eq(total, 4, "every empty snap photographs something")
	assert_eq(L.snaps, 4)
	assert_eq(Game.session.seen.size(), 0)


func test_snap_answers_within_two_frames_and_flash_is_short() -> void:
	_level()
	_empty_sea()
	_step({}, 2)
	_step({"demo:1": {"a": true}})
	assert_true(L.flash_sprite.visible, "flash on the press frame")
	assert_gt(L.screen_flash_t, 0.0)
	var lit := 1
	for i in 10:
		_step({"demo:1": {}})
		if L.flash_sprite.visible:
			lit += 1
	assert_lte(lit, 3, "the flash never lasts more than 3 frames")


func test_viewfinder_assist_snaps_to_creature_within_24px() -> void:
	_level()
	_empty_sea()
	var c = L.by_id["blue_tang"]
	c.roam = 0.0
	c.speed = 0.0
	# 18 px beyond the frame's right edge at rest: inside the assist range.
	var rest: Vector2 = L.sub_pos + Vector2(52, 0)
	c.pos = rest + Vector2(24 + 18, 0)
	c.home = c.pos
	_step({}, 20)
	assert_almost_eq(L.frame_pos.x, c.pos.x, 1.0, "the frame slid to centre the fish")
	assert_true(L.locked)
	# 30 px beyond the edge: no pull, the frame stays at rest.
	c.pos = rest + Vector2(24 + 30, 0)
	c.home = c.pos
	_step({}, 20)
	assert_almost_eq(L.frame_pos.x, rest.x, 1.0)


func test_one_seat_auto_snap_after_one_second_in_frame() -> void:
	_level(1)
	_empty_sea()
	_hold_in_frame("turtle")
	_step({}, 25)   # 0.83 s
	assert_false(Game.album.has("turtle"), "not before a second")
	_step({}, 10)   # 1.17 s
	assert_true(Game.album.has("turtle"), "auto-snapped after a second in the frame")
	_step({}, 60)
	assert_eq(Game.album.count("turtle"), 1, "no repeat auto-snaps of the same species")


# ---------------------------------------------------------------- lights

func test_lights_any_button_only_lights_seat_with_cooldown() -> void:
	_level()
	_empty_sea()
	_press("demo:0")          # pilot's a = sonar
	_press("demo:1")          # camera's a = snap
	assert_eq(L.flashes, 0, "only the lights seat flashes")
	_step({"demo:2": {"b": true}})   # ANY button of the lights seat
	assert_eq(L.flashes, 1)
	_step({"demo:2": {}})
	_step({"demo:2": {"a": true}})   # again inside the cooldown
	assert_eq(L.flashes, 1, "cooldown")
	_step({"demo:2": {}}, 8)
	_step({"demo:2": {"start": true}})
	assert_eq(L.flashes, 2)
	assert_eq(L.lights.color, 1, "the next colour")
	# With a lights seat, nothing flashes by itself.
	_step({"demo:2": {}}, 300)
	assert_eq(L.flashes, 2)


func test_lights_flash_by_themselves_without_a_lights_seat() -> void:
	_level(2)
	_empty_sea()
	_step({}, 30 * 9)
	assert_eq(L.flashes, 1, "every 8 s")


func test_lights_flash_near_a_shy_creature_without_a_lights_seat() -> void:
	_level(2)
	_empty_sea()
	var j = L.by_id["jellyfish"]
	j.home = L.sub_pos + Vector2(30, 0)
	j.pos = j.home
	_step({}, 2)
	assert_eq(L.flashes, 1, "a shy creature within 3 tiles lights the lights")
	_step({}, 10)
	assert_true(j.photographable(), "so it stays catchable")


func test_three_quick_presses_make_a_disco() -> void:
	_level()
	for i in 3:
		_step({"demo:2": {"a": true}})
		_step({"demo:2": {}}, 9)
	var spinning := 0
	for c in L.creatures:
		if c.spin > 0.0:
			spinning += 1
	assert_gt(spinning, 0, "the fish on screen spin")


func test_light_lovers_in_the_level_need_the_lights() -> void:
	_level()
	var sq = L.by_id["squid"]
	L.sub_pos = sq.home + Vector2(-52, 0)
	_step({}, 30)
	assert_false(sq.photographable(), "dark: the squid hides")
	_press("demo:2")
	_step({}, 8)
	assert_true(sq.photographable(), "lights on: it comes to dance")


# ---------------------------------------------------------------- the sub

func test_rock_bump_never_loses_photos() -> void:
	_level()
	Game.album.record("clownfish")
	Game.session.seen.append("clownfish")
	Game.album.add_bonus("shell")
	# Just above the shallows shelf (top at y = 160), diving into it fast.
	L.sub_pos = Vector2(250, 138)
	L.sub_vel = Vector2(0, SubMotion.MAX_SPEED)
	for i in 30:
		_step({"demo:0": {"move": Vector2.DOWN}})
	assert_gt(L.bumps, 0, "it bumped")
	assert_true(Game.album.has("clownfish"))
	assert_eq(Game.album.bonus("shell"), 1)
	assert_eq(Game.session.seen, ["clownfish"])
	assert_false(L.reef.rect_hits(L.sub_pos, SubMotion.HIT), "never inside the rock")
	assert_eq(L.state, L.State.RUN)


func test_current_returns_sub_inside_world_bounds() -> void:
	_level()
	var b: Rect2 = SubMotion.bounds()
	for start in [Vector2(-30, 60), Vector2(1310, 40), Vector2(400, -20)]:
		L.sub_pos = start
		L.sub_vel = Vector2.ZERO
		_step({"demo:0": {}}, 30 * 5)
		assert_true(b.grow(1.0).has_point(L.sub_pos), "back inside from %s (at %s)" % [start, L.sub_pos])
	# Pushing out against the current: it never gets farther than the margin.
	L.sub_pos = Vector2(40, 60)
	_step({"demo:0": {"move": Vector2.LEFT}}, 30 * 6)
	assert_gte(L.sub_pos.x, b.position.x - SubMotion.MARGIN - 0.1)


func test_sonar_brings_out_a_hider_and_marks_hiding_spots() -> void:
	_level()
	var crab = L.by_id["crab"]
	L.sub_pos = crab.home + Vector2(0, -44)
	_step({}, 5)
	assert_false(crab.photographable())
	_press("demo:0")
	assert_gt(L.reveal_t, 0.0, "hiding spots shown as rings")
	_step({}, 10)
	assert_true(crab.photographable(), "the crab came out")


# ---------------------------------------------------------------- run

func test_run_ends_at_six_minutes_or_full_page() -> void:
	_level()
	assert_eq(L.run_len, 360.0)
	L.time = 359.9
	_step({}, 4)
	assert_eq(L.state, L.State.END_BUBBLES, "six minutes")
	_step({}, 30 * 5)
	assert_eq(L.state, L.State.DONE, "surfaced into the sunset, then the album")
	# A full page ends early.
	L.queue_free()
	_level()
	L.time = 20.0
	Game.session.seen.assign(Species.PAGE)
	_step({}, 2)
	assert_ne(L.state, L.State.RUN)


func test_whale_passes_once_near_the_surface() -> void:
	_level()
	L.time = L.run_len * 0.31
	L.sub_pos = Vector2(640, 60)
	_step({}, 2)
	assert_eq(L.whale.state, Creatures.State.PASS)
	assert_true(L.whale.photographable())
	_step({}, 30 * 70)
	assert_eq(L.whale.state, Creatures.State.GONE, "once per run")


func test_pearl_trail_after_forty_seconds_without_a_new_photo() -> void:
	_level()
	_step({}, 2)
	assert_eq(L.trail_target, "")
	L.time = 41.0
	_step({}, 1)
	assert_ne(L.trail_target, "", "pearls lead to an unphotographed species")
	var shown := 0
	for p in L.pearls:
		if p.visible:
			shown += 1
	assert_gt(shown, 0)
