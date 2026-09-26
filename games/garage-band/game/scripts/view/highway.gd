extends Node2D
## The Lead's 5-lane highway. Lanes are stacked (top = highest note, so
## up/down on the stick moves up/down the lanes); note gems slide from the
## far end (right) toward the hit line (left), in a light perspective. A
## gem's inner mark tells the octave: a dot = low, a star = high. The
## selected lane's fret button glows, and two pips beside it show the octave.

const Draw := preload("res://scripts/view/draw.gd")
const Rules := preload("res://scripts/music/music_rules.gd")

const HIT_X := 46.0
const FAR_X := 184.0
const CENTER_Y := 212.0
const NEAR_H := 112.0   # half height at the hit line
const FAR_H := 70.0
const LOOKAHEAD_BEATS := 2.5

var band: RefCounted   # band.gd
var now := 0
var lane := 2
var octave := 0
var lane_flash: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var dim := false
var time := 0.0


func _process(delta: float) -> void:
	time += delta
	for i in 5:
		lane_flash[i] = maxf(0.0, lane_flash[i] - delta * 4.0)
	queue_redraw()


func half_h(f: float) -> float:
	return lerpf(NEAR_H, FAR_H, clampf(f, 0.0, 1.0))


## Position of lane i at depth f (0 = hit line, 1 = far end).
func lane_pos(i: int, f: float) -> Vector2:
	var h := half_h(f)
	var y := CENTER_Y + h - (i + 0.5) * 2.0 * h / 5.0
	return Vector2(lerpf(HIT_X, FAR_X, f), y)


func depth_of(sample: int) -> float:
	return float(sample - now) / (LOOKAHEAD_BEATS * band.spb)


func gem_pos(g: Dictionary) -> Vector2:
	return lane_pos(int(g.lane), depth_of(int(g.sample)))


func _draw() -> void:
	# Lane bands, far to near, as quads.
	for i in 5:
		var col: Color = Draw.LANE_COLORS[i]
		var hn := half_h(0.0)
		var hf := half_h(1.0)
		var y0n := CENTER_Y + hn - (i + 1) * 2.0 * hn / 5.0
		var y1n := CENTER_Y + hn - i * 2.0 * hn / 5.0
		var y0f := CENTER_Y + hf - (i + 1) * 2.0 * hf / 5.0
		var y1f := CENTER_Y + hf - i * 2.0 * hf / 5.0
		var a := 0.16 + 0.35 * lane_flash[i] + (0.1 if i == lane else 0.0)
		draw_colored_polygon(PackedVector2Array([Vector2(HIT_X - 14, y0n), Vector2(FAR_X, y0f),
			Vector2(FAR_X, y1f), Vector2(HIT_X - 14, y1n)]), Color(col, a))
		draw_line(Vector2(HIT_X - 14, y1n), Vector2(FAR_X, y1f), Color(Draw.INK, 0.9), 2.0)
	if band == null:
		return
	# Beat lines scrolling in (thicker on bar lines).
	var b0 := int(ceil(band.beat_at(now)))
	for b in range(b0, b0 + int(LOOKAHEAD_BEATS) + 1):
		var f := depth_of(band.sample_at_beat(b))
		if f < 0.0 or f > 1.0:
			continue
		var top := lane_pos(4, f) + Vector2(0, -half_h(f) / 5.0)
		var bot := lane_pos(0, f) + Vector2(0, half_h(f) / 5.0)
		var bar := posmod(b, 4) == 0
		draw_line(top, bot, Color(Draw.WHITE, 0.35 if bar else 0.12), 3.0 if bar else 1.5)
	# Hit line and fret buttons.
	draw_line(lane_pos(4, 0) + Vector2(0, -NEAR_H / 5.0), lane_pos(0, 0) + Vector2(0, NEAR_H / 5.0),
		Color(Draw.WHITE, 0.8), 3.0)
	for i in 5:
		var p := lane_pos(i, 0.0)
		var col: Color = Draw.LANE_COLORS[i]
		var sel := i == lane
		var r := 13.0 if sel else 9.0
		draw_circle(p, r + 3.0, Draw.INK)
		draw_circle(p, r, col if sel else col.darkened(0.3))
		if lane_flash[i] > 0.0:
			draw_circle(p, r + 6.0 * lane_flash[i], Color(Draw.WHITE, lane_flash[i]), false, 3.0)
		if sel:
			draw_circle(p, r * 0.45, Draw.WHITE)
	# Octave pips beside the selected fret: lower pip = low octave, upper = high.
	var sp := lane_pos(lane, 0.0)
	for o in 2:
		var pp := Vector2(22, sp.y + (6.0 if o == 0 else -6.0))
		draw_circle(pp, 4.0, Draw.WHITE if o == octave else Color(Draw.WHITE, 0.2))
	# Gems, far ones first.
	var gems: Array = band.gems_lead
	for gi in range(gems.size() - 1, -1, -1):
		var g: Dictionary = gems[gi]
		var f := depth_of(int(g.sample))
		if f > 1.0 or f < -0.15:
			continue
		if g.hit:
			continue
		var s := lerpf(1.0, 0.62, clampf(f, 0.0, 1.0))
		var p := lane_pos(int(g.lane), f)
		var col: Color = Draw.LANE_COLORS[int(g.lane)]
		var alpha := 1.0 if f >= 0.0 else 1.0 + f / 0.15
		if dim:
			alpha *= 0.5
		Draw.ngon(self, p, 12.0 * s, 6, Color(Draw.INK, alpha), PI / 6)
		Draw.ngon(self, p, 10.0 * s, 6, Color(col, alpha), PI / 6)
		Draw.ngon(self, p + Vector2(-2, -2) * s, 5.0 * s, 6, Color(col.lightened(0.45), alpha), PI / 6)
		if int(g.octave) == 1:
			Draw.star(self, p, 5.5 * s, Color(Draw.WHITE, alpha), time)
		else:
			draw_circle(p, 2.5 * s, Color(Draw.WHITE, alpha))
