extends Node
## Flow between screens, the rider roster, trip results, the album and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> launch -> flight -> party -> select ...

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "launch", "flight", "party"]
const Album := preload("res://scripts/logic/album.gd")

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
## Original riders plus the private pack's (res://private_pack/riders.json).
var roster: Array[String] = []

## Results of the last trip (for the party screen).
var fuel := 0
## Planet kinds (1..8) found on the last trip.
var trip_planets: Array[int] = []
## Planet kinds found on any trip, kept in album_path across runs.
var album: Array[int] = []
var album_path := "user://album.json"

## Multiplies every stage length (1.0 = the real ~5 minute trip). The demo
## driver shortens it so one capture reaches the Moon.
var trip_scale := 1.0

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
	if demo:
		# The demo never touches the family's real album.
		album_path = "user://album_demo.json"
	album = Album.load_kinds(album_path)
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


## A planet kind was found: remember it for this trip and in the album (saved now,
## so quitting mid-trip keeps it).
func found_planet(kind: int) -> bool:
	if not trip_planets.has(kind):
		trip_planets.append(kind)
	if album.has(kind):
		return false
	album.append(kind)
	album.sort()
	Album.save_kinds(album_path, album)
	return true


## Start of a new trip: clear the per-trip results.
func new_trip() -> void:
	fuel = 0
	trip_planets.clear()


func rider_color(rider: String) -> Color:
	# Placeholder tint per rider until real art exists.
	var palette := [Color("#333c57"), Color("#b13e53"), Color("#ef7d57"), Color("#38b764"), Color("#94b0c2"),
		Color("#5d275d"), Color("#29366f"), Color("#73eff7"), Color("#ffcd75"), Color("#257179")]
	return palette[absi(rider.hash()) % palette.size()]


## The seat that owns the big launch button: the Launcher, else the Grabber,
## else the Pilot (the fold-down for 2 and 1 seats).
func press_seat() -> int:
	for s in [Players.Seat.HONKER, Players.Seat.GUNNER, Players.Seat.DRIVER]:
		if Players.is_seated(s):
			return s
	return Players.Seat.DRIVER


## True when the press seat pressed its launch button this frame. The Launcher
## uses any button; a Grabber or Pilot standing in uses "a".
func launch_pressed() -> bool:
	var s := press_seat()
	if s == Players.Seat.HONKER:
		return Players.just_pressed(s, "any")
	return Players.just_pressed(s, "a")
