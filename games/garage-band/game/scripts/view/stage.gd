extends Node2D
## The band on the garage stage: four coloured light cones (additive), two
## amps whose speaker cones pulse on each bass note, and the three riders
## holding their instruments: the Lead's guitar, the Drummer's kit (each
## drum squashes 10 % on a hit) and the Crasher's cymbal / gong / cowbell /
## whoosh. The screen sets the public state every frame; the stage only draws.

const Draw := preload("res://scripts/view/draw.gd")

const X_LEAD := 262.0
const X_DRUM := 320.0
const X_CRASH := 376.0
const FEET := 284.0
const LIGHT_X: Array[float] = [236.0, 292.0, 348.0, 404.0]

## Beat phase 0..1 (0 = on the beat) for hops and light sway.
var beat_phase := 0.0
var bar_phase := 0.0
## 1 right after a bass note, decaying.
var bass_pulse := 0.0
var light_set := 0
var light_flash := 0.0
var drum_squash: Array[float] = [0.0, 0.0, 0.0, 0.0]
var strum := 0.0
var crash_wobble := 0.0
var crash_sound := 0
var bow := 0.0
var time := 0.0

var riders: Array[AnimatedSprite2D] = [null, null, null]
var _lights: Node2D
var _back: Node2D
var _front: Node2D


func setup(rider_ids: Array) -> void:
	_lights = Lights.new()
	_lights.stage = self
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_lights.material = mat
	add_child(_lights)
	_back = Back.new()
	_back.stage = self
	add_child(_back)
	for seat in 3:
		var id: String = rider_ids[seat] if seat < rider_ids.size() else ""
		if id == "":
			continue
		var s: AnimatedSprite2D = Game.rider_sprite(id)
		add_child(s)
		riders[seat] = s
	_front = Front.new()
	_front.stage = self
	add_child(_front)
	_place()


func _process(delta: float) -> void:
	time += delta
	_place()
	_lights.queue_redraw()
	_back.queue_redraw()
	_front.queue_redraw()


func _place() -> void:
	var hop := -4.0 * pow(1.0 - beat_phase, 3.0)
	var xs := [X_LEAD, X_DRUM, X_CRASH]
	for seat in 3:
		var s := riders[seat]
		if s == null:
			continue
		var feet := FEET - (22.0 if seat == 1 else 0.0)
		var h := hop * (0.6 if seat == 1 else 1.0)
		if seat == 0:
			h -= strum * 3.0
		if seat == 2:
			h -= crash_wobble * 5.0
		s.position = Vector2(xs[seat], feet - 24.0 + h + bow * 8.0)
		s.rotation = bow * 0.55
		s.flip_h = seat == 2 and bow < 0.01  # the Crasher faces the band


class Lights extends Node2D:
	var stage: Node2D

	func _draw() -> void:
		var set_cols: Array = Draw.LIGHT_SETS[stage.light_set % Draw.LIGHT_SETS.size()]
		for i in 4:
			var col: Color = set_cols[i]
			var top := Vector2(stage.LIGHT_X[i], 46)
			var sway: float = sin(stage.time * 1.3 + i * 1.7) * 18.0 + (stage.bar_phase - 0.5) * 6.0
			var base := Vector2(320 + (top.x - 320) * 0.5 + sway, 298)
			var a: float = 0.13 + 0.09 * (1.0 - stage.beat_phase) + 0.25 * stage.light_flash
			draw_colored_polygon(PackedVector2Array([top + Vector2(-5, 0), top + Vector2(5, 0),
				base + Vector2(36, 0), base + Vector2(-36, 0)]), Color(col, a))
			Draw.ellipse(self, base, 38, 9, Color(col, a * 1.3))


class Back extends Node2D:
	var stage: Node2D

	func _draw() -> void:
		# The light rig: a truss and four cans.
		draw_rect(Rect2(212, 34, 216, 5), Draw.GREY.darkened(0.3))
		for k in 13:
			draw_line(Vector2(214 + k * 16, 34), Vector2(222 + k * 16, 39), Draw.SLATE, 1.0)
		var set_cols: Array = Draw.LIGHT_SETS[stage.light_set % Draw.LIGHT_SETS.size()]
		for i in 4:
			var x: float = stage.LIGHT_X[i]
			draw_rect(Rect2(x - 7, 36, 14, 10), Draw.INK)
			Draw.ellipse(self, Vector2(x, 46), 6, 2.5, (set_cols[i] as Color).lightened(0.3))
		_amp(Vector2(220, 284))
		_amp(Vector2(420, 284))
		# Drum riser behind the kit.
		Draw.round_rect(self, Rect2(290, 262, 60, 16), 4, Draw.WOOD)
		draw_rect(Rect2(290, 262, 60, 3), Draw.ORANGE.darkened(0.2))
		# Cables snaking across the rug.
		draw_polyline(PackedVector2Array([Vector2(236, 284), Vector2(246, 292), Vector2(258, 290), Vector2(262, 286)]),
			Draw.INK, 2.0)

	func _amp(bottom: Vector2) -> void:
		var r := Rect2(bottom + Vector2(-20, -54), Vector2(40, 54))
		Draw.round_rect(self, r, 4, Draw.INK)
		Draw.round_rect(self, r.grow(-3), 3, Draw.DARK)
		draw_rect(Rect2(r.position + Vector2(4, 4), Vector2(32, 5)), Draw.SLATE)
		for k in 3:
			draw_circle(r.position + Vector2(10 + k * 8, 6.5), 1.4, Draw.YELLOW)
		var p: float = stage.bass_pulse
		for spk in [[Vector2(0, -22), 11.0], [Vector2(0, -8), 6.0]]:
			var c: Vector2 = bottom + spk[0] + Vector2(0, 0)
			var rad: float = spk[1] * (1.0 + 0.14 * p)
			draw_circle(c, rad, Draw.INK)
			draw_circle(c, rad * 0.78, Draw.SLATE.darkened(0.2))
			draw_circle(c, rad * 0.78, Draw.GREY, false, 1.0)
			draw_circle(c, rad * 0.3, Draw.GREY.lightened(0.2 * p))


class Front extends Node2D:
	var stage: Node2D

	func _draw() -> void:
		var sq: Array = stage.drum_squash
		var d := Vector2(stage.X_DRUM, 0)
		# Hi-hat on its stand, snare, tom and the kick in front.
		Draw.cymbal(self, Vector2(d.x - 34, 238 - 3.0 * sq[0]), 11, -0.1 + 0.15 * sq[0], Draw.YELLOW, 40)
		Draw.cymbal(self, Vector2(d.x - 34, 242 - 1.0 * sq[0]), 11, -0.1, Draw.YELLOW.darkened(0.2), 0)
		Draw.drum(self, Vector2(d.x - 20, 262), 22, 10, Draw.SKY, sq[1])
		Draw.drum(self, Vector2(d.x + 21, 262), 22, 12, Draw.LIME.darkened(0.2), sq[2])
		Draw.kick_drum(self, Vector2(d.x, 270), 15, Draw.RED, sq[3])
		# The Lead's guitar.
		var bob: float = stage.strum * 0.18
		Draw.guitar(self, Vector2(stage.X_LEAD + 2, 268 + stage.bow * 6.0), 0.85, -0.45 + bob)
		# The Crasher's instrument (the next sound it will make).
		Draw.crash_instrument(self, stage.crash_sound, Vector2(stage.X_CRASH + 26, 262), 0.85,
			sin(stage.time * 30.0) * stage.crash_wobble, stage.time)
