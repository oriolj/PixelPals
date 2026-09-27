extends Node2D
## Stage 3, the horse show. A ring with flags, a grandstand of the riders'
## friends and a judge (a friendly old horse in a hat) at his table.
##
## 1. The bell (NEIGH seat): a press starts each round, ding!, and the crowd claps.
## 2. The mare's course (Rider): 6 jumps on an automatic path around the ring;
##    A jumps with the same +-0.4 s assist. A clear jump pops confetti; a
##    refusal is a comedic stop, a snort and a lap back; it always finishes.
## 3. The foal's mini course (Foal seat): 4 tiny jumps (A, a huge window), then
##    4 pick-the-colour poles (a direction picks a cone; every pick is cheered).
## 4. The rosettes: everybody wins. The judge nods and gives the foal a carrot.

const ShowCourse := preload("res://scripts/logic/show_course.gd")
const Tex := preload("res://scripts/view/tex.gd")
const Pause := preload("res://scripts/view/pause.gd")
const Confetti := preload("res://scripts/view/confetti.gd")

const JUDGE_AT := Vector2(266, 22)
const BELL_AT := Vector2(240, 38)
const STAND_AT := Vector2(12, 22)
const TABLE := Rect2(236, 50, 56, 6)
const FENCE_Y := 86
const MINI_Y := ShowCourse.FOAL_Y
const CONE_OFFSETS: Array[Vector2] = [Vector2(0, -26), Vector2(18, -8), Vector2(0, 10), Vector2(-18, -8)]
const CONE_NAMES: Array[String] = ["cone_red", "cone_blue", "cone_yellow", "cone_green"]
const CONE_COLOURS: Array[Color] = [Color("#e43b44"), Color("#0099db"), Color("#feae34"), Color("#63c74d")]
const ROSETTE_MARE_AT := Vector2(140, 150)
const ROSETTE_FOAL_AT := Vector2(186, 156)
const PARTY_DELAY := 1.2

var auto_goto := true
var next_screen := ""
var time := 0.0
var show: ShowCourse
var done_t := -1.0
var crowd_t := 0.0              # the crowd bounces while > 0
var bell_t := -1.0              # the bell rings
var carrot_t := -1.0
var nod_t := 0.0
var neigh_t := -1.0
var events_log: Array[String] = []
var mare_home := Vector2.ZERO   # where the mare walks for the rosettes
var foal_home := Vector2.ZERO
var mare_at := Vector2.ZERO
var foal_at := Vector2.ZERO
var _confetti: Node2D
var _pause: Node2D
var _anim_t := 0.0
var _neigh_cool := 0.0


func _ready() -> void:
	show = ShowCourse.new(Game.has_toddler(), Game.foal_auto())
	mare_at = ShowCourse.pos(show.s)
	foal_at = Vector2(-20, MINI_Y)
	_confetti = Confetti.new()
	add_child(_confetti)
	_pause = Pause.new()
	_pause.back_to_join.connect(_back_to_join)
	add_child(_pause)
	Sfx.music("music_show")


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	if _pause.check():
		return
	time += dt
	_anim_t += dt
	crowd_t = maxf(0.0, crowd_t - dt)
	nod_t = maxf(0.0, nod_t - dt)
	if bell_t >= 0.0:
		bell_t += dt
		if bell_t > 0.8:
			bell_t = -1.0
	if neigh_t >= 0.0:
		neigh_t += dt
		if neigh_t > 0.6:
			neigh_t = -1.0
	var bell_phase := show.phase == ShowCourse.Phase.BELL_MARE or show.phase == ShowCourse.Phase.BELL_FOAL
	var neigh := Game.neigh_pressed()
	_neigh_cool = maxf(0.0, _neigh_cool - dt)
	if neigh and not bell_phase and _neigh_cool <= 0.0:
		# Outside the bell rounds the toddler's press is a whinny and a cheer.
		_neigh_cool = 0.4
		neigh_t = 0.0
		crowd_t = 0.6
		Sfx.play("neigh", 1.05, -3.0)
		Sfx.play("crowd_clap", 1.0, -8.0)
	var input := {
		"bell": neigh and bell_phase,
		"jump": Players.just_pressed(Players.Seat.DRIVER, "a"),
		"hop": not Game.foal_auto() and Players.just_pressed(Players.Seat.GUNNER, "a"),
		"dir": Players.dir4_just_pressed(Players.Seat.GUNNER) if not Game.foal_auto() else Vector2i.ZERO,
	}
	var was := show.phase
	for e in show.step(dt, input):
		_event(e)
	if show.phase == ShowCourse.Phase.ROSETTES and was != ShowCourse.Phase.ROSETTES:
		_start_rosettes()
	_move_horses(dt)
	_confetti.tick(dt)
	if carrot_t >= 0.0:
		carrot_t += dt
	if show.done():
		if done_t < 0.0:
			done_t = 0.0
			Game.day.rosettes = show.rosettes.duplicate(true)
			Game.day.clean_jumps = int(Game.day.clean_jumps) + show.clean_count()
			Game.day.foal_jumps = int(Game.day.foal_jumps) + show.foal_clean_count()
		done_t += dt
		if done_t >= PARTY_DELAY and next_screen == "":
			_finish()
	queue_redraw()


