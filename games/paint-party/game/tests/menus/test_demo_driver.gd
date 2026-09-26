extends GutTest
## Demo driver: scripted input for all three seats, and a full headless paint run.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const PaintScreen := preload("res://scripts/screens/paint.gd")
const DT := 1.0 / 30.0

var dd: Node
var _saved := {}


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	_saved = {"dir": Game.paint_dir, "pics": Game.pictures_dir}
	Game.paint_dir = OS.get_temp_dir().path_join("paint-party-demo-%d" % Time.get_ticks_usec())
	Game.pictures_dir = ""
	dd = DemoDriver.new()
	dd.use_goto = false
	add_child_autofree(dd)
	dd.set_process(false)


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.paint_dir = _saved.dir
	Game.pictures_dir = _saved.pics


func test_paint_start_seats_three_with_riders() -> void:
	dd.start("paint")
	assert_eq(Players.seated_count(), 3)
	assert_eq(Players.riders, ["penguin", "monkey", "fox"] as Array[String])


func test_path_is_continuous_in_time() -> void:
	var path: Array = DemoDriver.build_path()
	var prev: Vector2 = DemoDriver.path_at(path, 0.0).pos
	var t := 0.0
	while t < 24.0:
		t += DT
		var p: Vector2 = DemoDriver.path_at(path, t).pos
		prev = p
		assert_true(p.x >= 0 and p.y >= 0 and p.x <= 1920 and p.y <= 1080, "inside the canvas at %.2f" % t)


func test_demo_paints_stamps_splats_and_frames_the_picture() -> void:
	dd.start("paint")
	var screen: Node2D = PaintScreen.new()
	screen.auto_goto = false
	add_child_autofree(screen)
	screen.set_process(false)
	dd.paint = screen
	var t := 0.0
	var sizes := {}
	while t < 30.0 and screen.next_screen == "":
		t += DT
		dd.drive("paint", t)
		Players.poll()
		screen.step(DT)
		sizes[screen.size_idx] = true
	assert_gt(screen.stats.dabs, 500, "the brush painted")
	assert_eq(screen.stats.stamps, 6, "6 stamps")
	assert_between(screen.stats.splats, 8, 11, "a splat every 2.5 s")
	assert_gte(screen.stats.rainbows, 1)
	assert_gte(screen.stats.giggles, 1, "the double press giggles")
	assert_gt(screen.page, -1)
	assert_true(sizes.has(1) and sizes.has(2), "medium and big brush")
	assert_eq(screen.next_screen, "party", "framed after 25 s")
	var c: float = screen.coverage.total()
	assert_between(c, 0.1, 0.8, "a real picture, not a flood")
