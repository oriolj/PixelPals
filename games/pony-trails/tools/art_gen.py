"""Pony Trails's procedural sprites (Endesga 32), rendered by sprites.py.

generate() yields (name, w, h, fps, frames); frames are int8 arrays of palette
indices (-1 = transparent). ANIMS and POINTS are written by sprites.py to
game/art/anims.json and game/art/points.json.

The horses come from horses.py (one set of drawings, posed and recoloured per
coat). Everything else is geometry (ellipses, polygons, lines) plus small
stamped grids for faces, in the house style: soft shapes, a 1 px ink outline,
friendly faces, nothing sharp or dark.

Endesga 32 chars (index):
  0 be4a2f  1 d77643  2 ead4aa  3 e4a672  4 b86f50  5 733e39  6 3e2731  7 a22633
  8 e43b44  9 f77622  a feae34  b fee761  c 63c74d  d 3e8948  e 265c42  f 193c3e
  g 124e89  h 0099db  i 2ce8f5  j ffffff  k c0cbdc  l 8b9bb4  m 5a6988  n 3a4466
  o 262b44  p 181425  q ff0044  r 68386c  s b55088  t f6757a  u e8b796  v c28569
"""

from __future__ import annotations

import dataclasses
import math
import random

import numpy as np
from PIL import Image, ImageDraw

import horses as hz

CHARS = "0123456789abcdefghijklmnopqrstuv"
T = -1
INK = 25


def C(ch) -> int:
    return CHARS.index(ch) if isinstance(ch, str) else ch


# ---------------------------------------------------------------- drawing helpers

def grid(w: int, h: int) -> np.ndarray:
    return np.full((h, w), T, dtype=np.int8)


def mgrid(f: np.ndarray):
    return np.mgrid[0:f.shape[0], 0:f.shape[1]]


def ellipse(f, cx, cy, rx, ry, col, only=None) -> None:
    yy, xx = mgrid(f)
    m = ((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0
    if only is not None:
        m &= np.isin(f, [C(c) for c in only])
    f[m] = C(col)


def rect(f, x0, y0, x1, y1, col) -> None:
    h, w = f.shape
    if x1 < 0 or y1 < 0 or x0 >= w or y0 >= h:
        return
    f[max(0, y0):min(h, y1 + 1), max(0, x0):min(w, x1 + 1)] = C(col)


def poly(f, pts, col) -> None:
    h, w = f.shape
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in pts], fill=255)
    f[np.asarray(m) > 0] = C(col)


def line(f, pts, col, width=1) -> None:
    h, w = f.shape
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).line([(float(x), float(y)) for x, y in pts], fill=255, width=width)
    f[np.asarray(m) > 0] = C(col)


def px(f, x, y, col) -> None:
    h, w = f.shape
    if 0 <= x < w and 0 <= y < h:
        f[y, x] = C(col)


def stamp(f, x, y, rows) -> None:
    h, w = f.shape
    for dy, r in enumerate(rows):
        for dx, c in enumerate(r):
            if c != "." and 0 <= y + dy < h and 0 <= x + dx < w:
                f[y + dy, x + dx] = C(c)


def shade(f, region: str, col: str, where) -> None:
    f[(f == C(region)) & where] = C(col)


def outline(f: np.ndarray, col: int = INK) -> np.ndarray:
    return hz.outline(f, col)


def shift(f: np.ndarray, dx: int, dy: int) -> np.ndarray:
    h, w = f.shape
    out = np.full_like(f, T)
    ys, yd = (slice(max(0, -dy), h - max(0, dy)), slice(max(0, dy), h - max(0, -dy)))
    xs, xd = (slice(max(0, -dx), w - max(0, dx)), slice(max(0, dx), w - max(0, -dx)))
    out[yd, xd] = f[ys, xs]
    return out


def dither(f, x0, y0, x1, y1, a, b, frac) -> None:
    """Fill a rect with colour a, and b on a Bayer pattern for fraction frac."""
    bayer = np.array([[0, 8, 2, 10], [12, 4, 14, 6], [3, 11, 1, 9], [15, 7, 13, 5]]) / 16.0
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1):
            if 0 <= y < f.shape[0] and 0 <= x < f.shape[1]:
                f[y, x] = C(b) if bayer[y % 4, x % 4] < frac else C(a)


# ---------------------------------------------------------------- animation data

ANIMS: dict = {}
POINTS: dict = {}


# ---------------------------------------------------------------- horses

def _chin_fix() -> None:
    pass


def wild_model() -> hz.Model:
    """The mare's drawing at 0.78 scale for the far-away wild herd (32x24)."""
    k = 0.78
    m = hz.MARE

    def sc(v):
        if isinstance(v, tuple) and len(v) == 2 and all(isinstance(t, (int, float)) for t in v):
            return (v[0] * k, v[1] * k)
        if isinstance(v, tuple) and len(v) == 4:
            return (v[0] * k, v[1] * k, v[2] * k, v[3] * k)
        if isinstance(v, tuple):
            return tuple(sc(t) for t in v)
        if isinstance(v, list):
            return [sc(t) for t in v]
        if isinstance(v, dict):
            return {a: sc(b) if not isinstance(b, (int, float)) else b * k for a, b in v.items()}
        return v
    kw = {}
    for fld in dataclasses.fields(m):
        v = getattr(m, fld.name)
        if fld.name in ("w", "h"):
            continue
        if fld.name in ("ground", "pitch_c", "mane_w", "tail_w", "hoof_len"):
            kw[fld.name] = v * k
        elif fld.name in ("leg_w",):
            kw[fld.name] = 1.0
        elif fld.name in ("eye_big", "fluffy_tail", "saddle"):
            kw[fld.name] = v if fld.name != "saddle" else False
        else:
            kw[fld.name] = sc(v)
    return hz.Model(w=32, h=24, **kw)


