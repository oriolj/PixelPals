extends RefCounted
## Autosave clock: every INTERVAL seconds of painting time, if the canvas
## changed since the last save, tick() says "save now".

const INTERVAL := 30.0

var elapsed := 0.0
var dirty := false
var saves := 0


func mark_dirty() -> void:
	dirty = true


## Advance the clock; true when a save is due (the caller saves the PNG).
func tick(dt: float) -> bool:
	elapsed += dt
	if elapsed < INTERVAL:
		return false
	elapsed -= INTERVAL
	if not dirty:
		return false
	dirty = false
	saves += 1
	return true
