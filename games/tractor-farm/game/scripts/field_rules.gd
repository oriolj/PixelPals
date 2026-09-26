extends RefCounted
## The farm's rules, with no nodes: the 16x9 field, the trailer, the barn and
## the run clock. The level screen owns one of these, feeds it the tractor's
## footprint cells, rain and time, and drains `events` every frame for the
## visuals and sounds. Tests drive it directly.
##
## A tile goes grass -> ploughed -> seeded(crop) -> sprout -> growing -> ripe
## -> (harvested) -> ploughed. Nothing ever goes backwards on its own and no
## child input can destroy work: wheels never crush, rain never drowns, a
## second seed never replaces the first.

enum Tile { GRASS, PLOUGHED, SEEDED, SPROUT, GROWING, RIPE }
enum Crop { CARROT, PUMPKIN, SUNFLOWER, STRAWBERRY }

const W := 16
const H := 9
const TILE := 64
const CROP_COUNT := 4
## Plants grow one stage on their own this often (the sun), rain or not.
const SUN_SECONDS := 20.0
const TRAILER_CAP := 24
## The run ends (the giant vegetable) when the barn holds this many crops...
const END_CROPS := 30
## ...or after this many seconds of play.
const END_SECONDS := 360.0
## Rain footprint, in tiles, around the point under the cloud.
const RAIN_RADIUS := 1.5
## Seconds a rained-on empty tile stays wet (a puddle).
const WET_SECONDS := 7.0

var state := PackedInt32Array()
var crop := PackedInt32Array()
## Seconds since the tile last changed stage (drives the sun growth).
var grow_t := PackedFloat32Array()
## Seconds of puddle left on an empty tile.
var wet := PackedFloat32Array()
var trailer: Array[int] = []
var barn: Array[int] = [0, 0, 0, 0]
var planted: Array[int] = [0, 0, 0, 0]
var elapsed := 0.0
## The time limit of this run (Game.run_limit; the plan says 6 minutes).
var end_seconds := END_SECONDS
## What happened since the last drain: {"type", "cell", "crop", "stage"}.
## Types: plough, plant, grow, sparkle, puddle, wobble, harvest, tip, nibble.
var events: Array[Dictionary] = []


func _init() -> void:
	state.resize(W * H)
	crop.resize(W * H)
	grow_t.resize(W * H)
	wet.resize(W * H)
	crop.fill(-1)


# ---------------------------------------------------------------- cells

static func idx(c: Vector2i) -> int:
	return c.y * W + c.x


