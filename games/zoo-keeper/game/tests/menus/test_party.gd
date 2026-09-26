extends GutTest
## The party screen: each animal sings in turn, stars rain, then back to select.

const Rules := preload("res://scripts/zoo/rules.gd")
const PartyScreen := preload("res://scripts/screens/party.gd")
const DT := 1.0 / 30.0

var p: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()


func after_each() -> void:
	Game.stars = 0
	Players.reset()
	Players.clear_scripted()


func _party(stars: int) -> void:
	Game.stars = stars
	p = PartyScreen.new()
	p.auto_goto = false
	add_child_autofree(p)
	p.set_process(false)


func test_every_animal_is_on_stage_and_sings_in_turn() -> void:
	_party(12)
	assert_eq(p.dancers.size(), 6)
	var turns := {}
	for i in int(p.end_time() / DT) - 2:
		p.step(DT)
		if p.turn >= 0:
			turns[p.turn] = true
	assert_eq(turns.size(), Rules.ANIMALS.size(), "each animal had its turn")


func test_the_bucket_stars_rain_down() -> void:
	_party(12)
	for i in int(6.0 / DT):
		p.step(DT)
	assert_eq(p.stars_dropped, 12)


func test_zero_stars_still_rains_a_few() -> void:
	_party(0)
	for i in int(6.0 / DT):
		p.step(DT)
	assert_eq(p.stars_dropped, 3)


func test_goes_to_select_after_the_last_song() -> void:
	_party(5)
	for i in int((p.end_time() + 0.2) / DT):
		p.step(DT)
	assert_eq(p.next_screen, "select")


func test_keeper_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	_party(5)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(p.next_screen, "", "an a held from the zoo is ignored")
	Players.set_scripted("demo:0", {})
	for i in 50:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(p.next_screen, "select")
