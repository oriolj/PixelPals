extends Node2D
## Falling confetti (the `confetti` sprite, one colour per frame), whole pixels.

const Tex := preload("res://scripts/view/tex.gd")

var bits: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var rate := 30.0
var _acc := 0.0
var _tex: Array[Texture2D] = []


func _ready() -> void:
	rng.seed = 5
	for i in Tex.frame_count("confetti"):
		_tex.append(Tex.frame("confetti", i, Color("#feae34"), Vector2i(4, 4)))


func tick(dt: float) -> void:
	_acc += dt * rate
	while _acc >= 1.0:
		_acc -= 1.0
		bits.append({"pos": Vector2(rng.randf_range(0, 320), -4), "vy": rng.randf_range(20, 45),
			"ph": rng.randf() * TAU, "f": rng.randi() % maxi(1, _tex.size())})
	for b in bits:
		b.pos.y += b.vy * dt
		b.ph += dt * 3.0
	bits = bits.filter(func(b): return b.pos.y < 184)
	queue_redraw()


func _draw() -> void:
	for b in bits:
		var p := Vector2(roundf(b.pos.x + sin(b.ph) * 4.0), roundf(b.pos.y))
		draw_texture(_tex[b.f], p)
