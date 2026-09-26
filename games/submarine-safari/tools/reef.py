"""Generate the reef: the 4x2-screen world map, creature homes and the demo route.

Usage: uv run python tools/reef.py

Writes game/data/reef.json (read by scripts/level/reef.gd) and
art_src/reef_map.txt (the same map as text, for reviewing diffs).

The layout is designed here in tile coordinates (16 px tiles, 80 x 23 tiles
= 1280 x 368 px, the world is 1280 x 360): a shelf splits the top zones
(shallows left, reef right) from the deep ones (wreck left, trench right).
Two gaps in the shelf and an opening in the wreck/trench divider keep the
whole world one loop. A seeded pass adds the rock silhouettes (bumps on the
floor and the shelf edge) and picks the kelp columns and coral heads.

Tile chars: '.' water, '#' rock, 's' sand, 'c' coral head (all but '.' are solid).

The script fails (exit 1) if any creature home is inside rock, or if the
demo route would scrape a rock with the sub's hitbox (32 x 16).
"""

from __future__ import annotations

import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "data" / "reef.json"
TEXT = ROOT / "art_src" / "reef_map.txt"

TILE = 16
W, H = 80, 23
WORLD_W, WORLD_H = 1280, 360
SUB_HIT = (32, 16)
SEED = 20260926

# Creature homes (world px, the centre the creature swims around).
HOMES = {
    "clownfish": (200, 108),
    "turtle": (330, 56),
    "crab": (536, 150),
    "blue_tang": (760, 88),
    "pufferfish": (920, 116),
    "eel": (1140, 120),
    "lantern_fish": (1236, 232),
    "anglerfish": (1080, 316),
    "squid": (924, 276),
    "jellyfish": (780, 244),
    "seahorse": (456, 250),
    "octopus": (178, 296),
}

# The demo pilot's loop: (x, y, species it stops for or "").
ROUTE = [
    (148, 100, "clownfish"),
    (276, 56, "turtle"),
    (536, 104, "crab"),
    (708, 88, "blue_tang"),
    (868, 116, "pufferfish"),
    (1090, 120, "eel"),
    (1008, 120, ""),
    (1008, 200, ""),
    (1186, 232, "lantern_fish"),
    (1028, 312, "anglerfish"),
    (870, 276, "squid"),
    (728, 244, "jellyfish"),
    (650, 272, ""),
    (508, 250, "seahorse"),
    (232, 296, "octopus"),
    (300, 240, ""),
    (300, 130, ""),
    (90, 64, ""),
]

SUB_START = (90, 64)


