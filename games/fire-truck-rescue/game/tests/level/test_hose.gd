extends GutTest
## The hose: live only when slow and in range, aim assist, hydrant super spray.

const Rig := preload("res://tests/helpers/level_rig.gd")
const Rules := preload("res://scripts/level/rules.gd")
const FireState := preload("res://scripts/level/fire_state.gd")


func after_each() -> void:
	Rig.cleanup()


func _fire(pos: Vector2, lit := true) -> Object:
	var f := FireState.new()
	f.pos = pos
	if lit:
		f.activate()
	return f


## Hose seat holding A, stick pointing (on screen) at `target`.
func _aim(lvl: Node, target: Vector2) -> Dictionary:
	var d: Vector2i = Rules.world_to_screen4(target - lvl.truck.pos, lvl.cam_yaw)
	return {"demo:1": {"a": true, "move": Vector2(d)}}


func test_hose_only_live_when_slow_and_in_range() -> void:
	assert_true(Rules.hose_live(0.0))
	assert_true(Rules.hose_live(1.5))
	assert_false(Rules.hose_live(3.0), "faster than walking")
	assert_false(Rules.hose_live(-3.0), "reversing too")
	Rig.seat(2)
	var lvl := Rig.make_level(self)
	var fi: int = lvl.order[0]
	Rig.activate(lvl, fi)
	Rig.park(lvl, lvl.map.fires[fi].park)
	var aim := _aim(lvl, lvl.fires[fi].pos)
	Rig.step(lvl, aim)
	assert_true(lvl.spraying, "parked in range: water")
	assert_eq(lvl.spray_fire, fi)
	# Moving: no water, the fire is untouched.
	var water: float = lvl.fires[fi].water
	lvl.truck.speed = 6.0
	Rig.step(lvl, aim)
	assert_false(lvl.spraying, "moving: no water")
	assert_eq(lvl.fires[fi].water, water)
	# Stopped but far away: water goes nowhere near the fire.
	var far: Vector2i = lvl.map.station.door_cell
	Rig.park(lvl, far)
	if lvl.truck.pos.distance_to(lvl.fires[fi].pos) > Rules.HOSE_RANGE:
		Rig.step(lvl, _aim(lvl, lvl.fires[fi].pos))
		assert_eq(lvl.spray_fire, -1, "out of range")


func test_aim_assist_picks_nearest_fire_in_quadrant() -> void:
	var fires := [
		_fire(Vector2(3, 0.5)),       # 0 east, near
		_fire(Vector2(6, -1)),        # 1 east, farther
		_fire(Vector2(1.5, -5)),      # 2 north-ish (within 60 deg of north)
		_fire(Vector2(0, 20)),        # 3 south, out of range
		_fire(Vector2(-2, 0), false), # 4 west, not burning
	]
	var o := Vector2.ZERO
	assert_eq(Rules.pick_fire(o, Vector2.RIGHT, fires), 0, "nearest in the east")
	assert_eq(Rules.pick_fire(o, Vector2(0, -1), fires), 2, "north")
	assert_eq(Rules.pick_fire(o, Vector2(0, 1), fires), -1, "south is out of range")
	assert_eq(Rules.pick_fire(o, Vector2.LEFT, fires), -1, "an unlit fire is ignored")
	fires[0].out = true
	assert_eq(Rules.pick_fire(o, Vector2.RIGHT, fires), 1, "then the next one")
	# Screen directions through the camera: up is away from the camera.
	assert_almost_eq(Rules.screen_to_world(Vector2i(0, -1), 0.0).distance_to(Vector2(0, -1)), 0.0, 0.001)
	assert_almost_eq(Rules.screen_to_world(Vector2i(1, 0), 0.0).distance_to(Vector2(1, 0)), 0.0, 0.001)
	assert_eq(Rules.world_to_screen4(Vector2(0.2, -1), 0.0), Vector2i(0, -1))
	assert_eq(Rules.world_to_screen4(Vector2(0, -1), PI / 2.0), Vector2i(1, 0), "camera turned: north is screen-right")


func test_spraying_a_fire_out_gives_three_stars() -> void:
	Rig.seat(2)
	var lvl := Rig.make_level(self)
	var fi: int = lvl.order[0]
	Rig.activate(lvl, fi)
	Rig.park(lvl, lvl.map.fires[fi].park)
	Rig.run(lvl, 3.2, _aim(lvl, lvl.fires[fi].pos))
	assert_true(lvl.fires[fi].out)
	assert_eq(lvl.stars, 3)
	assert_eq(lvl.thankers.size(), 1, "somebody comes out to wave")


func test_spraying_people_giggles() -> void:
	Rig.seat(2)
	var lvl := Rig.make_level(self)
	var folk: Dictionary = lvl.town.folk[0]
	lvl._fun_targets(folk.pos)
	assert_eq(lvl.giggles, 1)
	assert_gt(folk.hop, 0.0, "they hop, nobody is scolded")


func test_hydrant_super_spray_lasts_five_seconds() -> void:
	Rig.seat(2)
	var lvl := Rig.make_level(self)
	var hp: Vector2 = lvl.map.hydrants[0].pos
	lvl.truck.place(hp + Vector2(0.5, 0.5), 0.0)
	lvl.left_station = true
	Rig.step(lvl)
	assert_eq(lvl.super_count, 1, "brushing the hydrant")
	assert_almost_eq(lvl.super_t, Rules.SUPER_SECONDS, 0.05)
	lvl.truck.place(lvl.map.station.bay, 0.0)
	Rig.run(lvl, 4.8)
	assert_gt(lvl.super_t, 0.0, "still super at 4.8 s")
	Rig.run(lvl, 0.3)
	assert_eq(lvl.super_t, 0.0, "over after 5 s")


func test_super_spray_puts_fires_out_faster() -> void:
	var f := FireState.new()
	f.activate()
	f.step(1.0, Rules.SUPER_RATE)
	assert_eq(f.size, 1, "1 s of super spray already knocks a size off")
