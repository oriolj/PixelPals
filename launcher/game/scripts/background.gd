extends Control
## The animated night sky behind the carousel: a dusk gradient, twinkling
## stars, a glowing moon, drifting soft clouds, rolling hills and a few
## fireflies. Every layer shifts with the carousel's scroll at its own depth
## (parallax). All drawn in code in the Sweetie 16 palette.

const Pal := preload("res://scripts/palette.gd")
const W := 1920.0
const H := 1080.0

## Set by the carousel every frame: the continuous scroll position in cards.
var scroll := 0.0
## 0..1: how much the scene is dimmed (while a game runs).
var dim := 0.0

var _t := 0.0
var _stars: Array = []
var _clouds: Array = []
var _flies: Array = []
var _sky: TextureRect
var _grad: Gradient


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 0.78, 1.0])
	g.colors = PackedColorArray([Pal.NIGHT, Pal.NAVY, Pal.BLUE.lerp(Pal.PURPLE, 0.55), Pal.PURPLE.lerp(Pal.RED, 0.35)])
	_grad = g
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(0, 1)
	gt.width = 8
	gt.height = 256
	_sky = TextureRect.new()
	_sky.texture = gt
	_sky.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_sky.stretch_mode = TextureRect.STRETCH_SCALE
	_sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	_sky.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sky.show_behind_parent = true
	add_child(_sky)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260927
	for i in 170:
		var col: Color = [Pal.WHITE, Pal.WHITE, Pal.WHITE, Pal.YELLOW, Pal.CYAN][rng.randi() % 5]
		_stars.append({"p": Vector2(rng.randf() * W, pow(rng.randf(), 1.4) * H * 0.72),
			"r": rng.randf_range(1.2, 3.4), "ph": rng.randf() * TAU, "sp": rng.randf_range(0.6, 2.2),
			"depth": rng.randf_range(0.01, 0.04), "c": col})
	for i in 7:
		_clouds.append({"x": rng.randf() * (W + 600), "y": rng.randf_range(120, 560),
			"s": rng.randf_range(0.7, 1.5), "v": rng.randf_range(6, 16), "depth": rng.randf_range(0.06, 0.14),
			"a": rng.randf_range(0.08, 0.16), "seed": rng.randi()})
	for i in 18:
		_flies.append({"x": rng.randf() * W, "y": rng.randf_range(700, 1060), "ph": rng.randf() * TAU,
			"v": rng.randf_range(8, 22), "r": rng.randf_range(2.5, 4.5)})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _px(depth: float) -> float:
	# Horizontal parallax offset for a layer (one card ~ 640 px of travel).
	return -scroll * 640.0 * depth


func _draw() -> void:
	# Moon with a soft halo.
	var moon := Vector2(1560 + _px(0.02), 170)
	for i in 6:
		draw_circle(moon, 70.0 + i * 26.0, Color(Pal.YELLOW, 0.035), true, -1.0, true)
	draw_circle(moon, 62.0, Pal.WHITE.lerp(Pal.YELLOW, 0.35), true, -1.0, true)
	draw_circle(moon + Vector2(-18, -10), 12.0, Color(Pal.YELLOW, 0.35), true, -1.0, true)
	draw_circle(moon + Vector2(20, 18), 8.0, Color(Pal.YELLOW, 0.3), true, -1.0, true)

	for s in _stars:
		var p: Vector2 = s.p
		p.x = fposmod(p.x + _px(s.depth), W)
		var tw := 0.55 + 0.45 * sin(_t * s.sp + s.ph)
		var c: Color = s.c
		draw_circle(p, s.r * (0.8 + 0.3 * tw), Color(c, 0.35 + 0.65 * tw), true, -1.0, true)
		if s.r > 3.0:
			var k: float = s.r * 3.0 * tw
			draw_line(p - Vector2(k, 0), p + Vector2(k, 0), Color(c, 0.35 * tw), 1.5, true)
			draw_line(p - Vector2(0, k), p + Vector2(0, k), Color(c, 0.35 * tw), 1.5, true)

	for c in _clouds:
		var x := fposmod(c.x + _t * c.v + _px(c.depth), W + 600) - 300
		# Opaque, tinted from the sky behind it: overlapping puffs never show seams.
		var tint := _grad.sample(c.y / H).lerp(Pal.GREY_LIGHT, c.a)
		_cloud(Vector2(x, c.y), c.s, tint, c.seed)

	_hills(H - 250, 70.0, 0.0011, 0.18, Pal.NAVY.lerp(Pal.PURPLE, 0.35), 1.3)
	_hills(H - 170, 55.0, 0.0017, 0.32, Pal.SLATE.lerp(Pal.NIGHT, 0.35), 4.1)
	_hills(H - 95, 40.0, 0.0024, 0.5, Pal.NIGHT, 7.7)

	for f in _flies:
		var x := fposmod(f.x + sin(_t * 0.3 + f.ph) * 40.0 + _px(0.4), W)
		var y: float = f.y - fposmod(_t * f.v, 380.0) + sin(_t * 1.3 + f.ph) * 10.0
		var a := 0.5 + 0.5 * sin(_t * 2.0 + f.ph)
		draw_circle(Vector2(x, y), f.r * 2.6, Color(Pal.YELLOW, 0.10 * a), true, -1.0, true)
		draw_circle(Vector2(x, y), f.r, Color(Pal.YELLOW, 0.75 * a), true, -1.0, true)

	if dim > 0.0:
		draw_rect(Rect2(0, 0, W, H), Color(Pal.NIGHT, 0.75 * dim))


func _cloud(at: Vector2, s: float, col: Color, seed: int) -> void:
	# A flat-bottomed puff: circles resting on one baseline, the biggest in the middle.
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var n := 5
	for i in n:
		var t := float(i) / (n - 1) * 2.0 - 1.0
		var r := (60.0 - 26.0 * absf(t) + rng.randf_range(-8, 8)) * s
		draw_circle(at + Vector2(t * 105.0 * s, -r), r, col, true, -1.0, true)
	draw_rect(Rect2(at + Vector2(-105.0 * s, -30.0 * s), Vector2(210.0 * s, 30.0 * s)), col)


func _hills(base: float, amp: float, freq: float, depth: float, col: Color, phase: float) -> void:
	var pts := PackedVector2Array()
	var off := _px(depth)
	var step := 24.0
	var x := 0.0
	while x <= W + step:
		var y := base - amp * (0.6 * sin((x - off) * freq * TAU / 6.0 + phase)
			+ 0.4 * sin((x - off) * freq * TAU / 2.3 + phase * 1.7))
		pts.append(Vector2(x, y))
		x += step
	var edge := pts.duplicate()
	pts.append(Vector2(W + step, H))
	pts.append(Vector2(0, H))
	draw_colored_polygon(pts, col)
	draw_polyline(edge, col, 2.0, true)
