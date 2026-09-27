extends "res://tests/helpers.gd"
## The show screen end to end and the party's wall.


func test_show_screen_finishes_and_awards_everyone() -> void:
	seat(3)
	var sh := open("show")
	var took := run_until(sh, func(): return sh.next_screen != "", 150.0, {"demo:2": {"a": true}})
	assert_lt(took, 150.0)
	assert_eq(sh.next_screen, "party")
	assert_eq(Game.day.rosettes.size(), 5, "mare, foal and three riders")


func test_party_pins_the_day_once() -> void:
	seat(2)
	Game.wall.reset()
	Game.day.rosettes = [{"who": "mare", "colour": "blue"}, {"who": "foal", "colour": "red"}]
	Game.day.lucky = 2
	var p := open("party")
	assert_eq(Game.wall.day_count(), 1)
	assert_eq(Game.wall.horseshoes(), 2)
	p.record_day()
	assert_eq(Game.wall.day_count(), 1, "the same day is pinned once")
	var t := run_until(p, func(): return p.next_screen != "", 20.0)
	assert_almost_eq(t, 14.0, 0.2)
	Game.wall.reset()
