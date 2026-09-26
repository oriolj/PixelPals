extends RefCounted
## The six animals, drawn face-on as flat vector rigs (face-on reads better
## than side-on: the PixelPals monkey read as a duck until redrawn).
##
## build(kind) returns a Node2D whose origin is between the feet. Its parts are
## named pivots (pivot, head, arm_l, arm_r, ear_l, ear_r, eye_l, eye_r,
## mouth_closed, mouth_open, tongue, cheeks, trunk, trunk_up, neck...), so
## pose(rig, name, t) animates by moving parts:
##   idle, hungry, munch (2 frames), dance (3 poses), shake, sing, sniff.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")

const KINDS: Array[String] = ["monkey", "penguin", "giraffe", "rabbit", "elephant", "seal"]
const POSES: Array[String] = ["idle", "hungry", "munch", "dance", "shake", "sing", "sniff"]
## Every pose frame, for the gallery: [pose, frame].
const GALLERY_POSES := [["idle", 0], ["hungry", 0], ["munch", 0], ["munch", 1],
	["dance", 0], ["dance", 1], ["dance", 2], ["shake", 0], ["sing", 0]]

## Approximate drawn height (feet to top) at scale 1, and where the mouth is
## (for thrown food and hearts), relative to the origin.
const HEIGHT := {"monkey": 132, "penguin": 142, "giraffe": 200, "rabbit": 168, "elephant": 158, "seal": 130}
const MOUTH := {"monkey": Vector2(0, -68), "penguin": Vector2(0, -100), "giraffe": Vector2(0, -170),
	"rabbit": Vector2(0, -70), "elephant": Vector2(4, -80), "seal": Vector2(0, -86)}
## Where the thought bubble sits (above the head).
const BUBBLE := {"monkey": Vector2(64, -150), "penguin": Vector2(64, -160), "giraffe": Vector2(70, -215),
	"rabbit": Vector2(64, -180), "elephant": Vector2(80, -170), "seal": Vector2(64, -150)}


static func build(kind: String) -> Node2D:
	var rig := Node2D.new()
	rig.name = kind
	var rx := 50.0 if kind != "elephant" else 66.0
	VA.shadow(rig, rx, 12.0)
	var pivot := VA.part(rig, "pivot")
	match kind:
		"monkey": _monkey(pivot)
		"penguin": _penguin(pivot)
		"giraffe": _giraffe(pivot)
		"rabbit": _rabbit(pivot)
		"elephant": _elephant(pivot)
		"seal": _seal(pivot)
		_: VA.shape(pivot, VA.circle(40, Vector2(0, -40)), Color.MAGENTA)
	_collect(rig)
	pose(rig, "idle", 0.0)
	return rig


## Records every named pivot and its rest transform (meta "parts", "rest").
static func _collect(rig: Node2D) -> void:
	var parts := {}
	var rest := {}
	var eyes: Array[Node2D] = []
	var stack: Array[Node] = [rig]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		if n is Node2D and not (n is Polygon2D or n is Line2D) and n != rig:
			var nm := String(n.name)
			if nm.begins_with("eye"):
				eyes.append(n)
			if nm == "pupil":
				continue
			parts[nm] = n
			rest[nm] = [n.position, n.rotation, n.scale]
		elif (n is Polygon2D or n is Line2D) and String(n.name) in ["mouth_open", "tongue", "cheeks", "mouth_closed", "trunk_up"]:
			parts[String(n.name)] = n
			rest[String(n.name)] = [n.position, n.rotation, n.scale]
	rig.set_meta("parts", parts)
	rig.set_meta("rest", rest)
	rig.set_meta("eyes", eyes)
	rig.set_meta("kind", String(rig.name))


# ================================================================ poses