func _event(e: String) -> void:
	events_log.append(e)
	match e:
		"bell":
			bell_t = 0.0
			crowd_t = 1.2
			Sfx.play("bell_ding")
			Sfx.play("crowd_clap", 1.0, -4.0)
		"jump_clean":
			Sfx.play("jump_hup")
			var jp := ShowCourse.jump_pos(show.jump_i - 1)
			_confetti.burst(jp + Vector2(0, -20), 26)
			Sfx.play("confetti")
			Sfx.play("crowd_clap", 1.05, -4.0)
			crowd_t = 1.0
		"jump":
			Sfx.play("jump_hup")
			Sfx.play("crowd_clap", 1.0, -8.0)
		"land":
			Sfx.play("land_thud")
		"refuse":
			Sfx.play("snort")
			Sfx.play("crowd_ooh", 1.0, -4.0)
			neigh_t = 0.0
		"finish":
			Sfx.play("crowd_clap")
			crowd_t = 1.5
		"foal_jump_clean":
			Sfx.play("jump_hup", 1.4, -4.0)
			_confetti.burst(show.foal_pos() + Vector2(0, -12), 14)
			crowd_t = 0.8
		"foal_jump":
			Sfx.play("jump_hup", 1.4, -8.0)
		"pick", "pick_match":
			Sfx.play("crowd_clap", 1.1, -4.0)
			Sfx.play("confetti", 1.2, -6.0)
			Sfx.play("foal_neigh", 1.0, -4.0)
			_confetti.burst(show.foal_pos() + Vector2(0, -18), 18)
			crowd_t = 0.8
		"rosette":
			nod_t = 0.8
			Sfx.play("rosette_fanfare" if show.rosette_shown == 1 else "ready", 1.0, -2.0)
			Sfx.play("crowd_clap", 1.0, -6.0)
			crowd_t = 1.0
		"carrot":
			carrot_t = 0.0
			nod_t = 1.0
			Sfx.play("munch")
			Sfx.play("foal_neigh")


func _start_rosettes() -> void:
	var seated: Array = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	show.award(Game.day, seated)
	_confetti.rate = 22.0
	mare_home = ROSETTE_MARE_AT
	foal_home = ROSETTE_FOAL_AT


func _move_horses(dt: float) -> void:
	match show.phase:
		ShowCourse.Phase.BELL_MARE, ShowCourse.Phase.MARE:
			mare_at = show.mare_pos()
		ShowCourse.Phase.BELL_FOAL, ShowCourse.Phase.FOAL, ShowCourse.Phase.PICKS:
			mare_at = mare_at.move_toward(ShowCourse.pos(ShowCourse.MARE_FINISH), 30.0 * dt)
			if show.phase == ShowCourse.Phase.PICKS:
				foal_at = foal_at.move_toward(show.foal_pos(), 70.0 * dt)
			else:
				foal_at = show.foal_pos()
		_:
			mare_at = mare_at.move_toward(mare_home, 40.0 * dt)
			foal_at = foal_at.move_toward(foal_home, 40.0 * dt)


# ---------------------------------------------------------------- view

func _mare_frame() -> Array:
	# [frame, faces_right]
	var right := true
	var fr := 0
	match show.phase:
		ShowCourse.Phase.BELL_MARE:
			fr = _af("mare", "stand")
		ShowCourse.Phase.MARE:
			right = show.mare_faces_right()
			match show.mstate:
				ShowCourse.MState.JUMP:
					var k := clampf(show.mstate_t / ShowCourse.JUMP_TIME, 0.0, 0.999)
					fr = _af("mare", "jump", 0 if k < 0.22 else (1 if k < 0.72 else 2))
				ShowCourse.MState.REFUSE:
					fr = _af("mare", "neigh")
				ShowCourse.MState.BACK:
					fr = _af("mare", "walk")
				ShowCourse.MState.TURN, ShowCourse.MState.FINISH:
					fr = _af("mare", "stand")
				_:
					fr = _af("mare", "canter")
		ShowCourse.Phase.ROSETTES, ShowCourse.Phase.DONE:
			var moving := mare_at.distance_to(mare_home) > 0.5
			right = true
			fr = _af("mare", "walk") if moving else _af("mare", "stand")
		_:
			right = false
			var moving2 := mare_at.distance_to(ShowCourse.pos(ShowCourse.MARE_FINISH)) > 0.5
			fr = _af("mare", "walk") if moving2 else _af("mare", "stand")
	if neigh_t >= 0.0 and show.mstate != ShowCourse.MState.JUMP:
		fr = _af("mare", "neigh")
	return [fr, right]


