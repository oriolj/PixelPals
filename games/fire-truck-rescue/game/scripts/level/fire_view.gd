extends Node3D
## One fire, seen: three wobbling prism flames with a silly pixel face, an
## orange glow, a smoke column tall enough to spot from anywhere, a big
## floating flame icon and a pulsing ring on the ground. Steam bursts when
## the water knocks it down a size. It never looks scary: the face squints
## and puffs its cheeks when sprayed.

const Low := preload("res://scripts/level/low.gd")

const SIZE_SCALE := [0.0, 1.0, 1.4, 1.8]
const FLAME_SHADER := """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 col : source_color;
uniform float phase = 0.0;
void vertex() {
	float h = clamp(VERTEX.y + 0.8, 0.0, 1.6);
	VERTEX.x += sin(TIME * 9.0 + phase + VERTEX.y * 5.0) * 0.14 * h;
	VERTEX.z += cos(TIME * 7.0 + phase * 1.7) * 0.09 * h;
	VERTEX.y *= 1.0 + sin(TIME * 11.0 + phase) * 0.08;
}
void fragment() {
	ALBEDO = col.rgb;
}
"""

static var _shader: Shader

var flames: Node3D
var face: AnimatedSprite3D
var icon: AnimatedSprite3D
var ring: MeshInstance3D
var glow: OmniLight3D
var smoke: CPUParticles3D
var steam: CPUParticles3D
var base_y := 0.3
var facing := Vector2.ZERO
var _scale := 0.0
var _blink := 0.0


func setup(pos: Vector2, kind: String, face_dir: Vector2) -> void:
	facing = face_dir
	base_y = {"house": 0.2, "bin": 1.3, "hay": 2.4}.get(kind, 0.2)
	position = Vector3(pos.x, 0, pos.y)


func _ready() -> void:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = FLAME_SHADER
	flames = Node3D.new()
	flames.position = Vector3(0, base_y, 0)
	add_child(flames)
	_flame(0.75, 2.3, Low.RED, Vector3(0, 1.15, 0.1), 0.0)
	_flame(0.6, 2.0, Low.ORANGE, Vector3(-0.35, 1.0, -0.1), 1.7)
	_flame(0.55, 1.7, Low.ORANGE, Vector3(0.4, 0.85, -0.05), 3.1)
	_flame(0.45, 1.35, Low.YELLOW, Vector3(0.05, 0.68, -0.25), 4.4)
	_flame(0.22, 0.8, Low.WHITE.lerp(Low.YELLOW, 0.4), Vector3(0.05, 0.4, -0.35), 5.3)
	face = Low.billboard(flames, "fire_face", Low.YELLOW, Vector3(facing.x * 0.45, 0.75, facing.y * 0.45), 1.0 / 16.0)
	face.stop()
	glow = OmniLight3D.new()
	glow.light_color = Low.ORANGE
	glow.omni_range = 7.0
	glow.position = Vector3(0, base_y + 1.5, 0)
	add_child(glow)
	smoke = CPUParticles3D.new()
	smoke.mesh = Low.puff_mesh(0.38)
	smoke.amount = 14
	smoke.lifetime = 3.2
	smoke.direction = Vector3.UP
	smoke.spread = 12.0
	smoke.initial_velocity_min = 2.4
	smoke.initial_velocity_max = 3.4
	smoke.gravity = Vector3(0.3, 0.3, 0)
	smoke.scale_amount_min = 0.8
	smoke.scale_amount_max = 1.3
	smoke.scale_amount_curve = _curve([Vector2(0, 0.4), Vector2(0.3, 1.4), Vector2(1, 2.4)])
	smoke.color_ramp = _gradient([Low.DARK, Low.SLATE, Low.GREY.lightened(0.2)])
	smoke.position = Vector3(0, base_y + 1.6, 0)
	smoke.emitting = false
	add_child(smoke)
	steam = CPUParticles3D.new()
	steam.mesh = Low.puff_mesh(0.45)
	steam.amount = 18
	steam.lifetime = 1.6
	steam.one_shot = true
	steam.explosiveness = 0.9
	steam.direction = Vector3.UP
	steam.spread = 60.0
	steam.initial_velocity_min = 2.0
	steam.initial_velocity_max = 4.0
	steam.gravity = Vector3(0, 1.0, 0)
	steam.scale_amount_curve = _curve([Vector2(0, 0.6), Vector2(0.4, 1.6), Vector2(1, 0.2)])
	steam.color_ramp = _gradient([Low.WHITE, Low.WHITE, Low.GREY])
	steam.position = Vector3(0, base_y + 0.8, 0)
	steam.emitting = false
	add_child(steam)
	icon = Low.billboard(self, "flame_icon", Low.ORANGE, Vector3(0, base_y + 8.0, 0), 0.16)
	var tm := TorusMesh.new()
	tm.inner_radius = 2.3
	tm.outer_radius = 2.8
	tm.rings = 16
	tm.ring_segments = 4
	ring = MeshInstance3D.new()
	ring.mesh = tm
	ring.material_override = Low.mat(Low.YELLOW, true)
	ring.scale = Vector3(1, 0.05, 1)
	ring.position = Vector3(0, 0.12, 0)
	add_child(ring)
	flames.scale = Vector3.ONE * 0.001
	_set_visible(false)


