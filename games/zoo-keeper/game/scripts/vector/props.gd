extends RefCounted
## Everything that is not an animal: the keeper, the food cart, the four foods,
## the thought bubble, enclosures, particles and the menu icons. Each builder
## returns a Node2D tree built from vector_art primitives.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")

const FOODS: Array[String] = ["banana", "fish", "carrot", "hay"]
const FOOD_COLOR := {"banana": Pal.BANANA, "fish": Pal.FISH, "carrot": Pal.CARROT, "hay": Pal.HAY}


# ================================================================ foods (64 px)

static func food(kind: String) -> Node2D:
	var n := Node2D.new()
	n.name = kind
	match kind:
		"banana": _banana(n)
		"fish": _fish(n)
		"carrot": _carrot(n)
		"hay": _hay(n)
	return n


static func _banana(n: Node2D) -> void:
	# A fat crescent smile with brown tips.
	var outer := VA.arc(34, 30, 0.35, PI - 0.35, Vector2(0, -14), 20)
	var inner := VA.arc(26, 18, PI - 0.5, 0.5, Vector2(0, -12), 20)
	var pts := PackedVector2Array()
	pts.append_array(outer)
	pts.append_array(inner)
	var body := VA.shape(n, pts, Pal.BANANA)
	VA.stroke(body, VA.arc(28, 22, 0.6, PI - 0.6, Vector2(0, -12), 14), Color("#e0b21f"), 3.0)
	VA.shape(n, VA.rrect(Rect2(-34, -6, 8, 8), 2), Color("#6b4a2b"), Pal.OUTLINE, 3.0).rotation = -0.5
	VA.shape(n, VA.rrect(Rect2(27, -12, 7, 10), 2), Color("#6b4a2b"), Pal.OUTLINE, 3.0)
	n.rotation = -0.25


static func _fish(n: Node2D) -> void:
	VA.shape(n, PackedVector2Array([Vector2(14, 0), Vector2(32, -16), Vector2(28, 0), Vector2(32, 16)]), Pal.FISH)
	VA.shape(n, VA.blob([Vector2(-6, -24), Vector2(4, -14), Vector2(-10, -12)], 4), Pal.FISH, Pal.OUTLINE, 3.5)
	VA.shape(n, VA.ellipse(24, 15, Vector2(-4, 0)), Pal.FISH)
	VA.fill(n, VA.ellipse(16, 5, Vector2(-4, 6)), Color("#9cc6ff"))
	VA.stroke(n, VA.arc(10, 12, -1.0, 1.0, Vector2(-20, 0), 8), Pal.OUTLINE, 3.0)
	VA.fill(n, VA.circle(4.5, Vector2(-16, -4), 12), Pal.CREAM)
	VA.fill(n, VA.circle(2.5, Vector2(-16, -4), 10), Pal.OUTLINE)


static func _carrot(n: Node2D) -> void:
	for a in [-0.5, 0.0, 0.5]:
		VA.leaf(n, Vector2(0, -18), 22, -PI / 2 + a)
	var body := VA.shape(n, VA.blob([Vector2(-14, -20), Vector2(14, -20), Vector2(8, 6), Vector2(1, 30), Vector2(-3, 30), Vector2(-9, 6)], 6), Pal.CARROT)
	for k in 3:
		var y := -10 + k * 11
		VA.stroke(body, PackedVector2Array([Vector2(-9 + k * 2, y), Vector2(-2 + k * 2, y + 2)]), Color("#d9642a"), 3.0)
	n.rotation = 0.35


static func _hay(n: Node2D) -> void:
	# A bale with the giraffe's leaves tucked in.
	VA.leaf(n, Vector2(-10, -18), 22, -PI / 2 - 0.5)
	VA.leaf(n, Vector2(6, -18), 20, -PI / 2 + 0.4)
	var bale := VA.shape(n, VA.rrect(Rect2(-30, -20, 60, 40), 10), Pal.HAY)
	for k in 7:
		var x := -22 + k * 7.5
		VA.stroke(bale, PackedVector2Array([Vector2(x, -15), Vector2(x + 3, 15)]), Color("#a8902f"), 2.5)
	VA.shape(n, VA.rrect(Rect2(-31, -5, 62, 10), 3), Color("#8a5733"), Pal.OUTLINE, 3.0)
	for side in [-1, 1]:
		VA.stroke(n, PackedVector2Array([Vector2(28 * side, -12), Vector2(38 * side, -18)]), Color("#a8902f"), 3.0)
		VA.stroke(n, PackedVector2Array([Vector2(28 * side, 10), Vector2(38 * side, 16)]), Color("#a8902f"), 3.0)


