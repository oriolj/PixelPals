"""Space Mission's procedural sprites (Endesga 32), rendered by sprites.py.

Every generator yields (name, w, h, fps, frames); frames are int8 arrays of
palette indices (-1 = transparent). Shapes are geometry (ellipses, polygons,
lines) plus small stamped grids, the same helper kit as Submarine Safari's
art_gen.py. Hardware is cute and toy-like, bright and generic: no agency
logos, no text. Characters and objects get a 1 px ink outline; the big
textures (Earth, stars, Mars layers, the party room) do not. Everything is
seeded, so a re-run gives the same pixels.

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


# ---------------------------------------------------------------- drawing helpers (Submarine Safari's)

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


def over(dst: np.ndarray, src: np.ndarray, x: int = 0, y: int = 0) -> None:
    """Paste the opaque pixels of src onto dst at (x, y)."""
    h, w = src.shape
    H, W = dst.shape
    for yy in range(h):
        for xx in range(w):
            if src[yy, xx] >= 0 and 0 <= y + yy < H and 0 <= x + xx < W:
                dst[y + yy, x + xx] = src[yy, xx]


# ---------------------------------------------------------------- tileable noise

def lattice_sample(lat: np.ndarray, X: np.ndarray, Y: np.ndarray, wrap_y: bool) -> np.ndarray:
    """Smooth value noise from a random lattice; X always wraps, Y wraps if asked."""
    cy, cx = lat.shape
    X = np.mod(X, cx)
    if wrap_y:
        Y = np.mod(Y, cy)
    else:
        Y = np.clip(Y, 0, cy - 1.000001)
    x0 = np.floor(X).astype(int)
    y0 = np.floor(Y).astype(int)
    fx = X - x0
    fy = Y - y0
    fx = fx * fx * (3 - 2 * fx)
    fy = fy * fy * (3 - 2 * fy)
    x1 = (x0 + 1) % cx
    y1 = (y0 + 1) % cy if wrap_y else np.minimum(y0 + 1, cy - 1)
    a = lat[y0, x0] * (1 - fx) + lat[y0, x1] * fx
    b = lat[y1, x0] * (1 - fx) + lat[y1, x1] * fx
    return a * (1 - fy) + b * fy


def fbm(w: int, h: int, cells_x: int, cells_y: int, seed: int, octaves: int = 4,
        wrap_y: bool = False, warp: np.ndarray | None = None, warp_y: np.ndarray | None = None) -> np.ndarray:
    """Fractal value noise over a w x h image, seamless in x (and y with wrap_y).

    cells_x cells span the width at octave 0 and double each octave, so the
    wrap is exact. warp / warp_y are optional pixel offsets (must be periodic
    in x themselves to keep the seam)."""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(float)
    if warp is not None:
        xx = xx + warp
    if warp_y is not None:
        yy = yy + warp_y
    total = np.zeros((h, w))
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        cx, cy = cells_x * 2 ** o, max(1, cells_y * 2 ** o)
        lat = rng.random((cy if wrap_y else cy + 1, cx))
        total += amp * lattice_sample(lat, xx * cx / w, yy * cy / h, wrap_y)
        norm += amp
        amp *= 0.5
    return total / norm


def roll_dilate(m: np.ndarray, wrap_y: bool = False) -> np.ndarray:
    out = m | np.roll(m, 1, axis=1) | np.roll(m, -1, axis=1)
    if wrap_y:
        return out | np.roll(m, 1, axis=0) | np.roll(m, -1, axis=0)
    out[1:, :] |= m[:-1, :]
    out[:-1, :] |= m[1:, :]
    return out


def distance_steps(mask: np.ndarray, steps: int) -> np.ndarray:
    """Distance (in 4-neighbour steps, capped) from every pixel to mask, x wrapping."""
    d = np.full(mask.shape, steps + 1, dtype=int)
    cur = mask.copy()
    d[cur] = 0
    for s in range(1, steps + 1):
        cur = roll_dilate(cur)
        d[cur & (d > s)] = s
    return d


# ================================================================ STAGE 1: Earth orbit

def shuttle_frame(k: int) -> np.ndarray:
    f = grid(48, 20)
    # tail fin at the rear (left)
    poly(f, [(6, 7), (16, 7), (11, 0.5), (7, 0.5)], "k")
    rect(f, 7, 1, 8, 6, "j")
    # fuselage and the rounded nose (right)
    rect(f, 6, 6, 38, 13, "j")
    ellipse(f, 38, 10, 8.6, 4.1, "j")
    # OMS pods: little bumps on the rear top
    ellipse(f, 12, 6.3, 4.5, 1.6, "j")
    yy, xx = mgrid(f)
    shade(f, "j", "k", (yy == 11) & (xx < 44))
    # dark belly and nose tiles
    shade(f, "j", "n", (yy >= 12))
    shade(f, "k", "n", (yy >= 12))
    shade(f, "j", "n", (xx >= 45) & (yy >= 9))
    shade(f, "j", "n", (xx >= 46))
    # cockpit windows at the nose
    stamp(f, 39, 7, ["o.oo", ".ooo"])
    px(f, 40, 8, "h")
    px(f, 42, 7, "h")
    # the open cargo bay: a dark slot along the top
    rect(f, 17, 6, 34, 7, "o")
    rect(f, 17, 7, 34, 7, "n")
    for x in (23, 29):
        px(f, x, 6, "m")
    # the robot arm's shoulder joint at (20, 4)
    rect(f, 19, 3, 21, 5, "l")
    px(f, 20, 4, "k")
    rect(f, 19, 5, 21, 5, "m")
    # delta wing under the fuselage
    poly(f, [(14, 12), (35, 12), (27, 16), (12, 16)], "k")
    shade(f, "k", "l", (yy >= 15) & (xx < 34))
    line(f, [(35, 12), (27, 16)], "n")
    # three main engines at the back
    for y in (7, 9, 11):
        rect(f, 3, y, 5, y + 1, "m")
        px(f, 3, y, "l")
    out = outline(f)
    # engine glow (no outline): flickers between two lengths
    for y in (7, 9, 11):
        if k == 0:
            stamp(out, 0, y, [".9aa", "..9a"])
        else:
            stamp(out, 0, y, ["99ab", "9aab"])
    return out


def gen_shuttle():
    yield ("shuttle", 48, 20, 8, [shuttle_frame(0), shuttle_frame(1)])


def iss_core_frame(lit: bool) -> np.ndarray:
    f = grid(32, 16)
    # the truss above: a lattice beam across the whole width
    rect(f, 1, 1, 30, 4, "l")
    rect(f, 2, 2, 29, 3, "m")
    for x in range(2, 30, 3):
        px(f, x, 2, "k")
        px(f, x + 1, 3, "k")
    # the post down to the module
    rect(f, 14, 5, 17, 5, "l")
    # the cylinder: white body, end caps, ring bands
    rect(f, 6, 6, 25, 12, "j")
    ellipse(f, 6, 9.5, 2.6, 3.6, "k")
    ellipse(f, 25.5, 9.5, 2.6, 3.6, "k")
    rect(f, 6, 6, 25, 12, "j")
    yy, xx = mgrid(f)
    shade(f, "j", "k", yy >= 11)
    shade(f, "k", "l", yy >= 12)
    for x in (10, 16, 21):
        rect(f, x, 6, x, 12, "k")
    # docking ports at the ends
    rect(f, 1, 8, 3, 10, "l")
    rect(f, 28, 8, 30, 10, "l")
    # windows
    for x in (8, 13, 18, 23):
        px(f, x, 8, "h")
    # the lights: dim when off, bright colours when on
    lights = [(3, 1, "q"), (9, 4, "a"), (15, 1, "c"), (22, 4, "h"), (28, 1, "a"),
              (12, 10, "q"), (19, 10, "c"), (2, 9, "a"), (29, 9, "i")]
    for x, y, col in lights:
        px(f, x, y, col if lit else "n")
    return outline(f)


def module_lab(blink: bool) -> np.ndarray:
    """A horizontal lab cylinder with windows, blue band. Fits rows 4..12."""
    f = grid(16, 16)
    rect(f, 2, 5, 13, 11, "j")
    ellipse(f, 2, 8.5, 1.8, 3.6, "k")
    ellipse(f, 14, 8.5, 1.8, 3.6, "k")
    rect(f, 2, 5, 13, 11, "j")
    yy, xx = mgrid(f)
    shade(f, "j", "k", yy >= 10)
    rect(f, 2, 5, 13, 5, "h")
    rect(f, 2, 11, 13, 11, "g")
    for x in (4, 7, 10):
        rect(f, x, 7, x + 1, 8, "i" if blink else "o")
        px(f, x, 7, "j" if blink else "h")
    return f


def module_habitat(blink: bool) -> np.ndarray:
    """A round inflatable pod with quilted seams, an orange ring."""
    f = grid(16, 16)
    ellipse(f, 8, 8.5, 6.4, 5.4, "j")
    yy, xx = mgrid(f)
    shade(f, "j", "k", (yy >= 11) | (xx >= 12))
    for x in (5, 11):
        shade(f, "j", "k", (xx == x))
    rect(f, 2, 8, 13, 8, "9")
    shade(f, "9", "1", (xx >= 11))
    # a docking collar on the left, a round window on top
    rect(f, 0, 7, 1, 9, "l")
    stamp(f, 7, 5, ["hh", "ho"])
    px(f, 8, 12, "a" if blink else "3")
    px(f, 12, 6, "b" if blink else "k")
    return f


def module_robot(blink: bool) -> np.ndarray:
    """A small box module with a mini robot arm and claw on top, green accent."""
    f = grid(16, 16)
    rect(f, 2, 7, 13, 12, "k")
    rect(f, 2, 7, 13, 7, "j")
    rect(f, 2, 12, 13, 12, "l")
    rect(f, 2, 9, 13, 10, "c")
    rect(f, 2, 10, 13, 10, "d")
    # the mini arm: a shoulder, a bent elbow, a little claw
    rect(f, 4, 5, 5, 6, "l")
    line(f, [(5, 5), (8, 3)], "j")
    line(f, [(8, 3), (11, 4)], "j")
    stamp(f, 11, 3, ["c.", "cc", "c."])
    px(f, 12, 3, "c")
    px(f, 12, 5, "c")
    px(f, 8, 3, "m")
    px(f, 11, 11, "c" if blink else "e")
    px(f, 13, 8, "b" if blink else "m")
    return f


def solar_frame(stage: int) -> np.ndarray:
    """stage 0 folded .. 3 fully open."""
    f = grid(32, 16)
    reach = [0, 5, 10, 14][stage]
    # the mast
    rect(f, 15, 1, 16, 14, "l")
    rect(f, 15, 1, 15, 14, "k")
    if stage == 0:
        # a folded stack in the middle
        rect(f, 12, 4, 19, 11, "g")
        for y in range(4, 12, 2):
            rect(f, 12, y, 19, y, "h")
        rect(f, 14, 3, 17, 3, "a")
        rect(f, 14, 12, 17, 12, "a")
    else:
        for side in (-1, 1):
            if side < 0:
                x0, x1 = 15 - reach, 14
            else:
                x0, x1 = 17, 16 + reach
            rect(f, x0, 4, x1, 11, "h")
            # the cell grid
            for x in range(x0, x1 + 1):
                if (x - x0) % 3 == 2:
                    rect(f, x, 4, x, 11, "g")
            for y in (6, 9):
                rect(f, x0, y, x1, y, "g")
            rect(f, x0, 4, x1, 4, "i")
            # gold frame at the far end
            xe = x0 if side < 0 else x1
            rect(f, xe, 4, xe, 11, "a")
            # a folded half-stack still at the mast when half open
            if stage < 3:
                rect(f, 15 - 2 if side < 0 else 17, 3, 14 if side < 0 else 18, 12, "a")
        px(f, 15, 1, "a")
        px(f, 16, 1, "a")
    return outline(f)


def pin_on(f: np.ndarray, x: int = 7, top: int = 1) -> None:
    """The grapple pin: a white knob on a short post."""
    rect(f, x, top, x + 1, top + 1, "j")
    rect(f, x, top + 2, x + 1, top + 3, "l")


def cargo_frames(body: np.ndarray, pin_x: int, pin_top: int) -> list[np.ndarray]:
    f = body.copy()
    pin_on(f, pin_x, pin_top)
    f0 = outline(f)
    return [f0, shift(f0, 0, 1)]


def folded_solar_small() -> np.ndarray:
    f = grid(16, 16)
    rect(f, 4, 5, 11, 12, "g")
    for y in range(5, 13, 2):
        rect(f, 4, y, 11, y, "h")
    rect(f, 7, 4, 8, 13, "l")
    rect(f, 5, 4, 10, 4, "a")
    rect(f, 5, 13, 10, 13, "a")
    return f


def gen_station():
    yield ("iss_core", 32, 16, 4, [iss_core_frame(False), iss_core_frame(True)])
    yield ("iss_lab", 16, 16, 2, [outline(module_lab(False)), outline(module_lab(True))])
    yield ("iss_habitat", 16, 16, 2, [outline(module_habitat(False)), outline(module_habitat(True))])
    yield ("iss_robot", 16, 16, 2, [outline(module_robot(False)), outline(module_robot(True))])
    yield ("iss_solar", 32, 16, 6, [solar_frame(i) for i in range(4)])
    yield ("cargo_lab", 16, 16, 2, cargo_frames(module_lab(False), 7, 1))
    yield ("cargo_solar", 16, 16, 2, cargo_frames(folded_solar_small(), 7, 0))
    yield ("cargo_habitat", 16, 16, 2, cargo_frames(module_habitat(False), 7, 0))
    yield ("cargo_robot", 16, 16, 2, cargo_frames(module_robot(False), 2, 2))

    # iss_port: a dashed white square with corner brackets (tinted in code: j and k only)
    frames = []
    for bright in (False, True):
        f = grid(16, 16)
        dash = "j" if bright else "k"
        for i in range(1, 15):
            if i % 3 != 0:
                for (x, y) in ((i, 1), (i, 14), (1, i), (14, i)):
                    px(f, x, y, dash)
        L = 4
        for (x, y, sx, sy) in ((0, 0, 1, 1), (15, 0, -1, 1), (0, 15, 1, -1), (15, 15, -1, -1)):
            for i in range(L):
                px(f, x + sx * i, y, "j")
                px(f, x, y + sy * i, "j")
                if bright:
                    px(f, x + sx * i, y + sy, "j")
                    px(f, x + sx, y + sy * i, "j")
        frames.append(f)
    yield ("iss_port", 16, 16, 3, frames)

    # dock_ring: a round docking ring side-on with a yellow target mark
    frames = []
    for glow in (False, True):
        f = grid(16, 16)
        ellipse(f, 8, 8, 5.4, 7.4, "l" if not glow else "k")
        ellipse(f, 8, 8, 3.6, 5.6, "m" if not glow else "b")
        ellipse(f, 8, 8, 2.6, 4.6, "n" if not glow else "a")
        yy, xx = mgrid(f)
        if not glow:
            shade(f, "l", "k", (xx <= 5) & (yy <= 7))
        # the target cross
        rect(f, 7, 5, 8, 10, "a" if not glow else "j")
        rect(f, 6, 7, 9, 8, "a" if not glow else "j")
        px(f, 7, 7, "b")
        frames.append(outline(f))
    yield ("dock_ring", 16, 16, 3, frames)


def gen_arm():
    f = grid(24, 4)
    rect(f, 0, 0, 23, 0, INK)
    rect(f, 0, 3, 23, 3, INK)
    rect(f, 0, 1, 23, 1, "j")
    rect(f, 0, 2, 23, 2, "k")
    for x in (0, 8, 16):
        rect(f, x, 1, x + 1, 2, "l")
        px(f, x, 1, "m")
    yield ("arm_segment", 24, 4, 0, [f])

    frames = []
    for closed in (False, True):
        f = grid(8, 8)
        rect(f, 1, 2, 2, 5, "l")
        px(f, 1, 2, "k")
        if not closed:
            line(f, [(3, 3), (5, 1), (6, 1)], "k")
            line(f, [(3, 4), (5, 6), (6, 6)], "k")
            px(f, 6, 1, "a")
            px(f, 6, 6, "a")
        else:
            line(f, [(3, 2), (6, 2)], "k")
            line(f, [(3, 5), (6, 5)], "k")
            px(f, 6, 3, "a")
            px(f, 6, 4, "a")
        frames.append(outline(f))
    yield ("arm_hand", 8, 8, 0, frames)

    frames = []
    for ph in (0, 1):
        f = grid(8, 8)
        rect(f, 1, 3, 2, 4, "m")
        poly(f, [(3, 1.5), (3, 6.5), (7, 4)], "l")
        yy, xx = mgrid(f)
        f[(f == C("l")) & (((xx + yy + ph) % 3) == 0)] = C("k")
        frames.append(outline(f))
    yield ("drill", 8, 8, 10, frames)


# ---------------------------------------------------------------- Earth textures

EW, EH = 768, 96


def earth_fields():
    """Land mask, elevation, biome noise, the polar-ice mask; all seamless in x."""
    xs = np.arange(EW)
    # a gentle, periodic domain warp so coasts curl a little
    warp = np.tile(9 * np.sin(xs * 2 * math.pi * 5 / EW)[None, :], (EH, 1)) \
        + 6 * np.sin(np.arange(EH)[:, None] * 0.13 + xs[None, :] * 2 * math.pi * 3 / EW)
    elev = fbm(EW, EH, 8, 2, seed=11, octaves=5, warp=warp)
    thr = np.quantile(elev, 0.65)
    land = elev > thr
    biome = fbm(EW, EH, 12, 3, seed=23, octaves=3)
    rnd = np.random.default_rng(5)
    ragged = fbm(EW, 1, 48, 1, seed=31, octaves=3)[0]
    ice_rows = 4 + (ragged - ragged.min()) / (ragged.max() - ragged.min()) * 5 + rnd.random(EW) * 0.8
    yy = np.arange(EH)[:, None]
    ice = yy < ice_rows[None, :]
    ice_edge = (yy >= ice_rows[None, :] - 1.4) & ice
    return land, elev, thr, biome, ice, ice_edge


def gen_earth():
    land, elev, thr, biome, ice, ice_edge = earth_fields()
    ocean = ~land
    to_land = distance_steps(land, 8)          # for ocean pixels: how far from the coast
    to_sea = distance_steps(ocean, 4)          # for land pixels: how far inland
    # day
    f = np.full((EH, EW), C("h"), dtype=np.int8)
    f[ocean & (to_land >= 7)] = C("g")
    f[ocean & (to_land == 1)] = C("i")
    hi = elev - thr
    f[land] = C("c")
    f[land & (to_sea >= 3)] = C("d")
    f[land & (biome < 0.42) & (to_sea >= 2)] = C("e")
    desert = land & (biome > 0.6)
    f[desert] = C("a")
    f[desert & (to_sea >= 3) & (biome > 0.66)] = C("3")
    f[land & (hi > np.quantile(hi[land], 0.93))] = C("4")
    f[land & (hi > np.quantile(hi[land], 0.985))] = C("2")
    f[ice] = C("j")
    f[ice_edge] = C("k")
    yield ("earth", EW, EH, 0, [f])

    # night: the same continents, dark ocean, city lights
    n = np.full((EH, EW), C("p"), dtype=np.int8)
    n[ocean & (to_land <= 3)] = C("o")
    n[land] = C("n")
    n[land & ((biome < 0.42) | (hi > np.quantile(hi[land], 0.93)))] = C("f")
    n[ice] = C("m")
    n[ice_edge] = C("n")
    rnd = random.Random(77)
    ys, xs = np.nonzero(land & ~ice)
    target = int(0.01 * len(ys))
    placed = 0
    tries = 0
    while placed < target and tries < 200000:
        tries += 1
        i = rnd.randrange(len(ys))
        y, x = int(ys[i]), int(xs[i])
        near_coast = to_sea[y, x] <= 2
        if not near_coast and rnd.random() > 0.3:
            continue
        col = C("b") if rnd.random() < 0.6 else C("a")
        n[y, x] = col
        placed += 1
        size = rnd.choice([1, 1, 1, 2, 3])
        for _ in range(size - 1):
            dx, dy = rnd.choice([(1, 0), (-1, 0), (0, 1), (0, -1)])
            yy2, xx2 = y + dy, (x + dx) % EW
            if 0 <= yy2 < EH and land[yy2, xx2]:
                n[yy2, xx2] = C("a") if col == C("b") else C("b")
                placed += 1
    yield ("earth_night", EW, EH, 0, [n])

    # clouds: swirly bands and puffs, ~18% coverage, seamless
    xs = np.arange(EW)
    yy = np.arange(EH)[:, None]
    warp = 18 * np.sin(xs[None, :] * 2 * math.pi * 4 / EW + yy * 0.09) \
        + 10 * np.sin(xs[None, :] * 2 * math.pi * 9 / EW - yy * 0.21)
    warp_y = 5 * np.sin(xs[None, :] * 2 * math.pi * 6 / EW + yy * 0.05)
    bands = fbm(EW, EH, 16, 6, seed=41, octaves=4, warp=warp, warp_y=warp_y)
    bands += 0.10 * np.sin(yy * 2 * math.pi / 24 + np.sin(xs[None, :] * 2 * math.pi * 3 / EW) * 2)
    thr_c = np.quantile(bands, 0.82)
    cloud = bands > thr_c
    c = np.full((EH, EW), T, dtype=np.int8)
    c[cloud] = C("j")
    # shading on the viewer side (bottom edge) and the thin fringes
    below_clear = np.zeros_like(cloud)
    below_clear[:-1, :] = ~cloud[1:, :]
    c[cloud & below_clear] = C("k")
    c[cloud & (bands < thr_c + 0.012)] = C("k")
    yield ("earth_clouds", EW, EH, 0, [c])


def gen_sky():
    # far stars: ~120 single pixels, dim colours
    rnd = random.Random(101)
    f = grid(320, 180)
    for _ in range(120):
        x, y = rnd.randrange(320), rnd.randrange(180)
        f[y, x] = C(rnd.choice("lmmnn"))
    yield ("stars_far", 320, 180, 0, [f])
    # near stars: ~40, some 2x2 or plus shaped, a couple tinted
    rnd = random.Random(202)
    f = grid(320, 180)
    for i in range(40):
        x, y = rnd.randrange(320), rnd.randrange(180)
        col = "a" if i in (3, 17) else "i" if i in (9, 28) else rnd.choice("kkjj")
        kind = rnd.random()
        pts = [(0, 0)]
        if kind < 0.18:
            pts = [(0, 0), (1, 0), (0, 1), (1, 1)]
        elif kind < 0.35:
            pts = [(0, 0), (1, 0), (-1, 0), (0, 1), (0, -1)]
        for dx, dy in pts:
            c = col
            if len(pts) == 5 and (dx or dy):
                c = "k" if col == "j" else "l"
            f[(y + dy) % 180, (x + dx) % 320] = C(c)
    yield ("stars_near", 320, 180, 0, [f])

    # aurora: a smooth curtain of light waving; bright green hem, soft rays fading up
    frames = []
    for k in range(4):
        f = grid(48, 16)
        ph = k * math.pi / 2
        for x in range(48):
            fade = math.sin(math.pi * (x + 0.5) / 48)
            hem = int(round(11.5 + 1.8 * math.sin(x * 0.22 + ph) + 0.6 * math.sin(x * 0.53 - ph)))
            height = 3 + 7 * fade * (0.75 + 0.25 * math.sin(x * 0.31 - ph * 1.5))
            glow = math.sin(x * 0.4 + ph) > 0.55          # the brighter folds
            for y in range(0, min(16, hem + 1)):
                t = (hem - y) / height                    # 0 at the hem, 1 at the ray tip
                if t > 1.0:
                    continue
                if y == hem:
                    col = "i" if glow else "c"
                elif t < 0.35:
                    col = "i" if glow and t < 0.2 else "c"
                elif t < 0.7:
                    col = "c" if glow else "d"
                else:
                    if (x + y) % 2:
                        continue
                    col = "d" if glow else "e"
                if fade < 0.3 and (x + y) % 2:
                    continue
                f[y, x] = C(col)
        frames.append(f)
    yield ("aurora", 48, 16, 4, frames)

    # hurricane: a white spiral swirl with an eye, rotating 90 degrees a frame
    f = grid(16, 16)
    yy, xx = mgrid(f)
    dx, dy = xx + 0.5 - 8, yy + 0.5 - 8
    r = np.sqrt(dx ** 2 + dy ** 2)
    a = np.arctan2(dy, dx)
    arm = np.mod(a * 2 / (2 * math.pi) + np.log(r + 0.5) * 1.3, 1.0)
    body = (r < 7.6) & ((arm < 0.55) | (r < 3.4))
    f[body] = C("k")
    f[body & (arm < 0.3)] = C("j")
    f[body & (r < 3.4)] = C("j")
    f[r < 1.4] = C("h")
    f[(r >= 1.4) & (r < 2.0)] = C("k")
    # drop stray specks at the rim (pixels with fewer than two neighbours)
    filled = f >= 0
    nb = np.zeros(f.shape, dtype=int)
    for dy, dx in ((0, 1), (0, -1), (1, 0), (-1, 0)):
        nb += np.roll(np.roll(filled, dy, axis=0), dx, axis=1)
    f[filled & (nb < 2)] = T
    frames = [np.rot90(f, -k).copy() for k in range(4)]
    yield ("hurricane", 16, 16, 4, frames)

    # sunrise_line: a golden gleam whose bright spot travels
    frames = []
    for k in range(4):
        f = grid(320, 4)
        cx = 40 + 80 * k
        for x in range(320):
            edge = min(x, 319 - x)
            if edge < 12 and (x % (13 - edge if edge < 12 else 1)) != 0 and edge < 6:
                continue
            f[1, x] = C("a")
            f[2, x] = C("a") if edge >= 6 else T
            d = abs(x - cx)
            if d < 30:
                f[1, x] = C("b")
            if d < 16:
                f[2, x] = C("b")
                if d % 3 == 0:
                    f[0, x] = C("b")
            if d < 7:
                f[1, x] = C("j")
                f[2, x] = C("j")
                f[3, x] = C("b") if d < 4 else T
            if d < 3:
                f[0, x] = C("j")
        frames.append(f)
    yield ("sunrise_line", 320, 4, 6, frames)


# ================================================================ STAGE 2: Mars landing

def gen_landing():
    frames = []
    for k in range(2):
        f = grid(32, 32)
        # the white back shell: a wide cone
        poly(f, [(12, 5), (19, 5), (28, 20), (3, 20)], "j")
        yy, xx = mgrid(f)
        shade(f, "j", "k", xx + (yy - 5) * 0.2 >= 20)
        rect(f, 12, 4, 19, 5, "l")
        rect(f, 13, 3, 18, 3, "k")
        # a band and a little window/porthole-ish sensor
        rect(f, 6, 15, 25, 15, "l")
        stamp(f, 14, 9, [".hh.", "hiih", ".hh."])
        # heat shield: a wide shallow dome underneath
        f2 = grid(32, 32)
        ellipse(f2, 16, 20, 14.5, 6.2, "4")
        f2[:21, :] = T
        f[f2 >= 0] = f2[f2 >= 0]
        rect(f, 2, 20, 29, 20, "5")
        shade(f, "4", "5", yy >= 24)
        out = outline(f)
        # the glowing hot rim under the shield (no outline), flickering
        ys = np.arange(32)
        for x in range(2, 30):
            col = [y for y in range(21, 32) if f[y, x] >= 0]
            if not col:
                continue
            yb = max(col) + 2
            hot = "a" if (x + k) % 3 == 0 else "9"
            if 0 <= yb < 32:
                out[yb, x] = C(hot)
            if 0 <= yb + 1 < 32 and (x + k) % 2 == 0:
                out[yb + 1, x] = C("8" if (x + k) % 4 == 0 else "0")
            if 0 <= yb + 2 < 32 and (x * 5 + k * 3) % 7 == 0:
                out[yb + 2, x] = C("9")
        frames.append(out)
    yield ("lander_shell", 32, 32, 8, frames)

    # parachute: orange and white striped canopy, lines to a point
    frames = []
    for k in range(2):
        f = grid(48, 32)
        rx, ry, cy = (21.5, 11.0, 13) if k == 0 else (22.5, 12.0, 13)
        ellipse(f, 24, cy, rx, ry, "j")
        f[cy:, :] = T
        yy, xx = mgrid(f)
        ang = np.degrees(np.arctan2(cy - (yy + 0.5), xx + 0.5 - 24))
        stripe = (np.floor(ang / 22.5).astype(int) % 2) == 0
        f[(f >= 0) & stripe] = C("9")
        # scalloped hem: small bumps under the rim
        for i in range(8):
            x0 = 24 - rx + (2 * rx) * (i + 0.5) / 8
            ellipse(f, x0, cy, 2.6, 1.6 + 0.4 * k, "9" if i % 2 else "j")
        # a vent hole at the top
        px(f, 23, cy - int(ry) + 1, "k")
        px(f, 24, cy - int(ry) + 1, "k")
        shade(f, "j", "k", yy >= cy - 1)
        shade(f, "9", "1", yy >= cy - 1)
        f = outline(f)
        # suspension lines converging at the bottom centre
        for i in range(5):
            x0 = 24 - rx + 1 + (2 * rx - 2) * i / 4
            line(f, [(x0, cy + 2), (24, 30)], "l")
        rect(f, 23, 29, 24, 31, "m")
        frames.append(f)
    yield ("parachute", 48, 32, 3, frames)

    # sky crane: a gold-foil rocket platform with four down thrusters
    frames = []
    for k in range(2):
        f = grid(32, 16)
        rect(f, 8, 3, 23, 8, "a")
        rect(f, 8, 3, 23, 3, "b")
        yy, xx = mgrid(f)
        shade(f, "a", "9", (yy >= 7))
        # grey tanks and deck
        ellipse(f, 12, 4, 2.6, 1.8, "k")
        ellipse(f, 19, 4, 2.6, 1.8, "k")
        rect(f, 14, 1, 17, 2, "l")
        # arms out to the thrusters
        rect(f, 2, 6, 29, 7, "l")
        rect(f, 2, 6, 29, 6, "k")
        for x in (3, 10, 20, 27):
            rect(f, x, 8, x + 1, 9, "m")
            px(f, x, 8, "l")
        rect(f, 15, 9, 16, 9, "m")          # the cable winch
        out = outline(f)
        for i, x in enumerate((3, 10, 20, 27)):
            long = (i + k) % 2 == 0
            stamp(out, x, 10, ["ab", "99", "9." if long else "..", ".9" if long else ".."])
            if not long:
                out[12, x] = C("9")
        frames.append(out)
    yield ("sky_crane", 32, 16, 8, frames)

    f = grid(1, 8)
    for y, col in enumerate("jjjljjjl"):
        f[y, 0] = C(col)
    yield ("cable", 1, 8, 0, [f])

    # the four landing sites
    def patch_base(base="1"):
        f = grid(32, 16)
        ellipse(f, 16, 8, 15.4, 7.4, base)
        return f

    rnd = random.Random(9)
    f = patch_base("3")
    yy, xx = mgrid(f)
    for i in range(4):
        ridge = 3 + i * 3.4 + 1.2 * np.sin(xx * 0.45 + i)
        inside = f >= 0
        f[inside & (np.abs(yy - ridge) < 0.6)] = C("9")
        f[inside & (np.abs(yy - ridge - 1) < 0.6)] = C("4")
    f[(f == C("3")) & (yy >= 12)] = C("1")
    yield ("site_dunes", 32, 16, 0, [outline(f)])

    f = patch_base("1")
    ellipse(f, 16, 8, 8.6, 4.8, "3")
    ellipse(f, 16, 8.6, 7.4, 3.9, "4")
    ellipse(f, 16.8, 9.2, 5.8, 2.8, "5")
    ellipse(f, 15, 8, 5.4, 2.4, "4")
    ellipse(f, 15, 7.6, 1.2, 0.8, "3")
    for (x, y) in ((4, 6), (27, 10), (6, 11), (26, 5)):
        px(f, x, y, "4")
    yield ("site_crater", 32, 16, 0, [outline(f)])

    f = patch_base("0")
    yy, xx = mgrid(f)
    shade(f, "0", "1", (yy <= 4))
    for (cx, cy, rx, ry) in ((10, 7, 5, 2.6), (21, 9, 6, 3.0), (16, 4, 3, 1.4), (25, 5, 2.4, 1.2)):
        ellipse(f, cx, cy, rx, ry, "j")
        ellipse(f, cx + 0.8, cy + 0.7, rx - 1.2, ry - 0.8, "i")
        ellipse(f, cx + 0.5, cy + 0.4, rx - 1.8, max(0.6, ry - 1.4), "j")
    shade(f, "j", "k", (yy >= 11))
    yield ("site_ice", 32, 16, 0, [outline(f)])

    f = patch_base("1")
    yy, xx = mgrid(f)
    shade(f, "1", "3", (yy <= 3))
    rnd = random.Random(14)
    pebbles = [(8, 6, 2.6, 1.8), (15, 10, 3.2, 2.2), (22, 5, 2.2, 1.6), (25, 10, 2.0, 1.4),
               (11, 11, 1.4, 1.0), (19, 4, 1.2, 0.9), (5, 9, 1.2, 0.9)]
    for (cx, cy, rx, ry) in pebbles:
        ellipse(f, cx, cy, rx, ry, "l")
        ellipse(f, cx - 0.4, cy - 0.5, max(0.6, rx - 1.0), max(0.5, ry - 0.8), "k")
        px(f, int(cx + rx - 1), int(cy + ry - 0.5), "m")
    yield ("site_rocks", 32, 16, 0, [outline(f)])


# ================================================================ STAGE 3: Mars surface

def rover_frame(k: int) -> np.ndarray:
    f = grid(40, 24)
    # suspension legs from the body down to the wheel centres (7, 20), (20, 20), (33, 20)
    line(f, [(10, 15), (7, 20)], "m", 2)
    line(f, [(15, 15), (20, 20)], "m", 2)
    line(f, [(25, 15), (20, 20)], "m", 2)
    line(f, [(30, 15), (33, 20)], "m", 2)
    # chassis and body
    rect(f, 5, 14, 34, 16, "l")
    rect(f, 5, 16, 34, 16, "m")
    rect(f, 6, 9, 33, 14, "j")
    rect(f, 6, 13, 33, 14, "k")
    rect(f, 6, 9, 33, 9, "j")
    # a stripe and little portholes/vents
    rect(f, 6, 11, 33, 11, "h")
    for x in (9, 13, 17):
        px(f, x, 13, "l")
    # back tray (left)
    rect(f, 1, 8, 6, 10, "l")
    rect(f, 2, 8, 5, 9, "m")
    # gold instrument box on the deck
    rect(f, 11, 6, 17, 8, "a")
    rect(f, 11, 6, 17, 6, "b")
    px(f, 16, 7, "9")
    # antenna with a ball
    rect(f, 21, 4, 21, 8, "l")
    ellipse(f, 21.5, 3.5, 1.3, 1.3, "q")
    px(f, 21, 3, "t")
    # the mast and the camera head (front, right)
    rect(f, 29, 4, 30, 8, "l")
    if k == 0:
        rect(f, 26, 0, 35, 4, "k")
        rect(f, 26, 0, 35, 0, "j")
        stamp(f, 33, 1, ["op", "hp"])          # looking right
        stamp(f, 30, 1, ["op", "hp"])
        px(f, 33, 1, "j")
        px(f, 30, 1, "j")
    else:
        rect(f, 27, 0, 33, 4, "k")
        rect(f, 27, 0, 33, 0, "j")
        stamp(f, 28, 1, ["op", "hp"])          # turned to look at the viewer
        stamp(f, 31, 1, ["op", "hp"])
        px(f, 28, 1, "j")
        px(f, 31, 1, "j")
    return outline(f)


def wheel_frame(k: int) -> np.ndarray:
    f = grid(8, 8)
    ellipse(f, 4, 4, 3.6, 3.6, "n")
    ellipse(f, 4, 4, 2.5, 2.5, "l")
    yy, xx = mgrid(f)
    a = math.radians(45 * k)
    dx, dy = xx + 0.5 - 4, yy + 0.5 - 4
    r = np.sqrt(dx ** 2 + dy ** 2)
    across = np.abs(-dx * math.sin(a) + dy * math.cos(a))
    f[(r < 2.6) & (across < 0.62)] = C("m")
    # tread lugs on the tyre turn with the spokes
    ang = np.arctan2(dy, dx)
    lug = np.mod((ang - a) / (math.pi / 3), 1.0) < 0.4
    f[(r >= 2.6) & (f >= 0) & lug] = C("o")
    rect(f, 3, 3, 4, 4, "k")
    px(f, 3, 3, "j")
    return outline(f)


def heli_frame(k: int) -> np.ndarray:
    f = grid(12, 8)
    rect(f, 4, 3, 7, 5, "k")
    rect(f, 4, 3, 7, 3, "j")
    px(f, 6, 4, "a")
    px(f, 5, 5, "a")
    out = outline(f)
    rect(out, 5, 1, 6, 1, "m")
    if k == 0:
        rect(out, 0, 0, 11, 0, "k")
        rect(out, 3, 1, 8, 1, "l")
    else:
        rect(out, 3, 0, 8, 0, "l")
        rect(out, 0, 1, 4, 1, "k")
        rect(out, 7, 1, 11, 1, "k")
    for (x0, x1) in ((4, 2), (7, 9)):
        line(out, [(x0, 6), (x1, 7)], "l")
    px(out, 5, 7, "l")
    px(out, 6, 7, "l")
    return out


def gen_mars():
    yield ("rover", 40, 24, 2, [rover_frame(0), rover_frame(1)])
    yield ("wheel", 8, 8, 10, [wheel_frame(k) for k in range(4)])
    yield ("helicopter", 12, 8, 12, [heli_frame(0), heli_frame(1)])

    # distant mountains
    W = 320
    xs = np.arange(W)
    tau = 2 * math.pi
    prof = 26 + 9 * np.sin(xs * tau * 2 / W + 0.7) + 6 * np.sin(xs * tau * 5 / W + 2.1) \
        + 3 * np.sin(xs * tau * 11 / W + 0.3) + 1.2 * np.sin(xs * tau * 23 / W + 1.1)
    dprof = np.roll(prof, -2) - np.roll(prof, 2)
    prof = np.round(prof).astype(int)
    f = grid(W, 60)
    for x in range(W):
        top = prof[x]
        f[top:, x] = C("5")
        if dprof[x] > 0.25:     # slopes facing the light (left) get a lit face
            depth = int(min(9, 2 + dprof[x] * 1.6))
            f[top:top + depth, x] = C("4")
        f[top, x] = C("v")
    yield ("mars_far", W, 60, 0, [f])

    prof = 20 + 5 * np.sin(xs * tau * 3 / W + 1.0) + 3.5 * np.sin(xs * tau * 7 / W + 0.2) \
        + 1.5 * np.sin(xs * tau * 13 / W + 2.3)
    dprof = np.roll(prof, -2) - np.roll(prof, 2)
    prof = np.round(prof).astype(int)
    f = grid(W, 48)
    for x in range(W):
        top = prof[x]
        f[top:, x] = C("4")
        f[top, x] = C("3")
        f[top + 1, x] = C("1")
        if dprof[x] > 0.2:
            f[top + 1:top + 2 + int(min(4, dprof[x])), x] = C("1")
    # ripple lines along the dunes
    for x in range(W):
        for j, off in enumerate((8, 15, 23)):
            y = prof[x] + off + int(round(1.5 * math.sin(x * tau * (4 + j) / W + j)))
            if 0 <= y < 48:
                f[y, x] = C("0")
    yield ("mars_mid", W, 48, 0, [f])

    # the ground tile
    n = fbm(16, 16, 4, 4, seed=61, octaves=2, wrap_y=True)
    f = np.full((16, 16), C("1"), dtype=np.int8)
    f[n > np.quantile(n, 0.7)] = C("0")
    f[n < np.quantile(n, 0.18)] = C("4")
    for (x, y, col) in ((3, 4, "5"), (11, 2, "3"), (7, 11, "5"), (13, 13, "3"), (1, 14, "5"),
                        (9, 7, "3"), (14, 8, "5")):
        f[y, x] = C(col)
    stamp(f, 5, 6, ["33", "45"])
    yield ("mars_ground", 16, 16, 0, [f])


def with_sparkle(f: np.ndarray) -> np.ndarray:
    g = f.copy()
    stamp(g, 9, 0, [".j.", "jjj", ".j."])
    return g


def rock(base, dark, light, seed) -> np.ndarray:
    f = grid(12, 10)
    ellipse(f, 5.5, 6.3, 4.6, 3.4, base)
    ellipse(f, 8.0, 7.2, 2.2, 2.0, base)
    yy, xx = mgrid(f)
    shade(f, base, dark, (xx + yy * 1.2) >= 12.5)
    shade(f, base, light, (xx + yy) <= 6.5)
    return f


def gen_targets():
    targets = {}
    f = rock("8", "7", "t", 1)
    px(f, 4, 5, "0")
    px(f, 7, 7, "0")
    targets["rock_red"] = f
    f = rock("l", "m", "k", 2)
    px(f, 6, 7, "m")
    targets["rock_grey"] = f
    f = rock("j", "k", "j", 3)
    px(f, 5, 7, "l")
    px(f, 8, 8, "l")
    targets["rock_white"] = f
    # ice: a small cluster of crystals
    f = grid(12, 10)
    poly(f, [(2, 9), (2, 5), (3.5, 3), (5, 5), (5, 9)], "h")
    poly(f, [(4, 9), (4, 3), (6, 0.8), (8, 3), (8, 9)], "i")
    poly(f, [(7, 9), (7, 5.5), (8.5, 4), (10, 5.5), (10, 9)], "h")
    rect(f, 5, 3, 5, 7, "j")
    px(f, 3, 5, "i")
    px(f, 8, 6, "i")
    targets["ice"] = f
    # shell: a pink/cream spiral seashell fossil
    f = grid(12, 10)
    ellipse(f, 5.5, 5.5, 4.4, 4.2, "u")
    yy, xx = mgrid(f)
    dx, dy = xx + 0.5 - 5.5, yy + 0.5 - 5.5
    r = np.sqrt(dx ** 2 + dy ** 2)
    a = np.arctan2(dy, dx)
    shade(f, "u", "2", (xx + yy) <= 5)
    pts = []
    for i in range(60):
        th = i * 0.22
        rr = 0.35 * th
        if rr > 4.0:
            break
        pts.append((5.0 + rr * math.cos(th), 5.0 + rr * math.sin(th)))
    line(f, pts, "t")
    px(f, 5, 5, "s")
    targets["shell"] = f

    for name in ("rock_red", "rock_grey", "rock_white", "ice", "shell"):
        base = outline(targets[name])
        yield (name, 12, 10, 3, [base, with_sparkle(base)])

    fills = {"red": ("8", "7"), "grey": ("l", "m"), "white": ("j", "k"),
             "ice": ("i", "h"), "shell": ("t", "u")}
    for key, (a, b) in fills.items():
        f = grid(6, 8)
        rect(f, 1, 1, 4, 1, "m")
        rect(f, 1, 2, 4, 5, "k")
        rect(f, 2, 6, 3, 6, "k")
        rect(f, 2, 3, 4, 5, a)
        px(f, 2, 6, a)
        px(f, 3, 6, b)
        px(f, 4, 5, b)
        rect(f, 1, 2, 1, 4, "j")
        yield (f"sample_{key}", 6, 8, 0, [outline(f)])


def gen_fx():
    # dust puff: grows, then thins out
    frames = []
    shapes = [
        [(3, 5), (4, 5), (4, 4), (3, 4), (5, 5), (2, 5)],
        [(2, 4), (3, 3), (4, 3), (5, 4), (6, 5), (1, 5), (3, 5), (4, 5), (5, 5), (2, 5), (3, 4), (4, 4)],
        [(1, 3), (2, 2), (4, 2), (5, 2), (6, 3), (7, 5), (0, 5), (2, 4), (5, 4), (3, 3), (1, 6), (6, 6)],
        [(1, 2), (5, 1), (7, 4), (0, 4), (3, 2), (6, 6)],
    ]
    cols = ["3", "2", "3", "4"]
    for k, pts in enumerate(shapes):
        f = grid(8, 8)
        for i, (x, y) in enumerate(pts):
            px(f, x, y, cols[(i + k) % 4])
        frames.append(f)
    yield ("dust_puff", 8, 8, 10, frames)

    rnd = random.Random(33)
    frames = []
    for k in range(4):
        f = grid(8, 8)
        for i in range(7):
            a = rnd.uniform(-math.pi, math.pi)
            r = rnd.uniform(1.0, 3.6)
            x, y = int(round(3.5 + r * math.cos(a))), int(round(3.5 + r * math.sin(a)))
            px(f, x, y, rnd.choice("abbj"))
        px(f, 3, 4, "j")
        px(f, 4, 3, "b")
        frames.append(f)
    yield ("drill_sparks", 8, 8, 12, frames)

    frames = []
    for k, rows in enumerate((
        ["........", "........", "........", "...j....", "........", "........", "........", "........"],
        ["........", "........", "...b....", "..bjb...", "...b....", "........", "........", "........"],
        ["...b....", "...b....", "...j....", "bbjjjbb.", "...j....", "...b....", "...b....", "........"],
        ["........", "...a....", "...b....", ".abjba..", "...b....", "...a....", "........", "........"],
    )):
        f = grid(8, 8)
        stamp(f, 0, 0, rows)
        frames.append(f)
    yield ("sparkle", 8, 8, 12, frames)

    frames = []
    shapes = [["jj..", "jj..", "....", "...."], [".j..", "jjj.", ".j..", "...."],
              ["jjj.", "....", "....", "...."], ["j...", ".j..", "..j.", "...."],
              ["jj..", "....", "....", "...."], [".jj.", ".jj.", "....", "...."]]
    for col, rows in zip("8acht9", shapes):
        f = grid(4, 4)
        stamp(f, 0, 0, [r.replace("j", col) for r in rows])
        frames.append(f)
    yield ("confetti", 4, 4, 10, frames)


# ================================================================ party screen

def gen_party():
    W, H = 320, 180
    f = np.full((H, W), C("2"), dtype=np.int8)
    yy, xx = np.mgrid[0:H, 0:W]
    # wall panels (soft vertical seams), a top trim, a skirting line
    for x in range(0, W, 40):
        f[:104, x] = C("u")
    rect(f, 0, 0, W - 1, 3, "k")
    rect(f, 0, 4, W - 1, 4, "l")
    rect(f, 0, 102, W - 1, 104, "u")
    # floor: light grey tiles
    rect(f, 0, 105, W - 1, H - 1, "k")
    for y in range(105, H, 12):
        rect(f, 0, y, W - 1, y, "l")
    for x in range(0, W, 24):
        rect(f, x, 105, x, H - 1, "l")

    # a planet poster on the left
    rect(f, 16, 24, 63, 79, "l")
    rect(f, 18, 26, 61, 77, "o")
    rnd = random.Random(3)
    for _ in range(14):
        px(f, rnd.randrange(19, 61), rnd.randrange(27, 77), rnd.choice("jkb"))
    poster = grid(W, H)
    ellipse(poster, 40, 52, 11, 11, "9")
    ellipse(poster, 38, 50, 8, 8, "a")
    ellipse(poster, 36, 48, 3, 3, "b")
    f[poster >= 0] = poster[poster >= 0]
    ring = grid(W, H)
    ellipse(ring, 40, 52, 19, 4.2, "k")
    ellipse(ring, 40, 52, 16, 2.6, T)
    hide = (yy < 52) & (np.sqrt((xx + 0.5 - 40) ** 2 + (yy + 0.5 - 52) ** 2) < 11)
    ring[hide] = T
    f[ring >= 0] = ring[ring >= 0]
    ellipse(f, 54, 34, 3, 3, "h")
    px(f, 53, 33, "i")

    # a round wall clock on the right (no numbers, just ticks and hands)
    ellipse(f, 280, 50, 17, 17, "l")
    ellipse(f, 280, 50, 15, 15, "j")
    for i in range(12):
        a = i * math.pi / 6
        px(f, int(round(279.5 + 12.5 * math.cos(a))), int(round(49.5 + 12.5 * math.sin(a))), "m")
    line(f, [(279.5, 49.5), (279.5, 40)], "n", 2)
    line(f, [(279.5, 49.5), (287, 53)], "n", 2)
    ellipse(f, 280, 50, 1.6, 1.6, "8")
    # little wall lamps
    for x in (70, 250):
        rect(f, x - 2, 12, x + 2, 16, "a")
        rect(f, x - 1, 17, x + 1, 17, "b")

    rnd = random.Random(12)

    def console(x0, y0, x1, y1, monitors):
        # desk top, front face, blinking lights, tiny monitors
        rect(f, x0, y0, x1, y0 + 3, "j")
        rect(f, x0, y0 + 4, x1, y1, "l")
        rect(f, x0, y0 + 4, x1, y0 + 4, "k")
        rect(f, x0, y1, x1, y1, "m")
        for x in range(x0 + 3, x1 - 2, 4):
            for y in (y0 + 7, y0 + 10):
                if y < y1 - 1:
                    px(f, x, y, rnd.choice("qcahbij"))
        rect(f, x0, y0 + 5, x0 + 1, y1 - 1, "9")
        rect(f, x1 - 1, y0 + 5, x1, y1 - 1, "9")
        for mx in monitors:
            rect(f, mx, y0 - 10, mx + 13, y0 - 1, "m")
            rect(f, mx + 1, y0 - 9, mx + 12, y0 - 2, "o")
            for i in range(10):
                yv = y0 - 5 + int(round(2 * math.sin(i * 0.9 + mx)))
                px(f, mx + 2 + i, yv, rnd.choice("cih"))
            rect(f, mx + 6, y0, mx + 7, y0, "m")

    # back row: a long desk under the big screen (all above y 128)
    console(20, 114, 299, 126, [30, 60, 245, 272])
    # front row: left and right only, leaving the middle for the crew
    console(0, 150, 95, 179, [10, 40, 70])
    console(225, 150, 319, 179, [232, 262, 292])
    yield ("mission_control", W, H, 0, [f])

    f = grid(160, 90)
    rect(f, 0, 0, 159, 89, INK)
    rect(f, 1, 1, 158, 88, "l")
    rect(f, 1, 1, 158, 1, "k")
    rect(f, 3, 3, 156, 86, "m")
    rect(f, 4, 4, 155, 85, "o")
    px(f, 154, 87, "c")
    px(f, 151, 87, "a")
    yield ("big_screen", 160, 90, 0, [f])

    # the mission patch
    f = grid(48, 48)
    yy, xx = mgrid(f)
    d = np.sqrt((xx + 0.5 - 24) ** 2 + (yy + 0.5 - 24) ** 2)
    f[d <= 23] = C("a")
    f[d <= 21] = C("8")
    f[d <= 18.2] = C("a")
    f[d <= 17.2] = C("o")
    # stitches on the red band
    ang = np.arctan2(yy + 0.5 - 24, xx + 0.5 - 24)
    f[(np.abs(d - 19.6) < 0.5) & (np.mod(ang * 40 / (2 * math.pi), 1.0) < 0.5)] = C("7")
    f[(np.abs(d - 22.1) < 0.45) & (np.mod(ang * 48 / (2 * math.pi), 1.0) < 0.5)] = C("b")
    for (x, y, col) in ((12, 16, "j"), (35, 12, "b"), (37, 18, "j"), (9, 22, "b"), (16, 9, "j")):
        px(f, x, y, col)
    for (x, y) in ((12, 16), (35, 12)):
        px(f, x - 1, y, "k")
        px(f, x + 1, y, "k")
        px(f, x, y - 1, "k")
        px(f, x, y + 1, "k")
    # Mars (left) and Earth (right) at the edges of the sky
    ellipse(f, 11, 29, 3.2, 3.2, "9")
    px(f, 10, 28, "a")
    px(f, 12, 30, "0")
    ellipse(f, 37, 29, 3.4, 3.4, "h")
    px(f, 36, 28, "c")
    px(f, 38, 30, "c")
    px(f, 36, 30, "c")
    # a small white shuttle silhouette along the bottom
    stamp(f, 16, 32, [
        "j...............",
        "jj..............",
        "jjj.............",
        "jjjjjjjjjjjjj...",
        "jjjjjjjjjjjjjjj.",
        "jjjjjjjjjjjjjj..",
        "...jjjjjjj......",
        "....jjjj........",
    ])
    px(f, 28, 35, "o")
    px(f, 29, 35, "o")
    yield ("patch", 48, 48, 0, [outline(f)])

    f = grid(8, 8)
    ellipse(f, 4, 4, 2.3, 2.3, "b")
    px(f, 4, 4, "a")
    px(f, 4, 5, "a")
    px(f, 5, 4, "a")
    for (x, y) in ((4, 0), (3, 0), (0, 3), (0, 4), (7, 3), (7, 4), (3, 7), (4, 7), (1, 1), (6, 1), (1, 6), (6, 6)):
        px(f, x, y, "a")
    yield ("sun_icon", 8, 8, 0, [f])


# ================================================================ icons

def gen_icons():
    # seat_pilot: a tiny shuttle nose-up
    f = grid(16, 16)
    poly(f, [(4, 12), (7, 6), (9, 6), (12, 12)], "k")
    rect(f, 6, 3, 9, 12, "j")
    ellipse(f, 8, 3.5, 2, 2.6, "j")
    rect(f, 6, 11, 9, 12, "n")
    rect(f, 7, 1, 8, 2, "n")
    px(f, 7, 4, "h")
    px(f, 8, 4, "h")
    rect(f, 7, 7, 8, 9, "o")
    rect(f, 7, 13, 8, 13, "m")
    out = outline(f)
    stamp(out, 6, 14, [".aa.", "9ab9"])
    out[15, 7] = C("9")
    out[15, 8] = C("a")
    yield ("seat_pilot", 16, 16, 0, [out])

    # seat_arm: a two-segment robot arm with a claw
    f = grid(16, 16)
    rect(f, 1, 12, 5, 14, "l")
    line(f, [(3, 12), (6, 5)], "j", 2)
    line(f, [(6, 5), (11, 8)], "j", 2)
    ellipse(f, 6.5, 5.5, 1.6, 1.6, "l")
    ellipse(f, 3.5, 11.5, 1.6, 1.6, "l")
    stamp(f, 11, 6, [".cc", "c..", "c..", "c..", ".cc"])
    px(f, 11, 8, "l")
    yield ("seat_arm", 16, 16, 0, [outline(f)])

    # seat_camera
    f = grid(16, 16)
    rect(f, 4, 3, 8, 5, "n")
    rect(f, 1, 5, 14, 12, "m")
    rect(f, 1, 5, 14, 6, "l")
    ellipse(f, 8, 9, 3.6, 3.6, "l")
    ellipse(f, 8, 9, 2.4, 2.4, "h")
    px(f, 7, 8, "j")
    rect(f, 11, 3, 13, 4, "a")
    rect(f, 2, 7, 3, 8, "q")
    yield ("seat_camera", 16, 16, 0, [outline(f)])

    # planet_earth
    f = grid(16, 16)
    ellipse(f, 8, 8, 6.6, 6.6, "h")
    stamp(f, 3, 4, ["..cc....", ".cccc...", "..ccd...", "...cc..c", "......cc", "......cd", ".....cc."])
    stamp(f, 9, 3, ["cc", ".c"])
    stamp(f, 4, 11, ["cc"])
    yy, xx = mgrid(f)
    inside = (xx + 0.5 - 8) ** 2 + (yy + 0.5 - 8) ** 2 <= 6.6 ** 2
    f[~inside] = T
    shade(f, "h", "g", (xx + yy) >= 19)
    shade(f, "c", "d", (xx + yy) >= 19)
    px(f, 5, 4, "j")
    px(f, 4, 5, "j")
    yield ("planet_earth", 16, 16, 0, [outline(f)])

    def mars(f, cx, cy, r):
        ellipse(f, cx, cy, r, r, "1")
        yy, xx = mgrid(f)
        shade(f, "1", "0", (xx + yy) >= cx + cy + r * 0.6)
        return f

    # planet_mars_landing: Mars below, a parachute above
    f = grid(16, 16)
    mars(f, 8, 12.5, 5.5)
    px(f, 6, 10, "4")
    px(f, 10, 12, "4")
    px(f, 5, 9, "3")
    ellipse(f, 8, 4.5, 5, 3.6, "9")
    f[5:, :][f[5:, :] == C("9")] = T
    yy, xx = mgrid(f)
    shade(f, "9", "j", (yy <= 4) & ((xx == 6) | (xx == 7) | (xx == 10) | (xx == 11)))
    out = outline(f)
    line(out, [(4, 5), (8, 8)], "l")
    line(out, [(12, 5), (8, 8)], "l")
    px(out, 8, 8, "k")
    px(out, 8, 7, "l")
    yield ("planet_mars_landing", 16, 16, 0, [out])

    # planet_mars: Mars with a tiny rover on top
    f = grid(16, 16)
    mars(f, 8, 10, 5.6)
    px(f, 6, 9, "4")
    px(f, 10, 11, "4")
    px(f, 5, 7, "3")
    rect(f, 5, 2, 10, 3, "j")
    rect(f, 9, 0, 9, 1, "l")
    px(f, 10, 0, "k")
    rect(f, 6, 2, 7, 2, "a")
    px(f, 5, 4, "n")
    px(f, 7, 4, "n")
    px(f, 10, 4, "n")
    yield ("planet_mars", 16, 16, 0, [outline(f)])


GENERATORS = [gen_shuttle, gen_station, gen_arm, gen_earth, gen_sky, gen_landing, gen_mars,
              gen_targets, gen_fx, gen_party, gen_icons]


def generate():
    for g in GENERATORS:
        yield from g()
