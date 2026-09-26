extends Node2D
## Party: the riders dance on a stage under falling confetti, a trophy
## bounces, and the run's stars pop in one by one (icons capped at 50, then a
## big star). A tiny pixel digit display shows the exact count. After about
## 10 s, or when the driver presses "a", it goes back to select.

const MAX_ICONS := 50
const PER_ROW := 10
const FIRST_POP := 0.8
const POP_EVERY := 0.09
const STAY_SECONDS := 10.0
const SKIP_GUARD := 1.0          # ignore an "a" still held from the level

const C_BG := Color("#29366f")
const C_BG_LOW := Color("#3b5dc9")
const C_STAGE := Color("#5d275d")
const C_STAGE_EDGE := Color("#ef7d57")
const C_YELLOW := Color("#ffcd75")
const C_WHITE := Color("#f4f4f4")
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

## 3x5 digit glyphs, one string per row, "#" = lit.
const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]

var time := 0.0
var total := 0
var shown := 0
var done := false
var riders: Array[AnimatedSprite2D] = []
var icons: Array[Dictionary] = []   # {node, born}
var confetti: Array[Dictionary] = []  # {node, pos, vel}
var trophy: AnimatedSprite2D
var big_star: AnimatedSprite2D
var digits: Digits
var rng := RandomNumberGenerator.new()
var _confetti_t := 0.0
var _pop_t := FIRST_POP


func _ready() -> void:
	rng.randomize()
	total = maxi(0, Game.stars)
	_build()
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func _build() -> void:
	var bg := ColorRect.new()
	bg.size = Vector2(320, 180)
	bg.color = C_BG
	add_child(bg)
	var low := ColorRect.new()
	low.size = Vector2(320, 70)
	low.position = Vector2(0, 70)
	low.color = C_BG_LOW
	add_child(low)
	var stage := ColorRect.new()
	stage.size = Vector2(320, 40)
	stage.position = Vector2(0, 140)
	stage.color = C_STAGE
	add_child(stage)
	var edge := ColorRect.new()
	edge.size = Vector2(320, 2)
	edge.position = Vector2(0, 140)
	edge.color = C_STAGE_EDGE
	add_child(edge)
	var pedestal := ColorRect.new()
	pedestal.size = Vector2(28, 16)
	pedestal.position = Vector2(146, 124)
	pedestal.color = C_STAGE_EDGE
	add_child(pedestal)

	trophy = Art.sprite("trophy", C_YELLOW, Vector2i(24, 24))
	trophy.position = Vector2(160, 110)
	add_child(trophy)

	var ids := dancers()
	for i in ids.size():
		var r := Art.sprite(ids[i], Game.rider_color(ids[i]), Vector2i(16, 16))
		# Alternate the dancers left and right of the trophy.
		var x: int = 160 + [-34, 34, -62, 62, -90, 90][i % 6]
		r.position = Vector2(x, 132)
		r.flip_h = x > 160
		add_child(r)
		riders.append(r)

	digits = Digits.new()
	digits.position = Vector2(160, 60)
	add_child(digits)


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
	# Dance: each rider hops on its own beat.
	for i in riders.size():
		var hop := absf(sin(time * 6.0 + i * 1.3)) * 6.0
		riders[i].position.y = 132 - roundf(hop)
	trophy.position.y = 110 - (1 if fmod(time, 0.5) < 0.25 else 0)

	_pop_t -= dt
	var icon_cap := mini(total, MAX_ICONS)
	while _pop_t <= 0.0 and icons.size() < icon_cap:
		_pop_t += POP_EVERY
		_add_icon(icons.size())
	if _pop_t <= 0.0 and icons.size() >= icon_cap and total > MAX_ICONS and big_star == null:
		big_star = Art.sprite("big_star", C_YELLOW, Vector2i(24, 24))
		big_star.position = Vector2(236, 30)
		add_child(big_star)
		shown = total
		Sfx.play("bigstar")
	digits.value = shown
	for ic in icons:
		var age: float = time - ic.born
		ic.node.position.y = ic.y - (2 if age < 0.1 else 0)

	_confetti_t -= dt
	while _confetti_t <= 0.0:
		_confetti_t += 0.06
		_add_confetti()
	for i in range(confetti.size() - 1, -1, -1):
		var c := confetti[i]
		c.pos += c.vel * dt
		c.vel.x = sin(time * 3.0 + i) * 12.0
		c.node.position = c.pos.round()
		if c.pos.y > 184:
			c.node.queue_free()
			confetti.remove_at(i)

	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		Game.goto("select")


func _add_icon(i: int) -> void:
	var s := Art.sprite("star", C_YELLOW, Vector2i(8, 8))
	var row := i / PER_ROW
	var col := i % PER_ROW
	var y := 10 + row * 10
	s.position = Vector2(115 + col * 10, y)
	add_child(s)
	icons.append({"node": s, "born": time, "y": y})
	shown = i + 1
	Sfx.play("star", 1.0 + 0.04 * (i % 12), -4.0)


func _add_confetti() -> void:
	var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
	var c := Art.sprite("confetti", tint, Vector2i(4, 4))
	c.speed_scale = rng.randf_range(0.5, 1.5)
	c.frame = rng.randi() % 6
	add_child(c)
	var at := Vector2(rng.randi_range(0, 320), -4)
	confetti.append({"node": c, "pos": at, "vel": Vector2(0, rng.randf_range(30, 55))})


## Tiny pixel number, drawn with rects (no font, no text).
class Digits extends Node2D:
	var value := -1:
		set(v):
			if v != value:
				value = v
				queue_redraw()

	func _draw() -> void:
		if value < 0:
			return
		var s := str(value)
		var scale := 2
		var w := s.length() * 4 * scale - scale
		var x0 := -w / 2
		for k in s.length():
			var glyph: Array = DIGITS[int(s[k])]
			for row in 5:
				for col in 3:
					if glyph[row][col] == "#":
						draw_rect(Rect2(x0 + (k * 4 + col) * scale, row * scale, scale, scale), Color("#f4f4f4"))
