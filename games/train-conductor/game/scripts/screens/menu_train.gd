extends Node2D
## The toy train standing on a straight piece of track, for the menus: the
## real TrainView (so riders sit in the cab and on the tender exactly as in
## the level), puffing steam, with its wheels turning slowly in place.

const Palette := preload("res://scripts/palette.gd")
const Train := preload("res://scripts/track/train.gd")
const TrainView := preload("res://scripts/level/train_view.gd")
const FxView := preload("res://scripts/level/fx_view.gd")

var sim
var view: Node2D
var fx: Node2D
var holder: Node2D
var nose_at := Vector2.ZERO
var time := 0.0
var track_scale := 1.0


## A single long straight edge: all the track a standing train needs.
class StraightTrack extends RefCounted:
	var lengths: Array[float] = [4000.0]
	var edge_from: Array[int] = [0]
	var edge_to: Array[int] = [0]
	var in_edges: Array = [[0]]

	func sample(_e: int, d: float) -> Vector2:
		return Vector2(d, 0)

	func tangent(_e: int, _d: float) -> Vector2:
		return Vector2.RIGHT


## What TrainView reads from a Sim.
class Standing extends RefCounted:
	var train
	var wobble := 0.0


## Put the train's nose at `screen_nose` with `cars` carriages, drawn at `size`.
func setup(screen_nose: Vector2, rider_ids: Array[String], cars := 1, size := 1.0) -> void:
	nose_at = screen_nose
	track_scale = size
	sim = Standing.new()
	sim.train = Train.new(StraightTrack.new(), 0, 3000.0)
	var t = sim.train
	t.cars = cars
	holder = Node2D.new()
	holder.scale = Vector2(size, size)
	add_child(holder)
	view = TrainView.new()
	holder.add_child(view)
	view.setup(sim, rider_ids)
	fx = FxView.new()
	holder.add_child(fx)
	holder.position = screen_nose - t.nose_position() * size


func toot() -> void:
	view.toot = 0.6
	fx.ring(view.chimney_position())


func _process(delta: float) -> void:
	time += delta
	sim.train.odometer += delta * 40.0
	fx.chimney(view.chimney_position(), 60.0)
	queue_redraw()


func _draw() -> void:
	var y := nose_at.y
	var k := track_scale
	draw_rect(Rect2(0, y - 29 * k, 1280, 58 * k), Palette.INK)
	draw_rect(Rect2(0, y - 24 * k, 1280, 48 * k), Palette.TRACK)
	var x := 0.0
	while x < 1280.0:
		draw_line(Vector2(x, y - 20 * k), Vector2(x, y + 20 * k), Palette.TRACK.darkened(0.12), 4.0 * k)
		x += 24.0 * k
	for off in [-11.0, 11.0]:
		draw_line(Vector2(0, y + off * k), Vector2(1280, y + off * k), Palette.GROOVE, 6.0 * k)
