extends RefCounted
## Photo capture for the Camera seat: the current view -> a small thumbnail kept
## in memory (Game.photos) for the party screen. Nothing is written to disk.
## Headless runs render nothing, so tests pass a fake image instead.

const THUMB := Vector2i(64, 36)
const MAX_PHOTOS := 30


## The viewport's current image, or null when there is none (headless).
static func grab(vp: Viewport) -> Image:
	if vp == null or DisplayServer.get_name() == "headless":
		return null  # the dummy renderer has no pixels to read
	var tex := vp.get_texture()
	if tex == null:
		return null
	var img := tex.get_image()
	if img == null or img.is_empty():
		return null
	return img


## A nearest-scaled 64x36 copy of `img`, or null for an empty one.
static func thumbnail(img: Image) -> Image:
	if img == null or img.is_empty():
		return null
	var t := img.duplicate() as Image
	if t.is_compressed():
		return null
	t.convert(Image.FORMAT_RGBA8)
	t.resize(THUMB.x, THUMB.y, Image.INTERPOLATE_NEAREST)
	return t


## Stores a photo from `img` into `album` (an Array of {tex, golden}). Returns
## the new entry, or an empty Dictionary when there was nothing to capture.
static func store(album: Array, img: Image, golden: bool) -> Dictionary:
	var thumb := thumbnail(img)
	if thumb == null:
		return {}
	var entry := {"tex": ImageTexture.create_from_image(thumb), "golden": golden}
	album.append(entry)
	# Keep the album small: drop the oldest ordinary photo first.
	while album.size() > MAX_PHOTOS:
		var drop := 0
		for i in album.size():
			if not album[i].golden:
				drop = i
				break
		album.remove_at(drop)
	return entry
