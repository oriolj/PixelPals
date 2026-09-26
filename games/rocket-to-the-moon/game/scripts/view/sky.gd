extends Node2D
## The sky behind everything: palette bands that darken with altitude, and a
## starfield in three parallax layers of 1-2 px stars (whole-pixel positions,
## so nothing jitters). `level` 0 = daytime at the pad, 5 = deep space.

const W := 320
const H := 180
const BANDS := 6
## Sweetie 16 blues from dark to light: 1a1c2c 333c57 29366f 3b5dc9 41a6f6 73eff7.
const RAMP: Array[Color] = [Color("#1a1c2c"), Color("#333c57"), Color("#29366f"), Color("#3b5dc9"),
	Color("#41a6f6"), Color("#73eff7")]
## Daytime ramp index per band, top to bottom.
const DAY: Array[int] = [3, 4, 4, 5, 5, 5]
## Deep space never gets darker than this per band: a faint glow low down.
const FLOOR: Array[int] = [0, 0, 0, 0, 1, 2]
const LAYERS := [
	{"n": 40, "speed": 0.12, "color": Color("#566c86"), "size": 1, "from": 3},
	{"n": 24, "speed": 0.35, "color": Color("#94b0c2"), "size": 1, "from": 4},
	{"n": 12, "speed": 0.8, "color": Color("#f4f4f4"), "size": 2, "from": 4},
]

var level := 0:
	set(v):
		v = clampi(v, 0, 5)
		if v != level:
			level = v
			queue_redraw()
## Accumulated world scroll in px (the stars move with it).
var scroll := 0.0:
	set(v):
		scroll = v
		queue_redraw()
var time := 0.0
var _stars: Array = []


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 42
	for layer in LAYERS:
		var pts: Array[Vector2] = []
		for i in int(layer.n):
			pts.append(Vector2(rng.randi_range(2, W - 3), rng.randi_range(0, H - 1)))
		_stars.append(pts)


func band_color(i: int) -> Color:
	return RAMP[clampi(DAY[i] - level, FLOOR[i], RAMP.size() - 1)]


func _draw() -> void:
	var bh := float(H) / BANDS
	for i in BANDS:
		draw_rect(Rect2(0, roundf(i * bh), W, ceilf(bh) + 1), band_color(i))
	for li in LAYERS.size():
		var layer: Dictionary = LAYERS[li]
		if level < int(layer.from):
			continue
		var sz := int(layer.size)
		for k in _stars[li].size():
			var p: Vector2 = _stars[li][k]
			var y := floorf(fposmod(p.y + scroll * float(layer.speed), H))
			var col: Color = layer.color
			if sz == 2:
				# Near stars twinkle: a plus shape on some beats.
				if int(time * 3.0 + k) % 5 == 0:
					draw_rect(Rect2(p.x - 1, y, 3, 1), col)
					draw_rect(Rect2(p.x, y - 1, 1, 3), col)
				else:
					draw_rect(Rect2(p.x, y, 2, 2), col)
			else:
				draw_rect(Rect2(p.x, y, 1, 1), col)
