"""Rocket to the Moon: render the palette-indexed sprite grids to PNG strips, lint them,
draw a contact sheet. (The PixelPals renderer and lint, with this game's generators.)

Usage: uv run python tools/sprites.py

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json (gitignored pack)
    GENERATORS (below)      -> procedural sprites (rocket, planets, Moon, ground...), same
                               path; their grids are also written to art_src/generated/*.txt
                               (reviewable, diffable; never edit them, change the generator)

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
GEN_DIR = SRC / "generated"
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


def ys_xs(h: int, w: int) -> tuple[np.ndarray, np.ndarray]:
    yy, xx = np.mgrid[0:h, 0:w]
    return yy + 0.5, xx + 0.5  # pixel centres


def disc_mask(h: int, w: int, cx: float, cy: float, r: float) -> np.ndarray:
    yy, xx = ys_xs(h, w)
    return (xx - cx) ** 2 + (yy - cy) ** 2 <= r * r


# ---------------------------------------------------------------- the rocket

ROCKET_CX = 12.0


def rocket_half_width(y: int) -> float:
    """Profile of the upper stage: an ogive nose (rows 2-12), a straight body, a nozzle."""
    if y < 13:
        t = (y + 0.5 - 1.5) / 11.5
        return 6.0 * math.sqrt(max(0.0, 1.0 - (1.0 - t) ** 2))
    if y < 34:
        return 6.0
    return 2.5 + (y - 34) * 0.6


def rocket_frame(theta: float, hot: bool = False) -> np.ndarray:
    """The rocket rolled by `theta` around its long axis (0 = porthole facing us).
    Three fins at 120 degrees; fins behind the body are drawn first, darker."""
    w, h = 24, 40
    f = grid(w, h)
    cx = ROCKET_CX

    def fin(phi: float, col: int) -> None:
        s = math.sin(phi)
        xb, xo = cx + s * 5.5, cx + s * 10.3
        if abs(xo - xb) < 1.6:
            rect(f, 11, 26, 12, 36, col)   # a fin seen edge-on, down the middle
            return
        poly(f, [(xb, 23.5), (xo, 30.5), (xo, 37.0), (xb, 34.0)], col)

    fins = [theta + k * 2 * math.pi / 3 for k in range(3)]
    for phi in fins:
        if math.cos(phi) < -0.05:
            fin(phi, 1)
    for y in range(2, 38):
        hw = rocket_half_width(y)
        x0, x1 = int(round(cx - hw)), int(round(cx + hw)) - 1
        col = 2 if y < 13 else (14 if y >= 34 else 12)
        rect(f, x0, y, x1, y, col)
    yy, xx = np.mgrid[0:h, 0:w]
    # Light from the upper left: shade the right side of the body and nose.
    shade(f, 12, 13, xx >= cx + 4)
    shade(f, 13, 14, xx >= cx + 5)
    shade(f, 2, 1, xx >= cx + 4)
    shade(f, 2, 3, (xx <= cx - 4) & (yy >= 6))
    # Red bands at the collar and near the bottom.
    for band in (13, 14, 31, 32):
        for x in range(w):
            if f[band, x] in (12, 13):
                f[band, x] = 2 if f[band, x] == 12 else 1
            elif f[band, x] == 14:
                f[band, x] = 1
    # The porthole rolls around with the body.
    wc, ws = math.cos(theta), math.sin(theta)
    if wc > 0.2:
        wx = cx + ws * 3.4
        rx = max(1.2, 3.3 * wc)
        ellipse(f, wx, 21.0, rx + 0.9, 4.0, 14)
        ellipse(f, wx, 21.0, max(0.6, rx - 0.2), 3.0, 9)
        ellipse(f, wx - 0.6, 20.4, max(0.4, rx - 1.3), 1.7, 10)
        if rx > 2.0:
            f[19, int(wx - 1.2)] = 12
    # Nozzle: a dark mouth, glowing when the engine rumbles.
    rect(f, 10, 37, 13, 37, 3 if hot else 15)
    for phi in fins:
        if math.cos(phi) >= -0.05:
            fin(phi, 2)
    # Front fins get a little shading on their shadow side.
    shade(f, 2, 1, (xx >= cx + 6) & (yy >= 24))
    # A tiny white tip on the nose.
    f[2, 11] = 12
    return outline(f)


def gen_rocket() -> Sprite:
    idle = [rocket_frame(0.0), rocket_frame(0.0, hot=True)]
    spin = [rocket_frame(k * math.pi / 4) for k in range(8)]
    return Sprite("rocket", 24, 40, 6, idle + spin, origin="generator:rocket")


def gen_rocket_stage() -> Sprite:
    """The lower stage: an adapter ring, a white body with a hazard band, small fins, a big nozzle."""
    w, h = 24, 16
    f = grid(w, h)
    cx = ROCKET_CX
    for y in range(0, 3):
        hw = 4.0 + y
        rect(f, int(round(cx - hw)), y, int(round(cx + hw)) - 1, y, 14)
    for y in range(3, 12):
        rect(f, 6, y, 17, y, 12)
    for y, hw in ((12, 3.5), (13, 4.2), (14, 4.8)):
        rect(f, int(round(cx - hw)), y, int(round(cx + hw)) - 1, y, 14)
    yy, xx = np.mgrid[0:h, 0:w]
    # Red and white checks.
    for y in (6, 7, 8):
        for x in range(6, 18):
            f[y, x] = 2 if ((x // 2) + (y // 3)) % 2 == 0 else 12
    shade(f, 12, 13, xx >= cx + 4)
    shade(f, 13, 14, xx >= cx + 5)
    shade(f, 2, 1, xx >= cx + 4)
    # Side fins.
    poly(f, [(6, 8), (2.5, 12), (2.5, 15), (6, 13)], 2)
    poly(f, [(18, 8), (21.5, 12), (21.5, 15), (18, 13)], 1)
    rect(f, 10, 14, 13, 14, 15)
    return Sprite("rocket_stage", w, h, 0, [outline(f)], origin="generator:rocket_stage")


def gen_flame() -> Sprite:
    """4 big flicker frames, then 4 small ones (an empty tank). No outline: it glows."""
    frames = []
    for length, width, sway in [(11.5, 3.3, 0.0), (10.5, 3.0, 0.4), (11.8, 3.4, -0.3), (9.8, 3.1, 0.2),
                                (5.5, 2.2, 0.0), (6.3, 2.0, 0.3), (5.0, 2.3, -0.3), (4.6, 2.1, 0.2)]:
        f = grid(8, 12)
        for y in range(12):
            t = (y + 0.5) / length
            if t >= 1.0:
                continue
            hw = width * (1.0 - t ** 1.7)
            c = 4.0 + sway * t
            for x in range(8):
                d = abs(x + 0.5 - c)
                if d <= hw:
                    col = 3
                    if d <= hw * 0.55:
                        col = 4
                    if d <= 0.9 and t < 0.4:
                        col = 12
                    if t > 0.78:
                        col = 2 if d > hw * 0.4 else 3
                    f[y, x] = col
        frames.append(f)
    return Sprite("flame", 8, 12, 14, frames, origin="generator:flame")


def gen_smoke() -> Sprite:
    """A puff that grows and thins out (the code picks the frame by age)."""
    frames = []
    specs = [
        [(8, 9, 3.0)],
        [(8, 9, 4.3), (5, 10, 2.6), (11, 10.5, 2.6)],
        [(8, 8.5, 5.4), (4.5, 10, 3.4), (11.5, 10, 3.6), (8, 5, 3.0)],
        [(8, 8, 6.2), (4, 10, 3.6), (12, 10, 3.8), (8, 4.5, 3.4)],
    ]
    for i, blobs in enumerate(specs):
        f = grid(16, 16)
        for cx, cy, r in blobs:
            ellipse(f, cx, cy, r, r * 0.9, 12)
        yy, xx = ys_xs(16, 16)
        cx0, cy0 = blobs[0][0], blobs[0][1]
        shade(f, 12, 13, (xx - cx0) * 0.5 + (yy - cy0) > 1.5)
        shade(f, 13, 14, (xx - cx0) * 0.5 + (yy - cy0) > 4.0)
        if i == 3:
            # Thinning out: a dither of holes.
            iy, ix = np.mgrid[0:16, 0:16]
            f[((ix + iy) % 2 == 0) & ((ix + 2 * iy) % 3 == 0)] = T
        frames.append(f)
    return Sprite("smoke", 16, 16, 0, frames, origin="generator:smoke")


# ---------------------------------------------------------------- the launch site

def gen_gantry() -> Sprite:
    """A red lattice tower with two service arms reaching right, a beacon on top."""
    w, h = 16, 64
    f = grid(w, h)
    rect(f, 2, 4, 3, 59, 2)
    rect(f, 10, 4, 11, 59, 2)
    for y0 in range(6, 56, 8):
        for k in range(7):
            f[y0 + k, 4 + k * 5 // 6] = 2
            f[y0 + k, 9 - k * 5 // 6] = 2
        rect(f, 2, y0 - 1, 11, y0 - 1, 2)
    for ay in (18, 40):
        rect(f, 2, ay, 14, ay + 1, 2)
        rect(f, 12, ay + 2, 14, ay + 2, 14)
    yy, xx = np.mgrid[0:h, 0:w]
    shade(f, 2, 1, (xx == 3) | (xx == 11))
    rect(f, 1, 60, 12, 62, 14)
    rect(f, 1, 60, 12, 60, 13)
    rect(f, 6, 1, 7, 3, 14)       # antenna mast
    f[1, 6] = 4
    f[1, 7] = 12
    return Sprite("gantry", w, h, 0, [outline(f)], origin="generator:gantry")


def gen_launch_pad() -> Sprite:
    """A concrete pad: light deck, a hazard-striped front, a dark flame trench, two legs."""
    w, h = 64, 16
    f = grid(w, h)
    rect(f, 1, 1, 62, 3, 13)
    rect(f, 1, 1, 62, 1, 12)
    for x in range(1, 63):
        for y in (4, 5):
            f[y, x] = 4 if ((x + y) // 3) % 2 == 0 else 0
    rect(f, 3, 6, 60, 11, 14)
    rect(f, 3, 11, 60, 11, 15)
    rect(f, 26, 6, 37, 11, 0)       # flame trench
    rect(f, 27, 6, 36, 6, 15)
    for vx in (8, 15, 46, 53):
        rect(f, vx, 7, vx + 3, 8, 15)
    rect(f, 5, 12, 10, 14, 15)
    rect(f, 53, 12, 58, 14, 15)
    return Sprite("launch_pad", w, h, 0, [outline(f)], origin="generator:launch_pad")


def gen_countdown_light() -> Sprite:
    frames = []
    for on in (False, True):
        f = grid(12, 12)
        ellipse(f, 6, 6, 4.9, 4.9, 14)
        ellipse(f, 6, 6, 3.9, 3.9, 2 if on else 1)
        if on:
            ellipse(f, 6, 6, 2.4, 2.4, 3)
            stamp(f, 4, 3, ["cc", "c."])
        else:
            yy, xx = ys_xs(12, 12)
            shade(f, 1, 15, (xx - 6) + (yy - 6) > 1.5)
            f[3, 4] = 13
        frames.append(outline(f))
    return Sprite("countdown_light", 12, 12, 0, frames, origin="generator:countdown_light")


def button_frame(w: int, h: int, cx: float, base_y: int, rx: float, dome_h: float, pressed: bool) -> np.ndarray:
    f = grid(w, h)
    rect(f, int(cx - rx - 2), base_y, int(cx + rx + 1), h - 2, 14)
    rect(f, int(cx - rx - 2), base_y, int(cx + rx + 1), base_y, 13)
    ellipse(f, cx, base_y, rx + 1.5, 2.2, 4)
    top = base_y - (dome_h * 0.45 if pressed else dome_h)
    ry = base_y - top
    dome = grid(w, h)
    ellipse(dome, cx, base_y, rx, ry, 2)
    yy, xx = ys_xs(h, w)
    dome[yy > base_y] = T
    f[dome == 2] = 2
    shade(f, 2, 1, (xx - cx) * 0.7 + (yy - base_y + ry * 0.5) > rx * 0.55)
    ys = int(top + ry * 0.35)
    if 0 <= ys < h:
        stamp(f, int(cx - rx * 0.55), ys, ["3c"] if rx > 4 else ["c"])
    return outline(f)


def gen_big_button() -> Sprite:
    frames = [button_frame(24, 16, 12, 10, 7.5, 7.0, p) for p in (False, True)]
    return Sprite("big_button", 24, 16, 0, frames, origin="generator:big_button")


def gen_seat_launcher() -> Sprite:
    """The Launcher's seat icon: a little big button."""
    return Sprite("seat_launcher", 16, 16, 0, [button_frame(16, 16, 8, 10, 5.0, 5.0, False)],
                  origin="generator:seat_launcher")


