extends RefCounted
## Game discovery: every games/<slug>/ of the monorepo becomes one entry.
##
##   playable     games/<slug>/game/project.godot exists
##   coming soon  no game/project.godot, but a PLAN.md (shown greyed)
##   (skipped)    neither
##
## title  = the "# " heading of README.md, else of PLAN.md, else the slug
## pitch  = one short sentence from the first paragraph under that heading
## cover  = games/<slug>/cover.png ("" when missing: the card draws a placeholder)
##
## Pure file reading, no nodes: the tests run it against a fixture tree.

const PITCH_MAX := 150


## Repo root from the launcher's own location (<root>/launcher/game/).
static func default_root() -> String:
	return (ProjectSettings.globalize_path("res://") + "../..").simplify_path()


static func discover(root: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var games_dir := root.path_join("games")
	var dir := DirAccess.open(games_dir)
	if dir == null:
		return out
	var slugs := Array(dir.get_directories())
	slugs.sort()
	for slug: String in slugs:
		if slug.begins_with("."):
			continue
		var e := read_game(games_dir.path_join(slug), slug)
		if not e.is_empty():
			out.append(e)
	return out


static func read_game(path: String, slug: String) -> Dictionary:
	var playable := FileAccess.file_exists(path.path_join("game/project.godot"))
	var readme := path.path_join("README.md")
	var plan := path.path_join("PLAN.md")
	if not playable and not FileAccess.file_exists(plan):
		return {}
	var title := ""
	var pitch := ""
	for doc in [readme, plan]:
		if title == "" and FileAccess.file_exists(doc):
			var parsed := parse_doc(FileAccess.get_file_as_string(doc))
			title = parsed.title
			pitch = parsed.pitch
	if title == "":
		title = slug.replace("-", " ").capitalize()
	var cover := path.path_join("cover.png")
	return {
		"slug": slug,
		"title": title,
		"pitch": pitch,
		"playable": playable,
		"dir": path,
		"game_dir": path.path_join("game"),
		"cover": cover if FileAccess.file_exists(cover) else "",
	}


## {"title", "pitch"} from a markdown document: the first "# " heading and a
## short sentence from the paragraph right under it.
static func parse_doc(text: String) -> Dictionary:
	var title := ""
	var para: PackedStringArray = []
	var in_para := false
	for raw in text.split("\n"):
		var line := raw.strip_edges()
		if title == "":
			if line.begins_with("# "):
				title = line.substr(2).strip_edges()
			continue
		if line == "":
			if in_para:
				break
			continue
		if line.begins_with("#") or line.begins_with("|") or line.begins_with(">") or line.begins_with("```"):
			if in_para:
				break
			continue
		in_para = true
		para.append(line)
	return {"title": title, "pitch": pick_pitch(" ".join(para))}


## The first sentence that says what the game IS (skipping the generic "a couch
## co-op game for a parent and small kids"), cut at a colon when it is long.
static func pick_pitch(paragraph: String) -> String:
	var text := paragraph.replace("**", "").replace("`", "").strip_edges()
	if text == "":
		return ""
	var sentences: Array[String] = []
	var re := RegEx.create_from_string("[^.!?]+[.!?:]?")
	for m in re.search_all(text):
		var s := m.get_string().strip_edges()
		if s != "":
			sentences.append(s)
	var chosen := ""
	for s in sentences:
		var low := s.to_lower()
		var generic := low.contains("couch co-op") and (low.contains(" for a ") or low.contains(" game for"))
		if not generic:
			chosen = s
			break
	if chosen == "":
		chosen = sentences[0] if not sentences.is_empty() else text
	if chosen.length() > PITCH_MAX:
		for sep in [": ", "; ", ", then", " — "]:
			var at := chosen.find(sep)
			if at > 20:
				chosen = chosen.substr(0, at)
				break
	if chosen.length() > PITCH_MAX:
		chosen = chosen.substr(0, chosen.rfind(" ", PITCH_MAX - 1)) + "…"
	chosen = chosen.strip_edges()
	if chosen.ends_with(":") or chosen.ends_with(";") or chosen.ends_with(","):
		chosen = chosen.substr(0, chosen.length() - 1)
	if not (chosen.ends_with(".") or chosen.ends_with("!") or chosen.ends_with("?") or chosen.ends_with("…")):
		chosen += "."
	return chosen


## Card order: the most recently played first (in recency order), then the
## other playable games by title, then the coming-soon plans.
static func order(games: Array[Dictionary], recent: Array) -> Array[Dictionary]:
	var played: Array[Dictionary] = []
	var rest: Array[Dictionary] = []
	var soon: Array[Dictionary] = []
	for g in games:
		if not g.playable:
			soon.append(g)
		elif recent.has(g.slug):
			played.append(g)
		else:
			rest.append(g)
	played.sort_custom(func(a, b): return recent.find(a.slug) < recent.find(b.slug))
	var by_title := func(a, b): return String(a.title).naturalnocasecmp_to(b.title) < 0
	rest.sort_custom(by_title)
	soon.sort_custom(by_title)
	return played + rest + soon
