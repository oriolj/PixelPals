extends Node2D
## Party: the run's three towers rebuilt as stacks of little blocks (one per
## flag reached, popping in one by one), a trophy on the tallest, the stars in
## pixel digits, confetti, and the riders dancing. After STAY_SECONDS, or the
## Builder's "a" (after a short guard), it goes back to select.

const Vec := preload("res://scripts/play/vec.gd")
const Icons := preload("res://scripts/icons.gd")
const BlockScript := preload("res://scripts/play/block.gd")

const STAY_SECONDS := 10.0
const SKIP_GUARD := 1.0
const FIRST_POP := 0.8
const POP_EVERY := 0.22
const COL_X: Array[float] = [200.0, 320.0, 440.0]
const STAGE_Y := 300.0
const BLOCK_H := 24.0
const KINDS: Array[String] = ["square", "plank", "arch", "tall", "roof", "square", "plank", "arch"]
## 3x5 digit glyphs, one string per row, "#" = lit.
const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]

var time := 0.0
var done := false
## Per tower: blocks to stack (the flags reached, at least 1 so every tower shows).
var heights: Array[int] = []
var shown: Array[int] = [0, 0, 0]
var tallest := 0
var riders: Array[AnimatedSprite2D] = []
var _pop_t := FIRST_POP
var _pop_col := 0
var _confetti_t := 0.0
var confetti_tex: Texture2D


func _ready() -> void:
	for i in 3:
		var h: int = Game.tower_heights[i] if i < Game.tower_heights.size() else 0
		heights.append(clampi(h, 1, 8))
	tallest = heights.max()
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	confetti_tex = ImageTexture.create_from_image(img)
	var ids := dancers()
	var xs := [70.0, 570.0, 120.0, 520.0, 30.0, 610.0]
	for i in ids.size():
		var r := Art.sprite(ids[i], Game.rider_color(ids[i]), Vector2i(16, 16))
		r.scale = Vector2(3, 3)
		r.position = Vector2(xs[i % xs.size()], STAGE_Y - 24)
		r.flip_h = xs[i % xs.size()] > 320.0
		add_child(r)
		riders.append(r)
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


## Rider ids to show: the seated riders, or the first of the roster if nobody.
func dancers() -> Array[String]:
	var out: Array[String] = []
	for seat in Players.SEAT_COUNT:
		var r: String = Players.riders[seat]
		if r == "" and Players.is_seated(seat) and not Game.roster.is_empty():
			r = Game.roster[seat % Game.roster.size()]
		if r != "":
			out.append(r)
	if out.is_empty():
		for i in mini(3, Game.roster.size()):
			out.append(Game.roster[i])
	return out


func step(dt: float) -> void:
	if done:
		return
	time += dt
	for i in riders.size():
		riders[i].position.y = STAGE_Y - 24 - absf(sin(time * 6.0 + i * 1.3)) * 12.0
	_pop_t -= dt
	while _pop_t <= 0.0 and _pop_col < 3:
		_pop_t += POP_EVERY
		if shown[_pop_col] < heights[_pop_col]:
			shown[_pop_col] += 1
			Sfx.play("flag_%d" % shown[_pop_col], 1.0, -3.0)
		else:
			_pop_col += 1
			if _pop_col < 3:
				_pop_t += 0.3
			else:
				Sfx.play("cheer")
	_confetti_t -= dt
	if _confetti_t <= 0.0:
		_confetti_t = 1.2
		_confetti(Vector2(randf_range(80, 560), -10))
	queue_redraw()
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(Players.Seat.DRIVER, "a")):
		done = true
		Game.goto("select")


## One level of a rebuilt tower: a chunky block in the block colours with a face.
func _draw_level(at: Vector2, k: int, top: bool) -> void:
	var col: Color = BlockScript.KINDS[KINDS[k % KINDS.size()]].color
	var w := 46.0 if k % 2 == 0 else 38.0
	var body := Vec.translated(Vec.rounded_rect(w, BLOCK_H - 1.0, 6), at)
	Vec.draw_bevel(self, body, col, 3.0)
	for dx in [-6.0, 6.0]:
		draw_circle(at + Vector2(dx, -2), 3.4, Vec.INK, true, -1.0, true)
		draw_circle(at + Vector2(dx, -2), 2.3, Vec.WHITE, true, -1.0, true)
		draw_circle(at + Vector2(dx, -1.5), 1.3, Vec.INK, true, -1.0, true)
	draw_arc(at + Vector2(0, 2), 3.5, 0.3, PI - 0.3, 6, Vec.INK, 2.0, true)
	if top:
		var roof := Vec.rounded(PackedVector2Array([Vector2(-24, 0), Vector2(0, -20), Vector2(24, 0)]), 3.0, 2)
		Vec.draw_shape(self, Vec.translated(roof, at + Vector2(0, -BLOCK_H * 0.5)), Color("#3b5dc9"))


