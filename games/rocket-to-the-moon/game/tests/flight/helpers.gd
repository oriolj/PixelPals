extends GutTest
## Shared setup for screen tests: a throwaway root, scripted devices, a test
## album file, and helpers to drive a screen frame by frame.

const DT := 1.0 / 30.0
const Album := preload("res://scripts/logic/album.gd")
const TEST_ALBUM := "user://test_album_screens.json"

var root: Node2D
var _saved_root: Node
var _saved_album_path := ""


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.trip_scale = 1.0
	Game.new_trip()
	_saved_album_path = Game.album_path
	Game.album_path = TEST_ALBUM
	Game.album.clear()
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	Game.current = null


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.trip_scale = 1.0
	Game.album_path = _saved_album_path
	Game.album = Album.load_kinds(Game.album_path)
	if FileAccess.file_exists(TEST_ALBUM):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(TEST_ALBUM))
	Players.reset()
	Players.clear_scripted()


func seat(n: int) -> void:
	for i in n:
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]


## Seat exactly these seats (e.g. [0, 2] = Pilot + Launcher).
func seat_only(seats: Array) -> void:
	for s in seats:
		Players.join_seat("demo:%d" % s, s)
		Players.riders[s] = Game.roster[s]


func open(screen_name: String) -> Node:
	Game.goto(screen_name)
	var scr: Node = Game.current
	scr.set_process(false)
	if "rng" in scr:
		scr.rng.seed = 1
	if "spawns" in scr:
		scr.spawns = [] as Array[Dictionary]  # no timeline spawns unless a test asks
	return scr


func drive(device: String, state: Dictionary, scr: Node) -> void:
	Players.set_scripted(device, state)
	Players.poll()
	scr.step(DT)


func tap(device: String, button: String, scr: Node) -> void:
	drive(device, {button: true}, scr)
	drive(device, {}, scr)


func run(scr: Node, seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		Players.poll()
		scr.step(DT)
