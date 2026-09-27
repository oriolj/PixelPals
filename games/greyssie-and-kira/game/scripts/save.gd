extends RefCounted
## Versioned JSON files in user:// that survive corrupt or foreign content.
##
## A local copy of the helper proposed for shared/godot/save.gd (see the
## game's CLAUDE.md): { "version": N, "data": {...} } written atomically
## (to <path>.tmp, then renamed). Reading never throws: a missing file, bad
## JSON, a non-object, or a newer version returns the default, and a corrupt
## file is kept aside as <path>.bad for inspection.


static func load_json(path: String, version: int, default: Dictionary) -> Dictionary:
	if not FileAccess.file_exists(path):
		return default.duplicate(true)
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var parsed = json.data if text != "" and json.parse(text) == OK else null
	if not (parsed is Dictionary) or not parsed.has("data") or not (parsed["data"] is Dictionary):
		_set_aside(path)
		return default.duplicate(true)
	var v := int(parsed.get("version", 0))
	if v > version:
		return default.duplicate(true)  # written by a newer game: leave it alone
	return parsed["data"]


static func save_json(path: String, version: int, data: Dictionary) -> bool:
	var tmp := path + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": version, "data": data}, "\t"))
	f.close()
	var dir := DirAccess.open(path.get_base_dir())
	if dir == null:
		return false
	if FileAccess.file_exists(path):
		dir.remove(path.get_file())
	return dir.rename(tmp.get_file(), path.get_file()) == OK


static func remove(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir:
		for p in [path, path + ".tmp", path + ".bad"]:
			if FileAccess.file_exists(p):
				dir.remove(p.get_file())


static func _set_aside(path: String) -> void:
	var dir := DirAccess.open(path.get_base_dir())
	if dir:
		if FileAccess.file_exists(path + ".bad"):
			dir.remove((path + ".bad").get_file())
		dir.rename(path.get_file(), (path + ".bad").get_file())
