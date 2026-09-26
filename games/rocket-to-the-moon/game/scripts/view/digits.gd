extends Node2D
## A pixel number drawn with rects (no font, no text): the PixelPals 3x5 glyphs.
## Centred on x = 0, top at y = 0. `px` is the size of one glyph pixel.

const GLYPHS := [
	["###", "#.#", "#.#", "#.#", "###"], [".#.", "##.", ".#.", ".#.", "###"],
	["###", "..#", "###", "#..", "###"], ["###", "..#", "###", "..#", "###"],
	["#.#", "#.#", "###", "..#", "..#"], ["###", "#..", "###", "..#", "###"],
	["###", "#..", "###", "#.#", "###"], ["###", "..#", "..#", ".#.", ".#."],
	["###", "#.#", "###", "#.#", "###"], ["###", "#.#", "###", "..#", "###"],
]

var px := 2
var color := Color("#f4f4f4")
var shadow := Color("#1a1c2c")
var value := -1:
	set(v):
		if v != value:
			value = v
			queue_redraw()


func width() -> int:
	var s := str(maxi(value, 0))
	return s.length() * 4 * px - px


func _draw() -> void:
	if value < 0:
		return
	var s := str(value)
	var x0 := -width() / 2
	for pass_i in 2:
		var off := Vector2(px / 2 + 1, px / 2 + 1) if pass_i == 0 else Vector2.ZERO
		var col := shadow if pass_i == 0 else color
		for k in s.length():
			var glyph: Array = GLYPHS[int(s[k])]
			for row in 5:
				for c in 3:
					if glyph[row][c] == "#":
						draw_rect(Rect2(Vector2(x0 + (k * 4 + c) * px, row * px) + off, Vector2(px, px)), col)