def gen_earth_ground() -> Sprite:
    """The launch site: hills at the sides, a flat field in the middle for the pad,
    a control building and a hangar, round trees. Rows 0-9 are sky (transparent)."""
    w, h = 320, 48
    f = grid(w, h)
    surf = []
    for x in range(w):
        d = abs(x + 0.5 - 160)
        y = 20.0
        if d > 56:
            y -= min(9.0, (d - 56) * 0.14)
            y += 1.4 * math.sin(x * 2 * math.pi / 64)
        surf.append(int(round(y)))
    # Buildings stand behind the grass line.
    rect(f, 62, surf[62] - 12, 90, surf[62] + 2, 12)     # control building
    rect(f, 62, surf[62] - 13, 90, surf[62] - 12, 14)
    for wx in range(65, 88, 6):
        rect(f, wx, surf[62] - 9, wx + 3, surf[62] - 7, 9)
        f[surf[62] - 9, wx] = 10
    rect(f, 74, surf[62] - 18, 75, surf[62] - 13, 14)    # antenna
    f[surf[62] - 19, 74] = 2
    rect(f, 226, surf[226] - 10, 258, surf[226] + 2, 14)  # hangar
    for x in range(226, 259):
        top = surf[226] - 10 - int(round(3 * math.sin((x - 226) / 32 * math.pi)))
        rect(f, x, top, x, surf[226] - 10, 13)
    rect(f, 234, surf[226] - 6, 250, surf[226] + 2, 15)
    for tx in (22, 44, 120, 196, 282, 304):
        base = surf[tx]
        ellipse(f, tx + 0.5, base - 5.5, 4.2, 4.6, 6)
        ellipse(f, tx - 0.8, base - 7.0, 1.8, 1.6, 5)
        rect(f, tx, base - 1, tx, base + 1, 1)
    for x in range(w):
        s = surf[x]
        f[s:, x] = 6
        f[s, x] = 5
        for y in range(s + 12, h):
            if y >= s + 18 or (x + y) % 2 == 0:
                f[y, x] = 7
    rnd = random.Random(11)
    for _ in range(90):
        x = rnd.randrange(w)
        y = rnd.randrange(surf[x] + 2, h)
        if f[y, x] == 6:
            f[y, x] = rnd.choice((5, 7, 4))
    # A path to the pad.
    for x in range(100, 221):
        f[surf[x] + 3, x] = 13 if f[surf[x] + 3, x] >= 0 else f[surf[x] + 3, x]
    return Sprite("earth_ground", w, h, 0, [f], origin="generator:earth_ground")


