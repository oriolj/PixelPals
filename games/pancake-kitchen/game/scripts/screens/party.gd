extends Node2D
## Party: every customer of the round sits at a long table behind their own
## pancake tower (exactly as it was served), bouncing by how big their joy
## was; then a giant pancake flips over the whole screen while confetti falls.
## After STAY_SECONDS, or when the cook presses "a" (after a guard), it goes
## back to select.

const VA := preload("res://scripts/vector_art.gd")
const Pal := preload("res://scripts/kitchen/palette.gd")

const STAY_SECONDS := 12.0
const SKIP_GUARD := 1.5
const ARRIVE_EVERY := 0.35
const GIANT_AT := 2.6
const GIANT_TIME := 2.4
const TABLE_Y := 540.0

var time := 0.0
var done := false
var plates: Array[Dictionary] = []
var confetti: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var giant_sound := false
var _confetti_t := 0.0
var _arrived := 0


func _ready() -> void:
	rng.randomize()
	plates = Game.plates.duplicate(true)
	if plates.is_empty():
		# Never an empty table: a plain stack for a friend.
		plates = [{"animal": "bear", "stack": [{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}], "toppings": [], "joy": 1}]
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	var want := mini(plates.size(), int(time / ARRIVE_EVERY) + 1)
	while _arrived < want:
		_arrived += 1
		Sfx.play("yum", 1.0 + 0.05 * _arrived, -4.0)
	if time >= GIANT_AT and not giant_sound:
		giant_sound = true
		Sfx.play("boing_4", 0.7)
		Sfx.play("cheer")
	if time >= GIANT_AT * 0.8:
		_confetti_t -= dt
		while _confetti_t <= 0.0:
			_confetti_t += 0.03
			confetti.append({"pos": Vector2(rng.randf_range(0, 1280), -20), "vel": Vector2(0, rng.randf_range(120, 240)),
				"col": Pal.CONFETTI[rng.randi() % Pal.CONFETTI.size()], "rot": rng.randf_range(0, TAU),
				"spin": rng.randf_range(-5, 5), "kind": rng.randi() % 3})
	for i in range(confetti.size() - 1, -1, -1):
		var c: Dictionary = confetti[i]
		c.pos += c.vel * dt
		c.pos.x += sin(time * 3.0 + i) * 40.0 * dt
		c.rot += c.spin * dt
		if c.pos.y > 740:
			confetti.remove_at(i)
	queue_redraw()
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		Game.goto("select")


func _draw() -> void:
	draw_rect(Rect2(0, 0, 1280, 720), Color("#fff1d6"))
	# Bunting across the top.
	for i in 16:
		var bx := i * 84.0
		var tri := PackedVector2Array([Vector2(bx, 40), Vector2(bx + 76, 40), Vector2(bx + 38, 96)])
		VA.shape(self, tri, Pal.CONFETTI[i % Pal.CONFETTI.size()], 4.0)
	draw_line(Vector2(0, 40), Vector2(1280, 40), Pal.OUTLINE, 5.0, true)
	_draw_chefs()
	var n := plates.size()
	var gap := minf(300.0, 1200.0 / maxf(n, 1))
	var sc := clampf(gap / 220.0, 0.8, 1.05)
	var x0 := 640.0 - gap * (n - 1) / 2.0
	# Guests behind the table.
	for i in _arrived:
		var pl: Dictionary = plates[i]
		var joy: int = pl.get("joy", 1)
		var amp: float = [6.0, 18.0, 34.0][clampi(joy - 1, 0, 2)]
		var hop := absf(sin(time * (4.0 + joy * 1.5) + i)) * amp
		var o := {"eyes": "happy" if joy >= 2 or fmod(time + i, 3.0) < 0.2 else "open",
			"mouth": "grin" if joy >= 2 else "smile", "arms": [0.2, 0.6, 0.95][clampi(joy - 1, 0, 2)],
			"look": Vector2(0, 0.6)}
		VA.creature(self, Transform2D(0.0, Vector2(sc, sc), 0.0, Vector2(x0 + i * gap, TABLE_Y + 20 - hop)), pl.animal, o)
	# The long table with a checkered cloth.
	VA.rrect(self, Rect2(-20, TABLE_Y, 1320, 40), 10, Color.WHITE, 5.0)
	for x in 22:
		for y in 3:
			var c := Color("#ff9fb6") if (x + y) % 2 == 0 else Color.WHITE
			draw_rect(Rect2(x * 60, TABLE_Y + 40 + y * 60, 60, 60), c)
	draw_line(Vector2(0, TABLE_Y + 40), Vector2(1280, TABLE_Y + 40), Pal.OUTLINE, 4.0)
	for i in _arrived:
		var pl: Dictionary = plates[i]
		VA.stack(self, Vector2(x0 + i * gap, TABLE_Y + 22), pl.stack.size(), pl.toppings, 0.0, time, 0.85 * sc)
	_draw_giant()
	for c in confetti:
		VA.confetti(self, c.pos, c.col, c.rot, c.kind)


## The chefs of the round cheer on a little stage above the table.
func _draw_chefs() -> void:
	var seats: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seats.append(s)
	for k in seats.size():
		var s := seats[k]
		var chef: String = Players.riders[s] if Players.riders[s] != "" else Game.CHEFS[s]
		var x := 640.0 + (k - (seats.size() - 1) / 2.0) * 150.0
		var hop := absf(sin(time * 5.0 + k * 1.1)) * 16.0
		VA.creature(self, Transform2D(0.0, Vector2(0.55, 0.55), 0.0, Vector2(x, 250 - hop)), chef,
			{"hat": Game.hat_color(s), "arms": 1.0, "mouth": "grin", "eyes": "happy"})
		VA.star(self, Vector2(x, 272), 18, Players.SEAT_COLORS[s], time + k, 3.5)


func _draw_giant() -> void:
	var u := (time - GIANT_AT) / GIANT_TIME
	if u < 0.0 or u > 1.0:
		return
	# Up from the bottom left, over the whole screen, down the right.
	var pos := Vector2(lerpf(-200, 1480, u), 820 - sin(u * PI) * 700)
	var spin := u * TAU * 1.5
	VA.push(self, Transform2D(0.0, Vector2(4.5, 4.5), 0.0, pos))
	VA.pancake(self, Vector2.ZERO, 1.0, 1.0, cos(spin), 0.0, 0.0, 1.0, 3, sin(u * 5.0) * 0.3)
	for k in 3:
		VA.topping(self, ["strawberry", "banana", "cream"][k], Vector2(-40 + k * 40, -6 * cos(spin)), 0.2 * k, 1.0)
	VA.pop(self)
