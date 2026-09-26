extends Node2D
## Party at the station, in pixel art: sunset sky, the station with its door
## open, the truck parked in front with the crew hopping on the bumper, the
## run's stars raining into the star bucket one by one, the rescued cats'
## badges lining up, a spinning trophy helmet and confetti. After about
## 10 s, or when the driver presses "a", back to select.

const W := 480
const H := 270
const MAX_STARS := 30
const FIRST_DROP := 0.9
const DROP_EVERY := 0.22
const STAY_SECONDS := 10.0
const SKIP_GUARD := 1.0
const BUCKET := Vector2(404, 206)
const GROUND_Y := 214

const SKY: Array[Color] = [Color("#5d275d"), Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75")]
const C_GROUND := Color("#566c86")
const C_KERB := Color("#94b0c2")
const C_YELLOW := Color("#ffcd75")
const C_WHITE := Color("#f4f4f4")
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

var time := 0.0
var total := 0
var cats_total := 0
var shown := 0
var done := false
var riders: Array[AnimatedSprite2D] = []
var drops: Array[Dictionary] = []     # falling stars {node, pos, vel}
var landed: Array[Node2D] = []
var badges: Array[AnimatedSprite2D] = []
var confetti: Array[Dictionary] = []
var trophy: AnimatedSprite2D
var bucket: AnimatedSprite2D
var truck: AnimatedSprite2D
var rng := RandomNumberGenerator.new()
var _drop_t := FIRST_DROP
var _dropped := 0
var _confetti_t := 0.0
var _badge_t := 1.5


func _ready() -> void:
	rng.seed = 7
	total = maxi(0, Game.stars)
	cats_total = clampi(Game.cats, 0, 3)
	_build()
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func _build() -> void:
	var band := float(GROUND_Y) / SKY.size()
	for i in SKY.size():
		var r := ColorRect.new()
		r.position = Vector2(0, roundf(i * band))
		r.size = Vector2(W, ceilf(band) + 1)
		r.color = SKY[i]
		add_child(r)
	var ground := ColorRect.new()
	ground.position = Vector2(0, GROUND_Y)
	ground.size = Vector2(W, H - GROUND_Y)
	ground.color = C_GROUND
	add_child(ground)
	var kerb := ColorRect.new()
	kerb.position = Vector2(0, GROUND_Y)
	kerb.size = Vector2(W, 3)
	kerb.color = C_KERB
	add_child(kerb)
	var station := Art.sprite("station_front", Color("#b13e53"), Vector2i(176, 112))
	station.centered = false
	station.position = Vector2(W / 2 - 88, GROUND_Y - 112)
	add_child(station)
	trophy = Art.sprite("trophy_helmet", C_YELLOW, Vector2i(24, 24))
	trophy.scale = Vector2(2, 2)
	trophy.position = Vector2(W / 2, 44)
	add_child(trophy)
	truck = Art.sprite("truck_side", Color("#b13e53"), Vector2i(112, 56))
	truck.position = Vector2(W / 2 - 10, GROUND_Y - 26)
	add_child(truck)
	bucket = Art.sprite("bucket", Color("#ef7d57"), Vector2i(24, 24))
	bucket.scale = Vector2(2, 2)
	bucket.position = BUCKET
	add_child(bucket)
	var ids := dancers()
	var xs := [W / 2 - 96, W / 2 + 74, W / 2 - 130, W / 2 + 108, W / 2 - 164, W / 2 + 142]
	for i in ids.size():
		var r2 := Art.sprite(Game.helmet_sprite(ids[i]), Game.rider_color(ids[i]), Vector2i(16, 16))
		r2.scale = Vector2(2, 2)
		r2.position = Vector2(xs[i % xs.size()], GROUND_Y - 18)
		r2.flip_h = r2.position.x > W / 2
		add_child(r2)
		riders.append(r2)


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
		var hop := absf(sin(time * 6.0 + i * 1.3)) * 8.0
		riders[i].position.y = GROUND_Y - 18 - roundf(hop)
	trophy.position.y = 44 - (2 if fmod(time, 0.5) < 0.25 else 0)
	truck.position.y = GROUND_Y - 26 - (1 if fmod(time, 0.4) < 0.2 else 0)
	bucket.position.y = BUCKET.y
	# Stars rain in, one by one, into the bucket (icons capped, the count isn't).
	_drop_t -= dt
	while _drop_t <= 0.0 and _dropped < mini(total, MAX_STARS):
		_drop_t += DROP_EVERY
		_dropped += 1
		var s := Art.sprite("star", C_YELLOW, Vector2i(8, 8))
		s.scale = Vector2(2, 2)
		var at := Vector2(rng.randi_range(40, W - 40), -10)
		add_child(s)
		drops.append({"node": s, "pos": at, "vel": Vector2((BUCKET.x - at.x) * 0.9, 40.0)})
	for i in range(drops.size() - 1, -1, -1):
		var d := drops[i]
		d.vel.y += 260.0 * dt
		d.pos += d.vel * dt
		d.node.position = d.pos.round()
		if d.pos.y >= BUCKET.y - 14:
			d.node.queue_free()
			drops.remove_at(i)
			shown += 1
			bucket.position.y = BUCKET.y - 3
			Sfx.play("star", 1.0 + 0.04 * (shown % 12), -4.0)
			_add_pip(shown - 1)
	if _dropped >= mini(total, MAX_STARS) and drops.is_empty():
		shown = total
	# Cat badges pop in one by one.
	_badge_t -= dt
	if _badge_t <= 0.0 and badges.size() < cats_total:
		_badge_t = 0.7
		var b := Art.sprite("badge_cat", C_YELLOW, Vector2i(16, 16))
		b.scale = Vector2(2, 2)
		b.position = Vector2(W - 30 - badges.size() * 38, 26)
		add_child(b)
		badges.append(b)
		Sfx.play("badge")
	# Confetti.
	_confetti_t -= dt
	while _confetti_t <= 0.0:
		_confetti_t += 0.05
		var c := Art.sprite("confetti", CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()], Vector2i(4, 4))
		c.frame = rng.randi() % 6
		c.speed_scale = rng.randf_range(0.5, 1.5)
		add_child(c)
		confetti.append({"node": c, "pos": Vector2(rng.randi_range(0, W), -4), "vel": Vector2(0, rng.randf_range(35, 60))})
	for i in range(confetti.size() - 1, -1, -1):
		var cf := confetti[i]
		cf.pos += cf.vel * dt
		cf.vel.x = sin(time * 3.0 + i) * 14.0
		cf.node.position = cf.pos.round()
		if cf.pos.y > H + 4:
			cf.node.queue_free()
			confetti.remove_at(i)
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		Game.goto("select")


## A small star pip per landed star, in rows at the top left.
func _add_pip(i: int) -> void:
	var s := Art.sprite("star", C_YELLOW, Vector2i(8, 8))
	s.stop()
	s.frame = 0
	s.position = Vector2(14 + (i % 10) * 11, 14 + (i / 10) * 11)
	add_child(s)
	landed.append(s)
