extends RefCounted
## The carousel's logic, with no nodes: which card is selected and where each
## card sits. It wraps both ways (right from the last card is the first).
##
## `target` is an unbounded float that moves by whole steps; `scroll` eases
## toward it every frame, so quick repeated presses stay smooth. A card's
## on-screen offset is its wrapped distance from `scroll`, in cards.

var count := 0
var target := 0.0
var scroll := 0.0

const EASE := 11.0


func _init(n := 0) -> void:
	count = n


func index() -> int:
	return posmod(roundi(target), count) if count > 0 else 0


func step(dir: int) -> int:
	if count > 0:
		target += dir
	return index()


## Jump to card i (no animation), e.g. to restore the selection.
func select(i: int) -> void:
	if count <= 0:
		return
	target = float(posmod(i, count))
	scroll = target


func update(delta: float) -> void:
	scroll = lerpf(scroll, target, 1.0 - exp(-EASE * delta))
	if absf(scroll - target) < 0.001:
		scroll = target


## Wrapped offset of card i from the scroll position, in [-count/2, count/2).
func offset(i: int) -> float:
	if count <= 0:
		return 0.0
	var o := fposmod(float(i) - scroll + count / 2.0, float(count)) - count / 2.0
	return o
