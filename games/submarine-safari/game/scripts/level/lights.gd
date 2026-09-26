extends RefCounted
## The toddler's lights: any press flashes the sub's lights in the next
## colour, three quick presses make a disco. Also the automatic flashes when
## nobody sits in the Lights seat, and the banded light textures (4 steps +
## ordered dither, so the 2D lights stay pixel-true instead of smooth).

const COOLDOWN := 0.25
const ON_SECONDS := 4.0           # light-lovers stay out this long after a flash
const DISCO_WINDOW := 1.2         # 3 flashes inside this = disco
const DISCO_COOLDOWN := 3.0
const AUTO_EVERY := 8.0
const AUTO_SHY_COOLDOWN := 3.0
## warm white, pink, green, blue
const COLORS: Array[Color] = [Color("#ead4aa"), Color("#f6757a"), Color("#63c74d"), Color("#2ce8f5")]
const BAYER4 := [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]


class State:
	var color := -1           # index into COLORS (-1 = never flashed)
	var cooldown := 0.0
	var on := 0.0             # seconds the lights stay "on"
	var pulse := 0.0          # 1 at a flash, decays (glow energy)
	var presses: Array[float] = []
	var disco_cd := 0.0
	var auto_t := 0.0
	var auto_shy_cd := 0.0
	var time := 0.0

	func lights_on() -> bool:
		return on > 0.0


static func step(s: State, dt: float) -> void:
	s.time += dt
	s.cooldown = maxf(0.0, s.cooldown - dt)
	s.on = maxf(0.0, s.on - dt)
	s.pulse = maxf(0.0, s.pulse - dt * 1.5)
	s.disco_cd = maxf(0.0, s.disco_cd - dt)
	s.auto_shy_cd = maxf(0.0, s.auto_shy_cd - dt)


## A press. Returns {"flashed": bool, "disco": bool, "color": int}.
static func press(s: State) -> Dictionary:
	if s.cooldown > 0.0:
		return {"flashed": false, "disco": false, "color": s.color}
	s.cooldown = COOLDOWN
	s.color = (s.color + 1) % COLORS.size()
	s.on = ON_SECONDS
	s.pulse = 1.0
	s.presses.append(s.time)
	while not s.presses.is_empty() and s.time - s.presses[0] > DISCO_WINDOW:
		s.presses.pop_front()
	var disco := false
	if s.presses.size() >= 3 and s.disco_cd <= 0.0:
		disco = true
		s.disco_cd = DISCO_COOLDOWN
		s.presses.clear()
	return {"flashed": true, "disco": disco, "color": s.color}


## Automatic flashes when the Lights seat is empty: every AUTO_EVERY seconds,
## and whenever a shy creature is within 3 tiles (so every species stays
## catchable). Returns true when it flashes this frame.
static func auto_tick(s: State, dt: float, shy_near: bool) -> bool:
	s.auto_t += dt
	if s.auto_t >= AUTO_EVERY:
		s.auto_t = 0.0
		return press(s).flashed
	if shy_near and s.auto_shy_cd <= 0.0 and not s.lights_on():
		s.auto_shy_cd = AUTO_SHY_COOLDOWN
		s.auto_t = 0.0
		return press(s).flashed
	return false


# ---------------------------------------------------------------- textures

## Quantise v (0..1) to `steps` levels with a 4x4 ordered dither.
static func band(v: float, x: int, y: int, steps := 4) -> float:
	var threshold := (float(BAYER4[(y % 4) * 4 + (x % 4)]) + 0.5) / 16.0
	return clampf(floorf(v * steps + threshold) / steps, 0.0, 1.0)


## A round light, `radius` px, 4 bands.
static func radial_image(radius: int, steps := 4) -> Image:
	var size := radius * 2
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5 - radius, y + 0.5 - radius).length() / radius
			var v := band(clampf(1.0 - d, 0.0, 1.0) * 1.1, x, y, steps)
			img.set_pixel(x, y, Color(v, v, v, v))
	return img


## A headlight cone pointing right from its left-middle edge.
static func cone_image(length: int, half_height: int, steps := 4) -> Image:
	var img := Image.create(length, half_height * 2, false, Image.FORMAT_RGBA8)
	for y in half_height * 2:
		for x in length:
			var fx := float(x) / length
			var spread := 3.0 + fx * (half_height - 3.0)
			var fy := absf(y + 0.5 - half_height) / spread
			var v := 0.0
			if fy <= 1.0:
				v = (1.0 - fx * 0.85) * (1.0 - fy * fy * 0.7)
			v = band(v, x, y, steps)
			img.set_pixel(x, y, Color(v, v, v, v))
	return img


static func distinct_levels(img: Image) -> int:
	var seen := {}
	for y in img.get_height():
		for x in img.get_width():
			seen[snappedf(img.get_pixel(x, y).a, 0.01)] = true
	return seen.size()
