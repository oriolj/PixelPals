extends RefCounted
## Pancake Kitchen rules: pure logic, no nodes and no input devices.
##
## The kitchen screen feeds it seat input (move_pan, try_flip, pick/drop a
## topping, serve) and draws what it holds; tests drive it directly. Every
## step is written with `dt`, and the flight is a closed-form parabola from
## the launch point, so `--fixed-fps 30` captures match live play.
##
## Coordinates are the 1280x720 canvas; y grows downwards.
##
## Something happened? It is appended to `events` ("flip", "catch",
## "gag_dog", "plop:banana", "joy:3" ...); the screen drains them for sounds
## and effects.

enum P { POURING, IN_PAN, FLYING, CATCHING, GAG, RETURNING, SETTLING, HOPPING }
enum C { WALK_IN, WAIT, SPRINKLE, EAT, HAPPY, LEAVE, GONE }

const TOPPINGS: Array[String] = ["strawberry", "chocolate", "banana", "cream"]
## Jar per 4-direction pick: up, right, down, left.
const JAR_DIRS: Array[Vector2i] = [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT]
const ANIMALS: Array[String] = ["bear", "cat", "penguin", "frog", "robot"]

# ---- layout
const PAN_Y := 470.0            ## pancake centre when it rests in the pan
const PAN_MIN_X := 250.0
const PAN_MAX_X := 510.0
const PAN_SPEED := 640.0        ## px/s at full stick
const COUNTER_Y := 548.0        ## top of the counter
const PLATE_POS := Vector2(820, 540)   ## plate centre on the counter
const JAR_CENTER := Vector2(820, 255)  ## middle of the cross of jars
const JAR_SPREAD := 96.0
const WINDOW_X := 1115.0        ## where the customer stands
const SHELF_X0 := 500.0
const SHELF_X1 := 624.0
const SHELF_Y := 228.0          ## shelf top; the cat's head is above it
const CAT_HEAD := Vector2(560, 150)
const DOG_ZONE_X := 330.0       ## a miss left of this lands on the dog
const DOG_HOME_X := 96.0
const DOG_MIN_X := 70.0
const DOG_MAX_X := 300.0
const DOG_HEAD_Y := 546.0      ## pancake centre when it sits on the dog

# ---- flip physics
const GRAVITY := 1500.0
const FLIP_VY_MIN := 1000.0     ## launch speed up (px/s): peaks 330-420 px high
const FLIP_VY_MAX := 1120.0
const FLIP_VX_MIN := 20.0
const FLIP_VX_MAX := 90.0
const MAGNET := 60.0            ## horizontal catch radius
const CATCH_LINE := PAN_Y - 70.0    ## a falling pancake below this can be caught
const MISS_LINE := PAN_Y + 14.0     ## ...and past this it is a gag
const CATCH_TIME := 0.14
const MAX_EXTRA_SPINS := 6

# ---- cooking and stacking
const POUR_TIME := 1.0
const COOK_TIME := 3.0          ## pale to golden, per side
const FLIPS_TO_DONE := 2
const SETTLE_TIME := 0.6
const HOP_TIME := 0.55
const STACK_FULL := 3
const STACK_STEP := 24.0        ## height of one pancake on the plate
const PANCAKE_A := 80.0         ## pancake ellipse semi-axes (160x36)
const PANCAKE_B := 18.0
const TOPPING_FALL := 0.38
const MAX_TOPPINGS := 60

# ---- gags and customers
const GAG_TIME := {"dog": 1.1, "cat": 1.2, "bounce": 0.8}
const RETURN_TIME := 0.8
const WALK_TIME := 1.6
const SPRINKLE_TIME := 1.3
const EAT_TIME := 2.4
const HAPPY_TIME := 2.0
const LEAVE_TIME := 1.4
const SLIDE_TIME := 0.7
const CUSTOMERS := 6
const ROUND_LIMIT := 420.0      ## 7 minutes: then everyone gets a pancake at once


