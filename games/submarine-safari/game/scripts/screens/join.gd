extends Node2D
## Join screen: any device presses to take the next seat (helm, camera, bulb).
##
## - Unseated devices that press anything join in press order (Players.join).
## - kb:2 (Space + every loose key) is the toddler block: it prefers the
##   Lights seat and yields a lower seat to a real device when seats are full.
## - The driver continues with start (on release), or by holding "a" for
##   HOLD_TIME (a ring fills around the driver's porthole).
## - A seated device's "b" leaves its seat (the driver's on release), except
##   the gunner's "b", which opens the album to browse it.
## - Parent reset: the driver holds start + b for RESET_TIME, and the album
##   is emptied (a ring of bubbles fills first). A toddler cannot do it.
## No text: seat colours, role icons, device icons and a key-shape legend.

const HOLD_TIME := 1.0
const RESET_TIME := 3.0
const PORT_R := 28
const PORT_Y := 46
const PORT_X: Array[int] = [60, 160, 260]
const ROLE_ICONS: Array[String] = ["seat_driver", "seat_gunner", "seat_honker"]
const TODDLER := "kb:2"

const WATER: Array[Color] = [Color("#0099db"), Color("#124e89"), Color("#262b44"), Color("#181425")]
const INK := Color("#181425")
const WHITE := Color("#ffffff")
const GREY := Color("#8b9bb4")
const BRASS := Color("#feae34")
const BRASS_DARK := Color("#c28569")

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var hold := 0.0
var reset_hold := 0.0
var resets := 0
var _hold_armed := false
var _combo_used := false
var _ignore_release := false
var _prev_start := false
var _prev_b := false
var _time := 0.0
var _bounce: Array[float] = [0.0, 0.0, 0.0]
var _reset_flash := 0.0
var _role_sprites: Array[AnimatedSprite2D] = []
var _device_sprites: Array[AnimatedSprite2D] = []
var _album_icon: AnimatedSprite2D
var _bubbles: Array[Vector2] = []
var _sub: AnimatedSprite2D


func _ready() -> void:
	for i in 24:
		_bubbles.append(Vector2((i * 53) % 320, (i * 97) % 180))
	_sub = Art.sprite("sub", BRASS, Vector2i(40, 24))
	_sub.scale = Vector2(2, 2)
	_sub.position = Vector2(160, 134)
	add_child(_sub)
	for s in Players.SEAT_COUNT:
		var role := Art.sprite(ROLE_ICONS[s], Players.SEAT_COLORS[s].lightened(0.3), Vector2i(16, 16))
		role.scale = Vector2(2, 2)
		add_child(role)
		_role_sprites.append(role)
		var dev := Art.sprite("icon_kb", WHITE, Vector2i(16, 16))
		dev.visible = false
		add_child(dev)
		_device_sprites.append(dev)
	_album_icon = Art.sprite("icon_album", Color("#e8b796"), Vector2i(16, 16))
	_album_icon.position = Vector2(PORT_X[1] + 26, PORT_Y + 40)
	add_child(_album_icon)
	_refresh_devices()
	_layout()
	Sfx.music("music_album")


func _process(delta: float) -> void:
	_time += delta
	_handle_input(delta)
	for s in Players.SEAT_COUNT:
		_bounce[s] = maxf(0.0, _bounce[s] - delta)
	_reset_flash = maxf(0.0, _reset_flash - delta)
	for i in _bubbles.size():
		_bubbles[i].y -= delta * (10.0 + i % 5 * 4.0)
		if _bubbles[i].y < -4.0:
			_bubbles[i].y += 188.0
	_layout()
	queue_redraw()


# ---------------------------------------------------------------- input

