"""Turn a folder of captured frames (f00000000.png ...) into an inspection sheet.

Usage: python tools/shots.py shots/<screen> [--count 8] [--scale 3]

Picks N frames evenly across the capture, upscales them with nearest-neighbour
(so pixel problems stay visible to a reviewer and to a vision model) and lays
them out in a grid with the frame number under each. Writes <dir>/sheet.png and
also <dir>/last.png (the final frame at 4x).
"""

import argparse
import sys
from pathlib import Path

from PIL import Image, ImageDraw


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir", type=Path)
    ap.add_argument("--count", type=int, default=8)
    ap.add_argument("--scale", type=int, default=3)
    ap.add_argument("--cols", type=int, default=2)
    args = ap.parse_args()

    frames = sorted(args.dir.glob("f*.png"))
    if not frames:
        print(f"no frames in {args.dir} (did the capture crash? run the game to see errors)", file=sys.stderr)
        return 1
    n = min(args.count, len(frames))
    picks = [frames[round(i * (len(frames) - 1) / max(n - 1, 1))] for i in range(n)]

    first = Image.open(picks[0])
    w, h = first.size[0] * args.scale, first.size[1] * args.scale
    label_h = 14
    cols = args.cols
    rows = (n + cols - 1) // cols
    pad = 6
    sheet = Image.new("RGB", (cols * (w + pad) + pad, rows * (h + label_h + pad) + pad), (24, 24, 32))
    draw = ImageDraw.Draw(sheet)
    for i, p in enumerate(picks):
        img = Image.open(p).convert("RGB").resize((w, h), Image.NEAREST)
        x = pad + (i % cols) * (w + pad)
        y = pad + (i // cols) * (h + label_h + pad)
        sheet.paste(img, (x, y))
        draw.text((x, y + h + 1), p.stem, fill=(200, 200, 200))
    sheet.save(args.dir / "sheet.png")
    last = Image.open(frames[-1]).convert("RGB")
    last.resize((last.size[0] * 4, last.size[1] * 4), Image.NEAREST).save(args.dir / "last.png")
    print(f"{len(frames)} frames -> {args.dir / 'sheet.png'}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
