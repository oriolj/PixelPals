extends RefCounted
## The space station's build plan: five module slots around the core, each with
## a glowing port of its kind. A module only fits its own kind's port. The
## cargo arrives in slot order along a lane from the left; a missed cargo
## drifts off the right edge and loops back in from the left.

const KINDS := ["lab", "solar", "habitat", "robot"]
const COLORS := {
	"lab": Color("#0099db"), "solar": Color("#feae34"),
	"habitat": Color("#f77622"), "robot": Color("#63c74d"),
}
## Slot kind, offset of the module centre from the core centre, and the point
## the Shuttle's autopilot parks at (relative to the core) to fit it.
const SLOTS := [
	{"kind": "lab", "offset": Vector2(-24, 0), "approach": Vector2(-60, 14)},
	{"kind": "solar", "offset": Vector2(0, -16), "approach": Vector2(-20, -42)},
	{"kind": "habitat", "offset": Vector2(24, 0), "approach": Vector2(12, 46)},
	{"kind": "solar", "offset": Vector2(0, 16), "approach": Vector2(-20, 46)},
	{"kind": "robot", "offset": Vector2(40, 0), "approach": Vector2(30, 46)},
]
## A held module within this distance of its matching port clicks in.
const DOCK_R := 6.0
## ... and within this one the port pulls it (the magnet assist).
const MAGNET_R := 22.0

## The cargo lane: y, spawn x, loop x, speed (the first stretch is faster so a
## new cargo arrives quickly).
const LANE_Y := 28.0
const SPAWN_X := -16.0
const LOOP_X := 336.0
const DRIFT := 9.0
const ENTER_DRIFT := 28.0
const ENTER_UNTIL_X := 24.0

var core := Vector2(256, 66)
var fitted: Array[bool] = [false, false, false, false, false]


func _init(core_pos := Vector2(256, 66)) -> void:
	core = core_pos


func port_pos(i: int) -> Vector2:
	return core + SLOTS[i].offset


func kind_of(i: int) -> String:
	return SLOTS[i].kind


## The next slot to build (lowest unfitted), or -1 when the station is complete.
func next_slot() -> int:
	return fitted.find(false)


func next_kind() -> String:
	var i := next_slot()
	return "" if i == -1 else kind_of(i)


func count() -> int:
	return fitted.count(true)


func done() -> bool:
	return next_slot() == -1


## The free slot of this kind whose port is within `radius` of pos, or -1.
## A module never fits another kind's port.
func can_dock(kind: String, pos: Vector2, radius := DOCK_R) -> int:
	var best := -1
	var best_d := radius
	for i in SLOTS.size():
		if fitted[i] or kind_of(i) != kind:
			continue
		var d := port_pos(i).distance_to(pos)
		if d <= best_d:
			best = i
			best_d = d
	return best


## The nearest free port of another kind within `radius` (a wrong fit: boing).
func wrong_port_near(kind: String, pos: Vector2, radius := DOCK_R) -> int:
	for i in SLOTS.size():
		if not fitted[i] and kind_of(i) != kind and port_pos(i).distance_to(pos) <= radius:
			return i
	return -1


## The free slot of `kind` nearest to pos (where the magnet pulls).
func target_slot(kind: String, pos: Vector2) -> int:
	var best := -1
	var best_d := INF
	for i in SLOTS.size():
		if fitted[i] or kind_of(i) != kind:
			continue
		var d := port_pos(i).distance_to(pos)
		if d < best_d:
			best = i
			best_d = d
	return best


func fit(i: int) -> void:
	fitted[i] = true


## The station's bounding box for soft collisions (the core plus every slot).
func bounds() -> Rect2:
	return Rect2(core + Vector2(-34, -26), Vector2(84, 52))


## Moves a floating cargo along the lane; returns true when it looped (missed).
static func drift(cargo: Dictionary, dt: float) -> bool:
	var speed := ENTER_DRIFT if cargo.pos.x < ENTER_UNTIL_X else DRIFT
	cargo.pos.x += speed * dt
	# Drift back toward the lane after being let go elsewhere.
	cargo.pos.y = move_toward(cargo.pos.y, LANE_Y, 6.0 * dt)
	if cargo.pos.x > LOOP_X:
		cargo.pos.x = SPAWN_X
		cargo.pos.y = LANE_Y
		cargo["loops"] = int(cargo.get("loops", 0)) + 1
		return true
	return false


static func new_cargo(kind: String) -> Dictionary:
	return {"kind": kind, "pos": Vector2(SPAWN_X, LANE_Y), "held": false, "loops": 0}
