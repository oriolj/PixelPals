extends GutTest
## Pure logic: viewfinder, creatures, lights, rules and the reef map.

const Viewfinder := preload("res://scripts/level/viewfinder.gd")
const Creatures := preload("res://scripts/level/creatures.gd")
const Lights := preload("res://scripts/level/lights.gd")
const Rules := preload("res://scripts/level/rules.gd")
const ReefMap := preload("res://scripts/level/reef.gd")
const SubMotion := preload("res://scripts/level/sub_motion.gd")
const Species := preload("res://scripts/level/species.gd")
const DT := 1.0 / 30.0


func _run(c, seconds: float, lights_on: bool) -> void:
	for i in int(seconds / DT):
		Creatures.step(c, DT, lights_on)


func test_assist_picks_within_24px_of_the_frame_only() -> void:
	var base := Vector2(100, 100)
	var near := base + Vector2(24 + 20, 0)   # 20 px beyond the right edge
	var far := base + Vector2(24 + 30, 0)
	assert_eq(Viewfinder.assist_pick(base, [far, near]), 1)
	assert_eq(Viewfinder.assist_pick(base, [far]), -1)
	var inside := base + Vector2(5, 5)
	assert_eq(Viewfinder.assist_pick(base, [near, inside]), 1, "the one closest to the centre")
	assert_eq(Viewfinder.goal(base, [base + Vector2(30, 0)]), base + Vector2(30, 0), "centres it")
	assert_eq(Viewfinder.goal(base, [far]), base)


func test_frame_sits_on_the_pointed_side() -> void:
	var sub := Vector2(200, 100)
	assert_gt(Viewfinder.base_center(sub, Vector2i.RIGHT).x, sub.x + 40)
	assert_lt(Viewfinder.base_center(sub, Vector2i.LEFT).x, sub.x - 40)
	assert_lt(Viewfinder.base_center(sub, Vector2i.UP).y, sub.y - 30)
	assert_gt(Viewfinder.base_center(sub, Vector2i.DOWN).y, sub.y + 30)


func test_contains_counts_any_motion_and_big_subjects() -> void:
	var frame := Viewfinder.rect_at(Vector2(100, 100))
	assert_true(Viewfinder.contains(frame, Rect2(Vector2(110, 90), Vector2(16, 16))))
	assert_false(Viewfinder.contains(frame, Rect2(Vector2(140, 90), Vector2(16, 16))))
	# The whale is bigger than the frame: a good overlap counts.
	assert_true(Viewfinder.contains(frame, Rect2(Vector2(60, 70), Vector2(128, 48))))


func test_light_lovers_appear_only_while_lights_are_on() -> void:
	for id in ["jellyfish", "anglerfish", "squid", "lantern_fish"]:
		var c = Creatures.make(id, Vector2(900, 280))
		_run(c, 2.0, false)
		assert_false(c.photographable(), "%s hides in the dark" % id)
		_run(c, 0.3, true)
		assert_true(c.photographable(), "%s appears with the lights" % id)
		_run(c, 0.5, false)
		assert_false(c.photographable(), "%s goes when the lights go" % id)


func test_hiders_come_out_after_sonar_or_nearby_flash() -> void:
	var crab = Creatures.make("crab", Vector2(536, 150))
	var octo = Creatures.make("octopus", Vector2(178, 296))
	var eel = Creatures.make("eel", Vector2(1140, 120))
	var all := [crab, octo, eel]
	for c in all:
		_run(c, 1.0, true)
		assert_false(c.photographable(), "%s stays hidden, even with the lights far away" % c.id)
	var out := Creatures.sonar(all, crab.home + Vector2(120, 0))
	assert_eq(out, ["crab"] as Array[String], "only the crab is in sonar range")
	out = Creatures.flash(all, octo.home + Vector2(40, 0))
	assert_eq(out, ["octopus"] as Array[String])
	Creatures.flash(all, eel.home + Vector2(200, 0))
	for c in all:
		_run(c, 0.3, false)
	assert_true(crab.photographable())
	assert_true(octo.photographable())
	assert_false(eel.photographable(), "a far flash leaves the eel in its hole")
	_run(crab, Creatures.OUT_SECONDS + 0.5, false)
	assert_false(crab.photographable(), "back under the rock after a while")


