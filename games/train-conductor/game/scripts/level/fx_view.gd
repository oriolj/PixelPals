extends Node2D
## Effects in the world: chimney steam (CPUParticles2D, faster with speed),
## the whistle's steam ring, sparkles for a perfect stop, hearts from the
## animals that answer, stars from a lit house, and the brake dust.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Draw := preload("res://scripts/level/draw.gd")

var steam: CPUParticles2D
## {kind, pos, vel, age, life, size, colour, rot}
var bits: Array[Dictionary] = []
var time := 0.0


func _ready() -> void:
	steam = CPUParticles2D.new()
	steam.texture = soft_circle(32)
	steam.amount = 48
	steam.lifetime = 1.6
	steam.local_coords = false
	steam.direction = Vector2(0, -1)
	steam.spread = 25.0
	steam.gravity = Vector2(0, -30)
	steam.initial_velocity_min = 30.0
	steam.initial_velocity_max = 60.0
	steam.scale_amount_min = 0.5
	steam.scale_amount_max = 0.8
	var grow := Curve.new()
	grow.add_point(Vector2(0, 0.6))
	grow.add_point(Vector2(1, 1.8))
	steam.scale_amount_curve = grow
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 0.85))
	ramp.set_color(1, Color(1, 1, 1, 0.0))
	steam.color_ramp = ramp
	add_child(steam)


static func soft_circle(size: int) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var c := Vector2(size, size) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(x + 0.5, y + 0.5).distance_to(c) / (size * 0.5)
			var a := clampf((1.0 - d) * 3.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	return ImageTexture.create_from_image(img)


## Steam follows the chimney; puffs come quicker the faster the train runs.
func chimney(at: Vector2, speed: float) -> void:
	steam.position = at
	steam.speed_scale = 0.6 + speed / 250.0


func ring(at: Vector2, big := false) -> void:
	bits.append({"kind": "ring", "pos": at, "vel": Vector2(0, -40), "age": 0.0, "life": 1.0 if not big else 1.4,
		"size": 60.0 if not big else 95.0, "colour": Palette.WHITE, "rot": 0.0})
	for i in 3:
		bits.append({"kind": "puff", "pos": at + Vector2(randf_range(-10, 10), 0), "vel": Vector2(randf_range(-30, 30), -80 - i * 30),
			"age": 0.0, "life": 1.1, "size": 18.0 + i * 6.0, "colour": Palette.WHITE, "rot": 0.0})


func sparkle(at: Vector2, colour := Palette.GLOW, count := 14) -> void:
	for i in count:
		var a := TAU * i / count
		bits.append({"kind": "star", "pos": at, "vel": Vector2.from_angle(a) * randf_range(140, 240), "age": 0.0,
			"life": 0.9, "size": randf_range(9, 15), "colour": colour, "rot": randf() * TAU})


func hearts(at: Vector2, count := 3) -> void:
	for i in count:
		bits.append({"kind": "heart", "pos": at + Vector2(randf_range(-20, 20), -30), "vel": Vector2(randf_range(-25, 25), -70),
			"age": -i * 0.15, "life": 1.3, "size": 11.0, "colour": Palette.PINK, "rot": 0.0})


func dust(at: Vector2) -> void:
	for i in 6:
		bits.append({"kind": "puff", "pos": at + Vector2(randf_range(-20, 20), randf_range(-20, 20)),
			"vel": Vector2(randf_range(-50, 50), randf_range(-50, 50)), "age": 0.0, "life": 0.6, "size": 10.0,
			"colour": Palette.CREAM, "rot": 0.0})


func _process(delta: float) -> void:
	time += delta
	for i in range(bits.size() - 1, -1, -1):
		var b: Dictionary = bits[i]
		b.age += delta
		if b.age >= b.life:
			bits.remove_at(i)
			continue
		if b.age < 0.0:
			continue
		b.pos += b.vel * delta
		b.vel *= 0.94 if b.kind == "star" else 0.98
		b.rot += delta * 3.0
	queue_redraw()


func _draw() -> void:
	for b in bits:
		if b.age < 0.0:
			continue
		var k: float = b.age / b.life
		var a := 1.0 - k
		match b.kind:
			"ring":
				var r: float = b.size * (0.3 + 0.9 * k)
				draw_arc(b.pos, r, 0, TAU, 40, Color(Palette.WHITE, a), 10.0 * a + 2.0)
				draw_arc(b.pos, r, 0, TAU, 40, Color(Palette.INK, a * 0.25), 2.0)
			"puff":
				draw_circle(b.pos, b.size * (0.7 + k), Color(b.colour, a * 0.8))
			"star":
				Shapes.fill_outline(self, Shapes.star(b.pos, b.size * (1.0 - 0.4 * k), -1.0, 5, b.rot),
					Color(b.colour, a), 1.5, Color(Palette.INK, a))
			"heart":
				_heart(b.pos, b.size, Color(b.colour, a))


func _heart(p: Vector2, s: float, col: Color) -> void:
	draw_circle(p + Vector2(-s * 0.5, 0), s * 0.6, col)
	draw_circle(p + Vector2(s * 0.5, 0), s * 0.6, col)
	draw_colored_polygon(PackedVector2Array([p + Vector2(-s * 1.05, s * 0.2), p + Vector2(s * 1.05, s * 0.2), p + Vector2(0, s * 1.4)]), col)
