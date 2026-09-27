extends Node2D
## Stage 1, the stable. The mare stands big in her stall, muddy after a night
## in the paddock; the foal peeks over the half-door.
##
## - Foal seat (5-year-old): a direction hops the brush to the nearest mud
##   patch that way; holding A scrubs (a patch fades in about 2 s). Once she
##   is clean, a direction picks the braid ribbon (up red, right blue, down
##   yellow, left purple).
## - NEIGH seat (2-year-old): any press offers a carrot; every third one the
##   foal pokes its head in and steals it. Hearts and a neigh.
## - Rider (adult): a hand cursor; A on a hoof picks it (she lifts it, a pebble
##   pops out, the shoe glints); with all four done, A on the saddle rack puts
##   the saddle and bridle on.
## - Clean + saddled + ribbon: the stall door swings open and the day goes on
##   to the trail. After 90 s the stable cat helps with whatever is left.
## Seats that are missing or idle for 5 s are helped: the brush scrubs by
## itself (slowly with no 5-year-old), the hand goes to the next hoof, and
## the mare neighs on her own at the fun moments when there is no toddler.

const Grooming := preload("res://scripts/logic/grooming.gd")
const AnimSprite := preload("res://scripts/view/anim_sprite.gd")
const Tex := preload("res://scripts/view/tex.gd")
const Pause := preload("res://scripts/view/pause.gd")
const LoopAudio := preload("res://scripts/view/loop_audio.gd")

const MARE_AT := Vector2(118, 84)           # top-left of the 80x64 mare
const FLOOR_Y := 148
const RACK_AT := Vector2(52, 94)            # the saddle rack (top-left, 24x24)
const HALF_DOOR_AT := Vector2(4, 124)
const HAY_AT := Vector2(212, 88)
const TROUGH_AT := Vector2(246, 136)
const BRUSH_REST := Vector2(158, 164)
const HAND_SPEED := 95.0
const CARROT_COOLDOWN := 0.5
const CARROT_FLIGHT := 0.45
const DOOR_TIME := 2.4
const WIPE_TIME := 0.8
const DEFAULT_PATCH_SIZE := {"head": Vector2i(12, 10), "back": Vector2i(20, 10), "legs": Vector2i(16, 12), "tail": Vector2i(12, 14)}
const DEFAULT_PATCHES := {"head": Vector2(62, 8), "back": Vector2(26, 18), "legs": Vector2(18, 44), "tail": Vector2(0, 16)}
const DEFAULT_HOOVES: Array[Vector2] = [Vector2(62, 63), Vector2(54, 63), Vector2(18, 63), Vector2(10, 63)]

var auto_goto := true
var next_screen := ""
var time := 0.0
var groom: Grooming
var hand := Vector2(90, 120)
var done_t := -1.0              # time since everything was ready (the door and the wipe)
var foal_idle := 0.0
var rider_idle := 0.0
var _auto_hop_t := 0.0
var _scrub_sfx_t := 0.0
var _carrot_cool := 0.0
var _carrots: Array[Dictionary] = []     # flying carrots {t, to, who}
var _hearts: Array[Dictionary] = []      # {pos, t}
var _sparks: Array[Dictionary] = []      # {pos, t, v}
var _pebbles: Array[Dictionary] = []     # {pos, v, t}
var _glints: Array[Dictionary] = []      # {pos, t}
var _mare_anim := "idle"
var _mare_anim_t := 0.0
var _hoof_lift := -1
var _foal_poke := 0.0
var _saddle_fly := -1.0
var _saddle_nope := 0.0
var _ribbon_t := -1.0          # time since clean (the braid auto-pick)
var _cat_x := 340.0
var _cat_target := Vector2(250, FLOOR_Y)
var _cat_t := 0.0
var _scrubbing := false
var _patch_names: Array[String] = []
var _patch_tl: Array[Vector2] = []
var _patch_size: Array[Vector2i] = []

var _mare: AnimSprite
var _tack: Sprite2D
var _foal: AnimSprite
var _mud: Array[Sprite2D] = []
var _brush: AnimatedSprite2D
var _hand: AnimatedSprite2D
var _cat: AnimSprite
var _ribbon: Sprite2D
var _pause: Node2D
var _music_on := false


func _ready() -> void:
	_build_groom()
	_build_nodes()
	_pause = Pause.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	Sfx.music("music_stable")


