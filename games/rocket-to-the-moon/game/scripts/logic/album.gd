extends RefCounted
## The planet album kept across trips: a JSON list of planet kinds (1..8).

const KINDS := 8


static func load_kinds(path: String) -> Array[int]:
	var out: Array[int] = []
	if not FileAccess.file_exists(path):
		return out
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	if data is Dictionary:
		data = data.get("planets", [])
	if data is Array:
		for v in data:
			var k := int(v)
			if k >= 1 and k <= KINDS and not out.has(k):
				out.append(k)
	out.sort()
	return out


static func save_kinds(path: String, kinds: Array[int]) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"planets": kinds}) + "\n")
	f.close()
	return true
