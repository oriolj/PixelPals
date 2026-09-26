extends Node3D
## The fire truck, built from boxes and cylinders: a vintage open-cab engine
## (so the crew is visible), red with a white stripe, a telescoping ladder on
## top, a blue/red light bar, a water monitor at the back and a dalmatian.
## Local forward is -Z. The level sets position/rotation from the model and
## calls update() every frame.

const Low := preload("res://scripts/level/low.gd")

const LADDER_SEG := 3.4
const LADDER_SLIDE := 3.1
const PIVOT := Vector3(0, 2.02, 1.75)
const NOZZLE_BASE := Vector3(0.72, 1.95, 1.85)

var body: Node3D
var wheels: Array[Node3D] = []
var light_blue: MeshInstance3D
var light_red: MeshInstance3D
var omni: OmniLight3D
var ladder_yaw: Node3D
var ladder_pitch: Node3D
var segments: Array[Node3D] = []
var nozzle_yaw: Node3D
var nozzle_tip: Node3D
var crew := {}          # seat -> AnimatedSprite3D
var dog: AnimatedSprite3D
var headlights: Array[MeshInstance3D] = []

## Ladder state set by the level: raise 0..1 (pitch), ext 0..1 (telescope),
## local yaw (radians, relative to the truck).
var ladder_raise := 0.0
var ladder_ext := 0.0
var ladder_turn := 0.0
var dog_hop := 0.0
var _spin := 0.0


func _ready() -> void:
	body = Node3D.new()
	add_child(body)
	_build_chassis()
	_build_cab()
	_build_body()
	_build_ladder()
	_build_nozzle()
	_build_lights()
	dog = Low.billboard(body, "dog", Low.WHITE, Vector3(0.62, 2.3, 0.35), 1.0 / 16.0)


func _build_chassis() -> void:
	Low.box(body, Vector3(1.9, 0.3, 4.4), Low.DARK, Vector3(0, 0.62, 0))
	for z in [-1.45, 1.45]:
		for x in [-1.02, 1.02]:
			var w := Node3D.new()
			w.position = Vector3(x, 0.45, z)
			body.add_child(w)
			var tyre := Low.cyl(w, 0.45, 0.45, 0.34, Low.INK, Vector3.ZERO, 10)
			tyre.rotation.z = PI / 2.0
			var hub := Low.cyl(w, 0.2, 0.2, 0.36, Low.GREY, Vector3.ZERO, 6)
			hub.rotation.z = PI / 2.0
			Low.box(w, Vector3(0.38, 0.1, 0.1), Low.WHITE, Vector3(0, 0.2, 0))
			wheels.append(w)
		# Mudguards.
		Low.box(body, Vector3(2.3, 0.12, 1.2), Low.RED.darkened(0.25), Vector3(0, 0.98, z))


func _build_cab() -> void:
	# Hood and engine at the front.
	Low.box(body, Vector3(1.8, 0.8, 1.15), Low.RED, Vector3(0, 1.15, -1.65))
	Low.box(body, Vector3(1.84, 0.1, 0.14), Low.YELLOW, Vector3(0, 1.58, -2.2))
	Low.box(body, Vector3(1.3, 0.62, 0.08), Low.GREY, Vector3(0, 1.1, -2.25))
	for k in 4:
		Low.box(body, Vector3(1.2, 0.05, 0.1), Low.SLATE, Vector3(0, 0.88 + k * 0.14, -2.28))
	for x in [-0.72, 0.72]:
		var hl := Low.box(body, Vector3(0.3, 0.3, 0.12), Low.YELLOW, Vector3(x, 1.25, -2.3), true)
		headlights.append(hl)
	Low.box(body, Vector3(2.2, 0.22, 0.24), Low.GREY, Vector3(0, 0.72, -2.38))
	# Open cab: floor, low sides, a seat, the windshield frame.
	Low.box(body, Vector3(1.9, 0.12, 1.0), Low.DARK, Vector3(0, 0.83, -0.65))
	for x in [-0.95, 0.95]:
		Low.box(body, Vector3(0.12, 0.62, 1.0), Low.RED, Vector3(x, 1.12, -0.65))
		Low.box(body, Vector3(0.14, 0.1, 1.02), Low.YELLOW, Vector3(x, 1.46, -0.65))
	Low.box(body, Vector3(1.7, 0.5, 0.35), Low.PURPLE, Vector3(0, 1.1, -0.3))
	for x in [-0.88, 0.88]:
		Low.box(body, Vector3(0.08, 0.95, 0.08), Low.GREY, Vector3(x, 1.95, -1.18))
	Low.box(body, Vector3(1.84, 0.08, 0.08), Low.GREY, Vector3(0, 2.42, -1.18))
	var glass := Low.box(body, Vector3(1.7, 0.7, 0.04), Low.CYAN, Vector3(0, 1.95, -1.18))
	glass.transparency = 0.35
	var wheel := Low.cyl(body, 0.2, 0.2, 0.05, Low.INK, Vector3(-0.45, 1.5, -0.98), 8)
	wheel.rotation.x = 1.0


