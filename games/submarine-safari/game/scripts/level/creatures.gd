extends RefCounted
## Creature behaviour as small node-free state machines (unit tested).
##
## One Creature per species. The level owns the sprites and just reads
## pos / shown / pose / glow / spin every frame.
##
## - EASY  (free swimmers): always out, wander around their home.
## - HIDER (crab, octopus, eel): hidden until a sonar ping or a light flash
##   comes near, then out for OUT_SECONDS (the eel only peeks), then hide.
## - LIGHT (trench light-lovers): shown only while the sub's lights are on.
## - WHALE: waits, passes once near the surface, is gone.
## Nothing here ever chases or harms the sub.

const Species := preload("res://scripts/level/species.gd")

enum State { SWIM, HIDDEN, OUT, WAIT, PASS, GONE }

const OUT_SECONDS := 9.0
const SONAR_RANGE := 170.0
const FLASH_NEAR := 80.0          # a flash this close brings a hider out
const GLOW_RANGE := 48.0          # 3 tiles: fish glow and wiggle
const GLOW_SECONDS := 2.0
const SPIN_SECONDS := 1.0
const PUFF_SECONDS := 2.5
const FADE_RATE := 5.0            # shown 0 -> 1 in 0.2 s
const WHALE_Y := 44.0


class Creature:
	var id := ""
	var kind := 0
	var home := Vector2.ZERO
	var pos := Vector2.ZERO
	var vel := Vector2.ZERO
	var target := Vector2.ZERO
	var state := 0
	var t := 0.0            # time in the current state
	var shown := 1.0        # 0 = invisible, 1 = fully out
	var glow := 0.0         # seconds of glow left
	var spin := 0.0         # seconds of disco spin left
	var puffed := 0.0       # pufferfish only
	var facing := 1         # 1 right, -1 left
	var roam := 0.0
	var speed := 0.0
	var size := Vector2i(16, 16)
	var rng := RandomNumberGenerator.new()

	func photographable() -> bool:
		match kind:
			Species.Kind.EASY:
				return true
			Species.Kind.HIDER:
				return state == State.OUT and shown >= 0.5
			Species.Kind.LIGHT:
				return shown >= 0.5
			Species.Kind.WHALE:
				return state == State.PASS
		return false

	func rect() -> Rect2:
		return Rect2(pos - Vector2(size) * 0.5, Vector2(size))

	## Pose frame hint for the level: 0 idle, 1 out (hider), 2 puffed.
	func is_hidden() -> bool:
		return shown < 0.05


static func make(id: String, home: Vector2, seed := 0) -> Creature:
	var c := Creature.new()
	c.id = id
	c.kind = Species.kind(id)
	c.home = home
	c.pos = home
	c.target = home
	c.roam = float(Species.INFO[id].roam)
	c.speed = float(Species.INFO[id].speed)
	c.size = Species.size_of(id)
	c.rng.seed = hash(id) + seed
	match c.kind:
		Species.Kind.EASY:
			c.state = State.SWIM
			c.shown = 1.0
		Species.Kind.HIDER:
			c.state = State.HIDDEN
			c.shown = 0.0
		Species.Kind.LIGHT:
			c.state = State.SWIM
			c.shown = 0.0
		Species.Kind.WHALE:
			c.state = State.WAIT
			c.shown = 0.0
	return c


## Advance one creature. `lights_on`: the sub's lights are flashing.
static func step(c: Creature, dt: float, lights_on: bool) -> void:
	c.t += dt
	c.glow = maxf(0.0, c.glow - dt)
	c.spin = maxf(0.0, c.spin - dt)
	c.puffed = maxf(0.0, c.puffed - dt)
	match c.kind:
		Species.Kind.EASY:
			_wander(c, dt)
		Species.Kind.HIDER:
			_hider(c, dt)
		Species.Kind.LIGHT:
			var want := 1.0 if lights_on else 0.0
			c.shown = move_toward(c.shown, want, FADE_RATE * dt)
			_wander(c, dt)
			if c.id == "jellyfish":
				c.pos.y += sin(c.t * 3.0) * 6.0 * dt   # the pulse bob
		Species.Kind.WHALE:
			_whale(c, dt)


