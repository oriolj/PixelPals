extends GutTest
## The building site: assist, button lighting, collapse, topple, freezing,
## height, body budget, fold-downs and the three-tower run (the plan's tests).

const PlayScreen := preload("res://scripts/screens/play.gd")
const BlockScript := preload("res://scripts/play/block.gd")
const Rules := preload("res://scripts/play/rules.gd")
const DT := 1.0 / 30.0

var p: Node2D


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.tower_seconds = Game.DEFAULT_TOWER_SECONDS
	Game.reset_results()


func after_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.tower_seconds = Game.DEFAULT_TOWER_SECONDS
	Game.reset_results()
	PhysicsServer2D.set_active(true)


func _seats(n: int) -> void:
	for i in n:
		Players.join("demo:%d" % i)
	Players.poll()


func _screen() -> Node2D:
	p = PlayScreen.new()
	p.auto_goto = false
	add_child_autofree(p)
	p.set_process(false)
	p.set_physics_process(false)
	return p


func _step(states := {}, frames := 1) -> void:
	for d in states:
		Players.set_scripted(d, states[d])
	for i in frames:
		Players.poll()
		p.step(DT)


func _press(d: String, button := "a") -> void:
	_step({d: {button: true}})
	_step({d: {}})


func _wait_hanging() -> void:
	for i in 60:
		if p.hanging != null and p.hang_age > Rules.REST_TIME:
			return
		_step()


## A tower block resting at `pos` (no physics runs inside a synchronous test).
func _place(kind: String, pos: Vector2, state := BlockScript.State.SETTLED) -> RigidBody2D:
	var b := BlockScript.make(kind)
	b.gravity_scale = 0.0
	b.state = state
	b.rest_t = 1.0
	b.serial = p.blocks.size() + 100
	p.block_layer.add_child(b)
	b.global_position = pos
	p.blocks.append(b)
	return b


func _stack(n: int) -> Array:
	var out := []
	for k in n:
		out.append(_place("square", Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP - 16.0 - 32.0 * k)))
	return out


# ---------------------------------------------------------------- the plan's tests

func test_drop_nudges_toward_tower_within_assist() -> void:
	_seats(3)
	_screen()
	_stack(1)
	p.update_height(p.measure_height())
	assert_almost_eq(p.height, 32.0, 1.0)
	var top: float = Rules.PLATFORM_TOP - 32.0
	var b := _place("square", Vector2(340, top - 10.0 - 16.0), BlockScript.State.FALLING)
	b.linear_velocity = Vector2(0, 400)
	p.apply_assist(b)
	assert_lt(b.linear_velocity.x, -50.0, "pushed left, toward the tower")
	assert_lte(b.linear_velocity.y, Rules.ASSIST_MAX_VY, "slowed for a soft landing")


func test_drop_far_from_tower_is_not_nudged() -> void:
	_seats(3)
	_screen()
	_stack(1)
	p.update_height(p.measure_height())
	var top: float = Rules.PLATFORM_TOP - 32.0
	var wide := _place("square", Vector2(430, top - 26.0), BlockScript.State.FALLING)
	wide.linear_velocity = Vector2(0, 400)
	p.apply_assist(wide)
	assert_eq(wide.linear_velocity, Vector2(0, 400), "too far sideways")
	var high := _place("square", Vector2(340, top - 120.0), BlockScript.State.FALLING)
	high.linear_velocity = Vector2(0, 400)
	p.apply_assist(high)
	assert_eq(high.linear_velocity, Vector2(0, 400), "still too high above the tower")


func test_toddler_press_before_lit_applies_no_impulse() -> void:
	_seats(3)
	_screen()
	var tower := _stack(3)
	var before := []
	for b in tower:
		before.append([b.linear_velocity, b.angular_velocity, b.freeze, b.global_position])
	_press("demo:2")
	assert_eq(p.giggles, 1, "the press giggles")
	assert_eq(p.impulses, 0)
	assert_false(p.lit)
	assert_eq(p.phase, p.Phase.BUILD)
	for i in tower.size():
		var b: RigidBody2D = tower[i]
		assert_eq([b.linear_velocity, b.angular_velocity, b.freeze, b.global_position], before[i])
		assert_eq(b.mood, BlockScript.Mood.GIGGLE)


func test_button_lights_at_cloud_line() -> void:
	_seats(3)
	_screen()
	p.update_height(Rules.CLOUD_HEIGHT - 10.0)
	_step()
	assert_false(p.lit)
	p.update_height(Rules.CLOUD_HEIGHT)
	_step()
	assert_true(p.lit)
	assert_eq(p.flags, Rules.FLAGS)


