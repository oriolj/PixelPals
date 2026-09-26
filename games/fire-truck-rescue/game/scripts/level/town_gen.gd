extends RefCounted
## Builds the 3D toy town from the ASCII map (town_map.gd), all from
## primitives: ground and roads in one vertex-coloured mesh, houses, trees,
## the station, hydrants, the bridge, the roundabout and some life.
##
## build(parent, map) returns references the level animates:
##   door, roof (station), station_node, hydrants: [Node3D], cat_trees: [Node3D],
##   fire_props: {fire index: Node3D}, folk: [{node, pos, base_y}], ducks: [Node3D]

const Low := preload("res://scripts/level/low.gd")
const TownMap := preload("res://scripts/level/town_map.gd")
const TruckModel := preload("res://scripts/level/truck_model.gd")

const WALLS: Array[Color] = [Color("#f4f4f4"), Color("#ffcd75"), Color("#f4f4f4"), Color("#94b0c2"), Color("#a7f070")]
const ROOFS: Array[Color] = [Color("#ef7d57"), Color("#b13e53"), Color("#3b5dc9"), Color("#257179"), Color("#ef7d57")]
const DOORS: Array[Color] = [Color("#b13e53"), Color("#3b5dc9"), Color("#5d275d"), Color("#257179")]
const GRASS_A := Color("#38b764")
const GRASS_B := Color("#45c06c")
const ROAD := Color("#566c86")
const PAVE := Color("#94b0c2")
const APRON := Color("#a9bccb")
const WATER := Color("#41a6f6")
const BANK := Color("#257179")
const LINE := Color("#f4f4f4")

var refs := {}


func build(parent: Node3D, map: TownMap, cast: Array[String]) -> Dictionary:
	refs = {"hydrants": [], "cat_trees": [], "fire_props": {}, "folk": [], "ducks": []}
	_ground(parent, map)
	_outskirts(parent, map)
	for hs in map.houses:
		_house(parent, hs)
	for tr in map.trees:
		var n := _tree(parent, tr)
		if tr.cat:
			refs.cat_trees.append(n)
	for i in map.fires.size():
		var f: Dictionary = map.fires[i]
		if f.kind == "bin":
			refs.fire_props[i] = _bin(parent, f)
		elif f.kind == "hay":
			refs.fire_props[i] = _hay(parent, f)
	for h in map.hydrants:
		refs.hydrants.append(_hydrant(parent, h.pos))
	for p in map.islands:
		_roundabout(parent, p)
	if not map.station.is_empty():
		_station(parent, map)
	_folk(parent, map, cast)
	_ducks(parent, map)
	return refs


# ---------------------------------------------------------------- ground

func _ground(parent: Node3D, map: TownMap) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var cs := TownMap.CELL
	for r in map.rows:
		for c in map.cols:
			var cell := Vector2i(c, r)
			var ch := map.char_at(cell)
			var lo := Vector2(c, r) * cs
			var hi := lo + Vector2(cs, cs)
			var watery := ch == "~" or ch == "="
			if watery:
				_flat(st, lo, hi, -0.7, WATER)
				for d in TownMap.DIRS:
					var nch := map.char_at(cell + d)
					if nch != "~" and nch != "=" and nch != "":
						_bank(st, lo, hi, d)
				if ch == "=":
					_bridge(st, map, cell, lo, hi)
				continue
			var col := GRASS_A if (c + r) % 2 == 0 else GRASS_B
			if map.is_road(cell) or ch == "o":
				col = ROAD
			elif ch == "S":
				col = APRON
			_flat(st, lo, hi, 0.0, col)
			if map.is_road(cell):
				_markings(st, map, cell, lo)
			elif ch != "S":
				for d in TownMap.DIRS:
					if map.is_road(cell + d):
						_kerb(st, lo, hi, d)
	st.index()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Low.vertex_mat()
	parent.add_child(mi)


