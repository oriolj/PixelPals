extends GutTest
## Select: distinct riders, the coats, readiness, the NEIGH seat's any-press cycling.

const SelectScreen := preload("res://scripts/screens/select.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Game.start_stage = 0
	Game.mare_coat = "bay"
	Game.foal_coat = "palomino"
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.mare_coat = "bay"
	Game.foal_coat = "palomino"


func _open() -> void:
	screen = SelectScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	screen.step(DT)


func _press(d: String, state: Dictionary) -> void:
	_step({d: state})
	_step({d: {}})


func test_default_picks_and_coats() -> void:
	_open()
	assert_eq(screen.picks[0], "penguin")
	assert_eq(Game.MARE_COATS[screen.mare_coat], "bay", "the default mare is a bay")
	assert_eq(Game.FOAL_COATS[screen.foal_coat], "palomino", "the default foal is a palomino")
	assert_eq(Game.MARE_COATS.size(), 6)
	assert_eq(Game.FOAL_COATS.size(), 7)


func test_select_forbids_duplicate_riders() -> void:
	_open()
	for i in 12:
		_press("demo:1", {"move": Vector2(1, 0)})
		assert_ne(screen.picks[1], screen.picks[0])
		assert_ne(screen.picks[1], screen.picks[2])


func test_up_down_picks_each_horse_coat() -> void:
	_open()
	_press("demo:0", {"move": Vector2(0, 1)})
	assert_eq(Game.mare_coat, "chestnut")
	_press("demo:0", {"move": Vector2(0, -1)})
	_press("demo:0", {"move": Vector2(0, -1)})
	assert_eq(Game.mare_coat, "pinto", "it wraps around")
	_press("demo:1", {"move": Vector2(0, -1)})
	assert_eq(Game.foal_coat, "chestnut", "the foal seat moves the foal's coat")
	_press("demo:2", {"move": Vector2(0, 1)})
	assert_eq(Game.mare_coat, "pinto", "the NEIGH seat never changes a coat")


func test_all_ready_advances_and_writes_riders() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:1", {"a": true})
	for i in int(5.0 / DT):
		_step({})
		if screen.next_screen != "":
			break
	assert_eq(screen.next_screen, "stable")
	assert_eq(Players.riders[0], screen.picks[0])


func test_the_neigh_seat_cycles_on_any_press() -> void:
	_open()
	var first: String = screen.picks[2]
	_press("demo:2", {"a": true})
	assert_ne(screen.picks[2], first)


func test_rider_b_when_not_ready_goes_back_to_join_keeping_seats() -> void:
	_open()
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "join")
	assert_eq(Players.seated_count(), 3)
