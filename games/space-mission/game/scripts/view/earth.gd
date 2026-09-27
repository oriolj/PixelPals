extends Node2D
## The Earth: a big dome filling the bottom of the orbit screen. A ColorRect
## runs a shader that maps the `earth` strip onto a sphere, scrolls it (the
## planet turns), lays the clouds on top at their own speed, and sweeps the
## day/night terminator with city lights (`earth_night`) on the dark side.
##
## Crisp by construction: every lookup is a texelFetch (no filtering at all),
## the edge is a precomputed pixel-circle mask (baked here into an image), and
## every output pixel is a palette colour: the terminator blends day and night
## with an ordered 4x4 dither, never with alpha.

const Tex := preload("res://scripts/view/tex.gd")

const TOP := 128                       # first screen row of the rect
const SIZE := Vector2i(320, 52)
const CENTER := Vector2(160.0, 222.0)  # globe centre in rect pixels (screen y 350)
const RADIUS := 220.0
const TEX_W := 768
const TEX_H := 96
## A sunrise every SUNRISE_EVERY seconds of play (the real ISS: every 90 minutes).
const SUNRISE_EVERY := 20.0
const TURN_SPEED := 6.0                # texels per second
const CLOUD_SPEED := 8.5

const SHADER := """
shader_type canvas_item;

uniform sampler2D day_tex : filter_nearest;
uniform sampler2D night_tex : filter_nearest;
uniform sampler2D cloud_tex : filter_nearest;
uniform sampler2D mask_tex : filter_nearest;
uniform vec2 rect_size;
uniform vec2 center;
uniform float radius;
uniform float k_tex;
uniform float rot;
uniform float cloud_rot;
uniform float sun_angle;
uniform float gleam;
uniform vec4 atmo_day : source_color;
uniform vec4 atmo_night : source_color;
uniform vec4 gold : source_color;
uniform vec4 cloud_night : source_color;

float bayer4(ivec2 p) {
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0 - 0.5;
}

void fragment() {
	ivec2 p = ivec2(floor(UV * rect_size));
	float m = texelFetch(mask_tex, p, 0).r;
	if (m < 0.25) {
		discard;
	}
	vec2 d = vec2(p) + 0.5 - center;
	vec3 n = vec3(d.x / radius, -d.y / radius, 0.0);
	n.z = sqrt(max(0.0, 1.0 - n.x * n.x - n.y * n.y));
	vec3 s = normalize(vec3(sin(sun_angle), 0.45, cos(sun_angle)));
	float light = dot(n, s);
	float dither = bayer4(p);
	bool day = light + dither * 0.16 > 0.0;
	if (m < 0.75) {
		COLOR = day ? atmo_day : atmo_night;
	} else {
		ivec2 ts = textureSize(day_tex, 0);
		float r_row = sqrt(max(1.0, radius * radius - d.y * d.y));
		float lon = asin(clamp(d.x / r_row, -1.0, 1.0));
		float lat = asin(clamp(-d.y / radius, -1.0, 1.0));
		int ty = clamp(int(floor((1.5707963 - lat) * k_tex)), 0, ts.y - 1);
		int tx = int(floor(lon * k_tex + rot));
		tx = ((tx % ts.x) + ts.x) % ts.x;
		vec4 c = day ? texelFetch(day_tex, ivec2(tx, ty), 0) : texelFetch(night_tex, ivec2(tx, ty), 0);
		int cx = int(floor(lon * k_tex + cloud_rot));
		cx = ((cx % ts.x) + ts.x) % ts.x;
		vec4 cl = texelFetch(cloud_tex, ivec2(cx, ty), 0);
		if (cl.a > 0.5) {
			c = day ? cl : cloud_night;
		}
		if (gleam > 0.0 && abs(light + dither * 0.02) < 0.05 * gleam) {
			c = gold;
		}
		COLOR = vec4(c.rgb, 1.0);
	}
}
"""

## Seconds of play; drives the turning and the sun.
var time := 0.0
## 0..1: the golden line along the terminator at a sunrise.
var gleam := 0.0
var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	_rect = ColorRect.new()
	_rect.position = Vector2(0, TOP)
	_rect.size = Vector2(SIZE)
	_rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("day_tex", Tex.texture("earth", Vector2i(TEX_W, TEX_H), Color("#0099db")))
	_mat.set_shader_parameter("night_tex", Tex.texture("earth_night", Vector2i(TEX_W, TEX_H), Color("#262b44")))
	_mat.set_shader_parameter("cloud_tex", Tex.texture("earth_clouds", Vector2i(TEX_W, TEX_H), Color(0, 0, 0, 0)))
	_mat.set_shader_parameter("mask_tex", ImageTexture.create_from_image(bake_mask()))
	_mat.set_shader_parameter("rect_size", Vector2(SIZE))
	_mat.set_shader_parameter("center", CENTER)
	_mat.set_shader_parameter("radius", RADIUS)
	_mat.set_shader_parameter("k_tex", TEX_W / TAU)
	_mat.set_shader_parameter("atmo_day", Color("#2ce8f5"))
	_mat.set_shader_parameter("atmo_night", Color("#124e89"))
	_mat.set_shader_parameter("gold", Color("#feae34"))
	_mat.set_shader_parameter("cloud_night", Color("#3a4466"))
	_rect.material = _mat
	add_child(_rect)
	tick(0.0)


## The pixel-circle mask: 1.0 inside the globe, 0.5 on the 2 px atmosphere rim
## just outside it, 0 elsewhere. Tested pixel centres, so the edge is exact.
static func bake_mask() -> Image:
	var img := Image.create(SIZE.x, SIZE.y, false, Image.FORMAT_R8)
	for y in SIZE.y:
		for x in SIZE.x:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(CENTER)
			var v := 0.0
			if d <= RADIUS:
				v = 1.0
			elif d <= RADIUS + 2.0:
				v = 0.5
			img.set_pixel(x, y, Color(v, 0, 0))
	return img


## The sun's angle for a time: the day side enters from the left at each sunrise.
static func sun_angle_at(t: float) -> float:
	return TAU * fposmod(t, SUNRISE_EVERY) / SUNRISE_EVERY - PI * 0.72


## True if screen point p is on the globe (the mask, not the rim).
static func on_globe(p: Vector2) -> bool:
	return Vector2(floorf(p.x) + 0.5, floorf(p.y) - TOP + 0.5).distance_to(CENTER) <= RADIUS


func tick(dt: float) -> void:
	time += dt
	_mat.set_shader_parameter("rot", floorf(time * TURN_SPEED))
	_mat.set_shader_parameter("cloud_rot", floorf(time * CLOUD_SPEED))
	_mat.set_shader_parameter("sun_angle", sun_angle_at(time))
	_mat.set_shader_parameter("gleam", gleam)
