extends Node2D
## The party on the Moon: the rocket on its pad, the crew's flags, the riders
## dancing in their helmets under falling confetti. On top, the album page:
## the eight planets, found ones in colour (this trip's pop in with a
## sparkle), missing ones as grey silhouettes. Under it, the fuel cans of this
## trip in the pixel digits. After about 12 s, or the Pilot's "a", back to select.

const Album := preload("res://scripts/logic/album.gd")
const SkyView := preload("res://scripts/view/sky.gd")
const Digits := preload("res://scripts/view/digits.gd")

const STAY_SECONDS := 12.0
const SKIP_GUARD := 1.5
const FIRST_POP := 0.8
const POP_EVERY := 0.35
const SLOT := 22
const ALBUM_Y := 30
const GROUND_Y := 156

const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

var time := 0.0
var done := false
var rng := RandomNumberGenerator.new()
## Planet kinds shown in colour (album), and which of them are new this trip.
var owned: Array[int] = []
var fresh: Array[int] = []
## kind -> {"node": AnimatedSprite2D, "shown": bool, "x": int}
var slots := {}
var dancers: Array[Node2D] = []
var confetti: Array[Dictionary] = []
var digits: Node2D
var sky: Node2D
var _pop_t := FIRST_POP
var _confetti_t := 0.0
var _reveal: Array[int] = []


func _ready() -> void:
	rng.randomize()
	owned = Game.album.duplicate()
	for k in Game.trip_planets:
		if not owned.has(k):
			owned.append(k)
	fresh = Game.trip_planets.duplicate()
	_build()
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func _build() -> void:
	sky = SkyView.new()
	sky.level = 5
	add_child(sky)
	var earth := EarthDot.new()
	earth.position = Vector2(292, 128)
	add_child(earth)
	var ground := Art.sprite("moon_ground", Color("#94b0c2"), Vector2i(320, 32))
	ground.position = Vector2(160, 180 - 16)
	add_child(ground)
	var pad := Art.sprite("launch_pad", Color("#566c86"), Vector2i(64, 16))
	pad.position = Vector2(48, 150 + 6)
	add_child(pad)
	var rocket := Art.sprite("rocket", Color("#f4f4f4"), Vector2i(24, 40))
	rocket.stop()
	rocket.position = Vector2(48, 150 - 20)
	add_child(rocket)

	var seats := _seats()
	var x := 104
	for seat in seats:
		var flag := Art.sprite("flag", Players.SEAT_COLORS[seat], Vector2i(16, 16))
		flag.modulate = Players.SEAT_COLORS[seat].lightened(0.25)
		flag.position = Vector2(x - 14, GROUND_Y - 12)
		add_child(flag)
		var d := Node2D.new()
		d.position = Vector2(x, GROUND_Y - 10)
		add_child(d)
		var rider: String = Players.riders[seat] if Players.riders[seat] != "" else Game.roster[seat % Game.roster.size()]
		var r := Art.sprite(rider, Game.rider_color(rider), Vector2i(16, 16))
		r.position = Vector2(0, 1)
		d.add_child(r)
		var helmet := Art.sprite("helmet", Color(1, 1, 1, 0), Vector2i(20, 20))
		d.add_child(helmet)
		dancers.append(d)
		x += 64

	# The album page: 8 slots in a frame.
	var page := Page.new()
	page.position = Vector2(160, ALBUM_Y)
	page.width = Album.KINDS * SLOT + 8
	add_child(page)
	for k in range(1, Album.KINDS + 1):
		var sx := 160 - (Album.KINDS * SLOT) / 2 + (k - 1) * SLOT + SLOT / 2
		var frame := Art.sprite("album_frame", Color("#333c57"), Vector2i(16, 16))
		frame.position = Vector2(sx, ALBUM_Y)
		add_child(frame)
		var has := owned.has(k)
		var old := has and not fresh.has(k)
		var sil := Art.sprite("silhouette_%d" % k, Color("#566c86"), Vector2i(16, 16))
		sil.position = Vector2(sx, ALBUM_Y)
		add_child(sil)
		var planet := Art.sprite("planet_%d" % k, Color("#ef7d57"), Vector2i(16, 16))
		planet.stop()
		planet.position = Vector2(sx, ALBUM_Y)
		planet.visible = has and old
		add_child(planet)
		slots[k] = {"node": planet, "sil": sil, "x": sx, "pop": 0.0}
		if has and not old:
			_reveal.append(k)

	var can := Art.sprite("fuel", Color("#b13e53"), Vector2i(8, 12))
	can.stop()
	can.scale = Vector2(2, 2)
	add_child(can)
	digits = Digits.new()
	digits.px = 3
	digits.value = maxi(0, Game.fuel)
	add_child(digits)
	var total_w: int = 16 + 6 + digits.width()
	can.position = Vector2(160 - total_w / 2 + 8, 72)
	digits.position = Vector2(160 - total_w / 2 + 22 + digits.width() / 2, 65)


