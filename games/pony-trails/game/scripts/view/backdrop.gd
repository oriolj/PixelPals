extends Node2D
## The menus' backdrop: a morning meadow with soft hills, a fence and a few
## drifting clouds, drawn in palette colours (no sprite needed).

const SKY: Array[Color] = [Color("#0099db"), Color("#2ce8f5")]
const HILL_FAR := Color("#63c74d")
const HILL_NEAR := Color("#3e8948")
const GRASS := Color("#265c42")
const FENCE := Color("#b86f50")
const FENCE_DARK := Color("#733e39")
const CLOUD := Color("#ffffff")

var time := 0.0


func tick(dt: float) -> void:
	time += dt
	queue_redraw()


func _draw() -> void:
	draw_rect(Rect2(0, 0, 320, 70), SKY[0])
	draw_rect(Rect2(0, 70, 320, 40), SKY[1])
	for i in 4:
		var cx := fposmod(40.0 + i * 90.0 + time * (3.0 + i), 380.0) - 30.0
		var cy := 18.0 + (i % 2) * 16.0
		for k in 3:
			draw_circle(Vector2(roundf(cx + k * 8.0), cy - (4.0 if k == 1 else 0.0)), 7.0, CLOUD)
	for x in range(0, 320, 2):
		var h := 96.0 + 8.0 * sin(x * 0.03) + 5.0 * sin(x * 0.071 + 1.0)
		draw_rect(Rect2(x, roundf(h), 2, 180 - roundf(h)), HILL_FAR)
	for x in range(0, 320, 2):
		var h2 := 120.0 + 6.0 * sin(x * 0.045 + 2.0)
		draw_rect(Rect2(x, roundf(h2), 2, 180 - roundf(h2)), HILL_NEAR)
	draw_rect(Rect2(0, 140, 320, 40), GRASS)
	for x in range(4, 320, 24):
		draw_rect(Rect2(x, 128, 3, 16), FENCE_DARK)
		draw_rect(Rect2(x, 128, 2, 15), FENCE)
	draw_rect(Rect2(0, 131, 320, 2), FENCE)
	draw_rect(Rect2(0, 138, 320, 2), FENCE)
