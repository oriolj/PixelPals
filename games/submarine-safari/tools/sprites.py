"""Render the palette-indexed sprite grids and generators to PNG strips, lint
them, derive the album icons and silhouettes, and draw a contact sheet.

Usage: uv run python tools/sprites.py [--palette endesga32]

This is PixelPals's renderer with a --palette argument (32-colour palettes use
the chars 0-9 a-v) and the album outputs this game needs; the proposal to move
it to shared/tools/ is in the game's CLAUDE.md.

Sources
    art_src/*.txt           -> game/art/<name>.png + game/art/manifest.json
    art_src/private/*.txt   -> game/private_pack/art/<name>.png + its manifest.json
                               + game/private_pack/riders.json
    tools/art_gen.py        -> the procedural sprites (sub, creatures, tiles...), same path
    derived                 -> icon_<id> (20x20, frame 0 centred) and sil_<id>
                               (its solid silhouette) for every album subject

Grid format (one or more sprites per file)
    # name WxH fps=N [base=<sprite>] [recolor=a:b,c:d] [mirror] [outline]
    <rows of W chars, H rows>     '.' = transparent, one char per palette index
    <blank line> <next frame, or a one-line directive (@bounce, @shift DX DY,
    @mirror, @recolor A:B, each optionally from=K)>
    A file whose first line is '; palette: <name>' is authored in another
    palette (e.g. the PixelPals riders in sweetie16); every pixel is mapped
    to the nearest colour of the game palette. 'outline' uses that palette's
    index 0; the game palette's outline is ink (Endesga 32 index 25, 'p').

Lint (exit 1): ragged rows, frame size different from the header, chars off
the palette, any PNG with partial alpha or an opaque colour off the palette.
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

# Album subjects: an icon + silhouette each (the page species, the whale, the bonus subjects).
ALBUM = ["clownfish", "blue_tang", "pufferfish", "turtle", "seahorse", "crab", "octopus", "eel",
         "jellyfish", "anglerfish", "squid", "lantern_fish"]
BONUS = ["bubble", "shell", "rock_smile", "starfish"]
ICON = 20
SIL_FILL = 23   # 3a4466
SIL_RIM = 21    # 8b9bb4


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
OUTLINE = 25


def nearest_map(src: list[tuple[int, int, int]]) -> dict[int, int]:
    pal = np.array(PALETTE, dtype=float)
    out = {}
    for i, c in enumerate(src):
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


# ---------------------------------------------------------------- album icons

def fit(f: np.ndarray, size: int = ICON) -> np.ndarray:
    """Frame cropped to its content, centred in size x size (centre-cropped if bigger)."""
    ys, xs = np.nonzero(f >= 0)
    out = np.full((size, size), T, dtype=np.int8)
    if len(xs) == 0:
        return out
    c = f[ys.min():ys.max() + 1, xs.min():xs.max() + 1]
    h, w = c.shape
    if w > size:
        c = c[:, (w - size) // 2:(w - size) // 2 + size]
    if h > size:
        c = c[(h - size) // 2:(h - size) // 2 + size, :]
    h, w = c.shape
    y0, x0 = (size - h) // 2, (size - w) // 2
    out[y0:y0 + h, x0:x0 + w] = c
    return out


def silhouette(f: np.ndarray) -> np.ndarray:
    filled = f >= 0
    inner = np.zeros_like(filled)
    inner[1:-1, 1:-1] = filled[:-2, 1:-1] & filled[2:, 1:-1] & filled[1:-1, :-2] & filled[1:-1, 2:]
    out = np.full_like(f, T)
    out[filled] = SIL_RIM
    out[filled & inner] = SIL_FILL
    return out


def album_outputs(sprites: dict[str, Sprite]) -> list[Sprite]:
    made = []
    for name in ALBUM + BONUS + ["whale"]:
        icon = sprites.get(f"icon_{name}")
        if icon is None:
            src = sprites.get(name)
            if src is None:
                err(f"album subject {name!r} has no sprite")
                continue
            icon = Sprite(f"icon_{name}", ICON, ICON, 0, [fit(src.frames[0])], origin=f"derived:{name}")
            made.append(icon)
        made.append(Sprite(f"sil_{name}", ICON, ICON, 0, [silhouette(icon.frames[0])], origin=f"derived:{name}"))
    whale = sprites.get("whale")
    if whale:
        made.append(Sprite("sil_whale_big", whale.w, whale.h, 0, [silhouette(whale.frames[0])], origin="derived:whale"))
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
    scale = 6
    while scale > 1 and (sp.w * n) * scale + gap * (n - 1) > MAX_W - 2 * PAD:
        scale -= 1
    fw, fh = sp.w * scale, sp.h * scale
    label = f"{sp.name} {sp.w}x{sp.h} x{n}" + (f" @{scale}x" if scale != 6 else "")
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
        if path.name == "reef_map.txt":
            continue
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
    for sp in album_outputs(public):
        public[sp.name] = sp
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

    derived = {s.name for s in pub if s.origin.startswith("derived:")}
    sheets = contact_sheets([s for s in pub if s.name not in derived], SRC / "contact_sheet.png")
    sheets += contact_sheets([s for s in pub if s.name in derived], SRC / "album_sheet.png")
    if private:
        sheets += contact_sheets(sorted(private.values(), key=lambda s: s.name), PRIVATE_SRC / "contact_sheet.png")
    print(f"sprites: {len(public)} public ({len(derived)} album icons/silhouettes), {len(private)} private; lint OK")
    for p in sheets:
        print(f"  sheet: {p.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    sys.exit(main())