## Sets the rig to a pose. `t` is seconds into the pose (or the beat clock for
## dances); `frame` forces a frame (munch 0/1, dance 0/1/2) when >= 0.
## `look` in -1..1 turns the eyes and head toward something left or right.
static func pose(rig: Node2D, pose_name: String, t: float, frame := -1, look := 0.0) -> void:
	var parts: Dictionary = rig.get_meta("parts")
	var rest: Dictionary = rig.get_meta("rest")
	for k in rest:
		var node: Node2D = parts[k]
		node.position = rest[k][0]
		node.rotation = rest[k][1]
		node.scale = rest[k][2]
	_vis(parts, "mouth_closed", true)
	_vis(parts, "mouth_open", false)
	_vis(parts, "tongue", false)
	_vis(parts, "cheeks", false)
	_vis(parts, "trunk", true)
	_vis(parts, "trunk_up", false)
	var pivot: Node2D = parts["pivot"]
	var head: Node2D = parts.get("head")
	var kind: String = rig.get_meta("kind")
	var shadow: Node2D = rig.get_node_or_null("shadow")
	if shadow:
		shadow.scale = Vector2.ONE

	var arm_up := 0.0      # radians, positive raises both arms
	var eye_look := look
	match pose_name:
		"idle":
			var b := sin(t * 2.4)
			pivot.scale = Vector2(1.0 - 0.012 * b, 1.0 + 0.022 * b)
			if head:
				head.position.y += b * 1.5
				head.rotation += look * 0.08
			_ears(parts, sin(t * 1.7) * 0.06)
			arm_up = 0.1 + 0.05 * b
		"hungry":
			var ph := fmod(t * 2.2, 1.0)
			var hop := sin(ph * PI) * 18.0
			pivot.position.y -= hop
			if ph < 0.12 or ph > 0.88:
				pivot.scale = Vector2(1.08, 0.92)
			if shadow:
				shadow.scale = Vector2.ONE * (1.0 - hop / 60.0)
			_vis(parts, "mouth_open", true)
			_vis(parts, "mouth_closed", false)
			if head:
				head.rotation += look * 0.12
			arm_up = 1.4 + 0.5 * sin(t * 9.0)
			_ears(parts, sin(t * 9.0) * 0.18)
		"munch":
			var f := frame if frame >= 0 else int(t * 7.0) % 2
			if f == 0:
				_vis(parts, "mouth_open", true)
				_vis(parts, "mouth_closed", false)
				if head:
					head.position.y += 3
			else:
				_vis(parts, "cheeks", true)
				if head:
					head.scale = Vector2(1.06, 0.97)
			arm_up = 0.9
			_ears(parts, 0.1 if f == 0 else -0.1)
		"dance":
			var f := frame if frame >= 0 else int(t) % 3
			var local := fmod(t, 1.0) if frame < 0 else 0.5
			var bounce := sin(local * PI) * 10.0
			match f:
				0:
					pivot.rotation = -0.18
					_arm(parts, "arm_l", 2.2)
					_arm(parts, "arm_r", -0.3)
					if head:
						head.rotation -= 0.12
				1:
					pivot.position.y -= 14.0 + bounce * 0.4
					arm_up = 2.0
					_vis(parts, "mouth_open", true)
					_vis(parts, "mouth_closed", false)
				2:
					pivot.rotation = 0.18
					_arm(parts, "arm_l", 0.3)
					_arm(parts, "arm_r", -2.2)
					if head:
						head.rotation += 0.12
			pivot.position.y -= bounce * 0.5
			_ears(parts, [-0.25, 0.3, 0.25][f])
			if parts.has("tail"):
				parts["tail"].rotation += [0.3, 0.0, -0.3][f]
		"shake":
			var s := sin(t * TAU * 3.2)
			if head:
				head.rotation += s * 0.32
				head.position.x += s * 4.0
			pivot.rotation = -s * 0.05
			_vis(parts, "tongue", true)
			_ears(parts, s * 0.3)
			arm_up = 0.25
			eye_look = -s
		"sing":
			var b := sin(t * 7.0)
			pivot.position.y -= absf(b) * 6.0
			pivot.scale = Vector2(0.97, 1.05)
			if head:
				head.rotation += -0.1 + b * 0.06
			_vis(parts, "mouth_open", true)
			_vis(parts, "mouth_closed", false)
			if parts.has("mouth_open"):
				parts["mouth_open"].scale *= 1.3
			_vis(parts, "trunk", false)
			_vis(parts, "trunk_up", true)
			arm_up = 1.6
			_ears(parts, 0.3 * b)
		"sniff":
			if head:
				head.position.y += 6.0 + sin(t * 14.0) * 1.5
				head.scale = Vector2(1.03, 1.0)
			arm_up = 0.2
			if parts.has("trunk"):
				parts["trunk"].rotation += sin(t * 10.0) * 0.12
	if arm_up != 0.0:
		_arm(parts, "arm_l", arm_up, true)
		_arm(parts, "arm_r", -arm_up, true)
	if kind == "elephant" and parts.has("trunk") and pose_name in ["idle", "hungry"]:
		parts["trunk"].rotation += sin(t * 2.0) * (0.1 if pose_name == "idle" else 0.25)
	if parts.has("tail") and pose_name != "dance":
		parts["tail"].rotation += sin(t * 3.0) * 0.12
	for e in rig.get_meta("eyes"):
		var p: Node2D = e.get_node_or_null("pupil")
		if p:
			p.position = Vector2(clampf(eye_look, -1.0, 1.0) * 2.5, 0)


