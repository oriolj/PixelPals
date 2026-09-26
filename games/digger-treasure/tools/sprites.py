"""Digger Treasure: render the palette-indexed sprite grids to PNG strips, lint them, draw a contact sheet.

Usage: uv run python tools/sprites.py

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json (gitignored pack)
    GENERATORS (below)      -> procedural sprites (hills, confetti...), same path

Grid format (one or more sprites per file)
    # name WxH fps=N [base=<sprite>] [recolor=a:b,c:d] [mirror]
    <rows of W chars, H rows>        '.' = transparent, '0'..'9','a'..'f' = Sweetie 16 index
    <blank line>
    <next frame, or a one-line directive>

    Lines starting with ';' are comments. The name defaults to the file stem.
    Frame directives (a frame made of one line), each optionally 'from=K'
    (the source frame index; default: the previous frame):
        @bounce              source shifted up 1 px (idle bounce)
        @shift DX DY         source shifted by DX, DY (pixels leaving the frame are lost)
        @mirror              source flipped horizontally
        @recolor A:B C:D     source with palette index A replaced by B, ...
        @sparkle X Y         source plus a 3x3 white sparkle with its top-left at X, Y
    Header 'outline' draws a 1 px index-0 outline around every grid frame
    (author the fill only, leaving a 1 px margin); directives copy it.
    Header 'base=<sprite>' takes all frames from another sprite, then applies
    'recolor=' and 'mirror' to every frame; no frames follow it.

Lint (exit 1): ragged rows, frame size different from the header, chars off
the palette, any PNG under game/art or the private art dir with partial alpha
or an opaque colour off the palette.

Also writes art_src/contact_sheet*.png (committed cast) and
art_src/private/contact_sheet.png (private pack): every frame at up to 8x,
nearest, on a checkerboard with a 1 px grid, labelled.
"""

from __future__ import annotations

import json
import math
import random
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src"
PRIVATE_SRC = SRC / "private"
PALETTE_FILE = SRC / "palettes" / "sweetie16.hex"
OUT = ROOT / "game" / "art"
PRIVATE_OUT = ROOT / "game" / "private_pack" / "art"
PRIVATE_RIDERS = ROOT / "game" / "private_pack" / "riders.json"

CHARS = "0123456789abcdef"
HEADER_RE = re.compile(r"^#\s+([a-z0-9_]+)\s+(\d+)x(\d+)(.*)$")
T = -1  # transparent index


def load_palette() -> list[tuple[int, int, int]]:
    cols = []
    for line in PALETTE_FILE.read_text().split():
        line = line.strip().lstrip("#")
        if line:
            cols.append((int(line[0:2], 16), int(line[2:4], 16), int(line[4:6], 16)))
    if len(cols) != 16:
        raise SystemExit(f"palette {PALETTE_FILE} must have 16 colours, has {len(cols)}")
    return cols


PALETTE = load_palette()


@dataclass
class Sprite:
    name: str
    w: int
    h: int
    fps: int
    frames: list[np.ndarray] = field(default_factory=list)
    private: bool = False
    origin: str = ""
    base: str | None = None
    recolor: dict[int, int] = field(default_factory=dict)
    mirror: bool = False
    outline: bool = False


errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


# ---------------------------------------------------------------- frame helpers

def shift(f: np.ndarray, dx: int, dy: int) -> np.ndarray:
    h, w = f.shape
    out = np.full_like(f, T)
    ys, yd = (slice(max(0, -dy), h - max(0, dy)), slice(max(0, dy), h - max(0, -dy)))
    xs, xd = (slice(max(0, -dx), w - max(0, dx)), slice(max(0, dx), w - max(0, -dx)))
    out[yd, xd] = f[ys, xs]
    return out


def outline(f: np.ndarray, col: int = 0) -> np.ndarray:
    """1 px outline in `col` on every transparent pixel 4-adjacent to a filled one."""
    filled = f >= 0
    near = np.zeros_like(filled)
    near[1:, :] |= filled[:-1, :]
    near[:-1, :] |= filled[1:, :]
    near[:, 1:] |= filled[:, :-1]
    near[:, :-1] |= filled[:, 1:]
    out = f.copy()
    out[near & ~filled] = col
    return out


def mirror(f: np.ndarray) -> np.ndarray:
    return f[:, ::-1].copy()


def recolor(f: np.ndarray, mapping: dict[int, int]) -> np.ndarray:
    out = f.copy()
    for a, b in mapping.items():
        out[f == a] = b
    return out


def parse_map(tokens: list[str], where: str) -> dict[int, int]:
    mapping = {}
    for tok in tokens:
        m = re.fullmatch(r"([0-9a-f.]):([0-9a-f.])", tok)
        if not m:
            err(f"{where}: bad recolor pair {tok!r} (want A:B)")
            continue
        a, b = (T if c == "." else CHARS.index(c) for c in m.groups())
        mapping[a] = b
    return mapping


# ---------------------------------------------------------------- parsing

