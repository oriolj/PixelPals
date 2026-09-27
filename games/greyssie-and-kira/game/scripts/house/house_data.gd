extends RefCounted
## The house, read from data/house.json (see CLAUDE.md "Making it our real
## house and cats"). Pure data plus the room graph; no nodes.
##
## World coordinates: every floor is a horizontal band BAND_H px tall,
## stacked with the top floor at y = 0. Inside a band the wall runs from
## CEIL_Y to FLOOR_Y, the feet line. Rooms sit left to right from x = 0;
## a thing's "x" in the JSON is relative to its room's left wall and is
## turned into a world x here. "y" in the JSON is a height above the floor.
##
## The graph: rooms are nodes; neighbours on a floor are joined by a doorway,
## and the "stairs" pairs join stairs rooms on adjacent floors.

const BAND_H := 180
const CEIL_Y := 24
const FLOOR_Y := 152

## [{"id", "rooms": [room ids left to right], "width"}], index 0 = ground.
var floors: Array = []
## id -> {"id", "floor", "index", "x0", "w", "kind", "wall", "floor_tile",
##        "window": {x, y} or {}, "sunny": [world x], "furniture": [{kind, x, y, cup}], "spots": [ids]}
var rooms := {}
## id -> {"id", "kind", "room", "floor", "x", "y", "high", "tags", "tell", "sprite", "cosy"}
var spots := {}
var spot_order: Array[String] = []
## [[stairs room a, stairs room b]]
var stairs: Array = []
## {"room", "floor", "x"}
var bowls := {}
## {"room", "floor", "x"}
var start := {}
var spot_kinds := {}
var errors: Array[String] = []


static func from_file(path: String) -> RefCounted:
	var h = load("res://scripts/house/house_data.gd").new()
	if not FileAccess.file_exists(path):
		h.errors.append("missing %s" % path)
		return h
	var d = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (d is Dictionary):
		h.errors.append("%s is not a JSON object" % path)
		return h
	h.parse(d)
	return h


func parse(d: Dictionary) -> bool:
	spot_kinds = {}
	for k in d.get("spot_kinds", {}):
		if not str(k).begins_with("_"):
			spot_kinds[k] = d.spot_kinds[k]
	var fl: Array = d.get("floors", [])
	if fl.is_empty():
		errors.append("no floors")
		return false
	for fi in fl.size():
		var f: Dictionary = fl[fi]
		var ids: Array[String] = []
		var x0 := 0
		var room_list: Array = f.get("rooms", [])
		for ri in room_list.size():
			var r: Dictionary = room_list[ri]
			var rid := str(r.get("id", ""))
			if rid == "" or rooms.has(rid):
				errors.append("room %d on floor %d: missing or duplicate id '%s'" % [ri, fi, rid])
				continue
			var w := int(r.get("w", 96))
			var room := {
				"id": rid, "floor": fi, "index": ri, "x0": x0, "w": w,
				"kind": str(r.get("kind", "room")),
				"wall": str(r.get("wall", "wall_yellow_dots")),
				"floor_tile": str(r.get("floor", "floor_wood")),
				"window": {}, "sunny": [], "furniture": [], "spots": [],
			}
			var win = r.get("window", null)
			if win is Dictionary:
				room.window = {"x": x0 + int(win.get("x", w / 2)), "y": int(win.get("y", 52))}
			for sx in r.get("sunny", []):
				room.sunny.append(x0 + int(sx))
			for fu in r.get("furniture", []):
				room.furniture.append({"kind": str(fu.get("kind", "")), "x": x0 + int(fu.get("x", 0)),
					"y": int(fu.get("y", 0)), "cup": bool(fu.get("cup", false))})
			for s in r.get("spots", []):
				var sid := str(s.get("id", ""))
				var kind := str(s.get("kind", ""))
				if sid == "" or spots.has(sid):
					errors.append("room %s: missing or duplicate spot id '%s'" % [rid, sid])
					continue
				if not spot_kinds.has(kind):
					errors.append("spot %s: unknown kind '%s'" % [sid, kind])
					continue
				var k: Dictionary = spot_kinds[kind]
				var tags: Array = k.get("tags", [])
				spots[sid] = {
					"id": sid, "kind": kind, "room": rid, "floor": fi,
					"x": x0 + int(s.get("x", w / 2)), "y": int(s.get("y", 0)),
					"high": bool(k.get("high", false)), "tags": tags,
					"tell": str(k.get("tell", "tail")), "sprite": str(k.get("sprite", kind)),
					"tell_at": k.get("tell_at", []), "cosy": tags.has("cosy"),
				}
				spot_order.append(sid)
				room.spots.append(sid)
			rooms[rid] = room
			ids.append(rid)
			x0 += w
		floors.append({"id": str(f.get("id", "floor%d" % fi)), "rooms": ids, "width": x0})
	for pair in d.get("stairs", []):
		if not (pair is Array) or pair.size() != 2 or not rooms.has(pair[0]) or not rooms.has(pair[1]):
			errors.append("bad stairs pair %s" % str(pair))
			continue
		if absi(int(rooms[pair[0]].floor) - int(rooms[pair[1]].floor)) != 1:
			errors.append("stairs %s must join adjacent floors" % str(pair))
			continue
		stairs.append([str(pair[0]), str(pair[1])])
	bowls = _place(d.get("bowls", {}), "bowls")
	start = _place(d.get("start", {}), "start")
	if spots.size() < 2:
		errors.append("the house needs at least 2 hiding spots")
	return errors.is_empty()


