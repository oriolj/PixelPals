extends RefCounted
## Peekaboo director: the toddler's any-button makes a friend pop out from
## behind the hiding spot nearest the flashlight that is not busy, cover its
## eyes, say "peekaboo!" and duck back. Presses inside the cooldown twinkle
## the fairy lights instead, so every press is answered.
##
## Nothing moves unless a player pressed, with one slow exception: with no
## toddler seated, a friend peeks out on its own every AUTO_EVERY seconds,
## and only from a spot inside the flashlight.
##
## Timeline of one friend (seconds since the press):
##   0.0-0.4  rises from behind the spot, eased (frame 0: peeking)
##   0.4-1.0  eyes covered (frame 1)
##   1.0-1.9  peekaboo! (frame 2), the chime plays at 1.0
##   1.9-2.3  ducks back (frame 3), sinking
##   2.3      gone

const COOLDOWN := 1.0
const AUTO_EVERY := 25.0
const RISE := 0.4
const COVER_END := 1.0
const PEEK_END := 1.9
const DONE := 2.3
const KINDS: Array[String] = ["teddy_big", "bunny_big", "sleepy_cat"]

## Active friends: {"spot": int, "kind": String, "t": float, "chimed": bool}
var friends: Array[Dictionary] = []
var cooldown_t := 0.0
var auto_t := 0.0
var pops := 0
var twinkles := 0
var _next_kind := 0


## A press from the toddler seat. `spots` are the fort's spot dicts (pos,
## open), `light` the flashlight centre. Returns {"pop": friend} or
## {"twinkle": true}.
func press(spots: Array, light: Vector2) -> Dictionary:
	if cooldown_t > 0.0:
		twinkles += 1
		return {"twinkle": true}
	var spot := pick_spot(spots, light, INF)
	if spot == -1:
		twinkles += 1
		return {"twinkle": true}
	return {"pop": _pop(spot)}


## With no toddler seated: count up and peek out slowly, inside the light only.
## `lit_radius` is how far from the light centre a spot still counts as lit.
func auto_step(dt: float, spots: Array, light: Vector2, lit_radius: float) -> Dictionary:
	auto_t += dt
	if auto_t < AUTO_EVERY or cooldown_t > 0.0:
		return {}
	var spot := pick_spot(spots, light, lit_radius)
	if spot == -1:
		return {}  # try again next frame: only ever inside the light
	auto_t = 0.0
	return {"pop": _pop(spot)}


## Spot nearest to `light` that is closed and has no friend, within max_dist.
func pick_spot(spots: Array, light: Vector2, max_dist: float) -> int:
	var best := -1
	var best_d := INF
	for i in spots.size():
		var s: Dictionary = spots[i]
		if s.get("open", 0.0) > 0.0 or busy(i):
			continue
		var d := light.distance_to(Vector2(s.pos))
		if d <= max_dist and d < best_d:
			best_d = d
			best = i
	return best


func busy(spot: int) -> bool:
	for f in friends:
		if f.spot == spot:
			return true
	return false


func _pop(spot: int) -> Dictionary:
	var f := {"id": pops, "spot": spot, "kind": KINDS[_next_kind % KINDS.size()], "t": 0.0, "chimed": false}
	_next_kind += 1
	friends.append(f)
	pops += 1
	cooldown_t = COOLDOWN
	return f


## Advances every friend. Returns the friends that reached "peekaboo!" this
## step (the caller plays the chime).
func step(dt: float) -> Array[Dictionary]:
	cooldown_t = maxf(0.0, cooldown_t - dt)
	var chimes: Array[Dictionary] = []
	for i in range(friends.size() - 1, -1, -1):
		var f: Dictionary = friends[i]
		f.t += dt
		if not f.chimed and f.t >= COVER_END:
			f.chimed = true
			chimes.append(f)
		if f.t >= DONE:
			friends.remove_at(i)
	return chimes


static func frame_at(t: float) -> int:
	if t < RISE:
		return 0
	if t < COVER_END:
		return 1
	if t < PEEK_END:
		return 2
	return 3


## How far up the friend has risen, 0 (hidden) to 1 (fully up). Smooth, never sudden.
static func rise_at(t: float) -> float:
	if t < RISE:
		var k := t / RISE
		return k * k * (3.0 - 2.0 * k)
	if t < PEEK_END:
		return 1.0
	var k2 := clampf((t - PEEK_END) / (DONE - PEEK_END), 0.0, 1.0)
	return 1.0 - k2 * k2 * (3.0 - 2.0 * k2)
