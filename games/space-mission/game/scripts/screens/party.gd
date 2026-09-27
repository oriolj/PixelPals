extends Node2D
## The party at Mission Control. The big screen plays the mission's highlights
## in turn: the Camera seat's Earth photos (golden ones in gold frames), the
## finished station, the rock samples in a tray, the landing site. Beside it,
## the mission patch with the crew in their helmets. The crew dance under
## falling confetti. After STAY_SECONDS, or the Pilot's A, back to select.

const Station := preload("res://scripts/logic/station.gd")
const Confetti := preload("res://scripts/view/confetti.gd")
const Tex := preload("res://scripts/view/tex.gd")

const STAY_SECONDS := 14.0
const SKIP_GUARD := 1.5
const SLIDE_TIME := 2.6
const SCREEN := Rect2(80, 10, 160, 90)     # the big screen on the wall
const INNER := Rect2(86, 16, 148, 78)      # its picture area
const PATCH := Vector2(40, 56)
const FLOOR_Y := 150

var auto_goto := true
var next_screen := ""
var time := 0.0
var slides: Array[String] = []
var dancers: Array[Dictionary] = []
var crew: Array[String] = []
var _confetti: Node2D
var _room: Node2D


func _ready() -> void:
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			crew.append(Game.rider_of(s))
	if crew.is_empty():
		crew.append(Game.roster[0])
	slides = build_slides()
	_room = Room.new()
	_room.party = self
	add_child(_room)
	var i := 0
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s):
			continue
		var rider := Game.rider_of(s)
		var spr := Art.sprite("astronaut_" + rider, Game.rider_color(rider), Vector2i(24, 24))
		spr.position = Vector2(128 + i * 32, FLOOR_Y)
		add_child(spr)
		dancers.append({"sprite": spr, "x": 128.0 + i * 32, "ph": i * 1.3})
		i += 1
	_confetti = Confetti.new()
	add_child(_confetti)
	Sfx.stop_music()
	Sfx.play("party")
	Sfx.music("music_menu")


## The highlight reel, in order: photos, station, samples, the landing site.
static func build_slides() -> Array[String]:
	var out: Array[String] = []
	if not Game.photos.is_empty():
		out.append("photos")
	if not Game.modules.is_empty():
		out.append("station")
	if not Game.samples.is_empty():
		out.append("samples")
	if Game.site != "":
		out.append("site")
	if out.is_empty():
		out.append("station")
	return out


func slide() -> String:
	return slides[int(time / SLIDE_TIME) % slides.size()]


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	time += dt
	_confetti.tick(dt)
	var cheer := Players.just_pressed(Players.Seat.HONKER, "any") or Players.just_pressed(Players.Seat.GUNNER, "a")
	for d in dancers:
		if cheer:
			d.ph += 1.0
		var hop := int(time * 4.0 + d.ph) % 4
		d.sprite.position = Vector2(d.x, FLOOR_Y - [0, 2, 3, 2][hop])
		d.sprite.rotation = (PI * 0.5) * float(int(time * 1.5 + d.ph) % 4) if cheer else d.sprite.rotation
	if cheer:
		Sfx.play("wave", 1.0 + randf() * 0.2)
	_room.queue_redraw()
	var skip := time >= SKIP_GUARD and Players.just_pressed(Players.Seat.DRIVER, "a")
	if time >= STAY_SECONDS or skip:
		next_screen = "select"
		set_process(false)
		if auto_goto:
			Game.goto.call_deferred("select")


