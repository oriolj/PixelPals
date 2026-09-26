"""Tractor Farm sound synth: every sound, the three loops and both music
tracks, made by our own code (the PixelPals synth, re-voiced for the farm).

Run: uv run python tools/sfx.py [--check DIR]   (or: make sfx)

Building blocks copied from games/pixelpals/tools/sfx.py: square/saw/
triangle/sine/noise oscillators with polyBLEP, ADSR, pitch glides,
vibrato and a zero-phase filter. Everything is seeded, so a rerun writes
byte-identical files. Output: game/audio/<name>.wav, 16-bit mono 44100 Hz.

Loudness: SFX are normalised to about -15 LUFS, the ambience loops (engine,
plough, rain) to LOOP_LUFS and the music to MUSIC_LUFS; no file peaks above
-1 dBFS. The report printed at the end is the verification: peak, RMS,
LUFS, length, and for every loop the seam continuity. With --check DIR it
also writes spectrogram + waveform PNGs to DIR.
"""

from __future__ import annotations


import argparse
import math
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "audio"

PEAK_DBFS = -1.0
SFX_LUFS = -15.0
# sfx.gd plays music at -8 dB, so a -14 LUFS file sits about 7 dB under the SFX in game.
MUSIC_LUFS = -14.0
# The level plays the loops at -14..-6 dB under this.
LOOP_LUFS = -18.0

# ----------------------------------------------------------------------------
# Building blocks
# ----------------------------------------------------------------------------


def secs(n: float) -> int:
    return int(round(n * SR))


def midi(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69) / 12.0)


def glide(n: int, pts: list[tuple[float, float]]) -> np.ndarray:
    """Frequency curve through (time_s, hz) breakpoints, interpolated in pitch (log2)."""
    t = np.arange(n) / SR
    ts = [p[0] for p in pts]
    hz = np.log2([p[1] for p in pts])
    return 2.0 ** np.interp(t, ts, hz)


def vibrato(freq: np.ndarray, rate: float, semis: float, delay: float = 0.0, decay: float = 0.0) -> np.ndarray:
    t = np.arange(len(freq)) / SR
    depth = np.clip((t - delay) / 0.05, 0.0, 1.0) * semis
    if decay > 0:
        depth = depth * np.exp(-t / decay)
    return freq * 2.0 ** (depth / 12.0 * np.sin(2 * np.pi * rate * t))


