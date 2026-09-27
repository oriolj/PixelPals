extends Node
## Flow between screens, the rider roster and hats, the house and cat data,
## the day's rounds and finds, demo flags, the real-meow hook and the save.
##
## Screens are scripts in res://scripts/screens/<name>.gd extending Node2D
## (built in code, no .tscn). Flow: join -> select -> house -> party -> select.

signal screen_changed(screen_name: String)

const SCREENS := ["join", "select", "house", "party"]
const HouseData := preload("res://scripts/house/house_data.gd")
const CatData := preload("res://scripts/house/cat_data.gd")
const Save := preload("res://scripts/save.gd")

## Seat aliases (the shared enum says DRIVER/GUNNER/HONKER).
const WALKER := 0   # adult: walks, opens, carries
const LASER := 1    # 5-year-old: the red dot
const TREATS := 2   # 2-year-old: the treat bag

## The parts of one day; each is a round. The last is the night round.
const DAY: Array[String] = ["morning", "afternoon", "evening", "night"]

const HOUSE_PATH := "res://data/house.json"
const CATS_PATH := "res://data/cats.json"
## Real recordings (never committed): meow_<cat>_*.wav here replace the synth.
const REAL_AUDIO_DIR := "res://audio/real"
const SAVE_PATH := "user://greyssie_and_kira.json"
const SAVE_VERSION := 1

const ORIGINAL_RIDERS := ["penguin", "monkey", "fox", "frog", "robot"]
## Hat colours for the laser and treat seats (Sweetie 16).
const HATS: Array[Color] = [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#38b764"),
	Color("#41a6f6"), Color("#73eff7"), Color("#5d275d"), Color("#f4f4f4")]

var roster: Array[String] = []
## seat -> index into HATS
var hats: Array[int] = [0, 2, 3]

## Data (reload with load_data(); tests point these at fixtures).
var house_path := HOUSE_PATH
var cats_path := CATS_PATH
var house: RefCounted
var cat_data: RefCounted

## The day in progress: which round (index into DAY) and what was found.
var round_index := 0
## [{"cat", "kind", "spot", "round"}] in find order, for the party photo strip.
var finds: Array[Dictionary] = []
## Stars (one per finished round).
var stars := 0
## First round of the next house screen (the night demo starts at 3).
var start_round := 0
## Scale for the game's timers (demo only shortens intros; never the 60/90 s rules).
var days_played := 0

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
	load_data()
	install_real_voices()
	var saved := Save.load_json(SAVE_PATH, SAVE_VERSION, {"days_played": 0})
	days_played = int(saved.get("days_played", 0))
	if quit_after > 0.0:
		get_tree().create_timer(quit_after).timeout.connect(get_tree().quit)


## (Re)reads the house and the cats. Returns the combined errors (empty = OK).
func load_data(house_file := "", cats_file := "") -> Array[String]:
	if house_file != "":
		house_path = house_file
	if cats_file != "":
		cats_path = cats_file
	house = HouseData.from_file(house_path)
	cat_data = CatData.from_file(cats_path)
	var errs: Array[String] = []
	errs.append_array(house.errors)
	errs.append_array(cat_data.errors)
	for e in errs:
		push_warning("data: " + e)
	return errs


## Real meow recordings: every res://audio/real/meow_<cat>_*.wav replaces
## the synthesized meow_<cat>_N voices (Sfx picks one at random per meow).
## Returns {cat id: number of recordings}.
func install_real_voices(dir_path := REAL_AUDIO_DIR) -> Dictionary:
	var out := {}
	var abs := ProjectSettings.globalize_path(dir_path)
	var dir := DirAccess.open(abs)
	if dir == null:
		return out
	var files := Array(dir.get_files())
	files.sort()
	for id in cat_data.ids():
		var streams := []
		for f in files:
			if f.begins_with("meow_%s_" % id) and f.ends_with(".wav"):
				var s := AudioStreamWAV.load_from_file(abs.path_join(f))
				if s:
					streams.append(s)
		if not streams.is_empty():
			Sfx._streams["meow_" + id] = streams
			out[id] = streams.size()
	return out


## A fresh day: round 0 (or start_round), no finds.
func new_day() -> void:
	round_index = start_round
	start_round = 0
	finds.clear()
	stars = 0


func day_part() -> String:
	return DAY[clampi(round_index, 0, DAY.size() - 1)]


func is_night() -> bool:
	return round_index >= DAY.size() - 1


## Called by the house when the night round ends.
func finish_day() -> void:
	days_played += 1
	Save.save_json(SAVE_PATH, SAVE_VERSION, {"days_played": days_played})


func hat_color(seat: int) -> Color:
	return HATS[posmod(hats[seat], HATS.size())]


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
	var palette := [Color("#333c57"), Color("#b13e53"), Color("#ef7d57"), Color("#38b764"), Color("#94b0c2"),
		Color("#5d275d"), Color("#29366f"), Color("#73eff7"), Color("#ffcd75"), Color("#257179")]
	return palette[absi(rider.hash()) % palette.size()]
