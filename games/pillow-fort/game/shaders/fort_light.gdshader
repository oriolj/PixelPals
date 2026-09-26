// Pillow Fort light mask (Godot 4.x canvas_item). Drawn by a ColorRect that
// covers the screen: it outputs the warm dusk colour with
// alpha = strength * (1 - lit), so it needs no screen read.
// scripts/fort/light_mask.gd is the exact GDScript mirror of this maths;
// `make light-check` compares the two pixel by pixel.
shader_type canvas_item;

const int MAX_LIGHTS = 8;

uniform vec2 size = vec2(320.0, 180.0);
// Light centres in whole pixels (floored by the caller) and radii in pixels.
uniform vec2 light_pos[MAX_LIGHTS];
uniform float light_radius[MAX_LIGHTS];
uniform float strength : hint_range(0.0, 0.6) = 0.55;
uniform vec4 dusk_top : source_color = vec4(0.161, 0.212, 0.435, 1.0);    // #29366f
uniform vec4 dusk_bottom : source_color = vec4(0.365, 0.153, 0.365, 1.0); // #5d275d
uniform vec4 warm : source_color = vec4(1.0, 0.804, 0.459, 1.0);         // #ffcd75
uniform float warm_alpha = 0.10;
// 1 = calibration output for the light check: opaque white where lit, black elsewhere.
uniform int debug_mode = 0;

float bayer4(ivec2 p) {
	int x = p.x & 3;
	int y = p.y & 3;
	int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
	return (float(m[y * 4 + x]) + 0.5) / 16.0;
}

// 1.0 in the core, 2/3 and 1/3 in the two edge bands, 0 outside. Squared
// integer distances only, so the GPU and the CPU mirror agree exactly.
float level(vec2 p, vec2 c, float r) {
	if (r <= 0.0) {
		return 0.0;
	}
	vec2 d = p - c;
	float d2 = d.x * d.x + d.y * d.y;
	float band = floor(max(2.0, r / 12.0));
	float r_core = max(r - 2.0 * band, 0.0);
	float r_mid = r - band;
	if (d2 <= r_core * r_core) {
		return 1.0;
	}
	if (d2 <= r_mid * r_mid) {
		return 2.0 / 3.0;
	}
	if (d2 <= r * r) {
		return 1.0 / 3.0;
	}
	return 0.0;
}

void fragment() {
	vec2 p = floor(UV * size);
	float amount = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		amount = max(amount, level(p, light_pos[i], light_radius[i]));
	}
	float lit = amount > bayer4(ivec2(p)) ? 1.0 : 0.0;
	if (debug_mode == 1) {
		COLOR = vec4(vec3(lit), 1.0);
	} else {
		vec4 dusk = mix(dusk_top, dusk_bottom, p.y / size.y);
		float a = min(strength, 0.6) * (1.0 - lit);
		// Inside the light: a thin warm tint instead of the dusk.
		COLOR = lit > 0.5 ? vec4(warm.rgb, warm_alpha * strength / 0.55) : vec4(dusk.rgb, a);
	}
}
