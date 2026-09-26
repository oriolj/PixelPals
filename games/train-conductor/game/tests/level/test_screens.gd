extends GutTest
## The level and party screens as a whole: they build, pause, end and move on.

const LevelScreen := preload("res://scripts/screens/level.gd")
const PartyScreen := preload("res://scripts/screens/party.gd")
const DT := 1.0 / 30.0


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.riders = ["penguin", "monkey", "fox"]
	Game.level_setup = {}
	Game.seed_value = 11
	Game.run_seconds = 360.0
	Players.poll()


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.level_setup = {}
	Game.seed_value = 0


func _level() -> Node2D:
	var s: Node2D = LevelScreen.new()
	s.auto_goto = false
	add_child_autofree(s)
	s.set_process(false)
	return s


func _press(screen: Node2D, d: String, button: String) -> void:
	Players.set_scripted(d, {button: true})
	Players.poll()
	screen._process(DT)
	Players.set_scripted(d, {})
	Players.poll()
	screen._process(DT)


func test_level_builds_with_every_view() -> void:
	var s := _level()
	for n in ["ground", "track_view", "stations", "points", "animals", "train_view", "people", "cover", "fx", "glow", "hud"]:
		assert_not_null(s.get(n), n)
	assert_false(s.sim.solo, "a points seat is here")
	assert_false(s.sim.auto_whistle, "a whistle seat is here")
	for i in 30:
		s._process(DT)
	assert_eq(s.next_screen, "")


func test_missing_seats_are_covered() -> void:
	Players.leave(Players.Seat.GUNNER)
	Players.leave(Players.Seat.HONKER)
	var s := _level()
	assert_true(s.sim.solo, "tour rule + automatic doors")
	assert_true(s.sim.auto_whistle, "the whistle toots by itself")


func test_driver_pauses_and_back_goes_to_join() -> void:
	var s := _level()
	_press(s, "demo:1", "start")
	assert_false(s.paused, "only the driver pauses")
	_press(s, "demo:0", "start")
	assert_true(s.paused)
	var t: float = s.sim.time
	for i in 10:
		s._process(DT)
	assert_eq(s.sim.time, t, "the run is frozen")
	_press(s, "demo:0", "b")
	assert_eq(s.next_screen, "join")


func test_the_finale_goes_to_the_party_with_the_results() -> void:
	Game.level_setup = {"deliveries": 11, "time_left": 1.0}
	var s := _level()
	var t := 0.0
	while s.next_screen == "" and t < 20.0:
		s._process(DT)
		t += DT
	assert_eq(s.next_screen, "party")
	assert_gt(s.night, 0.9, "night fell")
	assert_eq(Game.deliveries.size(), 11)
	assert_eq(Game.stars, 11 + s.sim.perfect_stops)


func test_party_returns_to_select() -> void:
	Game.deliveries.assign([0, 1, 2, 3, 3])
	Game.stars = 6
	var p: Node2D = PartyScreen.new()
	p.auto_goto = false
	add_child_autofree(p)
	p.set_process(false)
	var t := 0.0
	while p.next_screen == "" and t < 14.0:
		p.step(DT)
		t += DT
	assert_eq(p.next_screen, "select")
	assert_eq(p.stars_shown, 6, "one star per delivery and perfect stop")
	assert_eq(p.per_colour, [1, 1, 1, 2] as Array[int])
