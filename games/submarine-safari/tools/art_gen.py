"""Submarine Safari's procedural sprites (Endesga 32), rendered by sprites.py.

Every function returns (name, w, h, fps, frames); frames are int8 arrays of
palette indices (-1 = transparent). Shapes are geometry (ellipses, polygons)
plus small stamped grids for faces, so proportions stay clean and every
creature gets the same cute face: big dark eyes with a glint, a smile,
pink cheeks. Nothing has teeth that look sharp, nothing frowns.

Endesga 32 chars (index):
  0 be4a2f  1 d77643  2 ead4aa  3 e4a672  4 b86f50  5 733e39  6 3e2731  7 a22633
  8 e43b44  9 f77622  a feae34  b fee761  c 63c74d  d 3e8948  e 265c42  f 193c3e
  g 124e89  h 0099db  i 2ce8f5  j ffffff  k c0cbdc  l 8b9bb4  m 5a6988  n 3a4466
  o 262b44  p 181425  q ff0044  r 68386c  s b55088  t f6757a  u e8b796  v c28569
"""

from __future__ import annotations

import math
import random

import numpy as np
from PIL import Image, ImageDraw

CHARS = "0123456789abcdefghijklmnopqrstuv"
T = -1
INK = 25


def C(ch: str) -> int:
    return CHARS.index(ch)


# ---------------------------------------------------------------- drawing helpers

def grid(w: int, h: int) -> np.ndarray:
    return np.full((h, w), T, dtype=np.int8)


def mgrid(f: np.ndarray):
    return np.mgrid[0:f.shape[0], 0:f.shape[1]]


def ellipse(f, cx, cy, rx, ry, col) -> None:
    yy, xx = mgrid(f)
    f[((xx + 0.5 - cx) / rx) ** 2 + ((yy + 0.5 - cy) / ry) ** 2 <= 1.0] = C(col) if isinstance(col, str) else col


def rect(f, x0, y0, x1, y1, col) -> None:
    h, w = f.shape
    f[max(0, y0):min(h, y1 + 1), max(0, x0):min(w, x1 + 1)] = C(col) if isinstance(col, str) else col


def poly(f, pts, col) -> None:
    h, w = f.shape
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon([(float(x), float(y)) for x, y in pts], fill=255)
    f[np.asarray(m) > 0] = C(col) if isinstance(col, str) else col


def line(f, pts, col, width=1) -> None:
    h, w = f.shape
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).line([(float(x), float(y)) for x, y in pts], fill=255, width=width)
    f[np.asarray(m) > 0] = C(col) if isinstance(col, str) else col


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
    filled = f >= 0
    near = np.zeros_like(filled)
    near[1:, :] |= filled[:-1, :]
    near[:-1, :] |= filled[1:, :]
    near[:, 1:] |= filled[:, :-1]
    near[:, :-1] |= filled[:, 1:]
    out = f.copy()
    out[near & ~filled] = col
    return out


def shift(f: np.ndarray, dx: int, dy: int) -> np.ndarray:
    h, w = f.shape
    out = np.full_like(f, T)
    ys, yd = (slice(max(0, -dy), h - max(0, dy)), slice(max(0, dy), h - max(0, -dy)))
    xs, xd = (slice(max(0, -dx), w - max(0, dx)), slice(max(0, dx), w - max(0, -dx)))
    out[yd, xd] = f[ys, xs]
    return out


# A cute face kit.
EYE_S = ["jp", "pp"]                  # 2x2: glint top-left
EYE_M = ["jp", "pp", "pp"]            # 2x3
EYE_L = ["pjp", "ppp", "ppp"]         # 3x3
EYE_WHITE = ["jjj", "jpj", "jpp"]     # for dark bodies: white eye, dark pupil


def smile(f, x, y, w=3) -> None:
    """A little U smile, w wide (3 or 4), top-left at x, y."""
    if w <= 3:
        stamp(f, x, y, ["p.p", ".p."])
    else:
        stamp(f, x, y, ["p..p", ".pp."])


# ---------------------------------------------------------------- the sub

