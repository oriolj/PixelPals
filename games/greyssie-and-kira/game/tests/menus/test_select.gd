extends GutTest
## Select: the walker picks a character, the kids pick hat colours.

const SelectScreen := preload("res://scripts/screens/select.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for i in 3:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
	Players.poll()
	screen = SelectScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func _step(seat: int, state: Dictionary) -> void:
	Players.set_scripted("demo:%d" % seat, state)
	Players.poll()
	screen._process(DT)


func test_walker_cycles_characters_including_the_private_pack() -> void:
	var first: String = screen.pick
	_step(0, {"move": Vector2(1, 0)})
	_step(0, {})
	assert_ne(screen.pick, first)
	assert_true(Game.roster.size() >= 5)


func test_kids_hats_never_match() -> void:
	for i in 12:
		_step(1, {"move": Vector2(1, 0)})
		_step(1, {})
		assert_ne(screen.hat_pick[1], screen.hat_pick[2])
		_step(2, {"a": true})
		_step(2, {})
		assert_ne(screen.hat_pick[1], screen.hat_pick[2])


func test_all_ready_goes_to_the_house_with_choices_saved() -> void:
	_step(1, {"move": Vector2(1, 0)})
	_step(1, {})
	_step(0, {"a": true})
	_step(0, {})
	_step(1, {"a": true})
	_step(1, {})
	for i in 150:
		_step(2, {})
	assert_eq(screen.next_screen, "house")
	assert_eq(Players.riders[0], screen.pick)
	assert_eq(Game.hats[1], screen.hat_pick[1])


func test_toddler_cannot_go_back() -> void:
	_step(2, {"b": true, "start": true})
	assert_ne(screen.next_screen, "join")
