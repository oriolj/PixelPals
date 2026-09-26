extends Node
## Flow between screens, the chef roster, the round's plates and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> kitchen -> party -> select ...
## `gallery` is a review screen (every asset and state), reached only by
## `-- --demo=gallery` (make shot SHOT_SCREEN=gallery).

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "kitchen", "party", "gallery"]

## Animal chefs a seat can pick (drawn by vector_art.gd).
const CHEFS: Array[String] = ["bunny", "pig", "mouse", "fox", "duck"]
var roster: Array[String] = []
## seat -> index into Palette.HATS
var hats: Array[int] = [0, 1, 2]

## The last round, for the party: {"animal", "stack", "toppings", "joy"}.
var plates: Array[Dictionary] = []
## Customers per round and the round's time limit (the demo shortens both).
var round_customers := 6
var round_limit := 420.0

## Demo mode: `godot -- --demo` or --demo=<screen>. Scripted input, used by
## `make shot` and `make demo` to show real gameplay with nobody at the controls.
var demo := false
var demo_start := "join"
## `-- --quit-after-seconds=N` for unattended captures.
var quit_after := 0.0

var current: Node = null
var current_name := ""
var _root: Node


func _ready() -> void:
	roster.assign(CHEFS)
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


func hat_color(seat: int) -> Color:
	var hats_pal: Array[Color] = preload("res://scripts/kitchen/palette.gd").HATS
	return hats_pal[posmod(hats[seat], hats_pal.size())]
