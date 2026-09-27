extends RefCounted
## The countryside trail, node-free: six fields (meadow, farm, woods, stream,
## hill, lake), a gate at the end of each of the first five, the mare's
## obstacles, the foal's lanes of apples, wildflowers and lucky horseshoes,
## the animals that answer a neigh, the puddles, the weather and the wild
## herd. Built from a seed and a length scale, so it is the same every time.

const FULL_LENGTH := 10800.0
const SECTIONS: Array[String] = ["meadow", "farm", "woods", "stream", "hill", "lake"]
const GATE_REACH := 44.0        # the mare waits this close to a closed gate
const GATE_STOP := 22.0         # ... and stops this far before it
const GATE_AUTO := 5.0          # it opens by itself after this wait (toddler seated)
const GATE_AUTO_NO_TODDLER := 1.0
const NEIGH_REACH := 110.0      # a neigh opens a gate this close
const ANIMAL_REACH := 190.0     # a neigh wakes the nearest animal this close
const REACT_TIME := 1.6
const HERD_TIME := 12.0
const HERD_AUTO := 5.0
const GRAB_REACH := 10.0
const HOP_GRAB_REACH := 15.0

var length := FULL_LENGTH
var obstacles: Array[Dictionary] = []   # {x, w, kind, done, clean}
var items: Array[Dictionary] = []       # {x, lane, kind, taken, needs_hop, want}
var twigs: Array[Dictionary] = []       # {x, lane, hopped}
var gates: Array[Dictionary] = []       # {x, state 0 closed / 1 opening / 2 open, wait, t, by}
var animals: Array[Dictionary] = []     # {x, kind, react, reacts}
var puddles: Array[float] = []
var props: Array[Dictionary] = []       # {x, kind} scenery (trees, barn, bushes, reeds)
var herd_x := 0.0
var herd_t := -1.0                      # < 0 = not started
var herd_answered := false
var rainbow_t := -1.0
var rng := RandomNumberGenerator.new()


func _init(scale := 1.0, seed_ := 7) -> void:
	length = maxf(1200.0, FULL_LENGTH * scale)
	rng.seed = seed_
	build()


func section_bounds(i: int) -> Vector2:
	var n := SECTIONS.size()
	return Vector2(length * i / n, length * (i + 1) / n)


func section_at(x: float) -> String:
	var i := clampi(int(x / length * SECTIONS.size()), 0, SECTIONS.size() - 1)
	return SECTIONS[i]


func progress(x: float) -> float:
	return clampf(x / length, 0.0, 1.0)


func build() -> void:
	obstacles.clear()
	items.clear()
	twigs.clear()
	gates.clear()
	animals.clear()
	puddles.clear()
	props.clear()
	var start := 160.0
	for i in SECTIONS.size():
		var b := section_bounds(i)
		var a := maxf(b.x, start)
		var e := b.y
		if i < SECTIONS.size() - 1:
			gates.append({"x": e - 30.0, "state": 0, "wait": 0.0, "t": 0.0, "by": ""})
		_obstacles(i, a + 90.0, e - 110.0)
		_items(i, a + 40.0, e - 70.0)
		_twigs(a + 150.0, e - 120.0)
		_animals(i, a, e)
		_props(i, b.x, e)
	# The rain's puddles (woods to stream), on the path.
	var x := length * 0.40
	while x < length * 0.60:
		if not _near_obstacle(x, 36.0) and not _near_gate(x, 60.0):
			puddles.append(x)
		x += rng.randf_range(90.0, 150.0)
	herd_x = length * 0.66
	# Two rare lucky horseshoes (woods and hill).
	for f in [0.42, 0.70]:
		var lx: float = length * f
		items.append({"x": lx, "lane": 2, "kind": "lucky_horseshoe", "taken": false, "needs_hop": true, "want": true})


func _near_obstacle(x: float, gap: float) -> bool:
	for ob in obstacles:
		if x > float(ob.x) - gap and x < float(ob.x) + float(ob.w) + gap:
			return true
	return false


func _near_gate(x: float, gap: float) -> bool:
	for g in gates:
		if absf(float(g.x) - x) < gap:
			return true
	return false


