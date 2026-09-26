extends GutTest
## Select: cycling, ready, toddler auto-ready, advance to play.

const SelectScreen := preload("res://scripts/screens/select.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.join(d)
	Players.poll()
	screen = SelectScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	screen._process(DT)


func test_distinct_default_picks() -> void:
	assert_eq(screen.picks[0], "penguin")
	assert_ne(screen.picks[1], screen.picks[0])
	assert_ne(screen.picks[2], screen.picks[1])


func test_cycle_skips_taken_riders() -> void:
	var before: String = screen.picks[0]
	_step({"demo:0": {"move": Vector2.RIGHT}})
	_step({"demo:0": {}})
	assert_ne(screen.picks[0], before)
	assert_ne(screen.picks[0], screen.picks[1])


func test_everyone_ready_goes_to_play() -> void:
	_step({"demo:0": {"a": true}, "demo:1": {"a": true}})
	_step({"demo:0": {}, "demo:1": {}})
	for i in 150:
		_step()
		if screen.next_screen != "":
			break
	assert_eq(screen.next_screen, "play", "the toddler auto-readies, then play")
	assert_eq(Players.riders[0], screen.picks[0])


func test_builder_b_goes_back_to_join() -> void:
	_step({"demo:0": {"b": true}})
	assert_eq(screen.next_screen, "join")
