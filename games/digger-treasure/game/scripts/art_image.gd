extends RefCounted
## Raw Image access to a sprite strip (the terrain stamps dirt textures into
## its own Image; helmets look for the top of a rider's head). Same rule as
## the shared art.gd: from source read the PNG bytes, never the import cache;
## an exported build goes through the ResourceLoader.
## Local helper: shared/godot/autoload/art.gd has no Image accessor (see CLAUDE.md).

static var _cache := {}


static func load_image(sprite_name: String) -> Image:
	if _cache.has(sprite_name):
		return _cache[sprite_name]
	var img: Image = null
	var dir := "res://art"
	var tree := Engine.get_main_loop() as SceneTree
	var art: Node = tree.root.get_node_or_null("Art") if tree else null
	if art and art.manifest.has(sprite_name):
		dir = art.manifest[sprite_name].dir
	var path := "%s/%s.png" % [dir, sprite_name]
	if OS.has_feature("template"):
		if ResourceLoader.exists(path):
			var t: Texture2D = load(path)
			img = t.get_image() if t else null
	elif FileAccess.file_exists(path):
		img = Image.new()
		if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
			img = null
	if img and img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	_cache[sprite_name] = img
	return img


## First opaque row of frame `frame` and the middle column of that row's
## opaque run (frame-local pixels), or (-1, -1) when unknown.
static func head_top(sprite_name: String, frame_w: int, frame := 0) -> Vector2i:
	var img := load_image(sprite_name)
	if img == null:
		return Vector2i(-1, -1)
	var x0 := frame * frame_w
	for y in img.get_height():
		var first := -1
		var last := -1
		for x in frame_w:
			if img.get_pixel(x0 + x, y).a > 0.5:
				if first == -1:
					first = x
				last = x
		if first != -1:
			return Vector2i((first + last) / 2, y)
	return Vector2i(-1, -1)
