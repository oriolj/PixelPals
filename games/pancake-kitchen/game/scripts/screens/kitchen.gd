extends Node2D
## The kitchen: one fixed screen (no camera), the whole round.
##
## Seats: 0 cook (slides the pan, serves), 1 topper (four jars, drops
## toppings), 2 flipper (any button flips). With the flipper seat empty the
## cook's "a" flips; with the topper seat empty customers sprinkle their own.
## Rules live in scripts/kitchen/rules.gd; this node feeds it input, plays
## its events as sound and effects, and draws everything with vector_art.gd.
## No Label nodes, no text: `test_no_label_nodes_in_the_kitchen_screen`.

const Rules := preload("res://scripts/kitchen/rules.gd")
const VA := preload("res://scripts/vector_art.gd")
const Pal := preload("res://scripts/kitchen/palette.gd")
const DrawNode := preload("res://scripts/draw_node.gd")

const COOK := 0
const TOPPER := 1
const FLIPPER := 2
const END_DELAY := 2.2
const FINALE_DELAY := 3.6
const DROP_COOLDOWN := 0.18
const GIGGLE_COOLDOWN := 0.9
const CUSTOMER_SCALE := 1.3
const CHEF_POS := [Vector2(0, 606), Vector2(952, 690), Vector2(660, 700)]

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var rules: Rules
var time := 0.0
var paused := false
var end_t := 0.0
var fx: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var jar_bump: Array[float] = [0.0, 0.0, 0.0, 0.0]
var chef_hop: Array[float] = [0.0, 0.0, 0.0]
var cat_surprise := 0.0
var boing_i := 0
var drop_cd := 0.0
var giggle_cd := 0.0
var trail_t := 0.0
var shake := 0.0
var _cust_plate := {}

var _bg: Node2D
var _world: Node2D
var _front: Node2D
var _sizzle: AudioStreamPlayer


func _ready() -> void:
	rng.randomize()
	rules = Rules.new()
	rules.self_sprinkle = not Players.is_seated(TOPPER)
	rules.start(Game.round_customers, Game.round_limit)
	_bg = DrawNode.make(_draw_bg)
	add_child(_bg)
	_world = DrawNode.make(_draw_world)
	add_child(_world)
	_front = DrawNode.make(_draw_front)
	add_child(_front)
	_sizzle = AudioStreamPlayer.new()
	_sizzle.volume_db = -12.0
	add_child(_sizzle)
	var s := _load_loop("res://audio/sizzle.wav")
	if s:
		_sizzle.stream = s
	Sfx.music("music_kitchen")
	_play_events()


func _load_loop(path: String) -> AudioStream:
	# From source, read the WAV bytes (no import cache), like shared sfx.gd.
	var s: AudioStreamWAV = null
	if OS.has_feature("template"):
		s = load(path) if ResourceLoader.exists(path) else null
	elif FileAccess.file_exists(ProjectSettings.globalize_path(path)):
		s = AudioStreamWAV.load_from_file(ProjectSettings.globalize_path(path))
	if s:
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_end = int(s.get_length() * s.mix_rate)
	return s


func _exit_tree() -> void:
	if _sizzle:
		_sizzle.stop()


func _process(delta: float) -> void:
	step(delta)


## One frame of the kitchen (tests call it directly with set_process(false)).
func step(dt: float) -> void:
	time += dt
	if paused:
		_pause_input()
		_front.queue_redraw()
		return
	if Players.just_pressed(COOK, "start") and next_screen == "":
		paused = true
		Sfx.play("select")
		_front.queue_redraw()
		return
	rules.self_sprinkle = not Players.is_seated(TOPPER)
	_seat_input(dt)
	rules.step(dt)
	_play_events()
	_step_fx(dt)
	_update_sizzle()
	if rules.round_over and next_screen == "":
		end_t += dt
		if end_t >= (FINALE_DELAY if rules.finale else END_DELAY):
			_finish()
	_world.queue_redraw()
	_front.queue_redraw()


