extends RefCounted
## The spawn timeline: per stage, a list of events from res://data/timeline.json
## (a data file, not code), expanded into time-sorted spawns.
##
## An event is either a single spawn {"at": s, "kind": k, ...} or a series
## {"from": s, "to": s, "every": s, "kind": k, ...}. Optional fields: "x"
## (a number, or omitted for a seeded random column) and "planet" (1..8).
## `scale` multiplies every time (the demo's short trip); a series never gets
## denser than MIN_EVERY_SCALE of its real spacing, so a short trip is not a
## blizzard.

const PATH := "res://data/timeline.json"
const MIN_EVERY_SCALE := 0.4
const X_MIN := 24.0
const X_MAX := 296.0


static func load_data(path := PATH) -> Dictionary:
	var data = JSON.parse_string(FileAccess.get_file_as_string(path))
	return data if data is Dictionary else {}


## Stage length in seconds (already scaled).
static func stage_length(data: Dictionary, stage: String, scale := 1.0) -> float:
	return float(data.get(stage, {}).get("length", 60.0)) * scale


## Sorted spawns [{t, kind, x, planet}] for one stage.
static func expand(data: Dictionary, stage: String, scale := 1.0, seed := 1) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var out: Array[Dictionary] = []
	var events: Array = data.get(stage, {}).get("events", [])
	for e in events:
		var times: Array[float] = []
		if e.has("at"):
			times.append(float(e.at) * scale)
		else:
			var every := float(e.get("every", 5.0)) * maxf(scale, MIN_EVERY_SCALE)
			var t := float(e.get("from", 0.0)) * scale
			var stop := float(e.get("to", 0.0)) * scale
			while t <= stop + 0.0001:
				times.append(t)
				t += every
		for t in times:
			var x := float(e.x) if e.has("x") else roundf(rng.randf_range(X_MIN, X_MAX))
			out.append({"t": t, "kind": str(e.kind), "x": x, "planet": int(e.get("planet", 0))})
	out.sort_custom(func(a, b): return a.t < b.t)
	return out
