extends RefCounted
## Turns brush positions sampled once per frame into evenly spaced dabs, so a
## fast move leaves a continuous stroke instead of dotted gaps.
## Spacing is a quarter of the dab radius; the leftover distance carries over
## to the next frame so the spacing stays even across frames.

var active := false
var last := Vector2.ZERO
var radius := 12.0
var _carry := 0.0


func spacing() -> float:
	return maxf(1.0, radius * 0.25)


## Starts a stroke: returns the first dab.
func begin(pos: Vector2, r: float) -> PackedVector2Array:
	active = true
	radius = r
	last = pos
	_carry = 0.0
	return PackedVector2Array([pos])


## Dabs from the last position up to `pos` (excluding the last one, which was
## already drawn).
func move_to(pos: Vector2) -> PackedVector2Array:
	var out := PackedVector2Array()
	if not active:
		return out
	var seg := pos - last
	var dist := seg.length()
	if dist <= 0.0001:
		return out
	var step := spacing()
	var dir := seg / dist
	var t := step - _carry
	while t <= dist:
		out.append(last + dir * t)
		t += step
	_carry = dist - (t - step)
	last = pos
	return out


func end() -> void:
	active = false
	_carry = 0.0
