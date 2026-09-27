extends GutTest
## Discovery against a fixture tree: playable, planned-only, missing cover,
## title fallbacks, pitch picking, card order.

const Catalog := preload("res://scripts/catalog.gd")

var root := ""


func _write(rel: String, text: String) -> void:
	var p := root.path_join(rel)
	DirAccess.make_dir_recursive_absolute(p.get_base_dir())
	var f := FileAccess.open(p, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func before_all() -> void:
	root = OS.get_user_data_dir().path_join("catalog_fixture")
	_rm(root)
	_write("games/alpha/README.md", "# Alpha Flyer\n\nA couch co-op game for a parent and small kids. Alpha flies over the hills:\n\n| a | b |\n")
	_write("games/alpha/game/project.godot", "config_version=5\n")
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color.RED)
	img.save_png(root.path_join("games/alpha/cover.png"))
	_write("games/beta/PLAN.md", "# Beta Plan\n\nBeta will be about boats.\n\nStatus: plan\n")
	_write("games/gamma/PLAN.md", "# Gamma Rolls\n\nGamma is a rolling game.\n")
	_write("games/gamma/game/project.godot", "config_version=5\n")
	_write("games/epsilon/game/project.godot", "config_version=5\n")
	DirAccess.make_dir_recursive_absolute(root.path_join("games/delta"))


func after_all() -> void:
	_rm(root)


func _rm(path: String) -> void:
	if DirAccess.dir_exists_absolute(path):
		OS.execute("rm", ["-rf", path])


func _by_slug(list: Array[Dictionary]) -> Dictionary:
	var out := {}
	for g in list:
		out[g.slug] = g
	return out


func test_discovers_playable_and_planned_and_skips_empty_dirs() -> void:
	var g := _by_slug(Catalog.discover(root))
	assert_eq(g.keys().size(), 4, "alpha, beta, gamma, epsilon; delta has nothing")
	assert_false(g.has("delta"))
	assert_true(g.alpha.playable)
	assert_false(g.beta.playable, "a PLAN.md without game/ is coming soon")
	assert_true(g.gamma.playable)


func test_title_from_readme_then_plan_then_slug() -> void:
	var g := _by_slug(Catalog.discover(root))
	assert_eq(g.alpha.title, "Alpha Flyer")
	assert_eq(g.gamma.title, "Gamma Rolls", "no README: PLAN.md heading")
	assert_eq(g.beta.title, "Beta Plan")
	assert_eq(g.epsilon.title, "Epsilon", "no docs at all: the slug")


func test_cover_path_or_empty_for_a_placeholder() -> void:
	var g := _by_slug(Catalog.discover(root))
	assert_eq(g.alpha.cover, root.path_join("games/alpha/cover.png"))
	assert_eq(g.gamma.cover, "", "missing cover.png: the card draws a placeholder")
	assert_eq(g.alpha.game_dir, root.path_join("games/alpha/game"))


func test_pitch_skips_the_generic_sentence() -> void:
	var g := _by_slug(Catalog.discover(root))
	assert_eq(g.alpha.pitch, "Alpha flies over the hills.")
	assert_eq(g.beta.pitch, "Beta will be about boats.")


func test_long_pitch_is_cut_at_a_colon() -> void:
	var p := Catalog.pick_pitch("Fly the Space Shuttle to build a space station in Earth orbit, land on Mars with a sky crane, then drive a rover across the red planet: one crew, three jobs.")
	assert_true(p.length() <= Catalog.PITCH_MAX + 1, p)
	assert_true(p.begins_with("Fly the Space Shuttle"))


func test_order_recent_first_then_titles_then_coming_soon() -> void:
	var list := Catalog.order(Catalog.discover(root), ["gamma"])
	var slugs := list.map(func(e): return e.slug)
	assert_eq(slugs, ["gamma", "alpha", "epsilon", "beta"])


func test_the_real_repo_has_pixelpals_with_a_title() -> void:
	var g := _by_slug(Catalog.discover(Catalog.default_root()))
	assert_true(g.has("pixelpals"), "discovery from the launcher's own path")
	assert_eq(g.pixelpals.title, "PixelPals")
	assert_true(g.pixelpals.playable)
