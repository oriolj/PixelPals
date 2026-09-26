extends Node2D
## The zoo: a path loop between six enclosures, a screen and a half wide.
##
## - Keeper (seat 1) walks with the food cart; standing at a hungry animal's
##   feeding spot opens the food wheel.
## - Feeder (seat 2) picks a food on the wheel (4 directions) and throws it.
##   Without a feeder the keeper's own stick picks and "a" throws (solo).
## - Singer (seat 3): any button makes the nearest animal sing and dance.
## No game over: a wrong food costs nothing, and the run ends after 12 meals
## or at the bell (7 minutes). All logic runs in step(dt) so tests can drive
## it frame by frame with set_process(false) and scripted devices.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Animals := preload("res://scripts/vector/animals.gd")
const Rules := preload("res://scripts/zoo/rules.gd")
const Scheduler := preload("res://scripts/zoo/scheduler.gd")
const Animal := preload("res://scripts/zoo/animal.gd")
const FoodWheel := preload("res://scripts/zoo/food_wheel.gd")

const W := 1920.0
const H := 720.0
const VIEW_W := 1280.0
const KEEPER := 0
const FEEDER := 1
const SINGER := 2

# Layout: three enclosures above the path, three below.
const ENC_SIZE := Vector2(330, 215)
const TOP_Y := 40.0
const BOTTOM_Y := 470.0
const COLS: Array[float] = [90.0, 795.0, 1500.0]
const LAYOUT := {
	"monkey": [0, true], "penguin": [1, true], "giraffe": [2, true],
	"rabbit": [0, false], "elephant": [1, false], "seal": [2, false],
}
const PATH_RECT := Rect2(24, 258, 1872, 206)
const WALK_RECT := Rect2(70, 292, 1780, 160)   # where the keeper's feet may go
const FLOWERBEDS: Array[Rect2] = [Rect2(470, 342, 290, 44), Rect2(1165, 342, 290, 44)]
const SPOT_R := 72.0
## The keeper stands beside the gate (not in front of the animal), on the side
## with room for the wheel: right of the left column, left of the others.
const SPOT_DX: Array[float] = [95.0, -95.0, -95.0]
const KEEPER_START := Vector2(640, 424)
const KEEPER_SPEED := 300.0
const CART_OFFSET := 78.0
const SOLO_HOLD_TO_WALK := 0.45
const FLIGHT_SECONDS := 0.5
const BACK_SECONDS := 0.5
const BELL_SECONDS := 4.5
const TRAIL_STEP := 16.0

enum Phase { RUN, ROUND_BREAK, FINISH, BELL, DONE }

var auto_goto := true
var next_screen := ""

var phase := Phase.RUN
var phase_t := 0.0
var paused := false
var time := 0.0
var run_len := Rules.RUN_SECONDS
var rng := RandomNumberGenerator.new()
var scheduler := Scheduler.new()

var stars := 0
var meals := 0
var throws := 0
var bounced_back := 0
var hungry_ids: Array[String] = []
var gap_t := Rules.FIRST_HUNGER
var sing_cd := 0.0
var call_t := 9.0

var keeper_pos := KEEPER_START
var facing := 1.0
var walk_t := 0.0
var cart_pos := KEEPER_START + Vector2(CART_OFFSET, 6)
## The hungry animal whose feeding spot the keeper stands at ("" = none).
var at_animal := ""
var throw_lock := false
var _solo_hold := 0.0
var _solo_armed := false
var _cart_jiggle := 0.0
var _trail: Array[Vector2] = []

var animals := {}                 # kind -> Animal
var flights: Array[Dictionary] = []
var fx: Array[Dictionary] = []

var world: Node2D
var actors: Node2D
var fx_layer: Node2D
var keeper: Node2D
var cart: Node2D
var buddies: Array[Dictionary] = []   # {node, seat, kind}
var wheel: Node2D
var bell_node: Node2D
var spot_marks := {}              # kind -> Node2D
var cam: Camera2D
var hud: CanvasLayer
var plates_row: Node2D
var edge_marks := {}              # kind -> Node2D
var pause_overlay: Node2D


func _ready() -> void:
	rng.randomize()
	run_len = Rules.run_length(Game.run_seconds)
	scheduler.build(rng, Game.first_hungry)
	_build()
	Sfx.music("music_zoo")


func _process(delta: float) -> void:
	step(delta)


# ================================================================ build