func _build_groom() -> void:
	var table := Tex.point_table("mare_big", "patches")
	var patches: Array[Vector2] = []
	for n in Grooming.PATCHES:
		var tl: Vector2 = table.get(n, DEFAULT_PATCHES[n])
		var sz := Art.size_of("mud_" + n, DEFAULT_PATCH_SIZE[n])
		_patch_names.append(n)
		_patch_tl.append(MARE_AT + tl)
		_patch_size.append(sz)
		patches.append(MARE_AT + tl + Vector2(sz) * 0.5)
	var hooves: Array[Vector2] = []
	var hp := Tex.point_list("mare_big", "hooves")
	for i in 4:
		hooves.append(MARE_AT + (hp[i] if i < hp.size() else DEFAULT_HOOVES[i]))
	groom = Grooming.new(patches, hooves, RACK_AT + Vector2(12, 8), BRUSH_REST)
	groom.cat_at = Grooming.CAT_AT * Game.day_scale


func _build_nodes() -> void:
	var stage := Stall.new()
	stage.screen = self
	stage.z_index = -10
	add_child(stage)
	# The foal peeks over the half-door (drawn behind it).
	_foal = AnimSprite.new()
	_foal.setup("foal_" + Game.foal_coat, "foal", Vector2i(24, 20), Game.coat_color(Game.foal_coat))
	_foal.position = HALF_DOOR_AT + Vector2(16, 10)
	_foal.z_index = -2
	add_child(_foal)
	var door := Sprite2D.new()
	door.name = "HalfDoor"
	door.centered = false
	door.texture = Tex.frame("half_door", 0, Color("#b86f50"), Vector2i(32, 24))
	door.position = HALF_DOOR_AT
	door.z_index = -1
	add_child(door)
	_mare = AnimSprite.new()
	_mare.setup("mare_big_" + Game.mare_coat, "mare_big", Vector2i(80, 64), Game.coat_color(Game.mare_coat))
	_mare.play("idle")
	_mare.position = MARE_AT + Vector2(40, 64)
	add_child(_mare)
	for i in 4:
		var m := Sprite2D.new()
		m.centered = false
		m.position = _patch_tl[i]
		m.z_index = 2
		add_child(m)
		_mud.append(m)
	_tack = Sprite2D.new()
	_tack.centered = false
	_tack.position = MARE_AT
	_tack.z_index = 3
	_tack.visible = false
	add_child(_tack)
	_ribbon = Sprite2D.new()
	_ribbon.centered = true
	_ribbon.z_index = 4
	_ribbon.visible = false
	add_child(_ribbon)
	_cat = AnimSprite.new()
	_cat.setup("stable_cat", "stable_cat", Vector2i(16, 12), Color("#f77622"))
	_cat.play("walk")
	_cat.position = Vector2(_cat_x, FLOOR_Y)
	_cat.flip_h = true
	_cat.z_index = 5
	_cat.visible = false
	add_child(_cat)
	_brush = Art.sprite("brush", Players.SEAT_COLORS[1], Vector2i(16, 12))
	_brush.z_index = 20
	add_child(_brush)
	_hand = Art.sprite("hand", Players.SEAT_COLORS[0], Vector2i(12, 12))
	_hand.stop()
	_hand.z_index = 21
	add_child(_hand)
	_refresh()


# ---------------------------------------------------------------- frame

func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if _pause.check():
		return
	time += dt
	if done_t >= 0.0:
		done_t += dt
		_tick_fx(dt)
		_refresh()
		if done_t >= DOOR_TIME + WIPE_TIME and next_screen == "":
			_finish()
		return
	_toddler(dt)
	_foal_seat(dt)
	_rider(dt)
	var did := groom.cat_step(time, dt)
	if did != "":
		_cat_did(did)
	if groom.ready_to_go():
		done_t = 0.0
		Sfx.play("door_creak")
		_neigh(false)
	_tick_fx(dt)
	_refresh()


# ---------------------------------------------------------------- the toddler: carrots

func _toddler(dt: float) -> void:
	_carrot_cool = maxf(0.0, _carrot_cool - dt)
	if not Game.neigh_pressed():
		return
	if _carrot_cool > 0.0:
		_hearts.append({"pos": _mouth() + Vector2(0, -6), "t": 0.0})
		Sfx.play("nicker", 1.1, -4.0)
		return
	_carrot_cool = CARROT_COOLDOWN
	var who := groom.give_carrot()
	Game.day.carrots = groom.carrots
	var to := _foal_mouth() if who == "foal" else _mouth()
	_carrots.append({"t": 0.0, "to": to, "who": who, "from": Vector2(300, 176)})
	if who == "foal":
		_foal_poke = 1.4
	_neigh(who == "foal")


