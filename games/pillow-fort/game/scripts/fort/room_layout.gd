extends RefCounted
## Where everything sits in the bedroom (320x180). tools/sprites.py draws
## room_bg with the same coordinates (keep the two in step).

## The 14 hiding spots: sprite kind and centre.
const SPOTS: Array[Dictionary] = [
	{"kind": "curtain", "pos": Vector2i(72, 50)},
	{"kind": "box", "pos": Vector2i(120, 36)},
	{"kind": "blanket_fold", "pos": Vector2i(28, 110)},
	{"kind": "pillow_a", "pos": Vector2i(160, 66)},
	{"kind": "pillow_b", "pos": Vector2i(124, 126)},
	{"kind": "blanket_fold", "pos": Vector2i(196, 126)},
	{"kind": "pillow_b", "pos": Vector2i(262, 82)},
	{"kind": "pillow_a", "pos": Vector2i(296, 80)},
	{"kind": "blanket_fold", "pos": Vector2i(240, 96)},
	{"kind": "bed_edge", "pos": Vector2i(270, 118)},
	{"kind": "box", "pos": Vector2i(44, 152)},
	{"kind": "pillow_a", "pos": Vector2i(96, 154)},
	{"kind": "blanket_fold", "pos": Vector2i(222, 156)},
	{"kind": "pillow_b", "pos": Vector2i(290, 156)},
]

const FORT_POS := Vector2i(160, 102)       # centre of the 96x64 fort sprite
const LAMP_POS := Vector2i(92, 76)          # centre of the 16x32 lamp (on the nightstand)
const BASKET_POS := Vector2i(160, 160)      # centre of the 32x24 toy basket
const NIGHTLIGHT := Vector2i(214, 98)
const MOON := Vector2i(40, 34)
const FAIRY: Array[Vector2i] = [Vector2i(134, 76), Vector2i(186, 76)]
## Where the seats' avatars sit, in the fort's doorway.
const RIDER_SEATS: Array[Vector2i] = [Vector2i(146, 124), Vector2i(160, 125), Vector2i(174, 124)]
const FLASH_START := Vector2(160, 92)
