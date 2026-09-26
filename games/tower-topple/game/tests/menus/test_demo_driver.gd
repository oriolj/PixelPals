extends GutTest
## Demo driver: scripted input for all three seats.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const PlayScreen := preload("res://scripts/screens/play.gd")

var dd: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.tower_seconds = Game.DEFAULT_TOWER_SECONDS
	Game.reset_results()


func test_play_start_seats_three_and_shortens_towers() -> void:
	dd.start("play")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.tower_seconds, DemoDriver.DEMO_TOWER_SECONDS)


func test_party_start_sets_results() -> void:
	dd.start("party")
	assert_eq(Game.tower_heights, [5, 8, 3] as Array[int])
	assert_eq(Game.stars, 16)


func test_play_targets_include_two_misses() -> void:
	dd.start("play")
	var p := PlayScreen.new()
	p.auto_goto = false
	add_child_autofree(p)
	p.set_process(false)
	var misses := 0
	for n in 10:
		p.drops = n
		var tg := DemoDriver.play_targets(p, 1.0)
		if tg.miss:
			misses += 1
			assert_gt(absf(tg.drop_at - p.tower_com_x()), 120.0, "a miss aims at the ball pit")
		else:
			assert_eq(tg.drop_at, p.tower_com_x())
	assert_eq(misses, 2)


func test_toddler_presses_every_two_seconds_in_play() -> void:
	dd.start("play")
	var presses := 0
	var t := 0.0
	while t < 6.5:
		dd.drive("play", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			presses += 1
		t += 1.0 / 30.0
	assert_between(presses, 3, 4)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	var joined: Array[String] = []
	var t := 0.0
	while t < 3.5:
		dd.drive("join", t)
		Players.poll()
		for d in Players.unseated_devices_just_pressed("any"):
			Players.join(d)
			joined.append(d)
		t += 1.0 / 30.0
	assert_eq(joined, ["demo:0", "demo:1", "demo:2"] as Array[String])
