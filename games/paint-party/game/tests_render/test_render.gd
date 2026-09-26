extends GutTest
## Pixel tests: need a real renderer (make test-render runs them under xvfb).

const Painter := preload("res://scripts/paint/painter.gd")
const PaintScreen := preload("res://scripts/screens/paint.gd")
const Palette := preload("res://scripts/paint/palette.gd")

var dir := ""
var _saved := {}


func before_each() -> void:
	dir = OS.get_temp_dir().path_join("paint-party-render-%d" % Time.get_ticks_usec())
	_saved = {"dir": Game.paint_dir, "pics": Game.pictures_dir, "shot": Game.shot_dir}
	Game.paint_dir = dir
	Game.pictures_dir = dir.path_join("Pictures")
	Game.shot_dir = ""
	Players.reset()
	Players.clear_scripted()


func after_each() -> void:
	Game.paint_dir = _saved.dir
	Game.pictures_dir = _saved.pics
	Game.shot_dir = _saved.shot
	Game.last_painting = null
	Game.last_painting_path = ""
	Players.reset()
	Players.clear_scripted()
	_rm(dir)


func _rm(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_rm(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func _frames(n := 3) -> void:
	for i in n:
		await get_tree().process_frame


func _near(a: Color, b: Color, tol := 0.06) -> bool:
	return absf(a.r - b.r) < tol and absf(a.g - b.g) < tol and absf(a.b - b.b) < tol


func test_renderer_is_real() -> void:
	assert_true(Painter.can_read_back(), "run with make test-render (xvfb), not --headless")


func test_saved_png_is_1920x1080_and_not_blank() -> void:
	var p := Painter.new()
	add_child_autofree(p)
	await _frames()
	for i in 40:
		p.add_dab(Vector2(200 + i * 20, 300), 20, Palette.COLORS[1])
	p.add_stamp("sun", Vector2(1500, 700), Palette.COLORS[2])
	await _frames()
	var path := dir.path_join("paint-test.png")
	assert_not_null(p.save_png(path))
	assert_true(FileAccess.file_exists(path))
	var img := Game.load_png(path)
	assert_eq(img.get_size(), Vector2i(1920, 1080))
	assert_true(_near(img.get_pixel(5, 5), Palette.PAPER), "paper in the corner: %s" % img.get_pixel(5, 5))
	assert_true(_near(img.get_pixel(600, 300), Palette.COLORS[1]), "the stroke: %s" % img.get_pixel(600, 300))
	assert_true(_near(img.get_pixel(1500, 700), Palette.COLORS[2]), "the sun: %s" % img.get_pixel(1500, 700))
	# not blank: many distinct colours
	var cols := {}
	for y in range(0, 1080, 20):
		for x in range(0, 1920, 20):
			cols[img.get_pixel(x, y).to_html()] = true
	assert_gt(cols.size(), 3)


func test_undo_restores_the_previous_pixels() -> void:
	var p := Painter.new()
	add_child_autofree(p)
	await _frames()
	p.add_dab(Vector2(300, 300), 40, Palette.COLORS[0])
	await _frames()
	var before := p.snapshot()
	p.add_stamp("star", Vector2(310, 300), Palette.COLORS[1])
	p.add_dab(Vector2(1000, 800), 60, Palette.COLORS[3])
	await _frames()
	var during := p.snapshot()
	assert_false(_near(during.get_pixel(1000, 800), Palette.PAPER), "painted over")
	p.restore(before)
	await _frames()
	var after := p.snapshot()
	for pt in [Vector2i(300, 300), Vector2i(310, 260), Vector2i(1000, 800), Vector2i(5, 5), Vector2i(1919, 1079)]:
		assert_true(_near(after.get_pixel(pt.x, pt.y), before.get_pixel(pt.x, pt.y), 0.01), "pixel %s restored" % pt)


func test_stamp_lands_at_the_brush_position() -> void:
	for d in ["demo:0", "demo:1"]:
		Players.set_scripted(d, {})
		Players.join(d)
	Players.poll()
	var s: Node2D = PaintScreen.new()
	s.auto_goto = false
	add_child_autofree(s)
	s.set_process(false)
	await _frames()
	s.brush = Vector2(1400, 300)   # top right: catches a flipped readback too
	s.pick_colour(1)
	s.stamp()   # a star in colour 1
	await _frames()
	var img: Image = s.painter.snapshot()
	assert_true(_near(img.get_pixel(1400, 300), Palette.COLORS[1]), "star centre at the brush: %s" % img.get_pixel(1400, 300))
	assert_true(_near(img.get_pixel(1400, 1080 - 300), Palette.PAPER), "nothing at the mirrored spot")
	assert_true(_near(img.get_pixel(500, 300), Palette.PAPER), "nothing elsewhere")


func test_frame_it_saves_to_paint_dir_and_pictures() -> void:
	Players.set_scripted("demo:0", {})
	Players.join("demo:0")
	Players.poll()
	var s: Node2D = PaintScreen.new()
	s.auto_goto = false
	add_child_autofree(s)
	s.set_process(false)
	await _frames()
	s.stamp()
	await _frames()
	s.frame_it()
	assert_not_null(Game.last_painting)
	assert_true(FileAccess.file_exists(s.final_path()))
	assert_true(FileAccess.file_exists(Game.pictures_dir.path_join(s.final_path().get_file())), "copy in Pictures")
	assert_eq(Game.gallery(3).size(), 1)
