extends RefCounted
## The cats, read from data/cats.json (see CLAUDE.md "Making it our real
## house and cats"). The sprite generator (tools/sprites.py) and the synth
## (tools/sfx.py) read the same file for looks and voices; the game reads the
## ids, collar colours and personalities.

## Sweetie 16, in index order (the art palette). cats.json colours are indices.
const PALETTE: Array[Color] = [
	Color("#1a1c2c"), Color("#5d275d"), Color("#b13e53"), Color("#ef7d57"),
	Color("#ffcd75"), Color("#a7f070"), Color("#38b764"), Color("#257179"),
	Color("#29366f"), Color("#3b5dc9"), Color("#41a6f6"), Color("#73eff7"),
	Color("#f4f4f4"), Color("#94b0c2"), Color("#566c86"), Color("#333c57"),
]

## [{"id", "collar": Color, "fur": Color, "shy", "chatty", "zoomies",
##   "likes": {tag: weight}, "favourite_spots": [kinds], "needs_coaxing": bool}]
var cats: Array = []
var errors: Array[String] = []


static func from_file(path: String) -> RefCounted:
	var c = load("res://scripts/house/cat_data.gd").new()
	if not FileAccess.file_exists(path):
		c.errors.append("missing %s" % path)
		return c
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		c.errors.append("%s is not a JSON object" % path)
		return c
	c.parse(d)
	return c


static func color(index) -> Color:
	return PALETTE[clampi(int(index), 0, 15)]


func parse(d: Dictionary) -> bool:
	for raw in d.get("cats", []):
		var id := str(raw.get("id", ""))
		if id == "" or ids().has(id):
			errors.append("cat with missing or duplicate id '%s'" % id)
			continue
		var look: Dictionary = raw.get("look", {})
		var p: Dictionary = raw.get("personality", {})
		var shy := float(p.get("shy", 0.5))
		var fav: Array[String] = []
		for k in raw.get("favourite_spots", []):
			fav.append(str(k))
		cats.append({
			"id": id,
			"collar": color(look.get("collar", 2)),
			"fur": color(look.get("fur", 13)),
			"shy": shy,
			"chatty": float(p.get("chatty", 0.5)),
			"zoomies": float(p.get("zoomies", 0.3)),
			"likes": p.get("likes", {}),
			"favourite_spots": fav,
			"needs_coaxing": shy >= 0.5,
		})
	if cats.is_empty():
		errors.append("no cats")
	return errors.is_empty()


func ids() -> Array[String]:
	var out: Array[String] = []
	for c in cats:
		out.append(c.id)
	return out


func get_cat(id: String) -> Dictionary:
	for c in cats:
		if c.id == id:
			return c
	return {}
