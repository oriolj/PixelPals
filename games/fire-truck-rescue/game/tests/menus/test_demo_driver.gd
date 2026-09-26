extends GutTest
## Demo driver: scripted input for all three seats, and the level presets.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const Rig := preload("res://tests/helpers/level_rig.gd")

var dd: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Rig.cleanup()
	Game.current = null


func test_level_start_seats_three_with_riders() -> void:
	dd.start("level")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.level_preset, "")


func test_presets_open_the_level() -> void:
	dd.start("cat")
	assert_eq(dd.screen, "level")
	assert_eq(Game.level_preset, "cat")
	var lvl := Rig.make_level(self)
	assert_eq(Game.level_preset, "", "consumed by the level")
	assert_true(lvl.objective().kind == "cat", "parked under a stuck cat")
	assert_true(lvl.truck.pos.distance_to(lvl.cats[lvl.objective().cat].tree) < 8.5)
	dd.start("home")
	var lvl2 := Rig.make_level(self)
	assert_eq(lvl2.state, lvl2.State.HOMEWARD)
	assert_eq(lvl2.cats_saved, 3)


func test_level_script_drives_to_the_fire_sprays_and_sirens() -> void:
	dd.start("level")
	var lvl := Rig.make_level(self)
	lvl.next_fire_t = 0.5
	Game.current = lvl
	var t := 0.0
	var sirens := 0
	var sprayed := false
	while t < 40.0 and lvl.stars == 0:
		dd.drive("level", t, Rig.DT)
		Players.poll()
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			sirens += 1
		lvl.step(Rig.DT)
		sprayed = sprayed or lvl.spraying
		t += Rig.DT
	assert_true(sprayed, "the hose seat sprayed")
	assert_eq(lvl.stars, 3, "the first fire is out")
	assert_gt(sirens, 2, "the siren seat pressed every few seconds")


func test_party_start_sets_the_results() -> void:
	dd.start("party")
	assert_eq(Game.stars, 18)
	assert_eq(Game.cats, 3)
	assert_eq(Players.seated_count(), 3)


func test_join_script_presses_three_devices_in_turn() -> void:
	dd.start("join")
	assert_eq(Players.seated_count(), 0)
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


func test_world_to_stick_is_camera_relative() -> void:
	assert_eq(DemoDriver.world_to_stick(Vector2(0, -1), 0.0), Vector2(0, -1), "north = up when the camera looks north")
	var s: Vector2 = DemoDriver.world_to_stick(Vector2(0, -1), PI / 2.0)
	assert_almost_eq(s.x, 1.0, 0.001, "north = right when the camera looks west")
