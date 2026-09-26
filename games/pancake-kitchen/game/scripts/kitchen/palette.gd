extends RefCounted
## Pancake Kitchen colours (PLAN.md "Art direction"). Warm kitchen, thick
## dark outlines, one colour per topping.

const WALL := Color("#fff1d6")
const WALL_DEEP := Color("#fbe3bd")
const TILES := Color("#f6c89f")
const TILE_LINE := Color("#eab287")
const COUNTER := Color("#9b5e3c")
const COUNTER_TOP := Color("#c47f52")
const COUNTER_DARK := Color("#7a4529")
const PAN := Color("#3a3a4a")
const PAN_SHINE := Color("#5b5b70")
const BATTER := Color("#fbe7a8")
const GOLDEN := Color("#e8a13a")
const GOLDEN_EDGE := Color("#c9812a")
const OUTLINE := Color("#2b2438")
const STRAWBERRY := Color("#e8435a")
const CHOCOLATE := Color("#5a3525")
const BANANA := Color("#ffe066")
const CREAM := Color("#ffffff")
const PLATE := Color("#ffffff")
const PLATE_RIM := Color("#cfe6f5")
const STOVE := Color("#dfe4ea")
const STOVE_DARK := Color("#aab3bf")
const FLAME := Color("#5fb8ff")
const FLAME_HOT := Color("#ffb347")
const WINDOW_SKY := Color("#aee3ff")
const WINDOW_FRAME := Color("#6fb3d9")
const LEAF := Color("#6cc36c")
const PINK := Color("#ff9fb6")
const WHITE := Color("#ffffff")
const SHADOW := Color(0.17, 0.14, 0.22, 0.18)
const GLOW := Color("#fff27a")

const TOPPING_COLORS := {
	"strawberry": STRAWBERRY, "chocolate": CHOCOLATE, "banana": BANANA, "cream": CREAM,
}

## Chef hat colours the select screen cycles through.
const HATS: Array[Color] = [
	Color("#ffffff"), Color("#ff9fb6"), Color("#8fd3ff"), Color("#a7f070"),
	Color("#ffcd75"), Color("#c9a7ff"),
]

const CONFETTI: Array[Color] = [
	Color("#e8435a"), Color("#ffe066"), Color("#8fd3ff"), Color("#a7f070"),
	Color("#ff9fb6"), Color("#c9a7ff"), Color("#ffb347"),
]


## The pancake face colour for a cook amount (0 = batter, 1 = golden).
## Past golden it stays golden: pancakes never burn.
static func cook_color(cook: float) -> Color:
	return BATTER.lerp(GOLDEN, clampf(cook, 0.0, 1.0))
