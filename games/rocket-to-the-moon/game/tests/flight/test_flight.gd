extends "res://tests/flight/helpers.gd"
## The flight screen driven frame by frame: the no-fail rules, the roles and
## their fold-down for fewer seats, the landing and the whole trip.

const Rules := preload("res://scripts/logic/rules.gd")
const Claw := preload("res://scripts/logic/claw.gd")


func _flight(n := 3) -> Node:
	seat(n)
	var f := open("flight")
	f.rocket_pos = Vector2(160, 128)
	return f


func test_asteroid_bump_never_stops_the_rocket() -> void:
	var f := _flight(3)
	f.fuel_count = 5
	var clock: float = f.stage_t
	var scroll: float = f.scroll
	var a: Dictionary = f.spawn_asteroid(f.rocket_pos)
	a.vel = Vector2.ZERO
	f.step(DT)
	assert_gt(f.invuln, 0.0, "blinking invulnerability")
	assert_almost_eq(f.invuln, Rules.INVULN_SECONDS - DT, 0.05)
	assert_gt(f.wobble_t, 0.0, "the wobble spin")
	assert_eq(f.fuel_count, 3, "two cans fell out")
	assert_eq(f.pickups.filter(func(p): return p.dropped).size(), 2)
	assert_gt(f.scroll, scroll, "still flying")
	assert_gt(f.stage_t, clock, "the trip clock keeps going")
	assert_gt(f.speed, 0.0)
	# A second asteroid inside the invulnerability does nothing.
	var b: Dictionary = f.spawn_asteroid(f.rocket_pos)
	b.vel = Vector2.ZERO
	f.step(DT)
	assert_eq(f.fuel_count, 3)
	for i in 60:
		f.step(DT)
	assert_eq(f.stage, f.Stage.SKY, "nothing ended")
	assert_gt(f.speed, 0.0)


func test_bump_with_no_fuel_takes_nothing() -> void:
	var f := _flight(1)
	f.fuel_count = 0
	f.bump(f.spawn_asteroid(f.rocket_pos))
	assert_eq(f.fuel_count, 0, "never negative")
	assert_eq(f.pickups.size(), 0)


func test_empty_fuel_slows_but_never_stops() -> void:
	var f := _flight(2)
	f.step(DT)
	var full: float = f.speed
	f.tank = 0.0
	var clock: float = f.stage_t
	f.step(DT)
	assert_almost_eq(f.speed, full * Rules.EMPTY_FACTOR, 0.01, "30 % slower")
	assert_gt(f.speed, 0.0, "never stops")
	assert_almost_eq(f.stage_t - clock, DT, 0.0001, "the trip clock is not slowed")
	# Hours on an empty tank: still moving, still counting.
	for i in 300:
		f.step(DT)
	assert_gt(f.speed, 0.0)
	assert_eq(f.tank, 0.0)
	f.collect(f.spawn_pickup("fuel", f.rocket_pos))
	assert_gt(f.tank, 0.0, "a can refills it")
	assert_eq(f.fuel_count, 1)


func test_dropped_fuel_can_be_grabbed_back() -> void:
	var f := _flight(2)
	f.fuel_count = 4
	f.bump(f.spawn_asteroid(f.rocket_pos + Vector2(20, 0)))
	assert_eq(f.fuel_count, 2)
	f.invuln = 99.0  # nothing else interferes
	for i in 20:
		f.step(DT)  # the cans float out and slow down nearby
	var dropped: Array = f.pickups.filter(func(p): return p.dropped)
	assert_eq(dropped.size(), 2)
	for p in dropped:
		assert_lt(f.rocket_pos.distance_to(p.pos), 90.0, "they float nearby")
	# The Grabber aims at each can in turn and shoots.
	for p in dropped:
		var to: Vector2 = p.pos - f.claw_origin()
		var d := Vector2i(int(signf(to.x)), 0) if absf(to.x) >= absf(to.y) else Vector2i(0, int(signf(to.y)))
		drive("demo:1", {"move": Vector2(d)}, f)
		drive("demo:1", {"move": Vector2(d), "a": true}, f)
		drive("demo:1", {}, f)
		for i in 60:
			f.step(DT)
			if f.claw.idle():
				break
	assert_eq(f.fuel_count, 4, "both cans came back")


func test_claw_in_game_grabs_a_planet_into_the_album() -> void:
	var f := _flight(2)
	var p: Dictionary = f.spawn_pickup("planet", f.rocket_pos + Vector2(10, -60), 6)
	drive("demo:1", {"move": Vector2.UP}, f)
	drive("demo:1", {"move": Vector2.UP, "a": true}, f)
	drive("demo:1", {}, f)
	for i in 60:
		f.step(DT)
	assert_false(f.pickups.has(p))
	assert_true(Game.trip_planets.has(6))
	assert_true(Game.album.has(6))


