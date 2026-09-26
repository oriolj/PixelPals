extends GutTest
## The level screen driven frame by frame with scripted devices.

const LevelScreen := preload("res://scripts/screens/level.gd")
const FieldRules := preload("res://scripts/field_rules.gd")
const Tile := FieldRules.Tile
const DT := 1.0 / 30.0

var root: Node2D
var lv
var _saved_root: Node
var _saved_mute := false


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.run_limit = 360.0
	Game.level_preset = ""
	_saved_mute = Sfx.muted
	Sfx.muted = true
	_saved_root = Game._root
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
	Sfx.muted = _saved_mute
	Players.reset()
	Players.clear_scripted()


func _open(seats: int) -> void:
	for i in seats:
		Players.set_scripted("demo:%d" % i, {})
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]
	lv = LevelScreen.new()
	root.add_child(lv)
	lv.set_process(false)
	Game.current = lv


## One frame with the given scripted states (device index -> state).
func _step(states := {}) -> void:
	for i in 3:
		Players.set_scripted("demo:%d" % i, states.get(i, {}))
	Players.poll()
	lv.step(DT)


func _frames(n: int, states := {}) -> void:
	for k in n:
		_step(states)


func _press(seat: int, button := "a") -> void:
	_step({seat: {button: true}})
	_step({})


## Put the tractor chain somewhere, heading right, standing still.
func _place(pos: Vector2, heading := 0.0) -> void:
	lv.tractor_pos = pos
	lv.heading = heading
	lv.speed = 0.0
	var h := Vector2.from_angle(heading)
	lv.planter_pos = pos - h * (lv.HITCH_BACK + lv.PLANTER_GAP)
	lv.trailer_pos = lv.planter_pos - h * (34.0 + lv.TRAILER_GAP)
	lv._follow_chain()
	lv._last_wheel_cells = {}


func _cell_px(c: Vector2i) -> Vector2:
	return lv.FIELD_POS + FieldRules.cell_center(c)


# ---------------------------------------------------------------- tractor

func test_plough_turns_grass_to_furrows_under_footprint() -> void:
	_open(2)
	lv.planter_on = false
	lv.auto_rain_t = -100.0
	_place(_cell_px(Vector2i(2, 4)))
	var cells := {}
	for k in 60:
		_step({0: {"move": Vector2.RIGHT}})
		cells[FieldRules.cell_at(lv._local(lv.plough_point()))] = true
	assert_gt(cells.size(), 4, "the plough crossed several tiles")
	for y in FieldRules.H:
		for x in FieldRules.W:
			var c := Vector2i(x, y)
			var want := Tile.PLOUGHED if cells.has(c) else Tile.GRASS
			assert_eq(lv.field.tile(c), want, "cell %s" % c)


func test_planter_follows_and_sows_the_current_seed() -> void:
	_open(2)
	_place(_cell_px(Vector2i(2, 4)))
	lv.pick_seed(FieldRules.Crop.SUNFLOWER)
	_frames(90, {0: {"move": Vector2.RIGHT}})
	var seeded := 0
	for x in FieldRules.W:
		var c := Vector2i(x, 4)
		if lv.field.tile(c) >= Tile.SEEDED:
			seeded += 1
			assert_eq(lv.field.crop_of(c), FieldRules.Crop.SUNFLOWER)
	assert_gt(seeded, 3, "the planter sowed the furrows behind the plough")
	assert_eq(lv.field.count(Tile.SEEDED) + lv.field.count(Tile.SPROUT), seeded, "only on the driven row")


func test_driving_over_sprouts_never_destroys_them_in_play() -> void:
	_open(2)
	lv.planter_on = false
	lv.auto_rain_t = -100.0
	for x in range(3, 12):
		var c := Vector2i(x, 4)
		lv.field.plough(c)
		lv.field.plant(c, FieldRules.Crop.CARROT)
		lv.field.advance(c)
	_place(_cell_px(Vector2i(1, 4)))
	for pass_i in 2:
		_frames(80, {0: {"move": Vector2.RIGHT if pass_i == 0 else Vector2.LEFT}})
	for x in range(3, 12):
		assert_eq(lv.field.tile(Vector2i(x, 4)), Tile.SPROUT, "sprout %d" % x)


func test_fence_keeps_the_tractor_on_the_farm() -> void:
	_open(1)
	_place(Vector2(200, 400))
	for dir in [Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2.RIGHT]:
		_frames(240, {0: {"move": dir}})
		assert_true(lv.BOUNDS.grow(1.0).has_point(lv.tractor_pos), "stays inside going %s" % dir)