func _foal_frame() -> Array:
	var right := true
	var fr := _af("foal", "stand")
	match show.phase:
		ShowCourse.Phase.FOAL:
			if show.foal_hop_t >= 0.0:
				fr = _af("foal", "hop", int(clampf(show.foal_hop_t / ShowCourse.FOAL_HOP_TIME, 0.0, 0.99) * 3.0))
			else:
				fr = _af("foal", "trot")
		ShowCourse.Phase.PICKS:
			right = false
			if show.foal_x > ShowCourse.POLES[show.pole_i] + 0.5:
				fr = _af("foal", "trot")
			elif show.picked_t >= 0.0:
				fr = _af("foal", "neigh")
		ShowCourse.Phase.ROSETTES, ShowCourse.Phase.DONE:
			fr = _af("foal", "trot") if foal_at.distance_to(foal_home) > 0.5 else _af("foal", "stand")
			if carrot_t >= 0.0 and carrot_t < 1.5:
				fr = _af("foal", "neigh")
	if neigh_t >= 0.0 and show.phase != ShowCourse.Phase.FOAL:
		fr = _af("foal", "neigh")
	return [fr, right]


func _af(family: String, anim_name: String, hold := 0) -> int:
	var r := Tex.anim(family, anim_name)
	if float(r[2]) <= 0.0:
		return int(r[0]) + clampi(hold, 0, int(r[1]) - 1)
	if hold > 0 or anim_name == "jump" or anim_name == "hop":
		return int(r[0]) + clampi(hold, 0, int(r[1]) - 1)
	return int(r[0]) + int(floor(_anim_t * float(r[2]))) % int(r[1])


func _tex_flip(tex: Texture2D, at: Vector2, right: bool) -> void:
	var sz := tex.get_size()
	if right:
		draw_texture(tex, at)
	else:
		draw_texture_rect(tex, Rect2(at.x + sz.x, at.y, -sz.x, sz.y), false)


func _point(family: String, key: String, frame: int, fb: Vector2, w: int, right: bool) -> Vector2:
	var p := Tex.point(family, key, frame, fb)
	if not right:
		p.x = w - 1 - p.x
	return p


