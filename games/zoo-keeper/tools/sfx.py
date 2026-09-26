"""Zoo Keeper sound synth: animal voices, sound effects and both music loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR] [--only name,name]

The synth core (oscillators with polyBLEP, ADSR, glides, vibrato, zero-phase
filters, loudness measurement) is copied from PixelPals's tools/sfx.py. New
here: a formant voice (a buzzy source through time-varying band-pass
resonators at vowel formants) for the animals, and a marimba for the music.
Everything is seeded, so a rerun writes byte-identical files. Output:
game/audio/<name>.wav, 16-bit mono 44100 Hz.

Loudness: SFX about -15 LUFS, animal voices -13 LUFS (rabbits softer on
purpose), music MUSIC_LUFS; no file peaks above -1 dBFS. The report printed
at the end is the verification: peak, RMS, LUFS, length, and for the music
loops the bar count and the loop-seam continuity. With --check DIR it also
writes spectrogram + waveform PNGs to DIR.
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
# Formant voice (new for Zoo Keeper): a buzzy source through time-varying
# band-pass resonators at vowel formants, so a saw can say "ooh" and "aah".
# ----------------------------------------------------------------------------

VOWELS = {  # F1, F2, F3 in Hz (adult averages; animals scale them)
    "u": (300, 870, 2240), "o": (570, 840, 2410), "a": (730, 1090, 2440),
    "e": (530, 1840, 2480), "i": (270, 2290, 3010), "m": (250, 1100, 2200),
}


def bandpass_tv(x: np.ndarray, fc: np.ndarray, q: float) -> np.ndarray:
    """RBJ band-pass (0 dB peak) with a per-sample centre frequency."""
    fc = np.broadcast_to(np.asarray(fc, dtype=np.float64), x.shape)
    w0 = 2 * np.pi * np.clip(fc, 30, SR * 0.45) / SR
    alpha = np.sin(w0) / (2 * q)
    a0 = 1 + alpha
    b0 = (alpha / a0).tolist()
    a1 = (-2 * np.cos(w0) / a0).tolist()
    a2 = ((1 - alpha) / a0).tolist()
    y = np.empty_like(x)
    x1 = x2 = y1 = y2 = 0.0
    for i, xi in enumerate(x.tolist()):
        yi = b0[i] * xi - b0[i] * x2 - a1[i] * y1 - a2[i] * y2
        x2, x1, y2, y1 = x1, xi, y1, yi
        y[i] = yi
    return y


def vowel_track(n: int, pts: list[tuple[float, str]], scale: float = 1.0) -> list[np.ndarray]:
    """Three formant-frequency curves through (time_s, vowel) breakpoints."""
    t = np.arange(n) / SR
    ts = [p[0] for p in pts]
    return [np.interp(t, ts, [VOWELS[p[1]][k] * scale for p in pts]) for k in range(3)]


def formant_voice(src: np.ndarray, formants: list[np.ndarray], q: float = 6.0,
                  gains: tuple = (1.0, 0.7, 0.35)) -> np.ndarray:
    out = np.zeros_like(src)
    for f, g in zip(formants, gains):
        out += g * bandpass_tv(src, f, q)
    return out


def syllable(dur: float, pitch: list[tuple[float, float]], vowels: list[tuple[float, str]],
             fscale: float = 1.0, kind: str = "saw", q: float = 6.0, vib: float = 0.3,
             rough: float = 0.0, breath: float = 0.05, seed: int = 0,
             attack: float = 0.02, release: float = 0.06) -> np.ndarray:
    n = secs(dur)
    f = vibrato(glide(n, pitch), 6.0, vib, delay=0.04)
    src = 0.7 * osc(kind, f, duty=0.35) + 0.3 * osc("square", f * 1.002, duty=0.2)
    if rough:
        src *= 1.0 + rough * np.sin(2 * np.pi * 70 * np.arange(n) / SR)
    rng = np.random.default_rng(seed)
    src += breath * osc("white", np.ones(n), rng=rng)
    v = formant_voice(src, vowel_track(n, vowels, fscale), q)
    return v * adsr(n, attack, 0.05, 0.85, release)


# ----------------------------------------------------------------------------
# Animal voices (2-3 variants each)
# ----------------------------------------------------------------------------


def monkey(variant: int) -> np.ndarray:
    """'Ooh-ooh-aah-aah': vowels sliding from oo to ah, pitch whooping up."""
    plans = [
        [("u", 440, 0.16), ("u", 500, 0.16), ("a", 620, 0.22), ("a", 700, 0.3)],
        [("u", 520, 0.13), ("a", 640, 0.15), ("a", 720, 0.15), ("a", 800, 0.28)],
        [("i", 700, 0.1), ("i", 760, 0.1), ("i", 820, 0.1), ("a", 900, 0.3)],
    ][variant]
    total = sum(p[2] + 0.05 for p in plans) + 0.1
    out = np.zeros(secs(total))
    t = 0.0
    for k, (v, hz, d) in enumerate(plans):
        s = syllable(d, [(0, hz * 0.85), (d * 0.5, hz * 1.12), (d, hz)], [(0, "u" if v == "a" else v), (d * 0.5, v), (d, v)],
                     fscale=1.35, q=5.0, vib=0.6, breath=0.08, seed=10 + k)
        place(out, s, secs(t), 0.8 + 0.1 * k)
        t += d + 0.05
    return fft_filter(out, low=6000, high=200)


def penguin(variant: int) -> np.ndarray:
    """A braying honk: 'haa-haa-HAAAW', square buzz through a nasal band."""
    plans = [[(0.18, 330), (0.18, 350), (0.55, 390)], [(0.14, 380), (0.5, 420)],
             [(0.12, 300), (0.12, 320), (0.12, 340), (0.45, 360)]][variant]
    total = sum(d + 0.07 for d, _ in plans) + 0.1
    out = np.zeros(secs(total))
    t = 0.0
    for k, (d, hz) in enumerate(plans):
        s = syllable(d, [(0, hz * 0.9), (d * 0.3, hz * 1.1), (d, hz * 0.95)], [(0, "e"), (d * 0.4, "a"), (d, "o")],
                     fscale=1.2, kind="square", q=9.0, vib=0.8, rough=0.45, breath=0.06, seed=20 + k, attack=0.012)
        place(out, s, secs(t), 0.7 + 0.15 * k)
        t += d + 0.07
    return fft_filter(out, low=4500, high=350)


def seal(variant: int) -> np.ndarray:
    """Short noisy barks: 'ork! ork!'."""
    barks = [[0.0, 0.26], [0.0, 0.22, 0.44], [0.0]][variant]
    base = [260, 300, 230][variant]
    out = np.zeros(secs(max(barks) + 0.4))
    rng = np.random.default_rng(30 + variant)
    for k, st in enumerate(barks):
        d = 0.17
        n = secs(d)
        hz = base * (1.0 + 0.06 * k)
        s = syllable(d, [(0, hz * 1.25), (0.04, hz * 1.1), (d, hz * 0.75)], [(0, "a"), (d, "o")],
                     fscale=0.9, q=4.0, vib=0.0, rough=0.7, breath=0.25, seed=31 + k, attack=0.004, release=0.05)
        grit = fft_filter(osc("white", np.ones(n), rng=rng), low=2500, high=500) * perc(n, 0.003, 0.05) * 0.5
        place(out, s + grit, secs(st), 1.0)
    return fft_filter(out, low=5000, high=150)


def rabbit(variant: int) -> np.ndarray:
    """Rabbits are nearly silent: a soft nose-twitch 'pip-pip' and a sniff."""
    pips = [[0.0, 0.11, 0.3, 0.41], [0.0, 0.1, 0.2], [0.0, 0.14]][variant]
    base = [2100, 2400, 1900][variant]
    out = np.zeros(secs(max(pips) + 0.55))
    rng = np.random.default_rng(40 + variant)
    for k, st in enumerate(pips):
        n = secs(0.05)
        f = glide(n, [(0, base * 0.8), (0.02, base * 1.15), (0.05, base)])
        s = (0.8 * osc("sine", f) + 0.2 * osc("triangle", f * 0.5)) * perc(n, 0.004, 0.018)
        place(out, s, secs(st), 0.8)
    n = secs(0.22)
    sniff = fft_filter(osc("white", np.ones(n), rng=rng), low=6500, high=2500) * env_pts(n, [(0, 0), (0.08, 1), (0.22, 0)])
    place(out, sniff, secs(max(pips) + 0.14), 0.5)
    return fft_filter(out, low=9000, high=400)


def elephant(variant: int) -> np.ndarray:
    """Trumpet: a brassy saw whose pitch rises, with a growl and a breathy edge."""
    d = [0.95, 0.75, 1.1][variant]
    hz = [360, 420, 320][variant]
    n = secs(d)
    f = glide(n, [(0, hz * 0.7), (0.12, hz * 1.5), (d * 0.6, hz * 1.7), (d, hz * 1.35)])
    f = vibrato(f, 7.5, 0.7, delay=0.15)
    t = np.arange(n) / SR
    growl = 1.0 + 0.55 * np.sin(2 * np.pi * 34 * t) * np.exp(-t / 0.25)
    src = (0.75 * osc("saw", f) + 0.35 * osc("square", f * 2, duty=0.3)) * growl
    rng = np.random.default_rng(50 + variant)
    src += 0.25 * osc("white", np.ones(n), rng=rng)
    brass = formant_voice(src, [np.full(n, 1100.0), np.full(n, 2300.0), np.full(n, 3400.0)], q=3.0,
                          gains=(1.0, 0.8, 0.4))
    brass += 0.3 * fft_filter(src, low=900)
    out = brass * adsr(n, 0.05, 0.1, 0.9, 0.2)
    return fft_filter(out, low=6500, high=250)


def giraffe(variant: int) -> np.ndarray:
    """A soft hum 'mmm-hmm' (giraffes are quiet; they hum)."""
    parts = [[(0.0, 0.5, 170, 150)], [(0.0, 0.25, 160, 175), (0.32, 0.4, 185, 150)]][variant]
    out = np.zeros(secs(max(p[0] + p[1] for p in parts) + 0.2))
    for k, (st, d, h0, h1) in enumerate(parts):
        n = secs(d)
        f = vibrato(glide(n, [(0, h0), (d, h1)]), 5.0, 0.3)
        src = 0.6 * osc("triangle", f) + 0.4 * osc("saw", f)
        v = formant_voice(src, vowel_track(n, [(0, "m"), (d, "u")], 1.1), q=4.0, gains=(1.0, 0.25, 0.1))
        v += 0.4 * osc("sine", f) * 0.5
        place(out, v * adsr(n, 0.07, 0.08, 0.85, 0.12), secs(st), 1.0)
    return fft_filter(out, low=2500, high=90)


# ----------------------------------------------------------------------------
# Sound effects
# ----------------------------------------------------------------------------


def throw() -> np.ndarray:
    """A quick toss: a short airy whoosh with a soft 'fwip' on top."""
    n = secs(0.3)
    rng = np.random.default_rng(60)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 600), (0.12, 4000), (0.3, 900)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff) * env_pts(n, [(0, 0), (0.1, 1), (0.3, 0)]) ** 1.3
    m = secs(0.09)
    fwip = osc("sine", glide(m, [(0, 500), (0.09, 1300)])) * perc(m, 0.002, 0.04)
    out = np.zeros(n)
    place(out, fft_filter(y, high=200), 0)
    place(out, fwip, 0, 0.3)
    return out


def munch(variant: int) -> np.ndarray:
    """Chomp-chomp: crunchy noise bites with a soft jaw thump."""
    bites = [[0.0, 0.16], [0.0, 0.14, 0.28], [0.0, 0.2]][variant]
    out = np.zeros(secs(max(bites) + 0.2))
    rng = np.random.default_rng(70 + variant)
    for k, st in enumerate(bites):
        n = secs(0.11)
        crunch = osc("white", np.ones(n), rng=rng)
        crunch = fft_filter(crunch, low=4200 - 400 * variant, high=900) * perc(n, 0.002, 0.03)
        crunch *= 1.0 + 0.6 * (rng.random(n) > 0.9)
        thump = osc("sine", glide(n, [(0, 180), (0.11, 90)])) * perc(n, 0.002, 0.035)
        place(out, 0.7 * crunch + 0.6 * thump, secs(st), 1.0 - 0.1 * k)
    return out


def nope() -> np.ndarray:
    """A silly raspberry 'pffffbt': lips flapping (buzzy AM noise) with a sagging pitch."""
    n = secs(0.62)
    rng = np.random.default_rng(80)
    t = np.arange(n) / SR
    flap = glide(n, [(0, 55), (0.3, 42), (0.62, 30)])
    phase = np.cumsum(flap / SR)
    am = 0.5 + 0.5 * np.sign(np.sin(2 * np.pi * phase))
    air = fft_filter(osc("white", np.ones(n), rng=rng), low=2400, high=250)
    buzz = osc("saw", flap * 2.0) * 0.4
    s = (air * 0.8 + buzz) * (0.2 + 0.8 * am)
    s *= env_pts(n, [(0, 0), (0.04, 1), (0.45, 0.8), (0.62, 0)])
    pf = fft_filter(osc("white", np.ones(secs(0.12)), rng=rng), low=5000, high=1500) * env_pts(secs(0.12), [(0, 0), (0.03, 1), (0.12, 0)])
    out = np.zeros(secs(0.72))
    place(out, pf, 0, 0.35)
    place(out, s, secs(0.08), 1.0)
    return fft_filter(out, low=4500, high=60)


def wiggle() -> np.ndarray:
    """A springy 'boing-oing' for the hint wiggle and the magic swap."""
    n = secs(0.45)
    f = vibrato(glide(n, [(0, 380), (0.45, 520)]), 14, 3.0, decay=0.2)
    s = (0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * perc(n, 0.008, 0.16)
    return fft_filter(s, low=3500, high=120)


def star() -> np.ndarray:
    """Bright pickup blip: B5 then E6, with a sparkle."""
    out = np.zeros(secs(0.36))
    for start, m, dur, g in [(0.0, 83, 0.06, 0.7), (0.055, 88, 0.26, 1.0)]:
        n = secs(dur)
        e = adsr(n, 0.002, 0.05, 0.5, 0.14)
        s = 0.5 * osc("triangle", np.full(n, midi(m))) + 0.5 * osc("sine", np.full(n, midi(m + 12)))
        place(out, s * e, secs(start), g)
    return fft_filter(out, low=7000, high=150)


def bubble_pop() -> np.ndarray:
    """The thought bubble pops in: a round 'blup'."""
    n = secs(0.16)
    f = glide(n, [(0, 300), (0.05, 900), (0.16, 700)])
    s = osc("sine", f) * perc(n, 0.003, 0.05)
    click = np.zeros(n)
    click[:secs(0.003)] = np.linspace(1, 0, secs(0.003))
    return fft_filter(s + 0.2 * click, low=5000, high=120)


def bell() -> np.ndarray:
    """The zoo bell: a bright handbell with inharmonic partials, ringing out."""
    n = secs(1.8)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, (ratio, amp, dec) in enumerate([(1.0, 1.0, 0.9), (2.76, 0.55, 0.5), (5.4, 0.3, 0.25), (8.93, 0.18, 0.12), (2.0, 0.25, 0.7)]):
        out += amp * np.sin(2 * np.pi * midi(84) * ratio * t + k) * np.exp(-t / dec)
    e = np.minimum(t / 0.002, 1.0)
    out *= e
    second = np.concatenate([np.zeros(secs(0.28)), out[: n - secs(0.28)]]) * 0.7
    fade = min(n, secs(0.05))
    mix = out + second
    mix[n - fade:] *= np.linspace(1, 0, fade)
    return fft_filter(mix, low=9000, high=200)


def footstep(variant: int) -> np.ndarray:
    """A soft step on the sandy path."""
    n = secs(0.09)
    rng = np.random.default_rng(90 + variant)
    s = fft_filter(osc("white", np.ones(n), rng=rng), low=1400 + 500 * variant, high=150) * perc(n, 0.003, 0.025)
    thud = osc("sine", glide(n, [(0, 120), (0.09, 70)])) * perc(n, 0.002, 0.03)
    return 0.8 * s + 0.5 * thud


def arp_notes(notes: list[tuple[int, float]], kind: str = "triangle", tail: float = 0.18) -> np.ndarray:
    total = sum(d for _, d in notes) + tail
    out = np.zeros(secs(total))
    t = 0.0
    for i, (m, d) in enumerate(notes):
        last = i == len(notes) - 1
        n = secs(d + (tail if last else 0.03))
        s = marimba_note(m, n) if kind == "marimba" else osc(kind, np.full(n, midi(m))) * adsr(n, 0.003, 0.04, 0.55, 0.1)
        place(out, s, secs(t))
        t += d
    return fft_filter(out, low=7000, high=150)


def join() -> np.ndarray:
    return arp_notes([(67, 0.07), (71, 0.07), (74, 0.07), (79, 0.16)], kind="marimba")


def select() -> np.ndarray:
    n = secs(0.09)
    return marimba_note(84, n) * 0.9


def ready() -> np.ndarray:
    return arp_notes([(74, 0.09), (79, 0.25)], kind="marimba", tail=0.25)


def whoosh() -> np.ndarray:
    """Soft air swoosh (buddy change on the select screen)."""
    n = secs(0.45)
    rng = np.random.default_rng(88)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 250), (0.2, 2600), (0.45, 350)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.18, 1), (0.45, 0)]) ** 1.5
    return fft_filter(y * e, high=120)


def party() -> np.ndarray:
    """Party fanfare on marimba and brass-ish square: da-da-da-DAAA-da-DAAAA."""
    beat = 0.14
    melody = [(67, 1), (71, 1), (74, 1), (79, 3), (76, 1), (79, 6)]
    harmony = [(59, 1), (62, 1), (67, 1), (71, 3), (72, 1), (74, 6)]
    total = sum(d for _, d in melody) * beat + 0.6
    out = np.zeros(secs(total))
    for voice, g in [(melody, 0.7), (harmony, 0.35)]:
        t = 0.0
        for i, (m, d) in enumerate(voice):
            last = i == len(voice) - 1
            n = secs(d * beat + (0.45 if last else 0.02))
            f = np.full(n, midi(m))
            if d >= 3:
                f = vibrato(f, 6.0, 0.25, delay=0.1)
            e = adsr(n, 0.006, 0.06, 0.7, 0.3 if last else 0.03)
            s = 0.6 * osc("square", f, duty=0.3) + 0.4 * osc("triangle", f)
            place(out, fft_filter(s * e, low=3000), secs(t), g)
            place(out, marimba_note(m + 12, secs(0.3)), secs(t), g * 0.4)
            t += d * beat
    t = 0.0
    for m, d in [(43, 3), (48, 3), (50, 1), (43, 6)]:
        n = secs(d * beat + 0.02)
        place(out, osc("triangle", np.full(n, midi(m))) * adsr(n, 0.004, 0.05, 0.8, 0.03), secs(t), 0.5)
        t += d * beat
    rng = np.random.default_rng(77)
    n = secs(0.9)
    cym = fft_filter(osc("white", np.ones(n), rng=rng), low=9000, high=4000) * perc(n, 0.002, 0.25)
    place(out, cym, secs(7 * beat), 0.12)
    return fft_filter(out, low=7000, high=60)


# ----------------------------------------------------------------------------
# Music: a sunny marimba loop in G major at 100 BPM, rendered into a circular
# buffer so the loop has no seam.
# ----------------------------------------------------------------------------

S = "-"  # hold: no new note (marimba notes ring out on their own)


def marimba_note(m: float, n: int, decay: float = 0.32) -> np.ndarray:
    """Marimba-like bar: fundamental plus the 4th partial (ratio ~3.9) that dies fast, and a mallet tick."""
    t = np.arange(n) / SR
    f = midi(m)
    body = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    over = 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / (decay * 0.18))
    tick = 0.15 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / 0.008)
    e = np.minimum(t / 0.0015, 1.0)
    out = (body + over + tick) * e
    fade = min(n, secs(0.01))
    out[n - fade:] *= np.linspace(1, 0, fade)
    return out


def pluck(m: float, n: int) -> np.ndarray:
    """A ukulele-ish pluck for the off-beat chords."""
    t = np.arange(n) / SR
    f = midi(m)
    s = (0.6 * osc("triangle", np.full(n, f)) + 0.4 * osc("saw", np.full(n, f))) * np.exp(-t / 0.09)
    return fft_filter(s * np.minimum(t / 0.002, 1.0), low=2600)


# 12 bars of 8ths. Chords: G Em C D | G Em Am D | C D Em D (the D leads back to G).
ZOO_LEAD = [
    [67, 71, 74, 71, 72, 71, 69, 67], [64, 67, 71, S, 69, 67, 64, S],
    [64, 67, 72, S, 71, 69, 67, S], [66, 69, 74, S, 72, S, 69, S],
    [74, S, 71, 74, 79, S, 74, S], [76, S, 74, 71, 67, S, 71, S],
    [72, S, 69, 72, 76, S, 72, S], [74, S, 72, 69, 66, S, 62, S],
    [67, S, 72, S, 76, S, 72, S], [69, S, 74, S, 78, S, 74, S],
    [71, S, 76, S, 79, S, 76, 74], [72, 71, 69, 66, 69, S, None, None],
]
_ZOO_ROOTS = [43, 40, 36, 38, 43, 40, 45, 38, 36, 38, 40, 38]
_CHORD = {43: [55, 59, 62], 40: [52, 55, 59], 36: [52, 55, 60], 38: [54, 57, 62], 45: [57, 60, 64]}

# Menu: a gentle music-box tune, 8 bars of quarters, G major.
MENU_LEAD = [
    [79, 76, 74, 71], [72, 74, 76, S], [74, 71, 67, 69], [71, S, 74, S],
    [79, 76, 74, 71], [72, 76, 79, S], [78, 74, 76, 78], [79, S, S, None],
]
_MENU_ROOTS = [43, 36, 43, 38, 43, 36, 38, 43]


def render_zoo_song(bpm: float, lead: list, roots: list, steps: int, marimba_gain: float,
                    drums: bool, seed: int) -> tuple[np.ndarray, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    bars = len(lead)
    total = bar_len * bars
    step = bar_len // steps
    assert step * steps == bar_len
    rng = np.random.default_rng(seed)
    lead_buf = np.zeros(total)
    for b, bar in enumerate(lead):
        for k, m in enumerate(bar):
            if m is None or m == S:
                continue
            n = secs(0.9)
            place(lead_buf, marimba_note(m, n, decay=0.3 if drums else 0.6), b * bar_len + k * step, marimba_gain, circular=True)
            if not drums:  # music box: a soft octave shimmer
                place(lead_buf, marimba_note(m + 12, secs(0.5), decay=0.2), b * bar_len + k * step, marimba_gain * 0.25, circular=True)
    bass_buf = np.zeros(total)
    quarter = bar_len // 4
    for b, r in enumerate(roots):
        pattern = [r, r + 7, r + 12, r + 7] if drums else [r, None, r + 7, None]
        for k, m in enumerate(pattern):
            if m is None:
                continue
            n = quarter - secs(0.02)
            t = np.arange(n) / SR
            s = osc("triangle", np.full(n, midi(m))) * np.exp(-t / 0.22) * np.minimum(t / 0.004, 1.0)
            place(bass_buf, s, b * bar_len + k * quarter, 0.55, circular=True)
    bass_buf = fft_filter(bass_buf, low=1200, circular=True)
    chord_buf = np.zeros(total)
    if drums:
        eighth = bar_len // 8
        for b, r in enumerate(roots):
            for k in (1, 3, 5, 7):  # off-beats
                for m in _CHORD[r]:
                    place(chord_buf, pluck(m + 12, eighth), b * bar_len + k * eighth, 0.12, circular=True)
    drum_buf = np.zeros(total)
    if drums:
        sixteenth = bar_len // 16
        kick_n = secs(0.14)
        kick = osc("sine", glide(kick_n, [(0, 120), (0.08, 55), (0.14, 50)])) * perc(kick_n, 0.002, 0.05)
        for b in range(bars):
            for k in range(16):
                pos = b * bar_len + k * sixteenth
                if k in (0, 8):
                    place(drum_buf, kick, pos, 0.8, circular=True)
                if k in (4, 12):  # a woody clap
                    n = secs(0.08)
                    wb = osc("sine", np.full(n, 900.0)) * perc(n, 0.001, 0.02)
                    cl = fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=1200) * perc(n, 0.001, 0.02)
                    place(drum_buf, 0.3 * wb + 0.4 * cl, pos, 0.8, circular=True)
                n = secs(0.035)
                sh = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.004, 0.01)
                place(drum_buf, sh, pos, 0.12 if k % 2 == 0 else 0.07, circular=True)
        drum_buf = fft_filter(drum_buf, low=10000, circular=True)
    mix = lead_buf + bass_buf + chord_buf + drum_buf
    mix = fft_filter(mix, high=30, circular=True)
    return mix, bar_len


def music_zoo() -> tuple[np.ndarray, int]:
    return render_zoo_song(100, ZOO_LEAD, _ZOO_ROOTS, 8, 0.6, True, 100)


def music_menu() -> tuple[np.ndarray, int]:
    return render_zoo_song(100, MENU_LEAD, _MENU_ROOTS, 4, 0.5, False, 101)


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


def _variants(fn, count: int) -> dict:
    return {f"{fn.__name__}_{i + 1}": (lambda i=i: fn(i)) for i in range(count)}


SFX = {
    **_variants(monkey, 3), **_variants(penguin, 3), **_variants(seal, 3), **_variants(rabbit, 3),
    **_variants(elephant, 3), **_variants(giraffe, 2),
    "throw": throw, **_variants(munch, 3), "nope": nope, "wiggle": wiggle, "star": star,
    "bubble_pop": bubble_pop, "bell": bell, **_variants(footstep, 2), "join": join, "select": select,
    "ready": ready, "party": party, "whoosh": whoosh,
}
MUSIC = {"music_menu": music_menu, "music_zoo": music_zoo}
# Animal voices sit a little above the other sounds (the game also ducks the music under them).
VOICE_LUFS = -13.0
VOICES = ("monkey", "penguin", "seal", "rabbit", "elephant", "giraffe")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", type=Path, help="write spectrogram/seam PNGs to this directory")
    ap.add_argument("--only", help="comma-separated names to (re)build")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.check:
        args.check.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None

    ok = True
    total_bytes = 0
    print(f"{'file':<16}{'secs':>7}{'peak dBFS':>11}{'RMS dBFS':>10}{'LUFS':>8}{'ST max':>8}{'DC':>10}")
    rows = [(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in MUSIC.items()]
    for name, fn, loop in rows:
        if only and name not in only:
            p = OUT / f"{name}.wav"
            if p.exists():
                total_bytes += p.stat().st_size
            continue
        if loop:
            x, bar_len = fn()
            x = normalise(x, MUSIC_LUFS, loop=True)
        else:
            target = VOICE_LUFS if name.startswith(VOICES) else SFX_LUFS
            if name.startswith("rabbit"):
                target = SFX_LUFS - 3.0  # soft on purpose: rabbits are nearly silent
            x = normalise(fade_edges(fn()), target, loop=False)
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
    if total_bytes > 8e6:
        ok = False
        print("FAIL: audio total above 8 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
