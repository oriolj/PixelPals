extends GutTest
## The asset contract: every sound the code plays exists, loads from source
## bytes, and the riders' PNGs are there.

const SOUNDS := ["drop_1", "drop_2", "drop_3", "land_1", "land_2", "land_3", "land_4", "rotate",
	"flag_1", "flag_2", "flag_3", "flag_4", "flag_5", "flag_6", "flag_7", "flag_8", "wobble",
	"giggle_1", "giggle_2", "giggle_3", "giggle_4", "button_lit", "swing", "crash", "whee",
	"pit_boing", "sparkle", "cheer", "join", "select", "ready", "party", "music_build", "music_menu"]


func test_every_sound_exists_and_loads() -> void:
	for s in SOUNDS:
		var path := ProjectSettings.globalize_path("res://audio/%s.wav" % s)
		assert_true(FileAccess.file_exists(path), s)
		var st := AudioStreamWAV.load_from_file(path)
		assert_not_null(st, s)
		assert_gt(st.get_length(), 0.04, s)


func test_variant_groups_resolve() -> void:
	for group in ["drop", "land", "giggle"]:
		assert_gt(Sfx._variants(group).size(), 1, group)


func test_riders_have_art() -> void:
	for r in Game.ORIGINAL_RIDERS:
		assert_true(Art.has(r), r)
		assert_eq(Art.size_of(r), Vector2i(16, 16))
