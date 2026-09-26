extends Node2D
## Night lights and fireworks. Lives on a CanvasLayer that follows the
## camera but sits outside the world's CanvasModulate, so the lit windows,
## the engine's lamp and the fireworks stay bright when night falls.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")

const FIREWORK_COLOURS: Array[Color] = [Color("#e43b44"), Color("#3978a8"), Color("#feae34"), Color("#3e8948"),
	Color("#fff7e8"), Color("#f5a6c8")]

var stations  # StationView
var train_view  # TrainView
var night := 0.0
var time := 0.0
## {pos, age, colour, n}
var bursts: Array[Dictionary] = []


func setup(station_view, train_v) -> void:
	stations = station_view
	train_view = train_v


func firework(at: Vector2, colour := Color()) -> void:
	if colour == Color():
		colour = FIREWORK_COLOURS[randi() % FIREWORK_COLOURS.size()]
	bursts.append({"pos": at, "age": 0.0, "colour": colour, "n": 18})


func _process(delta: float) -> void:
	time += delta
	for i in range(bursts.size() - 1, -1, -1):
		bursts[i].age += delta
		if bursts[i].age > 1.6:
			bursts.remove_at(i)
	queue_redraw()


func _draw() -> void:
	if night > 0.01:
		for s in stations.track.stations.size():
			for i in stations.HOUSES:
				var h: Vector2 = stations.house_pos(s, i)
				var w := h + Vector2(-6, 1) * 1.3
				var flicker := 0.9 + 0.1 * sin(time * 7.0 + i * 3.0 + s)
				draw_circle(w, 34.0 * flicker, Color(Palette.GLOW, 0.22 * night))
				draw_circle(w, 16.0, Color(Palette.GLOW, 0.45 * night))
				draw_rect(Rect2(w - Vector2(6.5, 5.8), Vector2(13, 11.7)), Color(Palette.GLOW, night))
			var b: Vector2 = stations.building_pos(s)
			draw_circle(b, 90.0, Color(Palette.GLOW, 0.12 * night))
		# The engine's lamp.
		var nose: Vector2 = train_view.nose_position()
		draw_circle(nose, 30.0, Color(Palette.GLOW, 0.5 * night))
		draw_circle(nose, 70.0, Color(Palette.GLOW, 0.18 * night))
	for b in bursts:
		var k: float = b.age / 1.6
		var a := 1.0 - k * k
		var r: float = 20.0 + 170.0 * (1.0 - pow(1.0 - minf(k * 1.6, 1.0), 3.0))
		for i in b.n:
			var ang: float = TAU * i / b.n
			var p: Vector2 = b.pos + Vector2.from_angle(ang) * r + Vector2(0, 60.0 * k * k)
			draw_circle(p, 7.0 * a + 2.0, Color(b.colour, a))
			draw_circle(p, 3.0, Color(Palette.WHITE, a))
		if k < 0.2:
			draw_circle(b.pos, 40.0 * (1.0 - k * 5.0), Color(Palette.WHITE, 0.8))
