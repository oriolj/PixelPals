extends Node2D
## Star particles: gem bursts, crash sparkles and the party's flying stars.

const Draw := preload("res://scripts/view/draw.gd")
const MAX := 400

var parts: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 12345


## A burst of n stars from pos.
func burst(pos: Vector2, col: Color, n := 10, speed := 120.0, size := 5.0) -> void:
	for i in n:
		var a := rng.randf() * TAU
		var v := Vector2(cos(a), sin(a)) * speed * rng.randf_range(0.5, 1.0) + Vector2(0, -40)
		_add({"p": pos, "v": v, "life": 0.0, "max": rng.randf_range(0.5, 0.9), "col": col,
			"r": size * rng.randf_range(0.7, 1.2), "rot": rng.randf() * TAU, "spin": rng.randf_range(-6, 6), "g": 160.0})


## One big star flying in an arc from `from` up over the stage.
func fly(from: Vector2, col: Color) -> void:
	var v := Vector2(rng.randf_range(-90, 90), rng.randf_range(-260, -200))
	_add({"p": from, "v": v, "life": 0.0, "max": 1.8, "col": col, "r": 12.0, "rot": 0.0,
		"spin": rng.randf_range(-3, 3), "g": 150.0})


func _add(p: Dictionary) -> void:
	if parts.size() >= MAX:
		parts.pop_front()
	parts.append(p)


func _process(delta: float) -> void:
	step(delta)


func step(delta: float) -> void:
	for i in range(parts.size() - 1, -1, -1):
		var p := parts[i]
		p.life += delta
		if p.life >= p.max:
			parts.remove_at(i)
			continue
		p.v.y += p.g * delta
		p.p += p.v * delta
		p.rot += p.spin * delta
	queue_redraw()


func _draw() -> void:
	for p in parts:
		var k: float = 1.0 - p.life / p.max
		var r: float = p.r * (0.4 + 0.6 * k)
		Draw.star(self, p.p, r + 1.5, Color(Draw.WHITE, k), p.rot)
		Draw.star(self, p.p, r, Color(p.col, minf(1.0, k * 1.5)), p.rot)
