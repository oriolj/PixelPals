extends Node
## Sprite lookup with placeholder fallback, so gameplay never waits for art.
##
## Art lives in res://art/<name>.png as a horizontal strip of frames; the frame
## size is in res://art/manifest.json ({"<name>": {"w": 16, "h": 16, "frames": 2, "fps": 4}}).
## Private-pack art (res://private_pack/art/) overrides and extends it when present.

const DIRS := ["res://art", "res://private_pack/art"]

var manifest := {}
var _cache := {}


func _ready() -> void:
	for dir in DIRS:
		var path: String = dir + "/manifest.json"
		if FileAccess.file_exists(path):
			var data = JSON.parse_string(FileAccess.get_file_as_string(path))
			if data is Dictionary:
				for k in data:
					var entry: Dictionary = data[k]
					entry["dir"] = dir
					manifest[k] = entry


func has(sprite_name: String) -> bool:
	return manifest.has(sprite_name)


func size_of(sprite_name: String, fallback := Vector2i(16, 16)) -> Vector2i:
	if manifest.has(sprite_name):
		return Vector2i(int(manifest[sprite_name].w), int(manifest[sprite_name].h))
	return fallback


func _load_image_texture(path: String) -> Texture2D:
	# Imported resources exist when the editor has scanned the project;
	# fall back to loading the raw PNG so a fresh checkout still runs.
	if ResourceLoader.exists(path):
		return load(path)
	var abs := ProjectSettings.globalize_path(path)
	if FileAccess.file_exists(path) or FileAccess.file_exists(abs):
		var img := Image.load_from_file(abs)
		if img:
			return ImageTexture.create_from_image(img)
	return null


## SpriteFrames with a "default" animation. Placeholder: a solid rect of `tint`.
func frames(sprite_name: String, tint := Color.MAGENTA, fallback_size := Vector2i(16, 16)) -> SpriteFrames:
	var key := "%s|%s|%s" % [sprite_name, tint.to_html(), fallback_size]
	if _cache.has(key):
		return _cache[key]
	var sf := SpriteFrames.new()
	sf.set_animation_loop("default", true)
	var tex: Texture2D = null
	if manifest.has(sprite_name):
		var m: Dictionary = manifest[sprite_name]
		tex = _load_image_texture("%s/%s.png" % [m.dir, sprite_name])
		if tex:
			var w := int(m.w)
			var h := int(m.h)
			var n := int(m.get("frames", 1))
			sf.set_animation_speed("default", float(m.get("fps", 6)))
			for i in n:
				var at := AtlasTexture.new()
				at.atlas = tex
				at.region = Rect2(i * w, 0, w, h)
				sf.add_frame("default", at)
	if tex == null:
		var img := Image.create(fallback_size.x, fallback_size.y, false, Image.FORMAT_RGBA8)
		img.fill(tint)
		sf.add_frame("default", ImageTexture.create_from_image(img))
	_cache[key] = sf
	return sf


## Convenience: an AnimatedSprite2D already playing.
func sprite(sprite_name: String, tint := Color.MAGENTA, fallback_size := Vector2i(16, 16)) -> AnimatedSprite2D:
	var s := AnimatedSprite2D.new()
	s.sprite_frames = frames(sprite_name, tint, fallback_size)
	s.play("default")
	return s
