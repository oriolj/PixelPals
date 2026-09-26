extends GutTest
## The rules of a run: points, platforms, passengers, carriages, the cow, the end.

const Sim := preload("res://scripts/level/sim.gd")
const Train := preload("res://scripts/track/train.gd")
const DT := 1.0 / 30.0

var sim
var events: Array = []


func _new(seed_value := 3, passengers := false):
	sim = Sim.new(seed_value, passengers)
	events = []
	sim.event.connect(func(kind, data): events.append([kind, data]))
	return sim


func _run(seconds: float, input := {}) -> void:
	var t := 0.0
	while t < seconds:
		sim.step(DT, input)
		t += DT


func _count(kind: String) -> int:
	var n := 0
	for e in events:
		if e[0] == kind:
			n += 1
	return n


func _place_before_node(node_name: String, back: float) -> void:
	var n: int = sim.track.node(node_name)
	var e: int = sim.track.in_edges[n][0]
	sim.train.place(e, sim.track.lengths[e] - back)


func _place_at_station(s: int, offset: float) -> void:
	var st: Dictionary = sim.track.stations[s]
	sim.train.place(st.edge, st.mark + offset)


func _board(colour: int) -> Dictionary:
	var p: Dictionary = sim.spawn(0, colour)
	p.state = "aboard"
	p.seat = sim._free_seat()
	return p


func test_points_flip_only_by_points_seat_and_lock_before_junction() -> void:
	_new()
	_place_before_node("J1", 900.0)
	var j1: int = sim.track.node("J1")
	sim.step(DT, {})
	assert_eq(sim.target_junction, j1)
	assert_false(sim.locked)
	# Driver input, horn and whistle never touch the points.
	var before: int = sim.choices[j1]
	_run(0.5, {"up": true, "horn": true, "whistle": true, "doors": true})
	assert_eq(sim.choices[j1], before, "only the points input throws the points")
	# The points seat can: down picks the lower (blue) branch, up the red one.
	sim.step(DT, {"points": Vector2i.DOWN})
	assert_eq(sim.track.out_edges[j1][sim.choices[j1]], sim.track.edge("blue"))
	sim.step(DT, {"points": Vector2i.UP})
	assert_eq(sim.track.out_edges[j1][sim.choices[j1]], sim.track.edge("red"))
	sim.step(DT, {"points": Vector2i.RIGHT})
	assert_eq(sim.track.out_edges[j1][sim.choices[j1]], sim.track.edge("blue"), "across both: toggles")
	# One second (at speed) before the junction it locks.
	_place_before_node("J1", 200.0)
	sim.train.speed = 250.0
	sim.throttle = 250.0 / Sim.V_MAX
	sim.step(DT, {})
	assert_true(sim.locked, "200 px at 250 px/s is under a second away")
	var locked_choice: int = sim.choices[j1]
	sim.step(DT, {"points": Vector2i.UP})
	assert_eq(sim.choices[j1], locked_choice, "locked: no flip")
	assert_gt(_count("points_locked"), 0, "the sign flashes instead")
	# And the train takes the branch that was shown.
	_run(1.5, {"up": true})
	assert_eq(sim.train.edge, sim.track.out_edges[j1][locked_choice])
	assert_ne(sim.target_junction, j1, "the next junction is now the target")


func test_level_input_maps_seats_to_roles() -> void:
	var Level := preload("res://scripts/screens/level.gd")
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()
	Players.set_scripted("demo:0", {"move": Vector2.LEFT, "a": true})
	Players.set_scripted("demo:2", {"move": Vector2.RIGHT, "a": true})
	Players.poll()
	var input: Dictionary = Level.read_input()
	assert_eq(input.points, Vector2i.ZERO, "driver and whistle seats never throw the points")
	assert_true(input.horn)
	assert_true(input.whistle)
	assert_false(input.doors)
	Players.set_scripted("demo:0", {})
	Players.set_scripted("demo:2", {})
	Players.set_scripted("demo:1", {"move": Vector2.LEFT, "a": true})
	Players.poll()
	input = Level.read_input()
	assert_eq(input.points, Vector2i.LEFT)
	assert_true(input.doors)
	assert_false(input.whistle)
	Players.reset()
	Players.clear_scripted()


