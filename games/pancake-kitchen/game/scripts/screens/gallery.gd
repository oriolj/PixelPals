extends Node2D
## Gallery: every asset and state, for review (make shot SHOT_SCREEN=gallery).
## Four pages, PAGE_SECONDS each: food and kitchen, customers in every pose,
## chefs + gag animals + effects + icons, and silhouettes (the same art
## drawn through a black modulate, to check that every shape reads).

const VA := preload("res://scripts/vector_art.gd")
const Pal := preload("res://scripts/kitchen/palette.gd")
const DrawNode := preload("res://scripts/draw_node.gd")
const Rules := preload("res://scripts/kitchen/rules.gd")

const PAGE_SECONDS := 2.5
const PAGES := 4

var time := 0.0
var page := 0
var _canvas: Node2D
var _shadow: Node2D


func _ready() -> void:
	_canvas = DrawNode.make(_draw_page)
	add_child(_canvas)
	_shadow = DrawNode.make(_draw_silhouettes)
	_shadow.modulate = Color(0, 0, 0)
	add_child(_shadow)
	Sfx.stop_music()


func _process(delta: float) -> void:
	time += delta
	page = int(time / PAGE_SECONDS) % PAGES
	_shadow.visible = page == 3
	_canvas.queue_redraw()
	_shadow.queue_redraw()


func _draw_page(ci: Node2D) -> void:
	ci.draw_rect(Rect2(0, 0, 1280, 720), Pal.WALL if page != 3 else Color("#f4f0ff"))
	match page:
		0: _food(ci)
		1: _customers(ci)
		2: _cast(ci)


func _food(ci: Node2D) -> void:
	# Pancake states: raw, cooking (bubbles), golden, mid-flip thin, flipped
	# over (underside), squash on landing, pouring.
	var states := [[0.0, 0.0, 1.0, 0.0, 0.0, 1.0], [0.0, 0.6, 1.0, 0.0, 0.8, 1.0],
		[1.0, 1.0, 1.0, 0.0, 0.0, 1.0], [0.2, 1.0, 0.15, 0.0, 0.0, 1.0],
		[0.2, 1.0, -0.8, 0.0, 0.0, 1.0], [1.0, 1.0, 1.0, 1.0, 0.0, 1.0], [0.0, 0.0, 1.0, 0.0, 0.0, 0.5]]
	for i in states.size():
		var s: Array = states[i]
		VA.pancake(ci, Vector2(100 + i * 180, 70), s[0], s[1], s[2], s[3], s[4], s[5], i)
	for i in 4:
		VA.topping(ci, Rules.TOPPINGS[i], Vector2(90 + i * 90, 170), 0.0, 1.6)
		VA.jar(ci, Rules.TOPPINGS[i], Vector2(500 + i * 120, 180), i == 1, Players.SEAT_COLORS[1], 0.0, time)
	VA.pan(ci, Vector2(1120, 170), Players.SEAT_COLORS[0])
	VA.stove(ci, 40, 460, 560, 700, 250, time)
	VA.pan(ci, Vector2(250, 530), Players.SEAT_COLORS[0])
	VA.pancake(ci, Vector2(250, 504), 0.1, 0.9, 1.0, 0.0, 0.9, 1.0, 2)
	VA.stack(ci, Vector2(620, 640), 0, [], 0.0, time)
	var tops := []
	var r := Rules.new(3)
	for k in 12:
		tops.append({"kind": Rules.TOPPINGS[k % 4], "level": 2, "pos": r.random_spot(), "lift": (k / 4) * 2.5, "rot": 0.3 * k, "age": 1.0})
	VA.stack(ci, Vector2(860, 640), 3, [], 1.0, time)
	VA.stack(ci, Vector2(1110, 640), 3, tops, 0.0, time)
	VA.steam(ci, Vector2(250, 470), fmod(time, 1.0))


func _customers(ci: Node2D) -> void:
	var poses := [{"mouth": "smile"}, {"mouth": "open", "look": Vector2(0, 1)},
		{"mouth": "chew", "eyes": "happy"}, {"mouth": "grin", "eyes": "happy", "arms": 1.0}]
	for i in Rules.ANIMALS.size():
		for j in poses.size():
			var at := Vector2(75 + j * 100 + (i % 3) * 430, 330 + (i / 3) * 340)
			VA.creature(ci, Transform2D(0.0, Vector2(0.48, 0.48), 0.0, at), Rules.ANIMALS[i], poses[j])


func _cast(ci: Node2D) -> void:
	for i in Game.CHEFS.size():
		VA.creature(ci, Transform2D(0.0, Vector2(0.62, 0.62), 0.0, Vector2(120 + i * 200, 330)), Game.CHEFS[i],
			{"hat": Pal.HATS[i], "look": Vector2(0.5, 0)})
	VA.dog(ci, Transform2D(0.0, Vector2(1100, 340)), time, 0.0)
	VA.dog(ci, Transform2D(0.0, Vector2(1100, 520)), time, 1.0)
	VA.shelf_cat(ci, Transform2D(0.0, Vector2(140, 520)), time, 0.0)
	VA.shelf_cat(ci, Transform2D(0.0, Vector2(340, 520)), time, 1.0)
	VA.sparkle(ci, Vector2(480, 460), 20, Players.SEAT_COLORS[2], time)
	VA.star(ci, Vector2(560, 460), 20)
	VA.heart(ci, Vector2(640, 460), 20)
	for k in 6:
		VA.confetti(ci, Vector2(720 + k * 30, 460), Pal.CONFETTI[k], time + k, k)
	for s in 3:
		VA.role_icon(ci, s, Vector2(160 + s * 170, 640), Players.SEAT_COLORS[s], 1.2)
	VA.device_icon(ci, true, Vector2(720, 640), Color.WHITE, 1.4)
	VA.device_icon(ci, false, Vector2(860, 640), Color.WHITE, 1.4)


func _draw_silhouettes(ci: Node2D) -> void:
	if page != 3:
		return
	for i in Rules.ANIMALS.size():
		VA.creature(ci, Transform2D(0.0, Vector2(0.62, 0.62), 0.0, Vector2(130 + i * 250, 300)), Rules.ANIMALS[i], {})
	for i in Game.CHEFS.size():
		VA.creature(ci, Transform2D(0.0, Vector2(0.62, 0.62), 0.0, Vector2(130 + i * 200, 640)), Game.CHEFS[i], {"hat": Color.WHITE})
	VA.dog(ci, Transform2D(0.0, Vector2(1080, 640)), 0.0)
	VA.shelf_cat(ci, Transform2D(0.0, Vector2(1180, 500)), 0.0)