static func _vis(parts: Dictionary, part_name: String, on: bool) -> void:
	if parts.has(part_name):
		parts[part_name].visible = on


static func _arm(parts: Dictionary, part_name: String, amount: float, _additive := false) -> void:
	if parts.has(part_name):
		parts[part_name].rotation += amount


static func _ears(parts: Dictionary, amount: float) -> void:
	if parts.has("ear_l"):
		parts["ear_l"].rotation -= amount
	if parts.has("ear_r"):
		parts["ear_r"].rotation += amount


# ================================================================ shared face bits

## Eyes, a smile, an open mouth (with tongue) and munching cheeks.
static func _face(head: Node2D, eye_y: float, eye_dx: float, eye_r: float, mouth: Vector2,
		mouth_w: float, cheek_dx: float, cheek_y: float) -> void:
	VA.eye(head, Vector2(-eye_dx, eye_y), eye_r, "eye_l")
	VA.eye(head, Vector2(eye_dx, eye_y), eye_r, "eye_r")
	var smile := VA.stroke(head, VA.arc(mouth_w, mouth_w * 0.55, 0.25, PI - 0.25, mouth), Pal.OUTLINE, 3.5, "mouth_closed")
	smile.z_index = 1
	var open := VA.shape(head, VA.ellipse(mouth_w * 0.75, mouth_w * 0.7, mouth + Vector2(0, mouth_w * 0.35)),
		Pal.NOSE, Pal.OUTLINE, 3.0, "mouth_open")
	VA.fill(open, VA.ellipse(mouth_w * 0.45, mouth_w * 0.3, mouth + Vector2(0, mouth_w * 0.65)), Pal.TONGUE)
	open.z_index = 1
	var tongue := VA.shape(head, VA.rrect(Rect2(mouth + Vector2(-mouth_w * 0.4, 0), Vector2(mouth_w * 0.8, mouth_w * 1.1)), mouth_w * 0.4),
		Pal.TONGUE, Pal.OUTLINE, 3.0, "tongue")
	tongue.z_index = 1
	var cheeks := Node2D.new()
	cheeks.name = "cheeks_holder"
	head.add_child(cheeks)
	var c := VA.fill(cheeks, VA.ellipse(9, 6, Vector2(-cheek_dx, cheek_y)), Pal.CHEEK, "cheeks")
	VA.fill(c, VA.ellipse(9, 6, Vector2(cheek_dx, cheek_y)), Pal.CHEEK)
	cheeks.z_index = 1


# ================================================================ the six animals

