extends GutTest
## Fires: one size per spray interval, out at zero; alone they only grow to 3.

const FireState := preload("res://scripts/level/fire_state.gd")


func test_fire_shrinks_one_size_per_spray_interval_and_goes_out() -> void:
	var f := FireState.new()
	f.activate()
	assert_eq(f.size, 2)
	assert_eq(f.step(FireState.SPRAY_INTERVAL - 0.1, 1.0), "")
	assert_eq(f.size, 2, "not yet")
	assert_eq(f.step(0.2, 1.0), "shrink")
	assert_eq(f.size, 1)
	var ev := ""
	for i in 20:
		ev = f.step(0.1, 1.0)
		if ev != "":
			break
	assert_eq(ev, "out")
	assert_true(f.out)
	assert_false(f.lit())
	assert_eq(f.step(5.0, 1.0), "", "an out fire stays out")


func test_unattended_fire_caps_at_size_three() -> void:
	var f := FireState.new()
	f.activate()
	var grew := 0
	for i in 300:
		if f.step(1.0, 0.0) == "grow":
			grew += 1
	assert_eq(f.size, FireState.MAX_SIZE)
	assert_eq(grew, 1, "grew once, to 3, then stopped")
	assert_true(f.lit(), "never burns itself out or spreads")


func test_water_resets_growth() -> void:
	var f := FireState.new()
	f.activate()
	f.step(FireState.GROW_EVERY - 1.0, 0.0)
	f.step(0.1, 1.0)
	f.step(2.0, 0.0)
	assert_eq(f.size, 2, "a little water pauses the growing")


func test_fizzle_puts_out_without_a_fuss() -> void:
	var f := FireState.new()
	f.activate()
	f.fizzle()
	assert_true(f.out)
