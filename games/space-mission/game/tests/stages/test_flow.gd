extends "res://tests/helpers.gd"
## The mission flow: stage select, the seat fall-backs, the Pilot-only pause,
## and the toddler never changing the outcome.

const SelectScreen := preload("res://scripts/screens/select.gd")
const LandingScreen := preload("res://scripts/screens/landing.gd")


func test_stage_select_starts_at_chosen_stage() -> void:
	var want := ["orbit", "landing", "mars"]
	for stage in 3:
		Players.reset()
		seat(3)
		var sel := SelectScreen.new()
		sel.auto_goto = false
		add_child_autofree(sel)
		sel.set_process(false)
		for k in stage:
			Players.set_scripted("demo:0", {"move": Vector2(0, 1)})
			Players.poll()
			sel._process(DT)
			Players.set_scripted("demo:0", {})
			Players.poll()
			sel._process(DT)
		assert_eq(sel.start_stage, stage)
		Players.set_scripted("demo:0", {"start": true})
		Players.poll()
		sel._process(DT)
		assert_eq(sel.next_screen, want[stage])
		assert_eq(Game.start_stage, stage)
		Players.set_scripted("demo:0", {})
	# Only the Pilot moves the planet row.
	Players.reset()
	seat(3)
	Game.start_stage = 0
	var s2 := SelectScreen.new()
	s2.auto_goto = false
	add_child_autofree(s2)
	s2.set_process(false)
	Players.set_scripted("demo:1", {"move": Vector2(0, 1)})
	Players.poll()
	s2._process(DT)
	assert_eq(s2.start_stage, 0)


func test_the_flow_runs_orbit_landing_mars_party() -> void:
	assert_eq(Game.next_after("orbit"), "landing")
	assert_eq(Game.next_after("landing"), "mars")
	assert_eq(Game.next_after("mars"), "party")


func test_one_seat_and_two_seat_fallbacks() -> void:
	# One seat: the arm runs itself, the Pilot's A is the camera.
	seat(1)
	assert_true(Game.arm_auto())
	var o := open("orbit")
	tap("demo:0", "a", o)
	assert_eq(Game.photos.size(), 1, "the Pilot's A takes the photo")
	o.cargo.pos = o.tip() + Vector2(8, 0)
	drive({}, o)
	assert_true(o.holding, "the arm grabs by itself")
	o.free()
	Game.current = null
	Game.photos.clear()
	# Two seats: the Pilot's B takes photos; A does not.
	Players.reset()
	seat(2)
	assert_false(Game.arm_auto())
	var p := open("orbit")
	tap("demo:0", "a", p)
	assert_eq(Game.photos.size(), 0)
	p.photo_cd = 0.0
	tap("demo:0", "b", p)
	assert_eq(Game.photos.size(), 1, "the Pilot's B takes the photo")
	p.free()
	Game.current = null
	# Two seats at the landing: the parachute beat waits less for the empty seat.
	var l := open("landing")
	assert_true(l.beats.empty[l.beats.Beat.PARACHUTE])
	var t := run_until(l, func(): return l.chute_open, 10.0)
	assert_lt(t, LandingScreen.ENTRY_TIME + 2.5)
	l.free()
	Game.current = null
	# Pilot + Camera, no Arm: the landing site is picked for them, the rover's arm drills alone.
	Players.reset()
	seat_only([0, 2])
	var m := open("mars")
	m.rover.place(m.targets[0].x - m.TOOL_OFF, m.terrain)
	var d := run_until(m, func(): return m.drilling != -1, 3.0, {"demo:0": {"a": true}})
	assert_lt(d, 1.5, "no Arm seat: drilled within a second")


func test_pause_only_by_pilot() -> void:
	seat(3)
	for scr_name in ["orbit", "landing", "mars"]:
		if is_instance_valid(Game.current):
			Game.current.free()
		var scr := open(scr_name)
		tap("demo:1", "start", scr)
		tap("demo:2", "start", scr)
		assert_false(scr._pause.paused, "%s: only the Pilot pauses" % scr_name)
		tap("demo:0", "start", scr)
		assert_true(scr._pause.paused, "%s: the Pilot pauses" % scr_name)
		var frozen: float = scr.stage_t if "stage_t" in scr else scr.total_t
		run(scr, 1.0)
		var now: float = scr.stage_t if "stage_t" in scr else scr.total_t
		assert_eq(now, frozen, "%s: nothing moves in pause" % scr_name)
		tap("demo:1", "b", scr)
		assert_eq(scr.next_screen, "", "the Arm's B does nothing")
		tap("demo:0", "a", scr)
		assert_false(scr._pause.paused, "A resumes")
		tap("demo:0", "start", scr)
		tap("demo:0", "b", scr)
		assert_eq(scr.next_screen, "join", "%s: the Pilot's B in pause goes back" % scr_name)


## Runs the whole mission with nobody but the given scripted seats, returns the outcome.
func _mission(mash: bool) -> Dictionary:
	Players.reset()
	seat(3)
	Game.new_mission()
	Game.mission_scale = 0.3
	var toddler := func(t: float) -> Dictionary:
		return {"demo:2": {"a": mash and fmod(t, 0.4) < 0.05}}
	var reached: Array[String] = []
	for scr_name in ["orbit", "landing", "mars"]:
		if is_instance_valid(Game.current):
			Game.current.free()
		var scr := open(scr_name)
		var t := 0.0
		while scr.next_screen == "" and t < 600.0:
			drive(toddler.call(t), scr)
			t += DT
		reached.append(scr.next_screen)
	return {"reached": reached, "modules": Game.modules.duplicate(), "docked": Game.docked,
		"site": Game.site, "samples": Game.samples.duplicate(), "phoned": Game.phoned_home}


func test_toddler_input_never_changes_mission_outcome() -> void:
	var calm := _mission(false)
	var photos_calm := Game.photos.size()
	var busy := _mission(true)
	assert_eq(calm.reached, ["landing", "mars", "party"] as Array[String], "the mission always ends")
	assert_eq(busy.reached, calm.reached)
	assert_eq(busy.modules, calm.modules, "same station")
	assert_eq(busy.modules.size(), 5)
	assert_true(busy.docked)
	assert_eq(busy.site, calm.site, "same landing site")
	assert_eq(busy.samples, calm.samples, "same samples")
	assert_true(busy.phoned)
	assert_eq(photos_calm, 0)
	assert_gt(Game.photos.size(), 10, "the toddler's presses only add photos")
