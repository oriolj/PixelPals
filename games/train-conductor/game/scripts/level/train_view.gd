extends Node2D
## The train, seen from above like a wooden toy: the red engine (chimney,
## dome, cab with the driver's rider in a round window, a face on the
## smokebox that always stays upright, wheels with pistons), the tender with
## the kids' riders, and the painted carriages with round windows (the
## passengers' heads are drawn by the people view, above).
##
## Cars are placed from Train.car_transforms(): both bogies sit on the track,
## so the cars follow the curves instead of cutting the corners.

const Palette := preload("res://scripts/palette.gd")
const Shapes := preload("res://scripts/vector/shapes.gd")
const Train := preload("res://scripts/track/train.gd")

const WIDTH := 52.0
const WINDOW_R := 15.0
const RIDER_WINDOW_R := 27.0

var sim
var time := 0.0
var wobble := 0.0
## Per car: seconds of the "just coupled" pop.
var pop: Array[float] = []
## Horn / whistle pressed recently: the face goes "O".
var toot := 0.0
var blink := 0.0
var riders: Array[AnimatedSprite2D] = []
var xforms: Array[Transform2D] = []


func setup(run_sim, rider_ids: Array[String]) -> void:
	sim = run_sim
	for i in 3:
		var id := rider_ids[i] if i < rider_ids.size() else ""
		var spr := AnimatedSprite2D.new()
		spr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		spr.scale = Vector2(3, 3)
		spr.visible = id != ""
		if id != "":
			spr.sprite_frames = Art.frames(id, Palette.WHITE, Vector2i(16, 16))
			spr.play("default")
			spr.speed_scale = 0.8 + 0.2 * i
		add_child(spr)
		riders.append(spr)
	_refresh()


## Change who rides (select screen).
func set_riders(rider_ids: Array[String]) -> void:
	for i in riders.size():
		var id := rider_ids[i] if i < rider_ids.size() else ""
		riders[i].visible = id != ""
		if id != "":
			var sf := Art.frames(id, Palette.WHITE, Vector2i(16, 16))
			if riders[i].sprite_frames != sf:
				riders[i].sprite_frames = sf
				riders[i].play("default")


func on_coupled() -> void:
	pop.resize(sim.train.cars + 2)
	pop[sim.train.cars + 1] = 0.45


func _process(delta: float) -> void:
	time += delta
	toot = maxf(0.0, toot - delta)
	blink -= delta
	if blink < -3.2:
		blink = 0.15
	for i in pop.size():
		pop[i] = maxf(0.0, pop[i] - delta)
	wobble = move_toward(wobble, sim.wobble, delta * 3.0)
	_refresh()
	queue_redraw()


func _refresh() -> void:
	xforms = sim.train.car_transforms()
	if pop.size() < xforms.size():
		pop.resize(xforms.size())
	# Riders: driver in the cab, kids on the tender, always upright.
	var spots := [[0, Vector2(-30, 0)], [1, Vector2(24, 0)], [1, Vector2(-24, 0)]]
	for i in riders.size():
		var t := xforms[spots[i][0]]
		riders[i].position = t * (spots[i][1] as Vector2) + Vector2(0, -2)
		riders[i].z_index = 1


func car_transform(i: int) -> Transform2D:
	var t := xforms[i]
	if i >= 2 and wobble > 0.0:
		t = t.rotated_local(sin(time * 18.0 + i * 1.7) * 0.07 * wobble)
	var p: float = pop[i] if i < pop.size() else 0.0
	if p > 0.0:
		t = t.scaled_local(Vector2.ONE * (1.0 + 0.35 * sin(p / 0.45 * PI)))
	return t


## World position of passenger seat `seat` (2 per carriage).
func seat_position(seat: int) -> Vector2:
	var car := 2 + seat / Train.SEATS_PER_CAR
	if car >= xforms.size():
		car = xforms.size() - 1
	var x := 17.0 if seat % 2 == 0 else -17.0
	return car_transform(car) * Vector2(x, 0)


func chimney_position() -> Vector2:
	return xforms[0] * Vector2(28, 0) if not xforms.is_empty() else Vector2.ZERO


func nose_position() -> Vector2:
	return xforms[0] * Vector2(Train.ENGINE_LEN * 0.5, 0) if not xforms.is_empty() else Vector2.ZERO


func _draw() -> void:
	if xforms.is_empty():
		return
	# Couplings first, under the cars.
	var spans: Array[Vector3] = sim.train.car_spans()
	for i in range(1, spans.size()):
		var a: Vector2 = sim.train.point_back(spans[i - 1].z + spans[i - 1].x - Train.BOGIE_INSET)
		var b: Vector2 = sim.train.point_back(spans[i].x - Train.BOGIE_INSET)
		draw_line(a, b, Palette.INK, 8.0)
		draw_line(a, b, Palette.GROOVE, 4.0)
	for i in range(xforms.size() - 1, -1, -1):
		var t := car_transform(i)
		draw_set_transform_matrix(t)
		match i:
			0:
				_draw_engine()
			1:
				_draw_tender()
			_:
				_draw_carriage(i - 2)
	draw_set_transform(Vector2.ZERO, 0.0)
	_draw_face()


