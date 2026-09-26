extends GutTest
## The level screen driven frame by frame with scripted devices.

const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.run_seconds = 0.0
	Game.stars = 0
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
	Game.run_seconds = 0.0
	Players.reset()
	Players.clear_scripted()


func _seat(n: int) -> void:
	for i in n:
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]


func _level() -> Node:
	Game.goto("level")
	var lvl: Node = Game.current
	lvl.set_process(false)
	lvl.rng.seed = 1
	lvl.spawn_t = 999.0  # no random spawns unless a test asks
	lvl.big_t = 999.0
	return lvl


func _drive(device: String, state: Dictionary, lvl: Node) -> void:
	Players.set_scripted(device, state)
	Players.poll()
	lvl.step(DT)


func _tap(device: String, button: String, lvl: Node) -> void:
	_drive(device, {button: true}, lvl)
	_drive(device, {}, lvl)


func test_bullet_steers_into_a_target_off_its_line() -> void:
	_seat(2)
	var lvl := _level()
	var muzzle: Vector2 = lvl.tub_pos + lvl.turret.position
	var balloon: Dictionary = lvl.spawn_balloon(muzzle + Vector2(90, 26))
	balloon.vel = Vector2.ZERO
	lvl.fire()
	for i in 60:
		lvl.step(DT)
	assert_false(lvl.targets.has(balloon), "the balloon popped thanks to the aim assist")
	assert_gt(lvl.pending + lvl.stars, 0, "popping gives stars")


func test_stars_fly_to_the_tub_and_are_collected() -> void:
	_seat(1)
	var lvl := _level()
	lvl.spawn_star(lvl.tub_pos + Vector2(80, -40), Vector2(20, 0))
	for i in 90:
		lvl.step(DT)
	assert_eq(lvl.stars, 1)
	assert_eq(lvl.pending, 0)


func test_a_hit_costs_stars_but_never_ends_the_run() -> void:
	_seat(1)
	var lvl := _level()
	lvl.stars = 2
	var cloud: Dictionary = lvl.spawn_cloud(lvl.tub_pos)
	cloud.vel = Vector2.ZERO
	lvl.step(DT)
	assert_eq(lvl.stars, 0, "lost up to 3, clamped at zero")
	assert_gt(lvl.invuln, 0.0)
	var again: Dictionary = lvl.spawn_cloud(lvl.tub_pos)
	again.vel = Vector2.ZERO
	lvl.step(DT)
	assert_eq(lvl.stars, 0, "never negative")
	lvl.invuln = 0.0
	lvl.hit_tub(again)
	assert_eq(lvl.stars, 0)
	assert_eq(lvl.state, lvl.State.RUN, "still running")
	assert_eq(Game.current, lvl)


func test_a_hit_takes_at_most_three() -> void:
	_seat(1)
	var lvl := _level()
	lvl.stars = 10
	lvl.hit_tub(lvl.spawn_cloud(Vector2(300, 40)))
	assert_eq(lvl.stars, 7)


func test_honk_scares_clouds_and_scared_clouds_do_no_damage() -> void:
	_seat(3)
	var lvl := _level()
	lvl.stars = 5
	var cloud: Dictionary = lvl.spawn_cloud(Vector2(250, 60))
	_tap("demo:2", "a", lvl)
	assert_gt(cloud.scared, 0.0, "honk scared the cloud")
	assert_gt(lvl.bloom_t, 0.0, "flowers bloom")
	cloud.pos = lvl.tub_pos
	cloud.vel = Vector2.ZERO
	lvl.step(DT)
	assert_eq(lvl.stars, 5, "a scared cloud is harmless")
	assert_eq(lvl.invuln, 0.0)