def arpeggio(freq: np.ndarray, step: float, ratios: list[float]) -> np.ndarray:
    idx = (np.arange(len(freq)) // max(1, secs(step))) % len(ratios)
    return freq * np.asarray(ratios)[idx]


def _blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    y = np.zeros_like(t)
    m = t < dt
    x = t[m] / dt[m]
    y[m] = x + x - x * x - 1.0
    m = t > 1.0 - dt
    x = (t[m] - 1.0) / dt[m]
    y[m] = x * x + x + x + 1.0
    return y


def osc(kind: str, freq: np.ndarray | float, n: int | None = None, duty: float = 0.5,
        rng: np.random.Generator | None = None) -> np.ndarray:
    if np.isscalar(freq):
        freq = np.full(n, float(freq))
    freq = np.asarray(freq, dtype=np.float64)
    dt = np.clip(freq / SR, 1e-9, 0.5)
    phase = np.concatenate(([0.0], np.cumsum(dt)[:-1]))
    t = phase % 1.0
    if kind == "sine":
        return np.sin(2 * np.pi * phase)
    if kind == "triangle":
        return 1.0 - 4.0 * np.abs(t - 0.5)
    if kind == "saw":
        return 2.0 * t - 1.0 - _blep(t, dt)
    if kind == "square":
        naive = np.where(t < duty, 1.0, -1.0)
        return naive + _blep(t, dt) - _blep((t - duty) % 1.0, dt)
    if kind == "noise":  # sample-and-hold noise, pitched by freq (the sfxr way)
        rng = rng or np.random.default_rng(0)
        steps = np.floor(phase).astype(np.int64)
        vals = rng.uniform(-1.0, 1.0, steps[-1] + 2)
        return vals[steps]
    if kind == "white":
        rng = rng or np.random.default_rng(0)
        return rng.uniform(-1.0, 1.0, len(freq))
    raise ValueError(kind)


def env_pts(n: int, pts: list[tuple[float, float]]) -> np.ndarray:
    t = np.arange(n) / SR
    return np.interp(t, [p[0] for p in pts], [p[1] for p in pts])


def adsr(n: int, a: float, d: float, s: float, r: float, curve: float = 2.0) -> np.ndarray:
    """ADSR over n samples; the release ends exactly at the last sample."""
    total = n / SR
    r = min(r, total)
    a = min(a, max(total - r, 0.0))
    d = min(d, max(total - r - a, 0.0))
    t = np.arange(n) / SR
    e = np.empty(n)
    ra = t < a
    e[ra] = t[ra] / a if a > 0 else 1.0
    rd = (t >= a) & (t < a + d)
    e[rd] = s + (1 - s) * (1 - (t[rd] - a) / d) ** curve if d > 0 else s
    rs = (t >= a + d) & (t < total - r)
    e[rs] = s
    rr = t >= total - r
    e[rr] = s * (1 - (t[rr] - (total - r)) / r) ** curve if r > 0 else 0.0
    return e


def perc(n: int, attack: float, decay: float) -> np.ndarray:
    """Fast attack, exponential decay, forced to zero at the end."""
    t = np.arange(n) / SR
    e = np.minimum(t / max(attack, 1e-4), 1.0) * np.exp(-t / decay)
    fade = min(n, secs(0.005))
    e[n - fade:] *= np.linspace(1, 0, fade)
    return e


def _butter_mag(f: np.ndarray, fc: float, order: int) -> np.ndarray:
    return 1.0 / np.sqrt(1.0 + (f / fc) ** (2 * order))


def fft_filter(x: np.ndarray, low: float | None = None, high: float | None = None,
               order: int = 2, circular: bool = False, sr: int = SR) -> np.ndarray:
    """Zero-phase Butterworth-magnitude filter. low = low-pass cutoff, high = high-pass cutoff.
    circular=True treats x as a loop (used for the music, so the seam stays seamless)."""
    n = len(x)
    pad = 0 if circular else secs(0.1)
    y = np.concatenate([x, np.zeros(pad)]) if pad else x
    spec = np.fft.rfft(y)
    f = np.fft.rfftfreq(len(y), 1.0 / sr)
    g = np.ones_like(f)
    if low:
        g *= _butter_mag(f, low, order)
    if high:
        g *= 1.0 - _butter_mag(f, high, order)
        g[0] = 0.0
    return np.fft.irfft(spec * g, len(y))[:n]


def onepole_sweep(x: np.ndarray, cutoff: np.ndarray) -> np.ndarray:
    """Causal one-pole low-pass with a time-varying cutoff (for the whoosh)."""
    a = 1.0 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.empty_like(x)
    z = 0.0
    for i, (xi, ai) in enumerate(zip(x.tolist(), a.tolist())):
        z += ai * (xi - z)
        y[i] = z
    return y


def place(buf: np.ndarray, sig: np.ndarray, start: int, gain: float = 1.0, circular: bool = False) -> None:
    if circular:
        idx = (start + np.arange(len(sig))) % len(buf)
        np.add.at(buf, idx, sig * gain)
    else:
        end = min(len(buf), start + len(sig))
        buf[start:end] += sig[: end - start] * gain


def tone(kind: str, freq: np.ndarray, env: np.ndarray, duty: float = 0.5, rng=None) -> np.ndarray:
    return osc(kind, freq, duty=duty, rng=rng) * env



# ----------------------------------------------------------------------------
# Sound effects (the farm)
# ----------------------------------------------------------------------------


def pluck(m: float, dur: float, kind: str = "triangle", decay: float = 0.18, bright: float = 0.25) -> np.ndarray:
    n = secs(dur)
    f = np.full(n, midi(m))
    s = (1 - bright) * osc(kind, f) + bright * osc("sine", f * 2)
    return s * perc(n, 0.002, decay)


def horn() -> np.ndarray:
    """Tractor honk: a two-note 'meep-meep' of a reedy square+saw chord."""
    out = np.zeros(secs(0.62))
    for start, dur in [(0.0, 0.2), (0.28, 0.3)]:
        n = secs(dur)
        e = adsr(n, 0.01, 0.05, 0.85, 0.06)
        s = np.zeros(n)
        for hz, g in [(392, 0.6), (494, 0.5)]:
            f = vibrato(np.full(n, float(hz)), 30, 0.12)
            s += g * (0.6 * osc("square", f, duty=0.4) + 0.4 * osc("saw", f))
        place(out, fft_filter(s * e, low=2400, high=200), secs(start))
    return out


def seed_pick(i: int) -> np.ndarray:
    """One recognisable blip per vegetable: carrot crunchy-high, pumpkin
    round-low, sunflower bell-bright, strawberry sweet-sparkly."""
    base = [76, 60, 84, 79][i]
    out = np.zeros(secs(0.36))
    if i == 0:  # carrot: a quick 'crunch' tick then a bright hop up
        rng = np.random.default_rng(10)
        n = secs(0.03)
        place(out, fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=1500) * perc(n, 0.001, 0.01), 0, 0.5)
        n = secs(0.2)
        f = glide(n, [(0, midi(base)), (0.05, midi(base + 7)), (0.2, midi(base + 7))])
        place(out, (0.7 * osc("square", f, duty=0.3) + 0.3 * osc("sine", f)) * perc(n, 0.003, 0.08), secs(0.02))
    elif i == 1:  # pumpkin: a round 'bonk' with a low body
        n = secs(0.3)
        f = glide(n, [(0, midi(base + 5)), (0.05, midi(base)), (0.3, midi(base - 1))])
        place(out, (0.7 * osc("sine", f) + 0.3 * osc("triangle", f * 2)) * perc(n, 0.002, 0.12), 0)
    elif i == 2:  # sunflower: a bell ding (inharmonic partials)
        n = secs(0.34)
        s = sum(g * osc("sine", np.full(n, midi(base) * r)) for r, g in [(1, 0.6), (2.76, 0.25), (5.4, 0.12)])
        place(out, s * perc(n, 0.002, 0.14), 0)
    else:  # strawberry: two sweet sparkly notes
        for k, m in enumerate([base, base + 5]):
            n = secs(0.16)
            s = osc("sine", vibrato(np.full(n, midi(m)), 12, 0.2)) + 0.3 * osc("triangle", np.full(n, midi(m + 12)))
            place(out, s * perc(n, 0.002, 0.07), secs(0.08 * k))
    return fft_filter(out, low=8000, high=120)


