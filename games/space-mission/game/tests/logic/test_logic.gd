extends GutTest
## The node-free logic: arm IK, flight, station, terrain, rover, helicopter,
## landing beats, photos.

const ArmIK := preload("res://scripts/logic/arm_ik.gd")
const Flight := preload("res://scripts/logic/space_flight.gd")
const Station := preload("res://scripts/logic/station.gd")
const Terrain := preload("res://scripts/logic/terrain.gd")
const Rover := preload("res://scripts/logic/rover.gd")
const Heli := preload("res://scripts/logic/helicopter.gd")
const Beats := preload("res://scripts/logic/landing_beats.gd")
const Photos := preload("res://scripts/logic/photos.gd")
const DT := 1.0 / 30.0


func test_arm_ik_reaches_every_point_in_range() -> void:
	var base := Vector2(100, 60)
	var l1 := 23.0
	var l2 := 23.0
	var checked := 0
	for r in range(3, 46):
		for k in 24:
			var target := base + Vector2.RIGHT.rotated(TAU * k / 24.0) * float(r)
			assert_true(ArmIK.in_reach(base, target, l1, l2))
			for bend in [1.0, -1.0]:
				var s := ArmIK.solve(base, target, l1, l2, bend)
				assert_true(s.reached, "reaches %s" % target)
				assert_lt(s.tip.distance_to(target), 0.01)
				assert_almost_eq(s.elbow.distance_to(base), l1, 0.01, "first bone keeps its length")
				assert_almost_eq(s.tip.distance_to(s.elbow), l2, 0.01, "second bone keeps its length")
				checked += 1
	assert_gt(checked, 2000)
	# Out of reach: the tip stops at full stretch toward the target.
	var far := ArmIK.solve(base, base + Vector2(100, 0), l1, l2)
	assert_false(far.reached)
	assert_almost_eq(far.tip.distance_to(base), l1 + l2, 0.01)


func test_arm_ik_bend_side() -> void:
	var s := ArmIK.solve(Vector2.ZERO, Vector2(30, 0), 20, 20, 1.0)
	assert_lt(s.elbow.y, 0.0, "bend +1 lifts the elbow (y up is negative)")
	var t := ArmIK.solve(Vector2.ZERO, Vector2(30, 0), 20, 20, -1.0)
	assert_gt(t.elbow.y, 0.0)


func test_flight_stabilises_when_idle() -> void:
	var f := Flight.new(Vector2(100, 60))
	f.bounds = Rect2(0, 0, 320, 180)
	for i in 30:
		f.step(DT, Vector2.RIGHT, true)
	assert_gt(f.vel.x, 30.0)
	assert_lte(f.vel.length(), Flight.MAX_BOOST_SPEED + 0.01)
	for i in 90:
		f.step(DT, Vector2.ZERO)
	assert_eq(f.vel, Vector2.ZERO, "stops by itself within 3 s")


func test_flight_bump_is_a_soft_push_back() -> void:
	var f := Flight.new(Vector2(100, 60))
	var wall := Rect2(118, 0, 40, 180)
	assert_true(f.push_out(wall))
	assert_false(f.rect().intersects(wall))
	assert_lt(f.vel.x, 0.0, "bounced back")


func test_module_only_docks_in_matching_port() -> void:
	var st := Station.new()
	for i in Station.SLOTS.size():
		var port := st.port_pos(i)
		for kind in Station.KINDS:
			var got := st.can_dock(kind, port)
			if kind == st.kind_of(i):
				assert_ne(got, -1, "%s fits its own port" % kind)
			else:
				assert_eq(got, -1, "%s never fits the %s port" % [kind, st.kind_of(i)])
	# Both solar ports take a solar module; a fitted port takes nothing more.
	st.fit(1)
	assert_eq(st.can_dock("solar", st.port_pos(1)), -1)
	assert_eq(st.can_dock("solar", st.port_pos(3)), 3)


