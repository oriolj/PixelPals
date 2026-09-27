"""Make games/<slug>/cover.png for every committed, playable game.

Run from the repo root: `make covers` (or `uv run python launcher/tools/covers.py [--only a,b]`).

For each game it runs the game's own demo capture (`make -C games/<slug> shot
SHOT_SCREEN=<screen> SHOT_SECONDS=<n>`, xvfb, fixed 30 fps, so the frames are
reproducible), takes one frame and saves it as the cover at the game's native
capture resolution (320x180 / 480x270 pixel games, 1280x720 vector games),
16:9. The frame per game was CHOSEN BY LOOKING at the capture sheets
(2026-09-27): see PICKS. A game without a pick (a new game) uses its
Makefile's SHOT_SCREEN and the most colourful frame of the second half of the
capture; look at the result (launcher/shots/covers.png) and add a pick.

Only games whose Makefile is committed are touched, so a game another agent is
still building is never written into; rerun `make covers` once it is committed.
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

from PIL import Image, ImageDraw, ImageStat

ROOT = Path(__file__).resolve().parents[2]
GAMES = ROOT / "games"
SHEET = ROOT / "launcher" / "shots" / "covers.png"

# slug: (screen, seconds to capture, frame index, optional crop (x, y, w) in native px)
PICKS: dict[str, tuple[str, int, int, tuple[int, int, int] | None]] = {
    "pixelpals": ("level", 8, 196, None),            # the tub mid-sky, stars, a balloon
    "digger-treasure": ("dig", 8, 196, None),        # tunnels, the loaded dump truck, treasure
    "fire-truck-rescue": ("level", 10, 272, None),   # hosing a fire, smoke, the town
    "garage-band": ("play", 10, 82, None),           # the band on stage, gong burst, lights
    "paint-party": ("paint", 8, 239, None),          # the picture with strokes, star, splats
    "pancake-kitchen": ("kitchen", 8, 124, None),    # a pancake flipped sky-high, the bear customer
    "pillow-fort": ("fort", 10, 221, None),          # the bunny found under a pillow, glowing
    "rocket-to-the-moon": ("flight", 17, 457, None), # the rocket among planets and stars
    "space-mission": ("orbit", 27, 762, None),       # the Shuttle's arm, the ISS, Earth
    "submarine-safari": ("level", 8, 87, None),      # the sub's light, a turtle photo, kelp
    "tower-topple": ("play", 12, 327, None),         # a tall wobbly tower of silly blocks
    "tractor-farm": ("finale", 10, 240, None),       # the rainbow over the grown field, the tractor
    "train-conductor": ("level", 8, 196, (200, 90, 960)),  # the train with passengers at a station (cropped in)
    "zoo-keeper": ("zoo", 8, 76, None),              # the food picker in front of the monkey
}


def committed_games() -> list[str]:
    out = subprocess.run(["git", "ls-files", "games/*/Makefile"], cwd=ROOT, capture_output=True, text=True,
                         check=True).stdout.split()
    slugs = [p.split("/")[1] for p in out]
    return [s for s in slugs if (GAMES / s / "game" / "project.godot").exists()]


def default_screen(slug: str) -> str:
    mk = (GAMES / slug / "Makefile").read_text()
    m = re.search(r"^SHOT_SCREEN\s*\?=\s*(\S+)", mk, re.M)
    return m.group(1) if m else "level"


def colourfulness(img: Image.Image) -> float:
    """Hasler-Suesstrunk colourfulness plus a little contrast: busy, bright frames win."""
    import numpy as np

    a = np.asarray(img.convert("RGB"), dtype=np.float64)
    rg = a[..., 0] - a[..., 1]
    yb = 0.5 * (a[..., 0] + a[..., 1]) - a[..., 2]
    c = np.sqrt(rg.std() ** 2 + yb.std() ** 2) + 0.3 * np.sqrt(rg.mean() ** 2 + yb.mean() ** 2)
    return c + 0.5 * ImageStat.Stat(img.convert("L")).stddev[0]


def to_16_9(img: Image.Image) -> Image.Image:
    w, h = img.size
    if w * 9 == h * 16:
        return img
    if w * 9 > h * 16:
        nw = h * 16 // 9
        return img.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
    nh = w * 9 // 16
    return img.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))


def make_cover(slug: str) -> tuple[str, str]:
    pick = PICKS.get(slug)
    screen, seconds, index, crop = pick if pick else (default_screen(slug), 0, -1, None)
    cmd = ["make", "--no-print-directory", "-C", str(GAMES / slug), "shot", f"SHOT_SCREEN={screen}"]
    if seconds:
        cmd.append(f"SHOT_SECONDS={seconds}")
    frames: list[Path] = []
    for _attempt in range(3):
        # Parallel `xvfb-run -a` can race for a display and cut a capture
        # short; a capture shorter than the picked frame is simply retried.
        subprocess.run(cmd, capture_output=True, text=True, timeout=900)
        frames = sorted((GAMES / slug / "shots" / screen).glob("f*.png"))
        if frames and len(frames) > index:
            break
    if not frames:
        return slug, f"FAILED: no frames from `{' '.join(cmd[3:])}`"
    if index >= 0:
        frame = frames[min(index, len(frames) - 1)]
        how = f"frame {frame.stem} (picked)"
    else:
        tail = frames[len(frames) // 2:]
        frame = max(tail[:: max(1, len(tail) // 40)], key=lambda p: colourfulness(Image.open(p)))
        how = f"frame {frame.stem} (auto: most colourful; look at it and add a pick)"
    img = Image.open(frame).convert("RGB")
    native = img.size
    if crop:
        x, y, w = crop
        img = img.crop((x, y, x + w, y + w * 9 // 16))
        pixel = native[0] <= 640
        img = img.resize(native, Image.NEAREST if pixel else Image.LANCZOS)
    img = to_16_9(img)
    out = GAMES / slug / "cover.png"
    img.save(out, optimize=True)
    return slug, f"{screen} {how} -> {out.relative_to(ROOT)} {img.size[0]}x{img.size[1]}"


def contact_sheet(slugs: list[str]) -> None:
    tw, th = 480, 270
    cols = 4
    rows = (len(slugs) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (tw + 8) + 8, rows * (th + 26) + 8), (26, 28, 44))
    d = ImageDraw.Draw(sheet)
    for i, s in enumerate(slugs):
        p = GAMES / s / "cover.png"
        if not p.exists():
            continue
        im = Image.open(p).convert("RGB")
        im = im.resize((tw, th), Image.NEAREST if im.width <= 640 else Image.LANCZOS)
        x = 8 + (i % cols) * (tw + 8)
        y = 8 + (i // cols) * (th + 26)
        sheet.paste(im, (x, y))
        d.text((x + 2, y + th + 6), f"{s} ({Image.open(p).size[0]}x{Image.open(p).size[1]})", fill=(244, 244, 244))
    SHEET.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(SHEET)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", help="comma-separated slugs")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()
    slugs = committed_games()
    if args.only:
        want = args.only.split(",")
        skipped = [s for s in want if s not in slugs]
        if skipped:
            print(f"skipping (not committed or not playable yet): {', '.join(skipped)}")
        slugs = [s for s in slugs if s in want]
    pending = sorted(p.name for p in GAMES.iterdir() if p.is_dir() and p.name not in committed_games())
    if pending and not args.only:
        print(f"not committed yet, left alone: {', '.join(pending)} (rerun make covers once they are)")
    ok = True
    with ThreadPoolExecutor(max_workers=args.jobs) as pool:
        for slug, msg in pool.map(make_cover, slugs):
            print(f"  {slug:<22} {msg}")
            ok &= not msg.startswith("FAILED")
    contact_sheet(committed_games())
    print(f"contact sheet: {SHEET.relative_to(ROOT)}  (LOOK at it)")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