# ================================================================ keeper (90 px)

## The keeper, face-on. Parts: pivot, leg_l, leg_r, arm_l, arm_r, head, hat.
static func keeper(hat_color: Color) -> Node2D:
	var rig := Node2D.new()
	rig.name = "keeper"
	VA.shadow(rig, 30, 8)
	var p := VA.part(rig, "pivot")
	for side in [-1, 1]:
		var leg := VA.part(p, "leg_l" if side < 0 else "leg_r", Vector2(9 * side, -30))
		VA.shape(leg, VA.rrect(Rect2(-6, 0, 12, 24), 4), Pal.SKIN, Pal.OUTLINE, 4.0)
		VA.shape(leg, VA.rrect(Rect2(-8, 20, 17, 10), 4), Pal.BOOT, Pal.OUTLINE, 4.0)
	VA.shape(p, VA.rrect(Rect2(-19, -40, 38, 16), 5), Pal.SHORTS, Pal.OUTLINE, 4.0)
	for side in [-1, 1]:
		var arm := VA.part(p, "arm_l" if side < 0 else "arm_r", Vector2(19 * side, -60))
		VA.limb(arm, PackedVector2Array([Vector2(0, 0), Vector2(6 * side, 22)]), Pal.SHIRT, 9.0)
		VA.shape(arm, VA.circle(6, Vector2(6 * side, 26), 14), Pal.SKIN, Pal.OUTLINE, 3.5)
	VA.shape(p, VA.rrect(Rect2(-20, -66, 40, 30), 9), Pal.SHIRT, Pal.OUTLINE, 4.0)
	VA.stroke(p, PackedVector2Array([Vector2(0, -64), Vector2(0, -40)]), Pal.OUTLINE, 2.0)
	VA.fill(p, VA.rrect(Rect2(5, -60, 9, 8), 2), Color("#6b8446"))
	var head := VA.part(p, "head", Vector2(0, -74))
	VA.shape(head, VA.circle(17, Vector2(0, -6)), Pal.SKIN, Pal.OUTLINE, 4.0)
	VA.fill(head, VA.circle(2.8, Vector2(-6, -6), 10), Pal.OUTLINE)
	VA.fill(head, VA.circle(2.8, Vector2(6, -6), 10), Pal.OUTLINE)
	VA.stroke(head, VA.arc(6, 4, 0.3, PI - 0.3, Vector2(0, 1), 8), Pal.OUTLINE, 2.5)
	VA.fill(head, VA.ellipse(4, 2.5, Vector2(-11, 1), 10), Pal.CHEEK)
	VA.fill(head, VA.ellipse(4, 2.5, Vector2(11, 1), 10), Pal.CHEEK)
	var hat := VA.part(head, "hat", Vector2(0, -16))
	VA.shape(hat, VA.ellipse(30, 8, Vector2(0, 2)), hat_color, Pal.OUTLINE, 4.0, "brim")
	VA.shape(hat, VA.blob([Vector2(-16, 2), Vector2(-14, -14), Vector2(0, -20), Vector2(14, -14), Vector2(16, 2)], 5), hat_color, Pal.OUTLINE, 4.0, "crown")
	VA.fill(hat, VA.rrect(Rect2(-15, -4, 30, 5), 2), hat_color.darkened(0.35))
	return rig


static func set_hat(rig: Node2D, c: Color) -> void:
	var hat := VA.find(rig, "hat")
	for nm in ["brim", "crown"]:
		var poly := hat.get_node_or_null(nm) as Polygon2D
		if poly:
			poly.color = c
	for ch in hat.get_children():
		if ch is Polygon2D and String(ch.name) not in ["brim", "crown"]:
			ch.color = c.darkened(0.35)


## Walk cycle: frame 0..3 (legs swing, body bobs); frame -1 = standing.
static func keeper_pose(rig: Node2D, frame: int) -> void:
	var p := rig.get_node("pivot") as Node2D
	var legs := [p.get_node("leg_l"), p.get_node("leg_r")]
	var arms := [p.get_node("arm_l"), p.get_node("arm_r")]
	var swing: float = [0.0, 0.4, 0.0, -0.4][maxi(frame, 0) % 4] if frame >= 0 else 0.0
	legs[0].rotation = swing
	legs[1].rotation = -swing
	arms[0].rotation = -swing * 0.8
	arms[1].rotation = swing * 0.8
	p.position.y = -3.0 if frame == 1 or frame == 3 else 0.0


