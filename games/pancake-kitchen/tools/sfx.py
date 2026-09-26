"""Pancake Kitchen sound synth: every sound, the sizzle loop and both music loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR]

A small numpy synth (sine/triangle/saw/square/noise oscillators with polyBLEP,
ADSR envelopes, pitch slides by breakpoints, vibrato, zero-phase low/high-pass
filters), plus a mallet model (sine + a strong fast-decaying inharmonic
partial + a click: 3.93x = xylophone, 4x = marimba) and a small cartoon
formant voice (a glottal sawtooth with vibrato through three gliding resonant
formants, with a closed-mouth hum for 'm'/'n') for the customers' yums,
giggle, cheer, woof and mew. Everything is seeded, so a rerun writes
byte-identical files. Output: game/audio/<name>.wav, 16-bit mono 44100 Hz.
The audience is 2 and 5 years old: everything is soft, round and low-passed.

Loudness: SFX are normalised to about -15 LUFS (whole clip, K-weighted,
BS.1770 without gating), the sizzle loop to SIZZLE_LUFS (it plays under the
music) and the music to MUSIC_LUFS; no file peaks above -1 dBFS.
Loops (sizzle, music_menu at 90 BPM, music_kitchen at 96 BPM with swung 8ths)
are rendered into circular buffers, so the seam is continuous.
The report printed at the end is the verification: peak, RMS, LUFS, length,
and for the loops the bar count and the loop-seam continuity.
With --check DIR it also writes spectrogram + waveform (+ seam) PNGs to DIR.
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
# The sizzle loops under the music while a pancake cooks, so it stays well below everything.
SIZZLE_LUFS = -24.0

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

def resonator(x: np.ndarray, freq: np.ndarray | float, bw: np.ndarray | float) -> np.ndarray:
    """Two-pole resonant band-pass with a time-varying centre, unity gain at resonance (a formant)."""
    n = len(x)
    f = np.broadcast_to(np.asarray(freq, dtype=np.float64), (n,))
    b = np.broadcast_to(np.asarray(bw, dtype=np.float64), (n,))
    r = np.exp(-np.pi * b / SR)
    th = 2 * np.pi * f / SR
    a1 = (-2 * r * np.cos(th)).tolist()
    a2 = (r * r).tolist()
    g = ((1 - r) * np.sqrt(1 - 2 * r * np.cos(2 * th) + r * r)).tolist()
    y = np.empty(n)
    y1 = y2 = 0.0
    for i, xi in enumerate(x.tolist()):
        yi = g[i] * xi - a1[i] * y1 - a2[i] * y2
        y2, y1 = y1, yi
        y[i] = yi
    return y


def xylo(freq: float, n: int, decay: float = 0.28, partial: float = 3.93, bright: float = 0.45,
         click: float = 0.12, rng: np.random.Generator | None = None) -> np.ndarray:
    """Mallet bar: a sine, a strong fast-decaying inharmonic partial and a short mallet click.
    partial 3.93 = xylophone, 4.0 with a longer decay = marimba."""
    t = np.arange(n) / SR
    body = np.sin(2 * np.pi * freq * t) * np.exp(-t / decay)
    over = bright * np.sin(2 * np.pi * freq * partial * t) * np.exp(-t / (decay * 0.1))
    s = (body + over) * np.minimum(t / 0.0008, 1.0)
    if click and rng is not None:
        k = min(n, secs(0.004))
        s[:k] += click * fft_filter(rng.uniform(-1, 1, k), low=3500) * np.linspace(1, 0, k)
    fade = min(n, secs(0.006))
    s[n - fade:] *= np.linspace(1, 0, fade)
    return s


def marimba(freq: float, n: int, rng: np.random.Generator | None = None) -> np.ndarray:
    return xylo(freq, n, decay=0.45, partial=4.0, bright=0.28, click=0.06, rng=rng)


# ----------------------------------------------------------------------------
# The cartoon voice: a glottal source through three gliding formants
# ----------------------------------------------------------------------------

# (F1, F2, F3) in Hz for a small, bright cartoon voice.
VOWELS = {
    "a": (1000.0, 1600.0, 3000.0), "i": (380.0, 2900.0, 3600.0), "u": (420.0, 1000.0, 2600.0),
    "o": (620.0, 1050.0, 2700.0), "e": (650.0, 2300.0, 3100.0),
}
FORMANT_BW = (90.0, 140.0, 220.0)
FORMANT_AMP = (1.0, 0.55, 0.28)


def voice(dur: float, f0_pts: list, vowel_pts: list, open_pts: list | None = None,
          amp_pts: list | None = None, breath: float = 0.04, scale: float = 1.0,
          vib: tuple[float, float] = (6.0, 0.35), rough: float = 0.0, breath_pts: list | None = None,
          seed: int = 0) -> np.ndarray:
    """One voiced utterance.

    f0_pts: (t, hz) pitch breakpoints; vowel_pts: (t, vowel) targets the formants glide between;
    open_pts: (t, 0..1) mouth opening, 0 = closed-mouth hum (the 'm' and 'n'); amp_pts: (t, gain)
    loudness; breath_pts: (t, gain) extra breath noise (an 'h'); rough: throat rasp depth."""
    n = secs(dur)
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    f0 = vibrato(glide(n, f0_pts), vib[0], vib[1], delay=0.04)
    src = fft_filter(osc("saw", f0), low=3000, order=1)  # soft glottal tilt
    if rough:
        src *= 1.0 + rough * np.sin(2 * np.pi * 43 * t)
    br = breath * np.ones(n)
    if breath_pts:
        br = br + env_pts(n, breath_pts)
    exc = src + fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=300) * br
    vt = [p[0] for p in vowel_pts]
    out = np.zeros(n)
    for k in range(3):
        fk = np.interp(t, vt, [VOWELS[p[1]][k] * scale for p in vowel_pts])
        out += FORMANT_AMP[k] * resonator(exc, fk, FORMANT_BW[k] * scale)
    out *= 2.2  # the formants pass only a slice of the source; bring them level with the hum
    if open_pts:
        o = env_pts(n, open_pts)
        hum = fft_filter(src, low=450, order=2) * 0.8
        out = o * out + (1 - o) * hum
    env = env_pts(n, amp_pts) if amp_pts else adsr(n, 0.02, 0.1, 0.8, 0.12)
    return fft_filter(out * env, low=5000, high=90)


# ----------------------------------------------------------------------------
# Sound effects
# ----------------------------------------------------------------------------


def pour() -> np.ndarray:
    """Batter pouring: a thick, low noise stream that glides down, with a few gloopy bubbles."""
    dur = 0.9
    n = secs(dur)
    rng = np.random.default_rng(101)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 1600), (0.3, 1100), (dur, 600)])
    stream = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    t = np.arange(n) / SR
    stream *= 1.0 + 0.25 * np.sin(2 * np.pi * 7 * t + 1.3 * np.sin(2 * np.pi * 3 * t))  # wobble
    out = stream * env_pts(n, [(0, 0), (0.08, 1), (0.6, 0.85), (dur, 0)])
    for i in range(6):  # gloops
        start = 0.12 + 0.11 * i + rng.uniform(-0.02, 0.02)
        m = secs(0.06)
        f = glide(m, [(0, rng.uniform(170, 260)), (0.06, rng.uniform(320, 420))])
        place(out, osc("sine", f) * perc(m, 0.004, 0.02), secs(start), 0.25)
    return fft_filter(out, low=2500, high=120)


def sizzle() -> tuple[np.ndarray, int]:
    """Quiet frying loop (2 s, rendered circularly): band-passed noise with a slow swell and
    tiny crackles. Returned like a music loop so the seam is checked."""
    n = secs(2.0)
    rng = np.random.default_rng(102)
    bed = fft_filter(rng.uniform(-1, 1, n), low=4200, high=1400, order=2, circular=True)
    t = np.arange(n) / SR
    bed *= 0.8 + 0.12 * np.sin(2 * np.pi * 1.0 * t) + 0.08 * np.sin(2 * np.pi * 3.0 * t + 0.7)
    buf = bed * 0.5
    for _ in range(70):  # crackles
        k = secs(rng.uniform(0.002, 0.005))
        c = rng.uniform(-1, 1, k) * np.exp(-np.arange(k) / (k / 4))
        place(buf, c, int(rng.integers(0, n)), rng.uniform(0.3, 0.9), circular=True)
    return fft_filter(buf, low=5500, high=500, circular=True), n


def boing(pts: list, dur: float, rate: float, semis: float, tri: float) -> np.ndarray:
    """The flip: a pitch-bent sine/triangle spring whose wobble (pitch and level) dies away."""
    n = secs(dur)
    t = np.arange(n) / SR
    wob_decay = dur * 0.35
    f = vibrato(glide(n, pts), rate, semis, decay=wob_decay)
    e = perc(n, 0.006, dur * 0.38) * (1.0 + 0.3 * np.sin(2 * np.pi * rate * t) * np.exp(-t / wob_decay))
    s = (1 - tri) * osc("sine", f) + tri * osc("triangle", f) + 0.18 * osc("sine", f * 2) * np.exp(-t / 0.08)
    return fft_filter(s * e, low=2400, high=60)


def boing_1() -> np.ndarray:  # low, bouncy "bwoing"
    return boing([(0, 150), (0.05, 290), (0.55, 320)], 0.55, 11, 3.0, 0.35)


def boing_2() -> np.ndarray:  # mid "boing"
    return boing([(0, 230), (0.045, 420), (0.5, 470)], 0.5, 14, 2.5, 0.5)


def boing_3() -> np.ndarray:  # small, high "boink"
    return boing([(0, 330), (0.035, 620), (0.42, 580)], 0.42, 17, 2.0, 0.15)


def boing_4() -> np.ndarray:  # down-then-up "bwoi-oi-oing"
    return boing([(0, 480), (0.07, 250), (0.25, 390), (0.6, 440)], 0.6, 12, 3.5, 0.4)


def spin() -> np.ndarray:
    """A rising slide whistle."""
    dur = 0.45
    n = secs(dur)
    f = vibrato(glide(n, [(0, 560), (0.38, 1600), (dur, 1680)]), 7, 0.4, delay=0.08)
    whistle = 0.85 * osc("sine", f) + 0.15 * osc("triangle", f)
    breath = fft_filter(osc("white", np.ones(n), rng=np.random.default_rng(103)), low=3500, high=1200) * 0.05
    return fft_filter((whistle + breath) * adsr(n, 0.03, 0.08, 0.85, 0.09), low=4500)


def flop() -> np.ndarray:
    """A pancake landing in the pan: soft low thump and a padded 'pat'."""
    n = secs(0.25)
    thump = osc("sine", glide(n, [(0, 140), (0.25, 55)])) * perc(n, 0.002, 0.06)
    pat = fft_filter(osc("white", np.ones(n), rng=np.random.default_rng(104)), low=900, high=120)
    pat *= perc(n, 0.002, 0.025)
    return fft_filter(thump + 1.2 * pat, low=2000, high=40)


def plop(base: float, seed: int) -> np.ndarray:
    """A topping landing: a short wet bloop (the pitch rises, like a drop) and a tiny second bubble."""
    rng = np.random.default_rng(seed)
    out = np.zeros(secs(0.2))
    n = secs(0.13)
    f = glide(n, [(0, base), (0.07, base * 2.4), (0.13, base * 2.6)])
    place(out, osc("sine", f) * perc(n, 0.003, 0.04), 0)
    n = secs(0.07)
    b2 = base * rng.uniform(1.6, 1.9)
    place(out, osc("sine", glide(n, [(0, b2), (0.07, b2 * 1.8)])) * perc(n, 0.003, 0.02), secs(0.11), 0.35)
    return fft_filter(out, low=3000, high=90)


def plop_1() -> np.ndarray:
    return plop(300, 105)


def plop_2() -> np.ndarray:
    return plop(390, 106)


def plop_3() -> np.ndarray:
    return plop(240, 107)


def splat_soft() -> np.ndarray:
    """Whipped cream landing: a squishy low noise splat with a soft thump."""
    dur = 0.3
    n = secs(dur)
    rng = np.random.default_rng(108)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 2200), (0.05, 1200), (dur, 350)])
    squish = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    t = np.arange(n) / SR
    squish *= 1.0 + 0.5 * np.sin(2 * np.pi * 28 * t) * np.exp(-t / 0.1)
    squish *= perc(n, 0.004, 0.08)
    thump = osc("sine", glide(n, [(0, 190), (0.15, 80)])) * perc(n, 0.003, 0.05)
    return fft_filter(squish * 2.0 + 0.5 * thump, low=2500, high=80)


def ding() -> np.ndarray:
    """Plate ready: a bright little bell on C6 (partials 1, 2, 2.76, 5.4)."""
    n = secs(0.8)
    t = np.arange(n) / SR
    f = midi(84)
    s = np.zeros(n)
    for ratio, amp, dec in [(1.0, 1.0, 0.32), (2.0, 0.35, 0.2), (2.76, 0.3, 0.1), (5.4, 0.1, 0.04)]:
        s += amp * np.sin(2 * np.pi * f * ratio * t) * np.exp(-t / dec)
    s *= 1.0 + 0.08 * np.sin(2 * np.pi * 5 * t)  # a little shimmer
    return fft_filter(s * perc(n, 0.002, 10.0), low=8000, high=150)


def slide() -> np.ndarray:
    """The plate sliding along the counter: a soft friction whoosh."""
    dur = 0.6
    n = secs(dur)
    rng = np.random.default_rng(109)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 500), (0.25, 1500), (dur, 450)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    t = np.arange(n) / SR
    y *= 1.0 + 0.2 * np.sin(2 * np.pi * 19 * t)  # the grain of the counter
    e = env_pts(n, [(0, 0), (0.12, 1), (0.4, 0.8), (dur, 0)]) ** 1.3
    return fft_filter(y * e, low=3000, high=200)


def yum_1() -> np.ndarray:
    """'Mmm!': a happy closed-mouth hum that opens a little in the middle."""
    return voice(0.6, [(0, 280), (0.14, 390), (0.42, 340), (0.6, 260)], [(0, "u"), (0.6, "o")],
                 open_pts=[(0, 0), (0.15, 0.1), (0.3, 0.45), (0.45, 0.1), (0.6, 0)],
                 amp_pts=[(0, 0), (0.05, 1), (0.45, 0.9), (0.6, 0)], vib=(6.5, 0.5), seed=110)


def yum_2() -> np.ndarray:
    """'Nom nom': two syllables, n-o-m, the second one lower."""
    out = np.zeros(secs(0.7))
    for start, f_a, f_b, seed in [(0.0, 320, 360, 111), (0.33, 350, 290, 112)]:
        d = 0.32
        s = voice(d, [(0, f_a), (0.12, f_b), (d, f_b * 0.9)], [(0, "u"), (0.07, "o"), (0.2, "o"), (d, "u")],
                  open_pts=[(0, 0), (0.05, 0), (0.1, 1), (0.19, 1), (0.25, 0), (d, 0)],
                  amp_pts=[(0, 0), (0.03, 0.8), (0.12, 1), (0.25, 0.7), (d, 0)], vib=(6, 0.3), seed=seed)
        place(out, s, secs(start))
    return out


def yum_3() -> np.ndarray:
    """'Yum!': ee-glide into 'uh', closing to an 'm', pitch rising with delight."""
    d = 0.55
    return voice(d, [(0, 300), (0.18, 440), (0.4, 400), (d, 340)],
                 [(0, "i"), (0.12, "o"), (0.3, "o"), (d, "u")],
                 open_pts=[(0, 1), (0.32, 1), (0.4, 0), (d, 0)],
                 amp_pts=[(0, 0), (0.03, 0.9), (0.2, 1), (0.42, 0.8), (d, 0)], vib=(6.5, 0.45), seed=113)


def giggle() -> np.ndarray:
    """'Hee-hee-hee-hee': short breathy 'ee' bursts, each a step higher."""
    out = np.zeros(secs(0.8))
    for i, f in enumerate([420, 480, 540, 610]):
        d = 0.13 if i < 3 else 0.2
        s = voice(d, [(0, f * 1.06), (d, f * 0.92)], [(0, "i"), (d, "e")],
                  amp_pts=[(0, 0), (0.02, 1), (d * 0.6, 0.7), (d, 0)],
                  breath_pts=[(0, 0.5), (0.03, 0.05), (d, 0.02)], vib=(0.1, 0.0), seed=114 + i)
        place(out, s, secs(0.16 * i), 0.8 + 0.07 * i)
    return out


def cheer() -> np.ndarray:
    """A small crowd 'yaaay!': six detuned voices gliding i-a-e with rising pitch."""
    dur = 1.0
    out = np.zeros(secs(dur + 0.1))
    rng = np.random.default_rng(120)
    for k, base in enumerate([230, 270, 300, 340, 380, 430]):
        b = base * rng.uniform(0.97, 1.03)
        d = dur - rng.uniform(0.0, 0.1)
        s = voice(d, [(0, b), (0.5, b * 1.35), (d, b * 1.2)],
                  [(0, "i"), (0.15, "a"), (0.65, "a"), (d, "e")],
                  amp_pts=[(0, 0), (0.08, 0.7), (0.5, 1), (d * 0.85, 0.8), (d, 0)],
                  scale=rng.uniform(0.95, 1.1), vib=(rng.uniform(5.5, 7.0), 0.5), breath=0.07, seed=121 + k)
        place(out, s, secs(rng.uniform(0.0, 0.08)), 0.5)
    return out


def dog_woof() -> np.ndarray:
    """A friendly cartoon 'woof woof': low, a little rough, the second one lower."""
    out = np.zeros(secs(0.62))
    for start, f, seed in [(0.0, 210, 130), (0.3, 185, 131)]:
        d = 0.24
        s = voice(d, [(0, f * 0.8), (0.05, f * 1.15), (d, f * 0.7)], [(0, "u"), (0.06, "o"), (d, "u")],
                  amp_pts=[(0, 0), (0.02, 0.7), (0.06, 1), (0.16, 0.6), (d, 0)],
                  breath_pts=[(0, 0), (0.16, 0), (0.2, 0.3), (d, 0)],
                  scale=0.8, vib=(0.1, 0.0), rough=0.35, seed=seed)
        place(out, s, secs(start))
    return out


def meow() -> np.ndarray:
    """A friendly cartoon cat 'mew'."""
    d = 0.5
    return voice(d, [(0, 520), (0.14, 720), (0.3, 640), (d, 470)], [(0, "i"), (0.12, "i"), (0.4, "u"), (d, "u")],
                 open_pts=[(0, 0), (0.06, 1), (d, 1)],
                 amp_pts=[(0, 0), (0.04, 0.8), (0.15, 1), (0.38, 0.7), (d, 0)],
                 scale=1.15, vib=(7, 0.4), seed=132)


def sparkle() -> np.ndarray:
    """A tiny magic twinkle: F6 A6 C7 F7, soft sines with a shimmer."""
    out = np.zeros(secs(0.42))
    for i, m in enumerate([89, 93, 96, 101]):
        n = secs(0.2)
        f = vibrato(np.full(n, midi(m)), 16, 0.15)
        place(out, osc("sine", f) * perc(n, 0.002, 0.06), secs(0.05 * i), 0.5)
    return fft_filter(out, low=9000, high=200)


def whoosh() -> np.ndarray:
    """Soft air swoosh: noise through a low-pass that sweeps up and back down."""
    n = secs(0.55)
    rng = np.random.default_rng(88)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 250), (0.25, 2800), (0.55, 350)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.22, 1), (0.55, 0)]) ** 1.5
    return fft_filter(y * e, high=120)


def xylo_run(notes: list[tuple[int, float]], tail: float = 0.35, seed: int = 140) -> np.ndarray:
    rng = np.random.default_rng(seed)
    total = sum(d for _, d in notes) + tail
    out = np.zeros(secs(total))
    t = 0.0
    for i, (m, d) in enumerate(notes):
        last = i == len(notes) - 1
        n = secs(d + (tail if last else 0.15))
        place(out, xylo(midi(m), n, decay=0.22 if last else 0.12, rng=rng), secs(t))
        t += d
    return fft_filter(out, low=7000, high=150)


def join() -> np.ndarray:
    return xylo_run([(77, 0.06), (81, 0.06), (84, 0.06), (89, 0.12)])


def select() -> np.ndarray:
    return xylo_run([(84, 0.05)], tail=0.12, seed=141)


def ready() -> np.ndarray:
    return xylo_run([(84, 0.08), (89, 0.2)], tail=0.3, seed=142)


def party() -> np.ndarray:
    """Victory fanfare in F: da-da-da-DAAA-da-DAAAA on xylophone + a warm soft lead, bass,
    a brush roll and a xylophone tremolo on the last chord."""
    beat = 0.14
    melody = [(72, 1), (77, 1), (81, 1), (84, 3), (81, 1), (84, 6)]
    harmony = [(65, 1), (69, 1), (72, 1), (77, 3), (77, 1), (81, 6)]
    total = sum(d for _, d in melody) * beat + 0.45
    out = np.zeros(secs(total))
    rng = np.random.default_rng(150)
    for voice_notes, g in [(melody, 0.55), (harmony, 0.3)]:
        t = 0.0
        for i, (m, d) in enumerate(voice_notes):
            last = i == len(voice_notes) - 1
            n = secs(d * beat + (0.4 if last else 0.02))
            f = np.full(n, midi(m))
            if d >= 3:
                f = vibrato(f, 6, 0.25, delay=0.1)
            e = adsr(n, 0.01, 0.08, 0.7, 0.3 if last else 0.03)
            warm = fft_filter(0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2), low=2500)
            place(out, warm * e, secs(t), g)
            place(out, xylo(midi(m + 12), secs(0.4), decay=0.15, rng=rng), secs(t), g * 0.6)
            t += d * beat
    t = 0.0
    for m, d in [(41, 3), (46, 3), (48, 1), (53, 6)]:
        n = secs(d * beat + 0.02 + (0.4 if m == 53 else 0.0))
        place(out, osc("sine", np.full(n, midi(m))) * adsr(n, 0.005, 0.06, 0.8, 0.1), secs(t), 0.6)
        t += d * beat
    for i in range(8):  # soft brush roll into the last note
        n = secs(0.06)
        s = fft_filter(osc("white", np.ones(n), rng=rng), low=4500, high=800) * perc(n, 0.002, 0.02)
        place(out, s, secs(5 * beat + i * beat / 4), 0.1 + 0.02 * i)
    for i in range(12):  # tremolo on F6 A6 C7 over the last chord
        m = [89, 93, 96][i % 3]
        place(out, xylo(midi(m), secs(0.25), decay=0.08, rng=rng), secs(7 * beat + 0.06 * i),
              0.2 * (1 - i / 14))
    return fft_filter(out, low=7000, high=50)


# ----------------------------------------------------------------------------
# Music: patterns rendered into a circular buffer, so the loop has no seam
# ----------------------------------------------------------------------------

S = "-"  # hold the previous note (a mallet note then rings on until the next one)

# Chord symbol -> (bass root, third above the root, comping triad).
CHORDS = {
    "F": (41, 4, [65, 69, 72]), "Dm": (38, 3, [62, 65, 69]), "Gm": (43, 3, [62, 67, 70]),
    "C7": (48, 4, [64, 67, 70]), "C": (48, 4, [64, 67, 72]), "Bb": (46, 4, [62, 65, 70]),
    "Am": (45, 3, [64, 69, 72]),
}


def bar_samples(bpm: float) -> int:
    bar = 4 * 60.0 / bpm * SR
    assert abs(bar - round(bar)) < 1e-6, "a bar must be a whole number of samples"
    return int(round(bar))


def note_events(pattern: list, pos_of) -> list[tuple[int, int, int]]:
    """Flatten bars of 8th-note slots into (start_sample, length_samples, midi). S holds, None rests."""
    flat = [(b, k, m) for b, bar in enumerate(pattern) for k, m in enumerate(bar)]
    assert all(len(bar) == 8 for bar in pattern)
    events = []
    for i, (b, k, m) in enumerate(flat):
        if m is None or m == S:
            continue
        j = i + 1
        while j < len(flat) and flat[j][2] == S:
            j += 1
        start = pos_of(b, k)
        end = pos_of(*flat[j][:2]) if j < len(flat) else pos_of(len(pattern), 0)
        events.append((start, end - start, m))
    return events


def brush(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.2)
    s = fft_filter(rng.uniform(-1, 1, n), low=4500, high=900) * env_pts(n, [(0, 0), (0.015, 1), (0.2, 0)]) ** 2
    return s


def shaker(rng: np.random.Generator) -> np.ndarray:
    n = secs(0.05)
    return fft_filter(rng.uniform(-1, 1, n), low=6500, high=2500) * perc(n, 0.004, 0.012)


def soft_kick() -> np.ndarray:
    n = secs(0.18)
    return osc("sine", glide(n, [(0, 110), (0.08, 55), (0.18, 48)])) * perc(n, 0.003, 0.07)


def upright(m: int, n: int) -> np.ndarray:
    """Round plucked bass: sine plus a touch of triangle, quick pluck then a gentle decay."""
    f = np.full(n, midi(m))
    t = np.arange(n) / SR
    s = 0.8 * osc("sine", f) + 0.2 * osc("triangle", f)
    e = np.minimum(t / 0.004, 1.0) * (0.35 * np.exp(-t / 0.05) + 0.65 * np.exp(-t / 0.4))
    fade = min(n, secs(0.02))
    e[n - fade:] *= np.linspace(1, 0, fade)
    return s * e


# F major, 96 BPM, 16 bars of swung 8ths. A: F Dm Gm C7 F Bb C F / B: Bb F Gm C Am Dm C7 F.
KITCHEN_CHORDS = ["F", "Dm", "Gm", "C7", "F", "Bb", "C", "F", "Bb", "F", "Gm", "C", "Am", "Dm", "C7", "F"]
KITCHEN_LEAD = [
    [84, 81, 77, 81, 84, S, 86, 84], [81, S, 77, S, 74, 77, 81, S],
    [79, 82, 86, 82, 79, S, 77, 79], [76, 79, 82, 79, 76, S, None, 72],
    [77, 81, 84, 89, 88, 84, 81, S], [82, S, 86, S, 89, 86, 82, 81],
    [79, 81, 79, 76, 72, S, 74, 76], [77, S, 81, S, 77, None, None, None],
    [86, S, 82, 86, 89, S, 86, 82], [84, S, 81, 84, 89, S, 84, 81],
    [82, 81, 79, 77, 79, S, 82, S], [84, S, 79, S, 76, 79, 84, 86],
    [88, S, 84, S, 81, 84, 88, S], [89, 88, 86, 84, 81, S, 77, 81],
    [79, 82, 86, S, 84, 82, 79, 76], [77, S, 81, 84, 89, S, None, None],
]

# F major, 90 BPM, 8 bars of straight 8ths: F Am Bb C F Dm Gm C.
MENU_CHORDS = ["F", "Am", "Bb", "C", "F", "Dm", "Gm", "C"]
MENU_LEAD = [
    [77, S, 81, S, 84, S, 81, S], [81, S, 76, S, 72, S, 76, S],
    [74, S, 77, S, 82, S, 81, 79], [79, S, S, S, 76, S, 79, S],
    [84, S, 81, S, 77, S, 81, 84], [86, S, 84, S, 81, S, 77, S],
    [79, S, 82, S, 86, S, 84, 82], [81, S, 79, S, 76, S, None, None],
]


def music_kitchen() -> tuple[np.ndarray, int]:
    """Swingy kitchen loop: xylophone lead, walking upright bass, soft comping, brushes and shaker.
    The swing grid is 12 triplet ticks per bar; tick*bar_len//12 keeps every onset on a whole sample."""
    bar_len = bar_samples(96)
    bars = len(KITCHEN_CHORDS)
    total = bar_len * bars
    rng = np.random.default_rng(160)

    def tick(b: int, t12: int) -> int:
        return b * bar_len + t12 * bar_len // 12

    def swung(b: int, k: int) -> int:  # 8th slot k: on-beats on the beat, off-beats 2/3 through it
        return tick(b, (k // 2) * 3 + (2 if k % 2 else 0))

    lead = np.zeros(total)
    for start, length, m in note_events(KITCHEN_LEAD, swung):
        n = min(length + secs(0.3), secs(1.2))
        place(lead, xylo(midi(m), n, rng=rng), start, 0.5, circular=True)
    lead = fft_filter(lead, low=7000, circular=True)

    bass = np.zeros(total)
    comp = np.zeros(total)
    for b, name in enumerate(KITCHEN_CHORDS):
        root, third, triad = CHORDS[name]
        nxt = CHORDS[KITCHEN_CHORDS[(b + 1) % bars]][0]
        approach = nxt + 1 if abs(nxt + 1 - (root + 7)) < abs(nxt - 1 - (root + 7)) else nxt - 1
        for q, m in enumerate([root, root + third, root + 7, approach]):
            n = tick(b, 3 * q + 3) - tick(b, 3 * q) - secs(0.01)
            place(bass, upright(m, n), tick(b, 3 * q), 0.5, circular=True)
        for t12, g in [(0, 0.12), (5, 0.1)]:  # Charleston comp: beat 1 and the swung "and" of 2
            for m in triad:
                n = secs(0.35)
                place(comp, xylo(midi(m), n, decay=0.18, partial=4.0, bright=0.12, click=0.0),
                      tick(b, t12), g, circular=True)
    bass = fft_filter(bass, low=1000, circular=True)
    comp = fft_filter(comp, low=2500, circular=True)

    drums = np.zeros(total)
    kick = soft_kick()
    for b in range(bars):
        for q in range(4):
            if q in (0, 2):
                place(drums, kick, tick(b, 3 * q), 0.35, circular=True)
            else:
                place(drums, brush(rng), tick(b, 3 * q), 0.22, circular=True)
        for k in range(8):
            place(drums, shaker(rng), swung(b, k), 0.07 if k % 2 else 0.045, circular=True)
    drums = fft_filter(drums, low=7000, circular=True)

    mix = lead + bass + comp + drums
    return fft_filter(mix, high=30, circular=True), bar_len


def music_menu() -> tuple[np.ndarray, int]:
    """Calm menu loop: marimba lead, soft marimba arpeggio, round bass, a warm pad and a hushed shaker."""
    bar_len = bar_samples(90)
    bars = len(MENU_CHORDS)
    total = bar_len * bars
    eighth = bar_len // 8
    assert eighth * 8 == bar_len
    rng = np.random.default_rng(170)

    def pos(b: int, k: int) -> int:
        return b * bar_len + k * eighth

    lead = np.zeros(total)
    for start, length, m in note_events(MENU_LEAD, pos):
        n = min(length + secs(0.35), secs(1.6))
        place(lead, marimba(midi(m), n, rng=rng), start, 0.55, circular=True)

    arp = np.zeros(total)
    bass = np.zeros(total)
    pad = np.zeros(total)
    for b, name in enumerate(MENU_CHORDS):
        root, _, triad = CHORDS[name]
        order = [triad[0], triad[1], triad[2], triad[1]]
        for k in range(8):
            m = order[k % 4] - 12 if k % 4 == 0 else order[k % 4]
            place(arp, marimba(midi(m), secs(0.4)), pos(b, k), 0.14 if k % 2 else 0.18, circular=True)
        for q, m in [(0, root), (4, root + 7)]:
            n = 4 * eighth - secs(0.01)
            place(bass, upright(m, n), pos(b, q), 0.5, circular=True)
        n = bar_len + secs(0.3)
        t = np.arange(n) / SR
        chord = sum(osc("sine", np.full(n, midi(m))) for m in triad) * (1 + 0.1 * np.sin(2 * np.pi * 4 * t))
        place(pad, chord * adsr(n, 0.35, 0.2, 0.8, 0.45), pos(b, 0), 0.05, circular=True)
        if b % 2 == 0:
            place(pad, soft_kick(), pos(b, 0), 0.25, circular=True)
        for k in range(8):
            place(pad, shaker(rng), pos(b, k), 0.03 if k % 2 else 0.02, circular=True)

    mix = (fft_filter(lead, low=5000, circular=True) + fft_filter(arp, low=3000, circular=True)
           + fft_filter(bass, low=1000, circular=True) + fft_filter(pad, low=6000, circular=True))
    return fft_filter(mix, high=30, circular=True), bar_len


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
# ----------------------------------------------------------------------------


SFX = {
    "pour": pour, "boing_1": boing_1, "boing_2": boing_2, "boing_3": boing_3, "boing_4": boing_4,
    "spin": spin, "flop": flop, "plop_1": plop_1, "plop_2": plop_2, "plop_3": plop_3,
    "splat_soft": splat_soft, "ding": ding, "slide": slide, "yum_1": yum_1, "yum_2": yum_2,
    "yum_3": yum_3, "giggle": giggle, "dog_woof": dog_woof, "meow": meow, "sparkle": sparkle,
    "whoosh": whoosh, "join": join, "select": select, "ready": ready, "party": party, "cheer": cheer,
}
# name -> (render, target LUFS). Each render returns (samples, bar length in samples).
LOOPS = {
    "sizzle": (sizzle, SIZZLE_LUFS),
    "music_menu": (music_menu, MUSIC_LUFS),
    "music_kitchen": (music_kitchen, MUSIC_LUFS),
}
BUDGET_BYTES = 9e6


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
    rows = [(n, f, None) for n, f in SFX.items()] + [(n, f, t) for n, (f, t) in LOOPS.items()]
    for name, fn, loop_lufs in rows:
        loop = loop_lufs is not None
        if loop:
            x, bar_len = fn()
            x = normalise(x, loop_lufs, loop=True)
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
        target = loop_lufs if loop else SFX_LUFS
        if abs((st if loop else loud) - target) > 1.5:
            ok = False
            print(f"  FAIL: {name} loudness is far from its {target} LUFS target")
        if loop:
            bars = len(y) / bar_len
            step = np.abs(np.diff(y))
            seam = abs(y[0] - y[-1])
            p99 = np.percentile(step, 99)
            good = bars == int(bars) and seam <= p99
            ok &= good
            print(f"  loop: {len(y)} samples = {bars:g} bars x {bar_len}; seam jump {seam:.5f} "
                  f"vs median step {np.median(step):.5f}, p99 step {p99:.5f} -> {'OK' if good else 'FAIL'}")
        else:
            if abs(y[0]) > 1e-3 or abs(y[-1]) > 1e-3:
                ok = False
                print(f"  FAIL: {name} does not start/end at zero")
        if args.check:
            spectrogram_png(name, y, args.check / f"{name}.png")
            if loop:
                seam_png(name, y, args.check / f"{name}_seam.png")
    print(f"total {total_bytes / 1e6:.2f} MB in {OUT.relative_to(ROOT)}")
    if total_bytes > BUDGET_BYTES:
        ok = False
        print(f"FAIL: audio total above {BUDGET_BYTES / 1e6:g} MB")
    print("ALL OK" if ok else "SOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
