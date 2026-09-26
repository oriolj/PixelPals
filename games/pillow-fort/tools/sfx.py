"""Pillow Fort sound synth: every soft sound and the three lullaby loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR]

Copied from PixelPals's synth core (oscillators with polyBLEP, envelopes,
glides, vibrato, zero-phase filters, BS.1770 loudness) with this game's
voices: music-box tines, a formant "boo" and giggle, fabric swishes, pads.
Everything is seeded, so a rerun writes byte-identical files.
Output: game/audio/<name>.wav, 16-bit mono at SR (24 kHz: every sound is
low-passed well under 12 kHz anyway, and the loops stay small).

Loudness: this is a bedtime game, so SFX are normalised to about -18 LUFS
(PixelPals uses -15) and music to MUSIC_LUFS; no file peaks above -1 dBFS,
and every SFX attack is at least 5 ms (no clicks, no stings). The report
printed at the end is the verification: peak, RMS, LUFS, length, and for the
music loops the bar count and the loop-seam continuity.
With --check DIR it also writes spectrogram + waveform PNGs to DIR.
"""

from __future__ import annotations

import argparse
import math
import sys
import wave
from pathlib import Path

import numpy as np

SR = 24000
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "audio"

PEAK_DBFS = -1.0
SFX_LUFS = -18.0
# sfx.gd plays music at -8 dB, so a -17 LUFS file sits about 7 dB under the -18 LUFS SFX in game.
MUSIC_LUFS = -17.0

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
# Soft voices: every sound here has a gentle attack (>= 5 ms), a low-pass,
# and no stings. Nothing is scary; nothing is loud.
# ----------------------------------------------------------------------------


def bell(m: float, dur: float, bright: float = 0.25, decay: float = 0.6) -> np.ndarray:
    """Music-box tine: a sine with a soft inharmonic overtone, fast-but-soft attack, long decay."""
    n = secs(dur)
    f = np.full(n, midi(m))
    tine = osc("sine", f) + bright * osc("sine", f * 3.01) * np.exp(-np.arange(n) / SR / 0.12)
    tine += 0.12 * osc("sine", f * 2.0)
    return tine * perc(n, 0.006, decay)


def formant_voice(n: int, pitch: np.ndarray, formants: list[tuple[float, float]], seed: int,
                  breath: float = 0.05) -> np.ndarray:
    """A soft cartoon voice: a band-limited buzz through vowel formant bands."""
    rng = np.random.default_rng(seed)
    buzz = 0.6 * osc("saw", pitch) + 0.4 * osc("triangle", pitch)
    air = osc("white", np.ones(n), rng=rng) * breath
    src = buzz + air
    out = np.zeros(n)
    for fc, g in formants:
        out += g * fft_filter(src, low=fc * 1.25, high=fc * 0.8, order=2)
    return fft_filter(out, low=3500)


def peekaboo(variant: int) -> np.ndarray:
    """A rising two-note chime and a warm formant 'boo!'."""
    base = [0, 2, 4][variant]
    out = np.zeros(secs(1.0))
    place(out, bell(76 + base, 0.5, 0.2, 0.25), 0, 0.5)
    place(out, bell(83 + base, 0.7, 0.2, 0.35), secs(0.16), 0.55)
    n = secs(0.5)
    p0 = midi(62 + base)
    pitch = glide(n, [(0, p0 * 1.15), (0.12, p0 * 1.25), (0.5, p0 * 0.95)])
    pitch = vibrato(pitch, 5.5, 0.3, delay=0.15)
    voice = formant_voice(n, pitch, [(320, 1.0), (800, 0.45), (2300, 0.08)], 30 + variant)
    place(out, voice * adsr(n, 0.04, 0.1, 0.8, 0.25), secs(0.34), 0.9)
    return fft_filter(out, low=5000, high=90)