func _build() -> void:
	world = Node2D.new()
	world.name = "World"
	add_child(world)
	_build_ground()
	var top := VA.part(world, "top_row")
	var marks := VA.part(world, "spots")
	actors = VA.part(world, "actors")
	actors.y_sort_enabled = true
	var bottom := VA.part(world, "bottom_row")
	fx_layer = VA.part(world, "fx")
	fx_layer.z_index = 10
	var seed_i := 0
	for kind in Rules.ANIMALS:
		var col: int = LAYOUT[kind][0]
		var is_top: bool = LAYOUT[kind][1]
		var origin := Vector2(COLS[col], TOP_Y if is_top else BOTTOM_Y)
		var enc := Props.enclosure(kind, ENC_SIZE, not is_top)
		enc.position = origin
		(top if is_top else bottom).add_child(enc)
		var a: Node2D = Animal.new()
		a.name = kind
		var area := Rect2(70, 110, 190, 70) if is_top else Rect2(70, 120, 190, 64)
		var gate := Vector2(ENC_SIZE.x / 2.0, ENC_SIZE.y - 22.0) if is_top else Vector2(ENC_SIZE.x / 2.0, 104.0)
		a.setup(kind, area, gate, 1000 + seed_i)
		seed_i += 1
		# Between the back (ground, features, back fence) and the front fence.
		enc.add_child(a)
		enc.move_child(enc.get_node("front"), -1)
		var cx := origin.x + ENC_SIZE.x / 2.0
		a.spot = Vector2(cx + SPOT_DX[col], 300.0 if is_top else 428.0)
		animals[kind] = a
		var mark := _spot_mark()
		mark.position = a.spot + Vector2(0, 4)
		marks.add_child(mark)
		spot_marks[kind] = mark

	cart = Props.cart()
	actors.add_child(cart)
	keeper = Props.keeper(Game.hat_color(KEEPER))
	actors.add_child(keeper)
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.riders[s] != "":
			_add_buddy(s, Players.riders[s])
	for i in 60:
		_trail.append(keeper_pos)

	wheel = FoodWheel.new()
	wheel.z_index = 20
	world.add_child(wheel)
	wheel.set_ring_color(Players.SEAT_COLORS[FEEDER])

	bell_node = Props.bell(1.2)
	bell_node.visible = false
	bell_node.z_index = 21
	world.add_child(bell_node)

	cam = Camera2D.new()
	cam.limit_left = 0
	cam.limit_right = int(W)
	cam.limit_top = 0
	cam.limit_bottom = int(H)
	cam.position = Vector2(clampf(keeper_pos.x, VIEW_W / 2.0, W - VIEW_W / 2.0), H / 2.0)
	add_child(cam)
	cam.make_current()

	_build_hud()
	_place_nodes(0.0)


