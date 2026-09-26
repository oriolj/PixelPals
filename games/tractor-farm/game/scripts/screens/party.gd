extends Node2D
## The village fair. The barn's crops pop into four stacks, one per crop (a
## bar chart made of real vegetables, one icon per crop in the barn), the
## giant vegetable stands on a podium with a rosette, the riders and the
## animals dance under confetti. Any toddler press throws more confetti.
## After STAY_SECONDS, or the driver's "a" (after a short guard), back to
## select.

const S := preload("res://scripts/draw/shapes.gd")
const P := preload("res://scripts/draw/pal.gd")
const Crops := preload("res://scripts/draw/crop_art.gd")
const Farm := preload("res://scripts/draw/farm_art.gd")
const Painter := preload("res://scripts/draw/painter.gd")

const STAY_SECONDS := 14.0
const SKIP_GUARD := 1.0
const FIRST_POP := 0.8
const POP_EVERY := 0.08
const STACK_X: Array[float] = [150.0, 270.0, 390.0, 510.0]
const STACK_BOTTOM := 560.0
const STACK_TOP := 150.0
const PODIUM := Vector2(900, 560)
const ANIMALS := ["bunny", "pig", "hen", "duck", "frog"]

var time := 0.0
var done := false
## Crops shown so far per stack; ends equal to Game.barn.
var shown: Array[int] = [0, 0, 0, 0]
var counts: Array[int] = [0, 0, 0, 0]
var giant := 0
var confetti: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _pop_t := FIRST_POP
var _confetti_t := 0.0
var _order: Array[int] = []
var _riders: Array[AnimatedSprite2D] = []
var _view: Node2D


func _ready() -> void:
	rng.seed = 11
	counts = Game.barn.duplicate()
	giant = clampi(Game.giant_crop, 0, 3)
	# Pop order: round-robin over the stacks, so the bars grow together.
	var left := counts.duplicate()
	var more := true
	while more:
		more = false
		for c in 4:
			if left[c] > 0:
				left[c] -= 1
				_order.append(c)
				more = true
	_view = Painter.new(_draw_view)
	add_child(_view)
	var ids := dancers()
	for i in ids.size():
		var r := Game.rider_sprite(ids[i], 5.0)
		r.position = Vector2(PODIUM.x + [-170, 170, -250][i % 3], 640)
		r.z_index = 3
		add_child(r)
		_riders.append(r)
	Sfx.music("music_fair")
	Sfx.play("rainbow")


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


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	_pop_t -= dt
	while _pop_t <= 0.0 and not _order.is_empty():
		_pop_t += POP_EVERY
		var c: int = _order.pop_front()
		shown[c] += 1
		Sfx.play("harvest_pop", 0.9 + 0.03 * (shown[c] % 12), -6.0)
		if _order.is_empty():
			Sfx.play("ripe")
	for i in _riders.size():
		_riders[i].position.y = 640.0 - absf(sin(time * 5.0 + i * 1.3)) * 30.0
		_riders[i].flip_h = int(time * 1.5 + i) % 2 == 1
	if Players.just_pressed(Players.Seat.HONKER, "any"):
		for i in 30:
			_add_confetti(Vector2(rng.randf_range(0, 1280), rng.randf_range(-40, 200)))
		Sfx.play(["quack", "oink", "cluck", "ribbit", "bunny_boing"][rng.randi() % 5])
	_confetti_t -= dt
	while _confetti_t <= 0.0:
		_confetti_t += 0.05
		_add_confetti(Vector2(rng.randf_range(0, 1280), -10))
	for i in range(confetti.size() - 1, -1, -1):
		var c := confetti[i]
		c.pos += c.vel * dt
		c.vel.x = sin(time * 3.0 + i) * 40.0
		c.rot += c.spin * dt
		if c.pos.y > 740:
			confetti.remove_at(i)
	_view.queue_redraw()
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(Players.Seat.DRIVER, "a")):
		done = true
		Game.goto("select")


func _add_confetti(at: Vector2) -> void:
	confetti.append({"pos": at, "vel": Vector2(0, rng.randf_range(90, 170)), "rot": rng.randf() * TAU,
		"spin": rng.randf_range(-6, 6), "col": P.CONFETTI[rng.randi() % P.CONFETTI.size()]})


func _stack_step() -> float:
	var most := 1
	for v in counts:
		most = maxi(most, v)
	return minf(34.0, (STACK_BOTTOM - 40.0 - STACK_TOP) / most)


