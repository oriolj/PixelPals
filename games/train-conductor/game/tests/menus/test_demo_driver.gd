extends GutTest
## Demo driver: scripted input for all three seats, and a full run played
## through the real seat-to-role input mapping.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const Sim := preload("res://scripts/level/sim.gd")
const Level := preload("res://scripts/screens/level.gd")
const DT := 1.0 / 30.0

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
	Game.level_setup = {}


func test_level_start_seats_three_with_riders() -> void:
	dd.start("level")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.seed_value, DemoDriver.DEMO_SEED)
	assert_true(Game.level_setup.is_empty())


func test_finale_start_is_the_level_near_the_end() -> void:
	dd.start("finale")
	assert_eq(dd.screen, "level")
	assert_eq(Game.level_setup.deliveries, 11)


func test_party_start_sets_the_results() -> void:
	dd.start("party")
	assert_eq(Game.deliveries.size(), 12)
	assert_eq(Game.stars, 15)


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
		t += DT
	assert_eq(joined, ["demo:0", "demo:1", "demo:2"] as Array[String])


func test_demo_driver_plays_a_full_run() -> void:
	dd.start("level")
	var sim = Sim.new(DemoDriver.DEMO_SEED)
	var whistles := 0
	var counts := {"docked": 0, "coupled": 0, "took_branch": 0}
	sim.event.connect(func(kind, _data): if counts.has(kind): counts[kind] += 1)
	var t := 0.0
	while t < 150.0 and not sim.ended:
		var st: Array[Dictionary] = [{}, {}, {}]
		dd._drive_level(sim, t, DT, st)
		for i in 3:
			Players.set_scripted(DemoDriver.DEVICES[i], st[i])
		Players.poll()
		var input: Dictionary = Level.read_input()
		if input.whistle:
			whistles += 1
		sim.step(DT, input)
		t += DT
	assert_gte(counts.docked, 4, "stops at platforms")
	assert_gte(counts.coupled, 1, "the train grows")
	assert_gte(sim.deliveries.size(), 4, "passengers get home")
	assert_gte(counts.took_branch, 4, "passes junctions")
	assert_gte(whistles, 40, "the whistle seat presses every 3 s")
