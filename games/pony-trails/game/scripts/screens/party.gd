extends Node2D
## The party: back in the stable at dusk. The day's rosettes fly onto the
## rosette wall next to every earlier day's (kept between sessions), the lucky
## horseshoes hang over the door, the mare eats her hay and the foal lies down
## to sleep. After STAY_SECONDS, or the Rider's A, back to select.

const Tex := preload("res://scripts/view/tex.gd")
const Confetti := preload("res://scripts/view/confetti.gd")
const RosetteWall := preload("res://scripts/logic/rosette_wall.gd")

const STAY_SECONDS := 14.0
const SKIP_GUARD := 1.5
const FLY_EVERY := 0.6
const FLY_TIME := 0.7
const FLOOR_Y := 164
const BOARD := Rect2(16, 20, 208, 112)      # where the days are pinned (points.json rosette_wall.board)
const DAYS_SHOWN := 8
const GROUP_W := 102
const ROW_H := 27
const DOOR := Rect2(244, 64, 56, 108)       # rosette_wall.door
const MARE_AT := Vector2(120, FLOOR_Y)
const FOAL_AT := Vector2(178, FLOOR_Y)

var auto_goto := true
var next_screen := ""
var time := 0.0
var today: Array[String] = []           # today's rosette colours
var today_lucky := 0
var _confetti: Node2D


func _ready() -> void:
	record_day()
	_confetti = Confetti.new()
	_confetti.rate = 10.0
	add_child(_confetti)
	Sfx.stop_music()
	Sfx.play("rosette_fanfare")
	Sfx.music("music_stable")


## Pins today's rosettes and horseshoes on the wall and saves it (once per day).
func record_day() -> void:
	today.clear()
	for r in Game.day.get("rosettes", []):
		today.append(str(r.colour))
	if today.is_empty():
		today.assign(["blue", "red"])
	today_lucky = int(Game.day.get("lucky", 0))
	if not Game.day.get("saved", false):
		Game.wall.add_day(today, today_lucky)
		Game.wall.save()
		Game.day.saved = true


func _process(delta: float) -> void:
	step(delta)


func step(dt: float) -> void:
	time += dt
	_confetti.tick(dt)
	var n := today.size()
	var landed_before := int((time - dt - FLY_TIME) / FLY_EVERY) + 1 if time - dt >= FLY_TIME else 0
	var landed_now := int((time - FLY_TIME) / FLY_EVERY) + 1 if time >= FLY_TIME else 0
	if landed_now > landed_before and landed_now <= n:
		Sfx.play("horseshoe_clink" if landed_now % 2 == 0 else "ready", 1.0 + 0.05 * landed_now, -4.0)
	if Players.just_pressed(Players.Seat.HONKER, "any") and Players.is_seated(Players.Seat.HONKER):
		Sfx.play("nicker", randf_range(0.9, 1.2))
		_confetti.burst(Vector2(randf_range(40, 280), 120), 12)
	var skip := time >= SKIP_GUARD and Players.just_pressed(Players.Seat.DRIVER, "a")
	if (time >= STAY_SECONDS or skip) and next_screen == "":
		next_screen = "select"
		set_process(false)
		if auto_goto:
			Game.goto.call_deferred("select")
	queue_redraw()


## Screen position of rosette k of day d (d = index among the days shown).
func slot(d: int, k: int) -> Vector2:
	var col := d % 2
	var row := int(d / 2.0)
	return BOARD.position + Vector2(8 + col * GROUP_W + k * 14, 6 + row * ROW_H)


func _draw() -> void:
	draw_texture(Tex.frame("rosette_wall", 0, Color("#733e39"), Vector2i(320, 180)), Vector2.ZERO)
	# The board of days: every earlier day's rosettes, today's flying in.
	var days: Array = Game.wall.days()
	var first := maxi(0, days.size() - DAYS_SHOWN)
	var shown := days.slice(first)
	for d in shown.size():
		var is_today := first + d == days.size() - 1
		var cols: Array = shown[d]
		if is_today:
			var p := slot(d, 0) + Vector2(-3, -2)
			draw_rect(Rect2(p, Vector2(cols.size() * 14 + 4, 20)), Color("#feae34", 0.35))
		for k in cols.size():
			var at := slot(d, k)
			if is_today:
				var t0 := k * FLY_EVERY
				if time < t0:
					continue
				var f := clampf((time - t0) / FLY_TIME, 0.0, 1.0)
				var from := MARE_AT + Vector2(0, -40) if k % 2 == 0 else FOAL_AT + Vector2(0, -24)
				at = from.lerp(at, f) + Vector2(0, -30.0 * sin(PI * f))
			draw_texture(Tex.frame("rosette_" + str(cols[k]), 0, Color("#0099db"), Vector2i(12, 16)), at.round())
	# The lucky horseshoes over the door (today's glinting).
	var hs := mini(Game.wall.horseshoes(), 12)
	for i in hs:
		# Two rows of six over the door's lintel, lucky side up.
		var p2 := DOOR.position + Vector2(2 + (i % 6) * 9, -12 - int(i / 6.0) * 9)
		var glint := i >= hs - today_lucky and int(time * 4.0 + i) % 2 == 0
		draw_texture(Tex.frame("lucky_horseshoe", 1 if glint else 0, Color("#feae34"), Vector2i(8, 8)), p2.round())
	# A lantern, the hay, the mare munching, the foal asleep.
	draw_texture(Tex.frame("lantern", int(time * 3.0) % 2, Color("#feae34"), Vector2i(8, 12)), Vector2(214, 40))
	draw_texture(Tex.frame("hay_rack", 0, Color("#e4a672"), Vector2i(24, 16)), MARE_AT + Vector2(16, -14))
	var mr := Tex.anim("mare", "munch")
	var mf := int(mr[0]) + int(time * maxf(1.0, float(mr[2]))) % int(mr[1])
	draw_texture(Tex.frame("mare_" + Game.mare_coat, mf, Game.coat_color(Game.mare_coat), Vector2i(40, 32)), MARE_AT + Vector2(-20, -32))
	var rib := Game.ribbon_name()
	if rib != "":
		var bp := Tex.point("mare", "braid", mf, Vector2(30, 8))
		draw_texture(Tex.frame("ribbon_" + rib, 0, Color("#e43b44"), Vector2i(8, 8)), MARE_AT + Vector2(-20, -32) + bp - Vector2(4, 4))
	var sr := Tex.anim("foal", "sleep")
	var sf := int(sr[0]) + int(time * maxf(0.5, float(sr[2]))) % int(sr[1])
	draw_texture(Tex.frame("foal_" + Game.foal_coat, sf, Game.coat_color(Game.foal_coat), Vector2i(24, 20)), FOAL_AT + Vector2(-12, -20))
	# Zzz: three little rising dots over the sleeping foal.
	for k in 3:
		var zt := fmod(time * 0.8 + k * 0.33, 1.0)
		draw_rect(Rect2(FOAL_AT.x + 8 + zt * 8.0, FOAL_AT.y - 20 - zt * 16.0, 2, 2), Color("#ffffff", 1.0 - zt))
	# The riders, cheering in a row.
	var i2 := 0
	for s in Players.SEAT_COUNT:
		if not Players.is_seated(s):
			continue
		var hop := -2.0 if int(time * 4.0 + s) % 2 == 0 else 0.0
		draw_texture(Tex.frame(Game.jockey_of(s), int(time * 3.0) % 2, Game.rider_color(Game.rider_of(s)), Vector2i(16, 16)),
			Vector2(40 + i2 * 20, FLOOR_Y - 16 + hop))
		i2 += 1