def gen_horses():
    mp = hz.mare_poses()
    fp = hz.foal_poses()
    bp = hz.big_poses()
    ANIMS["mare"] = _ranges(mp, {"stand": 2, "walk": 4, "trot": 8, "canter": 6.6667, "jump": 6, "neigh": 4,
                                 "munch": 4, "hoof": 0})
    ANIMS["foal"] = _ranges(fp, {"stand": 2, "trot": 8, "hop": 6, "neigh": 4, "sleep": 1})
    ANIMS["mare_big"] = _ranges(bp, {"idle": 1, "munch": 4, "ear": 4, "hoof": 0})
    for coat in hz.MARE_COATS:
        yield f"mare_{coat}", 40, 32, 4, [hz.render(hz.MARE, p, coat) for _, p in mp]
        yield f"mare_big_{coat}", 80, 64, 1, [hz.render(hz.MARE, p, coat, s=2, tack=False) for _, p in bp]
    for coat in hz.FOAL_COATS:
        yield f"foal_{coat}", 24, 20, 8, [hz.render(hz.FOAL, p, coat) for _, p in fp]
    # the tack overlay: pixels that differ between the saddled and the bare stable mare
    tack = []
    for _, p in bp:
        a = hz.render(hz.MARE, p, "bay", s=2, tack=True)
        b = hz.render(hz.MARE, p, "bay", s=2, tack=False)
        f = np.where(a != b, a, T).astype(np.int8)
        tack.append(f)
    yield "mare_big_tack", 80, 64, 1, tack
    # anchor points
    POINTS["mare"] = {
        "rider": [hz.points(hz.MARE, p)["rider"] for _, p in mp],
        "passenger": [hz.points(hz.MARE, p)["passenger"] for _, p in mp],
        "braid": [hz.points(hz.MARE, p)["braid"] for _, p in mp],
        "mouth": [hz.points(hz.MARE, p)["mouth"] for _, p in mp],
    }
    POINTS["foal"] = {
        "hat": [hz.points(hz.FOAL, p)["hat"] for _, p in fp],
        "mouth": [hz.points(hz.FOAL, p)["mouth"] for _, p in fp],
    }
    big = hz.points(hz.MARE, bp[0][1], s=2)
    POINTS["mare_big"] = {
        "patches": {"head": [60, 8], "back": [18, 20], "legs": [44, 36], "tail": [4, 22]},
        "patch_sizes": {k: list(v) for k, v in MUD_SIZES.items()},
        "hooves": [[int(hz.MARE.feet[l] * 2), int(hz.MARE.ground * 2)] for l in ("FN", "FF", "HN", "HF")],
        "braid": big["braid"], "mouth": big["mouth"], "saddle": big["saddle"],
    }
    # the wild herd
    wm = wild_model()
    herd = [p for n, p in mp if n == "canter"] + [p for n, p in mp if n == "neigh"][:1]
    for i, coat in enumerate(["grey", "chestnut", "black"], 1):
        yield f"wild_horse_{i}", 32, 24, 7, [hz.render(wm, dataclasses.replace(p, tail=1.0), coat) for p in herd]
    ANIMS["wild_horse"] = {"gallop": [0, 4, 6.6667], "whinny": [4, 1, 0]}
    # coat swatches: the mare's head and neck (the appaloosa shows its spots)
    for coat in hz.FOAL_COATS:
        c = "appaloosa_swatch" if coat == "appaloosa" else coat
        f = hz.render(hz.MARE, hz.Pose(), c, tack=False)
        yield f"coat_{coat}", 16, 16, 0, [f[0:16, 24:40].copy()]


def _ranges(poses, fps: dict) -> dict:
    r = hz.anim_ranges(poses)
    return {k: [v[0], v[1], fps.get(k, 4)] for k, v in r.items()}


# ---------------------------------------------------------------- mud

MUD_SIZES = {"head": (12, 10), "back": (20, 10), "legs": (16, 12), "tail": (12, 14)}


def gen_mud():
    for i, (name, (w, h)) in enumerate(MUD_SIZES.items()):
        rng = random.Random(40 + i)
        f = grid(w, h)
        # a splotchy blob: a few overlapping ellipses
        for _ in range(5):
            cx = rng.uniform(w * 0.3, w * 0.7)
            cy = rng.uniform(h * 0.3, h * 0.7)
            ellipse(f, cx, cy, rng.uniform(w * 0.18, w * 0.34), rng.uniform(h * 0.2, h * 0.34), "5")
        yy, xx = mgrid(f)
        # texture: wet dark mud with clods, and a tan dried crust around the
        # edge, so it reads on every coat (dark on the light coats, the crust
        # on the bay and the black)
        for y, x in zip(*np.nonzero(f >= 0)):
            f[y, x] = C("6") if rng.random() < 0.7 else C("5")
        inner = f >= 0
        edge = inner.copy()
        edge[1:-1, 1:-1] = inner[1:-1, 1:-1] & ~(inner[:-2, 1:-1] & inner[2:, 1:-1] & inner[1:-1, :-2] & inner[1:-1, 2:])
        for y, x in zip(*np.nonzero(edge & inner)):
            if rng.random() < 0.8:
                f[y, x] = C("3")
        # splatter specks around the edge
        for _ in range(8):
            x, y = rng.randrange(w), rng.randrange(h)
            if f[y, x] < 0:
                f[y, x] = C("6") if rng.random() < 0.5 else C("3")
        full = f.copy()
        filled = list(zip(*np.nonzero(full >= 0)))
        # the patch shrinks toward a few clumps as it is scrubbed: rank by the
        # distance to the nearest clump centre plus a little noise
        clumps = [(rng.uniform(w * 0.3, w * 0.7), rng.uniform(h * 0.3, h * 0.7)) for _ in range(3)]
        def rank(p):
            y, x = p
            d = min(math.hypot((x + 0.5 - cx) / w, (y + 0.5 - cy) / h) for cx, cy in clumps)
            return d + rng.uniform(0, 0.12)
        filled.sort(key=rank)
        n = len(filled)
        frames = []
        for stage, keep in enumerate((1.0, 0.55, 0.28, 0.1)):
            g = grid(w, h)
            for y, x in filled[: max(1, int(n * keep))]:
                g[y, x] = full[y, x] if stage < 2 else (C("5") if full[y, x] == C("6") else C("3"))
                if stage == 3:
                    g[y, x] = C("3")
            frames.append(g)
        yield f"mud_{name}", w, h, 0, frames


# ---------------------------------------------------------------- stable items

