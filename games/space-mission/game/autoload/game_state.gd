extends Node
## Flow between screens, the rider roster, the mission's results and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> orbit -> landing -> mars -> party -> select ...
## The select screen can start the mission at any stage (Game.start_stage).

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "orbit", "landing", "mars", "party"]
## Stage index (the select screen's planet row) -> screen.
const STAGES := ["orbit", "landing", "mars"]

## Original cast: committed, shippable.
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
## Original riders plus the private pack's (res://private_pack/riders.json).
var roster: Array[String] = []

## The stage the next mission starts at (0 orbit, 1 landing, 2 mars).
var start_stage := 0

## Mission results, for the party screen. Photos live in memory only.
var photos: Array[Dictionary] = []   # {"tex": Texture2D, "golden": bool}
var modules: Array[String] = []      # station modules fitted, in order
var docked := false
var sunrises := 0
var site := ""                       # landing site picked: dunes|crater|ice|rocks
var samples: Array[String] = []      # rock kinds drilled: red|grey|white|ice|shell
var phoned_home := false

## Multiplies the stage lengths (1.0 = the real ~9 minute mission). The demo
## driver shortens it so each capture reaches its stage's end.
var mission_scale := 1.0

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


## The screen of the stage after `screen_name` (the party after Mars).
static func next_after(screen_name: String) -> String:
	var i := STAGES.find(screen_name)
	if i == -1 or i == STAGES.size() - 1:
		return "party"
	return STAGES[i + 1]


func start_screen() -> String:
	return STAGES[clampi(start_stage, 0, STAGES.size() - 1)]


## A new mission: clear the results.
func new_mission() -> void:
	for p in photos:
		p.tex = null
	photos.clear()
	modules.clear()
	docked = false
	sunrises = 0
	site = ""
	samples.clear()
	phoned_home = false


func rider_of(seat: int) -> String:
	var r: String = Players.riders[seat]
	if r == "" or not roster.has(r):
		r = roster[seat % roster.size()]
	return r


func rider_color(rider: String) -> Color:
	# Placeholder tint per rider until real art exists.
	var palette := [Color("#3a4466"), Color("#be4a2f"), Color("#f77622"), Color("#63c74d"), Color("#8b9bb4"),
		Color("#68386c"), Color("#124e89"), Color("#2ce8f5"), Color("#feae34"), Color("#265c42")]
	return palette[absi(rider.hash()) % palette.size()]


# ---------------------------------------------------------------- seat fall-backs

## True when the Camera seat (the toddler) pressed this frame. With no Camera
## seat, the Pilot's B stands in (2 seats), and when the Pilot plays alone
## their A does as well.
func camera_pressed() -> bool:
	if Players.is_seated(Players.Seat.HONKER):
		return Players.just_pressed(Players.Seat.HONKER, "any")
	if Players.just_pressed(Players.Seat.DRIVER, "b"):
		return true
	return Players.seated_count() == 1 and Players.just_pressed(Players.Seat.DRIVER, "a")


## The arm (and every Arm-seat choice) runs itself when nobody holds it.
func arm_auto() -> bool:
	return not Players.is_seated(Players.Seat.GUNNER)
