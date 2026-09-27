extends RefCounted
## Where the cats hide each round (pure, tested).
##
## Each spot's weight for a cat = 1 + the sum of the cat's likes over the
## spot's tags, x3 when the spot kind is one of its favourites, x4 for cosy
## spots at night (sleepy cats). The spot a cat used last round is avoided
## when there is any other choice, and two cats never share a spot.

const FAVOURITE_BONUS := 3.0
const NIGHT_COSY_BONUS := 4.0


static func weight(cat: Dictionary, spot: Dictionary, night: bool) -> float:
	var w := 1.0
	var likes: Dictionary = cat.get("likes", {})
	for tag in spot.tags:
		w += float(likes.get(tag, 0.0))
	if cat.get("favourite_spots", []).has(spot.kind):
		w *= FAVOURITE_BONUS
	if night and spot.cosy:
		w *= NIGHT_COSY_BONUS
	return w


## Returns {cat id: spot id}. `last` is last round's {cat id: spot id}.
static func choose(house: RefCounted, cats: Array, night: bool, rng: RandomNumberGenerator,
		last := {}) -> Dictionary:
	var out := {}
	var taken := {}
	for cat in cats:
		var ids: Array[String] = []
		var ws: Array[float] = []
		for sid in house.spot_order:
			if taken.has(sid):
				continue
			if last.get(cat.id, "") == sid and house.spots.size() > cats.size() + 1:
				continue
			ids.append(sid)
			ws.append(weight(cat, house.spots[sid], night))
		if ids.is_empty():
			continue
		var total := 0.0
		for w in ws:
			total += w
		var pick := rng.randf() * total
		var chosen := ids[ids.size() - 1]
		for i in ids.size():
			pick -= ws[i]
			if pick <= 0.0:
				chosen = ids[i]
				break
		out[cat.id] = chosen
		taken[chosen] = true
	return out
