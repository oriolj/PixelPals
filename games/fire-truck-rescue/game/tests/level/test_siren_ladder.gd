extends GutTest
## Siren seat: any button, cooldown, only that seat; the ladder and the cats;
## the automatic jobs when seats are empty; every press answered at once.

const Rig := preload("res://tests/helpers/level_rig.gd")
const Rules := preload("res://scripts/level/rules.gd")


func after_each() -> void:
	Rig.cleanup()


func _press(lvl: Node, device: String, button: String) -> void:
	Rig.step(lvl, {device: {button: true}})
	Rig.step(lvl)


func test_siren_any_button_and_cooldown_only_siren_seat() -> void:
	Rig.seat(3)
	var lvl := Rig.make_level(self)
	_press(lvl, "demo:0", "a")
	assert_eq(lvl.horn_count, 1, "the driver's A is the horn")
	assert_eq(lvl.siren_count, 0, "not the siren")
	_press(lvl, "demo:1", "a")
	assert_eq(lvl.siren_count, 0, "the hose seat never sirens")
	_press(lvl, "demo:2", "b")
	assert_eq(lvl.siren_count, 1, "any button of the siren seat, even b")
	assert_gt(lvl.siren_t, 0.0, "lights and siren on")
	_press(lvl, "demo:2", "start")
	assert_eq(lvl.siren_count, 1, "cooldown: no second siren")
	assert_eq(lvl.bark_count, 1, "a bark and a flash instead: the press still does something")
	Rig.run(lvl, Rules.SIREN_COOLDOWN + 0.1)
	_press(lvl, "demo:2", "a")
	assert_eq(lvl.siren_count, 2, "after the cooldown, siren again")
	assert_eq(lvl.stars, 0)
	assert_eq(lvl.state, lvl.State.RUN, "the toddler can never hurt the run")


func test_ladder_rescues_cat_only_when_parked_near_tree() -> void:
	Rig.seat(3)
	var lvl := Rig.make_level(self)
	lvl.cats[0].waiting = true
	# Far away (in the station): no ladder.
	_press(lvl, "demo:2", "a")
	assert_true(lvl.rescue.is_empty(), "too far")
	# Near, but driving past.
	Rig.park(lvl, lvl.cats[0].park)
	lvl.truck.speed = 5.0
	Rig.step(lvl, {"demo:2": {"a": true}})
	assert_true(lvl.rescue.is_empty(), "moving")
	Rig.step(lvl)
	# Parked under the tree.
	Rig.park(lvl, lvl.cats[0].park)
	Rig.run(lvl, Rules.SIREN_COOLDOWN + 0.1)
	_press(lvl, "demo:2", "a")
	assert_false(lvl.rescue.is_empty(), "the ladder goes up")
	assert_eq(lvl.rescue.cat, 0)
	Rig.run(lvl, 4.5)
	assert_true(lvl.cats[0].rescued, "the cat rode down")
	assert_eq(lvl.cats_saved, 1)
	assert_true(lvl.rescue.is_empty(), "ladder back down")


func test_one_seat_auto_hose_and_auto_ladder() -> void:
	Rig.seat(1)
	var lvl := Rig.make_level(self)
	# Leaving the station sounds the siren by itself.
	lvl.truck.place(lvl.map.cell_center(lvl.map.station.door_cell), 0.0)
	Rig.step(lvl)
	assert_eq(lvl.siren_count, 1, "auto siren when leaving the station")
	# Auto hose: parked by a fire, nobody on the hose.
	var fi: int = lvl.order[0]
	Rig.activate(lvl, fi)
	Rig.park(lvl, lvl.map.fires[fi].park)
	Rig.run(lvl, 0.2)
	assert_true(lvl.spraying, "the hose sprays by itself")
	Rig.run(lvl, 3.2)
	assert_true(lvl.fires[fi].out, "and puts the fire out")
	# Auto ladder: parked under a stuck cat.
	var c: int = 1
	lvl.cats[c].waiting = true
	Rig.park(lvl, lvl.cats[c].park)
	Rig.run(lvl, 1.2)
	assert_false(lvl.rescue.is_empty(), "the ladder rises by itself")
	Rig.run(lvl, 4.5)
	assert_true(lvl.cats[c].rescued)


func test_two_seats_hose_is_the_kids_but_the_ladder_is_automatic() -> void:
	Rig.seat(2)
	var lvl := Rig.make_level(self)
	var fi: int = lvl.order[0]
	Rig.activate(lvl, fi)
	Rig.park(lvl, lvl.map.fires[fi].park)
	Rig.run(lvl, 1.0)
	assert_false(lvl.spraying, "the hose kid is seated: no auto spray")
	lvl.cats[0].waiting = true
	Rig.park(lvl, lvl.cats[0].park)
	Rig.run(lvl, 1.2)
	assert_false(lvl.rescue.is_empty(), "no siren seat: auto ladder")


func test_every_press_answered_within_two_frames() -> void:
	Rig.seat(3)
	var lvl := Rig.make_level(self)
	var fi: int = lvl.order[0]
	Rig.activate(lvl, fi)
	Rig.park(lvl, lvl.map.fires[fi].park)
	var d: Vector2i = Rules.world_to_screen4(lvl.fires[fi].pos - lvl.truck.pos, lvl.cam_yaw)
	Rig.step(lvl, {"demo:0": {"a": true}, "demo:1": {"a": true, "move": Vector2(d)}, "demo:2": {"a": true}})
	var now: float = lvl.time
	assert_eq(lvl.answered[0], now, "horn on the press frame")
	assert_eq(lvl.horn_count, 1)
	assert_eq(lvl.answered[1], now, "hose on the press frame")
	assert_true(lvl.spraying, "water on the press frame")
	assert_eq(lvl.answered[2], now, "siren on the press frame")
	assert_gt(lvl.siren_t, 0.0)
	# A hose press while moving is answered too (a drip), not ignored.
	Rig.step(lvl)
	lvl.truck.speed = 6.0
	Rig.step(lvl, {"demo:1": {"a": true}})
	assert_eq(lvl.answered[1], lvl.time)
