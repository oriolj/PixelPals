extends RefCounted
## The twelve species of the album page, plus the whale (the big friend,
## photographed onto its own double page) and the bonus subjects that an
## empty snap photographs. Pure data.

enum Kind { EASY, HIDER, LIGHT, WHALE }

## Album page order (slot 0..11) and motif number (new_species_<i+1>).
const PAGE: Array[String] = ["clownfish", "blue_tang", "pufferfish", "turtle", "seahorse", "crab",
	"octopus", "eel", "jellyfish", "anglerfish", "squid", "lantern_fish"]
const WHALE := "whale"
const BONUS: Array[String] = ["bubble", "shell", "rock_smile", "starfish"]

## kind, sprite size, roam radius (px) and swim speed (px/s), placeholder tint.
const INFO := {
	"clownfish": {"kind": Kind.EASY, "size": Vector2i(16, 16), "roam": 22.0, "speed": 20.0, "tint": Color("#f77622")},
	"blue_tang": {"kind": Kind.EASY, "size": Vector2i(16, 16), "roam": 30.0, "speed": 24.0, "tint": Color("#0099db")},
	"pufferfish": {"kind": Kind.EASY, "size": Vector2i(16, 16), "roam": 18.0, "speed": 12.0, "tint": Color("#fee761")},
	"turtle": {"kind": Kind.EASY, "size": Vector2i(24, 24), "roam": 40.0, "speed": 14.0, "tint": Color("#63c74d")},
	"seahorse": {"kind": Kind.EASY, "size": Vector2i(16, 16), "roam": 14.0, "speed": 8.0, "tint": Color("#feae34")},
	"crab": {"kind": Kind.HIDER, "size": Vector2i(24, 24), "roam": 20.0, "speed": 14.0, "tint": Color("#e43b44")},
	"octopus": {"kind": Kind.HIDER, "size": Vector2i(24, 24), "roam": 12.0, "speed": 10.0, "tint": Color("#b55088")},
	"eel": {"kind": Kind.HIDER, "size": Vector2i(24, 24), "roam": 0.0, "speed": 0.0, "tint": Color("#3e8948")},
	"jellyfish": {"kind": Kind.LIGHT, "size": Vector2i(16, 24), "roam": 18.0, "speed": 8.0, "tint": Color("#f6757a")},
	"anglerfish": {"kind": Kind.LIGHT, "size": Vector2i(24, 24), "roam": 16.0, "speed": 10.0, "tint": Color("#5a6988")},
	"squid": {"kind": Kind.LIGHT, "size": Vector2i(24, 24), "roam": 20.0, "speed": 12.0, "tint": Color("#2ce8f5")},
	"lantern_fish": {"kind": Kind.LIGHT, "size": Vector2i(16, 16), "roam": 20.0, "speed": 16.0, "tint": Color("#63c74d")},
	"whale": {"kind": Kind.WHALE, "size": Vector2i(128, 48), "roam": 0.0, "speed": 26.0, "tint": Color("#124e89")},
}


static func kind(id: String) -> int:
	return int(INFO[id].kind)


static func size_of(id: String) -> Vector2i:
	return INFO[id].size


static func tint(id: String) -> Color:
	return INFO[id].tint


## 1-based motif number for new_species_<n>.
static func motif(id: String) -> int:
	return PAGE.find(id) + 1


static func is_shy(id: String) -> bool:
	var k := kind(id)
	return k == Kind.HIDER or k == Kind.LIGHT
