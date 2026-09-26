extends Node2D
## The thing that knocks the tower down, cycling per tower: a swinging
## wrecking ball, an elephant bum, a bouncing whale, a rocket boot.
## Pure motion + drawing (polygon compositions); the play screen reads
## `hit_time`, `contact_point()` and `push_dir` and applies the impulses.

const Vec := preload("res://scripts/play/vec.gd")
const Rules := preload("res://scripts/play/rules.gd")
const KINDS := ["ball", "elephant", "whale", "boot"]

var kind := "ball"
var t := 0.0
var duration := 2.6
var hit_time := 1.0
var push_dir := Vector2.RIGHT
## Tower geometry (world): centre x, top y, middle y; the view's left/right edges.
var tower_x := Rules.PLATFORM_X
var tower_top := Rules.PLATFORM_TOP - 64.0
var mid_y := Rules.PLATFORM_TOP - 32.0
var view_left := -40.0
var view_right := 680.0
var _pivot := Vector2.ZERO
var _len := 300.0


func setup(wrecker_kind: String, top_y: float, left: float, right: float) -> void:
	kind = wrecker_kind if KINDS.has(wrecker_kind) else "ball"
	tower_top = minf(top_y, Rules.PLATFORM_TOP - 40.0)
	mid_y = (Rules.PLATFORM_TOP + tower_top) * 0.5
	view_left = left
	view_right = right
	match kind:
		"ball":
			_len = 300.0
			_pivot = Vector2(tower_x - 40.0, mid_y - _len)
			hit_time = 1.0
			duration = 2.4
			push_dir = Vector2(1, -0.35)
		"elephant":
			hit_time = 1.45
			duration = 2.8
			push_dir = Vector2(-1, -0.45)
		"whale":
			hit_time = 1.5
			duration = 2.8
			push_dir = Vector2(1, -0.5)
		"boot":
			hit_time = 1.2
			duration = 2.6
			push_dir = Vector2(1, -0.3)
	position = pos_at(0.0)
	queue_redraw()


func advance(dt: float) -> void:
	t += dt
	position = pos_at(t)
	queue_redraw()


func pos_at(time: float) -> Vector2:
	match kind:
		"ball":
			return _pivot + Vector2(sin(_angle(time)), cos(_angle(time))) * _len
		"elephant":
			var stop_x := tower_x + Rules.PLATFORM_HALF + 20.0
			var x := lerpf(view_right + 90.0, stop_x, clampf(time / 1.3, 0.0, 1.0))
			if time > 1.3 and time < 1.6:
				x -= sin((time - 1.3) / 0.3 * PI) * 26.0  # the bum bump
			return Vector2(x, Rules.PIT_TOP - 44.0)
		"whale":
			var u := clampf(time / hit_time, 0.0, 1.2)
			var x := lerpf(view_left - 70.0, tower_x - 70.0, u)
			var hop := (Rules.PIT_TOP - 40.0) - mid_y
			var y := Rules.PIT_TOP - 40.0 - absf(sin(PI * 2.5 * u)) * maxf(hop, 90.0)
			if time > hit_time:
				var k := time - hit_time
				x = tower_x - 70.0 - k * 120.0
				y = mid_y - 60.0 * k + 260.0 * k * k
				y = minf(y, Rules.PIT_TOP - 40.0)
			return Vector2(x, y)
		"boot":
			var u := clampf(time / hit_time, 0.0, 1.0)
			var x := lerpf(view_left - 90.0, tower_x - 60.0, u)
			var y := mid_y + sin(time * 9.0) * 4.0
			if time > hit_time:
				var k := time - hit_time
				x = tower_x - 60.0 - k * 60.0
				y = mid_y - k * k * 260.0
			return Vector2(x, y)
	return Vector2.ZERO


func _angle(time: float) -> float:
	# A pendulum released from the left: the bottom of the swing is the hit.
	return -1.25 * cos(time / hit_time * PI * 0.5)


## Where the blow lands (world), used as the impulse origin.
func contact_point() -> Vector2:
	match kind:
		"ball":
			return pos_at(hit_time) + Vector2(24, 0)
		"elephant":
			return Vector2(tower_x + Rules.PLATFORM_HALF - 30.0, Rules.PLATFORM_TOP - 30.0)
		"whale":
			return Vector2(tower_x - 30.0, mid_y)
		"boot":
			return Vector2(tower_x - 30.0, mid_y)
	return Vector2(tower_x, mid_y)


