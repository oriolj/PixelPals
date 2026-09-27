extends Node2D
## Draws the static dollhouse from the house data: outside, roof/ceiling
## bands, wallpaper per room, floorboards, slab, doorways, stairs, windows
## and sunny patches. Everything comes from the house data plus the tile
## sprites in res://art (missing tiles fall back to flat palette colours),
## so a new house.json needs no code. Redraw with set_day_part().

const H := preload("res://scripts/house/house_data.gd")

## Outside sky per part of the day (Sweetie 16, warm at night: plum, not navy).
const SKY := {"morning": Color("#73eff7"), "afternoon": Color("#41a6f6"), "evening": Color("#ef7d57"),
	"night": Color("#5d275d")}
const GROUND := Color("#38b764")
const EDGE := Color("#333c57")
const SUN := Color("#ffcd75")

var house: RefCounted
var part := "morning"
var part_index := 0


func set_day_part(p: String, index: int) -> void:
	part = p
	part_index = index
	queue_redraw()


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED


func _tex(name: String, frame := 0) -> Texture2D:
	if not Art.has(name):
		return null
	var sf := Art.frames(name)
	if frame >= sf.get_frame_count("default"):
		frame = 0
	return sf.get_frame_texture("default", frame)


## Tiles a one-frame sprite over a rect (the atlas is the whole PNG).
func _tile(name: String, r: Rect2, fallback: Color) -> void:
	var t := _tex(name)
	if t is AtlasTexture and t.atlas and Art.manifest[name].get("frames", 1) == 1:
		draw_texture_rect(t.atlas, r, true)
	elif t:
		draw_texture_rect(t, r, true)
	else:
		draw_rect(r, fallback)


func _bottom_center(name: String, at: Vector2, frame := 0) -> void:
	var t := _tex(name, frame)
	if t == null:
		return
	var sz := Art.size_of(name)
	draw_texture(t, Vector2(roundf(at.x - sz.x / 2.0), at.y - sz.y))


func _draw() -> void:
	if house == null:
		return
	var maxw := 0
	for f in house.floor_count():
		maxw = maxi(maxw, house.width(f))
	var total_h: int = house.floor_count() * H.BAND_H
	# Outside: sky, a strip of garden under the ground floor.
	draw_rect(Rect2(-400, -40, maxw + 800, total_h + 80), SKY.get(part, SKY.morning))
	if part == "night":
		for i in 60:
			var sx := -390 + (i * 97) % (maxw + 780)
			var sy := -30 + (i * 53) % (total_h + 40)
			draw_rect(Rect2(sx, sy, 1, 1), SUN)
	draw_rect(Rect2(-400, total_h - 20, maxw + 800, 60), GROUND)
	for f in house.floor_count():
		_draw_floor(f)


func _draw_floor(f: int) -> void:
	var y0: int = house.band_top(f)
	var w: int = house.width(f)
	var top: bool = f == house.floor_count() - 1
	# The dollhouse shell: a dark edge around the band.
	draw_rect(Rect2(-3, y0, w + 6, H.BAND_H), EDGE)
	_tile("roof" if top else "ceiling", Rect2(0, y0, w, H.CEIL_Y), Color("#b13e53") if top else Color("#ef7d57"))
	for rid in house.floors[f].rooms:
		var r: Dictionary = house.rooms[rid]
		_tile(r.wall, Rect2(r.x0, y0 + H.CEIL_Y, r.w, H.FLOOR_Y - H.CEIL_Y), Color("#ffcd75"))
		_tile(r.floor_tile, Rect2(r.x0, y0 + H.FLOOR_Y, r.w, 8), Color("#ef7d57"))
	_tile("slab", Rect2(0, y0 + H.FLOOR_Y + 8, w, H.BAND_H - H.FLOOR_Y - 8), Color("#b13e53"))
	var fy: int = house.floor_y(f)
	for rid in house.floors[f].rooms:
		var r: Dictionary = house.rooms[rid]
		if r.kind == "stairs":
			if house.stair_link(rid, 1) != "":
				_bottom_center("stairs", Vector2(r.x0 + r.w / 2.0, fy))
			else:
				_bottom_center("banister", Vector2(r.x0 + r.w / 2.0, fy))
		if not r.window.is_empty():
			_bottom_center("window", Vector2(r.window.x, fy - r.window.y), part_index)
			if part_index <= 1:
				_sun_patch(r.window.x, fy)
		for sx in r.sunny:
			if part_index <= 1 and (r.window.is_empty() or absi(int(sx) - int(r.window.x)) > 8):
				_sun_patch(sx, fy)
		if r.index > 0:
			_bottom_center("doorway", Vector2(r.x0, fy))


## A dithered warm patch of sunlight on the floor and the wall under a window.
func _sun_patch(cx: int, fy: int) -> void:
	var c := Color(SUN, 0.55)
	for yy in range(fy - 10, fy + 6):
		var half := 10 + (yy - (fy - 10)) / 2
		for xx in range(cx - half, cx + half):
			if (xx + yy) % 2 == 0:
				draw_rect(Rect2(xx, yy, 1, 1), c)
