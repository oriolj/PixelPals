extends "res://tests/flight/helpers.gd"
## The launch pad screen: the countdown ritual with real seats.


func _launch(n := 3) -> Node:
	seat(n)
	var l := open("launch")
	l.auto_goto = false
	return l


func test_launcher_press_starts_and_mashing_cannot_skip() -> void:
	var l := _launch(3)
	run(l, 1.0)
	assert_eq(l.countdown.state, l.Countdown.State.WAIT, "waits for the Launcher")
	tap("demo:0", "a", l)
	tap("demo:1", "a", l)
	assert_eq(l.countdown.state, l.Countdown.State.WAIT, "only the Launcher's button launches")
	tap("demo:2", "b", l)
	assert_eq(l.countdown.state, l.Countdown.State.COUNT, "any Launcher button starts the count")
	var t := 0.0
	var i := 0
	while l.countdown.state == l.Countdown.State.COUNT:
		drive("demo:2", {"a": i % 2 == 0}, l)
		i += 1
		t += DT
	assert_almost_eq(t, 5.0, 0.1, "mashing did not speed the count up")
	assert_gt(l.presses_during_count, 30, "each press shook the rocket instead")
	run(l, 1.7)
	assert_eq(l.phase, l.Phase.LIFTOFF)
	run(l, 5.0)
	assert_eq(l.phase, l.Phase.DONE, "the rocket left the screen")


func test_launch_presses_itself_after_eight_seconds() -> void:
	var l := _launch(3)
	run(l, 7.8)
	assert_eq(l.countdown.state, l.Countdown.State.WAIT)
	run(l, 0.4)
	assert_eq(l.countdown.state, l.Countdown.State.COUNT, "nobody is stuck on the pad")


func test_launch_goes_to_the_flight() -> void:
	var l := _launch(2)
	l.auto_goto = true
	tap("demo:1", "a", l)
	run(l, 12.0)
	await get_tree().process_frame
	assert_eq(Game.current_name, "flight")


func test_pilot_pause_on_the_pad() -> void:
	var l := _launch(3)
	tap("demo:0", "start", l)
	assert_true(l.paused)
	run(l, 10.0)
	assert_eq(l.countdown.state, l.Countdown.State.WAIT, "no auto press while paused")
	tap("demo:0", "a", l)
	assert_false(l.paused)