func test_booster_cooldown() -> void:
	var f := _flight(3)
	tap("demo:2", "a", f)
	assert_gt(f.boost_t, 0.0, "the Launcher's press fires the booster")
	var first: float = f.boost_cd
	assert_almost_eq(first, Rules.BOOST_COOLDOWN - DT, 0.05)
	for i in 10:
		f.step(DT)
	tap("demo:2", "b", f)  # any button, but still cooling down
	assert_lt(f.boost_cd, first, "a press inside the cooldown does not restart it")
	for i in 40:
		f.step(DT)
	assert_eq(f.boost_t, 0.0, "a boost lasts one second")
	assert_eq(f.boost_cd, 0.0)
	tap("demo:2", "start", f)
	assert_gt(f.boost_t, 0.0, "ready again after 1.2 s")
	assert_false(f.paused, "the Launcher's start is just a boost, never a pause")


func test_booster_turns_asteroids_into_stars() -> void:
	var f := _flight(3)
	var ahead: Dictionary = f.spawn_asteroid(f.rocket_pos + Vector2(8, -50))
	var aside: Dictionary = f.spawn_asteroid(f.rocket_pos + Vector2(110, -50))
	ahead.vel = Vector2.ZERO
	aside.vel = Vector2.ZERO
	var tank: float = f.tank
	tap("demo:2", "a", f)
	assert_false(f.asteroids.has(ahead), "the asteroid in the lane became stars")
	assert_true(f.asteroids.has(aside), "the booster only cleans its lane")
	assert_gt(f.fx.filter(func(p): return p.get("home", false)).size(), 0, "sparkles fly home")
	# While boosting, even an asteroid on the rocket cannot bump it.
	var on: Dictionary = f.spawn_asteroid(f.rocket_pos + Vector2(0, 30))
	on.vel = Vector2.ZERO
	f.step(DT)
	assert_eq(f.invuln, 0.0)
	for i in 40:
		f.step(DT)
	assert_gt(f.tank + 0.001, tank - Rules.DRAIN * 1.5, "the stars topped the tank up")


func test_launcher_can_never_hurt_the_run() -> void:
	var f := _flight(3)
	f.fuel_count = 7
	var x: Vector2 = f.rocket_pos
	for i in 200:
		drive("demo:2", {"a": i % 2 == 0, "b": i % 3 == 0, "start": i % 5 == 0}, f)
	assert_eq(f.fuel_count, 7, "mashing costs nothing")
	assert_eq(f.invuln, 0.0, "and bumps nothing")
	assert_false(f.paused)
	assert_eq(f.rocket_pos.x, x.x, "the booster never moves the rocket")


func test_soft_walls_keep_the_rocket_on_screen() -> void:
	var f := _flight(1)
	for i in 120:
		drive("demo:0", {"move": Vector2(-1, -1)}, f)
	assert_eq(f.rocket_pos.x, f.X_MIN)
	assert_eq(f.rocket_pos.y, f.Y_MIN, "the rocket stays in the lower third")
	assert_gt(f.rocket_pos.y, 180.0 / 2.0)
	for i in 200:
		drive("demo:0", {"move": Vector2(1, 1)}, f)
	assert_eq(f.rocket_pos.x, f.X_MAX)
	assert_eq(f.rocket_pos.y, f.Y_MAX)


func test_offpad_landing_bounces_and_pad_slides_after_three() -> void:
	var f := _flight(3)
	f.stage = f.Stage.MOON
	f.stage_t = f.approach_len()
	f.step(DT)
	assert_eq(f.stage, f.Stage.LANDING)
	f.pad_x = 280.0
	f.rocket_pos.x = 60.0
	var bounces := 0
	var t := 0.0
	var last_tries := 0
	while f.stage == f.Stage.LANDING and t < 40.0:
		f.step(DT)
		t += DT
		if f.tries != last_tries:
			last_tries = f.tries
			bounces += 1
			assert_lt(f.rocket_vy, 0.0, "an off-pad touchdown bounces back up")
			assert_eq(f.stage, f.Stage.LANDING, "and never crashes")
			if f.tries < Rules.LANDING_TRIES:
				assert_false(f.pad_sliding)
	assert_eq(bounces, 3, "three tries")
	assert_true(f.pad_sliding, "then the pad slides under the rocket")
	assert_eq(f.stage, f.Stage.LANDED)
	assert_true(Rules.on_pad(f.rocket_pos.x, f.pad_x))


