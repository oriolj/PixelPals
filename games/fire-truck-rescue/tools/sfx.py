"""Fire Truck Rescue sound synth (PixelPals's engine, this game's sounds): every sound,
the three gameplay loops and the town music, made by our own code.

Run: make sfx   (uv run python games/fire-truck-rescue/tools/sfx.py [--check DIR])

A small sfxr-style synth (square/saw/triangle/sine/noise oscillators with
polyBLEP, ADSR envelopes, pitch slides by breakpoints, vibrato, arpeggios and
a zero-phase low/high-pass filter). Everything is seeded, so a rerun writes
byte-identical files. Output: game/audio/<name>.wav, 16-bit mono 44100 Hz.

Loudness: SFX are normalised to about -15 LUFS (whole clip, K-weighted,
BS.1770 without gating) and music to MUSIC_LUFS; no file peaks above -1 dBFS.
The report printed at the end is the verification: peak, RMS, LUFS, length,
and for the music and the gameplay loops the loop-seam continuity.
With --check DIR it also writes spectrogram + waveform PNGs to DIR.
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
# Sound effects (Fire Truck Rescue)
# ----------------------------------------------------------------------------


def _siren_voice(f: np.ndarray, e: np.ndarray, low: float = 2600) -> np.ndarray:
    """The siren timbre: a soft square + triangle, low-passed so it is round, not piercing."""
    s = 0.45 * osc("square", f, duty=0.5) + 0.55 * osc("triangle", f)
    return fft_filter(s * e, low=low, high=200)


def siren_hilo() -> np.ndarray:
    """European two-tone 'nee-naw', four notes with soft glides between them."""
    n = secs(1.5)
    pts = []
    t = 0.0
    for k in range(4):
        hz = 740 if k % 2 == 0 else 587
        pts += [(t, hz), (t + 0.33, hz)]
        t += 0.36
    pts.append((1.5, 587))
    f = glide(n, pts)
    f = vibrato(f, 6, 0.08)
    return _siren_voice(f, adsr(n, 0.03, 0.05, 0.9, 0.12))


def siren_whoop() -> np.ndarray:
    """A rising whoop that falls back."""
    n = secs(1.25)
    f = glide(n, [(0, 480), (0.85, 1250), (1.0, 1300), (1.25, 900)])
    return _siren_voice(f, adsr(n, 0.05, 0.1, 0.9, 0.2))


def siren_yelp() -> np.ndarray:
    """Short fast yelps."""
    n = secs(0.9)
    t = np.arange(n) / SR
    f = 950 + 380 * np.sin(2 * np.pi * 5.5 * t - np.pi / 2)
    return _siren_voice(f, adsr(n, 0.02, 0.05, 0.9, 0.12), low=2400)


def horn() -> np.ndarray:
    """Truck air horn: a two-note chord of saws and squares, short and warm."""
    n = secs(0.62)
    out = np.zeros(n)
    e = adsr(n, 0.015, 0.08, 0.85, 0.12)
    for hz, g in ((196.0, 0.6), (246.9, 0.5), (293.7, 0.35)):
        f = vibrato(np.full(n, hz), 5, 0.05)
        out += g * (0.6 * osc("saw", f) + 0.4 * osc("square", f * 1.004, duty=0.4))
    return fft_filter(out * e, low=2400, high=90)


def engine_loop() -> np.ndarray:
    """1 s seamless diesel hum: 50 Hz saw + 25 Hz square, a 12 Hz chug."""
    n = secs(1.0)
    t = np.arange(n) / SR
    s = 0.7 * osc("saw", np.full(n, 50.0)) + 0.4 * osc("square", np.full(n, 25.0))
    s *= 0.75 + 0.25 * np.sin(2 * np.pi * 12 * t) ** 2
    return fft_filter(s, low=420, high=30, circular=True)


def spray_loop() -> np.ndarray:
    """1 s seamless water jet: band-limited noise with a gentle 7 Hz sputter."""
    n = secs(1.0)
    t = np.arange(n) / SR
    rng = np.random.default_rng(101)
    s = osc("white", np.ones(n), rng=rng)
    s = fft_filter(s, low=6500, high=900, circular=True)
    s *= 0.85 + 0.15 * np.sin(2 * np.pi * 7 * t)
    return s


def spray_start() -> np.ndarray:
    n = secs(0.3)
    rng = np.random.default_rng(102)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 500), (0.12, 6000), (0.3, 4000)])
    y = onepole_sweep(noise, cutoff)
    return fft_filter(y * env_pts(n, [(0, 0), (0.06, 1), (0.3, 0)]), high=500)


def hiss_out() -> np.ndarray:
    """Tsssss: steam noise sliding down, with a friendly 'pff' at the end."""
    n = secs(0.85)
    rng = np.random.default_rng(103)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 7000), (0.5, 2500), (0.85, 500)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.03, 1), (0.5, 0.6), (0.85, 0)])
    return fft_filter(y * e, high=300)


def fire_crackle_loop() -> np.ndarray:
    """2 s seamless cosy crackle: sparse soft clicks over a low rumble."""
    n = secs(2.0)
    rng = np.random.default_rng(104)
    out = np.zeros(n)
    rumble = fft_filter(osc("white", np.ones(n), rng=rng), low=260, circular=True)
    out += rumble * 0.6
    for _ in range(34):
        m = secs(rng.uniform(0.002, 0.008))
        click = osc("white", np.ones(m), rng=rng) * perc(m, 0.0005, m / SR / 3)
        place(out, fft_filter(click, low=5000, high=600), int(rng.uniform(0, n)), rng.uniform(0.3, 1.0), circular=True)
    return fft_filter(out, high=40, circular=True)


def fire_start() -> np.ndarray:
    """Fwoomp: a soft whoosh up and a low thump (a new fire, not scary)."""
    n = secs(0.6)
    rng = np.random.default_rng(105)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 200), (0.2, 1800), (0.6, 300)])
    y = onepole_sweep(noise, cutoff) * env_pts(n, [(0, 0), (0.15, 1), (0.6, 0)])
    thump = osc("sine", glide(n, [(0, 120), (0.3, 60), (0.6, 50)])) * perc(n, 0.01, 0.12)
    return fft_filter(y + 0.8 * thump, high=40)


def _ratchet(pitches: list[float], gaps: list[float]) -> np.ndarray:
    total = sum(gaps) + 0.1
    out = np.zeros(secs(total))
    rng = np.random.default_rng(106)
    t = 0.0
    for hz, gap in zip(pitches, gaps):
        m = secs(0.04)
        blip = osc("square", np.full(m, hz), duty=0.3) * perc(m, 0.001, 0.008)
        tick = osc("white", np.ones(m), rng=rng) * perc(m, 0.0005, 0.004)
        place(out, fft_filter(0.6 * blip + 0.5 * tick, low=6000, high=300), secs(t))
        t += gap
    return out


def ladder_up() -> np.ndarray:
    k = 11
    return _ratchet([600 * 2 ** (i / 12) for i in range(k)], [0.1 - 0.004 * i for i in range(k)])


def ladder_down() -> np.ndarray:
    k = 11
    return _ratchet([1200 * 2 ** (-i / 12) for i in range(k)], [0.06 + 0.004 * i for i in range(k)])


def _meow(base: float, dur: float, seed: int) -> np.ndarray:
    """'Mi-aow': a pitch glide up then down, with a vowel that opens (a moving band-pass)."""
    n = secs(dur)
    f = glide(n, [(0, base), (dur * 0.3, base * 1.6), (dur * 0.75, base * 1.35), (dur, base * 0.9)])
    f = vibrato(f, 7, 0.3, delay=dur * 0.3)
    voice = 0.6 * osc("saw", f) + 0.4 * osc("triangle", f)
    e = adsr(n, 0.03, 0.1, 0.8, dur * 0.35)
    lo = fft_filter(voice, low=900, high=200)
    hi = fft_filter(voice, low=3200, high=900)
    mix = env_pts(n, [(0, 0.1), (dur * 0.4, 1.0), (dur, 0.3)])
    return (lo * (1 - mix * 0.6) + hi * mix) * e


def meow_1() -> np.ndarray:
    return _meow(520, 0.55, 1)


def meow_2() -> np.ndarray:
    return _meow(640, 0.42, 2)


def meow_3() -> np.ndarray:
    return _meow(460, 0.7, 3)


def purr() -> np.ndarray:
    """Two purring breaths: low noise pulsing at 24 Hz."""
    n = secs(1.3)
    t = np.arange(n) / SR
    rng = np.random.default_rng(107)
    noise = fft_filter(osc("white", np.ones(n), rng=rng), low=320, high=40)
    pulse = 0.5 + 0.5 * np.sin(2 * np.pi * 24 * t) ** 4
    breath = env_pts(n, [(0, 0), (0.1, 1), (0.55, 0.7), (0.65, 0.2), (0.75, 0.9), (1.2, 0.6), (1.3, 0)])
    return noise * pulse * breath


def boing() -> np.ndarray:
    """A springy, friendly bump."""
    n = secs(0.5)
    f = glide(n, [(0, 110), (0.05, 190), (0.5, 240)])
    f = vibrato(f, 13, 4.0, decay=0.18)
    e = perc(n, 0.015, 0.18)
    s = 0.7 * osc("triangle", f) + 0.3 * osc("square", f, duty=0.5)
    return fft_filter(s * e, low=1800, high=60)


def badge() -> np.ndarray:
    """A cat is safe: a bright arpeggio and a shimmer."""
    out = np.zeros(secs(0.9))
    rng = np.random.default_rng(108)
    for i, m in enumerate([76, 79, 84, 88]):
        n = secs(0.14)
        s = 0.7 * osc("square", np.full(n, midi(m)), duty=0.25) + 0.3 * osc("sine", np.full(n, midi(m + 12)))
        place(out, s * adsr(n, 0.002, 0.04, 0.5, 0.06), secs(0.07 * i), 0.7)
    for _ in range(6):
        n = secs(0.08)
        s = osc("sine", np.full(n, midi(rng.choice([96, 100, 103])))) * perc(n, 0.002, 0.025)
        place(out, s, secs(rng.uniform(0.3, 0.8)), 0.3)
    return fft_filter(out, low=7000, high=150)


def super_spray() -> np.ndarray:
    """Hydrant boost: a gush of water and a rainbow run up the scale."""
    n = secs(1.1)
    rng = np.random.default_rng(109)
    out = np.zeros(n)
    gush = fft_filter(osc("white", np.ones(n), rng=rng), low=5000, high=600) * env_pts(n, [(0, 0), (0.05, 1), (1.1, 0)])
    out += 0.45 * gush
    for i, m in enumerate([72, 74, 76, 79, 81, 84, 88, 91]):
        m_n = secs(0.12)
        s = osc("triangle", np.full(m_n, midi(m))) * adsr(m_n, 0.003, 0.03, 0.6, 0.05)
        place(out, s, secs(0.06 * i + 0.05), 0.8)
    return fft_filter(out, low=7000, high=100)


def _woof(base: float, seed: int) -> np.ndarray:
    n = secs(0.18)
    rng = np.random.default_rng(seed)
    f = glide(n, [(0, base * 1.3), (0.04, base * 1.5), (0.18, base * 0.8)])
    voice = 0.6 * osc("square", f, duty=0.3) + 0.4 * osc("saw", f)
    breath = osc("white", np.ones(n), rng=rng) * 0.35
    e = perc(n, 0.006, 0.07)
    return fft_filter((voice + breath) * e, low=1600, high=150)


def bark_1() -> np.ndarray:
    """Woof!"""
    return _woof(260, 110)


def bark_2() -> np.ndarray:
    """Ruff-ruff (a double, a bit higher)."""
    out = np.zeros(secs(0.45))
    place(out, _woof(330, 111), 0)
    place(out, _woof(360, 112), secs(0.22), 0.9)
    return out


def giggle() -> np.ndarray:
    """Hee-hee-hee: quick bouncy syllables, falling."""
    out = np.zeros(secs(0.7))
    for i in range(4):
        n = secs(0.11)
        base = 820 - 60 * i
        f = glide(n, [(0, base), (0.05, base * 1.25), (0.11, base * 1.05)])
        s = 0.7 * osc("sine", f) + 0.3 * osc("triangle", f * 2)
        place(out, fft_filter(s * adsr(n, 0.005, 0.03, 0.6, 0.04), low=4000, high=250), secs(0.14 * i), 1.0 - 0.12 * i)
    return out


def thanks() -> np.ndarray:
    """'Ya-ay!': a cheerful two-step glide from a townsperson."""
    out = np.zeros(secs(0.75))
    for start, pts, g in [(0.0, [(0, 520), (0.12, 600)], 0.8), (0.16, [(0, 600), (0.1, 880), (0.5, 820)], 1.0)]:
        dur = pts[-1][0]
        n = secs(dur)
        f = vibrato(glide(n, pts), 6.5, 0.35, delay=0.08)
        s = 0.55 * osc("triangle", f) + 0.45 * osc("square", f, duty=0.2)
        place(out, fft_filter(s * adsr(n, 0.01, 0.05, 0.7, 0.12), low=3000, high=200), secs(start), g)
    return out


def drip() -> np.ndarray:
    """Plip: the hose while the truck is still moving (the press is answered, no water yet)."""
    n = secs(0.14)
    f = glide(n, [(0, 1500), (0.14, 700)])
    return fft_filter(osc("sine", f) * perc(n, 0.002, 0.04), low=5000, high=200)


# Reused from PixelPals.


def star() -> np.ndarray:
    """Bright pickup blip: B5 then E6 (the coin interval)."""
    out = np.zeros(secs(0.28))
    for start, m, dur, g in [(0.0, 83, 0.06, 0.7), (0.055, 88, 0.22, 1.0)]:
        n = secs(dur)
        e = adsr(n, 0.002, 0.05, 0.5, 0.12)
        s = 0.7 * osc("square", np.full(n, midi(m)), duty=0.5) + 0.3 * osc("sine", np.full(n, midi(m + 12)))
        place(out, s * e, secs(start), g)
    return fft_filter(out, low=5500, high=150)



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



def party() -> np.ndarray:
    """Victory fanfare: da-da-da-DAAA-da-DAAAA with harmony, bass and a snare roll."""
    beat = 0.13
    melody = [(72, 1), (76, 1), (79, 1), (84, 3), (81, 1), (84, 6)]
    harmony = [(64, 1), (67, 1), (72, 1), (76, 3), (77, 1), (79, 6)]
    total = sum(d for _, d in melody) * beat + 0.4
    out = np.zeros(secs(total))
    for voice, kind, duty, g in [(melody, "square", 0.25, 0.6), (harmony, "square", 0.5, 0.3)]:
        t = 0.0
        for i, (m, d) in enumerate(voice):
            last = i == len(voice) - 1
            n = secs(d * beat + (0.35 if last else 0.0))
            f = np.full(n, midi(m))
            if d >= 3:
                f = vibrato(f, 6.5, 0.3, delay=0.12)
            e = adsr(n, 0.004, 0.06, 0.65, 0.25 if last else 0.03)
            place(out, osc(kind, f, duty=duty) * e, secs(t), g)
            t += d * beat
    t = 0.0
    for m, d in [(48, 3), (53, 3), (55, 1), (48, 6)]:
        n = secs(d * beat + 0.02)
        place(out, osc("triangle", np.full(n, midi(m))) * adsr(n, 0.004, 0.05, 0.8, 0.03), secs(t), 0.5)
        t += d * beat
    rng = np.random.default_rng(77)
    for i in range(8):  # soft snare roll into the last note
        n = secs(0.06)
        s = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=800) * perc(n, 0.001, 0.02)
        place(out, s, secs(5 * beat + i * beat / 4), 0.15 + 0.03 * i)
    n = secs(0.9)
    cym = fft_filter(osc("white", np.ones(n), rng=rng), low=9000, high=4000) * perc(n, 0.002, 0.25)
    place(out, cym, secs(7 * beat), 0.12)
    return fft_filter(out, low=7000, high=60)


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
# Music: patterns rendered into a circular buffer, so the loop has no seam
# ----------------------------------------------------------------------------

S = "-"  # sustain the previous note


def render_song(bpm: float, bars: int, steps_per_bar: int, lead: list, bass: list, chords: list,
                lead_duty: float, lead_low: float, lead_gain: float, drums: str, seed: int,
                arp_gain: float, lead_kind: str = "square") -> tuple[np.ndarray, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    total = bar_len * bars
    step = bar_len // steps_per_bar
    assert step * steps_per_bar == bar_len
    rng = np.random.default_rng(seed)

    def voice_track(pattern: list, kind: str, duty: float, gain: float, env_s: float, vib: bool) -> np.ndarray:
        buf = np.zeros(total)
        flat = [x for bar in pattern for x in bar]
        assert len(flat) == bars * steps_per_bar, (len(flat), bars * steps_per_bar)
        i = 0
        while i < len(flat):
            m = flat[i]
            if m is None or m == S:
                i += 1
                continue
            j = i + 1
            while j < len(flat) and flat[j] == S:
                j += 1
            n = (j - i) * step - secs(0.012)
            f = np.full(n, midi(m))
            if vib and n > secs(0.3):
                f = vibrato(f, 5.5, 0.2, delay=0.15)
            e = adsr(n, 0.004, 0.08, env_s, 0.05)
            place(buf, osc(kind, f, duty=duty) * e, i * step, gain, circular=True)
            i = j
        return buf

    lead_buf = fft_filter(voice_track(lead, lead_kind, lead_duty, lead_gain, 0.55, True), low=lead_low, circular=True)
    bass_buf = fft_filter(voice_track(bass, "triangle", 0.5, 0.75, 0.8, False), low=1500, circular=True)

    # Soft chord arpeggio (16ths) for sparkle.
    arp_buf = np.zeros(total)
    sixteenth = bar_len // 16
    for b, chord in enumerate(chords):
        for k in range(16):
            m = chord[k % len(chord)] + 12
            n = sixteenth - secs(0.005)
            s = osc("square", np.full(n, midi(m)), duty=0.125) * perc(n, 0.002, 0.04)
            place(arp_buf, s, b * bar_len + k * sixteenth, arp_gain, circular=True)
    arp_buf = fft_filter(arp_buf, low=3500, circular=True)

    drum_buf = np.zeros(total)
    kick_n = secs(0.16)
    kick = osc("sine", glide(kick_n, [(0, 140), (0.1, 50), (0.16, 45)])) * perc(kick_n, 0.002, 0.06)
    for b in range(bars):
        for k, ch in enumerate(drums):
            pos = b * bar_len + k * sixteenth
            if ch == "k":
                place(drum_buf, kick, pos, 0.9, circular=True)
            elif ch == "s":
                n = secs(0.14)
                sn = fft_filter(osc("white", np.ones(n), rng=rng), low=5000, high=900) * perc(n, 0.001, 0.045)
                body = osc("triangle", glide(n, [(0, 230), (0.14, 170)])) * perc(n, 0.001, 0.03)
                place(drum_buf, sn * 0.5 + body * 0.25, pos, 1.0, circular=True)
            elif ch == "h":
                n = secs(0.04)
                hh = fft_filter(osc("white", np.ones(n), rng=rng), high=7000) * perc(n, 0.001, 0.01)
                place(drum_buf, hh, pos, 0.18, circular=True)
    drum_buf = fft_filter(drum_buf, low=9000, circular=True)

    mix = lead_buf + bass_buf + arp_buf + drum_buf
    mix = fft_filter(mix, high=30, circular=True)  # removes DC, keeps the loop circular
    return mix, bar_len


# C major, 140 BPM, 12 bars of 8ths: A (C G Am F x2) + B (F G F G).
_TRIADS = {48: [60, 64, 67], 43: [55, 59, 62], 45: [57, 60, 64], 41: [53, 57, 60],
           53: [65, 69, 72], 50: [62, 66, 69], 46: [58, 62, 65], 40: [52, 55, 59]}

# F major, 100 BPM, 8 bars of quarters: F Dm Bb C x2.
MENU_LEAD = [
    [81, S, 77, 79], [81, S, 74, S], [74, 77, 82, S], [79, S, S, None],
    [81, 84, 81, 77], [79, 77, 74, S], [77, 74, 70, 74], [72, S, 76, S],
]
_MENU_ROOTS = [53, 50, 46, 48, 53, 50, 46, 48]
MENU_BASS = [[r, S, r + 7, S] for r in _MENU_ROOTS]
MENU_CHORDS = [_TRIADS[r if r != 48 else 48] for r in _MENU_ROOTS]
MENU_DRUMS = "k---h---k---h---"


# G major, 108 BPM (a bar is a whole number of samples), 16 bars of 8ths:
# A (G C D G x2) + B (Em C G D, Em C D G). Brassy saw lead, bouncy drums.
TOWN_LEAD = [
    [67, S, 71, 74, 79, S, 74, 71], [72, S, 76, 79, 76, S, 72, S],
    [74, 78, 81, S, 78, 74, 71, 74], [79, S, S, 74, 71, S, None, None],
    [67, 71, 74, 71, 79, S, 74, S], [76, S, 72, 76, 79, S, 84, S],
    [81, 79, 78, 76, 74, S, 78, S], [79, S, 74, S, 67, S, None, None],
    [76, S, 79, S, 83, S, 79, 76], [72, S, 76, S, 79, 81, 79, S],
    [74, S, 79, 83, 86, S, 83, 79], [81, S, 78, S, 74, S, None, None],
    [76, 79, 76, 71, 76, S, 79, S], [84, S, 81, S, 79, 76, 72, S],
    [74, 76, 78, 79, 81, S, 78, 74], [79, S, S, S, 67, S, 71, 74],
]
_TOWN_ROOTS = [43, 48, 50, 43, 43, 48, 50, 43, 40, 48, 43, 50, 40, 48, 50, 43]
TOWN_BASS = [[r, S, r + 12, r, r + 7, S, r + 12, r] for r in _TOWN_ROOTS]
TOWN_CHORDS = [_TRIADS[r] + [_TRIADS[r][1]] for r in _TOWN_ROOTS]
TOWN_DRUMS = "k-h-s-hkk-h-s-hh"


def music_town() -> tuple[np.ndarray, int]:
    return render_song(108, 16, 8, TOWN_LEAD, TOWN_BASS, TOWN_CHORDS, 0.5, 2400, 0.5,
                       TOWN_DRUMS, 108, 0.12, lead_kind="saw")


def music_menu() -> tuple[np.ndarray, int]:
    chords = [[m - 12 for m in c] for c in MENU_CHORDS]
    return render_song(100, 8, 4, MENU_LEAD, MENU_BASS, chords, 0.5, 2600, 0.5,
                       MENU_DRUMS, 100, 0.12)



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
    "siren_1": siren_hilo, "siren_2": siren_whoop, "siren_3": siren_yelp, "horn": horn,
    "spray_start": spray_start, "hiss_out": hiss_out, "fire_start": fire_start,
    "ladder_up": ladder_up, "ladder_down": ladder_down,
    "meow_1": meow_1, "meow_2": meow_2, "meow_3": meow_3, "purr": purr,
    "boing": boing, "star": star, "badge": badge, "super_spray": super_spray,
    "ready": ready, "join": join, "select": select, "bark_1": bark_1, "bark_2": bark_2,
    "giggle": giggle, "thanks": thanks, "drip": drip, "whoosh": whoosh, "party": party,
}
# Gameplay loops: seamless, normalised like SFX (the level sets their volume live).
LOOPS = {"engine_loop": engine_loop, "spray_loop": spray_loop, "fire_crackle_loop": fire_crackle_loop}
MUSIC = {"music_menu": music_menu, "music_town": music_town}


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
    rows = ([(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in LOOPS.items()]
            + [(n, f, True) for n, f in MUSIC.items()])
    for name, fn, loop in rows:
        if loop:
            made = fn()
            x, bar_len = made if isinstance(made, tuple) else (made, len(made))
            x = normalise(x, MUSIC_LUFS if name in MUSIC else SFX_LUFS, loop=True)
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
    if total_bytes > 8e6:  # 16-bar town song (35 s); PixelPals keeps 6 MB
        ok = False
        print("FAIL: audio total above 8 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