func _build_ground() -> void:
	var g := VA.part(world, "ground")
	VA.fill(g, PackedVector2Array([Vector2(0, 0), Vector2(W, 0), Vector2(W, H), Vector2(0, H)]), Pal.GRASS)
	# Lawn texture: soft lighter patches and tufts.
	var r := RandomNumberGenerator.new()
	r.seed = 7
	for i in 40:
		var p := Vector2(r.randf_range(0, W), r.randf_range(0, H))
		VA.fill(g, VA.ellipse(r.randf_range(30, 70), r.randf_range(10, 20), p, 16), Pal.GRASS_LIGHT if i % 2 == 0 else Pal.GRASS_DARK)
	# The path loop: a wide avenue with rounded ends and flowerbed islands.
	VA.shape(g, VA.rrect(PATH_RECT, 90), Pal.PATH, Pal.OUTLINE, 5.0)
	for i in 70:
		var p := Vector2(r.randf_range(PATH_RECT.position.x + 60, PATH_RECT.end.x - 60), r.randf_range(PATH_RECT.position.y + 16, PATH_RECT.end.y - 16))
		VA.fill(g, VA.ellipse(r.randf_range(7, 14), r.randf_range(4, 7), p, 12), Pal.PATH_DARK)
	for bed in FLOWERBEDS:
		VA.shape(g, VA.rrect(bed, 22), Pal.GRASS, Pal.OUTLINE, 4.5)
		for k in 7:
			var fp := Vector2(bed.position.x + 26 + k * (bed.size.x - 52) / 6.0, bed.get_center().y + (6 if k % 2 == 0 else -6))
			var c: Color = [Pal.HEART, Color("#b58cff"), Pal.CREAM][k % 3]
			for j in 5:
				var a := TAU * j / 5.0
				VA.shape(g, VA.circle(5, fp + Vector2(cos(a), sin(a)) * 6, 10), c, Pal.OUTLINE, 2.0)
			VA.fill(g, VA.circle(4, fp, 10), Pal.STAR)
	# A fountain at the middle of the loop.
	var f := Vector2(W / 2.0, 364)
	VA.shape(g, VA.ellipse(46, 20, f), Pal.ROCK, Pal.OUTLINE, 4.5)
	VA.fill(g, VA.ellipse(36, 13, f + Vector2(0, -2)), Pal.WATER)
	VA.shape(g, VA.rrect(Rect2(f + Vector2(-7, -34), Vector2(14, 32)), 5), Pal.ROCK, Pal.OUTLINE, 3.5)
	VA.shape(g, VA.blob([f + Vector2(-4, -34), f + Vector2(-16, -50), f + Vector2(0, -62), f + Vector2(16, -50), f + Vector2(4, -34)], 5), Pal.SKY, Pal.OUTLINE, 3.0)
	# Trees along the edges (outside the enclosures).
	for tp in [Vector2(30, 120), Vector2(1890, 110), Vector2(30, 640), Vector2(1890, 650), Vector2(600, 60), Vector2(1320, 700), Vector2(600, 700), Vector2(1320, 60)]:
		VA.shadow(g, 40, 10, tp + Vector2(0, 6))
		VA.shape(g, VA.rrect(Rect2(tp + Vector2(-8, -40), Vector2(16, 44)), 5), Pal.BARK, Pal.OUTLINE, 4.0)
		var ctrl := []
		for i in 9:
			var a := TAU * i / 9.0
			var rr := 1.0 if i % 2 == 0 else 0.85
			ctrl.append(tp + Vector2(cos(a) * 44 * rr, sin(a) * 36 * rr - 62))
		VA.shape(g, VA.blob(ctrl, 6), Pal.LEAF, Pal.OUTLINE, 4.0)


func _spot_mark() -> Node2D:
	var m := Node2D.new()
	VA.shape(m, VA.ellipse(44, 15), Pal.PATH_DARK, Pal.OUTLINE, 3.5)
	# A paw print: the keeper stops here to feed.
	VA.fill(m, VA.ellipse(8, 5.5, Vector2(0, 2)), Pal.FENCE)
	for k in 4:
		VA.fill(m, VA.circle(3, Vector2(-9 + k * 6, -5 + absf(k - 1.5) * 2.0), 8), Pal.FENCE)
	var ring := VA.stroke(m, VA.ellipse(52, 19), Pal.CREAM, 5.0, "ring")
	ring.closed = true
	ring.visible = false
	return m


func _add_buddy(seat: int, kind: String) -> void:
	var b := Animals.build(kind)
	b.scale = Vector2(0.42, 0.42)
	Animals.add_hat(b, Game.hat_color(seat))
	actors.add_child(b)
	buddies.append({"node": b, "seat": seat, "kind": kind})


func _build_hud() -> void:
	hud = CanvasLayer.new()
	hud.layer = 5
	add_child(hud)
	plates_row = Node2D.new()
	plates_row.position = Vector2(640, 34)
	hud.add_child(plates_row)
	_refresh_plates()
	for kind in Rules.ANIMALS:
		var m := Node2D.new()
		var b := Props.bubble()
		b.scale = Vector2(0.55, 0.55)
		m.add_child(b)
		var ar := Props.arrow(Pal.CREAM, 1)
		ar.name = "arrow"
		m.add_child(ar)
		m.visible = false
		hud.add_child(m)
		edge_marks[kind] = m
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	hud.add_child(pause_overlay)


func _refresh_plates() -> void:
	for c in plates_row.get_children():
		c.free()
	var panel := VA.shape(plates_row, VA.rrect(Rect2(-280, -24, 560, 48), 24), Color(Pal.CREAM, 0.85), Pal.OUTLINE, 4.0)
	panel.name = "panel"
	for i in Rules.TOTAL_MEALS:
		var p := Props.plate(i < meals)
		var x := -250.0 + i * 40.0 + (20.0 if i >= Rules.ROUND_MEALS else 0.0)
		p.position = Vector2(x + 20, 0)
		plates_row.add_child(p)


# ================================================================ frame

