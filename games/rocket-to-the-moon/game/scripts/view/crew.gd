extends Node2D
## The crew: one portrait per seated seat, the rider in a space helmet inside
## a frame in the seat colour. hop(seat) makes a portrait jump when that seat
## does something, so each child sees which one is theirs.

const SLOT := 24

var _slots := {}   # seat -> {"node": Node2D, "hop": float}


func _ready() -> void:
	var i := 0
	for seat in Players.SEAT_COUNT:
		if not Players.is_seated(seat):
			continue
		var slot := Node2D.new()
		slot.position = Vector2(i * SLOT + SLOT / 2, SLOT / 2)
		add_child(slot)
		var frame := Frame.new()
		frame.color = Players.SEAT_COLORS[seat]
		slot.add_child(frame)
		var rider: String = Players.riders[seat]
		if rider == "":
			rider = Game.roster[seat % Game.roster.size()]
		var r := Art.sprite(rider, Game.rider_color(rider), Vector2i(16, 16))
		r.position = Vector2(0, 1)
		slot.add_child(r)
		var helmet := Art.sprite("helmet", Color(0.7, 0.9, 1.0, 0.0), Vector2i(20, 20))
		slot.add_child(helmet)
		_slots[seat] = {"node": slot, "hop": 0.0, "x": slot.position.x}
		i += 1


func width() -> int:
	return _slots.size() * SLOT


func hop(seat: int) -> void:
	if _slots.has(seat):
		_slots[seat].hop = 0.25


func tick(dt: float) -> void:
	for seat in _slots:
		var s: Dictionary = _slots[seat]
		s.hop = maxf(0.0, s.hop - dt)
		s.node.position.y = SLOT / 2 - (2 if s.hop > 0.0 else 0)


class Frame extends Node2D:
	var color := Color.WHITE

	func _draw() -> void:
		draw_rect(Rect2(-11, -11, 22, 22), color)
		draw_rect(Rect2(-10, -10, 20, 20), Color("#1a1c2c"))