static func _monkey(p: Node2D) -> void:
	# Curly tail behind everything.
	var tail := VA.part(p, "tail", Vector2(22, -30))
	VA.limb(tail, VA.curve([Vector2(0, 0), Vector2(34, -4), Vector2(50, -34), Vector2(38, -58),
		Vector2(20, -52), Vector2(24, -38)]), Pal.MONKEY, 9.0)
	# Feet and body.
	VA.shape(p, VA.ellipse(17, 9, Vector2(-18, -7)), Pal.MONKEY_FACE)
	VA.shape(p, VA.ellipse(17, 9, Vector2(18, -7)), Pal.MONKEY_FACE)
	VA.shape(p, VA.ellipse(33, 34, Vector2(0, -40)), Pal.MONKEY)
	VA.shape(p, VA.ellipse(21, 23, Vector2(0, -36)), Pal.MONKEY_FACE, Pal.OUTLINE, 4.0)
	for side in [-1, 1]:
		var arm := VA.part(p, "arm_l" if side < 0 else "arm_r", Vector2(26 * side, -58))
		VA.limb(arm, PackedVector2Array([Vector2(0, 0), Vector2(12 * side, 16), Vector2(12 * side, 32)]), Pal.MONKEY, 11.0)
		VA.shape(arm, VA.circle(8, Vector2(12 * side, 36), 16), Pal.MONKEY_FACE, Pal.OUTLINE, 4.0)
	var head := VA.part(p, "head", Vector2(0, -76))
	for side in [-1, 1]:
		var ear := VA.part(head, "ear_l" if side < 0 else "ear_r", Vector2(40 * side, -12))
		VA.shape(ear, VA.circle(17), Pal.MONKEY)
		VA.shape(ear, VA.circle(10), Pal.MONKEY_FACE, Pal.OUTLINE, 3.0)
	VA.shape(head, VA.circle(37, Vector2(0, -12)), Pal.MONKEY)
	# Hair tuft.
	VA.shape(head, VA.blob([Vector2(-8, -44), Vector2(-2, -58), Vector2(6, -50), Vector2(14, -60), Vector2(12, -44)], 5), Pal.MONKEY)
	# Heart-shaped face mask: the monkey's signature.
	VA.shape(head, VA.blob([Vector2(0, -24), Vector2(14, -34), Vector2(27, -22), Vector2(24, -5),
		Vector2(29, 8), Vector2(18, 23), Vector2(0, 27), Vector2(-18, 23), Vector2(-29, 8),
		Vector2(-24, -5), Vector2(-27, -22), Vector2(-14, -34)]), Pal.MONKEY_FACE, Pal.OUTLINE, 4.0)
	VA.fill(head, VA.circle(2.6, Vector2(-4, 3), 10), Pal.NOSE)
	VA.fill(head, VA.circle(2.6, Vector2(4, 3), 10), Pal.NOSE)
	_face(head, -14, 11, 7, Vector2(0, 9), 10, 20, 8)