## Arms up (ringing the bell, cheering).
static func keeper_cheer(rig: Node2D, t: float) -> void:
	var p := rig.get_node("pivot") as Node2D
	p.get_node("arm_l").rotation = 2.4 + sin(t * 10.0) * 0.2
	p.get_node("arm_r").rotation = -2.4 - sin(t * 10.0) * 0.2
	p.position.y = -absf(sin(t * 6.0)) * 6.0


# ================================================================ food cart (110x80)

## The cart: a wooden box on two wheels, the four foods on top (colour cues)
## and the star bucket at its end. Parts: wheel_l, wheel_r, bucket, stars.
static func cart() -> Node2D:
	var c := Node2D.new()
	c.name = "cart"
	VA.shadow(c, 58, 9)
	VA.stroke(c, PackedVector2Array([Vector2(-50, -46), Vector2(-66, -64)]), Pal.OUTLINE, 9.0)
	VA.stroke(c, PackedVector2Array([Vector2(-50, -46), Vector2(-66, -64)]), Pal.CART_DARK, 4.0)
	VA.shape(c, VA.rrect(Rect2(-72, -70, 14, 8), 4), Pal.CART_DARK, Pal.OUTLINE, 3.5)
	# Food piles peeking over the rim.
	var xs := [-36, -14, 8, 30]
	for i in 4:
		var f := food(FOODS[i])
		f.scale = Vector2(0.42, 0.42)
		f.position = Vector2(xs[i], -64)
		c.add_child(f)
	VA.shape(c, VA.rrect(Rect2(-52, -62, 100, 40), 8), Pal.CART)
	for i in 3:
		VA.stroke(c, PackedVector2Array([Vector2(-26 + i * 24, -58), Vector2(-26 + i * 24, -26)]), Pal.CART_DARK, 3.0)
	for i in 4:
		VA.fill(c, VA.circle(4, Vector2(-38 + i * 24, -32), 10), FOOD_COLOR[FOODS[i]])
	var bucket := VA.part(c, "bucket", Vector2(56, -40))
	var stars := VA.part(bucket, "stars", Vector2(0, -22))
	stars.z_index = 0
	VA.shape(bucket, PackedVector2Array([Vector2(-14, -18), Vector2(14, -18), Vector2(10, 12), Vector2(-10, 12)]), Pal.BOWL, Pal.OUTLINE, 4.0)
	VA.stroke(bucket, VA.arc(14, 14, PI, TAU, Vector2(0, -18), 10), Pal.OUTLINE, 3.0)
	for side in [-1, 1]:
		var w := VA.part(c, "wheel_l" if side < 0 else "wheel_r", Vector2(30 * side, -16))
		VA.shape(w, VA.circle(15), Pal.WHEEL, Pal.OUTLINE, 4.0)
		VA.shape(w, VA.circle(5, Vector2.ZERO, 12), Pal.CREAM, Pal.OUTLINE, 3.0)
		for k in 3:
			var a := k * PI / 3.0
			VA.stroke(w, PackedVector2Array([Vector2(cos(a), sin(a)) * 6, Vector2(cos(a), sin(a)) * 12]), Pal.CREAM, 2.5)
			VA.stroke(w, PackedVector2Array([-Vector2(cos(a), sin(a)) * 6, -Vector2(cos(a), sin(a)) * 12]), Pal.CREAM, 2.5)
	return c


## Shows `count` stars piled in the cart's bucket (capped for looks).
static func cart_stars(c: Node2D, count: int) -> void:
	var holder := VA.find(c, "stars")
	var want := mini(count, 12)
	while holder.get_child_count() < want:
		var i := holder.get_child_count()
		var s := star(0.42)
		s.position = Vector2((i % 4) * 7 - 10, -int(i / 4) * 6)
		s.rotation = (i * 0.7)
		holder.add_child(s)
	while holder.get_child_count() > want:
		holder.get_child(holder.get_child_count() - 1).free()


# ================================================================ bubble (90 px)

