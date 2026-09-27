extends Node2D
## The whole-house mini view (64x40) that flashes for 2 s when a cat meows:
## every floor of house.json as a row of little rooms, the meowing room lit
## in the cat's collar colour, the walker as a white dot. HUD node; its
## origin is the top-left of the house_mini sprite.

const W := 64
const H := 40
## The region inside house_mini where rooms are painted.
const INNER := Rect2i(2, 10, 60, 28)
const DIM := Color("#566c86")
const WALL := Color("#94b0c2")

var house: RefCounted
var lit_room := ""
var lit_color := Color("#b13e53")
var walker_room := ""
var time := 0.0
var _frame: AnimatedSprite2D


func _ready() -> void:
	_frame = Art.sprite("house_mini", Color("#333c57"), Vector2i(W, H))
	_frame.centered = false
	_frame.show_behind_parent = true
	add_child(_frame)


func _process(delta: float) -> void:
	time += delta
	queue_redraw()


## The rectangle of a room inside the mini view (local pixels).
func room_rect(rid: String) -> Rect2i:
	var r: Dictionary = house.rooms[rid]
	var n: int = house.floor_count()
	var row_h := (INNER.size.y - (n - 1)) / n
	var row := n - 1 - int(r.floor)
	var maxw := 1
	for f in n:
		maxw = maxi(maxw, house.width(f))
	var sx := float(INNER.size.x) / maxw
	var x0 := INNER.position.x + int(roundf(r.x0 * sx))
	var x1 := INNER.position.x + int(roundf((r.x0 + r.w) * sx))
	var y0 := INNER.position.y + row * (row_h + 1)
	return Rect2i(x0, y0, maxi(2, x1 - x0 - 1), row_h)


func _draw() -> void:
	if house == null:
		return
	for rid in house.rooms:
		var rr := room_rect(rid)
		var col := DIM if house.rooms[rid].kind != "stairs" else DIM.darkened(0.2)
		if rid == lit_room:
			col = lit_color if int(time * 6.0) % 2 == 0 else lit_color.lightened(0.35)
		draw_rect(Rect2(rr), col)
		draw_rect(Rect2(rr.position.x, rr.position.y, rr.size.x, 1), WALL)
	if walker_room != "" and house.rooms.has(walker_room):
		var wr := room_rect(walker_room)
		draw_rect(Rect2(wr.position.x + wr.size.x / 2 - 1, wr.end.y - 3, 2, 2), Color("#f4f4f4"))