func _draw() -> void:
	# Sky, flags, the grandstand with the crowd, the judge at his table, the ring.
	draw_rect(Rect2(0, 0, 320, 40), Color("#0099db"))
	draw_rect(Rect2(0, 40, 320, 50), Color("#63c74d"))
	draw_rect(Rect2(0, 90, 320, 90), Color("#e4a672"))
	for x in range(0, 320, 24):
		draw_rect(Rect2(x + 6, 100 + (int(x / 24.0) % 3) * 20, 3, 1), Color("#d77643"))
	for k in 20:
		draw_texture(Tex.frame("flag", int(time * 3.0 + k) % 2, CONE_COLOURS[k % 4], Vector2i(8, 8)), Vector2(k * 16 + 2, 4 + (k % 2)))
	draw_rect(Rect2(0, 3, 320, 1), Color("#ffffff"))
	# The crowd: the whole roster sitting on the grandstand, bouncing on a cheer.
	draw_texture(Tex.frame("grandstand", 0, Color("#b86f50"), Vector2i(96, 32)), STAND_AT)
	var fans: Array[String] = []
	for r in Game.roster:
		if fans.size() < 10:
			fans.append(r)
	for i in fans.size():
		var bounce := -2.0 if crowd_t > 0.0 and int(time * 8.0 + i) % 2 == 0 else 0.0
		var row := i % 2
		var p := STAND_AT + Vector2(4 + (i / 2) * 18 + row * 9, 2 + row * 12 + bounce)
		draw_texture(Tex.frame(fans[i], 0, Game.rider_color(fans[i]), Vector2i(16, 16)), p.round())
	draw_rect(TABLE, Color("#733e39"))
	draw_rect(Rect2(TABLE.position.x + 4, TABLE.end.y, 2, 24), Color("#3e2731"))
	draw_rect(Rect2(TABLE.end.x - 6, TABLE.end.y, 2, 24), Color("#3e2731"))
	draw_texture(Tex.frame("judge", 1 if nod_t > 0.0 and int(time * 6.0) % 2 == 0 else 0, Color("#8b9bb4"), Vector2i(24, 32)), JUDGE_AT)
	draw_texture(Tex.frame("bell", 1 if bell_t >= 0.0 and int(bell_t * 12.0) % 2 == 0 else 0, Color("#feae34"), Vector2i(16, 16)), BELL_AT)
	var bell_phase := show.phase == ShowCourse.Phase.BELL_MARE or show.phase == ShowCourse.Phase.BELL_FOAL
	if bell_phase and Game.has_toddler():
		var bob := 2.0 if int(time * 4.0) % 2 == 0 else 0.0
		draw_texture(Tex.frame("seat_neigh", 0, Players.SEAT_COLORS[2], Vector2i(16, 16)), BELL_AT + Vector2(-20, -8 - bob))
	var fence := Tex.frame("show_fence", 0, Color("#ffffff"), Vector2i(16, 16))
	for x in range(0, 320, 16):
		draw_texture(fence, Vector2(x, FENCE_Y))
	# The jumps (the mare's), the mini jumps and the poles (the foal's).
	var things: Array = []
	for i in ShowCourse.MARE_JUMPS.size():
		var jp := ShowCourse.jump_pos(i)
		things.append([jp.y, Tex.frame("jump_%d" % (i + 1), 0, CONE_COLOURS[i % 4], Vector2i(24, 24)), jp + Vector2(-6, -24), true])
	if show.phase >= ShowCourse.Phase.BELL_FOAL and show.phase <= ShowCourse.Phase.FOAL:
		for x in ShowCourse.FOAL_JUMPS:
			things.append([MINI_Y, Tex.frame("mini_jump", 0, Color("#ffffff"), Vector2i(12, 10)), Vector2(x - 2, MINI_Y - 10), true])
	if show.phase == ShowCourse.Phase.PICKS:
		for k in ShowCourse.POLES.size():
			var px := ShowCourse.POLES[k]
			if k < show.pole_i:
				continue
			things.append([ShowCourse.POLE_Y - 1.0, Tex.frame("pick_pole", 0, Color("#ffffff"), Vector2i(8, 24)), Vector2(px - 14, ShowCourse.POLE_Y - 24), true, show.pole_colour[k]])
	# The horses (sorted by their feet with the jumps).
	var mf := _mare_frame()
	var mtex := Tex.frame("mare_" + Game.mare_coat, mf[0], Game.coat_color(Game.mare_coat), Vector2i(40, 32))
	things.append([mare_at.y + 0.5, mtex, (mare_at + Vector2(-20, -32)).round(), mf[1], -1, "mare", mf[0]])
	if show.phase >= ShowCourse.Phase.BELL_FOAL:
		var ff := _foal_frame()
		var ftex := Tex.frame("foal_" + Game.foal_coat, ff[0], Game.coat_color(Game.foal_coat), Vector2i(24, 20))
		things.append([foal_at.y + 0.5, ftex, (foal_at + Vector2(-12, -20)).round(), ff[1], -1, "foal", ff[0]])
	things.sort_custom(func(a, b): return a[0] < b[0])
	for t in things:
		_tex_flip(t[1], t[2], t[3])
		if t.size() > 4 and int(t[4]) >= 0:
			# The pick pole's flag colour.
			draw_rect(Rect2(t[2].x + 3, t[2].y + 2, 4, 3), CONE_COLOURS[int(t[4])])
		if t.size() > 5:
			if t[5] == "mare":
				_mare_extras(t[2], t[6], t[3])
			else:
				_foal_extras(t[2], t[6], t[3])
	if show.phase == ShowCourse.Phase.PICKS and show.foal_x <= ShowCourse.POLES[show.pole_i] + 0.5:
		_cones()
	if show.phase == ShowCourse.Phase.ROSETTES or show.phase == ShowCourse.Phase.DONE:
		_rosettes()
	_hud()