func _draw_view(ci: CanvasItem) -> void:
	ci.draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 520), Vector2(0, 520)]),
		PackedColorArray([P.SKY_TOP, P.SKY_TOP, P.SKY_LOW, P.SKY_LOW]))
	S.xform(ci, Vector2(1180, 80))
	Farm.sun(ci, 44, time, 0.3)
	S.reset(ci)
	# Fair tent behind the podium.
	var tent := Rect2(700, 250, 400, 290)
	for i in 8:
		ci.draw_rect(Rect2(tent.position.x + i * 50, tent.position.y, 50, tent.size.y), P.WHITE if i % 2 == 0 else P.STRAWBERRY)
	ci.draw_rect(tent, P.INK, false, 3.0)
	S.fill_ink(ci, PackedVector2Array([Vector2(680, 252), Vector2(900, 150), Vector2(1120, 252)]), P.STRAWBERRY, P.INK, 3.0)
	S.disc(ci, Vector2(900, 146), 10, P.SUNFLOWER)
	ci.draw_rect(Rect2(0, 520, 1280, 200), P.GRASS)
	for i in 3:
		ci.draw_rect(Rect2(0, 540 + i * 60, 1280, 26), P.GRASS_DARK.lerp(P.GRASS, 0.5))
	_bunting(ci)
	# The bar chart: a crate under each stack, vegetables piled up.
	var stepy := _stack_step()
	for c in 4:
		S.box(ci, Rect2(STACK_X[c] - 44, STACK_BOTTOM - 4, 88, 16), 6, P.WOOD_DARK)
		for k in shown[c]:
			var y := STACK_BOTTOM - 26.0 - k * stepy
			var pop := 1.0
			Crops.icon(ci, c, 46.0 * pop, Vector2(STACK_X[c] + (6.0 if k % 2 == 1 else -6.0), y))
		S.xform(ci, Vector2(STACK_X[c], STACK_BOTTOM + 44))
		Farm.crate(ci, c, 0)
		S.reset(ci)
	# Podium, giant vegetable, rosette.
	S.box(ci, Rect2(PODIUM.x - 120, PODIUM.y - 60, 240, 70), 8, P.SUNFLOWER, P.INK, 3.0)
	S.box(ci, Rect2(PODIUM.x - 200, PODIUM.y - 20, 80, 30), 6, P.METAL, P.INK, 3.0)
	S.box(ci, Rect2(PODIUM.x + 120, PODIUM.y - 10, 80, 20), 6, P.WOOD, P.INK, 3.0)
	S.fill_ink(ci, S.star(Vector2(PODIUM.x, PODIUM.y - 25), 18, 8), P.WHITE)
	var gk := minf(1.0, time / 1.2)
	var bounce := 1.0 + sin(time * 4.0) * 0.03
	ci.draw_circle(Vector2(PODIUM.x, PODIUM.y - 190), 150 * gk, Color(1, 1, 0.7, 0.35), true, -1.0, true)
	S.local(ci, Vector2(PODIUM.x, PODIUM.y - 60), Vector2(5.0 * gk / bounce, 5.0 * gk * bounce))
	S.aa = false
	Crops.draw(ci, giant, 3)
	S.aa = true
	S.unlocal(ci)
	_rosette(ci, Vector2(PODIUM.x + 120, PODIUM.y - 150))
	# Dancing animals along the front.
	for i in ANIMALS.size():
		var pose := int(time * 5.0 + i) % 2
		var x := 90.0 + i * 120.0
		var f := 1.0 if int(time * 1.2 + i) % 2 == 0 else -1.0
		S.xform(ci, Vector2(x, 690), 0.0, Vector2(1.7 * f, 1.7))
		Farm.animal(ci, ANIMALS[i], pose)
		S.reset(ci)
	for c in confetti:
		S.xform(ci, c.pos, c.rot)
		ci.draw_rect(Rect2(-6, -4, 12, 8), c.col)
	S.reset(ci)


func _bunting(ci: CanvasItem) -> void:
	for row in 2:
		var y0 := 30.0 + row * 50.0
		var pts := S.curve(Vector2(-20, y0), Vector2(640, y0 + 70), Vector2(1300, y0), 24)
		S.path(ci, pts, P.INK, 3.0)
		for i in range(0, pts.size() - 1):
			var a := pts[i]
			var b := pts[i + 1]
			var m := (a + b) * 0.5 + Vector2(0, 30)
			S.fill_ink(ci, PackedVector2Array([a, b, m]), P.CONFETTI[(i + row * 3) % 6], P.INK, 2.0)


func _rosette(ci: CanvasItem, c: Vector2) -> void:
	for sx in [-1.0, 1.0]:
		S.fill_ink(ci, PackedVector2Array([c + Vector2(sx * 6, 10), c + Vector2(sx * 26, 80), c + Vector2(sx * 14, 72),
			c + Vector2(sx * 4, 84), c + Vector2(-sx * 4, 14)]), Color("#3f6fd6"))
	for i in 16:
		var a := TAU * i / 16.0
		S.disc(ci, c + Vector2(cos(a), sin(a)) * 30, 11, Color("#3f6fd6"), P.INK, 2.0)
	S.disc(ci, c, 30, Color("#5b8cf0"), P.INK, 3.0)
	S.fill_ink(ci, S.star(c, 22, 10), P.SUNFLOWER, P.INK, 2.0)
