extends "res://tests/helpers.gd"
## The Mars surface: drilling, the helicopter, the sunset.


func _mars(n := 3, site := "dunes") -> Node:
	seat(n)
	Game.site = site
	return open("mars")


## Parks the rover so target i is right at the arm's reach point.
func _park_at(m: Node, i: int) -> void:
	m.rover.place(m.targets[i].x - m.TOOL_OFF, m.terrain)


func test_drill_collects_sample_of_rock_colour() -> void:
	var sites := {"red": "dunes", "grey": "rocks", "white": "crater", "ice": "ice", "shell": "dunes"}
	seat(3)
	for kind in sites:
		if is_instance_valid(Game.current):
			Game.current.free()
		Game.site = sites[kind]
		var m := open("mars")
		var i := -1
		for k in m.targets.size():
			if m.targets[k].kind == kind:
				i = k
				break
		assert_ne(i, -1, "a %s target exists" % kind)
		_park_at(m, i)
		drive({"demo:1": {"a": true}}, m)
		assert_eq(m.drilling, i, "drilling the %s rock" % kind)
		run(m, m.DRILL_TIME + 0.1)
		assert_true(m.targets[i].drilled)
		assert_eq(Game.samples[-1], kind, "the capsule has the rock's colour")
		assert_eq(m.tray[-1], kind)


func test_a_missed_drill_just_tries_again() -> void:
	var m := _mars(3)
	m.rover.place(150.0, m.terrain)  # nothing in reach
	assert_true(m.in_range().is_empty())
	drive({"demo:1": {"a": true}}, m)
	assert_true("poke" in m.events)
	assert_eq(Game.samples.size(), 0)
	run(m, 1.0)
	_park_at(m, 0)
	drive({"demo:1": {"a": true}}, m)
	assert_eq(m.drilling, 0, "the next try works")


func test_direction_picks_the_target() -> void:
	var m := _mars(3)
	# Two targets side by side in reach: left picks the nearer-left one.
	m.targets[1].x = m.targets[0].x + 30.0
	m.rover.place(m.targets[0].x - m.TOOL_OFF + 15.0, m.terrain)
	assert_eq(m.in_range().size(), 2)
	assert_eq(m.pick(Vector2i.RIGHT), 1)
	assert_eq(m.pick(Vector2i.LEFT), 0)


func test_a_rock_in_reach_is_drilled_for_you_after_5s() -> void:
	var m := _mars(3)
	_park_at(m, 0)
	var t := run_until(m, func(): return m.drilling != -1, 7.0, {"demo:0": {"a": true}})
	assert_almost_eq(t, m.AUTO, 0.2)


func test_helicopter_cooldown_and_reveal_on_screen() -> void:
	var m := _mars(3)
	tap("demo:2", "a", m)
	assert_true(m.heli.flying())
	var target: int = m.heli.target
	assert_ne(target, -1)
	var t := run_until(m, func(): return m.targets[target].revealed, 5.0, {"demo:0": {"a": true}})
	assert_lt(t, 5.0, "the spotlight reveals the next rock")
	tap("demo:2", "a", m)
	assert_eq(m.heli.loops, 1, "a press in flight loops")
	run_until(m, func(): return m.heli.state == m.heli.State.COOLDOWN, 8.0, {"demo:0": {"a": true}})
	tap("demo:2", "a", m)
	assert_false(m.heli.flying(), "resting: no launch")
	run(m, 3.1)
	tap("demo:2", "a", m)
	assert_true(m.heli.flying(), "launches again after the cooldown")


func test_sunset_is_blue_and_the_rover_phones_home() -> void:
	var m := _mars(3)
	m.rover.place(m.world_w - m.SUNSET_MARGIN - 1.0, m.terrain)
	var t := run_until(m, func(): return m.phase == m.Phase.SUNSET, 3.0, {"demo:0": {"move": Vector2(1, 0)}})
	assert_lt(t, 3.0)
	run(m, m.SUNSET_TIME + 0.1)
	assert_eq(m._sky.blend, 1.0)
	assert_eq(m.phase, m.Phase.PHONE)
	assert_true(Game.phoned_home)
	run(m, m.PHONE_TIME + 0.1)
	assert_eq(m.next_screen, "party")


func test_nobody_at_the_controls_still_reaches_the_sunset() -> void:
	Game.mission_scale = 0.3
	var m := _mars(1)
	var t := run_until(m, func(): return m.next_screen != "", 300.0)
	assert_lt(t, 300.0)
	assert_eq(m.next_screen, "party")
	assert_gt(Game.samples.size(), 0, "the arm drilled by itself")