## Thought bubble with an empty bowl. Parts: bowl, hint (a faint food, hidden).
static func bubble() -> Node2D:
	var b := Node2D.new()
	b.name = "bubble"
	VA.shape(b, VA.circle(6, Vector2(-34, 42), 12), Pal.CREAM, Pal.OUTLINE, 3.5)
	VA.shape(b, VA.circle(9, Vector2(-24, 30), 14), Pal.CREAM, Pal.OUTLINE, 3.5)
	var ctrl := []
	for i in 10:
		var a := TAU * i / 10.0
		var r := 44.0 if i % 2 == 0 else 34.0
		ctrl.append(Vector2(cos(a) * r * 1.05, sin(a) * r * 0.8))
	VA.shape(b, VA.blob(ctrl, 6), Pal.CREAM, Pal.OUTLINE, 4.0)
	var hint := VA.part(b, "hint", Vector2(0, -8))
	hint.visible = false
	var bowl := VA.part(b, "bowl", Vector2(0, 6))
	VA.shape(bowl, VA.arc(26, 18, 0.0, PI, Vector2.ZERO, 16), Pal.BOWL, Pal.OUTLINE, 4.0)
	VA.shape(bowl, VA.ellipse(26, 6), Color("#c9d6ec"), Pal.OUTLINE, 3.5)
	VA.fill(bowl, VA.ellipse(18, 3.5, Vector2(0, 1)), Color("#7f93b8"))
	return b


static func bubble_hint(b: Node2D, kind: String, on: bool) -> void:
	var hint := b.get_node("hint") as Node2D
	if on and hint.get_child_count() == 0:
		var f := food(kind)
		f.scale = Vector2(0.62, 0.62)
		f.modulate = Color(1, 1, 1, 0.55)
		hint.add_child(f)
	hint.visible = on


# ================================================================ particles and icons

static func star(s := 1.0, color := Pal.STAR) -> Node2D:
	var n := Node2D.new()
	var p := VA.shape(n, VA.star_pts(20, 9), color, Pal.OUTLINE, 4.0)
	VA.fill(p, VA.circle(3.2, Vector2(-5, -4), 10), Color(1, 1, 1, 0.7))
	n.scale = Vector2(s, s)
	return n


static func heart(s := 1.0) -> Node2D:
	var n := Node2D.new()
	var p := VA.shape(n, VA.heart_pts(16), Pal.HEART, Pal.OUTLINE, 4.0)
	VA.fill(p, VA.circle(3.5, Vector2(-7, -6), 10), Color(1, 1, 1, 0.6))
	n.scale = Vector2(s, s)
	return n


static func note(color: Color, s := 1.0) -> Node2D:
	var n := Node2D.new()
	var outline := PackedVector2Array([Vector2(-2, 10), Vector2(-2, -22), Vector2(14, -16), Vector2(14, -8), Vector2(2, -13), Vector2(2, 10)])
	VA.shape(n, outline, color, Pal.OUTLINE, 3.5)
	VA.shape(n, VA.ellipse(9, 7, Vector2(-8, 11)), color, Pal.OUTLINE, 3.5).rotation = -0.3
	n.scale = Vector2(s, s)
	return n


static func confetti(color: Color) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.rrect(Rect2(-6, -3, 12, 6), 2), color, Pal.OUTLINE, 2.0)
	return n


static func bell(s := 1.0) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.circle(5, Vector2(0, -26), 12), Pal.BELL, Pal.OUTLINE, 3.0)
	VA.shape(n, VA.blob([Vector2(-20, 10), Vector2(-14, -12), Vector2(0, -22), Vector2(14, -12), Vector2(20, 10)], 6), Pal.BELL)
	VA.shape(n, VA.rrect(Rect2(-24, 6, 48, 9), 4), Pal.BELL.darkened(0.15), Pal.OUTLINE, 4.0)
	VA.shape(n, VA.circle(5, Vector2(0, 19), 12), Pal.BELL.darkened(0.3), Pal.OUTLINE, 3.0)
	n.scale = Vector2(s, s)
	return n


## A plate in the progress row: empty, or with a star when that meal is done.
static func plate(done: bool) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.ellipse(17, 12), Pal.CREAM, Pal.OUTLINE, 3.5)
	VA.fill(n, VA.ellipse(10, 6.5), Color("#e9dcc3"))
	if done:
		var s := star(0.62)
		s.position = Vector2(0, -3)
		n.add_child(s)
	return n