def sub_frame(prop: int) -> np.ndarray:
    f = grid(40, 24)
    # tail fins
    poly(f, [(4, 9), (10, 12), (10, 16), (4, 19)], "9")
    # hull: a yellow capsule
    ellipse(f, 21, 15, 15.5, 7.2, "a")
    rect(f, 10, 10, 31, 20, "a")
    ellipse(f, 21, 15, 15.5, 7.2, "a")
    yy, xx = mgrid(f)
    shade(f, "a", "9", yy >= 19)
    shade(f, "a", "b", (yy <= 9) & (xx > 12) & (xx < 32))
    # conning tower + periscope
    rect(f, 16, 4, 25, 8, "a")
    rect(f, 16, 4, 25, 4, "b")
    rect(f, 23, 0, 24, 4, "l")
    rect(f, 23, 0, 27, 1, "l")
    px(f, 27, 1, "i")
    # three portholes (the three seats)
    for cx in (13, 21, 29):
        stamp(f, cx - 2, 12, [".kkk.", "kiiik", "kijik", "kiiik", ".kkk."])
        px(f, cx - 1, 13, "j")
    # headlight at the nose
    stamp(f, 35, 14, ["bj", "bb"])
    # rivet line and stripe
    for x in range(11, 33, 3):
        px(f, x, 18, "9")
    # propeller hub + blades (4-frame spin)
    rect(f, 2, 14, 4, 15, "l")
    if prop == 0:
        rect(f, 1, 8, 2, 13, "k")
        rect(f, 1, 16, 2, 21, "k")
    elif prop == 1:
        line(f, [(0, 9), (3, 20)], "k", 2)
    elif prop == 2:
        rect(f, 1, 12, 2, 17, "k")
    else:
        line(f, [(3, 9), (0, 20)], "k", 2)
    return outline(f)


def gen_sub():
    return [("sub", 40, 24, 12, [sub_frame(i) for i in range(4)])]


# ---------------------------------------------------------------- camera things

def gen_viewfinder():
    frames = []
    for locked in (False, True):
        f = grid(48, 40)
        col = "b" if locked else "j"
        L = 10
        for (x, y, sx, sy) in ((1, 1, 1, 1), (46, 1, -1, 1), (1, 38, 1, -1), (46, 38, -1, -1)):
            for i in range(L):
                for t in range(2):
                    px(f, x + sx * i, y + sy * t, col)
                    px(f, x + sx * t, y + sy * i, col)
        if locked:
            stamp(f, 22, 18, [".b.", "bjb", ".b."])
        else:
            stamp(f, 23, 19, ["jj", "jj"])
        frames.append(outline(f))
    return [("viewfinder", 48, 40, 0, frames)]


def gen_flash():
    frames = []
    for k, (r_core, r_ring, ray) in enumerate(((7, 12, 20), (12, 19, 28), (5, 26, 31))):
        f = grid(64, 64)
        yy, xx = mgrid(f)
        d = np.sqrt((xx + 0.5 - 32) ** 2 + (yy + 0.5 - 32) ** 2)
        if k < 2:
            f[d <= r_ring] = C("b")
            f[d <= r_ring - 3] = C("k")
            f[d <= r_core] = C("j")
        else:
            f[(d <= r_ring) & (d >= r_ring - 2)] = C("k")
            f[d <= r_core] = C("j")
        for i in range(8):
            a = i * math.pi / 4 + (math.pi / 8 if k == 1 else 0)
            x1, y1 = 32 + math.cos(a) * ray, 32 + math.sin(a) * ray
            line(f, [(32, 32), (x1, y1)], "j" if k < 2 else "k", 2 if i % 2 == 0 else 1)
        frames.append(f)
    return [("flash", 64, 64, 30, frames)]


def gen_polaroid():
    f = grid(24, 28)
    rect(f, 0, 0, 23, 27, "j")
    rect(f, 23, 1, 23, 27, "k")
    rect(f, 1, 27, 23, 27, "k")
    rect(f, 2, 2, 21, 21, "o")
    rect(f, 6, 24, 17, 24, "k")
    return [("polaroid", 24, 28, 0, [f])]


def gen_album_slot():
    f = grid(20, 20)
    rect(f, 1, 0, 18, 19, "n")
    rect(f, 0, 1, 19, 18, "n")
    rect(f, 1, 1, 18, 18, "o")
    return [("album_slot", 20, 20, 0, [f])]


# ---------------------------------------------------------------- the easy fish

def clownfish_frame(k: int) -> np.ndarray:
    f = grid(16, 16)
    tail = [(4, 8), (0, 4 + k), (0, 12 - k)]
    poly(f, tail, "9")
    ellipse(f, 8.5, 8.5, 6.2, 4.5, "9")
    poly(f, [(6, 5), (9, 2), (11, 5)], "9")      # dorsal fin
    poly(f, [(7, 12), (9, 14), (10, 12)], "9")   # belly fin
    yy, xx = mgrid(f)
    body = f == C("9")
    for sx, col in ((6, "j"), (7, "j"), (11, "j")):
        f[body & (xx == sx) & (yy >= 4) & (yy <= 13)] = C(col)
    f[body & (xx == 5) & (yy >= 5) & (yy <= 12)] = C("p")
    f[body & (xx == 8) & (yy >= 5) & (yy <= 12)] = C("p")
    stamp(f, 12, 6, EYE_S)
    stamp(f, 12, 10, ["pp"])
    px(f, 11, 9, "t")
    return outline(f)


def gen_clownfish():
    return [("clownfish", 16, 16, 4, [clownfish_frame(0), clownfish_frame(1)])]


