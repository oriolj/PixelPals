extends RefCounted
## The zoo's fixed rules: which animal eats what, the wheel's directions, the
## hint ladder, run length and pacing. Pure data and functions (tested).

const ANIMALS: Array[String] = ["monkey", "penguin", "giraffe", "rabbit", "elephant", "seal"]
const FOODS: Array[String] = ["banana", "fish", "carrot", "hay"]

## Each animal has exactly one right food; two animals per food keeps the
## four-food wheel honest (the giraffe's leaves are drawn into the hay).
const RIGHT_FOOD := {
	"monkey": "banana",
	"penguin": "fish",
	"seal": "fish",
	"rabbit": "carrot",
	"elephant": "hay",
	"giraffe": "hay",
}

## The cross-shaped wheel: up banana, right fish, down carrot, left hay.
const WHEEL := {
	Vector2i.UP: "banana",
	Vector2i.RIGHT: "fish",
	Vector2i.DOWN: "carrot",
	Vector2i.LEFT: "hay",
}

## Hint ladder, by wrong tries so far for the current hunger.
enum Hint { NONE, WIGGLE, GLOW }
## The throw after this many wrong tries always succeeds.
const ALWAYS_SUCCEEDS_AFTER := 2

const MEALS_PER_ANIMAL := 2
const TOTAL_MEALS := 12            # ANIMALS.size() * MEALS_PER_ANIMAL
const ROUND_MEALS := 6             # a "feeding done" moment after each round
const RUN_SECONDS := 420.0         # 7 minutes: the keeper rings the bell
const MAX_HUNGRY := 2              # one or two hungry at a time

# Pacing (balance, M3).
const FIRST_HUNGER := 1.2          # seconds before the first pair gets hungry
const HUNGER_GAP := 2.5            # after a meal, before the next animal gets hungry
const ROUND_BREAK := 4.0           # the "feeding done" dance between rounds
const FINISH_SECONDS := 4.5        # the end dance before the party
const SINGER_COOLDOWN := 0.8
const IDLE_CALL_MIN := 7.0         # no singer: an idle animal calls out now and then
const IDLE_CALL_MAX := 11.0

const MUSIC_BPM := 100.0
const BEAT := 60.0 / MUSIC_BPM


static func right_food(animal: String) -> String:
	return RIGHT_FOOD.get(animal, "")


static func accepts(animal: String, food: String) -> bool:
	return RIGHT_FOOD.get(animal, "") == food


static func food_for_dir(dir: Vector2i) -> String:
	return WHEEL.get(dir, "")


static func dir_for_food(food: String) -> Vector2i:
	for d in WHEEL:
		if WHEEL[d] == food:
			return d
	return Vector2i.ZERO


static func hint_for(wrong_tries: int) -> int:
	if wrong_tries <= 0:
		return Hint.NONE
	if wrong_tries == 1:
		return Hint.WIGGLE
	return Hint.GLOW


## True when a throw of `food` counts as the right one for this animal,
## given how many wrong tries it already had (the third try always works).
static func throw_succeeds(animal: String, food: String, wrong_tries: int) -> bool:
	return accepts(animal, food) or wrong_tries >= ALWAYS_SUCCEEDS_AFTER


static func run_length(override_seconds: float) -> float:
	return override_seconds if override_seconds > 0.0 else RUN_SECONDS