static func _penguin(p: Node2D) -> void:
	VA.shape(p, VA.ellipse(16, 8, Vector2(-17, -5)), Pal.PENGUIN_BEAK)
	VA.shape(p, VA.ellipse(16, 8, Vector2(17, -5)), Pal.PENGUIN_BEAK)
	for side in [-1, 1]:
		var arm := VA.part(p, "arm_l" if side < 0 else "arm_r", Vector2(34 * side, -78))
		VA.shape(arm, VA.blob([Vector2(0, -4), Vector2(10 * side, 6), Vector2(18 * side, 34),
			Vector2(10 * side, 44), Vector2(-2 * side, 18)], 6), Pal.PENGUIN)
	VA.shape(p, VA.blob([Vector2(0, -122), Vector2(30, -110), Vector2(42, -60), Vector2(36, -16),
		Vector2(0, -4), Vector2(-36, -16), Vector2(-42, -60), Vector2(-30, -110)]), Pal.PENGUIN)
	VA.shape(p, VA.ellipse(28, 40, Vector2(0, -46)), Pal.CREAM, Pal.OUTLINE, 4.0)
	var head := VA.part(p, "head", Vector2(0, -100))
	VA.shape(head, VA.circle(33, Vector2(0, -10)), Pal.PENGUIN)
	# White face patch with two lobes around the eyes.
	VA.shape(head, VA.blob([Vector2(0, -16), Vector2(13, -30), Vector2(26, -16), Vector2(22, 4),
		Vector2(10, 14), Vector2(0, 12), Vector2(-10, 14), Vector2(-22, 4), Vector2(-26, -16),
		Vector2(-13, -30)]), Pal.CREAM, Pal.OUTLINE, 3.5)
	_face(head, -12, 11, 6.5, Vector2(0, 12), 8, 17, 4)
	# Beak over the smile: closed = one triangle, open = two apart.
	var closed := VA.shape(head, VA.blob([Vector2(-11, 0), Vector2(11, 0), Vector2(0, 16)], 3), Pal.PENGUIN_BEAK, Pal.OUTLINE, 3.5)
	closed.z_index = 2
	closed.name = "beak_closed"
	head.get_node("mouth_closed").add_child(_detach(closed))
	var open: Node = head.get_node("mouth_open")
	var up := VA.shape(open, VA.blob([Vector2(-11, -2), Vector2(11, -2), Vector2(0, 8)], 3), Pal.PENGUIN_BEAK, Pal.OUTLINE, 3.5)
	up.z_index = 1
	var low := VA.shape(open, VA.blob([Vector2(-8, 14), Vector2(8, 14), Vector2(0, 22)], 3), Pal.PENGUIN_BEAK, Pal.OUTLINE, 3.5)
	low.z_index = 1


static func _detach(n: Node) -> Node:
	n.get_parent().remove_child(n)
	return n


static func _giraffe(p: Node2D) -> void:
	var tail := VA.part(p, "tail", Vector2(34, -74))
	VA.limb(tail, PackedVector2Array([Vector2(0, 0), Vector2(10, 16), Vector2(12, 30)]), Pal.GIRAFFE, 4.0)
	VA.shape(tail, VA.ellipse(5, 8, Vector2(12, 34), 12), Pal.GIRAFFE_SPOT, Pal.OUTLINE, 3.0)
	# Back legs (darker), body, front legs.
	for x in [-24, 24]:
		VA.shape(p, VA.rrect(Rect2(x - 6, -62, 12, 58), 5), Pal.GIRAFFE.darkened(0.12), Pal.OUTLINE, 4.0)
		VA.shape(p, VA.rrect(Rect2(x - 7, -10, 14, 10), 3), Pal.NOSE, Pal.OUTLINE, 3.0)
	VA.shape(p, VA.ellipse(42, 25, Vector2(0, -70)), Pal.GIRAFFE)
	for sp in [Vector2(-22, -76), Vector2(-4, -64), Vector2(18, -78), Vector2(26, -60), Vector2(-28, -58), Vector2(4, -84)]:
		VA.fill(p, VA.blob([sp + Vector2(-6, -4), sp + Vector2(5, -6), sp + Vector2(7, 3), sp + Vector2(-4, 6)], 4), Pal.GIRAFFE_SPOT)
	for x in [-12, 12]:
		VA.shape(p, VA.rrect(Rect2(x - 6, -56, 12, 56), 5), Pal.GIRAFFE, Pal.OUTLINE, 4.0)
		VA.shape(p, VA.rrect(Rect2(x - 7, -8, 14, 8), 3), Pal.NOSE, Pal.OUTLINE, 3.0)
	# Giraffes have no arms: the neck and ears do the dancing.
	var neck := VA.part(p, "neck", Vector2(0, -84))
	VA.shape(neck, PackedVector2Array([Vector2(-16, 4), Vector2(16, 4), Vector2(10, -86), Vector2(-10, -86)]), Pal.GIRAFFE)
	# Mane down the back of the neck.
	for i in 5:
		VA.fill(neck, VA.blob([Vector2(-7, -14 - i * 16), Vector2(5, -18 - i * 16), Vector2(6, -8 - i * 16), Vector2(-5, -6 - i * 16)], 4), Pal.GIRAFFE_SPOT)
	var head := VA.part(neck, "head", Vector2(0, -92))
	for side in [-1, 1]:
		VA.limb(head, PackedVector2Array([Vector2(8 * side, -20), Vector2(10 * side, -36)]), Pal.GIRAFFE, 5.0)
		VA.shape(head, VA.circle(5.5, Vector2(10 * side, -38), 12), Pal.GIRAFFE_SPOT, Pal.OUTLINE, 3.0)
		var ear := VA.part(head, "ear_l" if side < 0 else "ear_r", Vector2(20 * side, -18))
		VA.shape(ear, VA.ellipse(12, 6), Pal.GIRAFFE, Pal.OUTLINE, 3.5)
		ear.rotation = 0.35 * side
	VA.shape(head, VA.ellipse(20, 25, Vector2(0, -6)), Pal.GIRAFFE)
	VA.fill(head, VA.blob([Vector2(-14, -22), Vector2(-6, -24), Vector2(-6, -16), Vector2(-13, -14)], 4), Pal.GIRAFFE_SPOT)
	VA.fill(head, VA.blob([Vector2(8, -24), Vector2(14, -20), Vector2(12, -14), Vector2(6, -17)], 4), Pal.GIRAFFE_SPOT)
	VA.shape(head, VA.ellipse(16, 12, Vector2(0, 14)), Color("#f7d9a4"), Pal.OUTLINE, 4.0)
	VA.fill(head, VA.circle(2.4, Vector2(-5, 10), 10), Pal.NOSE)
	VA.fill(head, VA.circle(2.4, Vector2(5, 10), 10), Pal.NOSE)
	_face(head, -9, 10, 5.5, Vector2(0, 16), 7, 15, 4)