static func _wander(c: Creature, dt: float) -> void:
	if c.roam <= 0.0:
		return
	if c.pos.distance_to(c.target) < 3.0 or c.t > 4.0:
		var a := c.rng.randf() * TAU
		var r := c.roam * sqrt(c.rng.randf())
		c.target = c.home + Vector2(cos(a) * r, sin(a) * r * 0.6)
		c.t = 0.0
	var want := (c.target - c.pos).limit_length(1.0) * c.speed
	c.vel = c.vel.lerp(want, clampf(dt * 2.0, 0.0, 1.0))
	c.pos += c.vel * dt
	if absf(c.vel.x) > 2.0:
		c.facing = 1 if c.vel.x > 0.0 else -1


static func _hider(c: Creature, dt: float) -> void:
	match c.state:
		State.HIDDEN:
			c.shown = move_toward(c.shown, 0.0, FADE_RATE * dt)
			c.pos = c.pos.lerp(c.home, clampf(dt * 4.0, 0.0, 1.0))
		State.OUT:
			c.shown = move_toward(c.shown, 1.0, FADE_RATE * dt)
			match c.id:
				"crab":   # scuttles side to side along the shelf
					c.pos.x = c.home.x + sin(c.t * 1.2) * c.roam
					c.facing = 1 if cos(c.t * 1.2) > 0.0 else -1
				"octopus":  # floats up out of the wreck and bobs
					c.pos = c.home + Vector2(sin(c.t * 0.8) * c.roam, -10.0 + sin(c.t * 1.7) * 4.0)
				_:  # the eel only peeks out of its hole
					c.pos = c.home
					c.facing = -1
			if c.t >= OUT_SECONDS:
				c.state = State.HIDDEN
				c.t = 0.0


static func _whale(c: Creature, dt: float) -> void:
	match c.state:
		State.PASS:
			c.shown = move_toward(c.shown, 1.0, dt)
			c.pos.x += c.facing * c.speed * dt
			c.pos.y = WHALE_Y + sin(c.t * 0.6) * 4.0
			if (c.facing > 0 and c.pos.x > 1280.0 + 80.0) or (c.facing < 0 and c.pos.x < -80.0):
				c.state = State.GONE
				c.shown = 0.0
		_:
			c.shown = 0.0


## The whale starts its one pass, entering from the side away from `sub_x`
## so it swims past the sub on screen.
static func start_whale(c: Creature, sub_x: float) -> void:
	if c.state != State.WAIT:
		return
	c.state = State.PASS
	c.t = 0.0
	c.facing = 1 if sub_x > 640.0 else -1
	c.pos = Vector2(sub_x - 200.0 * c.facing, WHALE_Y)
	c.pos.x = clampf(c.pos.x, -80.0, 1360.0)


## A sonar ping from `origin`: hiders in range come out. Returns ids that did.
static func sonar(creatures: Array, origin: Vector2) -> Array[String]:
	var out: Array[String] = []
	for c in creatures:
		if c.kind == Species.Kind.HIDER and c.home.distance_to(origin) <= SONAR_RANGE:
			if c.state != State.OUT:
				out.append(c.id)
			_come_out(c)
	return out


## A light flash at `origin`: nearby fish glow and wiggle, hiders near it come
## out, a near pufferfish puffs. Returns ids that came out.
static func flash(creatures: Array, origin: Vector2) -> Array[String]:
	var out: Array[String] = []
	for c in creatures:
		var d: float = c.pos.distance_to(origin)
		if d <= GLOW_RANGE + c.size.x * 0.5 and c.kind != Species.Kind.WHALE:
			c.glow = GLOW_SECONDS
		if c.kind == Species.Kind.HIDER and c.home.distance_to(origin) <= FLASH_NEAR:
			if c.state != State.OUT:
				out.append(c.id)
			_come_out(c)
		if c.id == "pufferfish" and d <= FLASH_NEAR:
			c.puffed = PUFF_SECONDS
	return out


static func disco(creatures: Array, view: Rect2) -> int:
	var n := 0
	for c in creatures:
		if view.has_point(c.pos) and c.shown > 0.5:
			c.spin = SPIN_SECONDS
			c.glow = GLOW_SECONDS
			n += 1
	return n


static func _come_out(c: Creature) -> void:
	if c.state == State.OUT:
		c.t = minf(c.t, 1.0)  # stays out longer
		return
	c.state = State.OUT
	c.t = 0.0
