extends Node2D
## The Mars sky: a butterscotch day (#e4a672 at the top to #b86f50 at the
## horizon) and the real Mars sunset: a brown sky with a BLUE halo around a
## small white sun. A shader draws it; every pixel is a palette colour (ramps
## and the day-to-sunset change are ordered 4x4 dithers, never alpha).

const SHADER := """
shader_type canvas_item;

uniform vec2 rect_size;
uniform float horizon;
uniform float blend;
uniform vec2 sun;
uniform vec4 day_top : source_color;
uniform vec4 day_low : source_color;
uniform vec4 dusk_top : source_color;
uniform vec4 dusk_low : source_color;
uniform vec4 halo_in : source_color;
uniform vec4 halo_out : source_color;
uniform vec4 sun_col : source_color;

float bayer4(ivec2 p) {
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[(p.y & 3) * 4 + (p.x & 3)]) + 0.5) / 16.0;
}

void fragment() {
	ivec2 p = ivec2(floor(UV * rect_size));
	float th = bayer4(p);
	float y = float(p.y) + 0.5;
	float ramp = clamp((y / horizon - 0.3) / 0.6, 0.0, 1.0);
	vec4 c = ramp > th ? day_low : day_top;
	if (blend > th) {
		float dr = clamp((y / horizon - 0.15) / 0.8, 0.0, 1.0);
		c = dr > th ? dusk_low : dusk_top;
		float r = distance(vec2(p) + 0.5, sun);
		float out_k = clamp((24.0 - r) / 12.0, 0.0, 1.0);
		if (out_k > th) {
			c = halo_out;
		}
		if (r < 9.0 + (th - 0.5) * 2.0) {
			c = halo_in;
		}
		if (r < 4.6) {
			c = sun_col;
		}
	}
	COLOR = vec4(c.rgb, 1.0);
}
"""

## 0 = day, 1 = sunset (the dither steps between them).
var blend := 0.0:
	set(v):
		blend = clampf(v, 0.0, 1.0)
		if _mat:
			_mat.set_shader_parameter("blend", blend)
var sun := Vector2(232, 58):
	set(v):
		sun = v
		if _mat:
			_mat.set_shader_parameter("sun", sun)
var height := 180
var horizon := 130.0
var _mat: ShaderMaterial


func _ready() -> void:
	var rect := ColorRect.new()
	rect.size = Vector2(320, height)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = SHADER
	_mat = ShaderMaterial.new()
	_mat.shader = sh
	_mat.set_shader_parameter("rect_size", Vector2(320, height))
	_mat.set_shader_parameter("horizon", horizon)
	_mat.set_shader_parameter("day_top", Color("#e4a672"))
	_mat.set_shader_parameter("day_low", Color("#b86f50"))
	_mat.set_shader_parameter("dusk_top", Color("#733e39"))
	_mat.set_shader_parameter("dusk_low", Color("#b86f50"))
	_mat.set_shader_parameter("halo_in", Color("#2ce8f5"))
	_mat.set_shader_parameter("halo_out", Color("#0099db"))
	_mat.set_shader_parameter("sun_col", Color("#ffffff"))
	_mat.set_shader_parameter("blend", blend)
	_mat.set_shader_parameter("sun", sun)
	rect.material = _mat
	add_child(rect)