func _draw() -> void:
	match kind:
		"ball": _draw_ball()
		"elephant": _draw_elephant()
		"whale": _draw_whale()
		"boot": _draw_boot()


func _draw_ball() -> void:
	# Chain from the pivot (drawn in local space).
	var from := _pivot - position
	var links := 14
	for i in links:
		var a := from.lerp(Vector2.ZERO, float(i) / links)
		var b := from.lerp(Vector2.ZERO, float(i + 1) / links)
		draw_line(a, b, Vec.INK, 7.0, true)
		draw_line(a, b, Vec.GREY if i % 2 == 0 else Vec.SLATE, 3.5, true)
	var r := 30.0
	Vec.draw_disc(self, Vector2.ZERO, r, Vec.DUSK)
	draw_circle(Vector2(-4, -2), r - 8, Vec.SLATE, true, -1.0, true)
	draw_arc(Vector2.ZERO, r - 7, -2.7, -1.6, 10, Color(1, 1, 1, 0.5), 4.0, true)
	# A cheeky face.
	for e in [Vector2(-9, -3), Vector2(9, -3)]:
		draw_circle(e, 6.0, Vec.INK, true, -1.0, true)
		draw_circle(e, 4.6, Vec.WHITE, true, -1.0, true)
		draw_circle(e + Vector2(2, 0), 2.4, Vec.INK, true, -1.0, true)
	draw_arc(Vector2(0, 7), 9.0, 0.2, PI - 0.2, 10, Vec.INK, 3.0, true)
	# The shackle on top, facing the chain.
	var up := from.normalized()
	draw_circle(up * (r + 3), 7.0, Vec.INK, true, -1.0, true)
	draw_circle(up * (r + 3), 3.5, Vec.GREY, true, -1.0, true)


func _draw_elephant() -> void:
	var grey := Color("#94b0c2")
	var dark := Color("#566c86")
	var walk := sin(t * 14.0) * 5.0 if t < 1.3 else 0.0
	# Legs (four stubby ones).
	for i in 4:
		var lx := -34.0 + i * 20.0
		var off := walk if i % 2 == 0 else -walk
		var leg := Vec.rounded(Vec.translated(Vec.rect(16, 30), Vector2(lx + off * 0.4, 30)), 5.0, 3)
		Vec.draw_shape(self, leg, dark if i % 2 == 0 else grey)
	# Body, bum to the left (toward the tower).
	var body := Vec.rounded(Vec.translated(Vec.rect(100, 62), Vector2(0, 0)), 30.0, 6)
	Vec.draw_shape(self, body, grey)
	# The tail with a tuft.
	draw_line(Vector2(-50, -6), Vector2(-60, 8 + walk), Vec.INK, 5.0, true)
	draw_line(Vector2(-50, -6), Vector2(-60, 8 + walk), dark, 2.5, true)
	Vec.draw_disc(self, Vector2(-61, 11 + walk), 4.0, Vec.INK, Vec.INK, 1.0)
	# Bum cheeks line.
	draw_arc(Vector2(-40, 4), 14.0, -1.2, 1.2, 8, dark, 3.0, true)
	# Head, ear and trunk on the right.
	var head_at := Vector2(52, -12)
	Vec.draw_disc(self, head_at, 26.0, grey)
	var ear := Vec.rounded(PackedVector2Array([Vector2(34, -34), Vector2(52, -30), Vector2(50, 6), Vector2(30, 0)]), 8.0, 4)
	Vec.draw_shape(self, ear, Color("#f4b4c0"))
	var trunk_up := 1.0 if t > hit_time else 0.0
	var trunk := PackedVector2Array([head_at + Vector2(20, 2), head_at + Vector2(34, 8 - 22 * trunk_up),
		head_at + Vector2(40, -8 - 30 * trunk_up)])
	draw_polyline(trunk, Vec.INK, 13.0, true)
	draw_polyline(trunk, grey, 8.0, true)
	draw_circle(head_at + Vector2(10, -8), 5.0, Vec.INK, true, -1.0, true)
	draw_circle(head_at + Vector2(10, -8), 3.6, Vec.WHITE, true, -1.0, true)
	draw_circle(head_at + Vector2(9, -9), 2.0, Vec.INK, true, -1.0, true)
	draw_arc(head_at + Vector2(10, 6), 6.0, 0.3, PI - 0.3, 8, Vec.INK, 2.5, true)


