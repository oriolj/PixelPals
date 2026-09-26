extends "res://tests/flight/helpers.gd"
## The party on the Moon: the album page, the fuel count, then back to select.



func _party() -> Node:
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_album_persists_new_planets() -> void:
	assert_eq(Album.load_kinds(TEST_ALBUM), [] as Array[int], "a fresh album")
	assert_true(Game.found_planet(5), "new to the album")
	assert_true(Game.found_planet(2))
	assert_false(Game.found_planet(5), "already in it")
	assert_eq(Album.load_kinds(TEST_ALBUM), [2, 5] as Array[int], "saved at once")
	# The next trip (and the next run of the game) starts from the saved page.
	Game.new_trip()
	Game.album = Album.load_kinds(TEST_ALBUM)
	assert_eq(Game.trip_planets.size(), 0)
	Game.found_planet(7)
	assert_eq(Album.load_kinds(TEST_ALBUM), [2, 5, 7] as Array[int])


func test_album_page_colours_found_planets_and_pops_new_ones() -> void:
	seat(3)
	Game.album.assign([1, 3])
	Game.found_planet(6)
	Game.fuel = 12
	var p := _party()
	assert_true(p.slots[1].node.visible, "old finds are in colour from the start")
	assert_false(p.slots[6].node.visible, "this trip's find pops in a moment later")
	assert_false(p.slots[2].node.visible, "missing planets stay silhouettes")
	assert_true(p.slots[2].sil.visible)
	for i in 60:
		p.step(DT)
	assert_true(p.slots[6].node.visible)
	assert_false(p.slots[6].sil.visible)
	assert_eq(p.digits.value, 12, "the fuel count in pixel digits")
	assert_eq(p.dancers.size(), 3)


func test_party_with_nobody_seated_still_dances() -> void:
	var p := _party()
	assert_eq(p.dancers.size(), 1)
	for i in 30:
		p.step(DT)


func test_goes_to_select_after_the_stay() -> void:
	seat(1)
	var p := _party()
	for i in int(p.STAY_SECONDS / DT) + 10:
		p.step(DT)
	assert_eq(Game.current_name, "select")


func test_pilot_a_skips_after_the_guard() -> void:
	seat(1)
	var p := _party()
	drive("demo:0", {"a": true}, p)
	assert_eq(Game.current_name, "party", "an A held from the landing is ignored")
	drive("demo:0", {}, p)
	run(p, 2.0)
	drive("demo:0", {"a": true}, p)
	assert_eq(Game.current_name, "select")
