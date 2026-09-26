extends Node2D
## The album: a two-page book of the twelve species (six per page), the
## bonus row, and a double page for the whale.
##
## After a run: today's new species slide in one by one (a polaroid lands,
## the slot fills with colour, its motif plays), then stars pop on the
## repeats, then confetti bubbles; if the whale was photographed the book
## turns to the whale's double page. The driver's "a" goes back to select.
## Browsing from join (Game.album_browse): left/right turn the pages, and
## "a" or "b" of the driver or gunner goes back to join.
## Everything is timed in step(dt) for the tests.

const Species := preload("res://scripts/level/species.gd")

const FIRST_AT := 0.8
const NEW_EVERY := 0.9
const STAR_EVERY := 0.35
const STAY_AFTER := 6.0
const SKIP_GUARD := 1.0
const BROWSE_IDLE := 40.0
const SLOT := 44                     # 40 px icon (20 px art at 2x) + border

const C_WATER := Color("#124e89")
const C_DEEP := Color("#262b44")
const C_COVER := Color("#733e39")
const C_COVER_EDGE := Color("#3e2731")
const C_PAGE := Color("#ead4aa")
const C_PAGE_SHADE := Color("#e4a672")
const C_INK := Color("#181425")
const C_WHITE := Color("#ffffff")
const C_LEMON := Color("#fee761")
const CONFETTI := [Color("#2ce8f5"), Color("#fee761"), Color("#f6757a"), Color("#63c74d"), Color("#ffffff")]

enum Phase { NEW, STARS, CHEER, WHALE, IDLE }

var time := 0.0
var phase := Phase.NEW
var phase_t := 0.0
var browse := false
var spread := 0                   # 0 = species, 1 = whale double page
var done := false
var next_screen := ""
var auto_goto := true

var queue_new: Array[String] = []
var queue_stars: Array[String] = []
var shown_new: Array[String] = []   # new species already landed
var stars_shown := {}               # id -> stars popped
var landing := {}                   # id -> seconds since landing (for the bounce)
var flying := {}                    # id -> 0..1 slide progress of the incoming polaroid
var bubbles: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _bubble_t := 0.0
var _last_input := 0.0


func _ready() -> void:
	rng.seed = 11
	browse = Game.album_browse
	Game.album_browse = false
	var s: Dictionary = Game.session
	for id in Species.PAGE:
		if s.new.has(id):
			queue_new.append(id)
	for id in s.repeats:
		if Species.PAGE.has(id):
			queue_stars.append(id)
	if browse:
		phase = Phase.IDLE
		queue_new.clear()
		queue_stars.clear()
	Sfx.stop_music()
	Sfx.music("music_album")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if done:
		return
	time += dt
	phase_t += dt
	for k in landing.keys():
		landing[k] += dt
	_bubbles(dt)
	match phase:
		Phase.NEW:
			_new_phase()
		Phase.STARS:
			if phase_t >= STAR_EVERY:
				phase_t = 0.0
				if queue_stars.is_empty():
					_next_phase(Phase.CHEER)
				else:
					var id: String = queue_stars[0]
					var have: int = stars_shown.get(id, 0)
					if have < mini(int(Game.session.repeats[id]), 3):
						stars_shown[id] = have + 1
						Sfx.play("repeat_star", 1.0 + 0.05 * have)
					else:
						queue_stars.pop_front()
		Phase.CHEER:
			if phase_t < 0.05:
				_burst(40)
				Sfx.play("disco")
			if phase_t >= 2.0:
				_next_phase(Phase.WHALE if Game.session.whale else Phase.IDLE)
		Phase.WHALE:
			if phase_t < 0.05:
				spread = 1
				Sfx.play("whoosh")
				Sfx.play("whale_song")
			if phase_t >= 4.0:
				_next_phase(Phase.IDLE)
	_input_step()
	queue_redraw()


func _new_phase() -> void:
	if queue_new.is_empty():
		_next_phase(Phase.STARS)
		return
	var id: String = queue_new[0]
	var start := FIRST_AT if shown_new.is_empty() else 0.0
	if phase_t < start:
		return
	var k := clampf((phase_t - start) / 0.5, 0.0, 1.0)
	flying[id] = k
	if k >= 1.0 and phase_t >= start + NEW_EVERY:
		flying.erase(id)
		shown_new.append(id)
		landing[id] = 0.0
		queue_new.pop_front()
		Sfx.play("new_species_%d" % Species.motif(id))
		_burst(6, _slot_center(id))
		phase_t = 0.0


