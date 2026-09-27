extends RefCounted
## The Mars heightmap: gentle seeded hills sampled once per pixel, flat where
## the rover lands and where the stage ends. `height_at(x)` is the screen y of
## the ground surface (y grows downwards). The landing site flavours it:
## dunes roll more, a crater dips half-way, ice and rocks are calmer.

const SITES := ["dunes", "crater", "ice", "rocks"]
const BASE_Y := 146.0
const LAND_X := 70.0        # where the rover is set down
const FLAT_HALF := 40.0     # flat ground either side of LAND_X
const FIRST_TARGET := 230.0
const TARGET_EVERY := 250.0

var width := 3600
var site := "dunes"
var heights := PackedFloat32Array()


func _init(world_width := 3600, landing_site := "dunes", seed_value := 7) -> void:
	width = world_width
	site = landing_site if SITES.has(landing_site) else "dunes"
	_build(seed_value)


func _build(seed_value: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value + SITES.find(site) * 101
	var amp := {"dunes": 10.0, "crater": 6.0, "ice": 5.0, "rocks": 7.0}[site] as float
	var waves: Array = []
	for i in 3:
		waves.append([rng.randf_range(0.004, 0.012) * (1.0 + i), rng.randf() * TAU, amp / (1.0 + i * 1.3)])
	heights.resize(width + 1)
	for x in width + 1:
		var h := 0.0
		for w in waves:
			h += sin(x * float(w[0]) + float(w[1])) * float(w[2])
		if site == "crater":
			var cx := width * 0.45
			var d := absf(x - cx) / 70.0
			if d < 1.0:
				h += (1.0 - d * d) * 12.0           # the bowl
			elif d < 1.5:
				h -= sin((d - 1.0) / 0.5 * PI) * 4.0  # its soft rim
		# Flat at the landing spot and at the end, eased in.
		var flat := 1.0 - _ease(absf(x - LAND_X) - FLAT_HALF, 60.0)
		flat = maxf(flat, 1.0 - _ease((width - 60.0) - x, 80.0))
		heights[x] = roundf(BASE_Y + h * (1.0 - flat))


static func _ease(d: float, span: float) -> float:
	return clampf(d / span, 0.0, 1.0)


func height_at(x: float) -> float:
	var xi := clampf(x, 0.0, float(width))
	var i := int(floorf(xi))
	var j := mini(i + 1, width)
	return lerpf(heights[i], heights[j], xi - i)


## Steepest slope anywhere, in px per px (the rover's tilt test uses it).
func max_slope() -> float:
	var m := 0.0
	for x in range(1, width + 1):
		m = maxf(m, absf(heights[x] - heights[x - 1]))
	return m


## The science targets for this site: [{x, kind, drilled, revealed}].
## Every site has red, grey and white rocks; ice is common at the ice site and
## rare elsewhere; one pretty shell hides in every run.
func targets() -> Array[Dictionary]:
	var cycle: Array = {
		"dunes": ["red", "grey", "red", "white"],
		"crater": ["grey", "white", "red", "grey"],
		"ice": ["ice", "white", "ice", "red"],
		"rocks": ["grey", "red", "grey", "white"],
	}[site]
	var out: Array[Dictionary] = []
	var x := FIRST_TARGET
	var i := 0
	while x < width - 180.0:
		var kind: String = cycle[i % cycle.size()]
		if i == 3:
			kind = "shell"
		elif i == 5 and site != "ice":
			kind = "ice"
		out.append({"x": x, "kind": kind, "drilled": false, "revealed": false})
		x += TARGET_EVERY
		i += 1
	return out