func test_station_grows_after_each_module() -> void:
	var st := Station.new()
	var order: Array[String] = []
	var last := st.count()
	while not st.done():
		var i := st.next_slot()
		order.append(st.next_kind())
		st.fit(st.can_dock(st.kind_of(i), st.port_pos(i)))
		assert_eq(st.count(), last + 1)
		last = st.count()
	assert_eq(st.count(), 5)
	assert_eq(order, ["lab", "solar", "habitat", "solar", "robot"] as Array[String])


func test_missed_cargo_loops_back() -> void:
	var c := Station.new_cargo("lab")
	var looped := false
	for i in 3000:
		if Station.drift(c, DT):
			looped = true
			break
		assert_lt(c.pos.x, Station.LOOP_X + 1.0)
	assert_true(looped)
	assert_eq(c.pos.x, Station.SPAWN_X, "back at the left edge")
	assert_eq(c.loops, 1)
	# It keeps coming round.
	for i in 3000:
		Station.drift(c, DT)
	assert_gt(c.loops, 1)


func test_rover_never_flips_on_terrain() -> void:
	for site in Terrain.SITES:
		var tr := Terrain.new(3600, site)
		assert_lte(tr.max_slope(), 2.0, "%s: gentle hills (whole-pixel steps)" % site)
		var r := Rover.new()
		r.max_x = 3580.0
		r.place(Terrain.LAND_X, tr)
		var steps := 0
		# Full speed there and back, with a brake now and then.
		for dir in [1.0, -1.0, 1.0]:
			for i in 3600:
				r.step(DT, tr, dir, i % 200 < 10)
				steps += 1
				assert_true(r.upright(tr), "%s: upright at x=%d" % [site, r.x])
				assert_lte(absf(r.tilt), Rover.MAX_TILT + 0.0001)
				for k in 3:
					assert_lte(r.wheel_y[k], tr.height_at(r.x + Rover.WHEEL_X[k]) - Rover.WHEEL_R + 0.001)
		assert_gt(steps, 10000)


func test_rover_creeps_on_when_nobody_drives() -> void:
	var tr := Terrain.new(1200, "dunes")
	var r := Rover.new()
	r.place(Terrain.LAND_X, tr)
	for i in int(Rover.AUTO_AFTER / DT) - 2:
		r.step(DT, tr, 0.0)
	assert_almost_eq(r.x, Terrain.LAND_X, 0.01, "waits first")
	for i in 150:
		r.step(DT, tr, 0.0)
	assert_gt(r.x, Terrain.LAND_X + 20.0, "then rolls on")


func test_all_landing_sites_are_safe() -> void:
	for i in Terrain.SITES.size():
		var site: String = Terrain.SITES[i]
		# The beats: pick this site, then a Pilot who never lets go of "down".
		var b := Beats.new()
		b.site = 0
		var t := 0.0
		var ev := ""
		while b.beat != Beats.Beat.DONE and t < 30.0:
			var input := {"down": 1.0}
			if b.beat == Beats.Beat.SITE and not b.done_beat:
				input["arm_dir"] = 1 if b.site != i else 0
				input["arm_a"] = b.site == i
			ev = b.step(DT, input)
			t += DT
		assert_eq(b.beat, Beats.Beat.DONE, "%s: landed" % site)
		assert_eq(b.site, i)
		assert_lte(b.touchdown_speed, Beats.SAFE_TOUCHDOWN, "%s: a soft touchdown" % site)
		# The ground where the rover is set down is flat, and it stands upright.
		var tr := Terrain.new(3600, site)
		for dx in range(-30, 31):
			assert_eq(tr.height_at(Terrain.LAND_X + dx), Terrain.BASE_Y, "%s: flat landing zone" % site)
		var r := Rover.new()
		r.place(Terrain.LAND_X, tr)
		for k in 60:
			r.step(DT, tr, 0.0)
		assert_true(r.upright(tr))
		assert_almost_eq(r.tilt, 0.0, 0.001)
		assert_gt(tr.targets().size(), 8, "%s: rocks to drill" % site)


