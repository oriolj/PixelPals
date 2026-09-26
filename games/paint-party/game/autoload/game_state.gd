extends Node
## Flow between screens, the rider roster, where paintings are saved, and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> paint -> party -> select ...

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "paint", "party"]
const W := 640
const H := 360

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
var roster: Array[String] = []

## Where paintings go. `paint-<UTC>.png` = framed, `wip-<UTC>.png` = autosave
## of the picture in progress. Tests and demo runs point this elsewhere.
var paint_dir := "user://paintings"
## A copy of every framed picture lands here ("" = no copy). Defaults to
## ~/Pictures/PaintParty; demo runs and tests turn it off.
var pictures_dir := ""
## Demo runs also drop the framed painting here as painting.png ("" = off).
var shot_dir := ""

## The last framed picture (for the party screen). Null when none.
var last_painting: Image = null
var last_painting_path := ""

## Pause-menu option for 1-2 seats: a surprise splat every 20 s.
var surprise_splats := false

## Demo mode: `godot -- --demo` or --demo=<screen>.
var demo := false
var demo_start := "join"
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
	pictures_dir = default_pictures_dir()
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
		elif arg.begins_with("--save-dir="):
			paint_dir = arg.substr(11)
		elif arg.begins_with("--shot-dir="):
			shot_dir = arg.substr(11)
	if demo:
		pictures_dir = ""  # a demo never writes into the family's Pictures
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


static func default_pictures_dir() -> String:
	var pics := OS.get_system_dir(OS.SYSTEM_DIR_PICTURES)
	if pics == "":
		pics = OS.get_environment("HOME").path_join("Pictures")
	return pics.path_join("PaintParty")


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


## Framed paintings in paint_dir, newest first (file names sort by UTC stamp).
func gallery(limit := 3) -> Array[String]:
	var out: Array[String] = []
	var d := DirAccess.open(paint_dir)
	if d == null:
		return out
	var names: Array[String] = []
	for f in d.get_files():
		if f.begins_with("paint-") and f.ends_with(".png"):
			names.append(f)
	names.sort()
	names.reverse()
	for i in mini(limit, names.size()):
		out.append(paint_dir.path_join(names[i]))
	return out


## Loads a PNG from disk by bytes (works for user://, absolute paths and a fresh clone).
static func load_png(path: String) -> Image:
	if not FileAccess.file_exists(path):
		return null
	var img := Image.new()
	if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
		return null
	return img


func rider_color(rider: String) -> Color:
	var palette := [Color("#333c57"), Color("#b13e53"), Color("#ef7d57"), Color("#38b764"), Color("#94b0c2"),
		Color("#5d275d"), Color("#29366f"), Color("#73eff7"), Color("#ffcd75"), Color("#257179")]
	return palette[absi(rider.hash()) % palette.size()]