def plant() -> np.ndarray:
    """A tiny seed 'pip'."""
    n = secs(0.07)
    f = glide(n, [(0, 1100), (0.07, 1500)])
    return fft_filter(osc("sine", f) * perc(n, 0.002, 0.025), low=6000, high=300)


def droplets(n: int, count: int, rng: np.random.Generator, lo: float = 1800, hi: float = 4200,
             circular: bool = False, density=None) -> np.ndarray:
    buf = np.zeros(n)
    for _ in range(count):
        at = int(rng.uniform(0, n)) if density is None else int(density(rng.uniform()) * n)
        m = secs(0.03)
        f = glide(m, [(0, rng.uniform(lo, hi)), (0.03, rng.uniform(lo, hi) * 1.4)])
        place(buf, osc("sine", f) * perc(m, 0.001, 0.008), at, rng.uniform(0.2, 0.6), circular=circular)
    return buf


def rain_start() -> np.ndarray:
    """Pitter-patter swell: droplets thicken over the first 0.7 s, soft hiss."""
    n = secs(1.0)
    rng = np.random.default_rng(21)
    drops = droplets(n, 60, rng, density=lambda u: u ** 0.6 * 0.85)
    hiss = fft_filter(osc("white", np.ones(n), rng=rng), low=5000, high=1500) * env_pts(n, [(0, 0), (0.6, 0.25), (1.0, 0)])
    return fft_filter(drops + hiss, low=9000, high=300)


def grow(i: int) -> np.ndarray:
    """Rising spring boing plus a bright pluck; each stage higher (i = 1..3)."""
    out = np.zeros(secs(0.5))
    lo = [150, 200, 270][i - 1]
    n = secs(0.34)
    f = glide(n, [(0, lo), (0.12, lo * 2.2), (0.34, lo * 2.4)])
    f = vibrato(f, 14, 2.0, decay=0.12)
    place(out, (0.7 * osc("triangle", f) + 0.3 * osc("square", f, duty=0.5)) * perc(n, 0.01, 0.14), 0, 0.8)
    for k, m in enumerate([72 + 4 * i, 79 + 4 * i]):
        place(out, pluck(m, 0.18, "square", 0.06, 0.4) * 0.5, secs(0.1 + 0.06 * k))
    return fft_filter(out, low=6000, high=80)


def ripe() -> np.ndarray:
    """Sparkle: a quick high arpeggio with shimmer."""
    out = np.zeros(secs(0.7))
    rng = np.random.default_rng(31)
    for i, m in enumerate([91, 95, 98, 103, 107]):
        n = secs(0.2)
        s = osc("sine", vibrato(np.full(n, midi(m)), 20, 0.25)) * perc(n, 0.002, 0.07)
        place(out, s, secs(0.045 * i), 0.5)
    for _ in range(6):
        n = secs(0.06)
        place(out, osc("sine", np.full(n, midi(rng.choice([100, 103, 107])))) * perc(n, 0.001, 0.02),
              secs(rng.uniform(0.2, 0.55)), 0.25)
    return fft_filter(out, low=10000, high=300)


def harvest_pop() -> np.ndarray:
    """A cork 'pop' out of the soil and a little ding."""
    out = np.zeros(secs(0.32))
    rng = np.random.default_rng(41)
    n = secs(0.02)
    place(out, fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=500) * perc(n, 0.0005, 0.006), 0, 0.7)
    n = secs(0.09)
    place(out, osc("sine", glide(n, [(0, 350), (0.09, 1100)])) * perc(n, 0.002, 0.04), secs(0.005))
    place(out, pluck(88, 0.2, "sine", 0.07, 0.2) * 0.5, secs(0.07))
    return fft_filter(out, low=8000, high=100)


def thump(rng: np.random.Generator, hz: float) -> np.ndarray:
    n = secs(0.14)
    body = osc("sine", glide(n, [(0, hz * 1.6), (0.14, hz)])) * perc(n, 0.001, 0.045)
    knock = fft_filter(osc("white", np.ones(n), rng=rng), low=1800, high=200) * perc(n, 0.001, 0.012)
    return body + 0.5 * knock


def trailer_tip() -> np.ndarray:
    """The trailer tilts (a creak) and crops tumble out (soft thuds)."""
    out = np.zeros(secs(1.0))
    rng = np.random.default_rng(51)
    n = secs(0.3)
    creak = osc("saw", vibrato(glide(n, [(0, 180), (0.3, 140)]), 40, 1.5)) * adsr(n, 0.03, 0.1, 0.6, 0.1)
    place(out, fft_filter(creak, low=1500, high=300), 0, 0.35)
    for i in range(7):
        place(out, thump(rng, rng.uniform(90, 160)), secs(0.25 + i * 0.09 + rng.uniform(0, 0.03)), rng.uniform(0.6, 1.0))
    return fft_filter(out, low=6000, high=50)


