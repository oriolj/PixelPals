extends Node2D
## Party: every animal in a row on a stage, dancing on the beat; each one in
## turn steps into the spotlight and says its sound. The stars from the
## keeper's bucket rain down with the confetti. After the last song (about
## 11 s), or when the keeper presses "a", it goes back to select.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Animals := preload("res://scripts/vector/animals.gd")
const Rules := preload("res://scripts/zoo/rules.gd")

const FIRST_TURN := 1.2
const TURN_SECONDS := 1.4
const TAIL_SECONDS := 1.6
const SKIP_GUARD := 1.5
const STAGE_Y := 560.0
const BUCKET := Vector2(640, 92)

var auto_goto := true
var next_screen := ""

var time := 0.0
var done := false
var turn := -1
var total_stars := 0
var stars_dropped := 0
var dancers: Array[Node2D] = []
var keeper: Node2D
var bucket: Node2D
var spot: Node2D
var fx: Array[Dictionary] = []
var rng := RandomNumberGenerator.new()
var _star_t := 0.6
var _confetti_t := 0.0
var _singer_cd := 0.0


func _ready() -> void:
	rng.randomize()
	total_stars = maxi(3, Game.stars)
	_build()
	Sfx.stop_music()
	Sfx.play("party")


func _process(delta: float) -> void:
	step(delta)


func end_time() -> float:
	return FIRST_TURN + Rules.ANIMALS.size() * TURN_SECONDS + TAIL_SECONDS


func _build() -> void:
	var bg := VA.part(self, "backdrop")
	VA.fill(bg, PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, 720), Vector2(0, 720)]), Color("#5b3f8c"))
	# Bunting across the top.
	for i in 17:
		var x := i * 80.0
		var tri := PackedVector2Array([Vector2(x, 14), Vector2(x + 70, 14), Vector2(x + 35, 60)])
		VA.shape(bg, tri, Pal.CONFETTI[i % Pal.CONFETTI.size()], Pal.OUTLINE, 3.5)
	VA.stroke(bg, PackedVector2Array([Vector2(0, 14), Vector2(1280, 14)]), Pal.OUTLINE, 5.0)
	# Curtains.
	for side in [-1, 1]:
		var x0 := 0.0 if side < 0 else 1280.0
		var pts := PackedVector2Array([Vector2(x0, 0), Vector2(x0 - side * 150, 0), Vector2(x0 - side * 95, 260),
			Vector2(x0 - side * 120, STAGE_Y), Vector2(x0, STAGE_Y)])
		VA.shape(bg, pts, Color("#d8455b"), Pal.OUTLINE, 5.0)
		for k in 3:
			VA.stroke(bg, PackedVector2Array([Vector2(x0 - side * (30 + k * 32), 20), Vector2(x0 - side * (24 + k * 26), STAGE_Y - 10)]), Color("#b0344a"), 4.0)
	# Stage floor.
	VA.shape(bg, PackedVector2Array([Vector2(-10, STAGE_Y - 40), Vector2(1290, STAGE_Y - 40), Vector2(1290, 730), Vector2(-10, 730)]), Pal.FENCE, Pal.OUTLINE, 5.0)
	for k in 6:
		VA.stroke(bg, PackedVector2Array([Vector2(0, STAGE_Y + k * 30), Vector2(1280, STAGE_Y + k * 30)]), Pal.FENCE_DARK, 3.0)
	spot = VA.part(self, "spot")
	VA.fill(spot, PackedVector2Array([Vector2(-40, -560), Vector2(40, -560), Vector2(130, 0), Vector2(-130, 0)]), Color(1.0, 0.97, 0.75, 0.22))
	VA.fill(spot, VA.ellipse(130, 26), Color(1.0, 0.97, 0.75, 0.35))
	spot.visible = false
	for i in Rules.ANIMALS.size():
		var a := Animals.build(Rules.ANIMALS[i])
		a.scale = Vector2.ONE * (0.86 if Rules.ANIMALS[i] == "giraffe" else 1.0)
		a.position = Vector2(_slot_x(i), STAGE_Y)
		add_child(a)
		dancers.append(a)
	keeper = Props.keeper(Game.hat_color(0))
	keeper.scale = Vector2(1.3, 1.3)
	keeper.position = Vector2(640, 700)
	add_child(keeper)
	bucket = Node2D.new()
	bucket.position = BUCKET
	add_child(bucket)
	VA.shape(bucket, PackedVector2Array([Vector2(-40, -34), Vector2(40, -34), Vector2(30, 34), Vector2(-30, 34)]), Pal.BOWL, Pal.OUTLINE, 5.0)
	VA.stroke(bucket, VA.arc(40, 40, PI, TAU, Vector2(0, -34), 16), Pal.OUTLINE, 5.0)
	for i in 5:
		var s := Props.star(0.7)
		s.position = Vector2(-28 + i * 14, -36 - (i % 2) * 8)
		bucket.add_child(s)
		bucket.move_child(s, 0)
	bucket.rotation = 2.6