func _place(p, what: String) -> Dictionary:
	var rid := str(p.get("room", "")) if p is Dictionary else ""
	if not rooms.has(rid):
		errors.append("%s: unknown room '%s'" % [what, rid])
		rid = floors[0].rooms[0] if not floors.is_empty() and not floors[0].rooms.is_empty() else ""
		if rid == "":
			return {"room": "", "floor": 0, "x": 0}
	var r: Dictionary = rooms[rid]
	var x: int = int(p.get("x", r.w / 2)) if p is Dictionary else int(r.w / 2)
	return {"room": rid, "floor": r.floor, "x": r.x0 + x}


# ---------------------------------------------------------------- geometry

func floor_count() -> int:
	return floors.size()


func band_top(floor_i: int) -> int:
	return (floors.size() - 1 - floor_i) * BAND_H


## World y of the feet line of a floor.
func floor_y(floor_i: int) -> int:
	return band_top(floor_i) + FLOOR_Y


func width(floor_i: int) -> int:
	return int(floors[floor_i].width)


## The room on a floor that contains world x (clamped to the ends).
func room_at(floor_i: int, x: float) -> String:
	var ids: Array = floors[floor_i].rooms
	for rid in ids:
		var r: Dictionary = rooms[rid]
		if x < r.x0 + r.w:
			return rid
	return ids[ids.size() - 1]


func room_center(rid: String) -> float:
	var r: Dictionary = rooms[rid]
	return r.x0 + r.w / 2.0


func is_stairs(rid: String) -> bool:
	return rooms.has(rid) and rooms[rid].kind == "stairs"


## The stairs room on the floor above (dir = 1) or below (dir = -1) that
## `rid` connects to, or "".
func stair_link(rid: String, dir: int) -> String:
	for pair in stairs:
		for k in 2:
			if pair[k] == rid:
				var other: String = pair[1 - k]
				if int(rooms[other].floor) == int(rooms[rid].floor) + dir:
					return other
	return ""


# ---------------------------------------------------------------- graph

func neighbours(rid: String) -> Array[String]:
	var out: Array[String] = []
	var r: Dictionary = rooms[rid]
	var ids: Array = floors[r.floor].rooms
	var i: int = r.index
	if i > 0:
		out.append(ids[i - 1])
	if i < ids.size() - 1:
		out.append(ids[i + 1])
	for d in [1, -1]:
		var s := stair_link(rid, d)
		if s != "":
			out.append(s)
	return out


## Rooms from a to b inclusive (breadth first), or [] if unreachable.
func path_rooms(a: String, b: String) -> Array[String]:
	var prev := {a: ""}
	var queue: Array[String] = [a]
	while not queue.is_empty():
		var cur: String = queue.pop_front()
		if cur == b:
			break
		for n in neighbours(cur):
			if not prev.has(n):
				prev[n] = cur
				queue.append(n)
	if not prev.has(b):
		return []
	var out: Array[String] = []
	var c := b
	while c != "":
		out.push_front(c)
		c = prev[c]
	return out


func hops(a: String, b: String) -> int:
	var p := path_rooms(a, b)
	return p.size() - 1 if not p.is_empty() else 999


## True when every room can reach every other room.
func connected() -> bool:
	if rooms.is_empty():
		return false
	var first: String = rooms.keys()[0]
	for rid in rooms:
		if path_rooms(first, rid).is_empty():
			return false
	return true


## A distance for "nearest": room hops first, then pixels.
func distance(floor_a: int, xa: float, floor_b: int, xb: float) -> float:
	var ra := room_at(floor_a, xa)
	var rb := room_at(floor_b, xb)
	var h := hops(ra, rb)
	if floor_a == floor_b and h <= 1:
		return absf(xa - xb)
	return h * 1000.0 + absf(xa - xb)