class Pancake:
	var state := P.POURING
	var pos := Vector2.ZERO
	var t := 0.0                ## seconds in the current state
	var cook_top := 0.0         ## the face we see (0 = pale batter, 1 = golden)
	var cook_bottom := 0.0      ## the face on the pan
	var flips := 0
	var spin := 0.0             ## flip angle; the drawn y-scale is cos(spin)
	var spin_target := 0.0
	var extra_spins := 0
	var extra_anim := 0.0
	var squash := 0.0           ## 1 right after landing, decays to 0
	var launch_pos := Vector2.ZERO
	var launch_vel := Vector2.ZERO
	var from := Vector2.ZERO
	var gag := ""
	var landed_gag := false     ## the dog gag: false while still falling

	func vel() -> Vector2:
		return launch_vel + Vector2(0, GRAVITY * t)

	## Size factor while the batter spreads (0 -> 1).
	func spread() -> float:
		return clampf(t / POUR_TIME, 0.0, 1.0) if state == P.POURING else 1.0


var rng := RandomNumberGenerator.new()
var events: Array[String] = []

var pan_x := 380.0
var pan_vel := 0.0
var pancake: Pancake = null     ## null while the pan waits for a serve
## Pancakes on the plate, bottom first: {"cook": float}
var stack: Array[Dictionary] = []
## Toppings that stuck: {"kind", "level" (-1 = the plate), "pos" (inside the
## pancake ellipse, relative to its centre), "lift", "rot"}
var toppings: Array[Dictionary] = []
## Toppings on their way down: {"kind", "t", "pos", "local", "rot", "from"}
var falling: Array[Dictionary] = []
var jar := 0                    ## the selected jar (index into TOPPINGS)
var dog_x := DOG_HOME_X
var dog_jump := 0.0             ## 0..1, the dog's leap for the catch

## The customer at the window: {"animal", "state", "t", "x", "joy", "stack",
## "toppings"}; null between customers.
var customer = null
var queue: Array[String] = []
var customers_target := CUSTOMERS
var round_limit := ROUND_LIMIT
var served := 0
## Plates served, for the party: {"animal", "stack", "toppings"}
var plates: Array[Dictionary] = []
var time := 0.0
var round_over := false
var finale := false             ## the 7-minute rule served everyone at once
## Set true when nobody holds the topper seat: customers sprinkle their own.
var self_sprinkle := false
## Tests and the demo can force the next flip's sideways speed.
var next_flip_vx := NAN


func _init(seed_value := 0) -> void:
	if seed_value != 0:
		rng.seed = seed_value
	else:
		rng.randomize()


## Start a round: a fresh pancake and the queue of customers.
func start(target := CUSTOMERS, limit := ROUND_LIMIT) -> void:
	customers_target = target
	round_limit = limit
	queue.clear()
	var animals := ANIMALS.duplicate()
	_shuffle(animals)
	for i in target:
		queue.append(animals[i % animals.size()])
	pancake = _new_pancake()
	_next_customer()


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = a[i]
		a[i] = a[j]
		a[j] = tmp


func _new_pancake() -> Pancake:
	var p := Pancake.new()
	p.pos = Vector2(pan_x, PAN_Y)
	events.append("pour")
	return p


# ------------------------------------------------------------------ input

## Analog stick x in [-1, 1].
func move_pan(axis: float, dt: float) -> void:
	pan_vel = clampf(axis, -1.0, 1.0) * PAN_SPEED
	pan_x = clampf(pan_x + pan_vel * dt, PAN_MIN_X, PAN_MAX_X)


func can_flip() -> bool:
	return pancake != null and pancake.state == P.IN_PAN


func in_air() -> bool:
	return pancake != null and pancake.state == P.FLYING


## The flipper's press. In the pan: flip. In the air: one more spin and a
## sparkle. Anything else: a sparkle and a giggle. Never harmful.
func try_flip() -> bool:
	if can_flip():
		var vx := next_flip_vx
		if is_nan(vx):
			vx = rng.randf_range(FLIP_VX_MIN, FLIP_VX_MAX)
			# Lean towards the middle of the stove so flips stay catchable.
			var mid := (PAN_MIN_X + PAN_MAX_X) * 0.5
			var toward := 1.0 if pan_x < mid else -1.0
			vx *= toward if rng.randf() < 0.7 else -toward
		next_flip_vx = NAN
		launch(Vector2(vx, -rng.randf_range(FLIP_VY_MIN, FLIP_VY_MAX)))
		return true
	if in_air():
		if pancake.extra_spins < MAX_EXTRA_SPINS:
			pancake.extra_spins += 1
		events.append("spin")
		return false
	events.append("toddler_fun")
	return false


