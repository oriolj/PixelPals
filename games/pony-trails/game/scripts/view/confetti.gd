extends Node2D
## Confetti (the `confetti` sprite, one colour per frame) in whole pixels:
## a steady fall (rate > 0) and bursts that pop from a point.

const Tex := preload("res://scripts/view/tex.gd")

var bits: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var rate := 0.0
var _acc := 0.0
var _tex: Array[Texture2D] = []


func _ready() -> void:
	rng.seed = 5
	z_index = 60
	for i in Tex.frame_count("confetti"):
		_tex.append(Tex.frame("confetti", i, Color("#feae34"), Vector2i(4, 4)))


func burst(at: Vector2, n := 24) -> void:
	for i in n:
		var a := rng.randf_range(-PI * 0.95, -PI * 0.05)
		var sp := rng.randf_range(40, 110)
		bits.append({"pos": at, "v": Vector2(cos(a), sin(a)) * sp, "ph": rng.randf() * TAU,
			"f": rng.randi() % maxi(1, _tex.size()), "life": 2.5})


func tick(dt: float) -> void:
	_acc += dt * rate
	while _acc >= 1.0:
		_acc -= 1.0
		bits.append({"pos": Vector2(rng.randf_range(0, 320), -4), "v": Vector2(0, rng.randf_range(20, 45)),
			"ph": rng.randf() * TAU, "f": rng.randi() % maxi(1, _tex.size()), "life": 12.0})
	for b in bits:
		b.v.y = minf(b.v.y + 90.0 * dt, 45.0) if b.v.y > 0 or b.life < 12.0 else b.v.y
		b.v.x *= 1.0 - 1.5 * dt
		b.pos += b.v * dt
		b.ph += dt * 3.0
		b.life -= dt
	bits = bits.filter(func(b): return b.pos.y < 184 and b.life > 0.0)
	queue_redraw()


func _draw() -> void:
	if _tex.is_empty():
		return
	for b in bits:
		var p := Vector2(roundf(b.pos.x + sin(b.ph) * 3.0), roundf(b.pos.y))
		draw_texture(_tex[b.f], p)