func _seat_input(dt: float) -> void:
	drop_cd = maxf(0.0, drop_cd - dt)
	giggle_cd = maxf(0.0, giggle_cd - dt)
	rules.move_pan(Players.move(COOK).x, dt)
	var flipper_here := Players.is_seated(FLIPPER)
	if Players.just_pressed(COOK, "b"):
		rules.serve()
	if Players.just_pressed(COOK, "a"):
		if not flipper_here and (rules.can_flip() or rules.in_air()):
			flip_press(COOK)
		else:
			rules.serve()
	if Players.is_seated(TOPPER):
		var d := Players.dir4(TOPPER)
		if d != Vector2i.ZERO:
			rules.pick_jar(d)
		if Players.just_pressed(TOPPER, "a") and drop_cd <= 0.0:
			drop_cd = DROP_COOLDOWN
			jar_bump[rules.jar] = 1.0
			rules.drop_topping()
	if flipper_here and Players.just_pressed(FLIPPER, "any"):
		flip_press(FLIPPER)


## The flipper's press (or the cook's "a" when nobody holds the flipper seat).
func flip_press(seat: int) -> void:
	chef_hop[seat] = 1.0
	rules.try_flip()


func _pause_input() -> void:
	if Players.just_pressed(COOK, "start") or Players.just_pressed(COOK, "a"):
		paused = false
		Sfx.play("select")
	elif Players.just_pressed(COOK, "b"):
		Sfx.play("whoosh")
		_leave("join")


func _finish() -> void:
	Game.plates = rules.plates.duplicate(true)
	_leave("party")


func _leave(screen_name: String) -> void:
	next_screen = screen_name
	set_process(false)
	if _sizzle:
		_sizzle.stop()
	if auto_goto:
		Game.goto.call_deferred(screen_name)


func _update_sizzle() -> void:
	if _sizzle.stream == null or Sfx.muted:
		return
	var p = rules.pancake
	var want: bool = p != null and p.state in [Rules.P.POURING, Rules.P.IN_PAN, Rules.P.SETTLING]
	if want and not _sizzle.playing:
		_sizzle.play()
	elif not want and _sizzle.playing:
		_sizzle.stop()


# ------------------------------------------------------------------ events

func _play_events() -> void:
	for e in rules.drain_events():
		var p = rules.pancake
		var ppos: Vector2 = p.pos if p != null else Vector2(rules.pan_x, Rules.PAN_Y)
		match e:
			"pour":
				Sfx.play("pour", 1.0, -4.0)
			"flip":
				boing_i = boing_i % 4 + 1
				Sfx.play("boing_%d" % boing_i)
				_burst(ppos, "sparkle", 6, Players.SEAT_COLORS[FLIPPER])
			"spin":
				Sfx.play("spin", rng.randf_range(0.95, 1.15))
				_burst(ppos, "sparkle", 8, Players.SEAT_COLORS[FLIPPER])
			"toddler_fun":
				var at: Vector2 = CHEF_POS[FLIPPER] + Vector2(0, -300)
				if not Players.is_seated(FLIPPER):
					at = ppos + Vector2(0, -40)
				_burst(at, "sparkle", 7, Players.SEAT_COLORS[FLIPPER])
				_burst(at, "star", 2, Color("#ffd23f"))
				Sfx.play("sparkle", rng.randf_range(0.9, 1.2))
				if giggle_cd <= 0.0:
					giggle_cd = GIGGLE_COOLDOWN
					Sfx.play("giggle", rng.randf_range(1.0, 1.15), -3.0)
			"catch", "return":
				Sfx.play("flop")
				_burst(ppos + Vector2(0, -10), "steam", 3, Color.WHITE)
				_burst(ppos, "crumb", 5, Pal.BATTER)
			"gag_dog":
				Sfx.play("whoosh", 0.8)
			"woof":
				Sfx.play("dog_woof")
				_burst(ppos, "heart", 3, Pal.STRAWBERRY)
			"gag_cat":
				Sfx.play("meow")
				cat_surprise = 1.0
				_burst(Rules.CAT_HEAD, "star", 4, Color("#ffd23f"))
			"gag_bounce":
				Sfx.play("boing_%d" % (rng.randi() % 4 + 1), 0.7)
				_burst(ppos + Vector2(0, 20), "crumb", 6, Pal.BATTER)
			"toss":
				Sfx.play("whoosh", 1.2, -4.0)
			"hop":
				Sfx.play("boing_2", 1.4, -4.0)
			"stack":
				Sfx.play("flop", 1.2)
				_burst(rules.top_center(rules.stack.size() - 1), "steam", 3, Color.WHITE)
			"ding":
				Sfx.play("ding")
				_burst(Rules.PLATE_POS + Vector2(0, -80), "star", 8, Color("#ffd23f"))
			"drop":
				Sfx.play("whoosh", 1.8, -12.0)
			"serve":
				Sfx.play("slide")
			"yum":
				Sfx.play("yum")
				if rules.customer != null:
					_burst(Vector2(rules.customer.x, 380), "crumb", 4, Pal.GOLDEN)
			"leave":
				pass
			"finale":
				Sfx.play("cheer")
				for i in 60:
					_spawn("confetti", Vector2(rng.randf_range(0, 1280), rng.randf_range(-200, 0)),
						Vector2(rng.randf_range(-40, 40), rng.randf_range(80, 200)), Pal.CONFETTI[i % Pal.CONFETTI.size()], 4.0)
			"round_over":
				Sfx.play("party")
			_:
				if e.begins_with("plop:"):
					var kind := e.substr(5)
					if kind == "cream":
						Sfx.play("splat_soft")
					else:
						Sfx.play("plop", rng.randf_range(0.9, 1.15))
				elif e.begins_with("joy:"):
					_joy(int(e.substr(4)))