def tang_frame(k: int) -> np.ndarray:
    f = grid(16, 16)
    poly(f, [(3, 8), (0, 4 + k), (0, 12 - k)], "b")
    ellipse(f, 8.5, 8.5, 6.2, 5.0, "h")
    poly(f, [(4, 5), (8, 2), (12, 5)], "g")
    yy, xx = mgrid(f)
    # the dark "palette" marking along the back
    f[(f == C("h")) & (yy <= 6) & (xx >= 4) & (xx <= 11)] = C("g")
    f[(f == C("h")) & (yy == 7) & (xx >= 5) & (xx <= 8)] = C("g")
    f[(f == C("h")) & (yy >= 11)] = C("i")
    stamp(f, 11, 7, ["jp", "pp"])
    stamp(f, 13, 10, ["pp"])
    px(f, 11, 10, "t")
    return outline(f)


def gen_blue_tang():
    return [("blue_tang", 16, 16, 4, [tang_frame(0), tang_frame(1)])]


def puffer_frame(k: int, puffed: bool) -> np.ndarray:
    f = grid(16, 16)
    if puffed:
        r = 6.2 + 0.4 * k
        for i in range(10):
            a = i * math.pi / 5 + k * 0.3
            line(f, [(8, 8), (8 + math.cos(a) * (r + 1.8), 8 + math.sin(a) * (r + 1.8))], "v")
        ellipse(f, 8, 8, r, r, "b")
        yy, xx = mgrid(f)
        shade(f, "b", "j", yy >= 11)
        for sx, sy in ((5, 5), (10, 4), (4, 9), (11, 8)):
            px(f, sx, sy, "3")
        stamp(f, 5, 6, ["jp", "pp"])
        stamp(f, 9, 6, ["jp", "pp"])
        stamp(f, 7, 10, [".p.", "p.p", ".p."])
        px(f, 4, 9, "t")
        px(f, 12, 9, "t")
        return outline(f)
    poly(f, [(4, 8), (1, 5 + k), (1, 11 - k)], "a")
    ellipse(f, 8.5, 8.5, 5.6, 4.8, "b")
    yy, xx = mgrid(f)
    shade(f, "b", "j", yy >= 11)
    for sx, sy in ((6, 5), (9, 5), (7, 7)):
        px(f, sx, sy, "3")
    poly(f, [(8, 9), (10, 11 + k), (7, 11)], "a")
    stamp(f, 11, 6, EYE_S)
    px(f, 13, 9, "p")
    px(f, 14, 9, "p")
    px(f, 11, 9, "t")
    return outline(f)


def gen_pufferfish():
    return [("pufferfish", 16, 16, 4, [puffer_frame(0, False), puffer_frame(1, False)]),
            ("pufferfish_puffed", 16, 16, 6, [puffer_frame(0, True), puffer_frame(1, True)])]


