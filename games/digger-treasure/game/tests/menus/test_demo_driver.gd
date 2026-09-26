extends GutTest
## Demo driver: scripted input for all three seats.

const DemoDriver := preload("res://scripts/demo_driver.gd")

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
	Game.run_seconds = 0.0
	Game.found.clear()


func test_dig_start_seats_three_with_riders_and_a_short_run() -> void:
	dd.start("dig")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.run_seconds, 20.0)


func test_dig_script_scoops_every_one_and_a_half_seconds_and_booms_three_times() -> void:
	dd.start("dig")
	var scoops := 0
	var booms := []
	var aims := []
	var t := 0.0
	while t < 9.0:
		dd.drive("dig", t)
		Players.poll()
		if Players.just_pressed(Players.Seat.GUNNER, "a"):
			scoops += 1
			aims.append(Players.dir4(Players.Seat.GUNNER))
		if Players.just_pressed(Players.Seat.HONKER, "any"):
			booms.append(snappedf(t, 0.1))
		t += 1.0 / 30.0
	assert_eq(scoops, 6, "every 1.5 s")
	assert_eq(aims[0], Vector2i.DOWN, "down first")
	assert_eq(aims[-1], Vector2i.RIGHT, "then right")
	assert_eq(booms.size(), 3)
	assert_almost_eq(booms[0], 2.0, 0.1)
	assert_almost_eq(booms[2], 6.0, 0.1)


func test_party_start_fills_the_truck() -> void:
	dd.start("party")
	assert_eq(Game.found.size(), 12)
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


func test_driver_heads_for_the_nearest_buried_treasure() -> void:
	var saved = Game.current
	var fake := FakeDig.new()
	add_child_autofree(fake)
	Game.current = fake
	var v: Vector2 = dd.driver_move()
	Game.current = saved
	assert_almost_eq(v.x, 0.6, 0.01)
	assert_almost_eq(v.y, 0.8, 0.01)


class FakeDig extends Node:
	var body := BodyStub.new()

	func nearest_buried() -> Dictionary:
		return {"rect": Rect2i()}

	func treasure_center(_t: Dictionary) -> Vector2:
		return Vector2(130, 140)


class BodyStub extends RefCounted:
	var pos := Vector2(100, 100)