func _mare_extras(at: Vector2, frame: int, right: bool) -> void:
	var rib := Game.ribbon_name()
	if rib != "":
		var bp := _point("mare", "braid", frame, Vector2(30, 8), 40, right)
		draw_texture(Tex.frame("ribbon_" + rib, 0, Color("#e43b44"), Vector2i(8, 8)), at + bp - Vector2(4, 4))
	if show.phase >= ShowCourse.Phase.ROSETTES:
		return   # the riders have dismounted for their rosettes
	var sp := _point("mare", "rider", frame, Vector2(18, 4), 40, right)
	var jt := Tex.frame(Game.jockey_of(0), 0, Game.rider_color(Game.rider_of(0)), Vector2i(16, 16))
	if Game.has_toddler():
		var pp := _point("mare", "passenger", frame, Vector2(10, 6), 40, right)
		_tex_flip(Tex.frame(Game.jockey_of(2), 0, Game.rider_color(Game.rider_of(2)), Vector2i(16, 16)), at + pp - Vector2(8, 14), right)
	_tex_flip(jt, at + sp - Vector2(8, 14), right)


func _foal_extras(at: Vector2, frame: int, right: bool) -> void:
	var hp := _point("foal", "hat", frame, Vector2(17, 3), 24, right)
	var p := (at + hp).round()
	draw_rect(Rect2(p.x - 3, p.y - 1, 6, 1), Color("#c28569"))
	draw_rect(Rect2(p.x - 2, p.y - 3, 4, 2), Color("#feae34"))


func _cones() -> void:
	var fp := show.foal_pos()
	var picked := show.picks[show.pole_i] if show.picked_t >= 0.0 and show.pole_i < show.picks.size() else -1
	for k in 4:
		var c := show.cone_at(k)
		var p := fp + CONE_OFFSETS[k] + Vector2(-4, -10)
		if k == picked:
			draw_circle(p + Vector2(4, 5), 8, Color("#ffffff"))
		draw_texture(Tex.frame(CONE_NAMES[c], 0, CONE_COLOURS[c], Vector2i(8, 10)), p.round())


func _rosettes() -> void:
	# Everybody's rosette, shown in turn: over the mare, over the foal, then
	# over each rider, standing in a row beside the horses.
	var riders_at := Vector2(234, 170)
	var slots: Array[Vector2] = []
	var seated: Array[int] = []
	for s in Players.SEAT_COUNT:
		if Players.is_seated(s):
			seated.append(s)
	for i in seated.size():
		var rp := riders_at + Vector2(i * 22, 0)
		var hop := -2.0 if int(time * 4.0 + i) % 2 == 0 else 0.0
		draw_texture(Tex.frame(Game.jockey_of(seated[i]), 0, Game.rider_color(Game.rider_of(seated[i])), Vector2i(16, 16)),
			(rp + Vector2(-8, -16 + hop)).round())
	for r in show.rosettes:
		var who: String = r.who
		if who == "mare":
			slots.append(mare_at + Vector2(10, -42))
		elif who == "foal":
			slots.append(foal_at + Vector2(4, -32))
		else:
			var seat := int(who.substr(5))
			slots.append(riders_at + Vector2(seated.find(seat) * 22, -34))
	for i in mini(show.rosette_shown, show.rosettes.size()):
		var col: String = show.rosettes[i].colour
		var p: Vector2 = slots[i]
		var bob := 1.0 if int(time * 3.0 + i) % 2 == 0 else 0.0
		draw_texture(Tex.frame("rosette_" + col, 0, Color("#0099db"), Vector2i(12, 16)), (p + Vector2(-6, -8 - bob)).round())
	if carrot_t >= 0.0 and carrot_t < 0.6:
		var k := clampf(carrot_t / 0.5, 0.0, 1.0)
		var from := JUDGE_AT + Vector2(4, 20)
		var to := foal_at + Vector2(10, -12)
		var cp := from.lerp(to, k) + Vector2(0, -30.0 * sin(PI * k))
		draw_texture(Tex.frame("carrot", 0, Color("#f77622"), Vector2i(12, 8)), (cp - Vector2(6, 4)).round())
	elif carrot_t >= 0.6 and carrot_t < 1.8:
		draw_texture(Tex.frame("heart", 0, Color("#e43b44"), Vector2i(8, 8)), (foal_at + Vector2(6, -30 - carrot_t * 6.0)).round())


func _hud() -> void:
	# The mare's round: one little pole per jump, bright once cleared.
	for i in ShowCourse.MARE_JUMPS.size():
		var passed := i < show.jump_i
		var c: Color = CONE_COLOURS[i % 4] if passed else Color("#3a4466")
		draw_rect(Rect2(124 + i * 12, 16, 8, 3), c)
		if passed and show.clean[i]:
			draw_rect(Rect2(126 + i * 12, 20, 4, 2), Color("#ffffff"))


func _finish() -> void:
	next_screen = Game.next_after("show")
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred(next_screen)


func _back_to_join() -> void:
	next_screen = "join"
	set_process(false)
	if auto_goto:
		Game.goto.call_deferred("join")
