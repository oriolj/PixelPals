extends RefCounted
## The fixed palette of Train Conductor (wooden toy railway, flat vector).
## Every colour in the game comes from here.

const TRACK := Color("#d9a066")       # beechwood track
const TRACK_LIGHT := Color("#eec39a")  # wood highlight
const GROOVE := Color("#8f563b")      # rail grooves and sleepers
const GRASS := Color("#99e550")
const GRASS_DARK := Color("#6abe30")
const WATER := Color("#5fcde4")
const WATER_DARK := Color("#3f9fc4")
const INK := Color("#2a2135")         # 2 px outline on every shape
const WHITE := Color("#fff7e8")
const CREAM := Color("#fbf1c7")
const SKY := Color("#8fd3ff")
const NIGHT := Color("#1b1f4a")
const GLOW := Color("#ffe66d")        # lit windows, stars
const TRUNK := Color("#8f563b")
const LEAF := Color("#4b9e3a")
const LEAF_LIGHT := Color("#7ccf4c")
const ROCK := Color("#9badb7")
const SOIL := Color("#c9a26b")
const PINK := Color("#f5a6c8")
const BLACK := Color("#3a3148")

## Station colours: red (circle hats), blue (square), yellow (triangle), green (star).
enum { RED, BLUE, YELLOW, GREEN }
const STATION: Array[Color] = [Color("#e43b44"), Color("#3978a8"), Color("#feae34"), Color("#3e8948")]
## Shape per station colour, so colours also read for colour-blind players.
const SHAPES: Array[String] = ["circle", "square", "triangle", "star"]

## Train body colours.
const ENGINE := Color("#e43b44")
const ENGINE_DARK := Color("#a82a36")
const CAB_ROOF := Color("#3a3148")
const CARRIAGES: Array[Color] = [Color("#3978a8"), Color("#feae34"), Color("#3e8948"), Color("#b55088"), Color("#e8743b")]


static func station(i: int) -> Color:
	return STATION[posmod(i, STATION.size())]