# ---------------------------------------------------------------- space things

# kind: (radius, name)
PLANETS = {1: 5.4, 2: 4.8, 3: 6.3, 4: 6.9, 5: 6.0, 6: 6.0, 7: 5.2, 8: 4.7}


def planet_frame(kind: int, p: int) -> np.ndarray:
    w = h = 16
    f = grid(w, h)
    cx, cy, r = 8.0, 8.0, PLANETS[kind]
    yy, xx = ys_xs(h, w)
    dx, dy = xx - cx, yy - cy
    m = dx * dx + dy * dy <= r * r
    lit = (dx + dy) < -r * 0.85
    dark = (dx * 0.7 + dy * 0.7) > r * 0.38

    def paint(base: int, hi: int, lo: int) -> None:
        f[m] = base
        f[m & lit] = hi
        f[m & dark] = lo

    if kind == 1:      # Mars: orange with craters and a white cap
        paint(3, 4, 2)
        for ox, oy in ((-2, 1), (2, 2), (0, -1), (3, -2)):
            x = int(cx + ox - p)
            if 0 <= x < w and m[int(cy + oy), x]:
                f[int(cy + oy), x] = 2 if f[int(cy + oy), x] != 2 else 1
        f[m & (dy < -r + 1.6)] = 12
    elif kind == 2:    # Saturn: a yellow ball in a big grey ring
        ring = grid(w, h)
        ellipse(ring, cx, cy, 7.6, 2.4, 13)
        ellipse(ring, cx, cy, 5.9, 1.3, T)
        f[(ring == 13) & (yy < cy)] = 13
        paint(4, 12, 3)
        f[m & (np.abs(dy - 1.5) < 0.6)] = 3
        f[(ring == 13) & (yy >= cy)] = 13
        f[(ring == 13) & (yy >= cy) & (dx > 3)] = 14
        gx = int(cx - 6 + p * 9)
        if ring[int(cy), gx] == 13:
            f[int(cy), gx] = 12
    elif kind == 3:    # Earth: blue with green lands and a cloud
        paint(10, 11, 9)
        land = grid(w, h)
        for lx, ly, rx, ry in ((-2.5, -1.5, 2.2, 2.0), (2.5, 2.0, 2.4, 1.7), (-1.0, 3.5, 1.4, 1.0)):
            ellipse(land, cx + lx - p, cy + ly, rx, ry, 6)
        f[m & (land == 6)] = 6
        f[m & (land == 6) & lit] = 5
        f[m & (np.abs(dy + 3.5) < 0.6) & (np.abs(dx - 1 + p) < 2.2)] = 12
    elif kind == 4:    # Jupiter: stripes and the red spot
        bands = [4, 3, 12, 3, 4, 13, 3]
        for i, col in enumerate(bands):
            y0 = cy - r + i * (2 * r / len(bands))
            f[m & (yy >= y0) & (yy < y0 + 2 * r / len(bands) + 0.01)] = col
        f[m & dark & (f == 4)] = 3
        f[m & dark & (f == 12)] = 13
        spot = grid(w, h)
        ellipse(spot, cx + 2.0 - p * 1.5, cy + 2.2, 1.8, 1.0, 2)
        f[m & (spot == 2)] = 2
    elif kind == 5:    # Neptune: deep blue, a white streak and a dark storm
        paint(9, 10, 8)
        f[m & (np.abs(dy + 1.5) < 0.5) & (dx > -3.5 + p) & (dx < 1.5 + p)] = 11
        f[m & (np.abs(dy - 3.5) < 0.5) & (dx > -1.5 - p) & (dx < 2.5 - p)] = 10
        storm = grid(w, h)
        ellipse(storm, cx - 1.5 + p, cy + 2.0, 1.4, 0.9, 8)
        f[m & (storm == 8)] = 8
    elif kind == 6:    # Candy: purple with white swirl stripes
        paint(1, 2, 1)
        stripe = np.mod(dx - dy * 0.6 + p * 2.0, 5.0) < 1.4
        f[m & stripe] = 12
        f[m & stripe & dark] = 13
    elif kind == 7:    # Green planet with a little moon going round
        paint(6, 5, 7)
        for sx, sy in ((-2, -1), (2, 2)):
            f[int(cy + sy), int(cx + sx - p)] = 7
        mx, my = ((13.2, 3.2), (13.4, 12.6))[p]
        moon = grid(w, h)
        ellipse(moon, mx, my, 1.7, 1.7, 13)
        f[moon == 13] = 13
        f[int(my - 0.5), int(mx - 0.5)] = 12
    elif kind == 8:    # Pluto: a small pale world with a big white heart
        paint(12, 12, 13)
        heart = ["22.22", "22222", ".222.", "..2.."]
        stamp(f, int(cx - 2 + p * 0), int(cy - 2), heart)
        f[int(cy - 2), int(cx - 2)] = 3
    return outline(f)