func _flat(st: SurfaceTool, lo: Vector2, hi: Vector2, y: float, col: Color) -> void:
	Low.st_quad(st, Vector3(lo.x, y, lo.y), Vector3(hi.x, y, lo.y), Vector3(hi.x, y, hi.y), Vector3(lo.x, y, hi.y), Vector3.UP, col)


func _bank(st: SurfaceTool, lo: Vector2, hi: Vector2, d: Vector2i) -> void:
	# A vertical wall from the water up to the grass, on side d of the cell.
	var a := Vector3(hi.x, 0, lo.y)
	var b := Vector3(hi.x, 0, hi.y)
	if d == Vector2i(0, -1):
		a = Vector3(lo.x, 0, lo.y)
		b = Vector3(hi.x, 0, lo.y)
	elif d == Vector2i(0, 1):
		a = Vector3(hi.x, 0, hi.y)
		b = Vector3(lo.x, 0, hi.y)
	elif d == Vector2i(-1, 0):
		a = Vector3(lo.x, 0, hi.y)
		b = Vector3(lo.x, 0, lo.y)
	var n := -Vector3(d.x, 0, d.y)
	Low.st_quad(st, a + Vector3(0, -0.7, 0), a, b, b + Vector3(0, -0.7, 0), n, BANK)


func _bridge(st: SurfaceTool, map: TownMap, cell: Vector2i, lo: Vector2, hi: Vector2) -> void:
	var vertical := map.is_road(cell + Vector2i(0, -1)) or map.is_road(cell + Vector2i(0, 1))
	Low.st_box(st, Vector3(lo.x - 0.01, -0.35, lo.y - 0.01), Vector3(hi.x + 0.01, 0.0, hi.y + 0.01), Low.WOOD)
	# Planks: thin lighter strips across the deck.
	for k in 6:
		var t := (k + 0.5) / 6.0
		if vertical:
			var z := lerpf(lo.y, hi.y, t)
			Low.st_box(st, Vector3(lo.x + 0.8, 0.0, z - 0.12), Vector3(hi.x - 0.8, 0.02, z + 0.12), Low.ORANGE.darkened(0.25), false)
		else:
			var x := lerpf(lo.x, hi.x, t)
			Low.st_box(st, Vector3(x - 0.12, 0.0, lo.y + 0.8), Vector3(x + 0.12, 0.02, hi.y - 0.8), Low.ORANGE.darkened(0.25), false)
	# Railings: posts and a top rail on both sides.
	for side in [0, 1]:
		if vertical:
			var x := lo.x + 0.25 if side == 0 else hi.x - 0.25
			Low.st_box(st, Vector3(x - 0.12, 0.7, lo.y), Vector3(x + 0.12, 0.9, hi.y), Low.WHITE)
			for k in 5:
				var z := lerpf(lo.y + 0.3, hi.y - 0.3, k / 4.0)
				Low.st_box(st, Vector3(x - 0.1, 0.0, z - 0.1), Vector3(x + 0.1, 0.8, z + 0.1), Low.RED)
		else:
			var z2 := lo.y + 0.25 if side == 0 else hi.y - 0.25
			Low.st_box(st, Vector3(lo.x, 0.7, z2 - 0.12), Vector3(hi.x, 0.9, z2 + 0.12), Low.WHITE)
			for k in 5:
				var x2 := lerpf(lo.x + 0.3, hi.x - 0.3, k / 4.0)
				Low.st_box(st, Vector3(x2 - 0.1, 0.0, z2 - 0.1), Vector3(x2 + 0.1, 0.8, z2 + 0.1), Low.RED)


