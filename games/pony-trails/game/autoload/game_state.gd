extends Node
## Flow between screens, the rider roster, the horses' coats, the day's
## results, the persistent rosette wall and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> stable -> trail -> show -> party -> select ...
## The select screen can start the day at any stage (Game.start_stage).

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "stable", "trail", "show", "party"]
## Stage index (the select screen's stage row) -> screen.
const STAGES := ["stable", "trail", "show"]

const MARE_COATS: Array[String] = ["bay", "chestnut", "palomino", "grey", "black", "pinto"]
const FOAL_COATS: Array[String] = ["bay", "chestnut", "palomino", "grey", "black", "pinto", "appaloosa"]
## The braid ribbons, in the order of the 4 directions: up, right, down, left.
const RIBBONS: Array[String] = ["red", "blue", "yellow", "purple"]
const ROSETTES: Array[String] = ["blue", "red", "yellow", "green", "purple"]

const RosetteWall := preload("res://scripts/logic/rosette_wall.gd")
const WALL_PATH := "user://rosette_wall.json"
const DEMO_WALL_PATH := "user://rosette_wall_demo.json"
const TEST_WALL_PATH := "user://test_rosette_wall.json"

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
var roster: Array[String] = []

var start_stage := 0
var mare_coat := "bay"
var foal_coat := "palomino"

## The day so far (for the show's rosettes and the party).
##   ribbon       braid ribbon index into RIBBONS (-1 = none yet)
##   carrots      carrots given in the stable
##   apples, flowers, lucky   picked up by the foal on the trail
##   clean_jumps  the mare's clean jumps (trail and show)
##   foal_jumps   the foal's hops over its mini jumps
##   rosettes     [{"who": "mare"|"foal"|"rider0".., "colour": String}]
var day := {}

## The persistent rosette wall (the demo and the tests use their own files).
var wall: RosetteWall

## Multiplies the stage lengths (1.0 = the real ~8 minute day). The demo
## driver shortens it so each capture reaches its stage's end.
var day_scale := 1.0

## Demo mode: `godot -- --demo` or --demo=<screen>. Scripted input, used by
## `make shot` and `make demo` to show real gameplay with nobody at the controls.
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
	# The family wall is never touched by the demo or the tests.
	var path := WALL_PATH
	if running_tests():
		path = TEST_WALL_PATH
	elif demo:
		path = DEMO_WALL_PATH
	wall = RosetteWall.new(path)
	wall.load_file()
	new_day()
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


static func running_tests() -> bool:
	for arg in OS.get_cmdline_args():
		if "gut_cmdln" in arg:
			return true
	return false


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
	if demo:
		print("demo screen: %s at frame %d" % [screen_name, Engine.get_process_frames()])
	screen_changed.emit(screen_name)


## The screen after `screen_name` in the day (the party after the show).
static func next_after(screen_name: String) -> String:
	var i := STAGES.find(screen_name)
	if i == -1 or i == STAGES.size() - 1:
		return "party"
	return STAGES[i + 1]


func start_screen() -> String:
	return STAGES[clampi(start_stage, 0, STAGES.size() - 1)]


func new_day() -> void:
	day = {"ribbon": -1, "carrots": 0, "apples": 0, "flowers": 0, "lucky": 0,
		"clean_jumps": 0, "foal_jumps": 0, "rosettes": [], "saved": false}


func ribbon_name() -> String:
	var i := int(day.get("ribbon", -1))
	return RIBBONS[i] if i >= 0 and i < RIBBONS.size() else ""


func rider_of(seat: int) -> String:
	var r: String = Players.riders[seat]
	if r == "" or not roster.has(r):
		r = roster[seat % roster.size()]
	return r


## The rider in a riding helmet in the seat's colour.
func jockey_of(seat: int) -> String:
	return "jockey_%s_%d" % [rider_of(seat), seat]


func rider_color(rider: String) -> Color:
	var palette := [Color("#3a4466"), Color("#be4a2f"), Color("#f77622"), Color("#63c74d"), Color("#8b9bb4"),
		Color("#68386c"), Color("#124e89"), Color("#2ce8f5"), Color("#feae34"), Color("#265c42")]
	return palette[absi(rider.hash()) % palette.size()]


## Placeholder tint of a coat (used only while the art is missing).
static func coat_color(coat: String) -> Color:
	match coat:
		"bay": return Color("#733e39")
		"chestnut": return Color("#be4a2f")
		"palomino": return Color("#e4a672")
		"grey": return Color("#c0cbdc")
		"black": return Color("#3e2731")
		"pinto": return Color("#ead4aa")
		"appaloosa": return Color("#ffffff")
	return Color.MAGENTA


# ---------------------------------------------------------------- seat fall-backs

func has_toddler() -> bool:
	return Players.is_seated(Players.Seat.HONKER)


## True when the Neigh seat (the toddler) pressed this frame. With no Neigh
## seat, the Rider's B neighs instead.
func neigh_pressed() -> bool:
	if Players.is_seated(Players.Seat.HONKER):
		return Players.just_pressed(Players.Seat.HONKER, "any")
	return Players.just_pressed(Players.Seat.DRIVER, "b")


## The brush and the foal run themselves when nobody holds the Foal seat.
func foal_auto() -> bool:
	return not Players.is_seated(Players.Seat.GUNNER)