def crate() -> np.ndarray:
    """Wooden knock: a crop lands in its crate."""
    rng = np.random.default_rng(61)
    n = secs(0.2)
    s = 0.6 * osc("sine", np.full(n, 330.0)) * perc(n, 0.001, 0.05) + 0.3 * osc("sine", np.full(n, 740.0)) * perc(n, 0.001, 0.03)
    s += fft_filter(osc("white", np.ones(n), rng=rng), low=3000, high=600) * perc(n, 0.0005, 0.01) * 0.6
    return fft_filter(s, low=7000, high=120)


def quack() -> np.ndarray:
    """A nasal duck quack (saw through a moving band-pass, rough AM)."""
    n = secs(0.3)
    f = glide(n, [(0, 520), (0.05, 600), (0.3, 380)])
    t = np.arange(n) / SR
    s = osc("saw", f) * (1 + 0.4 * np.sin(2 * np.pi * 55 * t))
    s = fft_filter(s, low=1600, high=500, order=3)
    return s * adsr(n, 0.01, 0.06, 0.8, 0.08)


def ribbit() -> np.ndarray:
    """Two croaks: a buzzy low pulse train."""
    out = np.zeros(secs(0.5))
    for start, hz in [(0.0, 190), (0.2, 230)]:
        n = secs(0.16)
        t = np.arange(n) / SR
        s = osc("square", glide(n, [(0, hz), (0.16, hz * 0.85)]), duty=0.3) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 38 * t)))
        place(out, fft_filter(s * adsr(n, 0.005, 0.03, 0.8, 0.04), low=1400, high=120), secs(start))
    return out


def oink() -> np.ndarray:
    """A snorty oink: nasal square glide with grunt modulation."""
    out = np.zeros(secs(0.5))
    rng = np.random.default_rng(71)
    for start, dur, hz in [(0.0, 0.18, 330), (0.22, 0.22, 290)]:
        n = secs(dur)
        t = np.arange(n) / SR
        s = osc("square", glide(n, [(0, hz), (dur, hz * 0.8)]), duty=0.25) * (1 + 0.5 * np.sin(2 * np.pi * 30 * t))
        s += 0.3 * fft_filter(osc("white", np.ones(n), rng=rng), low=900, high=200)
        place(out, fft_filter(s * adsr(n, 0.01, 0.04, 0.8, 0.05), low=1800, high=150), secs(start))
    return out


def cluck() -> np.ndarray:
    """Hen: buk-buk-BAWK."""
    out = np.zeros(secs(0.6))
    for i, (start, dur, hz, g) in enumerate([(0.0, 0.06, 700, 0.7), (0.1, 0.06, 720, 0.7), (0.22, 0.2, 900, 1.0)]):
        n = secs(dur)
        f = glide(n, [(0, hz), (dur, hz * (0.75 if i < 2 else 0.8))])
        s = 0.6 * osc("square", f, duty=0.35) + 0.4 * osc("saw", f)
        place(out, fft_filter(s * adsr(n, 0.004, 0.02, 0.8, 0.02), low=2600, high=350), secs(start), g)
    return out