## Seat role icons (64 px): the keeper's hat, the feeder's wheel, the singer's note.
static func role_icon(seat: int, color: Color) -> Node2D:
	var n := Node2D.new()
	match seat:
		0:
			VA.shape(n, VA.ellipse(32, 9, Vector2(0, 10)), color, Pal.OUTLINE, 4.0)
			VA.shape(n, VA.blob([Vector2(-18, 10), Vector2(-15, -10), Vector2(0, -18), Vector2(15, -10), Vector2(18, 10)], 5), color, Pal.OUTLINE, 4.0)
			VA.fill(n, VA.rrect(Rect2(-16, 1, 32, 6), 2), color.darkened(0.35))
		1:
			var dirs := [Vector2(0, -1), Vector2(1, 0), Vector2(0, 1), Vector2(-1, 0)]
			VA.shape(n, VA.circle(9), color, Pal.OUTLINE, 3.5)
			for i in 4:
				var c: Vector2 = dirs[i] * 20.0
				VA.shape(n, VA.circle(11, c, 18), FOOD_COLOR[FOODS[i]], Pal.OUTLINE, 3.5)
			VA.stroke(n, VA.circle(13, dirs[0] * 20.0, 18), color, 4.0).closed = true
		2:
			n.add_child(note(color, 1.5))
	return n


static func icon_pad(color: Color) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.blob([Vector2(-30, -10), Vector2(0, -14), Vector2(30, -10), Vector2(34, 14), Vector2(20, 18), Vector2(0, 8), Vector2(-20, 18), Vector2(-34, 14)], 6), color, Pal.OUTLINE, 4.0)
	VA.fill(n, VA.rrect(Rect2(-22, -4, 14, 4), 1), Pal.OUTLINE)
	VA.fill(n, VA.rrect(Rect2(-17, -9, 4, 14), 1), Pal.OUTLINE)
	VA.fill(n, VA.circle(3.5, Vector2(16, -6), 10), Pal.OUTLINE)
	VA.fill(n, VA.circle(3.5, Vector2(23, 1), 10), Pal.OUTLINE)
	return n


static func icon_kb(color: Color) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.rrect(Rect2(-34, -16, 68, 32), 6), color, Pal.OUTLINE, 4.0)
	for row in 3:
		for col in 6:
			VA.fill(n, VA.rrect(Rect2(-28 + col * 9.6, -11 + row * 8, 7, 5.5), 1.5), Pal.OUTLINE)
	return n


static func arrow(color: Color, dir := 1) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, PackedVector2Array([Vector2(-10 * dir, -16), Vector2(12 * dir, 0), Vector2(-10 * dir, 16)]), color, Pal.OUTLINE, 4.0)
	return n


static func check(color: Color) -> Node2D:
	var n := Node2D.new()
	VA.shape(n, VA.circle(22), color, Pal.OUTLINE, 4.0)
	VA.stroke(n, PackedVector2Array([Vector2(-10, 0), Vector2(-3, 8), Vector2(11, -8)]), Pal.CREAM, 6.0)
	return n


# ================================================================ enclosures (~330x215)

## One enclosure: ground, back and side fences, the animal's features, and the
## gate facing the path (gate_top: the gate is in the back fence). The animal
## is added by the zoo between "back" and "front", both returned as children.
static func enclosure(kind: String, size: Vector2, gate_top: bool) -> Node2D:
	var e := Node2D.new()
	e.name = "enclosure_" + kind
	var back := VA.part(e, "back")
	var front := VA.part(e, "front")
	var ground_col := Pal.GRASS_LIGHT
	match kind:
		"penguin": ground_col = Color("#e3f1f8")
		"giraffe": ground_col = Color("#ecd48e")
		"elephant": ground_col = Color("#c9b98a")
		"seal": ground_col = Color("#e8dcb8")
	VA.shape(back, VA.rrect(Rect2(Vector2.ZERO, size), 22), ground_col, Pal.OUTLINE, 4.0)
	match kind:
		"monkey": _feat_monkey(back, size)
		"penguin": _feat_pool(back, size, true)
		"seal": _feat_pool(back, size, false)
		"giraffe": _feat_giraffe(back, size)
		"rabbit": _feat_rabbit(back, size)
		"elephant": _feat_elephant(back, size)
	# Fences: back rail (with a gate gap when gate_top), side rails, front rail.
	var gap := 90.0
	var cx := size.x / 2.0
	if gate_top:
		_fence(back, Vector2(8, 8), Vector2(cx - gap / 2, 8))
		_fence(back, Vector2(cx + gap / 2, 8), Vector2(size.x - 8, 8))
		_gate_posts(back, cx, 8, gap)
	else:
		_fence(back, Vector2(8, 8), Vector2(size.x - 8, 8))
	_fence(back, Vector2(8, 8), Vector2(8, size.y - 10), true)
	_fence(back, Vector2(size.x - 8, 8), Vector2(size.x - 8, size.y - 10), true)
	if gate_top:
		_fence(front, Vector2(8, size.y - 10), Vector2(size.x - 8, size.y - 10))
	else:
		_fence(front, Vector2(8, size.y - 10), Vector2(cx - gap / 2, size.y - 10))
		_fence(front, Vector2(cx + gap / 2, size.y - 10), Vector2(size.x - 8, size.y - 10))
		_gate_posts(front, cx, size.y - 10, gap)
	return e


