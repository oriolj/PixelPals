extends GutTest
## Pure logic: coverage-based splats, stroke interpolation, undo ring,
## autosave clock, palette. No renderer needed.

const Coverage := preload("res://scripts/paint/coverage.gd")
const Splatter := preload("res://scripts/paint/splatter.gd")
const Shapes := preload("res://scripts/paint/shapes.gd")
const Stroke := preload("res://scripts/paint/stroke.gd")
const UndoRing := preload("res://scripts/paint/undo_ring.gd")
const Autosave := preload("res://scripts/paint/autosave.gd")
const Palette := preload("res://scripts/paint/palette.gd")

const CANVAS_AREA := 1920.0 * 1080.0


func _paint_all_but(cov, keep: Vector2i) -> void:
	for row in Coverage.ROWS:
		for col in Coverage.COLS:
			if Vector2i(col, row) == keep:
				continue
			var c := Coverage.cell_center(Vector2i(col, row))
			for dx in [-45, -15, 15, 45]:
				for dy in [-45, -15, 15, 45]:
					cov.mark_disc(c + Vector2(dx, dy), 10)


func test_splat_targets_the_least_covered_cell() -> void:
	for keep in [Vector2i(3, 2), Vector2i(12, 6), Vector2i(8, 4)]:
		var cov := Coverage.new()
		_paint_all_but(cov, keep)
		assert_almost_eq(cov.cell(keep.x, keep.y), 0.0, 0.001)
		var sp := Splatter.new()
		sp.rng.seed = 42
		var s := sp.press(cov)
		assert_eq(s.cell, keep)
		assert_eq(Coverage.cell_of(s.center), keep, "the splat centre is inside the empty cell")


func test_splat_shrinks_when_neighbours_are_painted() -> void:
	var sums := [0.0, 0.0]
	for crowded in 2:
		for i in 20:
			var cov := Coverage.new()
			if crowded == 1:
				_paint_all_but(cov, Vector2i(8, 4))
			else:
				# paint one far corner so the centre cell is still the least covered
				cov.mark_disc(Vector2(10, 10), 5)
			var sp := Splatter.new()
			sp.rng.seed = i
			sums[crowded] += sp.make_splat(cov, false).radius
	assert_lt(sums[1], sums[0] * 0.7, "splats among drawings are smaller")


func test_splat_never_exceeds_eight_percent() -> void:
	var sp := Splatter.new()
	for i in 300:
		sp.rng.seed = i
		var cov := Coverage.new()
		var s := sp.make_splat(cov, i % 2 == 0)
		var area := Shapes.parts_area(s.parts)
		assert_true(area <= 0.08 * CANVAS_AREA, "splat %d covers %.3f of the canvas" % [i, area / CANVAS_AREA])
	# Even a huge radius request gets clamped.
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var parts := Shapes.splat(Vector2(960, 540), 600.0, [Color.RED], rng, 0.08 * CANVAS_AREA)
	assert_true(Shapes.parts_area(parts) <= 0.08 * CANVAS_AREA)


func test_splat_cooldown_ignores_fast_presses() -> void:
	var sp := Splatter.new()
	var cov := Coverage.new()
	var splats := 0
	var giggles := 0
	# Mash at 10 presses per second for 3 seconds.
	for i in 30:
		if sp.press(cov).is_empty():
			giggles += 1
		else:
			splats += 1
		sp.tick(0.1)
	assert_eq(splats, 6, "one splat per 0.5 s")
	assert_eq(giggles, 24)


func test_every_fifth_splat_is_rainbow() -> void:
	var sp := Splatter.new()
	var cov := Coverage.new()
	var rainbow: Array[bool] = []
	for i in 12:
		sp.tick(1.0)
		rainbow.append(sp.press(cov).rainbow)
	assert_eq(rainbow, [false, false, false, false, true, false, false, false, false, true, false, false] as Array[bool])


func test_rainbow_splat_uses_six_colours() -> void:
	var sp := Splatter.new()
	var s := sp.make_splat(Coverage.new(), true)
	var cols := {}
	for p in s.parts:
		cols[p.col.to_html()] = true
	assert_eq(cols.size(), 6)