static func _rabbit(p: Node2D) -> void:
	VA.shape(p, VA.ellipse(19, 9, Vector2(-17, -6)), Pal.RABBIT)
	VA.shape(p, VA.ellipse(19, 9, Vector2(17, -6)), Pal.RABBIT)
	VA.shape(p, VA.ellipse(31, 33, Vector2(0, -38)), Pal.RABBIT)
	VA.shape(p, VA.ellipse(19, 22, Vector2(0, -33)), Pal.CREAM, Pal.OUTLINE, 3.5)
	for side in [-1, 1]:
		var arm := VA.part(p, "arm_l" if side < 0 else "arm_r", Vector2(19 * side, -54))
		VA.shape(arm, VA.ellipse(8, 12, Vector2(3 * side, 10)), Pal.RABBIT, Pal.OUTLINE, 4.0)
	var head := VA.part(p, "head", Vector2(0, -72))
	for side in [-1, 1]:
		var ear := VA.part(head, "ear_l" if side < 0 else "ear_r", Vector2(12 * side, -26))
		VA.shape(ear, VA.ellipse(11, 36, Vector2(0, -32)), Pal.RABBIT)
		VA.fill(ear, VA.ellipse(5.5, 26, Vector2(0, -30)), Pal.RABBIT_PINK)
		ear.rotation = 0.14 * side
	VA.shape(head, VA.ellipse(31, 27, Vector2(0, -6)), Pal.RABBIT)
	_face(head, -10, 12, 6, Vector2(0, 7), 7, 20, 4)
	# Buck teeth ride with the mouths.
	for mname in ["mouth_closed", "mouth_open"]:
		var m: Node = head.get_node(mname)
		var teeth := VA.shape(m, VA.rrect(Rect2(-5, 9, 10, 8), 2), Pal.CREAM, Pal.OUTLINE, 2.5)
		VA.stroke(teeth, PackedVector2Array([Vector2(0, 10), Vector2(0, 16)]), Pal.OUTLINE, 1.5)
		if mname == "mouth_open":
			teeth.position = Vector2(0, -3)
	var nose := VA.shape(head, VA.blob([Vector2(-5, 0), Vector2(5, 0), Vector2(0, 5)], 4), Pal.RABBIT_PINK, Pal.OUTLINE, 2.5)
	nose.position = Vector2(0, 1)
	nose.z_index = 2
	for side in [-1, 1]:
		for k in 3:
			var w := VA.stroke(head, PackedVector2Array([Vector2(12 * side, 4 + k * 3), Vector2(30 * side, -2 + k * 6)]), Pal.OUTLINE, 1.8)
			w.z_index = 2