func _joy(size: int) -> void:
	var c = rules.customer
	var head := Vector2(c.x if c != null else Rules.WINDOW_X, 300)
	match size:
		1:
			Sfx.play("giggle")
			_burst(head, "heart", 3, Pal.STRAWBERRY)
		2:
			Sfx.play("giggle", 1.1)
			_burst(head, "heart", 6, Pal.STRAWBERRY)
			_burst(head, "star", 4, Color("#ffd23f"))
		_:
			Sfx.play("cheer")
			shake = 0.4
			_burst(head, "heart", 8, Pal.STRAWBERRY)
			_burst(head, "star", 10, Color("#ffd23f"))
			for i in 24:
				_spawn("confetti", head + Vector2(rng.randf_range(-60, 60), 0),
					Vector2(rng.randf_range(-260, 260), rng.randf_range(-520, -200)), Pal.CONFETTI[i % Pal.CONFETTI.size()], 2.2)


# ------------------------------------------------------------------ effects

func _spawn(kind: String, pos: Vector2, vel: Vector2, col: Color, life := 1.0) -> void:
	if fx.size() > 400:
		return
	fx.append({"kind": kind, "pos": pos, "vel": vel, "col": col, "t": 0.0, "life": life,
		"rot": rng.randf_range(0, TAU), "spin": rng.randf_range(-6, 6), "size": rng.randf_range(0.7, 1.2)})


func _burst(at: Vector2, kind: String, n: int, col: Color) -> void:
	for i in n:
		var a := rng.randf_range(0, TAU)
		var sp := rng.randf_range(80, 220)
		var vel := Vector2(cos(a), sin(a)) * sp
		var life := 0.8
		match kind:
			"steam":
				vel = Vector2(rng.randf_range(-15, 15), -40)
				life = 1.1
				at += Vector2(rng.randf_range(-50, 50), 0)
			"heart":
				vel = Vector2(rng.randf_range(-60, 60), rng.randf_range(-180, -120))
				life = 1.4
			"crumb":
				vel = Vector2(rng.randf_range(-160, 160), rng.randf_range(-260, -80))
				life = 0.7
		_spawn(kind, at, vel, col, life)


func _step_fx(dt: float) -> void:
	for i in 4:
		jar_bump[i] = maxf(0.0, jar_bump[i] - dt * 4.0)
	for i in 3:
		chef_hop[i] = maxf(0.0, chef_hop[i] - dt * 3.0)
	cat_surprise = maxf(0.0, cat_surprise - dt * 0.6)
	shake = maxf(0.0, shake - dt)
	# The flipper's green sparkle trail behind a flying pancake.
	if rules.in_air() and Players.is_seated(FLIPPER):
		trail_t -= dt
		if trail_t <= 0.0:
			trail_t = 0.045
			_spawn("sparkle", rules.pancake.pos + Vector2(rng.randf_range(-40, 40), rng.randf_range(-6, 12)),
				Vector2(rng.randf_range(-20, 20), rng.randf_range(10, 40)), Players.SEAT_COLORS[FLIPPER], 0.6)
	for i in range(fx.size() - 1, -1, -1):
		var f: Dictionary = fx[i]
		f.t += dt
		if f.t >= f.life:
			fx.remove_at(i)
			continue
		match f.kind:
			"confetti", "crumb":
				f.vel.y += 600.0 * dt
				f.vel.x *= 0.99
			"heart", "steam":
				pass
			_:
				f.vel *= 0.9
		f.pos += f.vel * dt
		f.rot += f.spin * dt