func _seats() -> Array[int]:
	var out: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			out.append(s)
	if out.is_empty():
		out.append(0)
	return out


func step(dt: float) -> void:
	if done:
		return
	time += dt
	sky.time = time
	sky.scroll = time * 3.0
	for i in dancers.size():
		var hop := absf(sin(time * 6.0 + i * 1.3)) * 6.0
		dancers[i].position.y = GROUND_Y - 10 - roundf(hop)
	# This trip's new planets pop into the album one by one.
	_pop_t -= dt
	if _pop_t <= 0.0 and not _reveal.is_empty():
		_pop_t = POP_EVERY
		var k: int = _reveal.pop_front()
		slots[k].node.visible = true
		slots[k].sil.visible = false
		slots[k].pop = 0.3
		Sfx.play("planet_%d" % k)
		for j in 6:
			_add_confetti(Vector2(slots[k].x, ALBUM_Y), Vector2.from_angle(TAU * j / 6.0) * 60.0)
	for k in slots:
		var s: Dictionary = slots[k]
		s.pop = maxf(0.0, s.pop - dt)
		s.node.position.y = ALBUM_Y - (3 if s.pop > 0.0 else 0)
		if s.node.visible:
			s.sil.visible = false
	_confetti_t -= dt
	while _confetti_t <= 0.0:
		_confetti_t += 0.07
		_add_confetti(Vector2(rng.randi_range(0, 320), -4), Vector2(0, rng.randf_range(30, 55)))
	for i in range(confetti.size() - 1, -1, -1):
		var c := confetti[i]
		c.pos += c.vel * dt
		c.vel = c.vel.move_toward(Vector2(sin(time * 3.0 + i) * 12.0, 45.0), 90.0 * dt)
		c.node.position = c.pos.round()
		if c.pos.y > GROUND_Y + 4:
			c.node.queue_free()
			confetti.remove_at(i)
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		Game.goto("select")


func _add_confetti(at: Vector2, vel: Vector2) -> void:
	var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
	var c := Art.sprite("confetti", tint, Vector2i(4, 4))
	c.stop()
	c.frame = rng.randi() % maxi(1, c.sprite_frames.get_frame_count("default"))
	add_child(c)
	confetti.append({"node": c, "pos": at, "vel": vel})


## The album page behind the slots.
class Page extends Node2D:
	var width := 184

	func _draw() -> void:
		var r := Rect2(-width / 2, -14, width, 28)
		draw_rect(r, Color("#ffcd75"))
		draw_rect(r.grow(-2), Color("#5d275d"))


## The Earth, small and far away over the Moon's horizon.
class EarthDot extends Node2D:
	func _draw() -> void:
		draw_circle(Vector2.ZERO, 9, Color("#41a6f6"))
		draw_rect(Rect2(-6, -5, 5, 4), Color("#38b764"))
		draw_rect(Rect2(1, 1, 5, 5), Color("#38b764"))
		draw_rect(Rect2(-3, 5, 4, 2), Color("#38b764"))
		draw_rect(Rect2(-4, -9, 6, 2), Color("#f4f4f4"))