def gen_planets() -> list[Sprite]:
    out = []
    for k in range(1, 9):
        frames = [planet_frame(k, 0), planet_frame(k, 1)]
        out.append(Sprite(f"planet_{k}", 16, 16, 2, frames, origin=f"generator:planet_{k}"))
        sil = frames[0].copy()
        body = sil >= 0
        sil[body] = 14
        sil[frames[0] == 0] = 15
        out.append(Sprite(f"silhouette_{k}", 16, 16, 0, [sil], origin=f"generator:silhouette_{k}"))
    return out


def gen_asteroid() -> Sprite:
    """A soft, grumpy space rock. Frame 1 blinks."""
    frames = []
    for blink in (False, True):
        f = grid(16, 16)
        for cx, cy, rx, ry in ((8, 8.5, 6.0, 5.6), (5.2, 6.0, 3.2, 3.2), (10.8, 5.8, 3.4, 3.0), (8.5, 11.5, 4.5, 2.8)):
            ellipse(f, cx, cy, rx, ry, 14)
        yy, xx = ys_xs(16, 16)
        shade(f, 14, 15, (xx - 8) * 0.6 + (yy - 8.5) > 3.0)
        shade(f, 14, 13, (xx - 8) + (yy - 8.5) < -6.5)
        for cx, cy, r in ((4.5, 11.0, 1.1), (12.0, 10.5, 1.3)):
            ellipse(f, cx, cy, r, r * 0.8, 15)
        if blink:
            stamp(f, 5, 7, ["000", "..."])
            stamp(f, 9, 7, ["000", "..."])
        else:
            stamp(f, 5, 5, ["00.", "..0"])     # cross brows
            stamp(f, 9, 5, [".00", "0.."])
            stamp(f, 5, 7, ["c0", "00"])
            stamp(f, 10, 7, ["c0", "00"])
        stamp(f, 6, 10, [".00.", "0..0"])       # frown
        frames.append(outline(f))
    return Sprite("asteroid", 16, 16, 2, frames, origin="generator:asteroid")