# ------------------------------------------------------------------ drawing

func _draw_bg(ci: Node2D) -> void:
	# Wall and a tiled backsplash.
	ci.draw_rect(Rect2(0, 0, 1280, 720), Pal.WALL)
	ci.draw_rect(Rect2(0, 0, 1280, 36), Pal.WALL_DEEP)
	ci.draw_rect(Rect2(0, 330, 1280, 230), Pal.TILES)
	for x in range(0, 1281, 64):
		ci.draw_line(Vector2(x, 330), Vector2(x, 560), Pal.TILE_LINE, 3.0)
	for y in range(330, 561, 58):
		ci.draw_line(Vector2(0, y), Vector2(1280, y), Pal.TILE_LINE, 3.0)
	ci.draw_line(Vector2(0, 330), Vector2(1280, 330), Pal.OUTLINE, 4.0)
	# Hanging spoons and a clock-less round window of polka dots on the wall.
	for i in 3:
		var hx := 120 + i * 44
		VA.line(ci, Vector2(hx, 36), Vector2(hx, 110 + i * 10), 4.0)
		VA.ellipse(ci, Vector2(hx, 128 + i * 10), 16, 22, [Color("#ffcd75"), Color("#8fd3ff"), Color("#ff9fb6")][i], 4.0)
	# Counter-service window on the right: sky, a sun, clouds, bunting.
	var win := Rect2(1000, 120, 268, 440)
	VA.rrect(ci, win.grow(14), 26, Pal.WINDOW_FRAME, 5.0)
	ci.draw_rect(win, Pal.WINDOW_SKY)
	VA.circle(ci, Vector2(1200, 190), 34, Color("#ffe066"), 4.0)
	for c in [Vector2(1060, 230), Vector2(1170, 290)]:
		for k in 3:
			ci.draw_circle(c + Vector2(k * 22 - 22, -8 * (k % 2)), 20, Color.WHITE, true, -1.0, true)
	ci.draw_rect(Rect2(win.position.x, 470, win.size.x, 90), Color("#9edc7a"))
	for i in 6:
		var bx := win.position.x + 12 + i * 44
		var tri := PackedVector2Array([Vector2(bx, 120), Vector2(bx + 40, 120), Vector2(bx + 20, 152)])
		VA.shape(ci, tri, Pal.CONFETTI[i], 3.5)
	ci.draw_polyline(VA.closed(VA.rrect_pts(win, 4)), Pal.OUTLINE, 5.0, true)
	# The shelf (the cat lives on it) with a plant.
	VA.rrect(ci, Rect2(Rules.SHELF_X0 - 20, Rules.SHELF_Y, Rules.SHELF_X1 - Rules.SHELF_X0 + 40, 16), 5, Pal.COUNTER, 4.5)
	for sx in [Rules.SHELF_X0, Rules.SHELF_X1 - 14]:
		VA.shape(ci, PackedVector2Array([Vector2(sx, Rules.SHELF_Y + 14), Vector2(sx + 14, Rules.SHELF_Y + 14), Vector2(sx + 14, Rules.SHELF_Y + 40)]), Pal.COUNTER_DARK, 4.0)
	# Progress plates on the wall: one per customer this round.
	pass