func _obstacles(i: int, a: float, e: float) -> void:
	var kinds: Array = [["log", "hay_bale"], ["hay_bale", "log"], ["log", "log"], ["stream", "log"],
		["hay_bale", "log"], ["log", "hay_bale"]][i]
	var n := 3
	var span := e - a
	if span < 120.0:
		return
	n = clampi(int(span / 220.0), 1, 3)
	for k in n:
		var kind: String = kinds[k % kinds.size()]
		var ox := a + span * (k + 0.5) / n + rng.randf_range(-20.0, 20.0)
		var w: float = {"log": 20.0, "hay_bale": 16.0, "stream": 32.0}[kind]
		obstacles.append({"x": ox, "w": w, "kind": kind, "done": false, "clean": false})


func _items(i: int, a: float, e: float) -> void:
	var x := a
	var flower_kinds := ["flower_pink", "flower_blue", "flower_yellow"]
	while x < e:
		var lane := rng.randi_range(0, 2)
		var roll := rng.randf()
		if roll < 0.55:
			items.append({"x": x, "lane": lane, "kind": "apple", "taken": false, "needs_hop": true, "want": true})
		else:
			items.append({"x": x, "lane": lane, "kind": flower_kinds[rng.randi() % 3], "taken": false,
				"needs_hop": false, "want": true})
		# Now and then a little row of three in one lane.
		if rng.randf() < 0.25:
			for k in 2:
				x += 18.0
				items.append({"x": x, "lane": lane, "kind": "apple", "taken": false, "needs_hop": true, "want": true})
		x += rng.randf_range(55.0, 95.0)


func _twigs(a: float, e: float) -> void:
	var x := a
	while x < e:
		twigs.append({"x": x, "lane": rng.randi_range(0, 2), "hopped": false})
		x += rng.randf_range(320.0, 520.0)


func _animals(i: int, a: float, e: float) -> void:
	var kinds: Array = [["rabbit", "sheep", "bird", "rabbit"], ["cow", "sheep", "sheep", "rabbit"],
		["bird", "rabbit", "bird"], ["duck", "bird", "duck"], ["sheep", "rabbit", "bird"],
		["duck", "duck", "cow", "duck", "bird"]][i]
	var span := e - a
	for k in kinds.size():
		var ax := a + span * (k + 0.6) / kinds.size()
		animals.append({"x": ax, "kind": kinds[k], "react": -1.0, "reacts": 0, "depth": k % 2})


func _props(i: int, a: float, e: float) -> void:
	var x := a + rng.randf_range(20.0, 60.0)
	var pool: Array = [["bush", "tree", "bush"], ["barn", "bush", "tree"], ["tree", "tree", "bush"],
		["reeds", "tree", "reeds"], ["bush", "tree"], ["reeds", "bush", "reeds"]][i]
	var first := true
	while x < e - 40.0:
		var kind: String = pool[rng.randi() % pool.size()]
		if i == 1 and first:
			kind = "barn"
		first = false
		props.append({"x": x, "kind": kind})
		x += rng.randf_range(110.0, 190.0) if kind != "barn" else 220.0


# ---------------------------------------------------------------- queries

## The first gate that is not open yet (ahead of or at x).
func gate_ahead(x: float) -> Dictionary:
	for g in gates:
		if int(g.state) < 2 and float(g.x) > x - 8.0:
			return g
	return {}


## Where the mare must stop (INF when no closed gate is near).
func stop_x_for(x: float) -> float:
	var g := gate_ahead(x)
	if g.is_empty():
		return INF
	return float(g.x) - GATE_STOP


func nearest_animal(x: float) -> int:
	var best := -1
	var best_d := ANIMAL_REACH
	for i in animals.size():
		var d := absf(float(animals[i].x) - x)
		if d <= best_d:
			best_d = d
			best = i
	return best


## Items the foal grabs this frame (marks them taken).
func grab(foal_x: float, lane: int, hop_h: float) -> Array[Dictionary]:
	var got: Array[Dictionary] = []
	for it in items:
		if it.taken or int(it.lane) != lane:
			continue
		var d := absf(float(it.x) - foal_x)
		if it.needs_hop:
			if hop_h >= 3.0 and d <= HOP_GRAB_REACH:
				it.taken = true
				got.append(it)
		elif d <= GRAB_REACH:
			it.taken = true
			got.append(it)
	return got


