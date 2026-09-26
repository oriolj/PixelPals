extends GutTest
## The gallery: the new picture in the middle, the previous two beside it.

const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node
var _saved_dir := ""
var dir := ""


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	_saved_root = Game._root
	_saved_dir = Game.paint_dir
	dir = OS.get_temp_dir().path_join("paint-party-gallery-%d" % Time.get_ticks_usec())
	DirAccess.make_dir_recursive_absolute(dir)
	Game.paint_dir = dir
	Game.last_painting = null
	Game.last_painting_path = ""
	root = Node2D.new()
	add_child(root)
	Game._root = root
	Game.current = null


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.paint_dir = _saved_dir
	Game.last_painting = null
	Game.last_painting_path = ""
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir.path_join(f))
	DirAccess.remove_absolute(dir)
	Players.reset()
	Players.clear_scripted()


func _png(name: String, col: Color) -> void:
	var img := Image.create(64, 36, false, Image.FORMAT_RGB8)
	img.fill(col)
	img.save_png(dir.path_join(name))


func _party() -> Node:
	Game.goto("party")
	var p: Node = Game.current
	p.set_process(false)
	return p


func test_gallery_is_newest_first_and_ignores_autosaves() -> void:
	_png("paint-20260101-100000.png", Color.RED)
	_png("paint-20260102-100000.png", Color.GREEN)
	_png("paint-20260103-100000.png", Color.BLUE)
	_png("paint-20251231-100000.png", Color.WHITE)
	_png("wip-20260104-100000.png", Color.BLACK)
	var g := Game.gallery(3)
	assert_eq(g.size(), 3)
	assert_string_ends_with(g[0], "paint-20260103-100000.png")
	assert_string_ends_with(g[2], "paint-20260101-100000.png")


func test_party_hangs_the_new_picture_and_the_previous_two() -> void:
	_png("paint-20260101-100000.png", Color.RED)
	_png("paint-20260102-100000.png", Color.GREEN)
	_png("paint-20260103-100000.png", Color.BLUE)
	Game.last_painting_path = dir.path_join("paint-20260103-100000.png")
	var p := _party()
	for i in 3:
		assert_not_null(p.pictures[i], "picture %d" % i)


func test_empty_gallery_is_fine() -> void:
	var p := _party()
	for i in 30:
		p.step(DT)
	assert_null(p.pictures[0])
	assert_eq(p.riders.size(), 3, "the roster dances when nobody is seated")


func test_goes_to_select_after_the_stay() -> void:
	var p := _party()
	p.auto_goto = false
	for i in int(11.5 / DT):
		p.step(DT)
	assert_eq(p.next_screen, "", "still partying at 11.5 s")
	for i in int(1.0 / DT):
		p.step(DT)
	assert_eq(p.next_screen, "select")


func test_brush_a_skips_after_the_guard() -> void:
	Players.join("demo:0")
	var p := _party()
	p.auto_goto = false
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(p.next_screen, "", "an a still held from the paint screen is ignored")
	Players.set_scripted("demo:0", {})
	for i in 50:
		Players.poll()
		p.step(DT)
	Players.set_scripted("demo:0", {"a": true})
	Players.poll()
	p.step(DT)
	assert_eq(p.next_screen, "select")
