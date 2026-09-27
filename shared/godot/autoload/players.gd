extends Node
## Seats and devices: who is playing, on what, as which role.
##
## A "device key" names one physical input source:
##   "pad:<id>"  a joypad (Godot device id)
##   "kb:0"      keyboard block 0 — WASD + Left Shift / Tab
##   "kb:1"      keyboard block 1 — arrow keys + Enter / Right Ctrl / Right Shift
##   "kb:2"      keyboard block 2 — Space and every key not owned by blocks 0/1
##   "demo:<n>"  scripted input (demo mode, tests)
## Everything else in the game asks this autoload per SEAT, never per device,
## so pads, keyboard and scripted input share every code path.

signal seat_joined(seat: int, device: String)
signal seat_left(seat: int, device: String)

enum Seat { DRIVER, GUNNER, HONKER }
const SEAT_COUNT := 3
const SEAT_COLORS: Array[Color] = [
	Color("#41a6f6"),  # driver: blue
	Color("#ffcd75"),  # gunner: yellow
	Color("#a7f070"),  # honker: green
]

## Logical buttons every device reports.
##   "a"      main button (fire / honk / confirm)
##   "b"      back
##   "start"  pause / parent menu
##   "any"    any button or key of that device (toddler-proof)
const BUTTONS := ["a", "b", "start", "any"]

const KB_BLOCKS := {
	0: {
		"up": [KEY_W], "down": [KEY_S], "left": [KEY_A], "right": [KEY_D],
		"a": [KEY_SHIFT, KEY_TAB], "b": [KEY_Q], "start": [KEY_ESCAPE],
	},
	1: {
		"up": [KEY_UP], "down": [KEY_DOWN], "left": [KEY_LEFT], "right": [KEY_RIGHT],
		"a": [KEY_ENTER, KEY_KP_ENTER, KEY_CTRL], "b": [KEY_BACKSPACE], "start": [KEY_P],
	},
	2: {
		"up": [], "down": [], "left": [], "right": [],
		"a": [KEY_SPACE], "b": [], "start": [],
	},
}

const DEADZONE := 0.3

## seat -> device key ("" = empty seat)
var seats: Array[String] = ["", "", ""]
## seat -> chosen rider id (see Game.roster)
var riders: Array[String] = ["", "", ""]

## device key -> {"move": Vector2, "a": bool, "b": bool, "start": bool, "any": bool}
var _now := {}
var _prev := {}
## Scripted devices: device key -> state dict, set by demo mode or tests.
var _scripted := {}
## Keys pressed this frame that belong to no block 0/1 binding (feed kb:2 "any").
var _loose_keys := {}
var _owned_keys := {}


func _ready() -> void:
	process_priority = -100  # poll before any gameplay node reads input
	for block in [0, 1]:
		for action in KB_BLOCKS[block]:
			for k in KB_BLOCKS[block][action]:
				_owned_keys[k] = true
	Input.joy_connection_changed.connect(_on_joy_connection_changed)
	_setup_quit_combo()


func _process(_delta: float) -> void:
	poll()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and not event.echo:
		var k: int = event.physical_keycode
		if not _owned_keys.has(k):
			if event.pressed:
				_loose_keys[k] = true
			else:
				_loose_keys.erase(k)


# ---------------------------------------------------------------- polling

func poll() -> void:
	_prev = _now
	_now = {}
	for d in all_devices():
		_now[d] = _read_device(d)


func all_devices() -> Array[String]:
	var out: Array[String] = ["kb:0", "kb:1", "kb:2"]
	for id in Input.get_connected_joypads():
		out.append("pad:%d" % id)
	for d in _scripted:
		out.append(d)
	return out


func _read_device(d: String) -> Dictionary:
	if _scripted.has(d):
		var s: Dictionary = _scripted[d]
		var st := {"move": s.get("move", Vector2.ZERO), "a": s.get("a", false),
			"b": s.get("b", false), "start": s.get("start", false)}
		st["any"] = s.get("any", st.a or st.b or st.start)
		return st
	if d.begins_with("kb:"):
		return _read_keyboard(int(d.substr(3)))
	if d.begins_with("pad:"):
		return _read_pad(int(d.substr(4)))
	return _empty_state()


func _empty_state() -> Dictionary:
	return {"move": Vector2.ZERO, "a": false, "b": false, "start": false, "any": false}


func _keys_down(keys: Array) -> bool:
	for k in keys:
		if Input.is_physical_key_pressed(k):
			return true
	return false


func _read_keyboard(block: int) -> Dictionary:
	var m: Dictionary = KB_BLOCKS[block]
	var v := Vector2(
		float(_keys_down(m.right)) - float(_keys_down(m.left)),
		float(_keys_down(m.down)) - float(_keys_down(m.up)))
	var st := {"move": v.limit_length(1.0), "a": _keys_down(m.a),
		"b": _keys_down(m.b), "start": _keys_down(m.start)}
	st["any"] = st.a or st.b or st.start or v != Vector2.ZERO
	if block == 2:
		# The toddler block: every key nobody else owns is a honk.
		var loose := false
		for k in _loose_keys:
			if Input.is_physical_key_pressed(k):
				loose = true
				break
		st.a = st.a or loose
		st.any = st.a
	return st