func _next_phase(p: int) -> void:
	phase = p
	phase_t = 0.0


func _input_step() -> void:
	var driver := Players.Seat.DRIVER
	var gunner := Players.Seat.GUNNER
	if browse:
		for s in [driver, gunner]:
			var d := Players.dir4_just_pressed(s)
			if d.x != 0 and Game.album.has(Species.WHALE):
				spread = 1 - spread
				_last_input = time
				Sfx.play("whoosh")
		if time >= SKIP_GUARD:
			for s in [driver, gunner]:
				if Players.just_pressed(s, "a") or Players.just_pressed(s, "b"):
					_leave("join")
					return
		if time - _last_input >= BROWSE_IDLE:
			_leave("join")
		return
	var finished := phase == Phase.IDLE
	if (time >= SKIP_GUARD and Players.just_pressed(driver, "a")) or (finished and phase_t >= STAY_AFTER):
		_leave("select")


func _leave(screen: String) -> void:
	done = true
	next_screen = screen
	Sfx.play("select")
	if auto_goto:
		Game.goto.call_deferred(screen)


# ---------------------------------------------------------------- confetti bubbles

func _burst(n: int, at := Vector2(-1, -1)) -> void:
	for i in n:
		var p := at if at.x >= 0 else Vector2(rng.randf_range(10, 310), rng.randf_range(170, 190))
		bubbles.append({"pos": p + Vector2(rng.randf_range(-6, 6), rng.randf_range(-4, 4)),
			"vel": Vector2(rng.randf_range(-20, 20), rng.randf_range(-70, -30)),
			"col": CONFETTI[rng.randi() % CONFETTI.size()], "r": rng.randi_range(1, 3)})


func _bubbles(dt: float) -> void:
	_bubble_t -= dt
	if _bubble_t <= 0.0:
		_bubble_t = 0.4
		bubbles.append({"pos": Vector2(rng.randf_range(0, 320), 184), "vel": Vector2(0, rng.randf_range(-25, -12)),
			"col": Color("#2ce8f5"), "r": rng.randi_range(1, 2)})
	for i in range(bubbles.size() - 1, -1, -1):
		var b := bubbles[i]
		b.pos += b.vel * dt
		b.vel.x *= 0.98
		if b.pos.y < -6:
			bubbles.remove_at(i)


# ---------------------------------------------------------------- drawing

## Top-left of a species' slot on the spread (6 per page, 3 x 2).
func slot_pos(id: String) -> Vector2:
	var i := Species.PAGE.find(id)
	var page := i / 6
	var k := i % 6
	var x0 := 16 + page * 152
	return Vector2(x0 + (k % 3) * (SLOT + 2), 22 + (k / 3) * (SLOT + 14))


func _slot_center(id: String) -> Vector2:
	return slot_pos(id) + Vector2(SLOT, SLOT) * 0.5


## Is the species drawn in colour now? (known before this run, or landed)
func is_shown(id: String) -> bool:
	if Game.session.new.has(id) and not browse:
		return shown_new.has(id)
	return Game.album.has(id)


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 180), C_WATER)
	draw_rect(Rect2(0, 120, 320, 60), C_DEEP)
	for b in bubbles:
		draw_circle(b.pos.round(), b.r, b.col, false, 1.0)
	# The book: cover, two pages, the spine.
	draw_rect(Rect2(8, 8, 304, 166), C_COVER_EDGE)
	draw_rect(Rect2(10, 10, 300, 162), C_COVER)
	draw_rect(Rect2(14, 12, 144, 156), C_PAGE)
	draw_rect(Rect2(162, 12, 144, 156), C_PAGE)
	draw_rect(Rect2(154, 12, 4, 156), C_PAGE_SHADE)
	draw_rect(Rect2(162, 12, 4, 156), C_PAGE_SHADE)
	draw_rect(Rect2(158, 10, 4, 162), C_COVER_EDGE)
	if spread == 1:
		_draw_whale_spread()
	else:
		_draw_species_spread()
	# Page dots: which spread is open (only when the whale page exists).
	if Game.album.has(Species.WHALE) or Game.session.whale:
		for k in 2:
			draw_rect(Rect2(152 + k * 12, 175, 4, 3), C_LEMON if k == spread else C_COVER_EDGE)