func _draw_whale() -> void:
	var blue := Color("#3b5dc9")
	var belly := Color("#73eff7")
	var squash := 1.0 + 0.12 * sin(t * 12.0)
	var body := Vec.scaled(Vec.rounded(PackedVector2Array([Vector2(-60, 0), Vector2(-20, -34), Vector2(40, -30),
		Vector2(64, 4), Vector2(40, 30), Vector2(-30, 26)]), 22.0, 6), Vector2(1.0, squash))
	# Tail on the left.
	var tail := Vec.rounded(PackedVector2Array([Vector2(-54, 2), Vector2(-84, -24), Vector2(-76, 2), Vector2(-86, 24)]), 5.0, 3)
	Vec.draw_shape(self, tail, blue)
	Vec.draw_shape(self, body, blue)
	var tummy := Vec.rounded(PackedVector2Array([Vector2(-30, 14), Vector2(40, 10), Vector2(30, 26), Vector2(-20, 24)]), 8.0, 4)
	draw_colored_polygon(tummy, belly)
	for i in 3:
		draw_line(Vector2(-14 + i * 14, 16), Vector2(-16 + i * 14, 24), Color(blue, 0.6), 2.0, true)
	# Eye and smile.
	draw_circle(Vector2(34, -8), 6.0, Vec.INK, true, -1.0, true)
	draw_circle(Vector2(34, -8), 4.5, Vec.WHITE, true, -1.0, true)
	draw_circle(Vector2(36, -8), 2.4, Vec.INK, true, -1.0, true)
	draw_arc(Vector2(44, 6), 9.0, 0.3, 1.9, 8, Vec.INK, 3.0, true)
	draw_circle(Vector2(26, 2), 3.0, Color(1, 0.55, 0.6, 0.6), true, -1.0, true)
	# The spout.
	var spout := absf(sin(t * 5.0)) * 10.0
	for i in 3:
		var x := -6.0 + i * 8.0
		draw_line(Vector2(4, -34), Vector2(x, -52 - spout), Vec.SKY, 4.0, true)
		Vec.draw_disc(self, Vector2(x, -54 - spout), 4.0, Vec.CYAN, Vec.SKY, 2.0)


func _draw_boot() -> void:
	var red := Color("#b13e53")
	# Flame behind (left).
	var flick := 1.0 + 0.25 * sin(t * 40.0)
	var flame := PackedVector2Array([Vector2(-44, -20), Vector2(-44 - 40 * flick, -12), Vector2(-50 - 22 * flick, -4),
		Vector2(-44 - 44 * flick, 4), Vector2(-44, 10)])
	Vec.draw_shape(self, flame, Vec.ORANGE, Vec.RED, 2.0)
	var inner := PackedVector2Array([Vector2(-44, -12), Vector2(-44 - 22 * flick, -4), Vector2(-44, 4)])
	draw_colored_polygon(inner, Vec.YELLOW)
	# The rocket tube with fins.
	var tube := Vec.rounded(Vec.translated(Vec.rect(56, 22), Vector2(-18, -4)), 8.0, 3)
	Vec.draw_shape(self, Vec.rounded(PackedVector2Array([Vector2(-40, -14), Vector2(-50, -28), Vector2(-30, -14)]), 2.0, 2), Vec.RED)
	Vec.draw_shape(self, tube, Vec.GREY)
	draw_line(Vector2(-30, -14), Vector2(-30, 6), Vec.SLATE, 3.0, true)
	# The boot: shaft up, toe to the right (the kicking end).
	var boot := Vec.rounded(PackedVector2Array([Vector2(-12, -46), Vector2(16, -46), Vector2(18, 4), Vector2(46, 10),
		Vector2(50, 30), Vector2(-14, 30)]), 9.0, 4)
	Vec.draw_shape(self, boot, red)
	var sole := Vec.rounded(PackedVector2Array([Vector2(-16, 26), Vector2(52, 26), Vector2(50, 36), Vector2(-16, 36)]), 3.0, 2)
	Vec.draw_shape(self, sole, Vec.INK, Vec.INK, 1.0)
	for i in 3:
		var y := -34.0 + i * 10.0
		draw_line(Vector2(-4, y), Vector2(10, y + 4), Vec.WHITE, 3.0, true)
	draw_arc(Vector2(32, 16), 7.0, PI, TAU, 8, Color(1, 1, 1, 0.5), 3.0, true)
