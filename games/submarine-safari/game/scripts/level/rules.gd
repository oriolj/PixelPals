extends RefCounted
## Run rules: length, the end condition, the pearl trail's target and the
## bonus subject an empty snap photographs. Pure static functions.

const Species := preload("res://scripts/level/species.gd")

const RUN_SECONDS := 360.0        # 6 minutes
const PEARL_AFTER := 40.0         # seconds without a new photo
const WHALE_AT := 0.2             # fraction of the run when the whale may come
const WHALE_LATEST := 0.8         # after this it comes wherever the sub is


static func run_length(override: float) -> float:
	return override if override > 0.0 else RUN_SECONDS


## The run ends at its length, or when all 12 species were photographed this run.
static func should_end(time: float, run_len: float, seen_this_run: int) -> bool:
	return time >= run_len or seen_this_run >= Species.PAGE.size()


## The species the pearl trail leads to: the nearest home of a page species
## not photographed this run ("" when all are).
static func trail_target(sub_pos: Vector2, homes: Dictionary, seen: Array) -> String:
	var best := ""
	var best_d := INF
	for id in Species.PAGE:
		if seen.has(id) or not homes.has(id):
			continue
		var d: float = sub_pos.distance_to(homes[id])
		if d < best_d:
			best_d = d
			best = id
	return best


## What an empty snap photographs: a smiling rock by the rocks, a shell or a
## starfish over sand (alternating), else a bubble. Never "nothing".
static func bonus_subject(near_rock: bool, near_sand: bool, n: int) -> String:
	if near_sand:
		return "shell" if n % 2 == 0 else "starfish"
	if near_rock:
		return "rock_smile"
	return "bubble"


## Should the whale start its pass now?
static func whale_due(time: float, run_len: float, sub_y: float) -> bool:
	if time < run_len * WHALE_AT:
		return false
	return sub_y < 176.0 or time >= run_len * WHALE_LATEST
