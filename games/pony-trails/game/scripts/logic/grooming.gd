extends RefCounted
## The stable's rules, node-free: four mud patches the brush scrubs off, the
## carrots (every third one goes to the foal), the four hooves the adult picks,
## the saddle that needs all four, the braid ribbon, and the stable cat that
## finishes whatever is left after 90 s.
##
## Positions are in the stable screen's pixels. The brush lives on a patch
## (the hotspot pattern of Pillow Fort's spot graph): a direction hops it to
## the nearest patch that way, so the 5-year-old can never miss.

const PATCHES: Array[String] = ["head", "back", "legs", "tail"]
const SCRUB_TIME := 2.0          # seconds of scrubbing to clear a patch
const SLOW_SCRUB := 0.45         # the self-scrubbing brush (no 5-year-old)
const CAT_AT := 90.0             # the cat comes to help (scaled by Game.day_scale)
const CAT_EVERY := 1.1           # the cat finishes one thing every this many seconds
const IDLE_ASSIST := 5.0         # a seat idle this long gets help

var patch_pos: Array[Vector2] = []
var dirt: Array[float] = [1.0, 1.0, 1.0, 1.0]
## Index of the patch the brush is on (-1 = resting at its start).
var brush := -1
var brush_rest := Vector2.ZERO
var hoof_pos: Array[Vector2] = []
var hooves: Array[bool] = [false, false, false, false]
var saddle_pos := Vector2.ZERO
var saddled := false
var ribbon := -1
var carrots := 0
var cat_at := CAT_AT
var cat_active := false
var _cat_t := 0.0
## What the cat finished last (a patch or hoof index).
var cat_last := -1


func _init(patches: Array[Vector2] = [], hoof_points: Array[Vector2] = [], saddle_at := Vector2.ZERO,
		rest := Vector2.ZERO) -> void:
	patch_pos = patches.duplicate()
	while patch_pos.size() < 4:
		patch_pos.append(Vector2(40 + patch_pos.size() * 30, 60))
	hoof_pos = hoof_points.duplicate()
	while hoof_pos.size() < 4:
		hoof_pos.append(Vector2(60 + hoof_pos.size() * 20, 150))
	saddle_pos = saddle_at
	brush_rest = rest


# ---------------------------------------------------------------- mud

## 0 (muddy) .. 3 (faint), 4 = gone.
func fade_stage(i: int) -> int:
	if dirt[i] <= 0.0:
		return 4
	return clampi(int((1.0 - dirt[i]) * 4.0), 0, 3)


func is_clean(i: int) -> bool:
	return dirt[i] <= 0.0


func all_clean() -> bool:
	for d in dirt:
		if d > 0.0:
			return false
	return true


func dirty_count() -> int:
	var n := 0
	for d in dirt:
		if d > 0.0:
			n += 1
	return n


func brush_pos() -> Vector2:
	return brush_rest if brush == -1 else patch_pos[brush]


## Scrubs the patch under the brush. Returns true on the frame it comes clean.
func scrub(dt: float, speed := 1.0) -> bool:
	if brush == -1 or dirt[brush] <= 0.0:
		return false
	dirt[brush] = maxf(0.0, dirt[brush] - dt * speed / SCRUB_TIME)
	return dirt[brush] <= 0.0


## The nearest patch from the brush in direction d (a spot-graph hop: the
## smallest along + 2 * across inside a cone; any patch ahead as a fall-back).
func nearest_in(d: Vector2i, from := Vector2.INF) -> int:
	if d == Vector2i.ZERO:
		return brush
	var origin := brush_pos() if from == Vector2.INF else from
	var dv := Vector2(d)
	var best := -1
	var best_cost := INF
	var loose := -1
	var loose_cost := INF
	for j in patch_pos.size():
		if j == brush:
			continue
		var delta := patch_pos[j] - origin
		var along := delta.dot(dv)
		if along <= 0.5:
			continue
		var across := absf(delta.dot(Vector2(dv.y, -dv.x)))
		var cost := along + 2.0 * across
		if across <= along * 1.2:
			if cost < best_cost:
				best_cost = cost
				best = j
		elif cost < loose_cost:
			loose_cost = cost
			loose = j
	return best if best != -1 else loose