func test_harvest_fills_the_trailer_while_driving() -> void:
	_open(2)
	lv.planter_on = false
	for x in range(4, 10):
		var c := Vector2i(x, 3)
		lv.field.plough(c)
		lv.field.plant(c, FieldRules.Crop.PUMPKIN)
		for k in 3:
			lv.field.advance(c)
	_place(_cell_px(Vector2i(2, 3)))
	_frames(90, {0: {"move": Vector2.RIGHT}})
	assert_eq(lv.field.trailer.size(), 6)
	assert_eq(lv.field.count(Tile.RIPE), 0)


func test_trailer_tips_at_the_barn_with_a_or_by_parking() -> void:
	_open(1)
	lv.field.trailer.assign([0, 1, 1, 2, 3])
	_place(Vector2(1160, 420), PI)
	_press(0)
	assert_eq(lv.field.trailer.size(), 0, "A tips in the barn zone")
	assert_eq(lv.field.barn, [1, 2, 1, 1] as Array[int])
	_frames(40)
	assert_eq(lv.display_barn, [1, 2, 1, 1] as Array[int], "the crops landed in the crates")
	lv.field.trailer.assign([3, 3])
	_frames(int(lv.PARK_TIP / DT) + 3)
	assert_eq(lv.field.barn[3], 3, "parking 2 s tips too")
	# Away from the barn, A is the horn and tips nothing.
	lv.field.trailer.assign([0])
	_place(Vector2(400, 400))
	_press(0)
	assert_eq(lv.field.trailer.size(), 1)


# ---------------------------------------------------------------- seeds

func test_seed_directions_map_to_four_crops() -> void:
	_open(2)
	var want := {Vector2.UP: 0, Vector2.RIGHT: 1, Vector2.DOWN: 2, Vector2.LEFT: 3}
	for d in want:
		_step({1: {"move": d}})
		_step({})
		assert_eq(lv.seed_crop, want[d], "flick %s" % d)
	assert_true(lv.planter_on)
	_press(1)
	assert_false(lv.planter_on, "A toggles the planter")
	_press(1)
	assert_true(lv.planter_on)


func test_no_seed_seat_cycles_the_seed_each_row() -> void:
	_open(1)
	_place(Vector2(500, 300))
	var seen := {lv.seed_crop: true}
	for i in 4:
		_frames(80, {0: {"move": Vector2.LEFT if i % 2 == 0 else Vector2.RIGHT}})
		seen[lv.seed_crop] = true
	assert_eq(seen.size(), 4, "each turn at the headland picks the next seed")


# ---------------------------------------------------------------- cloud

func _sprouts_under_cloud() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for c in FieldRules.rain_cells(lv.cloud_ground - lv.FIELD_POS):
		lv.field.plough(c)
		lv.field.plant(c, FieldRules.Crop.CARROT)
		out.append(c)
	lv.field.drain_events()
	return out


func test_only_cloud_seat_rains_with_cooldown() -> void:
	_open(3)
	_frames(3)
	var cells := _sprouts_under_cloud()
	var c := cells[0]
	_press(0)  # horn
	_press(1)  # planter toggle
	_step({0: {"start": false, "b": true}, 1: {"b": true}})
	assert_false(lv.raining(), "neither the driver nor the seed kid rains")
	assert_eq(lv.field.tile(c), Tile.SEEDED)
	lv.cloud_ground = lv.cloud_ground  # the cloud stays put: no driving
	_press(2)
	assert_true(lv.raining(), "any cloud press rains")
	assert_eq(lv.field.tile(c), Tile.SPROUT)
	_press(2)
	assert_eq(lv.field.tile(c), Tile.SPROUT, "a press inside the cooldown does not grow again")
	assert_eq(lv.rain_presses, 1)
	_frames(int(lv.RAIN_COOLDOWN / DT) + 1)
	_press(2)
	assert_eq(lv.rain_presses, 2)
	assert_eq(lv.field.tile(c), Tile.GROWING, "after the cooldown it rains again")


func test_rain_press_changes_plants_within_three_frames() -> void:
	_open(3)
	_frames(3)
	var cells := _sprouts_under_cloud()
	var node_count := 0
	_step({2: {"a": true}})
	for c in cells:
		assert_eq(lv.field.tile(c), Tile.SPROUT, "grown on the press frame")
		if lv.crop_nodes.has(c) and lv.crop_nodes[c].stage == Tile.SPROUT:
			node_count += 1
	assert_eq(node_count, cells.size(), "and every plant node shows it in the same frame")


