extends Node
## The painting: a 1920x1080 SubViewport that never clears, so every dab,
## stamp and splat drawn into it accumulates (the standard Godot 4 way to
## paint on the GPU). Draw calls are queued as ops; once per frame the Ink
## node emits them and the viewport renders ONCE, then sits idle until the
## next op. That keeps soft dabs from being re-blended every frame.
##
## Readback (snapshot/save_png) needs a real renderer; headless (dummy
## renderer) it returns null and saving is a no-op, which is why the pixel
## tests live in tests_render/ and run under xvfb.

const Shapes := preload("res://scripts/paint/shapes.gd")
const Palette := preload("res://scripts/paint/palette.gd")

const SIZE := Vector2i(1920, 1080)

var viewport: SubViewport
var ink: Ink
var ops: Array = []
## Frames in which the viewport actually rendered new ops (tests).
var renders := 0
var _dab_tex: ImageTexture
## The very first render can be dropped while the scene is still being built
## (seen when the game boots straight into this screen), so until something
## else is drawn the paper is laid again for the first few frames.
var _paper_frames := 4
var _drawn := false


func _init() -> void:
	# After the screens (default 0), so ops queued this frame render this frame.
	process_priority = 100


func _ready() -> void:
	viewport = SubViewport.new()
	viewport.size = SIZE
	viewport.disable_3d = true
	viewport.transparent_bg = true
	viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_NEVER
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(viewport)
	ink = Ink.new()
	ink.painter = self
	ink.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	viewport.add_child(ink)
	var img := Shapes.dab_image()
	img.generate_mipmaps()
	_dab_tex = ImageTexture.create_from_image(img)
	clear_paper()
	flush()


func _process(_delta: float) -> void:
	if _paper_frames > 0:
		_paper_frames -= 1
		if not _drawn:
			ops.push_front({"t": "paper"})
	flush()


## Emits the queued ops into the viewport and renders it once.
func flush() -> void:
	if ops.is_empty() or viewport == null:
		return
	for op in ops:
		if op.t != "paper":
			_drawn = true
	ink.batch = ops
	ops = []
	ink.queue_redraw()
	viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	renders += 1


func texture() -> Texture2D:
	return viewport.get_texture()


static func can_read_back() -> bool:
	return DisplayServer.get_name() != "headless"


# ---------------------------------------------------------------- drawing

func clear_paper() -> void:
	ops.append({"t": "paper"})


func add_dab(pos: Vector2, radius: float, col: Color) -> void:
	ops.append({"t": "dab", "pos": pos, "r": radius, "col": col})


func add_parts(parts: Array) -> void:
	ops.append({"t": "parts", "parts": parts})


func add_stamp(kind: String, pos: Vector2, col: Color, size := Shapes.STAMP_SIZE) -> void:
	add_parts(Shapes.stamp(kind, pos, size, col))


## Draws a full-size snapshot back (undo).
func restore(img: Image) -> void:
	if img == null:
		return
	ops.append({"t": "image", "tex": ImageTexture.create_from_image(img)})


# ---------------------------------------------------------------- readback

## The canvas as it was last rendered (null without a real renderer).
func snapshot() -> Image:
	if not can_read_back() or viewport == null:
		return null
	var img := viewport.get_texture().get_image()
	if img == null or img.is_empty():
		return null
	if img.get_format() != Image.FORMAT_RGB8:
		img.convert(Image.FORMAT_RGB8)
	return img


## Saves the canvas as a PNG (creating the folder). Returns the image saved,
## or null when there is nothing to read back.
func save_png(path: String) -> Image:
	var img := snapshot()
	if img == null:
		return null
	var dir := path.get_base_dir()
	if dir.begins_with("user://") or dir.begins_with("res://"):
		dir = ProjectSettings.globalize_path(dir)
	DirAccess.make_dir_recursive_absolute(dir)
	if img.save_png(path) != OK:
		push_warning("could not save %s" % path)
		return null
	return img


## Draws one frame's worth of ops. Its draw commands stay attached until the
## next batch, but the viewport only renders when a batch arrives.
class Ink extends Node2D:
	var painter
	var batch: Array = []

	func _draw() -> void:
		for op in batch:
			match op.t:
				"paper":
					draw_rect(Rect2(Vector2.ZERO, Vector2(SIZE)), Palette.PAPER)
				"dab":
					var r: float = op.r
					draw_texture_rect(painter._dab_tex, Rect2(op.pos - Vector2(r, r), Vector2(r, r) * 2.0), false, op.col)
				"parts":
					for p in op.parts:
						if p.has("pts"):
							draw_colored_polygon(p.pts, p.col)
							var loop: PackedVector2Array = p.pts.duplicate()
							loop.append(p.pts[0])
							draw_polyline(loop, p.edge, 3.0, true)
						elif p.has("line"):
							draw_polyline(p.line, p.col, p.width, true)
				"image":
					draw_texture(op.tex, Vector2.ZERO)