def gen_comet() -> Sprite:
    frames = []
    for i in range(2):
        f = grid(16, 8)
        for x in range(6, 16):
            spread = 0.6 + (x - 5) * 0.2
            col = 11 if x < 9 else (10 if x < 12 else 9)
            for y in range(8):
                d = abs(y + 0.5 - 3.8 - (x - 5) * 0.05)
                if d <= spread and (x + y + i) % (2 if x > 11 else 7) != 0:
                    f[y, x] = col
        ellipse(f, 4.0, 4.0, 2.7, 2.7, 11)
        ellipse(f, 3.6, 3.6, 1.5, 1.5, 12)
        frames.append(f)
    return Sprite("comet", 16, 8, 6, frames, origin="generator:comet")


def gen_moon() -> Sprite:
    """The Moon, 96 px: grey, lit from the upper left, with craters."""
    w = h = 96
    f = grid(w, h)
    cx = cy = 48.0
    r = 45.5
    yy, xx = ys_xs(h, w)
    dx, dy = xx - cx, yy - cy
    m = dx * dx + dy * dy <= r * r
    f[m] = 13
    f[m & ((dx * 0.6 + dy * 0.8) > 20)] = 14
    f[m & ((dx * 0.6 + dy * 0.8) > 34)] = 15
    f[m & ((dx + dy) < -48) & (dx * dx + dy * dy > (r - 5) ** 2)] = 12
    rnd = random.Random(5)
    craters = [(30, 30, 7), (60, 26, 5), (52, 56, 9), (26, 62, 5), (70, 60, 4), (40, 44, 3),
               (66, 40, 3), (20, 44, 3), (46, 78, 4), (76, 50, 2.5), (36, 18, 2.5)]
    for _ in range(10):
        a, d = rnd.uniform(0, 2 * math.pi), rnd.uniform(0, 38)
        craters.append((cx + d * math.cos(a), cy + d * math.sin(a), rnd.uniform(1.2, 2.0)))
    for x0, y0, cr in craters:
        c = (xx - x0) ** 2 + (yy - y0) ** 2 <= cr * cr
        inner_shadow = c & ((xx - x0) + (yy - y0) < -cr * 0.3)
        rim = ((xx - x0) ** 2 + (yy - y0) ** 2 <= (cr + 1.0) ** 2) & ~c & ((xx - x0) + (yy - y0) > cr * 0.6)
        base = f.copy()
        f[m & c] = np.where(base[m & c] == 15, 15, 14)
        f[m & inner_shadow] = 15
        f[m & rim & (base != 15)] = 12
    return Sprite("moon", w, h, 0, [outline(f)], origin="generator:moon")


