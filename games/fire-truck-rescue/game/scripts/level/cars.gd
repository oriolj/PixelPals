extends Node3D
## Town cars on looping routes (Path3D curves from road cells, corners
## rounded). They drive on the right, wait politely when the truck is in
## front of them, and slide to the kerb and crawl while the siren is on.
## Each car is a soft solid for the truck.

const Low := preload("res://scripts/level/low.gd")
const TownMap := preload("res://scripts/level/town_map.gd")

const SPEED := 5.5
const CRAWL := 1.0
const LANE := 1.8
const KERB_EXTRA := 1.5
const WAIT_DIST := 7.5
const PULL_RANGE := 32.0
const RADIUS := 1.7

## Routes as corner cells, driven in order and looping.
const ROUTES := [
	[Vector2i(1, 1), Vector2i(7, 1), Vector2i(7, 5), Vector2i(6, 6), Vector2i(1, 6)],
	[Vector2i(1, 1), Vector2i(1, 12), Vector2i(13, 12), Vector2i(13, 1)],
]
const COLOURS: Array[Color] = [Color("#3b5dc9"), Color("#ffcd75")]

## [{path: Path3D, curve: Curve3D, dist, speed, kerb, node, pos: Vector2, dir: Vector2}]
var cars: Array[Dictionary] = []


func setup(map: TownMap) -> void:
	for i in ROUTES.size():
		var pts: Array[Vector2] = []
		for c in ROUTES[i]:
			pts.append(map.cell_center(c))
		pts = _round(pts, 3.5)
		var curve := Curve3D.new()
		for p in pts:
			curve.add_point(Vector3(p.x, 0, p.y))
		curve.add_point(Vector3(pts[0].x, 0, pts[0].y))
		curve.bake_interval = 0.5
		var path := Path3D.new()
		path.curve = curve
		add_child(path)
		var node := _car_mesh(COLOURS[i % COLOURS.size()])
		add_child(node)
		cars.append({"path": path, "curve": curve, "dist": curve.get_baked_length() * (0.15 + 0.5 * i),
			"speed": SPEED, "kerb": 0.0, "node": node, "pos": Vector2.ZERO, "dir": Vector2.UP, "honk": 0.0})
	for c in cars:
		_place(c)


## Rounds each corner: three points instead of one, `r` metres either side.
static func _round(pts: Array[Vector2], r: float) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for i in pts.size():
		var p := pts[i]
		var a := (pts[i - 1] - p).normalized()
		var b := (pts[(i + 1) % pts.size()] - p).normalized()
		out.append(p + a * r)
		out.append(p + (a + b) * r * 0.3)
		out.append(p + b * r)
	return out


func _car_mesh(c: Color) -> Node3D:
	var n := Node3D.new()
	Low.box(n, Vector3(1.9, 0.8, 3.4), c, Vector3(0, 0.75, 0))
	Low.box(n, Vector3(1.7, 0.7, 1.8), c.lightened(0.15), Vector3(0, 1.45, 0.2))
	Low.box(n, Vector3(1.74, 0.5, 1.5), Low.CYAN, Vector3(0, 1.45, 0.2))
	Low.box(n, Vector3(1.6, 0.12, 1.6), c.darkened(0.2), Vector3(0, 1.84, 0.2))
	Low.box(n, Vector3(2.0, 0.2, 0.2), Low.GREY, Vector3(0, 0.5, -1.72))
	Low.box(n, Vector3(2.0, 0.2, 0.2), Low.GREY, Vector3(0, 0.5, 1.72))
	for x in [-0.6, 0.6]:
		Low.box(n, Vector3(0.35, 0.2, 0.08), Low.YELLOW, Vector3(x, 0.85, -1.72), true)
	for z in [-1.1, 1.1]:
		for x in [-0.95, 0.95]:
			var w := Low.cyl(n, 0.38, 0.38, 0.3, Low.INK, Vector3(x, 0.38, z), 8)
			w.rotation.z = PI / 2.0
	return n


func step(dt: float, truck_pos: Vector2, siren_on: bool) -> void:
	for c in cars:
		var near: bool = c.pos.distance_to(truck_pos) < PULL_RANGE
		var pull := siren_on and near
		c.kerb = move_toward(c.kerb, 1.0 if pull else 0.0, dt * 1.5)
		var to_truck: Vector2 = truck_pos - c.pos
		var blocked: bool = to_truck.length() < WAIT_DIST and absf(c.dir.angle_to(to_truck)) < 0.7
		var target := 0.0 if blocked else (CRAWL if pull else SPEED)
		c.speed = move_toward(c.speed, target, dt * 6.0)
		c.dist = fposmod(c.dist + c.speed * dt, c.curve.get_baked_length())
		c.honk = maxf(0.0, c.honk - dt)
		_place(c)


func _place(c: Dictionary) -> void:
	var curve: Curve3D = c.curve
	var len := curve.get_baked_length()
	var p3 := curve.sample_baked(c.dist)
	var ahead := curve.sample_baked(fposmod(c.dist + 1.5, len))
	var dir := Vector2(ahead.x - p3.x, ahead.z - p3.z).normalized()
	if dir == Vector2.ZERO:
		dir = c.dir
	var right := Vector2(-dir.y, dir.x)
	var p: Vector2 = Vector2(p3.x, p3.z) + right * (LANE + KERB_EXTRA * c.kerb)
	c.pos = p
	c.dir = dir
	var n: Node3D = c.node
	n.position = Vector3(p.x, 0, p.y)
	n.rotation.y = atan2(-dir.x, -dir.y) - 0.25 * c.kerb * (1.0 if c.speed > 0.5 else 0.0)


## Circle solids for the truck.
func solids() -> Array:
	var out := []
	for c in cars:
		out.append({"kind": "circle", "pos": c.pos, "r": RADIUS, "tag": "car"})
	return out
