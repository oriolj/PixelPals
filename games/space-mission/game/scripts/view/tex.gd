extends RefCounted
## Whole textures and images from the art folder, read from source bytes like
## the shared Art autoload (no import cache needed; an exported build loads the
## imported texture). For shader inputs and pixel sampling, where Art's
## SpriteFrames of AtlasTextures do not fit.

static var _images := {}


## The PNG strip `name` as an Image, or a solid `fallback` image when missing.
static func image(name: String, fallback := Vector2i(16, 16), tint := Color.MAGENTA) -> Image:
	if _images.has(name):
		return _images[name]
	var img: Image = null
	if Art.manifest.has(name):
		var path := "%s/%s.png" % [Art.manifest[name].dir, name]
		if OS.has_feature("template"):
			var t = load(path) if ResourceLoader.exists(path) else null
			if t is Texture2D:
				img = t.get_image()
		elif FileAccess.file_exists(path):
			img = Image.new()
			if img.load_png_from_buffer(FileAccess.get_file_as_bytes(path)) != OK:
				img = null
	if img == null:
		img = Image.create(fallback.x, fallback.y, false, Image.FORMAT_RGBA8)
		img.fill(tint)
	else:
		img.convert(Image.FORMAT_RGBA8)
	_images[name] = img
	return img


static func texture(name: String, fallback := Vector2i(16, 16), tint := Color.MAGENTA) -> ImageTexture:
	return ImageTexture.create_from_image(image(name, fallback, tint))


## One frame of a sprite as a texture (AtlasTexture from Art, placeholder-safe).
static func frame(name: String, i := 0, tint := Color.MAGENTA, fallback := Vector2i(16, 16)) -> Texture2D:
	var sf: SpriteFrames = Art.frames(name, tint, fallback)
	var n := sf.get_frame_count("default")
	return sf.get_frame_texture("default", posmod(i, n))


static func frame_count(name: String) -> int:
	return int(Art.manifest[name].get("frames", 1)) if Art.manifest.has(name) else 1