def gen_moon_ground() -> Sprite:
    """The Moon's surface strip: bumpy rim, flattened craters, grey layers. Tiles (periods divide 320)."""
    w, h = 320, 32
    f = grid(w, h)
    surf = []
    for x in range(w):
        y = 6 + 1.8 * math.sin(x * 2 * math.pi / 80) + 1.0 * math.sin(x * 2 * math.pi / 32 + 1.0)
        surf.append(int(round(y)))
    for x in range(w):
        s = surf[x]
        f[s:, x] = 13
        f[s, x] = 12
        f[s + 12:, x] = 14
        f[s + 20:, x] = 15
    rnd = random.Random(9)
    for cx in range(20, 320, 46):
        cx += rnd.randrange(-8, 9)
        cx %= w
        rx = rnd.uniform(6, 11)
        cy = surf[cx] + rnd.uniform(4, 9)
        ellipse(f, cx, cy, rx, rx * 0.28, 14)
        ellipse(f, cx - 0.5, cy - 0.6, rx * 0.8, rx * 0.16, 15)
        for x in range(int(cx - rx * 0.8), int(cx + rx * 0.8)):
            y = int(round(cy + rx * 0.28))
            if 0 <= x < w and 0 <= y < h and f[y, x] >= 0:
                f[y, x] = 12
    for _ in range(160):
        x = rnd.randrange(w)
        y = rnd.randrange(surf[x] + 2, h)
        f[y, x] = rnd.choice((14, 15, 12))
    return Sprite("moon_ground", w, h, 0, [f], origin="generator:moon_ground")


