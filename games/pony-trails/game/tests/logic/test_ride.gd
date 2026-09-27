extends GutTest
## The mare's gaits and jump assist, the foal's tether, lanes and grabs.

const MareRide := preload("res://scripts/logic/mare_ride.gd")
const FoalTether := preload("res://scripts/logic/foal_tether.gd")
const TrailCourse := preload("res://scripts/logic/trail_course.gd")
const DT := 1.0 / 30.0


func _mare_with(ob_x: float, w := 20.0) -> MareRide:
	var m := MareRide.new()
	m.obstacles = [{"x": ob_x, "w": w, "kind": "log", "done": false, "clean": false}]
	return m


func test_mare_gaits_follow_stick() -> void:
	var m := MareRide.new()
	assert_eq(m.gait(), MareRide.Gait.TROT, "she starts at a trot")
	for i in 60:
		m.steer(1.0, DT)
		m.step(DT)
	assert_eq(m.gait(), MareRide.Gait.CANTER, "right speeds her up to a canter")
	for i in 90:
		m.step(DT)
	assert_almost_eq(m.speed, MareRide.SPEEDS[2], 1.0)
	for i in 60:
		m.steer(-1.0, DT)
		m.step(DT)
	assert_eq(m.gait(), MareRide.Gait.WALK, "left slows her to a walk")
	for i in 120:
		m.steer(-1.0, DT)
		m.step(DT)
	assert_gt(m.speed, 20.0, "she never stops on her own (walk is the slowest)")
	# Releasing the stick keeps the gait.
	for i in 20:
		m.steer(1.0, DT)
	var g := m.gait()
	for i in 60:
		m.steer(0.0, DT)
		m.step(DT)
	assert_eq(m.gait(), g)


func test_jump_assist_window() -> void:
	# Trotting at 48 px/s toward a log at x 200: the takeoff point is 184.
	for case in [[0.3, true], [-0.0, true], [0.39, true], [0.6, false], [1.2, false]]:
		var m := _mare_with(200.0)
		m.speed = 48.0
		m.x = 184.0 - float(case[0]) * 48.0
		var r := m.press_jump()
		assert_eq(r == "scheduled", case[1], "press %.2f s before the takeoff" % case[0])
	# A scheduled jump starts exactly at the takeoff point and clears the log.
	var m2 := _mare_with(200.0)
	m2.speed = 48.0
	m2.throttle = 1.0
	m2.x = 184.0 - 0.3 * 48.0
	m2.press_jump()
	var took_off_at := -1.0
	var ev_all: Array[String] = []
	for i in 90:
		var before := m2.x
		var ev := m2.step(DT)
		ev_all.append_array(ev)
		if ev.has("jump"):
			took_off_at = before
	assert_true(ev_all.has("jump") and ev_all.has("land"))
	assert_false(ev_all.has("step_over"))
	assert_between(took_off_at, 184.0 - 2.0, 184.0 + 0.1, "the jump starts at the takeoff point")
	assert_gt(m2.x, 220.0, "she lands past the log")
	assert_eq(m2.clean_jumps, 1)
	# A press far from anything is a happy hop, not a jump.
	var m3 := _mare_with(900.0)
	m3.speed = 48.0
	assert_eq(m3.press_jump(), "hop")


func test_missed_jump_is_a_step_over() -> void:
	var m := _mare_with(200.0)
	m.x = 100.0
	m.speed = 74.0
	m.throttle = 2.0
	var ev_all: Array[String] = []
	var min_speed := INF
	for i in 150:
		ev_all.append_array(m.step(DT))
		if m.state == MareRide.State.STEP:
			min_speed = minf(min_speed, m.speed)
	assert_true(ev_all.has("step_over"))
	assert_false(ev_all.has("jump"))
	assert_lt(min_speed, MareRide.SPEEDS[0], "a step-over is slower")
	assert_gt(min_speed, 0.0, "but she never stops or falls")
	assert_gt(m.x, 240.0, "and she goes on past it")
	assert_eq(m.state, MareRide.State.RUN)
	assert_eq(m.step_overs, 1)
	assert_eq(m.clean_jumps, 0)


func test_foal_never_leaves_tether() -> void:
	var m := MareRide.new()
	var f := FoalTether.new()
	f.place(m.x)
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	var worst := 0.0
	for i in 60 * 30:
		m.steer(rng.randf_range(-1, 1), DT)
		if i % 90 == 0:
			m.x += rng.randf_range(-60, 120)   # teleports: the tether still holds
		m.step(DT)
		if i % 17 == 0:
			f.change_lane(rng.randi_range(-1, 1))
		if i % 23 == 0:
			f.hop()
		f.step(m.x, m.speed, DT)
		worst = maxf(worst, absf(f.x - m.x))
	assert_lte(worst, FoalTether.MAX_GAP + 0.001)


func test_foal_lane_change_and_grab() -> void:
	var c := TrailCourse.new(0.5)
	c.items.clear()
	c.items.append({"x": 300.0, "lane": 2, "kind": "apple", "taken": false, "needs_hop": true, "want": true})
	c.items.append({"x": 360.0, "lane": 0, "kind": "flower_pink", "taken": false, "needs_hop": false, "want": true})
	var f := FoalTether.new()
	f.x = 250.0
	assert_eq(f.lane, 1)
	assert_true(f.change_lane(1))
	assert_eq(f.lane, 2)
	assert_false(f.change_lane(1), "no lane beyond the meadow edge")
	for i in 30:
		f.step(f.x, 0.0, DT)
	assert_almost_eq(f.y, FoalTether.LANE_Y[2], 0.5, "the lane change eases in")
	f.x = 300.0
	assert_true(c.grab(f.x, f.lane, 0.0).is_empty(), "an apple needs a hop")
	f.hop()
	f.step(f.x, 0.0, 0.15)
	var got := c.grab(f.x, f.lane, f.hop_height())
	assert_eq(got.size(), 1)
	assert_eq(got[0].kind, "apple")
	assert_true(c.grab(f.x, 1, 9.0).is_empty(), "nothing in the wrong lane")
	# A flower is picked by trotting through its lane.
	f.set_lane(0)
	assert_eq(c.grab(362.0, 0, 0.0).size(), 1)
	# The self-steering foal heads for the next thing's lane and hops it.
	var auto := FoalTether.new()
	auto.x = 280.0
	c.items.append({"x": 290.0, "lane": 0, "kind": "apple", "taken": false, "needs_hop": true, "want": true})
	var hopped := false
	for i in 30:
		auto.auto_steer(c.items)
		auto.step(auto.x + 22.0, 0.0, DT)
		auto.x = 280.0 + i * 0.5
		hopped = hopped or auto.hopping()
	assert_eq(auto.lane, 0)
	assert_true(hopped)
