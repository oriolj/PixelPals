extends Node2D
## A rider wearing a hard hat in its seat's colour (blue driver, yellow
## scooper, green boomer). The helmet sits on the top of the head, found
## from the rider's own pixels, so private-pack riders get one too, and it
## follows the rider's idle bounce.

const ArtImage := preload("res://scripts/art_image.gd")
const HELMETS: Array[String] = ["helmet_blue", "helmet", "helmet_green"]
const HELMET_TINTS: Array[Color] = [Color("#41a6f6"), Color("#ffcd75"), Color("#a7f070")]

var rider: AnimatedSprite2D
var helmet: AnimatedSprite2D
var rider_id := ""
var seat := 0
var _base := Vector2.ZERO


func setup(id: String, seat_index: int) -> void:
	seat = clampi(seat_index, 0, 2)
	if rider == null:
		rider = Art.sprite(id, Game.rider_color(id), Vector2i(16, 16))
		add_child(rider)
		helmet = Art.sprite(HELMETS[seat], HELMET_TINTS[seat], Vector2i(12, 6))
		add_child(helmet)
	set_rider(id)


func set_rider(id: String) -> void:
	rider_id = id
	rider.sprite_frames = Art.frames(id, Game.rider_color(id), Vector2i(16, 16))
	rider.play("default")
	var top := ArtImage.head_top(id, 16)
	if top.x < 0:
		top = Vector2i(8, 1)
	# The helmet's brim (its row 4) lands two rows under the top of the head,
	# and its dome is centred over the head (helmet 12x6, rider 16x16, both centred).
	_base = Vector2(top.x - 7, top.y - 7)
	_place()


func flip(on: bool) -> void:
	rider.flip_h = on
	_place()


func _process(_dt: float) -> void:
	_place()


func _place() -> void:
	if helmet == null:
		return
	var bob := 1.0 if rider.frame == 1 and rider.sprite_frames.get_frame_count("default") > 1 else 0.0
	var x := _base.x
	if rider.flip_h:
		x = -x + 1.0
	helmet.position = Vector2(x, _base.y - bob)
