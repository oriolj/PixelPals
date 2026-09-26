extends Node2D
## Asset gallery (demo only: `make gallery`): every asset in every pose on a
## checkerboard, plus a solid-silhouette row, for the contact-sheet review.
## Pages advance every PAGE_SECONDS; the keeper's "a" also advances.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Animals := preload("res://scripts/vector/animals.gd")
const FoodWheel := preload("res://scripts/zoo/food_wheel.gd")
const Rules := preload("res://scripts/zoo/rules.gd")

const PAGE_SECONDS := 3.0
const PAGES := 5

var page := -1
var time := 0.0
var _content: Node2D


func _ready() -> void:
	Sfx.stop_music()
	show_page(0)


func _process(delta: float) -> void:
	time += delta
	var want := int(time / PAGE_SECONDS) % PAGES
	if Players.just_pressed(0, "a"):
		time = (page + 1) * PAGE_SECONDS
		want = (page + 1) % PAGES
	if want != page:
		show_page(want)


func show_page(p: int) -> void:
	page = p
	if _content:
		_content.free()
	_content = Node2D.new()
	add_child(_content)
	match p:
		0: _poses(["monkey", "penguin", "giraffe"])
		1: _poses(["rabbit", "elephant", "seal"])
		2: _silhouettes()
		3: _props()
		4: _enclosures()
	queue_redraw()


func _draw() -> void:
	for y in 18:
		for x in 32:
			draw_rect(Rect2(x * 40, y * 40, 40, 40), Color("#e6e1ea") if (x + y) % 2 == 0 else Color("#d3cddb"))


func _poses(kinds: Array) -> void:
	for r in kinds.size():
		for c in Animals.GALLERY_POSES.size():
			var pz: Array = Animals.GALLERY_POSES[c]
			var a := Animals.build(kinds[r])
			a.scale = Vector2.ONE * (0.72 if kinds[r] == "giraffe" else 0.9)
			a.position = Vector2(72 + c * 142, 222 + r * 240)
			Animals.pose(a, pz[0], 0.3 if pz[0] == "shake" else 0.0, pz[1])
			_content.add_child(a)


func _silhouettes() -> void:
	for i in Rules.ANIMALS.size():
		var kind: String = Rules.ANIMALS[i]
		for row in 2:
			var a := Animals.build(kind)
			a.position = Vector2(95 + i * 196, 300 + row * 330)
			if kind == "giraffe":
				a.scale = Vector2(0.92, 0.92)
			if row == 1:
				a.modulate = Color.BLACK
				a.get_node("shadow").visible = false
			_content.add_child(a)
	var k := Props.keeper(Game.HATS[0])
	k.position = Vector2(1240, 300)
	_content.add_child(k)


func _props() -> void:
	# Keeper walk cycle (4 poses), standing and cheering, with three hat colours.
	for i in 6:
		var k := Props.keeper(Game.HATS[i % Game.HATS.size()])
		k.position = Vector2(60 + i * 90, 130)
		if i < 4:
			Props.keeper_pose(k, i)
		elif i == 4:
			Props.keeper_pose(k, -1)
		else:
			Props.keeper_cheer(k, 0.1)
		_content.add_child(k)
	var c := Props.cart()
	c.position = Vector2(680, 130)
	Props.cart_stars(c, 7)
	_content.add_child(c)
	# Foods at wheel size and thrown size.
	for i in 4:
		var f := Props.food(Rules.FOODS[i])
		f.position = Vector2(820 + i * 110, 90)
		_content.add_child(f)
		var small := Props.food(Rules.FOODS[i])
		small.scale = Vector2(0.62, 0.62)
		small.position = Vector2(820 + i * 110, 160)
		_content.add_child(small)
	# The wheel with a selection and the glow hint, and a plain one.
	var w: Node2D = FoodWheel.new()
	w.position = Vector2(150, 420)
	_content.add_child(w)
	w.open(true)
	w.select_dir(Vector2i.RIGHT)
	w.set_hint(Rules.Hint.GLOW, "banana")
	for _i in 30:
		w.animate(1.0 / 30.0)
	var w2: Node2D = FoodWheel.new()
	w2.position = Vector2(410, 420)
	_content.add_child(w2)
	w2.open(true)
	for _i in 30:
		w2.animate(1.0 / 30.0)
	# Bubbles: empty bowl, and the faint hint.
	var b := Props.bubble()
	b.position = Vector2(600, 330)
	_content.add_child(b)
	var b2 := Props.bubble()
	b2.position = Vector2(600, 470)
	Props.bubble_hint(b2, "fish", true)
	_content.add_child(b2)
	# Particles and icons.
	var row := [Props.star(), Props.heart(), Props.note(Players.SEAT_COLORS[2]), Props.bell(),
		Props.plate(false), Props.plate(true)]
	for i in row.size():
		row[i].position = Vector2(730 + i * 80, 330)
		_content.add_child(row[i])
	for i in 6:
		var cf := Props.confetti(Pal.CONFETTI[i])
		cf.position = Vector2(1190 + (i % 2) * 30, 300 + int(i / 2) * 24)
		cf.rotation = i * 0.6
		_content.add_child(cf)
	var icons := [Props.role_icon(0, Players.SEAT_COLORS[0]), Props.role_icon(1, Players.SEAT_COLORS[1]),
		Props.role_icon(2, Players.SEAT_COLORS[2]), Props.icon_pad(Pal.CREAM), Props.icon_kb(Pal.CREAM),
		Props.arrow(Pal.CREAM, -1), Props.arrow(Pal.CREAM, 1), Props.check(Color("#5cb566"))]
	for i in icons.size():
		icons[i].position = Vector2(730 + (i % 4) * 130, 460 + int(i / 4) * 100)
		_content.add_child(icons[i])
	# Buddies with hats.
	for i in 6:
		var bd := Animals.build(Rules.ANIMALS[i])
		bd.scale = Vector2(0.34, 0.34)
		Animals.add_hat(bd, Game.HATS[i])
		bd.position = Vector2(80 + i * 70, 680)
		_content.add_child(bd)


func _enclosures() -> void:
	for i in Rules.ANIMALS.size():
		var kind: String = Rules.ANIMALS[i]
		var e := Props.enclosure(kind, Vector2(330, 215), i >= 3)
		e.scale = Vector2(1.1, 1.1)
		e.position = Vector2(40 + (i % 3) * 410, 70 + int(i / 3) * 330)
		_content.add_child(e)
		var a := Animals.build(kind)
		a.position = Vector2(165, 170)
		if kind == "giraffe":
			a.scale = Vector2(0.92, 0.92)
		e.add_child(a)
		e.move_child(e.get_node("front"), -1)
