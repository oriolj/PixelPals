extends Node2D
## Party: "dinner time" in the kitchen (both cats eating, everyone cheering,
## confetti), then a group cuddle on the sofa (hearts), then bedtime: the two
## cats curl up at the foot of the bed and everyone says goodnight. A photo
## strip of the day's finds (each cat in the spot where it was found) runs
## along the bottom during dinner and the cuddle. Then back to select; the
## walker's "a" skips ahead after SKIP_GUARD.

const Hat := preload("res://scripts/hat.gd")

const CUDDLE_AT := 6.0
const BED_AT := 11.0
const STAY_SECONDS := 16.0
const SKIP_GUARD := 1.5
const STRIP_Y := 146
const PHOTO := Vector2i(32, 30)
const CONFETTI_TINTS := [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"),
	Color("#73eff7"), Color("#f4f4f4")]

var time := 0.0
var done := false
var phase := 0
var rng := RandomNumberGenerator.new()
var scenes: Array[Node2D] = []
var cat_nodes: Array = []  # per scene: [AnimatedSprite2D]
var photos: Array[Dictionary] = []
var confetti: Array[Dictionary] = []
var hearts: Array[Dictionary] = []
var _confetti_t := 0.0
var _heart_t := 0.0
var _said_goodnight := false
var strip: Node2D


func _ready() -> void:
	rng.randomize()
	if Game.demo:
		print("DAY party")
	_build()
	Sfx.stop_music()
	Sfx.play("find_star")
	Sfx.music("music_party")


func _process(delta: float) -> void:
	step(delta)


## The finds to show (fake ones when the day had none, e.g. the party demo).
func finds() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for f in Game.finds:
		out.append(f)
	if out.is_empty():
		var kinds := ["wardrobe_top", "toy_box", "sunny_window", "bed", "tv_box", "laundry_basket", "bookshelf_top", "cushion"]
		var ids: Array[String] = Game.cat_data.ids()
		for i in kinds.size():
			out.append({"cat": ids[i % ids.size()], "kind": kinds[i], "spot": "", "round": i / 2})
	return out.slice(0, 8)


func _room_bg(parent: Node2D, wall: String, floor_tile: String) -> void:
	var bg := Backdrop.new()
	bg.wall = wall
	bg.floor_tile = floor_tile
	parent.add_child(bg)


func _build() -> void:
	var house: RefCounted = Game.house
	var bowl_room: Dictionary = house.rooms.get(house.bowls.room, {})
	var cats: Array = Game.cat_data.cats
	# 0: dinner in the kitchen.
	var s0 := Node2D.new()
	_room_bg(s0, bowl_room.get("wall", "wall_white_tiles"), bowl_room.get("floor_tile", "floor_tiles"))
	var row: Array = []
	for i in cats.size():
		var bx := 160 + (i - (cats.size() - 1) / 2.0) * 90
		var b := _sprite(s0, "bowl_" + cats[i].id, Vector2(bx + 16, 150), 2)
		b.stop()
		b.frame = 1
		row.append(_sprite(s0, cats[i].id + "_eat", Vector2(bx - 10, 150), 2))
	_add_family(s0, 150)
	scenes.append(s0)
	cat_nodes.append(row)
	# 1: cuddle on the sofa.
	var s1 := Node2D.new()
	var living := _first_room_with(house, "sofa")
	_room_bg(s1, living.get("wall", "wall_yellow_dots"), living.get("floor_tile", "floor_wood"))
	var sofa := _sprite(s1, "sofa", Vector2(160, 150), 2)
	sofa.stop()
	row = []
	for i in cats.size():
		var c := _sprite(s1, cats[i].id + "_sit", Vector2(160 + (i - (cats.size() - 1) / 2.0) * 44, 128), 2)
		c.flip_h = i % 2 == 1
		row.append(c)
	_add_family(s1, 150, true)
	scenes.append(s1)
	cat_nodes.append(row)
	# 2: bedtime.
	var s2 := Node2D.new()
	var kids := _first_room_with(house, "bed")
	_room_bg(s2, kids.get("wall", "wall_blue_stars"), kids.get("floor_tile", "floor_carpet"))
	var lamp := _sprite(s2, "furn_lamp", Vector2(48, 150), 2)
	lamp.stop()
	lamp.frame = 1
	var bed := _sprite(s2, "bed", Vector2(170, 150), 2)
	bed.stop()
	row = []
	for i in cats.size():
		row.append(_sprite(s2, cats[i].id + "_sleep", Vector2(214 - i * 34, 110), 2))
	var z := _sprite(s2, "zzz", Vector2(214, 78), 2)
	z.speed_scale = 0.6
	var veil := ColorRect.new()
	veil.size = Vector2(320, 180)
	veil.color = Color("#5d275d", 0.3)
	veil.mouse_filter = Control.MOUSE_FILTER_IGNORE
	s2.add_child(veil)
	scenes.append(s2)
	cat_nodes.append(row)
	for s in scenes:
		s.visible = false
		add_child(s)
	scenes[0].visible = true
	strip = PhotoStrip.new()
	strip.photos = finds()
	strip.position = Vector2(0, 200)
	add_child(strip)


