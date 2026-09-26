extends GutTest
## Rider select: distinct riders, readiness, the honker's any-press cycling.

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


func test_default_picks_start_with_the_penguin() -> void:
	_open()
	assert_eq(screen.picks[0], "penguin")
	assert_true(_distinct(screen.picks))


func test_select_forbids_duplicate_riders() -> void:
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
	for i in 5:  # held well under the repeat delay
		_step()
	assert_eq(screen.picks[0], after_one, "held stick moves only once at first")
	for i in 12:
		_step()
	assert_ne(screen.picks[0], after_one, "repeats after a short hold")


func test_stale_duplicate_riders_are_repaired() -> void:
	Players.riders = ["fox", "fox", ""]
	_open()
	assert_eq(screen.picks[0], "fox")
	assert_true(_distinct(screen.picks))


func test_all_ready_advances_and_writes_riders() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:1", {"a": true})
	assert_eq(screen.next_screen, "")
	for i in int(3.5 / DT):  # the honker auto-readies when idle
		_step()
	assert_eq(screen.next_screen, "dig")
	assert_eq(Players.riders, screen.picks)
	assert_true(_distinct(Players.riders))


func test_b_unreadies() -> void:
	_open()
	_press("demo:0", {"a": true})
	assert_true(screen.readied[0])
	_press("demo:0", {"b": true})
	assert_false(screen.readied[0])


func test_driver_start_advances_without_everyone_ready() -> void:
	_open()
	_press("demo:1", {"start": true})
	assert_eq(screen.next_screen, "", "only the driver's start")
	_press("demo:0", {"start": true})
	assert_eq(screen.next_screen, "dig")
	assert_eq(Players.riders[0], screen.picks[0])


func test_the_honker_cycles_on_any_press() -> void:
	_open()
	var seen := [screen.picks[2]]
	for i in 2:  # 3 free riders for the honker in the 5-rider roster
		_press("demo:2", {"any": true})
		assert_false(seen.has(screen.picks[2]), "new rider each press")
		seen.append(screen.picks[2])
		assert_true(_distinct(screen.picks))
	_press("demo:2", {"b": true})  # any button, even back
	assert_ne(screen.picks[2], seen[-1])
	assert_false(screen.readied[2])
	for i in int(3.2 / DT):
		_step()
	assert_true(screen.readied[2], "auto-ready after 3 s idle")


func test_driver_b_when_not_ready_goes_back_to_join_keeping_seats() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "", "first b only un-readies")
	assert_false(screen.readied[0])
	_press("demo:1", {"b": true})
	assert_eq(screen.next_screen, "", "the gunner's b does not leave")
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "join")
	assert_eq(Players.seated_count(), 3, "seats are kept")


func test_driver_picks_the_digger_paint_with_up_and_down() -> void:
	Game.digger_skin = 0
	_open()
	_press("demo:0", {"move": Vector2.DOWN})
	assert_eq(Game.digger_skin, 1)
	_press("demo:0", {"move": Vector2.UP})
	_press("demo:0", {"move": Vector2.UP})
	assert_eq(Game.digger_skin, Game.DIGGER_SKINS.size() - 1, "wraps around")
	var before: Array[String] = screen.picks.duplicate()
	_press("demo:1", {"move": Vector2.DOWN})
	assert_eq(Game.digger_skin, Game.DIGGER_SKINS.size() - 1, "only the driver paints")
	assert_eq(screen.picks, before, "up/down never changes riders")
	Game.digger_skin = 0


func test_every_rider_wears_a_helmet_in_its_seat_colour() -> void:
	_open()
	for s in 3:
		var rv = screen._nodes[s].rider
		assert_eq(rv.seat, s)
		assert_eq(rv.helmet.sprite_frames, Art.frames(rv.HELMETS[s], rv.HELMET_TINTS[s], Vector2i(12, 6)))
		assert_lt(rv.helmet.position.y, 0.0, "on top of the head")
