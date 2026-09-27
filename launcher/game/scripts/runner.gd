extends Node
## Starts one game at a time as a separate Godot process and watches it.
##
##   IDLE -> (import cache missing) IMPORTING -> RUNNING -> IDLE
##
## request_launch() is refused unless IDLE, so a double press, a second pad or
## a toddler mashing A never starts two games. The process calls go through
## spawn/is_alive callables so the tests can drive the whole flow without
## starting real processes.

signal importing(entry: Dictionary)
signal started(entry: Dictionary, pid: int)
signal finished(entry: Dictionary)
signal failed(entry: Dictionary, reason: String)

enum State { IDLE, IMPORTING, RUNNING }

const POLL_SECONDS := 0.25

var state := State.IDLE
var entry: Dictionary = {}
var pid := -1
## Absolute path of the pinned Godot binary (<root>/.tools/godot).
var godot := ""
## Launch games fullscreen (off for `make launcher-window`).
var fullscreen := true
## Extra user args for the game, passed after "--" (e.g. --quit-after-seconds=3).
var game_args: PackedStringArray = []
## (path: String, args: PackedStringArray) -> pid, -1 on failure.
var spawn: Callable = func(path: String, args: PackedStringArray) -> int: return OS.create_process(path, args)
## (pid: int) -> bool
var is_alive: Callable = func(p: int) -> bool: return OS.is_process_running(p)

var _poll := 0.0
var _started_ms := 0


static func import_cache_ready(game_dir: String) -> bool:
	return FileAccess.file_exists(game_dir.path_join(".godot/global_script_class_cache.cfg"))


static func import_args(game_dir: String) -> PackedStringArray:
	return PackedStringArray(["--headless", "--path", game_dir, "--import"])


static func launch_args(game_dir: String, full := true, extra: PackedStringArray = []) -> PackedStringArray:
	var a := PackedStringArray(["--path", game_dir])
	if full:
		a.append("--fullscreen")
	if not extra.is_empty():
		a.append("--")
		a.append_array(extra)
	return a


func busy() -> bool:
	return state != State.IDLE


## Start `e` (a catalog entry). Returns false (and does nothing) when a game is
## already importing or running, or when the entry is not playable.
func request_launch(e: Dictionary) -> bool:
	if busy() or not e.get("playable", false):
		return false
	entry = e
	if not import_cache_ready(e.game_dir):
		pid = spawn.call(godot, import_args(e.game_dir))
		if pid <= 0:
			return _fail("import could not start")
		state = State.IMPORTING
		importing.emit(entry)
		return true
	return _start_game()


func _start_game() -> bool:
	pid = spawn.call(godot, launch_args(entry.game_dir, fullscreen, game_args))
	if pid <= 0:
		return _fail("game could not start")
	state = State.RUNNING
	_started_ms = Time.get_ticks_msec()
	print("launcher: started %s pid=%d" % [entry.slug, pid])
	started.emit(entry, pid)
	return true


func _fail(reason: String) -> bool:
	var e := entry
	state = State.IDLE
	pid = -1
	entry = {}
	push_warning("launcher: %s (%s)" % [reason, e.get("slug", "?")])
	failed.emit(e, reason)
	return false


func _process(delta: float) -> void:
	if state == State.IDLE:
		return
	_poll += delta
	if _poll < POLL_SECONDS:
		return
	_poll = 0.0
	check()


## One poll step (tests call it directly).
func check() -> void:
	if state == State.IDLE or is_alive.call(pid):
		return
	if state == State.IMPORTING:
		if import_cache_ready(entry.game_dir):
			_start_game()
		else:
			_fail("import finished without a script cache")
		return
	var e := entry
	print("launcher: %s exited (pid=%d) after %.1f s" % [e.slug, pid, (Time.get_ticks_msec() - _started_ms) / 1000.0])
	state = State.IDLE
	pid = -1
	entry = {}
	finished.emit(e)
