extends RefCounted
## The rosette wall: every day's rosettes, pinned next to the earlier days',
## and the lucky horseshoes that hang over the stable door. Persisted with
## scripts/save.gd (versioned JSON in user://). It holds no personal data.
##
## data = {"days": [["blue", "red", ...], ...], "horseshoes": n}
## The wall keeps the most recent MAX_DAYS days (the oldest fall off).

const Save := preload("res://scripts/save.gd")
const VERSION := 1
const MAX_DAYS := 12
const MAX_ROSETTES_PER_DAY := 6

var path := ""
var data := {}


func _init(file_path := "") -> void:
	path = file_path
	data = empty()


static func empty() -> Dictionary:
	return {"days": [], "horseshoes": 0}


func load_file() -> void:
	data = Save.load_json(path, VERSION, empty()) if path != "" else empty()
	if not (data.get("days") is Array):
		data["days"] = []
	data["horseshoes"] = int(data.get("horseshoes", 0))


func save() -> bool:
	return Save.save_json(path, VERSION, data) if path != "" else false


## Pins a day's rosettes (colour names) and adds its lucky horseshoes.
func add_day(colours: Array, horseshoes := 0) -> void:
	var day: Array = []
	for c in colours:
		if day.size() < MAX_ROSETTES_PER_DAY:
			day.append(str(c))
	data.days.append(day)
	while data.days.size() > MAX_DAYS:
		data.days.pop_front()
	data.horseshoes = int(data.horseshoes) + maxi(0, horseshoes)


func days() -> Array:
	return data.days


func day_count() -> int:
	return data.days.size()


func horseshoes() -> int:
	return int(data.horseshoes)


## Parent reset (and the demo): empties the wall and its file.
func reset() -> void:
	data = empty()
	if path != "":
		Save.remove(path)