func test_overshoot_rolls_back_into_platform() -> void:
	_new()
	_place_at_station(0, 200.0)  # 200 px past the stop post
	sim.train.speed = 0.0
	sim.throttle = 0.0
	sim._rested = false
	sim.step(DT, {})
	assert_eq(sim.mode, "rollback")
	assert_eq(_count("rollback"), 1, "beep beep")
	_run(0.9, {"up": true})
	assert_eq(sim.mode, "rollback", "the driver's input is ignored while it rolls back")
	_run(4.0, {})
	assert_eq(sim.mode, "docked")
	var st: Dictionary = sim.track.stations[0]
	assert_almost_eq(sim.train.past(st.edge, st.mark), 0.0, 4.0, "nose back at the stop post")
	assert_eq(sim.dock_station, 0)


func test_stopping_short_or_on_the_mark_docks() -> void:
	_new()
	_place_at_station(1, -250.0)
	sim._rested = false
	sim.step(DT, {})
	assert_eq(sim.mode, "docked", "250 px short still docks (passengers walk further)")
	assert_eq(sim.perfect_stops, 0)
	_new()
	_place_at_station(1, 10.0)
	sim._rested = false
	sim.step(DT, {})
	assert_eq(sim.mode, "docked")
	assert_eq(sim.perfect_stops, 1, "on the mark: sparkle")
	# A real stop by braking from cruise, starting a braking distance away.
	_new()
	_place_at_station(2, -500.0)
	sim.train.speed = 220.0
	sim.throttle = 220.0 / Sim.V_MAX
	var t := 0.0
	while sim.mode == "run" and t < 10.0:
		var st: Dictionary = sim.track.stations[2]
		var ahead: float = -sim.train.past(st.edge, st.mark)
		var v: float = sim.train.speed
		sim.step(DT, {"down": ahead <= v * v / (2.0 * Sim.BRAKE) + v * 0.1})
		t += DT
	assert_eq(sim.mode, "docked")


func test_passenger_boards_and_leaves_at_matching_colour_only() -> void:
	_new()
	var red_rider := _board(0)
	var green_rider := _board(3)
	var waiting: Dictionary = sim.spawn(0, 1)  # at red, wants blue
	_place_at_station(0, 0.0)
	sim._dock(0, false)
	_run(2.0, {})
	assert_eq(red_rider.state, "aboard", "doors stay shut until the points seat opens them")
	sim.step(DT, {"doors": true})
	_run(3.0, {})
	assert_eq(red_rider.state, "home", "the red passenger gets off at red")
	assert_eq(green_rider.state, "aboard", "the green one stays on")
	assert_eq(waiting.state, "aboard", "the waiting one hops on")
	assert_eq(sim.deliveries, [0] as Array[int])
	# At blue: the blue one gets off, green still stays.
	sim.mode = "run"
	_place_at_station(1, 0.0)
	sim._dock(1, false)
	_run(0.2, {"doors": true})
	_run(3.0, {})
	assert_eq(waiting.state, "home")
	assert_eq(green_rider.state, "aboard")
	assert_eq(sim.deliveries, [0, 1] as Array[int])


func test_doors_open_by_themselves_with_one_seat() -> void:
	_new()
	sim.solo = true
	_board(0)
	_place_at_station(0, 0.0)
	sim._dock(0, false)
	_run(1.1, {})
	assert_true(sim.doors_open)


func test_train_grows_to_max_five_carriages() -> void:
	_new()
	for i in 14:
		sim.spawn(0, 2)
	_place_at_station(0, 0.0)
	sim._dock(0, false)
	sim.step(DT, {"doors": true})
	_run(20.0, {})
	assert_true(sim.exchange_done)
	assert_eq(sim.train.cars, Train.MAX_CARS, "grew to five carriages")
	assert_eq(_count("coupled"), Train.MAX_CARS - 1)
	assert_eq(sim.aboard().size(), Train.MAX_CARS * Train.SEATS_PER_CAR)
	assert_eq(sim.waiting_at(0).size(), 4, "the rest wait for the next train")
	# The longest train still rides the rails through the curves.
	_run(0.1, {"up": true})
	sim.mode = "run"
	_run(8.0, {"up": true})
	for t in sim.train.car_transforms():
		var near := INF
		for e in sim.track.curves.size():
			near = minf(near, t.origin.distance_to(sim.track.curves[e].get_closest_point(t.origin)))
		assert_lt(near, 4.0)