static func in_bounds(c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < W and c.y < H


## Cell under a point in field-local pixels (0,0 = the field's top-left).
static func cell_at(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


static func cell_center(c: Vector2i) -> Vector2:
	return Vector2((c.x + 0.5) * TILE, (c.y + 0.5) * TILE)


## The seed picker: up carrot, right pumpkin, down sunflower, left strawberry.
static func seed_for_dir(d: Vector2i) -> int:
	match d:
		Vector2i.UP: return Crop.CARROT
		Vector2i.RIGHT: return Crop.PUMPKIN
		Vector2i.DOWN: return Crop.SUNFLOWER
		Vector2i.LEFT: return Crop.STRAWBERRY
	return -1


static func dir_for_seed(c: int) -> Vector2i:
	return [Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT][c]


func tile(c: Vector2i) -> int:
	return state[idx(c)] if in_bounds(c) else -1


func crop_of(c: Vector2i) -> int:
	return crop[idx(c)] if in_bounds(c) else -1


func is_growing(c: Vector2i) -> bool:
	var s := tile(c)
	return s >= Tile.SEEDED and s < Tile.RIPE


func _emit(type: String, c: Vector2i, extra := {}) -> void:
	var e := {"type": type, "cell": c, "crop": crop_of(c), "stage": tile(c)}
	e.merge(extra, true)
	events.append(e)


func drain_events() -> Array[Dictionary]:
	var out := events
	events = []
	return out


# ---------------------------------------------------------------- tractor

## The plough turns grass into furrows. Anything else is left alone.
func plough(c: Vector2i) -> bool:
	if tile(c) != Tile.GRASS:
		return false
	state[idx(c)] = Tile.PLOUGHED
	wet[idx(c)] = 0.0
	_emit("plough", c)
	return true


## The planter sows `seed_crop` on ploughed soil only; a seeded tile keeps its
## first seed.
func plant(c: Vector2i, seed_crop: int) -> bool:
	if seed_crop < 0 or seed_crop >= CROP_COUNT or tile(c) != Tile.PLOUGHED:
		return false
	var i := idx(c)
	state[i] = Tile.SEEDED
	crop[i] = seed_crop
	grow_t[i] = 0.0
	wet[i] = 0.0
	planted[seed_crop] += 1
	_emit("plant", c)
	return true


## Wheels over a tile: a ripe crop is harvested into the trailer (while it
## has room); a young plant only wobbles.
func drive_over(c: Vector2i) -> void:
	var s := tile(c)
	if s == Tile.RIPE:
		harvest(c)
	elif s >= Tile.SEEDED and s < Tile.RIPE:
		_emit("wobble", c)


func harvest(c: Vector2i) -> bool:
	if tile(c) != Tile.RIPE or trailer.size() >= TRAILER_CAP:
		return false
	var i := idx(c)
	var got := crop[i]
	trailer.append(got)
	state[i] = Tile.PLOUGHED
	crop[i] = -1
	grow_t[i] = 0.0
	events.append({"type": "harvest", "cell": c, "crop": got, "stage": Tile.PLOUGHED})
	return true


func trailer_full() -> bool:
	return trailer.size() >= TRAILER_CAP


## Tip the trailer into the barn: every crop goes to its own crate.
## Returns the crops tipped, in trailer order.
func tip() -> Array[int]:
	var out: Array[int] = trailer.duplicate()
	for c in out:
		barn[c] += 1
	trailer.clear()
	if not out.is_empty():
		events.append({"type": "tip", "cell": Vector2i(-1, -1), "crop": -1, "stage": -1, "crops": out})
	return out


func barn_total() -> int:
	var n := 0
	for v in barn:
		n += v
	return n


# ---------------------------------------------------------------- growth

## One growth step on a tile, from rain or sun. Growing tiles advance a
## stage; ripe ones sparkle; empty ones get a puddle. Never harmful.
func advance(c: Vector2i) -> int:
	if not in_bounds(c):
		return -1
	var i := idx(c)
	var s := state[i]
	if s >= Tile.SEEDED and s < Tile.RIPE:
		state[i] = s + 1
		grow_t[i] = 0.0
		_emit("grow", c)
	elif s == Tile.RIPE:
		_emit("sparkle", c)
	else:
		var fresh := wet[i] <= 0.0
		wet[i] = WET_SECONDS
		if fresh:
			_emit("puddle", c)
	return state[i]


## Cells whose centre lies within the rain circle around `center_px`.
static func rain_cells(center_px: Vector2) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var r := RAIN_RADIUS * TILE
	var c0 := cell_at(center_px)
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := c0 + Vector2i(dx, dy)
			if in_bounds(c) and cell_center(c).distance_to(center_px) <= r:
				out.append(c)
	return out


## Rain under the cloud: every cell in the circle not in `already` grows one
## step (and is added to `already`, so one shower grows each tile once).
func rain(center_px: Vector2, already := {}) -> Array[Vector2i]:
	var hit: Array[Vector2i] = []
	for c in rain_cells(center_px):
		if already.has(c):
			continue
		already[c] = true
		advance(c)
		hit.append(c)
	return hit


## Is there anything under the circle that rain would grow?
func has_growing_near(center_px: Vector2) -> bool:
	for c in rain_cells(center_px):
		if is_growing(c):
			return true
	return false


## Time passes: the sun grows every plant one stage per SUN_SECONDS, and
## puddles dry.
func tick(dt: float) -> void:
	elapsed += dt
	for i in state.size():
		var s := state[i]
		if s >= Tile.SEEDED and s < Tile.RIPE:
			grow_t[i] += dt
			if grow_t[i] >= SUN_SECONDS:
				advance(Vector2i(i % W, i / W))
				if events.size() > 0 and events[-1].type == "grow":
					events[-1]["sun"] = true
		if wet[i] > 0.0:
			wet[i] = maxf(0.0, wet[i] - dt)


func run_over() -> bool:
	return barn_total() >= END_CROPS or elapsed >= end_seconds


## The crop sown most often this run (ties go to the lower id; carrot if
## nothing was planted).
func most_planted() -> int:
	var best := 0
	for c in CROP_COUNT:
		if planted[c] > planted[best]:
			best = c
	return best


# ---------------------------------------------------------------- visitors

## An animal visitor eats one ripe crop (no counter anywhere goes down).
func nibble(c: Vector2i) -> bool:
	if tile(c) != Tile.RIPE:
		return false
	var i := idx(c)
	var got := crop[i]
	state[i] = Tile.PLOUGHED
	crop[i] = -1
	grow_t[i] = 0.0
	events.append({"type": "nibble", "cell": c, "crop": got, "stage": Tile.PLOUGHED})
	return true


func cells_in(s: int) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for i in state.size():
		if state[i] == s:
			out.append(Vector2i(i % W, i / W))
	return out


func count(s: int) -> int:
	return state.count(s)
