extends Node2D
## The fort: one cosy bedroom at dusk, 14 hiding spots, 8 hidden toys.
##
## - Seat 0 (flashlight, the adult) moves a warm light with the stick. With
##   no seeker seated, "a" lifts the spot under the light, and holding the
##   light on a spot for DWELL seconds lifts it on its own.
## - Seat 1 (seeker, the 5-year-old) hops a paw between spots with 4
##   directions (the spot graph) and lifts with "a".
## - Seat 2 (peekaboo, the 2-year-old): any button makes a friend pop out
##   near the light (the peekaboo director); presses inside the cooldown
##   twinkle the fairy lights.
## A hidden toy shows a tip and its spot wiggles while the flashlight is on
## it. Lifting an empty spot always gives a small surprise. After HINT_AFTER
## seconds without a find, the nearest toy's spot glows. The round ends when
## all eight toys are found, or at Game.round_seconds, when the rest walk out
## on their own; then the lamp fades on over LAMP_FADE seconds -> party.
## No text, no timer shown, nothing can be lost.

const LightMask := preload("res://scripts/fort/light_mask.gd")
const SpotGraph := preload("res://scripts/fort/spot_graph.gd")
const Director := preload("res://scripts/fort/peekaboo_director.gd")
const Layout := preload("res://scripts/fort/room_layout.gd")
const Nightcap := preload("res://scripts/nightcap.gd")

enum State { RUN, WALKOUT, LAMP, DONE }

const W := 320
const H := 180
const ADULT := 0
const KID := 1
const TODDLER := 2
const TOY_COUNT := 8
const DWELL := 1.5
const HINT_AFTER := 45.0
const OPEN_TIME := 1.6
const LAMP_FADE := 2.0
const LAMP_STAY := 2.8
const FLASH_SPEED := 120.0
const FLASH_SMOOTH := 9.0
## A spot is "under the light" when its centre is this close to the light centre.
const UNDER_LIGHT := 16.0
const WALK_EVERY := 0.6
const SURPRISES: Array[String] = ["sock", "sleepy_mouse", "cookie"]
const SPOT_SIZES := {
	"pillow_a": Vector2i(24, 16), "pillow_b": Vector2i(20, 16), "blanket_fold": Vector2i(24, 16),
	"box": Vector2i(16, 16), "curtain": Vector2i(16, 24), "bed_edge": Vector2i(32, 16),
}
const SPOT_TINTS := {
	"pillow_a": Color("#f4f4f4"), "pillow_b": Color("#73eff7"), "blanket_fold": Color("#b13e53"),
	"box": Color("#ef7d57"), "curtain": Color("#a7f070"), "bed_edge": Color("#41a6f6"),
}
const TOY_TINTS := {
	"teddy": Color("#ef7d57"), "bunny": Color("#f4f4f4"), "duck": Color("#ffcd75"), "ball": Color("#b13e53"),
	"blocks": Color("#41a6f6"), "dino": Color("#38b764"), "car": Color("#b13e53"), "doll": Color("#73eff7"),
}
const C_BLUE_RIM := Color("#41a6f6")
const C_GREEN := Color("#a7f070")
const C_WARM := Color("#ffcd75")

## Set false in tests: the screen records next_screen instead of switching.
var auto_goto := true
var next_screen := ""

var state := State.RUN
var paused := false
var time := 0.0
var since_find := 0.0
var round_over := false
var rng := RandomNumberGenerator.new()

## Spot dicts: {"kind", "pos": Vector2i, "toy": String, "open": float, "found": bool}
var spots: Array[Dictionary] = []
var graph := SpotGraph.new()
var director := Director.new()
## Toys in the basket (arrived) and on their way (found but flying).
var found: Array[String] = []
var basket: Array[String] = []
var flying: Array[Dictionary] = []   # {node, toy, from, to, t, dur, walk}
var surprises: Array[Dictionary] = []  # {node, t, dur, base}
var surprise_count := 0
var _surprise_bag: Array[String] = []