func test_button_lights_after_fourteen_blocks() -> void:
	_seats(3)
	_screen()
	p.drops = Rules.MAX_DROPS - 1
	_step()
	assert_false(p.lit)
	p.drops = Rules.MAX_DROPS
	_step()
	assert_true(p.lit)


func test_button_lights_after_timer() -> void:
	_seats(3)
	Game.tower_seconds = 3.0
	_screen()
	_step({}, 80)
	assert_false(p.lit, "not before the timer")
	_step({}, 15)
	assert_true(p.lit)


func test_self_collapse_lights_button_and_keeps_stars() -> void:
	_seats(3)
	_screen()
	var tower := _stack(5)
	p.update_height(p.measure_height())
	assert_eq(p.flags, 4)
	assert_eq(p.stars, 4)
	assert_false(p.lit)
	for k in range(2, 5):
		tower[k].was_on_tower = true
		p.to_pit(tower[k])
	_step()
	assert_true(p.collapsed, "three blocks fell off the tower")
	assert_true(p.lit)
	assert_eq(p.stars, 4, "stars kept")
	assert_eq(p.flags, 4, "flags kept")
	assert_eq(p.phase, p.Phase.BUILD, "no topple until someone presses")


func test_topple_only_fires_when_lit() -> void:
	_seats(3)
	_screen()
	_stack(2)
	assert_false(p.try_topple())
	_press("demo:2")
	assert_eq(p.phase, p.Phase.BUILD)
	p.light()
	_press("demo:2")
	assert_eq(p.phase, p.Phase.TOPPLE)
	assert_false(p.try_topple(), "only once per tower")


func test_buried_blocks_freeze_and_unfreeze_on_topple() -> void:
	_seats(3)
	_screen()
	var tower := _stack(5)
	p.update_burying()
	assert_true(tower[0].buried and tower[0].freeze, "four blocks above")
	assert_true(tower[1].buried and tower[1].freeze, "three blocks above")
	assert_false(tower[2].buried, "only two above")
	assert_false(tower[4].freeze)
	p.light()
	assert_true(p.try_topple())
	p.hit(Vector2(290, Rules.PLATFORM_TOP - 60.0), Vector2.RIGHT)
	for b in tower:
		assert_false(b.freeze, "every block flies on the topple")
		assert_false(b.buried)
	assert_eq(p.impulses, 5)


func test_height_ignores_moving_blocks() -> void:
	_seats(3)
	_screen()
	var low := _place("square", Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP - 16.0))
	var high := _place("tall", Vector2(Rules.PLATFORM_X, Rules.PLATFORM_TOP - 64.0))
	low.rest_t = 0.0
	high.rest_t = 0.0
	high.linear_velocity = Vector2(30, 80)
	p.track_blocks(0.6)
	assert_gte(low.rest_t, Rules.REST_TIME)
	assert_eq(high.rest_t, 0.0)
	assert_almost_eq(p.measure_height(), 32.0, 1.0, "the moving block is not counted")
	high.linear_velocity = Vector2.ZERO
	p.track_blocks(0.6)
	assert_almost_eq(p.measure_height(), 96.0, 1.0, "counted once it rests")


func test_body_budget_removes_oldest_pit_block() -> void:
	_seats(3)
	_screen()
	for i in Rules.BODY_BUDGET - 2:
		_place("square", Vector2(300 + (i % 3) * 20, 100 + i), BlockScript.State.SETTLED)
	var old_pit := _place("ball", Vector2(100, Rules.PIT_TOP - 16.0), BlockScript.State.PIT)
	old_pit.serial = 3
	var new_pit := _place("ball", Vector2(560, Rules.PIT_TOP - 16.0), BlockScript.State.PIT)
	new_pit.serial = 90
	assert_eq(p.blocks.size(), Rules.BODY_BUDGET)
	p.spawn_hanging("square")
	assert_false(p.blocks.has(old_pit), "the oldest pit block goes")
	assert_true(old_pit.is_queued_for_deletion())
	assert_true(p.blocks.has(new_pit))
	assert_eq(p._live_count(), Rules.BODY_BUDGET)