func test_easy_fish_stay_near_home() -> void:
	for id in ["clownfish", "blue_tang", "pufferfish", "turtle", "seahorse"]:
		var c = Creatures.make(id, Vector2(300, 100))
		for i in 30 * 60:
			Creatures.step(c, DT, false)
			assert_lt(c.pos.distance_to(c.home), c.roam + 12.0, "%s wandered off" % id)
		assert_true(c.photographable())


func test_lights_cooldown_colours_and_disco() -> void:
	var s := Lights.State.new()
	assert_true(Lights.press(s).flashed)
	assert_false(Lights.press(s).flashed, "cooldown")
	assert_true(s.lights_on())
	var colours: Array[int] = [s.color]
	var disco := false
	for i in 3:
		for k in 9:
			Lights.step(s, DT)
		var r := Lights.press(s)
		colours.append(r.color)
		disco = disco or r.disco
	assert_eq(colours, [0, 1, 2, 3] as Array[int], "warm white, pink, green, blue")
	assert_true(disco, "three quick presses")
	for i in int(Lights.ON_SECONDS / DT) + 2:
		Lights.step(s, DT)
	assert_false(s.lights_on())


func test_light_textures_are_banded_not_smooth() -> void:
	var radial := Lights.radial_image(40)
	var cone := Lights.cone_image(100, 30)
	assert_lte(Lights.distinct_levels(radial), 5, "4 bands + dark")
	assert_lte(Lights.distinct_levels(cone), 5)
	assert_gte(Lights.distinct_levels(radial), 4)


func test_run_rules() -> void:
	assert_eq(Rules.run_length(0.0), 360.0)
	assert_eq(Rules.run_length(75.0), 75.0)
	assert_false(Rules.should_end(100.0, 360.0, 11))
	assert_true(Rules.should_end(100.0, 360.0, 12))
	assert_true(Rules.should_end(360.0, 360.0, 0))
	var homes := {"clownfish": Vector2(10, 0), "turtle": Vector2(100, 0)}
	assert_eq(Rules.trail_target(Vector2.ZERO, homes, []), "clownfish")
	assert_eq(Rules.trail_target(Vector2.ZERO, homes, ["clownfish"]), "turtle")
	for n in 4:
		assert_ne(Rules.bonus_subject(n % 2 == 0, n == 3, n), "")
	assert_eq(Rules.bonus_subject(false, false, 0), "bubble")
	assert_eq(Rules.bonus_subject(true, false, 0), "rock_smile")


func test_reef_map_homes_in_water_and_route_clear() -> void:
	var reef := ReefMap.new()
	reef.load_file(ReefMap.PATH)
	assert_eq(reef.w, 80)
	for id in Species.PAGE:
		assert_true(reef.homes.has(id), "home of %s" % id)
		assert_false(reef.solid_at(reef.homes[id]), "%s lives in water" % id)
	var zones := {}
	for id in Species.PAGE:
		zones[ReefMap.zone_of(reef.homes[id])] = true
		if Species.kind(id) == Species.Kind.LIGHT:
			assert_eq(ReefMap.zone_of(reef.homes[id]), "trench", "%s lives in the dark" % id)
	assert_eq(zones.size(), 4, "creatures in all four zones")
	var pts: Array[Vector2] = [reef.sub_start]
	for r in reef.route:
		pts.append(Vector2(r[0], r[1]))
	pts.append(pts[1])
	for i in pts.size() - 1:
		for k in 21:
			var p := pts[i].lerp(pts[i + 1], k / 20.0)
			assert_false(reef.rect_hits(p, SubMotion.HIT), "route clear near %s" % p)
	assert_lt(ReefMap.ambient_at(Vector2(1000, 330)).v, 0.4, "the trench is dark")
	assert_gt(ReefMap.ambient_at(Vector2(200, 20)).v, 0.9, "the shallows are bright")
