extends Sprite2D
## Draws the terrain grid into one Image (960x320, RGBA8) shown through an
## ImageTexture. A dig repaints only the dirty cells (plus a one-cell margin,
## for the tunnel edges) and uploads the texture once per frame.
##
## Each dirt cell gets its band's colours and a hashed 4x4 texture (plain,
## crumb, pebble) from the dirt_tex sprite strip; a solid cell next to a
## tunnel gets a 1 px darker edge on that side. Tunnels are dark with roots.

const Grid := preload("res://scripts/dig/terrain_grid.gd")
const ArtImage := preload("res://scripts/art_image.gd")

const C_TUNNEL := Color("#1a1c2c")
const C_ROOT := Color("#5d275d")
## Texture colour (authored as topsoil) -> colour per band.
const TEX_BASE := Color("#ef7d57")
const TEX_DARK := Color("#b13e53")
const TEX_LIGHT := Color("#ffcd75")
const BANDS := {
	Grid.TOPSOIL: [Color("#ef7d57"), Color("#b13e53"), Color("#ffcd75"), Color("#b13e53")],
	Grid.CLAY: [Color("#b13e53"), Color("#5d275d"), Color("#ef7d57"), Color("#5d275d")],
	Grid.DEEP: [Color("#5d275d"), Color("#1a1c2c"), Color("#b13e53"), Color("#333c57")],
	Grid.ROCK: [Color("#333c57"), Color("#1a1c2c"), Color("#566c86"), Color("#1a1c2c")],
}
## Texture variant weights: plain, plain, crumb, crumb, pebble, pebble.
const WEIGHTS := [46, 22, 8, 10, 6, 8]

var grid: Grid
var image: Image
var tex: ImageTexture
## band -> Array[Image] of 4x4 cells, one per texture variant.
var _cells := {}
var _air: Image
var _pick: PackedByteArray
## Stats for tests: cells repainted in total and in the last flush.
var painted_total := 0
var painted_last := 0


func setup(g: Grid) -> void:
	grid = g
	centered = false
	image = Image.create(grid.w * Grid.CELL, grid.h * Grid.CELL, false, Image.FORMAT_RGBA8)
	_build_cells()
	_pick = PackedByteArray()
	_pick.resize(100)
	var k := 0
	for v in WEIGHTS.size():
		for i in WEIGHTS[v]:
			_pick[k] = v
			k += 1
	grid.take_dirty()
	paint_rect(Rect2i(0, 0, grid.w, grid.h))
	tex = ImageTexture.create_from_image(image)
	texture = tex


func _build_cells() -> void:
	var src := ArtImage.load_image("dirt_tex")
	var n := 6
	for band in BANDS:
		var cols: Array = BANDS[band]
		var list: Array[Image] = []
		for v in n:
			var img := Image.create(Grid.CELL, Grid.CELL, false, Image.FORMAT_RGBA8)
			img.fill(cols[0])
			if src and src.get_width() >= Grid.CELL * n:
				for y in Grid.CELL:
					for x in Grid.CELL:
						var c := src.get_pixel(v * Grid.CELL + x, y)
						if c.a < 0.5:
							continue
						if c.is_equal_approx(TEX_DARK):
							c = cols[1]
						elif c.is_equal_approx(TEX_LIGHT):
							c = cols[2]
						else:
							c = cols[0]
						img.set_pixel(x, y, c)
			list.append(img)
		_cells[band] = list
	_air = Image.create(Grid.CELL, Grid.CELL, false, Image.FORMAT_RGBA8)
	_air.fill(C_TUNNEL)


## Repaint the dirty cells (grown by one for the edges) and upload once.
func flush() -> void:
	var d := grid.take_dirty()
	painted_last = 0
	if d.size == Vector2i.ZERO:
		return
	paint_rect(d.grow(1))
	if tex:
		tex.update(image)


func paint_rect(r: Rect2i) -> void:
	var clip := r.intersection(Rect2i(0, 0, grid.w, grid.h))
	for y in range(clip.position.y, clip.end.y):
		for x in range(clip.position.x, clip.end.x):
			_paint_cell(x, y)
	var n := clip.size.x * clip.size.y
	painted_last += n
	painted_total += n


func _paint_cell(x: int, y: int) -> void:
	var v := grid.cells[y * grid.w + x]
	var at := Vector2i(x * Grid.CELL, y * Grid.CELL)
	var h := absi(hash(Vector2i(x, y)))
	if v == Grid.AIR:
		image.blit_rect(_air, Rect2i(0, 0, Grid.CELL, Grid.CELL), at)
		# Roots hang from the ceiling of shallow tunnels.
		var above := grid.get_cell(Vector2i(x, y - 1))
		if (above == Grid.TOPSOIL or above == Grid.CLAY) and h % 5 == 0:
			var rx := at.x + 1 + (h >> 4) % 2
			image.fill_rect(Rect2i(rx, at.y, 1, 2 + (h >> 6) % 2), C_ROOT)
			image.set_pixel(rx + 1, at.y + 2, C_ROOT)
		return
	var list: Array = _cells[v]
	image.blit_rect(list[_pick[h % 100]], Rect2i(0, 0, Grid.CELL, Grid.CELL), at)
	var edge: Color = BANDS[v][3]
	if grid.get_cell(Vector2i(x, y - 1)) == Grid.AIR and y > 0:
		image.fill_rect(Rect2i(at.x, at.y, Grid.CELL, 1), edge)
	if grid.get_cell(Vector2i(x, y + 1)) == Grid.AIR:
		image.fill_rect(Rect2i(at.x, at.y + Grid.CELL - 1, Grid.CELL, 1), edge)
	if grid.get_cell(Vector2i(x - 1, y)) == Grid.AIR:
		image.fill_rect(Rect2i(at.x, at.y, 1, Grid.CELL), edge)
	if grid.get_cell(Vector2i(x + 1, y)) == Grid.AIR:
		image.fill_rect(Rect2i(at.x + Grid.CELL - 1, at.y, 1, Grid.CELL), edge)
