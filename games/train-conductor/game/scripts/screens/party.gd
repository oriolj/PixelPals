extends Node2D
## Party: the station at night. One house per station colour with its
## window lit; every delivered passenger stands in front of their house and
## waves; the sky fills with one star per delivery (and per perfect stop);
## fireworks go off; the train has pulled in with the riders and toots three
## times. After STAY_SECONDS, or the driver's "a", back to select.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")
const MenuTrain := preload("res://scripts/screens/menu_train.gd")
const GlowView := preload("res://scripts/level/glow_view.gd")

const STAY_SECONDS := 12.0
const SKIP_GUARD := 1.5
const FIRST_STAR := 0.8
const STAR_EVERY := 0.25
const TOOTS: Array[float] = [1.0, 1.7, 2.4]
const HOUSE_X: Array[float] = [190.0, 490.0, 790.0, 1090.0]

var auto_goto := true
var next_screen := ""
var time := 0.0
var done := false
var stars_total := 0
var stars_shown := 0
var star_spots: Array[Vector2] = []
var per_colour: Array[int] = [0, 0, 0, 0]
var train: Node2D
var fireworks: Node2D
var _toots := 0
var _firework_t := 1.2
var _star_t := FIRST_STAR
var rng := RandomNumberGenerator.new()


func _ready() -> void:
	rng.seed = 99
	stars_total = maxi(0, Game.stars)
	for c in Game.deliveries:
		per_colour[c] += 1
	for i in mini(stars_total, 60):
		star_spots.append(Vector2(40 + (i * 211) % 1200 + rng.randf_range(-20, 20), 30 + (i * 67) % 200 + rng.randf_range(-10, 10)))
	fireworks = GlowView.new()
	add_child(fireworks)
	train = MenuTrain.new()
	add_child(train)
	var cars := clampi(1 + Game.deliveries.size() / 3, 1, 5)
	train.setup(Vector2(1150, 640), Game.train_riders(), cars, 1.3)
	Sfx.music("music_night")
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	_star_t -= dt
	while _star_t <= 0.0 and stars_shown < stars_total:
		_star_t += STAR_EVERY
		stars_shown += 1
		Sfx.play("hop", 1.3 + 0.03 * (stars_shown % 12), -8.0)
	if _toots < TOOTS.size() and time >= TOOTS[_toots]:
		_toots += 1
		Sfx.play("whistle", 1.0 + 0.08 * _toots)
		train.toot()
	_firework_t -= dt
	if _firework_t <= 0.0:
		_firework_t = 0.7
		fireworks.firework(Vector2(rng.randf_range(150, 1130), rng.randf_range(80, 260)))
		Sfx.play("firework", rng.randf_range(0.9, 1.2), -8.0)
	if Players.just_pressed(Players.Seat.HONKER, "any"):
		train.toot()
		Sfx.play("whistle")
	queue_redraw()
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(Players.Seat.DRIVER, "a")):
		done = true
		next_screen = "select"
		if auto_goto:
			Game.goto.call_deferred("select")


func _draw() -> void:
	# Night sky.
	draw_rect(Rect2(0, 0, 1280, 720), Palette.NIGHT)
	draw_rect(Rect2(0, 250, 1280, 200), Palette.NIGHT.lightened(0.08))
	Shapes.fill_outline(self, Shapes.circle(Vector2(1160, 90), 46, 32), Palette.CREAM, 3.0)
	draw_circle(Vector2(1180, 78), 36, Palette.NIGHT)
	for i in stars_shown:
		if i < star_spots.size():
			var tw := 1.0 + 0.15 * sin(time * 4.0 + i)
			Shapes.fill_outline(self, Shapes.star(star_spots[i], 13 * tw), Palette.GLOW, 2.0)
	# Hills and the town.
	for i in 7:
		draw_colored_polygon(Shapes.ellipse(Vector2(i * 220 - 20, 470), 200, 110, 32), Palette.GRASS_DARK.darkened(0.45))
	draw_rect(Rect2(0, 470, 1280, 250), Palette.GRASS_DARK.darkened(0.35))
	for c in 4:
		var h := Vector2(HOUSE_X[c], 420)
		draw_circle(h + Vector2(-8, 0) * 2.6, 60, Color(Palette.GLOW, 0.18))
		Draw.house(self, h, c, true, 2.6)
		# The passengers of that colour on the porch, waving.
		var n := per_colour[c]
		for k in n:
			var x := h.x + (k - (n - 1) * 0.5) * 34.0
			var hop := absf(sin(time * 6.0 + k * 0.9 + c)) * 10.0
			Draw.passenger(self, Vector2(x, 548), c, 1.5, hop, 1.0 if int(time * 3.0 + k) % 2 == 0 else 0.2, true)