func _neigh(foal_too: bool) -> void:
	Sfx.play("neigh", 1.0, -2.0)
	if foal_too:
		Sfx.play("foal_neigh", 1.0, -3.0)
	if _mare_anim == "idle":
		_set_mare("ear", 0.7)


func _mouth() -> Vector2:
	return MARE_AT + Tex.point("mare_big", "mouth", -1, Vector2(76, 22))


func _foal_mouth() -> Vector2:
	return _foal.position + Vector2(10, -12)


# ---------------------------------------------------------------- the 5-year-old: the brush and the braid

func _foal_seat(dt: float) -> void:
	var seated := not Game.foal_auto()
	var flick := Players.dir4_just_pressed(Players.Seat.GUNNER) if seated else Vector2i.ZERO
	var holding := seated and Players.pressed(Players.Seat.GUNNER, "a")
	if flick != Vector2i.ZERO or holding:
		foal_idle = 0.0
	else:
		foal_idle += dt
	_scrubbing = false
	if groom.all_clean():
		if _ribbon_t < 0.0:
			_ribbon_t = 0.0
		_ribbon_t += dt
		if flick != Vector2i.ZERO:
			var r := Grooming.ribbon_for(flick)
			if r != -1:
				_choose_ribbon(r)
		elif groom.ribbon == -1 and _ribbon_t >= (Grooming.IDLE_ASSIST if seated else 1.5):
			_choose_ribbon(int(time * 7.0) % 4)
		return
	var auto := not seated or foal_idle >= Grooming.IDLE_ASSIST
	if flick != Vector2i.ZERO:
		if groom.move_brush(flick) != -1:
			Sfx.play("whoosh", 1.6, -12.0)
	if holding:
		_scrub(dt, 1.0)
	elif auto:
		_auto_hop_t += dt
		if groom.brush == -1 or groom.is_clean(groom.brush):
			if _auto_hop_t >= 0.6:
				_auto_hop_t = 0.0
				groom.brush = groom.next_dirty()
		else:
			_scrub(dt, Grooming.SLOW_SCRUB if not seated else 0.7)


func _scrub(dt: float, speed: float) -> void:
	if groom.brush == -1:
		groom.brush = groom.next_dirty()
		if groom.brush == -1:
			return
	_scrubbing = true
	_scrub_sfx_t -= dt
	if _scrub_sfx_t <= 0.0:
		_scrub_sfx_t = 0.3
		Sfx.play("brush_scrub", 0.9 + 0.2 * randf(), -4.0)
		_sparks.append({"pos": groom.brush_pos() + Vector2(randf_range(-6, 6), randf_range(-4, 4)), "t": 0.0,
			"v": Vector2(randf_range(-10, 10), -14)})
	if groom.scrub(dt, speed):
		_patch_cleared(groom.brush)


func _patch_cleared(i: int) -> void:
	Sfx.play("mud_poof")
	for k in 6:
		_sparks.append({"pos": groom.patch_pos[i], "t": 0.0, "v": Vector2(cos(k * 1.05), sin(k * 1.05)) * 22.0})
	if not Game.has_toddler():
		_neigh(false)


func _choose_ribbon(r: int) -> void:
	var first := groom.ribbon == -1
	groom.pick_ribbon(r)
	Game.day.ribbon = r
	Sfx.play("ready" if first else "select", 1.0 + 0.1 * r)
	for k in 4:
		_sparks.append({"pos": _braid_pos(), "t": 0.0, "v": Vector2(cos(k * 1.57), sin(k * 1.57)) * 16.0})


func _braid_pos() -> Vector2:
	return MARE_AT + Tex.point("mare_big", "braid", -1, Vector2(58, 12))


# ---------------------------------------------------------------- the adult: hooves and saddle

func _rider(dt: float) -> void:
	var mv := Players.move(Players.Seat.DRIVER)
	var press := Players.just_pressed(Players.Seat.DRIVER, "a")
	if mv != Vector2.ZERO or press:
		rider_idle = 0.0
	else:
		rider_idle += dt
	if rider_idle >= Grooming.IDLE_ASSIST:
		var tg := groom.next_target()
		if not tg.is_empty():
			var to: Vector2 = tg.pos - hand
			if to.length() > 2.0:
				hand += to.normalized() * minf(HAND_SPEED * 0.6 * dt, to.length())
			else:
				press = true
	else:
		hand += mv * HAND_SPEED * dt
		# A gentle magnet onto the nearest spot while the stick rests.
		if mv == Vector2.ZERO:
			var near := groom.hotspot_at(hand, 14.0)
			if not near.is_empty():
				var p: Vector2 = groom.hoof_pos[near.i] if near.kind == "hoof" else groom.saddle_pos
				hand = hand.move_toward(p, 40.0 * dt)
	hand = hand.clamp(Vector2(6, 40), Vector2(314, 174))
	if press:
		use_hand()