func _markings(st: SurfaceTool, map: TownMap, cell: Vector2i, lo: Vector2) -> void:
	var cs := TownMap.CELL
	var ns := map.is_road(cell + Vector2i(0, -1)) and map.is_road(cell + Vector2i(0, 1))
	var ew := map.is_road(cell + Vector2i(-1, 0)) and map.is_road(cell + Vector2i(1, 0))
	var mid := lo + Vector2(cs, cs) / 2.0
	if ns and not map.is_road(cell + Vector2i(-1, 0)) and not map.is_road(cell + Vector2i(1, 0)):
		for k in 2:
			var z := lo.y + cs * (0.25 + 0.5 * k)
			Low.st_box(st, Vector3(mid.x - 0.15, 0.0, z - 1.0), Vector3(mid.x + 0.15, 0.03, z + 1.0), LINE, false)
	elif ew and not map.is_road(cell + Vector2i(0, -1)) and not map.is_road(cell + Vector2i(0, 1)):
		for k in 2:
			var x := lo.x + cs * (0.25 + 0.5 * k)
			Low.st_box(st, Vector3(x - 1.0, 0.0, mid.y - 0.15), Vector3(x + 1.0, 0.03, mid.y + 0.15), LINE, false)


func _kerb(st: SurfaceTool, lo: Vector2, hi: Vector2, d: Vector2i) -> void:
	var w := 1.1
	var a := lo
	var b := hi
	if d == Vector2i(0, -1):
		b = Vector2(hi.x, lo.y + w)
	elif d == Vector2i(0, 1):
		a = Vector2(lo.x, hi.y - w)
	elif d == Vector2i(-1, 0):
		b = Vector2(lo.x + w, hi.y)
	else:
		a = Vector2(hi.x - w, lo.y)
	Low.st_box(st, Vector3(a.x, 0.0, a.y), Vector3(b.x, 0.1, b.y), PAVE)


# ---------------------------------------------------------------- outskirts

func _outskirts(parent: Node3D, map: TownMap) -> void:
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(420, 420)
	plane.mesh = pm
	plane.material_override = Low.mat(GRASS_A.darkened(0.08))
	plane.position = Vector3(map.size.x / 2.0, -0.08, map.size.y / 2.0)
	parent.add_child(plane)
	# A ring of woods and round hills around the town, so the edge of the
	# map is never a void.
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in 90:
		var side := i % 4
		var along := rng.randf_range(-10.0, (map.size.x if side < 2 else map.size.y) + 10.0)
		var out := rng.randf_range(3.0, 26.0)
		var p: Vector2
		match side:
			0: p = Vector2(along, -out)
			1: p = Vector2(along, map.size.y + out)
			2: p = Vector2(-out, along)
			_: p = Vector2(map.size.x + out, along)
		_tree(parent, {"pos": p, "pine": rng.randf() < 0.5, "seed": rng.randi(), "cat": false})
	for i in 10:
		var ang := TAU * i / 10.0 + 0.3
		var p2 := map.size / 2.0 + Vector2(cos(ang), sin(ang)) * rng.randf_range(110.0, 140.0)
		var hill := Low.sphere(parent, 1.0, GRASS_A.lerp(Low.TEAL, rng.randf_range(0.1, 0.5)), Vector3(p2.x, -6.0, p2.y), 10, 6)
		hill.scale = Vector3(40, 22, 40)


# ---------------------------------------------------------------- props