def seahorse_frame(k: int) -> np.ndarray:
    f = grid(16, 16)
    dy = k
    ellipse(f, 8.5, 9.5 + dy * 0.5, 2.8, 3.8, "a")            # belly
    ellipse(f, 9.0, 4.0 + dy * 0.5, 2.6, 2.4, "a")            # head
    rect(f, 10, 3 + dy // 2 + 1, 13, 4 + dy // 2 + 1, "a")     # snout
    rect(f, 7, 6, 9, 7, "a")                                    # neck
    # curly tail
    for x, y in ((8, 13), (8, 14), (7, 14), (6, 14), (6, 13), (7, 12)):
        px(f, x, y, "a")
    yy, xx = mgrid(f)
    shade(f, "a", "9", (xx <= 7) & (yy >= 7))
    for y in (8, 10, 12):
        if f[y, 10] == C("a"):
            px(f, 10, y, "b")
    poly(f, [(5, 8), (3, 9), (5, 11)], "b")                    # back fin
    stamp(f, 7, 1, ["a.a"])                                     # crown
    stamp(f, 9, 3 + dy // 2, ["jp", "pp"])
    px(f, 11, 6 + dy // 2, "t")
    return outline(f)


def gen_seahorse():
    return [("seahorse", 16, 16, 3, [seahorse_frame(0), seahorse_frame(1)])]


def lantern_frame(k: int) -> np.ndarray:
    f = grid(16, 16)
    poly(f, [(3, 9), (0, 6 + k), (0, 12 - k)], "g")
    ellipse(f, 8.5, 9.5, 6.0, 3.6, "g")
    yy, xx = mgrid(f)
    shade(f, "g", "h", yy <= 7)
    for x in (4, 6, 8, 10):
        px(f, x, 11, "i")
    line(f, [(11, 6), (12, 3), (14, 2)], "l")                  # the lantern's stalk
    stamp(f, 13, 0, ["bj", "bb"] if k == 0 else ["jj", "jb"])
    stamp(f, 11, 8, ["jj", "jp"])
    px(f, 14, 11, "p")
    px(f, 13, 11, "p")
    return outline(f)


def gen_lantern_fish():
    return [("lantern_fish", 16, 16, 3, [lantern_frame(0), lantern_frame(1)])]


def turtle_frame(k: int) -> np.ndarray:
    f = grid(24, 24)
    # flippers first (under the shell)
    up = -2 if k else 0
    poly(f, [(14, 14), (20, 18 + up), (18, 20 + up), (13, 16)], "c")
    poly(f, [(7, 15), (3, 18 - up), (5, 19 - up), (9, 16)], "c")
    # head and neck
    ellipse(f, 19.2, 11.5, 3.2, 2.9, "c")
    # shell: a dome with a light rim
    ellipse(f, 11, 12, 7.8, 5.6, "d")
    yy, xx = mgrid(f)
    f[(f == C("d")) & (yy >= 16)] = C("3")
    f[(f == C("d")) & (yy <= 8) & (xx >= 7) & (xx <= 14)] = C("c")
    # hexagon pattern
    for cx, cy in ((8, 11), (12, 10), (15, 12), (11, 14)):
        stamp(f, cx - 1, cy - 1, [".e.", "ece", ".e."])
    stamp(f, 19, 10, EYE_S)
    px(f, 21, 13, "p")
    px(f, 22, 12, "p")
    px(f, 19, 13, "t")
    ellipse(f, 3.5, 13, 1.4, 1.1, "c")                           # little tail
    return outline(f)


def gen_turtle():
    return [("turtle", 24, 24, 3, [turtle_frame(0), turtle_frame(1)])]


# ---------------------------------------------------------------- the hiders

def crab_frame(k: int) -> np.ndarray:
    f = grid(24, 24)
    # legs
    for side in (-1, 1):
        for i in range(3):
            x0 = 12 + side * (3 + i * 2)
            x1 = x0 + side * 2
            y1 = 21 if (i + k) % 2 == 0 else 20
            line(f, [(x0, 16), (x1, y1)], "7")
    # arms and claws (raised, waving between frames)
    ly = 9 - k
    line(f, [(8, 14), (5, ly + 2)], "8", 2)
    line(f, [(16, 14), (19, ly + 2)], "8", 2)
    for cx in (4.5, 19.5):
        ellipse(f, cx, ly, 3.0, 2.8, "8")
    # pincer notches
    for cx in (4, 19):
        px(f, cx, ly - 2, "p")
        if k:
            px(f, cx + 1, ly - 2, "p")
    # body
    ellipse(f, 12, 16, 7.2, 4.3, "8")
    yy, xx = mgrid(f)
    shade(f, "8", "0", yy >= 19)
    shade(f, "8", "t", (yy == 13) & (xx >= 9) & (xx <= 14))
    # eye stalks
    for sx in (9, 14):
        rect(f, sx, 9, sx, 12, "8")
        stamp(f, sx - 1, 7, ["jj", "jp"])
    stamp(f, 10, 16, ["p..p", ".pp."])
    px(f, 8, 16, "t")
    px(f, 16, 16, "t")
    return outline(f)


def gen_crab():
    return [("crab", 24, 24, 4, [crab_frame(0), crab_frame(1)])]


def octopus_frame(k: int) -> np.ndarray:
    f = grid(24, 24)
    # tentacles: six curls under the head
    for i in range(6):
        x0 = 6.5 + i * 2.2
        pts = []
        for s in range(8):
            y = 13 + s
            x = x0 + math.sin(s * 0.8 + i + k * 1.6) * 1.2 + (i - 2.5) * s * 0.28
            pts.append((x, y))
        line(f, pts, "s", 2)
        ex, ey = pts[-1]
        px(f, int(round(ex)), int(round(ey)), "t")
    ellipse(f, 12, 9.5, 7.0, 6.4, "s")
    yy, xx = mgrid(f)
    shade(f, "s", "t", (yy <= 6) & (xx >= 8) & (xx <= 13))
    for sx, sy in ((7, 7), (16, 6), (15, 13)):
        px(f, sx, sy, "r")
    stamp(f, 8, 9, EYE_M)
    stamp(f, 14, 9, EYE_M)
    stamp(f, 10, 13, ["p..p", ".pp."])
    px(f, 7, 12, "t")
    px(f, 17, 12, "t")
    return outline(f)


def gen_octopus():
    return [("octopus", 24, 24, 4, [octopus_frame(0), octopus_frame(1)])]


def eel_frame(hx: int, mouth_open: bool, k: int) -> np.ndarray:
    """Facing right, coming out of a hole at the left edge (the level flips it)."""
    f = grid(24, 24)
    pts = [(0, 14)]
    for x in range(0, hx + 1, 2):
        pts.append((x, 14 + math.sin(x * 0.45 + k) * 1.2))
    line(f, pts, "c", 5)
    ellipse(f, hx + 1.5, 12.5, 4.4, 3.6, "c")
    yy, xx = mgrid(f)
    shade(f, "c", "b", (yy >= 15))
    shade(f, "c", "d", (yy <= 11) & (xx % 4 == 1))
    stamp(f, hx + 1, 10, ["jp", "pp"])
    if mouth_open:
        stamp(f, hx + 3, 13, ["ppp", "ptp", ".p."])
    else:
        stamp(f, hx + 3, 13, ["p.p", ".p."])
    px(f, hx, 14, "t")
    # the hole's dark rim at the left edge
    rect(f, 0, 9, 1, 19, "p")
    return outline(f)


def gen_eel():
    frames = [eel_frame(10, False, 0), eel_frame(14, False, 1), eel_frame(15, True, 2), eel_frame(14, False, 3)]
    return [("eel", 24, 24, 4, frames)]


# ---------------------------------------------------------------- the light-lovers

def jelly_frame(k: int) -> np.ndarray:
    f = grid(16, 24)
    rx = [6.5, 6.0, 5.5, 6.2][k]
    ry = [4.6, 5.0, 5.6, 4.9][k]
    for i in range(4):
        x0 = 4.5 + i * 2.3
        pts = [(x0 + math.sin(s * 0.9 + k * 1.5 + i) * 1.1, 10 + s) for s in range(12)]
        line(f, pts, "s" if i % 2 else "t")
    ellipse(f, 8, 8, rx, ry, "t")
    yy, xx = mgrid(f)
    shade(f, "t", "s", yy >= 11)
    shade(f, "t", "u", (yy <= 5) & (xx <= 7))
    px(f, 5, 5, "j")
    stamp(f, 5, 7, ["jp", "pp"])
    stamp(f, 9, 7, ["jp", "pp"])
    stamp(f, 7, 10, ["pp"])
    return outline(f)


def gen_jellyfish():
    return [("jellyfish", 16, 24, 6, [jelly_frame(i) for i in range(4)])]


def angler_frame(k: int) -> np.ndarray:
    f = grid(24, 24)
    poly(f, [(5, 14), (1, 10 + k), (1, 18 - k)], "r")                # tail
    ellipse(f, 12, 14, 8.0, 7.2, "r")
    yy, xx = mgrid(f)
    shade(f, "r", "s", (yy >= 17))
    shade(f, "r", "s", (yy <= 9) & (xx >= 9) & (xx <= 13))
    poly(f, [(9, 20), (12, 23), (14, 20)], "r")                        # fin
    # the lure on its stalk
    line(f, [(11, 8), (12, 4), (15, 2), (18, 3)], "l")
    stamp(f, 17, 2 + k, [".b.", "bjb", ".b."] if k == 0 else [".j.", "jbj", ".j."])
    # a big friendly eye and a wide smile with two little teeth
    stamp(f, 13, 9, ["jjj", "jpp", "jpp"])
    line(f, [(12, 16), (14, 18), (18, 18), (20, 16)], "p")
    px(f, 15, 18, "j")
    px(f, 17, 18, "j")
    px(f, 12, 13, "t")
    px(f, 18, 13, "t")
    return outline(f)


def gen_anglerfish():
    return [("anglerfish", 24, 24, 3, [angler_frame(0), angler_frame(1)])]


def squid_frame(k: int) -> np.ndarray:
    f = grid(24, 24)
    for i in range(6):
        x0 = 8.5 + i * 1.5
        pts = [(x0 + math.sin(s * 0.8 + k * 2 + i) * 1.0 + (i - 2.5) * s * 0.18, 14 + s) for s in range(8)]
        line(f, pts, "h" if i % 2 else "i")
    poly(f, [(12, 1), (6, 6), (18, 6)], "i")                           # fin tip
    ellipse(f, 12, 9.5 - k * 0.5, 5.0, 6.0 + k * 0.5, "i")
    yy, xx = mgrid(f)
    shade(f, "i", "h", (yy >= 12) & (xx >= 9) & (xx <= 15) & (yy <= 14))
    shade(f, "i", "j", (yy <= 6) & (xx <= 11) & (xx >= 9))
    stamp(f, 9, 9, EYE_M)
    stamp(f, 13, 9, EYE_M)
    stamp(f, 11, 13, ["pp"])
    px(f, 8, 12, "t")
    px(f, 16, 12, "t")
    return outline(f)


def gen_squid():
    return [("squid", 24, 24, 4, [squid_frame(0), squid_frame(1)])]


# ---------------------------------------------------------------- the whale

def whale_frame(k: int) -> np.ndarray:
    f = grid(128, 48)
    up = -5 if k == 0 else 5
    # tail stock and flukes
    poly(f, [(30, 18), (6, 22), (6, 30), (30, 36)], "g")
    poly(f, [(10, 26), (0, 16 + up), (4, 25), (0, 36 + up)], "g")
    # body
    ellipse(f, 70, 26, 52, 17, "g")
    yy, xx = mgrid(f)
    shade(f, "g", "h", (yy <= 14) & (xx >= 40) & (xx <= 110))
    # pale grooved belly
    belly = grid(128, 48)
    ellipse(belly, 78, 34, 42, 9, "k")
    f[(belly >= 0) & (f >= 0) & (yy >= 30)] = C("k")
    for gy in (33, 36, 39):
        f[(f == C("k")) & (yy == gy) & (xx % 2 == 0)] = C("l")
    # flipper
    poly(f, [(74, 34), (88, 44 + (1 if k else 0)), (82, 46 + (1 if k else 0)), (70, 38)], "g")
    # face: eye, smile, cheek
    stamp(f, 100, 22, ["pjp", "ppp", "ppp"])
    line(f, [(98, 30), (104, 32), (114, 31), (119, 28)], "p")
    rect(f, 96, 27, 98, 28, "t")
    # blowhole and a few spots
    rect(f, 88, 10, 90, 10, "o")
    for sx, sy in ((50, 18), (60, 13), (72, 16), (44, 24)):
        px(f, sx, sy, "i")
    return outline(f)


def gen_whale():
    return [("whale", 128, 48, 2, [whale_frame(0), whale_frame(1)])]


def gen_icon_whale():
    f = grid(20, 20)
    poly(f, [(5, 9), (1, 6), (2, 10), (1, 14)], "g")
    ellipse(f, 11.5, 10.5, 7.5, 5.2, "g")
    yy, xx = mgrid(f)
    f[(f == C("g")) & (yy >= 13)] = C("k")
    shade(f, "g", "h", (yy <= 6))
    stamp(f, 14, 8, ["jp", "pp"])
    stamp(f, 15, 12, ["p..", ".pp"])
    return [("icon_whale", 20, 20, 0, [outline(f)])]


# ---------------------------------------------------------------- bonus subjects

def gen_bonus():
    out = []
    frames = []
    for k in range(2):
        f = grid(8, 8)
        r = 3.4 if k == 0 else 3.1
        ellipse(f, 4, 4, r, r + (0.3 if k else 0), "k")
        ellipse(f, 4, 4, r - 1.0, r - 0.7, "i")
        px(f, 3, 2, "j")
        px(f, 2, 3, "j")
        frames.append(f)
    out.append(("bubble", 8, 8, 3, frames))

    f = grid(12, 12)
    ellipse(f, 6, 7, 5.2, 4.6, "u")
    rect(f, 4, 10, 7, 11, "u")
    yy, xx = mgrid(f)
    for rx in (2, 4, 6, 8, 10):
        f[(f == C("u")) & (xx == rx) & (yy <= 9)] = C("t")
    stamp(f, 4, 6, ["p..p", "....", ".pp."])
    out.append(("shell", 12, 12, 0, [outline(f)]))

    f = grid(12, 12)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 5.6 if i % 2 == 0 else 2.4
        pts.append((6 + r * math.cos(a), 6.5 + r * math.sin(a)))
    poly(f, pts, "9")
    for sx, sy in ((6, 2), (2, 5), (9, 5)):
        px(f, sx, sy, "a")
    stamp(f, 4, 5, ["p.p", "...", ".p."])
    out.append(("starfish", 12, 12, 0, [outline(f)]))

    f = grid(16, 16)
    ellipse(f, 8, 9.5, 7.0, 5.6, "l")
    yy, xx = mgrid(f)
    shade(f, "l", "m", yy >= 12)
    shade(f, "l", "k", (yy <= 6) & (xx <= 8))
    rect(f, 3, 5, 5, 5, "c")
    stamp(f, 5, 8, EYE_S)
    stamp(f, 9, 8, EYE_S)
    stamp(f, 6, 11, ["p..p", ".pp."])
    px(f, 4, 11, "t")
    px(f, 11, 11, "t")
    out.append(("rock_smile", 16, 16, 0, [outline(f)]))

    minis = {
        "mini_bubble": [".kk.....", "kjik....", "kiik....", ".kk.....", "....kk..", "...kjik.", "...kiik.", "....kk.."],
        "mini_shell": ["..uuuu..", ".utututu"[:8], "utututu."[:8], "uuuuuuu.", ".uuuuu..", "..uuu...", "..uuu...", "........"],
        "mini_rock_smile": ["..kll...", ".kllll..", "llpllpl.", "llllll l".replace(" ", "l"), "lpllplm.", "mlppllm.".replace("pp", "pp"), ".mmmmm..", "........"],
        "mini_starfish": ["...9....", "...9....", "9999999.", ".99999..", "..999...", ".99.99..", ".9...9..", "........"],
    }
    for name, rows in minis.items():
        f = grid(8, 8)
        stamp(f, 0, 0, [r[:8].ljust(8, ".") for r in rows])
        out.append((name, 8, 8, 0, [f]))
    return out


# ---------------------------------------------------------------- reef tiles and props

def gen_tiles():
    rnd = random.Random(3)
    out = []
    rock = grid(16, 16)
    rect(rock, 0, 0, 15, 15, "m")
    for _ in range(26):
        px(rock, rnd.randrange(16), rnd.randrange(16), "n")
    for _ in range(10):
        x, y = rnd.randrange(15), rnd.randrange(15)
        stamp(rock, x, y, ["ln", "nn"])
    line(rock, [(3, 10), (6, 12), (9, 11)], "n")
    out.append(("rock", 16, 16, 0, [rock]))
    top = rock.copy()
    rect(top, 0, 0, 15, 1, "l")
    rect(top, 0, 2, 15, 2, "m")
    for x in range(0, 16, 3):
        px(top, x + 1, 0, "k")
    for x in (2, 3, 9, 10, 13):
        px(top, x, 0, "c")
        px(top, x, 1, "d")
    out.append(("rock_top", 16, 16, 0, [top]))
    sand = grid(16, 16)
    rect(sand, 0, 0, 15, 15, "3")
    for _ in range(18):
        px(sand, rnd.randrange(16), rnd.randrange(16), rnd.choice("4v"))
    for _ in range(6):
        px(sand, rnd.randrange(16), rnd.randrange(16), "u")
    out.append(("sand", 16, 16, 0, [sand]))
    stop = sand.copy()
    rect(stop, 0, 0, 15, 1, "u")
    for x in range(0, 16, 4):
        px(stop, x, 1, "3")
        px(stop, x + 1, 2, "u")
    out.append(("sand_top", 16, 16, 0, [stop]))

    # coral heads: a pink branching coral and an orange brain coral
    c0 = grid(16, 16)
    rect(c0, 2, 13, 13, 15, "7")
    for bx, top_y in ((4, 4), (7, 2), (10, 5), (13, 7), (2, 8)):
        line(c0, [(bx, 14), (bx, top_y)], "t", 2)
        px(c0, bx, top_y - 1, "u")
    line(c0, [(7, 9), (4, 6)], "t", 2)
    line(c0, [(10, 10), (13, 8)], "t", 2)
    c0 = outline(c0)
    c1 = grid(16, 16)
    ellipse(c1, 8, 11, 7.4, 5.5, "9")
    rect(c1, 1, 11, 14, 15, "9")
    yy, xx = mgrid(c1)
    for y in (8, 11, 14):
        c1[(c1 == C("9")) & (yy == y) & ((xx + y) % 5 != 0)] = C("1")
    shade(c1, "9", "a", (yy <= 7))
    c1 = outline(c1)
    out.append(("coral", 16, 16, 0, [c0, c1]))

    # kelp (2 sway frames), and its top
    for name, top in (("kelp", False), ("kelp_top", True)):
        frames = []
        for k in range(2):
            f = grid(16, 16)
            sway = 1 if k else -1
            line(f, [(7, 16), (7 + sway, 8), (7, 0 if not top else 4)], "d", 2)
            for ly, side in ((12, -1), (6, 1), (2, -1)):
                if top and ly < 4:
                    continue
                cx = 7 + side * 3 + (sway if ly < 8 else 0)
                ellipse(f, cx + 0.5, ly + 0.5, 2.8, 1.5, "c")
            if top:
                ellipse(f, 7.5 + sway, 3, 1.6, 1.6, "b")
            frames.append(outline(f))
        out.append((name, 16, 16, 2, frames))

    # anemone (the clownfish's home)
    frames = []
    for k in range(2):
        f = grid(16, 16)
        for i in range(7):
            x0 = 2.5 + i * 1.8
            x1 = x0 + (1.2 if k else -1.2) * (1 if i % 2 else 0.6)
            line(f, [(x0, 14), (x1, 3 + (i % 3))], "t")
            px(f, int(round(x1)), 2 + (i % 3), "u")
        ellipse(f, 8, 14, 6.5, 2.5, "8")
        frames.append(outline(f))
    out.append(("anemone", 16, 16, 2, frames))

    # sunken ship
    f = grid(96, 48)
    line(f, [(40, 26), (47, 1)], "v", 3)                               # broken mast
    line(f, [(44, 12), (58, 10)], "v", 2)
    rect(f, 60, 11, 86, 26, "1")                                        # cabin
    rect(f, 60, 11, 86, 12, "4")
    rect(f, 74, 15, 82, 26, "p")                                        # the octopus's door
    rect(f, 63, 15, 69, 19, "n")
    poly(f, [(2, 27), (92, 21), (94, 30), (86, 46), (12, 47), (4, 40)], "4")
    yy, xx = mgrid(f)
    shade(f, "4", "5", yy >= 38)
    for py in range(28, 47, 4):
        f[(f == C("4")) & (yy == py)] = C("5")
        f[(f == C("5")) & (yy == py) & (yy >= 38)] = C("6")
    for cx, cy in ((22, 34), (36, 33), (50, 32), (64, 31)):
        ellipse(f, cx, cy, 2.8, 2.8, "l")
        ellipse(f, cx, cy, 1.6, 1.6, "o")
    rect(f, 2, 26, 92, 26, "v")
    for x0, y0 in ((10, 40), (30, 44), (70, 42), (84, 35)):
        stamp(f, x0, y0, [".d.", "dcd", ".d."])
    for x0 in range(8, 90, 11):
        px(f, x0, 30 + (x0 % 3), "k")
    out.append(("wreck", 96, 48, 0, [outline(f)]))

    # pearls for the trail (4-frame shimmer), small bubbles
    frames = []
    for k in range(4):
        f = grid(6, 6)
        ellipse(f, 3, 3, 2.6, 2.6, "k")
        gx, gy = [(2, 1), (3, 1), (3, 2), (2, 2)][k]
        px(f, gx, gy, "j")
        px(f, 4 - (k % 2), 4, "u")
        frames.append(f)
    out.append(("pearl", 6, 6, 8, frames))
    f = grid(4, 4)
    stamp(f, 0, 0, [".ii.", "ij.i", "i..i", ".ii."])
    out.append(("bubble_small", 4, 4, 0, [f]))
    return out


# ---------------------------------------------------------------- ui icons

def gen_ui():
    out = []
    f = grid(8, 8)
    pts = []
    for i in range(10):
        a = -math.pi / 2 + i * math.pi / 5
        r = 3.9 if i % 2 == 0 else 1.7
        pts.append((4 + r * math.cos(a), 4.3 + r * math.sin(a)))
    poly(f, pts, "b")
    px(f, 3, 3, "j")
    out.append(("star", 8, 8, 0, [outline(f)]))

    # seat_driver: the helm wheel
    f = grid(16, 16)
    for i in range(8):
        a = i * math.pi / 4
        line(f, [(8, 8), (8 + math.cos(a) * 7.2, 8 + math.sin(a) * 7.2)], "4", 1)
        ellipse(f, 8 + math.cos(a) * 7.0, 8 + math.sin(a) * 7.0, 1.2, 1.2, "v")
    ring = grid(16, 16)
    ellipse(ring, 8, 8, 5.2, 5.2, "4")
    ellipse(ring, 8, 8, 3.8, 3.8, T)
    f[ring >= 0] = C("4")
    ellipse(f, 8, 8, 1.8, 1.8, "a")
    px(f, 7, 7, "b")
    out.append(("seat_driver", 16, 16, 0, [outline(f)]))

    # seat_gunner: a camera
    f = grid(16, 16)
    rect(f, 1, 5, 14, 13, "n")
    rect(f, 4, 3, 8, 5, "n")
    rect(f, 1, 5, 14, 6, "m")
    ellipse(f, 8, 9.5, 3.6, 3.6, "l")
    ellipse(f, 8, 9.5, 2.4, 2.4, "h")
    px(f, 7, 8, "j")
    rect(f, 11, 3, 13, 4, "q")
    rect(f, 2, 7, 3, 8, "b")
    out.append(("seat_gunner", 16, 16, 0, [outline(f)]))

    # seat_honker: a light bulb
    f = grid(16, 16)
    ellipse(f, 8, 6.5, 5.2, 5.2, "b")
    rect(f, 5, 9, 10, 11, "b")
    yy, xx = mgrid(f)
    shade(f, "b", "a", (xx >= 10) & (yy >= 5))
    px(f, 6, 3, "j")
    px(f, 5, 4, "j")
    rect(f, 5, 12, 10, 14, "l")
    rect(f, 5, 13, 10, 13, "k")
    rect(f, 7, 15, 8, 15, "m")
    stamp(f, 6, 7, [".9.9", "9.9."])   # a glowing zigzag filament
    out.append(("seat_honker", 16, 16, 0, [outline(f)]))

    # icon_album: the photo book
    f = grid(16, 16)
    rect(f, 2, 2, 13, 13, "5")
    rect(f, 3, 3, 13, 12, "u")
    rect(f, 2, 2, 3, 13, "6")
    ellipse(f, 9, 7.5, 3.0, 2.0, "h")
    poly(f, [(6, 7.5), (4.5, 5.5), (4.5, 9.5)], "h")
    px(f, 10, 7, "p")
    out.append(("icon_album", 16, 16, 0, [outline(f)]))
    return out


GENERATORS = [gen_sub, gen_viewfinder, gen_flash, gen_polaroid, gen_album_slot, gen_clownfish,
              gen_blue_tang, gen_pufferfish, gen_seahorse, gen_lantern_fish, gen_turtle, gen_crab,
              gen_octopus, gen_eel, gen_jellyfish, gen_anglerfish, gen_squid, gen_whale, gen_icon_whale,
              gen_bonus, gen_tiles, gen_ui]


def generate():
    for g in GENERATORS:
        yield from g()
