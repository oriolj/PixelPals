extends RefCounted
## The Splatter's rules (the 2-year-old's any button), as plain logic:
## - a press makes a splat unless the last one was under COOLDOWN seconds
##   ago (then it is a giggle: the rider jumps, nothing is painted);
## - the splat lands on the least painted cell of the 16x9 coverage grid,
##   jittered, so it fills gaps instead of covering drawings;
## - its radius shrinks when the neighbouring cells are painted, and it never
##   covers more than MAX_FRACTION of the canvas;
## - every RAINBOW_EVERY-th splat is a rainbow splat.

const Coverage := preload("res://scripts/paint/coverage.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")
const Palette := preload("res://scripts/paint/palette.gd")

const COOLDOWN := 0.5
const RAINBOW_EVERY := 5
const MAX_FRACTION := 0.08
const R_MIN := 60.0       # 120-260 px across on the canvas
const R_MAX := 130.0
const JITTER := 36.0

var rng := RandomNumberGenerator.new()
var count := 0
var since := INF          # seconds since the last splat


func tick(dt: float) -> void:
	since += dt


func ready_to_splat() -> bool:
	return since >= COOLDOWN


## A press. Returns the splat (see make_splat) or {} when still cooling down.
func press(coverage: Coverage) -> Dictionary:
	if not ready_to_splat():
		return {}
	since = 0.0
	count += 1
	return make_splat(coverage, count % RAINBOW_EVERY == 0)


## {"center", "radius", "rainbow", "parts", "cell"}
func make_splat(coverage: Coverage, rainbow: bool, colour := Color(0, 0, 0, 0)) -> Dictionary:
	var cell := coverage.least_covered(rng)
	var center := Coverage.cell_center(cell) + Vector2(rng.randf_range(-JITTER, JITTER), rng.randf_range(-JITTER, JITTER))
	var crowd := coverage.neighbours(cell.x, cell.y)
	var r := rng.randf_range(R_MIN, R_MAX) * lerpf(1.0, 0.55, crowd)
	var cols: Array = []
	if rainbow:
		cols.assign(Palette.RAINBOW)
	else:
		cols.append(colour if colour.a > 0.0 else Palette.COLORS[rng.randi() % Palette.COLORS.size()])
	var max_area := MAX_FRACTION * Coverage.CANVAS.x * Coverage.CANVAS.y
	var parts := Shapes.splat(center, r, cols, rng, max_area)
	return {"center": center, "radius": r, "rainbow": rainbow, "parts": parts, "cell": cell}
