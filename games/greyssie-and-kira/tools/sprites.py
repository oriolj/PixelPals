"""Greyssie and Kira art: render grids and generators to PNG strips, lint them, draw contact sheets.

Copied from Pillow Fort tools/sprites.py (itself PixelPals's: same grid format,
renderer and lint). The generators below are this game's own. Two of them read
the game's data at generation time, so a new look is one JSON edit plus
`make sprites`:

    game/data/cats.json   -> every cat's full animation set, HUD face, tail tip,
                             peek eyes, meow bubble and bowl (drawn with ROLE
                             indices, then palette-remapped to the cat's "look")
    game/data/house.json  -> the wall_* / floor_* tiles it names must exist
                             (an unknown style fails the lint with the list)

Usage: uv run python tools/sprites.py

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json (gitignored: local only)
    GENERATORS (below)      -> procedural sprites (cats, walkers, house tiles, spots, props)

Grid format: see Pillow Fort / PixelPals (# name WxH fps=N [outline] [base=] [recolor=] [mirror];
'.' transparent, 0-9a-f = Sweetie 16 index; @bounce/@shift/@mirror/@recolor frame directives).

Lint (exit 1): ragged rows, frame size different from the header, chars off
the palette, any PNG under game/art or the private art dir with partial alpha
or an opaque colour off the palette, a wall_/floor_ style in house.json that
no generator makes.

Also writes art_src/contact_sheet*.png, art_src/private/contact_sheet.png and
art_src/cats_compare.png (both cats, every frame at 1x, 4x and as solid
silhouettes: the "are the two grey cats distinct" check), plus
art_src/tells.json (where each hiding spot shows its tail tip or eyes).
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


# ================================================================ data
DATA = ROOT / "game" / "data"


def load_cats() -> list[dict]:
    return json.loads((DATA / "cats.json").read_text())["cats"]


def load_house() -> dict:
    return json.loads((DATA / "house.json").read_text())


# ================================================================ cats
# Drawn with ROLE indices, then remapped to the cat's look (palette remap).
# Role codes live above the palette range (int8 grids hold them); raw palette
# indices 0-15 drawn in the same frame (ink, plum shadow, kibble) stay as they are.
R_FUR, R_DARK, R_LIGHT, R_EYE, R_NOSE, R_COLLAR, R_TAG, R_WHITE = 20, 21, 22, 23, 24, 25, 26, 27
R_PATCH = 28  # patches: 28, 29, 30 (one per patch entry)

BUILDS = {
    # rx/ry of the standing body, head radius, leg length, leg width, tail kind
    "fluffy": {"brx": 6.6, "bry": 4.4, "hr": 4.0, "leg": 2, "lw": 2, "tail": "bushy"},
    "sleek": {"brx": 6.4, "bry": 2.8, "hr": 3.2, "leg": 4, "lw": 1, "tail": "thin"},
}


def _dot(f, x, y, col):
    h, w = f.shape
    x, y = int(round(x)), int(round(y))
    if 0 <= x < w and 0 <= y < h:
        f[y, x] = col


def _line(f, pts, col, r=0.0):
    """Polyline through pts; r > 0 draws discs of radius r along it (a thick stroke)."""
    for (x0, y0), (x1, y1) in zip(pts, pts[1:]):
        n = int(max(abs(x1 - x0), abs(y1 - y0)) * 2) + 1
        for i in range(n + 1):
            x = x0 + (x1 - x0) * i / n
            y = y0 + (y1 - y0) * i / n
            if r > 0:
                ellipse(f, x + 0.5, y + 0.5, r, r, col)
            else:
                _dot(f, x, y, col)


def _body(f, cx, cy, rx, ry, b):
    """Body ellipse with a darker belly and a light back line."""
    g = grid(f.shape[1], f.shape[0])
    ellipse(g, cx, cy, rx, ry, R_FUR)
    yy, xx = mgrid(g)
    g[(g == R_FUR) & (yy + 0.5 > cy + ry * 0.35)] = R_DARK
    top = (g == R_FUR) & (yy + 0.5 < cy - ry * 0.55)
    g[top & ((xx % 3) != 0)] = R_LIGHT
    f[g >= 0] = g[g >= 0]


def _head(f, hx, hy, r, b, eyes="open", ears="round", ears_up=0, tufts=False):
    # ears first (behind the head outline)
    if ears == "round":
        for s in (-1, 1):
            ellipse(f, hx + s * r * 0.62 + 0.5, hy - r * 0.72 - ears_up + 0.5, 1.7, 1.7, R_FUR)
            _dot(f, hx + s * r * 0.62, hy - r * 0.72 - ears_up, R_NOSE)
    else:  # tall pointed ears
        for s in (-1, 1):
            base_o = hx + s * (r * 0.95)
            base_i = hx + s * (r * 0.1)
            tip = (hx + s * r * 0.72, hy - r - 2.2 - ears_up)
            poly(f, [(base_o + 0.5, hy - r * 0.2 + 0.5), (tip[0] + 0.5, tip[1]), (base_i + 0.5, hy - r * 0.8 + 0.5)], R_FUR)
            _dot(f, hx + s * r * 0.6, hy - r - 0.3 - ears_up, R_NOSE)
    ellipse(f, hx + 0.5, hy + 0.5, r + (0.3 if tufts else 0), r, R_FUR)
    if tufts:  # fluffy cheeks sticking out
        _dot(f, hx - r - 0.2, hy + 1, R_FUR)
        _dot(f, hx + r + 0.2, hy + 1, R_FUR)
        _dot(f, hx - r + 0.4, hy + 2, R_LIGHT)
    # muzzle lighter
    _dot(f, hx - 1, hy + 1.6, R_LIGHT)
    _dot(f, hx + 1, hy + 1.6, R_LIGHT)
    _dot(f, hx, hy + 1.6, R_LIGHT)
    ex = 1.6 if r >= 3.8 else 1.4
    if eyes == "open":
        _dot(f, hx - ex, hy - 0.2, R_EYE)
        _dot(f, hx + ex, hy - 0.2, R_EYE)
        _dot(f, hx - ex, hy + 0.8, 0)
        _dot(f, hx + ex, hy + 0.8, 0)
    elif eyes == "wide":
        for s in (-1, 1):
            _dot(f, hx + s * ex, hy - 0.5, R_EYE)
            _dot(f, hx + s * ex, hy + 0.5, 0)
            _dot(f, hx + s * (ex + 1), hy - 0.5, R_WHITE)
            _dot(f, hx + s * (ex + 1), hy + 0.5, R_EYE)
    elif eyes == "closed":
        _dot(f, hx - ex, hy + 0.3, 0)
        _dot(f, hx + ex, hy + 0.3, 0)
    elif eyes == "happy":  # ^ ^
        for s in (-1, 1):
            _dot(f, hx + s * ex, hy - 0.3, 0)
            _dot(f, hx + s * ex - 1, hy + 0.5, 0)
            _dot(f, hx + s * ex + 1, hy + 0.5, 0)
    _dot(f, hx, hy + 1.0, R_NOSE)


def _collar(f, hx, hy, r):
    y = min(15, hy + r * 0.95)
    for x in range(max(0, int(round(hx - r * 0.9))), min(f.shape[1] - 1, int(round(hx + r * 0.9))) + 1):
        if f[int(round(y)), x] >= 0:
            f[int(round(y)), x] = R_COLLAR
    _dot(f, hx, min(15, y + 1), R_TAG)


def _legs(f, xs, top, bottom, lw, col_near=R_FUR, col_far=R_DARK, lifts=(0, 0, 0, 0), dxs=(0, 0, 0, 0)):
    for i, x in enumerate(xs):
        col = col_far if i % 2 == 0 else col_near
        x0 = int(round(x + dxs[i]))
        rect(f, x0, int(top), x0 + lw - 1, int(bottom - lifts[i]), col)


def _tail(f, kind, pts, tip_col=R_FUR):
    if kind == "bushy":
        _line(f, pts, R_FUR, r=1.7)
        _line(f, pts[-2:], R_LIGHT, r=0.6)
    else:
        _line(f, pts, R_FUR)
        # thin tail gets a 2 px root so it joins the body
        x, y = pts[0]
        _dot(f, x + 1, y, R_FUR)
    if tip_col != R_FUR:
        _dot(f, pts[-1][0], pts[-1][1], tip_col)


def cat_pose(b: dict, build: str, ears: str, pose: str, fr: int, patches: list[str]) -> np.ndarray:
    f = grid(20, 16)
    fl = build == "fluffy"
    rx, ry, hr, leg, lw, tk = b["brx"], b["bry"], b["hr"], b["leg"], b["lw"], b["tail"]
    tufts = fl
    eyes = "open"
    if pose in ("idle", "walk", "eat"):
        bob = 1 if (pose == "walk" and fr % 2 == 1) else 0
        bx, by = 9.0, 15 - leg - ry + 0.3 + bob
        # tail behind body
        sway = (fr % 2) if pose == "idle" else (1 if fr in (1, 2) else 0)
        if tk == "bushy":
            _tail(f, tk, [(3.5, by - 0.5), (1.6, by - 2.5), (1.4 + sway * 0.6, by - 5), (2.6 + sway, by - 7.2),
                          (4.4 + sway, by - 7.4)])
        else:
            _tail(f, tk, [(3, by), (1.5, by - 1.5), (1, by - 4), (1.5 + sway, by - 6.5), (3 + sway, by - 7.5)])
        _body(f, bx + 0.5, by + 0.5, rx, ry, b)
        base = [bx - 4.5, bx - 3, bx + 3, bx + 4.5] if lw == 1 else [bx - 5, bx - 3, bx + 2, bx + 4]
        dxs, lifts = (0, 0, 0, 0), (0, 0, 0, 0)
        if pose == "walk":
            k = [(-1, 1, 1, -1), (0, 0, 0, 0), (1, -1, -1, 1), (0, 0, 0, 0)][fr]
            dxs = k
            lifts = [(0, 1, 1, 0), (0, 0, 0, 0), (1, 0, 0, 1), (0, 0, 0, 0)][fr]
        _legs(f, base, by + ry * 0.5, 15, lw, lifts=lifts, dxs=dxs)
        if pose == "eat":
            hx, hy = 15.0, 15 - hr + 0.2 - (fr % 2) * 0.6
            eyes = "closed"
        else:
            hx, hy = 15.0, by - ry + 0.3 - (0.5 if fl else 0.8)
            if pose == "idle" and fr == 1:
                eyes = "closed"
        _head(f, hx, hy, hr, b, eyes=eyes, ears=ears, tufts=tufts)
        _collar(f, hx, hy, hr)
    elif pose in ("sit", "alert"):
        cy = 15 - (4.6 if fl else 4.4)
        # tail along the floor to the front
        flick = fr % 2 if pose == "sit" else 0
        if tk == "bushy":
            _line(f, [(4, 14), (9, 14.5), (13, 14 - flick)], R_FUR, r=1.6)
        else:
            _line(f, [(4, 15), (10, 15), (14, 15), (15, 14 - flick)], R_FUR)
        g_rx = 4.8 if fl else 3.4
        _body(f, 8.5, cy + 0.5, g_rx, 4.8 if fl else 4.6, b)
        # front legs
        fx = 10 if fl else 10
        rect(f, fx, int(cy), fx + (1 if fl else 0), 15, R_DARK)
        rect(f, fx + (2 if fl else 2), int(cy), fx + (3 if fl else 2), 15, R_FUR)
        hx, hy = 11.5, cy - 4.2 + (0.2 if fl else 0)
        up = 1 if pose == "alert" else 0
        if pose == "alert":
            eyes = "wide"
        _head(f, hx, hy, hr, b, eyes=eyes, ears=ears, ears_up=up if fr == 0 else 0, tufts=tufts)
        _collar(f, hx, hy, hr)
    elif pose in ("sleep", "carried"):
        breathe = 0.4 * (fr % 2) if pose == "sleep" else 0
        lrx = 8.2 if fl else 7.6
        lry = (3.8 if fl else 3.0) + breathe
        cy = 15 - lry + 0.4
        if pose == "carried":
            cy -= 1
        if pose == "carried":
            # dangling paws and a draped tail
            rect(f, 13, int(cy + 2), 13 + lw - 1, 15, R_FUR)
            rect(f, 6, int(cy + 2), 6 + lw - 1, 14, R_DARK)
            sw = fr % 2
            if tk == "bushy":
                _line(f, [(3, cy), (2, cy + 3), (2 + sw, 14)], R_FUR, r=1.5)
            else:
                _line(f, [(3, cy), (2, cy + 3), (2, 13), (3 + sw, 15)], R_FUR)
        _body(f, 9.5, cy + 0.5, lrx, lry, b)
        if pose == "sleep":
            if tk == "bushy":
                _line(f, [(3, 14), (9, 14.2), (14, 14)], R_LIGHT, r=1.2)
                _line(f, [(3, 14), (9, 14.2), (14, 14)], R_FUR, r=0.9)
            else:
                _line(f, [(3, 15), (10, 15), (15, 15)], R_LIGHT)
        hx, hy = 15.3, cy + 0.4
        _head(f, hx, hy, hr - 0.4, b, eyes="closed" if pose == "sleep" else "happy", ears=ears, tufts=tufts)
        if pose == "carried":
            _collar(f, hx, hy, hr - 0.4)
    elif pose in ("stalk", "pounce", "zoomies"):
        if pose == "zoomies":
            srx, sry = rx + 1.4, ry - 0.6
            bx, by = 9.5, 15 - (2 if fl else 3) - sry + (fr % 2) * 0.5
            _line(f, [(3, by), (0.5, by - 1 - (fr % 2))], R_FUR, r=1.6 if tk == "bushy" else 0)
            _body(f, bx + 0.5, by + 0.5, srx, sry, b)
            ext = fr % 2 == 0
            if ext:  # legs stretched out front and back
                _line(f, [(bx + 4, by + 1), (bx + 7, 15)], R_FUR, r=0.5 if lw == 2 else 0)
                _line(f, [(bx - 4, by + 1), (bx - 7.5, 15)], R_DARK, r=0.5 if lw == 2 else 0)
            else:  # bunched under
                _line(f, [(bx + 2, by + 1), (bx, 15)], R_FUR, r=0.5 if lw == 2 else 0)
                _line(f, [(bx - 2, by + 1), (bx + 1, 15)], R_DARK, r=0.5 if lw == 2 else 0)
            hx, hy = 16.3, by - 1.8
            _head(f, hx, hy, hr - 0.2, b, eyes="wide" if fr >= 2 else "open", ears=ears, ears_up=-1, tufts=tufts)
            _collar(f, hx, hy, hr - 0.2)
        elif pose == "pounce" and fr == 1:
            # stretched leap, feet off the floor
            bx, by = 9.5, 8.0
            if tk == "bushy":
                _line(f, [(3.5, by), (1.5, by + 1.5)], R_FUR, r=1.8)
            else:
                _line(f, [(3, by), (0.5, by + 2)], R_FUR)
            _body(f, bx + 0.5, by + 0.5, rx + 1.0, ry - 0.4, b)
            _line(f, [(bx + 4, by + 1), (bx + 8.5, by + 3)], R_FUR, r=0.5 if lw == 2 else 0)
            _line(f, [(bx - 4, by + 2), (bx - 7, by + 6)], R_DARK, r=0.5 if lw == 2 else 0)
            hx, hy = 16.0, by - 2.4
            _head(f, hx, hy, hr - 0.2, b, eyes="wide", ears=ears, tufts=tufts)
            _collar(f, hx, hy, hr - 0.2)
        else:
            # stalk frames, pounce crouch (0) and land (2)
            rump = 1 if (pose == "stalk" and fr == 1) or (pose == "pounce" and fr == 0) else 0
            land = pose == "pounce" and fr == 2
            sry = ry - 0.8 if fl else ry - 0.4
            bx, by = 9.0, 15 - 1 - sry + 0.2
            tail_up = 1 if fr == 1 else 0
            if tk == "bushy":
                _tail(f, tk, [(3, by - rump), (1.8, by - 1.5 - tail_up), (2.4, by - 3.5 - tail_up)])
            else:
                _tail(f, tk, [(3, by - rump), (1, by - 1), (0.5, by - 2.5 - tail_up)])
            _body(f, bx + 0.5, by + 0.5 - (0.5 if land else 0), rx, sry, b)
            if rump or land:
                ellipse(f, bx - 3.5, by - 0.5, 2.6, 2.0, R_FUR)
            _legs(f, [bx - 5, bx - 3, bx + 3, bx + 5] if lw == 1 else [bx - 5, bx - 3, bx + 2, bx + 4], by + 1, 15, lw)
            hx, hy = 16.0, by + (0.2 if not land else 1.0) - (0.5 if fl else 0)
            _head(f, hx, hy, hr - 0.2, b, eyes="wide", ears=ears, ears_up=-1 if pose == "stalk" else 0, tufts=tufts)
            _collar(f, hx, hy, hr - 0.2)
    # patches (role colours 28..30), after the body so they overlay
    for k, where in enumerate(patches):
        col = R_PATCH + k
        yy, xx = mgrid(f)
        furry = np.isin(f, [R_FUR, R_DARK, R_LIGHT])
        if where == "socks":
            f[furry & (yy >= 14)] = col
        elif where == "belly":
            f[(f == R_DARK)] = col
        elif where == "chest":
            # the lower-front body just under the collar
            cols = np.argwhere(f == R_COLLAR)
            if len(cols):
                cy_, cx_ = cols.mean(axis=0)
                f[furry & (np.abs(xx - cx_) <= 1.5) & (yy > cy_) & (yy <= cy_ + 3)] = col
        elif where == "face_blaze":
            eyes_ = np.argwhere(f == R_NOSE)
            if len(eyes_):
                ny, nx = eyes_[-1]
                f[furry & (xx == nx) & (yy < ny) & (yy >= ny - 4)] = col
        elif where == "tail_tip":
            # the leftmost furry pixels (the tail end in most poses)
            xs_ = np.argwhere(furry)
            if len(xs_):
                minx = xs_[:, 1].min()
                f[furry & (xx <= minx + 1)] = col
    return outline(f)


POSES = [("idle", 2, 2), ("walk", 4, 8), ("sit", 2, 2), ("sleep", 2, 1), ("stalk", 2, 4), ("pounce", 3, 8),
         ("eat", 2, 4), ("carried", 2, 2), ("zoomies", 4, 12), ("alert", 2, 3)]


def cat_remap(look: dict) -> dict[int, int]:
    m = {R_FUR: look["fur"], R_DARK: look["fur_dark"], R_LIGHT: look["fur_light"], R_EYE: look["eyes"],
         R_NOSE: look.get("nose", 2), R_COLLAR: look["collar"], R_TAG: look.get("collar_tag", 4), R_WHITE: 12}
    for k, p in enumerate(look.get("patches", [])[:3]):
        m[R_PATCH + k] = int(p.get("colour", p.get("color", 12)))
    return m


def remap_roles(f: np.ndarray, m: dict[int, int]) -> np.ndarray:
    """Role indices -> palette indices in one pass (so a remap never feeds into another role)."""
    out = f.copy()
    for a, b_ in m.items():
        out[f == a] = b_
    return out


def tail_tip_frame(tk: str, fr: int) -> np.ndarray:
    f = grid(8, 12)
    if tk == "bushy":
        pts = [(3.5, 11.5), (3.5, 7)] if fr == 0 else [(3, 11.5), (2.5, 6), (3.5, 3), (5, 2)]
        _line(f, pts, R_FUR, r=1.9)
        _line(f, pts[-2:], R_LIGHT, r=0.7)
    else:
        pts = [(3.5, 11), (3.5, 8), (4.5, 6.5)] if fr == 0 else [(3.5, 11), (3, 7), (3, 4), (4, 2), (5, 1.5)]
        _line(f, pts, R_FUR)
        _line(f, [(4.5, 11), (4.5, 10)], R_DARK)
    return outline(f)


def peek_eyes_frame(ears: str, fr: int) -> np.ndarray:
    f = grid(12, 8)
    # a soft plum shadow behind the eyes (reads as "a dark gap with someone in it")
    ellipse(f, 6, 5.5, 5.5, 2.6, 1)
    if ears == "round":
        ellipse(f, 2.8, 2.4, 1.6, 1.6, R_DARK)
        ellipse(f, 9.2, 2.4, 1.6, 1.6, R_DARK)
    else:
        poly(f, [(1, 4), (2.5, 0), (4.5, 3.5)], R_DARK)
        poly(f, [(7.5, 3.5), (9.5, 0), (11, 4)], R_DARK)
    if fr == 0:
        for x in (3, 7):
            rect(f, x, 4, x + 1, 5, R_EYE)
            f[4, x] = R_WHITE
            f[5, x + 1] = 0
    else:
        for x in (3, 7):
            rect(f, x, 5, x + 1, 5, R_EYE)
    return f


def face_frame(b: dict, ears: str, fl: bool) -> np.ndarray:
    f = grid(12, 12)
    hy = 5.6 if fl else 6.2
    _head(f, 6, hy, 4.2 if fl else 3.6, b, eyes="open", ears=ears, tufts=fl)
    _collar(f, 6, hy, 4.2 if fl else 3.6)
    return outline(f)


def bubble_frame(fr: int) -> np.ndarray:
    f = grid(20, 14)
    if fr == 0:
        ellipse(f, 11, 6, 6, 4.2, R_COLLAR)
        poly(f, [(6, 8), (8, 9), (4.5, 12)], R_COLLAR)
    else:
        ellipse(f, 11, 6, 8.4, 5.4, R_COLLAR)
        poly(f, [(5, 8), (8, 10), (3, 13)], R_COLLAR)
        # white cat-head glyph
        ellipse(f, 11, 7, 3.2, 2.6, R_WHITE)
        poly(f, [(7.8, 6.5), (8.3, 2.6), (10.2, 5.2)], R_WHITE)
        poly(f, [(11.8, 5.2), (13.7, 2.6), (14.2, 6.5)], R_WHITE)
        f[6, 10] = R_COLLAR
        f[6, 12] = R_COLLAR
        # a little music note to the right
        rect(f, 17, 3, 17, 7, R_WHITE)
        rect(f, 16, 7, 17, 8, R_WHITE)
        f[3, 18] = R_WHITE
    return outline(f)


def bowl_frame(fr: int) -> np.ndarray:
    f = grid(12, 8)
    poly(f, [(1, 4), (11, 4), (9.5, 8), (2.5, 8)], R_COLLAR)
    rect(f, 1, 4, 10, 4, R_TAG)
    if fr == 1:
        ellipse(f, 6, 4, 4.2, 2.2, 3)
        for x, y in [(3, 3), (5, 2), (7, 3), (8, 2), (4, 4), (6, 3)]:
            f[y, x] = 2
        rect(f, 1, 4, 10, 4, R_TAG)
        f[3, 4] = 4
    return outline(f)


def gen_cats() -> list[Sprite]:
    out = []
    for cat in load_cats():
        cid = cat["id"]
        look = cat["look"]
        build = look.get("build", "fluffy")
        if build not in BUILDS:
            err(f"cats.json: {cid}: build {build!r} unknown (known: {', '.join(BUILDS)})")
            continue
        for k in ("fur", "fur_dark", "fur_light", "eyes", "collar"):
            v = look.get(k)
            if not isinstance(v, int) or not 0 <= v <= 15:
                err(f"cats.json: {cid}: look.{k} must be a Sweetie 16 index 0-15, got {v!r}")
        if errors:
            continue
        b = BUILDS[build]
        ears = look.get("ears", "round" if build == "fluffy" else "tall")
        patches = [p.get("where", "") for p in look.get("patches", [])][:3]
        m = cat_remap(look)
        for pose, n, fps in POSES:
            frames = [remap_roles(cat_pose(b, build, ears, pose, fr, patches), m) for fr in range(n)]
            out.append(Sprite(f"{cid}_{pose}", 20, 16, fps, frames, origin=f"generator:cats.json:{cid}"))
        out.append(Sprite(f"{cid}_tail_tip", 8, 12, 3, [remap_roles(tail_tip_frame(b["tail"], fr), m) for fr in range(2)],
                          origin=f"generator:cats.json:{cid}"))
        out.append(Sprite(f"{cid}_peek_eyes", 12, 8, 1, [remap_roles(peek_eyes_frame(ears, fr), m) for fr in range(2)],
                          origin=f"generator:cats.json:{cid}"))
        out.append(Sprite(f"{cid}_face", 12, 12, 0, [remap_roles(face_frame(b, ears, build == "fluffy"), m)],
                          origin=f"generator:cats.json:{cid}"))
        out.append(Sprite(f"meow_bubble_{cid}", 20, 14, 8, [remap_roles(bubble_frame(fr), m) for fr in range(2)],
                          origin=f"generator:cats.json:{cid}"))
        out.append(Sprite(f"bowl_{cid}", 12, 8, 0, [remap_roles(bowl_frame(fr), m) for fr in range(2)],
                          origin=f"generator:cats.json:{cid}"))
    return out


# ================================================================ walkers from riders

def strip_outline(f: np.ndarray) -> np.ndarray:
    """Remove the 1 px ink outline (ink pixels touching transparency or the frame edge)."""
    h, w = f.shape
    pad = np.pad(f, 1, constant_values=T)
    near_t = np.zeros((h, w), bool)
    for dy, dx in ((0, 1), (2, 1), (1, 0), (1, 2)):
        near_t |= pad[dy:dy + h, dx:dx + w] == T
    out = f.copy()
    out[(f == 0) & near_t] = T
    return out


def walker_frames(rider: Sprite) -> dict[str, list[np.ndarray]]:
    fill = strip_outline(rider.frames[0])
    rows = np.argwhere(fill >= 0)
    if len(rows) == 0:
        return {}
    bottom = rows[:, 0].max()
    feet_row = fill[bottom]
    feet_x = [x for x in range(16) if feet_row[x] >= 0]
    foot_col = int(feet_row[feet_x[0]]) if feet_x else 15
    # split the feet into two groups (left and right)
    groups: list[list[int]] = []
    for x in feet_x:
        if groups and x == groups[-1][-1] + 1:
            groups[-1].append(x)
        else:
            groups.append([x])
    if len(groups) == 1:
        g = groups[0]
        groups = [g[: max(1, len(g) // 2)], g[max(1, len(g) // 2):] or g]
    mid = int(np.median(rows[:, 0]))
    arm_row = min(bottom - 4, mid + 1)
    # the contiguous run of body pixels around the centre (ignores tails and ears)
    left = right = 8
    if fill[arm_row, 8] >= 0:
        while left > 1 and fill[arm_row, left - 1] >= 0:
            left -= 1
        while right < 14 and fill[arm_row, right + 1] >= 0:
            right += 1
    body_cols = [left, right]
    arm_col_l = int(fill[arm_row, left]) if body_cols else 15
    arm_col_r = int(fill[arm_row, right]) if body_cols else 15
    shift_down = 18 - bottom - 2  # feet end at row 18 after the legs, outline row 19

    def compose(leg_dy: tuple[int, int], leg_dx: tuple[int, int], arms: str, lift: int = 0) -> np.ndarray:
        f = grid(16, 20)
        dy = shift_down - lift
        src = fill[max(0, -dy):, :]
        f[max(0, dy):max(0, dy) + src.shape[0], :] = src[: 20 - max(0, dy), :]
        leg_top = bottom + dy + 1
        for gi, g in enumerate(groups[:2]):
            for x in g:
                xx = x + leg_dx[gi]
                if 0 <= xx < 16:
                    rect(f, xx, leg_top, xx, 18 - leg_dy[gi], foot_col)
                    # a darker sole
                    f[18 - leg_dy[gi], xx] = 15 if foot_col != 15 else 0
        ar = arm_row + dy
        if arms == "swing_a":
            rect(f, left - 1, ar, left - 1, ar + 2, arm_col_l)
            rect(f, right + 1, ar - 1, right + 1, ar + 1, arm_col_r)
        elif arms == "swing_b":
            rect(f, left - 1, ar - 1, left - 1, ar + 1, arm_col_l)
            rect(f, right + 1, ar, right + 1, ar + 2, arm_col_r)
        elif arms in ("up", "up2"):
            k = 0 if arms == "up" else 1
            for x, col in ((max(0, left - 1), arm_col_l), (min(15, right + 1), arm_col_r)):
                rect(f, x, ar - 6 - k, x, ar, col)
                sx = x - 1 if x == max(0, left - 1) else x + 1
                if 0 <= sx < 16:
                    f[ar - 6 - k, sx] = col
        elif arms == "climb_a":
            rect(f, left - 1, ar - 4, left - 1, ar - 1, arm_col_l)
            rect(f, right + 1, ar, right + 1, ar + 2, arm_col_r)
        elif arms == "climb_b":
            rect(f, left - 1, ar, left - 1, ar + 2, arm_col_l)
            rect(f, right + 1, ar - 4, right + 1, ar - 1, arm_col_r)
        return outline(f)

    return {
        "walk": [compose((0, 1), (-1, 1), "swing_a"), compose((0, 0), (0, 0), "swing_b", lift=1),
                 compose((1, 0), (1, -1), "swing_b"), compose((0, 0), (0, 0), "swing_a", lift=1)],
        "climb": [compose((2, 0), (0, 0), "climb_a", lift=1), compose((0, 2), (0, 0), "climb_b")],
        "carry": [compose((0, 0), (0, 0), "up"), compose((0, 0), (0, 0), "up2", lift=1)],
    }


def gen_walkers(riders: list[Sprite]) -> list[Sprite]:
    out = []
    for r in riders:
        wf = walker_frames(r)
        for kind, fps in (("walk", 8), ("climb", 6), ("carry", 3)):
            if kind in wf:
                out.append(Sprite(f"{kind}_{r.name}", 16, 20, fps, wf[kind], private=r.private,
                                  origin=f"generator:walker:{r.name}"))
    return out


# ================================================================ house tiles
# Palette: 0 ink, 1 plum, 2 raspberry, 3 orange, 4 yellow, 5 lime, 6 green, 7 teal,
# 8 navy, 9 blue, 10 sky, 11 cyan, 12 white, 13 light grey, 14 grey, 15 dark grey.

def _tile(w: int, h: int, base: int) -> np.ndarray:
    return np.full((h, w), base, dtype=np.int8)


def wall_style(name: str) -> np.ndarray:
    if name == "wall_wood":             # warm horizontal planks (stairwell, attic)
        f = _tile(16, 16, 4)
        for y in (0, 8):
            rect(f, 0, y + 7, 15, y + 7, 3)
        f[3, 5] = 3
        f[11, 12] = 3
        rect(f, 10, 7, 10, 7, 4)
        f[2, 13] = 12
        return f
    if name == "wall_orange_stripes":   # peach-yellow with soft orange stripes
        f = _tile(16, 16, 4)
        rect(f, 2, 0, 3, 15, 3)
        rect(f, 10, 0, 10, 15, 3)
        f[4, 6] = 12
        f[12, 14] = 12
        return f
    if name == "wall_yellow_dots":
        f = _tile(16, 16, 4)
        stamp(f, 3, 3, [".c.", "ccc", ".c."])
        stamp(f, 11, 11, [".3.", "333", ".3."])
        f[12, 4] = 12
        f[4, 12] = 3
        return f
    if name == "wall_white_tiles":      # bathroom / kitchen tiles
        f = _tile(16, 16, 12)
        rect(f, 0, 7, 15, 7, 11)
        rect(f, 0, 15, 15, 15, 11)
        rect(f, 7, 0, 7, 6, 11)
        rect(f, 15, 8, 15, 14, 11)
        f[2, 2] = 11
        f[10, 10] = 11
        return f
    if name == "wall_cyan_plain":
        f = _tile(16, 16, 11)
        for x, y in [(3, 4), (11, 2), (7, 10), (14, 13), (1, 14)]:
            f[y, x] = 12
        return f
    if name == "wall_blue_stars":       # the kids' room: sky blue with yellow stars
        f = _tile(16, 16, 10)
        stamp(f, 2, 2, [".4.", "444", ".4."])
        stamp(f, 10, 9, ["..4..", ".444.", "44444", ".4.4."])
        f[12, 3] = 12
        f[3, 12] = 12
        return f
    if name == "wall_green_flowers":
        f = _tile(16, 16, 5)
        stamp(f, 2, 2, [".c.", "c4c", ".c.", ".6.", "66."])
        stamp(f, 10, 9, [".2.", "242", ".2.", ".6.", ".66"])
        f[14, 6] = 6
        return f
    raise KeyError(name)


WALL_STYLES = ["wall_wood", "wall_orange_stripes", "wall_yellow_dots", "wall_white_tiles", "wall_cyan_plain",
               "wall_blue_stars", "wall_green_flowers"]
FLOOR_STYLES = ["floor_wood", "floor_tiles", "floor_carpet"]


def floor_style(name: str) -> np.ndarray:
    if name == "floor_wood":
        f = _tile(16, 8, 3)
        rect(f, 0, 0, 15, 0, 4)
        rect(f, 0, 7, 15, 7, 2)
        rect(f, 5, 1, 5, 3, 2)
        rect(f, 13, 4, 13, 6, 2)
        rect(f, 0, 3, 15, 3, 2)
        f[2, 9] = 4
        f[5, 2] = 4
        return f
    if name == "floor_tiles":
        f = _tile(16, 8, 12)
        rect(f, 4, 0, 7, 3, 10)
        rect(f, 12, 0, 15, 3, 10)
        rect(f, 0, 4, 3, 7, 10)
        rect(f, 8, 4, 11, 7, 10)
        rect(f, 0, 7, 15, 7, 9)
        return f
    if name == "floor_carpet":
        f = _tile(16, 8, 2)
        rect(f, 0, 0, 15, 0, 3)
        for x, y in [(2, 2), (6, 4), (10, 2), (14, 5), (4, 6), (12, 6)]:
            f[y, x] = 3
        rect(f, 0, 7, 15, 7, 1)
        return f
    raise KeyError(name)


def gen_tiles() -> list[Sprite]:
    out = []
    house = load_house()
    used = {r.get(k) for fl in house.get("floors", []) for r in fl.get("rooms", []) for k in ("wall", "floor")}
    used.discard(None)
    for name in sorted(used):
        if name not in WALL_STYLES + FLOOR_STYLES:
            err(f"house.json uses {name!r}, which no generator makes. Known walls: {', '.join(WALL_STYLES)}; "
                f"known floors: {', '.join(FLOOR_STYLES)}")
    for name in WALL_STYLES:
        out.append(Sprite(name, 16, 16, 0, [wall_style(name)], origin="generator:tiles"))
    for name in FLOOR_STYLES:
        out.append(Sprite(name, 16, 8, 0, [floor_style(name)], origin="generator:tiles"))
    # slab under the boards: a warm raspberry beam with plum grain
    f = _tile(16, 20, 2)
    rect(f, 0, 0, 15, 1, 1)
    for y in (6, 13):
        rect(f, 0, y, 15, y, 1)
    f[9, 4] = 1
    f[9, 5] = 1
    f[16, 11] = 1
    rect(f, 0, 19, 15, 19, 1)
    out.append(Sprite("slab", 16, 20, 0, [f], origin="generator:tiles"))
    # ceiling: the underside of the floor above (beam) with a white cornice
    f = _tile(16, 24, 2)
    rect(f, 0, 0, 15, 0, 1)
    for y in (6, 13):
        rect(f, 0, y, 15, y, 1)
    f[9, 10] = 1
    rect(f, 0, 17, 15, 19, 3)
    rect(f, 0, 17, 15, 17, 4)
    rect(f, 0, 20, 15, 21, 12)
    rect(f, 0, 22, 15, 22, 13)
    rect(f, 0, 23, 15, 23, 12)
    out.append(Sprite("ceiling", 16, 24, 0, [f], origin="generator:tiles"))
    # roof: scalloped tiles over a raspberry base, gutter at the bottom
    f = _tile(16, 24, 2)
    for row, y0 in enumerate(range(0, 18, 6)):
        off = 4 if row % 2 else 0
        for x0 in range(-8 + off, 16, 8):
            ellipse(f, x0 + 4, y0 + 2, 4, 4, 3)
            ellipse(f, x0 + 4, y0 + 1.5, 3, 3, 3)
            rect(f, x0 + 1, y0 + 4, x0 + 7, y0 + 5, 2)
            _dot(f, x0 + 3, y0, 4)
    rect(f, 0, 19, 15, 21, 12)
    rect(f, 0, 22, 15, 23, 13)
    out.append(Sprite("roof", 16, 24, 0, [f], origin="generator:tiles"))
    return out


def gen_stairs() -> list[Sprite]:
    w, h = 48, 128
    f = grid(w, h)
    steps = 16
    sh = h // steps          # 8 px per step
    for k in range(steps):
        y0 = h - sh * (k + 1)
        xl = int(round(w - 6 - (w - 6) * (k + 1) / steps))
        for y in range(y0, y0 + sh):
            xr = min(w - 1, int((w - 6) * (y + sh) / h) + 16)   # the diagonal underside
            rect(f, xl, y, xr, y, 2)
        xr0 = min(w - 1, int((w - 6) * (y0 + sh) / h) + 16)
        rect(f, xl, y0, xr0, y0 + 1, 4)         # tread
        rect(f, xl, y0 + 2, xr0, y0 + 2, 3)
        rect(f, xl, y0 + 3, xl, y0 + sh - 1, 3)  # riser edge
    yy, xx = mgrid(f)
    f[(f == 2) & ((yy % 8) == 6) & ((xx + yy) % 5 != 0)] = 1   # stringer planks
    # banister: rail parallel to the steps, white balusters
    for k in range(steps):
        y0 = h - sh * (k + 1)
        xl = int(round(w - 6 - (w - 6) * (k + 1) / steps))
        if k % 1 == 0 and xl + 3 < w:
            rect(f, xl + 3, max(0, y0 - 14), xl + 3, y0 - 1, 12)
    for k in range(steps * 8):
        t = k / (steps * 8)
        x = int(round(w - 6 - (w - 6) * t)) + 2
        y = int(round(h - h * t)) - 16
        if 0 <= y < h and 0 <= x + 2 < w:
            f[y, x:x + 3] = 3
            if y + 1 < h:
                f[y + 1, x:x + 3] = 2
    rect(f, w - 4, h - 22, w - 2, h - 1, 3)     # newel post
    rect(f, w - 5, h - 24, w - 1, h - 22, 4)
    out = [Sprite("stairs", w, h, 0, [outline(f)], origin="generator:stairs")]
    b = grid(48, 16)
    rect(b, 0, 1, 47, 2, 3)
    rect(b, 0, 1, 47, 1, 4)
    rect(b, 0, 14, 47, 15, 2)
    for x in range(2, 47, 5):
        rect(b, x, 3, x + 1, 13, 12)
        b[3, x + 1] = 13
    rect(b, 0, 1, 2, 15, 3)
    rect(b, 45, 1, 47, 15, 3)
    out.append(Sprite("banister", 48, 16, 0, [b], origin="generator:stairs"))
    d = grid(12, 72)
    rect(d, 0, 0, 11, 3, 12)
    rect(d, 0, 0, 2, 71, 12)
    rect(d, 9, 0, 11, 71, 12)
    rect(d, 2, 4, 2, 71, 13)
    rect(d, 9, 4, 9, 71, 13)
    rect(d, 0, 3, 11, 3, 13)
    rect(d, 0, 0, 11, 0, 0)
    rect(d, 0, 0, 0, 71, 0)
    rect(d, 11, 0, 11, 71, 0)
    out.append(Sprite("doorway", 12, 72, 0, [d], origin="generator:stairs"))
    return out


# ================================================================ skies (window, terrace door)

def sky(f: np.ndarray, x0: int, y0: int, x1: int, y1: int, part: int) -> None:
    """Paint a sky in the rectangle for part 0 morning, 1 afternoon, 2 evening, 3 night."""
    w = x1 - x0 + 1
    if part == 0:
        rect(f, x0, y0, x1, y1, 11)
        ellipse(f, x1 - 3, y0 + 4, 3, 3, 4)
        rect(f, x0 + 1, y0 + 9, x0 + 6, y0 + 10, 12)
        rect(f, x0 + 2, y0 + 8, x0 + 4, y0 + 8, 12)
        rect(f, x0, y1 - 2, x1, y1, 5)
    elif part == 1:
        rect(f, x0, y0, x1, y1, 10)
        ellipse(f, x0 + 4, y0 + 3, 3, 3, 4)
        rect(f, x1 - 7, y0 + 10, x1 - 1, y0 + 11, 12)
        rect(f, x1 - 5, y0 + 9, x1 - 3, y0 + 9, 12)
        rect(f, x0, y1 - 2, x1, y1, 6)
    elif part == 2:
        hgt = y1 - y0 + 1
        rect(f, x0, y0, x1, y1, 1)
        rect(f, x0, y0 + hgt // 4, x1, y1, 2)
        rect(f, x0, y0 + hgt // 2, x1, y1, 3)
        rect(f, x0, y0 + 3 * hgt // 4, x1, y1, 4)
        ellipse(f, x0 + w / 2, y1 - 1, 3.5, 3.5, 12)
        rect(f, x0, y1 - 1, x1, y1, 2)
    else:
        rect(f, x0, y0, x1, y1, 8)
        ellipse(f, x1 - 4, y0 + 5, 3, 3, 4)
        ellipse(f, x1 - 2.5, y0 + 4, 2.4, 2.4, 8)
        for dx, dy in [(2, 2), (5, 8), (1, 12), (8, 4), (4, 15), (w - 3, 12)]:
            if x0 + dx <= x1 and y0 + dy <= y1:
                f[y0 + dy, x0 + dx] = 12
        rect(f, x0, y1 - 1, x1, y1, 9)


def gen_windows() -> list[Sprite]:
    out = []
    frames = []
    for part in range(4):
        f = grid(28, 36)
        rect(f, 3, 1, 24, 32, 12)            # frame
        sky(f, 5, 3, 22, 30, part)
        rect(f, 13, 3, 14, 30, 12)           # mullions
        rect(f, 5, 16, 22, 16, 12)
        rect(f, 1, 32, 26, 35, 3)            # sill
        rect(f, 1, 32, 26, 32, 4)
        # curtain tiebacks at the sides
        for x0 in (0, 24):
            rect(f, x0, 0, x0 + 3, 28, 2)
            rect(f, x0 + 1, 0, x0 + 1, 28, 3)
            rect(f, x0, 18, x0 + 3, 18, 4)
        rect(f, 0, 0, 27, 0, 3)
        frames.append(edge_outline(f))
    out.append(Sprite("window", 28, 36, 0, frames, origin="generator:windows"))
    frames = []
    for part in range(4):
        f = grid(28, 56)
        rect(f, 1, 1, 26, 55, 12)
        sky(f, 4, 4, 23, 36, part)
        rect(f, 13, 4, 14, 36, 12)
        rect(f, 4, 39, 23, 52, 3)
        rect(f, 6, 41, 21, 50, 2)
        rect(f, 20, 30, 21, 32, 4)           # handle
        frames.append(edge_outline(f))
    out.append(Sprite("furn_terrace_door", 28, 56, 0, frames, origin="generator:windows"))
    return out


# ================================================================ hiding spots
# Frame 0 closed, frame 1 open. Bottom-centre anchor. TELLS: where a hiding
# cat shows (tail tip bottom or peek-eyes bottom), from the bottom-centre anchor.

TELLS: dict[str, list[int]] = {}


def edge_outline(f: np.ndarray) -> np.ndarray:
    """outline() plus ink on filled pixels at the frame border (a prop that fills
    its box keeps a closed outline)."""
    f = outline(f)
    for sl in (np.s_[0, :], np.s_[-1, :], np.s_[:, 0], np.s_[:, -1]):
        v = f[sl]
        v[v > 0] = 0
    return f


def two(name: str, w: int, h: int, draw, tell: tuple[int, int]) -> Sprite:
    frames = []
    for fr in range(2):
        f = grid(w, h)
        draw(f, fr)
        frames.append(edge_outline(f))
    TELLS[name] = [int(tell[0]), int(tell[1])]
    return Sprite(name, w, h, 0, frames, origin=f"generator:spot:{name}")


def d_sofa(f, fr):
    w, h = 48, 24
    if fr == 1:
        rect(f, 3, 17, 44, 22, 1)             # the dark gap under it
    rect(f, 1, 3, 46, 10, 2)                  # back
    rect(f, 1, 3, 46, 3, 3)
    rect(f, 0, 8, 6, 19, 2)                   # arms
    rect(f, 41, 8, 47, 19, 2)
    rect(f, 0, 8, 6, 8, 3)
    rect(f, 41, 8, 47, 8, 3)
    rect(f, 7, 11, 40, 16, 3)                 # seat cushions
    rect(f, 7, 11, 40, 11, 4)
    rect(f, 23, 11, 23, 16, 2)
    ellipse(f, 12, 7, 3, 2.5, 4)              # a throw pillow
    if fr == 0:
        rect(f, 1, 17, 46, 22, 2)             # skirt down to the floor
        for x in range(2, 46, 3):
            f[22, x] = 1
        rect(f, 1, 17, 46, 17, 1)
    else:
        rect(f, 1, 17, 46, 17, 2)             # skirt tucked up
        rect(f, 2, 18, 3, 23, 1)
        rect(f, 44, 18, 45, 23, 1)
    rect(f, 2, 23, 3, 23, 1)
    rect(f, 44, 23, 45, 23, 1)


def d_bed(f, fr):
    rect(f, 0, 0, 5, 23, 2)                   # headboard (left)
    rect(f, 1, 1, 4, 1, 3)
    rect(f, 52, 6, 55, 23, 2)                 # footboard
    if fr == 1:
        rect(f, 6, 16, 51, 22, 1)
    rect(f, 6, 8, 51, 14, 12)                 # sheet
    ellipse(f, 12, 8, 5, 2.6, 12)             # pillow
    rect(f, 20, 7, 51, 15, 9)                 # quilt
    rect(f, 20, 7, 51, 7, 10)
    for x in range(24, 51, 6):
        rect(f, x, 9, x + 1, 10, 4)
    if fr == 0:
        rect(f, 6, 15, 51, 22, 9)             # quilt hangs to the floor
        for x in range(8, 51, 4):
            f[22, x] = 8
        rect(f, 6, 15, 51, 15, 10)
    else:
        rect(f, 20, 15, 51, 16, 9)            # quilt lifted
    rect(f, 6, 23, 7, 23, 2)
    rect(f, 50, 23, 51, 23, 2)


def d_desk(f, fr):
    rect(f, 0, 4, 35, 7, 3)                   # top
    rect(f, 0, 4, 35, 4, 4)
    rect(f, 1, 8, 3, 23, 2)
    rect(f, 22, 8, 34, 23, 2)                 # drawers
    for y in (11, 17):
        rect(f, 24, y, 32, y, 1)
        rect(f, 27, y + 2, 29, y + 2, 4)
    rect(f, 4, 8, 21, 22, 1)                  # knee hole (dark)
    rect(f, 6, 0, 13, 3, 12)                  # a lamp and a book
    rect(f, 17, 1, 21, 3, 9)
    cx = 12 if fr == 0 else 5                 # chair pushed in / pulled out
    rect(f, cx - 4, 12, cx + 4, 14, 10)
    rect(f, cx + 3, 6, cx + 4, 14, 10)
    rect(f, cx - 4, 15, cx - 4, 23, 9)
    rect(f, cx + 4, 15, cx + 4, 23, 9)


def d_wardrobe(f, fr):
    rect(f, 0, 0, 27, 49, 3)
    rect(f, 0, 0, 27, 1, 4)
    rect(f, 1, 50, 2, 51, 2)
    rect(f, 25, 50, 26, 51, 2)
    if fr == 0:
        rect(f, 13, 3, 14, 47, 2)
        rect(f, 2, 3, 12, 47, 3)
        rect(f, 15, 3, 25, 47, 3)
        rect(f, 11, 22, 11, 26, 4)
        rect(f, 16, 22, 16, 26, 4)
        for y in (6, 30):
            rect(f, 4, y, 9, y, 2)
            rect(f, 18, y, 23, y, 2)
    else:
        rect(f, 3, 3, 24, 47, 1)              # inside, warm plum
        rect(f, 4, 5, 23, 5, 13)              # rail
        for x, c in [(6, 9), (11, 2), (16, 6), (20, 4)]:
            poly(f, [(x - 2, 7), (x + 3, 7), (x + 3, 24), (x - 2, 24)], c)
        rect(f, 0, 3, 2, 47, 2)               # doors swung open (thin edges)
        rect(f, 25, 3, 27, 47, 2)


def d_cupboard(f, fr):
    rect(f, 0, 0, 39, 3, 13)                  # worktop
    rect(f, 0, 0, 39, 0, 12)
    rect(f, 1, 4, 38, 26, 10)
    rect(f, 1, 27, 38, 27, 9)
    if fr == 0:
        rect(f, 19, 5, 20, 25, 9)
        for x in (16, 23):
            rect(f, x, 12, x, 16, 12)
        rect(f, 3, 6, 17, 24, 11)
        rect(f, 22, 6, 36, 24, 11)
        rect(f, 3, 6, 17, 6, 12)
        rect(f, 22, 6, 36, 6, 12)
    else:
        rect(f, 3, 5, 36, 25, 1)
        rect(f, 4, 15, 35, 15, 3)             # a shelf with pots
        ellipse(f, 30, 12, 3, 2.5, 13)
        rect(f, 1, 5, 2, 25, 11)
        rect(f, 37, 5, 38, 25, 11)
    rect(f, 24, 1, 34, 1, 14)                 # a small hob line
    ellipse(f, 7, -1, 2, 2, 12)               # kettle lid on the worktop
    rect(f, 5, 0, 9, 0, 12)


def d_box(f, fr):
    rect(f, 1, 4, 18, 13, 3)
    rect(f, 1, 8, 18, 8, 2)
    rect(f, 8, 4, 11, 13, 4)                  # tape
    if fr == 0:
        rect(f, 0, 2, 19, 4, 4)               # lid
        rect(f, 0, 4, 19, 4, 2)
    else:
        poly(f, [(1, 4), (-0.5, 0), (4, 1), (5, 4)], 4)     # flaps open
        poly(f, [(15, 4), (16, 1), (20, 0), (19, 4)], 4)
        rect(f, 3, 4, 16, 5, 1)


def d_boxes(f, fr):
    rect(f, 0, 12, 27, 23, 3)
    rect(f, 0, 17, 27, 17, 2)
    rect(f, 12, 12, 15, 23, 4)
    if fr == 0:
        rect(f, 4, 2, 23, 11, 4)
        rect(f, 4, 6, 23, 6, 3)
        rect(f, 12, 2, 15, 11, 3)
    else:
        poly(f, [(14, 11), (23, 1), (28, 6), (20, 11.5)], 4)   # top box tipped over
        rect(f, 2, 11, 12, 12, 1)
    rect(f, 3, 20, 7, 21, 12)                 # a label


def d_toy_box(f, fr):
    rect(f, 1, 5, 22, 15, 6)
    rect(f, 1, 5, 22, 5, 5)
    for x, c in [(5, 4), (11, 2), (17, 10)]:
        ellipse(f, x + 0.5, 10.5, 2, 2, c)
    if fr == 0:
        rect(f, 0, 2, 23, 5, 5)
        rect(f, 0, 5, 23, 5, 6)
    else:
        poly(f, [(0, 5), (3, 0), (23, -1), (21, 4)], 5)
        rect(f, 2, 5, 21, 6, 1)
        ellipse(f, 7, 4, 2, 2, 4)             # a toy peeks out
        rect(f, 14, 3, 16, 5, 2)


def d_laundry_basket(f, fr):
    poly(f, [(1, 4), (19, 4), (17, 16), (3, 16)], 4)
    yy, xx = mgrid(f)
    f[(f == 4) & (((xx // 2) + (yy // 2)) % 2 == 0)] = 3
    if fr == 0:
        ellipse(f, 10, 4, 9, 3, 12)           # a sheet draped over
        rect(f, 2, 4, 5, 8, 12)
        rect(f, 3, 8, 4, 9, 13)
    else:
        ellipse(f, 7, 3, 4, 2.5, 9)           # laundry pile
        ellipse(f, 13, 3, 4, 2.5, 2)
        ellipse(f, 10, 2, 3, 2, 12)
    rect(f, 1, 4, 18, 5, 3)


def d_bathtub(f, fr):
    rect(f, 0, 4, 43, 15, 12)
    rect(f, 0, 4, 43, 5, 13)
    rect(f, 2, 16, 4, 19, 4)                  # clawed feet
    rect(f, 39, 16, 41, 19, 4)
    rect(f, 40, 0, 41, 4, 13)                 # tap
    rect(f, 37, 0, 41, 1, 13)
    ellipse(f, 8, 3, 3, 1.5, 11)              # bubbles over the rim
    ellipse(f, 13, 2.5, 2, 1.5, 11)
    if fr == 0:
        rect(f, 18, 3, 30, 13, 9)             # towel draped over the rim
        rect(f, 18, 11, 30, 11, 10)
        rect(f, 18, 3, 30, 3, 10)
    else:
        rect(f, 31, 0, 36, 6, 9)              # towel lifted up and away
    rect(f, 6, 8, 38, 8, 13)


def d_sink(f, fr):
    rect(f, 1, 8, 18, 27, 10)                 # vanity
    rect(f, 9, 10, 10, 25, 9)
    rect(f, 7, 16, 7, 18, 12)
    rect(f, 12, 16, 12, 18, 12)
    ellipse(f, 10, 6, 9.5, 3, 12)             # basin
    rect(f, 0, 6, 19, 8, 12)
    rect(f, 9, 0, 10, 3, 13)                  # tap
    rect(f, 9, 0, 12, 0, 13)
    if fr == 0:
        rect(f, 3, 4, 16, 9, 2)               # towel over the basin
        rect(f, 3, 4, 16, 4, 3)
        rect(f, 5, 10, 7, 13, 2)
    else:
        rect(f, 3, 5, 16, 6, 11)              # water in the basin
        rect(f, 17, 9, 19, 16, 2)             # towel hung on the side


def d_curtain(f, fr):
    rect(f, 0, 0, 23, 1, 3)                   # rod
    if fr == 0:
        rect(f, 1, 2, 22, 62, 2)
        for x in range(3, 22, 4):
            rect(f, x, 2, x, 62, 1)
            rect(f, x + 2, 4, x + 2, 60, 3)
        rect(f, 1, 62, 22, 63, 1)
    else:
        poly(f, [(1, 2), (7, 2), (6, 40), (4, 63), (0, 63)], 2)   # bunched to the left
        rect(f, 3, 2, 3, 62, 1)
        rect(f, 5, 4, 5, 40, 3)
        rect(f, 1, 34, 6, 35, 4)              # tieback


def d_plant_pot(f, fr):
    poly(f, [(3, 18), (13, 18), (12, 27), (4, 27)], 3)
    rect(f, 2, 17, 13, 19, 2)
    rect(f, 5, 21, 10, 21, 4)
    leaves = [(8, 12, 6, 5), (5, 8, 3, 4), (11, 7, 3, 4), (8, 4, 2.5, 4)] if fr == 0 else \
             [(3, 10, 3, 5), (13, 10, 3, 5), (4, 5, 2, 3.5), (12, 5, 2, 3.5)]
    for cx, cy, rx, ry in leaves:
        ellipse(f, cx, cy, rx, ry, 6)
        ellipse(f, cx - 0.5, cy - 1, rx * 0.5, ry * 0.5, 5)
    if fr == 1:
        rect(f, 6, 12, 9, 17, 1)              # the parted middle
        rect(f, 7, 8, 8, 17, 6)


def d_tv_box(f, fr):
    if fr == 0:
        ellipse(f, 12, 7, 11, 4, 9)           # a folded blanket lump
        rect(f, 1, 7, 22, 9, 9)
        for x in range(3, 22, 4):
            f[8, x] = 10
        rect(f, 4, 4, 18, 4, 10)
    else:
        rect(f, 14, 5, 23, 9, 9)              # blanket slid off to the side
        rect(f, 14, 5, 23, 5, 10)


def d_cushion(f, fr):
    ellipse(f, 11, 5, 10.5, 3.2, 2)
    rect(f, 2, 5, 19, 7, 2)
    rect(f, 3, 3, 18, 3, 3)
    if fr == 0:
        rect(f, 4, 1, 17, 6, 10)              # a little blanket on it
        rect(f, 4, 1, 17, 1, 11)
        for x in range(5, 17, 3):
            f[6, x] = 9


def d_sunny_window(f, fr):
    if fr == 0:
        rect(f, 4, 2, 23, 31, 4)              # roller blind down
        for y in range(5, 31, 4):
            rect(f, 4, y, 23, y, 3)
        rect(f, 3, 30, 24, 31, 3)
        rect(f, 13, 32, 13, 33, 12)           # pull cord
    else:
        rect(f, 4, 2, 23, 5, 4)
        rect(f, 3, 5, 24, 6, 3)
        rect(f, 13, 7, 13, 9, 12)


def d_wardrobe_top(f, fr):
    if fr == 0:
        poly(f, [(1, 3), (19, 3), (17, 11), (3, 11)], 4)
        yy, xx = mgrid(f)
        f[(f == 4) & ((xx + yy) % 3 == 0)] = 3
        rect(f, 1, 3, 18, 4, 3)
        ellipse(f, 10, 2.5, 6, 2.2, 12)       # a folded blanket in it
    else:
        poly(f, [(1, 11), (3, 3), (11, 1), (13, 9)], 4)   # basket tipped on its side
        yy, xx = mgrid(f)
        f[(f == 4) & ((xx + yy) % 3 == 0)] = 3
        rect(f, 14, 9, 19, 11, 12)


def d_bookshelf_top(f, fr):
    rect(f, 0, 3, 17, 9, 9)
    rect(f, 0, 6, 17, 6, 8)
    rect(f, 3, 7, 8, 8, 12)
    if fr == 0:
        rect(f, 0, 1, 17, 3, 10)              # lid on
    else:
        poly(f, [(12, 3), (15, -1), (18, 0), (17, 3)], 10)
        rect(f, 1, 3, 11, 4, 1)


def gen_spots() -> list[Sprite]:
    TELLS.clear()
    return [
        two("sofa", 48, 24, d_sofa, (0, 0)),
        two("bed", 56, 24, d_bed, (4, 0)),
        two("desk", 36, 24, d_desk, (-6, -1)),
        two("wardrobe", 28, 52, d_wardrobe, (0, -18)),
        two("cupboard", 40, 28, d_cupboard, (0, -8)),
        two("box", 20, 14, d_box, (6, -13)),
        two("boxes", 28, 24, d_boxes, (8, -22)),
        two("toy_box", 24, 16, d_toy_box, (7, -15)),
        two("laundry_basket", 20, 16, d_laundry_basket, (6, -15)),
        two("bathtub", 44, 20, d_bathtub, (-8, -16)),
        two("sink", 20, 28, d_sink, (5, -21)),
        two("curtain", 24, 64, d_curtain, (11, 0)),
        two("plant_pot", 16, 28, d_plant_pot, (2, -17)),
        two("tv_box", 24, 10, d_tv_box, (9, -8)),
        two("cushion", 22, 8, d_cushion, (8, -6)),
        two("sunny_window", 28, 36, d_sunny_window, (7, -4)),
        two("wardrobe_top", 20, 12, d_wardrobe_top, (6, -10)),
        two("bookshelf_top", 18, 10, d_bookshelf_top, (6, -9)),
    ]


# ================================================================ furniture

def one(name: str, w: int, h: int, draw, frames: int = 1) -> Sprite:
    out = []
    for fr in range(frames):
        f = grid(w, h)
        draw(f, fr)
        out.append(edge_outline(f))
    return Sprite(name, w, h, 2 if frames > 1 else 0, out, origin=f"generator:furniture:{name}")


def f_door(f, fr):
    rect(f, 0, 0, 19, 43, 12)
    rect(f, 2, 2, 17, 43, 2)
    rect(f, 4, 4, 15, 18, 3)
    rect(f, 4, 22, 15, 40, 3)
    rect(f, 5, 7, 14, 12, 11)                 # little window
    rect(f, 14, 25, 15, 26, 4)                # knob
    rect(f, 0, 43, 19, 43, 13)


def f_coat_rack(f, fr):
    rect(f, 5, 4, 6, 38, 3)
    rect(f, 1, 38, 10, 39, 2)
    rect(f, 2, 3, 9, 4, 2)
    poly(f, [(0, 5), (5, 5), (4, 20), (0, 18)], 9)      # a coat
    ellipse(f, 9, 7, 2.5, 3, 6)                          # a hat
    rect(f, 8, 12, 10, 22, 4)                            # a scarf


def f_picture(f, fr):
    rect(f, 0, 0, 15, 11, 3)
    rect(f, 2, 2, 13, 9, 11)
    rect(f, 2, 7, 13, 9, 6)
    ellipse(f, 11, 4, 1.5, 1.5, 4)
    poly(f, [(3, 8), (6, 4), (9, 8)], 5)


def f_rug(f, fr):
    rect(f, 0, 0, 55, 3, 2)
    rect(f, 2, 1, 53, 2, 3)
    for x in range(4, 53, 6):
        f[1, x] = 4
        f[2, x + 3] = 4


def f_tv(f, fr):
    rect(f, 1, 14, 26, 29, 2)                 # cabinet
    rect(f, 1, 14, 26, 14, 3)
    rect(f, 3, 17, 12, 27, 3)
    rect(f, 15, 17, 24, 27, 3)
    rect(f, 11, 21, 11, 23, 4)
    rect(f, 16, 21, 16, 23, 4)
    rect(f, 4, 0, 23, 13, 15)                 # an old warm TV (the cats' favourite)
    rect(f, 6, 2, 18, 11, 9)
    rect(f, 7, 3, 9, 4, 11)
    rect(f, 20, 3, 21, 4, 4)
    rect(f, 20, 7, 21, 8, 2)


def f_lamp(f, fr):
    poly(f, [(2.5, 1), (7.5, 1), (10, 9), (0, 9)], 4 if fr else 3)
    if fr:
        rect(f, 3, 3, 6, 7, 12)
    rect(f, 4, 10, 5, 29, 13)
    ellipse(f, 5, 30.5, 4, 1.8, 2)


def f_fridge(f, fr):
    rect(f, 0, 0, 19, 43, 12)
    rect(f, 0, 15, 19, 15, 13)
    rect(f, 16, 4, 17, 11, 13)
    rect(f, 16, 19, 17, 30, 13)
    stamp(f, 4, 20, ["2.2", "222", ".2."])    # magnets: a heart, a star, a drawing
    stamp(f, 8, 24, [".4.", "444", ".4."])
    rect(f, 3, 29, 9, 35, 11)
    rect(f, 4, 31, 6, 33, 6)
    rect(f, 1, 42, 18, 43, 13)


def f_table(f, fr):
    rect(f, 0, 0, 27, 3, 3)
    rect(f, 0, 0, 27, 0, 4)
    rect(f, 2, 4, 3, 19, 2)
    rect(f, 24, 4, 25, 19, 2)
    rect(f, 3, 4, 24, 5, 2)


def f_washing_machine(f, fr):
    rect(f, 0, 0, 21, 23, 12)
    rect(f, 0, 0, 21, 4, 13)
    rect(f, 2, 1, 6, 2, 10)
    ellipse(f, 17, 2.5, 1.5, 1.5, 4)
    ring(f, 11, 14, 7, 7, 1.5, 13)
    ellipse(f, 11, 14, 5.5, 5.5, 11)
    ellipse(f, 9, 16, 3, 2, 9)                # a sock going round


def f_mirror(f, fr):
    ellipse(f, 8, 10, 7.5, 9.5, 4)
    ellipse(f, 8, 10, 6, 8, 11)
    rect(f, 4, 5, 5, 8, 12)
    rect(f, 6, 4, 6, 4, 12)


def f_bookshelf(f, fr):
    rect(f, 0, 0, 27, 47, 2)
    rect(f, 2, 2, 25, 45, 1)
    rng = random.Random(5)
    for y in (2, 14, 26, 38):
        rect(f, 2, y + 10, 25, y + 11, 3)
        x = 3
        while x < 24:
            hgt = rng.randrange(6, 10)
            wdt = rng.randrange(2, 4)
            c = rng.choice([9, 6, 4, 10, 12, 3])
            rect(f, x, y + 10 - hgt, min(24, x + wdt - 1), y + 9, c)
            x += wdt + (1 if rng.random() < 0.3 else 0)
    rect(f, 0, 0, 27, 1, 3)


def f_plant_small(f, fr):
    poly(f, [(3, 10), (9, 10), (8, 15), (4, 15)], 3)
    rect(f, 2, 9, 9, 10, 2)
    for cx, cy in [(6, 5), (3.5, 7), (8.5, 7), (6, 2.5)]:
        ellipse(f, cx, cy, 2.2, 2.5, 6)
    f[4, 5] = 5
    f[6, 3] = 5


def gen_furniture() -> list[Sprite]:
    return [
        one("furn_door", 20, 44, f_door), one("furn_coat_rack", 12, 40, f_coat_rack),
        one("furn_picture", 16, 12, f_picture), one("furn_rug", 56, 4, f_rug), one("furn_tv", 28, 30, f_tv),
        one("furn_lamp", 10, 32, f_lamp, 2), one("furn_fridge", 20, 44, f_fridge), one("furn_table", 28, 20, f_table),
        one("furn_washing_machine", 22, 24, f_washing_machine), one("furn_mirror", 16, 20, f_mirror),
        one("furn_bookshelf", 28, 48, f_bookshelf), one("furn_plant_small", 12, 16, f_plant_small),
    ]


# ================================================================ props and icons

def gen_confetti() -> Sprite:
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


def gen_props() -> list[Sprite]:
    out = [gen_confetti()]
    # laser dot: red core with a bright centre, a glow ring
    frames = []
    for fr in range(2):
        f = grid(5, 5)
        if fr == 1:
            stamp(f, 0, 0, [".333.", "33333", "33333", "33333", ".333."])
        else:
            stamp(f, 1, 0, [".3.", "333", "333", "333", ".3."])
            stamp(f, 0, 1, ["3...3", "3...3", "3...3"])
        stamp(f, 1, 1, ["222", "2c2", "222"])
        frames.append(f)
    out.append(Sprite("laser_dot", 5, 5, 6, frames, origin="generator:props"))
    # treat bag: 3 shake frames
    frames = []
    for fr in range(3):
        f = grid(12, 14)
        dx = [0, -1, 1][fr]
        poly(f, [(2 + dx, 4), (10 + dx, 4), (11 + dx, 13), (1 + dx, 13)], 2)
        rect(f, 3 + dx, 1, 8 + dx, 4, 3)
        rect(f, 3 + dx, 1, 8 + dx, 1, 4)
        ellipse(f, 6 + dx, 9, 2.5, 2, 12)      # fish label
        f[9, 8 + dx] = 12
        f[9, 5 + dx] = 0
        if fr:
            for x, y in ([(1, 1), (10, 2)] if fr == 1 else [(0, 3), (11, 0)]):
                f[y, x] = 3                    # a treat flying out
        frames.append(outline(f))
    out.append(Sprite("treat_bag", 12, 14, 10, frames, origin="generator:props"))
    # house_mini: roof and a frame for three floors (the game lights rooms inside)
    f = grid(64, 40)
    poly(f, [(0, 10), (32, 0), (64, 10)], 2)
    poly(f, [(4, 10), (32, 2), (60, 10)], 3)
    rect(f, 44, 1, 48, 6, 2)                   # chimney
    rect(f, 0, 9, 63, 39, 12)
    rect(f, 2, 10, 61, 37, 15)
    rect(f, 0, 38, 63, 39, 6)
    out.append(Sprite("house_mini", 64, 40, 0, [f], origin="generator:props"))
    # zzz, star, sparkle (heart comes from art_src/icons.txt)
    frames = []
    for fr in range(3):
        f = grid(8, 8)
        if fr >= 0:
            stamp(f, 1, 4, ["ccc", ".c.", "ccc"])
        if fr >= 1:
            stamp(f, 4, 1, ["cc", ".c", "cc"])
        if fr >= 2:
            stamp(f, 6, 1, ["c"])
        f[f == 12] = 9
        frames.append(outline(f))
    out.append(Sprite("zzz", 8, 8, 2, frames, origin="generator:props"))
    frames = []
    for fr in range(2):
        f = grid(12, 12)
        poly(f, star_points(6, 6.4, 5.8, 2.6), 4)
        f[4, 5] = 12
        f[5, 4] = 12
        if fr == 1:
            f[0, 1] = 12
            f[1, 0] = 12
            f[1, 2] = 12
            f[2, 1] = 12
        frames.append(outline(f))
    out.append(Sprite("star", 12, 12, 4, frames, origin="generator:props"))
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
    out.append(Sprite("sparkle", 8, 8, 8, frames, origin="generator:props"))
    # funny finds
    def finds(name, draw):
        fs = []
        for fr in range(2):
            g = grid(8, 8)
            draw(g, fr)
            fs.append(outline(g))
        out.append(Sprite(name, 8, 8, 3, fs, origin="generator:finds"))

    def toy_mouse(g, fr):
        ellipse(g, 4.5, 5.5, 3, 2, 13)
        ellipse(g, 6.5, 4.5, 1.2, 1.2, 2)
        g[5, 6] = 0
        g[6, 7] = 2
        g[6 - fr, 1] = 2
        g[7 - fr, 0] = 2

    def sock(g, fr):
        stamp(g, 2, 0, ["ccc", "222", "ccc", "222"])
        stamp(g, 1, 4, ["cccc.", "22222", ".222."] if fr == 0 else ["cccc.", "2222.", "222.."])

    def wool_ball(g, fr):
        ellipse(g, 4, 4.5, 3.2, 3.2, 9)
        for x, y in ([(2, 3), (4, 2), (5, 5), (3, 6)] if fr == 0 else [(3, 2), (5, 3), (2, 5), (4, 6)]):
            g[y, x] = 10
        g[6, 7] = 9
        g[7, 7 - fr] = 9

    def dust_bunny(g, fr):
        ellipse(g, 4, 5, 3.3, 2.6, 13)
        g[2, 2] = 13
        g[2, 5] = 13
        g[1 + fr, 2] = 13
        g[4, 3] = 0
        g[4, 5] = 0
        g[5, 4] = 2 if fr else 13

    def cup(g, fr):
        if fr == 0:
            rect(g, 1, 2, 5, 7, 12)
            rect(g, 1, 2, 5, 2, 10)
            rect(g, 6, 3, 6, 5, 12)
            g[4, 3] = 2
        else:
            rect(g, 1, 3, 6, 7, 12)
            rect(g, 0, 3, 0, 7, 10)
            rect(g, 3, 1, 5, 2, 12)
            g[5, 4] = 2

    finds("toy_mouse", toy_mouse)
    finds("sock", sock)
    finds("wool_ball", wool_ball)
    finds("dust_bunny", dust_bunny)
    finds("cup", cup)
    # seat icons
    f = grid(16, 16)
    for x0 in (1, 8):                          # a pair of shoes
        rect(f, x0, 7, x0 + 3, 11, 2)
        rect(f, x0, 10, x0 + 6, 12, 2)
        rect(f, x0, 13, x0 + 6, 13, 12)
        rect(f, x0 + 1, 8, x0 + 2, 8, 12)
    out.append(Sprite("seat_shoes", 16, 16, 0, [outline(f)], origin="generator:icons"))
    f = grid(16, 16)
    _line(f, [(2, 13), (9, 6)], 15, r=1.3)    # laser pointer pen
    _line(f, [(3, 12), (8, 7)], 13)
    f[6, 9] = 12
    stamp(f, 11, 1, [".3.", "323", ".3."])     # its red dot
    f[4, 10] = 3
    out.append(Sprite("seat_laser", 16, 16, 0, [outline(f)], origin="generator:icons"))
    f = grid(16, 16)
    poly(f, [(4, 5), (12, 5), (13, 15), (3, 15)], 2)
    rect(f, 5, 2, 10, 5, 3)
    rect(f, 5, 2, 10, 2, 4)
    ellipse(f, 8, 10.5, 2.8, 2.2, 12)
    f[10, 6] = 0
    f[10, 11] = 12
    f[1, 13] = 3
    f[3, 2] = 3
    out.append(Sprite("seat_treats", 16, 16, 0, [outline(f)], origin="generator:icons"))
    return out


def gen_all_cats() -> list[Sprite]:
    return gen_cats()


GENERATORS = [gen_all_cats, gen_tiles, gen_stairs, gen_windows, gen_spots, gen_furniture, gen_props]


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


# ---------------------------------------------------------------- the two cats, compared

def cats_compare(public: dict, path: Path) -> Path:
    """Both cats, every frame: 1x, 4x, and solid silhouettes at 4x, one row per animation."""
    cats = [c["id"] for c in load_cats()]
    anims = [p for p, _, _ in POSES] + ["tail_tip", "peek_eyes", "face"]
    s = 4
    one_w, big_w = 4 * 22, 4 * (20 * s + 4)
    col_w = one_w + 2 * big_w + 30
    row_h = 16 * s + 10
    img = Image.new("RGB", (80 + len(cats) * col_w, 40 + len(anims) * row_h), (228, 222, 210))
    d = ImageDraw.Draw(img)
    d.text((6, 6), "cats_compare: 1x | 4x | solid silhouette 4x", fill=(20, 20, 30))
    for ci, cid in enumerate(cats):
        x0 = 80 + ci * col_w
        d.text((x0, 22), cid, fill=(20, 20, 30))
        for ai, a in enumerate(anims):
            sp = public.get(f"{cid}_{a}")
            y0 = 40 + ai * row_h
            if ci == 0:
                d.text((4, y0 + 20), a, fill=(20, 20, 30))
            if sp is None:
                continue
            for k, f in enumerate(sp.frames):
                im = Image.fromarray(to_rgba(f), "RGBA")
                img.paste(im, (x0 + k * 22, y0), im)
                big = im.resize((sp.w * s, sp.h * s), Image.NEAREST)
                img.paste(big, (x0 + one_w + k * (sp.w * s + 4), y0), big)
                sil = np.zeros((sp.h, sp.w, 4), np.uint8)
                sil[f >= 0] = (0, 0, 0, 255)
                sim = Image.fromarray(sil, "RGBA").resize((sp.w * s, sp.h * s), Image.NEAREST)
                img.paste(sim, (x0 + one_w + big_w + 10 + k * (sp.w * s + 4), y0), sim)
    img.save(path, optimize=True)
    return path


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
    # Walkers are derived from the riders (public -> game/art, private -> the pack).
    riders = [sp for sp in everything.values() if sp.origin.startswith(("riders.txt", "private_riders.txt"))]
    for sp in gen_walkers(riders):
        (private if sp.private else public)[sp.name] = sp
        everything[sp.name] = sp
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
        riders = [s.name for s in private.values() if s.origin.startswith("private_riders.txt")]
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
    sheets.append(cats_compare(public, SRC / "cats_compare.png"))
    (SRC / "tells.json").write_text(json.dumps(TELLS, indent=1, sort_keys=True) + "\n")
    if private:
        sheets += contact_sheets(sorted(private.values(), key=lambda s: s.name), PRIVATE_SRC / "contact_sheet.png")
    print(f"sprites: {len(public)} public, {len(private)} private; lint OK")
    for p in sheets:
        print(f"  sheet: {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
