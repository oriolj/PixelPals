extends Node
## Flow between screens, the rider roster, the album and this run's photos.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> level -> album -> select ...
## The album is also reachable from join (the gunner's B) to browse it.

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "level", "album"]
const AlbumModel := preload("res://scripts/album.gd")

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
var roster: Array[String] = []

## The family album (persistent, user://album.json; the demo uses its own file).
const ALBUM_PATH := "user://album.json"
const DEMO_ALBUM_PATH := "user://album_demo.json"
var album: AlbumModel

## This run, for the album screen:
##   new      species ids photographed for the first time ever, in order
##   repeats  species id -> photos of an already known species this run
##   seen     species ids photographed this run (new or repeat), in order
##   bonus    bonus subject -> count ("bubble", "shell", "rock_smile", "starfish")
##   whale    true if the whale was photographed this run
var session := {}
## Run length override in seconds (0 = the normal 6 minutes). Demo and tests.
var run_seconds := 0.0
## True when the album screen was opened from join to browse (goes back to join).
var album_browse := false

## Demo mode: `godot -- --demo` or --demo=<screen>. Scripted input, used by
## `make shot` and `make demo` to show real gameplay with nobody at the controls.
var demo := false
var demo_start := "join"
## `-- --album=reset` (demo only): start the demo album empty.
var album_reset := false
## `-- --quit-after-seconds=N` for unattended captures.
var quit_after := 0.0

var current: Node = null
var current_name := ""
var _root: Node


func _ready() -> void:
	roster.assign(ORIGINAL_RIDERS)
	var private_path := "res://private_pack/riders.json"
	if FileAccess.file_exists(private_path):
		var extra = JSON.parse_string(FileAccess.get_file_as_string(private_path))
		if extra is Array:
			for r in extra:
				if not roster.has(str(r)):
					roster.append(str(r))
	for arg in OS.get_cmdline_user_args():
		if arg == "--demo":
			demo = true
		elif arg.begins_with("--demo="):
			demo = true
			demo_start = arg.substr(7)
		elif arg == "--album=reset":
			album_reset = true
		elif arg.begins_with("--quit-after-seconds="):
			quit_after = float(arg.substr(21))
		elif arg == "--mute":
			Sfx.muted = true
	# The family album is never touched by the demo (or the tests).
	album = AlbumModel.new(DEMO_ALBUM_PATH if demo or _running_tests() else ALBUM_PATH)
	album.load_file()
	if demo and album_reset:
		album.reset()
	new_session()
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


func _running_tests() -> bool:
	for arg in OS.get_cmdline_args():
		if "gut_cmdln" in arg:
			return true
	return false


func new_session() -> void:
	session = {"new": [], "repeats": {}, "seen": [], "bonus": {}, "whale": false}


## Called by main.gd once the tree is ready.
func boot(root: Node) -> void:
	_root = root
	if demo:
		var dm = load("res://scripts/demo_driver.gd").new()
		dm.name = "DemoDriver"
		root.add_child(dm)
		dm.start(demo_start)
	else:
		goto("join")


## Tests: point screens at a throwaway root (and restore with set_root(null)).
func set_root(root: Node) -> void:
	_root = root


func goto(screen_name: String) -> void:
	if _root == null:
		current_name = screen_name
		screen_changed.emit(screen_name)
		return
	if current and is_instance_valid(current):
		current.queue_free()
	var script: GDScript = load("res://scripts/screens/%s.gd" % screen_name)
	current = script.new()
	current.name = screen_name.capitalize()
	current_name = screen_name
	_root.add_child(current)
	screen_changed.emit(screen_name)


func rider_color(rider: String) -> Color:
	var palette := [Color("#3a4466"), Color("#e43b44"), Color("#f77622"), Color("#63c74d"), Color("#8b9bb4"),
		Color("#68386c"), Color("#124e89"), Color("#2ce8f5"), Color("#feae34"), Color("#265c42")]
	return palette[absi(rider.hash()) % palette.size()]