def bunny_boing() -> np.ndarray:
    """A small springy hop."""
    n = secs(0.35)
    f = glide(n, [(0, 300), (0.06, 520), (0.35, 600)])
    f = vibrato(f, 16, 3.0, decay=0.12)
    return fft_filter((0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * perc(n, 0.01, 0.12), low=4000, high=120)


def rainbow() -> np.ndarray:
    """Harp-like upward glissando over two octaves, then a held chord."""
    out = np.zeros(secs(2.2))
    scale = [60, 62, 64, 67, 69, 72, 74, 76, 79, 81, 84, 86, 88, 91]
    for i, m in enumerate(scale):
        place(out, pluck(m, 1.2, "triangle", 0.35, 0.35), secs(0.05 * i), 0.5)
    n = secs(1.4)
    chord = sum(osc("sine", vibrato(np.full(n, midi(m)), 5, 0.12)) for m in [72, 76, 79, 84])
    place(out, chord * adsr(n, 0.05, 0.3, 0.5, 0.8), secs(0.7), 0.18)
    return fft_filter(out, low=8000, high=100)


def giant_grow() -> np.ndarray:
    """A long rising swell (the giant vegetable), ending in sparkles."""
    n = secs(3.0)
    rng = np.random.default_rng(81)
    f = glide(n, [(0, 110), (2.4, 440), (3.0, 450)])
    pad = 0.4 * osc("saw", f) + 0.4 * osc("saw", f * 1.005) + 0.3 * osc("square", f * 1.5, duty=0.5)
    cutoff = glide(n, [(0, 300), (2.4, 4000), (3.0, 3000)])
    pad = onepole_sweep(pad, cutoff) * env_pts(n, [(0, 0), (0.4, 0.5), (2.3, 1.0), (3.0, 0)])
    out = pad * 0.8
    for _ in range(12):
        m = secs(0.08)
        place(out, osc("sine", np.full(m, midi(rng.choice([96, 100, 103, 108])))) * perc(m, 0.002, 0.03),
              secs(rng.uniform(2.1, 2.9)), 0.4)
    return fft_filter(out, low=8000, high=60)


def join() -> np.ndarray:
    return arp_notes([(67, 0.06), (71, 0.06), (74, 0.06), (79, 0.14)], kind="triangle", duty=0.5)


def select() -> np.ndarray:
    n = secs(0.06)
    e = perc(n, 0.001, 0.018)
    s = 0.6 * osc("triangle", np.full(n, midi(84))) + 0.4 * osc("square", np.full(n, midi(91)), duty=0.5)
    return fft_filter(s * e, low=5000, high=200)


def ready() -> np.ndarray:
    return arp_notes([(74, 0.08), (79, 0.22)], kind="square", duty=0.5, tail=0.18)


def arp_notes(notes: list[tuple[int, float]], kind: str = "square", duty: float = 0.25,
              tail: float = 0.15, low: float = 5000) -> np.ndarray:
    total = sum(d for _, d in notes) + tail
    out = np.zeros(secs(total))
    t = 0.0
    for i, (m, d) in enumerate(notes):
        last = i == len(notes) - 1
        n = secs(d + (tail if last else 0.02))
        f = np.full(n, midi(m))
        if last:
            f = vibrato(f, 7, 0.25, delay=0.06)
        e = adsr(n, 0.003, 0.04, 0.55, 0.1 if last else 0.02)
        s = 0.8 * osc(kind, f, duty=duty) + 0.2 * osc("sine", f * 2)
        place(out, s * e, secs(t))
        t += d
    return fft_filter(out, low=low, high=150)


# ----------------------------------------------------------------------------
# Loops: built in circular buffers, so the seam is inaudible
# ----------------------------------------------------------------------------


def engine_loop() -> np.ndarray:
    """Putt-putt: 12 low square pulses per second (the level raises the
    pitch with speed), a chuff of noise on each."""
    n = SR  # exactly 1 s
    buf = np.zeros(n)
    rng = np.random.default_rng(91)
    per = n // 12
    for k in range(12):
        m = secs(0.07)
        f = glide(m, [(0, 95), (0.07, 60)])
        pulse = osc("square", f, duty=0.3) * perc(m, 0.002, 0.025)
        chuff = fft_filter(osc("white", np.ones(m), rng=rng), low=900, high=150) * perc(m, 0.001, 0.015)
        place(buf, pulse * (0.9 if k % 2 == 0 else 0.7) + 0.4 * chuff, k * per, circular=True)
    return fft_filter(buf, low=1200, high=40, circular=True)


def plough_loop() -> np.ndarray:
    """Soft dirt crunch: band-limited noise with grainy crunches."""
    n = int(SR * 1.5)
    rng = np.random.default_rng(101)
    bed = fft_filter(osc("white", np.ones(n), rng=rng), low=1400, high=250, circular=True) * 0.25
    for _ in range(40):
        m = secs(0.05)
        g = fft_filter(osc("white", np.ones(m), rng=rng), low=2500, high=400) * perc(m, 0.002, 0.015)
        place(bed, g, int(rng.uniform(0, n)), rng.uniform(0.3, 0.8), circular=True)
    return fft_filter(bed, high=60, circular=True)


def rain_loop() -> np.ndarray:
    """Gentle rain: filtered hiss and scattered droplets."""
    n = SR * 2
    rng = np.random.default_rng(111)
    hiss = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=900, circular=True) * 0.3
    drops = droplets(n, 70, rng, circular=True)
    return fft_filter(hiss + drops, low=9000, high=200, circular=True)


# ----------------------------------------------------------------------------
# Music: every note is placed in a circular buffer (the loop has no seam).
# Onsets are rounded to samples, so any tempo works.
# ----------------------------------------------------------------------------

S = "-"  # sustain the previous note


def render_voice(total: int, pattern: list, step: float, make) -> np.ndarray:
    buf = np.zeros(total)
    flat = [x for bar in pattern for x in bar]
    i = 0
    while i < len(flat):
        m = flat[i]
        if m is None or m == S:
            i += 1
            continue
        j = i + 1
        while j < len(flat) and flat[j] == S:
            j += 1
        start = int(round(i * step))
        n = int(round((j - i) * step)) - secs(0.01)
        place(buf, make(m, n), start, circular=True)
        i = j
    return buf


def fiddle(m: int, n: int) -> np.ndarray:
    f = np.full(n, midi(m))
    if n > secs(0.25):
        f = vibrato(f, 5.5, 0.25, delay=0.12)
    s = 0.55 * osc("saw", f) + 0.25 * osc("saw", f * 1.004) + 0.2 * osc("square", f, duty=0.3)
    return s * adsr(n, 0.03, 0.1, 0.75, 0.06)


def banjo(m: int, n: int) -> np.ndarray:
    f = np.full(n, midi(m))
    return (0.7 * osc("triangle", f) + 0.3 * osc("square", f, duty=0.2)) * perc(n, 0.002, 0.12)


def bass_note(m: int, n: int) -> np.ndarray:
    f = np.full(n, midi(m))
    return osc("triangle", f) * adsr(n, 0.004, 0.08, 0.7, 0.04)


def square_lead(m: int, n: int) -> np.ndarray:
    f = np.full(n, midi(m))
    if n > secs(0.3):
        f = vibrato(f, 6, 0.2, delay=0.12)
    return osc("square", f, duty=0.25) * adsr(n, 0.004, 0.08, 0.6, 0.05)


