extends GutTest
## Pure rules, shapes and wreckers.

const Rules := preload("res://scripts/play/rules.gd")
const Vec := preload("res://scripts/play/vec.gd")
const BlockScript := preload("res://scripts/play/block.gd")
const WreckerScript := preload("res://scripts/play/wrecker.gd")


func test_roles_three_seats() -> void:
	var r := Rules.roles(true, true, true)
	assert_eq(r.move, 0)
	assert_eq(r.rotate, [0, "a"])
	assert_eq(r.drop, [1, "a"])
	assert_eq(r.pick, 1)
	assert_eq(r.topple, [[2, "any"]])
	assert_eq(r.grace, [[1, "a"]])


func test_roles_fold_down_to_one_seat() -> void:
	var r := Rules.roles(true, false, false)
	assert_eq(r.drop, [0, "a"])
	assert_eq(r.rotate, [0, "b"])
	assert_eq(r.pick, -1)
	assert_eq(r.topple, [[0, "a"]])


func test_roles_builder_plus_toddler() -> void:
	var r := Rules.roles(true, false, true)
	assert_eq(r.drop, [0, "a"])
	assert_eq(r.topple, [[2, "any"]])
	assert_eq(r.grace, [[0, "a"]])


func test_roles_two_seats() -> void:
	var r := Rules.roles(true, true, false)
	assert_eq(r.topple, [[1, "a"]])
	assert_eq(r.rotate, [0, "a"])


func test_assist_window() -> void:
	assert_true(Rules.in_assist(330, 250, 260, 320))
	assert_false(Rules.in_assist(330, 230, 260, 320), "more than 20 px above")
	assert_false(Rules.in_assist(380, 250, 260, 320), "too far sideways")
	assert_lt(Rules.assist_vx(330, 250, 260, 320, 0.0), 0.0)
	assert_eq(Rules.assist_vx(380, 250, 260, 320, 7.0), 7.0)


func test_flags_and_collapse() -> void:
	assert_eq(Rules.flags_for(0), 0)
	assert_eq(Rules.flags_for(Rules.FLAG_STEP * 3 + 1), 3)
	assert_eq(Rules.flags_for(9999), Rules.FLAGS)
	assert_false(Rules.is_collapse(1, 1))
	assert_true(Rules.is_collapse(2, 1), "most of a small tower fell")
	assert_false(Rules.is_collapse(2, 8))
	assert_true(Rules.is_collapse(3, 8))


func test_every_shape_is_centred_and_sized() -> void:
	var areas := {"square": 1000.0, "plank": 2300.0, "tall": 1500.0, "roof": 1024.0, "arch": 2150.0, "ball": 800.0}
	for k in Rules.SHAPES:
		var poly := BlockScript.shape_points(k)
		assert_almost_eq(Vec.centroid(poly).length(), 0.0, 0.01, "%s centred on its centroid" % k)
		assert_almost_eq(Vec.area(poly), areas[k], areas[k] * 0.12, "%s area" % k)
		assert_eq(Geometry2D.triangulate_polygon(poly).is_empty(), false, "%s is a simple polygon" % k)


func test_arch_is_concave_with_a_cut() -> void:
	var poly := BlockScript.shape_points("arch")
	var raw := Vec.arch(64, 40, 16)
	assert_false(Geometry2D.is_point_in_polygon(Vector2(0, 15), raw), "the middle of the cut is empty")
	assert_true(Geometry2D.is_point_in_polygon(Vector2(0, -12), raw), "the bridge above it is solid")
	assert_gt(poly.size(), 20)


func test_block_face_stays_upright() -> void:
	var b := BlockScript.make("plank")
	add_child_autofree(b)
	b.freeze = true
	b.rotation = PI * 0.9
	b._process(0.016)
	var total: float = b.rotation + b.visual.rotation + b.face.rotation
	assert_lt(absf(wrapf(total, -PI, PI)), PI / 4 + 0.01)


func test_wreckers_hit_before_they_end_near_the_tower() -> void:
	for k in WreckerScript.KINDS:
		var w := WreckerScript.new()
		add_child_autofree(w)
		w.setup(k, Rules.PLATFORM_TOP - 150.0, -100.0, 740.0)
		assert_lt(w.hit_time, w.duration, k)
		var c: Vector2 = w.contact_point()
		assert_lt(absf(c.x - Rules.PLATFORM_X), 100.0, "%s hits the tower" % k)
		assert_between(c.y, Rules.PLATFORM_TOP - 160.0, Rules.PLATFORM_TOP, k)
		var start := w.pos_at(0.0)
		assert_gt(start.distance_to(c), 120.0, "%s comes from afar" % k)
		assert_lt(w.pos_at(w.hit_time).distance_to(c), 90.0, "%s is at the tower at the hit" % k)
