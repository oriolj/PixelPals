extends RigidBody2D
## One silly block: a RigidBody2D with a polygon collider, drawn as a flat
## outlined shape with a face. Built in code: Block.new().setup("square").
##
## The face is counter-rotated by whole quarter turns, so it always reads
## upright within 45 degrees, and its pupils follow `look_at_point`.

const Vec := preload("res://scripts/play/vec.gd")
const Rules := preload("res://scripts/play/rules.gd")

enum State { HANGING, FALLING, SETTLING, SETTLED, PIT, CLEARING }
enum Mood { HAPPY, GIGGLE, WHEE, SLEEP, OOPS }

## kind -> size, colour, face anchor (relative to the shape's box) and face scale.
const KINDS := {
	"square": {"color": Color("#b13e53"), "face": Vector2(0, 1), "scale": 1.0},
	"plank": {"color": Color("#ef7d57"), "face": Vector2(28, 0), "scale": 0.85},
	"tall": {"color": Color("#38b764"), "face": Vector2(0, -12), "scale": 0.85},
	"roof": {"color": Color("#3b5dc9"), "face": Vector2(0, 2), "scale": 0.85},
	"arch": {"color": Color("#ffcd75"), "face": Vector2(0, -5), "scale": 0.9},
	"ball": {"color": Color("#a7f070"), "face": Vector2(0, 0), "scale": 0.95},
}

var kind := "square"
var state := State.HANGING
var poly := PackedVector2Array()
var color := Color.WHITE
## Seconds slower than Rules.REST_SPEED (reset when it moves).
var rest_t := 0.0
## Seconds since it first landed (settling window).
var settle_t := 0.0
## Seconds spent in the ball pit.
var pit_t := 0.0
## Spawn order (the body budget removes the oldest pit blocks first).
var serial := 0
## True once it has rested on the tower (falling off it later counts as a collapse).
var was_on_tower := false
var buried := false
var mood := Mood.HAPPY
var mood_t := 0.0
var look_at_point := Vector2(320, -200)

var visual: Node2D
var face: Face
var _collider: Node2D
var _mat_settle := PhysicsMaterial.new()
var _mat_normal := PhysicsMaterial.new()


static func make(block_kind: String) -> RigidBody2D:
	var b = load("res://scripts/play/block.gd").new()
	b.setup(block_kind)
	return b


func setup(block_kind: String) -> void:
	kind = block_kind if KINDS.has(block_kind) else "square"
	var info: Dictionary = KINDS[kind]
	color = info.color
	poly = shape_points(kind)
	_mat_settle.friction = Rules.SETTLE_FRICTION
	_mat_settle.bounce = Rules.SETTLE_BOUNCE
	_mat_normal.friction = 0.8
	_mat_normal.bounce = 0.15
	physics_material_override = _mat_normal
	mass = maxf(0.3, Vec.area(poly) / 1024.0)
	center_of_mass_mode = RigidBody2D.CENTER_OF_MASS_MODE_CUSTOM
	center_of_mass = Vector2.ZERO
	gravity_scale = 0.8
	contact_monitor = true
	max_contacts_reported = 6
	can_sleep = true
	continuous_cd = RigidBody2D.CCD_MODE_CAST_RAY
	if _collider:
		_collider.queue_free()
	if kind == "ball":
		var cs := CollisionShape2D.new()
		var circle := CircleShape2D.new()
		circle.radius = 16.0
		cs.shape = circle
		_collider = cs
	else:
		var cp := CollisionPolygon2D.new()
		cp.build_mode = CollisionPolygon2D.BUILD_SOLIDS
		cp.polygon = poly
		_collider = cp
	add_child(_collider)
	if visual == null:
		visual = BlockVisual.new()
		visual.block = self
		add_child(visual)
		face = Face.new()
		face.block = self
		visual.add_child(face)
	face.position = info.face
	face.scale = Vector2.ONE * float(info.scale)
	visual.queue_redraw()