func _slot_x(i: int) -> float:
	return 170.0 + i * 188.0


func step(dt: float) -> void:
	if done:
		return
	time += dt
	_singer_cd = maxf(0.0, _singer_cd - dt)
	var beat := time / Rules.BEAT
	var new_turn := int(floor((time - FIRST_TURN) / TURN_SECONDS)) if time >= FIRST_TURN else -1
	if new_turn != turn and new_turn < dancers.size():
		turn = new_turn
		if turn >= 0:
			Game.voice(Rules.ANIMALS[turn])
	for i in dancers.size():
		var a := dancers[i]
		var base := Vector2.ONE * (0.86 if Rules.ANIMALS[i] == "giraffe" else 1.0)
		if i == turn and time - FIRST_TURN - turn * TURN_SECONDS < TURN_SECONDS:
			var k := clampf((time - FIRST_TURN - turn * TURN_SECONDS) / 0.2, 0.0, 1.0)
			a.scale = base * (1.0 + 0.2 * k)
			a.position.y = STAGE_Y + 24.0 * k
			Animals.pose(a, "sing", time)
		else:
			a.scale = base
			a.position.y = STAGE_Y
			Animals.pose(a, "dance", beat + i * 0.5)
	spot.visible = turn >= 0 and turn < dancers.size()
	if spot.visible:
		spot.position = Vector2(_slot_x(turn), STAGE_Y + 24)
	Props.keeper_cheer(keeper, time)
	bucket.rotation = 2.6 + sin(time * 4.0) * 0.12

	# Stars pour from the bucket, then confetti keeps falling.
	_star_t -= dt
	var every := 5.0 / float(total_stars)
	while _star_t <= 0.0 and stars_dropped < total_stars:
		_star_t += every
		stars_dropped += 1
		var s := Props.star(0.9)
		add_child(s)
		fx.append({"node": s, "pos": BUCKET + Vector2(rng.randf_range(-20, 20), 20),
			"vel": Vector2(rng.randf_range(-260, 260), rng.randf_range(-120, 40)), "grav": 380.0, "spin": rng.randf_range(-4, 4)})
		Sfx.play("star", 1.0 + 0.03 * (stars_dropped % 12), -6.0)
	_confetti_t -= dt
	while _confetti_t <= 0.0:
		_confetti_t += 0.07
		var c := Props.confetti(Pal.CONFETTI[rng.randi() % Pal.CONFETTI.size()])
		add_child(c)
		fx.append({"node": c, "pos": Vector2(rng.randf_range(0, 1280), -10),
			"vel": Vector2(0, rng.randf_range(90, 160)), "grav": 0.0, "spin": rng.randf_range(-5, 5), "sway": true})
	for i in range(fx.size() - 1, -1, -1):
		var p := fx[i]
		p.vel.y += p.grav * dt
		if p.get("sway", false):
			p.vel.x = sin(time * 3.0 + i) * 50.0
		p.pos += p.vel * dt
		p.node.position = p.pos
		p.node.rotation += p.spin * dt
		if p.pos.y > 760:
			p.node.queue_free()
			fx.remove_at(i)

	# The singer can still make the whole row cheer.
	if Players.just_pressed(2, "any") and _singer_cd <= 0.0:
		_singer_cd = Rules.SINGER_COOLDOWN
		Sfx.play("ready", 1.2, -6.0)
	if time >= end_time() or (time >= SKIP_GUARD and Players.just_pressed(0, "a")):
		done = true
		next_screen = "select"
		if auto_goto:
			Game.goto.call_deferred("select")