func step(dt: float) -> void:
	if phase == Phase.DONE:
		return
	if _pause_input():
		return
	time += dt
	phase_t += dt
	sing_cd = maxf(0.0, sing_cd - dt)
	_cart_jiggle = maxf(0.0, _cart_jiggle - dt)

	var moving := _keeper(dt)
	_update_spot()
	_picking(dt, moving)
	_singer()
	_idle_calls(dt)
	_hunger(dt)
	_phases()
	_update_flights(dt)
	_update_fx(dt)
	var beat := _beat()
	for kind in animals:
		(animals[kind] as Animal).update(dt, beat, keeper_pos.x)
	_place_nodes(dt)


func solo() -> bool:
	return not Players.is_seated(FEEDER)


func _keeper(dt: float) -> bool:
	var mv := Players.move(KEEPER)
	if phase in [Phase.BELL, Phase.FINISH]:
		mv = Vector2.ZERO
	if solo() and wheel.is_open and _solo_armed:
		# Solo picking: the stick picks; holding it walks away again.
		if mv.length() > Players.DEADZONE:
			_solo_hold += dt
			if _solo_hold < SOLO_HOLD_TO_WALK:
				mv = Vector2.ZERO
		else:
			_solo_hold = 0.0
	if mv.length() < 0.05:
		return false
	var next := keeper_pos + mv * KEEPER_SPEED * dt
	next.x = clampf(next.x, WALK_RECT.position.x, WALK_RECT.end.x)
	next.y = clampf(next.y, WALK_RECT.position.y, WALK_RECT.end.y)
	for bed in FLOWERBEDS:
		if bed.grow(6).has_point(next) and not bed.grow(6).has_point(keeper_pos):
			# Slide along the flowerbed instead of walking through it.
			if not bed.grow(6).has_point(Vector2(next.x, keeper_pos.y)):
				next.y = keeper_pos.y
			elif not bed.grow(6).has_point(Vector2(keeper_pos.x, next.y)):
				next.x = keeper_pos.x
			else:
				next = keeper_pos
	if absf(mv.x) > 0.2:
		facing = signf(mv.x)
	var was := int(walk_t / 0.14)
	walk_t += dt * mv.length()
	if int(walk_t / 0.14) != was and int(walk_t / 0.14) % 2 == 0:
		Sfx.play("footstep", 1.0 + rng.randf() * 0.1, -10.0)
	keeper_pos = next
	return true


## The hungry animal whose feeding spot the keeper stands at.
func _update_spot() -> void:
	var best := ""
	var best_d := SPOT_R
	if phase == Phase.RUN:
		for kind in hungry_ids:
			var d := keeper_pos.distance_to((animals[kind] as Animal).spot)
			if d < best_d:
				best_d = d
				best = kind
	if best != at_animal:
		at_animal = best
		_solo_armed = false
		_solo_hold = 0.0
		if best != "":
			Sfx.play("bubble_pop", 1.3, -4.0)
	var open := at_animal != ""
	if open and not wheel.is_open:
		wheel.open(true)
	elif not open and wheel.is_open:
		wheel.open(false)
	if at_animal != "":
		var a: Animal = animals[at_animal]
		wheel.set_hint(Rules.hint_for(a.wrong_tries), Rules.right_food(a.kind))


## The feeder's wheel input, or the keeper's in solo play.
func _picking(_dt: float, _moving: bool) -> void:
	if solo():
		if not wheel.is_open:
			return
		if not _solo_armed:
			if Players.move(KEEPER).length() < Players.DEADZONE:
				_solo_armed = true
			return
		var flick := Players.dir4_just_pressed(KEEPER)
		if flick != Vector2i.ZERO and wheel.select_dir(flick):
			Sfx.play("select", 1.0 + 0.1 * Rules.FOODS.find(wheel.selected))
		if Players.just_pressed(KEEPER, "a"):
			_try_throw()
		return
	# Keeper's "a" with a feeder present: ring the cart's little bell (animals look).
	if Players.just_pressed(KEEPER, "a"):
		Sfx.play("bell", 1.8, -8.0)
		_cart_jiggle = 0.3
	var d := Players.dir4(FEEDER)
	if wheel.is_open and d != Vector2i.ZERO and wheel.select_dir(d):
		Sfx.play("select", 1.0 + 0.1 * Rules.FOODS.find(wheel.selected))
	if Players.just_pressed(FEEDER, "a"):
		if wheel.is_open:
			_try_throw()
		else:
			_cart_jiggle = 0.3
			Sfx.play("select", 0.7, -6.0)


func _try_throw() -> void:
	if wheel.selected == "":
		wheel.set("_bump", 0.25)
		Sfx.play("wiggle", 1.2, -6.0)
		return
	throw_food(wheel.selected)