var light_pos := Layout.FLASH_START
var light_vel := Vector2.ZERO
var paw_spot := 3
var dwell_t := 0.0
var dwell_spot := -1
var _dwell_done_spot := -1
var hint_spot := -1
var walk_t := 0.0
var lamp_t := 0.0
var strength := LightMask.STRENGTH
var twinkle_t := 0.0
var cheer_t := 0.0
var lights: Array[Dictionary] = []
var lift_count := 0

# nodes
var mask: ColorRect
var mask_mat: ShaderMaterial
var overlay: Overlay
var pause_overlay: PauseOverlay
var fort_spr: AnimatedSprite2D
var lamp_spr: AnimatedSprite2D
var basket_spr: AnimatedSprite2D
var spot_nodes: Array[AnimatedSprite2D] = []
var tip_nodes: Array[AnimatedSprite2D] = []
var friend_nodes := {}  # friend dict id -> sprite
var rider_nodes: Array[AnimatedSprite2D] = []
var basket_nodes: Array[AnimatedSprite2D] = []
var paw: AnimatedSprite2D
var _light_check_t := -1.0


func _ready() -> void:
	rng.randomize()
	var pts: Array = []
	for s in Layout.SPOTS:
		spots.append({"kind": s.kind, "pos": s.pos, "toy": "", "open": 0.0, "found": false})
		pts.append(s.pos)
	graph.build(pts)
	_build()
	hide_toys()
	Sfx.music("music_fort")
	if Game.light_check:
		_light_check_t = 0.0


func _process(delta: float) -> void:
	step(delta)
	if _light_check_t >= 0.0:
		_light_check_step(delta)


# ================================================================ setup

