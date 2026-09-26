extends Node
## Flow between screens, the rider roster, the run's results and demo mode.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Game.goto("join") swaps the current screen.
## Flow: join -> select -> level -> party -> select ...
## "crops" is a developer screen (the crop contact sheet), outside the flow.

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "level", "party"]
## Extra demo starts: "finale" is the level with a full barn, "crops" the
## contact sheet.
const DEMO_STARTS := ["join", "select", "level", "finale", "party", "crops"]

## Original cast: committed, shippable (the PixelPals riders).
const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
var roster: Array[String] = []

## Results of the last run, for the party: crops per crate (carrot, pumpkin,
## sunflower, strawberry) and the giant vegetable's crop.
var barn: Array[int] = [0, 0, 0, 0]
var giant_crop := 0
var run_seconds := 0.0
## "" for a normal level; "finale" starts the level at its end (demo, tests).
var level_preset := ""
## Seconds of play before the level ends by time (FieldRules.END_SECONDS,
## shortened by the demo so a join->party demo loop stays watchable).
var run_limit := 360.0

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


func barn_total() -> int:
	var n := 0
	for v in barn:
		n += v
	return n


## A pixel-art rider sprite, nearest-filtered so it stays crisp on the
## smooth vector canvas, `k` times its 16 px size.
func rider_sprite(rider: String, k := 3.0) -> AnimatedSprite2D:
	var s := Art.sprite(rider, rider_color(rider), Vector2i(16, 16))
	s.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	s.scale = Vector2(k, k)
	return s


func rider_color(rider: String) -> Color:
	var palette := [Color("#333c57"), Color("#b13e53"), Color("#ef7d57"), Color("#38b764"), Color("#94b0c2"),
		Color("#5d275d"), Color("#29366f"), Color("#73eff7"), Color("#ffcd75"), Color("#257179")]
	return palette[absi(rider.hash()) % palette.size()]
