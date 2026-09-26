extends Node2D
## Party: the dump truck drives in, tips its load, and every treasure of the
## run bounces out into a row, one by one, under falling confetti while the
## riders dance in their hard hats. No numbers: the row IS the haul. After
## STAY_SECONDS, or the driver's "a" (after a short guard), back to select.

const RiderView := preload("res://scripts/rider_view.gd")

const STAY_SECONDS := 13.0
const SKIP_GUARD := 1.5            # ignore an "a" still held from the dig
const DRIVE_IN := 2.2
const TRUCK_FROM := -60.0
const TRUCK_AT := 92.0
const TRUCK_Y := 118.0             # the truck is drawn at 2x (96x48)
const TIP_AT := 2.6
const OUT_EVERY := 0.32
const HOP_TIME := 0.7
const ROW_Y := 44.0
const GROUND_Y := 142

const C_SKY := Color("#41a6f6")
const C_SKY_LOW := Color("#73eff7")
const C_WHITE := Color("#f4f4f4")
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

var time := 0.0
var done := false
var truck: AnimatedSprite2D
var tipped := false
## {node, kind, slot: Vector2, t, landed}
var items: Array[Dictionary] = []
var dancers: Array[Node2D] = []
var trophy: AnimatedSprite2D
var confetti: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _out_t := 0.0
var _confetti_t := 0.0
var _kinds: Array[String] = []


func _ready() -> void:
	rng.randomize()
	_kinds.assign(Game.found)
	_build()
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func _build() -> void:
	var sky := ColorRect.new()
	sky.size = Vector2(320, 70)
	sky.color = C_SKY
	add_child(sky)
	var low := ColorRect.new()
	low.position = Vector2(0, 70)
	low.size = Vector2(320, 60)
	low.color = C_SKY_LOW
	add_child(low)
	var hills := Art.sprite("sky_hills", Color("#257179"), Vector2i(320, 48))
	hills.position = Vector2(160, GROUND_Y - 30)
	add_child(hills)
	var dirt := ColorRect.new()
	dirt.position = Vector2(0, GROUND_Y)
	dirt.size = Vector2(320, 180 - GROUND_Y)
	dirt.color = Color("#ef7d57")
	add_child(dirt)
	var deep := ColorRect.new()
	deep.position = Vector2(0, 166)
	deep.size = Vector2(320, 14)
	deep.color = Color("#b13e53")
	add_child(deep)
	var grass := Art.sprite("grass_strip", Color("#38b764"), Vector2i(320, 16))
	grass.position = Vector2(160, GROUND_Y - 4)
	add_child(grass)

	trophy = Art.sprite("trophy", Color("#ffcd75"), Vector2i(24, 24))
	trophy.position = Vector2(160, 16)
	trophy.visible = false
	add_child(trophy)

	truck = Art.sprite("dump_truck", Color("#b13e53"), Vector2i(48, 24))
	truck.stop()
	truck.frame = 2 if not _kinds.is_empty() else 0
	truck.scale = Vector2(2, 2)
	truck.position = Vector2(TRUCK_FROM, TRUCK_Y)
	add_child(truck)

	var ids := dancer_ids()
	for i in ids.size():
		var rv := RiderView.new()
		add_child(rv)
		rv.setup(ids[i].rider, ids[i].seat)
		rv.position = Vector2(206 + i * 34, GROUND_Y - 8)
		rv.flip(i % 2 == 1)
		dancers.append(rv)


## The seated riders (with their seats, for the helmet colours), or the
## first three of the roster when nobody is seated.
func dancer_ids() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for seat in Players.SEAT_COUNT:
		var r: String = Players.riders[seat]
		if r == "" and Players.is_seated(seat) and not Game.roster.is_empty():
			r = Game.roster[seat % Game.roster.size()]
		if r != "":
			out.append({"rider": r, "seat": seat})
	if out.is_empty():
		for i in mini(3, Game.roster.size()):
			out.append({"rider": Game.roster[i], "seat": i})
	return out


## Where the i-th treasure lands: one row across the sky, centred.
func slot(i: int, n: int) -> Vector2:
	var gap := 24.0 if n <= 12 else 288.0 / n
	var x0 := 160.0 - gap * (n - 1) * 0.5
	return Vector2(roundf(x0 + gap * i), ROW_Y + (8.0 if i % 2 == 1 else 0.0))


func step(dt: float) -> void:
	if done:
		return
	time += dt
	# The truck drives in, then tips.
	var u := clampf(time / DRIVE_IN, 0.0, 1.0)
	var eased := 1.0 - (1.0 - u) * (1.0 - u)
	truck.position = Vector2(roundf(lerpf(TRUCK_FROM, TRUCK_AT, eased)), TRUCK_Y - (1 if u < 1.0 and int(time * 12.0) % 2 == 0 else 0))
	if not tipped and time >= TIP_AT:
		tipped = true
		truck.frame = 3
		Sfx.play("truck_clunk", 0.8)
		_out_t = 0.0
	if tipped and items.size() < _kinds.size():
		_out_t -= dt
		if _out_t <= 0.0:
			_out_t = OUT_EVERY
			_launch(items.size())
	for i in items.size():
		var it := items[i]
		it.t += dt
		var k := clampf(it.t / HOP_TIME, 0.0, 1.0)
		var from: Vector2 = it.from
		var to: Vector2 = it.slot
		if k < 1.0:
			var p := from.lerp(to, k) + Vector2(0, -50.0 * sin(k * PI))
			it.node.position = p.round()
			it.node.rotation = floorf(it.t * 10.0) * PI * 0.5
		else:
			if not it.landed:
				it.landed = true
				it.node.rotation = 0.0
				Sfx.play("treasure_pop", 0.9 + 0.05 * i, -6.0)
			# Keep bouncing on their own beat.
			var hop := absf(sin((time - it.born) * 4.0 + i * 0.7)) * 3.0
			it.node.position = (to + Vector2(0, -roundf(hop))).round()
	if items.size() == _kinds.size() and (items.is_empty() or items[-1].landed) and not trophy.visible and tipped:
		trophy.visible = true
		Sfx.play("ready")
	if trophy.visible:
		trophy.position.y = 16 - (1 if fmod(time, 0.5) < 0.25 else 0)
	for i in dancers.size():
		var hop := absf(sin(time * 6.0 + i * 1.3)) * 6.0
		dancers[i].position.y = GROUND_Y - 8 - roundf(hop)

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


func _launch(i: int) -> void:
	var kind := _kinds[i]
	var n := Art.sprite(kind, Color("#ffcd75"), Vector2i(16, 16))
	# Out of the tipped bed's back end (left of the truck).
	var from := truck.position + Vector2(-44, -14)
	n.position = from
	add_child(n)
	items.append({"node": n, "kind": kind, "from": from, "slot": slot(i, _kinds.size()), "t": 0.0,
		"landed": false, "born": time})
	Sfx.play("scoop", 1.2 + 0.04 * i, -4.0)


func _add_confetti() -> void:
	var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
	var c := Art.sprite("confetti", tint, Vector2i(4, 4))
	c.speed_scale = rng.randf_range(0.5, 1.5)
	c.frame = rng.randi() % 6
	add_child(c)
	var at := Vector2(rng.randi_range(0, 320), -4)
	confetti.append({"node": c, "pos": at, "vel": Vector2(0, rng.randf_range(30, 55))})