func _build_body() -> void:
	Low.box(body, Vector3(2.2, 1.1, 2.6), Low.RED, Vector3(0, 1.32, 0.95))
	Low.box(body, Vector3(2.24, 0.16, 2.64), Low.WHITE, Vector3(0, 1.38, 0.95))
	for x in [-1.08, 1.08]:
		Low.box(body, Vector3(0.1, 0.08, 2.64), Low.YELLOW, Vector3(x, 1.88, 0.95))
	for x in [-1.12, 1.12]:
		for z in [0.4, 1.5]:
			Low.box(body, Vector3(0.04, 0.4, 0.8), Low.RED.lightened(0.12), Vector3(x, 1.1, z))
			Low.box(body, Vector3(0.05, 0.08, 0.2), Low.GREY, Vector3(x, 1.05, z - 0.2))
	# Hose reel at the back, the rear step and tail lights.
	var reel := Low.cyl(body, 0.36, 0.36, 1.2, Low.YELLOW, Vector3(0, 1.2, 2.32), 10)
	reel.rotation.z = PI / 2.0
	var reel_hub := Low.cyl(body, 0.15, 0.15, 1.3, Low.GREY, Vector3(0, 1.2, 2.32), 6)
	reel_hub.rotation.z = PI / 2.0
	Low.box(body, Vector3(1.9, 0.12, 0.45), Low.GREY, Vector3(0, 0.65, 2.45))
	for x in [-0.95, 0.95]:
		Low.box(body, Vector3(0.22, 0.22, 0.1), Low.RED.lightened(0.3), Vector3(x, 1.05, 2.27), true)
	# Ladder turntable.
	Low.cyl(body, 0.45, 0.5, 0.2, Low.GREY, PIVOT - Vector3(0, 0.12, 0), 8)


func _build_ladder() -> void:
	ladder_yaw = Node3D.new()
	ladder_yaw.position = PIVOT
	body.add_child(ladder_yaw)
	ladder_pitch = Node3D.new()
	ladder_yaw.add_child(ladder_pitch)
	for k in 3:
		var seg := Node3D.new()
		seg.position = Vector3(0, 0.07 * k, 0)
		ladder_pitch.add_child(seg)
		var half := 0.38 - 0.05 * k
		var rail := Low.GREY if k % 2 == 0 else Low.SLATE
		for x in [-half, half]:
			Low.box(seg, Vector3(0.09, 0.09, LADDER_SEG), rail, Vector3(x, 0, -LADDER_SEG / 2.0))
		var rungs := int(LADDER_SEG / 0.45)
		for r in rungs:
			Low.box(seg, Vector3(half * 2.0, 0.05, 0.05), Low.GREY, Vector3(0, 0, -0.2 - r * 0.45))
		segments.append(seg)


func _build_nozzle() -> void:
	nozzle_yaw = Node3D.new()
	nozzle_yaw.position = NOZZLE_BASE
	body.add_child(nozzle_yaw)
	Low.cyl(nozzle_yaw, 0.16, 0.2, 0.3, Low.GREY, Vector3(0, 0.1, 0), 6)
	var pitch := Node3D.new()
	pitch.position = Vector3(0, 0.22, 0)
	pitch.rotation.x = 0.35
	nozzle_yaw.add_child(pitch)
	var barrel := Low.cyl(pitch, 0.07, 0.11, 0.8, Low.YELLOW, Vector3(0, 0, -0.4), 6)
	barrel.rotation.x = PI / 2.0
	var tip := Low.cyl(pitch, 0.09, 0.07, 0.14, Low.SLATE, Vector3(0, 0, -0.84), 6)
	tip.rotation.x = PI / 2.0
	nozzle_tip = Node3D.new()
	nozzle_tip.position = Vector3(0, 0, -0.95)
	pitch.add_child(nozzle_tip)