def build() -> tuple[list[list[str]], dict]:
    rnd = random.Random(SEED)
    g = [["." for _ in range(W)] for _ in range(H)]

    def fill(x0: int, y0: int, x1: int, y1: int, c: str) -> None:
        for y in range(max(0, y0), min(H, y1 + 1)):
            for x in range(max(0, x0), min(W, x1 + 1)):
                g[y][x] = c

    # --- the shelf (rows 10-11) with two gaps: x 15-23 and x 60-65
    fill(0, 10, 14, 11, "#")
    fill(24, 10, 59, 11, "#")
    fill(66, 10, 79, 11, "#")
    # shallows: a sand slope rising to the left
    fill(0, 7, 6, 9, "s")
    fill(7, 8, 10, 9, "s")
    fill(11, 9, 14, 9, "s")
    # crab rock on the shelf
    fill(28, 8, 31, 9, "#")
    # reef: the eel's pillar
    fill(72, 5, 74, 9, "#")
    fill(73, 4, 73, 4, "#")
    # --- deep floor
    fill(0, 20, 37, 22, "s")          # wreck sand
    fill(38, 20, 42, 22, "#")
    fill(43, 22, 79, 22, "#")         # trench floor, deeper
    # divider between wreck and trench (open rows 14-19)
    fill(38, 12, 42, 13, "#")
    # trench rocks: a stalactite, a short pillar and a tall one
    fill(56, 12, 57, 13, "#")
    fill(52, 20, 53, 21, "#")
    fill(72, 17, 74, 21, "#")
    fill(73, 16, 73, 16, "#")

    # --- seeded rock silhouettes: bumps that never touch the route corridors
    for x in range(W):
        if 43 <= x <= 79 and rnd.random() < 0.35 and not (50 <= x <= 54):
            g[21][x] = "#"
    x = 1
    while x < 36:           # low sand dunes on the wreck floor, 3-5 tiles wide
        if rnd.random() < 0.45:
            wide = rnd.randint(3, 5)
            for k in range(x, min(x + wide, 37)):
                g[19][k] = "s"
            x += wide + rnd.randint(2, 4)
        else:
            x += 2
    for x in list(range(0, 15)) + list(range(24, 56)) + list(range(74, 80)):
        if rnd.random() < 0.25:
            g[12][x] = "#"    # the shelf's ragged underside
    # keep the wreck/trench opening and the gaps clean
    fill(38, 14, 42, 19, ".")
    fill(15, 10, 23, 13, ".")
    fill(60, 10, 65, 13, ".")

    # --- coral heads on the reef shelf
    coral = []
    for x in (44, 45, 50, 55, 56, 68, 69, 77):
        g[9][x] = "c"
        coral.append([x, 9, rnd.randrange(2)])

    # --- kelp columns: base tile (on top of the floor) and height in tiles
    kelp = []
    for x, scan in ((2, 0), (4, 0), (9, 0), (26, 14), (29, 14), (32, 14), (35, 14), (47, 0), (58, 0)):
        base = scan
        while base + 1 < H and g[base + 1][x] == ".":
            base += 1          # the last water tile above the floor
        kelp.append([x, base, rnd.randint(2, 4)])

    decor = {
        "kelp": kelp,
        "coral": coral,
        "anemone": [[12, 8]],
        "wreck": [96, 272],        # top-left of the 96 x 48 wreck prop (on the sand)
        "rock_hide": [[30, 9]],    # the crab's rock (for the sonar rings)
    }
    return g, decor


def solid(g: list[list[str]], px: float, py: float) -> bool:
    tx, ty = int(px // TILE), int(py // TILE)
    if tx < 0 or tx >= W or ty < 0 or ty >= H:
        return False
    return g[ty][tx] != "."


def rect_hits(g: list[list[str]], cx: float, cy: float, w: int, h: int) -> bool:
    for x in (cx - w / 2, cx, cx + w / 2 - 1):
        for y in (cy - h / 2, cy, cy + h / 2 - 1):
            if solid(g, x, y):
                return True
    for x in range(int(cx - w / 2), int(cx + w / 2), 8):
        for y in (cy - h / 2, cy + h / 2 - 1):
            if solid(g, x, y):
                return True
    return False


def check(g: list[list[str]]) -> list[str]:
    errors = []
    for name, (x, y) in HOMES.items():
        if solid(g, x, y):
            errors.append(f"home of {name} at {x},{y} is inside rock")
    pts = [SUB_START] + [(x, y) for x, y, _ in ROUTE] + [(ROUTE[0][0], ROUTE[0][1])]
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = max(1, int(max(abs(x1 - x0), abs(y1 - y0)) / 4))
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            y = y0 + (y1 - y0) * i / n
            if rect_hits(g, x, y, *SUB_HIT):
                errors.append(f"route segment {x0},{y0} -> {x1},{y1} scrapes rock near {x:.0f},{y:.0f}")
                break
    return errors


def main() -> int:
    g, decor = build()
    errors = check(g)
    if errors:
        for e in errors:
            print(f"REEF: {e}", file=sys.stderr)
        return 1
    data = {
        "tile": TILE,
        "w": W,
        "h": H,
        "world": [WORLD_W, WORLD_H],
        "rows": ["".join(r) for r in g],
        "homes": {k: list(v) for k, v in HOMES.items()},
        "route": [[x, y, s] for x, y, s in ROUTE],
        "sub_start": list(SUB_START),
        "decor": decor,
    }
    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=1) + "\n")
    TEXT.write_text("; generated by tools/reef.py (do not edit): . water  # rock  s sand  c coral\n"
                    + "\n".join(data["rows"]) + "\n")
    print(f"reef: {W}x{H} tiles, {len(HOMES)} homes, {len(ROUTE)} route stops; route clear")
    return 0


if __name__ == "__main__":
    sys.exit(main())
