extends GutTest
## The trail's gates and animals, the show course, the rosettes, the wall, the coats.

const TrailCourse := preload("res://scripts/logic/trail_course.gd")
const ShowCourse := preload("res://scripts/logic/show_course.gd")
const RosetteWall := preload("res://scripts/logic/rosette_wall.gd")
const DT := 1.0 / 30.0

## Endesga 32 (art_src/palettes/endesga32.hex).
const PALETTE := ["be4a2f", "d77643", "ead4aa", "e4a672", "b86f50", "733e39", "3e2731", "a22633",
	"e43b44", "f77622", "feae34", "fee761", "63c74d", "3e8948", "265c42", "193c3e", "124e89", "0099db",
	"2ce8f5", "ffffff", "c0cbdc", "8b9bb4", "5a6988", "3a4466", "262b44", "181425", "ff0044", "68386c",
	"b55088", "f6757a", "e8b796", "c28569"]


func test_neigh_opens_gate_and_gate_autoopens() -> void:
	var c := TrailCourse.new(0.5)
	var g: Dictionary = c.gates[0]
	var gx: float = g.x
	# Far away a neigh does nothing to the gate.
	assert_false(c.neigh(gx - 400.0).gate)
	assert_eq(int(g.state), 0)
	# The mare stops before a closed gate.
	assert_almost_eq(c.stop_x_for(gx - 100.0), gx - TrailCourse.GATE_STOP, 0.01)
	# Close by, a neigh opens it at once.
	assert_true(c.neigh(gx - 60.0).gate)
	c.update(gx - 60.0, DT, true)
	c.update(gx - 60.0, 0.6, true)
	assert_eq(int(g.state), 2)
	assert_eq(c.gate_frame(g), 2)
	assert_eq(c.stop_x_for(gx - 60.0), c.stop_x_for(gx + 10.0), "no stop at an open gate")
	# The next gate: nobody neighs, and after 5 s waiting it opens by itself.
	var g2: Dictionary = c.gates[1]
	var at: float = float(g2.x) - TrailCourse.GATE_STOP
	var t := 0.0
	while int(g2.state) == 0 and t < 10.0:
		c.update(at, DT, true)
		t += DT
	assert_almost_eq(t, TrailCourse.GATE_AUTO, 0.1)
	# With no toddler it opens as she arrives (about 1 s).
	var g3: Dictionary = c.gates[2]
	var t3 := 0.0
	while int(g3.state) == 0 and t3 < 10.0:
		c.update(float(g3.x) - TrailCourse.GATE_STOP, DT, false)
		t3 += DT
	assert_lt(t3, 1.2)


func test_neigh_wakes_nearest_animal() -> void:
	var c := TrailCourse.new(0.5)
	var a0: Dictionary = c.animals[0]
	var x: float = float(a0.x) + 5.0
	var want := c.nearest_animal(x)
	assert_eq(want, 0)
	var out := c.neigh(x)
	assert_eq(out.animal, 0)
	assert_gte(float(a0.react), 0.0, "it reacts")
	for an in c.animals.slice(1):
		assert_lt(float(an.react), 0.0, "only the nearest one reacts")
	for i in 60:
		c.update(x, DT, true)
	assert_lt(float(a0.react), 0.0, "and settles again")
	# Too far from every animal: nobody answers, and nothing breaks.
	var empty := TrailCourse.new(0.5)
	empty.animals.clear()
	assert_eq(empty.neigh(500.0).animal, -1)
	# The herd: a neigh while it gallops answers it and brings the rainbow.
	var h := TrailCourse.new(0.5)
	h.update(h.herd_x + 1.0, DT, true)
	assert_true(h.herd_running())
	assert_true(h.neigh(h.herd_x + 1.0).herd)
	assert_gte(h.rainbow_t, 0.0)


func test_show_course_always_finishes() -> void:
	for scenario in ["nobody", "perfect", "mash"]:
		var sc := ShowCourse.new(scenario != "nobody", scenario == "nobody")
		var t := 0.0
		var refused := 0
		while not sc.done() and t < 240.0:
			var input := {}
			match scenario:
				"perfect":
					if sc.phase == ShowCourse.Phase.MARE and sc.jump_i < 6:
						var tt := (ShowCourse.MARE_JUMPS[sc.jump_i] - ShowCourse.TAKEOFF - sc.s) / ShowCourse.MARE_SPEED
						input.jump = tt < 0.1 and tt > 0.0
					input.bell = true
					input.dir = Vector2i.UP
				"mash":
					input = {"bell": true, "jump": true, "hop": true, "dir": Vector2i.LEFT}
			for e in sc.step(DT, input):
				if e == "refuse":
					refused += 1
			if sc.phase == ShowCourse.Phase.ROSETTES and sc.rosettes.is_empty():
				sc.award({}, [0, 1, 2])
			t += DT
		assert_true(sc.done(), "%s: the show finishes" % scenario)
		assert_lt(t, 150.0, "%s: in reasonable time" % scenario)
		assert_eq(sc.jump_i, 6, "%s: all six jumps" % scenario)
		if scenario == "nobody":
			assert_eq(refused, 6, "one refusal per jump, then she clears it")
			assert_eq(sc.clean_count(), 0)
		if scenario == "perfect":
			assert_eq(sc.clean_count(), 6)
			assert_eq(refused, 0)