def gen_stable_items():
    # brush: wooden back, grey bristles
    fr = []
    for k in range(2):
        f = grid(16, 12)
        ellipse(f, 8, 4.5, 6.5, 3.2, "4")
        ellipse(f, 8, 3.8, 5.0, 1.8, "v")
        rect(f, 3, 1, 12, 1, "3")
        for x in range(3, 13):
            top = 7
            ln = 3 if (x + k) % 2 else 2
            rect(f, x, top, x, top + ln, "k" if x % 3 else "l")
        fr.append(outline(f))
    yield "brush", 16, 12, 6, fr
    # hoof pick: red handle, metal hook
    f = grid(12, 12)
    line(f, [(1, 10), (6, 5)], "8", 3)
    line(f, [(2, 10), (5, 7)], "q", 1)
    line(f, [(6, 5), (9, 2)], "l", 2)
    line(f, [(9, 2), (10, 4)], "k", 1)
    px(f, 8, 3, "k")
    yield "hoof_pick", 12, 12, 0, [outline(f)]
    # hand: open, pointing
    a = grid(12, 12)
    ellipse(a, 6, 7.5, 3.8, 3.3, "u")
    for i, x in enumerate([3, 5, 7, 9]):
        rect(a, x, 2 + (1 if i in (0, 3) else 0), x, 6, "u")
    rect(a, 1, 6, 2, 8, "u")
    shade(a, "u", "v", mgrid(a)[0] >= 10)
    b = grid(12, 12)
    ellipse(b, 5, 8, 3.8, 3.0, "u")
    rect(b, 7, 1, 8, 7, "u")
    rect(b, 1, 6, 2, 8, "u")
    shade(b, "u", "v", mgrid(b)[0] >= 10)
    yield "hand", 12, 12, 0, [outline(a), outline(b)]
    # carrot
    f = grid(12, 8)
    poly(f, [(3, 2), (11.5, 4), (3, 6.5)], "9")
    line(f, [(5, 3), (6, 4)], "1")
    line(f, [(7, 4), (8, 5)], "1")
    shade(f, "9", "1", mgrid(f)[0] >= 5)
    line(f, [(0, 1), (3, 3)], "c")
    line(f, [(0, 4), (3, 4)], "d")
    line(f, [(1, 6), (3, 5)], "c")
    yield "carrot", 12, 8, 0, [outline(f)]
    # saddle on its own (on the rack)
    f = grid(24, 16)
    rect(f, 3, 7, 20, 11, "h")
    rect(f, 3, 11, 20, 11, "g")
    poly(f, [(4, 7), (7, 3), (16, 3.5), (20, 1.5), (20.5, 5), (18, 8), (5, 8.5)], "5")
    line(f, [(8, 4), (15, 4.5)], "4")
    rect(f, 11, 9, 11, 12, "5")
    rect(f, 10, 13, 13, 14, "l")
    yield "saddle", 24, 16, 0, [outline(f)]
    # bridle on a hook
    f = grid(16, 16)
    rect(f, 7, 0, 8, 2, "l")
    line(f, [(5, 3), (10, 3)], "5")
    line(f, [(5, 3), (4, 11)], "5")
    line(f, [(10, 3), (11, 11)], "5")
    line(f, [(4, 7), (11, 7)], "8")
    line(f, [(4, 11), (11, 11)], "5")
    ellipse(f, 3.5, 12.5, 1.6, 1.6, "k")
    ellipse(f, 11.5, 12.5, 1.6, 1.6, "k")
    ellipse(f, 3.5, 12.5, 0.6, 0.6, "l")
    ellipse(f, 11.5, 12.5, 0.6, 0.6, "l")
    yield "bridle", 16, 16, 0, [outline(f)]
    # horseshoe (silver), glint on frame 1
    yield "horseshoe", 8, 8, 3, _shoe("k", "l", "j")
    # the lucky horseshoe (gold) for the trail
    yield "lucky_horseshoe", 8, 8, 3, _shoe("a", "9", "b", sparkle=True)
    f = grid(4, 4)
    ellipse(f, 2, 2, 1.8, 1.5, "l")
    px(f, 1, 1, "k")
    yield "pebble", 4, 4, 0, [f]
    for name, (a, b) in {"red": ("8", "7"), "blue": ("h", "g"), "yellow": ("b", "a"), "purple": ("s", "r")}.items():
        f = grid(8, 8)
        poly(f, [(0.5, 1), (3.5, 3), (0.5, 5)], a)
        poly(f, [(7.5, 1), (4.5, 3), (7.5, 5)], a)
        px(f, 1, 4, b)
        px(f, 6, 4, b)
        rect(f, 3, 2, 4, 3, b)
        line(f, [(3, 4), (2, 7)], a)
        line(f, [(4, 4), (5, 7)], b)
        yield f"ribbon_{name}", 8, 8, 0, [outline(f)]
    f = grid(8, 8)
    ellipse(f, 2.5, 3, 2.1, 2.1, "8")
    ellipse(f, 5.5, 3, 2.1, 2.1, "8")
    poly(f, [(0.6, 3.5), (7.4, 3.5), (4, 7.2)], "8")
    px(f, 2, 2, "t")
    px(f, 1, 3, "t")
    yield "heart", 8, 8, 0, [outline(f)]
    fr = []
    for k, r in enumerate([1, 2, 3, 2]):
        f = grid(8, 8)
        rect(f, 4 - r, 4, 3 + r, 4, "b")
        rect(f, 4, 4 - r, 4, 3 + r, "b")
        rect(f, 3, 3, 4, 4, "j")
        if r == 3:
            px(f, 2, 2, "b")
            px(f, 6, 6, "b")
        fr.append(f)
    yield "sparkle", 8, 8, 10, fr


def _shoe(a, b, glint, sparkle=False):
    fr = []
    for k in range(2):
        f = grid(8, 8)
        ellipse(f, 4, 4, 3.4, 3.4, a)
        ellipse(f, 4, 4.4, 1.7, 2.2, T)
        rect(f, 3, 5, 4, 7, T)
        shade(f, a, b, mgrid(f)[0] >= 5)
        px(f, 1, 3, "p")
        px(f, 6, 3, "p")
        if k == 1:
            px(f, 2, 1, glint)
            px(f, 3, 1, glint)
        f = outline(f)
        if k == 1 and sparkle:
            px(f, 7, 0, glint)
        fr.append(f)
    return fr


# ---------------------------------------------------------------- stable tiles and props