func launch(velocity: Vector2) -> void:
	var p := pancake
	p.state = P.FLYING
	p.t = 0.0
	p.launch_pos = Vector2(pan_x, PAN_Y)
	p.pos = p.launch_pos
	p.launch_vel = velocity
	p.spin = 0.0
	p.extra_spins = 0
	p.extra_anim = 0.0
	events.append("flip")


## Where the flight is at `time_s` after launch (the closed-form parabola).
func flight_pos(time_s: float) -> Vector2:
	var p := pancake
	return p.launch_pos + p.launch_vel * time_s + Vector2(0, 0.5 * GRAVITY * time_s * time_s)


## Seconds from launch until the pancake falls back to height `y`.
func time_to_y(y: float) -> float:
	var p := pancake
	var vy := p.launch_vel.y
	var disc := vy * vy + 2.0 * GRAVITY * (y - p.launch_pos.y)
	return (-vy + sqrt(maxf(disc, 0.0))) / GRAVITY


## x where the current flight comes back to pan height.
func predict_landing_x() -> float:
	if not in_air():
		return pan_x
	return flight_pos(time_to_y(PAN_Y)).x


func pick_jar(dir: Vector2i) -> void:
	var i := JAR_DIRS.find(dir)
	if i != -1 and i != jar:
		jar = i
		events.append("pick")


func jar_pos(i: int) -> Vector2:
	return JAR_CENTER + Vector2(JAR_DIRS[i]) * JAR_SPREAD


## The topper's "a": the selected jar drops its topping on the top pancake.
func drop_topping(kind := "") -> void:
	if kind == "":
		kind = TOPPINGS[jar]
	var i := TOPPINGS.find(kind)
	var from := jar_pos(i) + Vector2(0, 30)
	falling.append({"kind": kind, "t": 0.0, "from": from, "pos": from,
		"local": random_spot(), "rot": rng.randf_range(-0.5, 0.5)})
	events.append("drop")


## A random point inside the pancake's top ellipse (relative to its centre).
func random_spot() -> Vector2:
	var x := rng.randf_range(-0.75, 0.75) * PANCAKE_A
	var half := PANCAKE_B * sqrt(maxf(0.0, 1.0 - pow(x / PANCAKE_A, 2.0)))
	return Vector2(x, rng.randf_range(-0.6, 0.5) * half)


## Clamp any point into the pancake ellipse (the "stick where it lands" rule).
static func clamp_to_ellipse(v: Vector2) -> Vector2:
	var k := pow(v.x / PANCAKE_A, 2.0) + pow(v.y / PANCAKE_B, 2.0)
	if k <= 1.0:
		return v
	return v / sqrt(k) * 0.98


func plate_ready() -> bool:
	return stack.size() >= STACK_FULL


func customer_waiting() -> bool:
	return customer != null and customer.state == C.WAIT


func can_serve() -> bool:
	return plate_ready() and customer_waiting()


## The cook's serve: the plate slides to the window. False when not ready.
func serve() -> bool:
	if not can_serve():
		return false
	var c: Dictionary = customer
	c.stack = stack.duplicate(true)
	c.toppings = toppings.duplicate(true)
	# Toppings still falling land on the new empty plate.
	stack.clear()
	toppings.clear()
	c.state = C.SPRINKLE if self_sprinkle else C.EAT
	c.t = -SLIDE_TIME          # the plate slides first
	c.sprinkled = 0
	c.sprinkle_n = rng.randi_range(2, 5)
	events.append("serve")
	if pancake == null:
		pancake = _new_pancake()
	return true


# ------------------------------------------------------------------ rules

## Always true: there is no wrong combination.
static func happy(_combo: Array) -> bool:
	return true


## 1 (a smile and hearts), 2 (a hop), 3 (a jump with stars) by topping count.
static func reaction_size(topping_count: int) -> int:
	if topping_count >= 7:
		return 3
	if topping_count >= 3:
		return 2
	return 1


# ------------------------------------------------------------------ step

