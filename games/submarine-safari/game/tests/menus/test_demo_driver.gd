extends GutTest
## Demo driver: scripted input for all three seats, and the level demo finds
## at least 8 species in 60 seconds (the M1 check).

const DemoDriver := preload("res://scripts/demo_driver.gd")
const LevelScreen := preload("res://scripts/screens/level.gd")
const AlbumModel := preload("res://scripts/album.gd")
const DT := 1.0 / 30.0

var dd: Node
var _saved_album


func before_each() -> void:
	_saved_album = Game.album
	Game.album = AlbumModel.new("user://test_album_demo.json")
	Game.album.reset()
	Players.reset()
	Players.clear_scripted()
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Game.album.reset()
	Game.album = _saved_album
	Game.new_session()
	Game.run_seconds = 0.0
	Players.reset()
	Players.clear_scripted()


func test_level_start_seats_three_with_riders() -> void:
	dd.start("level")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])
	assert_eq(Game.run_seconds, 75.0)


func test_album_start_seeds_a_run() -> void:
	dd.start("album")
	assert_gt(Game.session.new.size(), 5)
	assert_true(Game.session.whale)
	assert_true(Game.album.has("whale"))


func test_demo_finds_at_least_eight_species_in_sixty_seconds() -> void:
	dd.start("level")
	var level = LevelScreen.new()
	add_child_autofree(level)
	level.set_process(false)
	var t := 0.0
	for i in 60 * 30:
		t += DT
		var st: Array[Dictionary] = [{}, {}, {}]
		dd._drive_level(level, st, t, DT)
		for k in 3:
			Players.set_scripted(dd.DEVICES[k], st[k])
		Players.poll()
		level.step(DT)
	gut.p("demo found %d species: %s (bumps %d)" % [Game.session.seen.size(), Game.session.seen, level.bumps])
	assert_gte(Game.session.seen.size(), 8)