def giggle() -> np.ndarray:
    """Five little 'hee' syllables stepping down, soft."""
    out = np.zeros(secs(0.75))
    for i in range(5):
        n = secs(0.085)
        p = midi(79 - i * 1.5)
        pitch = glide(n, [(0, p * 1.05), (0.085, p * 0.95)])
        v = formant_voice(n, pitch, [(350, 0.8), (2200, 0.5)], 40 + i, breath=0.15)
        place(out, v * adsr(n, 0.008, 0.02, 0.7, 0.04), secs(0.02 + i * 0.13), 1.0 - i * 0.1)
    return fft_filter(out, low=4200, high=150)


def lift() -> np.ndarray:
    """Fabric swish: noise through a gently sweeping low-pass."""
    n = secs(0.42)
    rng = np.random.default_rng(5)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 400), (0.18, 2200), (0.42, 500)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.15, 1), (0.42, 0)]) ** 1.6
    return fft_filter(y * e, high=150, low=4000)


def toy_found() -> np.ndarray:
    """Music-box arpeggio up the pentatonic, and a sparkle."""
    out = np.zeros(secs(1.3))
    for i, m in enumerate([72, 76, 79, 84, 88]):
        place(out, bell(m, 0.8, 0.3, 0.35), secs(0.08 * i), 0.5)
    place(out, bell(91, 0.6, 0.2, 0.2), secs(0.5), 0.25)
    return fft_filter(out, low=6000, high=120)


def basket_plop() -> np.ndarray:
    """A soft cushioned plop: a low sine drop plus a little wicker rustle."""
    out = np.zeros(secs(0.35))
    n = secs(0.2)
    thump = osc("sine", glide(n, [(0, 330), (0.2, 150)])) * perc(n, 0.006, 0.07)
    place(out, thump, 0, 1.0)
    n = secs(0.12)
    rustle = fft_filter(osc("white", np.ones(n), rng=np.random.default_rng(9)), low=3000, high=900) * perc(n, 0.005, 0.03)
    place(out, rustle, secs(0.02), 0.25)
    place(out, bell(84, 0.25, 0.1, 0.1), secs(0.06), 0.2)
    return fft_filter(out, low=4000, high=60)


def mouse_squeak() -> np.ndarray:
    """Two tiny, sleepy squeaks (sine glides, no harsh edges)."""
    out = np.zeros(secs(0.45))
    for start, (a, b) in [(0.0, (1400, 1900)), (0.18, (1500, 1250))]:
        n = secs(0.12)
        f = vibrato(glide(n, [(0, a), (0.12, b)]), 22, 0.4)
        place(out, osc("sine", f) * adsr(n, 0.01, 0.03, 0.7, 0.05), secs(start), 0.8)
    return fft_filter(out, low=4000, high=300)


def surprise() -> np.ndarray:
    """A small sweet 'ding-dong' (a sock! a cookie!)."""
    out = np.zeros(secs(0.8))
    place(out, bell(81, 0.5, 0.2, 0.25), 0, 0.6)
    place(out, bell(76, 0.6, 0.2, 0.3), secs(0.14), 0.6)
    return fft_filter(out, low=5000, high=120)


def twinkle(variant: int) -> np.ndarray:
    """Fairy lights: three quick high tines, a different little run each time."""
    runs = [[88, 91, 96], [91, 93, 96], [86, 88, 93]]
    out = np.zeros(secs(0.7))
    for i, m in enumerate(runs[variant]):
        place(out, bell(m, 0.4, 0.1, 0.15), secs(0.06 * i), 0.4)
    return fft_filter(out, low=7000, high=300)


def hint_glow() -> np.ndarray:
    """A soft pad swell: a warm C major triad fading in and out."""
    n = secs(1.6)
    x = np.zeros(n)
    for m in (60, 64, 67, 72):
        x += osc("triangle", vibrato(np.full(n, midi(m)), 4.5, 0.08))
    e = env_pts(n, [(0, 0), (0.6, 1), (1.6, 0)]) ** 1.5
    return fft_filter(x * e, low=1800, high=80)


