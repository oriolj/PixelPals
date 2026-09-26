"""Submarine Safari sound synth: every sound and both music loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR]

PixelPals's small synth (oscillators with polyBLEP, envelopes, glides,
vibrato, zero-phase filters, loudness normalisation and the inspection
images), with this game's sounds: the sub's hum loop, sonar, shutter, one
4-note marimba motif per species (so the album page "plays"), the lights'
glass tones, bubbles, the whale's song, and two calm loops (music_reef at
80 bpm, music_album at 96 bpm). Seeded: reruns write identical files.
Output: game/audio/<name>.wav, 16-bit mono 44100 Hz.
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
# Sound effects
# ----------------------------------------------------------------------------


def marimba(m: float, dur: float = 0.5, bright: float = 1.0) -> np.ndarray:
    """A soft wooden pluck: fundamental + the 4th partial that makes it a marimba."""
    n = secs(dur)
    f = midi(m)
    s = osc("sine", np.full(n, f)) * perc(n, 0.002, dur * 0.45)
    s += 0.35 * bright * osc("sine", np.full(n, f * 4.0)) * perc(n, 0.001, 0.045)
    s += 0.12 * bright * osc("sine", np.full(n, f * 9.9)) * perc(n, 0.001, 0.012)
    return s


def glass(m: float, dur: float = 0.9) -> np.ndarray:
    """A glassy bell: sine plus an inharmonic partial, slow shimmer."""
    n = secs(dur)
    f = vibrato(np.full(n, midi(m)), 5.5, 0.08)
    s = osc("sine", f) * perc(n, 0.01, dur * 0.4)
    s += 0.3 * osc("sine", f * 2.76) * perc(n, 0.004, dur * 0.15)
    s += 0.12 * osc("sine", f * 5.4) * perc(n, 0.002, 0.05)
    return s


def notes(seq: list[tuple[float, float]], step: float, ring: float = 0.6, fn=marimba) -> np.ndarray:
    total = step * len(seq) + ring
    out = np.zeros(secs(total))
    for i, (m, g) in enumerate(seq):
        last = i == len(seq) - 1
        place(out, fn(m, ring if last else step * 2.5), secs(i * step), g)
    return fft_filter(out, low=7000, high=90)


# One 4-note motif per species (album page order), F major pentatonic.
MOTIFS = [
    [72, 76, 79, 84],   # clownfish: up we go
    [79, 76, 74, 72],   # blue tang
    [72, 72, 79, 79],   # pufferfish: puff, puff
    [67, 69, 72, 74],   # turtle: slow and steady
    [84, 81, 79, 81],   # seahorse
    [74, 72, 74, 72],   # crab: scuttle scuttle
    [76, 79, 81, 79],   # octopus
    [69, 72, 76, 81],   # eel: peeking out
    [84, 79, 84, 88],   # jellyfish
    [67, 72, 67, 76],   # anglerfish
    [81, 84, 88, 84],   # squid
    [88, 84, 81, 79],   # lantern fish
]


def species_motif(i: int):
    def make() -> np.ndarray:
        m = MOTIFS[i]
        step = 0.2 if i == 3 else 0.13
        seq = [(n, 1.0 if k == 3 else 0.8) for k, n in enumerate(m)]
        out = notes(seq, step, ring=0.7)
        # a sparkle on top of the last note
        n = secs(0.3)
        place(out, 0.25 * osc("sine", np.full(n, midi(m[-1] + 24))) * perc(n, 0.002, 0.06), secs(step * 3 + 0.03))
        return out
    return make


def repeat_star() -> np.ndarray:
    out = notes([(88, 0.8), (93, 1.0)], 0.07, ring=0.4)
    return out


def lights_tone(i: int):
    roots = [79, 81, 84, 86]

    def make() -> np.ndarray:
        r = roots[i]
        out = np.zeros(secs(1.1))
        for k, iv in enumerate([0, 4, 7, 12]):
            place(out, glass(r + iv, 0.9 - k * 0.1), secs(k * 0.045), 0.6)
        return fft_filter(out, low=8000, high=200)
    return make


def disco() -> np.ndarray:
    out = np.zeros(secs(1.2))
    run = [72, 76, 79, 84, 88, 91, 96, 91, 88, 84, 88, 96]
    for i, m in enumerate(run):
        place(out, glass(m, 0.35), secs(i * 0.055), 0.5)
    rng = np.random.default_rng(12)
    for _ in range(10):
        n = secs(0.07)
        s = osc("sine", np.full(n, midi(rng.choice([96, 100, 103, 108])))) * perc(n, 0.002, 0.02)
        place(out, s, secs(rng.uniform(0.1, 1.0)), 0.3)
    return fft_filter(out, low=9000, high=150)


def bubble(i: int):
    def make() -> np.ndarray:
        out = np.zeros(secs(0.35))
        starts = [(0.0, 380, 1.0)] if i < 2 else [(0.0, 320, 1.0), (0.11, 520, 0.7)]
        base = [1.0, 1.3, 1.0][i]
        for st, f0, g in starts:
            n = secs(0.09)
            f = glide(n, [(0, f0 * base), (0.07, f0 * base * 3.2), (0.09, f0 * base * 3.4)])
            place(out, osc("sine", f) * perc(n, 0.002, 0.035), secs(st), g)
        return fft_filter(out, low=5000, high=150)
    return make


def sonar() -> np.ndarray:
    """The classic ping: a pure tone with a long tail and a soft echo."""
    out = np.zeros(secs(1.8))
    n = secs(1.2)
    f = vibrato(np.full(n, 1150.0), 4.0, 0.05)
    ping = osc("sine", f) * perc(n, 0.004, 0.32) + 0.2 * osc("sine", f * 2) * perc(n, 0.002, 0.05)
    place(out, ping, 0, 1.0)
    place(out, fft_filter(ping, low=1800), secs(0.45), 0.3)
    place(out, fft_filter(ping, low=1400), secs(0.9), 0.12)
    return fft_filter(out, high=200)


def shutter() -> np.ndarray:
    """Click-clack of a camera: two noise clicks and a little mechanical chk."""
    out = np.zeros(secs(0.22))
    rng = np.random.default_rng(21)
    for st, g in ((0.0, 1.0), (0.075, 0.7)):
        n = secs(0.012)
        click = fft_filter(osc("white", np.ones(n), rng=rng), high=2500) * perc(n, 0.0005, 0.003)
        place(out, click, secs(st), g)
    n = secs(0.03)
    chk = osc("square", np.full(n, 190.0), duty=0.3) * perc(n, 0.001, 0.008)
    place(out, fft_filter(chk, low=2500), secs(0.01), 0.5)
    n = secs(0.09)
    swish = fft_filter(osc("white", np.ones(n), rng=rng), low=7000, high=3000) * perc(n, 0.003, 0.025)
    place(out, swish, secs(0.02), 0.25)
    return out


def propeller() -> np.ndarray:
    out = np.zeros(secs(0.22))
    for i in range(3):
        n = secs(0.035)
        f = glide(n, [(0, 240 - i * 15), (0.035, 170 - i * 15)])
        place(out, osc("triangle", f) * perc(n, 0.002, 0.012), secs(i * 0.05), 1.0 - i * 0.2)
    return fft_filter(out, low=2000, high=80)


def boing() -> np.ndarray:
    """A springy, friendly BOING for a rock bump."""
    n = secs(0.55)
    f = glide(n, [(0, 110), (0.05, 190), (0.55, 240)])
    f = vibrato(f, 13, 4.0, decay=0.18)
    e = perc(n, 0.015, 0.18)
    s = 0.7 * osc("triangle", f) + 0.3 * osc("square", f, duty=0.5)
    return fft_filter(s * e, low=1800, high=60)


def whale_song() -> np.ndarray:
    """Slow, deep sine glides: the big friend says hello."""
    out = np.zeros(secs(3.2))
    for st, pts, g in (
        (0.0, [(0, 180), (0.5, 300), (1.1, 260), (1.5, 210)], 1.0),
        (1.6, [(0, 240), (0.6, 170), (1.4, 200)], 0.8),
    ):
        dur = pts[-1][0]
        n = secs(dur)
        f = vibrato(glide(n, pts), 4.5, 0.25, delay=0.2)
        e = adsr(n, 0.25, 0.2, 0.8, 0.5)
        s = osc("sine", f) + 0.3 * osc("sine", f * 2.0) + 0.1 * osc("triangle", f * 3.0)
        place(out, fft_filter(s * e, low=1600), secs(st), g)
    return fft_filter(out, high=60)


def eel_peek() -> np.ndarray:
    out = np.zeros(secs(0.35))
    for st, a, b, g in ((0.0, 380, 900, 1.0), (0.15, 600, 1200, 0.6)):
        n = secs(0.12)
        f = glide(n, [(0, a), (0.1, b), (0.12, b * 0.95)])
        place(out, osc("sine", f) * perc(n, 0.004, 0.05), secs(st), g)
    return fft_filter(out, low=4000, high=120)


def puff() -> np.ndarray:
    """The pufferfish inflates: a rising whoosh and a little pop."""
    n = secs(0.4)
    rng = np.random.default_rng(31)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 300), (0.35, 3000), (0.4, 3000)])
    air = onepole_sweep(noise, cutoff) * env_pts(n, [(0, 0), (0.3, 1), (0.4, 0)])
    f = glide(n, [(0, 180), (0.35, 520), (0.4, 540)])
    body = osc("sine", f) * env_pts(n, [(0, 0), (0.1, 0.6), (0.35, 0.8), (0.4, 0)])
    out = np.zeros(secs(0.5))
    place(out, 0.6 * air + body, 0)
    m = secs(0.06)
    place(out, osc("sine", glide(m, [(0, 900), (0.06, 1400)])) * perc(m, 0.001, 0.02), secs(0.38), 0.6)
    return fft_filter(out, high=100)


def surface() -> np.ndarray:
    """Splash through the surface, then two seagull-ish chirps."""
    out = np.zeros(secs(1.2))
    rng = np.random.default_rng(41)
    n = secs(0.5)
    splash = fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=300) * perc(n, 0.004, 0.13)
    place(out, splash, 0, 1.0)
    for st in (0.45, 0.7):
        n = secs(0.2)
        f = vibrato(glide(n, [(0, 1500), (0.05, 1900), (0.2, 1300)]), 18, 0.6)
        s = (0.6 * osc("saw", f) + 0.4 * osc("square", f, duty=0.3)) * adsr(n, 0.01, 0.05, 0.6, 0.08)
        place(out, fft_filter(s, low=4000, high=600), secs(st), 0.35)
    return out


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


def join() -> np.ndarray:
    return arp_notes([(72, 0.06), (76, 0.06), (79, 0.06), (84, 0.12)])


def select() -> np.ndarray:
    n = secs(0.06)
    e = perc(n, 0.001, 0.018)
    s = 0.6 * osc("triangle", np.full(n, midi(84))) + 0.4 * osc("square", np.full(n, midi(91)), duty=0.5)
    return fft_filter(s * e, low=5000, high=200)


def ready() -> np.ndarray:
    return arp_notes([(79, 0.08), (84, 0.22)], kind="square", duty=0.5, tail=0.18)

def whoosh() -> np.ndarray:
    """Soft air swoosh: noise through a low-pass that sweeps up and back down."""
    n = secs(0.55)
    rng = np.random.default_rng(88)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 250), (0.25, 2800), (0.55, 350)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.22, 1), (0.55, 0)]) ** 1.5
    return fft_filter(y * e, high=120)



# ----------------------------------------------------------------------------
# Loops: rendered into a circular buffer, so the loop has no seam
# ----------------------------------------------------------------------------


def sub_hum_loop() -> tuple[np.ndarray, int]:
    """4 s of low engine hum; every component has a whole number of cycles in the loop."""
    n = secs(4.0)
    t = np.arange(n) / SR
    lfo = 1.0 + 0.25 * np.sin(2 * np.pi * 0.5 * t)
    x = (np.sin(2 * np.pi * 55 * t) + 0.45 * np.sin(2 * np.pi * 110 * t)
         + 0.15 * np.sin(2 * np.pi * 165 * t)) * lfo
    rng = np.random.default_rng(51)
    x += 0.2 * fft_filter(rng.uniform(-1, 1, n), low=300, high=60, circular=True)
    return x, n


def render_calm(bpm: float, chords: list[list[int]], bass: list[list[tuple[int, int]]],
                melody: list[dict[int, int]], seed: int, shaker: float, bubbles: bool,
                pad_low: float) -> tuple[np.ndarray, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    bars = len(chords)
    total = bar_len * bars
    eighth = bar_len // 8
    rng = np.random.default_rng(seed)
    pad = np.zeros(total)
    for b, chord in enumerate(chords):
        n = bar_len + secs(0.6)
        e = adsr(n, 0.5, 0.3, 0.8, 0.6)
        for m in chord:
            for det in (-0.06, 0.06):
                s = osc("saw", vibrato(np.full(n, midi(m + det)), 0.3 + rng.uniform(0, 0.2), 0.05))
                place(pad, s * e, b * bar_len, 0.12, circular=True)
    pad = fft_filter(pad, low=pad_low, circular=True)
    low = np.zeros(total)
    for b, notes_ in enumerate(bass):
        for step, m in notes_:
            n = secs(0.9)
            s = osc("triangle", np.full(n, midi(m))) * perc(n, 0.004, 0.35)
            s += 0.3 * osc("sine", np.full(n, midi(m + 12))) * perc(n, 0.002, 0.1)
            place(low, s, b * bar_len + step * eighth, 0.7, circular=True)
    low = fft_filter(low, low=1200, circular=True)
    mel = np.zeros(total)
    for b, bar in enumerate(melody):
        for step, m in bar.items():
            place(mel, marimba(m, 0.9), b * bar_len + step * eighth, 0.45, circular=True)
    mel = fft_filter(mel, low=6000, circular=True)
    perc_buf = np.zeros(total)
    for b in range(bars):
        for k in range(8):
            if k % 2 == 1:
                n = secs(0.05)
                sh = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.004, 0.015)
                place(perc_buf, sh, b * bar_len + k * eighth, shaker, circular=True)
        if bubbles and b % 2 == 1:
            n = secs(0.09)
            f = glide(n, [(0, 400), (0.08, 1300), (0.09, 1350)])
            place(perc_buf, osc("sine", f) * perc(n, 0.002, 0.03), b * bar_len + 5 * eighth + eighth // 2,
                  0.15, circular=True)
    mix = pad + low + mel + perc_buf
    return fft_filter(mix, high=35, circular=True), bar_len


# F major, 80 bpm, 8 bars: Fmaj7 Dm7 Bbmaj7 Csus4 x2. Calm pads, plucked bass,
# a sparse marimba and soft bubbles.
REEF_CHORDS = [[65, 69, 72, 76], [62, 65, 69, 72], [58, 62, 65, 69], [60, 65, 67, 72]] * 2
REEF_BASS = [[(0, r), (4, r + 7)] for r in (41, 38, 46, 48, 41, 38, 46, 48)]
REEF_MELODY = [
    {0: 77, 3: 81, 6: 84}, {2: 81, 4: 77}, {0: 74, 3: 77, 5: 81}, {4: 79},
    {0: 77, 2: 81, 4: 84, 6: 86}, {1: 84, 4: 81}, {0: 81, 3: 77, 6: 74}, {0: 79, 4: 77},
]

# C major, 96 bpm, 8 bars: C Am F G x2. The album: brighter, a little bouncy.
ALBUM_CHORDS = [[60, 64, 67], [57, 60, 64], [53, 57, 60], [55, 59, 62]] * 2
ALBUM_BASS = [[(0, r), (3, r + 7), (4, r + 12), (6, r + 7)] for r in (48, 45, 41, 43, 48, 45, 41, 43)]
ALBUM_MELODY = [
    {0: 76, 2: 79, 4: 84, 6: 79}, {0: 81, 2: 76, 4: 72}, {0: 77, 2: 81, 4: 84, 5: 81}, {0: 79, 4: 74, 6: 79},
    {0: 84, 2: 79, 3: 81, 4: 84}, {0: 88, 2: 84, 4: 81}, {0: 81, 1: 79, 2: 77, 4: 81}, {0: 79, 2: 74, 4: 72},
]


def music_reef() -> tuple[np.ndarray, int]:
    return render_calm(80, REEF_CHORDS, REEF_BASS, REEF_MELODY, 80, 0.05, True, 1300)


def music_album() -> tuple[np.ndarray, int]:
    return render_calm(96, ALBUM_CHORDS, ALBUM_BASS, ALBUM_MELODY, 96, 0.08, False, 2200)


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
    "sonar": sonar, "shutter": shutter, "propeller": propeller, "boing": boing,
    "repeat_star": repeat_star, "disco": disco, "whale_song": whale_song, "eel_peek": eel_peek,
    "puff": puff, "surface": surface, "join": join, "select": select, "ready": ready, "whoosh": whoosh,
}
for _i in range(12):
    SFX[f"new_species_{_i + 1}"] = species_motif(_i)
for _i in range(4):
    SFX[f"lights_{_i + 1}"] = lights_tone(_i)
for _i in range(3):
    SFX[f"bubble_{_i + 1}"] = bubble(_i)
MUSIC = {"music_reef": music_reef, "music_album": music_album, "sub_hum_loop": sub_hum_loop}
MAX_BYTES = 8e6


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
    rows = [(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in MUSIC.items()]
    for name, fn, loop in rows:
        if loop:
            x, bar_len = fn()
            x = normalise(x, MUSIC_LUFS, loop=True)
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
            bars = len(y) / bar_len
            step = np.abs(np.diff(y))
            seam = abs(y[0] - y[-1])
            p99 = np.percentile(step, 99)
            good = bars == int(bars) and seam <= p99
            ok &= good
            print(f"  loop: {len(y)} samples = {bars:g} bars x {bar_len}; seam jump {seam:.5f} "
                  f"vs p99 step {p99:.5f} -> {'OK' if good else 'FAIL'}")
        elif abs(y[0]) > 1e-3 or abs(y[-1]) > 1e-3:
            ok = False
            print(f"  FAIL: {name} does not start/end at zero")
        if args.check:
            spectrogram_png(name, y, args.check / f"{name}.png")
            if loop:
                seam_png(name, y, args.check / f"{name}_seam.png")
    for stale in OUT.glob("*.wav"):
        if stale.stem not in SFX and stale.stem not in MUSIC:
            print(f"removing stale {stale.name}")
            stale.unlink()
    print(f"total {total_bytes / 1e6:.2f} MB in {OUT.relative_to(ROOT)}")
    if total_bytes > MAX_BYTES:
        ok = False
        print(f"FAIL: audio total above {MAX_BYTES / 1e6:.0f} MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