func _draw_world(ci: Node2D) -> void:
	var t := time
	var off := Vector2(sin(t * 60.0), cos(t * 53.0)) * 6.0 * shake
	VA.push(ci, Transform2D(0.0, off))
	_draw_progress(ci)
	_draw_cat(ci, t)
	_draw_chefs(ci, t, [COOK])
	_draw_customer(ci, t)
	# Window sill and counter over the customer's legs.
	ci.draw_rect(Rect2(0, Rules.COUNTER_Y + 22, 1280, 200), Pal.COUNTER)
	VA.rrect(ci, Rect2(-20, Rules.COUNTER_Y, 1320, 26), 8, Pal.COUNTER_TOP, 5.0)
	for i in 9:
		var dx := 590 + i * 80
		ci.draw_line(Vector2(dx, Rules.COUNTER_Y + 50), Vector2(dx, 720), Pal.COUNTER_DARK, 4.0)
	VA.rrect(ci, Rect2(600, 600, 360, 110), 14, Pal.COUNTER_DARK, 4.0)
	VA.rrect(ci, Rect2(980, 600, 280, 110), 14, Pal.COUNTER_DARK, 4.0)
	for k in [Vector2(780, 616), Vector2(1120, 616)]:
		VA.rrect(ci, Rect2(k.x - 30, k.y, 60, 12), 6, Color("#ffcd75"), 3.5)
	if not _cust_plate.is_empty():
		VA.stack(ci, _cust_plate.at, _cust_plate.n, _cust_plate.tops, 0.0, t, 0.85)
	# The topper and flipper chefs stand in front of the counter.
	_draw_chefs(ci, t, [TOPPER, FLIPPER])
	# Stove, flame, pan and the pancake in it.
	VA.stove(ci, 150, 570, 526, 740, rules.pan_x, t)
	var p = rules.pancake
	if p != null and p.state == Rules.P.POURING:
		_draw_pour(ci, p)
	VA.pan(ci, Vector2(rules.pan_x, 496), Players.SEAT_COLORS[COOK], rules.pan_vel / Rules.PAN_SPEED * 0.03)
	if p != null and p.state in [Rules.P.POURING, Rules.P.IN_PAN, Rules.P.SETTLING]:
		_draw_pancake(ci, p)
		if p.state != Rules.P.POURING:
			for i in 2:
				var ph := fmod(t * 0.7 + i * 0.5, 1.0)
				VA.steam(ci, p.pos + Vector2(-30 + i * 60, -18), ph, 0.8)
	# Plate, stack, jars.
	var glow := 1.0 if rules.plate_ready() else 0.0
	VA.stack(ci, Rules.PLATE_POS, rules.stack.size(), rules.toppings, glow, t)
	for i in 4:
		VA.jar(ci, Rules.TOPPINGS[i], rules.jar_pos(i), i == rules.jar and Players.is_seated(TOPPER),
			Players.SEAT_COLORS[TOPPER], jar_bump[i], t)
	for f in rules.falling:
		VA.topping(ci, f.kind, f.pos, f.rot + f.t * 6.0)
	# The dog, in front of everything low.
	var happy := 0.0
	if p != null and p.state == Rules.P.GAG and p.gag == "dog":
		happy = 1.0
	var look := Vector2.ZERO
	if p != null:
		look = (p.pos - Vector2(rules.dog_x, 580)).normalized()
	VA.dog(ci, Transform2D(0.0, Vector2(rules.dog_x, 712 - rules.dog_jump * 30.0)), t, happy, look)
	# A pancake anywhere but the pan flies in front of everything.
	if p != null and not p.state in [Rules.P.POURING, Rules.P.IN_PAN, Rules.P.SETTLING]:
		_draw_pancake(ci, p)
	_draw_fx(ci)
	VA.pop(ci)


func _draw_pancake(ci: Node2D, p) -> void:
	var bubbles := 0.0
	if p.flips == 0 and p.state == Rules.P.IN_PAN:
		bubbles = p.cook_bottom
	var tilt := 0.0
	if p.state == Rules.P.FLYING:
		tilt = clampf(p.launch_vel.x / 400.0, -0.25, 0.25)
	VA.pancake(ci, p.pos, p.cook_top, p.cook_bottom, cos(p.spin), p.squash, bubbles, p.spread(), 7, tilt)


func _draw_pour(ci: Node2D, p) -> void:
	# A jug tips over the pan and a ribbon of batter falls into it.
	var u: float = clampf(p.t / Rules.POUR_TIME, 0.0, 1.0)
	var jug := Vector2(rules.pan_x + 40, 330)
	VA.push(ci, Transform2D(-0.6 * sin(u * PI), jug))
	VA.rrect(ci, Rect2(-34, -40, 68, 80), 18, Color("#8fd3ff"), 5.0)
	VA.arc(ci, Vector2(38, 0), 22, -PI / 2, PI / 2, 9.0)
	ci.draw_colored_polygon(VA.rrect_pts(Rect2(-26, -10, 52, 42), 12), Pal.BATTER)
	VA.pop(ci)
	if u > 0.1 and u < 0.9:
		var w := 14.0 * sin(u * PI)
		ci.draw_line(jug + Vector2(-30, -10), Vector2(rules.pan_x, Rules.PAN_Y), Pal.OUTLINE, w + 6.0, true)
		ci.draw_line(jug + Vector2(-30, -10), Vector2(rules.pan_x, Rules.PAN_Y), Pal.BATTER, w, true)


