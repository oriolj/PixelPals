extends Node2D
## The level's pixel HUD at 480x270, icons only: the star bucket with a pip
## per star, a flame pip per fire (lit = still to do), a badge slot per cat,
## an arrow at the screen edge toward the objective when it is off screen,
## and the pause overlay. Reads everything from the level each frame.

const W := 480
const H := 270
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")
const YELLOW := Color("#ffcd75")
const ORANGE := Color("#ef7d57")
const GREY := Color("#94b0c2")

var level: Node
var paused := false
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _tex(sprite_name: String, frame := 0, tint := Color.MAGENTA, size := Vector2i(16, 16)) -> Texture2D:
	var sf := Art.frames(sprite_name, tint, size)
	var n := sf.get_frame_count("default")
	return sf.get_frame_texture("default", frame % maxi(n, 1))


func _draw() -> void:
	if level == null:
		return
	_draw_stars()
	_draw_fires()
	_draw_cats()
	_draw_edge_arrow()
	if paused:
		_draw_pause()


func _panel(r: Rect2) -> void:
	draw_rect(r, Color(INK, 0.55))
	draw_rect(Rect2(r.position.x, r.end.y - 1, r.size.x, 1), Color(INK, 0.8))


func _draw_stars() -> void:
	var shown: int = level.shown_stars
	var cols := 9
	var rows := maxi(1, ceili(shown / float(cols)))
	_panel(Rect2(2, 2, 36 + mini(shown, cols) * 9, 30 if rows < 3 else 40))
	var bounce := -2 if level.bucket_bounce > 0.0 else 0
	draw_texture(_tex("bucket", 0, ORANGE, Vector2i(24, 24)), Vector2(6, 5 + bounce))
	var star := _tex("star", 0, YELLOW, Vector2i(8, 8))
	for i in shown:
		var col := i % cols
		var row := i / cols
		draw_texture(star, Vector2(34 + col * 9, 5 + row * 9))


func _draw_fires() -> void:
	var fires: Array = level.fires
	var n := fires.size()
	var step := 18
	var x0 := W / 2 - (n * step) / 2
	_panel(Rect2(x0 - 4, 2, n * step + 6, 22))
	for i in n:
		var f = fires[i]
		var done: bool = f.out
		var frame := int(_t * 6.0 + i) % 2
		var tex := _tex("pip_flame_out" if done else "pip_flame", frame, GREY if done else ORANGE, Vector2i(8, 8))
		var y := 5
		if f.lit() and int(_t * 4.0) % 2 == 0:
			y = 4
		draw_texture_rect(tex, Rect2(x0 + i * step, y, 16, 16), false)


func _draw_cats() -> void:
	var cats: Array = level.cats
	var n := cats.size()
	var step := 22
	var x0 := W - 6 - n * step
	_panel(Rect2(x0 - 4, 2, n * step + 8, 26))
	for i in n:
		var c: Dictionary = cats[i]
		var name_ := "badge_cat" if c.rescued else "badge_empty"
		var y := 5
		if c.rescued and c.get("pop", 0.0) > 0.0:
			y = 3
		draw_texture_rect(_tex(name_, 0, YELLOW if c.rescued else GREY), Rect2(x0 + i * step, y, 20, 20), false)


func _draw_edge_arrow() -> void:
	var info: Dictionary = level.objective_screen()
	if info.is_empty() or info.on_screen:
		return
	var p: Vector2 = info.pos
	var centre := Vector2(W / 2.0, H / 2.0 + 10)
	var dir := (p - centre).normalized()
	if dir == Vector2.ZERO:
		return
	var margin := Vector2(26, 34)
	var half := Vector2(W / 2.0, H / 2.0) - margin
	var k := minf(absf(half.x / dir.x) if dir.x != 0.0 else INF, absf(half.y / dir.y) if dir.y != 0.0 else INF)
	var at := centre + dir * k
	at = at.round()
	var bob := sin(_t * 8.0) * 2.0
	var tip := at + dir * (12.0 + bob)
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([tip, at + side * 9.0 + dir * bob, at - side * 9.0 + dir * bob])
	var outline := PackedVector2Array([tip + dir * 2.0, at + side * 11.5 + dir * (bob - 1.5), at - side * 11.5 + dir * (bob - 1.5)])
	draw_colored_polygon(outline, INK)
	draw_colored_polygon(pts, YELLOW if int(_t * 4.0) % 2 == 0 else WHITE)
	var icon := _tex(info.icon, int(_t * 4.0) % 2, ORANGE)
	var ip := (at - dir * 14.0 - Vector2(8, 8)).round()
	draw_circle(ip + Vector2(8, 8), 11, Color(INK, 0.7))
	draw_texture(icon, ip)


func _draw_pause() -> void:
	draw_rect(Rect2(0, 0, W, H), Color(INK, 0.6))
	# Back arrow (driver's b) on the left, play triangle (a / start) on the right.
	var c := Vector2(W / 2.0, H / 2.0)
	draw_colored_polygon(PackedVector2Array([c + Vector2(-70, 0), c + Vector2(-44, -22), c + Vector2(-44, 22)]), GREY)
	draw_rect(Rect2(c.x - 46, c.y - 8, 26, 16), GREY)
	draw_colored_polygon(PackedVector2Array([c + Vector2(34, -26), c + Vector2(74, 0), c + Vector2(34, 26)]), WHITE)