def drum_track(total: int, bars: int, bar: float, pattern: str, seed: int, kick_g=0.8, snare_g=0.7, hat_g=0.15) -> np.ndarray:
    rng = np.random.default_rng(seed)
    buf = np.zeros(total)
    step = bar / len(pattern)
    kn = secs(0.16)
    kick = osc("sine", glide(kn, [(0, 130), (0.1, 50), (0.16, 45)])) * perc(kn, 0.002, 0.06)
    for b in range(bars):
        for k, ch in enumerate(pattern):
            pos = int(round(b * bar + k * step))
            if ch == "k":
                place(buf, kick, pos, kick_g, circular=True)
            elif ch == "s":
                n = secs(0.12)
                sn = fft_filter(osc("white", np.ones(n), rng=rng), low=5000, high=900) * perc(n, 0.001, 0.04)
                place(buf, sn, pos, snare_g * 0.5, circular=True)
            elif ch == "h":
                n = secs(0.05)
                hh = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.001, 0.012)
                place(buf, hh, pos, hat_g, circular=True)
    return fft_filter(buf, low=9000, circular=True)


# G major, 98 BPM (the plan's "relaxed 96": 98 gives whole-sample beats),
# 8 bars of 8ths: G C G D / G C D G. Fiddle lead, banjo-ish plucks, bass.
FARM_LEAD = [
    [74, S, 71, 74, 79, S, 78, 76], [76, S, 72, 76, 79, S, 76, 72],
    [71, S, 74, 79, 83, S, 81, 79], [78, S, 76, 74, 76, 78, 81, S],
    [83, S, 81, 79, 81, S, 79, 76], [76, S, 79, 76, 72, S, 76, 79],
    [78, 79, 81, 78, 74, S, 76, 78], [79, S, S, S, None, 74, 76, 78],
]
_FARM_ROOTS = [43, 48, 43, 50, 43, 48, 50, 43]
_FARM_TRIADS = {43: [55, 59, 62], 48: [60, 64, 67], 50: [62, 66, 69]}
FARM_BASS = [[r, None, r + 7, None, r + 12, None, r + 7, None] for r in _FARM_ROOTS]
FARM_PLUCK = [[_FARM_TRIADS[r][k % 3] + (12 if k % 4 == 3 else 0) for k in range(8)] for r in _FARM_ROOTS]


def music_farm() -> tuple[np.ndarray, float]:
    bpm, bars = 98, 8
    bar = 4 * 60.0 / bpm * SR
    total = int(round(bar * bars))
    step = bar / 8
    lead = fft_filter(render_voice(total, FARM_LEAD, step, fiddle), low=3200, high=200, circular=True)
    pl = fft_filter(render_voice(total, FARM_PLUCK, step, banjo), low=4000, circular=True)
    bass = fft_filter(render_voice(total, FARM_BASS, step, bass_note), low=1200, circular=True)
    drums = drum_track(total, bars, bar, "k-h-h-h-s-h-h-h-", 98, 0.7, 0.35, 0.12)
    mix = 0.42 * lead + 0.3 * pl + 0.7 * bass + drums
    return fft_filter(mix, high=30, circular=True), bar


# C major, 124 BPM, 8 bars: the fair's oompah (C F G C / C F G C).
FAIR_LEAD = [
    [72, 76, 79, S, 76, S, 72, S], [77, S, 81, S, 84, S, 81, S],
    [79, 77, 76, 74, 71, S, 74, S], [76, S, 72, S, 79, S, S, S],
    [84, S, 83, 81, 79, S, 76, S], [81, S, 77, 81, 84, S, 86, S],
    [84, 83, 81, 79, 77, 76, 74, 71], [72, S, 79, S, 84, S, None, None],
]
_FAIR_ROOTS = [48, 53, 55, 48, 48, 53, 55, 48]
FAIR_HARM = [[m - 5 if isinstance(m, int) else m for m in b] for b in FAIR_LEAD]
FAIR_BASS = [[r, None, r + 7 + 12, None, r + 7, None, r + 12 + 4, None] for r in _FAIR_ROOTS]


def music_fair() -> tuple[np.ndarray, float]:
    bpm, bars = 124, 8
    bar = 4 * 60.0 / bpm * SR
    total = int(round(bar * bars))
    step = bar / 8
    lead = fft_filter(render_voice(total, FAIR_LEAD, step, square_lead), low=4500, circular=True)
    harm = fft_filter(render_voice(total, FAIR_HARM, step, banjo), low=3000, circular=True)
    bass = fft_filter(render_voice(total, FAIR_BASS, step, bass_note), low=1400, circular=True)
    drums = drum_track(total, bars, bar, "k-h-s-h-k-h-s-hh", 124, 0.8, 0.6, 0.15)
    mix = 0.5 * lead + 0.18 * harm + 0.75 * bass + drums
    return fft_filter(mix, high=30, circular=True), bar


# ----------------------------------------------------------------------------
# Measurement, normalisation, output
# ----------------------------------------------------------------------------


