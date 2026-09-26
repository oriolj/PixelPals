extends Node3D
## The hose's water: a parabola from the nozzle to the target drawn as a
## camera-facing ribbon (ImmediateMesh) whose stripes flow along it, a
## splash of droplets where it lands, and during a super spray a wider jet
## with a rainbow in the mist.

const Low := preload("res://scripts/level/low.gd")
const SEGMENTS := 18
const RAINBOW: Array[Color] = [Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#a7f070"), Color("#41a6f6"), Color("#5d275d")]

var ribbon: MeshInstance3D
var rainbow: MeshInstance3D
var splash: CPUParticles3D
var _mesh := ImmediateMesh.new()
var _rain_mesh := ImmediateMesh.new()
var _mat: StandardMaterial3D


func _ready() -> void:
	_mat = StandardMaterial3D.new()
	_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat.vertex_color_use_as_albedo = true
	_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	ribbon = MeshInstance3D.new()
	ribbon.mesh = _mesh
	ribbon.material_override = _mat
	ribbon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ribbon)
	rainbow = MeshInstance3D.new()
	rainbow.mesh = _rain_mesh
	rainbow.material_override = _mat
	rainbow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(rainbow)
	splash = CPUParticles3D.new()
	splash.mesh = Low.puff_mesh(0.14)
	splash.amount = 24
	splash.lifetime = 0.7
	splash.direction = Vector3.UP
	splash.spread = 50.0
	splash.initial_velocity_min = 2.5
	splash.initial_velocity_max = 4.5
	splash.gravity = Vector3(0, -9.8, 0)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 1.0])
	g.colors = PackedColorArray([Low.WHITE, Low.CYAN])
	splash.color_ramp = g
	splash.emitting = false
	add_child(splash)


static func arc_point(from: Vector3, to: Vector3, s: float) -> Vector3:
	var apex := 0.8 + from.distance_to(to) * 0.18
	return from.lerp(to, s) + Vector3.UP * 4.0 * apex * s * (1.0 - s)


func update(from: Vector3, to: Vector3, cam_pos: Vector3, on: bool, super_spray: bool, t: float) -> void:
	_mesh.clear_surfaces()
	_rain_mesh.clear_surfaces()
	splash.emitting = on
	if not on:
		return
	splash.global_position = to
	var width := 0.62 if super_spray else 0.34
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var prev_l := Vector3.ZERO
	var prev_r := Vector3.ZERO
	for i in SEGMENTS + 1:
		var s := float(i) / SEGMENTS
		var p := arc_point(from, to, s)
		var tangent := arc_point(from, to, minf(s + 0.02, 1.0)) - arc_point(from, to, maxf(s - 0.02, 0.0))
		var side := tangent.cross(cam_pos - p).normalized() * width * (0.6 + 0.4 * s) * 0.5
		var l := p - side
		var r := p + side
		if i > 0:
			var flow := fposmod(s * 7.0 - t * 5.0, 1.0)
			var c := Low.CYAN if flow < 0.45 else Low.SKY
			if super_spray and flow > 0.8:
				c = Low.WHITE
			for v in [prev_l, prev_r, r, prev_l, r, l]:
				_mesh.surface_set_color(c)
				_mesh.surface_add_vertex(v)
		prev_l = l
		prev_r = r
	_mesh.surface_end()
	if super_spray:
		_draw_rainbow(to, cam_pos)


func _draw_rainbow(at: Vector3, cam_pos: Vector3) -> void:
	var view := (cam_pos - at)
	view.y = 0.0
	view = view.normalized()
	var across := Vector3.UP.cross(view).normalized()
	var centre := at + Vector3.UP * 0.2 + view * 0.6
	_rain_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var steps := 14
	for b in RAINBOW.size():
		var r0 := 2.6 - b * 0.22
		var r1 := r0 - 0.22
		for k in steps:
			var a0 := PI * k / steps
			var a1 := PI * (k + 1) / steps
			var p00 := centre + (across * cos(a0) + Vector3.UP * sin(a0)) * r0
			var p01 := centre + (across * cos(a1) + Vector3.UP * sin(a1)) * r0
			var p10 := centre + (across * cos(a0) + Vector3.UP * sin(a0)) * r1
			var p11 := centre + (across * cos(a1) + Vector3.UP * sin(a1)) * r1
			for v in [p00, p01, p11, p00, p11, p10]:
				_rain_mesh.surface_set_color(RAINBOW[b])
				_rain_mesh.surface_add_vertex(v)
	_rain_mesh.surface_end()