static func _fence(parent: Node, a: Vector2, b: Vector2, side := false) -> void:
	var len := a.distance_to(b)
	var n := maxi(1, int(len / 42.0))
	if side:
		VA.limb(parent, PackedVector2Array([a + Vector2(0, -8), b + Vector2(0, -8)]), Pal.FENCE, 5.0)
	else:
		VA.limb(parent, PackedVector2Array([a + Vector2(0, -16), b + Vector2(0, -16)]), Pal.FENCE, 6.0)
		VA.limb(parent, PackedVector2Array([a + Vector2(0, -6), b + Vector2(0, -6)]), Pal.FENCE, 6.0)
	for i in n + 1:
		var p := a.lerp(b, float(i) / n)
		VA.shape(parent, VA.rrect(Rect2(p + Vector2(-5, -26), Vector2(10, 30)), 4), Pal.FENCE, Pal.OUTLINE, 3.5)


static func _gate_posts(parent: Node, cx: float, y: float, gap: float) -> void:
	for side in [-1, 1]:
		var x: float = cx + side * gap / 2.0
		VA.shape(parent, VA.rrect(Rect2(x - 7, y - 40, 14, 44), 5), Pal.FENCE_DARK, Pal.OUTLINE, 3.5)
		VA.shape(parent, VA.circle(8, Vector2(x, y - 42), 14), Pal.FENCE, Pal.OUTLINE, 3.5)


static func _tree(parent: Node, base: Vector2, height: float, canopy: Vector2, flat := false) -> void:
	VA.shape(parent, VA.rrect(Rect2(base + Vector2(-9, -height), Vector2(18, height)), 6), Pal.BARK, Pal.OUTLINE, 4.0)
	var c := base + Vector2(0, -height)
	if flat:
		VA.shape(parent, VA.blob([c + Vector2(-canopy.x, 4), c + Vector2(-canopy.x * 0.6, -canopy.y),
			c + Vector2(0, -canopy.y * 1.2), c + Vector2(canopy.x * 0.6, -canopy.y), c + Vector2(canopy.x, 4),
			c + Vector2(0, canopy.y * 0.35)], 6), Pal.LEAF, Pal.OUTLINE, 4.0)
	else:
		var ctrl := []
		for i in 9:
			var a := TAU * i / 9.0
			var r := 1.0 if i % 2 == 0 else 0.84
			ctrl.append(c + Vector2(cos(a) * canopy.x * r, sin(a) * canopy.y * r - canopy.y * 0.4))
		VA.shape(parent, VA.blob(ctrl, 6), Pal.LEAF, Pal.OUTLINE, 4.0)
		VA.fill(parent, VA.circle(canopy.y * 0.3, c + Vector2(-canopy.x * 0.3, -canopy.y * 0.7), 14), Color("#5cb566"))


static func _feat_monkey(p: Node, s: Vector2) -> void:
	_tree(p, Vector2(58, s.y - 40), 110, Vector2(56, 46))
	# A tyre swing on a rope from the branch.
	VA.stroke(p, PackedVector2Array([Vector2(88, s.y - 150), Vector2(88, s.y - 72)]), Pal.OUTLINE, 3.0)
	VA.shape(p, VA.ellipse(16, 12, Vector2(88, s.y - 62)), Pal.WHEEL, Pal.OUTLINE, 4.0)
	VA.fill(p, VA.ellipse(7, 5, Vector2(88, s.y - 62)), Color("#8fcf7a"))
	_tufts(p, [Vector2(s.x - 50, s.y - 40), Vector2(s.x - 80, 60)])


