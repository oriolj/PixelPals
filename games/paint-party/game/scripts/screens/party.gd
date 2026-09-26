extends Node2D
## Party = the gallery: the new picture hangs in a gold frame in the middle of
## the wall, the previous two beside it, the riders dance and confetti falls.
## After STAY_SECONDS, or the Brush's "a" (after a short guard), it goes back
## to select for the next picture.

const Kit := preload("res://scripts/ui/draw_kit.gd")
const Palette := preload("res://scripts/paint/palette.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")

const STAY_SECONDS := 12.0
const SKIP_GUARD := 1.5
const FLOOR_Y := 296.0
const MAIN := Rect2(184, 44, 272, 153)
const SIDE: Array[Rect2] = [Rect2(24, 92, 128, 72), Rect2(488, 92, 128, 72)]

var time := 0.0
var done := false
var auto_goto := true
var next_screen := ""
## Textures: [main, left, right]; null = nothing there yet.
var pictures: Array = [null, null, null]
var riders: Array[AnimatedSprite2D] = []
var rng := RandomNumberGenerator.new()
var _confetti: Array[Dictionary] = []
var _placeholder: Array = []


func _ready() -> void:
	rng.randomize()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	_load_pictures()
	var ids := dancers()
	var xs := [250.0, 390.0, 320.0, 180.0, 460.0]
	for i in ids.size():
		var r := Art.sprite(ids[i], Game.rider_color(ids[i]), Vector2i(16, 16))
		r.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		r.scale = Vector2(3, 3)
		r.position = Vector2(xs[i % xs.size()], 322)
		r.flip_h = r.position.x > 320
		add_child(r)
		riders.append(r)
	var prng := RandomNumberGenerator.new()
	prng.seed = 5
	for i in 5:
		_placeholder.append(Shapes.splat(Vector2(300 + i * 330, 300 + (i % 2) * 450), 120, [Palette.COLORS[i * 2]], prng))
	Sfx.stop_music()
	Sfx.play("party")
	Sfx.play("clap", 1.0, -4.0)


func _load_pictures() -> void:
	var main_img: Image = Game.last_painting
	var main_path := Game.last_painting_path
	var files := Game.gallery(3)
	if main_img == null and main_path != "":
		main_img = Game.load_png(main_path)
	if main_img == null and not files.is_empty():
		main_path = files[0]
		main_img = Game.load_png(main_path)
	pictures[0] = _tex(main_img)
	var k := 1
	for f in files:
		if k > 2:
			break
		if f == main_path:
			continue
		pictures[k] = _tex(Game.load_png(f))
		k += 1


static func _tex(img: Image) -> Texture2D:
	if img == null:
		return null
	var copy := img.duplicate() as Image
	if copy.get_format() != Image.FORMAT_RGBA8:
		copy.convert(Image.FORMAT_RGBA8)
	copy.generate_mipmaps()
	return ImageTexture.create_from_image(copy)


## Rider ids to show: the seated riders, or the first of the roster if nobody.
func dancers() -> Array[String]:
	var out: Array[String] = []
	for seat in Players.SEAT_COUNT:
		var r: String = Players.riders[seat]
		if r == "" and Players.is_seated(seat) and not Game.roster.is_empty():
			r = Game.roster[seat % Game.roster.size()]
		if r != "":
			out.append(r)
	if out.is_empty():
		for i in mini(3, Game.roster.size()):
			out.append(Game.roster[i])
	return out


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	for i in riders.size():
		var hop := absf(sin(time * 6.0 + i * 1.3)) * 12.0
		riders[i].position.y = 322 - hop
		riders[i].rotation = sin(time * 3.0 + i) * 0.12
	if rng.randf() < 0.6:
		_confetti.append({"pos": Vector2(rng.randf_range(0, 640), -6), "vel": Vector2(rng.randf_range(-15, 15), rng.randf_range(35, 70)),
			"col": Palette.COLORS[rng.randi() % Palette.COLORS.size()], "rot": rng.randf() * TAU, "spin": rng.randf_range(-5, 5)})
	for i in range(_confetti.size() - 1, -1, -1):
		var c: Dictionary = _confetti[i]
		c.pos += c.vel * dt
		c.pos.x += sin(time * 3.0 + i) * 0.4
		c.rot += c.spin * dt
		if c.pos.y > 366:
			_confetti.remove_at(i)
	if fmod(time, 2.4) < dt and time > 1.0:
		Sfx.play("clap", rng.randf_range(0.95, 1.1), -6.0)
	queue_redraw()
	if time >= STAY_SECONDS or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		next_screen = "select"
		if auto_goto:
			Game.goto.call_deferred("select")


func _draw() -> void:
	Kit.wall(self, Rect2(0, 0, 640, FLOOR_Y))
	# picture rail and skirting board
	draw_rect(Rect2(0, 18, 640, 5), Kit.WOOD)
	draw_rect(Rect2(0, FLOOR_Y - 8, 640, 8), Kit.WOOD)
	Kit.floor_strip(self, Rect2(0, FLOOR_Y, 640, 360 - FLOOR_Y))
	_hang(1, SIDE[0], 9.0)
	_hang(2, SIDE[1], 9.0)
	var grow := maxf(0.0, 1.0 - time / 0.5) * 20.0
	_hang(0, MAIN.grow(grow), 16.0)
	# twinkles around the new picture
	for i in 6:
		var ph := fmod(time * 0.9 + i / 6.0, 1.0)
		var a := TAU * i / 6.0 + time * 0.4
		var p := MAIN.get_center() + Vector2(cos(a) * 172, sin(a) * 104)
		Kit.sparkle(self, p, 3.0 + 5.0 * sin(ph * PI), Kit.GOLD_LIGHT.lerp(Kit.WHITE, 0.3))
	for c in _confetti:
		draw_set_transform(c.pos, c.rot, Vector2.ONE)
		draw_rect(Rect2(-3, -1.5, 6, 3), c.col)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## One framed picture hanging from a nail on two strings.
func _hang(i: int, inner: Rect2, t: float) -> void:
	var nail := Vector2(inner.get_center().x, inner.position.y - t - 22)
	draw_line(nail, Vector2(inner.position.x + inner.size.x * 0.2, inner.position.y - t), Kit.WOOD_DARK, 1.5, true)
	draw_line(nail, Vector2(inner.end.x - inner.size.x * 0.2, inner.position.y - t), Kit.WOOD_DARK, 1.5, true)
	Kit.disc(self, nail, 3.0, Color("#566c86"))
	# shadow on the wall
	draw_rect(inner.grow(t).grow(1).abs().merge(Rect2(inner.grow(t).position + Vector2(4, 5), inner.grow(t).size)), Color(0, 0, 0, 0.12))
	var tex: Texture2D = pictures[i]
	if tex != null:
		draw_texture_rect(tex, inner, false)
	else:
		draw_rect(inner, Palette.PAPER)
		if i == 0:
			var k := inner.size.x / 1920.0
			for p in _placeholder:
				Kit.parts(self, p, inner.position, k)
	Kit.gold_frame(self, inner, t)
