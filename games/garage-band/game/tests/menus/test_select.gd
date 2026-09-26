extends GutTest
## Select: distinct riders, readiness, the Crasher's any-press cycling, then
## the Lead's song picker.

const SelectScreen := preload("res://scripts/screens/select.gd")
const Songs := preload("res://scripts/music/songs.gd")
const DT := 1.0 / 30.0

var screen: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	for d in ["demo:0", "demo:1", "demo:2"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()
	Game.song_index = 0


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


func test_select_forbids_duplicate_riders() -> void:
	_open()
	assert_eq(screen.picks[0], "penguin")
	for i in Game.roster.size() * 2:
		_press("demo:0", {"move": Vector2.RIGHT})
		_press("demo:1", {"move": Vector2.LEFT})
		var seen := {}
		for p in screen.picks:
			assert_false(seen.has(p), "duplicate %s" % p)
			seen[p] = true


func test_crasher_any_press_cycles_and_auto_readies() -> void:
	_open()
	var before: String = screen.picks[2]
	_press("demo:2", {"a": true})
	assert_ne(screen.picks[2], before)
	assert_false(screen.readied[2])
	for i in int(3.2 / DT):
		_step()
	assert_true(screen.readied[2], "the toddler never blocks the band")


func test_all_ready_goes_to_the_song_picker() -> void:
	_open()
	_press("demo:0", {"a": true})
	_press("demo:1", {"a": true})
	for i in int(4.0 / DT):
		_step()
	assert_eq(screen.phase, "songs")
	assert_eq(Players.riders[0], screen.picks[0])


func test_lead_picks_a_song_and_plays_it() -> void:
	_open()
	_press("demo:0", {"start": true})
	assert_eq(screen.phase, "songs")
	_press("demo:0", {"move": Vector2.RIGHT})
	assert_eq(screen.song, 1)
	_press("demo:0", {"move": Vector2.RIGHT})
	_press("demo:0", {"move": Vector2.RIGHT})
	assert_eq(screen.song, 0, "wraps around the three covers")
	_press("demo:0", {"move": Vector2.LEFT})
	assert_eq(screen.song, Songs.count() - 1)
	# The other seats cannot choose the song.
	_press("demo:1", {"move": Vector2.RIGHT, "a": true})
	_press("demo:2", {"a": true, "start": true})
	assert_eq(screen.next_screen, "")
	_press("demo:0", {"a": true})
	assert_eq(screen.next_screen, "play")
	assert_eq(Game.song_index, Songs.count() - 1)


func test_lead_b_in_the_picker_goes_back_to_riders() -> void:
	_open()
	_press("demo:0", {"start": true})
	_press("demo:0", {"b": true})
	assert_eq(screen.phase, "riders")
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "join")