static func _elephant(p: Node2D) -> void:
	for x in [-26, 26]:
		VA.shape(p, VA.rrect(Rect2(x - 15, -44, 30, 44), 8), Pal.ELEPHANT)
		for k in [-7, 0, 7]:
			VA.fill(p, VA.ellipse(3.5, 3, Vector2(x + k, -6), 10), Pal.CREAM)
	VA.shape(p, VA.ellipse(56, 38, Vector2(0, -60)), Pal.ELEPHANT)
	var head := VA.part(p, "head", Vector2(0, -92))
	for side in [-1, 1]:
		var ear := VA.part(head, "ear_l" if side < 0 else "ear_r", Vector2(28 * side, -14))
		var pts := VA.blob([Vector2(0, -24), Vector2(28, -38), Vector2(52, -16), Vector2(50, 18),
			Vector2(30, 40), Vector2(8, 26)], 8)
		if side < 0:
			pts = VA.mirror_x(pts)
		VA.shape(ear, pts, Pal.ELEPHANT)
		var inner := VA.blob([Vector2(8, -14), Vector2(28, -24), Vector2(42, -8), Vector2(40, 14),
			Vector2(26, 28), Vector2(12, 18)], 8)
		if side < 0:
			inner = VA.mirror_x(inner)
		VA.fill(ear, inner, Color("#efb3c4"))
	VA.shape(head, VA.ellipse(40, 36, Vector2(0, -12)), Pal.ELEPHANT)
	# Tusks peek out beside the trunk.
	for side in [-1, 1]:
		VA.shape(head, VA.blob([Vector2(10 * side, 10), Vector2(18 * side, 12), Vector2(22 * side, 24), Vector2(16 * side, 22)], 4), Pal.CREAM, Pal.OUTLINE, 3.0)
	_face(head, -18, 16, 6, Vector2(19, 10), 6, 25, 2)
	var trunk := VA.part(head, "trunk", Vector2(0, 2))
	VA.limb(trunk, VA.curve([Vector2(0, -6), Vector2(0, 20), Vector2(-3, 40), Vector2(6, 54), Vector2(16, 50)]), Pal.ELEPHANT, 18.0)
	for k in 3:
		VA.stroke(trunk, PackedVector2Array([Vector2(-7, 14 + k * 9), Vector2(7, 14 + k * 9)]), Pal.ELEPHANT_DARK, 3.0)
	var up := VA.part(head, "trunk_up_holder", Vector2(0, 2))
	var tu := VA.limb(up, VA.curve([Vector2(0, -4), Vector2(12, 12), Vector2(32, 6), Vector2(46, -16), Vector2(50, -42)]), Pal.ELEPHANT, 18.0, "trunk_up")
	tu.z_index = 1
	VA.shape(tu, VA.ellipse(14, 7, Vector2(51, -46)), Pal.ELEPHANT, Pal.OUTLINE, 4.0)
	VA.fill(tu, VA.ellipse(7, 3, Vector2(51, -46)), Pal.NOSE)
	# The trunk hides the closed smile's middle; keep the mouth to the side.