func _handle_input(delta: float) -> void:
	var joined_now: Array[String] = []
	for s in [Players.Seat.GUNNER, Players.Seat.HONKER]:
		if Players.is_seated(s) and Players.just_pressed(s, "b"):
			if s == Players.Seat.GUNNER:
				_open_album()
				return
			Players.leave(s)
			Sfx.play("whoosh")
	for d in Players.unseated_devices_just_pressed("any"):
		if Players.device_pressed(d, "b"):
			continue  # a back press never joins
		var seat := join_device(d)
		if seat != -1:
			joined_now.append(d)
			_bounce[seat] = 0.35
			Sfx.play("join", 1.0 + 0.12 * seat)
			if seat == Players.Seat.DRIVER:
				_hold_armed = false
				hold = 0.0
				_ignore_release = true
	_refresh_devices()

	if not Players.is_seated(Players.Seat.DRIVER):
		hold = 0.0
		reset_hold = 0.0
		_prev_start = false
		_prev_b = false
		return
	var start := Players.pressed(Players.Seat.DRIVER, "start")
	var b := Players.pressed(Players.Seat.DRIVER, "b")
	# Parent reset combo: start + b held together.
	if start and b:
		_combo_used = true
		if reset_hold >= 0.0:
			reset_hold += delta
			if reset_hold >= RESET_TIME:
				_reset_album()
				reset_hold = -1.0  # once per hold
	else:
		reset_hold = 0.0
	var start_released := _prev_start and not start
	var b_released := _prev_b and not b
	_prev_start = start
	_prev_b = b
	if not start and not b:
		var used := _combo_used
		_combo_used = false
		var ignore := _ignore_release
		_ignore_release = false
		if used or ignore:
			return
		if b_released:
			Players.leave(Players.Seat.DRIVER)
			Sfx.play("whoosh")
			hold = 0.0
			return
		if start_released:
			_continue()
			return
	if start or b:
		return
	if joined_now.has(Players.device_of(Players.Seat.DRIVER)):
		return
	if Players.pressed(Players.Seat.DRIVER, "a"):
		if _hold_armed:
			hold += delta
			if hold >= HOLD_TIME:
				_continue()
	else:
		_hold_armed = true
		hold = 0.0


## Seat a device. The toddler block goes to the HONKER seat when it is free;
## a real device may bump the toddler block out of a lower seat when full.
func join_device(d: String) -> int:
	if Players.seat_of(d) != -1:
		return -1
	if d == TODDLER and not Players.is_seated(Players.Seat.HONKER):
		return Players.Seat.HONKER if Players.join_seat(d, Players.Seat.HONKER) else -1
	var seat := Players.join(d)
	if seat == -1 and d != TODDLER:
		var t := Players.seat_of(TODDLER)
		if t != -1 and t != Players.Seat.HONKER:
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


func _open_album() -> void:
	Sfx.play("select")
	Game.album_browse = true
	next_screen = "album"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("album")


func _reset_album() -> void:
	Game.album.reset()
	resets += 1
	_reset_flash = 0.6
	Sfx.play("bubble", 0.7)
	Sfx.play("whoosh")


# ---------------------------------------------------------------- layout

func _refresh_devices() -> void:
	for s in Players.SEAT_COUNT:
		var d := Players.device_of(s)
		var spr := _device_sprites[s]
		spr.visible = d != ""
		if d != "":
			var icon := "icon_pad" if d.begins_with("pad:") else "icon_kb"
			var sf := Art.frames(icon, WHITE, Vector2i(16, 16))
			if spr.sprite_frames != sf:
				spr.sprite_frames = sf
				spr.play("default")


func _bounce_offset(s: int) -> int:
	if _bounce[s] <= 0.0:
		return 0
	return -int(roundf(sin(_bounce[s] / 0.35 * PI) * 6.0))


func _layout() -> void:
	for s in Players.SEAT_COUNT:
		var by := _bounce_offset(s)
		var seated := Players.is_seated(s)
		_role_sprites[s].position = Vector2(PORT_X[s], PORT_Y + by)
		_role_sprites[s].modulate = Color.WHITE if seated else Color(0.5, 0.55, 0.7)
		var beat := int(_time * 3.0 + s) % 2
		_device_sprites[s].position = Vector2(PORT_X[s], PORT_Y + PORT_R + 14 - beat)
	_album_icon.visible = Players.is_seated(Players.Seat.GUNNER)
	_album_icon.position.y = PORT_Y + PORT_R + 14 - (int(_time * 2.0) % 2)
	_sub.position.y = 134 + (int(_time * 1.5) % 2)


