"""Draw the launcher icon (desktop entry + Godot window icon) from code.

Run: uv run python tools/icon.py   ->  game/icon.png (256x256, RGBA)

A rounded night-sky tile with a big friendly gamepad and three coloured seat
dots, in the Sweetie 16 palette. Drawn at 4x and downsampled for smooth edges.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "icon.png"

SS = 4
N = 256 * SS

NIGHT = (26, 28, 44)
NAVY = (41, 54, 111)
BLUE = (59, 93, 201)
SKY = (65, 166, 246)
YELLOW = (255, 205, 117)
GREEN = (167, 240, 112)
RED = (177, 62, 83)
ORANGE = (239, 125, 87)
WHITE = (244, 244, 244)
SLATE = (51, 60, 87)


def s(v: float) -> int:
    return int(round(v * SS))


def main() -> None:
    img = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    # Background tile: vertical gradient night -> navy -> blue, rounded.
    grad = Image.new("RGBA", (N, N))
    gd = ImageDraw.Draw(grad)
    for y in range(N):
        t = y / (N - 1)
        a, b, u = (NIGHT, NAVY, t / 0.6) if t < 0.6 else (NAVY, BLUE, (t - 0.6) / 0.4)
        gd.line([(0, y), (N, y)], fill=tuple(int(a[i] + (b[i] - a[i]) * u) for i in range(3)) + (255,))
    mask = Image.new("L", (N, N), 0)
    ImageDraw.Draw(mask).rounded_rectangle([s(8), s(8), N - s(8), N - s(8)], radius=s(52), fill=255)
    img.paste(grad, (0, 0), mask)
    d = ImageDraw.Draw(img)
    # Stars.
    for x, y, r, c in [(48, 50, 5, WHITE), (200, 40, 4, YELLOW), (170, 78, 3, WHITE), (82, 88, 3, SKY),
                       (128, 34, 3, WHITE), (220, 100, 3, WHITE)]:
        d.ellipse([s(x - r), s(y - r), s(x + r), s(y + r)], fill=c)
    # Gamepad body: two grips and a bridge, with a dark outline.
    body = [(46, 118, 210, 186)]
    for pad, col in [(0, SLATE), (-7, WHITE)]:
        o = -pad
        x0, y0, x1, y1 = body[0]
        d.rounded_rectangle([s(x0 - o), s(y0 - o), s(x1 + o), s(y1 + o)], radius=s(34 + o), fill=col)
        for cx in (74, 182):
            d.ellipse([s(cx - 34 - o), s(150 - o), s(cx + 34 + o), s(222 + o)], fill=col)
    # D-pad.
    d.rounded_rectangle([s(66), s(142), s(104), s(156)], radius=s(4), fill=SLATE)
    d.rounded_rectangle([s(78), s(130), s(92), s(168)], radius=s(4), fill=SLATE)
    # Buttons.
    for cx, cy, c in [(176, 132, YELLOW), (196, 150, RED), (156, 150, SKY), (176, 168, GREEN)]:
        d.ellipse([s(cx - 10), s(cy - 10), s(cx + 10), s(cy + 10)], fill=c)
    # Three seat dots above: who is here.
    for cx, c in [(98, SKY), (128, YELLOW), (158, GREEN)]:
        d.ellipse([s(cx - 11), s(84), s(cx + 11), s(106)], fill=c, outline=NIGHT, width=s(3))
    img = img.resize((256, 256), Image.LANCZOS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    img.save(OUT)
    print(f"-> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