def gen_stable():
    f = grid(16, 16)
    for x in range(16):
        col = "v" if (x // 4) % 2 == 0 else "4"
        rect(f, x, 0, x, 15, col)
    for x in (3, 7, 11, 15):
        rect(f, x, 0, x, 15, "5")
    px(f, 1, 5, "3")
    px(f, 9, 11, "3")
    px(f, 5, 2, "5")
    px(f, 13, 8, "5")
    yield "stall_wall", 16, 16, 0, [f]
    rng = random.Random(3)
    f = grid(16, 16)
    rect(f, 0, 0, 15, 15, "3")
    for _ in range(26):
        x, y = rng.randrange(16), rng.randrange(16)
        ln = rng.randrange(2, 5)
        col = rng.choice("abv2")
        for k in range(ln):
            px(f, (x + k) % 16, y, col)
    yield "stall_floor", 16, 16, 0, [f]
    # stall door 32x48: closed, half, open (the paddock beyond, sunny)
    fr = []
    for state in range(3):
        f = grid(32, 48)
        rect(f, 0, 0, 31, 47, "5")
        # the doorway shows the sunny yard
        rect(f, 3, 3, 28, 47, "i")
        rect(f, 3, 30, 28, 47, "c")
        rect(f, 3, 28, 28, 29, "d")
        ellipse(f, 10, 12, 4, 2, "j")
        doorw = [26, 14, 4][state]
        rect(f, 3, 3, 2 + doorw, 47, "4")
        for x in range(3, 3 + doorw):
            if (x - 3) % 4 == 3:
                rect(f, x, 3, x, 47, "5")
        if doorw > 8:
            line(f, [(4, 44), (1 + doorw, 6)], "v", 2)
            rect(f, 3, 24, 2 + doorw, 25, "v")
        rect(f, 2 + doorw, 3, 2 + doorw, 47, "6")
        px(f, doorw, 25, "a")
        fr.append(f)
    yield "stall_door", 32, 48, 6, fr
    f = grid(32, 24)
    rect(f, 0, 2, 31, 23, "4")
    for x in range(0, 32, 4):
        rect(f, x + 3, 2, x + 3, 23, "5")
    rect(f, 0, 0, 31, 2, "v")
    rect(f, 0, 2, 31, 2, "5")
    line(f, [(1, 22), (30, 4)], "v", 2)
    rect(f, 26, 10, 27, 11, "a")
    yield "half_door", 32, 24, 0, [outline(f)]
    f = grid(24, 16)
    poly(f, [(1, 1), (22, 1), (19, 13), (4, 13)], "5")
    rng = random.Random(9)
    for _ in range(40):
        x = rng.uniform(2, 21)
        y = rng.uniform(0, 9)
        line(f, [(x, y), (x + rng.uniform(-2, 2), y + rng.uniform(1, 3))], rng.choice("ab3"))
    for x in range(4, 21, 3):
        rect(f, x, 6, x, 13, "5")
    rect(f, 3, 13, 20, 14, "4")
    yield "hay_rack", 24, 16, 0, [outline(f)]
    f = grid(24, 24)
    rect(f, 1, 2, 4, 21, "4")
    rect(f, 1, 2, 1, 21, "v")
    poly(f, [(4, 8), (22, 7), (22, 11), (4, 13)], "4")
    line(f, [(5, 8), (21, 7)], "v")
    rect(f, 20, 11, 22, 14, "5")
    yield "saddle_rack", 24, 24, 0, [outline(f)]
    f = grid(32, 12)
    poly(f, [(1, 2), (30, 2), (27, 11), (4, 11)], "l")
    rect(f, 2, 2, 29, 3, "i")
    rect(f, 3, 3, 28, 3, "h")
    shade(f, "l", "m", mgrid(f)[0] >= 9)
    rect(f, 6, 5, 25, 5, "k")
    yield "water_trough", 32, 12, 0, [outline(f)]
    fr = []
    for k in range(2):
        f = grid(8, 12)
        rect(f, 3, 0, 4, 1, "n")
        rect(f, 1, 2, 6, 2, "n")
        rect(f, 1, 3, 6, 9, "b")
        rect(f, 2, 4, 5, 8, "a")
        ellipse(f, 3.5 + (0.5 if k else 0), 6.5, 1.1, 1.6 + 0.3 * k, "j")
        rect(f, 1, 10, 6, 10, "n")
        rect(f, 1, 3, 1, 9, "n")
        rect(f, 6, 3, 6, 9, "n")
        fr.append(outline(f))
    yield "lantern", 8, 12, 4, fr
    yield "stable_cat", 16, 12, 4, cat_frames()
    ANIMS["stable_cat"] = {"walk": [0, 2, 4], "sit": [2, 2, 2]}


def cat_frames():
    fr = []
    for k in range(4):
        f = grid(16, 12)
        sit = k >= 2
        if not sit:
            ellipse(f, 7, 6.5, 4.5, 2.3, "9")
            for i, x in enumerate([4, 5, 9, 10]):
                off = 1 if (i + k) % 2 else 0
                rect(f, x + off - (1 if i % 2 else 0), 8, x + off - (1 if i % 2 else 0), 10, "9" if i in (0, 2) else "1")
            line(f, [(2.5, 6), (1, 3), (2, 1)], "9", 1)
            head = (12, 4.5)
        else:
            ellipse(f, 7, 7, 3.5, 3.6, "9")
            rect(f, 8, 9, 9, 10, "9")
            rect(f, 5, 10, 10, 10, "1")
            line(f, [(4, 9), (1.5, 9), (1, 7)], "9", 1)
            head = (10, 3.5)
        hx, hy = head
        ellipse(f, hx, hy, 2.8, 2.4, "9")
        poly(f, [(hx - 2.4, hy - 1), (hx - 2, hy - 3.8), (hx - 0.4, hy - 1.8)], "9")
        poly(f, [(hx + 0.6, hy - 1.8), (hx + 2.2, hy - 3.8), (hx + 2.6, hy - 1)], "9")
        # tabby stripes and a cream belly
        for x in range(0, 16, 2):
            for y in range(12):
                if f[y, x] == C("9") and y <= 5:
                    f[y, x] = C("1")
        ellipse(f, hx + 0.3, hy + 1.3, 1.4, 0.9, "2")
        ex = int(hx)
        blink = sit and k == 3
        px(f, ex, int(hy), "p" if not blink else "1")
        px(f, ex + 2, int(hy), "p" if not blink else "1")
        px(f, ex + 1, int(hy) + 1, "t")
        fr.append(outline(f))
    return fr


# ---------------------------------------------------------------- the trail

def gen_skies():
    skies = {
        "sky_morning": (["h", "i", "i", "j"], "j", "k"),
        "sky_rain": (["m", "l", "l", "k"], "k", "l"),
        "sky_afternoon": (["g", "h", "i", "i"], "j", "k"),
        "sky_golden": (["t", "u", "a", "b"], "b", "u"),
    }
    for name, (bands, cloud, cloud_s) in skies.items():
        f = grid(320, 60)
        n = len(bands)
        for y in range(60):
            t = y / 59 * (n - 1)
            i = min(int(t), n - 2)
            frac = t - i
            dither(f, 0, y, 319, y, bands[i], bands[i + 1], frac)
        rng = random.Random(len(name) * 7)
        for c in range(6 if name != "sky_rain" else 9):
            cx = rng.uniform(0, 320)
            cy = rng.uniform(8, 34)
            for b in range(4):
                for wrap in (-320, 0, 320):
                    ellipse(f, cx + wrap + b * 7 - 10, cy - (3 if b in (1, 2) else 0), 7 + rng.random() * 2, 4, cloud)
            for wrap in (-320, 0, 320):
                ellipse(f, cx + wrap, cy + 3, 13, 1.4, cloud_s)
        if name in ("sky_morning", "sky_afternoon"):
            ellipse(f, 40 if name == "sky_morning" else 250, 14, 6, 6, "b")
            ellipse(f, 40 if name == "sky_morning" else 250, 14, 4, 4, "j")
        if name == "sky_golden":
            ellipse(f, 270, 44, 9, 9, "b")
            ellipse(f, 270, 44, 6, 6, "j")
        yield name, 320, 60, 0, [f]


def _wave(x, parts):
    return sum(a * math.sin(2 * math.pi * (x / p) + ph) for a, p, ph in parts)


def gen_hills():
    f = grid(320, 60)
    for x in range(320):
        back = 26 + _wave(x, [(6, 320, 0.3), (3, 80, 1.1), (1.5, 64, 0.2)])
        front = 38 + _wave(x, [(5, 160, 2.0), (2, 64, 0.7)])
        rect(f, x, int(back), x, 59, "d")
        px(f, x, int(back), "c")
        rect(f, x, int(front), x, 59, "c")
    # texture: little bushes on the back hills, flowers on the front
    rng = random.Random(11)
    for _ in range(60):
        x, y = rng.randrange(320), rng.randrange(30, 60)
        if f[y, x] == C("c") and y > 40:
            px(f, x, y, "d")
        elif f[y, x] == C("d"):
            px(f, x, y, "e")
    # the windmill on a hilltop
    wx = 236
    top = int(38 + _wave(wx, [(5, 160, 2.0), (2, 64, 0.7)]))
    poly(f, [(wx - 5, top + 1), (wx - 3, top - 18), (wx + 3, top - 18), (wx + 5, top + 1)], "k")
    shade(f, "k", "l", mgrid(f)[1] >= wx + 2)
    poly(f, [(wx - 4, top - 18), (wx, top - 23), (wx + 4, top - 18)], "8")
    rect(f, wx - 1, top - 5, wx + 1, top, "5")
    rect(f, wx - 1, top - 13, wx, top - 12, "g")
    hub = (wx, top - 17)
    for dx, dy in [(1, 1), (1, -1), (-1, 1), (-1, -1)]:
        line(f, [hub, (hub[0] + 10 * dx, hub[1] + 10 * dy)], "5")
        line(f, [(hub[0] + 4 * dx, hub[1] + 4 * dy), (hub[0] + 10 * dx + (2 if dx * dy > 0 else -2) * 0, hub[1] + 10 * dy)], "2")
    px(f, hub[0], hub[1], "6")
    yield "hills_far", 320, 60, 0, [f]


def gen_trees_mid():
    f = grid(320, 48)
    rng = random.Random(21)
    rect(f, 0, 38, 319, 47, "d")
    for x in range(320):
        y = 36 + int(_wave(x, [(1.5, 40, 0.3), (1, 32, 1.0)]))
        rect(f, x, y, x, 47, "d")
    xs = sorted(rng.uniform(0, 320) for _ in range(16))
    for cx in xs:
        r = rng.uniform(7, 12)
        cy = 38 - r - rng.uniform(2, 8)
        for wrap in (-320, 0, 320):
            rect(f, int(cx + wrap) - 1, int(cy), int(cx + wrap) + 1, 40, "5")
            ellipse(f, cx + wrap, cy, r, r * 0.9, "e")
            ellipse(f, cx + wrap - 2, cy - 2, r * 0.7, r * 0.6, "d")
            ellipse(f, cx + wrap - 3, cy - 4, r * 0.3, r * 0.25, "c")
    for x in range(0, 320, 3):
        if f[38, x] == C("d"):
            px(f, x, 37 + (x % 2), "e")
    yield "trees_mid", 320, 48, 0, [f]


def gen_ground():
    rng = random.Random(5)
    f = grid(16, 16)
    rect(f, 0, 0, 15, 15, "c")
    for _ in range(14):
        x, y = rng.randrange(16), rng.randrange(16)
        px(f, x, y, "d")
        px(f, x, (y - 1) % 16, "d")
    px(f, 4, 7, "b")
    px(f, 12, 12, "j")
    yield "grass", 16, 16, 0, [f]
    f = grid(16, 16)
    rect(f, 0, 0, 15, 15, "3")
    for _ in range(18):
        x, y = rng.randrange(16), rng.randrange(16)
        px(f, x, y, rng.choice("v2v4"))
    yield "path", 16, 16, 0, [f]
    f = grid(16, 16)
    rect(f, 1, 3, 3, 15, "4")
    rect(f, 1, 3, 1, 15, "v")
    rect(f, 0, 5, 15, 6, "v")
    rect(f, 0, 6, 15, 6, "4")
    rect(f, 0, 10, 15, 11, "v")
    rect(f, 0, 11, 15, 11, "4")
    rect(f, 1, 2, 3, 2, "v")
    yield "fence", 16, 16, 0, [f]
    fr = []
    for state in range(3):
        f = grid(32, 24)
        rect(f, 0, 2, 2, 23, "4")
        rect(f, 29, 2, 31, 23, "4")
        rect(f, 0, 2, 0, 23, "v")
        rect(f, 29, 2, 29, 23, "v")
        end = [28, 16, 6][state]
        for y in (6, 10, 14, 18):
            rect(f, 3, y, end, y + 1, "2")
            rect(f, 3, y + 1, end, y + 1, "3")
        if end > 8:
            rect(f, end - 1, 5, end, 20, "2")
            line(f, [(4, 19), (end - 2, 7)], "2", 1)
        else:
            rect(f, end - 1, 5, end, 20, "2")
        rect(f, 0, 1, 2, 1, "v")
        rect(f, 29, 1, 31, 1, "v")
        fr.append(outline(f))
    yield "gate", 32, 24, 6, fr


def gen_props():
    f = grid(48, 40)
    poly(f, [(2, 16), (24, 3), (46, 16)], "7")
    poly(f, [(4, 16), (24, 5), (44, 16)], "8")
    rect(f, 5, 16, 43, 39, "8")
    for x in range(5, 44, 3):
        rect(f, x, 16, x, 39, "7")
    rect(f, 5, 16, 43, 17, "j")
    rect(f, 16, 22, 32, 39, "7")
    rect(f, 16, 22, 32, 23, "j")
    rect(f, 16, 22, 16, 39, "j")
    rect(f, 32, 22, 32, 39, "j")
    line(f, [(17, 24), (31, 38)], "j")
    line(f, [(31, 24), (17, 38)], "j")
    rect(f, 21, 9, 27, 14, "j")
    rect(f, 22, 10, 26, 13, "a")
    rect(f, 24, 10, 24, 13, "3")
    yield "barn", 48, 40, 0, [outline(f)]
    f = grid(24, 32)
    rect(f, 10, 18, 13, 31, "5")
    rect(f, 10, 18, 10, 31, "4")
    ellipse(f, 12, 12, 10.5, 9.5, "d")
    ellipse(f, 10, 9, 7.5, 6.5, "c")
    ellipse(f, 8, 7, 3, 2.5, "b")
    shade(f, "d", "e", mgrid(f)[0] >= 17)
    for x, y in [(15, 9), (6, 14), (17, 15)]:
        ellipse(f, x, y, 1.3, 1.3, "8")
    yield "tree", 24, 32, 0, [outline(f)]
    f = grid(16, 12)
    ellipse(f, 8, 7.5, 7.2, 4.2, "d")
    ellipse(f, 6.5, 6, 4.5, 3, "c")
    for x, y in [(4, 6), (10, 5), (12, 8)]:
        px(f, x, y, "t")
    yield "bush", 16, 12, 0, [outline(f)]
    f = grid(16, 16)
    for x, h in [(2, 9), (5, 12), (8, 8), (11, 13), (13, 10)]:
        rect(f, x, 15 - h, x, 15, "d")
        rect(f, x, 16 - h - 3, x + 1, 16 - h - 1, "5")
        line(f, [(x, 15), (x - 2, 10)], "c")
    yield "reeds", 16, 16, 0, [outline(f)]


def gen_obstacles():
    f = grid(20, 8)
    rect(f, 1, 1, 16, 6, "4")
    rect(f, 1, 1, 16, 1, "v")
    rect(f, 1, 6, 16, 6, "5")
    for x in (4, 9, 13):
        px(f, x, 3, "5")
        px(f, x + 1, 4, "5")
    ellipse(f, 17, 4, 2.2, 3, "3")
    ellipse(f, 17, 4, 1.1, 1.6, "v")
    px(f, 8, 0, "c")
    px(f, 9, 0, "c")
    yield "log", 20, 8, 0, [outline(f)]
    fr = []
    for k in range(2):
        f = grid(32, 10)
        ellipse(f, 16, 5, 16, 5, "3")
        ellipse(f, 16, 5.3, 14, 3.6, "h")
        for x in range(4, 28, 5):
            xx = x + (2 if k else 0)
            rect(f, xx, 4 + (x // 5) % 2, xx + 2, 4 + (x // 5) % 2, "i")
        rect(f, 6 + k * 3, 6, 7 + k * 3, 6, "j")
        ellipse(f, 1, 3, 2, 2, "c")
        ellipse(f, 30, 7, 2, 2, "c")
        fr.append(f)
    yield "stream", 32, 10, 3, fr
    f = grid(16, 12)
    rect(f, 1, 1, 14, 11, "a")
    rect(f, 1, 1, 14, 2, "b")
    rect(f, 1, 10, 14, 11, "9")
    rng = random.Random(4)
    for _ in range(14):
        px(f, rng.randrange(1, 15), rng.randrange(3, 10), "b" if rng.random() < 0.5 else "3")
    rect(f, 4, 1, 4, 11, "5")
    rect(f, 11, 1, 11, 11, "5")
    px(f, 0, 3, "b")
    px(f, 15, 6, "b")
    yield "hay_bale", 16, 12, 0, [outline(f)]
    f = grid(12, 6)
    rect(f, 1, 1, 9, 4, "4")
    rect(f, 1, 1, 9, 1, "v")
    ellipse(f, 10, 2.5, 1.5, 2, "3")
    px(f, 4, 0, "c")
    yield "twig_log", 12, 6, 0, [outline(f)]
    f = grid(16, 4)
    ellipse(f, 8, 2, 8, 2, "h")
    rect(f, 4, 1, 7, 1, "i")
    px(f, 10, 2, "j")
    yield "puddle", 16, 4, 0, [f]
    fr = []
    for k in range(3):
        f = grid(16, 8)
        rng = random.Random(k)
        for i in range(7):
            ang = math.pi * (0.15 + 0.7 * i / 6)
            d = 2 + k * 2.2
            x = 8 - math.cos(ang) * d * 1.3
            y = 7 - math.sin(ang) * d * (1.1 if k < 2 else 0.9)
            px(f, int(x), int(y), "i" if i % 2 else "j")
            if k < 2:
                px(f, int(x), int(y) + 1, "h")
        fr.append(f)
    yield "splash", 16, 8, 12, fr


def gen_collectibles():
    fr = []
    for k in range(2):
        f = grid(8, 8)
        ellipse(f, 4, 4.6, 3.2, 3.0, "8")
        shade(f, "8", "7", mgrid(f)[0] >= 6)
        px(f, 2, 3, "t")
        px(f, 2, 4, "j")
        rect(f, 4, 0, 4, 2, "5")
        px(f, 5, 1, "c")
        px(f, 6, 1, "c")
        f = outline(f)
        if k:
            px(f, 7, 0, "b")
            px(f, 0, 7, "j")
        fr.append(f)
    yield "apple", 8, 8, 3, fr
    for name, (a, b) in {"pink": ("t", "s"), "blue": ("i", "h"), "yellow": ("b", "a")}.items():
        fr = []
        for k in range(2):
            f = grid(8, 8)
            rect(f, 4, 4, 4, 7, "d")
            px(f, 3, 6, "c")
            px(f, 5, 5, "c")
            cx = 4 + (0 if k == 0 else 0)
            for dx, dy in [(-1, 0), (1, 0), (0, -1), (0, 1)]:
                px(f, cx + dx, 2 + dy, a)
            px(f, cx - 1, 1, b if k else a)
            px(f, cx + 1, 3, b)
            px(f, cx, 2, "a" if name != "yellow" else "9")
            f = outline(f)
            if k:
                px(f, 7, 0, "j")
            fr.append(f)
        yield f"flower_{name}", 8, 8, 2, fr


def gen_animals():
    # rabbit 12x10: hole, peek, up, ears wiggle
    fr = []
    for k in range(4):
        f = grid(12, 10)
        if k >= 1:
            up = [0, 2, 5, 5][k]
            by = 8 - up
            if k >= 2:
                ellipse(f, 6, by + 1.8, 3.2, 2.4, "k")
                ellipse(f, 6.5, by + 2.3, 1.8, 1.4, "j")
            ellipse(f, 6, by, 2.6, 2.2, "k")
            ear = 1 if k == 3 else 0
            rect(f, 4 - ear, by - 5, 5 - ear, by - 1, "k")
            rect(f, 7 + ear, by - 5, 8 + ear, by - 1, "k")
            px(f, 4 - ear, by - 4, "t")
            px(f, 8 + ear, by - 4, "t")
            px(f, 5, by, "p")
            px(f, 7, by, "p")
            px(f, 6, by + 1, "t")
            f = outline(f)
        ellipse(f, 6, 9, 5.8, 1.6, "6")
        rect(f, 0, 9, 11, 9, "5")
        ellipse(f, 6, 9.2, 4.5, 0.9, "6")
        fr.append(f)
    yield "rabbit", 12, 10, 4, fr
    ANIMS["rabbit"] = {"hole": [0, 1, 0], "peek": [1, 1, 0], "up": [2, 2, 4]}
    # sheep 16x12
    fr = []
    for k in range(4):
        f = grid(16, 12)
        run = k >= 2
        for i, x in enumerate([4, 6, 10, 12]):
            off = (1 if (i + k) % 2 else -1) if run else 0
            rect(f, x + off, 8, x + off, 11, "6")
        for cx, cy in [(5, 5), (8, 4), (11, 5), (7, 7), (10, 7), (5, 7), (12, 7)]:
            ellipse(f, cx, cy, 2.3, 2.1, "j")
        for cx, cy in [(6, 6), (10, 6)]:
            px(f, cx, cy, "k")
        if run:
            hx, hy = 14, 3
        else:
            hx, hy = 14, 7 + (k % 2)
        ellipse(f, hx, hy, 1.8, 1.6, "u")
        px(f, hx - 2, hy - 1, "u")
        px(f, hx, hy - 1, "p")
        px(f, hx + 1, hy + 1, "v" if not run else "7")
        ellipse(f, hx - 1, hy - 2, 1.3, 1.0, "j")
        fr.append(outline(f))
    yield "sheep", 16, 12, 4, fr
    ANIMS["sheep"] = {"graze": [0, 2, 2], "run": [2, 2, 8]}
    # duck 10x8
    fr = []
    for k in range(4):
        f = grid(10, 8)
        bob = k % 2
        ellipse(f, 4.5, 5 + bob * 0.5, 3.5, 2, "j")
        ellipse(f, 7, 2.8 + bob * 0.5, 1.6, 1.6, "j")
        rect(f, 8, 3 + bob, 9, 3 + bob, "9")
        px(f, 7, 2 + bob, "p")
        if k >= 2:
            poly(f, [(2, 4), (4, 0 + (k - 2) * 2), (6, 4)], "k")
        else:
            line(f, [(2, 5), (5, 5)], "k")
        f = outline(f)
        rect(f, 0, 7, 9, 7, "h")
        fr.append(f)
    yield "duck", 10, 8, 4, fr
    ANIMS["duck"] = {"swim": [0, 2, 2], "flap": [2, 2, 8]}
    # cow 24x16: idle, moo
    fr = []
    for k in range(2):
        f = grid(24, 16)
        ellipse(f, 10, 8, 8, 4.2, "j")
        for x in (4, 7, 13, 16):
            rect(f, x, 11, x + 1, 15, "j")
            px(f, x, 15, "o")
            px(f, x + 1, 15, "o")
        ellipse(f, 7, 7, 2.6, 2.0, "o")
        ellipse(f, 13, 9, 2.2, 1.6, "o")
        ellipse(f, 12, 12.2, 1.6, 0.9, "t")
        line(f, [(2.5, 6), (1, 10)], "j")
        px(f, 1, 11, "o")
        hy = 6 if k == 0 else 3
        ellipse(f, 19.5, hy, 2.6, 2.6, "j")
        ellipse(f, 20.5, hy + 2, 2.2, 1.4, "t")
        px(f, 19, hy - 1, "p")
        rect(f, 17, hy - 3, 17, hy - 2, "k")
        rect(f, 21, hy - 3, 21, hy - 2, "k")
        px(f, 16, hy - 1, "o")
        if k:
            px(f, 21, hy + 2, "7")
            px(f, 22, hy + 2, "7")
        fr.append(outline(f))
    yield "cow", 24, 16, 2, fr
    ANIMS["cow"] = {"idle": [0, 1, 0], "moo": [1, 1, 0]}
    fr = []
    for k in range(2):
        f = grid(8, 6)
        ellipse(f, 4, 3.5, 2, 1.4, "h")
        px(f, 6, 3, "a")
        px(f, 5, 2, "p")
        if k == 0:
            line(f, [(2, 3), (1, 0)], "g")
            line(f, [(4, 2), (5, 0)], "g")
        else:
            line(f, [(2, 4), (0, 5)], "g")
            line(f, [(4, 4), (5, 5)], "g")
        fr.append(f)
    yield "bird", 8, 6, 8, fr
    f = grid(160, 60)
    yy, xx = mgrid(f)
    d = np.sqrt((xx + 0.5 - 80) ** 2 + ((yy + 0.5 - 62) * 1.35) ** 2)
    for i, col in enumerate(["8", "9", "b", "c", "h", "r"]):
        r0 = 78 - i * 4
        f[(d <= r0) & (d > r0 - 4)] = C(col)
    yield "rainbow", 160, 60, 0, [f]


# ---------------------------------------------------------------- the show

JUMP_COLS = [("8", "7"), ("h", "g"), ("b", "a"), ("c", "d"), ("s", "r"), ("9", "1")]


def gen_show():
    f = grid(16, 16)
    rect(f, 1, 4, 2, 15, "j")
    rect(f, 2, 4, 2, 15, "k")
    rect(f, 0, 6, 15, 7, "j")
    rect(f, 0, 7, 15, 7, "k")
    rect(f, 0, 11, 15, 12, "j")
    rect(f, 0, 12, 15, 12, "k")
    yield "show_fence", 16, 16, 0, [f]
    for i, (a, b) in enumerate(JUMP_COLS, 1):
        f = grid(24, 24)
        for x0 in (1, 19):
            rect(f, x0, 4, x0 + 3, 23, "j")
            rect(f, x0 + 3, 4, x0 + 3, 23, "k")
            rect(f, x0, 3, x0 + 3, 4, a)
            rect(f, x0 + 1, 2, x0 + 2, 2, a)
        for y in ([9, 14, 19] if i % 2 else [11, 17]):
            for x in range(5, 19):
                px(f, x, y, a if (x // 3) % 2 == 0 else "j")
                px(f, x, y + 1, b if (x // 3) % 2 == 0 else "k")
        # flower boxes at the foot of the wings
        rect(f, 0, 21, 5, 23, "4")
        rect(f, 18, 21, 23, 23, "4")
        for x in (1, 3, 19, 21):
            px(f, x, 20, "t" if x % 4 == 1 else "b")
        yield f"jump_{i}", 24, 24, 0, [outline(f)]
    f = grid(12, 10)
    rect(f, 1, 3, 2, 9, "j")
    rect(f, 9, 3, 10, 9, "j")
    for x in range(3, 9):
        px(f, x, 6, "t" if x % 2 else "j")
    rect(f, 1, 2, 2, 2, "t")
    rect(f, 9, 2, 10, 2, "t")
    yield "mini_jump", 12, 10, 0, [outline(f)]
    for name, (a, b) in {"red": ("8", "7"), "blue": ("h", "g"), "yellow": ("b", "a"), "green": ("c", "d")}.items():
        f = grid(8, 10)
        poly(f, [(3.5, 0.5), (4.5, 0.5), (7, 8.5), (1, 8.5)], a)
        rect(f, 2, 4, 5, 4, "j")
        rect(f, 0, 8, 7, 9, b)
        yield f"cone_{name}", 8, 10, 0, [outline(f)]
    f = grid(8, 24)
    rect(f, 1, 1, 2, 23, "k")
    rect(f, 1, 1, 1, 23, "j")
    poly(f, [(3, 1), (7, 3.5), (3, 6)], "j")
    rect(f, 0, 22, 3, 23, "l")
    yield "pick_pole", 8, 24, 0, [outline(f)]
    fr = []
    for k in range(2):
        f = grid(8, 8)
        rect(f, 0, 0, 7, 0, "5")
        if k == 0:
            poly(f, [(0.5, 1), (7.5, 1), (4, 7.5)], "8")
            poly(f, [(2.5, 1), (5.5, 1), (4, 4)], "b")
        else:
            poly(f, [(0.5, 1), (7.5, 1), (4.8, 7.5)], "8")
            poly(f, [(2.5, 1), (5.5, 1), (4.4, 4)], "b")
        fr.append(f)
    yield "flag", 8, 8, 3, fr
    f = grid(96, 32)
    for i, y in enumerate([4, 13, 22]):
        rect(f, 2 + i * 0, y, 93, y + 3, "v")
        rect(f, 2, y, 93, y, "3")
        rect(f, 2, y + 3, 93, y + 3, "4")
        rect(f, 2, y + 4, 93, y + 8, "5")
    for x in (2, 30, 64, 92):
        rect(f, x, 4, x + 1, 31, "4")
    rect(f, 0, 29, 95, 31, "d")
    rect(f, 0, 29, 95, 29, "c")
    yield "grandstand", 96, 32, 0, [outline(f)]
    yield "judge", 24, 32, 2, judge_frames()
    ANIMS["judge"] = {"idle": [0, 1, 0], "nod": [0, 2, 3]}
    fr = []
    for k in range(2):
        f = grid(16, 16)
        rect(f, 7, 1, 8, 3, "5")
        poly(f, [(4.5, 12), (5.5, 5), (8, 3.5), (10.5, 5), (11.5, 12)], "a")
        rect(f, 3, 11, 12, 12, "a")
        shade(f, "a", "9", mgrid(f)[1] >= 10)
        line(f, [(6, 6), (6, 10)], "b")
        cx = 8 + (2 if k else 0)
        ellipse(f, cx, 13.5, 1.3, 1.3, "5")
        f = outline(f)
        if k:
            for (x0, y0, x1, y1) in [(1, 6, 2, 4), (14, 6, 13, 4), (0, 10, 2, 10), (15, 10, 13, 10)]:
                line(f, [(x0, y0), (x1, y1)], "j")
        fr.append(f)
    yield "bell", 16, 16, 4, fr
    for name, (a, b) in {"blue": ("h", "g"), "red": ("8", "7"), "yellow": ("b", "a"), "green": ("c", "d"),
                         "purple": ("s", "r")}.items():
        f = grid(12, 16)
        poly(f, [(3, 8), (5.5, 8), (4.5, 15), (2.5, 13.5)], b)
        poly(f, [(6.5, 8), (9, 8), (9.5, 13.5), (7.5, 15)], a)
        ellipse(f, 6, 6, 5.6, 5.6, a)
        yy, xx = mgrid(f)
        ang = np.arctan2(yy + 0.5 - 6, xx + 0.5 - 6)
        d = np.sqrt((xx + 0.5 - 6) ** 2 + (yy + 0.5 - 6) ** 2)
        f[(d > 3.2) & (d <= 5.6) & (((ang * 8 / math.pi).astype(int)) % 2 == 0)] = C(b)
        ellipse(f, 6, 6, 3.0, 3.0, "j")
        ellipse(f, 6, 6, 2.0, 2.0, "a")
        px(f, 5, 5, "b")
        yield f"rosette_{name}", 12, 16, 0, [outline(f)]
    yield "rosette_wall", 320, 180, 0, [rosette_wall()]
    POINTS["rosette_wall"] = {"board": [16, 20, 208, 112], "door": [244, 64, 56, 108], "shoes": [238, 46, 68]}
    fr = []
    for col in ["8", "b", "h", "c", "s", "9"]:
        f = grid(4, 4)
        rect(f, 0, 1, 2, 2, col)
        px(f, 3, 1, col)
        fr.append(f)
    yield "confetti", 4, 4, 0, fr


def judge_frames():
    fr = []
    for k in range(2):
        f = grid(24, 32)
        head = hz.render(hz.FOAL, hz.Pose(neck=-6 + 6 * k, tail=0.0), "grey", s=2, tack=False)
        crop = head[0:26, 20:44]          # the head and neck of the foal drawing, at 2x
        f[4:30, 0:24] = np.where(crop >= 0, crop, f[4:30, 0:24])
        # wise white eyebrows and a white muzzle: an old horse
        yy, xx = mgrid(f)
        # the hat: a brown bowler with a red band, between the ears
        top = int(np.nonzero((f >= 0).any(axis=1))[0][0])
        hx = int(np.nonzero(f[top] >= 0)[0].mean())
        hy = top - 1
        ellipse(f, hx + 0.5, hy + 1.5, 3.6, 2.6, "5")
        rect(f, hx - 5, hy + 3, hx + 5, hy + 3, "5")
        rect(f, hx - 3, hy + 2, hx + 3, hy + 2, "8")
        px(f, hx - 1, hy, "4")
        # bow tie
        poly(f, [(4, 21), (6.5, 22.5), (4, 24)], "h")
        poly(f, [(9, 21), (6.5, 22.5), (9, 24)], "h")
        # the table with a green cloth and a white card
        rect(f, 0, 25, 23, 31, "d")
        rect(f, 0, 25, 23, 26, "c")
        rect(f, 2, 27, 21, 27, "j")
        f = outline(f)
        fr.append(f)
    return fr


def rosette_wall():
    f = grid(320, 180)
    for x in range(320):
        col = "4" if (x // 10) % 2 == 0 else "v"
        rect(f, x, 0, x, 179, col)
    for x in range(9, 320, 10):
        rect(f, x, 0, x, 179, "5")
    rng = random.Random(8)
    for _ in range(90):
        px(f, rng.randrange(320), rng.randrange(150), "5")
    # the board
    rect(f, 12, 16, 227, 135, "5")
    rect(f, 16, 20, 223, 131, "3")
    for _ in range(300):
        px(f, rng.randrange(16, 224), rng.randrange(20, 132), rng.choice("v2"))
    rect(f, 12, 16, 227, 17, "6")
    # the door to the paddock
    rect(f, 240, 60, 303, 171, "5")
    rect(f, 244, 64, 299, 171, "4")
    for x in range(247, 299, 5):
        rect(f, x, 64, x, 171, "5")
    line(f, [(245, 169), (298, 66)], "v", 3)
    rect(f, 244, 116, 299, 118, "v")
    rect(f, 290, 110, 292, 113, "a")
    # the horseshoe rail over the door
    rect(f, 236, 52, 307, 54, "5")
    # a warm straw floor
    rect(f, 0, 150, 319, 179, "3")
    for _ in range(420):
        x, y = rng.randrange(320), rng.randrange(150, 180)
        ln = rng.randrange(2, 5)
        line(f, [(x, y), (x + ln, y + rng.choice([-1, 0, 1]))], rng.choice("abv2"))
    rect(f, 0, 148, 319, 149, "5")
    return f


# ---------------------------------------------------------------- icons

def gen_icons():
    # seat_rider: a big horseshoe
    f = grid(16, 16)
    ellipse(f, 8, 7.5, 6.5, 6.5, "k")
    ellipse(f, 8, 8.2, 3.4, 4.2, T)
    rect(f, 6, 9, 9, 15, T)
    shade(f, "k", "l", mgrid(f)[0] >= 10)
    for x, y in [(3, 5), (12, 5), (3, 9), (12, 9)]:
        px(f, x, y, "n")
    px(f, 5, 2, "j")
    px(f, 6, 1, "j")
    yield "seat_rider", 16, 16, 0, [outline(f)]
    f = grid(16, 16)
    ellipse(f, 8, 6, 6.8, 3.6, "4")
    ellipse(f, 8, 5, 5.2, 2, "v")
    for x in range(2, 15):
        rect(f, x, 9, x, 13 + (x % 2), "k" if x % 2 else "l")
    yield "seat_brush", 16, 16, 0, [outline(f)]
    f = grid(16, 16)
    head = hz.render(hz.MARE, hz.Pose(neck=-16, mouth=True, toss=True), "bay", tack=False)
    crop = head[0:14, 24:38]
    f[1:15, 0:14] = crop
    for (x0, y0, x1, y1) in [(14, 4, 15, 3), (14, 7, 15, 7), (14, 10, 15, 11)]:
        line(f, [(x0, y0), (x1, y1)], "j")
    yield "seat_neigh", 16, 16, 0, [f]
    f = grid(16, 16)
    poly(f, [(1, 7), (8, 1), (15, 7)], "7")
    rect(f, 2, 7, 13, 15, "8")
    rect(f, 5, 9, 10, 15, "5")
    line(f, [(5, 9), (10, 15)], "4")
    line(f, [(10, 9), (5, 15)], "4")
    stamp(f, 6, 3, ["k..k", "k..k", ".kk."])
    yield "stage_stable", 16, 16, 0, [outline(f)]
    f = grid(16, 16)
    rect(f, 7, 9, 8, 14, "5")
    ellipse(f, 8, 6.5, 6.5, 5.5, "d")
    ellipse(f, 7, 5, 4.5, 3.5, "c")
    px(f, 11, 6, "8")
    px(f, 5, 8, "8")
    rect(f, 1, 14, 14, 15, "c")
    yield "stage_trail", 16, 16, 0, [outline(f)]
    f = grid(16, 16)
    poly(f, [(4, 9), (7, 9), (6, 15), (3, 14)], "g")
    poly(f, [(9, 9), (12, 9), (13, 14), (10, 15)], "h")
    ellipse(f, 8, 7, 6.5, 6.5, "h")
    yy, xx = mgrid(f)
    ang = np.arctan2(yy + 0.5 - 7, xx + 0.5 - 8)
    d = np.sqrt((xx + 0.5 - 8) ** 2 + (yy + 0.5 - 7) ** 2)
    f[(d > 3.6) & (d <= 6.5) & (((ang * 8 / math.pi).astype(int)) % 2 == 0)] = C("g")
    ellipse(f, 8, 7, 3.4, 3.4, "j")
    ellipse(f, 8, 7, 2.2, 2.2, "a")
    yield "stage_show", 16, 16, 0, [outline(f)]
    f = grid(8, 8)
    poly(f, [(4, 1), (7.5, 6), (0.5, 6)], "b")
    rect(f, 1, 5, 6, 5, "a")
    up = outline(f)
    yield "arrow_up", 8, 8, 0, [up]
    yield "arrow_down", 8, 8, 0, [up[::-1, :].copy()]


GENERATORS = [gen_horses, gen_mud, gen_stable_items, gen_stable, gen_skies, gen_hills, gen_trees_mid,
              gen_ground, gen_props, gen_obstacles, gen_collectibles, gen_animals, gen_show, gen_icons]


def generate():
    for g in GENERATORS:
        yield from g()