def lamp_on() -> np.ndarray:
    """The lamp warms up: a slow major swell with a music-box sparkle on top."""
    n = secs(2.4)
    x = np.zeros(n)
    for m in (48, 55, 60, 64, 67):
        x += osc("sine", np.full(n, midi(m))) + 0.3 * osc("triangle", np.full(n, midi(m)))
    x *= env_pts(n, [(0, 0), (1.4, 1), (2.4, 0)]) ** 1.4
    out = fft_filter(x, low=1500, high=60)
    for i, m in enumerate([79, 84, 88, 91]):
        place(out, bell(m, 0.8, 0.2, 0.3) * 0.35, secs(0.9 + 0.18 * i))
    return out


def arp_bells(notes: list[int], step: float, tail: float = 0.6, gain: float = 0.5) -> np.ndarray:
    out = np.zeros(secs(step * len(notes) + tail))
    for i, m in enumerate(notes):
        place(out, bell(m, tail + step, 0.25, 0.3), secs(step * i), gain)
    return fft_filter(out, low=6000, high=120)


def join() -> np.ndarray:
    return arp_bells([72, 76, 79, 84], 0.07)


def select() -> np.ndarray:
    return arp_bells([84], 0.05, tail=0.25, gain=0.6)


def ready() -> np.ndarray:
    return arp_bells([79, 84], 0.1, tail=0.5)


def hop() -> np.ndarray:
    """The paw hops: a tiny soft pat."""
    n = secs(0.12)
    x = osc("sine", glide(n, [(0, 700), (0.12, 520)])) * perc(n, 0.005, 0.03)
    return fft_filter(x, low=3000, high=200)


def party() -> np.ndarray:
    """A gentle music-box fanfare: up the pentatonic, then a warm chord."""
    out = np.zeros(secs(2.4))
    for i, m in enumerate([72, 74, 76, 79, 81, 84]):
        place(out, bell(m, 0.6, 0.25, 0.25), secs(0.12 * i), 0.45)
    for m in (72, 76, 79, 84):
        place(out, bell(m, 1.6, 0.2, 0.7), secs(0.8), 0.3)
    n = secs(1.6)
    pad = sum(osc("triangle", np.full(n, midi(m))) for m in (60, 64, 67)) * env_pts(n, [(0, 0), (0.3, 1), (1.6, 0)])
    place(out, fft_filter(pad, low=1500), secs(0.7), 0.25)
    return fft_filter(out, low=6000, high=80)


def yawn() -> np.ndarray:
    """A big sleepy 'aaah-oom': pitch sinks, the vowel closes from ah to oo."""
    n = secs(1.5)
    pitch = vibrato(glide(n, [(0, 330), (0.3, 360), (1.5, 190)]), 5, 0.2, delay=0.3)
    ah = formant_voice(n, pitch, [(750, 1.0), (1200, 0.5)], 60, breath=0.2)
    oo = formant_voice(n, pitch, [(320, 1.0), (800, 0.4)], 61, breath=0.2)
    k = np.clip(np.arange(n) / n * 1.4 - 0.2, 0, 1)
    v = ah * (1 - k) + oo * k
    return fft_filter(v * adsr(n, 0.15, 0.2, 0.8, 0.5), low=3000, high=90)


# ----------------------------------------------------------------------------
# Music: music-box lullabies rendered into circular buffers (seamless loops)
# ----------------------------------------------------------------------------

S = "-"  # sustain the previous note

# C major pentatonic lullaby, 8 bars of 8ths.
THEME = [
    [76, S, 79, S, 81, 79, 76, S], [74, S, 76, S, 72, S, S, S],
    [76, S, 79, S, 81, S, 84, S], [81, S, 79, S, S, S, S, S],
    [79, 81, 79, 76, 74, S, 76, S], [79, S, 76, S, 74, S, S, S],
    [76, 74, 72, 74, 76, S, 79, S], [72, S, S, S, S, S, None, None],
]
CHORDS = [[48, 52, 55], [43, 47, 50], [45, 48, 52], [41, 45, 48],
          [48, 52, 55], [45, 48, 52], [43, 47, 50], [48, 52, 55]]


