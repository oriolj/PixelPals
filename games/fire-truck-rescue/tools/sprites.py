"""Fire Truck Rescue sprites (copied from PixelPals, with this game's generators).

Render the palette-indexed sprite grids to PNG strips, lint them, draw a contact sheet.

Usage: make sprites   (uv run python games/fire-truck-rescue/tools/sprites.py)

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json (gitignored pack)
    GENERATORS (below)      -> procedural sprites (icons, truck, station, town strip...), same path
    helmet_rider()          -> h_<rider> (16x20) for every rider, public and private

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


def gen_cloud_bg() -> Sprite:
    f = grid(32, 16)
    for cx, cy, r in ((7, 10.5, 4), (13, 7.2, 5), (20, 5.8, 4.8), (26, 9.5, 4.2), (16, 11, 4.5), (19, 10, 5)):
        ellipse(f, cx, cy, r, r, 12)
    rect(f, 6, 11, 27, 14, 12)
    yy, _ = np.mgrid[0:16, 0:32]
    shade(f, 12, 13, yy >= 13)
    return Sprite("cloud_bg", 32, 16, 0, [f], origin="generator:cloud_bg")


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



# Fire Truck Rescue generators. Sweetie 16 indices:
# 0 ink 1 purple 2 red 3 orange 4 yellow 5 lime 6 green 7 teal 8 navy 9 blue
# 10 sky 11 cyan 12 white 13 grey 14 slate 15 dark


def yx(f: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
    return np.mgrid[0:f.shape[0], 0:f.shape[1]]


def gen_seat_hose() -> Sprite:
    """Hose nozzle (brass) spraying water to the right."""
    f = grid(16, 16)
    rect(f, 1, 11, 4, 13, 2)                 # red hose coming in
    rect(f, 3, 9, 5, 12, 2)
    poly(f, [(4, 6.5), (10.5, 7.5), (10.5, 10.5), (4, 11.5)], 4)
    yy, _ = yx(f)
    shade(f, 4, 3, yy >= 10)
    rect(f, 10, 8, 11, 10, 13)               # tip
    f[8, 5] = 12
    for x, y in ((12, 6), (13, 9), (12, 11), (14, 7), (14, 11)):
        f[y, x] = 11 if (x + y) % 2 else 10
    return Sprite("seat_hose", 16, 16, 0, [outline(f)], origin="generator:seat_hose")


def gen_seat_siren() -> Sprite:
    """A siren light: red dome on a grey base, yellow rays."""
    f = grid(16, 16)
    ellipse(f, 8, 10, 4.6, 5.2, 2)
    f[10:, :] = np.where(f[10:, :] == 2, T, f[10:, :])
    rect(f, 3, 10, 12, 12, 13)
    rect(f, 3, 12, 12, 12, 14)
    rect(f, 6, 6, 6, 7, 12)
    f[5, 7] = 12
    for x, y in ((1, 4), (2, 2), (8, 1), (13, 2), (14, 4)):
        f[y, x] = 4
    f[3, 3] = 4
    f[3, 12] = 4
    return Sprite("seat_siren", 16, 16, 0, [outline(f)], origin="generator:seat_siren")


def flame_shape(f: np.ndarray, cx: float, base: float, rx: float, top: float, sway: float, col: int) -> None:
    """A teardrop flame: round bottom, a tip at (cx + sway, top)."""
    ry = rx * 0.9
    ellipse(f, cx, base - ry, rx, ry, col)
    poly(f, [(cx - rx, base - ry), (cx + sway, top), (cx + rx, base - ry)], col)


def gen_flame_icon() -> Sprite:
    frames = []
    for i, sway in enumerate((-1.2, 1.2)):
        f = grid(16, 16)
        flame_shape(f, 8, 15, 5.8, 1.0, sway, 2)
        flame_shape(f, 8, 14.5, 4.6, 3.0, sway * 0.8, 3)
        flame_shape(f, 8, 14.2, 3.0, 6.5, sway * 0.5, 4)
        flame_shape(f, 8, 14.0, 1.6, 9.5, 0.0, 12)
        frames.append(outline(f))
    return Sprite("flame_icon", 16, 16, 4, frames, origin="generator:flame_icon")


def gen_pips() -> list[Sprite]:
    lit = []
    for sway in (-0.8, 0.8):
        f = grid(8, 8)
        flame_shape(f, 4, 8, 3.3, 0.0, sway, 2)
        flame_shape(f, 4, 7.8, 2.4, 2.0, sway * 0.6, 3)
        flame_shape(f, 4, 7.6, 1.3, 4.0, 0.0, 4)
        lit.append(f)
    out = grid(8, 8)
    for cx, cy, r in ((2.8, 5.0, 2.2), (5.2, 4.6, 2.4), (4.0, 3.2, 2.0)):
        ellipse(out, cx, cy, r, r * 0.9, 13)
    ellipse(out, 3.4, 2.8, 1.0, 0.8, 12)
    rect(out, 1, 6, 6, 6, 14)
    return [Sprite("pip_flame", 8, 8, 6, lit, origin="generator:pip_flame"),
            Sprite("pip_flame_out", 8, 8, 0, [out], origin="generator:pip_flame_out")]


CAT_FACE = [
    "3......3",
    "33....33",
    "33333333",
    "30333303",
    "33322333",
    ".333333.",
]


def cat_face(f: np.ndarray, x: int, y: int) -> None:
    layer = grid(f.shape[1], f.shape[0])
    stamp(layer, x, y, CAT_FACE)
    layer = outline(layer, 1)
    f[layer >= 0] = layer[layer >= 0]


def gen_badges() -> list[Sprite]:
    f = grid(16, 16)
    ellipse(f, 8, 8, 7.0, 7.0, 4)
    yy, xx = yx(f)
    shade(f, 4, 3, (xx - 8) + (yy - 8) > 5)
    ellipse(f, 8, 8, 5.4, 5.4, 12)
    cat_face(f, 4, 5)
    f[3, 5] = 12
    full = outline(f)
    e = grid(16, 16)
    ellipse(e, 8, 8, 7.0, 7.0, 15)
    ring = grid(16, 16)
    ellipse(ring, 8, 8, 7.0, 7.0, 13)
    ellipse(ring, 8, 8, 5.8, 5.8, T)
    ang = np.arctan2(yy - 7.5, xx - 7.5)
    dashed = (ring == 13) & (np.floor((ang + math.pi) / (math.pi / 6)) % 2 == 0)
    e[dashed] = 14
    return [Sprite("badge_cat", 16, 16, 0, [full], origin="generator:badge_cat"),
            Sprite("badge_empty", 16, 16, 0, [e], origin="generator:badge_empty")]


def gen_cat_icon() -> Sprite:
    """Floating 'a cat needs you' bubble above a cat tree."""
    frames = []
    for dy in (0, 1):
        f = grid(16, 16)
        ellipse(f, 8, 7 + dy, 6.6, 6.0, 12)
        poly(f, [(5, 11 + dy), (8, 11 + dy), (4, 15)], 12)
        cat_face(f, 4, 4 + dy)
        frames.append(outline(f))
    return Sprite("cat_icon", 16, 16, 3, frames, origin="generator:cat_icon")


def gen_home_icon() -> Sprite:
    f = grid(16, 16)
    rect(f, 3, 7, 12, 13, 2)
    poly(f, [(1.5, 7.5), (8, 1.5), (14.5, 7.5)], 14)
    rect(f, 6, 9, 9, 13, 15)
    rect(f, 6, 9, 9, 9, 13)
    f[4, 8] = 4
    f[4, 7] = 4
    return Sprite("home_icon", 16, 16, 0, [outline(f)], origin="generator:home_icon")


def gen_bucket() -> Sprite:
    f = grid(24, 24)
    # Stars poking out first (behind the rim).
    poly(f, star_points(8.5, 6.0, 4.2, 2.0), 4)
    poly(f, star_points(15.5, 5.0, 3.8, 1.8), 4)
    f[5, 8] = 12
    f[4, 15] = 12
    poly(f, [(3.5, 9), (20.5, 9), (18, 22.5), (6, 22.5)], 2)
    yy, xx = yx(f)
    shade(f, 2, 1, xx >= 16)
    rect(f, 3, 8, 20, 9, 13)
    rect(f, 5, 14, 18, 15, 12)
    rect(f, 7, 11, 7, 20, 3)
    ring = grid(24, 24)
    ellipse(ring, 12, 9, 9.5, 7.5, 13)
    ellipse(ring, 12, 9, 8.3, 6.3, T)
    ring[9:, :] = T
    f[(ring == 13) & (f < 0)] = 14
    return Sprite("bucket", 24, 24, 0, [outline(f)], origin="generator:bucket")


def helmet_frame(view: int) -> np.ndarray:
    """Gold fire helmet: 0 front, 1 three-quarter, 2 side."""
    f = grid(24, 24)
    squash = (1.0, 0.8, 0.62)[view]
    ellipse(f, 12, 12, 8.0 * (0.85 + 0.15 * squash), 7.5, 4)
    f[13:, :] = np.where(f[13:, :] == 4, T, f[13:, :])
    # Brim: wide, longer at the back in the side views.
    back = (0.0, 2.0, 4.0)[view]
    ellipse(f, 12 - back / 2, 14, 11.0 * (0.7 + 0.3 * squash) + back / 2, 2.6, 3)
    rect(f, 5, 12, 19, 13, 4)
    yy, xx = yx(f)
    shade(f, 4, 3, xx >= 15)
    # Crest along the top.
    cw = (1, 3, 6)[view]
    rect(f, 12 - cw // 2, 4, 12 + (cw + 1) // 2 - 1, 5, 3)
    # Front badge: a red shield with a yellow dot, moving round with the view.
    bx = (12, 15, 17)[view]
    bw = (3, 2, 1)[view]
    rect(f, bx - bw, 7, bx + bw - 1, 11, 2)
    f[9, bx] = 12 if view < 2 else 2
    # Shine.
    rect(f, 8, 7, 8, 9, 12)
    f[6, 9] = 12
    out = outline(f)
    stamp(out, 2, 1, [".c.", "cbc", ".c."] if view == 0 else ["...", ".b.", "..."])
    return out


def gen_trophy_helmet() -> Sprite:
    frames = [helmet_frame(0), helmet_frame(1), helmet_frame(2), mirror(helmet_frame(1))]
    return Sprite("trophy_helmet", 24, 24, 6, frames, origin="generator:trophy_helmet")


def truck_side_frame(flash: int) -> np.ndarray:
    f = grid(112, 56)
    # Mudguards behind the wheels.
    for cx in (26, 86):
        ellipse(f, cx, 44, 11, 9, 2)
    rect(f, 6, 36, 108, 42, 15)               # chassis
    rect(f, 6, 20, 72, 38, 2)                 # body
    rect(f, 6, 20, 72, 21, 4)                 # gold trim
    rect(f, 6, 28, 72, 30, 12)                # white stripe
    for x0 in (12, 34, 54):                   # compartment doors
        rect(f, x0, 23, x0 + 14, 27, 3)
        rect(f, x0, 31, x0 + 14, 36, 3)
        rect(f, x0 + 12, 33, x0 + 13, 33, 13)
    rect(f, 72, 12, 100, 40, 2)               # cab
    rect(f, 72, 12, 100, 13, 4)
    rect(f, 76, 16, 86, 25, 11)               # side window
    rect(f, 76, 16, 86, 16, 12)
    poly(f, [(89, 16), (99, 16), (103, 26), (89, 26)], 11)
    rect(f, 91, 17, 92, 18, 12)
    rect(f, 72, 28, 100, 30, 12)              # stripe continues on the cab
    rect(f, 86, 32, 88, 33, 13)               # door handle
    rect(f, 100, 26, 106, 40, 2)              # hood
    rect(f, 104, 30, 107, 38, 13)             # grille
    for y in (31, 33, 35, 37):
        rect(f, 104, y, 107, y, 14)
    rect(f, 104, 27, 108, 29, 4)              # headlight
    rect(f, 96, 40, 109, 43, 13)              # bumper
    rect(f, 1, 38, 8, 40, 13)                 # rear step
    ellipse(f, 8, 29, 5.2, 5.2, 4)            # hose reel
    ellipse(f, 8, 29, 2.5, 2.5, 3)
    f[29, 8] = 15
    # Ladder on top.
    rect(f, 4, 15, 78, 15, 12)
    rect(f, 4, 18, 78, 18, 13)
    for x in range(6, 78, 5):
        rect(f, x, 15, x, 18, 13)
    rect(f, 14, 19, 15, 19, 15)
    rect(f, 60, 19, 61, 19, 15)
    # Light bar on the cab roof.
    rect(f, 78, 10, 94, 11, 12)
    rect(f, 79, 7, 85, 9, 11 if flash == 0 else 9)
    rect(f, 87, 7, 93, 9, 12 if flash == 1 else 2)
    if flash == 1:
        rect(f, 88, 8, 92, 8, 2)
    # Bell.
    ellipse(f, 101, 22, 2.2, 2.4, 4)
    f[24, 101] = 3
    # Wheels.
    for cx in (26, 86):
        ellipse(f, cx, 46, 8.2, 8.2, 0)
        ellipse(f, cx, 46, 4.2, 4.2, 13)
        ellipse(f, cx, 46, 1.6, 1.6, 15)
        f[46 - 3 + flash * 6, cx] = 12
    return outline(f)


def gen_truck_side() -> Sprite:
    return Sprite("truck_side", 112, 56, 4, [truck_side_frame(0), truck_side_frame(1)], origin="generator:truck_side")


def gen_station_front() -> Sprite:
    w, h = 176, 112
    f = grid(w, h)
    rect(f, 8, 30, 167, 111, 2)
    for i, y in enumerate(range(34, 108, 6)):
        off = 0 if i % 2 == 0 else 6
        for x in range(10 + off, 164, 12):
            rect(f, x, y, x + 8, y, 3)
            f[y + 1, x] = 1 if f[y + 1, x] == 2 else f[y + 1, x]
    poly(f, [(2, 33), (88, 4), (173, 33)], 14)
    for t in range(0, 88):
        y = int(33 - t * 29 / 86)
        f[y, 2 + t] = 12
        f[y, 173 - t] = 12
    rect(f, 4, 30, 171, 33, 12)
    ellipse(f, 88, 22, 7.5, 7.5, 4)
    ellipse(f, 88, 22, 5.5, 5.5, 3)
    poly(f, star_points(88, 22.5, 5.2, 2.3), 2)
    # The open door: dark bay, floor, the rolled-up door at the top.
    rect(f, 45, 43, 130, 111, 12)
    rect(f, 48, 46, 127, 111, 15)
    rect(f, 48, 98, 127, 111, 14)
    for x in range(52, 127, 10):
        rect(f, x, 104, x + 4, 104, 4)
    rect(f, 49, 47, 126, 53, 13)
    for y in (48, 50, 52):
        rect(f, 49, y, 126, y, 14)
    # Windows and lamps.
    for x0 in (16, 139):
        rect(f, x0, 50, x0 + 20, 72, 12)
        rect(f, x0 + 2, 52, x0 + 18, 70, 11)
        rect(f, x0 + 10, 52, x0 + 10, 70, 12)
        rect(f, x0 + 2, 61, x0 + 18, 61, 12)
        rect(f, x0 + 3, 53, x0 + 5, 55, 12)
    for x0 in (38, 135):
        rect(f, x0, 46, x0 + 2, 50, 4)
        f[45, x0 + 1] = 13
    rect(f, 8, 108, 167, 111, 13)
    return Sprite("station_front", w, h, 0, [outline(f)], origin="generator:station_front")


def gen_town_strip() -> Sprite:
    """Menu backdrop: green hills, a row of toy houses, trees and the station."""
    w, h = 480, 64
    f = grid(w, h)
    xs = np.arange(w)
    far = np.round(30 + 6 * np.sin(xs * 2 * math.pi / 240) + 3 * np.sin(xs * 2 * math.pi / 96 + 1.0)).astype(int)
    for x in range(w):
        f[far[x]:, x] = 7
        f[far[x], x] = 5
    rnd = random.Random(11)
    x = 4
    while x < w - 20:
        if 280 <= x <= 330:
            x = 336
            continue
        kind = rnd.random()
        base = 56
        if kind < 0.3:
            ellipse(f, x + 6, base - 11, 6, 6, 6)
            ellipse(f, x + 4, base - 13, 2, 1.5, 5)
            rect(f, x + 5, base - 6, x + 6, base, 15)
            x += 14
        else:
            hw = rnd.randint(14, 22)
            hh = rnd.randint(10, 16)
            wall = rnd.choice((12, 4, 13, 5))
            roof = rnd.choice((2, 3, 9, 7))
            rect(f, x, base - hh, x + hw, base, wall)
            poly(f, [(x - 2, base - hh + 0.5), (x + hw / 2, base - hh - 9), (x + hw + 2, base - hh + 0.5)], roof)
            rect(f, x + hw // 2 - 2, base - 7, x + hw // 2 + 1, base, rnd.choice((2, 9, 1)))
            rect(f, x + 2, base - hh + 3, x + 5, base - hh + 6, 11)
            rect(f, x + hw - 5, base - hh + 3, x + hw - 2, base - hh + 6, 11)
            x += hw + rnd.randint(4, 10)
    # The station with its hose tower.
    rect(f, 284, 30, 326, 56, 2)
    poly(f, [(282, 30.5), (305, 20), (328, 30.5)], 14)
    rect(f, 296, 40, 314, 56, 15)
    rect(f, 296, 40, 314, 42, 13)
    rect(f, 318, 14, 326, 30, 2)
    poly(f, [(316, 14.5), (322, 6), (328, 14.5)], 15)
    rect(f, 320, 18, 324, 22, 12)
    ellipse(f, 305, 26, 2, 2, 4)
    out = outline(f)
    rect(out, 0, 57, w - 1, 63, 6)
    rect(out, 0, 57, w - 1, 57, 5)
    for k in range(40):
        out[rnd.randrange(59, 64), rnd.randrange(w)] = rnd.choice((5, 4, 12))
    return Sprite("town_strip", w, h, 0, [out], origin="generator:town_strip")


HELMET = [
    ".....00000....",
    "...002222200..",
    "..02222244420.",
    "..02c22244420.",
    ".0222222222220",
    "02222222222220",
    ".000000000000.",
]
HELMET_H = 20
HELMET_DY = 4


def helmet_rider(sp: Sprite) -> Sprite:
    """h_<rider>: the rider 4 px lower in a 16x20 frame, a red fire helmet on
    its head (brim one row under the top of the head), bounce frame derived."""
    src = sp.frames[0]
    f = np.full((HELMET_H, 16), T, dtype=np.int8)
    f[HELMET_DY:HELMET_DY + 16, :] = src
    rows = np.where((f >= 0).any(axis=1))[0]
    top = int(rows[0])
    head = f[top:top + 5]
    xs = np.where(head >= 0)[1]
    cx = float(xs.mean()) if len(xs) else 7.5
    x0 = int(round(cx - 6.5))
    y0 = top + 1 - 5
    stamp(f, x0, y0, HELMET)
    return Sprite("h_" + sp.name, 16, HELMET_H, sp.fps, [f, shift(f, 0, -1)], private=sp.private,
                  origin=f"helmet:{sp.name}")


GENERATORS = [gen_confetti, gen_cloud_bg, gen_seat_driver, gen_seat_hose, gen_seat_siren, gen_flame_icon,
              gen_pips, gen_badges, gen_cat_icon, gen_home_icon, gen_bucket, gen_trophy_helmet,
              gen_truck_side, gen_station_front, gen_town_strip]


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
    # Every rider also gets a helmeted version (h_<rider>) for the fire crew.
    for sp in list(public.values()):
        if sp.origin.startswith("riders.txt"):
            h = helmet_rider(sp)
            public[h.name] = h
    for sp in list(private.values()):
        if (sp.w, sp.h) == (16, 16) and len(sp.frames) == 2:
            h = helmet_rider(sp)
            private[h.name] = h
    everything = {**public, **private}
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