class Room extends Node2D:
	var party: Node2D

	func _draw() -> void:
		var P = party
		draw_texture(Tex.frame("mission_control", 0, Color("#c0cbdc"), Vector2i(320, 180)), Vector2.ZERO)
		draw_texture(Tex.frame("big_screen", 0, Color("#262b44"), Vector2i(160, 90)), P.SCREEN.position)
		match P.slide():
			"photos": _photos(P)
			"station": _station(P)
			"samples": _samples(P)
			"site": _site(P)
		_patch(P)

	func _photos(P) -> void:
		var n: int = Game.photos.size()
		var show := mini(n, 4)
		var page := int(P.time / P.SLIDE_TIME / maxf(1.0, float(P.slides.size())))
		for k in show:
			var ph: Dictionary = Game.photos[(page * 4 + k) % n]
			var p := Vector2(P.INNER.position.x + 4 + (k % 2) * 72, P.INNER.position.y + 3 + (k / 2) * 38)
			draw_rect(Rect2(p - Vector2(2, 1), Vector2(68, 37)), Color("#feae34") if ph.golden else Color("#ffffff"))
			draw_texture_rect(ph.tex, Rect2(p + Vector2(0, 0), Vector2(64, 34)), false,
				Color.WHITE)

	func _station(P) -> void:
		var core: Vector2 = P.INNER.get_center() + Vector2(14, 0)
		draw_texture(Tex.frame("iss_core", int(P.time * 2.0) % 2, Color("#c0cbdc"), Vector2i(32, 16)), (core - Vector2(16, 8)).round())
		var done := Game.modules.duplicate()
		for i in Station.SLOTS.size():
			var kind: String = Station.SLOTS[i].kind
			var idx: int = done.find(kind)
			if idx == -1:
				continue
			done.remove_at(idx)
			var frame := 3 if kind == "solar" else 0
			var tex := Tex.frame("iss_" + kind, frame, Station.COLORS[kind], Vector2i(16, 16))
			draw_texture(tex, (core + Station.SLOTS[i].offset - tex.get_size() / 2.0).round())
		if Game.docked:
			var sh := Tex.frame("shuttle", 0, Color("#ffffff"), Vector2i(48, 20))
			draw_texture(sh, (core + Vector2(-60, 0) - sh.get_size() / 2.0).round())

	func _samples(P) -> void:
		var r: Rect2 = Rect2(P.INNER.position + Vector2(14, 44), Vector2(120, 16))
		draw_rect(r, Color("#8b9bb4"))
		draw_rect(r.grow(-1), Color("#5a6988"))
		var n := mini(Game.samples.size(), 14)
		for i in n:
			var tex := Tex.frame("sample_" + Game.samples[i], 0, Color("#be4a2f"), Vector2i(6, 8))
			draw_texture(tex, r.position + Vector2(5 + i * 8, 4))
		var kinds := {}
		for s in Game.samples:
			kinds[s] = true
		var i := 0
		for kind in kinds:
			var name: String = kind if kind in ["ice", "shell"] else "rock_" + kind
			draw_texture(Tex.frame(name, int(P.time * 3.0) % 2, Color("#be4a2f"), Vector2i(12, 10)),
				P.INNER.position + Vector2(20 + i * 22, 20))
			i += 1

	func _site(P) -> void:
		var tex := Tex.frame("site_" + Game.site, 0, Color("#b86f50"), Vector2i(32, 16))
		var c: Vector2 = P.INNER.get_center()
		draw_rect(Rect2(P.INNER.position + Vector2(0, 50), Vector2(148, 28)), Color("#b86f50"))
		draw_texture_rect(tex, Rect2((c + Vector2(-32, 8)).round(), Vector2(64, 32)), false)
		draw_texture(Tex.frame("rover", 0, Color("#c0cbdc"), Vector2i(40, 24)), (c + Vector2(-20, -22)).round())

	func _patch(P) -> void:
		var tex := Tex.frame("patch", 0, Color("#feae34"), Vector2i(48, 48))
		draw_texture(tex, P.PATCH - Vector2(24, 24))
		# The crew on the patch: the riders themselves (their helmets are on the dancers).
		var n: int = P.crew.size()
		for i in n:
			var a := Tex.frame(P.crew[i], 0, Color("#ffffff"), Vector2i(16, 16))
			var off := Vector2((i - (n - 1) / 2.0) * 11.0, -4 + (0 if i % 2 == 1 or n == 1 else 3))
			draw_texture(a, (P.PATCH + off - Vector2(8, 8)).round())
