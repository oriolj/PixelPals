extends GutTest
## Launch command building, the import step and the no-double-launch guard,
## with fake process callables (no real process is started).

const Runner := preload("res://scripts/runner.gd")

var runner: Runner
var spawned: Array = []
var alive := {}
var next_pid := 100
var dir := ""


func _spawn(path: String, args: PackedStringArray) -> int:
	next_pid += 1
	spawned.append([path, args])
	alive[next_pid] = true
	return next_pid


func _alive(p: int) -> bool:
	return alive.get(p, false)


func before_each() -> void:
	spawned.clear()
	alive.clear()
	dir = OS.get_user_data_dir().path_join("runner_fixture/game")
	DirAccess.make_dir_recursive_absolute(dir.path_join(".godot"))
	FileAccess.open(dir.path_join(".godot/global_script_class_cache.cfg"), FileAccess.WRITE).close()
	runner = Runner.new()
	runner.godot = "/repo/.tools/godot"
	runner.spawn = _spawn
	runner.is_alive = _alive
	add_child_autofree(runner)


func after_all() -> void:
	OS.execute("rm", ["-rf", OS.get_user_data_dir().path_join("runner_fixture")])


func _entry() -> Dictionary:
	return {"slug": "alpha", "title": "Alpha", "playable": true, "game_dir": dir}


func test_launch_command_is_godot_path_fullscreen() -> void:
	assert_eq(Runner.launch_args("/r/games/x/game"), PackedStringArray(["--path", "/r/games/x/game", "--fullscreen"]))
	assert_eq(Runner.launch_args("/g", false), PackedStringArray(["--path", "/g"]))
	assert_eq(Runner.launch_args("/g", true, PackedStringArray(["--quit-after-seconds=3"])),
		PackedStringArray(["--path", "/g", "--fullscreen", "--", "--quit-after-seconds=3"]))


func test_import_command() -> void:
	assert_eq(Runner.import_args("/g"), PackedStringArray(["--headless", "--path", "/g", "--import"]))


func test_launch_spawns_the_pinned_godot() -> void:
	assert_true(runner.request_launch(_entry()))
	assert_eq(spawned.size(), 1)
	assert_eq(spawned[0][0], "/repo/.tools/godot")
	assert_eq(spawned[0][1], Runner.launch_args(dir))
	assert_eq(runner.state, Runner.State.RUNNING)


func test_no_double_launch_while_running() -> void:
	runner.request_launch(_entry())
	assert_false(runner.request_launch(_entry()), "second press ignored")
	assert_false(runner.request_launch({"slug": "b", "playable": true, "game_dir": dir}), "another game too")
	assert_eq(spawned.size(), 1)


func test_game_exit_frees_the_runner_and_reports_it() -> void:
	watch_signals(runner)
	runner.request_launch(_entry())
	runner.check()
	assert_signal_not_emitted(runner, "finished", "still running")
	alive.clear()
	runner.check()
	assert_signal_emitted(runner, "finished")
	assert_false(runner.busy())
	assert_true(runner.request_launch(_entry()), "can launch again after the exit")


func test_missing_import_cache_imports_first_then_launches() -> void:
	OS.execute("rm", ["-rf", dir.path_join(".godot")])
	watch_signals(runner)
	assert_true(runner.request_launch(_entry()))
	assert_eq(runner.state, Runner.State.IMPORTING)
	assert_eq(spawned[0][1], Runner.import_args(dir))
	assert_signal_emitted(runner, "importing")
	assert_false(runner.request_launch(_entry()), "no double launch while importing")
	# The import finishes and writes the cache.
	DirAccess.make_dir_recursive_absolute(dir.path_join(".godot"))
	FileAccess.open(dir.path_join(".godot/global_script_class_cache.cfg"), FileAccess.WRITE).close()
	alive.clear()
	runner.check()
	assert_eq(runner.state, Runner.State.RUNNING)
	assert_eq(spawned.size(), 2)
	assert_eq(spawned[1][1], Runner.launch_args(dir))


func test_coming_soon_cards_never_launch() -> void:
	assert_false(runner.request_launch({"slug": "p", "playable": false, "game_dir": dir}))
	assert_eq(spawned.size(), 0)


func test_failed_spawn_returns_to_idle() -> void:
	runner.spawn = func(_p, _a): return -1
	watch_signals(runner)
	assert_false(runner.request_launch(_entry()))
	assert_signal_emitted(runner, "failed")
	assert_false(runner.busy())