func test_auto_rain_every_4s_with_one_seat_and_6s_with_two() -> void:
	for seats in [1, 2]:
		_open(seats)
		_frames(2)
		_sprouts_under_cloud()
		var every: float = lv.AUTO_RAIN_1 if seats == 1 else lv.AUTO_RAIN_2
		_frames(int((every - 0.3) / DT))
		assert_eq(lv.rain_presses, 0, "%d seats: not yet" % seats)
		_frames(int(0.6 / DT))
		assert_eq(lv.rain_presses, 1, "%d seats: rained by itself" % seats)
		lv.free()
		Players.reset()


func test_no_auto_rain_when_the_cloud_seat_is_taken() -> void:
	_open(3)
	_frames(2)
	_sprouts_under_cloud()
	_frames(int(8.0 / DT))
	assert_eq(lv.rain_presses, 0, "the toddler owns the rain")


func test_five_quick_presses_make_a_rainbow() -> void:
	_open(3)
	for i in 5:
		_press(2)
		_frames(6)
	assert_gt(lv.rainbow_t, 0.0)


func test_toddler_mashing_never_hurts_the_run() -> void:
	_open(3)
	for x in 16:
		lv.field.plough(Vector2i(x, 5))
		lv.field.plant(Vector2i(x, 5), x % 4)
	lv.field.trailer.assign([0, 1])
	lv.field.barn.assign([2, 2, 2, 2])
	for k in 600:
		_step({2: {"a": k % 2 == 0, "any": k % 2 == 0}})
	assert_eq(lv.field.trailer.size(), 2)
	assert_eq(lv.field.barn, [2, 2, 2, 2] as Array[int])
	for x in 16:
		assert_eq(lv.field.crop_of(Vector2i(x, 5)), x % 4, "crop %d still there" % x)
	assert_eq(lv.state, lv.State.RUN)


# ---------------------------------------------------------------- flow

func test_run_ends_at_thirty_crops_or_six_minutes() -> void:
	_open(1)
	lv.field.barn.assign([10, 10, 5, 5])
	_frames(40)
	assert_eq(lv.state, lv.State.FINALE, "30 crops in the barn")
	lv.free()
	Players.reset()
	_open(1)
	lv.field.elapsed = 359.0
	_frames(20)
	assert_eq(lv.state, lv.State.RUN)
	_frames(20)
	assert_eq(lv.state, lv.State.FINALE, "6 minutes")


func test_finale_grows_the_giant_and_goes_to_the_party() -> void:
	_open(3)
	lv.field.planted = [1, 5, 2, 0] as Array[int]
	lv.field.barn.assign([10, 8, 7, 5])
	_frames(40)
	assert_eq(lv.giant_crop, 1, "the most-planted crop")
	for k in 60 * 30:
		_step({2: {"a": k % 20 == 0}})
		if lv.state == lv.State.DONE:
			break
	assert_eq(lv.state, lv.State.DONE)
	assert_eq(Game.barn, [10, 8, 7, 5] as Array[int])
	assert_eq(Game.giant_crop, 1)


func test_pause_and_back_to_join() -> void:
	_open(2)
	_press(0, "start")
	assert_true(lv.paused)
	var t0: float = lv.t
	_frames(10, {0: {"move": Vector2.RIGHT}})
	assert_eq(lv.t, t0, "nothing moves while paused")
	_press(0)
	assert_false(lv.paused, "A resumes")
	_press(0, "start")
	_press(0, "b")
	assert_eq(Game.current_name, "join")


func test_visitor_nibbles_a_ripe_crop_and_leaves_a_heart() -> void:
	_open(1)
	var c := Vector2i(3, 3)
	lv.field.plough(c)
	lv.field.plant(c, 0)
	for k in 3:
		lv.field.advance(c)
	lv.field.elapsed = lv.VISITOR_TIMES[0]
	lv.field.barn.assign([1, 0, 0, 0])
	_place(Vector2(900, 650))
	_frames(1)
	assert_eq(lv.animals.size(), 1)
	assert_eq(lv.animals[0].kind, "bunny")
	var saw_dance := false
	for k in 30 * 12:
		_frames(1)
		if lv.animals.size() > 0 and lv.animals[0].phase == "dance":
			saw_dance = true
	assert_true(saw_dance)
	assert_eq(lv.field.tile(c), Tile.PLOUGHED, "one crop nibbled")
	assert_eq(lv.field.barn, [1, 0, 0, 0] as Array[int], "no loss counters")