func _house(parent: Node3D, hs: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = hs.seed
	var n := Node3D.new()
	n.position = Vector3(hs.pos.x, 0, hs.pos.y)
	var facing: Vector2i = hs.facing
	if facing == Vector2i.ZERO:
		facing = TownMap.DIRS[rng.randi() % 4]
	n.rotation.y = TruckModel.yaw_of(Vector2(facing))
	parent.add_child(n)
	var w: float = hs.w
	var d: float = hs.d
	var h: float = hs.height
	var wall: Color = WALLS[rng.randi() % WALLS.size()]
	var roof: Color = ROOFS[rng.randi() % ROOFS.size()]
	Low.box(n, Vector3(w, h, d), wall, Vector3(0, h / 2.0, 0))
	# Gable-front roof, like a child's drawing; a darker eave strip under it.
	var rh := rng.randf_range(1.5, 2.2)
	Low.prism(n, Vector3(w + 0.6, rh, d + 0.5), roof, Vector3(0, h + rh / 2.0, 0))
	Low.box(n, Vector3(w + 0.2, 0.2, d + 0.2), roof.darkened(0.3), Vector3(0, h + 0.05, 0))
	# Front: door, two windows, a round attic window. Front is -Z.
	var fz := -d / 2.0 - 0.06
	Low.box(n, Vector3(1.0, 1.7, 0.14), DOORS[rng.randi() % DOORS.size()], Vector3(0, 0.85, fz))
	Low.box(n, Vector3(0.14, 0.14, 0.16), Low.YELLOW, Vector3(0.3, 0.85, fz - 0.02))
	for sx in [-1.0, 1.0]:
		var wx: float = sx * w * 0.3
		Low.box(n, Vector3(1.0, 1.0, 0.1), Low.WHITE, Vector3(wx, h * 0.58, fz))
		Low.box(n, Vector3(0.8, 0.8, 0.12), Low.CYAN, Vector3(wx, h * 0.58, fz - 0.01))
		Low.box(n, Vector3(0.1, 0.8, 0.14), Low.WHITE, Vector3(wx, h * 0.58, fz - 0.02))
	Low.box(n, Vector3(0.7, 0.7, 0.12), Low.CYAN, Vector3(0, h + rh * 0.35, fz + 0.2))
	# Side windows.
	for sx2 in [-1.0, 1.0]:
		Low.box(n, Vector3(0.1, 0.8, 0.8), Low.CYAN, Vector3(sx2 * (w / 2.0 + 0.04), h * 0.58, 0.4))
	# Chimney.
	var cx := rng.randf_range(-0.25, 0.25) * w
	Low.box(n, Vector3(0.55, 1.3, 0.55), Low.RED.darkened(0.2), Vector3(cx, h + rh * 0.55, d * 0.2))
	# A flower box and a front path stone.
	Low.box(n, Vector3(1.0, 0.25, 0.25), Low.WOOD, Vector3(-w * 0.3, h * 0.58 - 0.6, fz - 0.15))
	for k in 3:
		Low.sphere(n, 0.13, [Low.RED, Low.YELLOW, Low.WHITE][k], Vector3(-w * 0.3 - 0.3 + k * 0.3, h * 0.58 - 0.4, fz - 0.15), 5, 3)
	return n


func _tree(parent: Node3D, tr: Dictionary) -> Node3D:
	var rng := RandomNumberGenerator.new()
	rng.seed = tr.seed
	var n := Node3D.new()
	n.position = Vector3(tr.pos.x, 0, tr.pos.y)
	n.rotation.y = rng.randf() * TAU
	parent.add_child(n)
	if tr.cat:
		Low.cyl(n, 0.3, 0.42, 3.0, Low.WOOD, Vector3(0, 1.5, 0), 6)
		Low.sphere(n, 2.1, Low.GREEN, Vector3(0, 4.2, 0), 8, 5, 0.85)
		Low.sphere(n, 1.4, Low.LIME.darkened(0.15), Vector3(1.2, 4.9, 0.3), 7, 4)
		Low.sphere(n, 1.3, Low.GREEN.darkened(0.1), Vector3(-1.1, 4.7, -0.5), 7, 4)
		# A branch reaching toward the road, where the cat sits.
		var br := Low.box(n, Vector3(0.25, 0.25, 2.6), Low.WOOD, Vector3(0, 3.3, -1.3))
		br.name = "Branch"
		return n
	var s := rng.randf_range(0.85, 1.2)
	if tr.pine:
		Low.cyl(n, 0.18, 0.24, 1.0 * s, Low.WOOD, Vector3(0, 0.5 * s, 0), 5)
		var green := Low.TEAL if rng.randf() < 0.5 else Low.GREEN.darkened(0.2)
		Low.cyl(n, 0.0, 1.5 * s, 2.2 * s, green, Vector3(0, 1.9 * s, 0), 7)
		Low.cyl(n, 0.0, 1.1 * s, 1.8 * s, green.lightened(0.1), Vector3(0, 3.0 * s, 0), 7)
	else:
		Low.cyl(n, 0.2, 0.28, 1.6 * s, Low.WOOD, Vector3(0, 0.8 * s, 0), 5)
		var leaf := Low.GREEN if rng.randf() < 0.6 else Low.LIME.darkened(0.2)
		Low.sphere(n, 1.4 * s, leaf, Vector3(0, 2.4 * s, 0), 8, 4, 0.9)
		if rng.randf() < 0.5:
			Low.sphere(n, 0.9 * s, leaf.lightened(0.1), Vector3(0.6 * s, 3.1 * s, 0.2), 6, 4)
		if rng.randf() < 0.3:
			for k in 3:
				Low.sphere(n, 0.16, Low.RED, Vector3(cos(k * 2.1) * 1.2 * s, 2.3 * s, sin(k * 2.1) * 1.2 * s), 5, 3)
	return n


func _hydrant(parent: Node3D, p: Vector2) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(p.x, 0.1, p.y)
	parent.add_child(n)
	Low.cyl(n, 0.24, 0.3, 0.2, Low.YELLOW.darkened(0.2), Vector3(0, 0.1, 0), 8)
	Low.cyl(n, 0.22, 0.24, 0.75, Low.YELLOW, Vector3(0, 0.55, 0), 8)
	Low.sphere(n, 0.25, Low.YELLOW, Vector3(0, 0.92, 0), 8, 4)
	Low.box(n, Vector3(0.7, 0.16, 0.16), Low.ORANGE, Vector3(0, 0.6, 0))
	Low.box(n, Vector3(0.12, 0.12, 0.12), Low.ORANGE, Vector3(0, 1.15, 0))
	return n


func _bin(parent: Node3D, f: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(f.pos.x, 0, f.pos.y)
	parent.add_child(n)
	Low.box(n, Vector3(1.0, 1.2, 1.0), Low.GREEN.darkened(0.2), Vector3(0, 0.6, 0))
	Low.box(n, Vector3(1.1, 0.14, 1.1), Low.TEAL, Vector3(0, 1.25, 0))
	Low.box(n, Vector3(0.6, 0.12, 0.12), Low.DARK, Vector3(0, 1.0, -0.52))
	return n


func _hay(parent: Node3D, f: Dictionary) -> Node3D:
	var n := Node3D.new()
	n.position = Vector3(f.pos.x, 0, f.pos.y)
	parent.add_child(n)
	for k in 2:
		var b := Low.cyl(n, 0.75, 0.75, 1.3, Low.YELLOW, Vector3(-0.75 + k * 1.5, 0.75, 0), 10)
		b.rotation.z = PI / 2.0
	var top := Low.cyl(n, 0.7, 0.7, 1.2, Low.YELLOW.darkened(0.1), Vector3(0, 1.95, 0), 10)
	top.rotation.z = PI / 2.0
	return n


func _roundabout(parent: Node3D, p: Vector2) -> void:
	var n := Node3D.new()
	n.position = Vector3(p.x, 0, p.y)
	parent.add_child(n)
	Low.cyl(n, TownMap.ISLAND_R, TownMap.ISLAND_R + 0.1, 0.3, PAVE, Vector3(0, 0.15, 0), 16)
	Low.cyl(n, TownMap.ISLAND_R - 0.4, TownMap.ISLAND_R - 0.4, 0.34, GRASS_B, Vector3(0, 0.17, 0), 16)
	# Fountain: basin, water, a column and a splash ball on top.
	Low.cyl(n, 1.6, 1.7, 0.7, Low.GREY, Vector3(0, 0.5, 0), 12)
	Low.cyl(n, 1.35, 1.35, 0.72, Low.SKY, Vector3(0, 0.52, 0), 12)
	Low.cyl(n, 0.25, 0.3, 1.8, Low.GREY, Vector3(0, 1.2, 0), 6)
	Low.sphere(n, 0.55, Low.CYAN, Vector3(0, 2.3, 0), 8, 4)
	for k in 6:
		var a := TAU * k / 6.0
		Low.sphere(n, 0.3, [Low.RED, Low.YELLOW, Low.WHITE][k % 3], Vector3(cos(a) * 2.4, 0.45, sin(a) * 2.4), 6, 3)


func _station(parent: Node3D, map: TownMap) -> void:
	var st: Dictionary = map.station
	var r: Rect2 = st.rect
	var n := Node3D.new()
	n.position = Vector3(r.position.x, 0, r.position.y)
	parent.add_child(n)
	refs.station_node = n
	var w := r.size.x
	var d := r.size.y
	var dx: Vector2 = st.door_x - Vector2(r.position.x, r.position.x)
	var hgt := 5.2
	var red := Low.RED
	# Walls matching the solids.
	Low.box(n, Vector3(2.4, hgt, d - 0.8), red, Vector3(0.4 + 1.2, hgt / 2.0, d / 2.0))
	Low.box(n, Vector3(2.4, hgt, d - 0.8), red, Vector3(w - 0.4 - 1.2, hgt / 2.0, d / 2.0))
	Low.box(n, Vector3(w - 0.8, hgt, 2.0), red, Vector3(w / 2.0, hgt / 2.0, d - 0.4 - 1.0))
	Low.box(n, Vector3(dx.x - 0.4, hgt, 1.2), red, Vector3((0.4 + dx.x) / 2.0, hgt / 2.0, 0.4 + 0.6))
	Low.box(n, Vector3(w - 0.4 - dx.y, hgt, 1.2), red, Vector3((dx.y + w - 0.4) / 2.0, hgt / 2.0, 0.4 + 0.6))
	# White trim and a lintel over the door.
	Low.box(n, Vector3(dx.y - dx.x + 0.2, 1.0, 1.2), red, Vector3(w / 2.0, hgt - 0.5, 1.0))
	for sx in [dx.x, dx.y]:
		Low.box(n, Vector3(0.3, hgt - 1.0, 1.3), Low.WHITE, Vector3(sx, (hgt - 1.0) / 2.0, 1.0))
	# Front windows either side of the door.
	for wx in [(0.4 + dx.x) / 2.0, (dx.y + w - 0.4) / 2.0]:
		Low.box(n, Vector3(1.6, 1.4, 0.1), Low.WHITE, Vector3(wx, 3.2, 0.34))
		Low.box(n, Vector3(1.3, 1.1, 0.12), Low.CYAN, Vector3(wx, 3.2, 0.33))
	# Emblem: a yellow badge with a red cross-star over the door.
	var badge := Low.cyl(n, 0.9, 0.9, 0.2, Low.YELLOW, Vector3(w / 2.0, hgt + 1.2, 0.35), 10)
	badge.rotation.x = PI / 2.0
	var star := Low.cyl(n, 0.5, 0.5, 0.1, Low.RED, Vector3(w / 2.0, hgt + 1.2, 0.2), 5)
	star.rotation.x = PI / 2.0
	Low.box(n, Vector3(3.0, 1.4, 0.3), red, Vector3(w / 2.0, hgt + 1.0, 0.6))
	# Roof (hidden while the truck is inside, so the camera sees in).
	var roof := Node3D.new()
	n.add_child(roof)
	Low.box(roof, Vector3(w - 0.2, 0.5, d - 0.2), Low.DARK, Vector3(w / 2.0, hgt + 0.55, d / 2.0))
	Low.prism(roof, Vector3(w - 1.0, 1.6, d - 1.6), Low.SLATE, Vector3(w / 2.0, hgt + 1.6, d / 2.0 + 0.4))
	Low.box(roof, Vector3(w - 0.6, 0.3, d - 0.6), Low.WHITE, Vector3(w / 2.0, hgt + 0.15, d / 2.0))
	refs.roof = roof
	# Hose tower at the back corner, with a bell.
	Low.box(n, Vector3(3.0, 9.5, 3.0), red.darkened(0.1), Vector3(w - 2.0, 4.75, d - 2.0))
	Low.cyl(n, 0.0, 2.3, 2.0, Low.DARK, Vector3(w - 2.0, 10.5, d - 2.0), 4)
	Low.box(n, Vector3(1.4, 1.4, 3.1), Low.WHITE, Vector3(w - 2.0, 7.8, d - 2.0))
	Low.sphere(n, 0.5, Low.YELLOW, Vector3(w - 2.0, 7.7, d - 3.6), 8, 4)
	# The roll-up door: white with grey slats; slides up when open.
	var door := Node3D.new()
	door.position = Vector3(w / 2.0, 0, 0.75)
	n.add_child(door)
	var dw := dx.y - dx.x
	Low.box(door, Vector3(dw, hgt - 1.0, 0.2), Low.WHITE, Vector3(0, (hgt - 1.0) / 2.0, 0))
	for k in 5:
		Low.box(door, Vector3(dw, 0.12, 0.24), Low.GREY, Vector3(0, 0.5 + k * 0.8, 0))
	Low.box(door, Vector3(dw * 0.6, 0.5, 0.26), Low.RED, Vector3(0, 2.4, 0))
	refs.door = door
	# Floor stripes inside the bay (a parking box).
	var bay: Rect2 = st.bay_rect
	for sx2 in [bay.position.x, bay.end.x]:
		Low.box(parent, Vector3(0.25, 0.04, bay.size.y), Low.YELLOW, Vector3(sx2, 0.02, bay.get_center().y))
	Low.box(parent, Vector3(bay.size.x, 0.04, 0.25), Low.YELLOW, Vector3(bay.get_center().x, 0.02, bay.end.y))


func _folk(parent: Node3D, map: TownMap, cast: Array[String]) -> void:
	if cast.is_empty():
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var spots := map.kerbs.duplicate()
	for i in range(spots.size() - 1, 0, -1):
		var j := rng.randi() % (i + 1)
		var tmp = spots[i]
		spots[i] = spots[j]
		spots[j] = tmp
	for i in mini(10, spots.size()):
		var k: Dictionary = spots[i]
		var rider: String = cast[i % cast.size()]
		var s := Low.billboard(parent, rider, Low.WHITE, Vector3(k.pos.x, 0.6, k.pos.y), 1.2 / 16.0)
		s.speed_scale = rng.randf_range(0.7, 1.3)
		refs.folk.append({"node": s, "pos": k.pos, "base_y": 0.6, "hop": 0.0})


func _ducks(parent: Node3D, map: TownMap) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for r in map.rows:
		if map.char_at(Vector2i(3, r)) != "~":
			continue
		for i in 3:
			var n := Node3D.new()
			n.position = Vector3(rng.randf_range(20.0, map.size.x - 20.0), -0.55, (r + 0.5) * TownMap.CELL + rng.randf_range(-2.0, 2.0))
			parent.add_child(n)
			Low.sphere(n, 0.4, Low.YELLOW, Vector3.ZERO, 7, 4, 0.8)
			Low.sphere(n, 0.24, Low.YELLOW, Vector3(0, 0.35, -0.3), 6, 4)
			Low.box(n, Vector3(0.14, 0.08, 0.22), Low.ORANGE, Vector3(0, 0.32, -0.55))
			refs.ducks.append(n)
		break