## Throws a food at the animal whose spot the keeper stands at. Returns true
## if a food left the cart.
func throw_food(food: String) -> bool:
	if phase != Phase.RUN or at_animal == "" or throw_lock:
		return false
	var a: Animal = animals[at_animal]
	# Only a refusal in progress blocks the next throw; a song or dance (the
	# singer's doing) never gets in the feeder's way.
	if a.action in ["sniff", "shake", "eat"] or not a.hungry:
		return false
	var success := Rules.throw_succeeds(a.kind, food, a.wrong_tries)
	var node := Props.food(food)
	node.scale = Vector2(0.62, 0.62)
	fx_layer.add_child(node)
	var from := cart_pos + Vector2(0, -70)
	flights.append({"node": node, "from": from, "to": a.mouth_global(), "t": 0.0,
		"dur": FLIGHT_SECONDS, "food": food, "animal": a.kind, "kind": "throw",
		"success": success, "morph": success and not Rules.accepts(a.kind, food), "arc": 130.0})
	throw_lock = true
	throws += 1
	Sfx.play("throw", 1.0 + rng.randf() * 0.1)
	return true


func _singer() -> void:
	if Players.just_pressed(SINGER, "any"):
		singer_press()


## Any button of the singer: the nearest animal sings and dances; presses
## during the cooldown float music notes up. Never touches hunger or stars.
func singer_press() -> void:
	var a := nearest_animal(keeper_pos)
	if a == null:
		return
	if sing_cd <= 0.0:
		sing_cd = Rules.SINGER_COOLDOWN
		if not a.busy() or a.action in ["dance", "sing"]:
			a.sing()
		else:
			Game.voice(a.kind)
		for k in 3:
			_note(a.head_global() + Vector2(rng.randf_range(-30, 30), 0))
	else:
		_note(a.head_global() + Vector2(rng.randf_range(-30, 30), 0))
		Sfx.play("select", 1.5 + rng.randf() * 0.5, -8.0)


## The animal whose enclosure is nearest: measured to its feeding spot by the
## gate (stable while animals wander), so the singer's pick is predictable.
func nearest_animal(pos: Vector2) -> Animal:
	var best: Animal = null
	var best_d := INF
	for kind in animals:
		var a: Animal = animals[kind]
		var d := pos.distance_to(a.spot)
		if d < best_d:
			best_d = d
			best = a
	return best


## Without a singer, an idle animal calls out now and then.
func _idle_calls(dt: float) -> void:
	if Players.is_seated(SINGER) or phase != Phase.RUN:
		return
	call_t -= dt
	if call_t > 0.0:
		return
	call_t = rng.randf_range(Rules.IDLE_CALL_MIN, Rules.IDLE_CALL_MAX)
	var idle: Array[String] = []
	for kind in animals:
		if not (animals[kind] as Animal).busy():
			idle.append(kind)
	if not idle.is_empty():
		(animals[idle[rng.randi() % idle.size()]] as Animal).sing()


func _hunger(dt: float) -> void:
	if phase != Phase.RUN:
		return
	gap_t -= dt
	var round_i := 0 if meals < Rules.ROUND_MEALS else 1
	var round_cap := (round_i + 1) * Rules.ROUND_MEALS
	if gap_t <= 0.0 and hungry_ids.size() < Rules.MAX_HUNGRY and scheduler.has_next() and scheduler.taken() < round_cap:
		var kind := scheduler.take()
		(animals[kind] as Animal).make_hungry()
		hungry_ids.append(kind)
		gap_t = 0.8


func _phases() -> void:
	match phase:
		Phase.RUN, Phase.ROUND_BREAK:
			if time >= run_len:
				ring_bell()
				return
			if phase == Phase.ROUND_BREAK:
				_dance_all()
				if phase_t >= Rules.ROUND_BREAK:
					_set_phase(Phase.RUN)
					gap_t = Rules.FIRST_HUNGER
		Phase.FINISH:
			_dance_all()
			if phase_t >= Rules.FINISH_SECONDS:
				_finish()
		Phase.BELL:
			if phase_t >= BELL_SECONDS:
				_finish()


func _set_phase(p: int) -> void:
	phase = p
	phase_t = 0.0


func _dance_all() -> void:
	for kind in animals:
		var a: Animal = animals[kind]
		if not a.busy():
			a.dance()
	if fmod(phase_t, 0.25) < 1.0 / 30.0:
		_confetti_burst(Vector2(cam.position.x + rng.randf_range(-600, 600), rng.randf_range(80, 300)), 6)