static func _feat_pool(p: Node, s: Vector2, penguin: bool) -> void:
	var c := Vector2(s.x * 0.74, s.y * 0.52)
	VA.shape(p, VA.blob([c + Vector2(-70, -10), c + Vector2(-40, -48), c + Vector2(30, -50),
		c + Vector2(72, -14), c + Vector2(56, 40), c + Vector2(-10, 48), c + Vector2(-66, 30)], 6), Pal.WATER, Pal.OUTLINE, 4.0)
	for k in 3:
		VA.stroke(p, VA.arc(14, 5, PI + 0.4, TAU - 0.4, c + Vector2(-34 + k * 30, -10 + (k % 2) * 22), 8), Pal.SKY, 3.0)
	if penguin:
		VA.shape(p, VA.blob([c + Vector2(10, 4), c + Vector2(40, -6), c + Vector2(52, 16), c + Vector2(22, 24)], 5), Pal.CREAM, Pal.OUTLINE, 3.5)
		VA.shape(p, VA.blob([Vector2(30, 40), Vector2(70, 30), Vector2(84, 62), Vector2(36, 70)], 5), Pal.CREAM, Pal.OUTLINE, 3.5)
	else:
		VA.shape(p, VA.blob([Vector2(24, 44), Vector2(60, 30), Vector2(86, 52), Vector2(70, 76), Vector2(30, 72)], 5), Pal.ROCK, Pal.OUTLINE, 4.0)
		# A striped beach ball.
		var b := Vector2(c.x + 34, c.y + 44)
		VA.shape(p, VA.circle(16, b, 20), Pal.CREAM, Pal.OUTLINE, 4.0)
		VA.fill(p, PackedVector2Array([b + Vector2(-6, -15), b + Vector2(6, -15), b + Vector2(4, 15), b + Vector2(-4, 15)]), Pal.HEART)
		VA.fill(p, PackedVector2Array([b + Vector2(-15, -5), b + Vector2(-8, -12), b + Vector2(-8, 12), b + Vector2(-15, 5)]), Color("#7de0c8"))


static func _feat_giraffe(p: Node, s: Vector2) -> void:
	_tree(p, Vector2(s.x - 62, s.y - 36), 128, Vector2(66, 26), true)
	_tufts(p, [Vector2(50, s.y - 40), Vector2(90, 70)])


static func _feat_rabbit(p: Node, s: Vector2) -> void:
	var m := Vector2(s.x - 70, s.y - 60)
	VA.shape(p, VA.blob([m + Vector2(-52, 20), m + Vector2(-30, -22), m + Vector2(20, -30), m + Vector2(54, 20)], 6), Pal.MUD, Pal.OUTLINE, 4.0)
	VA.shape(p, VA.ellipse(16, 12, m + Vector2(0, 6)), Pal.OUTLINE, Pal.OUTLINE, 2.0)
	for fpos in [Vector2(46, 70), Vector2(70, s.y - 44), Vector2(40, s.y - 70), Vector2(s.x - 40, 50)]:
		_flower(p, fpos, Pal.HEART if int(fpos.x) % 2 == 0 else Color("#b58cff"))


static func _feat_elephant(p: Node, s: Vector2) -> void:
	VA.shape(p, VA.ellipse(68, 30, Vector2(s.x - 86, s.y * 0.55)), Pal.MUD, Pal.OUTLINE, 4.0)
	VA.fill(p, VA.ellipse(30, 9, Vector2(s.x - 96, s.y * 0.55 - 6)), Color("#b08466"))
	VA.shape(p, VA.blob([Vector2(24, 60), Vector2(60, 40), Vector2(90, 62), Vector2(70, 90), Vector2(30, 88)], 5), Pal.ROCK, Pal.OUTLINE, 4.0)


static func _tufts(p: Node, at: Array) -> void:
	for pos in at:
		for k in 3:
			VA.stroke(p, PackedVector2Array([pos + Vector2(k * 6 - 6, 0), pos + Vector2(k * 8 - 8, -12)]), Pal.GRASS_DARK, 3.5)


static func _flower(p: Node, pos: Vector2, c: Color) -> void:
	for i in 5:
		var a := TAU * i / 5.0
		VA.shape(p, VA.circle(5, pos + Vector2(cos(a), sin(a)) * 6, 10), c, Pal.OUTLINE, 2.0)
	VA.fill(p, VA.circle(4, pos, 10), Pal.CREAM)
