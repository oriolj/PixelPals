extends RefCounted
## GDScript mirror of shaders/fort_light.gdshader, so gameplay (which spots
## are lit) and the tests never depend on the GPU. Same maths, same pixel
## snapping, same Bayer 4x4 dither. `make light-check` proves they agree.
##
## A light is {"pos": Vector2, "r": float}. Positions are floored to whole
## pixels before use, exactly as the fort passes them to the shader.

const MAX_LIGHTS := 8
## The dusk never goes past 60% (the "it must not be scary" rule).
const MAX_STRENGTH := 0.6
const STRENGTH := 0.55
const FLASH_RADIUS := 36.0
const SHADER_PATH := "res://shaders/fort_light.gdshader"
const BAYER := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


static func snap(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x), floori(p.y))


static func band_of(r: float) -> float:
	return floorf(maxf(2.0, r / 12.0))


## 1.0 in the core, 2/3 and 1/3 in the dithered edge bands, 0 outside.
static func level(p: Vector2i, c: Vector2i, r: float) -> float:
	if r <= 0.0:
		return 0.0
	var dx := p.x - c.x
	var dy := p.y - c.y
	var d2 := float(dx * dx + dy * dy)
	var band := band_of(r)
	var r_core := maxf(r - 2.0 * band, 0.0)
	var r_mid := r - band
	if d2 <= r_core * r_core:
		return 1.0
	if d2 <= r_mid * r_mid:
		return 2.0 / 3.0
	if d2 <= r * r:
		return 1.0 / 3.0
	return 0.0


## How lit the pixel under `pos` is (the max over all lights), before dithering.
static func light_amount(pos: Vector2, lights: Array) -> float:
	var p := snap(pos)
	var best := 0.0
	for i in mini(lights.size(), MAX_LIGHTS):
		var l: Dictionary = lights[i]
		best = maxf(best, level(p, snap(l.pos), roundf(float(l.r))))
	return best


static func bayer(p: Vector2i) -> float:
	return (float(BAYER[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0


## The shader's per-pixel answer: is this pixel lit after the dither?
static func lit_pixel(p: Vector2i, lights: Array) -> bool:
	return light_amount(Vector2(p), lights) > bayer(p)


## Mask alpha at a pixel (what the dusk overlay covers it with).
static func darkness(p: Vector2i, lights: Array, strength: float) -> float:
	return 0.0 if lit_pixel(p, lights) else minf(strength, MAX_STRENGTH)


## Shader uniform arrays for up to MAX_LIGHTS lights (missing ones get r = 0).
static func uniforms(lights: Array) -> Dictionary:
	var pos := PackedVector2Array()
	var rad := PackedFloat32Array()
	for i in MAX_LIGHTS:
		if i < lights.size():
			pos.append(Vector2(snap(lights[i].pos)))
			rad.append(roundf(float(lights[i].r)))
		else:
			pos.append(Vector2(-1000, -1000))
			rad.append(0.0)
	return {"light_pos": pos, "light_radius": rad}


static func make_material() -> ShaderMaterial:
	var sh: Shader
	if OS.has_feature("template"):
		sh = load(SHADER_PATH)
	else:
		# From source read the text itself: no dependency on the import cache.
		sh = Shader.new()
		sh.code = FileAccess.get_file_as_string(SHADER_PATH)
	var m := ShaderMaterial.new()
	m.shader = sh
	return m
