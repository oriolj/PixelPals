"""Pillow Fort art: render grids and generators to PNG strips, lint them, draw a contact sheet.

Copied from PixelPals tools/sprites.py (same grid format, renderer and lint);
the generators below are this game's own (room, fort, spots, toys, friends...).

Usage: uv run python tools/sprites.py

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json (committed: private repo)
    GENERATORS (below)      -> procedural sprites (room_bg, fort, spots, toys, tips, friends...)

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


def mgrid(f: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    return np.mgrid[0:f.shape[0], 0:f.shape[1]]


def ring(f: np.ndarray, cx: float, cy: float, rx: float, ry: float, t: float, col: int) -> None:
    g = grid(f.shape[1], f.shape[0])
    ellipse(g, cx, cy, rx, ry, 1)
    ellipse(g, cx, cy, rx - t, ry - t, T)
    f[g == 1] = col


# ---------------------------------------------------------------- the room
# Coordinates match game/scripts/fort/room_layout.gd.

WALL_BOTTOM = 103
FLOOR_TOP = 110


def gen_room_bg() -> Sprite:
    w, h = 320, 180
    f = np.full((h, w), 13, dtype=np.int8)            # wall: soft grey-blue
    yy, xx = mgrid(f)
    # Wallpaper: little yellow stars and white dots on a diagonal lattice.
    for y0 in range(8, WALL_BOTTOM - 6, 18):
        for x0 in range(6 + (9 if (y0 // 18) % 2 else 0), w, 18):
            stamp(f, x0, y0, [".c.", "c4c", ".c."])
            if x0 + 9 < w and y0 + 9 < WALL_BOTTOM - 2:
                f[y0 + 10, x0 + 10] = 12
    rect(f, 0, 0, w - 1, 1, 14)                       # ceiling shadow
    # Bunting across the top of the wall.
    cols = [2, 4, 6, 10, 3]
    for i, x0 in enumerate(range(88, 312, 12)):
        sag = int(round(2 * math.sin((x0 - 88) / 224 * math.pi)))
        rect(f, x0, 5 + sag, x0 + 11, 5 + sag, 12)
        poly(f, [(x0 + 1, 6 + sag), (x0 + 11, 6 + sag), (x0 + 6, 13 + sag)], cols[i % len(cols)])
    # Skirting board and floor.
    rect(f, 0, WALL_BOTTOM + 1, w - 1, FLOOR_TOP - 2, 12)
    rect(f, 0, FLOOR_TOP - 1, w - 1, FLOOR_TOP - 1, 14)
    rect(f, 0, FLOOR_TOP, w - 1, h - 1, 3)            # warm wooden floor
    rnd = random.Random(11)
    for y0 in range(FLOOR_TOP + 9, h, 10):
        rect(f, 0, y0, w - 1, y0, 2)                  # plank seams
    for row, y0 in enumerate(range(FLOOR_TOP, h, 10)):
        for x0 in range(((row * 37) % 60), w, 60):
            rect(f, x0, y0, x0, min(y0 + 8, h - 1), 2)
    for _ in range(90):                               # grain highlights
        x, y = rnd.randrange(w - 6), rnd.randrange(FLOOR_TOP + 1, h)
        if f[y, x] == 3 and f[y, x + 4] == 3:
            rect(f, x, y, x + rnd.randrange(2, 5), y, 4)
    # Round rug under the fort.
    ellipse(f, 160, 146, 104, 26, 9)
    ellipse(f, 160, 146, 100, 23, 10)
    ring(f, 160, 146, 88, 18, 1.2, 12)
    for k in range(0, 360, 20):
        a = math.radians(k)
        x, y = int(160 + 94 * math.cos(a)), int(146 + 20.5 * math.sin(a))
        stamp(f, x, y, ["4"])
    # Window with the sleepy moon (Layout.MOON = 53, 24).
    rect(f, 14, 12, 66, 62, 12)
    rect(f, 17, 15, 63, 59, 8)
    rect(f, 17, 48, 63, 59, 9)                        # a little glow at the horizon
    rect(f, 17, 55, 63, 59, 10)
    for x, y in [(22, 20), (31, 27), (24, 41), (47, 44), (58, 42), (33, 18)]:
        f[y, x] = 12
    stamp(f, 27, 32, [".4.", "4c4", ".4."])
    ellipse(f, 53.5, 24.5, 6.2, 6.2, 4)
    ellipse(f, 56.5, 22.5, 5.0, 5.0, 8)              # crescent
    f[24, 50] = 3                                     # closed sleepy eye
    f[25, 51] = 3
    f[27, 51] = 2                                     # cheek
    rect(f, 39, 15, 41, 59, 12)                       # mullions
    rect(f, 17, 36, 63, 37, 12)
    rect(f, 10, 62, 70, 65, 12)                       # sill
    rect(f, 10, 65, 70, 65, 14)
    # Curtain rod, the left curtain and the top of the right one (the spot is its hem).
    rect(f, 2, 8, 84, 9, 14)
    rect(f, 1, 7, 2, 10, 4)
    rect(f, 84, 7, 85, 10, 4)
    for x0, x1, y1 in [(3, 13, 66), (64, 79, 38)]:
        rect(f, x0, 10, x1, y1, 6)
        for x in range(x0 + 1, x1, 4):
            rect(f, x, 10, x, y1, 5)
            if x + 2 <= x1:
                rect(f, x + 2, 12, x + 2, y1, 7)
    rect(f, 3, 60, 13, 60, 4)                         # tie-back
    # Shelf with books and the box spot (Layout: box at 120, 36).
    rect(f, 96, 44, 148, 46, 2)
    rect(f, 96, 47, 148, 47, 1)
    for bx in (100, 143):
        rect(f, bx, 48, bx + 1, 53, 1)
    for i, (x, hgt, c) in enumerate([(98, 11, 9), (101, 13, 6), (104, 10, 4), (107, 12, 2),
                                     (131, 12, 10), (134, 10, 5), (137, 13, 3), (140, 11, 9), (143, 9, 2)]):
        rect(f, x, 44 - hgt, x + 2, 43, c)
        rect(f, x, 44 - hgt + 2, x + 2, 44 - hgt + 2, 12)
    # A child's drawing in a frame: sun, house, grass.
    rect(f, 178, 22, 206, 44, 12)
    rect(f, 180, 24, 204, 42, 11)
    rect(f, 180, 38, 204, 42, 5)
    ellipse(f, 199, 29, 3, 3, 4)
    rect(f, 184, 32, 192, 39, 2)
    poly(f, [(182.5, 32.5), (188, 27), (193.5, 32.5)], 3)
    rect(f, 187, 36, 188, 39, 1)
    # Nightstand (the lamp stands on it) at x 80-104.
    rect(f, 80, 92, 104, 95, 10)
    rect(f, 80, 95, 104, 95, 8)
    rect(f, 82, 96, 102, 128, 9)
    rect(f, 82, 111, 102, 111, 8)
    for y in (103, 119):
        rect(f, 91, y, 93, y + 1, 4)
    rect(f, 83, 129, 85, 131, 8)
    rect(f, 99, 129, 101, 131, 8)
    # Nightlight: a little star on a plug (Layout.NIGHTLIGHT = 214, 98).
    rect(f, 211, 95, 217, 102, 12)
    rect(f, 211, 102, 217, 102, 14)
    stamp(f, 211, 93, ["...4...", "..444..", "4444444", ".44444.", "..4.4..", ".4...4."])
    # Laundry basket (the blanket fold spot sits on it).
    lb = grid(w, h)
    poly(lb, [(10, 112), (46, 112), (43, 134), (13, 134)], 4)
    lyy, lxx = mgrid(lb)
    weave = ((lxx // 3 + lyy // 2) % 2 == 0)
    shade(lb, 4, 3, weave)
    shade(lb, 4, 2, lyy >= 131)
    shade(lb, 3, 2, lyy >= 131)
    f[lb >= 0] = lb[lb >= 0]
    rect(f, 9, 110, 47, 113, 3)
    rect(f, 9, 110, 47, 110, 4)
    # The bed: headboard right, footboard left, quilt, drape and skirt.
    rect(f, 306, 54, 316, 132, 2)
    ellipse(f, 311, 55, 6, 5, 2)
    rect(f, 307, 58, 308, 130, 1)
    stamp(f, 309, 66, [".2.2.", "22222", "22c22", ".222.", "..2.."])
    for y in range(60, 128, 12):
        stamp(f, 310, y, ["44", "44"])
    rect(f, 224, 70, 230, 132, 2)
    ellipse(f, 227, 70, 4, 3, 2)
    rect(f, 225, 73, 225, 130, 1)
    rect(f, 231, 76, 305, 100, 10)                    # quilt top
    for qx in range(231, 306, 8):
        rect(f, qx, 76, qx, 100, 9)
    for qy in range(80, 101, 8):
        rect(f, 231, qy, 305, qy, 9)
    for qx in range(235, 306, 8):
        for qy in range(84, 101, 8):
            f[qy - 1, qx] = 12
    rect(f, 231, 101, 305, 109, 9)                    # quilt drape over the side
    for x in range(233, 306, 6):
        rect(f, x, 101, x, 109, 8)
    rect(f, 231, 110, 305, 126, 12)                   # bed skirt (the bed_edge spot covers part of it)
    for x in range(233, 306, 4):
        rect(f, x, 110, x, 125, 13)
    for x in range(231, 306):
        if (x // 3) % 2 == 0:
            f[126, x] = 14
    rect(f, 231, 127, 305, 128, 1)                    # soft plum shadow under the bed
    return Sprite("room_bg", w, h, 0, [f], origin="generator:room_bg")


# ---------------------------------------------------------------- the fort

def gen_fort() -> Sprite:
    """Blanket fort draped over two chairs; fairy lights along the eaves.
    Frame 1 = the fairy lights twinkle. Door: local x 26-70 (riders sit in it)."""
    frames = []
    for fr in range(2):
        w, h = 96, 64
        f = grid(w, h)
        yy, xx = mgrid(f)
        # chair backs (teal) with rails
        for x0 in (3, 83):
            rect(f, x0, 14, x0 + 1, 62, 7)
            rect(f, x0 + 8, 14, x0 + 9, 62, 7)
            for y in (16, 22):
                rect(f, x0, y, x0 + 9, y + 1, 7)
        # the blanket: a ridge, sloping sides, then hanging walls
        pts = [(2, 24), (18, 6), (78, 6), (94, 24), (93, 60), (3, 60)]
        poly(f, pts, 2)
        # wavy hem
        for x in range(3, 94):
            y = 58 + int(round(1.5 * math.sin(x / 3.0)))
            f[y:61, x] = 2
            f[y + 2:, x] = T if y + 2 < h else f[y + 2:, x]
        # polka dots and a folded crease
        for y0 in range(10, 58, 6):
            for x0 in range(4 + (3 if (y0 // 6) % 2 else 0), 94, 6):
                if f[y0, x0] == 2:
                    f[y0, x0] = 4
        shade(f, 2, 1, (xx < 8) | (xx > 88))
        for x in range(4, 92):
            if f[25, x] in (2, 4):
                f[25, x] = 1
        rect(f, 18, 6, 78, 7, 3)                      # ridge highlight
        # doorway: warm plum inside, tied-back flaps
        door = grid(w, h)
        ellipse(door, 48, 36, 22, 16, 1)
        rect(door, 26, 36, 69, 63, 1)
        f[door == 1] = 1
        inner = grid(w, h)
        ellipse(inner, 48, 38, 19, 13, 1)
        rect(inner, 29, 38, 66, 63, 1)
        edge = (door == 1) & (inner != 1)
        f[edge & (yy < 48)] = 3
        for x0 in (25, 67):
            rect(f, x0, 44, x0 + 3, 46, 4)            # ties
        # a soft cushion floor inside the fort (warm, never a black hole)
        rect(f, 29, 58, 66, 63, 2)
        rect(f, 29, 58, 66, 58, 3)
        f = outline(f)
        # fairy lights: two swags across the front of the roof, 2 px bulbs
        bulb_cols = [4, 5, 11, 3, 12, 10]
        swags = [(6, 50), (46, 90)]
        k = 0
        for x0, x1 in swags:
            for x in range(x0, x1 + 1):
                t = (x - x0) / (x1 - x0)
                y = 14 + int(round(7 * math.sin(t * math.pi)))
                f[y, x] = 14
                if (x - x0) % 5 == 2:
                    col = bulb_cols[(k + fr) % len(bulb_cols)]
                    bright = (k + fr) % 2 == 0
                    rect(f, x, y + 1, x + 1, y + 2, col)
                    if bright:
                        f[y + 1, x] = 12
                    k += 1
        frames.append(f)
    return Sprite("fort", 96, 64, 2, frames, origin="generator:fort")


# ---------------------------------------------------------------- hiding spots (rest, wiggle, lifted)

def pillow_body(w: int, h: int, x0: int, y0: int, pw: int, ph: int, base: int, lo: int, hi: int,
                deco: str, tilt: float = 0.0, squish: int = 0) -> np.ndarray:
    f = grid(w, h)
    cx, cy = x0 + pw / 2, y0 + ph / 2
    yy, xx = mgrid(f)
    # a soft rounded pillow: superellipse, optionally sheared (tilted)
    u = (xx + 0.5 - cx - tilt * (yy + 0.5 - cy)) / (pw / 2)
    v = (yy + 0.5 - cy) / ((ph - squish) / 2)
    body = (np.abs(u) ** 3 + np.abs(v) ** 3) <= 1.0
    # corner ears
    f[body] = base
    f[body & (v > 0.35)] = lo
    f[body & (v < -0.55) & (np.abs(u) < 0.7)] = hi
    if deco == "stripes":
        f[body & (np.abs(((xx - tilt * (yy - cy)) % 6) - 2.5) < 0.6) & (v <= 0.35)] = 10
    elif deco == "dots":
        f[body & ((xx + yy * 2) % 5 == 0) & (np.abs(v) < 0.6)] = 12
    return f


def gen_pillows() -> list[Sprite]:
    out = []
    for name, w, h, pw, base, lo, hi, deco in [("pillow_a", 24, 16, 22, 12, 13, 12, "stripes"),
                                                ("pillow_b", 20, 16, 18, 10, 9, 11, "dots")]:
        frames = []
        frames.append(outline(pillow_body(w, h, 1, 5, pw, 10, base, lo, hi, deco)))
        frames.append(outline(pillow_body(w, h, 1, 5, pw, 10, base, lo, hi, deco, tilt=0.25, squish=1)))
        lifted = pillow_body(w, h, 1, 2, pw, 9, base, lo, hi, deco, tilt=-0.45, squish=1)
        frames.append(outline(lifted))
        out.append(Sprite(name, w, h, 0, frames, origin=f"generator:{name}"))
    return out


def blanket_frame(lift: int) -> np.ndarray:
    w, h = 24, 16
    f = grid(w, h)
    # a stack of three soft folds
    for i, (y0, col, hi) in enumerate([(11, 2, 3), (8, 6, 5), (5, 2, 3)]):
        if i == 2 and lift:
            continue
        rect(f, 2, y0, 21, y0 + 3, col)
        rect(f, 2, y0, 21, y0, hi)
        f[y0 + 3, 2] = T
        f[y0 + 3, 21] = T
    if lift == 1:   # wiggle: the top fold pushed up at one corner
        poly(f, [(2, 6), (22, 4), (22, 8), (2, 9)], 2)
        rect(f, 2, 6, 12, 6, 3)
    if lift == 2:   # lifted: the top fold flipped up like a flap
        poly(f, [(2, 8), (8, 0), (12, 0), (8, 8)], 2)
        poly(f, [(8, 8), (12, 0), (22, 1), (22, 8)], 3)
        rect(f, 3, 8, 21, 8, 1)
    for x in range(3, 21, 4):                    # stitches on the folds
        for y0 in (12, 9):
            if f[y0 + 1, x] in (2, 6):
                f[y0 + 1, x] = 4
    return outline(f)


def gen_blanket_fold() -> Sprite:
    return Sprite("blanket_fold", 24, 16, 0, [blanket_frame(0), blanket_frame(1), blanket_frame(2)],
                  origin="generator:blanket_fold")


def box_frame(state: int) -> np.ndarray:
    f = grid(16, 16)
    rect(f, 2, 6, 13, 14, 3)
    rect(f, 11, 6, 13, 14, 2)                    # shaded side
    rect(f, 2, 9, 13, 10, 4)                     # tape
    stamp(f, 5, 11, [".c.c.", "ccccc", ".ccc.", "..c.."])   # a heart sticker
    if state == 0:
        rect(f, 1, 4, 14, 5, 4)                  # closed lid
        rect(f, 1, 5, 14, 5, 3)
    elif state == 1:
        poly(f, [(1, 4), (15, 2), (15, 4), (1, 6)], 4)
        rect(f, 2, 6, 13, 6, 1)
    else:
        rect(f, 3, 6, 12, 7, 1)                  # the open box: warm plum inside
        poly(f, [(1, 6), (3, 0), (5, 0), (4, 6)], 4)   # flaps up
        poly(f, [(11, 6), (12, 0), (14, 0), (14, 6)], 4)
    return outline(f)


def gen_box() -> Sprite:
    return Sprite("box", 16, 16, 0, [box_frame(0), box_frame(1), box_frame(2)], origin="generator:box")


def curtain_frame(state: int) -> np.ndarray:
    f = grid(16, 24)
    if state < 2:
        sway = 1 if state == 1 else 0
        for y in range(0, 22):
            dx = sway * (y // 8)
            rect(f, 1 + dx, y, 14 + dx if y > 7 else 14, y, 6)
        for x in range(2, 14, 4):
            for y in range(0, 22):
                dx = sway * (y // 8)
                f[y, min(15, x + dx)] = 5
                if x + 2 < 14:
                    f[y, min(15, x + 2 + dx)] = 7
        for x in range(1, 15, 3):                # pompom hem
            f[22, min(15, x + sway * 2)] = 4
    else:
        poly(f, [(1, 0), (14, 0), (6, 22), (1, 22)], 6)  # gathered to the left
        for y in range(0, 22):
            f[y, 2] = 5
            f[y, 4] = 7 if y < 16 else f[y, 4]
        rect(f, 1, 12, 7, 13, 4)                 # tie
    return outline(f)


def gen_curtain() -> Sprite:
    return Sprite("curtain", 16, 24, 0, [curtain_frame(0), curtain_frame(1), curtain_frame(2)],
                  origin="generator:curtain")


def bed_edge_frame(state: int) -> np.ndarray:
    w, h = 32, 16
    f = grid(w, h)
    if state < 2:
        top = 0 if state == 0 else 1
        rect(f, 0, top, 31, 14, 12)
        for x in range(1, 32, 4):
            rect(f, x, top, x, 14, 13)
        for x in range(0, 32):
            if ((x + state) // 3) % 2 == 0:
                f[15, x] = 14
        if state == 1:
            rect(f, 0, 0, 31, 0, T)
    else:
        rect(f, 0, 5, 31, 15, 1)                 # under the bed: warm plum, never black
        rect(f, 0, 13, 31, 15, 2)
        for x in range(2, 30, 7):
            f[9, x] = 4                          # a few dust-bunny sparkles
        for y in range(0, 5):
            rect(f, 0, y, 31, y, 12)
        for x in range(0, 32, 3):
            f[4, x] = 13
            f[5, x] = 14
    return f


def gen_bed_edge() -> Sprite:
    return Sprite("bed_edge", 32, 16, 0, [bed_edge_frame(0), bed_edge_frame(1), bed_edge_frame(2)],
                  origin="generator:bed_edge")


# ---------------------------------------------------------------- toys (idle, happy hop) and tips

def toy_teddy(fr: int) -> np.ndarray:
    f = grid(16, 16)
    arm_y = 10 if fr == 0 else 8
    ellipse(f, 8, 12, 4.6, 3.2, 3)
    ellipse(f, 3.5, arm_y, 1.6, 1.6, 3)
    ellipse(f, 12.5, arm_y, 1.6, 1.6, 3)
    ellipse(f, 4, 3.6, 1.9, 1.9, 3)
    ellipse(f, 12, 3.6, 1.9, 1.9, 3)
    f[3, 3] = 2
    f[3, 12] = 2
    ellipse(f, 8, 7, 4.6, 4.1, 3)
    ellipse(f, 8, 12.3, 2.3, 1.8, 4)
    ellipse(f, 8, 8.6, 2.2, 1.6, 4)
    f[6, 6] = 0
    f[6, 9] = 0
    rect(f, 7, 8, 8, 8, 0)
    if fr == 1:
        stamp(f, 6, 9, ["0..0", ".00."])
    else:
        f[9, 7] = 1
        f[9, 8] = 1
    f[7, 5] = 2
    f[7, 10] = 2
    return f


def toy_bunny(fr: int) -> np.ndarray:
    f = grid(16, 16)
    ellipse(f, 8, 12.4, 4.2, 2.4, 12)
    ellipse(f, 6, 4, 1.4, 3.4, 12)
    ellipse(f, 10, 4, 1.4, 3.4, 12)
    rect(f, 6, 2, 6, 5, 2)
    rect(f, 9, 2, 9, 5, 2)
    ellipse(f, 8, 8.6, 4.1, 3.4, 12)
    yy, xx = mgrid(f)
    shade(f, 12, 13, (yy >= 13) | ((xx >= 11) & (yy >= 9)))
    f[8, 6] = 0
    f[8, 9] = 0
    rect(f, 7, 9, 8, 9, 2)
    if fr == 1:
        stamp(f, 7, 10, ["00"])
        ellipse(f, 3, 9, 1.3, 1.3, 12)
        ellipse(f, 13, 9, 1.3, 1.3, 12)
    f[9, 5] = 2
    f[9, 10] = 2
    return f


def toy_duck(fr: int) -> np.ndarray:
    f = grid(16, 16)
    ellipse(f, 8.5, 11, 5.6, 3.2, 4)
    ellipse(f, 13.2, 8.6, 1.4, 1.6, 4)        # tail
    ellipse(f, 6, 6, 3.2, 3.0, 4)
    rect(f, 1, 6, 2, 7, 3) if fr == 0 else rect(f, 1, 5, 2, 7, 3)
    f[5, 5] = 0
    yy, xx = mgrid(f)
    shade(f, 4, 3, (yy >= 13))
    wing = [".333.", "34443", ".333."] if fr == 0 else [".3...", "343..", "3443.", ".333."]
    stamp(f, 8, 9 if fr == 0 else 7, wing)
    f[7, 4] = 2
    return f


def toy_ball(fr: int) -> np.ndarray:
    f = grid(16, 16)
    ellipse(f, 8, 8.5, 6.0, 6.0, 12)
    yy, xx = mgrid(f)
    inside = f == 12
    u = (xx + 0.5 - 8) / 6.0
    band = np.floor((u + 1.0) * 2.5 + (1 if fr else 0) * 0.5).astype(int) % 3
    f[inside & (band == 0)] = 2
    f[inside & (band == 1)] = 12
    f[inside & (band == 2)] = 9
    ellipse(f, 8, 3.2, 1.2, 0.8, 4)
    stamp(f, 4, 4, ["c.", ".c"])
    shade(f, 12, 13, (yy >= 12))
    return f


def toy_blocks(fr: int) -> np.ndarray:
    f = grid(16, 16)
    rect(f, 1, 8, 7, 14, 9)
    rect(f, 7, 8, 7, 14, 8)
    rect(f, 1, 14, 7, 14, 8)
    stamp(f, 2, 9, ["..c..", ".ccc.", "..c.."])
    rect(f, 8, 8, 14, 14, 2)
    rect(f, 14, 8, 14, 14, 1)
    rect(f, 8, 14, 14, 14, 1)
    stamp(f, 10, 10, ["cc", "cc"])
    dx = 0 if fr == 0 else 1
    rect(f, 4 + dx, 2, 10 + dx, 7, 4)
    rect(f, 10 + dx, 2, 10 + dx, 7, 3)
    rect(f, 4 + dx, 7, 10 + dx, 7, 3)
    stamp(f, 5 + dx, 3, [".2.2", "2222", ".22."])
    return f


def toy_dino(fr: int) -> np.ndarray:
    f = grid(16, 16)
    ellipse(f, 7.5, 10.5, 4.8, 3.0, 6)
    poly(f, [(3, 9), (1, 11.5), (3, 13)], 6)            # tail
    ellipse(f, 11.5, 6, 3.0, 2.6, 6)                    # head
    rect(f, 10, 7, 12, 10, 6)                           # neck
    rect(f, 4, 13, 5, 14, 6)
    rect(f, 9, 13, 10, 14, 6)
    ellipse(f, 8, 11.5, 2.8, 1.5, 5)                    # belly
    for x in (4, 7, 10):                                # spikes
        f[7, x] = 4
        f[6, x] = 4 if x < 10 else f[6, x]
    f[3, 11] = 4
    f[5, 12] = 0
    if fr == 1:
        stamp(f, 11, 7, ["0000", ".00."])
    else:
        stamp(f, 11, 7, ["0..0", ".00."])
    return f


def toy_car(fr: int) -> np.ndarray:
    f = grid(16, 16)
    dy = 0 if fr == 0 else -1
    rect(f, 1, 8 + dy, 14, 12 + dy, 2)
    poly(f, [(3.5, 8.5 + dy), (5, 4 + dy), (11, 4 + dy), (12.5, 8.5 + dy)], 2)
    rect(f, 5, 5 + dy, 7, 7 + dy, 11)
    rect(f, 9, 5 + dy, 10, 7 + dy, 11)
    rect(f, 1, 12 + dy, 14, 12 + dy, 1)
    f[9 + dy, 14] = 4
    f[9 + dy, 1] = 3
    rect(f, 2, 9 + dy, 13, 9 + dy, 3)
    for cx in (4.5, 11.5):
        ellipse(f, cx, 12.8, 1.9, 1.9, 15)
        f[12, int(cx)] = 13
    return f


def toy_doll(fr: int) -> np.ndarray:
    f = grid(16, 16)
    poly(f, [(8, 8), (13, 14.5), (3, 14.5)], 2)          # dress
    f[11, 7] = 12
    f[13, 5] = 12
    f[12, 10] = 12
    arm_y = 10 if fr == 0 else 8
    ellipse(f, 3.5, arm_y, 1.2, 1.2, 4)
    ellipse(f, 12.5, arm_y, 1.2, 1.2, 4)
    ellipse(f, 3.5, 6.5, 1.6, 2.2, 1)                   # pigtails
    ellipse(f, 12.5, 6.5, 1.6, 2.2, 1)
    ellipse(f, 8, 6, 3.7, 3.6, 4)                       # face
    rect(f, 5, 2, 10, 3, 1)                             # yarn hair
    f[4, 5] = 1
    f[4, 10] = 1
    f[2, 7] = 2
    f[2, 8] = 2
    f[6, 6] = 0
    f[6, 9] = 0
    f[7, 5] = 2
    f[7, 10] = 2
    if fr == 1:
        stamp(f, 7, 8, ["00"])
    else:
        stamp(f, 6, 8, ["0..0"])
        stamp(f, 7, 9, ["00"])
    return f


TOYS = {"teddy": toy_teddy, "bunny": toy_bunny, "duck": toy_duck, "ball": toy_ball, "blocks": toy_blocks,
        "dino": toy_dino, "car": toy_car, "doll": toy_doll}
# The 8x8 tip cut from frame 0 of each toy: what peeks out of a hiding spot.
TIPS = {"teddy": (0, 1), "bunny": (4, 0), "duck": (1, 2), "ball": (4, 1), "blocks": (4, 1),
        "dino": (8, 2), "car": (4, 3), "doll": (4, 1)}


def gen_toys() -> list[Sprite]:
    out = []
    for name, fn in TOYS.items():
        idle = outline(fn(0))
        hop = shift(outline(fn(1)), 0, -1)
        out.append(Sprite(name, 16, 16, 4, [idle, hop], origin=f"generator:{name}"))
        x, y = TIPS[name]
        tip = idle[y:y + 8, x:x + 8].copy()
        out.append(Sprite(f"tip_{name}", 8, 8, 0, [tip], origin=f"generator:tip_{name}"))
    return out


# ---------------------------------------------------------------- peekaboo friends (hidden, eyes covered, peekaboo, duck back)

FRIENDS = {
    "teddy_big": {"body": 3, "lo": 2, "muzzle": 4, "inner": 2, "ears": "round", "head_y": 12},
    "bunny_big": {"body": 12, "lo": 13, "muzzle": 12, "inner": 2, "ears": "long", "head_y": 13},
    "sleepy_cat": {"body": 13, "lo": 14, "muzzle": 12, "inner": 2, "ears": "cat", "head_y": 12},
}


def friend_frame(kind: str, fr: int) -> np.ndarray:
    p = FRIENDS[kind]
    f = grid(24, 24)
    hy = p["head_y"]
    b, lo = p["body"], p["lo"]
    ellipse(f, 12, 22, 6.5, 4.0, b)                         # shoulders (hidden behind the spot)
    if p["ears"] == "round":
        ellipse(f, 5.5, hy - 5.5, 2.6, 2.6, b)
        ellipse(f, 18.5, hy - 5.5, 2.6, 2.6, b)
        ellipse(f, 5.5, hy - 5.5, 1.2, 1.2, p["inner"])
        ellipse(f, 18.5, hy - 5.5, 1.2, 1.2, p["inner"])
    elif p["ears"] == "long":
        droop = 1 if fr == 3 else 0
        ellipse(f, 8.5 - droop, hy - 8, 1.9, 5.2, b)
        ellipse(f, 15.5 + droop, hy - 8, 1.9, 5.2, b)
        rect(f, 8 - droop, hy - 11, 8 - droop, hy - 6, p["inner"])
        rect(f, 15 + droop, hy - 11, 15 + droop, hy - 6, p["inner"])
    else:
        poly(f, [(4, hy - 2), (5.5, hy - 9), (10, hy - 5)], b)
        poly(f, [(20, hy - 2), (18.5, hy - 9), (14, hy - 5)], b)
        poly(f, [(5.5, hy - 3.5), (6, hy - 7), (8.5, hy - 5)], p["inner"])
        poly(f, [(18.5, hy - 3.5), (18, hy - 7), (15.5, hy - 5)], p["inner"])
    ellipse(f, 12, hy, 7.6, 6.4, b)                        # head
    yy, xx = mgrid(f)
    shade(f, b, lo, (yy >= hy + 5) & (yy < 19))
    if kind == "sleepy_cat":
        for x in (10, 12, 14):
            f[hy - 5, x] = 14
            f[hy - 4, x] = 14 if x == 12 else f[hy - 4, x]
    ellipse(f, 12, hy + 2.6, 3.2, 2.2, p["muzzle"])
    rect(f, 11, hy + 1, 12, hy + 1, 2 if kind != "teddy_big" else 0)   # nose
    ex1, ex2, ey = 8, 15, hy - 1
    if fr == 2:
        stamp(f, 9, hy + 3, ["0..0", "0220", ".00."])       # open happy "boo!"
        for ex in (ex1, ex2):
            rect(f, ex, ey - 1, ex + 1, ey, 0)
            f[ey - 1, ex] = 12                              # glint (small, warm-lit)
        f[hy + 2, 6] = 2
        f[hy + 2, 7] = 2
        f[hy + 2, 16] = 2
        f[hy + 2, 17] = 2
    else:
        if fr == 3 or (kind == "sleepy_cat" and fr == 0):
            stamp(f, ex1 - 1, ey, [".00.", "0..0"]) if fr == 3 else rect(f, ex1, ey, ex1 + 1, ey, 0)
            stamp(f, ex2 - 1, ey, [".00.", "0..0"]) if fr == 3 else rect(f, ex2, ey, ex2 + 1, ey, 0)
        else:
            rect(f, ex1, ey - 1, ex1, ey, 0)
            rect(f, ex2 + 1, ey - 1, ex2 + 1, ey, 0)
        stamp(f, 10, hy + 3, ["0..0", ".00."])
    paw = b if kind != "teddy_big" else 3
    if fr == 1:       # paws over the eyes
        for cx in (8.5, 15.5):
            ellipse(f, cx, ey - 0.5, 2.8, 2.4, paw)
            f[int(ey + 1), int(cx)] = lo
        rect(f, 7, ey - 2, 7, ey - 2, 4 if kind == "teddy_big" else 13)
    elif fr == 2:     # paws out wide: ta-da!
        ellipse(f, 2.5, hy + 1, 2.2, 2.2, paw)
        ellipse(f, 21.5, hy + 1, 2.2, 2.2, paw)
        f[hy + 1, 2] = p["inner"]
        f[hy + 1, 21] = p["inner"]
    else:             # paws holding the edge of the spot
        for cx in (7.5, 16.5):
            ellipse(f, cx, 20.5, 2.4, 1.8, paw)
            f[20, int(cx)] = lo
    out = outline(f)
    out[23, :] = f[23, :]  # the bottom row stays open (it sits behind the spot)
    return out


def gen_friends() -> list[Sprite]:
    return [Sprite(k, 24, 24, 0, [friend_frame(k, i) for i in range(4)], origin=f"generator:{k}") for k in FRIENDS]


# ---------------------------------------------------------------- surprises, pointer, basket, lamp, fx

def gen_surprises() -> list[Sprite]:
    sock = []
    for fr in range(2):
        f = grid(8, 8)
        stamp(f, 2, 0, ["ccc", "222", "ccc", "222"])
        stamp(f, 1, 4, ["cccc.", "22222", ".222."] if fr == 0 else ["cccc.", "2222.", "222.."])
        sock.append(outline(f))
    cookie = []
    for fr in range(2):
        f = grid(8, 8)
        ellipse(f, 4, 4, 3.4, 3.2, 3)
        yy, xx = mgrid(f)
        shade(f, 3, 2, yy >= 6)
        for x, y in [(2, 3), (5, 2), (4, 5), (6, 4)]:
            f[y, x] = 1
        f[2, 3] = 4
        if fr == 1:
            ellipse(f, 7.5, 1.5, 1.6, 1.6, T)        # a bite
        cookie.append(f)
    mouse = []
    for fr in range(2):
        f = grid(16, 16)
        ellipse(f, 7, 11.5, 4.5, 3.2, 13)          # body
        ellipse(f, 7, 7.5, 3.6, 3.1, 13)           # head
        ellipse(f, 3.5, 4.5, 1.8, 1.8, 13)
        ellipse(f, 10.5, 4.5, 1.8, 1.8, 13)
        f[4, 3] = 2
        f[4, 10] = 2
        f[7, 5] = 0                                  # sleepy closed eyes
        f[7, 8] = 0
        f[8, 4] = 0
        f[8, 9] = 0
        f[7, 4] = 13
        rect(f, 6, 9, 7, 9, 2)                       # nose
        # nightcap
        poly(f, [(4, 4), (10, 4), (13, 0.5)], 9)
        f[0, 13] = 12
        f[1, 13] = 12
        rect(f, 4, 4, 10, 4, 12)
        # tail
        for x, y in [(12, 13), (13, 12), (14, 11), (14, 10)]:
            f[y, x] = 2
        # waving paw
        if fr == 0:
            ellipse(f, 11.5, 10, 1.3, 1.3, 13)
        else:
            ellipse(f, 12, 7.5, 1.3, 1.3, 13)
        mouse.append(outline(f))
    return [Sprite("sock", 8, 8, 3, sock, origin="generator:sock"),
            Sprite("cookie", 8, 8, 2, cookie, origin="generator:cookie"),
            Sprite("sleepy_mouse", 16, 16, 3, mouse, origin="generator:sleepy_mouse")]


def paw_frame(fr: int) -> np.ndarray:
    f = grid(16, 16)
    ellipse(f, 8, 10.5, 3.8, 3.2, 12)
    for cx, cy in [(3.3, 6.3), (6.3, 3.8), (9.7, 3.8), (12.7, 6.3)]:
        ellipse(f, cx, cy, 1.5, 1.8, 12)
    yy, _ = mgrid(f)
    if fr == 0:
        shade(f, 12, 13, yy >= 12)
    return outline(f)


def gen_misc() -> list[Sprite]:
    out = [Sprite("paw_pointer", 16, 16, 3, [paw_frame(0), paw_frame(1)], origin="generator:paw_pointer")]
    # toy basket: empty, half, full
    frames = []
    for fr in range(3):
        f = grid(32, 24)
        poly(f, [(1, 7), (31, 7), (27, 23), (5, 23)], 4)
        yy, xx = mgrid(f)
        weave = ((xx // 3 + yy // 2) % 2 == 0)
        shade(f, 4, 3, weave)
        shade(f, 4, 2, yy >= 21)
        shade(f, 3, 2, yy >= 21)
        ellipse(f, 16, 6.5, 14, 2.4, 1 if fr == 0 else 5)       # opening: plum inside, or a blanket
        if fr == 2:
            f[(f == 5) & ((xx + yy) % 3 == 0)] = 6
        rect(f, 1, 7, 30, 8, 3)                                 # rim
        rect(f, 1, 7, 30, 7, 4)
        for x in range(2, 30, 4):
            f[8, x] = 2
        for x0 in (0, 29):                                      # side handles
            ring(f, x0 + 1.5, 11, 2.2, 2.4, 1.0, 3)
        if fr >= 1:
            stamp(f, 13, 12, [".2.2.", "22222", ".222.", "..2.."])   # a red heart label
        if fr == 2:
            for x, y in [(4, 3), (27, 2), (16, 1)]:
                stamp(f, x - 1, y - 1, [".c.", "c4c", ".c."])
        frames.append(outline(f))
    out.append(Sprite("toy_basket", 32, 24, 0, frames, origin="generator:toy_basket"))
    # lamp: off, on
    frames = []
    for on in range(2):
        f = grid(16, 32)
        poly(f, [(4.5, 2), (11.5, 2), (15, 14), (1, 14)], 4 if on else 3)
        rect(f, 1, 13, 14, 14, 3 if on else 2)
        yy, xx = mgrid(f)
        if on:
            f[(f == 4) & (yy >= 5) & (yy <= 10) & (np.abs(xx - 7.5) < 3)] = 12
        else:
            f[(f == 3) & ((xx + yy) % 4 == 0)] = 2
        rect(f, 7, 15, 8, 26, 12)
        rect(f, 8, 15, 8, 26, 13)
        f[15:20, 10] = 14                                        # pull chain
        f[20, 10] = 4
        ellipse(f, 8, 28.5, 5.5, 2.4, 9)
        rect(f, 3, 28, 12, 28, 10)
        frames.append(outline(f))
    out.append(Sprite("lamp", 16, 32, 0, frames, origin="generator:lamp"))
    # sparkle (white, tinted in code)
    frames = []
    for fr in range(3):
        f = grid(8, 8)
        if fr == 0:
            stamp(f, 3, 3, ["cc", "cc"])
        elif fr == 1:
            stamp(f, 1, 1, ["..c..", "..c..", "ccccc", "..c..", "..c.."])
        else:
            stamp(f, 0, 0, ["...c....", "...c....", "c..d..c.", ".c.d.c..", "..ccc...", ".c.d.c..", "c..d..c.", "...c...."])
        frames.append(f)
    out.append(Sprite("sparkle", 8, 8, 8, frames, origin="generator:sparkle"))
    # seat icons
    f = grid(16, 16)
    poly(f, [(10, 7), (15, 3), (15, 13), (10, 9)], 4)             # beam
    rect(f, 2, 6, 8, 10, 9)                                      # body
    rect(f, 4, 6, 4, 10, 14)
    rect(f, 8, 5, 10, 11, 13)                                    # head
    rect(f, 10, 6, 10, 10, 4)                                    # lens
    rect(f, 2, 10, 8, 10, 8)
    out.append(Sprite("seat_flashlight", 16, 16, 0, [outline(f)], origin="generator:seat_flashlight"))
    f = paw_frame(1)
    f[f == 12] = 4
    out.append(Sprite("seat_seeker", 16, 16, 0, [f], origin="generator:seat_seeker"))
    f = grid(16, 16)
    ellipse(f, 8, 9, 6, 5.2, 12)
    ellipse(f, 3.5, 4, 1.8, 1.8, 12)
    ellipse(f, 12.5, 4, 1.8, 1.8, 12)
    f[4, 3] = 2
    f[4, 12] = 2
    ellipse(f, 5.5, 8, 2.2, 1.8, 5)                              # green paws over the eyes
    ellipse(f, 10.5, 8, 2.2, 1.8, 5)
    stamp(f, 6, 11, ["0..0", ".00."])
    out.append(Sprite("seat_peekaboo", 16, 16, 0, [outline(f)], origin="generator:seat_peekaboo"))
    return out


GENERATORS = [gen_confetti, gen_room_bg, gen_fort, gen_pillows, gen_blanket_fold, gen_box, gen_curtain,
              gen_bed_edge, gen_toys, gen_friends, gen_surprises, gen_misc]


# ---------------------------------------------------------------- render + lint

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