func _draw_progress(ci: Node2D) -> void:
	# One little plate per customer on the wall above the window; a served
	# one carries a pancake. Pictures, not numbers.
	var n := rules.customers_target
	VA.rrect(ci, Rect2(1134 - n * 23 - 16, 78, n * 46 + 32, 12), 5, Pal.COUNTER, 4.0)
	for i in n:
		var c := Vector2(1134 - (n - 1) * 23 + i * 46, 70)
		VA.ellipse(ci, c, 20, 7, Pal.PLATE_RIM, 3.5)
		if i < rules.served:
			VA.ellipse(ci, c + Vector2(0, -8), 16, 6, Pal.GOLDEN, 3.0)
			VA.ellipse(ci, c + Vector2(0, -16), 16, 6, Pal.GOLDEN, 3.0)
			VA.dot(ci, c + Vector2(-4, -20), 3.5, Pal.STRAWBERRY)


func _draw_cat(ci: Node2D, t: float) -> void:
	var sur := cat_surprise
	var p = rules.pancake
	if p != null and p.state == Rules.P.GAG and p.gag == "cat":
		sur = 1.0
	VA.shelf_cat(ci, Transform2D(0.0, Vector2(Rules.CAT_HEAD.x + 40, Rules.SHELF_Y)), t, sur)


func _chef_look(from: Vector2) -> Vector2:
	var p = rules.pancake
	var target := Rules.PLATE_POS + Vector2(0, -60)
	if p != null:
		target = p.pos
	return (target - from).normalized()


func _draw_chefs(ci: Node2D, t: float, seats: Array) -> void:
	for seat in seats:
		if not Players.is_seated(seat):
			continue
		var kind: String = Players.riders[seat] if Players.riders[seat] != "" else Game.CHEFS[seat]
		var pos: Vector2 = CHEF_POS[seat]
		var s := 0.82
		match seat:
			COOK:
				pos = Vector2(rules.pan_x - 200, 580)
			TOPPER:
				s = 0.66
			FLIPPER:
				s = 0.66
		var hop := sin(chef_hop[seat] * PI) * 40.0
		pos.y -= hop + absf(sin(t * 3.0 + seat)) * 4.0
		var head := pos + Vector2(0, -168 * s)
		var o := {"hat": Game.hat_color(seat), "look": _chef_look(head),
			"arms": 0.9 if chef_hop[seat] > 0.2 else (0.35 if seat == COOK else 0.1),
			"mouth": "grin" if chef_hop[seat] > 0.2 else "smile",
			"eyes": "happy" if chef_hop[seat] > 0.5 else "open"}
		VA.creature(ci, Transform2D(0.0, Vector2(s, s), 0.0, pos), kind, o)


