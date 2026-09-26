extends GutTest
## field_rules.gd on its own: tile states, growth, harvest, trailer, barn,
## the run's end. No nodes.

const FieldRules := preload("res://scripts/field_rules.gd")
const Tile := FieldRules.Tile
const Crop := FieldRules.Crop

var f


func before_each() -> void:
	f = FieldRules.new()


func _ripe(c: Vector2i, crop := Crop.CARROT) -> void:
	f.plough(c)
	f.plant(c, crop)
	for i in 3:
		f.advance(c)


func _center(c: Vector2i) -> Vector2:
	return FieldRules.cell_center(c)


func test_planter_seeds_only_ploughed_tiles_with_current_seed() -> void:
	var grass := Vector2i(2, 2)
	var soil := Vector2i(3, 2)
	f.plough(soil)
	assert_false(f.plant(grass, Crop.PUMPKIN), "grass is never seeded")
	assert_eq(f.tile(grass), Tile.GRASS)
	assert_true(f.plant(soil, Crop.PUMPKIN))
	assert_eq(f.tile(soil), Tile.SEEDED)
	assert_eq(f.crop_of(soil), Crop.PUMPKIN)
	assert_eq(f.planted[Crop.PUMPKIN], 1)
	assert_false(f.plant(Vector2i(-1, 0), Crop.CARROT), "outside the field")
	assert_false(f.plant(Vector2i(4, 2), -1), "no seed, no planting")


func test_replanting_a_seeded_tile_keeps_the_first_seed() -> void:
	var c := Vector2i(5, 5)
	f.plough(c)
	f.plant(c, Crop.SUNFLOWER)
	assert_false(f.plant(c, Crop.CARROT))
	assert_eq(f.crop_of(c), Crop.SUNFLOWER)
	f.advance(c)
	assert_false(f.plant(c, Crop.STRAWBERRY))
	assert_eq(f.crop_of(c), Crop.SUNFLOWER)
	assert_eq(f.tile(c), Tile.SPROUT, "a second pass never resets growth")
	assert_eq(f.planted[Crop.CARROT], 0)


func test_plough_only_changes_grass() -> void:
	var c := Vector2i(1, 1)
	assert_true(f.plough(c))
	f.plant(c, Crop.CARROT)
	assert_false(f.plough(c), "the plough never turns a seeded tile back")
	assert_eq(f.tile(c), Tile.SEEDED)


func test_rain_advances_tiles_in_radius_by_one_stage() -> void:
	var mid := Vector2i(8, 4)
	for y in range(2, 7):
		for x in range(6, 11):
			var c := Vector2i(x, y)
			f.plough(c)
			f.plant(c, Crop.CARROT)
	var hit: Array[Vector2i] = f.rain(_center(mid))
	# Radius 1.5 tiles: the centre, its 4 neighbours and 4 diagonals (1.41).
	assert_eq(hit.size(), 9)
	for y in range(2, 7):
		for x in range(6, 11):
			var c := Vector2i(x, y)
			var inside := absi(x - 8) <= 1 and absi(y - 4) <= 1
			assert_eq(f.tile(c), Tile.SPROUT if inside else Tile.SEEDED, "cell %s" % c)
	# One shower grows each tile once, however long it lasts.
	var already := {}
	f.rain(_center(mid), already)
	f.rain(_center(mid), already)
	assert_eq(f.tile(mid), Tile.GROWING)


func test_rain_on_empty_soil_makes_a_puddle_never_harm() -> void:
	var grass := Vector2i(3, 3)
	var soil := Vector2i(4, 3)
	f.plough(soil)
	var ripe := Vector2i(5, 3)
	_ripe(ripe, Crop.STRAWBERRY)
	f.drain_events()
	for i in 10:
		f.rain(_center(Vector2i(4, 3)))
	assert_eq(f.tile(grass), Tile.GRASS)
	assert_eq(f.tile(soil), Tile.PLOUGHED)
	assert_gt(f.wet[FieldRules.idx(grass)], 0.0)
	assert_gt(f.wet[FieldRules.idx(soil)], 0.0)
	assert_eq(f.tile(ripe), Tile.RIPE, "no over-watering")
	assert_eq(f.crop_of(ripe), Crop.STRAWBERRY)
	var types := {}
	for e in f.drain_events():
		types[e.type] = true
	assert_true(types.has("puddle"))
	assert_true(types.has("sparkle"), "rain on ripe crops sparkles")
	f.tick(FieldRules.WET_SECONDS + 0.1)
	assert_eq(f.wet[FieldRules.idx(grass)], 0.0, "puddles dry up")


func test_sun_growth_advances_without_rain() -> void:
	var c := Vector2i(0, 0)
	f.plough(c)
	f.plant(c, Crop.PUMPKIN)
	f.tick(FieldRules.SUN_SECONDS - 0.5)
	assert_eq(f.tile(c), Tile.SEEDED)
	f.tick(1.0)
	assert_eq(f.tile(c), Tile.SPROUT)
	for i in 10:
		f.tick(FieldRules.SUN_SECONDS)
	assert_eq(f.tile(c), Tile.RIPE, "the sun alone ripens everything")
	assert_eq(f.crop_of(c), Crop.PUMPKIN, "and nothing ever wilts")