## The adult's A: pick the hoof or put the saddle on (whatever is under the hand).
func use_hand() -> void:
	var spot := groom.hotspot_at(hand, 12.0)
	if spot.is_empty():
		return
	if spot.kind == "hoof":
		if groom.pick_hoof(spot.i):
			_hoof_picked(spot.i)
	else:
		if groom.put_saddle():
			_saddle_fly = 0.0
			Sfx.play("saddle_creak")
			if not Game.has_toddler():
				_neigh(false)
		else:
			_saddle_nope = 0.4
			Sfx.play("snort", 1.2, -6.0)


func _hoof_picked(i: int) -> void:
	_hoof_lift = i
	_set_mare("hoof", 1.2)
	_mare.hold_index = i
	Sfx.play("hoof_pick_ping")
	var hp: Vector2 = groom.hoof_pos[i]
	_pebbles.append({"pos": hp + Vector2(0, -4), "v": Vector2(randf_range(-30, 30), -60), "t": 0.0})
	_glints.append({"pos": hp + Vector2(0, -3), "t": -0.35})


func _set_mare(anim_name: String, dur: float) -> void:
	_mare_anim = anim_name
	_mare_anim_t = dur
	_mare.play(anim_name, true)


# ---------------------------------------------------------------- the stable cat

func _cat_did(what: String) -> void:
	_cat.visible = true
	match what:
		"cat_arrives":
			Sfx.play("stable_cat_meow")
			_cat_target = Vector2(250, FLOOR_Y)
		"patch":
			_cat_target = Vector2(clampf(groom.patch_pos[groom.cat_last].x, 20, 300), FLOOR_Y)
			_patch_sparkle_all()
			Sfx.play("stable_cat_meow", 1.2, -4.0)
		"hoof":
			_cat_target = Vector2(clampf(groom.hoof_pos[groom.cat_last].x + 10, 20, 300), FLOOR_Y)
			_hoof_picked(groom.cat_last)
			Sfx.play("stable_cat_meow", 1.1, -4.0)
		"saddle":
			_saddle_fly = 0.0
			Sfx.play("saddle_creak")
		"ribbon":
			Game.day.ribbon = groom.ribbon
			Sfx.play("ready")


func _patch_sparkle_all() -> void:
	for i in 4:
		if groom.is_clean(i):
			_sparks.append({"pos": groom.patch_pos[i], "t": 0.0, "v": Vector2(0, -16)})
	Sfx.play("mud_poof")


# ---------------------------------------------------------------- effects and view

func _tick_fx(dt: float) -> void:
	_mare.tick(dt)
	_foal.tick(dt)
	if _cat.visible:
		_cat.tick(dt)
	if _mare_anim_t > 0.0:
		_mare_anim_t -= dt
		if _mare_anim_t <= 0.0:
			_mare_anim = "idle"
			_mare.play("idle")
			_hoof_lift = -1
	_foal_poke = maxf(0.0, _foal_poke - dt)
	_saddle_nope = maxf(0.0, _saddle_nope - dt)
	if _saddle_fly >= 0.0 and _saddle_fly < 1.0:
		_saddle_fly = minf(1.0, _saddle_fly + dt / 0.5)
	for c in _carrots:
		c.t += dt
		if c.t >= CARROT_FLIGHT and not c.get("eaten", false):
			c.eaten = true
			Sfx.play("munch")
			_hearts.append({"pos": c.to + Vector2(-4, -8), "t": 0.0})
			_hearts.append({"pos": c.to + Vector2(4, -10), "t": -0.15})
			if c.who == "mare":
				_set_mare("munch", 1.2)
	_carrots = _carrots.filter(func(c): return c.t < CARROT_FLIGHT + 0.05)
	for h in _hearts:
		h.t += dt
		h.pos.y -= 14.0 * dt
	_hearts = _hearts.filter(func(h): return h.t < 1.2)
	for s in _sparks:
		s.t += dt
		s.pos += s.v * dt
	_sparks = _sparks.filter(func(s): return s.t < 0.6)
	for p in _pebbles:
		p.t += dt
		p.v.y += 200.0 * dt
		p.pos += p.v * dt
	_pebbles = _pebbles.filter(func(p): return p.t < 0.8)
	for g in _glints:
		g.t += dt
	_glints = _glints.filter(func(g): return g.t < 1.2)
	if _cat.visible:
		var cx := move_toward(_cat.position.x, _cat_target.x, 60.0 * dt)
		_cat.flip_h = _cat_target.x < _cat.position.x
		_cat.play("walk" if absf(cx - _cat.position.x) > 0.01 else "sit")
		_cat.position = Vector2(roundf(cx), FLOOR_Y + 12)
	queue_redraw()


