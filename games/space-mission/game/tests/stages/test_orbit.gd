extends "res://tests/helpers.gd"
## The orbit stage driven frame by frame: the arm, the ports, the station
## growing, the docking assist, the photos.

const Station := preload("res://scripts/logic/station.gd")


func _orbit(n := 3) -> Node:
	seat(n)
	return open("orbit")


## Puts the current cargo right at the arm tip (floating, not held).
func _cargo_at_tip(o: Node, offset := Vector2.ZERO) -> void:
	o.cargo.pos = o.tip() + offset
	o.cargo.held = false


func test_arm_snap_grabs_cargo_within_radius() -> void:
	var o := _orbit(3)
	# Within 12 px: A grabs (the cargo snaps into the hand).
	_cargo_at_tip(o, Vector2(10, 0))
	tap("demo:1", "a", o)
	assert_true(o.holding, "grabbed from 10 px")
	assert_lt(o.cargo.pos.distance_to(o.tip()), 0.01, "snapped to the hand")
	# Farther than the snap radius and the magnet: A only clacks.
	var p := _orbit_fresh()
	_cargo_at_tip(p, Vector2(0, 30))
	tap("demo:1", "a", p)
	assert_false(p.holding, "no grab from 30 px")


func _orbit_fresh() -> Node:
	if is_instance_valid(Game.current):
		Game.current.free()
	return open("orbit")


func test_the_magnet_pulls_the_hand_onto_nearby_cargo() -> void:
	var o := _orbit(3)
	_cargo_at_tip(o, Vector2(0, -18))
	o.cargo.pos.x = o.tip().x
	var t := run_until(o, func(): return o.tip().distance_to(o.cargo.pos) < o.SNAP_R, 1.5,
		{"demo:1": {}})
	assert_lt(t, 1.5, "the hand is pulled in within a second or two")


func test_module_fits_only_its_own_port_on_screen() -> void:
	var o := _orbit(3)
	var st: RefCounted = o.station
	# Hold the lab module at the habitat port: it never clicks in.
	o.cargo = Station.new_cargo("lab")
	o.holding = true
	o.cargo.held = true
	o.flight.pos = st.core + Station.SLOTS[2].approach
	o.flight.vel = Vector2.ZERO
	o.tip_rel = st.port_pos(2) - o.shoulder()
	drive({"demo:1": {"a": true}}, o)
	assert_true("wrong_port" in o.events, "a boing at the wrong port")
	assert_true(o.holding, "still held")
	assert_eq(st.count(), 0)
	# At its own port it clicks in.
	o.flight.pos = st.core + Station.SLOTS[0].approach
	o.tip_rel = st.port_pos(0) - o.shoulder()
	drive({}, o)
	assert_true("fit" in o.events)
	assert_true(st.fitted[0])
	assert_eq(Game.modules, ["lab"] as Array[String])


func test_missed_cargo_loops_back_on_screen() -> void:
	var o := _orbit(3)
	o.cargo.pos = Vector2(Station.LOOP_X - 1.0, Station.LANE_Y)
	o.flight.pos = Vector2(60, 110)
	var looped := run_until(o, func(): return o.cargo.get("loops", 0) >= 1, 3.0,
		{"demo:0": {"move": Vector2(0, 1)}})
	assert_lt(looped, 3.0)
	assert_lt(o.cargo.pos.x, 0.0, "back at the left edge")
	assert_eq(o.phase, o.Phase.BUILD, "nothing lost")


func test_station_grows_after_each_module() -> void:
	var o := _orbit(1)  # the Pilot alone: autopilot and the arm run themselves
	var counts: Array[int] = []
	var t := 0.0
	while o.phase == o.Phase.BUILD and t < 400.0:
		drive({}, o)
		t += DT
		if "fit" in o.events:
			counts.append(o.station.count())
	assert_eq(counts, [1, 2, 3, 4, 5] as Array[int], "one more module each time")
	assert_eq(Game.modules.size(), 5)
	for m in o._modules:
		assert_true(m.visible, "every module is on the station")
	assert_eq(o.phase, o.Phase.DOCKING)


func test_docking_assist_completes_within_5s() -> void:
	for start in [Vector2(28, 114), Vector2(292, 20), Vector2(28, 20), Vector2(292, 114)]:
		var o := _orbit_fresh() if is_instance_valid(Game.current) else _orbit(3)
		for i in 5:
			o.station.fit(i)
		o.phase = o.Phase.DOCKING
		o.cargo = {}
		o.flight.pos = start
		# The Pilot even pushes away from the ring.
		var away: Vector2 = (start - o.dock_pos()).normalized()
		var t := run_until(o, func(): return Game.docked, 5.0, {"demo:0": {"move": away}})
		assert_lte(t, 5.0, "docked from %s in %.1f s" % [start, t])
		assert_eq(o.phase, o.Phase.CELEBRATE)
		Game.docked = false


func test_after_docking_the_crew_floats_out_then_mars() -> void:
	var o := _orbit(3)
	for i in 5:
		o.station.fit(i)
	o.phase = o.Phase.DOCKING
	o.cargo = {}
	run_until(o, func(): return Game.docked, 6.0)
	assert_eq(o.astronauts.size(), 3, "one astronaut per seat")
	tap("demo:2", "a", o)
	assert_eq(o.waves, 1, "the toddler makes them wave")
	var t := run_until(o, func(): return o.next_screen != "", 12.0)
	assert_lt(t, 12.0)
	assert_eq(o.next_screen, "landing")


func test_camera_press_takes_a_photo_and_blinks_the_lights() -> void:
	var o := _orbit(3)
	tap("demo:2", "a", o)
	assert_eq(Game.photos.size(), 1)
	assert_gt(o.lights_t, 0.0)
	assert_gt(o.flash_t, 0.0)
	var img: Image = Game.photos[0].tex.get_image()
	assert_eq(img.get_size(), Vector2i(64, 36))
	# Mashing: every press flashes, photos at most every PHOTO_GAP.
	for i in 10:
		tap("demo:2", "a", o)
	assert_between(Game.photos.size(), 2, 8)


func test_photo_during_an_earth_moment_is_golden() -> void:
	var o := _orbit(3)
	o.stage_t = o.MOMENT_FIRST + 1.0
	assert_ne(o.moment(), "")
	tap("demo:2", "a", o)
	assert_true(Game.photos[-1].golden)
	o.stage_t = o.MOMENT_FIRST + o.MOMENT_LEN + 1.0
	o.gleam_t = 0.0
	o.photo_cd = 0.0
	assert_eq(o.moment(), "")
	tap("demo:2", "a", o)
	assert_false(Game.photos[-1].golden)


func test_sunrise_every_20_seconds() -> void:
	var o := _orbit(3)
	run(o, 41.0)
	assert_eq(Game.sunrises, 2)
