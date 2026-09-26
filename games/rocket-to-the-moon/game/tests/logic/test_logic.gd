extends GutTest
## Pure logic: aim assist, the countdown state machine, the claw, the timeline,
## the rules and the album file.

const Aim := preload("res://scripts/logic/aim.gd")
const Countdown := preload("res://scripts/logic/countdown.gd")
const Claw := preload("res://scripts/logic/claw.gd")
const Timeline := preload("res://scripts/logic/timeline.gd")
const Rules := preload("res://scripts/logic/rules.gd")
const Album := preload("res://scripts/logic/album.gd")
const DT := 1.0 / 30.0
const TEST_ALBUM := "user://test_album_logic.json"


func after_each() -> void:
	if FileAccess.file_exists(TEST_ALBUM):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ALBUM))


# ---------------------------------------------------------------- aim

func test_aim_picks_the_nearest_target_inside_the_cone() -> void:
	var targets := [Vector2(100, 0), Vector2(40, 10), Vector2(60, -5)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.RIGHT, targets), 1)


func test_aim_ignores_a_nearer_target_outside_the_cone() -> void:
	var targets := [Vector2(10, 20), Vector2(80, 10), Vector2(-15, 0)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.RIGHT, targets), 1)


# ---------------------------------------------------------------- countdown

func test_countdown_cannot_be_skipped_by_presses() -> void:
	var c := Countdown.new(5, 1.0, 1.5)
	c.step(DT, true)
	assert_eq(c.state, Countdown.State.COUNT, "the first press starts the count")
	var t := 0.0
	var shakes := 0
	var lights := 0
	# Mash on every frame: the lights still go out one per second.
	while c.state == Countdown.State.COUNT:
		var ev := c.step(DT, true)
		t += DT
		shakes += ev.count("shake")
		lights += ev.count("light")
		if t < 0.99:
			assert_eq(c.out, 0, "no light goes out before a second")
		assert_lt(t, 6.0, "the count ends")
	assert_almost_eq(t, 5.0, DT * 1.5, "five lights take five seconds, mashing or not")
	assert_eq(lights, 5)
	assert_gt(shakes, 100, "every press shook the rocket instead")
	assert_eq(c.state, Countdown.State.IGNITION)
	var ign := 0.0
	while c.state != Countdown.State.DONE:
		c.step(DT, true)
		ign += DT
	assert_almost_eq(ign, 1.5, DT * 1.5, "ignition cannot be skipped either")


func test_countdown_auto_presses_after_eight_seconds() -> void:
	var c := Countdown.new()
	var t := 0.0
	var auto := false
	while t < 7.9:
		var ev := c.step(DT, false)
		t += DT
		assert_false(ev.has("start"), "still waiting at %.2f s" % t)
	assert_eq(c.state, Countdown.State.WAIT)
	for i in 6:
		var ev := c.step(DT, false)
		auto = auto or ev.has("auto")
	assert_eq(c.state, Countdown.State.COUNT, "the button pressed itself after 8 s")
	assert_true(auto)


func test_countdown_digit_counts_down_from_five() -> void:
	var c := Countdown.new()
	c.step(DT, true)
	var seen: Array[int] = []
	while c.counting():
		if not seen.has(c.digit()):
			seen.append(c.digit())
		c.step(DT, false)
	assert_eq(seen, [5, 4, 3, 2, 1] as Array[int])


# ---------------------------------------------------------------- claw

func _pickup(at: Vector2) -> Dictionary:
	return {"pos": at, "grabbed": false}


func test_claw_snaps_to_nearest_pickup_in_cone() -> void:
	var claw := Claw.new()
	claw.aim = Vector2i.UP
	var far := _pickup(Vector2(20, -100))
	var near := _pickup(Vector2(-25, -50))       # ~27 degrees off straight up: inside the cone
	var outside := _pickup(Vector2(40, -8))      # nearer, but far outside the cone
	var behind := _pickup(Vector2(0, 30))
	var pickups := [far, near, outside, behind]
	assert_true(claw.shoot(Vector2.ZERO, pickups))
	assert_true(is_same(claw.target, near), "snapped to the nearest pickup in the cone")
	assert_almost_eq(claw.dir.angle(), near.pos.angle(), 0.001, "the arm heads for it")
	var got = null
	for i in 60:
		var ev := claw.step(DT, Vector2.ZERO, pickups)
		if ev.has("delivered"):
			got = ev.delivered
			break
	assert_true(is_same(got, near), "grabbed it and carried it home")
	assert_true(claw.idle())


