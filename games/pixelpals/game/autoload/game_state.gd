extends Node
## Flow between screens, the rider roster, run results and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> level -> party -> select ...

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "level", "party"]

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
## Private pack (gitignored, res://private_pack/riders.json lists ids).
var roster: Array[String] = []

## Stars collected in the last run (for the party screen).
var stars := 0
var run_seconds := 0.0

## Demo mode: `godot -- --demo` or --demo=<screen>. Scripted input, used by
## `make shot` and `make demo` to show real gameplay with nobody at the controls.
var demo := false
var demo_start := "join"
## `-- --quit-after-seconds=N` for unattended captures.
var quit_after := 0.0

var current: Node = null
var current_name := ""


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
		elif arg.begins_with("--quit-after-seconds="):
			quit_after = float(arg.substr(21))
		elif arg == "--mute":
			Sfx.muted = true
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


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


var _root: Node


## Tests: point screens at a throwaway root (and restore with set_root(null)).
func set_root(root: Node) -> void:
	_root = root


func goto(screen_name: String) -> void:
	if _root == null:
		# No tree to show it in (unit tests that only check the requested screen).
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
	# Placeholder tint per rider until real art exists.
	var palette := [Color("#333c57"), Color("#b13e53"), Color("#ef7d57"), Color("#38b764"), Color("#94b0c2"),
		Color("#5d275d"), Color("#29366f"), Color("#73eff7"), Color("#ffcd75"), Color("#257179")]
	return palette[absi(rider.hash()) % palette.size()]
