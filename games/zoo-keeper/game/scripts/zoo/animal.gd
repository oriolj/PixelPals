extends Node2D
## One zoo animal: a tiny state machine (idle, hungry, eating, singing,
## dancing, refusing) over a vector rig. No pathfinding: it wanders inside its
## enclosure rectangle and walks to the gate when hungry.
##
## The zoo screen owns the rules (right food, stars, meals); the animal only
## reacts and animates. Hunger never turns into sadness: a hungry animal just
## keeps bouncing.

const Animals := preload("res://scripts/vector/animals.gd")
const Props := preload("res://scripts/vector/props.gd")
const Rules := preload("res://scripts/zoo/rules.gd")

const WALK_SPEED := 55.0
const EAT_SECONDS := 1.5
const SING_SECONDS := 0.9
const DANCE_SECONDS := 1.8
const SNIFF_SECONDS := 0.4
const SHAKE_SECONDS := 0.9

var kind := ""
var rig: Node2D
var bubble: Node2D
## Wander area and the spot by the gate, both in the parent's coordinates.
var home := Rect2()
var feed_pos := Vector2.ZERO
## The keeper's feeding spot on the path, in world coordinates (set by the zoo).
var spot := Vector2.ZERO

var hungry := false
var wrong_tries := 0
var meals := 0

## Current action: "" (none), "eat", "sniff", "shake", "sing", "dance".
var action := ""
var action_t := 0.0
var _queue: Array[String] = []
var _time := 0.0
var _target := Vector2.ZERO
var _rest := 0.0
var _bubble_amount := 0.0
var _walking := false
var look := 0.0
var rng := RandomNumberGenerator.new()


func setup(animal_kind: String, area: Rect2, gate_pos: Vector2, seed_value: int) -> void:
	kind = animal_kind
	home = area
	feed_pos = gate_pos
	rng.seed = seed_value
	rig = Animals.build(kind)
	if kind == "giraffe":
		rig.scale = Vector2(0.92, 0.92)
	add_child(rig)
	bubble = Props.bubble()
	bubble.position = Animals.BUBBLE[kind] * rig.scale
	bubble.scale = Vector2.ZERO
	bubble.visible = false
	bubble.z_index = 5
	add_child(bubble)
	position = area.get_center()
	_target = position
	_time = rng.randf() * 3.0


# ---------------------------------------------------------------- reactions

func make_hungry() -> void:
	hungry = true
	wrong_tries = 0
	Props.bubble_hint(bubble, Rules.right_food(kind), false)
	Sfx.play("bubble_pop", 1.0 + rng.randf() * 0.1)


## The right food arrived: munch, then sing. Hunger is over.
func eat() -> void:
	hungry = false
	wrong_tries = 0
	meals += 1
	Props.bubble_hint(bubble, Rules.right_food(kind), false)
	_start("eat", ["sing"])


## A snack at the bell: munch and sing, whether hungry or not.
func snack() -> void:
	hungry = false
	Props.bubble_hint(bubble, Rules.right_food(kind), false)
	_start("eat", ["dance"])


## The wrong food arrived: a sniff, then a head shake with a raspberry.
func refuse() -> void:
	wrong_tries += 1
	if Rules.hint_for(wrong_tries) >= Rules.Hint.GLOW:
		Props.bubble_hint(bubble, Rules.right_food(kind), true)
	_start("sniff", ["shake"])


## Singer press (or a call-out): the animal says its sound and dances.
func sing(dance_after := true) -> void:
	_start("sing", ["dance"] if dance_after else [])


func dance() -> void:
	_start("dance", [])


func busy() -> bool:
	return action != ""


func mouth_global() -> Vector2:
	return rig.to_global(Animals.MOUTH[kind])


func head_global() -> Vector2:
	return rig.to_global(Animals.MOUTH[kind] + Vector2(0, -30))


func _start(a: String, then: Array) -> void:
	action = a
	action_t = 0.0
	_queue.assign(then)
	match a:
		"eat":
			Sfx.play("munch", 1.0 + rng.randf() * 0.15)
		"shake":
			Sfx.play("nope", 1.0 + rng.randf() * 0.1)
		"sing":
			Game.voice(kind, 1.0 + rng.randf_range(-0.04, 0.04))


func _length(a: String) -> float:
	match a:
		"eat": return EAT_SECONDS
		"sniff": return SNIFF_SECONDS
		"shake": return SHAKE_SECONDS
		"sing": return SING_SECONDS
		"dance": return DANCE_SECONDS
	return 0.0


# ---------------------------------------------------------------- frame

## beat: the music clock in beats (for dances); keeper_x: world x to look at.
func update(dt: float, beat: float, keeper_x: float) -> void:
	_time += dt
	if action != "":
		action_t += dt
		if action == "eat" and fmod(action_t, 0.5) < dt and action_t > 0.2 and action_t < EAT_SECONDS - 0.3:
			Sfx.play("munch", 1.0 + rng.randf() * 0.2, -3.0)
		if action_t >= _length(action):
			if _queue.is_empty():
				action = ""
			else:
				_start(_queue.pop_front(), _queue.duplicate())
	_move(dt)
	# Turn to watch the keeper: eyes and a little head turn.
	var dx := keeper_x - global_position.x
	look = move_toward(look, clampf(dx / 300.0, -1.0, 1.0), dt * 3.0)
	match action:
		"eat": Animals.pose(rig, "munch", action_t, -1, look)
		"sniff": Animals.pose(rig, "sniff", action_t, -1, look)
		"shake": Animals.pose(rig, "shake", action_t)
		"sing": Animals.pose(rig, "sing", action_t, -1, look)
		"dance": Animals.pose(rig, "dance", beat)
		_:
			if hungry:
				Animals.pose(rig, "hungry", _time, -1, look)
			else:
				Animals.pose(rig, "idle", _time, -1, look)
				if _walking:
					rig.get_node("pivot").position.y -= absf(sin(_time * 9.0)) * 4.0
					rig.get_node("pivot").rotation = sin(_time * 9.0) * 0.05
	# Bubble pops in while hungry.
	var want := 1.0 if hungry and action == "" or (hungry and action in ["sniff", "shake"]) else 0.0
	_bubble_amount = move_toward(_bubble_amount, want, dt * 5.0)
	bubble.visible = _bubble_amount > 0.01
	var s := _bubble_amount * (1.0 + 0.04 * sin(_time * 3.0))
	bubble.scale = Vector2(s, s)


func _move(dt: float) -> void:
	_walking = false
	if action != "":
		return
	if hungry:
		_target = feed_pos
	else:
		_rest -= dt
		if _rest <= 0.0 and position.distance_to(_target) < 4.0:
			_rest = rng.randf_range(1.5, 4.0)
			_target = Vector2(rng.randf_range(home.position.x, home.end.x), rng.randf_range(home.position.y, home.end.y))
	if position.distance_to(_target) > 2.0 and (_rest <= 0.0 or hungry):
		var speed := WALK_SPEED * (1.8 if hungry else 1.0)
		position = position.move_toward(_target, speed * dt)
		_walking = true