def render_lullaby(bpm: float, octave: int, arp: bool, bass_pluck: bool, shaker: float,
                   bright: float, pad_gain: float) -> tuple[np.ndarray, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    bars = len(THEME)
    total = bar_len * bars
    step = bar_len // 8
    assert step * 8 == bar_len
    mel = np.zeros(total)
    flat = [x for bar in THEME for x in bar]
    for i, m in enumerate(flat):
        if m is None or m == S:
            continue
        j = i + 1
        while j < len(flat) and flat[j] == S:
            j += 1
        dur = (j - i) * step / SR + 0.6
        place(mel, bell(m + 12 * octave, dur, bright, 0.25 + 0.15 * (j - i)), i * step, 0.5, circular=True)
        if octave >= 0 and bright > 0.3:
            place(mel, bell(m + 12 * octave + 12, dur, bright, 0.2), i * step, 0.12, circular=True)
    mel = fft_filter(mel, low=6000, circular=True)
    pad = np.zeros(total)
    acc = np.zeros(total)
    for b, chord in enumerate(CHORDS):
        n = bar_len + secs(0.3)
        tones = sum(osc("triangle", vibrato(np.full(n, midi(m + 12)), 4.0, 0.06)) for m in chord)
        e = env_pts(n, [(0, 0), (0.5, 1), (n / SR - 0.4, 0.9), (n / SR, 0)])
        place(pad, tones * e, b * bar_len, pad_gain, circular=True)
        root = chord[0]
        for beat in (0, 2):
            n2 = secs(0.9)
            k = osc("sine", np.full(n2, midi(root))) * (perc(n2, 0.02, 0.35) if bass_pluck else adsr(n2, 0.05, 0.2, 0.6, 0.4))
            place(acc, k, b * bar_len + beat * 2 * step, 0.5, circular=True)
        if arp:
            for k8 in range(8):
                m = chord[[0, 1, 2, 1][k8 % 4]] + 24
                place(acc, bell(m, 0.5, 0.1, 0.18), b * bar_len + k8 * step, 0.12, circular=True)
    pad = fft_filter(pad, low=1400, circular=True)
    acc = fft_filter(acc, low=4000, circular=True)
    mix = mel + pad + acc
    if shaker > 0:
        rng = np.random.default_rng(3)
        sh = np.zeros(total)
        for k8 in range(bars * 8):
            n = secs(0.06)
            s = fft_filter(osc("white", np.ones(n), rng=rng), low=8000, high=3000) * perc(n, 0.006, 0.02)
            place(sh, s, k8 * step, shaker * (1.0 if k8 % 2 else 0.6), circular=True)
        mix += sh
    mix = fft_filter(mix, high=30, circular=True)
    return mix, bar_len


def music_fort() -> tuple[np.ndarray, int]:
    return render_lullaby(72, 0, arp=False, bass_pluck=False, shaker=0.0, bright=0.2, pad_gain=0.08)


def music_menu() -> tuple[np.ndarray, int]:
    return render_lullaby(80, -1, arp=True, bass_pluck=True, shaker=0.0, bright=0.2, pad_gain=0.05)


def music_party() -> tuple[np.ndarray, int]:
    return render_lullaby(96, 0, arp=True, bass_pluck=True, shaker=0.05, bright=0.4, pad_gain=0.06)


SFX = {
    "peekaboo_1": lambda: peekaboo(0), "peekaboo_2": lambda: peekaboo(1), "peekaboo_3": lambda: peekaboo(2),
    "giggle": giggle, "lift": lift, "toy_found": toy_found, "basket_plop": basket_plop,
    "mouse_squeak": mouse_squeak, "surprise": surprise,
    "twinkle_1": lambda: twinkle(0), "twinkle_2": lambda: twinkle(1), "twinkle_3": lambda: twinkle(2),
    "hint_glow": hint_glow, "lamp_on": lamp_on, "join": join, "select": select, "ready": ready,
    "hop": hop, "party": party, "yawn": yawn,
}
MUSIC = {"music_menu": music_menu, "music_fort": music_fort, "music_party": music_party}


# ----------------------------------------------------------------------------
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
    if total_bytes > 6e6:
        ok = False
        print("FAIL: audio total above 6 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