func test_one_seat_builder_drops_and_topples() -> void:
	_seats(1)
	_screen()
	_wait_hanging()
	assert_false(p.tray_view.visible, "no Dropper: no tray, random shapes")
	_press("demo:0", "b")
	assert_eq(p.hang_rot, 1, "B rotates when alone")
	var b: RigidBody2D = p.hanging
	_press("demo:0", "a")
	assert_null(p.hanging)
	assert_eq(p.drops, 1)
	assert_eq(b.state, BlockScript.State.FALLING)
	p.light()
	_wait_hanging()
	_press("demo:0", "a")
	assert_eq(p.phase, p.Phase.TOPPLE, "A on a lit button topples")
	assert_eq(p.drops, 1, "and does not also drop")


func test_two_seats_dropper_topples() -> void:
	_seats(2)
	_screen()
	_wait_hanging()
	_press("demo:0", "a")
	assert_eq(p.hang_rot, 1, "the Builder's A rotates")
	assert_eq(p.drops, 0)
	_press("demo:1", "a")
	assert_eq(p.drops, 1, "the Dropper's A drops")
	p.light()
	_wait_hanging()
	_press("demo:0", "a")
	assert_eq(p.phase, p.Phase.BUILD, "the Builder cannot topple with a Dropper there")
	_press("demo:1", "a")
	assert_eq(p.phase, p.Phase.TOPPLE)


func test_run_ends_after_three_towers() -> void:
	_seats(3)
	_screen()
	for tower in 3:
		assert_eq(p.tower_index, tower)
		_stack(tower + 1)
		p.update_height(p.measure_height())
		p.light()
		assert_true(p.try_topple())
		var guard := 0
		while p.tower_index == tower and p.next_screen == "" and guard < 600:
			_step()
			guard += 1
	assert_eq(p.next_screen, "party")
	assert_eq(Game.tower_heights, [0, 1, 2] as Array[int])
	assert_eq(Game.stars, 3)


# ---------------------------------------------------------------- more

func test_toddler_grace_lets_the_dropper_topple() -> void:
	_seats(3)
	_screen()
	_wait_hanging()
	p.light()
	p.drop()
	_wait_hanging()
	_press("demo:1", "a")
	assert_eq(p.phase, p.Phase.BUILD, "the toddler owns the button at first")
	p.lit_t = Rules.TODDLER_GRACE + 0.1
	_wait_hanging()
	_press("demo:1", "a")
	assert_eq(p.phase, p.Phase.TOPPLE)


func test_dropper_picks_the_hanging_shape() -> void:
	_seats(2)
	_screen()
	_wait_hanging()
	p.tray = ["plank", "roof", "tall", "square"] as Array[String]
	_step({"demo:1": {"move": Vector2.RIGHT}})
	_step({"demo:1": {}})
	assert_eq(p.tray_sel, 1)
	assert_eq(p.hanging.kind, "roof")
	_step({"demo:1": {"move": Vector2.UP}})
	assert_eq(p.hanging.kind, "plank")


func test_only_one_ball_per_tower() -> void:
	_seats(3)
	_screen()
	p.ball_used = true
	for i in 200:
		assert_ne(p.random_kind(), "ball")
	p._next_tower()
	assert_false(p.ball_used, "a new tower allows a ball again")


func test_missed_block_recycles_from_the_pit() -> void:
	_seats(3)
	_screen()
	var b := _place("square", Vector2(100, Rules.PIT_TOP - 16.0), BlockScript.State.FALLING)
	p.to_pit(b)
	assert_eq(b.state, BlockScript.State.PIT)
	assert_eq(p.fallen, 0, "a miss is not a collapse")
	p.track_blocks(Rules.SETTLE_TIME)
	assert_eq(b.state, BlockScript.State.CLEARING)
	await wait_seconds(0.5)
	assert_false(p.blocks.has(b), "recycled")


func test_pause_is_builder_only_and_b_goes_back_to_join() -> void:
	_seats(3)
	_screen()
	_press("demo:1", "start")
	assert_false(p.paused)
	_press("demo:0", "start")
	assert_true(p.paused)
	_press("demo:0", "b")
	assert_eq(p.next_screen, "join")
	assert_eq(Players.seated_count(), 0)


func test_real_drop_lands_on_the_platform() -> void:
	_seats(3)
	_screen()
	p.set_process(true)
	p.set_physics_process(true)
	await wait_seconds(0.8)
	var b: RigidBody2D = p.hanging
	assert_not_null(b)
	p.hook_x = Rules.PLATFORM_X
	await wait_physics_frames(2)
	p.drop()
	await wait_seconds(2.5)
	assert_true(b.state in [BlockScript.State.SETTLING, BlockScript.State.SETTLED], "landed on the platform")
	assert_true(b.was_on_tower)
	assert_gt(p.height, 20.0, "the tower has a height")
