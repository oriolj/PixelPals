extends RefCounted
## The family album: which species have been photographed, the best photo of
## each, and the bonus subjects. Persisted with scripts/save.gd. It holds no
## personal data (no names, no dates).
##
## data = {
##   "species": {"<id>": {"count": n, "best": 0..1, "frame": k}},
##   "bonus":   {"bubble": n, "shell": n, "rock_smile": n, "starfish": n},
## }

const Save := preload("res://scripts/save.gd")
const VERSION := 1

var path := ""
var data := {}


func _init(file_path := "") -> void:
	path = file_path
	data = empty()


static func empty() -> Dictionary:
	return {"species": {}, "bonus": {}}


func load_file() -> void:
	data = Save.load_json(path, VERSION, empty()) if path != "" else empty()
	if not (data.get("species") is Dictionary):
		data["species"] = {}
	if not (data.get("bonus") is Dictionary):
		data["bonus"] = {}


func save() -> bool:
	return Save.save_json(path, VERSION, data) if path != "" else false


func has(id: String) -> bool:
	return data.species.has(id)


func count(id: String) -> int:
	return int(data.species.get(id, {}).get("count", 0))


func found_count(ids: Array) -> int:
	var n := 0
	for id in ids:
		if has(id):
			n += 1
	return n


## Records a photo. Returns true when the species is new to the album.
func record(id: String, score := 1.0, frame := 0) -> bool:
	var is_new := not has(id)
	var e: Dictionary = data.species.get(id, {"count": 0, "best": 0.0, "frame": 0})
	e["count"] = int(e.get("count", 0)) + 1
	if score >= float(e.get("best", 0.0)):
		e["best"] = snappedf(score, 0.01)
		e["frame"] = frame
	data.species[id] = e
	return is_new


func add_bonus(kind: String) -> void:
	data.bonus[kind] = int(data.bonus.get(kind, 0)) + 1


func bonus(kind: String) -> int:
	return int(data.bonus.get(kind, 0))


## Parent reset: empties the album and its file.
func reset() -> void:
	data = empty()
	if path != "":
		Save.remove(path)