func test_cow_steps_aside_on_whistle_and_train_never_stops_forever() -> void:
	_new()
	assert_eq(sim.cow.state, "on")
	sim.step(DT, {"whistle": true})
	assert_eq(sim.cow.state, "aside", "a whistle shoos the cow")
	# Without a whistle, the train slows, waits, and the cow moves by itself.
	_new()
	sim.train.place(sim.cow.edge, sim.cow.d - 700.0)
	var stopped_for := 0.0
	var longest := 0.0
	var t := 0.0
	var min_gap := INF
	var passed := false
	while t < 20.0:
		sim.step(DT, {"up": true})
		if sim.cow.state == "on":
			min_gap = minf(min_gap, sim.distance_ahead(sim.cow.edge, sim.cow.d))
		stopped_for = stopped_for + DT if sim.train.speed < 1.0 else 0.0
		longest = maxf(longest, stopped_for)
		if sim.train.edge == sim.cow.edge and sim.train.dist > sim.cow.d + 100.0:
			passed = true
		t += DT
	assert_eq(sim.cow.state, "aside")
	assert_gt(min_gap, 60.0, "never bumps the cow")
	assert_lt(longest, 2.5, "never stops for long")
	assert_true(passed, "and drives past it")


func test_one_seat_tour_rule_prefers_waiting_colour() -> void:
	_new()
	sim.solo = true
	var j1: int = sim.track.node("J1")
	_board(1)  # wants blue
	_place_before_node("J1", 800.0)
	sim.step(DT, {})
	assert_eq(sim.track.out_edges[j1][sim.choices[j1]], sim.track.edge("blue"))
	# Nobody aboard: a station with people waiting wins.
	_new()
	sim.solo = true
	sim.spawn(0, 2)  # waiting at red
	_place_before_node("J1", 800.0)
	sim.step(DT, {})
	assert_eq(sim.track.out_edges[j1][sim.choices[j1]], sim.track.edge("red"))
	# At J3 a passenger for yellow sends the train over the pond.
	_new()
	sim.solo = true
	_board(2)
	var j3: int = sim.track.node("J3")
	_place_before_node("J3", 400.0)
	sim.step(DT, {})
	assert_eq(sim.track.out_edges[j3][sim.choices[j3]], sim.track.edge("pond"))
	# Nothing to prefer: it alternates with the branch taken last time.
	_new()
	sim.solo = true
	sim.last_taken[j3] = 0
	assert_eq(sim.tour_choice(j3), 1)
	sim.last_taken[j3] = 1
	assert_eq(sim.tour_choice(j3), 0)


func test_run_ends_at_twelve_deliveries_or_six_minutes() -> void:
	_new()
	assert_eq(sim.run_len, 360.0, "six minutes")
	for i in 11:
		sim.deliveries.append(i % 4)
	sim.step(DT, {})
	assert_false(sim.ended)
	sim.deliveries.append(0)
	sim.step(DT, {})
	assert_true(sim.ended, "twelve deliveries end the run")
	assert_eq(_count("run_end"), 1)
	_run(20.0, {})  # the finale rolls gently into the next platform and stops there
	assert_eq(sim.train.speed, 0.0, "stopped")
	var so: Array = sim.station_offset()
	assert_ne(so[0], -1)
	assert_almost_eq(so[1], 0.0, 3.0, "at the stop post")
	_new()
	sim.run_len = 360.0
	_run(359.0, {"up": true})
	assert_false(sim.ended)
	_run(1.5, {"up": true})
	assert_true(sim.ended, "six minutes end the run")


func test_the_whistle_seat_can_never_hurt_the_run() -> void:
	_new(5, true)
	var waiting: int = sim.waiting_count()
	var choices: Dictionary = sim.choices.duplicate()
	for i in 600:
		sim.step(DT, {"whistle": i % 2 == 0})
	assert_eq(sim.choices, choices, "no points thrown")
	assert_eq(sim.train.speed, 0.0, "the train does not move")
	assert_eq(sim.mode, "run")
	assert_true(sim.waiting_count() >= waiting, "nobody leaves")
	assert_false(sim.ended)
	# At a station it only speeds the boarding up.
	_new()
	sim.spawn(0, 1)
	sim.spawn(0, 2)
	_place_at_station(0, 0.0)
	sim._dock(0, false)
	sim.step(DT, {"doors": true, "whistle": true})
	assert_true(sim.fast_hops)
	assert_eq(_count("bell"), 1)
	_run(0.9, {})
	assert_eq(sim.aboard().size(), 2, "both hopped on quickly")


func test_passengers_never_leave_and_keep_coming() -> void:
	_new(9, true)
	# Pick four up (no timer on anybody left behind), then wait.
	for s in 2:
		for p in sim.waiting_at(s):
			p.state = "aboard"
	var ids := {}
	for p in sim.passengers:
		if p.state == "waiting":
			ids[p.id] = true
	_run(60.0, {})
	for p in sim.passengers:
		if ids.has(p.id):
			assert_eq(p.state, "waiting", "still waiting, no timer")
	assert_gt(sim.passengers.size(), ids.size(), "new passengers arrive")
	assert_lte(sim.waiting_count(), Sim.WAITING_MAX)
