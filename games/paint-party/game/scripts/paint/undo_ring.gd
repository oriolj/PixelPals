extends RefCounted
## A ring of the last CAPACITY canvas snapshots (Images, or any value in tests).
## push() adds the newest and drops the oldest when full; pop() takes the newest.

const CAPACITY := 10

var items: Array = []


func push(item) -> void:
	items.append(item)
	while items.size() > CAPACITY:
		items.pop_front()


func pop():
	return items.pop_back() if not items.is_empty() else null


func size() -> int:
	return items.size()


func clear() -> void:
	items.clear()
