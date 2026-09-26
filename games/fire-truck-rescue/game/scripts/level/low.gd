extends RefCounted
## Low-poly helpers: flat-shaded meshes from Godot's primitives, one matte
## material per colour, and small builders. Everything the town is made of
## goes through here, so the toy look stays consistent.

# Sweetie 16.
const INK := Color("#1a1c2c")
const PURPLE := Color("#5d275d")
const RED := Color("#b13e53")
const ORANGE := Color("#ef7d57")
const YELLOW := Color("#ffcd75")
const LIME := Color("#a7f070")
const GREEN := Color("#38b764")
const TEAL := Color("#257179")
const NAVY := Color("#29366f")
const BLUE := Color("#3b5dc9")
const SKY := Color("#41a6f6")
const CYAN := Color("#73eff7")
const WHITE := Color("#f4f4f4")
const GREY := Color("#94b0c2")
const SLATE := Color("#566c86")
const DARK := Color("#333c57")
## Not in the palette as such: a toy-wood brown mixed from two of its colours.
const WOOD := Color("#8a4a4f")

static var _mats := {}
static var _meshes := {}


## Matte material for a colour (cached). `unshaded` for lights and glows.
static func mat(c: Color, unshaded := false) -> StandardMaterial3D:
	var key := "%s|%s" % [c.to_html(), unshaded]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if c.a < 1.0:
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_mats[key] = m
	return m


## Material that takes its colour from the vertices (ground, particles).
static func vertex_mat(unshaded := false) -> StandardMaterial3D:
	var key := "vertex|%s" % unshaded
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	if unshaded:
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mats[key] = m
	return m


## A flat-shaded copy of a primitive (one normal per triangle), cached by key.
static func flat(key: String, prim: PrimitiveMesh) -> ArrayMesh:
	if _meshes.has(key):
		return _meshes[key]
	var src := prim.get_mesh_arrays()
	var verts: PackedVector3Array = src[Mesh.ARRAY_VERTEX]
	var norms: PackedVector3Array = src[Mesh.ARRAY_NORMAL]
	var idx: PackedInt32Array = src[Mesh.ARRAY_INDEX]
	if idx.is_empty():
		idx = PackedInt32Array(range(verts.size()))
	var out_v := PackedVector3Array()
	var out_n := PackedVector3Array()
	for t in range(0, idx.size() - 2, 3):
		var a := verts[idx[t]]
		var b := verts[idx[t + 1]]
		var c := verts[idx[t + 2]]
		var n := (b - a).cross(c - a)
		var ref := norms[idx[t]] + norms[idx[t + 1]] + norms[idx[t + 2]]
		if n.length_squared() < 1e-10:
			n = ref
		if n.dot(ref) < 0.0:
			n = -n
		n = n.normalized()
		out_v.append_array([a, b, c])
		out_n.append_array([n, n, n])
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = out_v
	arr[Mesh.ARRAY_NORMAL] = out_n
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_meshes[key] = mesh
	return mesh


static func _inst(mesh: Mesh, c: Color, parent: Node, at: Vector3, unshaded := false) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat(c, unshaded)
	mi.position = at
	if parent:
		parent.add_child(mi)
	return mi


static func box(parent: Node, size: Vector3, c: Color, at := Vector3.ZERO, unshaded := false) -> MeshInstance3D:
	var key := "box%s" % size
	if not _meshes.has(key):
		var m := BoxMesh.new()
		m.size = size
		_meshes[key] = m
	return _inst(_meshes[key], c, parent, at, unshaded)


static func cyl(parent: Node, r_top: float, r_bot: float, h: float, c: Color, at := Vector3.ZERO, segs := 8) -> MeshInstance3D:
	var key := "cyl%s|%s|%s|%d" % [r_top, r_bot, h, segs]
	if not _meshes.has(key):
		var m := CylinderMesh.new()
		m.top_radius = r_top
		m.bottom_radius = r_bot
		m.height = h
		m.radial_segments = segs
		m.rings = 1
		flat(key, m)
	return _inst(_meshes[key], c, parent, at)


static func sphere(parent: Node, r: float, c: Color, at := Vector3.ZERO, segs := 8, rings := 5, h_scale := 1.0) -> MeshInstance3D:
	var key := "sph%s|%d|%d|%s" % [r, segs, rings, h_scale]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0 * h_scale
		m.radial_segments = segs
		m.rings = rings
		flat(key, m)
	return _inst(_meshes[key], c, parent, at)


## A roof-like prism: triangle in the XY plane, extruded along Z.
static func prism(parent: Node, size: Vector3, c: Color, at := Vector3.ZERO) -> MeshInstance3D:
	var key := "prism%s" % size
	if not _meshes.has(key):
		var m := PrismMesh.new()
		m.size = size
		flat(key, m)
	return _inst(_meshes[key], c, parent, at)


## A small low-poly sphere mesh for particles (vertex coloured).
static func puff_mesh(r: float) -> Mesh:
	var key := "puff%s" % r
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = r
		m.height = r * 2.0
		m.radial_segments = 6
		m.rings = 3
		var fm := flat(key, m)
		fm.surface_set_material(0, vertex_mat())
	return _meshes[key]


## A billboard pixel sprite in 3D (riders, the cat, icons). 16 px = 1 m by default.
static func billboard(parent: Node, sprite_name: String, tint: Color, at: Vector3, px := 1.0 / 16.0,
		fallback := Vector2i(16, 16)) -> AnimatedSprite3D:
	var s := AnimatedSprite3D.new()
	s.sprite_frames = Art.frames(sprite_name, tint, fallback)
	s.play("default")
	s.pixel_size = px
	s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.shaded = false
	s.position = at
	if parent:
		parent.add_child(s)
	return s


## Adds an axis-aligned box to a SurfaceTool (flat normals, one colour).
## Faces: top and the four sides (the bottom is never seen).
static func st_box(st: SurfaceTool, lo: Vector3, hi: Vector3, c: Color, sides := true) -> void:
	var p := [
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	st_quad(st, p[0], p[1], p[2], p[3], Vector3.UP, c)
	if not sides:
		return
	st_quad(st, Vector3(lo.x, lo.y, hi.z), Vector3(lo.x, hi.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, lo.y, hi.z), Vector3.BACK, c)
	st_quad(st, Vector3(hi.x, lo.y, lo.z), Vector3(hi.x, hi.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, lo.y, lo.z), Vector3.FORWARD, c)
	st_quad(st, Vector3(lo.x, lo.y, lo.z), Vector3(lo.x, hi.y, lo.z), Vector3(lo.x, hi.y, hi.z), Vector3(lo.x, lo.y, hi.z), Vector3.LEFT, c)
	st_quad(st, Vector3(hi.x, lo.y, hi.z), Vector3(hi.x, hi.y, hi.z), Vector3(hi.x, hi.y, lo.z), Vector3(hi.x, lo.y, lo.z), Vector3.RIGHT, c)


## A quad a-b-c-d with normal n; the winding is fixed up to face n.
static func st_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3, col: Color) -> void:
	var tris := [[a, b, c], [a, c, d]]
	for t in tris:
		var fn: Vector3 = (t[1] - t[0]).cross(t[2] - t[0])
		# Godot's front faces wind clockwise seen from the front: the
		# geometric normal of a front face points away from the viewer.
		if fn.dot(n) > 0.0:
			t = [t[0], t[2], t[1]]
		for v in t:
			st.set_color(col)
			st.set_normal(n)
			st.add_vertex(v)
