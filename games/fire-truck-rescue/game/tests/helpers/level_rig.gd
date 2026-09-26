extends RefCounted
## Shared set-up for level tests: seats N scripted devices, builds a level
## screen that the test steps by hand (set_process(false), auto_goto false).

const LevelScreen := preload("res://scripts/screens/level.gd")
const DEVICES: Array[String] = ["demo:0", "demo:1", "demo:2"]
const DT := 1.0 / 30.0


static func seat(n: int) -> void:
	Players.reset()
	Players.clear_scripted()
	for i in n:
		Players.set_scripted(DEVICES[i], {})
		Players.join(DEVICES[i])
	Players.riders = ["penguin", "monkey", "fox"]
	Players.poll()


static func make_level(test: GutTest) -> Node:
	var lvl: Node = LevelScreen.new()
	lvl.auto_goto = false
	test.add_child_autofree(lvl)
	lvl.set_process(false)
	lvl.hud.set_process(false)
	lvl.next_fire_t = 9999.0  # tests activate fires themselves
	return lvl


## One frame with these scripted states ({device: state}); others idle.
static func step(lvl: Node, states := {}, dt := DT) -> void:
	for d in DEVICES:
		Players.set_scripted(d, states.get(d, {}))
	Players.poll()
	lvl.step(dt)


static func run(lvl: Node, seconds: float, states := {}) -> void:
	var t := 0.0
	while t < seconds:
		step(lvl, states)
		t += DT


## Park the truck on a road cell, still, facing along the road; the camera follows.
static func park(lvl: Node, cell: Vector2i) -> void:
	var yaw: float = lvl._road_yaw(cell, Vector2.UP)
	lvl.truck.place(lvl.map.cell_center(cell), yaw)
	lvl.cam_yaw = yaw
	lvl.left_station = true


static func activate(lvl: Node, fire: int) -> void:
	lvl.fires[fire].activate()
	lvl.order_i = lvl.order.find(fire)


static func cleanup() -> void:
	Players.reset()
	Players.clear_scripted()
	Game.level_preset = ""