## Hops the brush in direction d. Returns the new patch (unchanged at an edge).
func move_brush(d: Vector2i) -> int:
	var to := nearest_in(d)
	if to != -1:
		brush = to
	return brush


## The dirty patch nearest the brush (for the self-scrubbing brush and the cat).
func next_dirty() -> int:
	var best := -1
	var best_d := INF
	for j in patch_pos.size():
		if dirt[j] > 0.0:
			var dd := patch_pos[j].distance_to(brush_pos())
			if dd < best_d:
				best_d = dd
				best = j
	return best


# ---------------------------------------------------------------- carrots

## The toddler's carrot. Returns who eats it: every third goes to the foal.
func give_carrot() -> String:
	carrots += 1
	return "foal" if carrots % 3 == 0 else "mare"


# ---------------------------------------------------------------- hooves and saddle

func hooves_done() -> int:
	var n := 0
	for h in hooves:
		if h:
			n += 1
	return n


func pick_hoof(i: int) -> bool:
	if i < 0 or i >= 4 or hooves[i]:
		return false
	hooves[i] = true
	return true


func can_saddle() -> bool:
	return hooves_done() == 4


## Saddle and bridle go on (only once all four hooves are done).
func put_saddle() -> bool:
	if saddled or not can_saddle():
		return false
	saddled = true
	return true


## The hotspot under the hand: {"kind": "hoof"|"saddle", "i": n} or {} (within `reach`).
func hotspot_at(p: Vector2, reach := 12.0) -> Dictionary:
	var best := {}
	var best_d := reach
	for i in 4:
		if hooves[i]:
			continue
		var d := hoof_pos[i].distance_to(p)
		if d <= best_d:
			best_d = d
			best = {"kind": "hoof", "i": i}
	if not saddled and saddle_pos.distance_to(p) <= maxf(best_d, reach + 4.0) and (best.is_empty() or saddle_pos.distance_to(p) < best_d):
		best = {"kind": "saddle", "i": 0}
	return best


## Where the adult should go next (the idle assist and the demo): a hoof, then the saddle.
func next_target() -> Dictionary:
	for i in 4:
		if not hooves[i]:
			return {"kind": "hoof", "i": i, "pos": hoof_pos[i]}
	if not saddled:
		return {"kind": "saddle", "i": 0, "pos": saddle_pos}
	return {}


# ---------------------------------------------------------------- braid

func pick_ribbon(i: int) -> void:
	ribbon = clampi(i, 0, 3)


## Ribbon index for a 4-way direction: up, right, down, left.
static func ribbon_for(d: Vector2i) -> int:
	match d:
		Vector2i.UP: return 0
		Vector2i.RIGHT: return 1
		Vector2i.DOWN: return 2
		Vector2i.LEFT: return 3
	return -1


func ready_to_go() -> bool:
	return all_clean() and saddled and ribbon != -1


# ---------------------------------------------------------------- the stable cat

## Called every frame with the stage time. After cat_at seconds the cat finishes
## one thing every CAT_EVERY s. Returns what it did ("" when nothing).
func cat_step(time: float, dt: float) -> String:
	if time < cat_at or ready_to_go():
		return ""
	if not cat_active:
		cat_active = true
		_cat_t = 0.0
		return "cat_arrives"
	_cat_t += dt
	if _cat_t < CAT_EVERY:
		return ""
	_cat_t = 0.0
	var j := next_dirty()
	if j != -1:
		dirt[j] = 0.0
		cat_last = j
		return "patch"
	var t := next_target()
	if not t.is_empty():
		if t.kind == "hoof":
			pick_hoof(t.i)
			cat_last = t.i
			return "hoof"
		put_saddle()
		return "saddle"
	if ribbon == -1:
		ribbon = 0
		return "ribbon"
	return ""
