extends GutTest
## The GDScript mirror of the light-mask shader (gameplay and tests use it).

const LightMask := preload("res://scripts/fort/light_mask.gd")


func _flash(at: Vector2) -> Array:
	return [{"pos": at, "r": LightMask.FLASH_RADIUS}]


func test_light_amount_is_full_at_the_centre_and_zero_outside() -> void:
	var lights := _flash(Vector2(100, 90))
	assert_eq(LightMask.light_amount(Vector2(100, 90), lights), 1.0)
	assert_eq(LightMask.light_amount(Vector2(120, 90), lights), 1.0)
	assert_eq(LightMask.light_amount(Vector2(100 + 37, 90), lights), 0.0)
	assert_eq(LightMask.light_amount(Vector2(10, 10), lights), 0.0)
	# The two dithered bands sit at the edge, inside the radius.
	assert_almost_eq(LightMask.light_amount(Vector2(100 + 32, 90), lights), 2.0 / 3.0, 0.001)
	assert_almost_eq(LightMask.light_amount(Vector2(100 + 35, 90), lights), 1.0 / 3.0, 0.001)


func test_light_mirror_snaps_to_whole_pixels() -> void:
	# Any sub-pixel position inside one pixel gives the same answer.
	var a := _flash(Vector2(100.0, 90.0))
	var b := _flash(Vector2(100.9, 90.7))
	for x in range(60, 141):
		for y in [90, 60, 100]:
			var p := Vector2(x, y)
			assert_eq(LightMask.light_amount(p, a), LightMask.light_amount(p, b), "pixel %s" % p)
			assert_eq(LightMask.light_amount(p + Vector2(0.99, 0.5), a), LightMask.light_amount(p, a))
	assert_eq(LightMask.snap(Vector2(3.99, -0.2)), Vector2i(3, -1))
	var u := LightMask.uniforms(b)
	assert_eq(u.light_pos[0], Vector2(100, 90), "the shader gets the snapped centre")


func test_dithered_edge_uses_two_bands_of_the_bayer_matrix() -> void:
	var lights := _flash(Vector2(160, 90))
	var lit_mid := 0
	var lit_outer := 0
	var mid_n := 0
	var outer_n := 0
	for y in range(40, 141):
		for x in range(100, 221):
			var p := Vector2i(x, y)
			var a := LightMask.light_amount(Vector2(p), lights)
			if is_equal_approx(a, 2.0 / 3.0):
				mid_n += 1
				lit_mid += int(LightMask.lit_pixel(p, lights))
			elif is_equal_approx(a, 1.0 / 3.0):
				outer_n += 1
				lit_outer += int(LightMask.lit_pixel(p, lights))
			elif a == 1.0:
				assert_true(LightMask.lit_pixel(p, lights))
			else:
				assert_false(LightMask.lit_pixel(p, lights))
	assert_almost_eq(float(lit_mid) / mid_n, 11.0 / 16.0, 0.05)
	assert_almost_eq(float(lit_outer) / outer_n, 5.0 / 16.0, 0.05)


func test_darkness_strength_never_exceeds_sixty_percent() -> void:
	assert_true(LightMask.STRENGTH <= 0.6)
	assert_eq(LightMask.MAX_STRENGTH, 0.6)
	assert_eq(LightMask.darkness(Vector2i(0, 0), [], 0.95), 0.6, "clamped even if asked for more")
	# The shader clamps too, and its uniform hint caps at 0.6.
	var code := FileAccess.get_file_as_string(LightMask.SHADER_PATH)
	assert_string_contains(code, "min(strength, 0.6)")
	assert_string_contains(code, "hint_range(0.0, 0.6)")


func test_max_eight_lights_reach_the_shader() -> void:
	var many := []
	for i in 12:
		many.append({"pos": Vector2(i * 20, 10), "r": 10.0})
	var u := LightMask.uniforms(many)
	assert_eq(u.light_pos.size(), 8)
	assert_eq(u.light_radius.size(), 8)
	assert_eq(LightMask.light_amount(Vector2(200, 10), many), 0.0, "light 11 is ignored by both")


func test_shader_file_is_godot_4_syntax() -> void:
	var code := FileAccess.get_file_as_string(LightMask.SHADER_PATH)
	assert_string_contains(code, "shader_type canvas_item;")
	assert_false(code.contains("SCREEN_TEXTURE"))
	assert_false(code.contains("hint_color"))
	var m := LightMask.make_material()
	assert_not_null(m.shader)