func _read_pad(id: int) -> Dictionary:
	var v := Vector2(Input.get_joy_axis(id, JOY_AXIS_LEFT_X), Input.get_joy_axis(id, JOY_AXIS_LEFT_Y))
	if v.length() < DEADZONE:
		v = Vector2.ZERO
	var dpad := Vector2(
		float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_RIGHT)) - float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_LEFT)),
		float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_DOWN)) - float(Input.is_joy_button_pressed(id, JOY_BUTTON_DPAD_UP)))
	if dpad != Vector2.ZERO:
		v = dpad
	var a := Input.is_joy_button_pressed(id, JOY_BUTTON_A) or Input.is_joy_button_pressed(id, JOY_BUTTON_X) \
		or Input.get_joy_axis(id, JOY_AXIS_TRIGGER_RIGHT) > 0.5
	var b := Input.is_joy_button_pressed(id, JOY_BUTTON_B)
	var start := Input.is_joy_button_pressed(id, JOY_BUTTON_START)
	var any := false
	for btn in JOY_BUTTON_SDL_MAX:
		if Input.is_joy_button_pressed(id, btn):
			any = true
			break
	return {"move": v.limit_length(1.0), "a": a, "b": b, "start": start, "any": any or v != Vector2.ZERO}


# ---------------------------------------------------------------- devices

func device_move(d: String) -> Vector2:
	return _now.get(d, _empty_state()).move


func device_pressed(d: String, button: String) -> bool:
	return _now.get(d, _empty_state())[button]


func device_just_pressed(d: String, button: String) -> bool:
	return _now.get(d, _empty_state())[button] and not _prev.get(d, _empty_state())[button]


## Devices that pressed "a"/"any" this frame and are not seated (join screen).
func unseated_devices_just_pressed(button := "a") -> Array[String]:
	var out: Array[String] = []
	for d in _now:
		if seat_of(d) == -1 and device_just_pressed(d, button):
			out.append(d)
	return out


func set_scripted(d: String, state: Dictionary) -> void:
	_scripted[d] = state


func clear_scripted(d := "") -> void:
	if d == "":
		_scripted.clear()
	else:
		_scripted.erase(d)


# ---------------------------------------------------------------- seats

func seat_of(d: String) -> int:
	return seats.find(d)


func device_of(seat: int) -> String:
	return seats[seat]


func is_seated(seat: int) -> bool:
	return seats[seat] != ""


func seated_count() -> int:
	return seats.count("") * -1 + SEAT_COUNT


## Seat a device in the first free seat (DRIVER, then GUNNER, then HONKER).
## Returns the seat, or -1 if it is already seated or every seat is taken.
func join(d: String) -> int:
	if seat_of(d) != -1:
		return -1
	var seat := seats.find("")
	if seat == -1:
		return -1
	seats[seat] = d
	seat_joined.emit(seat, d)
	return seat


func join_seat(d: String, seat: int) -> bool:
	if seat_of(d) != -1 or seats[seat] != "":
		return false
	seats[seat] = d
	seat_joined.emit(seat, d)
	return true


func leave(seat: int) -> void:
	var d := seats[seat]
	if d == "":
		return
	seats[seat] = ""
	seat_left.emit(seat, d)


func reset() -> void:
	for s in SEAT_COUNT:
		leave(s)
	riders = ["", "", ""]


func _on_joy_connection_changed(id: int, connected: bool) -> void:
	if connected:
		return
	var seat := seat_of("pad:%d" % id)
	if seat != -1:
		leave(seat)


# ---------------------------------------------------------------- per seat

## Analog move vector for a seat (zero if empty).
func move(seat: int) -> Vector2:
	return device_move(seats[seat]) if seats[seat] != "" else Vector2.ZERO


## Move snapped to 4 directions (for the gunner). Zero when idle.
func dir4(seat: int) -> Vector2i:
	var v := move(seat)
	if v.length() < DEADZONE:
		return Vector2i.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2i(signi(int(signf(v.x))), 0)
	return Vector2i(0, int(signf(v.y)))


static func _snap4(v: Vector2) -> Vector2i:
	if v.length() < DEADZONE:
		return Vector2i.ZERO
	if absf(v.x) >= absf(v.y):
		return Vector2i(int(signf(v.x)), 0)
	return Vector2i(0, int(signf(v.y)))


## A 4-direction flick: the direction this frame if it differs from last
## frame's (so holding right yields one event), else ZERO. For menus and
## choices (junctions, food pickers, next-shape trays).
func dir4_just_pressed(seat: int) -> Vector2i:
	var d := seats[seat]
	if d == "":
		return Vector2i.ZERO
	var now := _snap4(_now.get(d, _empty_state()).move)
	var before := _snap4(_prev.get(d, _empty_state()).move)
	return now if now != before else Vector2i.ZERO