def gen_flag() -> Sprite:
    """A white flag on a pole (the code tints it with the seat colour), waving in 2 frames."""
    frames = []
    for p in range(2):
        f = grid(16, 16)
        rect(f, 3, 2, 3, 14, 13)
        rect(f, 4, 2, 4, 14, 14)
        stamp(f, 3, 1, ["44"])
        for x in range(5, 14):
            wave = int(round(0.9 * math.sin((x - 5) * 0.9 + p * math.pi)))
            top = 3 + wave
            rect(f, x, top, x, top + 5, 12)
            if (x + p) % 4 in (2, 3):
                f[top + 5, x] = 13
                f[top, x] = 13 if x % 2 else 12
        stamp(f, 6, 5 + int(round(0.9 * math.sin(1 * 0.9 + p * math.pi))), [".4.", "444", ".4."])
        rect(f, 1, 14, 6, 14, 14)
        frames.append(outline(f))
    return Sprite("flag", 16, 16, 3, frames, origin="generator:flag")


def gen_helmet() -> Sprite:
    """A see-through space helmet for a 16x16 rider: a glass rim, a glint, a collar."""
    w = h = 20
    f = grid(w, h)
    cx, cy = 10.0, 9.2
    yy, xx = ys_xs(h, w)
    d = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    ring = (d >= 8.0) & (d <= 9.1) & (yy < 16)
    f[ring] = 11
    f[ring & ((xx - cx) + (yy - cy) > 5)] = 10
    ang = np.arctan2(yy - cy, xx - cx)
    glint = (d >= 5.6) & (d <= 6.6) & (ang > -2.6) & (ang < -1.9)
    f[glint] = 12
    rect(f, 3, 16, 16, 18, 12)
    rect(f, 3, 18, 16, 18, 13)
    rect(f, 9, 16, 10, 17, 2)    # a little red badge on the collar
    return Sprite("helmet", w, h, 0, [outline(f)], origin="generator:helmet")


