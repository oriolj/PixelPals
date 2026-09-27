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


# ---------------------------------------------------------------- quit combo

var _quits := 0


func _count_quit() -> void:
	_quits += 1


func _with_counter() -> void:
	_quits = 0
	Players.quit_action = _count_quit
	Players.quit_combo_enabled = true
	Players._quit_tick(0.0)  # a frame with nothing held arms the combo


func _restore_quit() -> void:
	Players.clear_scripted()
	Players._quit_tick(0.0)
	Players.quit_action = Callable()
	Players.quit_combo_enabled = true


func test_back_plus_start_held_quits_after_the_hold_time() -> void:
	_with_counter()
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players._quit_tick(1.0)
	assert_eq(_quits, 0, "not yet: 1.0 s of 1.5 s")
	Players._quit_tick(0.6)
	assert_eq(_quits, 1, "quit after 1.5 s")
	Players._quit_tick(2.0)
	assert_eq(_quits, 1, "still held: quits once, needs a release to re-arm")
	_restore_quit()


func test_releasing_early_resets_the_hold() -> void:
	_with_counter()
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players._quit_tick(1.2)
	Players.set_scripted("demo:q", {"start": true})
	Players._quit_tick(0.1)
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players._quit_tick(1.2)
	assert_eq(_quits, 0, "each hold starts from zero")
	_restore_quit()


func test_start_or_back_alone_never_quits() -> void:
	_with_counter()
	Players.set_scripted("demo:q", {"start": true})
	Players._quit_tick(5.0)
	Players.set_scripted("demo:q", {"back": true})
	Players._quit_tick(5.0)
	assert_eq(_quits, 0)
	_restore_quit()


func test_combo_held_from_before_needs_a_release() -> void:
	_quits = 0
	Players.quit_action = _count_quit
	Players.quit_combo_enabled = false  # e.g. the launcher while a game ran
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players.quit_combo_enabled = true
	Players._quit_tick(3.0)
	assert_eq(_quits, 0, "a hold that began before arming is ignored")
	Players.clear_scripted()
	Players._quit_tick(0.0)
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players._quit_tick(1.6)
	assert_eq(_quits, 1, "armed after the release")
	_restore_quit()


func test_disabled_combo_does_nothing() -> void:
	_with_counter()
	Players.quit_combo_enabled = false
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players._quit_tick(5.0)
	assert_eq(_quits, 0)
	_restore_quit()


func test_ctrl_q_quits() -> void:
	_with_counter()
	var ev := InputEventKey.new()
	ev.pressed = true
	ev.physical_keycode = KEY_Q
	ev.ctrl_pressed = true
	Players._quit_key(ev)
	assert_eq(_quits, 1)
	var plain := InputEventKey.new()
	plain.pressed = true
	plain.physical_keycode = KEY_Q
	Players._quit_key(plain)
	assert_eq(_quits, 1, "Q alone is kb:0's back button, not quit")
	_restore_quit()


func test_the_combo_leaves_seat_input_untouched() -> void:
	_with_counter()
	Players.join("demo:q")
	Players.set_scripted("demo:q", {"back": true, "start": true})
	Players.poll()
	assert_true(Players.pressed(Players.Seat.DRIVER, "start"), "start still reads as start")
	assert_false(Players.pressed(Players.Seat.DRIVER, "a"))
	_restore_quit()
