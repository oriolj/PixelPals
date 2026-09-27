extends GutTest
## "Who is here" bubbles: hot-plug in and out, keyboard blocks on first use.

const Bubbles := preload("res://scripts/bubbles.gd")


func test_a_plugged_pad_gets_a_bubble_and_an_unplugged_one_pops_out() -> void:
	var b := Bubbles.new()
	add_child_autofree(b)
	b._on_joy(7, true)
	assert_true(b.devices.has("pad:7"))
	b._on_joy(7, false)
	assert_true(b.devices["pad:7"].gone)
	for i in 30:
		b._process(0.05)
	assert_false(b.devices.has("pad:7"), "gone after the pop-out")


func test_keyboard_blocks_appear_when_used_and_demo_devices_never() -> void:
	var b := Bubbles.new()
	add_child_autofree(b)
	b.ping("kb:1")
	b.ping("demo:0")
	assert_true(b.devices.has("kb:1"))
	assert_false(b.devices.has("demo:0"))
	assert_gt(b.devices["kb:1"].hop, 0.0, "it hops")


func test_each_device_gets_its_own_colour() -> void:
	var b := Bubbles.new()
	add_child_autofree(b)
	b.add_device("pad:1")
	b.add_device("pad:2")
	assert_ne(b.devices["pad:1"].color, b.devices["pad:2"].color)
