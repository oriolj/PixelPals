extends Node
## Flow between screens, the buddy roster, hat colours, run results and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> zoo -> party -> select ...  ("gallery" is a demo-only
## contact sheet of every asset.)

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "zoo", "party", "gallery"]

## Seat aliases for this game (Players.Seat.DRIVER/GUNNER/HONKER).
const KEEPER := 0
const FEEDER := 1
const SINGER := 2

## Buddy animals a seat can pick (the same six live in the zoo).
const ROSTER: Array[String] = ["monkey", "penguin", "rabbit", "elephant", "giraffe", "seal"]
var roster: Array[String] = []

## Hat colours a seat can pick (no food colour among them).
const HATS: Array[Color] = [
	Color("#e84a5f"),  # red
	Color("#3d7be0"),  # blue
	Color("#8e6bd8"),  # purple
	Color("#ff7eb6"),  # pink
	Color("#2bb3a3"),  # teal
	Color("#f5f0e6"),  # white
]
## seat -> index into HATS
var hats: Array[int] = [1, 0, 4]

## Results of the last run (for the party screen).
var stars := 0
var meals := 0
## 0 = the default run length (Rules.RUN_SECONDS); the demo sets it shorter.
var run_seconds := 0.0
## Demo: animals that get hungry first (the scripted route needs them).
var first_hungry: Array[String] = []

## Demo mode: `godot -- --demo` or --demo=<screen>.
var demo := false
var demo_start := "join"
var quit_after := 0.0

var current: Node = null
var current_name := ""
var _root: Node


func _ready() -> void:
	roster.assign(ROSTER)
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
	return HATS[posmod(hats[seat], HATS.size())]


# ---------------------------------------------------------------- music ducking

## Local helper until shared sfx.gd has one: lowers the music under an animal
## voice so the voice is heard, then brings it back.
const MUSIC_DB := -8.0
const DUCK_DB := -22.0
var _duck_left := 0.0


func duck(seconds: float) -> void:
	_duck_left = maxf(_duck_left, seconds)


func _process(delta: float) -> void:
	var player: AudioStreamPlayer = Sfx.get("_music")
	if player == null:
		return
	var target := MUSIC_DB
	if _duck_left > 0.0:
		_duck_left -= delta
		target = DUCK_DB
	player.volume_db = move_toward(player.volume_db, target, delta * (60.0 if target < player.volume_db else 20.0))


## Plays an animal voice (a random variant) and ducks the music under it.
func voice(animal: String, pitch := 1.0) -> void:
	Sfx.play(animal, pitch, 2.0)
	duck(1.3)