def parse_file(path: Path, private: bool) -> list[Sprite]:
    sprites: list[Sprite] = []
    cur: Sprite | None = None
    block: list[tuple[int, str]] = []

    def flush() -> None:
        nonlocal block
        if block and cur is not None:
            add_block(cur, block, path)
        elif block:
            err(f"{path.name}:{block[0][0]}: grid rows before any '# name WxH' header")
        block = []

    lines = path.read_text().splitlines()
    for no, raw in enumerate(lines, 1):
        line = raw.rstrip()
        if line.startswith(";"):
            continue
        m = HEADER_RE.match(line)
        if m:
            flush()
            name, w, h, rest = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
            cur = Sprite(name, w, h, 6, private=private, origin=f"{path.name}:{no}")
            for opt in rest.split():
                if opt.startswith("fps="):
                    cur.fps = int(opt[4:])
                elif opt.startswith("base="):
                    cur.base = opt[5:]
                elif opt.startswith("recolor="):
                    cur.recolor = parse_map(opt[8:].split(","), cur.origin)
                elif opt == "mirror":
                    cur.mirror = True
                elif opt == "outline":
                    cur.outline = True
                else:
                    err(f"{cur.origin}: unknown header option {opt!r}")
            sprites.append(cur)
            continue
        if line.startswith("#"):
            continue  # free comment
        if not line.strip():
            flush()
            continue
        if cur is None and not sprites:
            # headerless file: name from the stem, size from the first frame
            cur = Sprite(path.stem, 0, 0, 6, private=private, origin=f"{path.name}:{no}")
            sprites.append(cur)
        block.append((no, line.strip()))
    flush()
    return sprites


def add_block(sp: Sprite, block: list[tuple[int, str]], path: Path) -> None:
    no0 = block[0][0]
    where = f"{path.name}:{no0} ({sp.name} frame {len(sp.frames)})"
    first = block[0][1]
    if first.startswith("@"):
        if len(block) != 1:
            err(f"{where}: a directive frame must be a single line")
            return
        toks = first.split()
        src_idx = len(sp.frames) - 1
        rest = []
        for t in toks[1:]:
            if t.startswith("from="):
                src_idx = int(t[5:])
            else:
                rest.append(t)
        if not (0 <= src_idx < len(sp.frames)):
            err(f"{where}: {toks[0]} has no source frame {src_idx}")
            return
        src = sp.frames[src_idx]
        op = toks[0]
        if op == "@bounce":
            sp.frames.append(shift(src, 0, -1))
        elif op == "@shift" and len(rest) == 2:
            sp.frames.append(shift(src, int(rest[0]), int(rest[1])))
        elif op == "@mirror":
            sp.frames.append(mirror(src))
        elif op == "@recolor":
            sp.frames.append(recolor(src, parse_map(rest, where)))
        elif op == "@sparkle" and len(rest) == 2:
            sp.frames.append(with_sparkle(src, int(rest[0]), int(rest[1])))
        else:
            err(f"{where}: unknown directive {first!r}")
        return

    rows = [r for _, r in block]
    widths = {len(r) for r in rows}
    if len(widths) != 1:
        err(f"{where}: ragged rows (widths {sorted(widths)})")
        return
    w, h = widths.pop(), len(rows)
    if sp.w == 0 and sp.h == 0:
        sp.w, sp.h = w, h
    if (w, h) != (sp.w, sp.h):
        err(f"{where}: frame is {w}x{h}, header says {sp.w}x{sp.h}")
        return
    arr = np.full((h, w), T, dtype=np.int8)
    for y, (no, r) in enumerate(block):
        for x, c in enumerate(r):
            if c == ".":
                continue
            if c not in CHARS:
                err(f"{path.name}:{no}: char {c!r} at column {x + 1} is not in the palette")
                continue
            arr[y, x] = CHARS.index(c)
    sp.frames.append(outline(arr) if sp.outline else arr)


def resolve_bases(sprites: dict[str, Sprite]) -> None:
    for sp in sprites.values():
        if sp.base:
            base = sprites.get(sp.base)
            if base is None:
                err(f"{sp.origin}: base sprite {sp.base!r} not found")
                continue
            if base.base:
                err(f"{sp.origin}: base {sp.base!r} is itself derived (one level only)")
                continue
            if sp.frames:
                err(f"{sp.origin}: a base= sprite takes no frames of its own")
            sp.w, sp.h = base.w, base.h
            sp.frames = [f.copy() for f in base.frames]
        if sp.recolor:
            sp.frames = [recolor(f, sp.recolor) for f in sp.frames]
        if sp.mirror:
            sp.frames = [mirror(f) for f in sp.frames]


# ---------------------------------------------------------------- generators
# Shapes that are easier as geometry than as hand-typed grids. They return
# Sprites that go through exactly the same checks, PNG writer and lint.

def grid(w: int, h: int) -> np.ndarray:
    return np.full((h, w), T, dtype=np.int8)