func _wheels(len: float, count: int) -> void:
	var phase := int(sim.train.odometer / 14.0) % 2
	for side in [-1.0, 1.0]:
		for k in count:
			var x := -len * 0.5 + len * (k + 0.5) / count
			Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(x - 11, side * (WIDTH * 0.5 + 1) - 5, 22, 10), 4), Palette.BLACK, 2.0)
		if count >= 3:
			var off := 5.0 if phase == 0 else -5.0
			draw_line(Vector2(-len * 0.33 + off, side * (WIDTH * 0.5 + 1)), Vector2(len * 0.33 + off, side * (WIDTH * 0.5 + 1)),
				Palette.ROCK, 4.0)


func _draw_engine() -> void:
	var l := Train.ENGINE_LEN
	draw_colored_polygon(Shapes.rounded_rect(Rect2(-l * 0.5 + 5, -WIDTH * 0.5 + 7, l, WIDTH), 12), Color(Palette.INK, 0.25))
	_wheels(l - 20.0, 3)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-l * 0.5, -WIDTH * 0.5, l, WIDTH), 12), Palette.ENGINE_DARK, 3.0)
	# Boiler with brass bands.
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-6, -21, l * 0.5 + 2, 42), 16), Palette.ENGINE, 2.0)
	for x in [8.0, 26.0, 44.0]:
		draw_line(Vector2(x, -20), Vector2(x, 20), Palette.STATION[2], 3.0)
	# Dome and chimney.
	Shapes.fill_outline(self, Shapes.circle(Vector2(10, 0), 9, 18), Palette.STATION[2], 2.0)
	Shapes.fill_outline(self, Shapes.circle(Vector2(28, 0), 12, 20), Palette.BLACK, 2.0)
	draw_circle(Vector2(28, 0), 6, Palette.INK)
	# Buffers.
	for y in [-17.0, 17.0]:
		Shapes.fill_outline(self, Shapes.circle(Vector2(l * 0.5 + 1, y), 5, 12), Palette.BLACK, 1.5)
	# Cab: dark roof and the driver's round window.
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-l * 0.5 - 2, -WIDTH * 0.5 - 2, 54, WIDTH + 4), 10), Palette.CAB_ROOF, 3.0)
	Shapes.fill_outline(self, Shapes.circle(Vector2(-30, 0), RIDER_WINDOW_R, 28), Palette.SKY.lightened(0.35), 3.0)


func _draw_tender() -> void:
	var l := Train.TENDER_LEN
	draw_colored_polygon(Shapes.rounded_rect(Rect2(-l * 0.5 + 5, -WIDTH * 0.5 + 7, l, WIDTH), 12), Color(Palette.INK, 0.25))
	_wheels(l - 16.0, 2)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-l * 0.5, -WIDTH * 0.5, l, WIDTH), 12), Palette.ENGINE, 3.0)
	draw_line(Vector2(-l * 0.5 + 6, 0), Vector2(l * 0.5 - 6, 0), Palette.ENGINE_DARK, 3.0)
	for k in 2:
		var c := Vector2(24 if k == 0 else -24, 0)
		var seated: bool = riders[k + 1].visible
		Shapes.fill_outline(self, Shapes.circle(c, RIDER_WINDOW_R, 28), Palette.SKY.lightened(0.35) if seated else Palette.BLACK, 3.0)
		if not seated:
			# Coal lumps where nobody rides.
			for m in 5:
				draw_circle(c + Vector2.from_angle(m * 1.3) * 11.0, 7.0, Palette.INK.lightened(0.15))


func _draw_carriage(k: int) -> void:
	var l := Train.CAR_LEN
	var col: Color = Palette.CARRIAGES[k % Palette.CARRIAGES.size()]
	draw_colored_polygon(Shapes.rounded_rect(Rect2(-l * 0.5 + 5, -WIDTH * 0.5 + 7, l, WIDTH - 4), 12), Color(Palette.INK, 0.25))
	_wheels(l - 16.0, 2)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-l * 0.5, -WIDTH * 0.5 + 2, l, WIDTH - 4), 12), col, 3.0)
	Shapes.fill_outline(self, Shapes.rounded_rect(Rect2(-l * 0.5 + 6, -WIDTH * 0.5 + 8, l - 12, WIDTH - 16), 9), col.lightened(0.25), 2.0)
	for x in [17.0, -17.0]:
		Shapes.fill_outline(self, Shapes.circle(Vector2(x, 0), WINDOW_R, 22), Palette.SKY.lightened(0.45), 2.0)


func _draw_face() -> void:
	# The smokebox face stays upright whatever way the engine points.
	var c := xforms[0] * Vector2(Train.ENGINE_LEN * 0.5 - 4, 0)
	Shapes.fill_outline(self, Shapes.circle(c, 21, 28), Palette.ROCK.lightened(0.25), 3.0)
	var eye_h := 1.0 if blink > 0.0 else 5.0
	for x in [-7.0, 7.0]:
		draw_colored_polygon(Shapes.ellipse(c + Vector2(x, -5), 4.0, eye_h, 12), Palette.INK)
		if eye_h > 2.0:
			draw_circle(c + Vector2(x + 1.2, -6.5), 1.3, Palette.WHITE)
	draw_circle(c + Vector2(-12, 4), 3.5, Color(Palette.PINK, 0.8))
	draw_circle(c + Vector2(12, 4), 3.5, Color(Palette.PINK, 0.8))
	if toot > 0.0:
		Shapes.fill_outline(self, Shapes.ellipse(c + Vector2(0, 7), 5, 6, 14), Palette.INK, 0.0)
	else:
		draw_arc(c + Vector2(0, 4), 7.0, 0.35, PI - 0.35, 12, Palette.INK, 2.5)
