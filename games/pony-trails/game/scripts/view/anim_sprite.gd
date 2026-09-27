extends Sprite2D
## A sprite strip played through the named ranges of art/anims.json, advanced
## by tick(dt) (so tests and captures are deterministic). The node's position
## is the FEET point: the bottom-centre of the frame. flip_h mirrors it.

const Tex := preload("res://scripts/view/tex.gd")

var sprite_name := ""
var family := ""
var anim := ""
var t := 0.0
## For fps-0 ranges (the hoof lifts): which frame of the range to show.
var hold_index := 0
var size := Vector2i(16, 16)
var _tint := Color.MAGENTA


func setup(name_: String, family_: String, fallback_size: Vector2i, tint := Color.MAGENTA) -> void:
	sprite_name = name_
	family = family_
	_tint = tint
	size = Art.size_of(name_, fallback_size)
	centered = false
	offset = Vector2(-int(size.x / 2.0), -size.y)
	if anim == "":
		anim = "stand"
	_show()


## Swap the strip (another coat) keeping the animation.
func set_sprite(name_: String) -> void:
	if name_ == sprite_name:
		return
	sprite_name = name_
	_show()


func play(anim_name: String, restart := false) -> void:
	if anim_name == anim and not restart:
		return
	anim = anim_name
	t = 0.0
	_show()


func tick(dt: float) -> void:
	t += dt
	_show()


## Absolute frame index in the strip.
func current_frame() -> int:
	var r := Tex.anim(family, anim)
	var first: int = r[0]
	var count: int = r[1]
	var fps: float = r[2]
	if fps <= 0.0:
		return first + clampi(hold_index, 0, count - 1)
	return first + int(floor(t * fps)) % count


## True once a non-looping range has played through (jump, hop).
func finished() -> bool:
	var r := Tex.anim(family, anim)
	return r[2] > 0.0 and t * float(r[2]) >= float(r[1])


## An anchor point of the current frame, relative to this node, mirrored when flipped.
func anchor(key: String, fallback := Vector2.ZERO) -> Vector2:
	var p := Tex.point(family, key, current_frame(), fallback)
	var half := float(int(size.x / 2.0))
	var x := p.x - half
	if flip_h:
		x = float(size.x) - 1.0 - p.x - half
	return Vector2(x, p.y - size.y)


func _show() -> void:
	texture = Tex.frame(sprite_name, current_frame(), _tint, size)
