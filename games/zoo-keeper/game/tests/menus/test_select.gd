extends GutTest
## Buddy select: distinct buddies, hat colours, readiness, the singer's any-press cycling.

const SelectScreen := preload("res://scripts/screens/select.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()
	Game.hats.assign([1, 0, 4])


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()


func _open() -> void:
	screen = SelectScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)


func _step(states := {}) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	Players.poll()
	screen._process(DT)


func _press(d: String, state: Dictionary) -> void:
	_step({d: state})
	_step({d: {}})


func _distinct(picks: Array) -> bool:
	var seen := {}
	for p in picks:
		if p != "" and seen.has(p):
			return false
		seen[p] = true
	return true


func test_default_picks_are_distinct_zoo_animals() -> void:
	_open()
	assert_eq(screen.picks, ["monkey", "penguin", "elephant"] as Array[String])
	for p in screen.picks:
		assert_true(Game.roster.has(p))


func test_select_forbids_duplicate_buddies() -> void:
	_open()
	for i in Game.roster.size() * 2:
		_press("demo:0", {"move": Vector2.RIGHT})
		assert_true(_distinct(screen.picks), "after flick %d: %s" % [i, screen.picks])
		_press("demo:1", {"move": Vector2.LEFT})
		assert_true(_distinct(screen.picks), "after flick %d: %s" % [i, screen.picks])


func test_flick_moves_once_then_repeats_after_a_hold() -> void:
	_open()
	var start: String = screen.picks[0]
	_step({"demo:0": {"move": Vector2.RIGHT}})
	var after_one: String = screen.picks[0]
	assert_ne(after_one, start)
	for i in 5:
		_step()
	assert_eq(screen.picks[0], after_one, "held stick moves only once at first")
	for i in 12:
		_step()
	assert_ne(screen.picks[0], after_one, "repeats after a short hold")


func test_up_down_cycles_the_hat_colour() -> void:
	_open()
	var h: int = Game.hats[0]
	_press("demo:0", {"move": Vector2.DOWN})
	assert_eq(Game.hats[0], (h + 1) % Game.HATS.size())
	_press("demo:0", {"move": Vector2.UP})
	_press("demo:0", {"move": Vector2.UP})
	assert_eq(Game.hats[0], posmod(h - 1, Game.HATS.size()))
	assert_eq(Game.hat_color(0), Game.HATS[Game.hats[0]])


func test_all_ready_advances_to_the_zoo_and_writes_buddies() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:1", {"a": true})
	assert_eq(screen.next_screen, "")
	for i in int(3.5 / DT):
		_step()
	assert_eq(screen.next_screen, "zoo")
	assert_eq(Players.riders, screen.picks)
	assert_true(_distinct(Players.riders))


func test_b_unreadies() -> void:
	_open()
	_press("demo:0", {"a": true})
	assert_true(screen.readied[0])
	_press("demo:0", {"b": true})
	assert_false(screen.readied[0])


func test_keeper_start_advances_without_everyone_ready() -> void:
	_open()
	_press("demo:1", {"start": true})
	assert_eq(screen.next_screen, "", "only the keeper's start")
	_press("demo:0", {"start": true})
	assert_eq(screen.next_screen, "zoo")


func test_the_singer_cycles_on_any_press() -> void:
	_open()
	var seen := [screen.picks[2]]
	for i in 3:
		_press("demo:2", {"any": true})
		assert_false(seen.has(screen.picks[2]), "new buddy each press")
		seen.append(screen.picks[2])
		assert_true(_distinct(screen.picks))
	assert_false(screen.readied[2])
	for i in int(3.2 / DT):
		_step()
	assert_true(screen.readied[2], "auto-ready after 3 s idle")


func test_keeper_b_when_not_ready_goes_back_to_join_keeping_seats() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "", "first b only un-readies")
	_press("demo:1", {"b": true})
	assert_eq(screen.next_screen, "", "the feeder's b does not leave")
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "join")
	assert_eq(Players.seated_count(), 3, "seats are kept")
