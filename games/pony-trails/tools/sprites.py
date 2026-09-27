"""Render the palette-indexed sprite grids and the procedural sprites to PNG
strips, lint them, derive a riding-helmeted jockey for every rider, write the
animation ranges and anchor points, and draw the contact and gait sheets.

Usage: uv run python tools/sprites.py [--palette endesga32]

This is Space Mission's renderer (Submarine Safari's, plus REMAP_OVERRIDES for
the Sweetie 16 -> Endesga 32 remap), with its bubble helmet replaced by a
riding helmet in the seat colour.

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json
    tools/art_gen.py        -> the procedural sprites (horses in every coat, the
                               stable, the trail, the show...), same path, plus
                               game/art/anims.json and game/art/points.json
    derived                 -> jockey_<rider>_<seat> (16x16, 2 frames) for every
                               rider and seat, private riders into the private pack

Grid format (one or more sprites per file)
    # name WxH fps=N [base=<sprite>] [recolor=a:b,c:d] [mirror] [outline]
    <rows of W chars, H rows>     '.' = transparent, one char per palette index
    <blank line> <next frame, or a one-line directive (@bounce, @shift DX DY,
    @mirror, @recolor A:B, each optionally from=K)>
    A file whose first line is '; palette: <name>' is authored in another
    palette (the PixelPals riders in sweetie16); every pixel is mapped to the
    nearest colour of the game palette (REMAP_OVERRIDES fixes the hue slips).

Lint (exit 1): ragged rows, frame size different from the header, chars off
the palette, any PNG with partial alpha or an opaque colour off the palette,
every horse coat's colours in the palette, anims.json ranges inside their
sprites, points.json points inside their frames.

Sheets: art_src/contact_sheet*.png, art_src/jockey_sheet.png,
art_src/gait_sheet.png (the gaits at 1x, 4x and in silhouette, every coat).
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SRC = ROOT / "art_src"
PRIVATE_SRC = SRC / "private"
PALETTES = SRC / "palettes"
OUT = ROOT / "game" / "art"
PRIVATE_OUT = ROOT / "game" / "private_pack" / "art"
PRIVATE_RIDERS = ROOT / "game" / "private_pack" / "riders.json"

CHARS = "0123456789abcdefghijklmnopqrstuv"
HEADER_RE = re.compile(r"^#\s+([a-z0-9_]+)\s+(\d+)x(\d+)(.*)$")
PALETTE_RE = re.compile(r"^;\s*palette:\s*([a-z0-9_]+)")
T = -1  # transparent index



def load_palette(name: str) -> list[tuple[int, int, int]]:
    path = PALETTES / f"{name}.hex"
    cols = []
    for line in path.read_text().split():
        line = line.strip().lstrip("#")
        if line:
            cols.append((int(line[0:2], 16), int(line[2:4], 16), int(line[4:6], 16)))
    if len(cols) > len(CHARS):
        raise SystemExit(f"palette {path} has {len(cols)} colours, at most {len(CHARS)}")
    return cols


PALETTE: list[tuple[int, int, int]] = []
# The committed riders (art_src/riders.txt); every one gets jockey_<name>_<seat>.
RIDERS = ["penguin", "monkey", "fox", "frog", "robot"]
OUTLINE = 25


# Where the nearest colour loses the hue, the remap is fixed by hand (Sweetie 16
# -> Endesga 32): the blue went grey (Sonic), the light green went beige, the
# fox's orange went pink.
REMAP_OVERRIDES = {"3b5dc9": "124e89", "a7f070": "63c74d", "ef7d57": "f77622"}


def nearest_map(src: list[tuple[int, int, int]]) -> dict[int, int]:
    pal = np.array(PALETTE, dtype=float)
    out = {}
    for i, c in enumerate(src):
        want = REMAP_OVERRIDES.get("%02x%02x%02x" % c)
        if want is not None:
            out[i] = [("%02x%02x%02x" % p) for p in PALETTE].index(want)
            continue
        # weighted RGB distance (green counts most, as the eye does)
        d = ((pal - np.array(c, dtype=float)) ** 2 * np.array([0.3, 0.59, 0.11])).sum(axis=1)
        out[i] = int(np.argmin(d))
    return out


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
    remap: dict[int, int] | None = None


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


def outline(f: np.ndarray, col: int) -> np.ndarray:
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
        m = re.fullmatch(r"([0-9a-v.]):([0-9a-v.])", tok)
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
    remap: dict[int, int] | None = None
    ncols = len(PALETTE)

    def flush() -> None:
        nonlocal block
        if block and cur is not None:
            add_block(cur, block, path, ncols)
        elif block:
            err(f"{path.name}:{block[0][0]}: grid rows before any '# name WxH' header")
        block = []

    lines = path.read_text().splitlines()
    for no, raw in enumerate(lines, 1):
        line = raw.rstrip()
        pm = PALETTE_RE.match(line)
        if pm and no <= 3:
            src = load_palette(pm.group(1))
            remap = nearest_map(src)
            ncols = len(src)
            continue
        if line.startswith(";"):
            continue
        m = HEADER_RE.match(line)
        if m:
            flush()
            name, w, h, rest = m.group(1), int(m.group(2)), int(m.group(3)), m.group(4)
            cur = Sprite(name, w, h, 6, private=private, origin=f"{path.name}:{no}", remap=remap)
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
            continue
        if not line.strip():
            flush()
            continue
        block.append((no, line.strip()))
    flush()
    for sp in sprites:
        if sp.remap is not None:
            sp.frames = [recolor(f, sp.remap) for f in sp.frames]
    return sprites


def add_block(sp: Sprite, block: list[tuple[int, str]], path: Path, ncols: int) -> None:
    where = f"{path.name}:{block[0][0]} ({sp.name} frame {len(sp.frames)})"
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
    if (w, h) != (sp.w, sp.h):
        err(f"{where}: frame is {w}x{h}, header says {sp.w}x{sp.h}")
        return
    arr = np.full((h, w), T, dtype=np.int8)
    for y, (no, r) in enumerate(block):
        for x, c in enumerate(r):
            if c == ".":
                continue
            if c not in CHARS[:ncols]:
                err(f"{path.name}:{no}: char {c!r} at column {x + 1} is not in the palette")
                continue
            arr[y, x] = CHARS.index(c)
    out_col = 0 if sp.remap is not None else OUTLINE
    sp.frames.append(outline(arr, out_col) if sp.outline else arr)


def resolve_bases(sprites: dict[str, Sprite]) -> None:
    for sp in sprites.values():
        if sp.base:
            base = sprites.get(sp.base)
            if base is None:
                err(f"{sp.origin}: base sprite {sp.base!r} not found")
                continue
            sp.w, sp.h = base.w, base.h
            sp.frames = [f.copy() for f in base.frames]
        if sp.recolor:
            sp.frames = [recolor(f, sp.recolor) for f in sp.frames]
        if sp.mirror:
            sp.frames = [mirror(f) for f in sp.frames]


# ---------------------------------------------------------------- jockeys

# Riding helmet per seat: (dome, shade/brim) Endesga 32 indices.
HELMET = {0: (17, 16), 1: (11, 10), 2: (12, 13)}   # 0099db/124e89, fee761/feae34, 63c74d/3e8948
GLINT = 19


def jockey_frame(fr: np.ndarray, seat: int) -> np.ndarray:
    """The rider with a riding helmet over the top of the head: a 3-row dome in
    the seat colour, a darker band on its last row and a little brim to the
    right (the riders face right), re-outlined in ink."""
    f = fr.copy()
    filled = f >= 0
    rows = np.nonzero(filled.any(axis=1))[0]
    if len(rows) == 0:
        return f
    y0 = int(rows[0])  # the outline row on top of the head
    xs = np.nonzero(filled[y0 + 1:y0 + 4].any(axis=0))[0]
    if len(xs) == 0:
        return f
    x0, x1 = int(xs.min()), int(xs.max())
    if x1 - x0 > 9:  # a wide head (ears, spikes): helmet over the front part
        x0 = x1 - 9
    dome, dark = HELMET[seat]
    cx = (x0 + x1) / 2.0
    rx = (x1 - x0) / 2.0 + 0.2
    helmet = np.zeros_like(filled)
    for y in range(y0, y0 + 3):
        for x in range(x0, x1 + 1):
            if y == y0 and (abs(x + 0.5 - (cx + 0.5)) > rx - 1.2):
                continue  # round the top corners
            helmet[y, x] = True
    f[helmet] = dome
    f[y0 + 2, x0:x1 + 1] = dark
    # brim to the right
    for x in range(x1 + 1, min(x1 + 3, f.shape[1])):
        f[y0 + 2, x] = dark
        helmet[y0 + 2, x] = True
    gx = int(round(cx)) - 1
    if 0 <= gx < f.shape[1] and helmet[y0 + 1, gx]:
        f[y0 + 1, gx] = GLINT
    # outline the helmet where it meets empty pixels
    near = np.zeros_like(helmet)
    near[1:, :] |= helmet[:-1, :]
    near[:-1, :] |= helmet[1:, :]
    near[:, 1:] |= helmet[:, :-1]
    near[:, :-1] |= helmet[:, 1:]
    f[near & (f < 0)] = OUTLINE
    return f


def jockey_outputs(riders: list[Sprite]) -> list[Sprite]:
    made = []
    for sp in riders:
        for seat in range(3):
            frames = [jockey_frame(fr, seat) for fr in sp.frames]
            made.append(Sprite(f"jockey_{sp.name}_{seat}", sp.w, sp.h, sp.fps, frames, private=sp.private,
                               origin=f"derived:{sp.name}"))
    return made


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
    a = np.asarray(Image.open(path).convert("RGBA"))
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
    arr = np.where(on[..., None], np.array([60, 70, 100], np.uint8), np.array([40, 48, 76], np.uint8))
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
        bg = checker(fw, fh, max(scale, 4))
        spr = Image.fromarray(to_rgba(f), "RGBA").resize((fw, fh), Image.NEAREST)
        bg.paste(spr, (0, 0), spr)
        img.paste(bg, (i * (fw + gap), LABEL_H))
    return img


def contact_sheets(sprites: list[Sprite], first: Path) -> list[Path]:
    tiles = [tile(sp) for sp in sprites]
    sheets: list[list[tuple[Image.Image, int, int]]] = [[]]
    x, y, row_h = PAD, PAD, 0
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
    for old in first.parent.glob(f"{first.stem}_*.png"):
        if old not in paths:
            old.unlink()
    return paths


# ---------------------------------------------------------------- horse data lint + gait sheet

def lint_horse_data(public: dict, art_gen) -> None:
    """Every coat in the palette (the PNG lint covers the pixels; this checks each
    coat's role map), every contract sprite present, the anim ranges inside
    their sprites and the per-frame points inside their frames."""
    import horses as hz
    for coat, roles in hz.COATS.items():
        for role, ch in {**roles, **hz.TACK}.items():
            if ch not in CHARS[:len(PALETTE)]:
                err(f"coat {coat}: role {role} -> {ch!r} is not in the palette")
    for coat in hz.MARE_COATS:
        for fam in ("mare", "mare_big"):
            if f"{fam}_{coat}" not in public:
                err(f"missing {fam}_{coat}")
    for coat in hz.FOAL_COATS:
        for fam in ("foal", "coat"):
            if f"{fam}_{coat}" not in public:
                err(f"missing {fam}_{coat}")
    fams = {"mare": "mare_bay", "foal": "foal_palomino", "mare_big": "mare_big_bay", "stable_cat": "stable_cat",
            "sheep": "sheep", "duck": "duck", "rabbit": "rabbit", "wild_horse": "wild_horse_1", "cow": "cow",
            "judge": "judge"}
    for fam, ranges in art_gen.ANIMS.items():
        sp = public.get(fams.get(fam, fam))
        if sp is None:
            err(f"anims.json: family {fam!r} has no sprite")
            continue
        for anim, (first, count, _fps) in ranges.items():
            if first < 0 or count < 1 or first + count > len(sp.frames):
                err(f"anims.json: {fam}.{anim} = [{first}, {count}] is outside {sp.name}'s {len(sp.frames)} frames")
    for fam, pts in art_gen.POINTS.items():
        sp = public.get(fams.get(fam, fam))
        if sp is None:
            continue
        for key, val in pts.items():
            if isinstance(val, list) and val and isinstance(val[0], list) and len(val) == len(sp.frames):
                for i, (x, y) in enumerate(val):
                    if not (0 <= x < sp.w and 0 <= y < sp.h):
                        err(f"points.json: {fam}.{key}[{i}] = {x},{y} outside {sp.w}x{sp.h}")


def gait_sheet(public: dict, path: Path) -> None:
    """For the bay mare and the palomino foal: every gait at 1x, at 4x and in
    solid silhouette; then every coat side by side at 1x and 4x."""
    import art_gen
    rows: list[Image.Image] = []
    font_h = 12

    def label(img: Image.Image, text: str) -> Image.Image:
        out = Image.new("RGB", (max(img.width, 200), img.height + font_h), (24, 24, 32))
        ImageDraw.Draw(out).text((2, 0), text, fill=(230, 230, 230))
        out.paste(img, (0, font_h))
        return out

    def strip_of(frames, scale, sil=False, bg=(99, 199, 77)):
        w, h = frames[0].shape[1] * scale, frames[0].shape[0] * scale
        gap = 4 * max(1, scale // 2)
        img = Image.new("RGB", (len(frames) * (w + gap), h), bg)
        for i, f in enumerate(frames):
            rgba = to_rgba(f)
            if sil:
                rgba[..., :3] = np.where(rgba[..., 3:] > 0, 24, 0)
            im = Image.fromarray(rgba, "RGBA").resize((w, h), Image.NEAREST)
            img.paste(im, (i * (w + gap), 0), im)
        return img

    for fam, sp_name in (("mare", "mare_bay"), ("foal", "foal_palomino")):
        sp = public[sp_name]
        for anim, (first, count, _fps) in art_gen.ANIMS[fam].items():
            frames = sp.frames[first:first + count]
            one = strip_of(frames, 1)
            four = strip_of(frames, 4)
            sil = strip_of(frames, 4, sil=True, bg=(235, 235, 235))
            row = Image.new("RGB", (one.width + four.width + sil.width + 40, four.height), (24, 24, 32))
            row.paste(one, (0, 0))
            row.paste(four, (one.width + 20, 0))
            row.paste(sil, (one.width + four.width + 40, 0))
            rows.append(label(row, f"{sp_name} {anim} (1x | 4x | silhouette)"))
    for fam, coats in (("mare", "bay chestnut palomino grey black pinto"),
                       ("foal", "bay chestnut palomino grey black pinto appaloosa")):
        frames = [public[f"{fam}_{c}"].frames[0] for c in coats.split()]
        one = strip_of(frames, 1)
        four = strip_of(frames, 4)
        rows.append(label(one, f"{fam} coats at 1x: {coats}"))
        rows.append(label(four, f"{fam} coats at 4x"))
    frames = [public[f"mare_big_{c}"].frames[0] for c in "bay chestnut palomino grey black pinto".split()]
    rows.append(label(strip_of(frames, 1), "mare_big coats at 1x"))
    w = max(r.width for r in rows)
    h = sum(r.height + 6 for r in rows)
    sheet = Image.new("RGB", (w, h), (24, 24, 32))
    y = 0
    for r in rows:
        sheet.paste(r, (0, y))
        y += r.height + 6
    sheet.save(path, optimize=True)


# ---------------------------------------------------------------- main

def main() -> int:
    global PALETTE
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--palette", default="endesga32", help="palette name in art_src/palettes/")
    args = ap.parse_args()
    PALETTE = load_palette(args.palette)

    import art_gen  # the drawings; imported after the palette is known

    public: dict[str, Sprite] = {}
    private: dict[str, Sprite] = {}
    for path in sorted(SRC.glob("*.txt")):
        for sp in parse_file(path, private=False):
            if sp.name in public:
                err(f"{sp.origin}: duplicate sprite {sp.name!r}")
            public[sp.name] = sp
    for name, w, h, fps, frames in art_gen.generate():
        if name in public:
            err(f"generator:{name}: duplicate sprite {name!r}")
        public[name] = Sprite(name, w, h, fps, frames, origin=f"generator:{name}")
    if PRIVATE_SRC.is_dir():
        for path in sorted(PRIVATE_SRC.glob("*.txt")):
            for sp in parse_file(path, private=True):
                if sp.name in private or sp.name in public:
                    err(f"{sp.origin}: duplicate sprite {sp.name!r}")
                private[sp.name] = sp
    everything = {**public, **private}
    resolve_bases(everything)
    rider_sprites = [public[r] for r in RIDERS if r in public]
    rider_sprites += [sp for sp in private.values() if (sp.w, sp.h) == (16, 16) and len(sp.frames) == 2]
    for sp in jockey_outputs(rider_sprites):
        (private if sp.private else public)[sp.name] = sp
    everything = {**public, **private}
    for sp in everything.values():
        if not sp.frames:
            err(f"{sp.origin}: sprite {sp.name!r} has no frames")
        for i, f in enumerate(sp.frames):
            if f.shape != (sp.h, sp.w):
                err(f"{sp.origin}: {sp.name} frame {i} is {f.shape[1]}x{f.shape[0]}, header says {sp.w}x{sp.h}")
            if f.max() >= len(PALETTE) or f.min() < T:
                err(f"{sp.origin}: {sp.name} frame {i} has indices off the palette")
    if errors:
        for e in errors:
            print(f"LINT: {e}", file=sys.stderr)
        return 1

    pub = sorted(public.values(), key=lambda s: s.name)
    manifest = write_outputs(pub, OUT)
    for stale in OUT.glob("*.png"):
        if stale.stem not in manifest:
            print(f"removing stale {stale.relative_to(ROOT)}")
            stale.unlink()
            imp = stale.with_suffix(".png.import")
            if imp.exists():
                imp.unlink()
    if private:
        priv = sorted(private.values(), key=lambda s: s.name)
        write_outputs(priv, PRIVATE_OUT)
        riders = [s.name for s in private.values() if (s.w, s.h) == (16, 16) and len(s.frames) == 2
                  and not s.name.startswith("jockey_")]
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

    lint_horse_data(public, art_gen)
    if errors:
        for e in errors:
            print(f"LINT: {e}", file=sys.stderr)
        return 1
    (OUT / "anims.json").write_text(json.dumps(art_gen.ANIMS, indent=1, sort_keys=True) + "\n")
    (OUT / "points.json").write_text(json.dumps(art_gen.POINTS, sort_keys=True) + "\n")
    gait_sheet(public, SRC / "gait_sheet.png")

    derived = {s.name for s in pub if s.origin.startswith("derived:")}
    sheets = contact_sheets([s for s in pub if s.name not in derived], SRC / "contact_sheet.png")
    sheets += contact_sheets([s for s in pub if s.name in derived], SRC / "jockey_sheet.png")
    if private:
        sheets += contact_sheets(sorted(private.values(), key=lambda s: s.name), PRIVATE_SRC / "contact_sheet.png")
    sheets.append(SRC / "gait_sheet.png")
    print(f"sprites: {len(public)} public ({len(derived)} jockeys), {len(private)} private; lint OK")
    for p in sheets:
        print(f"  sheet: {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
