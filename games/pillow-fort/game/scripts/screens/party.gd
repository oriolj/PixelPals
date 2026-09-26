extends Node2D
## Party: the lamp is on, the eight toys and the riders dance in front of the
## fort under falling confetti. Then everyone yawns, the dancing stops, the
## lamp dims to a soft dusk (a bedtime ending) and it goes back to select.
## The flashlight seat's "a" skips ahead after SKIP_GUARD.

const Layout := preload("res://scripts/fort/room_layout.gd")
const Nightcap := preload("res://scripts/nightcap.gd")

const DANCE_UNTIL := 8.0
const YAWN_AT := 8.4
const DIM_FROM := 9.0
const DIM_TIME := 3.0
const STAY_SECONDS := 14.0
const SKIP_GUARD := 1.5
const DIM_ALPHA := 0.35
const TOY_TINTS := {
	"teddy": Color("#ef7d57"), "bunny": Color("#f4f4f4"), "duck": Color("#ffcd75"), "ball": Color("#b13e53"),
	"blocks": Color("#41a6f6"), "dino": Color("#38b764"), "car": Color("#b13e53"), "doll": Color("#73eff7"),
}
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

var time := 0.0
var done := false
var yawned := false
var dancers: Array[AnimatedSprite2D] = []
var homes: Array[Vector2] = []
var confetti: Array[Dictionary] = []
var lamp: AnimatedSprite2D
var veil: ColorRect
var rng := RandomNumberGenerator.new()
var _confetti_t := 0.0


func _ready() -> void:
	rng.randomize()
	_build()
	Sfx.stop_music()
	Sfx.play("party")
	Sfx.music("music_party")


func _process(delta: float) -> void:
	step(delta)


## The toys to show: the ones found this round (all eight after a normal round).
func toys() -> Array[String]:
	var out: Array[String] = []
	for t in Game.toys_found:
		if Game.TOYS.has(t) and not out.has(t):
			out.append(t)
	if out.is_empty():
		out.assign(Game.TOYS)
	return out


func riders() -> Array[String]:
	var out: Array[String] = []
	for seat in Players.SEAT_COUNT:
		var r: String = Players.riders[seat]
		if r == "" and Players.is_seated(seat) and not Game.roster.is_empty():
			r = Game.roster[seat % Game.roster.size()]
		if r != "":
			out.append(r)
	return out


func _build() -> void:
	var bg := Art.sprite("room_bg", Color("#94b0c2"), Vector2i(320, 180))
	bg.centered = false
	add_child(bg)
	var fort := Art.sprite("fort", Color("#b13e53"), Vector2i(96, 64))
	fort.position = Vector2(Layout.FORT_POS)
	fort.speed_scale = 2.0
	add_child(fort)
	lamp = Art.sprite("lamp", Color("#ffcd75"), Vector2i(16, 32))
	lamp.stop()
	lamp.frame = 1
	lamp.position = Vector2(Layout.LAMP_POS)
	add_child(lamp)
	# Riders in the fort's doorway, in their nightcaps.
	var seat := 0
	for r in riders():
		var s := Art.sprite(r, Game.rider_color(r), Vector2i(16, 16))
		var cap := Nightcap.new()
		cap.color = Players.SEAT_COLORS[seat % Players.SEAT_COUNT]
		s.add_child(cap)
		add_child(s)
		_add_dancer(s, Vector2(Layout.RIDER_SEATS[seat % 3]))
		seat += 1
	# The toys in a line on the rug, in front of the fort.
	var list := toys()
	for i in list.size():
		var s := Art.sprite(list[i], TOY_TINTS.get(list[i], Color.WHITE), Vector2i(16, 16))
		add_child(s)
		var x := 160 - (list.size() - 1) * 10 + i * 20
		_add_dancer(s, Vector2(x, 156))
	veil = ColorRect.new()
	veil.size = Vector2(320, 180)
	veil.color = Color("#5d275d", 0.0)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(veil)


func _add_dancer(s: AnimatedSprite2D, at: Vector2) -> void:
	s.position = at
	dancers.append(s)
	homes.append(at)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	for i in dancers.size():
		var d := dancers[i]
		var hop := 0.0
		if time < DANCE_UNTIL:
			hop = absf(sin(time * 6.0 + i * 0.9)) * 6.0
			d.flip_h = int(time * 2.0 + i) % 2 == 0
		elif time >= YAWN_AT:
			# Sleepy: settle one pixel lower, stop bouncing, slow blink via frames.
			hop = -1.0
			d.stop()
			d.frame = 0
		d.position = homes[i] - Vector2(0, roundf(hop))
	if time >= YAWN_AT and not yawned:
		yawned = true
		Sfx.play("yawn")
	if time >= DIM_FROM:
		var k := clampf((time - DIM_FROM) / DIM_TIME, 0.0, 1.0)
		veil.color.a = DIM_ALPHA * k
		if k >= 0.5:
			lamp.frame = 0
	if time < DANCE_UNTIL:
		_confetti_t -= dt
		while _confetti_t <= 0.0:
			_confetti_t += 0.07
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
		Game.goto.call_deferred("select")


func _add_confetti() -> void:
	var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
	var c := Art.sprite("confetti", tint, Vector2i(4, 4))
	c.speed_scale = rng.randf_range(0.5, 1.5)
	c.frame = rng.randi() % 6
	add_child(c)
	var at := Vector2(rng.randi_range(0, 320), -4)
	confetti.append({"node": c, "pos": at, "vel": Vector2(0, rng.randf_range(30, 55))})