func _refresh() -> void:
	for i in 4:
		var st := groom.fade_stage(i)
		_mud[i].visible = st < 4
		if st < 4:
			_mud[i].texture = Tex.frame("mud_" + _patch_names[i], st, Color("#733e39"), _patch_size[i])
	_tack.visible = groom.saddled and _saddle_fly >= 1.0
	if _tack.visible:
		_tack.texture = Tex.frame("mare_big_tack", _mare.current_frame(), Color("#733e39"), Vector2i(80, 64))
	_ribbon.visible = groom.ribbon != -1
	if _ribbon.visible:
		_ribbon.texture = Tex.frame("ribbon_" + Game.RIBBONS[groom.ribbon], 0, Color("#e43b44"), Vector2i(8, 8))
		_ribbon.position = _braid_pos()
	# The brush sits on its patch (wiggling while it scrubs); the hand on its spot.
	var bp := groom.brush_pos()
	if _scrubbing:
		bp += Vector2(1 if int(time * 16.0) % 2 == 0 else -1, 0)
		_brush.frame = int(time * 10.0) % 2
	_brush.position = bp.round()
	_brush.visible = done_t < 0.0
	_hand.position = hand.round() + Vector2(2, 4)
	_hand.frame = 1 if not groom.hotspot_at(hand, 12.0).is_empty() else 0
	_hand.visible = done_t < 0.0
	_foal.position = HALF_DOOR_AT + Vector2(16, 10 - (6 if _foal_poke > 0.0 else 0))
	_foal.play("neigh" if _foal_poke > 0.8 else "stand")
	var door := get_node_or_null("HalfDoor") as Sprite2D
	if door:
		var f := 0
		if done_t >= 0.0:
			f = 1 if done_t < 0.35 else 2
		if f > 0 and Art.has("stall_door"):
			door.texture = Tex.frame("stall_door", f, Color("#b86f50"), Vector2i(32, 48))
			door.position = HALF_DOOR_AT + Vector2(0, -24)
		elif f > 0:
			door.visible = false