## The 7-minute bell (or an early end): every animal gets a snack at once.
func ring_bell() -> void:
	if phase in [Phase.BELL, Phase.DONE]:
		return
	_set_phase(Phase.BELL)
	Sfx.play("bell")
	wheel.open(false)
	at_animal = ""
	for kind in animals:
		var a: Animal = animals[kind]
		a.hungry = false
		var node := Props.food(Rules.right_food(kind))
		node.scale = Vector2(0.62, 0.62)
		fx_layer.add_child(node)
		flights.append({"node": node, "from": cart_pos + Vector2(0, -70), "to": a.mouth_global(), "t": -rng.randf_range(0.0, 0.5),
			"dur": 0.9, "food": Rules.right_food(kind), "animal": kind, "kind": "snack", "arc": 220.0, "hide_wait": true})
	hungry_ids.clear()


func _finish() -> void:
	_set_phase(Phase.DONE)
	Game.stars = stars
	Game.meals = meals
	next_screen = "party"
	if auto_goto:
		Game.goto.call_deferred("party")


# ================================================================ flights and fx

func _update_flights(dt: float) -> void:
	for i in range(flights.size() - 1, -1, -1):
		var f := flights[i]
		f.t += dt
		if f.t < 0.0:
			f.node.visible = not f.get("hide_wait", false)
			continue
		f.node.visible = true
		var k: float = clampf(f.t / f.dur, 0.0, 1.0)
		var to: Vector2 = f.to
		if f.kind == "throw" or f.kind == "snack":
			to = (animals[f.animal] as Animal).mouth_global()
		elif f.kind == "back" or f.kind == "star":
			to = cart_pos + Vector2(0, -70) if f.kind == "back" else cart_pos + Vector2(56, -60)
		var p: Vector2 = (f.from as Vector2).lerp(to, k)
		p.y -= sin(k * PI) * f.arc
		f.node.position = p
		f.node.rotation += dt * (8.0 if f.kind != "star" else 3.0)
		if f.kind == "throw" and f.get("morph", false) and k >= 0.5 and not f.get("morphed", false):
			_morph(f)
		if k >= 1.0:
			flights.remove_at(i)
			_land(f)


func _morph(f: Dictionary) -> void:
	# The third try always works: the food turns into the right one mid-air.
	f.morphed = true
	var right := Rules.right_food(f.animal)
	var pos: Vector2 = f.node.position
	f.node.queue_free()
	var node := Props.food(right)
	node.scale = Vector2(0.62, 0.62)
	node.position = pos
	fx_layer.add_child(node)
	f.node = node
	f.food = right
	_sparkle(pos, 8)
	Sfx.play("wiggle")


func _land(f: Dictionary) -> void:
	match f.kind:
		"throw":
			var a: Animal = animals[f.animal]
			if f.success:
				f.node.queue_free()
				_meal(a)
			else:
				a.refuse()
				# The food bounces back into the cart.
				flights.append({"node": f.node, "from": f.node.position, "to": cart_pos, "t": -SNIFF_DELAY,
					"dur": BACK_SECONDS, "food": f.food, "animal": f.animal, "kind": "back", "arc": 90.0})
		"back":
			f.node.queue_free()
			bounced_back += 1
			throw_lock = false
			_cart_jiggle = 0.3
			Sfx.play("bubble_pop", 0.8, -4.0)
		"star":
			f.node.queue_free()
			Props.cart_stars(cart, stars)
			_cart_jiggle = 0.3
			Sfx.play("star", 1.2)
		"snack":
			f.node.queue_free()
			(animals[f.animal] as Animal).snack()
			_hearts(animals[f.animal].mouth_global(), 3)


const SNIFF_DELAY := 0.8


func _meal(a: Animal) -> void:
	a.eat()
	meals += 1
	stars += 1
	hungry_ids.erase(a.kind)
	throw_lock = false
	gap_t = Rules.HUNGER_GAP
	_hearts(a.mouth_global(), 5)
	var s := Props.star(1.0)
	fx_layer.add_child(s)
	flights.append({"node": s, "from": a.head_global(), "to": cart_pos, "t": -0.6, "dur": 0.9,
		"kind": "star", "arc": 160.0, "animal": a.kind, "food": "", "hide_wait": true})
	Sfx.play("star")
	_refresh_plates()
	if meals >= Rules.TOTAL_MEALS:
		_set_phase(Phase.FINISH)
		Sfx.play("ready")
	elif meals == Rules.ROUND_MEALS:
		_set_phase(Phase.ROUND_BREAK)
		Sfx.play("ready")