func _draw() -> void:
	var band := 180.0 / WATER.size()
	for i in WATER.size():
		draw_rect(Rect2(0, roundf(i * band), 320, ceilf(band)), WATER[i])
	for i in _bubbles.size():
		var p := _bubbles[i].round()
		draw_circle(p, 1 + i % 3, Color("#2ce8f5"), false, 1.0)
	for s in Players.SEAT_COUNT:
		_draw_porthole(s)
	if _reset_flash > 0.0:
		draw_rect(Rect2(0, 0, 320, 180), Color(1, 1, 1, _reset_flash * 0.6))
	_draw_legend()


func _draw_porthole(s: int) -> void:
	var col: Color = Players.SEAT_COLORS[s]
	var seated := Players.is_seated(s)
	var c := Vector2(PORT_X[s], PORT_Y + _bounce_offset(s))
	draw_circle(c, PORT_R + 3, BRASS_DARK)
	draw_circle(c, PORT_R + 1, BRASS if seated else BRASS.darkened(0.45))
	draw_circle(c, PORT_R - 3, col.darkened(0.45) if seated else Color(INK, 0.9))
	# Rivets.
	for k in 8:
		var a := k * TAU / 8.0
		draw_rect(Rect2((c + Vector2(cos(a), sin(a)) * (PORT_R - 1)).round() - Vector2(1, 1), Vector2(2, 2)), BRASS_DARK)
	# Glass glint.
	draw_arc(c, PORT_R - 7, PI * 1.1, PI * 1.45, 8, Color(1, 1, 1, 0.35), 2.0)
	if not seated:
		if int(_time * 2.0 + s * 0.5) % 2 == 0:
			draw_circle(Vector2(c.x, PORT_Y + PORT_R + 14), 7, col, false, 2.0)
			draw_circle(Vector2(c.x, PORT_Y + PORT_R + 14), 3, col)
		return
	if s == Players.Seat.DRIVER:
		if hold > 0.0:
			draw_arc(c, PORT_R + 5, -PI * 0.5, -PI * 0.5 + TAU * clampf(hold / HOLD_TIME, 0.0, 1.0), 40, WHITE, 2.0)
		if reset_hold > 0.0:
			# The reset ring: bubbles around the helm, one per 1/12 of the hold.
			var n := int(clampf(reset_hold / RESET_TIME, 0.0, 1.0) * 12.0)
			for k in n:
				var a := -PI * 0.5 + k * TAU / 12.0
				draw_circle((c + Vector2(cos(a), sin(a)) * (PORT_R + 7)).round(), 2, Color("#2ce8f5"))
		# "Go" triangle beside the helm.
		var tx := c.x + PORT_R + 10
		var go := WHITE if int(_time * 2.0) % 2 == 0 or hold > 0.0 else GREY
		draw_colored_polygon(PackedVector2Array([Vector2(tx, c.y - 6), Vector2(tx + 9, c.y), Vector2(tx, c.y + 6)]), go)


## Key-shape legend, one cluster per keyboard block; a block lights up in the
## colour of the seat it took.
func _draw_legend() -> void:
	draw_rect(Rect2(0, 158, 320, 22), Color(INK, 0.6))
	for block in 3:
		var d := "kb:%d" % block
		var seat := Players.seat_of(d)
		var col := GREY if seat == -1 else Players.SEAT_COLORS[seat]
		var cx := PORT_X[block]
		match block:
			0: _draw_cross_keys(cx - 4, col, true)
			1: _draw_cross_keys(cx + 4, col, false)
			2: _draw_key(Rect2(cx - 22, 168, 44, 8), col)


func _draw_cross_keys(cx: int, col: Color, fire_left: bool) -> void:
	_draw_key(Rect2(cx - 3, 161, 7, 7), col)
	for i in 3:
		_draw_key(Rect2(cx - 11 + i * 8, 169, 7, 7), col)
	var fx := cx - 25 if fire_left else cx + 14
	_draw_key(Rect2(fx, 169, 11, 7), col.lightened(0.2))


func _draw_key(r: Rect2, col: Color) -> void:
	draw_rect(r, col.darkened(0.4))
	draw_rect(Rect2(r.position, r.size - Vector2(0, 2)), col)