def ellipse(f: np.ndarray, cx: float, cy: float, rx: float, ry: float, col: int) -> None:
    h, w = f.shape
    yy, xx = np.mgrid[0:h, 0:w]
    f[((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0] = col


def rect(f: np.ndarray, x0: int, y0: int, x1: int, y1: int, col: int) -> None:
    """Inclusive corners, clipped."""
    h, w = f.shape
    f[max(0, y0):min(h, y1 + 1), max(0, x0):min(w, x1 + 1)] = col


def poly(f: np.ndarray, pts: list[tuple[float, float]], col: int) -> None:
    h, w = f.shape
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(pts, fill=255)
    f[np.asarray(m) > 0] = col


def stamp(f: np.ndarray, x: int, y: int, rows: list[str]) -> None:
    """Paint a small grid ('.' = leave as is) with its top-left at x, y."""
    h, w = f.shape
    for dy, r in enumerate(rows):
        for dx, c in enumerate(r):
            if c != "." and 0 <= y + dy < h and 0 <= x + dx < w:
                f[y + dy, x + dx] = CHARS.index(c)


def shade(f: np.ndarray, region: int, col: int, where: np.ndarray) -> None:
    f[(f == region) & where] = col


def star_points(cx: float, cy: float, r_out: float, r_in: float, sx: float = 1.0) -> list[tuple[float, float]]:
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = r_out if i % 2 == 0 else r_in
        pts.append((cx + sx * r * math.cos(a), cy + r * math.sin(a)))
    return pts


def gen_hills() -> Sprite:
    """Far teal hills and near green hills with trees. Seamless: every period divides 320.
    Background layer: no dark outline, a light rim instead."""
    w, h = 320, 48
    f = grid(w, h)
    xs = np.arange(w)
    far = 20 + 7 * np.sin(xs * 2 * math.pi / 160) + 4 * np.sin(xs * 2 * math.pi / 64 + 1.0)
    near = 33 + 5 * np.sin(xs * 2 * math.pi / 106.666666 + 2.0) + 3 * np.sin(xs * 2 * math.pi / 40)
    far = np.round(far).astype(int)
    near = np.round(near).astype(int)
    for x in range(w):
        f[far[x]:, x] = 7
        f[far[x], x] = 11          # cyan rim on the far hills
    rnd = random.Random(7)
    # trees on the near hills, drawn before the near fill so trunks sit in the grass
    for tx in range(24, w, 64):
        base = near[tx]
        ellipse(f, tx + 0.5, base - 5.5, 3.2, 3.6, 6)
        ellipse(f, tx - 0.5, base - 6.5, 1.4, 1.2, 5)
        rect(f, tx, base - 2, tx, base, 7)
    for x in range(w):
        f[near[x]:, x] = 6
        f[near[x], x] = 5          # sunny rim
    for _ in range(50):
        x = rnd.randrange(w)
        y = rnd.randrange(near[x] + 3, h)
        f[y, x] = rnd.choice((4, 12, 5))
    return Sprite("hills", w, h, 0, [f], origin="generator:hills")


def gen_confetti() -> Sprite:
    """6 frames, one colour each (the code picks a frame per piece)."""
    shape = ["..X.", ".XXX", "XXX.", ".X.."]
    frames = []
    for col in (2, 4, 6, 10, 3, 11):
        f = grid(4, 4)
        for y, r in enumerate(shape):
            for x, c in enumerate(r):
                if c == "X":
                    f[y, x] = col
        frames.append(f)
    return Sprite("confetti", 4, 4, 0, frames, origin="generator:confetti")


def gen_cloud_bg() -> Sprite:
    f = grid(32, 16)
    for cx, cy, r in ((7, 10.5, 4), (13, 7.2, 5), (20, 5.8, 4.8), (26, 9.5, 4.2), (16, 11, 4.5), (19, 10, 5)):
        ellipse(f, cx, cy, r, r, 12)
    rect(f, 6, 11, 27, 14, 12)
    yy, _ = np.mgrid[0:16, 0:32]
    shade(f, 12, 13, yy >= 13)
    return Sprite("cloud_bg", 32, 16, 0, [f], origin="generator:cloud_bg")


def gen_trophy() -> Sprite:
    frames = []
    for i in range(2):
        f = grid(24, 24)
        halfw = [7, 7, 7, 7, 6.5, 6, 5.5, 5, 4, 3, 2]
        for k, hw in enumerate(halfw):
            y = 3 + k
            rect(f, round(12 - hw), y, round(12 + hw) - 1, y, 4)
        # handles: rings on both sides
        for cx in (4.5, 19.5):
            ring = grid(24, 24)
            ellipse(ring, cx, 7.5, 3.2, 3.4, 4)
            ellipse(ring, cx, 7.5, 1.5, 1.7, T)
            f[(ring == 4) & (f < 0)] = 4
        rect(f, 10, 14, 13, 16, 4)       # stem
        rect(f, 7, 17, 16, 18, 4)        # collar
        rect(f, 5, 19, 18, 21, 1)        # plinth
        rect(f, 5, 21, 18, 21, 15)
        yy, xx = np.mgrid[0:24, 0:24]
        shade(f, 4, 3, xx >= 14)
        # shine stripe sweeps between frames
        sx = 7 if i == 0 else 10
        for y in range(4, 12):
            if f[y, sx] in (3, 4):
                f[y, sx] = 12
        stamp(f, 10, 6, [".c.", "ccc", ".c."] if i == 0 else [".4.", "4c4", ".4."])
        f = outline(f)
        if i == 1:
            stamp(f, 19, 0, [".c.", "cbc", ".c."])
        frames.append(f)
    return Sprite("trophy", 24, 24, 3, frames, origin="generator:trophy")


def gen_seat_driver() -> Sprite:
    """Steering wheel."""
    f = grid(16, 16)
    ellipse(f, 8, 8, 7.0, 7.0, 14)
    ellipse(f, 8, 8, 5.0, 5.0, T)
    yy, xx = np.mgrid[0:16, 0:16]
    shade(f, 14, 13, (xx + yy) < 13)
    rect(f, 3, 7, 12, 8, 14)             # horizontal spoke
    rect(f, 7, 9, 8, 13, 14)             # lower spoke
    rect(f, 6, 6, 9, 9, 2)               # red hub
    f[6, 6] = 12
    return Sprite("seat_driver", 16, 16, 0, [outline(f)], origin="generator:seat_driver")



# ---------------------------------------------------------------- Digger Treasure generators

def gen_sky_hills() -> Sprite:
    """PixelPals's hills recoloured for the dig surface: blue far hills, teal near hills
    (the green grass strip sits in front of them)."""
    sp = gen_hills()
    sp.name = "sky_hills"
    sp.origin = "generator:sky_hills"
    sp.frames = [recolor(f, {7: 9, 11: 10, 6: 7, 5: 6}) for f in sp.frames]
    return sp


def gen_grass_strip() -> Sprite:
    """320x16 grass lip over the topsoil. Blades on top (transparent sky between),
    a solid turf band, then a soil row that meets the field's topsoil."""
    w, h = 320, 16
    f = grid(w, h)
    rnd = random.Random(11)
    for x in range(w):
        top = 9 - rnd.choice((1, 2, 2, 3, 3, 4, 5))
        f[top:10, x] = 6
        f[top, x] = 5
    rect(f, 0, 9, w - 1, 11, 6)
    for x in range(0, w, 3):
        f[9, x + rnd.randrange(0, 2) if x + 1 < w else x] = 5
    rect(f, 0, 12, w - 1, 12, 7)
    rect(f, 0, 13, w - 1, 15, 3)
    for _ in range(90):
        x, y = rnd.randrange(w), rnd.randrange(13, 16)
        f[y, x] = rnd.choice((2, 4, 2))
    # little flowers poking out of the grass (period divides 320: seamless)
    for i, fx in enumerate(range(17, w, 40)):
        col = (2, 12, 4, 10)[i % 4]
        rect(f, fx, 4, fx, 8, 6)
        stamp(f, fx - 1, 1, [f".{CHARS[col]}.", f"{CHARS[col]}4{CHARS[col]}", f".{CHARS[col]}."])
    return Sprite("grass_strip", w, h, 0, [f], origin="generator:grass_strip")


def digger_frame(dx: int, dy: int, phase: int, beacon: bool) -> np.ndarray:
    """32x24, facing right. Tracks stay put; the body bobs (dy) or shakes (dx)."""
    w, h = 32, 24
    f = grid(w, h)
    # tracks: a rounded loop with wheels
    ellipse(f, 5.5, 19.5, 3.4, 3.4, 15)
    ellipse(f, 24.5, 19.5, 3.4, 3.4, 15)
    rect(f, 5, 16, 24, 22, 15)
    for x in range(4, 27):
        if (x + phase) % 3 == 0:
            if f[16, x] == 15:
                f[16, x] = 14
            if f[22, x] == 15:
                f[22, x] = 14
    for wx in (6, 12, 18, 24):
        ellipse(f, wx + 0.5, 19.5, 2.1, 2.1, 13)
        f[19, wx] = 14
    # body
    bx, by = dx, dy
    rect(f, 3 + bx, 10 + by, 26 + bx, 15 + by, 4)
    rect(f, 3 + bx, 15 + by, 26 + bx, 15 + by, 3)
    rect(f, 4 + bx, 10 + by, 25 + bx, 10 + by, 12)  # sunny top edge
    # hazard stripes along the skirt
    for x in range(4, 26):
        if ((x + bx) // 2) % 2 == 0:
            f[14 + by, x + bx] = 0
    # engine hood at the back with a grille
    rect(f, 2 + bx, 6 + by, 10 + bx, 10 + by, 4)
    rect(f, 2 + bx, 6 + by, 10 + bx, 6 + by, 12)
    for gx in (4, 6, 8):
        rect(f, gx + bx, 8 + by, gx + bx, 9 + by, 3)
    # exhaust pipe with a black cap
    rect(f, 4 + bx, 2 + by, 5 + bx, 5 + by, 14)
    rect(f, 4 + bx, 2 + by, 5 + bx, 2 + by, 15)
    # beacon on the hood
    stamp(f, 8 + bx, 4 + by, ["c2" if beacon else "22", "22"])
    # seat back (the driver sits in front of it)
    rect(f, 12 + bx, 4 + by, 13 + bx, 9 + by, 2)
    rect(f, 12 + bx, 4 + by, 12 + bx, 9 + by, 1)
    # arm mount at the front: a pivot boss and a headlight
    rect(f, 22 + bx, 7 + by, 27 + bx, 13 + by, 3)
    ellipse(f, 25.5 + bx, 10.5 + by, 2.2, 2.2, 14)
    f[10 + by, 25 + bx] = 13
    stamp(f, 28 + bx, 9 + by, ["4", "c", "4"])
    return outline(f)


def gen_digger() -> Sprite:
    frames = [digger_frame(0, 0, 0, True), digger_frame(0, -1, 1, False),
              digger_frame(1, 0, 2, True), digger_frame(-1, 0, 1, False)]
    return Sprite("digger", 32, 24, 8, frames, origin="generator:digger")


def truck_frame(load: int) -> np.ndarray:
    """48x24 dump truck facing right. load: 0 empty, 1 half, 2 full, 3 tipping."""
    w, h = 48, 24
    f = grid(w, h)
    rect(f, 4, 15, 44, 16, 15)                     # chassis
    if load < 3:
        rect(f, 3, 8, 33, 14, 3)                   # bed
        rect(f, 3, 8, 33, 8, 4)
        rect(f, 3, 14, 33, 14, 2)
        for rx in (9, 17, 25):
            rect(f, rx, 9, rx, 13, 2)              # ribs
        if load >= 1:
            peak = 5 if load == 1 else 1
            span = (8, 28) if load == 1 else (5, 31)
            for x in range(span[0], span[1] + 1):
                t = (x - span[0]) / (span[1] - span[0])
                top = round(7 - (7 - peak) * math.sin(math.pi * t))
                rect(f, x, top, x, 7, 4)
                if (x + top) % 3 == 0:
                    f[top + 1 if top + 1 <= 7 else top, x] = 3
            gems = [(12, 6, 10), (20, 5, 2), (24, 6, 6)] if load == 1 else \
                   [(9, 5, 10), (14, 3, 2), (19, 2, 12), (23, 3, 6), (27, 5, 11), (17, 6, 1)]
            for gx, gy, gc in gems:
                if f[gy, gx] == 4:
                    stamp(f, gx, gy, [CHARS[gc] * 2])
            if load == 2:  # a crown on top of the heap
                stamp(f, 16, 0, ["4.4.4", "44444"])
    else:
        # the bed tips up around its back hinge, spilling coins
        hx, hy, a = 3.0, 15.0, math.radians(13)
        def rot(x: float, y: float) -> tuple[float, float]:
            dx, dy = x - hx, y - hy
            return (hx + dx * math.cos(a) + dy * math.sin(a), hy - dx * math.sin(a) + dy * math.cos(a))
        poly(f, [rot(3, 8), rot(34, 8), rot(34, 15), rot(3, 15)], 3)
        poly(f, [rot(3, 8), rot(34, 8), rot(34, 9), rot(3, 9)], 4)
        rect(f, 22, 11, 23, 14, 13)                # hydraulic ram
        for cx, cy in ((1, 12), (2, 15), (1, 18), (3, 20)):
            stamp(f, cx, cy, ["44", "33"])
    # cab
    rect(f, 35, 5, 44, 14, 2)
    rect(f, 35, 5, 44, 5, 3)
    rect(f, 35, 13, 44, 14, 1)
    rect(f, 38, 7, 42, 10, 11)                     # window
    f[7, 41] = 12
    f[8, 42] = 12
    rect(f, 45, 11, 45, 14, 13)                    # bumper
    f[11, 44] = 4                                  # headlight
    # wheels
    for wx in (12, 38):
        ellipse(f, wx + 0.5, 18.5, 3.7, 3.7, 15)
        ellipse(f, wx + 0.5, 18.5, 1.8, 1.8, 13)
        f[18, wx] = 14
    return outline(f)


def gen_dump_truck() -> Sprite:
    return Sprite("dump_truck", 48, 24, 0, [truck_frame(i) for i in range(4)], origin="generator:dump_truck")


def gen_boom_ring() -> Sprite:
    """64x64, 5 frames: a flash, then a green ring that grows and thins (radius 7 cells = 28 px)."""
    frames = []
    yy, xx = np.mgrid[0:64, 0:64]
    d = np.sqrt((xx + 0.5 - 32) ** 2 + (yy + 0.5 - 32) ** 2)
    for i, (r_out, thick) in enumerate([(11, 11), (19, 5), (25, 4), (29, 3), (31, 2)]):
        f = grid(64, 64)
        ring = (d <= r_out) & (d > r_out - thick)
        f[ring] = 5
        f[ring & (d > r_out - 1.2)] = 12 if i < 2 else 6
        f[ring & (d <= r_out - thick + 1.0) & (d > r_out - thick)] = 6
        if i == 0:
            f[d <= 6] = 12
            f[(d <= 9) & (d > 6)] = 4
        if i == 4:
            f[ring & (((xx + yy) % 2) == 1)] = T   # a dotted ring as it fades
        frames.append(f)
    return Sprite("boom_ring", 64, 64, 0, frames, origin="generator:boom_ring")


def gen_dirt_chunk() -> Sprite:
    """4 frames, one per depth band (topsoil, clay, deep clay, rock)."""
    shape = [".XX.", "XXXX", "XXX.", ".X.."]
    frames = []
    for base, hi in ((3, 4), (2, 3), (1, 2), (15, 14)):
        f = grid(4, 4)
        for y, r in enumerate(shape):
            for x, c in enumerate(r):
                if c == "X":
                    f[y, x] = base
        f[0, 1] = hi
        f[1, 0] = hi
        frames.append(f)
    return Sprite("dirt_chunk", 4, 4, 0, frames, origin="generator:dirt_chunk")


def with_sparkle(f: np.ndarray, x: int, y: int) -> np.ndarray:
    out = f.copy()
    stamp(out, x, y, [".c.", "cbc", ".c."])
    return out


def gen_dino_egg() -> Sprite:
    f = grid(16, 16)
    ellipse(f, 8, 8.5, 5.2, 6.4, 12)
    yy, xx = np.mgrid[0:16, 0:16]
    shade(f, 12, 13, ((xx - 8) * 0.7 + (yy - 8.5)) > 4.2)
    for sx, sy in ((6, 5), (10, 8), (6, 11), (9, 12), (4, 8)):
        ellipse(f, sx, sy, 1.3, 1.1, 6)
        if f[sy - 1, sx - 1] == 6:
            f[sy - 1, sx - 1] = 5
    ellipse(f, 6, 4, 1.0, 1.4, 12)
    f[3, 6] = 12
    f = outline(f)
    return Sprite("dino_egg", 16, 16, 2, [f, with_sparkle(f, 11, 1)], origin="generator:dino_egg")


def gen_coins() -> Sprite:
    """Two stacks of gold coins and one lying in front."""
    f = grid(16, 16)

    def stack(x0: int, base: int, n: int) -> None:
        """A stack 5 px wide: alternating coin sides and edges, a flat top."""
        for k in range(n):
            y = base - 2 * k
            rect(f, x0, y, x0 + 4, y, 3)
            rect(f, x0, y - 1, x0 + 4, y - 1, 4)
        top = base - 2 * n
        rect(f, x0 + 1, top, x0 + 3, top, 4)
        f[top, x0 + 1] = 12
        f[top + 1, x0 + 4] = 3

    stack(2, 13, 3)
    stack(9, 13, 5)
    f = outline(f)
    return Sprite("coins", 16, 16, 2, [f, with_sparkle(f, 2, 3)], origin="generator:coins")


def gen_worm() -> Sprite:
    frames = []
    for phase in (0.0, math.pi):
        f = grid(16, 16)
        pts = []
        for x in range(2, 13):
            y = 10.5 + 1.6 * math.sin(x * 0.75 + phase)
            pts.append((x, int(round(y))))
            rect(f, x, int(round(y)) - 1, x, int(round(y)), 3)
        for x, y in pts[1:-1:3]:
            f[y, x] = 2
        hx, hy = pts[-1]
        ellipse(f, hx + 1.0, hy - 0.5, 1.7, 1.6, 3)
        f[hy - 1, hx + 1] = 0
        f[hy, hx + 2] = 2
        frames.append(outline(f))
    return Sprite("worm", 16, 16, 4, frames, origin="generator:worm")


def gen_snail() -> Sprite:
    frames = []
    for i in range(2):
        f = grid(16, 16)
        s = i  # the body stretches one pixel in frame 1
        rect(f, 2, 12, 12 + s, 13, 13)
        rect(f, 11 + s, 9, 13 + s, 13, 13)
        rect(f, 11 + s, 6 + i, 11 + s, 8, 13)
        rect(f, 13 + s, 6 + i, 13 + s, 8, 13)
        f[5 + i, 11 + s] = 0
        f[5 + i, 13 + s] = 0
        f[10, 12 + s] = 0
        ellipse(f, 6.5, 8.5, 4.6, 4.4, 3)
        ellipse(f, 6.5, 8.5, 3.0, 2.9, 2)
        ellipse(f, 6.8, 8.3, 1.8, 1.7, 4)
        f[8, 7] = 2
        f[6, 4] = 12
        frames.append(outline(f))
    return Sprite("snail", 16, 16, 2, frames, origin="generator:snail")


def gen_fossil() -> Sprite:
    """A little fish skeleton in a pebble."""
    f = grid(16, 16)
    ellipse(f, 8, 8.5, 6.6, 5.4, 14)
    yy, xx = np.mgrid[0:16, 0:16]
    shade(f, 14, 13, ((xx - 8) + (yy - 8.5) * 1.3) < -4.5)
    rect(f, 4, 8, 11, 8, 12)                      # spine
    for rx in (5, 7, 9):
        rect(f, rx, 6, rx, 10, 12)                # ribs
    stamp(f, 11, 6, [".c.", "ccc", "c0c", "ccc", ".c."])   # head with an eye
    stamp(f, 2, 6, ["c..", ".c.", "..c", ".c.", "c.."])    # tail
    f = outline(f)
    return Sprite("fossil", 16, 16, 2, [f, with_sparkle(f, 12, 1)], origin="generator:fossil")


def gen_seat_scooper() -> Sprite:
    """A toy spade (the scooper's role icon)."""
    f = grid(16, 16)
    poly(f, [(2, 3), (4, 1), (10, 7), (8, 9)], 4)          # handle
    rect(f, 2, 1, 4, 3, 2)                                  # grip
    poly(f, [(7.5, 8), (11, 5), (15, 11), (10.5, 14.5)], 13)  # blade
    poly(f, [(11.5, 9), (14, 10.5), (10.5, 14)], 14)
    f[7, 11] = 12
    f[8, 11] = 12
    return Sprite("seat_scooper", 16, 16, 0, [outline(f)], origin="generator:seat_scooper")


def gen_seat_boomer() -> Sprite:
    """A round cartoon boom (the boomer's role icon)."""
    f = grid(16, 16)
    pts = []
    for i in range(16):
        a = -math.pi / 2 + i * math.pi / 8
        r = 7.2 if i % 2 == 0 else 4.6
        pts.append((8 + r * math.cos(a), 8 + r * math.sin(a)))
    poly(f, pts, 5)
    yy, xx = np.mgrid[0:16, 0:16]
    shade(f, 5, 6, ((xx - 8) + (yy - 8)) > 4)
    ellipse(f, 8, 8, 3.2, 3.2, 4)
    ellipse(f, 8, 8, 1.6, 1.6, 12)
    return Sprite("seat_boomer", 16, 16, 0, [outline(f)], origin="generator:seat_boomer")


GENERATORS = [gen_sky_hills, gen_grass_strip, gen_confetti, gen_cloud_bg, gen_trophy, gen_seat_driver,
              gen_digger, gen_dump_truck, gen_boom_ring, gen_dirt_chunk, gen_dino_egg, gen_coins,
              gen_worm, gen_snail, gen_fossil, gen_seat_scooper, gen_seat_boomer]


def to_rgba(f: np.ndarray) -> np.ndarray:
    h, w = f.shape
    out = np.zeros((h, w, 4), dtype=np.uint8)
    pal = np.array(PALETTE, dtype=np.uint8)
    mask = f >= 0
    out[mask, :3] = pal[f[mask]]
    out[mask, 3] = 255
    return out


def strip(sp: Sprite) -> Image.Image:
    return Image.fromarray(np.concatenate([to_rgba(f) for f in sp.frames], axis=1), "RGBA")


def lint_png(path: Path) -> None:
    img = Image.open(path).convert("RGBA")
    a = np.asarray(img)
    alpha = a[..., 3]
    if np.any((alpha > 0) & (alpha < 255)):
        err(f"{path.relative_to(ROOT)}: partial alpha")
    opaque = a[alpha == 255][:, :3]
    if len(opaque):
        pal = {tuple(c) for c in PALETTE}
        bad = {tuple(int(v) for v in c) for c in np.unique(opaque, axis=0)} - pal
        if bad:
            sample = ", ".join("%02x%02x%02x" % c for c in sorted(bad)[:4])
            err(f"{path.relative_to(ROOT)}: {len(bad)} colour(s) off the palette ({sample})")


def write_outputs(sprites: list[Sprite], out: Path) -> dict:
    out.mkdir(parents=True, exist_ok=True)
    manifest = {}
    for sp in sprites:
        strip(sp).save(out / f"{sp.name}.png", optimize=True)
        manifest[sp.name] = {"w": sp.w, "h": sp.h, "frames": len(sp.frames), "fps": sp.fps}
    (out / "manifest.json").write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n")
    return manifest


# ---------------------------------------------------------------- contact sheet

MAX_W = 1960
MAX_H = 1960
PAD = 12
LABEL_H = 14


def checker(w: int, h: int, cell: int) -> Image.Image:
    yy, xx = np.mgrid[0:h, 0:w]
    on = ((yy // cell + xx // cell) % 2).astype(bool)
    arr = np.where(on[..., None], np.array([200, 200, 210], np.uint8), np.array([232, 232, 240], np.uint8))
    return Image.fromarray(arr.astype(np.uint8), "RGB")


def tile(sp: Sprite) -> Image.Image:
    gap = 6
    n = len(sp.frames)
    scale = 8
    while scale > 1 and (sp.w * n) * scale + gap * (n - 1) > MAX_W - 2 * PAD:
        scale -= 1
    fw, fh = sp.w * scale, sp.h * scale
    label = f"{sp.name} {sp.w}x{sp.h} x{n}" + (f" @{scale}x" if scale != 8 else "")
    label_w = int(ImageDraw.Draw(Image.new("RGB", (1, 1))).textlength(label)) + 2
    img = Image.new("RGB", (max(n * fw + (n - 1) * gap, label_w), fh + LABEL_H), (40, 42, 54))
    d = ImageDraw.Draw(img)
    d.text((0, 1), label, fill=(240, 240, 240))
    for i, f in enumerate(sp.frames):
        x0 = i * (fw + gap)
        bg = checker(fw, fh, max(scale, 4))
        spr = Image.fromarray(to_rgba(f), "RGBA").resize((fw, fh), Image.NEAREST)
        bg.paste(spr, (0, 0), spr)
        gd = ImageDraw.Draw(bg)
        if scale >= 4:
            for gx in range(0, fw, scale):
                gd.line([(gx, 0), (gx, fh)], fill=(150, 150, 165))
            for gy in range(0, fh, scale):
                gd.line([(0, gy), (fw, gy)], fill=(150, 150, 165))
        img.paste(bg, (x0, LABEL_H))
    return img


def contact_sheets(sprites: list[Sprite], first: Path) -> list[Path]:
    tiles = [tile(sp) for sp in sprites]
    # shelf packing
    sheets: list[list[tuple[Image.Image, int, int]]] = [[]]
    x, y, row_h, sheet_w = PAD, PAD, 0, 0
    for t in tiles:
        if x + t.width + PAD > MAX_W and x > PAD:
            x, y, row_h = PAD, y + row_h + PAD, 0
        if y + t.height + PAD > MAX_H and sheets[-1]:
            sheets.append([])
            x, y, row_h = PAD, PAD, 0
        sheets[-1].append((t, x, y))
        x += t.width + PAD
        row_h = max(row_h, t.height)
    paths = []
    for i, items in enumerate(sheets):
        w = max(tx + t.width for t, tx, _ in items) + PAD
        h = max(ty + t.height for t, _, ty in items) + PAD
        sheet = Image.new("RGB", (w, h), (24, 24, 32))
        for t, tx, ty in items:
            sheet.paste(t, (tx, ty))
        p = first if i == 0 else first.with_name(f"{first.stem}_{i + 1}.png")
        sheet.save(p, optimize=True)
        paths.append(p)
    # remove stale extra sheets
    for old in first.parent.glob(f"{first.stem}_*.png"):
        if old not in paths:
            old.unlink()
    return paths


# ---------------------------------------------------------------- main

def main() -> int:
    public: dict[str, Sprite] = {}
    private: dict[str, Sprite] = {}
    for path in sorted(SRC.glob("*.txt")):
        for sp in parse_file(path, private=False):
            if sp.name in public:
                err(f"{sp.origin}: duplicate sprite {sp.name!r}")
            public[sp.name] = sp
    for gen in GENERATORS:
        made = gen()
        for sp in made if isinstance(made, list) else [made]:
            if sp.name in public:
                err(f"{sp.origin}: duplicate sprite {sp.name!r} (also in art_src)")
            public[sp.name] = sp
    if PRIVATE_SRC.is_dir():
        for path in sorted(PRIVATE_SRC.glob("*.txt")):
            for sp in parse_file(path, private=True):
                if sp.name in private or sp.name in public:
                    err(f"{sp.origin}: duplicate sprite {sp.name!r}")
                private[sp.name] = sp
    everything = {**public, **private}
    resolve_bases(everything)
    for sp in everything.values():
        if not sp.frames:
            err(f"{sp.origin}: sprite {sp.name!r} has no frames")
        for i, f in enumerate(sp.frames):
            if f.shape != (sp.h, sp.w):
                err(f"{sp.origin}: {sp.name} frame {i} is {f.shape[1]}x{f.shape[0]}, header says {sp.w}x{sp.h}")
            if f.max() > 15 or f.min() < T:
                err(f"{sp.origin}: {sp.name} frame {i} has indices off the palette")

    if errors:
        for e in errors:
            print(f"LINT: {e}", file=sys.stderr)
        return 1

    pub = sorted(public.values(), key=lambda s: s.name)
    manifest = write_outputs(pub, OUT)
    for stale in OUT.glob("*.png"):
        if stale.stem not in manifest:
            print(f"note: {stale.relative_to(ROOT)} has no source (hand-made PNG?), linting it anyway")
    if private:
        priv = sorted(private.values(), key=lambda s: s.name)
        write_outputs(priv, PRIVATE_OUT)
        riders = [s.name for s in private.values() if (s.w, s.h) == (16, 16) and len(s.frames) == 2]
        PRIVATE_RIDERS.write_text(json.dumps(riders, indent=2) + "\n")

    for png in sorted(OUT.glob("*.png")):
        lint_png(png)
    if PRIVATE_OUT.is_dir():
        for png in sorted(PRIVATE_OUT.glob("*.png")):
            lint_png(png)
    if errors:
        for e in errors:
            print(f"LINT: {e}", file=sys.stderr)
        return 1

    sheets = contact_sheets(pub, SRC / "contact_sheet.png")
    if private:
        sheets += contact_sheets(sorted(private.values(), key=lambda s: s.name), PRIVATE_SRC / "contact_sheet.png")
    print(f"sprites: {len(public)} public, {len(private)} private; lint OK")
    for p in sheets:
        print(f"  sheet: {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
