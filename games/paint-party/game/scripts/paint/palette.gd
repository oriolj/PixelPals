extends RefCounted
## The 12 paint colours on 3 pages of 4 pots, and which d-pad direction picks
## which pot. Sweetie 16 minus the darks, plus pink and brown; all print-friendly.

## Pot order on a page: up, right, down, left (clockwise from the top), which
## is also where the pots stand in the cross beside the easel.
const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
const PAGES := 3
const POTS := 4

const COLORS: Array[Color] = [
	# page 1: the primaries
	Color("#3b5dc9"), Color("#b13e53"), Color("#ffcd75"), Color("#38b764"),
	# page 2: the warm ones
	Color("#ef7d57"), Color("#ff5fa2"), Color("#5d275d"), Color("#a7f070"),
	# page 3: sky, sea and trees
	Color("#41a6f6"), Color("#8b5a2b"), Color("#73eff7"), Color("#257179"),
]

const RAINBOW: Array[Color] = [
	Color("#b13e53"), Color("#ef7d57"), Color("#ffcd75"), Color("#38b764"), Color("#41a6f6"), Color("#5d275d"),
]

const PAPER := Color("#fdfdf8")
const INK := Color("#1a1c2c")
const WHITE := Color("#f4f4f4")


static func color(page: int, pot: int) -> Color:
	return COLORS[posmod(page, PAGES) * POTS + posmod(pot, POTS)]


static func index(page: int, pot: int) -> int:
	return posmod(page, PAGES) * POTS + posmod(pot, POTS)


## Direction -> pot on the page, or -1 for no direction.
static func pot_for_dir(d: Vector2i) -> int:
	return DIRS.find(d)


## A readable detail colour on top of `c` (eyes, windows, wheels).
static func detail_on(c: Color) -> Color:
	return INK if c.get_luminance() > 0.45 else WHITE
