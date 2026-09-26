extends GutTest
## The paint screen driven by scripted seats (headless: the painter queues
## ops but renders nothing, so these check the rules, not the pixels).

const PaintScreen := preload("res://scripts/screens/paint.gd")
const Palette := preload("res://scripts/paint/palette.gd")
const DT := 1.0 / 30.0
const DEVS: Array[String] = ["demo:0", "demo:1", "demo:2"]

var screen: Node2D
var _saved := {}


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	_saved = {"dir": Game.paint_dir, "pics": Game.pictures_dir, "shot": Game.shot_dir, "surprise": Game.surprise_splats}
	Game.paint_dir = OS.get_temp_dir().path_join("paint-party-test-%d" % Time.get_ticks_usec())
	Game.pictures_dir = ""
	Game.shot_dir = ""
	Game.surprise_splats = false


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.paint_dir = _saved.dir
	Game.pictures_dir = _saved.pics
	Game.shot_dir = _saved.shot
	Game.surprise_splats = _saved.surprise


func _open(seats: int) -> void:
	for i in seats:
		Players.set_scripted(DEVS[i], {})
		Players.join(DEVS[i])
	Players.poll()
	screen = PaintScreen.new()
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


func test_dir4_just_pressed_picks_each_pot() -> void:
	_open(3)
	var dirs := [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]
	for i in 4:
		_press("demo:1", {"move": dirs[i]})
		assert_eq(screen.pot, i)
		assert_eq(screen.colour(), Palette.color(0, i))
	# holding a direction picks once
	_step({"demo:1": {"move": Vector2.UP}})
	assert_eq(screen.pot, 0)
	for i in 10:
		_step()
	assert_eq(screen.pot, 0)


func test_palette_page_cycles_three_pages() -> void:
	_open(2)
	_press("demo:1", {"move": Vector2.RIGHT})
	var seen := []
	for i in 4:
		seen.append(screen.page)
		assert_eq(screen.colour(), Palette.color(screen.page, 1), "same pot, the page's colour")
		_press("demo:1", {"b": true})
	assert_eq(seen, [0, 1, 2, 0])


func test_brush_paints_while_held_and_cycles_sizes() -> void:
	_open(2)
	_step({"demo:0": {"a": true}})
	for i in 10:
		_step({"demo:0": {"a": true, "move": Vector2.RIGHT}})
	assert_gt(screen.stats.dabs, 20)
	assert_true(screen.stroke.active)
	_step({"demo:0": {}})
	assert_false(screen.stroke.active)
	assert_eq(screen.undo.size(), 1, "one stroke = one undo step")
	var sizes := []
	for i in 3:
		_press("demo:0", {"b": true})
		sizes.append(screen.size_idx)
	assert_eq(sizes, [2, 0, 1])


func test_colourist_stamps_the_next_shape_at_the_brush() -> void:
	_open(2)
	var ops_before: int = screen.painter.ops.size()
	_press("demo:1", {"a": true})
	_press("demo:1", {"a": true})
	assert_eq(screen.stats.stamps, 2)
	assert_eq(screen.stamp_idx, 2)
	assert_eq(screen.next_stamp(), "flower", "star, heart, then flower")


func test_splatter_splats_and_giggles() -> void:
	_open(3)
	_press("demo:2", {"any": true})
	assert_eq(screen.stats.splats, 1)
	_press("demo:2", {"b": true})  # any button, 2 frames later: cooling down
	assert_eq(screen.stats.splats, 1)
	assert_eq(screen.stats.giggles, 1)
	for i in 20:
		_step()
	_press("demo:2", {"start": true})
	assert_eq(screen.stats.splats, 2, "even start is just a splat for the toddler")
	assert_false(screen.paused)


