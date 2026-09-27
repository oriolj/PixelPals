extends GutTest
## Cover loading from bytes and the generated placeholder.

const Card := preload("res://scripts/card.gd")


func test_pixel_cover_is_prescaled_by_a_whole_factor() -> void:
	var p := OS.get_user_data_dir().path_join("cover_test.png")
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color.BLUE)
	img.save_png(p)
	var tex := Card.load_cover(p)
	assert_not_null(tex)
	assert_eq(tex.get_size(), Vector2(1280, 720), "320x180 x4, nearest")
	DirAccess.remove_absolute(p)


func test_vector_cover_keeps_its_size() -> void:
	var p := OS.get_user_data_dir().path_join("cover_test_v.png")
	var img := Image.create(1280, 720, false, Image.FORMAT_RGBA8)
	img.save_png(p)
	assert_eq(Card.load_cover(p).get_size(), Vector2(1280, 720))
	DirAccess.remove_absolute(p)


func test_missing_cover_gives_null_and_a_placeholder_exists() -> void:
	assert_null(Card.load_cover(""))
	assert_null(Card.load_cover("/nope/cover.png"))
	var ph := Card.placeholder("some-game")
	assert_eq(ph.get_size(), Vector2(640, 360))


func test_a_card_builds_without_a_cover() -> void:
	var c := Card.new()
	c.setup({"slug": "x", "title": "Xylophone", "playable": true, "cover": ""}, ThemeDB.fallback_font)
	add_child_autofree(c)
	assert_eq(c.size, Card.SIZE)
	assert_eq(c.kind, "game")