func step(dt: float) -> void:
	if round_over:
		if customer != null:
			customer.t += dt   # the finale reaction keeps playing
		return
	time += dt
	_step_pancake(dt)
	_step_falling(dt)
	_step_dog(dt)
	_step_customer(dt)
	if not round_over and time >= round_limit:
		_finale()


func _step_pancake(dt: float) -> void:
	var p := pancake
	if p == null:
		return
	p.t += dt
	p.squash = maxf(0.0, p.squash - dt * 3.0)
	match p.state:
		P.POURING:
			p.pos = Vector2(pan_x, PAN_Y)
			if p.t >= POUR_TIME:
				_to_state(p, P.IN_PAN)
		P.IN_PAN:
			p.pos = Vector2(pan_x, PAN_Y)
			p.cook_bottom = minf(1.0, p.cook_bottom + dt / COOK_TIME)
		P.FLYING:
			_step_flight(p, dt)
		P.CATCHING:
			var target := Vector2(pan_x, PAN_Y)
			var u := clampf(p.t / CATCH_TIME, 0.0, 1.0)
			p.pos = p.from.lerp(target, u * u * (3.0 - 2.0 * u))
			p.spin = lerpf(p.spin, p.spin_target, clampf(dt * 20.0, 0.0, 1.0))
			if u >= 1.0:
				_land(p, "catch")
		P.GAG:
			_step_gag(p, dt)
		P.RETURNING:
			var target := Vector2(pan_x, PAN_Y)
			var u := clampf(p.t / RETURN_TIME, 0.0, 1.0)
			p.pos = p.from.lerp(target, u) + Vector2(0, -4.0 * 170.0 * u * (1.0 - u))
			p.spin = p.spin_target * u
			if u >= 1.0:
				_land(p, "return")
		P.SETTLING:
			p.pos = Vector2(pan_x, PAN_Y)
			p.cook_top = minf(1.0, p.cook_top + dt * 2.0)
			p.cook_bottom = minf(1.0, p.cook_bottom + dt * 2.0)
			if p.t >= SETTLE_TIME:
				p.from = p.pos
				_to_state(p, P.HOPPING)
				events.append("hop")
		P.HOPPING:
			var target := top_center(stack.size())
			var u := clampf(p.t / HOP_TIME, 0.0, 1.0)
			p.pos = p.from.lerp(target, u) + Vector2(0, -4.0 * 150.0 * u * (1.0 - u))
			p.spin = TAU * u
			if u >= 1.0:
				stack.append({"cook": 1.0})
				events.append("stack")
				if plate_ready():
					events.append("ding")
					pancake = null
				else:
					pancake = _new_pancake()


func _to_state(p: Pancake, s: int) -> void:
	p.state = s
	p.t = 0.0


func _step_flight(p: Pancake, dt: float) -> void:
	var prev_y := p.pos.y
	p.pos = flight_pos(p.t)
	var vy := p.vel().y
	# Half a turn over the whole flight (so it lands on its other face), plus
	# a full quick turn for every extra press of the flipper.
	var u := clampf(p.t / time_to_y(PAN_Y), 0.0, 1.0)
	p.extra_anim = move_toward(p.extra_anim, p.extra_spins * TAU, dt * TAU * 3.0)
	p.spin = PI * u + p.extra_anim
	if vy <= 0.0:
		return
	# The shelf cat: the pancake comes down onto the shelf.
	var shelf_y := SHELF_Y - PANCAKE_B
	if prev_y < shelf_y and p.pos.y >= shelf_y and p.pos.x >= SHELF_X0 and p.pos.x <= SHELF_X1:
		_start_gag(p, "cat")
		return
	if p.pos.y >= CATCH_LINE and absf(p.pos.x - pan_x) <= MAGNET:
		p.from = p.pos
		p.spin_target = PI + p.extra_spins * TAU
		_to_state(p, P.CATCHING)
		return
	if p.pos.y >= MISS_LINE:
		_start_gag(p, "dog" if p.pos.x < DOG_ZONE_X else "bounce")


func _start_gag(p: Pancake, kind: String) -> void:
	p.gag = kind
	p.landed_gag = kind != "dog"
	p.from = p.pos
	if kind == "cat":
		p.pos = CAT_HEAD
	_to_state(p, P.GAG)
	events.append("gag_" + kind)


