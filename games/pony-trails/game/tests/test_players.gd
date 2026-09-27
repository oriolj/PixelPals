extends GutTest
## Seats, joining and per-seat input, driven by scripted devices.


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func test_seats_fill_in_role_order() -> void:
	assert_eq(Players.join("demo:a"), Players.Seat.DRIVER)
	assert_eq(Players.join("demo:b"), Players.Seat.GUNNER)
	assert_eq(Players.join("demo:c"), Players.Seat.HONKER)
	assert_eq(Players.join("demo:d"), -1, "fourth device gets no seat")
	assert_eq(Players.seated_count(), 3)


func test_same_device_cannot_take_two_seats() -> void:
	Players.join("kb:0")
	assert_eq(Players.join("kb:0"), -1)
	assert_eq(Players.seated_count(), 1)


func test_leaving_frees_the_seat_for_the_next_join() -> void:
	Players.join("demo:a")
	Players.join("demo:b")
	Players.leave(Players.Seat.DRIVER)
	assert_eq(Players.join("demo:c"), Players.Seat.DRIVER)


func test_unplugged_pad_leaves_its_seat() -> void:
	Players.join("pad:7")
	Players._on_joy_connection_changed(7, false)
	assert_false(Players.is_seated(Players.Seat.DRIVER))


func test_just_pressed_is_one_frame_only() -> void:
	Players.join("demo:a")
	Players.set_scripted("demo:a", {"a": true})
	Players.poll()
	assert_true(Players.just_pressed(Players.Seat.DRIVER, "a"))
	Players.poll()
	assert_false(Players.just_pressed(Players.Seat.DRIVER, "a"), "held, not just pressed")
	assert_true(Players.pressed(Players.Seat.DRIVER, "a"))


func test_dir4_snaps_diagonals_to_the_dominant_axis() -> void:
	Players.join("demo:a")
	Players.set_scripted("demo:a", {"move": Vector2(0.9, 0.4)})
	Players.poll()
	assert_eq(Players.dir4(Players.Seat.DRIVER), Vector2i(1, 0))
	Players.set_scripted("demo:a", {"move": Vector2(-0.2, -0.8)})
	Players.poll()
	assert_eq(Players.dir4(Players.Seat.DRIVER), Vector2i(0, -1))
	Players.set_scripted("demo:a", {"move": Vector2(0.1, 0.1)})
	Players.poll()
	assert_eq(Players.dir4(Players.Seat.DRIVER), Vector2i.ZERO, "inside the deadzone")


func test_empty_seat_reads_as_idle() -> void:
	assert_eq(Players.move(Players.Seat.GUNNER), Vector2.ZERO)
	assert_false(Players.pressed(Players.Seat.HONKER, "any"))


func test_unseated_devices_that_press_are_offered_to_join() -> void:
	Players.set_scripted("demo:x", {"a": true})
	Players.poll()
	assert_has(Players.unseated_devices_just_pressed(), "demo:x")
	Players.join("demo:x")
	assert_does_not_have(Players.unseated_devices_just_pressed(), "demo:x")


func test_dir4_just_pressed_fires_once_per_flick() -> void:
	Players.join("demo:a")
	Players.set_scripted("demo:a", {"move": Vector2(1, 0)})
	Players.poll()
	assert_eq(Players.dir4_just_pressed(Players.Seat.DRIVER), Vector2i(1, 0))
	Players.poll()
	assert_eq(Players.dir4_just_pressed(Players.Seat.DRIVER), Vector2i.ZERO, "held")
	Players.set_scripted("demo:a", {"move": Vector2(0, -1)})
	Players.poll()
	assert_eq(Players.dir4_just_pressed(Players.Seat.DRIVER), Vector2i(0, -1), "new direction")
	assert_eq(Players.dir4_just_pressed(Players.Seat.GUNNER), Vector2i.ZERO, "empty seat")
