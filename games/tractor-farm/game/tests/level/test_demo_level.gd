extends GutTest
## The demo driver playing a real level for two simulated minutes: rows get
## ploughed and sown with all four seeds, crops ripen, get harvested and
## reach the barn. This is the "whole season" check of M1.

const DemoDriver := preload("res://scripts/demo_driver.gd")
const FieldRules := preload("res://scripts/field_rules.gd")
const DT := 1.0 / 20.0

var root: Node2D
var _saved_root: Node
var dd


func before_each() -> void:
	Sfx.muted = true
	_saved_root = Game._root
	root = Node2D.new()
	add_child(root)
	Game._root = root
	dd = DemoDriver.new()
	root.add_child(dd)
	dd.set_process(false)


func after_each() -> void:
	if is_instance_valid(root):
		root.free()
	Game._root = _saved_root
	Game.current = null
	Game.current_name = ""
	Sfx.muted = false
	Players.reset()
	Players.clear_scripted()
	Game.run_limit = 360.0


func test_demo_plays_a_season() -> void:
	dd.start("level")
	var lv = Game.current
	lv.set_process(false)
	var t := 0.0
	var max_trailer := 0
	while t < 140.0 and is_instance_valid(lv) and lv.state == lv.State.RUN:
		dd.t = t
		dd.drive("level", t, DT)
		Players.poll()
		lv.step(DT)
		max_trailer = maxi(max_trailer, lv.field.trailer.size())
		t += DT
	var f = lv.field
	var ploughed: int = FieldRules.W * FieldRules.H - f.count(FieldRules.Tile.GRASS)
	assert_gt(ploughed, 80, "most of the field got ploughed")
	for c in 4:
		assert_gt(f.planted[c], 0, "crop %d was sown" % c)
	assert_gt(max_trailer, 5, "the trailer filled up")
	assert_gt(f.barn_total(), 10, "crops reached the barn")