def gen_album_frame() -> Sprite:
    f = grid(16, 16)
    ellipse(f, 8, 8, 7.6, 7.6, 14)
    ellipse(f, 8, 8, 6.6, 6.6, 15)
    return Sprite("album_frame", 16, 16, 0, [f], origin="generator:album_frame")


def gen_sparkle() -> Sprite:
    frames = []
    for arm in (1, 2, 3, 2):
        f = grid(8, 8)
        rect(f, 4 - arm, 3, 3 + arm, 4, 4)
        rect(f, 3, 4 - arm, 4, 3 + arm, 4)
        if arm == 3:
            for dx, dy in ((2, 2), (5, 2), (2, 5), (5, 5)):
                f[dy, dx] = 4
        f[3, 3] = 12
        frames.append(f)
    return Sprite("sparkle", 8, 8, 10, frames, origin="generator:sparkle")


# ---------------------------------------------------------------- sky things (from PixelPals)

def gen_cloud() -> Sprite:
    f = grid(32, 16)
    for cx, cy, r in ((7, 10.5, 4), (13, 7.2, 5), (20, 5.8, 4.8), (26, 9.5, 4.2), (16, 11, 4.5), (19, 10, 5)):
        ellipse(f, cx, cy, r, r, 12)
    rect(f, 6, 11, 27, 14, 12)
    yy, _ = np.mgrid[0:16, 0:32]
    shade(f, 12, 13, yy >= 13)
    return Sprite("cloud", 32, 16, 0, [f], origin="generator:cloud")


def gen_balloon() -> Sprite:
    frames = []
    strings = ([8, 8, 7, 7, 8, 8], [8, 9, 9, 8, 7, 7])
    for i in range(2):
        f = grid(16, 24)
        ellipse(f, 8, 8.5, 6.2, 7.2, 2)
        yy, xx = np.mgrid[0:24, 0:16]
        shade(f, 2, 1, ((xx - 8) * 0.8 + (yy - 8.5) > 6.5))
        ellipse(f, 5.5, 5.5, 1.3, 2.2, 12)
        stamp(f, 7, 16, ["22", "12"])
        f = outline(f)
        for k, sx in enumerate(strings[i]):
            f[18 + k, sx] = 13
        frames.append(f)
    return Sprite("balloon", 16, 24, 3, frames, origin="generator:balloon")


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


GENERATORS = [gen_rocket, gen_rocket_stage, gen_flame, gen_smoke, gen_gantry, gen_launch_pad,
              gen_countdown_light, gen_big_button, gen_seat_launcher, gen_earth_ground, gen_planets,
              gen_asteroid, gen_comet, gen_moon, gen_moon_ground, gen_flag, gen_helmet, gen_album_frame,
              gen_sparkle, gen_cloud, gen_balloon, gen_confetti]


def write_generated_grid(sp: Sprite) -> None:
    """Keep every generated sprite as a reviewable text grid in art_src/generated/."""
    GEN_DIR.mkdir(parents=True, exist_ok=True)
    lines = [f"; generated by tools/sprites.py ({sp.origin}); do not edit, change the generator",
             f"# {sp.name} {sp.w}x{sp.h} fps={sp.fps}"]
    for i, fr in enumerate(sp.frames):
        if i:
            lines.append("")
        for row in fr:
            lines.append("".join("." if v < 0 else CHARS[v] for v in row))
    (GEN_DIR / f"{sp.name}.txt").write_text("\n".join(lines) + "\n")



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
    generated: list[Sprite] = []
    for gen in GENERATORS:
        made = gen()
        for sp in made if isinstance(made, list) else [made]:
            if sp.name in public:
                err(f"{sp.origin}: duplicate sprite {sp.name!r} (also in art_src)")
            public[sp.name] = sp
            generated.append(sp)
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
    for sp in generated:
        write_generated_grid(sp)
    for stale in GEN_DIR.glob("*.txt"):
        if stale.stem not in {sp.name for sp in generated}:
            stale.unlink()
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