def _biquad(x: np.ndarray, b: tuple, a: tuple) -> np.ndarray:
    b0, b1, b2 = b
    _, a1, a2 = a
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x.tolist()):
        yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def _rbj(kind: str, fc: float, q: float, gain_db: float, sr: int) -> tuple[tuple, tuple]:
    a_ = 10 ** (gain_db / 40)
    w0 = 2 * math.pi * fc / sr
    alpha = math.sin(w0) / (2 * q)
    c = math.cos(w0)
    if kind == "high_shelf":
        sa = 2 * math.sqrt(a_) * alpha
        b = (a_ * ((a_ + 1) + (a_ - 1) * c + sa), -2 * a_ * ((a_ - 1) + (a_ + 1) * c), a_ * ((a_ + 1) + (a_ - 1) * c - sa))
        a = ((a_ + 1) - (a_ - 1) * c + sa, 2 * ((a_ - 1) - (a_ + 1) * c), (a_ + 1) - (a_ - 1) * c - sa)
    else:  # high_pass
        b = ((1 + c) / 2, -(1 + c), (1 + c) / 2)
        a = (1 + alpha, -2 * c, 1 - alpha)
    return tuple(v / a[0] for v in b), tuple(v / a[0] for v in a)


def k_weight(x: np.ndarray, sr: int = SR) -> np.ndarray:
    y = _biquad(x, *_rbj("high_shelf", 1500.0, 1 / math.sqrt(2), 4.0, sr))
    return _biquad(y, *_rbj("high_pass", 38.0, 0.5, 0.0, sr))


def lufs(x: np.ndarray, loop: bool = False) -> tuple[float, float]:
    """(loudness over the clip, max short-term 3 s loudness). Ungated BS.1770."""
    y = k_weight(np.concatenate([x, x]) if loop else x)
    if loop:
        y = y[len(x):]  # second pass: the filters are settled, as when the loop repeats
    ms = y * y
    whole = -0.691 + 10 * math.log10(max(ms.mean(), 1e-12))
    w = secs(3.0)
    if len(ms) <= w:
        return whole, whole
    c = np.concatenate([[0.0], np.cumsum(ms)])
    hop = secs(0.1)
    st = [(c[i + w] - c[i]) / w for i in range(0, len(ms) - w + 1, hop)]
    return whole, -0.691 + 10 * math.log10(max(max(st), 1e-12))


def db(v: float) -> float:
    return 20 * math.log10(max(v, 1e-12))


def normalise(x: np.ndarray, target_lufs: float, loop: bool) -> np.ndarray:
    x = x - (x.mean() if loop else 0.0)
    loud, st = lufs(x, loop)
    ref = st if loop else loud
    x = x * 10 ** ((target_lufs - ref) / 20)
    ceiling = 10 ** (PEAK_DBFS / 20)
    peak = np.abs(x).max()
    if peak > ceiling:
        # Gentle soft-knee limiter for the few transients above the ceiling, then a hard safety trim.
        knee = ceiling * 0.7
        ax = np.abs(x)
        over = ax > knee
        span = ceiling - knee
        ax[over] = knee + span * np.tanh((ax[over] - knee) / span)
        x = np.sign(x) * ax
        x *= min(1.0, ceiling * 0.999 / np.abs(x).max())
    return x


def to_pcm(x: np.ndarray) -> np.ndarray:
    return np.clip(np.round(x * 32767), -32768, 32767).astype("<i2")


def write_wav(path: Path, pcm: np.ndarray) -> None:
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())


def fade_edges(x: np.ndarray) -> np.ndarray:
    x = x.copy()
    a, r = secs(0.002), secs(0.01)
    x[:a] *= np.linspace(0, 1, a)
    x[-r:] *= np.linspace(1, 0, r)
    return x


# ----------------------------------------------------------------------------
# Inspection images
# ----------------------------------------------------------------------------


FMAX = 8000  # spectrogram top frequency: keeps the pitch lines readable


def _colormap(v: np.ndarray) -> np.ndarray:
    stops = np.array([[0, 0, 0], [40, 10, 90], [170, 30, 120], [250, 130, 30], [255, 250, 190]], float)
    pos = np.linspace(0, 1, len(stops))
    return np.stack([np.interp(v, pos, stops[:, c]) for c in range(3)], -1).astype(np.uint8)


