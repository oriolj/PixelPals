extends RefCounted
## The fixed colours of Zoo Keeper. The twelve core colours come from the plan;
## each food owns its colour, which appears nowhere else, so the colour itself
## is a cue. Animal and character colours are listed below them.

# ---- the twelve core colours
const GRASS := Color("#7cc36b")
const PATH := Color("#f1d6a0")
const WATER := Color("#5fb8e8")
const FENCE := Color("#b0764a")
const OUTLINE := Color("#2b2438")
const BANANA := Color("#ffd23f")
const FISH := Color("#6aa8ff")
const CARROT := Color("#ff8a3d")
const HAY := Color("#c9b04a")
const CREAM := Color("#fff6e4")    # bubbles, eye glints, bellies
const LEAF := Color("#3f9a4a")     # trees, carrot tops, the hay's leaves
const SKY := Color("#bfe8ff")      # party backdrop, pool shine

# ---- scenery shades
const GRASS_DARK := Color("#62ab55")
const GRASS_LIGHT := Color("#95d47f")
const PATH_DARK := Color("#dcb97d")
const FENCE_DARK := Color("#8a5733")
const WATER_DARK := Color("#3f93c9")
const MUD := Color("#9a6b4f")
const ROCK := Color("#a9a5b8")
const BARK := Color("#8d5a3a")
const SHADOW := Color(0.17, 0.14, 0.22, 0.22)

# ---- animals
const MONKEY := Color("#9a6440")
const MONKEY_FACE := Color("#f2c9a0")
const PENGUIN := Color("#34384f")
const PENGUIN_BEAK := Color("#f6a13a")
const RABBIT := Color("#e9e4ef")
const RABBIT_PINK := Color("#ffb3c7")
const ELEPHANT := Color("#9aa7c7")
const ELEPHANT_DARK := Color("#8190b3")
const GIRAFFE := Color("#f0b85a")
const GIRAFFE_SPOT := Color("#a8683a")
const SEAL := Color("#8795ab")
const SEAL_LIGHT := Color("#b9c3d3")
const NOSE := Color("#3a2e3f")
const TONGUE := Color("#ff6f8e")
const CHEEK := Color(1.0, 0.5, 0.6, 0.45)

# ---- keeper and props
const SKIN := Color("#f4c7a1")
const SHIRT := Color("#7d9a52")
const SHORTS := Color("#6b5a45")
const BOOT := Color("#5a4636")
const CART := Color("#d9854f")
const CART_DARK := Color("#b0643a")
const WHEEL := Color("#4a4458")
const BOWL := Color("#9fb4d6")
const STAR := Color("#ffb938")
const HEART := Color("#ff5c8a")
const BELL := Color("#e8b23a")
const CONFETTI: Array[Color] = [Color("#ff5c8a"), Color("#ffb938"), Color("#7de0c8"),
	Color("#b58cff"), Color("#ff9e7a"), Color("#8fd0ff")]