func test_every_landing_beat_autocompletes_without_input() -> void:
	var b := Beats.new()
	var starts := {}
	var done := {}
	var t := 0.0
	var prev := -1
	while b.beat != Beats.Beat.DONE and t < 40.0:
		if b.beat != prev:
			starts[b.beat] = t
			prev = b.beat
		var ev := b.step(DT, {})
		t += DT
		if ev in ["pop", "site", "touchdown"]:
			done[b.beat] = t - starts[b.beat]
	assert_eq(b.beat, Beats.Beat.DONE)
	assert_eq(done.size(), 3, "all three beats completed")
	assert_almost_eq(done[Beats.Beat.PARACHUTE], Beats.AUTO, DT * 2)
	assert_almost_eq(done[Beats.Beat.SITE], Beats.AUTO, DT * 2)
	assert_lt(done[Beats.Beat.CRANE], Beats.AUTO + 1.0, "the crane lowers itself after 5 s")
	assert_eq(b.auto_completed, [true, true, true] as Array[bool])
	# An empty seat's beat completes sooner.
	var e := Beats.new()
	e.empty[Beats.Beat.PARACHUTE] = true
	var tt := 0.0
	while e.step(DT, {}) != "pop":
		tt += DT
	assert_almost_eq(tt, Beats.AUTO_EMPTY, DT * 2)


func test_pressed_beats_finish_before_the_auto() -> void:
	var b := Beats.new()
	assert_eq(b.step(DT, {"camera": true}), "pop")
	assert_false(b.auto_completed[0])


func test_helicopter_cooldown_and_reveal() -> void:
	var h := Heli.new()
	var home := Vector2(100, 120)
	var target := Vector2(220, 140)
	h.pos = home
	assert_true(h.can_launch())
	assert_true(h.launch(3))
	assert_false(h.launch(3), "no second launch while it flies")
	assert_true(h.press(), "a press while flying loops")
	assert_false(h.press(), "one loop at a time")
	var revealed := false
	var landed := false
	var t := 0.0
	while t < 12.0 and not landed:
		var ev := h.step(DT, home, target)
		revealed = revealed or ev == "revealed"
		landed = ev == "landed"
		if ev == "revealed":
			assert_lt(absf(h.pos.x - target.x), 1.5, "the spotlight is over the target")
		t += DT
	assert_true(revealed)
	assert_true(landed)
	assert_eq(h.pos, home, "back on the rover")
	assert_false(h.launch(1), "resting after landing")
	var rest := 0.0
	while not h.can_launch():
		h.step(DT, home, target)
		rest += DT
	assert_almost_eq(rest, Heli.COOLDOWN, DT * 2)
	assert_true(h.launch(-1))
	assert_eq(h.loops, 1)
	assert_eq(h.launches, 2)


func test_photo_capture_stores_thumbnail() -> void:
	var album: Array = []
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color("#124e89"))
	img.fill_rect(Rect2i(0, 90, 320, 90), Color("#63c74d"))
	var e := Photos.store(album, img, true)
	assert_eq(album.size(), 1)
	assert_true(e.golden)
	var thumb: Image = e.tex.get_image()
	assert_eq(thumb.get_size(), Photos.THUMB)
	assert_eq(thumb.get_pixel(10, 5).to_html(false), "124e89", "nearest scaling keeps palette colours")
	assert_eq(thumb.get_pixel(10, 30).to_html(false), "63c74d")
	# No image (headless, no viewport): nothing stored, nothing breaks.
	assert_true(Photos.store(album, null, false).is_empty())
	assert_eq(album.size(), 1)
	# The album is bounded and keeps golden photos.
	for i in 40:
		Photos.store(album, img, false)
	assert_eq(album.size(), Photos.MAX_PHOTOS)
	assert_true(album[0].golden)