## Hide the eight toys in eight distinct random spots (or where `placement`
## says: {spot_index: toy}).
func hide_toys(placement := {}) -> void:
	for s in spots:
		s.toy = ""
	if not placement.is_empty():
		for i in placement:
			spots[int(i)].toy = placement[i]
		return
	var idx: Array[int] = []
	for i in spots.size():
		idx.append(i)
	for i in range(idx.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := idx[i]
		idx[i] = idx[j]
		idx[j] = tmp
	for k in TOY_COUNT:
		spots[idx[k]].toy = Game.TOYS[k]


func _build() -> void:
	var bg := _spr("room_bg", Color("#94b0c2"), Vector2i(W, H), self)
	bg.centered = false
	bg.z_index = 0
	fort_spr = _spr("fort", Color("#b13e53"), Vector2i(96, 64), self)
	fort_spr.stop()
	fort_spr.position = Vector2(Layout.FORT_POS)
	fort_spr.z_index = 30
	lamp_spr = _spr("lamp", C_WARM, Vector2i(16, 32), self)
	lamp_spr.stop()
	lamp_spr.frame = 0
	lamp_spr.position = Vector2(Layout.LAMP_POS)
	lamp_spr.z_index = 39
	for i in spots.size():
		var s: Dictionary = spots[i]
		var sz: Vector2i = SPOT_SIZES[s.kind]
		var n := _spr(s.kind, SPOT_TINTS[s.kind], sz, self)
		n.stop()
		n.position = Vector2(s.pos)
		n.z_index = _spot_z(i)
		spot_nodes.append(n)
		var tip := _spr("tip_teddy", C_WARM, Vector2i(8, 8), self)
		tip.stop()
		tip.visible = false
		tip.z_index = _spot_z(i) - 1
		tip_nodes.append(tip)
	# The seats' avatars sit in the fort's doorway, in nightcaps of their seat colour.
	for seat in Players.SEAT_COUNT:
		if not Players.is_seated(seat):
			continue
		var rid: String = Players.riders[seat]
		if rid == "":
			rid = Game.roster[seat % Game.roster.size()]
		var r := _spr(rid, Game.rider_color(rid), Vector2i(16, 16), self)
		r.position = Vector2(Layout.RIDER_SEATS[seat])
		r.z_index = 50
		var cap := Nightcap.new()
		cap.color = Players.SEAT_COLORS[seat]
		r.add_child(cap)
		rider_nodes.append(r)
	basket_spr = _spr("toy_basket", Color("#ef7d57"), Vector2i(32, 24), self)
	basket_spr.stop()
	basket_spr.position = Vector2(Layout.BASKET_POS)
	basket_spr.z_index = 62
	mask = ColorRect.new()
	mask.size = Vector2(W, H)
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE
	mask.z_index = 100
	mask_mat = LightMask.make_material()
	mask.material = mask_mat
	add_child(mask)
	overlay = Overlay.new()
	overlay.fort = self
	overlay.z_index = 110
	add_child(overlay)
	paw = _spr("paw_pointer", Players.SEAT_COLORS[KID], Vector2i(16, 16), overlay)
	paw.modulate = Players.SEAT_COLORS[KID]
	paw.visible = Players.is_seated(KID)
	pause_overlay = PauseOverlay.new()
	pause_overlay.visible = false
	pause_overlay.z_index = 200
	add_child(pause_overlay)
	_update_lights()
	_place_nodes()


func _spr(sprite_name: String, tint: Color, size: Vector2i, parent: Node) -> AnimatedSprite2D:
	var s := Art.sprite(sprite_name, tint, size)
	parent.add_child(s)
	return s


func _spot_z(i: int) -> int:
	return 20 + int(spots[i].pos.y / 4)


# ================================================================ frame

func step(dt: float) -> void:
	if state == State.DONE:
		return
	if _pause_input():
		return
	time += dt
	twinkle_t = maxf(0.0, twinkle_t - dt)
	cheer_t = maxf(0.0, cheer_t - dt)
	for s in spots:
		s.open = maxf(0.0, s.open - dt)
	_move_light(dt)
	if state == State.RUN:
		since_find += dt
		_seeker()
		_flashlight_lift(dt)
		_hint()
		if time >= Game.round_seconds and not round_over:
			_start_walkout()
	_peekaboo(dt)
	_update_flying(dt)
	_update_surprises(dt)
	if state == State.RUN and round_over and flying.is_empty():
		_start_lamp()
	elif state == State.WALKOUT:
		_walkout(dt)
	elif state == State.LAMP:
		lamp_t += dt
		strength = LightMask.STRENGTH * (1.0 - clampf(lamp_t / LAMP_FADE, 0.0, 1.0))
		if lamp_t >= LAMP_FADE + LAMP_STAY:
			_finish()
			return
	_update_lights()
	_place_nodes()


func _move_light(dt: float) -> void:
	var target := Players.move(ADULT) * FLASH_SPEED if state == State.RUN else Vector2.ZERO
	light_vel = light_vel.lerp(target, 1.0 - exp(-dt * FLASH_SMOOTH))
	light_pos += light_vel * dt
	light_pos = light_pos.clamp(Vector2(6, 6), Vector2(W - 6, H - 6))


func _seeker() -> void:
	if not Players.is_seated(KID):
		return
	var d := Players.dir4_just_pressed(KID)
	if d != Vector2i.ZERO:
		var to := graph.hop(paw_spot, d)
		if to != paw_spot:
			paw_spot = to
			Sfx.play("hop", 1.0 + 0.05 * (to % 4), -4.0)
		else:
			Sfx.play("hop", 0.8, -8.0)
		overlay.paw_bump = 0.15
	if Players.just_pressed(KID, "a"):
		lift(paw_spot)


## The spot under the flashlight, or -1.
func spot_under_light() -> int:
	var best := -1
	var best_d := UNDER_LIGHT
	var lp := Vector2(LightMask.snap(light_pos))
	for i in spots.size():
		var d := lp.distance_to(Vector2(spots[i].pos))
		if d <= best_d:
			best_d = d
			best = i
	return best


func _flashlight_lift(dt: float) -> void:
	if Players.is_seated(KID):
		dwell_t = 0.0
		return
	var under := spot_under_light()
	if Players.just_pressed(ADULT, "a") and under != -1:
		lift(under)
		_dwell_done_spot = under
		dwell_t = 0.0
		return
	if under != dwell_spot:
		dwell_spot = under
		dwell_t = 0.0
		if under != _dwell_done_spot:
			_dwell_done_spot = -1
	if under == -1 or under == _dwell_done_spot or spots[under].open > 0.0:
		dwell_t = 0.0
		return
	dwell_t += dt
	if dwell_t >= DWELL:
		lift(under)
		_dwell_done_spot = under
		dwell_t = 0.0


## Lift a spot. A toy hops out and flies to the basket; an empty spot always
## gives a small surprise. Returns {"toy": name} or {"surprise": kind}, or
## {} while the spot is still open from the last lift.
func lift(i: int) -> Dictionary:
	if i < 0 or i >= spots.size():
		return {}
	var s: Dictionary = spots[i]
	if s.open > 0.0:
		overlay.paw_bump = 0.15
		return {}
	s.open = OPEN_TIME
	lift_count += 1
	Sfx.play("lift", rng.randf_range(0.9, 1.1))
	if s.toy != "":
		var toy: String = s.toy
		s.toy = ""
		s.found = true
		found.append(toy)
		since_find = 0.0
		hint_spot = -1
		cheer_t = 1.2
		Sfx.play("toy_found")
		_launch_toy(toy, Vector2(s.pos) + Vector2(0, -6), false)
		overlay.burst(Vector2(s.pos) + Vector2(0, -10), C_WARM, "heart")
		if found.size() >= TOY_COUNT:
			round_over = true
		return {"toy": toy}
	var kind := _next_surprise()
	surprise_count += 1
	var n := _spr(kind, C_WARM, Vector2i(8, 8), self)
	n.z_index = _spot_z(i) + 2
	var base := Vector2(s.pos) + Vector2(0, -6)
	n.position = base
	surprises.append({"node": n, "t": 0.0, "dur": 1.8, "base": base})
	Sfx.play("mouse_squeak" if kind == "sleepy_mouse" else "surprise", rng.randf_range(0.95, 1.08))
	return {"surprise": kind}


func _next_surprise() -> String:
	if _surprise_bag.is_empty():
		_surprise_bag.assign(SURPRISES)
		for k in range(_surprise_bag.size() - 1, 0, -1):
			var j := rng.randi_range(0, k)
			var tmp := _surprise_bag[k]
			_surprise_bag[k] = _surprise_bag[j]
			_surprise_bag[j] = tmp
	return _surprise_bag.pop_back()


func _launch_toy(toy: String, from: Vector2, walk: bool) -> void:
	var n := _spr(toy, TOY_TINTS.get(toy, C_WARM), Vector2i(16, 16), self)
	n.z_index = 90
	n.position = from
	var slot := found.size() - 1 if not walk else basket.size() + flying.size()
	flying.append({"node": n, "toy": toy, "from": from, "to": basket_slot(slot), "t": 0.0,
		"dur": 2.2 if walk else 1.0, "walk": walk})


## Where the k-th toy sits in the basket: two rows peeking over the rim.
func basket_slot(k: int) -> Vector2:
	var row := 1 - (k / 4) % 2
	var col := k % 4
	return Vector2(Layout.BASKET_POS) + Vector2(-9 + col * 6, -12 + row * 4)


func _update_flying(dt: float) -> void:
	for i in range(flying.size() - 1, -1, -1):
		var f: Dictionary = flying[i]
		f.t += dt
		var k := clampf(f.t / f.dur, 0.0, 1.0)
		var p: Vector2 = f.from.lerp(f.to, k)
		if f.walk:
			p.y -= absf(sin(f.t * 9.0)) * 4.0  # little hops, waving
		else:
			p.y -= sin(k * PI) * 34.0 + (6.0 if k < 0.15 else 0.0)
		f.node.position = p.round()
		if k >= 1.0:
			f.node.queue_free()
			flying.remove_at(i)
			_arrive(f.toy)


func _arrive(toy: String) -> void:
	basket.append(toy)
	if not found.has(toy):
		found.append(toy)
	var k := basket.size() - 1
	var n := _spr(toy, TOY_TINTS.get(toy, C_WARM), Vector2i(16, 16), self)
	n.stop()
	n.frame = 0
	n.position = basket_slot(k)
	n.z_index = 60 + (1 if k % 8 >= 4 else 0)
	basket_nodes.append(n)
	Sfx.play("basket_plop", 1.0 + 0.04 * k)
	overlay.burst(Vector2(Layout.BASKET_POS) + Vector2(0, -14), C_WARM, "sparkle")


func _update_surprises(dt: float) -> void:
	for i in range(surprises.size() - 1, -1, -1):
		var s: Dictionary = surprises[i]
		s.t += dt
		var up := minf(s.t / 0.25, 1.0)
		s.node.position = (s.base + Vector2(0, -10.0 * up)).round()
		s.node.visible = s.t < s.dur - 0.2 or int(s.t * 12.0) % 2 == 0
		if s.t >= s.dur:
			s.node.queue_free()
			surprises.remove_at(i)


func _hint() -> void:
	if hint_spot != -1 or since_find < HINT_AFTER:
		return
	var from := Vector2(spots[paw_spot].pos) if Players.is_seated(KID) else light_pos
	var best_d := INF
	for i in spots.size():
		if spots[i].toy == "":
			continue
		var d := from.distance_to(Vector2(spots[i].pos))
		if d < best_d:
			best_d = d
			hint_spot = i
	if hint_spot != -1:
		Sfx.play("hint_glow")


func _peekaboo(dt: float) -> void:
	var result := {}
	if Players.is_seated(TODDLER):
		if Players.just_pressed(TODDLER, "any"):
			result = director.press(spots, light_pos)
			if result.has("twinkle"):
				twinkle_t = 0.5
				Sfx.play("twinkle", rng.randf_range(0.95, 1.1), -2.0)
				overlay.burst(Vector2(Layout.FAIRY[rng.randi() % 2]), C_GREEN, "sparkle")
	elif state == State.RUN:
		result = director.auto_step(dt, spots, light_pos, LightMask.FLASH_RADIUS - 6.0)
	if result.has("pop"):
		var f: Dictionary = result.pop
		Sfx.play("giggle", rng.randf_range(0.95, 1.1), -6.0)
		overlay.burst(Vector2(spots[f.spot].pos) + Vector2(0, 6), C_GREEN, "sparkle")
	for f in director.step(dt):
		Sfx.play("peekaboo", 1.0, -2.0)
		overlay.burst(Vector2(spots[f.spot].pos) + Vector2(0, -22), C_GREEN, "sparkle")


# ================================================================ ending

func _start_walkout() -> void:
	round_over = true
	state = State.WALKOUT
	walk_t = 0.0
	hint_spot = -1


func _walkout(dt: float) -> void:
	walk_t -= dt
	if walk_t <= 0.0:
		walk_t = WALK_EVERY
		for i in spots.size():
			var s: Dictionary = spots[i]
			if s.toy != "":
				var toy: String = s.toy
				s.toy = ""
				s.open = OPEN_TIME
				Sfx.play("lift", 1.05)
				_launch_toy(toy, Vector2(s.pos) + Vector2(0, -6), true)
				break
	var hidden := 0
	for s in spots:
		if s.toy != "":
			hidden += 1
	if hidden == 0 and flying.is_empty():
		_start_lamp()


func _start_lamp() -> void:
	state = State.LAMP
	lamp_t = 0.0
	lamp_spr.frame = 1
	cheer_t = LAMP_FADE + LAMP_STAY
	Sfx.play("lamp_on")


func _finish() -> void:
	state = State.DONE
	Game.toys_found = basket.duplicate()
	Game.round_time = time
	next_screen = "party"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("party")


## The dusk strength the mask uses this frame (never above 60%).
func mask_strength() -> float:
	return minf(strength, LightMask.MAX_STRENGTH)


# ================================================================ pause

## Pause belongs to the flashlight seat only. Returns true while paused.
func _pause_input() -> bool:
	if state != State.RUN:
		return false
	if Players.just_pressed(ADULT, "start"):
		_set_paused(not paused)
		return true
	if paused:
		if Players.just_pressed(ADULT, "a"):
			_set_paused(false)
		elif Players.just_pressed(ADULT, "b"):
			state = State.DONE
			Players.reset()
			next_screen = "join"
			if auto_goto:
				Game.goto.call_deferred("join")
	return paused


func _set_paused(on: bool) -> void:
	paused = on
	pause_overlay.visible = on
	Sfx.play("select")


# ================================================================ view

func _update_lights() -> void:
	lights.clear()
	var fade := 1.0 if state != State.LAMP else 1.0 - clampf(lamp_t / LAMP_FADE, 0.0, 1.0)
	lights.append({"pos": light_pos, "r": roundf(LightMask.FLASH_RADIUS * fade)})
	lights.append({"pos": Vector2(Layout.NIGHTLIGHT), "r": 16.0})
	lights.append({"pos": Vector2(Layout.MOON), "r": 22.0})
	var tw := 4.0 if twinkle_t > 0.0 else 0.0
	for k in 2:
		var pulse := 1.0 if int(time * 2.0 + k) % 2 == 0 else 0.0
		lights.append({"pos": Vector2(Layout.FAIRY[k]), "r": 12.0 + pulse + tw})
	var paw_r := 14.0 if Players.is_seated(KID) and state == State.RUN else 0.0
	lights.append({"pos": Vector2(spots[paw_spot].pos), "r": paw_r})
	var friend_light := {"pos": Vector2.ZERO, "r": 0.0}
	if not director.friends.is_empty():
		var f: Dictionary = director.friends[director.friends.size() - 1]
		friend_light = {"pos": Vector2(spots[f.spot].pos) + Vector2(0, -10), "r": 18.0}
	lights.append(friend_light)
	var hint_r := 0.0
	if hint_spot != -1:
		hint_r = 12.0 + (2.0 if int(time * 1.5) % 2 == 0 else 0.0)
	lights.append({"pos": Vector2(spots[maxi(hint_spot, 0)].pos), "r": hint_r})
	if mask_mat:
		var u := LightMask.uniforms(lights)
		mask_mat.set_shader_parameter("light_pos", u.light_pos)
		mask_mat.set_shader_parameter("light_radius", u.light_radius)
		mask_mat.set_shader_parameter("strength", mask_strength())


## Only the flashlight (slot 0) reveals toy tips.
func flash_amount(pos: Vector2) -> float:
	return LightMask.light_amount(pos, [lights[0]]) if not lights.is_empty() else 0.0


func _place_nodes() -> void:
	fort_spr.frame = 1 if twinkle_t > 0.0 or int(time * 1.5) % 2 == 0 else 0
	var friend_spots := {}
	for f in director.friends:
		friend_spots[f.spot] = true
	for i in spots.size():
		var s: Dictionary = spots[i]
		var n := spot_nodes[i]
		var lit: bool = s.toy != "" and flash_amount(Vector2(s.pos)) > 0.0
		var wiggle: bool = (lit or i == hint_spot) and int(time * 4.0) % 2 == 0
		n.frame = 2 if s.open > 0.0 else (1 if wiggle else 0)
		var tip := tip_nodes[i]
		tip.visible = s.toy != "" and s.open <= 0.0 and (lit or i == hint_spot or friend_spots.has(i))
		if tip.visible:
			var tname: String = "tip_" + s.toy
			var sf := Art.frames(tname, TOY_TINTS.get(s.toy, C_WARM), Vector2i(8, 8))
			if tip.sprite_frames != sf:
				tip.sprite_frames = sf
			var h: int = SPOT_SIZES[s.kind].y
			var peek := 1 if int(time * 2.0 + i) % 2 == 0 else 0
			tip.position = Vector2(s.pos) + Vector2(5 if i % 2 == 0 else -5, -h / 2 - 1 - peek)
	# Peekaboo friends rise from behind their spot.
	var alive := {}
	for f in director.friends:
		var key: int = f.id
		alive[key] = true
		var n: AnimatedSprite2D = friend_nodes.get(key)
		if n == null:
			n = _spr(f.kind, C_GREEN, Vector2i(24, 24), self)
			n.stop()
			n.z_index = _spot_z(f.spot) - 1
			friend_nodes[key] = n
		n.frame = Director.frame_at(f.t)
		var sp := Vector2(spots[f.spot].pos)
		n.position = (sp + Vector2(0, 6.0 - 18.0 * Director.rise_at(f.t))).round()
	for key in friend_nodes.keys():
		if not alive.has(key):
			friend_nodes[key].queue_free()
			friend_nodes.erase(key)
	# Riders cheer on finds and at the end.
	for k in rider_nodes.size():
		var r := rider_nodes[k]
		var seat_pos: Vector2 = r.get_meta("home", r.position)
		r.set_meta("home", seat_pos)
		var hop := 0.0
		if cheer_t > 0.0:
			hop = absf(sin(time * 9.0 + k * 1.3)) * 3.0
		r.position = seat_pos - Vector2(0, roundf(hop))
	# Basket fill and the toys dancing in it at the end.
	basket_spr.frame = 0 if basket.is_empty() else (1 if basket.size() < 6 else 2)
	for k in basket_nodes.size():
		var hop2 := 0.0
		if state == State.LAMP:
			hop2 = roundf(absf(sin(time * 7.0 + k)) * 3.0)
			basket_nodes[k].frame = 1 if int(time * 4.0 + k) % 2 == 0 else 0
		basket_nodes[k].position = basket_slot(k) - Vector2(0, hop2)
	paw.visible = Players.is_seated(KID) and state == State.RUN
	overlay.queue_redraw()


# ================================================================ light check

## `-- --lightcheck`: after the demo has moved the light a bit, freeze, switch
## the shader to its calibration output (white = lit) and compare every pixel
## of the rendered frame with LightMask.lit_pixel(). Needs a real display (xvfb).
func _light_check_step(delta: float) -> void:
	_light_check_t += delta
	if _light_check_t < 1.2:
		return
	_light_check_t = -1.0
	set_process(false)
	mask_mat.set_shader_parameter("debug_mode", 1)
	overlay.visible = false  # the paw and sparkles draw above the mask
	for i in 3:
		await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var sx := float(img.get_width()) / W
	var sy := float(img.get_height()) / H
	var bad := 0
	var lit_n := 0
	for y in H:
		for x in W:
			var c := img.get_pixel(int((x + 0.5) * sx), int((y + 0.5) * sy))
			var gpu := c.r > 0.5
			var cpu := LightMask.lit_pixel(Vector2i(x, y), lights)
			if cpu:
				lit_n += 1
			if gpu != cpu:
				bad += 1
				if bad <= 12:
					print("  differ at %d,%d gpu=%s cpu=%s amount=%.3f bayer=%.3f" % [x, y, gpu, cpu,
						LightMask.light_amount(Vector2(x, y), lights), LightMask.bayer(Vector2i(x, y))])
	var total := W * H
	if bad == 0:
		print("LIGHT CHECK OK %d/%d pixels agree (%d lit, image %dx%d)" % [total, total, lit_n, img.get_width(), img.get_height()])
	else:
		print("LIGHT CHECK FAIL %d/%d pixels differ (%d lit by the mirror)" % [bad, total, lit_n])
	get_tree().quit()


# ================================================================ drawn layers

## Above the dusk: the flashlight's thin blue rim, the paw, sparkles and hearts.
class Overlay extends Node2D:
	var fort: Node
	var paw_bump := 0.0
	var fx: Array[Dictionary] = []  # {node, vel, t}

	func burst(at: Vector2, tint: Color, sprite_name: String) -> void:
		for k in 5:
			var s := Art.sprite(sprite_name, tint, Vector2i(8, 8))
			if sprite_name == "sparkle":
				s.modulate = tint
			add_child(s)
			s.position = at.round()
			var a := -PI / 2 + (k - 2) * 0.55
			fx.append({"node": s, "pos": at, "vel": Vector2(cos(a), sin(a)) * 26.0, "t": 0.0})

	func _process(delta: float) -> void:
		paw_bump = maxf(0.0, paw_bump - delta)
		for i in range(fx.size() - 1, -1, -1):
			var f: Dictionary = fx[i]
			f.t += delta
			f.pos += f.vel * delta
			f.vel *= 0.9
			f.node.position = f.pos.round()
			if f.t > 0.8:
				f.node.queue_free()
				fx.remove_at(i)
		if fort and fort.paw:
			var sp: Vector2 = Vector2(fort.spots[fort.paw_spot].pos)
			var bob := 1 if int(fort.time * 3.0) % 2 == 0 else 0
			fort.paw.position = sp + Vector2(7, 5 - bob - (2 if paw_bump > 0.0 else 0))

	func _draw() -> void:
		if fort == null or fort.state != 0:
			return
		# Thin dotted blue rim: the adult's light.
		var c := Vector2(LightMask.snap(fort.light_pos))
		var r := LightMask.FLASH_RADIUS + 1.0
		var n := 72
		for k in n:
			if k % 2 == 1:
				continue
			var a: float = TAU * k / n + fort.time * 0.4
			var p := (c + Vector2(cos(a), sin(a)) * r).floor()
			draw_rect(Rect2(p, Vector2(1, 1)), Color(C_BLUE_RIM, 0.85))
		# The dwell ring fills while the light rests on a spot (solo play).
		if fort.dwell_t > 0.0 and fort.dwell_spot != -1:
			var sp := Vector2(fort.spots[fort.dwell_spot].pos)
			var frac: float = clampf(fort.dwell_t / DWELL, 0.0, 1.0)
			var m := 24
			for k in int(m * frac):
				var a: float = -PI / 2 + TAU * k / m
				draw_rect(Rect2((sp + Vector2(cos(a), sin(a)) * 13.0).floor(), Vector2(2, 2)), C_WARM)


## Pause: a soft plum veil, a back arrow (flashlight "b") and a play triangle.
class PauseOverlay extends Node2D:
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 320, 180), Color(0.36, 0.15, 0.36, 0.55))
		draw_circle(Vector2(110, 90), 22, Color("#b13e53"))
		draw_colored_polygon(PackedVector2Array([Vector2(98, 90), Vector2(110, 78), Vector2(110, 85),
			Vector2(121, 85), Vector2(121, 95), Vector2(110, 95), Vector2(110, 102)]), Color("#f4f4f4"))
		draw_circle(Vector2(210, 90), 26, Color("#38b764"))
		draw_colored_polygon(PackedVector2Array([Vector2(202, 76), Vector2(222, 90), Vector2(202, 104)]),
			Color("#f4f4f4"))