func _first_room_with(house: RefCounted, kind: String) -> Dictionary:
	for sid in house.spot_order:
		if house.spots[sid].kind == kind:
			return house.rooms[house.spots[sid].room]
	return {}


func _sprite(parent: Node2D, name: String, bottom: Vector2, scale_i: int) -> AnimatedSprite2D:
	var s := Art.sprite(name, Color("#94b0c2"), Vector2i(20, 16))
	s.centered = false
	var sz := Art.size_of(name, Vector2i(20, 16))
	s.offset = Vector2(-sz.x / 2, -sz.y)
	s.scale = Vector2(scale_i, scale_i)
	s.position = bottom
	parent.add_child(s)
	return s


## The walker's character and the kids' seats (their role icon in a hat).
func _add_family(parent: Node2D, floor_y: int, close := false) -> void:
	var rider: String = Players.riders[Game.WALKER]
	if rider == "":
		rider = Game.roster[0]
	var xs := [36, 272, 298] if not close else [100, 228, 254]
	var w := _sprite(parent, "carry_" + rider if Art.has("carry_" + rider) else rider, Vector2(xs[0], floor_y), 2)
	w.set_meta("dance", true)
	for seat in [Game.LASER, Game.TREATS]:
		if not Players.is_seated(seat):
			continue
		var icon := "seat_laser" if seat == Game.LASER else "seat_treats"
		var k := _sprite(parent, icon, Vector2(xs[seat], floor_y), 1)
		k.set_meta("dance", true)
		var hat := Hat.new()
		hat.color = Game.hat_color(seat)
		hat.position = Vector2(0, -16)
		k.add_child(hat)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	var p := 0 if time < CUDDLE_AT else (1 if time < BED_AT else 2)
	if p != phase:
		phase = p
		for i in scenes.size():
			scenes[i].visible = i == phase
		if phase == 1:
			Sfx.play("purr")
		if phase == 2 and not _said_goodnight:
			_said_goodnight = true
			Sfx.stop_music()
			Sfx.music("music_night")
			Sfx.play("goodnight")
	# The strip slides up from below, and away at bedtime.
	var target := STRIP_Y if phase < 2 and time > 1.0 else 200
	strip.position.y = move_toward(strip.position.y, target, 80.0 * dt)
	for n in scenes[phase].get_children():
		if n is AnimatedSprite2D and n.has_meta("dance"):
			n.position.y = roundf(150 - absf(sin(time * 5.0 + n.position.x)) * (6.0 if phase == 0 else 2.0))
	if phase == 0:
		_confetti_t -= dt
		while _confetti_t <= 0.0:
			_confetti_t += 0.08
			_add_confetti()
	if phase == 1:
		_heart_t -= dt
		while _heart_t <= 0.0:
			_heart_t += 0.35
			var h := Art.sprite("heart", Color("#b13e53"), Vector2i(8, 8))
			add_child(h)
			hearts.append({"node": h, "pos": Vector2(rng.randf_range(110, 210), 100), "t": 0.0})
			Sfx.play("heart", rng.randf_range(0.9, 1.2), -10.0)
	for i in range(hearts.size() - 1, -1, -1):
		var h: Dictionary = hearts[i]
		h.t += dt
		h.pos.y -= 20.0 * dt
		h.node.position = h.pos.round()
		h.node.visible = phase == 1
		if h.t > 2.0:
			h.node.queue_free()
			hearts.remove_at(i)
	for i in range(confetti.size() - 1, -1, -1):
		var c: Dictionary = confetti[i]
		c.pos += c.vel * dt
		c.vel.x = sin(time * 3.0 + i) * 12.0
		c.node.position = c.pos.round()
		c.node.visible = phase == 0
		if c.pos.y > 184:
			c.node.queue_free()
			confetti.remove_at(i)
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(Game.WALKER, "a")):
		done = true
		Game.goto.call_deferred("select")


