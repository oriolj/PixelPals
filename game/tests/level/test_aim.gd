extends GutTest
## Aim assist and run rules (pure functions).

const Aim := preload("res://scripts/level/aim.gd")
const Rules := preload("res://scripts/level/rules.gd")


func test_picks_the_nearest_target_inside_the_cone() -> void:
	var targets := [Vector2(100, 0), Vector2(40, 10), Vector2(60, -5)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.RIGHT, targets), 1)


func test_ignores_a_nearer_target_outside_the_cone() -> void:
	# (10, 20) is nearer but ~63 degrees off; the cone is 60 wide (30 each side).
	var targets := [Vector2(10, 20), Vector2(80, 10), Vector2(-15, 0)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.RIGHT, targets), 1)


func test_no_target_in_the_cone_returns_minus_one() -> void:
	var targets := [Vector2(0, 50), Vector2(-50, 0)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.RIGHT, targets), -1)
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.ZERO, targets), -1, "no direction, no assist")


func test_cone_follows_the_aim_direction() -> void:
	var targets := [Vector2(50, 0), Vector2(5, -60)]
	assert_eq(Aim.pick_target(Vector2.ZERO, Vector2.UP, targets), 1)


func test_steer_turns_gently_and_keeps_speed() -> void:
	var v := Aim.steer(Vector2(100, 0), Vector2.ZERO, Vector2(0, 100), 0.1)
	assert_almost_eq(v.length(), 100.0, 0.01)
	assert_almost_eq(v.angle(), 0.1, 0.001, "turn is capped per frame")
	var direct := Aim.steer(Vector2(100, 0), Vector2.ZERO, Vector2(100, 5), 1.0)
	assert_almost_eq(direct.angle(), Vector2(100, 5).angle(), 0.001)


func test_turret_rotates_only_in_quarter_turns() -> void:
	for d in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		var a := Aim.angle_of(d)
		assert_almost_eq(fmod(absf(a), PI * 0.5), 0.0, 0.0001)
		assert_eq(Aim.snap4(Vector2.from_angle(a)), d)


func test_stars_never_go_negative() -> void:
	assert_eq(Rules.stars_after_hit(10), 7)
	assert_eq(Rules.stars_after_hit(2), 0)
	assert_eq(Rules.stars_after_hit(0), 0)


func test_run_length_override() -> void:
	assert_eq(Rules.run_length(0.0), 180.0)
	assert_eq(Rules.run_length(5.0), 5.0)


func test_spawn_rate_ramps_up_gently() -> void:
	assert_gt(Rules.spawn_interval(0, 180), Rules.spawn_interval(180, 180))
	assert_gt(Rules.spawn_interval(180, 180), 1.0)
