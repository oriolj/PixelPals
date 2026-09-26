extends RefCounted
## The reef map made by tools/reef.py (res://data/reef.json): solid tiles,
## zones, creature homes, the demo route and the decor positions. Collision
## and the depth-based darkness are pure functions here, unit tested.

const PATH := "res://data/reef.json"
const TILE := 16
const WORLD := Vector2(1280, 360)
## Top of the water (world y). Above it is the sky.
const SURFACE_Y := 0.0

var rows: PackedStringArray = []
var w := 0
var h := 0
var homes := {}
var route: Array = []
var sub_start := Vector2(90, 64)
var decor := {}


static func load_default():
	var r = load("res://scripts/level/reef.gd").new()
	r.load_file(PATH)
	return r


func load_file(path: String) -> void:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (data is Dictionary):
		push_error("reef map missing: %s (run make reef)" % path)
		return
	w = int(data.w)
	h = int(data.h)
	rows = PackedStringArray(data.rows)
	for k in data.homes:
		homes[k] = Vector2(data.homes[k][0], data.homes[k][1])
	route = data.route
	sub_start = Vector2(data.sub_start[0], data.sub_start[1])
	decor = data.decor


func tile(tx: int, ty: int) -> String:
	if tx < 0 or ty < 0 or tx >= w or ty >= h:
		return "."
	return rows[ty][tx]


func solid_at(p: Vector2) -> bool:
	return tile(floori(p.x / TILE), floori(p.y / TILE)) != "."


## True if an axis-aligned box (centre, size) overlaps any solid tile.
func rect_hits(center: Vector2, size: Vector2) -> bool:
	var x0 := floori((center.x - size.x * 0.5) / TILE)
	var x1 := floori((center.x + size.x * 0.5 - 1.0) / TILE)
	var y0 := floori((center.y - size.y * 0.5) / TILE)
	var y1 := floori((center.y + size.y * 0.5 - 1.0) / TILE)
	for ty in range(y0, y1 + 1):
		for tx in range(x0, x1 + 1):
			if tile(tx, ty) != ".":
				return true
	return false


## "shallows" | "reef" | "wreck" | "trench"
static func zone_of(p: Vector2) -> String:
	var right := p.x >= WORLD.x * 0.5
	if p.y < 176.0:
		return "reef" if right else "shallows"
	return "trench" if right else "wreck"


## Ambient light (CanvasModulate colour) at a world position: bright near
## the surface, dim in the wreck, near black in the trench.
static func ambient_at(p: Vector2) -> Color:
	var d := clampf(p.y / WORLD.y, 0.0, 1.0)
	var top := Color(1.0, 1.0, 1.0)
	var mid := Color(0.62, 0.72, 0.86)
	var deep := Color(0.34, 0.38, 0.55)
	var c := top.lerp(mid, clampf(d * 2.0, 0.0, 1.0)) if d < 0.5 else mid.lerp(deep, (d - 0.5) * 2.0)
	# The trench: to the right of the divider and below the shelf, darker.
	var trench := clampf((p.x - 600.0) / 80.0, 0.0, 1.0) * clampf((p.y - 170.0) / 50.0, 0.0, 1.0)
	return c.lerp(Color(0.2, 0.2, 0.34), trench * 0.85)


## Distance (in px, capped) from a point to the nearest solid tile (bonus subjects).
func near_rock(p: Vector2, radius := 24.0) -> bool:
	for dy in [-radius, 0.0, radius]:
		for dx in [-radius, 0.0, radius]:
			var q: Vector2 = p + Vector2(dx, dy)
			var t := tile(floori(q.x / TILE), floori(q.y / TILE))
			if t == "#" or t == "c":
				return true
	return false


func near_sand(p: Vector2, radius := 32.0) -> bool:
	for dx in [-radius * 0.5, 0.0, radius * 0.5]:
		var q: Vector2 = p + Vector2(dx, radius)
		if tile(floori(q.x / TILE), floori(q.y / TILE)) == "s":
			return true
	return false