func _add_confetti() -> void:
	var tint: Color = CONFETTI_TINTS[rng.randi() % CONFETTI_TINTS.size()]
	var c := Art.sprite("confetti", tint, Vector2i(4, 4))
	c.speed_scale = rng.randf_range(0.5, 1.5)
	c.frame = rng.randi() % 6
	add_child(c)
	confetti.append({"node": c, "pos": Vector2(rng.randi_range(0, 320), -4), "vel": Vector2(0, rng.randf_range(30, 55))})


## A room wall and floor from the house's tiles, full screen.
class Backdrop extends Node2D:
	var wall := ""
	var floor_tile := ""

	func _ready() -> void:
		texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	func _atlas(name: String) -> Texture2D:
		if not Art.has(name):
			return null
		var t := Art.frames(name).get_frame_texture("default", 0)
		return t.atlas if t is AtlasTexture else t

	func _draw() -> void:
		var w := _atlas(wall)
		if w:
			draw_texture_rect(w, Rect2(0, 0, 320, 150), true)
		else:
			draw_rect(Rect2(0, 0, 320, 150), Color("#ffcd75"))
		var f := _atlas(floor_tile)
		if f:
			draw_texture_rect(f, Rect2(0, 150, 320, 8), true)
		else:
			draw_rect(Rect2(0, 150, 320, 8), Color("#ef7d57"))
		var s := _atlas("slab")
		if s:
			draw_texture_rect(s, Rect2(0, 158, 320, 22), true)
		else:
			draw_rect(Rect2(0, 158, 320, 22), Color("#b13e53"))


## The day's finds: one little photo per find, the spot open with the cat's
## face in it, a white frame, a collar-coloured corner.
class PhotoStrip extends Node2D:
	var photos: Array[Dictionary] = []

	func _draw() -> void:
		var n := photos.size()
		var gap := 4
		var total := n * 32 + (n - 1) * gap
		var x0 := (320 - total) / 2
		draw_rect(Rect2(x0 - 4, -2, total + 8, 34), Color("#1a1c2c", 0.5))
		for i in n:
			var p: Dictionary = photos[i]
			var r := Rect2(x0 + i * (32 + gap), 0, 32, 30)
			draw_rect(r, Color("#f4f4f4"))
			var inner := Rect2(r.position + Vector2(2, 2), Vector2(28, 21))
			draw_rect(inner, Color("#ffcd75"))
			var kind: String = str(p.get("kind", ""))
			if Art.has(kind):
				var sf := Art.frames(kind)
				var t := sf.get_frame_texture("default", mini(1, sf.get_frame_count("default") - 1))
				var sz := Art.size_of(kind)
				# Crop the bottom-centre of the open spot into the photo.
				var src := Rect2(maxf(0, sz.x / 2.0 - 14), maxf(0, sz.y - 21), minf(28, sz.x), minf(21, sz.y))
				var dst := Rect2(inner.position + Vector2((28 - src.size.x) / 2.0, 21 - src.size.y), src.size)
				draw_texture_rect_region(t, dst, src)
			var face := str(p.get("cat", "")) + "_face"
			if Art.has(face):
				draw_texture(Art.frames(face).get_frame_texture("default", 0), inner.position + Vector2(8, 5))
			var col: Color = Game.cat_data.get_cat(str(p.get("cat", ""))).get("collar", Color("#b13e53"))
			draw_rect(Rect2(r.position + Vector2(2, 24), Vector2(28, 4)), col)