func all_shown() -> bool:
	return shown == heights


func _confetti(at: Vector2) -> void:
	var p := CPUParticles2D.new()
	p.texture = confetti_tex
	p.amount = 40
	p.one_shot = true
	p.explosiveness = 0.3
	p.lifetime = 4.0
	p.direction = Vector2(0, 1)
	p.spread = 60.0
	p.initial_velocity_min = 40.0
	p.initial_velocity_max = 120.0
	p.gravity = Vector2(0, 60)
	p.angular_velocity_min = -300.0
	p.angular_velocity_max = 300.0
	p.scale_amount_min = 1.2
	p.scale_amount_max = 2.0
	p.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	p.emission_rect_extents = Vector2(120, 4)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.2, 0.4, 0.6, 0.8, 1.0])
	g.colors = PackedColorArray([Vec.RED, Vec.YELLOW, Vec.LIME, Vec.SKY, Vec.ORANGE, Vec.WHITE])
	g.interpolation_mode = Gradient.GRADIENT_INTERPOLATE_CONSTANT
	p.color_initial_ramp = g
	p.position = at
	add_child(p)
	p.emitting = true
	get_tree().create_timer(5.0).timeout.connect(p.queue_free)


func _draw() -> void:
	var bands := 18
	for i in bands:
		var c := Color("#29366f").lerp(Color("#3b5dc9"), float(i) / (bands - 1))
		draw_rect(Rect2(0, i * 360.0 / bands, 640, 360.0 / bands + 1), c)
	# Spotlights.
	for i in 3:
		var x: float = COL_X[i]
		var sway := sin(time * 1.3 + i) * 30.0
		draw_colored_polygon(PackedVector2Array([Vector2(x + sway - 14, 0), Vector2(x + sway + 14, 0),
			Vector2(x + 60, STAGE_Y), Vector2(x - 60, STAGE_Y)]), Color(1, 1, 0.8, 0.12))
	# Stage.
	draw_rect(Rect2(0, STAGE_Y, 640, 60), Color("#5d275d"))
	draw_rect(Rect2(0, STAGE_Y, 640, 6), Color("#ef7d57"))
	draw_line(Vector2(0, STAGE_Y), Vector2(640, STAGE_Y), Vec.INK, 3.0, true)
	# The three towers.
	for i in 3:
		var x: float = COL_X[i]
		var base := Vec.translated(Vec.rounded_rect(80, 12, 4), Vector2(x, STAGE_Y - 4))
		Vec.draw_shape(self, base, Color("#566c86"))
		for k in shown[i]:
			var y := STAGE_Y - 10 - BLOCK_H * 0.5 - k * BLOCK_H
			var wob := sin(time * 3.0 + k * 0.7 + i) * 1.5 * k * 0.3
			_draw_level(Vector2(x + wob, y), k, k == shown[i] - 1 and shown[i] == heights[i])
		if all_shown() and heights[i] == tallest:
			var ty := STAGE_Y - 10 - heights[i] * BLOCK_H - 52 - absf(sin(time * 4.0)) * 6.0
			Icons.draw(self, "trophy", Vector2(x, ty), 44, Color("#ffcd75"))
		# Tower number as dots under the base.
		for d in i + 1:
			draw_circle(Vector2(x - i * 6 + d * 12, STAGE_Y + 24), 4, Vec.WHITE, true, -1.0, true)
	# Stars earned: a big star and the count in pixel digits (top left).
	draw_colored_polygon(Vec.star(18, Vector2(40, 36)), Vec.YELLOW)
	draw_polyline(Vec.closed(Vec.star(18, Vector2(40, 36))), Vec.INK, 3.0, true)
	var s := str(maxi(0, Game.stars))
	var px := 5.0
	for k in s.length():
		var glyph: Array = DIGITS[int(s[k])]
		for row in 5:
			for col in 3:
				if glyph[row][col] == "#":
					draw_rect(Rect2(68 + (k * 4 + col) * px, 24 + row * px, px, px), Vec.WHITE)