func test_honk_has_a_cooldown_and_only_the_honker_honks() -> void:
	_seat(3)
	var lvl := _level()
	var cloud: Dictionary = lvl.spawn_cloud(Vector2(250, 60))
	_tap("demo:1", "a", lvl)
	assert_eq(cloud.scared, 0.0, "the gunner's button does not honk")
	_tap("demo:2", "a", lvl)
	var first: float = lvl.honk_cd
	assert_gt(first, 0.0)
	_tap("demo:2", "b", lvl)
	assert_lt(lvl.honk_cd, first, "second honk inside the cooldown is ignored")


func test_honk_collects_the_big_star_worth_ten() -> void:
	_seat(3)
	var lvl := _level()
	lvl.spawn_big_star()
	lvl.big_star.pos = Vector2(200, 56)
	_tap("demo:2", "a", lvl)
	assert_true(lvl.big_star.collecting)
	for i in 150:
		lvl.step(DT)
	assert_eq(lvl.stars, 10)


func test_run_ends_and_goes_to_party() -> void:
	_seat(2)
	Game.run_seconds = 1.0
	var lvl := _level()
	lvl.stars = 4
	for i in 30:
		lvl.step(DT)
	assert_eq(Game.current_name, "level", "celebrating, not gone yet")
	for i in 120:
		lvl.step(DT)
	assert_eq(Game.current_name, "party")
	assert_eq(Game.stars, 4)


func test_pause_only_responds_to_the_driver() -> void:
	_seat(3)
	var lvl := _level()
	_tap("demo:1", "start", lvl)
	_tap("demo:2", "start", lvl)
	assert_false(lvl.paused, "gunner and honker cannot pause")
	_tap("demo:0", "start", lvl)
	assert_true(lvl.paused)
	var t: float = lvl.time
	_tap("demo:1", "b", lvl)
	_tap("demo:2", "a", lvl)
	_tap("demo:1", "start", lvl)
	assert_true(lvl.paused, "other seats cannot resume or quit")
	assert_eq(lvl.time, t, "time stands still")
	assert_eq(Game.current_name, "level")
	_tap("demo:0", "a", lvl)
	assert_false(lvl.paused, "driver a resumes")


func test_driver_b_in_pause_goes_back_to_join() -> void:
	_seat(2)
	var lvl := _level()
	_tap("demo:0", "b", lvl)
	assert_eq(Game.current_name, "level", "b does nothing outside pause")
	_tap("demo:0", "start", lvl)
	_tap("demo:0", "b", lvl)
	assert_eq(Game.current_name, "join")
	assert_eq(Players.seated_count(), 0)


func test_solo_driver_turret_fires_by_itself() -> void:
	_seat(1)
	var lvl := _level()
	lvl.spawn_balloon(lvl.tub_pos + Vector2(100, 0))
	for i in 45:
		lvl.step(DT)
	assert_gt(lvl.bullets.size() + lvl.pending + lvl.stars, 0)


func test_gunner_aims_in_four_directions_and_keeps_the_last() -> void:
	_seat(2)
	var lvl := _level()
	assert_eq(lvl.aim_dir, Vector2i.RIGHT, "starts right")
	_drive("demo:1", {"move": Vector2(0, -1)}, lvl)
	_drive("demo:1", {}, lvl)
	assert_eq(lvl.aim_dir, Vector2i.UP, "kept when idle")
	_drive("demo:1", {"a": true}, lvl)
	assert_eq(lvl.bullets.size(), 1)
	for i in 3:
		_drive("demo:1", {"a": true}, lvl)
	assert_eq(lvl.bullets.size(), 1, "cooldown")
	for i in 6:
		_drive("demo:1", {"a": true}, lvl)
	assert_gt(lvl.bullets.size(), 1, "holding auto-fires")


func test_works_with_every_party_size() -> void:
	for n in [1, 2, 3]:
		Players.reset()
		_seat(n)
		var lvl := _level()
		lvl.spawn_t = 0.0
		for i in 120:
			lvl.step(DT)
		assert_eq(lvl.state, lvl.State.RUN)
		assert_eq(lvl.tub.get_child_count(), n + 2, "riders + tub + turret")
