extends RefCounted
## Single frames, named animation ranges (art/anims.json) and anchor points
## (art/points.json), all read from source bytes like the shared Art autoload.
## Placeholder-safe: a missing sprite is a solid rect, a missing range is
## frame 0, a missing point is the fallback.

static var _anims: Dictionary = {}
static var _points: Dictionary = {}
static var _loaded := false


static func _load() -> void:
	if _loaded:
		return
	_loaded = true
	for pair in [["res://art/anims.json", "a"], ["res://art/points.json", "p"]]:
		if FileAccess.file_exists(pair[0]):
			var d = JSON.parse_string(FileAccess.get_file_as_string(pair[0]))
			if d is Dictionary:
				if pair[1] == "a":
					_anims = d
				else:
					_points = d


## One frame of a sprite as a texture (an AtlasTexture from Art).
static func frame(name: String, i := 0, tint := Color.MAGENTA, fallback := Vector2i(16, 16)) -> Texture2D:
	var sf: SpriteFrames = Art.frames(name, tint, fallback)
	var n := sf.get_frame_count("default")
	return sf.get_frame_texture("default", posmod(i, n))


static func frame_count(name: String) -> int:
	return int(Art.manifest[name].get("frames", 1)) if Art.manifest.has(name) else 1


## [first, count, fps] of animation `anim` of sprite family `family`.
static func anim(family: String, anim_name: String) -> Array:
	_load()
	var fam = _anims.get(family, {})
	if fam is Dictionary and fam.has(anim_name):
		var r: Array = fam[anim_name]
		return [int(r[0]), maxi(1, int(r[1])), float(r[2]) if r.size() > 2 else 6.0]
	return [0, 1, 0.0]


static func has_anim(family: String, anim_name: String) -> bool:
	_load()
	return _anims.get(family, {}).has(anim_name)


## An anchor point: points.json[family][key], optionally the per-frame entry.
static func point(family: String, key: String, frame_i := -1, fallback := Vector2.ZERO) -> Vector2:
	_load()
	var fam = _points.get(family, {})
	if not (fam is Dictionary) or not fam.has(key):
		return fallback
	var v = fam[key]
	if v is Array and v.size() > 0 and v[0] is Array:
		if frame_i < 0:
			frame_i = 0
		v = v[clampi(frame_i, 0, v.size() - 1)]
	if v is Array and v.size() >= 2:
		return Vector2(float(v[0]), float(v[1]))
	return fallback


## A named sub-point table (e.g. mare_big.patches) as {key: Vector2}.
static func point_table(family: String, key: String) -> Dictionary:
	_load()
	var out := {}
	var fam = _points.get(family, {})
	if fam is Dictionary and fam.get(key) is Dictionary:
		for k in fam[key]:
			var v = fam[key][k]
			out[k] = Vector2(float(v[0]), float(v[1]))
	return out


static func point_list(family: String, key: String) -> Array[Vector2]:
	_load()
	var out: Array[Vector2] = []
	var fam = _points.get(family, {})
	if fam is Dictionary and fam.get(key) is Array:
		for v in fam[key]:
			out.append(Vector2(float(v[0]), float(v[1])))
	return out