func _step_gag(p: Pancake, dt: float) -> void:
	match p.gag:
		"dog":
			if not p.landed_gag:
				# Keep falling in front of the counter; the dog trots under it.
				var fall_t := p.t
				p.pos = p.from + Vector2(p.launch_vel.x * 0.4 * fall_t, 520.0 * fall_t + 0.5 * GRAVITY * fall_t * fall_t)
				p.pos.x = clampf(p.pos.x, DOG_MIN_X, DOG_MAX_X)
				if p.pos.y >= DOG_HEAD_Y - dog_jump * 30.0:
					p.landed_gag = true
					p.t = 0.0
					p.squash = 1.0
					events.append("woof")
			else:
				p.pos = Vector2(dog_x, DOG_HEAD_Y - dog_jump * 30.0)
				if p.t >= GAG_TIME.dog:
					_return(p)
		"cat":
			p.pos = CAT_HEAD + Vector2(sin(p.t * 18.0) * 4.0 * (1.0 - p.t / GAG_TIME.cat), 0)
			if p.t >= GAG_TIME.cat:
				_return(p)
		"bounce":
			var u := p.t / GAG_TIME.bounce
			var hop := absf(sin(u * TAU)) * 70.0 * (1.0 - u)
			p.pos = Vector2(p.from.x, MISS_LINE - hop)
			if p.t >= GAG_TIME.bounce:
				_return(p)
	p.spin = 0.0 if p.gag != "bounce" else p.spin


func _return(p: Pancake) -> void:
	p.from = p.pos
	p.spin = 0.0
	p.spin_target = PI
	_to_state(p, P.RETURNING)
	events.append("toss")


## A landing in the pan (a catch or the end of a gag): it counts as a flip.
func _land(p: Pancake, how: String) -> void:
	p.flips += 1
	var top := p.cook_top
	p.cook_top = p.cook_bottom
	p.cook_bottom = top
	p.spin = 0.0
	p.spin_target = 0.0
	p.extra_spins = 0
	p.squash = 1.0
	p.gag = ""
	p.pos = Vector2(pan_x, PAN_Y)
	_to_state(p, P.SETTLING if p.flips >= FLIPS_TO_DONE else P.IN_PAN)
	events.append(how)


## Centre of the top face of pancake `level` on the plate (-1 = the plate).
func top_center(level: int) -> Vector2:
	if level < 0:
		return PLATE_POS + Vector2(0, -6)
	return PLATE_POS + Vector2(0, -16 - level * STACK_STEP)


func _step_falling(dt: float) -> void:
	for i in range(falling.size() - 1, -1, -1):
		var f: Dictionary = falling[i]
		f.t += dt
		var level := stack.size() - 1
		var target: Vector2 = top_center(level) + f.local
		var u := clampf(f.t / TOPPING_FALL, 0.0, 1.0)
		f.pos = f.from.lerp(target, u * u)
		if u >= 1.0:
			falling.remove_at(i)
			_stick(f.kind, level, f.local, f.rot)


func _stick(kind: String, level: int, local: Vector2, rot: float) -> void:
	var on_level := 0
	for tp in toppings:
		if tp.level == level:
			on_level += 1
	if toppings.size() >= MAX_TOPPINGS:
		toppings.pop_front()
	toppings.append({"kind": kind, "level": level, "pos": clamp_to_ellipse(local),
		"lift": minf(on_level * 2.5, 40.0), "rot": rot, "age": 0.0})
	events.append("plop:" + kind)


func _step_dog(dt: float) -> void:
	var p := pancake
	var want := DOG_HOME_X
	var jump := 0.0
	if p != null and p.state == P.GAG and p.gag == "dog":
		want = clampf(p.pos.x, DOG_MIN_X, DOG_MAX_X)
		jump = 1.0 if p.landed_gag else 0.4
	dog_x = move_toward(dog_x, want, 900.0 * dt)
	dog_jump = move_toward(dog_jump, jump, 4.0 * dt)
	for tp in toppings:
		tp.age = tp.get("age", 0.0) + dt