## Points of each shape, centred on its centroid (so the centre of mass is the origin).
static func shape_points(block_kind: String) -> PackedVector2Array:
	var p: PackedVector2Array
	match block_kind:
		"square": p = Vec.rounded_rect(32, 32, 7)
		"plank": p = Vec.rounded_rect(96, 24, 7)
		"tall": p = Vec.rounded_rect(24, 64, 7)
		"roof": p = Vec.rounded(PackedVector2Array([Vector2(-32, 16), Vector2(0, -16), Vector2(32, 16)]), 5.0, 4)
		"arch": p = Vec.arch(64, 40, 16)
		"ball": p = Vec.ngon(16, 24)
		_: p = Vec.rounded_rect(32, 32, 7)
	return Vec.translated(p, -Vec.centroid(p))


## Draws a block kind scaled to fit `size` px, centred on `at` (tray, party, menus).
static func draw_mini(ci: CanvasItem, block_kind: String, at: Vector2, size: float, rot := 0.0) -> void:
	var p := shape_points(block_kind)
	var r := Rect2(p[0].rotated(rot), Vector2.ZERO)
	for q in p:
		r = r.expand(q.rotated(rot))
	var s := size / maxf(r.size.x, r.size.y)
	var off := at - r.get_center() * s
	var pts := PackedVector2Array()
	for q in p:
		pts.append(off + q.rotated(rot) * s)
	var col: Color = KINDS[block_kind].color
	ci.draw_colored_polygon(pts, col)
	ci.draw_polyline(Vec.closed(pts), Vec.INK, 2.5, true)
	var f: Vector2 = KINDS[block_kind].face
	var er := maxf(1.3, 5.0 * s)
	for dx in [-6.0, 6.0]:
		var e := off + (f + Vector2(dx, -2)).rotated(rot) * s
		ci.draw_circle(e, er, Vec.INK, true, -1.0, true)
		ci.draw_circle(e, er * 0.55, Vec.WHITE, true, -1.0, true)


## Axis-aligned bounds of the shape in world space.
func world_rect() -> Rect2:
	var xf := global_transform
	var r := Rect2(xf * poly[0], Vector2.ZERO)
	for p in poly:
		r = r.expand(xf * p)
	return r


func top_y() -> float:
	return world_rect().position.y


func bottom_y() -> float:
	var r := world_rect()
	return r.position.y + r.size.y


## Contact response while settling: grippy, not bouncy, damped spin.
func begin_settling() -> void:
	state = State.SETTLING
	settle_t = 0.0
	physics_material_override = _mat_settle
	angular_damp_mode = RigidBody2D.DAMP_MODE_REPLACE
	angular_damp = Rules.SETTLE_ANGULAR_DAMP
	linear_damp = 1.5


func end_settling() -> void:
	if state == State.SETTLING:
		state = State.SETTLED
	physics_material_override = _mat_normal
	angular_damp_mode = RigidBody2D.DAMP_MODE_COMBINE
	angular_damp = 0.5
	linear_damp = 0.0


## Hanging on the hook: no collisions, moved by the play screen.
func hang() -> void:
	state = State.HANGING
	freeze_mode = RigidBody2D.FREEZE_MODE_KINEMATIC
	freeze = true
	collision_layer = 0
	collision_mask = 0


func release(vy := 60.0) -> void:
	state = State.FALLING
	collision_layer = 1
	collision_mask = 1
	freeze = false
	linear_velocity = Vector2(0, vy)
	angular_velocity = 0.0


func bury(on: bool) -> void:
	if buried == on:
		return
	buried = on
	if on:
		freeze_mode = RigidBody2D.FREEZE_MODE_STATIC
		freeze = true
	else:
		freeze = false


func set_mood(m: int, seconds := 1.0) -> void:
	mood = m
	mood_t = seconds


## Cosmetic only: the face giggles and the drawing wiggles. Never touches physics.
func giggle() -> void:
	set_mood(Mood.GIGGLE, 0.7)


func _process(delta: float) -> void:
	if mood_t > 0.0:
		mood_t -= delta
		if mood_t <= 0.0:
			mood = Mood.HAPPY
	# Face upright within 45 degrees: undo whole quarter turns of the body.
	face.rotation = -snappedf(rotation, PI / 2)
	var wiggle := 0.0
	if mood == Mood.GIGGLE:
		wiggle = sin(mood_t * 40.0) * 0.08 * mood_t
	visual.rotation = wiggle
	face.queue_redraw()