func test_stroke_interpolates_dabs_between_frames() -> void:
	var st := Stroke.new()
	var r := 16.0
	var all := PackedVector2Array()
	all.append_array(st.begin(Vector2(100, 100), r))
	# A fast move: 300 px in one frame, then more frames of uneven length.
	for p in [Vector2(400, 100), Vector2(410, 100), Vector2(410, 350), Vector2(700, 600)]:
		all.append_array(st.move_to(p))
	var spacing := r / 4.0
	var gaps := 0
	for i in range(1, all.size()):
		var d := all[i].distance_to(all[i - 1])
		if d > spacing + 0.01:
			gaps += 1
	assert_eq(gaps, 0, "no gap between dabs is wider than a quarter radius")
	assert_gt(all.size(), 80)
	assert_almost_eq(all[all.size() - 1].distance_to(Vector2(700, 600)), 0.0, spacing + 0.01, "reaches the end")
	st.end()
	assert_eq(st.move_to(Vector2(0, 0)).size(), 0, "no dabs once the stroke ended")


func test_stroke_sitting_still_adds_no_dabs() -> void:
	var st := Stroke.new()
	st.begin(Vector2(50, 50), 8.0)
	for i in 10:
		assert_eq(st.move_to(Vector2(50, 50)).size(), 0)


func test_undo_ring_keeps_ten_and_drops_oldest() -> void:
	var ring := UndoRing.new()
	for i in 14:
		ring.push(i)
	assert_eq(ring.size(), 10)
	assert_eq(ring.items[0], 4, "the four oldest were dropped")
	var popped := []
	while ring.size() > 0:
		popped.append(ring.pop())
	assert_eq(popped, [13, 12, 11, 10, 9, 8, 7, 6, 5, 4])
	assert_null(ring.pop(), "an empty ring pops null")


func test_autosave_every_thirty_seconds() -> void:
	var a := Autosave.new()
	var saves := 0
	a.mark_dirty()
	for i in 29 * 10:
		if a.tick(0.1):
			saves += 1
	assert_eq(saves, 0, "nothing before 30 s")
	for i in 20:
		if a.tick(0.1):
			saves += 1
	assert_eq(saves, 1, "saved at 30 s")
	for i in 300:  # 30 s with nothing painted
		if a.tick(0.1):
			saves += 1
	assert_eq(saves, 1, "an unchanged picture is not saved again")
	a.mark_dirty()
	for i in 300:
		if a.tick(0.1):
			saves += 1
	assert_eq(saves, 2)


func test_palette_has_twelve_colours_and_dir_mapping() -> void:
	assert_eq(Palette.COLORS.size(), 12)
	var seen := {}
	for c in Palette.COLORS:
		seen[c.to_html()] = true
	assert_eq(seen.size(), 12, "all distinct")
	assert_eq(Palette.pot_for_dir(Vector2i.UP), 0)
	assert_eq(Palette.pot_for_dir(Vector2i.RIGHT), 1)
	assert_eq(Palette.pot_for_dir(Vector2i.DOWN), 2)
	assert_eq(Palette.pot_for_dir(Vector2i.LEFT), 3)
	assert_eq(Palette.pot_for_dir(Vector2i.ZERO), -1)


func test_every_stamp_has_a_shape_around_its_centre() -> void:
	for kind in Shapes.STAMPS:
		var parts := Shapes.stamp(kind, Vector2(500, 400), 150.0, Palette.COLORS[0])
		assert_gt(parts.size(), 0, kind)
		var box := Rect2(Vector2(500, 400), Vector2.ZERO)
		for p in parts:
			var pts: PackedVector2Array = p.pts if p.has("pts") else p.line
			for v in pts:
				box = box.expand(v)
		assert_between(box.size.x, 80.0, 170.0, "%s width" % kind)
		assert_lt(box.get_center().distance_to(Vector2(500, 400)), 30.0, "%s is centred" % kind)


func test_coverage_counts_overlaps_once() -> void:
	var cov := Coverage.new()
	for i in 50:
		cov.mark_disc(Vector2(60, 60), 30)
	var once := cov.total()
	var cov2 := Coverage.new()
	cov2.mark_disc(Vector2(60, 60), 30)
	assert_almost_eq(once, cov2.total(), 0.0001)
	assert_gt(cov.cell(0, 0), 0.0)