func test_kids_have_no_undo() -> void:
	_open(3)
	_press("demo:1", {"a": true})
	for i in 20:
		_step()
	_press("demo:2", {"a": true})
	var steps: int = screen.undo.size()
	assert_eq(steps, 2)
	# The kids mash every button, including start and b.
	for i in 60:
		var st := {"a": i % 2 == 0, "b": i % 3 == 0, "start": i % 4 == 0, "move": [Vector2.UP, Vector2.LEFT][i % 2]}
		_step({"demo:1": st, "demo:2": st})
		assert_false(screen.paused, "only the Brush opens the menu")
	assert_gte(screen.undo.size(), steps, "nothing the kids press undoes")
	assert_eq(screen.stats.undos, 0)
	# The Brush can.
	_press("demo:0", {"start": true})
	assert_true(screen.paused)
	screen.menu_sel = screen.menu_items.find("undo")
	var before: int = screen.undo.size()
	_press("demo:0", {"a": true})
	assert_eq(screen.undo.size(), before - 1)
	assert_eq(screen.stats.undos, 1)
	assert_true(screen.paused, "undo keeps the menu open for another")


func test_one_seat_tap_stamps_and_hold_paints() -> void:
	_open(1)
	assert_true(screen.tap_mode())
	# a quick tap (3 frames = 0.1 s) without moving: a stamp, no paint
	_step({"demo:0": {"a": true}})
	_step({"demo:0": {"a": true}})
	_step({"demo:0": {}})
	assert_eq(screen.stats.stamps, 1)
	assert_eq(screen.stats.dabs, 0)
	# holding still past 0.2 s paints
	for i in 10:
		_step({"demo:0": {"a": true}})
	assert_true(screen.stroke.active)
	_step({"demo:0": {}})
	assert_eq(screen.stats.stamps, 1, "a hold is not a stamp")
	assert_gt(screen.stats.dabs, 0)
	# a short press while moving paints too
	var dabs: int = screen.stats.dabs
	_step({"demo:0": {"a": true, "move": Vector2.RIGHT}})
	_step({"demo:0": {"a": true, "move": Vector2.RIGHT}})
	_step({"demo:0": {}})
	assert_eq(screen.stats.stamps, 1)
	assert_gt(screen.stats.dabs, dabs)


func test_one_seat_brush_picks_colours() -> void:
	_open(1)
	var seen := {}
	for i in 12:
		seen[screen.colour().to_html()] = true
		_press("demo:0", {"b": true})
		assert_eq(screen.size_idx, 1, "the size stays medium")
	assert_eq(seen.size(), 12, "b walks through all 12 colours")
	assert_eq(screen.colour_idx, 0, "and wraps around")
	assert_eq(screen.colour(), Palette.color(screen.page, screen.pot), "the pot display follows")


func test_two_seats_have_no_splats_unless_surprise_is_on() -> void:
	_open(2)
	for i in int(25.0 / DT):
		_step()
	assert_eq(screen.stats.splats, 0)
	_press("demo:0", {"start": true})
	assert_true(screen.menu_items.has("splats"))
	screen.menu_sel = screen.menu_items.find("splats")
	_press("demo:0", {"a": true})
	assert_true(Game.surprise_splats)
	_press("demo:0", {"start": true})
	assert_false(screen.paused)
	for i in int(41.0 / DT):
		_step()
	assert_eq(screen.stats.splats, 2, "a surprise splat every 20 s")


func test_splats_toggle_is_hidden_with_a_splatter() -> void:
	_open(3)
	_press("demo:0", {"start": true})
	assert_false(screen.menu_items.has("splats"))


func test_menu_frame_it_goes_to_the_party() -> void:
	_open(3)
	_press("demo:0", {"start": true})
	assert_eq(screen.menu_items[screen.menu_sel], "play", "opens on keep painting")
	_press("demo:0", {"move": Vector2.LEFT})
	assert_eq(screen.menu_items[screen.menu_sel], "frame")
	_press("demo:0", {"a": true})
	assert_gte(screen.framing, 0.0)
	for i in int(4.0 / DT):
		_step()
	assert_eq(screen.next_screen, "party")


func test_menu_b_goes_back_to_join() -> void:
	_open(2)
	_press("demo:0", {"start": true})
	_press("demo:0", {"b": true})
	assert_eq(screen.next_screen, "join")


func test_autosave_clock_runs_while_painting() -> void:
	_open(1)
	_step({"demo:0": {"a": true, "move": Vector2.RIGHT}})
	_step({"demo:0": {}})
	assert_true(screen.autosave.dirty)
	for i in int(31.0 / DT):
		_step()
	assert_false(screen.autosave.dirty, "the 30 s save happened (headless it writes nothing)")
