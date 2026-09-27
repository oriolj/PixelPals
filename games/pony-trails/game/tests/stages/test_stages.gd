extends "res://tests/helpers.gd"
## The stages driven frame by frame: the stable's cat, the toddler never
## hurting, the seat fall-backs, the Rider-only pause, the stage select.

const Grooming := preload("res://scripts/logic/grooming.gd")
const SelectScreen := preload("res://scripts/screens/select.gd")
const ShowCourse := preload("res://scripts/logic/show_course.gd")


func test_stable_autofinishes_at_90s() -> void:
	# The rule: nothing from the cat before 90 s, then everything is finished.
	var g := Grooming.new()
	for i in int(89.0 / DT):
		assert_eq(g.cat_step(i * DT, DT), "")
	var t := 90.0
	while not g.ready_to_go() and t < 110.0:
		g.cat_step(t, DT)
		t += DT
	assert_true(g.ready_to_go(), "the cat finished the patches, the hooves, the saddle and the ribbon")
	assert_lt(t, 90.0 + 12.0 * Grooming.CAT_EVERY)
	# The stage: three seats that never touch anything still reach the trail.
	seat(3)
	var st := open("stable")
	var took := run_until(st, func(): return st.next_screen != "", 110.0)
	assert_lt(took, 100.0)
	assert_eq(st.next_screen, "trail")
	assert_true(st.groom.saddled and st.groom.all_clean())


func test_stable_carrots_go_every_third_to_the_foal() -> void:
	seat(3)
	var st := open("stable")
	for i in 3:
		tap("demo:2", "a", st)
		run(st, 0.6)
	assert_eq(Game.day.carrots, 3)
	assert_eq(st.groom.carrots, 3)


func test_toddler_input_never_hurts() -> void:
	# The stable: mashing carrots never undoes any grooming.
	seat(3)
	var st := open("stable")
	st.groom.brush = 0
	run(st, 1.0, {"demo:1": {"a": true}})
	var dirt: float = st.groom.dirt[0]
	for i in 60:
		drive({"demo:2": {"a": i % 2 == 0}}, st)
	assert_lte(st.groom.dirt[0], dirt)
	st.free()
	Game.current = null
	# The trail: the same ride with and without a toddler mashing every key.
	var results := []
	for mash in [false, true]:
		Game.new_day()
		var tr := open("trail")
		for i in int(50.0 / DT):
			var states := {"demo:0": {"move": Vector2(1, 0) if i < 60 else Vector2.ZERO}}
			if mash:
				states["demo:2"] = {"a": i % 3 == 0}
			drive(states, tr)
		results.append([tr.mare.x, tr.mare.clean_jumps, tr.mare.step_overs, Game.day.apples])
		tr.free()
		Game.current = null
	assert_gte(results[1][0], results[0][0] - 0.5, "the toddler never slows the ride (gates open sooner)")
	assert_eq(results[1][1], results[0][1], "nor changes a jump")
	# The show: mashing never changes the course's outcome.
	var outs := []
	for mash in [false, true]:
		var sc := ShowCourse.new(true, false)
		for i in int(40.0 / DT):
			var input := {"bell": mash or sc.phase_t > 5.0}
			if mash:
				input["bell"] = i % 2 == 0
			sc.step(DT, input)
		outs.append([sc.clean_count(), sc.refusals])
	assert_eq(outs[0], outs[1])


func test_one_and_two_seat_fallbacks() -> void:
	# One seat: the brush scrubs by itself (slowly), the foal steers and hops
	# by itself, and the Rider's B neighs.
	seat(1)
	assert_true(Game.foal_auto())
	var st := open("stable")
	run(st, 3.0)
	var total := 0.0
	for d in st.groom.dirt:
		total += d
	assert_lt(total, 4.0, "the brush scrubbed on its own")
	st.free()
	Game.current = null
	var tr := open("trail")
	run(tr, 40.0)
	assert_gt(int(Game.day.apples) + int(Game.day.flowers), 0, "the self-steering foal picked things up")
	tap("demo:0", "b", tr)
	assert_ne(tr.neigh_t, -1.0, "the Rider's B neighs")
	tr.free()
	Game.current = null
	# Two seats, no toddler: a gate opens about 1 s after she arrives.
	Players.reset()
	seat_only([0, 1])
	Game.new_day()
	var tr2 := open("trail")
	var g: Dictionary = tr2.course.gates[0]
	var arrived := -1.0
	var t := 0.0
	while int(g.state) == 0 and t < 200.0:
		drive({"demo:0": {"move": Vector2(1, 0)}}, tr2)
		t += DT
		if arrived < 0.0 and float(g.x) - tr2.mare.x <= 44.0:
			arrived = t
	assert_gt(arrived, 0.0)
	assert_lt(t - arrived, 1.3)
	assert_false(Game.has_toddler())


func test_pause_only_by_rider() -> void:
	seat(3)
	var tr := open("trail")
	run(tr, 1.0)
	for d in ["demo:1", "demo:2"]:
		var x0: float = tr.mare.x
		tap(d, "start", tr)
		run(tr, 0.5)
		assert_false(tr._pause.paused, d + " cannot pause")
		assert_gt(tr.mare.x, x0)
	tap("demo:0", "start", tr)
	assert_true(tr._pause.paused)
	var x1: float = tr.mare.x
	run(tr, 1.0, {"demo:1": {"a": true}, "demo:2": {"a": true}})
	assert_eq(tr.mare.x, x1, "nothing moves while paused")
	tap("demo:0", "a", tr)
	assert_false(tr._pause.paused, "the Rider's A resumes")
	tap("demo:0", "start", tr)
	tap("demo:0", "b", tr)
	assert_eq(tr.next_screen, "join", "the Rider's B in pause goes back to join")


func test_stage_select() -> void:
	var want := ["stable", "trail", "show"]
	for stage in 3:
		Players.reset()
		seat(3)
		var sel := SelectScreen.new()
		sel.auto_goto = false
		add_child_autofree(sel)
		sel.set_process(false)
		# The Rider readies, then moves the stage row with right.
		_sel(sel, {"demo:0": {"a": true}})
		_sel(sel, {})
		for k in stage:
			_sel(sel, {"demo:0": {"move": Vector2(1, 0)}})
			_sel(sel, {})
		assert_eq(sel.start_stage, stage)
		_sel(sel, {"demo:0": {"start": true}})
		assert_eq(sel.next_screen, want[stage])
		assert_eq(Game.start_stage, stage)
		assert_eq(Game.start_screen(), want[stage])
	# Only the Rider moves the stage row, and only once ready.
	Players.reset()
	seat(3)
	Game.start_stage = 0
	var s2 := SelectScreen.new()
	s2.auto_goto = false
	add_child_autofree(s2)
	s2.set_process(false)
	_sel(s2, {"demo:1": {"a": true}})
	_sel(s2, {"demo:1": {"move": Vector2(1, 0)}})
	_sel(s2, {"demo:2": {"a": true}})
	assert_eq(s2.start_stage, 0)
	# The flow of the day.
	assert_eq(Game.next_after("stable"), "trail")
	assert_eq(Game.next_after("trail"), "show")
	assert_eq(Game.next_after("show"), "party")


func _sel(sel: Node, states: Dictionary) -> void:
	for i in 3:
		Players.set_scripted("demo:%d" % i, states.get("demo:%d" % i, {}))
	Players.poll()
	sel.step(DT)