func _draw_species_spread() -> void:
	var slot_tex := Art.frames("album_slot", Color("#3a4466"), Vector2i(20, 20)).get_frame_texture("default", 0)
	var star_tex := Art.frames("star", C_LEMON, Vector2i(8, 8)).get_frame_texture("default", 0)
	for id in Species.PAGE:
		var p := slot_pos(id)
		var hop := 0.0
		if landing.has(id) and landing[id] < 0.3:
			hop = -roundf(sin(landing[id] / 0.3 * PI) * 4.0)
		p.y += hop
		draw_texture_rect(slot_tex, Rect2(p + Vector2(2, 2), Vector2(40, 40)), false)
		var shown := is_shown(id)
		var name := ("icon_" if shown else "sil_") + id
		var tex := Art.frames(name, Species.tint(id) if shown else Color("#262b44"), Vector2i(20, 20)).get_frame_texture("default", 0)
		draw_texture_rect(tex, Rect2(p + Vector2(2, 2), Vector2(40, 40)), false)
		if landing.has(id) and landing[id] < 0.5:
			draw_rect(Rect2(p, Vector2(SLOT, SLOT)), Color(1, 1, 1, 1.0 - landing[id] / 0.5), false, 2.0)
		if shown:
			# A photo corner in each corner of a filled slot.
			for c in [Vector2(0, 0), Vector2(SLOT - 4, 0), Vector2(0, SLOT - 4), Vector2(SLOT - 4, SLOT - 4)]:
				draw_rect(Rect2(p + c, Vector2(4, 4)), Color("#b86f50"))
		var stars: int = stars_shown.get(id, 0) if not browse else 0
		for k in stars:
			draw_texture(star_tex, p + Vector2(SLOT - 10 - k * 9, -5))
	# The polaroid sliding in from below for the species landing now.
	for id in flying:
		var k: float = flying[id]
		var e := 1.0 - (1.0 - k) * (1.0 - k)
		var to := slot_pos(id) + Vector2(10, 8)
		var from := Vector2(to.x, 190)
		var at := from.lerp(to, e).round()
		var card := Art.frames("polaroid", C_WHITE, Vector2i(24, 28)).get_frame_texture("default", 0)
		draw_texture(card, at)
		var icon := Art.frames("icon_" + id, Species.tint(id), Vector2i(20, 20)).get_frame_texture("default", 0)
		draw_texture(icon, at + Vector2(2, 2))
	# Bonus row at the foot of the pages: icon + count.
	for b in Species.BONUS.size():
		var kind: String = Species.BONUS[b]
		var p := Vector2(28 + b * 72 + (8 if b >= 2 else 0), 142)
		var t := Art.frames("icon_" + kind, Color("#c0cbdc"), Vector2i(20, 20)).get_frame_texture("default", 0)
		draw_texture(t, p)
		var n := Game.album.bonus(kind)
		if n > 0:
			_digits(p + Vector2(23, 6), mini(n, 999), C_INK)


func _draw_whale_spread() -> void:
	var has_whale: bool = Game.album.has(Species.WHALE) or Game.session.whale
	var name := "whale" if has_whale else "sil_whale_big"
	var sf := Art.frames(name, Species.tint(Species.WHALE), Vector2i(128, 48))
	var frame := int(time * 2.0) % maxi(sf.get_frame_count("default"), 1)
	var tex := sf.get_frame_texture("default", frame)
	var bob := roundf(sin(time * 1.5) * 2.0)
	# The whale fills the double page at 2x, across the spine.
	draw_texture_rect(tex, Rect2(32, 42 + bob, 256, 96), false)
	# Photo corners on the whole spread.
	for c in [Vector2(22, 26), Vector2(290, 26), Vector2(22, 148), Vector2(290, 148)]:
		draw_rect(Rect2(c, Vector2(8, 8)), Color("#b86f50"))


func _digits(p: Vector2, n: int, col: Color) -> void:
	var s := str(n)
	for k in s.length():
		var glyph: Array = DIGITS[int(s[k])]
		for row in 5:
			for c in 3:
				if glyph[row][c] == "#":
					draw_rect(Rect2(p.x + (k * 4 + c) * 2, p.y + row * 2, 2, 2), col)


const DIGITS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]
