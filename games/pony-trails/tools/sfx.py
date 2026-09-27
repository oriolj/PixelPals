"""Pony Trails sound synth: horse voices, hooves, the stable/trail/show effects and four music loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR] [--only name,name]

The synth core (oscillators with polyBLEP, ADSR, glides, vibrato, zero-phase
filters, loudness measurement) and the formant voice (a buzzy source through
time-varying band-pass resonators at vowel formants) are copied from Zoo
Keeper's tools/sfx.py. New here: the whinny (a falling pitch with a fast
wobble through i -> e -> a), hoof clops and the seamless per-gait hoof loops
(walk 1.0 s / 4 beats, trot 0.5 s / 2 beats, canter 0.6 s / 3 beats per
stride cycle, the same cycles the animations use), creaks (stick-slip pulse
trains through wooden resonances), and the music (every beat and step a
whole number of samples, asserted).

Everything is seeded, so a rerun writes byte-identical files. Output:
game/audio/<name>.wav, 16-bit mono 44100 Hz. Loudness: SFX -15 LUFS, voices
-13 LUFS, loops -14 LUFS; no file peaks above -1 dBFS. The report printed at
the end is the verification: peak, RMS, LUFS, length, and for the loops the
bar/cycle count and the loop-seam continuity. With --check DIR it also writes
spectrogram + waveform PNGs (and seam PNGs for the loops) to DIR.
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
# Instruments (marimba and pluck from Zoo Keeper; the rest new here)
# ----------------------------------------------------------------------------

S = "-"  # hold: no new note


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


def pad_note(m: float, n: int, attack: float = 0.25) -> np.ndarray:
    """A soft warm pad: three detuned triangles, slow attack and release."""
    f = midi(m)
    s = sum(osc("triangle", np.full(n, f * d)) for d in (0.997, 1.0, 1.003)) / 3.0
    return s * adsr(n, attack, 0.2, 0.8, min(0.4, n / SR * 0.4))


def brass_note(m: float, n: int, vib: bool = False) -> np.ndarray:
    f = np.full(n, midi(m))
    if vib:
        f = vibrato(f, 5.5, 0.2, delay=0.15)
    s = 0.6 * osc("square", f, duty=0.3) + 0.4 * osc("saw", f)
    return fft_filter(s * adsr(n, 0.015, 0.08, 0.7, min(0.08, n / SR * 0.3)), low=2800)


def box_note(m: float, n: int) -> np.ndarray:
    """Music box tine: a bright bell-like sine with a fast upper partial."""
    t = np.arange(n) / SR
    f = midi(m)
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / 0.5) + 0.3 * np.sin(2 * np.pi * f * 4.0 * t) * np.exp(-t / 0.06)
    s *= np.minimum(t / 0.001, 1.0)
    fade = min(n, secs(0.01))
    s[n - fade:] *= np.linspace(1, 0, fade)
    return s


def kick(n: int | None = None) -> np.ndarray:
    n = n or secs(0.14)
    return osc("sine", glide(n, [(0, 120), (0.08, 55), (0.14, 50)])) * perc(n, 0.002, 0.05)


def snare(rng) -> np.ndarray:
    n = secs(0.14)
    body = osc("sine", np.full(n, 200.0)) * perc(n, 0.001, 0.03)
    noise = fft_filter(osc("white", np.ones(n), rng=rng), low=7000, high=1500) * perc(n, 0.001, 0.05)
    return 0.4 * body + 0.6 * noise


def hat(rng) -> np.ndarray:
    n = secs(0.035)
    return fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.002, 0.01)


def woodblock(m: float = 84) -> np.ndarray:
    n = secs(0.07)
    t = np.arange(n) / SR
    f = midi(m)
    return (np.sin(2 * np.pi * f * t) + 0.4 * np.sin(2 * np.pi * f * 2.7 * t)) * np.exp(-t / 0.015)


# ----------------------------------------------------------------------------
# Horse voices
# ----------------------------------------------------------------------------


def _snort_tail(n: int, seed: int, low: float = 1800) -> np.ndarray:
    """A nasal noise puff with a lip flutter."""
    rng = np.random.default_rng(seed)
    t = np.arange(n) / SR
    noise = fft_filter(osc("white", np.ones(n), rng=rng), low=low, high=180)
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 26 * t)
    return noise * flutter * env_pts(n, [(0, 0), (0.02, 1), (n / SR * 0.5, 0.6), (n / SR, 0)])


def whinny(base: float, dur: float, rate: float, seed: int, fscale: float = 1.3,
           snort: bool = True) -> np.ndarray:
    """High bright onset that falls through a fast pitch wobble, nasal i -> e -> a, breathy tail."""
    n = secs(dur)
    t = np.arange(n) / SR
    f = glide(n, [(0, base * 0.9), (dur * 0.1, base * 1.12), (dur * 0.35, base * 0.95),
                  (dur * 0.8, base * 0.6), (dur, base * 0.45)])
    depth = 1.2 + 1.3 * np.clip(t / (dur * 0.4), 0, 1)       # the wobble grows as it falls
    f = f * 2.0 ** (depth / 12.0 * np.sin(2 * np.pi * rate * t))
    src = 0.65 * osc("saw", f) + 0.35 * osc("square", f * 1.003, duty=0.25)
    rng = np.random.default_rng(seed)
    breath = np.clip((t - dur * 0.5) / (dur * 0.5), 0, 1) * 0.35 + 0.06
    src = src + breath * osc("white", np.ones(n), rng=rng)
    v = formant_voice(src, vowel_track(n, [(0, "i"), (dur * 0.3, "e"), (dur * 0.75, "a"), (dur, "a")], fscale),
                      q=5.0, gains=(1.0, 0.8, 0.35))
    trem = 1.0 + 0.3 * np.sin(2 * np.pi * rate * t)
    v = v * trem * adsr(n, 0.03, 0.1, 0.85, dur * 0.35)
    out = np.zeros(n + (secs(0.3) if snort else secs(0.05)))
    place(out, v, 0)
    if snort:
        m = secs(0.2)
        place(out, _snort_tail(m, seed + 7), n - secs(0.03), 0.35)
    return fft_filter(out, low=5500, high=200)


def neigh(variant: int) -> np.ndarray:
    base, dur, rate = [(820, 1.0, 14.0), (900, 0.85, 16.0), (760, 1.15, 13.0), (860, 0.95, 17.0)][variant]
    return whinny(base, dur, rate, 100 + variant)


def foal_neigh(variant: int) -> np.ndarray:
    base, dur, rate = [(1150, 0.55, 17.0), (1250, 0.45, 18.0)][variant]
    return whinny(base, dur, rate, 110 + variant, fscale=1.55, snort=False)


def snort() -> np.ndarray:
    n = secs(0.38)
    out = np.zeros(secs(0.45))
    place(out, _snort_tail(n, 120, low=1500), 0, 1.0)
    rng = np.random.default_rng(121)
    m = secs(0.12)
    lips = osc("saw", glide(m, [(0, 70), (0.12, 45)])) * perc(m, 0.004, 0.05)
    place(out, fft_filter(lips, low=900), secs(0.05), 0.4)
    return fft_filter(out, low=4000, high=120)


def nicker() -> np.ndarray:
    """Soft low 'hu-hu-hu': a few rumbling pulses on 'm/u'."""
    pulses = [(0.0, 140), (0.13, 130), (0.26, 122), (0.39, 112)]
    out = np.zeros(secs(0.7))
    for k, (st, hz) in enumerate(pulses):
        d = 0.1
        s = syllable(d, [(0, hz * 1.08), (d, hz * 0.92)], [(0, "u"), (d, "m")], fscale=0.9, q=4.0, vib=0.0,
                     rough=0.5, breath=0.15, seed=130 + k, attack=0.01, release=0.04)
        place(out, s, secs(st), 1.0 - 0.12 * k)
    return fft_filter(out, low=2500, high=70)


# ----------------------------------------------------------------------------
# Hooves: seamless clip-clop loops, one per gait
# ----------------------------------------------------------------------------


def clop(pitch: float, seed: int, crisp: float = 1.0) -> np.ndarray:
    """A hoof on packed dirt: a hollow woody knock, a low body, a gritty click."""
    n = secs(0.09)
    t = np.arange(n) / SR
    rng = np.random.default_rng(seed)
    knock = (np.sin(2 * np.pi * pitch * t) + 0.35 * np.sin(2 * np.pi * pitch * 2.4 * t)) * np.exp(-t / 0.018)
    body = np.sin(2 * np.pi * 170 * t) * np.exp(-t / 0.03)
    grit = fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=700) * np.exp(-t / 0.007)
    s = 0.7 * knock + 0.5 * body + 0.45 * crisp * grit
    s *= np.minimum(t / 0.0008, 1.0)
    fade = secs(0.01)
    s[n - fade:] *= np.linspace(1, 0, fade)
    return s


def hoof_loop(cycle: float, cycles: int, beats: list[float], pitches: list[float], gains: list[float],
              seed: int, flam: float = 0.0, crisp: float = 1.0) -> tuple[np.ndarray, int]:
    cyc = secs(cycle)
    assert abs(cycle * SR - cyc) < 1e-6
    total = cyc * cycles
    buf = np.zeros(total)
    k = 0
    for c in range(cycles):
        for b, p, g in zip(beats, pitches, gains):
            jitter = 1.0 + 0.02 * ((k * 7) % 5 - 2)
            place(buf, clop(p * jitter, seed + k, crisp), c * cyc + secs(b), g, circular=True)
            if flam:
                place(buf, clop(p * 0.92, seed + 50 + k, crisp), c * cyc + secs(b + flam), g * 0.6, circular=True)
            k += 1
    return fft_filter(buf, high=60, low=9000, circular=True), cyc


def walk_loop() -> tuple[np.ndarray, int]:
    return hoof_loop(1.0, 2, [0.0, 0.25, 0.5, 0.75], [640, 560, 610, 540], [0.8, 0.65, 0.75, 0.6], 200, crisp=0.6)


def trot_loop() -> tuple[np.ndarray, int]:
    # Two beats per stride: each beat is a diagonal pair landing almost together.
    return hoof_loop(0.5, 4, [0.0, 0.25], [700, 650], [1.0, 0.9], 220, flam=0.014, crisp=1.0)


def canter_loop() -> tuple[np.ndarray, int]:
    # Ba-da-DUM ... (three beats, then the moment of suspension).
    return hoof_loop(0.6, 3, [0.0, 0.12, 0.24], [600, 660, 560], [0.7, 0.8, 1.0], 240, crisp=0.9)


# ----------------------------------------------------------------------------
# Sound effects
# ----------------------------------------------------------------------------


def whoosh(dur: float = 0.45, seed: int = 88, top: float = 2600) -> np.ndarray:
    n = secs(dur)
    rng = np.random.default_rng(seed)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 250), (dur * 0.45, top), (dur, 350)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (dur * 0.4, 1), (dur, 0)]) ** 1.5
    return fft_filter(y * e, high=120)


def jump_hup() -> np.ndarray:
    out = np.zeros(secs(0.55))
    place(out, whoosh(0.5, 301, 3200), 0, 0.6)
    s = syllable(0.16, [(0, 240), (0.06, 330), (0.16, 300)], [(0, "u"), (0.08, "a"), (0.16, "a")],
                 fscale=1.1, q=5.0, vib=0.0, breath=0.1, seed=302, attack=0.008, release=0.05)
    place(out, s, secs(0.02), 1.0)
    return fft_filter(out, low=6000, high=120)


def step_hup() -> np.ndarray:
    """The funny step-over: 'hup-hup' on two notes with a springy boing."""
    out = np.zeros(secs(0.7))
    for k, (st, hz) in enumerate([(0.0, 320), (0.2, 250)]):
        s = syllable(0.13, [(0, hz * 0.9), (0.05, hz * 1.1), (0.13, hz)], [(0, "u"), (0.13, "a")],
                     fscale=1.15, q=5.0, vib=0.0, breath=0.08, seed=310 + k, attack=0.008, release=0.04)
        place(out, s, secs(st), 1.0)
    n = secs(0.35)
    f = vibrato(glide(n, [(0, 220), (0.35, 300)]), 14, 3.0, decay=0.15)
    boing = (0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * perc(n, 0.006, 0.12)
    place(out, boing, secs(0.3), 0.6)
    return fft_filter(out, low=5000, high=100)


def land_thud() -> np.ndarray:
    n = secs(0.3)
    rng = np.random.default_rng(320)
    thump = osc("sine", glide(n, [(0, 95), (0.2, 48)])) * perc(n, 0.002, 0.07)
    dirt = fft_filter(osc("white", np.ones(n), rng=rng), low=1500, high=150) * perc(n, 0.002, 0.05)
    out = thump + 0.5 * dirt
    place(out, clop(520, 321), 0, 0.4)
    return fft_filter(out, low=4000, high=40)


def brush_scrub() -> np.ndarray:
    n = secs(0.4)
    rng = np.random.default_rng(330)
    t = np.arange(n) / SR
    noise = fft_filter(osc("white", np.ones(n), rng=rng), low=8000, high=2200)
    strokes = np.abs(np.sin(2 * np.pi * 2.5 * t)) ** 0.7        # two strokes back and forth
    grain = 0.7 + 0.3 * (rng.random(n) > 0.5)
    return noise * strokes * grain * env_pts(n, [(0, 0), (0.02, 1), (0.36, 1), (0.4, 0)])


def mud_poof() -> np.ndarray:
    n = secs(0.35)
    rng = np.random.default_rng(340)
    puff = fft_filter(osc("white", np.ones(n), rng=rng), low=900, high=80) * env_pts(n, [(0, 0), (0.03, 1), (0.35, 0)]) ** 2
    m = secs(0.12)
    pop = osc("sine", glide(m, [(0, 250), (0.04, 600), (0.12, 450)])) * perc(m, 0.003, 0.04)
    out = puff.copy()
    place(out, pop, 0, 0.5)
    return fft_filter(out, low=5000, high=60)


def munch(variant: int) -> np.ndarray:
    """Chomp-chomp: crunchy carrot bites with a soft jaw thump."""
    bites = [[0.0, 0.16], [0.0, 0.14, 0.28], [0.0, 0.2]][variant]
    out = np.zeros(secs(max(bites) + 0.2))
    rng = np.random.default_rng(70 + variant)
    for k, st in enumerate(bites):
        n = secs(0.11)
        crunch = osc("white", np.ones(n), rng=rng)
        crunch = fft_filter(crunch, low=4200 - 400 * variant, high=900) * perc(n, 0.002, 0.03)
        crunch *= 1.0 + 0.6 * (rng.random(n) > 0.9)
        thump = osc("sine", glide(n, [(0, 160), (0.11, 80)])) * perc(n, 0.002, 0.035)
        place(out, 0.7 * crunch + 0.6 * thump, secs(st), 1.0 - 0.1 * k)
    return out


def metal(freq: float, n: int, partials=((1.0, 1.0, 0.25), (2.71, 0.5, 0.12), (5.13, 0.3, 0.06), (7.9, 0.15, 0.03))) -> np.ndarray:
    t = np.arange(n) / SR
    s = sum(a * np.sin(2 * np.pi * freq * r * t + k) * np.exp(-t / d) for k, (r, a, d) in enumerate(partials))
    s *= np.minimum(t / 0.0005, 1.0)
    fade = min(n, secs(0.01))
    s[n - fade:] *= np.linspace(1, 0, fade)
    return s


def hoof_pick_ping() -> np.ndarray:
    out = np.zeros(secs(0.5))
    rng = np.random.default_rng(350)
    n = secs(0.12)
    scrape = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=1500) * env_pts(n, [(0, 0), (0.08, 1), (0.12, 0)])
    place(out, scrape, 0, 0.5)
    place(out, metal(2300, secs(0.38)), secs(0.1), 0.7)
    place(out, woodblock(90) * 0.5, secs(0.28), 0.5)   # the pebble lands
    return fft_filter(out, low=9000, high=200)


def horseshoe_clink() -> np.ndarray:
    out = np.zeros(secs(0.8))
    place(out, metal(1750, secs(0.6)), 0, 1.0)
    place(out, metal(1980, secs(0.5)), secs(0.14), 0.6)
    return fft_filter(out, low=10000, high=300)


def creak(dur: float, rates: list[tuple[float, float]], formants: tuple[float, float, float], seed: int,
          noise: float = 0.1) -> np.ndarray:
    """Stick-slip creak: a train of narrow pulses (irregular rate) through wooden resonances."""
    n = secs(dur)
    rng = np.random.default_rng(seed)
    rate = glide(n, rates) * (1.0 + 0.15 * np.cumsum(rng.normal(0, 0.02, n)).clip(-1, 1))
    src = osc("square", rate, duty=0.06) + 1.0
    src += noise * osc("white", np.ones(n), rng=rng)
    v = formant_voice(src - src.mean(), [np.full(n, f) for f in formants], q=10.0, gains=(1.0, 0.6, 0.3))
    return v * env_pts(n, [(0, 0), (0.04, 1), (dur * 0.8, 0.9), (dur, 0)])


def saddle_creak() -> np.ndarray:
    out = np.zeros(secs(0.75))
    place(out, creak(0.28, [(0, 45), (0.28, 30)], (420, 950, 1900), 360, noise=0.4), 0, 1.0)
    place(out, creak(0.3, [(0, 35), (0.3, 55)], (380, 880, 1800), 361, noise=0.4), secs(0.38), 0.8)
    return fft_filter(out, low=4500, high=120)


def door_creak() -> np.ndarray:
    out = creak(0.95, [(0, 18), (0.3, 42), (0.6, 30), (0.95, 60)], (700, 1500, 2600), 370)
    return fft_filter(out, low=6000, high=200)


def stable_cat_meow() -> np.ndarray:
    s = syllable(0.55, [(0, 560), (0.15, 820), (0.4, 700), (0.55, 520)], [(0, "m"), (0.08, "i"), (0.3, "a"), (0.55, "u")],
                 fscale=1.7, q=6.0, vib=0.4, breath=0.05, seed=380, attack=0.03, release=0.12)
    return fft_filter(s, low=7000, high=250)


def gate_open() -> np.ndarray:
    out = np.zeros(secs(1.1))
    place(out, metal(1400, secs(0.2), ((1.0, 1.0, 0.04), (2.3, 0.6, 0.03), (4.1, 0.3, 0.02))), 0, 0.7)  # latch
    place(out, creak(0.65, [(0, 25), (0.65, 45)], (600, 1300, 2400), 390), secs(0.08), 0.8)
    place(out, woodblock(62), secs(0.8), 0.9)   # the gate knocks open against its post
    place(out, woodblock(55) * 0.6, secs(0.88), 0.6)
    return fft_filter(out, low=6000, high=90)


def apple_pop() -> np.ndarray:
    out = np.zeros(secs(0.4))
    n = secs(0.12)
    f = glide(n, [(0, 350), (0.05, 1000), (0.12, 800)])
    place(out, osc("sine", f) * perc(n, 0.002, 0.05), 0, 1.0)
    for st, m in [(0.07, 84), (0.13, 91)]:
        k = secs(0.2)
        place(out, (0.5 * osc("triangle", np.full(k, midi(m))) + 0.5 * osc("sine", np.full(k, midi(m + 12)))) * adsr(k, 0.002, 0.05, 0.4, 0.12), secs(st), 0.45)
    return fft_filter(out, low=8000, high=150)


def flower_pick() -> np.ndarray:
    out = np.zeros(secs(0.5))
    n = secs(0.1)
    fwip = osc("sine", glide(n, [(0, 600), (0.1, 1700)])) * perc(n, 0.003, 0.04)
    place(out, fwip, 0, 0.5)
    for i, m in enumerate([79, 83, 86]):
        place(out, box_note(m, secs(0.35)), secs(0.06 + 0.06 * i), 0.5)
    return fft_filter(out, low=9000, high=200)


def lucky_chime() -> np.ndarray:
    out = np.zeros(secs(1.3))
    for i, m in enumerate([84, 88, 91, 96]):
        place(out, metal(midi(m), secs(0.9), ((1.0, 1.0, 0.4), (2.0, 0.3, 0.2), (3.0, 0.15, 0.1))), secs(0.09 * i), 0.6)
    rng = np.random.default_rng(400)
    for k in range(10):
        m = secs(0.05)
        f = 4000 + 2500 * rng.random()
        place(out, osc("sine", np.full(m, f)) * perc(m, 0.001, 0.015), secs(0.3 + 0.07 * k), 0.15)
    return fft_filter(out, low=11000, high=300)


def splash() -> np.ndarray:
    n = secs(0.5)
    rng = np.random.default_rng(410)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 4500), (0.5, 500)])
    body = onepole_sweep(noise, cutoff) * env_pts(n, [(0, 0), (0.01, 1), (0.5, 0)]) ** 1.5
    out = np.zeros(secs(0.7))
    place(out, fft_filter(body, high=200), 0, 1.0)
    for k in range(4):
        m = secs(0.06)
        f0 = 900 + 500 * rng.random()
        drop = osc("sine", glide(m, [(0, f0), (0.06, f0 * 1.8)])) * perc(m, 0.002, 0.02)
        place(out, drop, secs(0.15 + 0.09 * k), 0.35)
    return fft_filter(out, low=8000, high=100)


def rainbow() -> np.ndarray:
    notes = [72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96]
    out = np.zeros(secs(2.2))
    for i, m in enumerate(notes):
        k = secs(1.0)
        t = np.arange(k) / SR
        s = (np.sin(2 * np.pi * midi(m) * t) + 0.3 * np.sin(2 * np.pi * midi(m + 12) * t)) * np.exp(-t / 0.45)
        s *= (1 + 0.25 * np.sin(2 * np.pi * 7 * t)) * np.minimum(t / 0.004, 1.0)
        s[-secs(0.01):] *= np.linspace(1, 0, secs(0.01))
        place(out, s, secs(0.1 * i), 0.5)
    pad = pad_note(72, secs(1.9), attack=0.5) + pad_note(76, secs(1.9), attack=0.5) + pad_note(79, secs(1.9), attack=0.5)
    place(out, pad, 0, 0.15)
    return fft_filter(out, low=10000, high=150)


def baa() -> np.ndarray:
    n_d = 0.7
    s = syllable(n_d, [(0, 300), (0.1, 330), (0.7, 280)], [(0, "e"), (0.15, "a"), (0.7, "a")],
                 fscale=1.2, q=5.0, vib=0.0, rough=0.2, breath=0.08, seed=420, attack=0.02, release=0.15)
    t = np.arange(len(s)) / SR
    s *= 0.6 + 0.4 * np.sin(2 * np.pi * 19 * t)       # the bleat's quaver
    return fft_filter(s, low=5000, high=180)


def quack() -> np.ndarray:
    out = np.zeros(secs(0.5))
    for k, st in enumerate([0.0, 0.2]):
        s = syllable(0.14, [(0, 250), (0.03, 280), (0.14, 200)], [(0, "e"), (0.05, "a"), (0.14, "a")],
                     fscale=1.1, kind="square", q=10.0, vib=0.0, rough=0.4, breath=0.1, seed=430 + k,
                     attack=0.005, release=0.04)
        place(out, s, secs(st), 1.0 - 0.15 * k)
    return fft_filter(out, low=4500, high=300)


def moo() -> np.ndarray:
    s = syllable(1.1, [(0, 105), (0.25, 128), (0.8, 118), (1.1, 92)], [(0, "m"), (0.2, "u"), (0.6, "o"), (1.1, "u")],
                 fscale=0.8, q=5.0, vib=0.2, rough=0.25, breath=0.05, seed=440, attack=0.08, release=0.25)
    return fft_filter(s, low=3000, high=60)


def bunny_boing() -> np.ndarray:
    n = secs(0.5)
    f = vibrato(glide(n, [(0, 330), (0.5, 620)]), 13, 3.0, decay=0.2)
    s = (0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * perc(n, 0.006, 0.17)
    out = np.zeros(secs(0.6))
    place(out, s, 0, 1.0)
    m = secs(0.05)
    pip = osc("sine", glide(m, [(0, 2000), (0.02, 2600), (0.05, 2300)])) * perc(m, 0.003, 0.015)
    place(out, pip, secs(0.42), 0.3)
    return fft_filter(out, low=6000, high=120)


def birds() -> np.ndarray:
    out = np.zeros(secs(1.0))
    rng = np.random.default_rng(450)
    n = secs(0.4)
    t = np.arange(n) / SR
    flutter = fft_filter(osc("white", np.ones(n), rng=rng), low=3000, high=400) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 17 * t)))
    place(out, flutter * env_pts(n, [(0, 0), (0.03, 1), (0.4, 0)]), 0, 0.6)
    for k, st in enumerate([0.12, 0.3, 0.42, 0.62, 0.7]):
        m = secs(0.07)
        f0 = 2800 + 700 * rng.random()
        chirp = osc("sine", glide(m, [(0, f0), (0.035, f0 * 1.45), (0.07, f0 * 1.1)])) * perc(m, 0.003, 0.025)
        place(out, chirp, secs(st), 0.45)
    return fft_filter(out, low=9000, high=300)


def wild_herd() -> np.ndarray:
    dur = 3.2
    out = np.zeros(secs(dur))
    k = 0
    for h in range(6):
        cyc = 0.42 + 0.02 * h
        t0 = 0.05 * h
        while t0 < dur - 0.2:
            for b, p in zip([0.0, 0.08, 0.16, 0.22], [520, 600, 560, 480]):
                if t0 + b < dur - 0.1:
                    place(out, clop(p * (1 + 0.03 * h), 500 + k, 0.5), secs(t0 + b), 0.35)
                    k += 1
            t0 += cyc
    t = np.arange(len(out)) / SR
    out *= np.interp(t, [0, 1.0, 2.2, dur], [0.15, 1.0, 1.0, 0.0])     # they come by, then gallop away
    out = fft_filter(out, low=1400, high=60)                             # far away on the hill
    for st, base in [(0.8, 900), (1.7, 780)]:
        w = whinny(base, 0.8, 15.0, 510 + int(st * 10), snort=False)
        place(out, fft_filter(w, low=3000), secs(st), 0.25)
    return out


def bell_ding() -> np.ndarray:
    n = secs(1.5)
    t = np.arange(n) / SR
    out = np.zeros(n)
    for k, (ratio, amp, dec) in enumerate([(1.0, 1.0, 0.8), (2.76, 0.55, 0.4), (5.4, 0.3, 0.2), (8.93, 0.18, 0.1), (2.0, 0.25, 0.6)]):
        out += amp * np.sin(2 * np.pi * midi(88) * ratio * t + k) * np.exp(-t / dec)
    out *= np.minimum(t / 0.002, 1.0)
    out[-secs(0.05):] *= np.linspace(1, 0, secs(0.05))
    return fft_filter(out, low=10000, high=250)


def crowd_clap() -> np.ndarray:
    dur = 2.0
    out = np.zeros(secs(dur))
    rng = np.random.default_rng(530)
    for c in range(9):
        rate = 4.2 + 1.6 * rng.random()
        tone_hi = 2200 + 1500 * rng.random()
        t0 = 0.05 * rng.random()
        while t0 < dur - 0.1:
            n = secs(0.04)
            clap = fft_filter(osc("white", np.ones(n), rng=rng), low=tone_hi, high=700) * perc(n, 0.001, 0.01)
            place(out, clap, secs(t0), 0.5 + 0.5 * rng.random())
            t0 += 1.0 / rate * (0.9 + 0.2 * rng.random())
    t = np.arange(len(out)) / SR
    out *= np.interp(t, [0, 0.25, 1.2, dur], [0.3, 1.0, 0.9, 0.0])
    return fft_filter(out, low=8000, high=250)


def crowd_ooh() -> np.ndarray:
    out = np.zeros(secs(1.4))
    for k, hz in enumerate([170, 205, 240, 280, 310]):
        s = syllable(1.2, [(0, hz * 0.85), (0.4, hz * 1.12), (1.2, hz * 0.9)], [(0, "u"), (0.5, "o"), (1.2, "u")],
                     fscale=1.0 + 0.08 * k, q=5.0, vib=0.35, breath=0.1, seed=540 + k, attack=0.15, release=0.35)
        place(out, s, secs(0.03 * k), 0.6)
    return fft_filter(out, low=4000, high=100)


def confetti() -> np.ndarray:
    out = np.zeros(secs(0.9))
    rng = np.random.default_rng(550)
    n = secs(0.08)
    pop = osc("sine", glide(n, [(0, 900), (0.08, 300)])) * perc(n, 0.001, 0.02)
    crack = fft_filter(osc("white", np.ones(n), rng=rng), low=5000, high=800) * perc(n, 0.001, 0.01)
    place(out, pop + 0.8 * crack, 0, 1.0)
    m = secs(0.8)
    rustle = fft_filter(osc("white", np.ones(m), rng=rng), low=9000, high=3000)
    rustle *= (rng.random(m) > 0.97) * 1.0 + 0.15
    rustle = fft_filter(rustle, low=8000) * env_pts(m, [(0, 0), (0.05, 1), (0.8, 0)])
    place(out, rustle, secs(0.05), 0.5)
    for i, mm in enumerate([84, 88, 91]):
        place(out, box_note(mm, secs(0.3)), secs(0.05 + 0.05 * i), 0.25)
    return fft_filter(out, low=10000, high=150)


def rosette_fanfare() -> np.ndarray:
    """Da-da-da-DAAA-da-DAAAA on brass, with a marimba sparkle and a cymbal."""
    beat = 0.14
    melody = [(67, 1), (72, 1), (76, 1), (79, 3), (76, 1), (79, 6)]
    harmony = [(64, 1), (67, 1), (72, 1), (76, 3), (72, 1), (76, 6)]
    total = sum(d for _, d in melody) * beat + 0.6
    out = np.zeros(secs(total))
    for voice, g in [(melody, 0.7), (harmony, 0.35)]:
        t = 0.0
        for i, (m, d) in enumerate(voice):
            last = i == len(voice) - 1
            n = secs(d * beat + (0.45 if last else 0.02))
            place(out, brass_note(m, n, vib=d >= 3), secs(t), g)
            place(out, marimba_note(m + 12, secs(0.3)), secs(t), g * 0.35)
            t += d * beat
    t = 0.0
    for m, d in [(48, 3), (43, 3), (48, 1), (48, 6)]:
        n = secs(d * beat + 0.02)
        place(out, osc("triangle", np.full(n, midi(m))) * adsr(n, 0.004, 0.05, 0.8, 0.03), secs(t), 0.5)
        t += d * beat
    rng = np.random.default_rng(560)
    n = secs(0.9)
    place(out, fft_filter(osc("white", np.ones(n), rng=rng), low=9000, high=4000) * perc(n, 0.002, 0.25), secs(7 * beat), 0.12)
    return fft_filter(out, low=7000, high=60)


def arp_notes(notes: list[tuple[int, float]], tail: float = 0.18) -> np.ndarray:
    total = sum(d for _, d in notes) + tail
    out = np.zeros(secs(total))
    t = 0.0
    for i, (m, d) in enumerate(notes):
        last = i == len(notes) - 1
        place(out, marimba_note(m, secs(d + (tail if last else 0.03))), secs(t))
        t += d
    return fft_filter(out, low=7000, high=150)


def join() -> np.ndarray:
    out = arp_notes([(67, 0.07), (71, 0.07), (74, 0.07), (79, 0.16)])
    return out


def select() -> np.ndarray:
    return marimba_note(84, secs(0.09)) * 0.9


def ready() -> np.ndarray:
    return arp_notes([(74, 0.09), (79, 0.25)], tail=0.25)


# ----------------------------------------------------------------------------
# Loops: rain and the four music pieces, rendered into circular buffers.
# ----------------------------------------------------------------------------


def rain_loop() -> tuple[np.ndarray, int]:
    bar = SR  # 1 s "bars", 4 of them
    total = bar * 4
    rng = np.random.default_rng(600)
    hiss = fft_filter(rng.uniform(-1, 1, total), low=5500, high=500, circular=True)
    t = np.arange(total) / SR
    hiss *= 0.8 + 0.2 * np.sin(2 * np.pi * t / 4.0)   # one slow swell per loop: periodic, so seamless
    drips = np.zeros(total)
    for k in range(26):
        m = secs(0.05)
        f0 = 1400 + 1600 * rng.random()
        d = osc("sine", glide(m, [(0, f0), (0.05, f0 * 1.6)])) * perc(m, 0.002, 0.012)
        place(drips, d, int(rng.integers(0, total)), 0.25 + 0.3 * rng.random(), circular=True)
    rumble = fft_filter(rng.uniform(-1, 1, total), low=300, high=40, circular=True)
    return 0.6 * hiss + 0.8 * drips + 0.25 * rumble, bar


def _check_grid(samples: float, what: str) -> int:
    assert abs(samples - round(samples)) < 1e-6, f"{what} must be a whole number of samples ({samples})"
    return int(round(samples))


def music_stable() -> tuple[np.ndarray, int]:
    """Cosy 84 BPM in F: pad, plucked arpeggios, a soft marimba tune, a round bass."""
    beat = _check_grid(60 / 84 * SR, "84 BPM beat")        # 31500
    eighth = _check_grid(beat / 2, "84 BPM eighth")
    bar = beat * 4
    chords = [[53, 57, 60], [48, 52, 55], [50, 53, 57], [46, 50, 53], [53, 57, 60], [48, 52, 55], [46, 50, 53], [48, 52, 55]]
    roots = [41, 36, 38, 34, 41, 36, 34, 36]
    lead = [[72, S, 69, S, 67, S, 65, S], [67, S, S, S, 64, S, 67, S], [69, S, 72, S, 74, S, 72, S], [70, S, S, S, 69, S, 67, S],
            [65, S, 69, S, 72, S, 77, S], [76, S, 74, S, 72, S, 67, S], [70, S, 69, S, 67, S, 65, S], [67, S, S, S, None, S, 64, S]]
    total = bar * len(chords)
    buf = np.zeros(total)
    for b, (ch, r) in enumerate(zip(chords, roots)):
        for m in ch:
            place(buf, pad_note(m, bar + secs(0.3), attack=0.4), b * bar, 0.12, circular=True)
        arp = [ch[0], ch[1], ch[2], ch[2] + 5, ch[2], ch[1], ch[0] + 12, ch[1]]
        for k, m in enumerate(arp):
            place(buf, pluck(m + 12, eighth + secs(0.1)), b * bar + k * eighth, 0.14, circular=True)
        for k in (0, 2):
            n = beat * 2 - secs(0.05)
            t = np.arange(n) / SR
            bass = osc("triangle", np.full(n, midi(r if k == 0 else r + 7))) * np.exp(-t / 0.5) * np.minimum(t / 0.01, 1.0)
            place(buf, bass, b * bar + k * beat, 0.4, circular=True)
        for k, m in enumerate(lead[b]):
            if m is None or m == S:
                continue
            place(buf, marimba_note(m, secs(1.2), decay=0.55), b * bar + k * eighth, 0.4, circular=True)
    buf = fft_filter(buf, low=5000, high=35, circular=True)
    return buf, bar


def music_trail() -> tuple[np.ndarray, int]:
    """Jaunty 6/8 'trot' at 126 BPM (quarter = 21000 samples, eighth = 10500): oom-pa-pa, a woodblock gallop."""
    quarter = _check_grid(60 / 126 * SR, "126 BPM quarter")
    eighth = _check_grid(quarter / 2, "126 BPM eighth")
    dotted = _check_grid(eighth * 3, "dotted-quarter beat")
    bar = dotted * 2                                   # 6/8 = 6 eighths
    chord_of = {"G": [55, 59, 62], "C": [52, 55, 60], "D": [54, 57, 62]}
    root_of = {"G": 43, "C": 48, "D": 38}
    prog = ["G", "G", "C", "G", "D", "D", "G", "D", "G", "G", "C", "C", "G", "D", "D", "G"]
    lead = [[67, S, 71, 74, S, 71], [79, S, 78, 79, S, 74], [76, S, 72, 76, S, 79], [74, S, 71, 67, S, S],
            [69, S, 74, 78, S, 74], [72, S, 69, 66, S, 69], [71, S, 74, 79, S, 74], [72, S, 71, 69, S, S],
            [67, S, 71, 74, S, 79], [83, S, 79, 74, S, 71], [72, S, 76, 79, S, 76], [72, S, 69, 76, S, 72],
            [71, S, 74, 79, S, 74], [78, S, 74, 72, S, 69], [66, S, 69, 72, S, 69], [67, S, S, None, 62, S]]
    total = bar * len(prog)
    rng = np.random.default_rng(700)
    lead_buf = np.zeros(total)
    for b, notes in enumerate(lead):
        for k, m in enumerate(notes):
            if m is None or m == S:
                continue
            steps = 1
            while k + steps < 6 and notes[k + steps] == S:
                steps += 1
            n = steps * eighth - secs(0.02)
            f = np.full(n, midi(m))
            s = (0.55 * osc("square", f, duty=0.25) + 0.45 * osc("triangle", f)) * adsr(n, 0.005, 0.06, 0.6, 0.05)
            place(lead_buf, s, b * bar + k * eighth, 0.32, circular=True)
            place(lead_buf, marimba_note(m + 12, secs(0.3)), b * bar + k * eighth, 0.1, circular=True)
    lead_buf = fft_filter(lead_buf, low=4000, circular=True)
    acc = np.zeros(total)
    for b, c in enumerate(prog):
        r = root_of[c]
        for k, m in [(0, r), (3, r + 7)]:                  # oom on each dotted beat
            n = dotted - secs(0.03)
            t = np.arange(n) / SR
            s = osc("triangle", np.full(n, midi(m))) * np.exp(-t / 0.25) * np.minimum(t / 0.004, 1.0)
            place(acc, s, b * bar + k * eighth, 0.5, circular=True)
        for k in (1, 2, 4, 5):                             # pa-pa
            for m in chord_of[c]:
                place(acc, pluck(m + 12, eighth), b * bar + k * eighth, 0.09, circular=True)
    acc = fft_filter(acc, low=3000, circular=True)
    perc_buf = np.zeros(total)
    for b in range(len(prog)):
        for k, (g, p) in enumerate([(1.0, 80), (0.0, 0), (0.55, 86), (0.85, 78), (0.0, 0), (0.55, 86)]):
            if g:
                place(perc_buf, woodblock(p), b * bar + k * eighth, 0.35 * g, circular=True)   # clip-clop gallop
        place(perc_buf, kick(), b * bar, 0.6, circular=True)
        place(perc_buf, kick(), b * bar + dotted, 0.45, circular=True)
        for k in range(6):
            place(perc_buf, hat(rng), b * bar + k * eighth, 0.08, circular=True)
    mix = lead_buf + acc + perc_buf
    return fft_filter(mix, high=30, circular=True), bar


def music_show() -> tuple[np.ndarray, int]:
    """Fanfare-ish march at 105 BPM in C: brass lead, bass, snare and kick, bright hats."""
    beat = _check_grid(60 / 105 * SR, "105 BPM beat")     # 25200
    eighth = _check_grid(beat / 2, "105 BPM eighth")
    six = _check_grid(beat / 4, "105 BPM sixteenth")
    bar = beat * 4
    lead = [[67, S, 72, S, 76, S, 79, S], [77, S, 76, S, 74, S, 72, S], [74, S, S, 71, 74, S, 79, S], [76, S, 72, S, 67, S, S, S],
            [67, 67, 72, S, 76, 76, 79, S], [81, S, 79, S, 77, S, 76, S], [74, S, 76, S, 77, S, 74, S], [72, S, S, S, None, S, 67, S]]
    roots = [36, 41, 43, 36, 36, 41, 43, 36]
    total = bar * len(lead)
    rng = np.random.default_rng(800)
    buf = np.zeros(total)
    for b, notes in enumerate(lead):
        for k, m in enumerate(notes):
            if m is None or m == S:
                continue
            steps = 1
            while k + steps < 8 and notes[k + steps] == S:
                steps += 1
            n = steps * eighth - secs(0.02)
            place(buf, brass_note(m, n, vib=steps >= 3), b * bar + k * eighth, 0.4, circular=True)
            place(buf, brass_note(m - 5 if m - 5 > 60 else m - 3, n), b * bar + k * eighth, 0.15, circular=True)
        r = roots[b]
        for k, m in enumerate([r, r + 7, r + 12, r + 7]):
            n = beat - secs(0.03)
            t = np.arange(n) / SR
            s = osc("triangle", np.full(n, midi(m))) * np.exp(-t / 0.2) * np.minimum(t / 0.004, 1.0)
            place(buf, s, b * bar + k * beat, 0.5, circular=True)
        for k in range(16):
            pos = b * bar + k * six
            if k in (0, 8):
                place(buf, kick(), pos, 0.7, circular=True)
            if k in (4, 12) or (b % 4 == 3 and k in (13, 14, 15)):
                place(buf, snare(rng), pos, 0.45, circular=True)
            place(buf, hat(rng), pos, 0.1 if k % 2 == 0 else 0.05, circular=True)
    return fft_filter(buf, low=8000, high=30, circular=True), bar


def music_menu() -> tuple[np.ndarray, int]:
    """A music box in D at 90 BPM (beat = 29400 samples)."""
    beat = _check_grid(60 / 90 * SR, "90 BPM beat")
    bar = beat * 4
    lead = [[74, 78, 81, 78], [79, 78, 76, S], [74, 76, 78, 74], [76, S, 69, S],
            [74, 78, 81, 86], [83, 81, 79, S], [78, 76, 73, 76], [74, S, S, None]]
    roots = [38, 43, 38, 33, 38, 43, 33, 38]
    total = bar * len(lead)
    buf = np.zeros(total)
    for b, notes in enumerate(lead):
        for k, m in enumerate(notes):
            if m is None or m == S:
                continue
            place(buf, box_note(m, secs(1.4)), b * bar + k * beat, 0.5, circular=True)
            place(buf, box_note(m + 12, secs(0.6)), b * bar + k * beat, 0.12, circular=True)
        r = roots[b]
        for k, m in [(0, r + 12), (2, r + 19)]:
            place(buf, box_note(m, secs(1.2)), b * bar + k * beat, 0.3, circular=True)
            place(buf, pad_note(m, beat * 2, attack=0.2), b * bar + k * beat, 0.08, circular=True)
    return fft_filter(buf, low=7000, high=60, circular=True), bar


# ----------------------------------------------------------------------------
# Measurement, normalisation, output, inspection images
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


def _variants(fn, count: int) -> dict:
    return {f"{fn.__name__}_{i + 1}": (lambda i=i: fn(i)) for i in range(count)}


SFX = {
    **_variants(neigh, 4), **_variants(foal_neigh, 2), "snort": snort, "nicker": nicker,
    "jump_hup": jump_hup, "step_hup": step_hup, "land_thud": land_thud,
    "brush_scrub": brush_scrub, "mud_poof": mud_poof, **_variants(munch, 3), "hoof_pick_ping": hoof_pick_ping,
    "horseshoe_clink": horseshoe_clink, "saddle_creak": saddle_creak, "door_creak": door_creak,
    "stable_cat_meow": stable_cat_meow,
    "gate_open": gate_open, "apple_pop": apple_pop, "flower_pick": flower_pick, "lucky_chime": lucky_chime,
    "splash": splash, "rainbow": rainbow, "baa": baa, "quack": quack, "moo": moo, "bunny_boing": bunny_boing,
    "birds": birds, "wild_herd": wild_herd,
    "bell_ding": bell_ding, "crowd_clap": crowd_clap, "crowd_ooh": crowd_ooh, "confetti": confetti,
    "rosette_fanfare": rosette_fanfare,
    "join": join, "select": select, "ready": ready, "whoosh": whoosh,
}
LOOPS = {
    "walk_loop": walk_loop, "trot_loop": trot_loop, "canter_loop": canter_loop, "rain_loop": rain_loop,
    "music_stable": music_stable, "music_trail": music_trail, "music_show": music_show, "music_menu": music_menu,
}
LOOP_LUFS = -14.0
VOICE_LUFS = -13.0
VOICES = ("neigh", "foal_neigh", "nicker", "baa", "moo", "quack", "stable_cat_meow")
MAX_BYTES = 12e6


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
    print(f"{'file':<18}{'secs':>7}{'peak dBFS':>11}{'RMS dBFS':>10}{'LUFS':>8}{'ST max':>8}{'DC':>10}")
    rows = [(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in LOOPS.items()]
    for name, fn, loop in rows:
        if only and name not in only:
            p = OUT / f"{name}.wav"
            if p.exists():
                total_bytes += p.stat().st_size
            continue
        if loop:
            x, bar_len = fn()
            x = normalise(x, LOOP_LUFS, loop=True)
        else:
            target = VOICE_LUFS if name.startswith(VOICES) else SFX_LUFS
            x = normalise(fade_edges(fn()), target, loop=False)
            x = fade_edges(x)
        pcm = to_pcm(x)
        path = OUT / f"{name}.wav"
        write_wav(path, pcm)
        total_bytes += path.stat().st_size
        y = pcm.astype(np.float64) / 32768.0
        peak = np.abs(y).max()
        loud, st = lufs(y, loop)
        print(f"{name:<18}{len(y) / SR:>7.2f}{db(peak):>11.2f}{db(np.sqrt((y * y).mean())):>10.2f}"
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
            print(f"  loop: {len(y)} samples = {bars:g} x {bar_len}; seam jump {seam:.5f} "
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
    if total_bytes > MAX_BYTES:
        ok = False
        print(f"FAIL: audio total above {MAX_BYTES / 1e6:g} MB")
    print("ALL OK" if ok else "SOME CHECKS FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