func _hearts(at: Vector2, n: int) -> void:
	for i in n:
		var h := Props.heart(rng.randf_range(0.6, 0.9))
		fx_layer.add_child(h)
		fx.append({"node": h, "pos": at, "vel": Vector2(rng.randf_range(-70, 70), rng.randf_range(-190, -120)),
			"life": 1.3, "max": 1.3, "grav": 60.0, "spin": 0.0})


func _note(at: Vector2) -> void:
	var n := Props.note(Players.SEAT_COLORS[SINGER], rng.randf_range(0.9, 1.2))
	fx_layer.add_child(n)
	fx.append({"node": n, "pos": at, "vel": Vector2(rng.randf_range(-40, 40), -120), "life": 1.4, "max": 1.4,
		"grav": 0.0, "spin": 0.0, "wobble": true})


func _sparkle(at: Vector2, n: int) -> void:
	for i in n:
		var s := Props.star(0.4)
		fx_layer.add_child(s)
		var a := TAU * i / n
		fx.append({"node": s, "pos": at, "vel": Vector2(cos(a), sin(a)) * 160.0, "life": 0.5, "max": 0.5, "grav": 0.0, "spin": 6.0})


func _confetti_burst(at: Vector2, n: int) -> void:
	for i in n:
		var c := Props.confetti(Pal.CONFETTI[rng.randi() % Pal.CONFETTI.size()])
		fx_layer.add_child(c)
		fx.append({"node": c, "pos": at, "vel": Vector2(rng.randf_range(-160, 160), rng.randf_range(-260, -60)),
			"life": 2.0, "max": 2.0, "grav": 320.0, "spin": rng.randf_range(-8, 8)})


func _update_fx(dt: float) -> void:
	for i in range(fx.size() - 1, -1, -1):
		var p := fx[i]
		p.life -= dt
		if p.life <= 0.0:
			p.node.queue_free()
			fx.remove_at(i)
			continue
		p.vel.y += p.grav * dt
		p.pos += p.vel * dt
		var pos: Vector2 = p.pos
		if p.get("wobble", false):
			pos.x += sin(p.life * 8.0) * 8.0
		p.node.position = pos
		p.node.rotation += p.spin * dt
		p.node.modulate.a = clampf(p.life / (p.max * 0.4), 0.0, 1.0)


# ================================================================ view

## The music clock in beats (dances land on the beat).
func _beat() -> float:
	var m: AudioStreamPlayer = Sfx.get("_music")
	if m and m.playing:
		return m.get_playback_position() / Rules.BEAT
	return time / Rules.BEAT


