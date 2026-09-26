extends Node2D
## The cross-shaped food wheel (220 px): up banana, right fish, down carrot,
## left hay. The selected slot gets a ring in the feeder's colour; the hint
## ladder makes the right slot wiggle, then glow.

const VA := preload("res://scripts/vector/vector_art.gd")
const Pal := preload("res://scripts/vector/palette.gd")
const Props := preload("res://scripts/vector/props.gd")
const Rules := preload("res://scripts/zoo/rules.gd")

const ARM := 74.0
const SLOT_R := 38.0

## "" when nothing is picked yet.
var selected := ""
## Rules.Hint for the right food, and which food that is.
var hint := Rules.Hint.NONE
var hint_food := ""
var ring_color := Color("#ffcd75")
var open_amount := 0.0          # 0 closed .. 1 open (pop-in animation)
var is_open := false

var _slots := {}   # food -> Node2D
var _glows := {}   # food -> Node2D
var _ring: Node2D
var _time := 0.0
var _bump := 0.0


func _ready() -> void:
	var hub := Node2D.new()
	add_child(hub)
	VA.shape(hub, VA.circle(22), Pal.CREAM, Pal.OUTLINE, 4.0)
	for d in Rules.WHEEL:
		var dir := Vector2(d)
		VA.fill(hub, PackedVector2Array([dir * 20 + dir.orthogonal() * 7, dir * 20 - dir.orthogonal() * 7, dir * 31]), Pal.OUTLINE)
		VA.limb(hub, PackedVector2Array([dir * 22, dir * (ARM - SLOT_R)]), Pal.CREAM, 10.0)
	for d in Rules.WHEEL:
		var food: String = Rules.WHEEL[d]
		var slot := Node2D.new()
		slot.name = "slot_" + food
		slot.position = Vector2(d) * ARM
		add_child(slot)
		var glow := Node2D.new()
		slot.add_child(glow)
		for k in 3:
			VA.fill(glow, VA.circle(SLOT_R + 18 - k * 6), Color(1.0, 0.95, 0.55, 0.22 + k * 0.1))
		glow.visible = false
		_glows[food] = glow
		VA.shape(slot, VA.circle(SLOT_R), Pal.CREAM, Pal.OUTLINE, 4.5)
		var f := Props.food(food)
		f.scale = Vector2(0.9, 0.9)
		slot.add_child(f)
		_slots[food] = slot
	_ring = Node2D.new()
	_ring.name = "ring"
	add_child(_ring)
	var r1 := VA.stroke(_ring, VA.circle(SLOT_R + 7), Pal.OUTLINE, 13.0)
	r1.closed = true
	var r2 := VA.stroke(_ring, VA.circle(SLOT_R + 7), ring_color, 8.0)
	r2.closed = true
	r2.name = "ring_color"
	_ring.visible = false
	scale = Vector2.ZERO
	visible = false


func set_ring_color(c: Color) -> void:
	ring_color = c
	if _ring:
		(_ring.get_node("ring_color") as Line2D).default_color = c


## Picks the food for a 4-direction input; returns true when it changed.
func select_dir(dir: Vector2i) -> bool:
	var f := Rules.food_for_dir(dir)
	if f == "" or f == selected:
		return false
	selected = f
	_bump = 0.18
	return true


func set_hint(level: int, food: String) -> void:
	hint = level
	hint_food = food


func open(on: bool) -> void:
	if on == is_open:
		return
	is_open = on
	if on:
		selected = ""
		visible = true


func slot_position(food: String) -> Vector2:
	return (_slots[food] as Node2D).position if _slots.has(food) else Vector2.ZERO


func animate(dt: float) -> void:
	_time += dt
	_bump = maxf(0.0, _bump - dt)
	open_amount = move_toward(open_amount, 1.0 if is_open else 0.0, dt * 6.0)
	var s := _ease_back(open_amount)
	scale = Vector2(s, s)
	visible = open_amount > 0.01
	for food in _slots:
		var slot: Node2D = _slots[food]
		slot.rotation = 0.0
		slot.scale = Vector2.ONE
		(_glows[food] as Node2D).visible = false
		if food == hint_food and hint >= Rules.Hint.WIGGLE:
			slot.rotation = sin(_time * 14.0) * 0.22
			slot.scale = Vector2.ONE * (1.0 + 0.06 * absf(sin(_time * 7.0)))
		if food == hint_food and hint >= Rules.Hint.GLOW:
			var g: Node2D = _glows[food]
			g.visible = true
			g.scale = Vector2.ONE * (1.0 + 0.1 * sin(_time * 6.0))
			slot.scale *= 1.1
		if food == selected:
			slot.scale *= 1.12 + (0.1 if _bump > 0.0 else 0.0)
	_ring.visible = selected != ""
	if selected != "":
		_ring.position = slot_position(selected)
		_ring.rotation = (_slots[selected] as Node2D).rotation
		_ring.scale = (_slots[selected] as Node2D).scale


static func _ease_back(x: float) -> float:
	if x <= 0.0:
		return 0.0
	var c := 1.7
	var y := x - 1.0
	return 1.0 + (c + 1.0) * y * y * y + c * y * y