## A twig log right ahead of the foal in its lane (it hops those by itself).
func twig_ahead(foal_x: float, lane: int) -> Dictionary:
	for tw in twigs:
		if tw.hopped or int(tw.lane) != lane:
			continue
		var d := float(tw.x) - foal_x
		if d > 0.0 and d < 14.0:
			return tw
	return {}


func puddle_at(x: float) -> bool:
	for p in puddles:
		if absf(p - x) < 8.0:
			return true
	return false


# ---------------------------------------------------------------- the neigh and the gates

## A neigh at mare x: opens a close gate, wakes the nearest animal, answers the
## herd. Returns what happened: {"gate": bool, "animal": index or -1, "herd": bool}.
func neigh(x: float) -> Dictionary:
	var out := {"gate": false, "animal": -1, "herd": false}
	var g := gate_ahead(x)
	if not g.is_empty() and int(g.state) == 0 and float(g.x) - x <= NEIGH_REACH:
		open_gate(g, "neigh")
		out.gate = true
	var a := nearest_animal(x)
	if a != -1:
		animals[a].react = 0.0
		animals[a].reacts = int(animals[a].reacts) + 1
		out.animal = a
	if herd_running() and not herd_answered:
		answer_herd()
		out.herd = true
	return out


func open_gate(g: Dictionary, by: String) -> void:
	if int(g.state) != 0:
		return
	g.state = 1
	g.t = 0.0
	g.by = by


## Per-frame gate and animal clocks. Returns events ("gate_open", "herd_start", "rainbow").
func update(mare_x: float, dt: float, toddler: bool) -> Array[String]:
	var ev: Array[String] = []
	for g in gates:
		match int(g.state):
			0:
				if float(g.x) - mare_x <= GATE_REACH:
					g.wait = float(g.wait) + dt
					if float(g.wait) >= (GATE_AUTO if toddler else GATE_AUTO_NO_TODDLER):
						open_gate(g, "auto")
			1:
				g.t = float(g.t) + dt
				if float(g.t) >= 0.5:
					g.state = 2
		if int(g.state) >= 1 and not g.get("told", false):
			g["told"] = true
			ev.append("gate_open")
	for an in animals:
		if float(an.react) >= 0.0:
			an.react = float(an.react) + dt
			if float(an.react) >= REACT_TIME:
				an.react = -1.0
	if herd_t < 0.0 and mare_x >= herd_x:
		herd_t = 0.0
		ev.append("herd_start")
	elif herd_t >= 0.0:
		herd_t += dt
		if not herd_answered and herd_t >= HERD_AUTO and herd_t < HERD_TIME:
			answer_herd()
			ev.append("rainbow")
	if rainbow_t >= 0.0:
		rainbow_t += dt
	return ev


func herd_running() -> bool:
	return herd_t >= 0.0 and herd_t < HERD_TIME


func answer_herd() -> void:
	herd_answered = true
	if rainbow_t < 0.0:
		rainbow_t = 0.0


func gate_frame(g: Dictionary) -> int:
	match int(g.state):
		0: return 0
		1: return 1 if float(g.t) < 0.25 else 2
	return 2


# ---------------------------------------------------------------- weather

## {"a": sky, "b": sky, "mix": 0..1 (b over a), "rain": 0..1} at progress p.
static func weather(p: float) -> Dictionary:
	var keys := [[0.0, "sky_morning"], [0.34, "sky_morning"], [0.39, "sky_rain"], [0.57, "sky_rain"],
		[0.63, "sky_afternoon"], [0.80, "sky_afternoon"], [0.9, "sky_golden"], [1.0, "sky_golden"]]
	var a: String = keys[0][1]
	var b: String = a
	var mix := 0.0
	for i in keys.size() - 1:
		var k0: Array = keys[i]
		var k1: Array = keys[i + 1]
		if p >= float(k0[0]) and p <= float(k1[0]):
			a = k0[1]
			b = k1[1]
			var span := float(k1[0]) - float(k0[0])
			mix = 0.0 if span <= 0.0 or a == b else (p - float(k0[0])) / span
			break
	if p > 1.0:
		a = "sky_golden"
		b = a
	var rain := 0.0
	if p > 0.37 and p < 0.61:
		rain = clampf(minf((p - 0.37) / 0.03, (0.61 - p) / 0.03), 0.0, 1.0)
	return {"a": a, "b": b, "mix": mix, "rain": rain}