func test_onpad_landing_lands_first_time() -> void:
	var f := _flight(1)
	f.stage = f.Stage.MOON
	f.stage_t = f.approach_len()
	f.step(DT)
	f.pad_x = f.rocket_pos.x
	for i in 300:
		f.step(DT)
		if f.stage != f.Stage.LANDING:
			break
	assert_eq(f.stage, f.Stage.LANDED)
	assert_eq(f.tries, 0)


func test_trip_always_reaches_the_moon() -> void:
	# Real stage lengths, nobody touching anything, three seats: every
	# transition presses itself after 8 s and the pad comes to the rocket.
	seat(3)
	Game.goto("flight")
	var f: Node = Game.current
	f.set_process(false)
	var t := 0.0
	var seen := {}
	var step := 1.0 / 20.0
	while Game.current_name == "flight" and t < 420.0:
		Players.poll()
		f.step(step)
		t += step
		seen[f.stage] = true
	assert_eq(Game.current_name, "party", "the trip ended at the party on the Moon")
	for s in [f.Stage.SKY, f.Stage.SPACE, f.Stage.MOON, f.Stage.LANDING, f.Stage.LANDED]:
		assert_true(seen.has(s), "went through stage %d" % s)
	assert_true(f.separated, "the stage separation happened")
	assert_true(f.flags_planted)
	gut.p("the trip took %.0f s of game time" % t)
	assert_between(t, 250.0, 330.0, "about five minutes (%.0f s)" % t)


func test_one_seat_pilot_launches_and_boosts() -> void:
	seat(1)
	assert_eq(Game.press_seat(), 0, "alone, the Pilot owns the button")
	var l := open("launch")
	l.auto_goto = false
	tap("demo:0", "a", l)
	assert_eq(l.countdown.state, l.Countdown.State.COUNT, "the Pilot's A launched")
	root.remove_child(l)
	l.free()
	var f := open("flight")
	f.rocket_pos = Vector2(160, 128)
	tap("demo:0", "a", f)
	assert_gt(f.boost_t, 0.0, "the Pilot's A boosts")
	# No Grabber: pickups near the rocket are pulled in and collected.
	f.spawn_pickup("fuel", f.rocket_pos + Vector2(30, -20))
	for i in 30:
		f.step(DT)
	assert_eq(f.fuel_count, 1, "the magnet collected the can")


func test_two_seats_grabber_presses_and_booster_fires_itself() -> void:
	seat(2)
	assert_eq(Game.press_seat(), 1, "the Grabber's A launches")
	var f := open("flight")
	f.stage_t = f.lengths.sky
	f.step(DT)
	assert_eq(f.awaiting, f.AWAIT_SPACE)
	tap("demo:1", "a", f)
	assert_eq(f.stage, f.Stage.SPACE)
	assert_gt(f.boost_t, 0.0, "the booster fired by itself at the stage change")


func test_transition_waits_then_presses_itself_after_eight_seconds() -> void:
	var f := _flight(3)
	f.stage_t = f.lengths.sky
	f.step(DT)
	assert_eq(f.awaiting, f.AWAIT_SPACE)
	run(f, 7.5)
	assert_eq(f.stage, f.Stage.SKY, "waiting for the Launcher")
	run(f, 0.6)
	assert_eq(f.stage, f.Stage.SPACE, "pressed itself")


func test_separation_countdown_drops_the_stage() -> void:
	var f := _flight(3)
	f.stage = f.Stage.SPACE
	f.stage_t = f.lengths.space * 0.5
	f.step(DT)
	assert_ne(f.separation, null)
	tap("demo:2", "a", f)
	assert_eq(f.separation.state, f.Countdown.State.COUNT)
	run(f, 3.2)
	assert_eq(f.separation, null)
	assert_true(f.separated)
	assert_false(f.stage_sprite.visible, "the lower stage fell away")


func test_pause_only_responds_to_the_pilot() -> void:
	var f := _flight(3)
	tap("demo:1", "start", f)
	tap("demo:2", "start", f)
	assert_false(f.paused)
	tap("demo:0", "start", f)
	assert_true(f.paused)
	var t: float = f.trip_t
	tap("demo:2", "a", f)
	assert_eq(f.trip_t, t, "time stands still")
	tap("demo:0", "b", f)
	assert_eq(Game.current_name, "join")


func test_works_with_every_party_size_and_timeline() -> void:
	for n in [1, 2, 3]:
		Players.reset()
		seat(n)
		Game.goto("flight")
		var f: Node = Game.current
		f.set_process(false)
		f.stage = f.Stage.SPACE
		f._load_stage("space")
		for i in 300:
			Players.poll()
			f.step(DT)
		assert_eq(f.stage, f.Stage.SPACE)
		assert_gt(f.pickups.size() + f.asteroids.size(), 0, "the timeline spawned things")
