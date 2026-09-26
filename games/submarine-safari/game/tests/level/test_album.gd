extends GutTest
## The album: persistence and the album screen.

const AlbumModel := preload("res://scripts/album.gd")
const Save := preload("res://scripts/save.gd")
const AlbumScreen := preload("res://scripts/screens/album.gd")
const Species := preload("res://scripts/level/species.gd")
const PATH := "user://test_album.json"
const DT := 1.0 / 30.0

var _saved_album


func before_each() -> void:
	Save.remove(PATH)
	_saved_album = Game.album
	Players.reset()
	Players.clear_scripted()


func after_each() -> void:
	Save.remove(PATH)
	Game.album = _saved_album
	Game.new_session()
	Players.reset()
	Players.clear_scripted()


func test_album_saves_and_loads_and_survives_corrupt_file() -> void:
	var a := AlbumModel.new(PATH)
	a.load_file()
	assert_false(a.has("clownfish"), "a missing file is an empty album")
	assert_true(a.record("clownfish", 0.6, 1), "new")
	assert_false(a.record("clownfish", 0.9, 0), "repeat")
	a.add_bonus("shell")
	assert_true(a.save())
	var b := AlbumModel.new(PATH)
	b.load_file()
	assert_eq(b.count("clownfish"), 2)
	assert_almost_eq(float(b.data.species.clownfish.best), 0.9, 0.001, "the best photo is kept")
	assert_eq(b.bonus("shell"), 1)
	# Corrupt file: no crash, an empty album, the bad file kept aside.
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	f.store_string("{not json at all")
	f.close()
	var c := AlbumModel.new(PATH)
	c.load_file()
	assert_false(c.has("clownfish"))
	assert_true(FileAccess.file_exists(PATH + ".bad"))
	c.record("turtle")
	assert_true(c.save(), "it saves again after a corrupt file")
	# Wrong shapes and newer versions are refused politely too.
	for text in ["[1, 2, 3]", "{\"version\": 1, \"data\": 5}", "{\"version\": 99, \"data\": {\"species\": {}}}", ""]:
		f = FileAccess.open(PATH, FileAccess.WRITE)
		f.store_string(text)
		f.close()
		var d := AlbumModel.new(PATH)
		d.load_file()
		assert_eq(d.data.species.size(), 0, "safe on %s" % text)


func test_album_never_stores_personal_data() -> void:
	var a := AlbumModel.new(PATH)
	a.record("eel")
	a.add_bonus("bubble")
	a.save()
	var text := FileAccess.get_file_as_string(PATH)
	assert_true(text.contains("eel"))
	var keys: Array = JSON.parse_string(text).data.keys()
	keys.sort()
	assert_eq(keys, ["bonus", "species"])


func _screen(browse := false) -> Node2D:
	Game.album = AlbumModel.new(PATH)
	Game.album.load_file()
	Game.album_browse = browse
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()
	var s := AlbumScreen.new()
	s.auto_goto = false
	add_child_autofree(s)
	s.set_process(false)
	return s


func _step(s, states := {}, n := 1) -> void:
	for i in n:
		for d in states:
			Players.set_scripted(d, states[d])
		Players.poll()
		s.step(DT)


func test_album_screen_slides_in_new_species_then_stars_then_whale() -> void:
	Game.new_session()
	var a := AlbumModel.new(PATH)
	a.record("pufferfish")
	for id in ["clownfish", "crab"]:
		a.record(id)
		Game.session.new.append(id)
	a.record("pufferfish")
	Game.session.repeats["pufferfish"] = 1
	a.record("whale")
	Game.session.whale = true
	a.save()
	var s := _screen()
	assert_false(s.is_shown("clownfish"), "today's species start as silhouettes")
	assert_true(s.is_shown("pufferfish"), "known species are in colour")
	_step(s, {}, 30 * 3)
	assert_eq(s.shown_new, ["clownfish", "crab"] as Array[String], "one by one, in page order")
	_step(s, {}, 30 * 2)
	assert_eq(s.stars_shown.get("pufferfish", 0), 1, "a star for the repeat")
	_step(s, {}, 30 * 3)
	assert_eq(s.spread, 1, "the whale gets the double page")
	_step(s, {"demo:0": {"a": true}})
	assert_eq(s.next_screen, "select", "the driver's a goes back to select")


func test_album_browse_from_join_turns_pages_and_returns_to_join() -> void:
	Game.new_session()
	var a := AlbumModel.new(PATH)
	a.record("whale")
	a.save()
	var s := _screen(true)
	assert_true(s.browse)
	_step(s, {}, 40)
	_step(s, {"demo:1": {"move": Vector2.RIGHT}})
	assert_eq(s.spread, 1, "right turns the page")
	_step(s, {"demo:1": {}})
	_step(s, {"demo:1": {"b": true}})
	assert_eq(s.next_screen, "join")