func _draw() -> void:
	# Carrots in flight, hearts, sparkles, pebbles, the saddle flying on,
	# the ribbon picker, the glinting new shoes, the wipe.
	for c in _carrots:
		var k := clampf(c.t / CARROT_FLIGHT, 0.0, 1.0)
		var p: Vector2 = c.from.lerp(c.to, k) + Vector2(0, -30.0 * sin(PI * k))
		draw_texture(Tex.frame("carrot", 0, Color("#f77622"), Vector2i(12, 8)), (p - Vector2(6, 4)).round())
	for h in _hearts:
		if h.t >= 0.0:
			draw_texture(Tex.frame("heart", 0, Color("#e43b44"), Vector2i(8, 8)), (h.pos - Vector2(4, 4)).round())
	for s in _sparks:
		draw_texture(Tex.frame("sparkle", int(s.t * 8.0), Color("#ffffff"), Vector2i(8, 8)), (s.pos - Vector2(4, 4)).round())
	for p in _pebbles:
		draw_texture(Tex.frame("pebble", 0, Color("#8b9bb4"), Vector2i(4, 4)), (p.pos - Vector2(2, 2)).round())
	for g in _glints:
		if g.t >= 0.0:
			draw_texture(Tex.frame("horseshoe", 1 if int(g.t * 6.0) % 2 == 0 else 0, Color("#c0cbdc"), Vector2i(8, 8)),
				(g.pos - Vector2(4, 8)).round())
	# The saddle: on its rack, flying to her back, then part of the tack overlay.
	var saddle_tex := Tex.frame("saddle", 0, Color("#733e39"), Vector2i(24, 16))
	var rack_p := RACK_AT + Vector2(0, -6)
	if not groom.saddled:
		var wig := Vector2(1 if int(_saddle_nope * 30.0) % 2 == 0 else -1, 0) if _saddle_nope > 0.0 else Vector2.ZERO
		draw_texture(saddle_tex, rack_p + wig)
		draw_texture(Tex.frame("bridle", 0, Color("#733e39"), Vector2i(16, 16)), RACK_AT + Vector2(28, -8))
	elif _saddle_fly < 1.0:
		var to := MARE_AT + Tex.point("mare_big", "saddle", -1, Vector2(34, 12)) - Vector2(12, 8)
		var p2 := rack_p.lerp(to, _saddle_fly) + Vector2(0, -24.0 * sin(PI * _saddle_fly))
		draw_texture(saddle_tex, p2.round())
	# The HUD: four shoes (shiny once picked) and the carrots given.
	for i in 4:
		var shiny: bool = groom.hooves[i]
		var tex := Tex.frame("horseshoe", 0, Color("#c0cbdc"), Vector2i(8, 8))
		draw_texture(tex, Vector2(6 + i * 10, 4), Color.WHITE if shiny else Color(0.35, 0.3, 0.4, 0.9))
	for i in mini(groom.carrots, 12):
		draw_texture(Tex.frame("carrot", 0, Color("#f77622"), Vector2i(12, 8)), Vector2(306 - i * 8, 4))
	# The ribbon picker once she is clean (4 bows around the Foal seat's cross).
	if groom.all_clean() and done_t < 0.0:
		var c := Vector2(160, 30)
		draw_circle(c, 17, Color(Players.SEAT_COLORS[1], 0.35))
		var at := [Vector2(0, -11), Vector2(11, 0), Vector2(0, 11), Vector2(-11, 0)]
		for r in 4:
			var p3: Vector2 = c + at[r]
			if r == groom.ribbon:
				draw_rect(Rect2(p3 - Vector2(6, 6), Vector2(12, 12)), Color("#ffffff"))
			draw_texture(Tex.frame("ribbon_" + Game.RIBBONS[r], 0, Color("#e43b44"), Vector2i(8, 8)), p3 - Vector2(4, 4))
	if done_t >= DOOR_TIME:
		var w := clampf((done_t - DOOR_TIME) / WIPE_TIME, 0.0, 1.0) * 320.0
		draw_rect(Rect2(0, 0, roundf(w), 180), Color("#e4a672"))


func _finish() -> void:
	Game.day.ribbon = groom.ribbon
	next_screen = Game.next_after("stable")
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")


## The stall: plank walls, straw floor, a window, the hay rack, the trough.
class Stall extends Node2D:
	var screen: Node2D

	func _draw() -> void:
		var wall := Tex.frame("stall_wall", 0, Color("#b86f50"), Vector2i(16, 16))
		var floor_t := Tex.frame("stall_floor", 0, Color("#e4a672"), Vector2i(16, 16))
		for y in range(0, FLOOR_Y, 16):
			for x in range(0, 320, 16):
				draw_texture(wall, Vector2(x, y))
		for y in range(FLOOR_Y, 180, 16):
			for x in range(0, 320, 16):
				draw_texture(floor_t, Vector2(x, y))
		# A window with morning light (above the mare), and a beam.
		draw_rect(Rect2(142, 20, 36, 26), Color("#733e39"))
		draw_rect(Rect2(144, 22, 32, 22), Color("#2ce8f5"))
		draw_rect(Rect2(159, 22, 2, 22), Color("#733e39"))
		draw_rect(Rect2(144, 32, 32, 2), Color("#733e39"))
		# The stall's doorway behind the half-door: the morning outside.
		draw_rect(Rect2(HALF_DOOR_AT.x - 2, 98, 36, 50), Color("#733e39"))
		draw_rect(Rect2(HALF_DOOR_AT.x, 100, 32, 26), Color("#2ce8f5"))
		draw_rect(Rect2(HALF_DOOR_AT.x, 126, 32, 22), Color("#63c74d"))
		draw_texture(Tex.frame("hay_rack", 0, Color("#e4a672"), Vector2i(24, 16)), HAY_AT)
		draw_texture(Tex.frame("water_trough", 0, Color("#124e89"), Vector2i(32, 12)), TROUGH_AT)
		draw_texture(Tex.frame("saddle_rack", 0, Color("#733e39"), Vector2i(24, 24)), RACK_AT)
		draw_texture(Tex.frame("lantern", 0, Color("#feae34"), Vector2i(8, 12)), Vector2(100, 40))
