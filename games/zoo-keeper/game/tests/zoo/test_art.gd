extends GutTest
## The vector art: every animal builds with its parts, every pose runs, the
## gallery builds every page, and nothing is text.

const Animals := preload("res://scripts/vector/animals.gd")
const Props := preload("res://scripts/vector/props.gd")
const Rules := preload("res://scripts/zoo/rules.gd")
const Gallery := preload("res://scripts/screens/gallery.gd")


func test_every_animal_has_its_parts() -> void:
	for kind in Rules.ANIMALS:
		var a := Animals.build(kind)
		add_child_autofree(a)
		var parts: Dictionary = a.get_meta("parts")
		for p in ["pivot", "head", "mouth_open", "mouth_closed", "tongue", "cheeks"]:
			assert_true(parts.has(p), "%s has %s" % [kind, p])
		assert_eq(a.get_meta("eyes").size(), 2, "%s has two eyes" % kind)


func test_every_pose_changes_something_and_resets() -> void:
	for kind in Rules.ANIMALS:
		var a := Animals.build(kind)
		add_child_autofree(a)
		var head: Node2D = a.get_meta("parts")["head"]
		Animals.pose(a, "idle", 0.0)
		var rest_rot := head.rotation
		for pz in Animals.POSES:
			for f in [0, 1, 2]:
				Animals.pose(a, pz, 0.37, f)
		Animals.pose(a, "shake", 0.08)
		assert_ne(head.rotation, rest_rot, "%s shakes its head" % kind)
		Animals.pose(a, "munch", 0.0, 0)
		assert_true(a.get_meta("parts")["mouth_open"].visible, "%s munch frame 0 opens" % kind)
		Animals.pose(a, "munch", 0.0, 1)
		assert_true(a.get_meta("parts")["cheeks"].visible, "%s munch frame 1 puffs" % kind)
		Animals.pose(a, "idle", 0.0)
		assert_almost_eq(head.rotation, rest_rot, 0.001, "%s resets" % kind)
		assert_false(a.get_meta("parts")["tongue"].visible)


func test_foods_are_distinct_colours() -> void:
	var seen := {}
	for f in Rules.FOODS:
		var c: Color = Props.FOOD_COLOR[f]
		assert_false(seen.has(c.to_html()), "%s has its own colour" % f)
		seen[c.to_html()] = true
		var n := Props.food(f)
		add_child_autofree(n)
		assert_gt(n.get_child_count(), 1)


func test_gallery_builds_every_page_without_text() -> void:
	var g: Node2D = Gallery.new()
	add_child_autofree(g)
	g.set_process(false)
	for p in Gallery.PAGES:
		g.show_page(p)
		var stack: Array[Node] = [g]
		var polys := 0
		while not stack.is_empty():
			var n: Node = stack.pop_back()
			assert_false(n is Label or n is RichTextLabel)
			if n is Polygon2D:
				polys += 1
			for c in n.get_children():
				stack.append(c)
		assert_gt(polys, 50, "page %d draws things" % p)


func test_hat_can_be_recoloured() -> void:
	var a := Animals.build("penguin")
	add_child_autofree(a)
	Animals.add_hat(a, Color.RED)
	Animals.set_hat_color(a, Color.BLUE)
	var hat := a.find_child("hat", true, false)
	assert_eq((hat.get_node("crown") as Polygon2D).color, Color.BLUE)
