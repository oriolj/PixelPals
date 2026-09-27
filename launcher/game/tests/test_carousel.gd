extends GutTest
## Navigation: wrap-around both ways, offsets, restoring a selection.

const Carousel := preload("res://scripts/carousel.gd")


func test_right_from_the_last_card_wraps_to_the_first() -> void:
	var c := Carousel.new(4)
	c.select(3)
	assert_eq(c.step(1), 0)


func test_left_from_the_first_card_wraps_to_the_last() -> void:
	var c := Carousel.new(4)
	assert_eq(c.step(-1), 3)
	assert_eq(c.step(-1), 2)


func test_many_steps_stay_in_range() -> void:
	var c := Carousel.new(5)
	for i in 23:
		c.step(1)
	assert_eq(c.index(), 23 % 5)


func test_offsets_wrap_around_the_selection() -> void:
	var c := Carousel.new(6)
	c.select(0)
	assert_eq(c.offset(0), 0.0)
	assert_eq(c.offset(1), 1.0)
	assert_eq(c.offset(5), -1.0, "the last card sits left of the first")


func test_scroll_eases_to_the_target() -> void:
	var c := Carousel.new(6)
	c.step(1)
	c.update(0.016)
	assert_between(c.scroll, 0.01, 0.99, "moving")
	for i in 120:
		c.update(0.016)
	assert_eq(c.scroll, c.target, "arrived")


func test_empty_carousel_is_safe() -> void:
	var c := Carousel.new(0)
	assert_eq(c.step(1), 0)
	assert_eq(c.offset(3), 0.0)