func _next_customer() -> void:
	if queue.is_empty():
		customer = null
		return
	customer = {"animal": queue.pop_front(), "state": C.WALK_IN, "t": 0.0, "x": 1420.0,
		"joy": 0, "stack": [], "toppings": [], "sprinkled": 0, "sprinkle_n": 0}
	events.append("next_customer")


func _step_customer(dt: float) -> void:
	if customer == null:
		return
	var c: Dictionary = customer
	c.t += dt
	match c.state:
		C.WALK_IN:
			var u := clampf(c.t / WALK_TIME, 0.0, 1.0)
			c.x = lerpf(1420.0, WINDOW_X, 1.0 - pow(1.0 - u, 2.0))
			if u >= 1.0:
				c.state = C.WAIT
				c.t = 0.0
		C.WAIT:
			c.x = WINDOW_X
		C.SPRINKLE:
			if c.t >= 0.0:
				var want := int(c.t / SPRINKLE_TIME * c.sprinkle_n) + 1
				while c.sprinkled < mini(want, c.sprinkle_n):
					c.sprinkled += 1
					var kind := TOPPINGS[rng.randi() % TOPPINGS.size()]
					var level: int = c.stack.size() - 1
					c.toppings.append({"kind": kind, "level": level, "pos": random_spot(),
						"lift": c.sprinkled * 2.5, "rot": rng.randf_range(-0.5, 0.5), "age": 0.0})
					events.append("plop:" + kind)
				if c.t >= SPRINKLE_TIME:
					c.state = C.EAT
					c.t = 0.0
		C.EAT:
			if c.t >= 0.0 and int((c.t - dt) / 0.8) != int(c.t / 0.8):
				events.append("yum")
			if c.t >= EAT_TIME:
				c.state = C.HAPPY
				c.t = 0.0
				c.joy = reaction_size(c.toppings.size())
				events.append("joy:%d" % c.joy)
		C.HAPPY:
			if c.t >= HAPPY_TIME:
				c.state = C.LEAVE
				c.t = 0.0
				plates.append({"animal": c.animal, "stack": c.stack, "toppings": c.toppings, "joy": c.joy})
				served += 1
				events.append("leave")
		C.LEAVE:
			var u := clampf(c.t / LEAVE_TIME, 0.0, 1.0)
			c.x = lerpf(WINDOW_X, 1440.0, u * u)
			if u >= 1.0:
				if served >= customers_target:
					round_over = true
					events.append("round_over")
				else:
					_next_customer()


## The 7-minute rule: every customer still waiting gets a pancake at once.
## The one at the window gets a loaded stack and cheers (the screen shows it).
func _finale() -> void:
	finale = true
	var at_window := false
	if customer != null and served < customers_target:
		var c: Dictionary = customer
		if c.state == C.WALK_IN or c.state == C.WAIT:
			var plate := _gift_plate(c.animal, rng.randi_range(7, 10))
			c.stack = plate.stack
			c.toppings = plate.toppings
			c.x = WINDOW_X
			at_window = true
		elif c.state != C.LEAVE:
			pass  # already eating their own plate
		if c.state != C.LEAVE:
			c.joy = reaction_size(c.toppings.size())
			plates.append({"animal": c.animal, "stack": c.stack, "toppings": c.toppings, "joy": c.joy})
			c.state = C.HAPPY
			c.t = 0.0
			events.append("joy:%d" % c.joy)
	for a in queue:
		if plates.size() >= customers_target:
			break
		plates.append(_gift_plate(a, rng.randi_range(2, 8)))
	queue.clear()
	served = customers_target
	if not at_window and customer != null and customer.state == C.LEAVE:
		customer = null
	round_over = true
	events.append("finale")
	events.append("round_over")


func _gift_plate(animal: String, n_toppings: int) -> Dictionary:
	var tops: Array = []
	for k in n_toppings:
		tops.append({"kind": TOPPINGS[rng.randi() % 4], "level": 2, "pos": random_spot(),
			"lift": (k / 3) * 2.5, "rot": rng.randf_range(-0.5, 0.5), "age": 1.0})
	return {"animal": animal, "stack": [{"cook": 1.0}, {"cook": 1.0}, {"cook": 1.0}],
		"toppings": tops, "joy": reaction_size(n_toppings)}


func drain_events() -> Array[String]:
	var out := events.duplicate()
	events.clear()
	return out
