"""The horse engine: one set of body and leg drawings for the mare (40x32, and
80x64 for the stable) and the foal (24x20), posed per animation frame and
recoloured per coat. Used by art_gen.py.

A horse is drawn in *model units* (the 40x32 mare, or the 24x20 foal) into a
canvas of *roles* (body, shade, mane, near/far leg, hoof, muzzle, tack...), at
an integer scale s (1 or 2). A pose moves the body (bob `dy`, rocking `pitch`),
turns the neck and head about the withers, and places each foot by 2-bone IK
(front knees bend forward, hind hocks backward). Shading is a pass over the
roles (a highlight row along the top, a shade row underneath). A coat maps the
roles to Endesga 32 indices; pinto patches and appaloosa spots are overlay
masks in body coordinates, so they move with the horse.

Every leg is exactly w pixels thick (rasterised along its major axis), so the
legs never flicker between widths as they swing.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

import numpy as np
from PIL import Image, ImageDraw

CHARS = "0123456789abcdefghijklmnopqrstuv"
T = -1
INK = 25


def C(ch: str) -> int:
    return CHARS.index(ch)


# roles
E, B, S, L, M, MS, LG, LGF, H, Z, EYE, GLI, FAR, SAD, PAD, PADS, STRAP, MOUTH, NOST, EARIN, BLAZE, LEGU, SADL, HF_ = range(24)
BODYLIKE = (B, S, L, LEGU)

# coat -> role -> palette char
COATS: dict[str, dict[int, str]] = {
    "bay": {B: "4", S: "5", L: "v", M: "6", MS: "p", LG: "6", LGF: "p", H: "n", Z: "5", FAR: "5",
            EARIN: "5", BLAZE: "j", LEGU: "4"},
    "chestnut": {B: "1", S: "0", L: "3", M: "0", MS: "7", LG: "1", LGF: "0", H: "5", Z: "4", FAR: "0",
                 EARIN: "0", BLAZE: "j", LEGU: "1"},
    "palomino": {B: "a", S: "1", L: "b", M: "2", MS: "3", LG: "a", LGF: "1", H: "4", Z: "3", FAR: "1",
                 EARIN: "1", BLAZE: "j", LEGU: "a"},
    "grey": {B: "k", S: "l", L: "j", M: "j", MS: "k", LG: "l", LGF: "m", H: "m", Z: "m", FAR: "l",
             EARIN: "l", BLAZE: "j", LEGU: "k"},
    "black": {B: "o", S: "6", L: "m", M: "p", MS: "n", LG: "o", LGF: "6", H: "m", Z: "n", FAR: "6",
              EARIN: "6", BLAZE: "j", LEGU: "o"},
    "pinto": {B: "j", S: "k", L: "j", M: "5", MS: "6", LG: "j", LGF: "k", H: "u", Z: "u", FAR: "k",
              EARIN: "t", BLAZE: "j", LEGU: "j"},
    "appaloosa": {B: "j", S: "k", L: "j", M: "m", MS: "n", LG: "4", LGF: "5", H: "m", Z: "m", FAR: "5",
                  EARIN: "4", BLAZE: "j", LEGU: "j"},
}
TACK = {EYE: "p", GLI: "j", SAD: "5", SADL: "4", PAD: "h", PADS: "g", STRAP: "5", MOUTH: "7", NOST: "p"}
COATS["appaloosa_swatch"] = dict(COATS["appaloosa"])
MARE_COATS = ["bay", "chestnut", "palomino", "grey", "black", "pinto"]
FOAL_COATS = MARE_COATS + ["appaloosa"]


@dataclass
class Pose:
    dy: float = 0.0            # body bob (model units, + = down)
    pitch: float = 0.0         # + = front up
    neck: float = 0.0          # degrees, + = head down
    legs: dict = field(default_factory=dict)   # "FN","FF","HN","HF" -> (dx, lift)
    mouth: bool = False
    jaw: int = 0               # 1 = jaw dropped (munch)
    ear: int = 0               # 1 = near ear flicked back
    tail: float = 0.0          # 0 hangs, 1 streams out behind
    swish: int = 0             # -1, 0, 1: tail tip sideways
    toss: bool = False         # mane flipped up (neigh)
    breath: int = 0            # 1 = belly one row lower
    eye_closed: bool = False
    lying: bool = False        # foal asleep
    tucked: dict = field(default_factory=dict)  # leg -> True: draw folded against the body


# ---------------------------------------------------------------- canvas

class Canvas:
    def __init__(self, w: int, h: int, s: int):
        self.w, self.h, self.s = w, h, s
        self.r = np.zeros((h, w), dtype=np.int16)
        yy, xx = np.mgrid[0:h, 0:w]
        self.cx = xx + 0.5
        self.cy = yy + 0.5

    def _px(self, p):
        return (p[0] * self.s, p[1] * self.s)

    def poly(self, pts, role):
        m = Image.new("L", (self.w, self.h), 0)
        ImageDraw.Draw(m).polygon([(x * self.s - 0.5, y * self.s - 0.5) for x, y in pts], fill=255)
        self.r[np.asarray(m) > 0] = role

    def ellipse(self, c, rx, ry, role, only=None):
        x0, y0 = self._px(c)
        mask = ((self.cx - x0) / (rx * self.s)) ** 2 + ((self.cy - y0) / (ry * self.s)) ** 2 <= 1.0
        if only is not None:
            mask &= np.isin(self.r, only)
        self.r[mask] = role

    def dot(self, p, role, size=None):
        n = size if size is not None else self.s
        x0 = int(math.floor(p[0] * self.s))
        y0 = int(math.floor(p[1] * self.s))
        for dy in range(n):
            for dx in range(n):
                self.set(x0 + dx, y0 + dy, role)

    def set(self, x, y, role):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.r[y, x] = role

    def seg(self, a, b, width, role, end_role=None, end_len=0.0):
        """A line exactly `width*s` pixels thick. The last `end_len` model units
        near b use end_role (the hoof)."""
        w = max(1, int(round(width * self.s)))
        ax, ay = self._px(a)
        bx, by = self._px(b)
        dx, dy = bx - ax, by - ay
        length = math.hypot(dx, dy)
        if length < 1e-6:
            self.dot(a, role)
            return
        steps = int(math.ceil(max(abs(dx), abs(dy)))) + 1
        cut = 1.0 - (end_len * self.s) / length if end_role is not None else 2.0
        for i in range(steps + 1):
            t = i / steps
            x = ax + dx * t
            y = ay + dy * t
            rl = end_role if t >= cut else role
            if abs(dy) >= abs(dx):
                x0 = int(math.floor(x - w / 2.0 + 0.5))
                for k in range(w):
                    self.set(x0 + k, int(math.floor(y)), rl)
            else:
                y0 = int(math.floor(y - w / 2.0 + 0.5))
                for k in range(w):
                    self.set(int(math.floor(x)), y0 + k, rl)


def rot(p, pivot, deg):
    a = math.radians(deg)
    x, y = p[0] - pivot[0], p[1] - pivot[1]
    return (pivot[0] + x * math.cos(a) - y * math.sin(a), pivot[1] + x * math.sin(a) + y * math.cos(a))


def ik(hip, foot, l1, l2, bend):
    """Joint of a 2-bone leg from hip to foot; bend=+1 joint forward (+x), -1 back."""
    dx, dy = foot[0] - hip[0], foot[1] - hip[1]
    d = math.hypot(dx, dy)
    d = min(d, l1 + l2 - 1e-3)
    if d < 1e-3:
        return hip
    # distance along hip->foot to the joint's projection, and the offset
    a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
    hgt = math.sqrt(max(0.0, l1 * l1 - a * a))
    ux, uy = dx / max(1e-6, math.hypot(dx, dy)), dy / max(1e-6, math.hypot(dx, dy))
    px_, py_ = hip[0] + ux * a, hip[1] + uy * a
    # perpendicular that points to +x when the leg hangs down
    nx, ny = -uy, ux
    if nx * bend < 0:
        nx, ny = -nx, -ny
    return (px_ + nx * hgt, py_ + ny * hgt)


# ---------------------------------------------------------------- models

@dataclass
class Model:
    w: int
    h: int
    ground: float
    pivot: tuple          # neck rotation pivot (withers)
    pitch_c: float        # x about which pitch rocks
    barrel: tuple         # (cx, cy, rx, ry)
    hind: tuple
    chest: tuple
    neck: list
    cranium: tuple
    face: list
    muzzle: tuple
    ear_near: list
    ear_far: list
    ear_flick: list
    eye: tuple
    eye_big: bool
    blaze: tuple
    nostril: tuple
    mouth: tuple          # (a, b) mouth line
    crest: list           # mane crest, poll to withers
    mane_w: float
    forelock: tuple
    tail_hang: list
    tail_stream: list
    tail_w: float
    fluffy_tail: bool
    hips: dict            # leg -> hip point
    feet: dict            # leg -> standing foot x
    l1: dict
    l2: dict
    leg_w: float
    hoof_len: float
    saddle: bool          # draws tack
    points: dict          # named model points (body frame unless in head_points)
    head_points: dict     # named model points that turn with the head


MARE = Model(
    w=40, h=32, ground=30.0, pivot=(24.5, 15.0), pitch_c=20.0,
    barrel=(19.6, 16.4, 9.2, 4.3),
    hind=(12.4, 15.2, 4.5, 4.7),
    chest=(26.4, 15.9, 3.7, 4.2),
    neck=[(22.5, 13.2), (25.0, 9.4), (28.2, 6.2), (30.8, 4.9), (32.8, 6.6), (31.4, 10.0),
          (30.0, 14.0), (28.8, 18.4), (25.0, 18.0)],
    cranium=(32.8, 6.9, 2.6, 2.4),
    face=[(31.6, 5.0), (34.2, 5.0), (37.4, 9.2), (37.7, 11.3), (36.2, 12.3), (33.8, 11.0), (31.3, 8.8)],
    muzzle=(36.6, 11.0, 1.5, 1.3),
    ear_near=[(32.5, 5.2), (33.5, 1.6), (34.3, 5.2)],
    ear_far=[(31.4, 5.2), (31.9, 2.0), (32.8, 5.2)],
    ear_flick=[(32.4, 5.2), (31.6, 2.6), (33.8, 5.0)],
    eye=(33.9, 6.4), eye_big=False,
    blaze=(35.6, 7.3),
    nostril=(37.0, 10.2),
    mouth=((35.2, 12.0), (37.4, 11.8)),
    crest=[(31.4, 4.3), (29.8, 5.1), (28.0, 6.4), (26.2, 8.4), (24.4, 10.6), (22.9, 12.2)],
    mane_w=2.0,
    forelock=((33.4, 4.6), (34.4, 6.2)),
    tail_hang=[(8.6, 11.6), (6.6, 13.2), (5.6, 16.4), (5.3, 20.2), (5.8, 23.6)],
    tail_stream=[(8.6, 11.6), (6.2, 12.4), (4.2, 14.0), (2.6, 16.2), (1.7, 18.6)],
    tail_w=2.6, fluffy_tail=False,
    hips={"FN": (26.6, 18.2), "FF": (24.6, 18.2), "HN": (13.4, 17.8), "HF": (15.6, 17.8)},
    feet={"FN": 27.5, "FF": 24.5, "HN": 11.5, "HF": 14.5},
    l1={"FN": 5.8, "FF": 5.8, "HN": 6.1, "HF": 6.1},
    l2={"FN": 6.4, "FF": 6.4, "HN": 6.5, "HF": 6.5},
    leg_w=2.0, hoof_len=1.0, saddle=True,
    points={"rider": (20.5, 13.0), "passenger": (14.8, 12.6), "saddle": (20.5, 10.6),
            "back": (17.0, 12.8), "legs": (10.4, 21.0), "tail": (6.0, 12.0)},
    head_points={"braid": (27.4, 7.4), "mouth": (37.8, 11.0), "head": (33.4, 6.2), "hat": (32.9, 4.2)},
)

FOAL = Model(
    w=24, h=20, ground=18.0, pivot=(14.0, 9.0), pitch_c=11.5,
    barrel=(11.4, 9.8, 4.3, 2.5),
    hind=(7.7, 9.3, 2.6, 2.7),
    chest=(14.5, 9.6, 2.3, 2.6),
    neck=[(13.0, 8.6), (14.5, 5.8), (16.0, 3.9), (17.8, 4.4), (17.4, 7.0), (16.7, 10.6), (14.8, 11.4)],
    cranium=(17.7, 4.7, 2.2, 2.1),
    face=[(16.6, 3.4), (18.6, 3.2), (20.8, 6.0), (20.9, 7.4), (19.6, 8.1), (17.8, 7.2), (16.4, 5.8)],
    muzzle=(20.1, 7.2, 1.0, 0.9),
    ear_near=[(17.5, 3.1), (18.2, 1.3), (19.0, 3.1)],
    ear_far=[(16.5, 3.1), (16.8, 1.6), (17.6, 3.1)],
    ear_flick=[(17.4, 3.1), (16.9, 1.2), (18.6, 3.0)],
    eye=(18.4, 4.2), eye_big=True,
    blaze=(19.2, 5.8),
    nostril=(20.4, 6.6),
    mouth=((19.0, 8.0), (20.7, 7.9)),
    crest=[(17.0, 2.9), (15.8, 3.9), (14.6, 5.6), (13.6, 7.4)],
    mane_w=1.0,
    forelock=((18.0, 2.8), (18.6, 3.6)),
    tail_hang=[(5.4, 8.4), (4.5, 9.6), (4.2, 11.0)],
    tail_stream=[(5.4, 8.4), (4.2, 8.6), (3.0, 9.4)],
    tail_w=1.6, fluffy_tail=True,
    hips={"FN": (15.0, 11.0), "FF": (13.8, 11.0), "HN": (8.2, 10.8), "HF": (9.4, 10.8)},
    feet={"FN": 15.4, "FF": 13.6, "HN": 7.4, "HF": 9.2},
    l1={"FN": 3.5, "FF": 3.5, "HN": 3.6, "HF": 3.6},
    l2={"FN": 3.9, "FF": 3.9, "HN": 3.9, "HF": 3.9},
    leg_w=1.0, hoof_len=0.9, saddle=False,
    points={"rider": (11.0, 8.0), "passenger": (8.0, 8.0), "saddle": (11.0, 7.5),
            "back": (10.0, 8.5), "legs": (8.0, 13.0), "tail": (5.0, 9.0)},
    head_points={"braid": (15.2, 5.2), "mouth": (20.8, 7.3), "head": (18.0, 4.2), "hat": (17.6, 2.3)},
)


# ---------------------------------------------------------------- drawing

def draw(model: Model, pose: Pose, s: int = 1, tack: bool | None = None):
    """Returns (roles canvas, body-transform, head-transform)."""
    cv = Canvas(model.w * s, model.h * s, s)
    tack = model.saddle if tack is None else tack
    dy = pose.dy
    if pose.lying:
        dy += model.ground - (model.barrel[1] + model.barrel[3]) - 0.3

    def xf(p):
        return (p[0], p[1] + dy - pose.pitch * (p[0] - model.pitch_c) / 20.0)

    piv = xf(model.pivot)

    def hf(p):
        q = xf(p)
        return rot(q, piv, pose.neck)

    def hpoly(pts):
        return [hf(p) for p in pts]

    # far legs, then the tail (behind the body)
    for leg in ("FF", "HF"):
        _leg(cv, model, pose, leg, xf, FAR, LGF)
    tail = [(a * (1 - pose.tail) + b * pose.tail, c * (1 - pose.tail) + d * pose.tail)
            for (a, c), (b, d) in zip(model.tail_hang, model.tail_stream)]
    if pose.swish:
        tail = [(x + pose.swish * 0.9 * (i / max(1, len(tail) - 1)) ** 2 * 2, y) for i, (x, y) in enumerate(tail)]
    tail = [xf(p) for p in tail]
    for i in range(len(tail) - 1):
        wdt = model.tail_w if i < len(tail) - 2 else max(1.0, model.tail_w - 1.0)
        cv.seg(tail[i], tail[i + 1], wdt, M)
    if model.fluffy_tail:
        c = tail[-1]
        cv.ellipse(c, 1.3, 1.5, M)
        cv.ellipse((c[0] - 0.4, c[1] + 0.2), 0.7, 0.8, MS)
    else:
        # a darker strand down the middle of the tail
        for i in range(1, len(tail) - 1):
            cv.seg((tail[i][0] + 0.4, tail[i][1]), (tail[i + 1][0] + 0.4, tail[i + 1][1]), 1.0 / s if s > 1 else 1.0, MS)
    # body
    bx, by, brx, bry = model.barrel
    cv.ellipse(xf((bx, by + (0.25 if pose.breath else 0.0))), brx, bry + (0.25 if pose.breath else 0.0), B)
    cv.ellipse(xf(model.hind[:2]), model.hind[2], model.hind[3], B)
    cv.ellipse(xf(model.chest[:2]), model.chest[2], model.chest[3], B)
    # neck and head
    cv.poly(hpoly(model.neck), B)
    cv.ellipse(hf(model.cranium[:2]), model.cranium[2], model.cranium[3], B)
    cv.poly(hpoly(model.face), B)
    if pose.jaw:
        # the jaw drops a little: the chin moves down
        fa = model.face
        k = model.w / 40.0 if model.w != 24 else 0.5
        chin = [fa[5], fa[4], fa[3], ((fa[5][0] + fa[4][0]) / 2, fa[4][1] + 0.7 * k)]
        cv.poly(hpoly(chin), B)
    cv.ellipse(hf(model.muzzle[:2]), model.muzzle[2], model.muzzle[3], Z, only=[B])
    # ears
    cv.poly(hpoly(model.ear_far), S)
    cv.poly(hpoly(model.ear_flick if pose.ear else model.ear_near), B)
    # shading pass on the body roles (before mane, legs and tack)
    _shade(cv, s)
    # mane: the crest line, strands falling on the near side of the neck
    crest = hpoly(model.crest)
    for i in range(len(crest) - 1):
        cv.seg(crest[i], crest[i + 1], model.mane_w, M)
    for i, p in enumerate(crest[:-1]):
        if pose.toss:
            q = (p[0] - 1.2, p[1] - 1.6)
        else:
            q = (p[0] - 0.9, p[1] + 1.7 + 0.4 * (i % 2))
        cv.seg(p, q, 1.0 if model.mane_w < 1.5 else 1.2, M if i % 2 == 0 else MS)
    fl = hpoly(model.forelock)
    cv.seg(fl[0], fl[1], 1.0, M)
    # face details
    if pose.eye_closed:
        e = hf(model.eye)
        cv.seg((e[0] - 0.6, e[1] + 0.3), (e[0] + 0.6, e[1] + 0.3), 1.0 / s, EYE)
    else:
        e = hf(model.eye)
        if s == 1:
            cv.dot(e, EYE, 1)
            if model.eye_big:
                cv.dot((e[0], e[1] + 1.0), EYE, 1)
        else:
            cv.dot(e, EYE, 2)
            cv.dot((e[0], e[1] + 1.0), EYE, 2)
            cv.set(int(e[0] * s), int(e[1] * s), GLI)
    if pose.mouth:
        a, b = hpoly(list(model.mouth))
        cv.seg(a, b, 1.2, MOUTH)
    elif s > 1:
        a, b = hpoly(list(model.mouth))
        cv.seg(((a[0] + b[0]) / 2, (a[1] + b[1]) / 2 - 0.2), b, 0.5, S)
    if s > 1:
        cv.dot(hf(model.nostril), NOST, 1)
        cv.dot(hf(model.blaze), BLAZE, 2)
    # near legs
    for leg in ("FN", "HN"):
        _leg(cv, model, pose, leg, xf, LEGU, LG)
    if pose.lying:
        _folded_legs(cv, model, xf)
    # tack
    if tack:
        _tack(cv, model, xf, hf, s)
    return cv, xf, hf


def _leg(cv, model, pose, leg, xf, upper_role, lower_role):
    if pose.lying:
        return
    hip = xf(model.hips[leg])
    dx, lift = pose.legs.get(leg, (0.0, 0.0))
    foot = (model.feet[leg] + dx, model.ground - lift)
    bend = 1 if leg.startswith("F") else -1
    l1, l2 = model.l1[leg], model.l2[leg]
    j = ik(hip, foot, l1, l2, bend)
    # clamp the foot to the reachable end of the lower bone
    fx, fy = foot
    d = math.hypot(fx - j[0], fy - j[1])
    if d > 1e-6:
        foot = (j[0] + (fx - j[0]) * l2 / d, j[1] + (fy - j[1]) * l2 / d) if d > l2 else foot
    cv.seg(hip, j, model.leg_w + (0.0 if model is FOAL else 0.0), upper_role)
    cv.seg(j, foot, model.leg_w, lower_role, end_role=H, end_len=model.hoof_len)


def _folded_legs(cv, model, xf):
    g = model.ground - 0.5
    # front legs folded forward under the chest, hind folded under the belly
    cv.seg((model.chest[0] - 1.0, g - 0.6), (model.chest[0] + 3.2, g), 1.0, LG, end_role=H, end_len=0.8)
    cv.seg((model.hind[0] + 0.5, g - 0.4), (model.hind[0] + 3.5, g), 1.0, LG, end_role=H, end_len=0.8)


def _tack(cv, model, xf, hf, s):
    cv.poly([xf(p) for p in [(16.6, 11.0), (24.4, 11.4), (24.5, 14.8), (16.9, 14.8)]], PAD)
    cv.poly([xf(p) for p in [(16.6, 14.2), (24.5, 14.2), (24.5, 14.8), (16.9, 14.8)]], PADS)
    cv.poly([xf(p) for p in [(17.6, 10.6), (23.4, 11.0), (23.4, 13.4), (17.6, 13.2)]], SAD)
    cv.dot(xf((17.3, 9.8)), SAD)
    cv.dot(xf((23.1, 10.2)), SAD)
    if s > 1:
        cv.seg(xf((18.4, 11.4)), xf((22.4, 11.7)), 0.5, SADL)
    cv.seg(xf((22.2, 13.6)), xf((22.6, 20.0)), 1.0 / s if s > 1 else 1.0, STRAP)
    # bridle: cheek strap, noseband, browband
    cv.seg(hf((32.1, 5.1)), hf((34.7, 10.9)), 1.0 / s if s > 1 else 1.0, STRAP)
    cv.seg(hf((35.5, 9.1)), hf((35.9, 12.1)), 1.0 / s if s > 1 else 1.0, STRAP)
    if s > 1:
        cv.seg(hf((32.2, 5.0)), hf((34.2, 4.6)), 0.5, STRAP)


def _shade(cv, s):
    r = cv.r
    body = r == B
    up = np.zeros_like(body)
    up[1:, :] = ~np.isin(r[:-1, :], [B, S, L])
    down = np.zeros_like(body)
    down[:-1, :] = ~np.isin(r[1:, :], [B, S, L])
    down[-1, :] = True
    r[body & up] = L
    shade = body & down
    if s > 1:
        d2 = np.zeros_like(body)
        d2[:-1, :] = shade[1:, :]
        r[body & d2] = S
    r[shade] = S


# ---------------------------------------------------------------- coats

def coat_overlay(cv, xf_inv, coat: str, model: Model):
    """Pinto patches / appaloosa blanket and spots / grey dapples, in body coordinates."""
    r = cv.r
    s = cv.s
    ys, xs = np.nonzero(np.isin(r, [B, S, L, LEGU, LG, LGF, FAR]))
    out = {}
    k = model.w / 40.0  # model scale relative to the mare
    for y, x in zip(ys, xs):
        mx, my = xf_inv(((x + 0.5) / s, (y + 0.5) / s))
        role = int(r[y, x])
        if coat == "pinto":
            if role in (LG, LGF):
                continue
            patch = (_in(mx, my, 27.5 * k, 8.5 * k, 3.6 * k, 4.2 * k) or _in(mx, my, 11.8 * k, 12.4 * k, 3.8 * k, 3.0 * k)
                     or _in(mx, my, 20.5 * k, 15.0 * k, 2.4 * k, 1.8 * k) or mx > 30.5 * k)
            if patch:
                out[(y, x)] = "5" if role in (S, FAR) else "4"
        elif coat == "appaloosa_swatch":
            ix, iy = x // s, y // s
            if (ix * 5 + iy * 3) % 7 == 0 and role in (B, L, S):
                out[(y, x)] = "6"
        elif coat == "appaloosa":
            if mx > 19.0 * k or (role in (LG, LGF)):
                if role in (B, L, LEGU):
                    out[(y, x)] = "4" if role != L else "v"
                elif role in (S, FAR):
                    out[(y, x)] = "5"
            else:
                ix, iy = x // s, y // s
                if (ix * 5 + iy * 3) % 7 == 0 and role in (B, L, S):
                    out[(y, x)] = "6"
        elif coat == "grey":
            ix, iy = x // s, y // s
            h_ = (ix * 7 + iy * 13 + (iy // 3) * 5) % 11
            if role == B and h_ == 0:
                out[(y, x)] = "j"
            elif role == B and h_ == 6 and iy % 2:
                out[(y, x)] = "l"
    return out


def _in(x, y, cx, cy, rx, ry):
    return ((x - cx) / rx) ** 2 + ((y - cy) / ry) ** 2 <= 1.0


def render(model: Model, pose: Pose, coat: str, s: int = 1, tack: bool | None = None,
           only_roles=None) -> np.ndarray:
    cv, xf, hf = draw(model, pose, s, tack)
    dy = pose.dy + ((model.ground - (model.barrel[1] + model.barrel[3]) - 0.3) if pose.lying else 0.0)

    def inv(p):
        x = p[0]
        return (x, p[1] - dy + pose.pitch * (x - model.pitch_c) / 20.0)

    cmap = {**COATS[coat], **TACK}
    over = coat_overlay(cv, inv, coat, model)
    out = np.full(cv.r.shape, T, dtype=np.int8)
    for role, ch in cmap.items():
        out[cv.r == role] = C(ch)
    for (y, x), ch in over.items():
        out[y, x] = C(ch)
    if coat == "pinto":
        # a white blaze down the brown face
        pass
    if only_roles is not None:
        keep = np.isin(cv.r, only_roles)
        out[~keep] = T
        return out
    return outline(out)


def points(model: Model, pose: Pose, s: int = 1) -> dict:
    cv, xf, hf = draw(model, pose, s)
    out = {}
    for k, p in model.points.items():
        q = xf(p)
        out[k] = [int(round(q[0] * s)), int(round(q[1] * s))]
    for k, p in model.head_points.items():
        q = hf(p)
        out[k] = [int(round(q[0] * s)), int(round(q[1] * s))]
    return out


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


# ---------------------------------------------------------------- the gaits

def _legs(fn, ff, hn, hf):
    return {"FN": fn, "FF": ff, "HN": hn, "HF": hf}


def mare_poses() -> list[tuple[str, Pose]]:
    P = []
    # stand 2: an ear flick and a tail swish
    P.append(("stand", Pose()))
    P.append(("stand", Pose(ear=1, swish=1)))
    # walk 4: four-beat, one foot in the air at a time (hind near, fore near, hind far, fore far)
    walk = [
        _legs((2.2, 0), (-2.0, 0), (0.5, 3.2), (0.0, 0)),
        _legs((0.5, 3.4), (0.0, 0), (-2.0, 0), (2.2, 0)),
        _legs((-2.0, 0), (2.2, 0), (0.0, 0), (0.5, 3.2)),
        _legs((0.0, 0), (0.5, 3.4), (2.2, 0), (-2.0, 0)),
    ]
    for i, lg in enumerate(walk):
        P.append(("walk", Pose(legs=lg, neck=(2 if i % 2 else -1), swish=(1 if i < 2 else -1))))
    # trot 4: diagonal pairs (fore near + hind far, fore far + hind near), a bob
    trot = [
        (_legs((1.2, 5.0), (-1.8, 0), (-1.8, 0), (1.6, 4.2)), -1.0),
        (_legs((4.2, 1.0), (-3.8, 1.6), (-4.2, 1.6), (3.8, 0.8)), 0.0),
        (_legs((-1.8, 0), (1.2, 5.0), (1.6, 4.2), (-1.8, 0)), -1.0),
        (_legs((-3.8, 1.6), (4.2, 1.0), (3.8, 0.8), (-4.2, 1.6)), 0.0),
    ]
    for lg, bob in trot:
        P.append(("trot", Pose(legs=lg, dy=bob, neck=-3, tail=0.35)))
    # canter 4: suspension (gathered), outside hind, the diagonal, the leading fore; rocking
    canter = [
        Pose(legs=_legs((1.0, 6.0), (-0.5, 5.0), (2.5, 4.0), (1.0, 4.5)), dy=-1.5, pitch=0.5, neck=4, tail=0.8),
        Pose(legs=_legs((5.0, 3.2), (3.6, 4.4), (3.5, 2.0), (1.5, 0)), dy=-0.6, pitch=2.2, neck=-2, tail=0.7),
        Pose(legs=_legs((4.4, 1.2), (1.2, 0), (-1.0, 0), (-3.8, 1.2)), dy=0.0, pitch=0.0, neck=6, tail=0.8),
        Pose(legs=_legs((0.2, 0), (-3.2, 1.5), (-4.4, 2.5), (-5.4, 3.6)), dy=0.2, pitch=-2.2, neck=12, tail=1.0),
    ]
    P += [("canter", p) for p in canter]
    # jump 3: takeoff (front tucked, pushing off the hinds), air (all tucked), landing (front reach)
    P.append(("jump", Pose(legs=_legs((-1.0, 9.0), (-2.0, 8.0), (-2.8, 0), (-1.0, 0)), pitch=3.5, dy=-0.5,
                           neck=6, tail=0.8)))
    P.append(("jump", Pose(legs=_legs((0.0, 9.5), (-1.2, 9.0), (-4.5, 6.5), (-3.5, 7.0)), pitch=0.5, dy=-2.0,
                           neck=14, tail=1.0)))
    P.append(("jump", Pose(legs=_legs((3.5, 0), (1.5, 1.2), (-3.5, 5.5), (-2.5, 6.0)), pitch=-3.0, dy=0.0,
                           neck=6, tail=0.9)))
    # neigh 2: head up, mouth open, mane tossed
    P.append(("neigh", Pose(neck=-16, mouth=True, toss=True, legs=_legs((0.5, 1.5), (0, 0), (0, 0), (0, 0)),
                            swish=1, dy=-0.5, pitch=1.0)))
    P.append(("neigh", Pose(neck=-12, mouth=True, legs=_legs((0.8, 2.5), (0, 0), (0, 0), (0, 0)), swish=-1,
                            dy=-0.5, pitch=1.0)))
    # munch 2: head down to the grass, jaw
    P.append(("munch", Pose(neck=74, pitch=-1.5, legs=_legs((1.5, 0), (-1.0, 0), (0, 0), (0, 0)))))
    P.append(("munch", Pose(neck=74, pitch=-1.5, jaw=1, legs=_legs((1.5, 0), (-1.0, 0), (0, 0), (0, 0)), swish=1)))
    # hoof 4: one hoof lifted each (fore near, fore far, hind near, hind far)
    P.append(("hoof", Pose(legs=_legs((-2.4, 5.0), (0, 0), (0, 0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (-2.4, 5.0), (0, 0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (0, 0), (1.5, 4.0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (0, 0), (0, 0), (1.5, 4.0)))))
    return P


def foal_poses() -> list[tuple[str, Pose]]:
    P = []
    P.append(("stand", Pose()))
    P.append(("stand", Pose(ear=1, swish=1)))
    trot = [
        (_legs((0.8, 3.0), (-1.0, 0), (-1.0, 0), (0.8, 2.6)), -1.0),
        (_legs((1.8, 0.4), (-1.6, 0.6), (-1.6, 0.6), (1.6, 0.3)), 0.0),
        (_legs((-1.0, 0), (0.8, 3.0), (0.8, 2.6), (-1.0, 0)), -1.0),
        (_legs((-1.6, 0.6), (1.8, 0.4), (1.6, 0.3), (-1.6, 0.6)), 0.0),
    ]
    for lg, bob in trot:
        P.append(("trot", Pose(legs=lg, dy=bob, neck=-4, tail=0.6)))
    # hop 3: crouch, up (all tucked), land
    P.append(("hop", Pose(legs=_legs((0.6, 0), (-0.4, 0), (-0.8, 0), (0.2, 0)), dy=1.0, neck=4)))
    P.append(("hop", Pose(legs=_legs((0.0, 4.5), (-0.6, 4.0), (-1.2, 3.6), (-0.6, 3.8)), dy=-1.0, pitch=0.5,
                          neck=-6, tail=1.0)))
    P.append(("hop", Pose(legs=_legs((1.6, 0), (0.6, 0.6), (-1.4, 2.4), (-0.8, 2.6)), pitch=-1.0, neck=4,
                          tail=0.8)))
    P.append(("neigh", Pose(neck=-18, mouth=True, toss=True, dy=-0.5, pitch=1.0)))
    P.append(("neigh", Pose(neck=-14, mouth=True, swish=1, dy=-0.5, pitch=1.0)))
    P.append(("sleep", Pose(lying=True, neck=52, eye_closed=True)))
    P.append(("sleep", Pose(lying=True, neck=52, eye_closed=True, breath=1)))
    return P


def big_poses() -> list[tuple[str, Pose]]:
    P = []
    P.append(("idle", Pose()))
    P.append(("idle", Pose(breath=1, swish=1)))
    P.append(("munch", Pose()))
    P.append(("munch", Pose(jaw=1)))
    P.append(("ear", Pose(ear=1)))
    P.append(("ear", Pose(swish=-1)))
    P.append(("hoof", Pose(legs=_legs((-2.4, 5.0), (0, 0), (0, 0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (-2.4, 5.0), (0, 0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (0, 0), (1.5, 4.0), (0, 0)))))
    P.append(("hoof", Pose(legs=_legs((0, 0), (0, 0), (0, 0), (1.5, 4.0)))))
    return P


def anim_ranges(poses) -> dict:
    out = {}
    for i, (name, _) in enumerate(poses):
        if name not in out:
            out[name] = [i, 0]
        out[name][1] += 1
    return out