def spectrogram_png(name: str, x: np.ndarray, path: Path) -> None:
    from PIL import Image, ImageDraw

    nfft, hop = 1024, 128 if len(x) < SR * 2 else 512
    win = np.hanning(nfft)
    padded = np.concatenate([np.zeros(nfft // 2), x, np.zeros(nfft)])
    frames = [padded[i:i + nfft] * win for i in range(0, len(padded) - nfft, hop)]
    top_bin = int(FMAX / (SR / nfft))
    mag = np.abs(np.fft.rfft(np.array(frames), axis=1))[:, :top_bin] / (nfft / 4)
    dbv = 20 * np.log10(mag + 1e-9)
    v = np.clip((dbv + 90) / 90, 0, 1).T[::-1]  # rows: high frequencies on top
    img = Image.fromarray(_colormap(v)).resize((900, 360), Image.NEAREST)
    wave_h = 160
    canvas = Image.new("RGB", (900, 360 + wave_h + 20), (20, 20, 20))
    canvas.paste(img, (0, 20))
    d = ImageDraw.Draw(canvas)
    d.text((4, 4), f"{name}  0-{FMAX} Hz  {len(x) / SR:.2f}s  peak {db(np.abs(x).max()):.1f} dBFS  "
                   f"DC {x.mean():+.5f}", fill=(230, 230, 230))
    top = 380
    mid = top + wave_h // 2
    ceil = 10 ** (PEAK_DBFS / 20)
    for lvl, col in [(1.0, (200, 40, 40)), (ceil, (200, 160, 40))]:
        for s in (-1, 1):
            yy = mid - s * lvl * (wave_h / 2 - 2)
            d.line([(0, yy), (899, yy)], fill=col)
    d.line([(0, mid), (899, mid)], fill=(70, 70, 70))
    cols = np.array_split(x, 900)
    for i, c in enumerate(cols):
        if len(c):
            d.line([(i, mid - c.max() * (wave_h / 2 - 2)), (i, mid - c.min() * (wave_h / 2 - 2))], fill=(120, 220, 140))
    canvas.save(path)


def seam_png(name: str, x: np.ndarray, path: Path) -> None:
    """The last 600 and first 600 samples side by side: the loop point is the centre line."""
    from PIL import Image, ImageDraw

    k = 600
    seg = np.concatenate([x[-k:], x[:k]])
    h = 300
    img = Image.new("RGB", (len(seg), h + 20), (20, 20, 20))
    d = ImageDraw.Draw(img)
    d.text((4, 4), f"{name} loop seam (end | start)", fill=(230, 230, 230))
    scale = (h / 2 - 4) / max(np.abs(seg).max(), 1e-6)
    pts = [(i, 20 + h / 2 - v * scale) for i, v in enumerate(seg)]
    d.line([(k, 20), (k, 20 + h)], fill=(200, 60, 60))
    d.line(pts, fill=(120, 220, 140))
    img.save(path)



# ----------------------------------------------------------------------------


SFX = {
    "horn": horn, "plant": plant, "rain_start": rain_start,
    "seed_pick_1": lambda: seed_pick(0), "seed_pick_2": lambda: seed_pick(1),
    "seed_pick_3": lambda: seed_pick(2), "seed_pick_4": lambda: seed_pick(3),
    "grow_1": lambda: grow(1), "grow_2": lambda: grow(2), "grow_3": lambda: grow(3),
    "ripe": ripe, "harvest_pop": harvest_pop, "trailer_tip": trailer_tip, "crate": crate,
    "quack": quack, "ribbit": ribbit, "oink": oink, "cluck": cluck, "bunny_boing": bunny_boing,
    "rainbow": rainbow, "giant_grow": giant_grow, "join": join, "select": select, "ready": ready,
}
LOOPS = {"engine_loop": engine_loop, "plough": plough_loop, "rain_loop": rain_loop}
MUSIC = {"music_farm": music_farm, "music_fair": music_fair}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", type=Path, help="write spectrogram/seam PNGs to this directory")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.check:
        args.check.mkdir(parents=True, exist_ok=True)

    ok = True
    total_bytes = 0
    print(f"{'file':<16}{'secs':>7}{'peak dBFS':>11}{'RMS dBFS':>10}{'LUFS':>8}{'ST max':>8}{'DC':>10}")
    rows = ([(n, f, "sfx") for n, f in SFX.items()] + [(n, f, "loop") for n, f in LOOPS.items()]
            + [(n, f, "music") for n, f in MUSIC.items()])
    for name, fn, kind in rows:
        loop = kind != "sfx"
        bar_len = None
        if kind == "music":
            x, bar_len = fn()
            x = normalise(x, MUSIC_LUFS, loop=True)
        elif kind == "loop":
            x = normalise(fn(), LOOP_LUFS, loop=True)
        else:
            x = normalise(fade_edges(fn()), SFX_LUFS, loop=False)
            x = fade_edges(x)
        pcm = to_pcm(x)
        path = OUT / f"{name}.wav"
        write_wav(path, pcm)
        total_bytes += path.stat().st_size
        y = pcm.astype(np.float64) / 32768.0
        peak = np.abs(y).max()
        loud, st = lufs(y, loop)
        print(f"{name:<16}{len(y) / SR:>7.2f}{db(peak):>11.2f}{db(np.sqrt((y * y).mean())):>10.2f}"
              f"{loud:>8.1f}{st:>8.1f}{y.mean():>10.5f}")
        if db(peak) > PEAK_DBFS + 0.01:
            ok = False
            print(f"  FAIL: {name} peaks above {PEAK_DBFS} dBFS")
        if loop:
            step = np.abs(np.diff(y))
            seam = abs(y[0] - y[-1])
            p99 = np.percentile(step, 99)
            good = seam <= p99
            if bar_len:
                bars = len(y) / bar_len
                good = good and abs(bars - round(bars)) < 1e-3
                print(f"  loop: {len(y)} samples = {bars:.3f} bars", end="; ")
            else:
                print("  loop:", end=" ")
            ok &= good
            print(f"seam jump {seam:.5f} vs p99 step {p99:.5f} -> {'OK' if good else 'FAIL'}")
        elif abs(y[0]) > 1e-3 or abs(y[-1]) > 1e-3:
            ok = False
            print(f"  FAIL: {name} does not start/end at zero")
        if args.check:
            spectrogram_png(name, y, args.check / f"{name}.png")
            if loop:
                seam_png(name, y, args.check / f"{name}_seam.png")
    print(f"total {total_bytes / 1e6:.2f} MB in {OUT.relative_to(ROOT)}")
    if total_bytes > 8e6:
        ok = False
        print("FAIL: audio total above 8 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