func pressed(seat: int, button: String) -> bool:
	return seats[seat] != "" and device_pressed(seats[seat], button)


func just_pressed(seat: int, button: String) -> bool:
	return seats[seat] != "" and device_just_pressed(seats[seat], button)


## True if the device of any seated player just pressed button.
func anyone_just_pressed(button: String) -> bool:
	for s in SEAT_COUNT:
		if just_pressed(s, button):
			return true
	return false


# ---------------------------------------------------------------- quit combo
# Additive (2026-09-27, for the TV launcher): a parent-only way out of any game
# with a pad. Hold Back/Select + Start on any pad for QUIT_HOLD_SECONDS, or
# press Ctrl+Q on the keyboard, and the game quits (back to the launcher).
# It runs on its own watcher node with PROCESS_MODE_ALWAYS, so it works while
# a game's tree is paused, and it never touches the seat/input state above.
# The hold must START inside this app: a combo still held when the app starts
# (or when it is re-enabled) arms only after a release. Games must not bind
# Back+Start to anything else.

signal quit_requested

const QUIT_HOLD_SECONDS := 1.5

## false = the combo is ignored (the launcher turns it off while a game runs).
var quit_combo_enabled := true:
	set(v):
		quit_combo_enabled = v
		if not v:
			_quit_armed = false
			_quit_held = 0.0
			_show_quit_ring(0.0)
## What the combo does. Invalid (the default) = get_tree().quit(). Tests swap it.
var quit_action := Callable()

var _quit_held := 0.0
var _quit_armed := false
var _quit_layer: CanvasLayer = null
var _quit_ring: Control = null


class _QuitWatch extends Node:
	var players: Node

	func _process(delta: float) -> void:
		players._quit_tick(delta)

	func _input(event: InputEvent) -> void:
		players._quit_key(event)


class _QuitRing extends Control:
	var progress := 0.0

	func _draw() -> void:
		var vp := get_viewport_rect().size
		var r := maxf(4.0, minf(vp.x, vp.y) * 0.035)
		var c := Vector2(vp.x - r * 1.8, vp.y - r * 1.8)
		var w := maxf(1.0, r * 0.3)
		draw_arc(c, r, 0.0, TAU, 32, Color(0.1, 0.11, 0.17, 0.55), w, true)
		draw_arc(c, r, -PI / 2, -PI / 2 + TAU * progress, 32, Color("#f4f4f4"), w, true)


func _setup_quit_combo() -> void:
	var watch := _QuitWatch.new()
	watch.name = "QuitWatch"
	watch.players = self
	watch.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(watch)


## True while Back/Select + Start are both down on one pad (or a scripted
## device whose state has "back" and "start").
func quit_combo_held() -> bool:
	for id in Input.get_connected_joypads():
		if Input.is_joy_button_pressed(id, JOY_BUTTON_BACK) and Input.is_joy_button_pressed(id, JOY_BUTTON_START):
			return true
	for d in _scripted:
		var s: Dictionary = _scripted[d]
		if s.get("back", false) and s.get("start", false):
			return true
	return false


func _quit_tick(delta: float) -> void:
	var held := quit_combo_enabled and quit_combo_held()
	if not held:
		_quit_armed = quit_combo_enabled
		if _quit_held > 0.0:
			_quit_held = 0.0
			_show_quit_ring(0.0)
		return
	if not _quit_armed:
		return
	_quit_held += delta
	_show_quit_ring(clampf(_quit_held / QUIT_HOLD_SECONDS, 0.0, 1.0))
	if _quit_held >= QUIT_HOLD_SECONDS:
		_quit_held = 0.0
		_quit_armed = false
		_show_quit_ring(0.0)
		_do_quit()


func _quit_key(event: InputEvent) -> void:
	if not quit_combo_enabled:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_Q and event.ctrl_pressed:
		_do_quit()


func _do_quit() -> void:
	quit_requested.emit()
	if quit_action.is_valid():
		quit_action.call()
	elif is_inside_tree():
		get_tree().quit()


func _show_quit_ring(progress: float) -> void:
	if progress <= 0.0:
		if _quit_layer:
			_quit_layer.visible = false
		return
	if _quit_layer == null:
		_quit_layer = CanvasLayer.new()
		_quit_layer.name = "QuitRing"
		_quit_layer.layer = 128
		_quit_layer.process_mode = Node.PROCESS_MODE_ALWAYS
		_quit_ring = _QuitRing.new()
		_quit_ring.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_quit_ring.set_anchors_preset(Control.PRESET_FULL_RECT)
		_quit_layer.add_child(_quit_ring)
		add_child(_quit_layer)
	_quit_layer.visible = true
	_quit_ring.progress = progress
	_quit_ring.queue_redraw()
