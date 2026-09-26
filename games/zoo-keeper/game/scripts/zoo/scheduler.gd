extends RefCounted
## Hunger scheduler: the order in which animals get hungry.
##
## Two rounds; in each round every animal gets hungry once (so every animal
## eats twice, 12 meals). The order is shuffled, and no food is asked three
## times in a row across the whole run. `first` pins the start of the order
## (the demo needs the monkey and the penguin first).

const Rules := preload("res://scripts/zoo/rules.gd")

var order: Array[String] = []
var _next := 0


func build(rng: RandomNumberGenerator, first: Array[String] = []) -> Array[String]:
	for _attempt in 200:
		order.clear()
		for round_i in Rules.MEALS_PER_ANIMAL:
			var bag: Array[String] = []
			bag.assign(Rules.ANIMALS)
			if round_i == 0:
				for f in first:
					if bag.has(f):
						bag.erase(f)
						order.append(f)
			_shuffle(bag, rng)
			order.append_array(bag)
		if is_valid(order):
			break
	_next = 0
	return order


static func is_valid(seq: Array[String]) -> bool:
	var counts := {}
	for a in seq:
		counts[a] = counts.get(a, 0) + 1
	for a in Rules.ANIMALS:
		if counts.get(a, 0) != Rules.MEALS_PER_ANIMAL:
			return false
	for i in range(2, seq.size()):
		var f := Rules.right_food(seq[i])
		if f == Rules.right_food(seq[i - 1]) and f == Rules.right_food(seq[i - 2]):
			return false
	# Each round holds every animal once, so a round's meals are all different animals.
	for r in Rules.MEALS_PER_ANIMAL:
		var seen := {}
		for i in range(r * Rules.ANIMALS.size(), (r + 1) * Rules.ANIMALS.size()):
			if seen.has(seq[i]):
				return false
			seen[seq[i]] = true
	return true


func has_next() -> bool:
	return _next < order.size()


func peek() -> String:
	return order[_next] if has_next() else ""


func take() -> String:
	if not has_next():
		return ""
	_next += 1
	return order[_next - 1]


## How many animals have been handed out so far.
func taken() -> int:
	return _next


static func _shuffle(arr: Array[String], rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