func test_claw_without_a_target_goes_straight_and_comes_back() -> void:
	var claw := Claw.new()
	claw.aim = Vector2i.LEFT
	assert_true(claw.shoot(Vector2.ZERO, [_pickup(Vector2(80, 0))]))
	assert_eq(claw.target, null)
	assert_eq(claw.dir, Vector2.LEFT)
	assert_false(claw.shoot(Vector2.ZERO, []), "one claw at a time")
	var missed := false
	for i in 60:
		missed = missed or claw.step(DT, Vector2.ZERO, []).has("missed")
	assert_true(missed)
	assert_true(claw.idle())


func test_claw_rotates_in_quarter_turns() -> void:
	var claw := Claw.new()
	for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		claw.aim = d
		assert_almost_eq(fposmod(claw.rotation(), PI * 0.5), 0.0, 0.0001, "idle, aimed %s" % d)
		assert_eq(Aim.snap4(Vector2.from_angle(claw.rotation())), d)
	# While out, the arm may point anywhere; the claw sprite still turns by 90s.
	for deg in range(0, 360, 7):
		claw.phase = Claw.Phase.OUT
		claw.dir = Vector2.from_angle(deg_to_rad(deg))
		var r := claw.rotation()
		var q := fposmod(r, PI * 0.5)
		assert_true(q < 0.0001 or q > PI * 0.5 - 0.0001, "%d deg -> %f" % [deg, r])


# ---------------------------------------------------------------- timeline, rules, album

func test_timeline_is_data_and_expands_sorted() -> void:
	var data := Timeline.load_data()
	for s in ["sky", "space", "moon"]:
		assert_true(data.has(s), "stage %s in the data file" % s)
	var ev := Timeline.expand(data, "space")
	assert_gt(ev.size(), 20)
	for i in range(1, ev.size()):
		assert_true(ev[i - 1].t <= ev[i].t)
	var kinds := {}
	for e in ev:
		if e.kind == "planet":
			kinds[e.planet] = true
	assert_eq(kinds.size(), 8, "all eight planets show up in space")
	assert_eq(Timeline.expand(data, "space").size(), ev.size(), "deterministic")


func test_timeline_scale_shortens_without_a_blizzard() -> void:
	var data := Timeline.load_data()
	var full := Timeline.expand(data, "sky", 1.0)
	var short := Timeline.expand(data, "sky", 0.2)
	assert_lt(short.back().t, 12.1)
	assert_lt(float(short.size()), full.size() * 1.0 / Timeline.MIN_EVERY_SCALE * 0.2 + 4.0)


func test_bump_drop_never_goes_negative() -> void:
	assert_eq(Rules.bump_drop(10), 2)
	assert_eq(Rules.bump_drop(1), 1)
	assert_eq(Rules.bump_drop(0), 0)


func test_scroll_speed_never_stops() -> void:
	assert_gt(Rules.scroll_speed(0.0, false), 0.0)
	assert_almost_eq(Rules.scroll_speed(0.0, false), Rules.BASE_SCROLL * 0.7, 0.001, "30 % slower")
	assert_gt(Rules.scroll_speed(0.5, true), Rules.scroll_speed(0.5, false))


func test_album_file_round_trip() -> void:
	assert_eq(Album.load_kinds(TEST_ALBUM), [] as Array[int], "no file yet")
	Album.save_kinds(TEST_ALBUM, [3, 1] as Array[int])
	assert_eq(Album.load_kinds(TEST_ALBUM), [1, 3] as Array[int])
	var f := FileAccess.open(TEST_ALBUM, FileAccess.WRITE)
	f.store_string("{\"planets\": [2, 99, \"x\", 2]}")
	f.close()
	assert_eq(Album.load_kinds(TEST_ALBUM), [2] as Array[int], "junk and duplicates are dropped")