class BlockVisual extends Node2D:
	var block

	func _draw() -> void:
		Vec.draw_bevel(self, block.poly, block.color)
		if block.kind == "plank":
			# Wood grain lines.
			var c := Color(block.color.darkened(0.3), 0.6)
			draw_line(Vector2(-38, -4), Vector2(8, -4), c, 2.0, true)
			draw_line(Vector2(-30, 4), Vector2(-4, 4), c, 2.0, true)
		elif block.kind == "ball":
			draw_arc(Vector2.ZERO, 10, -2.6, -1.4, 8, Color(1, 1, 1, 0.55), 3.0, true)
		elif block.kind == "square":
			draw_circle(Vector2(-9, -9), 3, Color(1, 1, 1, 0.45), true, -1.0, true)


class Face extends Node2D:
	var block

	func _draw() -> void:
		var mood: int = block.mood
		var ink := Vec.INK
		var white := Vec.WHITE
		var bounce := 0.0
		if mood == Mood.GIGGLE:
			bounce = -absf(sin(block.mood_t * 18.0)) * 3.0
		var eye_l := Vector2(-7, -3 + bounce)
		var eye_r := Vector2(7, -3 + bounce)
		# Pupils look at the point of interest (in face space).
		var look := Vector2.ZERO
		var to: Vector2 = get_global_transform().affine_inverse() * block.look_at_point
		if to.length() > 1.0:
			look = to.normalized() * 1.8
		match mood:
			Mood.SLEEP:
				for e in [eye_l, eye_r]:
					draw_arc(e + Vector2(0, 1), 3.5, 0.2, PI - 0.2, 6, ink, 2.0, true)
				draw_circle(Vector2(0, 6), 2.0, ink, true, -1.0, true)
				return
			Mood.GIGGLE:
				for e in [eye_l, eye_r]:
					draw_polyline(PackedVector2Array([e + Vector2(-4, 2), e + Vector2(0, -2), e + Vector2(4, 2)]),
						ink, 2.5, true)
				_mouth_open(Vector2(0, 6 + bounce), 5.0, 4.0, ink)
				return
			Mood.WHEE:
				for e in [eye_l, eye_r]:
					draw_circle(e, 6.0, ink, true, -1.0, true)
					draw_circle(e, 4.6, white, true, -1.0, true)
					draw_circle(e + look * 0.6, 2.4, ink, true, -1.0, true)
				_mouth_open(Vector2(0, 8), 4.0, 5.0, ink)
				return
			Mood.OOPS:
				for e in [eye_l, eye_r]:
					draw_circle(e, 5.5, ink, true, -1.0, true)
					draw_circle(e, 4.2, white, true, -1.0, true)
					draw_circle(e + look, 2.0, ink, true, -1.0, true)
				draw_arc(Vector2(0, 10), 4.0, PI + 0.4, TAU - 0.4, 8, ink, 2.5, true)
				return
		# Happy.
		for e in [eye_l, eye_r]:
			draw_circle(e, 5.2, ink, true, -1.0, true)
			draw_circle(e, 3.9, white, true, -1.0, true)
			draw_circle(e + look, 2.2, ink, true, -1.0, true)
			draw_circle(e + look + Vector2(-0.8, -0.9), 0.8, white, true, -1.0, true)
		draw_arc(Vector2(0, 3), 5.0, 0.35, PI - 0.35, 8, ink, 2.5, true)
		# Rosy cheeks.
		draw_circle(Vector2(-11, 4), 2.2, Color(1, 0.55, 0.6, 0.55), true, -1.0, true)
		draw_circle(Vector2(11, 4), 2.2, Color(1, 0.55, 0.6, 0.55), true, -1.0, true)

	func _mouth_open(at: Vector2, rx: float, ry: float, ink: Color) -> void:
		var pts := PackedVector2Array()
		for i in 12:
			var a := TAU * i / 12.0
			pts.append(at + Vector2(cos(a) * rx, sin(a) * ry))
		draw_colored_polygon(pts, ink)
		draw_circle(at + Vector2(0, ry * 0.4), rx * 0.5, Color("#b13e53"), true, -1.0, true)