func test_driving_over_sprouts_never_destroys_them() -> void:
	var c := Vector2i(6, 1)
	f.plough(c)
	f.plant(c, Crop.CARROT)
	for stage in [Tile.SEEDED, Tile.SPROUT, Tile.GROWING]:
		assert_eq(f.tile(c), stage)
		for i in 5:
			f.drive_over(c)
			f.plough(c)
		assert_eq(f.tile(c), stage, "wheels and plough leave stage %d alone" % stage)
		assert_eq(f.crop_of(c), Crop.CARROT)
		f.advance(c)
	var wobbles := 0
	for e in f.drain_events():
		if e.type == "wobble":
			wobbles += 1
	assert_eq(wobbles, 15, "every pass is a wobble")


func test_harvest_moves_ripe_crop_to_trailer_and_resets_tile() -> void:
	var c := Vector2i(9, 8)
	_ripe(c, Crop.SUNFLOWER)
	f.drive_over(c)
	assert_eq(f.trailer, [Crop.SUNFLOWER] as Array[int])
	assert_eq(f.tile(c), Tile.PLOUGHED, "ready to be planted again")
	assert_eq(f.crop_of(c), -1)
	f.drive_over(c)
	assert_eq(f.trailer.size(), 1, "nothing left to harvest")


func test_trailer_caps_at_24_and_tips_at_barn() -> void:
	for i in 30:
		_ripe(Vector2i(i % 16, i / 16), i % 4)
	for i in 30:
		f.drive_over(Vector2i(i % 16, i / 16))
	assert_eq(f.trailer.size(), FieldRules.TRAILER_CAP)
	assert_true(f.trailer_full())
	assert_eq(f.count(Tile.RIPE), 6, "crops that do not fit simply stay ripe")
	var tipped: Array[int] = f.tip()
	assert_eq(tipped.size(), 24)
	assert_eq(f.trailer.size(), 0)
	assert_eq(f.barn, [6, 6, 6, 6] as Array[int], "each crop to its own crate")
	for i in range(24, 30):
		f.drive_over(Vector2i(i % 16, i / 16))
	assert_eq(f.trailer.size(), 6, "the empty trailer takes the rest")


func test_seed_directions_map_to_four_crops() -> void:
	assert_eq(FieldRules.seed_for_dir(Vector2i.UP), Crop.CARROT)
	assert_eq(FieldRules.seed_for_dir(Vector2i.RIGHT), Crop.PUMPKIN)
	assert_eq(FieldRules.seed_for_dir(Vector2i.DOWN), Crop.SUNFLOWER)
	assert_eq(FieldRules.seed_for_dir(Vector2i.LEFT), Crop.STRAWBERRY)
	assert_eq(FieldRules.seed_for_dir(Vector2i.ZERO), -1)
	for c in 4:
		assert_eq(FieldRules.seed_for_dir(FieldRules.dir_for_seed(c)), c)


func test_run_ends_at_thirty_crops_or_six_minutes() -> void:
	assert_false(f.run_over())
	f.barn.assign([10, 10, 9, 0])
	assert_false(f.run_over(), "29 crops")
	f.barn[3] = 1
	assert_true(f.run_over(), "30 crops")
	var g = FieldRules.new()
	g.tick(359.0)
	assert_false(g.run_over())
	g.tick(1.0)
	assert_true(g.run_over(), "6 minutes")
	assert_eq(FieldRules.END_SECONDS, 360.0)
	assert_eq(FieldRules.END_CROPS, 30)


func test_most_planted_picks_the_giant() -> void:
	assert_eq(f.most_planted(), Crop.CARROT, "carrot when nothing was planted")
	for x in 3:
		f.plough(Vector2i(x, 0))
		f.plant(Vector2i(x, 0), Crop.STRAWBERRY)
	f.plough(Vector2i(5, 0))
	f.plant(Vector2i(5, 0), Crop.PUMPKIN)
	assert_eq(f.most_planted(), Crop.STRAWBERRY)


func test_nibble_only_takes_a_ripe_crop_and_no_counter_drops() -> void:
	var c := Vector2i(2, 7)
	f.plough(c)
	f.plant(c, Crop.CARROT)
	assert_false(f.nibble(c), "visitors never eat young plants")
	for i in 3:
		f.advance(c)
	f.barn.assign([3, 0, 0, 0])
	f.trailer.append(Crop.PUMPKIN)
	assert_true(f.nibble(c))
	assert_eq(f.tile(c), Tile.PLOUGHED)
	assert_eq(f.barn, [3, 0, 0, 0] as Array[int])
	assert_eq(f.trailer.size(), 1)