func _draw_customer(ci: Node2D, t: float) -> void:
	_cust_plate = {}
	var c = rules.customer
	if c == null:
		return
	var st: int = c.state
	var x: float = c.x
	var feet := Vector2(x, 660)
	var o := {"look": Vector2(-1, 0.3), "mouth": "smile", "eyes": "open", "arms": 0.0}
	var bob := 0.0
	var head := feet + Vector2(0, -168 * CUSTOMER_SCALE)
	var plate_at := Vector2(x - 20, Rules.COUNTER_Y - 6)
	var show_plate := false
	var n := 0
	match st:
		Rules.C.WALK_IN, Rules.C.LEAVE:
			bob = absf(sin(t * 10.0)) * 10.0
			o.look = Vector2(-1, 0) if st == Rules.C.WALK_IN else Vector2(1, 0)
			if st == Rules.C.LEAVE:
				o.arms = 0.5 + 0.3 * sin(t * 12.0)
				o.eyes = "happy"
		Rules.C.WAIT:
			bob = sin(t * 2.0) * 3.0
			o.look = _chef_look(head)
			var wait: float = c.t
			if wait > 15.0:
				# Patience: a hungry tummy rub and an "o", never a frown.
				o.mouth = "o" if fmod(wait, 4.0) < 1.2 else "smile"
				o.arms = 0.2 + 0.1 * sin(t * 6.0)
			if fmod(wait, 3.3) < 0.12:
				o.eyes = "happy"  # a blink
			if rules.plate_ready():
				o.mouth = "grin"
				o.eyes = "wide"
				bob = absf(sin(t * 8.0)) * 8.0
		Rules.C.SPRINKLE:
			show_plate = true
			n = c.stack.size()
			o.arms = 0.6 + 0.2 * sin(t * 14.0)
			o.mouth = "grin"
			o.look = Vector2(-0.4, 1)
		Rules.C.EAT:
			show_plate = true
			var et: float = maxf(c.t, 0.0)
			n = c.stack.size() - int(et / (Rules.EAT_TIME / 3.0 + 0.01)) if c.t >= 0.0 else c.stack.size()
			var pose := int(et / 0.3) % 3
			o.mouth = ["open", "chew", "chew"][pose] if c.t >= 0.0 else "grin"
			o.eyes = ["open", "happy", "happy"][pose] if c.t >= 0.0 else "wide"
			o.look = Vector2(-0.3, 1)
			bob = sin(t * 9.0) * 3.0
		Rules.C.HAPPY:
			show_plate = true
			if rules.finale:
				n = c.stack.size()   # the 7-minute gift: a whole loaded stack
			var j: int = c.joy
			o.eyes = "happy"
			o.mouth = "grin"
			o.arms = [0.3, 0.7, 1.0][clampi(j - 1, 0, 2)]
			var hop_h: float = [8.0, 30.0, 70.0][clampi(j - 1, 0, 2)]
			bob = absf(sin(c.t * (7.0 + j * 2.0))) * hop_h
			o.squish = 0.0
	if st == Rules.C.SPRINKLE or st == Rules.C.EAT:
		if c.t < 0.0:
			# The plate is still sliding over from the middle of the counter.
			var u: float = 1.0 + c.t / Rules.SLIDE_TIME
			plate_at = Rules.PLATE_POS.lerp(plate_at, u * u * (3.0 - 2.0 * u))
	var xf := Transform2D(0.0, Vector2(CUSTOMER_SCALE, CUSTOMER_SCALE), 0.0, feet + Vector2(0, -bob))
	if st == Rules.C.HAPPY and c.joy >= 3:
		xf = Transform2D(sin(c.t * 5.0) * 0.12, Vector2(CUSTOMER_SCALE, CUSTOMER_SCALE), 0.0, feet + Vector2(0, -bob))
	VA.creature(ci, xf, c.animal, o)
	if show_plate:
		# Drawn after the counter (see _draw_world), so it sits on the sill.
		_cust_plate = {"at": plate_at, "n": maxi(n, 0), "tops": _visible_tops(c.toppings, maxi(n, 0))}


func _visible_tops(tops: Array, n: int) -> Array:
	var out := []
	for tp in tops:
		if int(tp.level) < n:
			out.append(tp)
	return out


func _draw_fx(ci: Node2D) -> void:
	for f in fx:
		var u: float = f.t / f.life
		var a := 1.0 - u * u
		var col: Color = f.col
		col.a = a
		match f.kind:
			"sparkle":
				VA.sparkle(ci, f.pos, 12.0 * f.size * (1.0 - u * 0.5), col, f.rot)
			"star":
				VA.star(ci, f.pos, 16.0 * f.size, Color(col, a), f.rot, 3.0)
			"heart":
				VA.heart(ci, f.pos, 14.0 * f.size, Color(col, a), 3.0)
			"steam":
				VA.steam(ci, f.pos, u, 0.7)
			"crumb":
				VA.dot(ci, f.pos, 5.0 * f.size, Color(col, a))
			"confetti":
				VA.confetti(ci, f.pos, col, f.rot, int(f.size * 10))


func _draw_front(ci: Node2D) -> void:
	if not paused:
		return
	ci.draw_rect(Rect2(0, 0, 1280, 720), Color(0.1, 0.08, 0.15, 0.55))
	VA.circle(ci, Vector2(640, 360), 110, Color.WHITE, 8.0)
	VA.rrect(ci, Rect2(592, 300, 34, 120), 10, Players.SEAT_COLORS[COOK], 6.0)
	VA.rrect(ci, Rect2(654, 300, 34, 120), 10, Players.SEAT_COLORS[COOK], 6.0)
