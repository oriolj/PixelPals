extends GutTest
## Shared setup for stage tests: a throwaway root, scripted seats, a clean
## mission, a fake camera, and helpers to drive a screen frame by frame.

const DT := 1.0 / 30.0

var root: Node2D
var _saved_root: Node


func before_each() -> void:
	Players.reset()
	Players.clear_scripted()
	Players.poll()
	Game.mission_scale = 1.0
	Game.start_stage = 0
	Game.new_mission()
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	Game.current = null


func after_each() -> void:
	if is_instance_valid(Game.current):
		Game.current.free()
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Game.mission_scale = 1.0
	Game.new_mission()
	Players.reset()
	Players.clear_scripted()


## Seats 0..n-1 with scripted devices demo:0.. and riders.
func seat(n: int) -> void:
	for i in n:
		Players.join("demo:%d" % i)
		Players.riders[i] = Game.roster[i]


## Seat exactly these seats (e.g. [0, 2] = Pilot + Camera).
func seat_only(seats: Array) -> void:
	for s in seats:
		Players.join_seat("demo:%d" % s, s)
		Players.riders[s] = Game.roster[s]


static func fake_view() -> Image:
	var img := Image.create(320, 180, false, Image.FORMAT_RGBA8)
	img.fill(Color("#124e89"))
	img.fill_rect(Rect2i(0, 130, 320, 50), Color("#63c74d"))
	return img


func open(screen_name: String) -> Node:
	Game.goto(screen_name)
	var scr: Node = Game.current
	scr.set_process(false)
	scr.auto_goto = false
	if "capture_source" in scr:
		scr.capture_source = fake_view
	return scr


## Sets every listed device's state (others released), polls, steps once.
func drive(states: Dictionary, scr: Node) -> void:
	for i in 3:
		var d := "demo:%d" % i
		Players.set_scripted(d, states.get(d, {}))
	Players.poll()
	scr.step(DT)


func tap(device: String, button: String, scr: Node) -> void:
	drive({device: {button: true}}, scr)
	drive({}, scr)


## Steps with nobody touching anything.
func run(scr: Node, seconds: float) -> void:
	for i in int(ceil(seconds / DT)):
		drive({}, scr)


## Steps until cond() is true or `limit` seconds pass; returns the seconds taken (INF if never).
func run_until(scr: Node, cond: Callable, limit: float, states := {}) -> float:
	var t := 0.0
	while t < limit:
		drive(states, scr)
		t += DT
		if cond.call():
			return t
		if scr.next_screen != "":
			return t if cond.call() else INF
	return INF