## A low-poly flame: a 6-sided cone with the wobble shader.
func _flame(r: float, h: float, c: Color, at: Vector3, phase: float) -> void:
	var cm := CylinderMesh.new()
	cm.top_radius = 0.0
	cm.bottom_radius = r
	cm.height = h
	cm.radial_segments = 6
	cm.rings = 2
	var mi := MeshInstance3D.new()
	mi.mesh = cm
	var m := ShaderMaterial.new()
	m.shader = _shader
	m.set_shader_parameter("col", c)
	m.set_shader_parameter("phase", phase)
	mi.material_override = m
	mi.position = at
	mi.rotation.y = phase
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	flames.add_child(mi)


static func _curve(pts: Array) -> Curve:
	var c := Curve.new()
	c.max_value = 3.0
	for p in pts:
		c.add_point(p)
	return c


static func _gradient(cols: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray(cols)
	return g


func _set_visible(on: bool) -> void:
	flames.visible = on
	icon.visible = on
	glow.visible = on


func puff() -> void:
	steam.restart()
	steam.emitting = true


## `fire` is the fire_state; `target` = this is the current objective.
func update(dt: float, fire, target: bool, t: float, cam_pos := Vector3.ZERO) -> void:
	var lit: bool = fire.lit()
	var want: float = SIZE_SCALE[clampi(fire.size, 0, 3)] if lit else 0.0
	_scale = move_toward(_scale, want, dt * 1.6)
	var s := maxf(_scale, 0.001)
	flames.scale = Vector3(s, s, s)
	_set_visible(_scale > 0.01)
	icon.visible = lit
	smoke.emitting = lit
	smoke.scale_amount_min = 0.5 + 0.25 * fire.size
	smoke.scale_amount_max = 0.8 + 0.3 * fire.size
	glow.light_energy = (1.6 + 0.6 * sin(t * 17.0) + 0.3 * sin(t * 5.0)) * _scale
	icon.position.y = base_y + 8.0 + sin(t * 3.0) * 0.5
	ring.visible = lit and target
	var pulse := 1.0 + 0.15 * sin(t * 6.0)
	ring.scale = Vector3(pulse, 0.05, pulse)
	# The face sits on the flames' camera side, so it is never hidden inside them.
	if cam_pos != Vector3.ZERO and flames.visible:
		var centre := global_position + Vector3(0, base_y + 0.9 * s, 0)
		var to_cam := (cam_pos - centre)
		to_cam.y = 0.0
		face.global_position = centre + to_cam.normalized() * 0.75 * s
		face.pixel_size = 1.3 / 16.0 * clampf(s, 0.8, 1.4)
	# Face: squints while wet, blinks now and then.
	_blink -= dt
	if _blink < -0.15:
		_blink = randf_range(1.5, 3.5)
	if fire.dry_t < 0.25:
		face.frame = 1
	elif _blink < 0.0:
		face.frame = 2 if face.sprite_frames.get_frame_count("default") > 2 else 0
	else:
		face.frame = 0
