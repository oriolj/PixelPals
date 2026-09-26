extends RefCounted
## Trip rules as pure static functions and constants (unit tested). No game over, ever.

## World scroll (px/s) with a full or part-full tank.
const BASE_SCROLL := 36.0
## An empty tank only slows the scroll to this fraction; it never stops.
const EMPTY_FACTOR := 0.7
## Extra scroll while the booster burns.
const BOOST_SCROLL := 70.0
const BOOST_SECONDS := 1.0
const BOOST_COOLDOWN := 1.2

## Tank drain per second, and what each pickup refills (tank is 0..1).
const DRAIN := 0.022
const FUEL_REFILL := 0.3
const BALLOON_REFILL := 0.15
const SPARKLE_REFILL := 0.04

## A bump: how many cans fall out, and the blinking invulnerability.
const BUMP_DROP := 2
const INVULN_SECONDS := 1.5
const WOBBLE_SECONDS := 0.8

## Landing: tries before the pad slides under the rocket.
const LANDING_TRIES := 3
## Half-width of the pad zone that counts as on the pad.
const PAD_HALF := 22.0


static func scroll_speed(tank: float, boosting: bool) -> float:
	var s := BASE_SCROLL * (EMPTY_FACTOR if tank <= 0.0 else 1.0)
	if boosting:
		s += BOOST_SCROLL
	return s


static func on_pad(rocket_x: float, pad_x: float) -> bool:
	return absf(rocket_x - pad_x) <= PAD_HALF


## Cans a bump drops: two, or fewer when the count is lower (never negative).
static func bump_drop(count: int) -> int:
	return mini(BUMP_DROP, maxi(count, 0))


## Overlap of two centred rectangles.
static func overlap(a_pos: Vector2, a_size: Vector2, b_pos: Vector2, b_size: Vector2) -> bool:
	return absf(a_pos.x - b_pos.x) * 2.0 < a_size.x + b_size.x \
		and absf(a_pos.y - b_pos.y) * 2.0 < a_size.y + b_size.y