func test_everyone_gets_a_rosette() -> void:
	for seated in [[0], [0, 1], [0, 2], [0, 1, 2]]:
		var sc := ShowCourse.new()
		sc.award({"apples": 0, "flowers": 0, "carrots": 0, "clean_jumps": 0}, seated)
		var who := []
		for r in sc.rosettes:
			who.append(r.who)
			assert_true(["blue", "red", "yellow", "green", "purple"].has(r.colour))
		assert_true(who.has("mare") and who.has("foal"))
		for s in seated:
			assert_true(who.has("rider%d" % s), "rider %d gets one too" % s)
		assert_eq(sc.rosettes.size(), 2 + seated.size())
	# A great day and a quiet day both get rosettes (the colour differs).
	var a := ShowCourse.new()
	a.award({"apples": 30, "flowers": 20, "carrots": 9, "clean_jumps": 9}, [0])
	var b := ShowCourse.new()
	b.award({}, [0])
	assert_eq(a.rosettes.size(), b.rosettes.size())
	assert_ne(a.rosettes[1].colour, b.rosettes[1].colour)


func test_rosette_wall_persists_and_demo_uses_own_file() -> void:
	var path := "user://test_rosette_wall_persist.json"
	var w := RosetteWall.new(path)
	w.reset()
	w.add_day(["blue", "red"], 1)
	w.add_day(["green"], 2)
	assert_true(w.save())
	var w2 := RosetteWall.new(path)
	w2.load_file()
	assert_eq(w2.day_count(), 2)
	assert_eq(w2.days()[0], ["blue", "red"])
	assert_eq(w2.horseshoes(), 3)
	for i in 20:
		w2.add_day(["yellow"])
	assert_eq(w2.day_count(), RosetteWall.MAX_DAYS, "the oldest days fall off")
	# A corrupt file is set aside, never a crash.
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("{not json")
	f.close()
	var w3 := RosetteWall.new(path)
	w3.load_file()
	assert_eq(w3.day_count(), 0)
	w3.reset()
	# The game under test never points at the family wall; the demo has its own file.
	assert_ne(Game.wall.path, Game.WALL_PATH)
	assert_eq(Game.wall.path, Game.TEST_WALL_PATH)
	assert_ne(Game.DEMO_WALL_PATH, Game.WALL_PATH)
	var src := FileAccess.get_file_as_string("res://autoload/game_state.gd")
	assert_true(src.contains("path = DEMO_WALL_PATH"), "demo mode switches to the demo wall")


func test_coat_recolour_stays_in_palette() -> void:
	var pal := {}
	for h in PALETTE:
		pal[h] = true
	var names: Array[String] = []
	for c in Game.MARE_COATS:
		names.append("mare_" + c)
		names.append("mare_big_" + c)
	for c in Game.FOAL_COATS:
		names.append("foal_" + c)
		names.append("coat_" + c)
	assert_eq(names.size(), 26, "6 mare coats (x2) and 7 foal coats (x2)")
	var firsts := {}
	for n in names:
		var path := "res://art/%s.png" % n
		assert_true(FileAccess.file_exists(path), n + " exists")
		var img := Image.new()
		assert_eq(img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)), OK)
		img.convert(Image.FORMAT_RGBA8)
		var bad := 0
		var body := {}
		for y in img.get_height():
			for x in img.get_width():
				var c := img.get_pixel(x, y)
				if c.a8 == 0:
					continue
				if c.a8 != 255 or not pal.has(c.to_html(false)):
					bad += 1
				body[c.to_html(false)] = int(body.get(c.to_html(false), 0)) + 1
		assert_eq(bad, 0, n + " stays in the Endesga 32 palette")
		if n.begins_with("mare_") and not n.begins_with("mare_big"):
			# The most common colour of each coat (its body) differs between coats.
			var top := ""
			for k in body:
				if k == "181425":
					continue  # the ink outline
				if top == "" or body[k] > body[top]:
					top = k
			firsts[n] = top
	var bodies := {}
	for n in firsts:
		bodies[firsts[n]] = true
	assert_gte(bodies.size(), 5, "the coats are distinct: %s" % str(firsts))
