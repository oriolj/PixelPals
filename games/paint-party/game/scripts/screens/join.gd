extends Node2D
## Join screen: any device presses to take the next seat (PixelPals rules).
##
## - Unseated devices that press anything join in press order (Players.join).
## - A seated device's "b" leaves its seat.
## - The Brush (seat 1) continues with "start", or by holding "a" for
##   HOLD_TIME (a ring fills around its panel), then Game.goto("select").
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   Splatter seat, and yields a lower seat to a real device when the seats
##   are full, because it has no "b" to leave and no stick to steer.
## No text: seat colours, role icons (brush, palette, splat), device icons
## and a key-shape legend.

const Kit := preload("res://scripts/ui/draw_kit.gd")
const Palette := preload("res://scripts/paint/palette.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")

const HOLD_TIME := 1.0
const PANEL_W := 176.0
const PANEL_H := 232.0
const PANEL_Y := 18.0
const PANEL_X: Array[float] = [28.0, 232.0, 436.0]
const TODDLER := "kb:2"

var auto_goto := true
var next_screen := ""

var hold := 0.0
var _hold_armed := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _blobs: Array = []   # background paint blobs: parts lists


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	# Paint blobs around the edges, kept clear of the key legend at the bottom.
	var spots := [Vector2(14, 20), Vector2(218, 8), Vector2(424, 10), Vector2(628, 24), Vector2(12, 250),
		Vector2(628, 236), Vector2(214, 340), Vector2(414, 344), Vector2(620, 336)]
	for i in spots.size():
		var c: Vector2 = spots[i] + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
		_blobs.append(Shapes.splat(c, rng.randf_range(14, 24), [Palette.COLORS[(i * 5) % 12].lightened(0.35)], rng))
	Sfx.music("music_menu")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			Players.leave(s)
			Sfx.play("whoosh")
			if s == 0:
				hold = 0.0
	for d in Players.unseated_devices_just_pressed("any"):
		if Players.device_pressed(d, "b"):
			continue  # a back press never joins
		var seat := join_device(d)
		if seat != -1:
			joined_now.append(d)
			_bounce[seat] = 0.35
			Sfx.play("join", 1.0 + 0.12 * seat)
			if seat == 0:
				_hold_armed = false
				hold = 0.0
	if not Players.is_seated(0):
		hold = 0.0
		return
	var driver_dev := Players.device_of(0)
	if joined_now.has(driver_dev):
		return  # the joining press never also continues
	if Players.just_pressed(0, "start"):
		_continue()
		return
	if Players.pressed(0, "a"):
		if _hold_armed:
			hold += delta
			if hold >= HOLD_TIME:
				_continue()
	else:
		_hold_armed = true
		hold = 0.0


## Seat a device. The toddler block goes to the Splatter seat when it is free;
## a real device may bump the toddler block out of a lower seat when full.
func join_device(d: String) -> int:
	if Players.seat_of(d) != -1:
		return -1
	if d == TODDLER and not Players.is_seated(2):
		return 2 if Players.join_seat(d, 2) else -1
	var seat := Players.join(d)
	if seat == -1 and d != TODDLER:
		var t := Players.seat_of(TODDLER)
		if t != -1 and t != 2:
			Players.leave(t)
			seat = Players.join(d)
	return seat


func _continue() -> void:
	hold = 0.0
	Sfx.play("select")
	next_screen = "select"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("select")


# ---------------------------------------------------------------- view

func _bounce_offset(s: int) -> float:
	if _bounce[s] <= 0.0:
		return 0.0
	return -sin(_bounce[s] / 0.35 * PI) * 10.0


func _draw() -> void:
	draw_rect(Rect2(0, 0, 640, 360), Palette.PAPER)
	for b in _blobs:
		Kit.parts(self, b)
	for s in Players.SEAT_COUNT:
		_draw_panel(s)
	_draw_legend()


static func role_icon(ci: CanvasItem, s: int, c: Vector2, size: float, lit: bool) -> void:
	var col: Color = Players.SEAT_COLORS[s] if lit else Color("#94b0c2")
	match s:
		0: Kit.icon_brush(ci, c, size, Palette.COLORS[1] if lit else col)
		1: Kit.icon_palette(ci, c, size)
		2: Kit.icon_splat(ci, c, size * 1.4, Palette.COLORS[5] if lit else col)


func _draw_panel(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var r := Rect2(PANEL_X[s], PANEL_Y + _bounce_offset(s), PANEL_W, PANEL_H)
	Kit.rrect(self, r.grow(3), 18, col.darkened(0.3) if seated else Color("#94b0c2"))
	Kit.rrect(self, r, 16, col.lightened(0.55) if seated else Color("#e4e9ee"))
	var cx := r.get_center().x
	Kit.disc(self, Vector2(cx, r.position.y + 56), 38, Kit.WHITE)
	role_icon(self, s, Vector2(cx, r.position.y + 56), 56.0, seated)
	var dev_c := Vector2(cx, r.position.y + 140)
	if not seated:
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			Kit.ring(self, dev_c, 20, col.darkened(0.2), 3.0)
			Kit.disc(self, dev_c, 9, col.darkened(0.2))
		return
	var d := Players.device_of(s)
	var beat := sin(_time * 5.0 + s) * 2.0
	if d.begins_with("pad:"):
		Kit.icon_pad(self, dev_c + Vector2(0, beat), 56.0, Kit.INK.lightened(0.2))
	else:
		Kit.icon_kb(self, dev_c + Vector2(0, beat), 56.0, Kit.WHITE)
	for i in 3:
		Kit.disc(self, Vector2(cx - 20 + i * 20, r.position.y + 180), 4, col.darkened(0.2))
	if s == 0:
		var ty := r.position.y + 206
		var go := Kit.INK if int(_time * 2.0) % 2 == 0 or hold > 0.0 else Color("#94b0c2")
		Kit.icon_play(self, Vector2(cx, ty), 30.0, go)
		if hold > 0.0:
			var k := clampf(hold / HOLD_TIME, 0.0, 1.0)
			draw_arc(Vector2(cx, ty), 20, -PI / 2, -PI / 2 + TAU * k, 40, Kit.INK, 4.0, true)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	for block in 3:
		var seat := Players.seat_of("kb:%d" % block)
		var col := Color("#94b0c2") if seat == -1 else Players.SEAT_COLORS[seat].darkened(0.1)
		var cx := PANEL_X[block] + PANEL_W / 2
		match block:
			0: _draw_cross_keys(cx - 8, col, true)
			1: _draw_cross_keys(cx + 8, col, false)
			2: _draw_key(Rect2(cx - 48, 318, 96, 16), col)


func _draw_cross_keys(cx: float, col: Color, fire_left: bool) -> void:
	_draw_key(Rect2(cx - 7, 298, 15, 15), col)
	for i in 3:
		_draw_key(Rect2(cx - 24 + i * 17, 316, 15, 15), col)
	var fx := cx - 54 if fire_left else cx + 30
	_draw_key(Rect2(fx, 316, 24, 15), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	Kit.rrect(self, r, 3, col.darkened(0.4))
	Kit.rrect(self, Rect2(r.position, r.size - Vector2(0, 3)), 3, col)