func _place_nodes(dt: float) -> void:
	keeper.position = keeper_pos
	keeper.scale.x = facing
	var walking := walk_t > 0.0 and Players.move(KEEPER).length() > 0.05 and phase in [Phase.RUN, Phase.ROUND_BREAK]
	if phase in [Phase.BELL, Phase.FINISH, Phase.ROUND_BREAK] and not walking:
		Props.keeper_cheer(keeper, time)
	else:
		Props.keeper_pose(keeper, int(walk_t / 0.14) % 4 if walking else -1)
	# The cart rolls ahead of the keeper.
	var want := keeper_pos + Vector2(facing * CART_OFFSET, 6)
	var before := cart_pos
	cart_pos = cart_pos.lerp(want, clampf(dt * 10.0, 0.0, 1.0)) if dt > 0.0 else want
	cart.position = cart_pos + Vector2(0, -absf(sin(_cart_jiggle * 30.0)) * 4.0)
	var roll := (cart_pos.x - before.x) / 15.0
	for w in ["wheel_l", "wheel_r"]:
		var wn := cart.get_node(w) as Node2D
		wn.rotation += roll
	# Buddies trail the keeper.
	# The trail records a point every TRAIL_STEP pixels walked, so buddies keep
	# the same spacing at any frame rate.
	if keeper_pos.distance_to(_trail[0]) >= TRAIL_STEP:
		_trail.push_front(keeper_pos)
		_trail.pop_back()
	for i in buddies.size():
		var b: Dictionary = buddies[i]
		var node: Node2D = b.node
		var tp: Vector2 = _trail[mini(3 + i * 3, _trail.size() - 1)]
		tp += Vector2(-facing * 30.0, 12.0 + i * 4.0)
		node.position = node.position.lerp(tp, clampf(dt * 8.0, 0.0, 1.0)) if dt > 0.0 else tp
		if phase in [Phase.ROUND_BREAK, Phase.FINISH, Phase.BELL]:
			Animals.pose(node, "dance", _beat())
		elif walking:
			Animals.pose(node, "idle", time)
			node.get_node("pivot").position.y -= absf(sin(time * 12.0 + i)) * 10.0
		else:
			Animals.pose(node, "idle", time + i)
	# Wheel beside and above the keeper, on the side away from the animal.
	var side := facing
	if at_animal != "":
		var ax: float = (animals[at_animal] as Animal).global_position.x
		side = 1.0 if ax <= keeper_pos.x else -1.0
	var wx := clampf(keeper_pos.x + side * 175.0, cam.position.x - VIEW_W / 2.0 + 130.0, cam.position.x + VIEW_W / 2.0 - 130.0)
	var wy := clampf(keeper_pos.y - 110.0, 190.0, 560.0)
	if at_animal != "" and LAYOUT[at_animal][1] == false:
		wy = clampf(keeper_pos.y - 170.0, 190.0, 560.0)
	wheel.position = wheel.position.lerp(Vector2(wx, wy), clampf(dt * 10.0, 0.0, 1.0)) if wheel.visible else Vector2(wx, wy)
	wheel.animate(dt)
	bell_node.visible = phase == Phase.BELL
	if bell_node.visible:
		bell_node.position = keeper_pos + Vector2(facing * 30.0, -130)
		bell_node.rotation = sin(time * 18.0) * 0.4
	# Spot marks glow for hungry animals.
	for kind in spot_marks:
		var ring: Line2D = spot_marks[kind].get_node("ring")
		ring.visible = hungry_ids.has(kind)
		ring.default_color = Color(Pal.CREAM, 0.6 + 0.4 * sin(time * 6.0))
	# Camera follows the keeper across the screen and a half.
	var cx := clampf(keeper_pos.x, VIEW_W / 2.0, W - VIEW_W / 2.0)
	cam.position.x = lerpf(cam.position.x, cx, clampf(dt * 5.0, 0.0, 1.0)) if dt > 0.0 else cx
	# Off-screen hungry animals: a bubble and an arrow at the screen edge.
	for kind in edge_marks:
		var m: Node2D = edge_marks[kind]
		var a: Animal = animals[kind]
		var sx := a.global_position.x - (cam.position.x - VIEW_W / 2.0)
		m.visible = a.hungry and (sx < 30.0 or sx > VIEW_W - 30.0)
		if m.visible:
			var left := sx < 30.0
			m.position = Vector2(62.0 if left else VIEW_W - 62.0, clampf(a.global_position.y - 60.0, 120.0, 640.0))
			m.position.x += sin(time * 6.0) * 6.0 * (-1.0 if left else 1.0)
			var ar: Node2D = m.get_node("arrow")
			ar.scale = Vector2(-1.0 if left else 1.0, 1.0)
			ar.position = Vector2(-40.0 if left else 40.0, 0)


# ================================================================ pause

## Pause belongs to the keeper only. Returns true while paused.
func _pause_input() -> bool:
	if phase != Phase.RUN and phase != Phase.ROUND_BREAK:
		return false
	if Players.just_pressed(KEEPER, "start"):
		_set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(KEEPER, "a"):
			_set_paused(false)
		elif Players.just_pressed(KEEPER, "b"):
			_back_to_join()
	return paused


func _set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	Sfx.play("select")


func _back_to_join() -> void:
	_set_phase(Phase.DONE)
	Players.reset()
	next_screen = "join"
	if auto_goto:
		Game.goto.call_deferred("join")


## Dimmed pause screen: a back arrow (keeper "b") and a play triangle ("a"/start).
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0.1, 0.08, 0.16, 0.65))
		draw_circle(Vector2(480, 360), 80, Color("#e84a5f"))
		draw_circle(Vector2(480, 360), 80, Color("#2b2438"), false, 8.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(430, 360), Vector2(485, 305), Vector2(485, 335),
			Vector2(530, 335), Vector2(530, 385), Vector2(485, 385), Vector2(485, 415)]), Color("#fff6e4"))
		draw_circle(Vector2(800, 360), 95, Color("#5cb566"))
		draw_circle(Vector2(800, 360), 95, Color("#2b2438"), false, 8.0, true)
		draw_colored_polygon(PackedVector2Array([Vector2(770, 305), Vector2(850, 360), Vector2(770, 415)]), Color("#fff6e4"))