func _build_lights() -> void:
	Low.box(body, Vector3(1.4, 0.1, 0.26), Low.WHITE, Vector3(0, 2.5, -1.18))
	light_blue = Low.box(body, Vector3(0.55, 0.26, 0.3), Low.BLUE, Vector3(-0.42, 2.66, -1.18))
	light_red = Low.box(body, Vector3(0.55, 0.26, 0.3), Low.RED, Vector3(0.42, 2.66, -1.18))
	omni = OmniLight3D.new()
	omni.position = Vector3(0, 3.0, -1.2)
	omni.omni_range = 9.0
	omni.light_energy = 0.0
	body.add_child(omni)


## Crew billboards for the seated riders (helmets on).
func set_crew(riders: Array[String], seated: Array[bool]) -> void:
	for s in crew:
		crew[s].queue_free()
	crew.clear()
	var spots := [Vector3(-0.45, 1.5, -0.72), Vector3(-0.55, 2.42, 1.95), Vector3(0.42, 1.42, -0.72)]
	for s in 3:
		if not seated[s] or riders[s] == "":
			continue
		var name_ := Game.helmet_sprite(riders[s])
		var spr := Low.billboard(body, name_, Game.rider_color(riders[s]), spots[s], 1.0 / 16.0)
		crew[s] = spr


## Per frame visuals. `lights` = siren lights flashing.
func update(dt: float, speed: float, wobble: float, lift: float, lights: bool, t: float) -> void:
	_spin += speed * dt / 0.45
	for w in wheels:
		w.rotation.x = -_spin
	body.rotation.z = sin(t * 28.0) * 0.07 * clampf(wobble / 0.45, 0.0, 1.0)
	body.rotation.x = sin(t * 21.0) * 0.03 * clampf(wobble / 0.45, 0.0, 1.0)
	body.position.y = sin(clampf(lift / 0.7, 0.0, 1.0) * PI) * 1.3 + absf(sin(t * 9.0)) * 0.03 * clampf(absf(speed) / 6.0, 0.0, 1.0)
	var phase := int(t * 7.0) % 2 == 0
	if lights:
		light_blue.material_override = Low.mat(Low.CYAN if phase else Low.BLUE.darkened(0.3), phase)
		light_red.material_override = Low.mat(Color("#ff8a8a") if not phase else Low.RED.darkened(0.3), not phase)
		omni.light_color = Low.SKY if phase else Low.RED
		omni.light_energy = 2.5
	else:
		light_blue.material_override = Low.mat(Low.BLUE)
		light_red.material_override = Low.mat(Low.RED)
		omni.light_energy = 0.0
	# Ladder: telescoping segments and the pitch/yaw.
	ladder_yaw.rotation.y = ladder_turn
	ladder_pitch.rotation.x = ladder_raise * 0.9
	for k in segments.size():
		segments[k].position.z = -ladder_ext * LADDER_SLIDE * k
	# The dog hops when it barks.
	dog_hop = maxf(0.0, dog_hop - dt)
	dog.position.y = 2.3 + sin(clampf(dog_hop / 0.3, 0.0, 1.0) * PI) * 0.4


## Point the monitor at a world position (only its yaw turns).
func aim_nozzle(world_target: Vector3) -> void:
	var local := to_local(world_target) - NOZZLE_BASE
	if Vector2(local.x, local.z).length() > 0.1:
		nozzle_yaw.rotation.y = atan2(-local.x, -local.z) - body.rotation.y


func nozzle_tip_global() -> Vector3:
	return nozzle_tip.global_position


## Global position of the ladder's tip for the current raise/ext/turn.
func ladder_tip_global() -> Vector3:
	return ladder_pitch.to_global(Vector3(0, 0.14, -(LADDER_SEG + ladder_ext * LADDER_SLIDE * 2.0)))


func ladder_base_global() -> Vector3:
	return ladder_pitch.global_position


## Ladder settings that put the tip on `world_target`: {turn, raise, ext}.
func ladder_solve(world_target: Vector3) -> Dictionary:
	var local := to_local(world_target) - PIVOT
	var horiz := Vector2(local.x, local.z).length()
	var turn := atan2(-local.x, -local.z)
	var pitch := atan2(local.y, horiz)
	var reach := Vector2(horiz, local.y).length()
	var ext := clampf((reach - LADDER_SEG) / (LADDER_SLIDE * 2.0), 0.0, 1.0)
	return {"turn": turn, "raise": clampf(pitch / 0.9, 0.0, 1.0), "ext": ext}