static func _seal(p: Node2D) -> void:
	# A sleek body that sweeps into a tail with a fan flipper: a seal, not a penguin.
	var tail := VA.part(p, "tail", Vector2(60, -8))
	VA.shape(tail, VA.blob([Vector2(14, -2), Vector2(36, -24), Vector2(46, -14), Vector2(40, 2), Vector2(46, 14), Vector2(34, 12), Vector2(16, 6)], 5), Pal.SEAL.darkened(0.12))
	VA.shape(p, VA.blob([Vector2(0, -104), Vector2(26, -94), Vector2(36, -58), Vector2(42, -26),
		Vector2(60, -14), Vector2(80, -12), Vector2(80, 0), Vector2(30, 2), Vector2(-26, -2),
		Vector2(-42, -16), Vector2(-38, -56), Vector2(-26, -94)]), Pal.SEAL)
	for sp in [Vector2(-24, -66), Vector2(28, -40), Vector2(56, -6), Vector2(-30, -36)]:
		VA.fill(p, VA.ellipse(4, 3, sp, 10), Pal.SEAL.darkened(0.18))
	VA.shape(p, VA.ellipse(24, 32, Vector2(0, -32)), Pal.SEAL_LIGHT, Pal.OUTLINE, 3.5)
	for side in [-1, 1]:
		var arm := VA.part(p, "arm_l" if side < 0 else "arm_r", Vector2(32 * side, -52))
		VA.shape(arm, VA.blob([Vector2(0, -4), Vector2(12 * side, 4), Vector2(22 * side, 30),
			Vector2(12 * side, 34), Vector2(-2 * side, 12)], 6), Pal.SEAL.darkened(0.08))
	var head := VA.part(p, "head", Vector2(0, -90))
	VA.shape(head, VA.ellipse(33, 29, Vector2(0, -6)), Pal.SEAL)
	_face(head, -14, 13, 7.5, Vector2(0, 16), 7, 24, 4)
	# Whisker pads with dots, a dark nose and whiskers: the seal's signature.
	for side in [-1, 1]:
		var pad := VA.shape(head, VA.ellipse(11, 8.5, Vector2(8 * side, 8)), Pal.SEAL_LIGHT, Pal.OUTLINE, 3.0)
		pad.z_index = 2
		for d in [Vector2(5, 6), Vector2(10, 9), Vector2(6, 11)]:
			var dot := VA.fill(head, VA.circle(1.3, Vector2(d.x * side + 2 * side, d.y), 8), Pal.OUTLINE)
			dot.z_index = 3
		for k in 3:
			var w := VA.stroke(head, PackedVector2Array([Vector2(16 * side, 6 + k * 3), Vector2(36 * side, 0 + k * 6)]), Pal.OUTLINE, 1.8)
			w.z_index = 3
	var nose := VA.shape(head, VA.blob([Vector2(-6, 0), Vector2(6, 0), Vector2(0, 6)], 4), Pal.NOSE, Pal.OUTLINE, 2.5)
	nose.z_index = 3


# ================================================================ hats (buddies)

## Where a hat sits on each head (in the head part's coordinates).
const HAT_Y := {"monkey": -44.0, "penguin": -40.0, "giraffe": -30.0, "rabbit": -30.0, "elephant": -44.0, "seal": -32.0}


## Puts a little safari hat in the seat's colour on the rig's head.
static func add_hat(rig: Node2D, color: Color) -> Node2D:
	var head: Node2D = rig.get_meta("parts").get("head")
	var hat := Node2D.new()
	hat.name = "hat"
	hat.position = Vector2(0, HAT_Y.get(String(rig.get_meta("kind")), -40.0))
	hat.scale = Vector2(1.3, 1.3)
	hat.z_index = 4
	head.add_child(hat)
	VA.shape(hat, VA.ellipse(30, 8, Vector2(0, 2)), color, Pal.OUTLINE, 4.0, "brim")
	VA.shape(hat, VA.blob([Vector2(-16, 2), Vector2(-14, -14), Vector2(0, -20), Vector2(14, -14), Vector2(16, 2)], 5), color, Pal.OUTLINE, 4.0, "crown")
	VA.fill(hat, VA.rrect(Rect2(-15, -4, 30, 5), 2), color.darkened(0.35), "band")
	return hat


static func set_hat_color(rig: Node2D, color: Color) -> void:
	var hat := rig.find_child("hat", true, false)
	if hat == null:
		return
	(hat.get_node("brim") as Polygon2D).color = color
	(hat.get_node("crown") as Polygon2D).color = color
	(hat.get_node("band") as Polygon2D).color = color.darkened(0.35)
