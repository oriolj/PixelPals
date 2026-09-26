extends Node2D
## Developer contact sheet (not in the play flow): every crop stage at 1x
## and 2x, the ripe crops in silhouette, and every prop and animal.
## `make contact` captures it (`--demo=crops`).

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Crops := preload("res://scripts/draw/crop_art.gd")
const Farm := preload("res://scripts/draw/farm_art.gd")
const Painter := preload("res://scripts/draw/painter.gd")

var t := 0.0


func _ready() -> void:
	var bg := Painter.new(_bg)
	add_child(bg)
	# 1x: 4 rows (crops) x 4 columns (stages), on 64 px soil tiles.
	for c in 4:
		for st in 4:
			_crop(Vector2(40 + st * 72 + 32, 40 + c * 72 + 50), c, st, 1.0, false)
	# 2x: the same, stages 1..3 only (the seed is a mound).
	for c in 4:
		for st in range(1, 4):
			_crop(Vector2(360 + (st - 1) * 130 + 64, 20 + c * 150 + 128), c, st, 2.0, false)
	# Silhouettes of the ripe crops at 1x.
	for c in 4:
		_crop(Vector2(40 + c * 72 + 32, 380 + 50), c, 3, 1.0, true)
	# Props.
	_prop(Vector2(830, 140), _tractor)
	_prop(Vector2(990, 140), func(ci): Farm.planter(ci, 1, true, Players.SEAT_COLORS[1], t))
	_prop(Vector2(1150, 140), func(ci): Farm.trailer(ci, [0, 1, 2, 3, 0, 1, 2, 3, 3, 2, 1], t))
	for f in 3:
		var face := f
		_prop(Vector2(820 + f * 150, 250), func(ci): Farm.cloud(ci, face, false, t))
	var kinds := ["bunny", "pig", "hen", "duck", "frog"]
	for i in kinds.size():
		var k: String = kinds[i]
		_prop(Vector2(800 + i * 90, 370), func(ci): Farm.animal(ci, k, 0))
		_prop(Vector2(800 + i * 90, 440), func(ci): Farm.animal(ci, k, 1))
	_prop(Vector2(860, 690), func(ci): Farm.barn(ci, 0.0))
	for i in 4:
		var cr := i
		_prop(Vector2(990 + i * 52, 560), func(ci): Farm.crate(ci, cr, 3 + cr * 3))
	_prop(Vector2(1030, 690), func(ci): Farm.tree(ci, 100, t))
	_prop(Vector2(1180, 650), func(ci): Farm.pond(ci, 70, 26, t))
	_prop(Vector2(60, 560), func(ci): Farm.steering_wheel(ci, 30, Players.SEAT_COLORS[0]))
	_prop(Vector2(140, 560), func(ci): Farm.seed_bag(ci, Vector2.ZERO, 60, 0))
	_prop(Vector2(240, 560), func(ci): Farm.cloud(ci, 0, false, t))
	_prop(Vector2(80, 650), func(ci): Farm.pad_icon(ci, 60, P.CREAM))
	_prop(Vector2(170, 650), func(ci): Farm.kb_icon(ci, 60, P.CREAM))
	_prop(Vector2(330, 660), func(ci): Farm.sun(ci, 34, t, 0.0))
	_prop(Vector2(560, 700), func(ci): Farm.rainbow(ci, 150, 14, 0.9))
	for c in 4:
		var cc := c
		_prop(Vector2(420 + c * 60, 470), func(ci): Crops.icon(ci, cc, 40))


func _tractor(ci: CanvasItem) -> void:
	Farm.tractor(ci, t)
	Farm.tractor_front(ci, t)


func _crop(at: Vector2, crop: int, stage: int, k: float, silhouette: bool) -> void:
	var tile := Painter.new(func(ci): _soil(ci, k, stage))
	tile.position = at
	add_child(tile)
	var n := Painter.new(func(ci): Crops.draw(ci, crop, stage))
	n.position = at + Vector2(0, 18) * k
	n.scale = Vector2(k, k)
	if silhouette:
		n.modulate = Color(0, 0, 0)
	add_child(n)


func _soil(ci: CanvasItem, k: float, stage: int) -> void:
	var r := Rect2(Vector2(-32, -32) * k, Vector2(64, 64) * k)
	ci.draw_rect(r, P.SOIL)
	for i in 3:
		S.line(ci, Vector2(-28, -18 + i * 18) * k, Vector2(28, -18 + i * 18) * k, P.FURROW, 4.0 * k)


func _prop(at: Vector2, fn: Callable) -> void:
	var n := Painter.new(fn)
	n.position = at
	add_child(n)


func _bg(ci: CanvasItem) -> void:
	ci.draw_rect(Rect2(0, 0, 1280, 720), P.GRASS_LIGHT.lerp(P.CREAM, 0.6))


func _process(delta: float) -> void:
	t += delta
	for c in get_children():
		c.queue_redraw()
