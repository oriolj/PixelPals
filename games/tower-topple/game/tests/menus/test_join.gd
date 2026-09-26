extends GutTest
## Join screen: seats in press order, "b" leaves, only the Builder continues, and
## the Builder can move a pad from the Dropper seat to the Toppler seat.

const JoinScreen := preload("res://scripts/screens/join.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	screen = JoinScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)  # driven manually


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	screen._process(DT)


func _press(d: String, button := "a") -> void:
	_step({d: {button: true}})
	_step({d: {}})


func test_join_order_assigns_seats() -> void:
	_press("demo:b")
	_press("demo:a")
	_press("demo:c")
	assert_eq(Players.device_of(Players.Seat.DRIVER), "demo:b")
	assert_eq(Players.device_of(Players.Seat.GUNNER), "demo:a")
	assert_eq(Players.device_of(Players.Seat.HONKER), "demo:c")


func test_toddler_block_takes_the_honker_seat() -> void:
	_press("kb:2")  # someone presses Space first
	assert_eq(Players.seat_of("kb:2"), Players.Seat.HONKER)
	assert_eq(screen.join_device("demo:a"), Players.Seat.DRIVER)


func test_real_device_bumps_toddler_block_out_of_a_lower_seat() -> void:
	Players.join("demo:h")
	Players.join_seat("demo:h2", Players.Seat.HONKER)
	Players.leave(Players.Seat.DRIVER)
	Players.leave(Players.Seat.GUNNER)
	Players.join_seat("demo:x", Players.Seat.GUNNER)
	Players.join_seat("kb:2", Players.Seat.DRIVER)
	assert_eq(screen.join_device("demo:y"), Players.Seat.DRIVER)
	assert_eq(Players.seat_of("kb:2"), -1)


func test_b_leaves_the_seat() -> void:
	_press("demo:a")
	_press("demo:b")
	_press("demo:a", "b")
	assert_false(Players.is_seated(Players.Seat.DRIVER))
	assert_eq(Players.seat_of("demo:b"), Players.Seat.GUNNER)
	_press("demo:c")
	assert_eq(Players.seat_of("demo:c"), Players.Seat.DRIVER, "the freed seat is taken next")


func test_b_never_joins() -> void:
	_press("demo:a", "b")
	assert_eq(Players.seated_count(), 0)


func test_start_from_the_driver_only() -> void:
	_press("demo:a")
	_press("demo:b")
	_press("demo:b", "start")
	assert_eq(screen.next_screen, "", "gunner start does nothing")
	_press("demo:a", "start")
	assert_eq(screen.next_screen, "select")


func test_joining_press_does_not_continue() -> void:
	_step({"demo:a": {"start": true}})
	assert_eq(Players.seat_of("demo:a"), Players.Seat.DRIVER)
	assert_eq(screen.next_screen, "")


func test_driver_holding_a_for_a_second_continues() -> void:
	_press("demo:a")
	_step({"demo:a": {"a": true}})
	for i in 20:
		_step()
	assert_eq(screen.next_screen, "", "not yet")
	assert_gt(screen.hold, 0.0)
	for i in 15:
		_step()
	assert_eq(screen.next_screen, "select")


func test_the_joining_hold_does_not_count() -> void:
	_step({"demo:a": {"a": true}})
	for i in 45:
		_step()
	assert_eq(screen.next_screen, "", "must release after joining")


func test_builder_down_moves_the_dropper_pad_to_the_toppler_seat() -> void:
	_press("demo:a")
	_press("demo:b")
	_step({"demo:a": {"move": Vector2.DOWN}})
	_step({"demo:a": {}})
	assert_eq(Players.seat_of("demo:b"), Players.Seat.HONKER, "dad + toddler on two pads")
	assert_false(Players.is_seated(Players.Seat.GUNNER))
	_step({"demo:a": {"move": Vector2.UP}})
	_step({"demo:a": {}})
	assert_eq(Players.seat_of("demo:b"), Players.Seat.GUNNER, "and back")


func test_space_bar_toddler_is_never_moved_up() -> void:
	_press("demo:a")
	_press("kb:2")
	assert_false(screen.move_to_dropper())
	assert_eq(Players.seat_of("kb:2"), Players.Seat.HONKER)
