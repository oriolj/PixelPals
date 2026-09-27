extends Node2D
## A robot arm drawn pixel by pixel: each bone is rasterised from the
## `arm_segment` pattern (rows = the arm's cross-section, columns = its
## stripes), so the arm bends to any angle and stays crisp (never a rotated
## sprite). The hand (or the drill) sits at the tip, unrotated, facing the way
## the arm points (flipped for left).

const Tex := preload("res://scripts/view/tex.gd")
const WIDTH := 4

var base := Vector2.ZERO
var elbow := Vector2(10, -10)
var tip := Vector2(20, 0)
var closed := false
var tool := "arm_hand"
var spin := 0
var _pattern: Image
var _tools := {}


func _ready() -> void:
	_pattern = Tex.image("arm_segment", Vector2i(24, 4), Color("#c0cbdc"))


func set_pose(b: Vector2, e: Vector2, t: Vector2) -> void:
	base = b
	elbow = e
	tip = t
	queue_redraw()


func _tool_tex(frame_i: int) -> Texture2D:
	var key := "%s:%d" % [tool, frame_i]
	if not _tools.has(key):
		_tools[key] = Tex.frame(tool, frame_i, Color("#c0cbdc"), Vector2i(8, 8))
	return _tools[key]


func _draw() -> void:
	_bone(base.round(), elbow.round())
	_bone(elbow.round(), tip.round())
	# Joints: small round blocks.
	for j in [base.round(), elbow.round()]:
		draw_rect(Rect2(j - Vector2(2, 2), Vector2(4, 4)), Color("#181425"))
		draw_rect(Rect2(j - Vector2(1, 1), Vector2(2, 2)), Color("#8b9bb4"))
	var frame_i := (1 if closed else 0) if tool == "arm_hand" else spin
	var tex := _tool_tex(frame_i)
	var sz := tex.get_size()
	var left := tip.x < elbow.x - 0.5
	var p := (tip.round() - Vector2(0 if not left else sz.x, sz.y / 2)).round()
	if left:
		draw_texture_rect(tex, Rect2(p + Vector2(sz.x, 0), Vector2(-sz.x, sz.y)), false)
	else:
		draw_texture(tex, p)


func _bone(a: Vector2, b: Vector2) -> void:
	var v := b - a
	var length := v.length()
	if length < 0.5:
		return
	var u := v / length
	var n := Vector2(-u.y, u.x)
	var half := WIDTH * 0.5
	var lo := Vector2(minf(a.x, b.x), minf(a.y, b.y)) - Vector2(3, 3)
	var hi := Vector2(maxf(a.x, b.x), maxf(a.y, b.y)) + Vector2(3, 3)
	var pw := _pattern.get_width()
	var ph := _pattern.get_height()
	for y in range(int(lo.y), int(hi.y) + 1):
		for x in range(int(lo.x), int(hi.x) + 1):
			var c := Vector2(x + 0.5, y + 0.5) - a
			var t := c.dot(u)
			var s := c.dot(n)
			if t < -0.5 or t > length + 0.5 or absf(s) >= half:
				continue
			var row := clampi(int(floorf((s + half) / WIDTH * ph)), 0, ph - 1)
			var col := posmod(int(floorf(t)), pw)
			var col_c := _pattern.get_pixel(col, row)
			if col_c.a > 0.5:
				draw_rect(Rect2(x, y, 1, 1), col_c)
