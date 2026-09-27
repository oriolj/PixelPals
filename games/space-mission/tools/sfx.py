"""Space Mission sound synth: every sound, both engine loops and three music loops, made by our own code.

Run: uv run python tools/sfx.py [--check DIR]

PixelPals's small synth (oscillators with polyBLEP, envelopes, glides,
vibrato, zero-phase filters, loudness normalisation and the inspection
images), with this game's sounds. Space is silent, so orbit is "radio" and
cabin sounds: the real NASA Quindar beeps (2525 Hz in, 2475 Hz out), RCS
puffs, the arm's servo, latches, clunks, the camera, sunrise bells. Then the
Mars landing (parachute, winch, dust), the rover and its drill, the little
helicopter, the beam home and the party. Loops: rover_hum and heli_buzz
(every component a whole number of cycles) and music_orbit (72 bpm, lydian
bells), music_mars (100 bpm, plucky), music_menu (90 bpm, bouncy), 8 bars
each, rendered into a circular buffer. Everything soft for small kids: no
harsh highs, no scary low drones. Seeded: reruns write identical files.
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
# Voices
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


def bell(m: float, dur: float = 0.9, decay: float = 0.35) -> np.ndarray:
    """A warm bell: near-harmonic partials (1, 2.01, 3.99), gentle late vibrato."""
    n = secs(dur)
    f = vibrato(np.full(n, midi(m)), 6, 0.1, delay=0.2)
    s = osc("sine", f) + 0.35 * osc("sine", f * 2.01) * perc(n, 0.002, decay * 0.5)
    s = s * perc(n, 0.003, decay) + 0.12 * osc("sine", f * 3.99) * perc(n, 0.002, decay * 0.25)
    return s


def pluck(m: float, dur: float = 0.3, duty: float = 0.25) -> np.ndarray:
    """A soft chiptune pluck: a narrow square rounded off by a sine octave."""
    n = secs(dur)
    f = np.full(n, midi(m))
    s = 0.7 * osc("square", f, duty=duty) + 0.3 * osc("sine", f * 2)
    return s * adsr(n, 0.003, 0.06, 0.35, dur * 0.5)


def sparkle(out: np.ndarray, start: float, ms: list[int], step: float, gain: float, seed: int) -> None:
    """Little high sine pings, one per note, with a touch of timing jitter."""
    rng = np.random.default_rng(seed)
    for i, m in enumerate(ms):
        n = secs(0.12)
        f = vibrato(np.full(n, midi(m)), 16, 0.15)
        s = osc("sine", f) * perc(n, 0.002, 0.035)
        place(out, s, secs(start + i * step + rng.uniform(0, 0.008)), gain)


def noise(n: int, seed: int) -> np.ndarray:
    return osc("white", np.ones(n), rng=np.random.default_rng(seed))


# ----------------------------------------------------------------------------
# Radio and orbit
# ----------------------------------------------------------------------------


def quindar(hz: float, seed: int):
    """The real NASA Quindar tone: 250 ms of a pure sine (2525 Hz opens the
    transmission, 2475 Hz closes it), soft 12 ms edges, a whisper of radio hiss."""
    def make() -> np.ndarray:
        out = np.zeros(secs(0.3))
        n = secs(0.25)
        beep = osc("sine", np.full(n, hz)) * adsr(n, 0.012, 0.0, 1.0, 0.012, curve=1.0)
        place(out, beep, secs(0.025))
        hiss = fft_filter(noise(len(out), seed), low=3800, high=1200)
        place(out, hiss * env_pts(len(out), [(0, 0), (0.02, 1), (0.28, 1), (0.3, 0)]), 0, 0.05)
        return out
    return make


def thruster() -> np.ndarray:
    """A soft RCS puff: noise through a closing low-pass, and a tiny push of air."""
    n = secs(0.28)
    y = onepole_sweep(noise(n, 201), glide(n, [(0, 2200), (0.28, 350)]))
    y = fft_filter(y, high=150) * env_pts(n, [(0, 0), (0.015, 1), (0.28, 0)]) ** 2
    m = secs(0.12)
    y[:m] += 0.25 * osc("sine", glide(m, [(0, 160), (0.12, 90)])) * perc(m, 0.004, 0.04)
    return y


def arm_move() -> np.ndarray:
    """A short servo whirr: a buzzy tone that spins up, holds and settles."""
    n = secs(0.3)
    f = glide(n, [(0, 150), (0.08, 230), (0.24, 215), (0.3, 170)])
    trem = 1.0 + 0.25 * np.sin(2 * np.pi * 32 * np.arange(n) / SR)
    s = (0.6 * osc("saw", f) + 0.4 * osc("square", f * 2, duty=0.3)) * trem
    return fft_filter(s * adsr(n, 0.03, 0.05, 0.8, 0.08), low=1800, high=120)


def grab() -> np.ndarray:
    """The latch clicks shut, then a little rising 'got it' blip."""
    out = np.zeros(secs(0.3))
    n = secs(0.015)
    place(out, fft_filter(noise(n, 211), high=2000, low=6000) * perc(n, 0.0005, 0.003), 0, 0.8)
    for fr, g, d in ((820, 0.5, 0.03), (1930, 0.25, 0.02), (3100, 0.1, 0.01)):
        n = secs(0.1)
        place(out, osc("sine", np.full(n, fr)) * perc(n, 0.001, d), 0, g)
    n = secs(0.14)
    f = glide(n, [(0, midi(76)), (0.08, midi(84)), (0.14, midi(84))])
    place(out, (0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * adsr(n, 0.004, 0.04, 0.5, 0.06),
          secs(0.07), 0.6)
    return fft_filter(out, low=6000, high=100)


def clunk() -> np.ndarray:
    """A module docks: a soft metallic clunk (a low thump and a short ring) and a happy sparkle."""
    out = np.zeros(secs(0.8))
    n = secs(0.25)
    place(out, osc("sine", glide(n, [(0, 150), (0.25, 70)])) * perc(n, 0.004, 0.07), 0, 0.7)
    for fr, g, d in ((233, 0.5, 0.12), (571, 0.3, 0.08), (947, 0.18, 0.05), (1409, 0.1, 0.03)):
        n = secs(0.4)
        place(out, osc("sine", np.full(n, fr)) * perc(n, 0.001, d), 0, g)
    sparkle(out, 0.14, [84, 88, 91, 96], 0.05, 0.35, 221)
    return fft_filter(out, low=7000, high=50)


def solar_unfold() -> np.ndarray:
    """The solar wings open: rising ratchet clicks, then a bright shimmer."""
    out = np.zeros(secs(0.95))
    t = 0.0
    for i in range(10):
        n = secs(0.03)
        fr = 700 * 2 ** (i / 12)
        click = osc("triangle", np.full(n, fr)) * perc(n, 0.0005, 0.006)
        click += 0.4 * fft_filter(noise(n, 230 + i), high=2500, low=6000) * perc(n, 0.0005, 0.002)
        place(out, click, secs(t), 0.6)
        t += 0.06 - i * 0.0035
    for k, m in enumerate([84, 88, 91, 96]):
        n = secs(0.95 - 0.42)
        f = vibrato(np.full(n, midi(m)), 7, 0.12)
        s = osc("sine", f) * env_pts(n, [(0, 0), (0.12, 1), (n / SR, 0)]) ** 1.5
        place(out, s, secs(0.42 + k * 0.03), 0.3)
    sparkle(out, 0.5, [96, 100, 103, 100, 108], 0.07, 0.2, 231)
    return fft_filter(out, low=8000, high=150)


def camera(k: int):
    """Shutter click-clack, then the flash charging up (three pitches, one per press)."""
    mul = [1.0, 1.19, 1.41][k]

    def make() -> np.ndarray:
        out = np.zeros(secs(0.5))
        for st, g in ((0.0, 1.0), (0.07, 0.7)):
            n = secs(0.012)
            place(out, fft_filter(noise(n, 240 + k * 3 + int(st * 100)), high=2200, low=7000)
                  * perc(n, 0.0005, 0.003), secs(st), g)
        n = secs(0.03)
        chk = osc("square", np.full(n, 190.0 * mul), duty=0.3) * perc(n, 0.001, 0.008)
        place(out, fft_filter(chk, low=2500), secs(0.01), 0.5)
        n = secs(0.38)
        f = glide(n, [(0, 700 * mul), (0.38, 1900 * mul)])
        whine = osc("sine", f) * env_pts(n, [(0, 0), (0.08, 0.6), (0.3, 1.0), (0.38, 0)])
        place(out, whine, secs(0.1), 0.18)
        return fft_filter(out, low=7000, high=150)
    return make


def sunrise_chime() -> np.ndarray:
    """The sun comes up over the Earth: four warm bell notes, C E G C."""
    out = np.zeros(secs(1.7))
    for i, m in enumerate([72, 76, 79, 84]):
        place(out, bell(m, 1.7 - i * 0.2, 0.45), secs(i * 0.2), 0.7 if i < 3 else 0.85)
    return fft_filter(out, low=6000, high=120)


def photo_golden() -> np.ndarray:
    """A golden photo: a glassy arpeggio up two octaves, with sparkles over it."""
    out = np.zeros(secs(1.2))
    run = [72, 76, 79, 84, 88, 91, 96]
    for i, m in enumerate(run):
        place(out, glass(m, 0.6 if i < len(run) - 1 else 0.8), secs(i * 0.055), 0.5)
    sparkle(out, 0.3, [96, 100, 103, 108, 103, 100, 108, 103], 0.08, 0.2, 251)
    return fft_filter(out, low=8000, high=150)


def boing() -> np.ndarray:
    """A soft, friendly bump: everything out here is made of sponge."""
    n = secs(0.42)
    f = glide(n, [(0, 240), (0.42, 150)])
    f = vibrato(f, 12, 3.0, decay=0.16)
    s = 0.75 * osc("sine", f) + 0.25 * osc("triangle", f)
    return fft_filter(s * perc(n, 0.004, 0.14), low=1600, high=70)


def wave_hi() -> np.ndarray:
    """A tiny 'hi!': a chirp that rises and falls back, like a cartoon voice."""
    n = secs(0.24)
    f = vibrato(glide(n, [(0, 520), (0.06, 900), (0.16, 1000), (0.24, 800)]), 9, 0.4, delay=0.08)
    s = osc("sine", f) + 0.3 * osc("triangle", f * 2) + 0.15 * osc("sine", f * 3)
    return fft_filter(s * adsr(n, 0.015, 0.05, 0.7, 0.09), low=4500, high=200)


def dock() -> np.ndarray:
    """Docked! A warm C-E-G chord that swells in note by note, and a bell on top."""
    out = np.zeros(secs(1.6))
    for i, m in enumerate([60, 64, 67]):
        n = secs(1.6 - i * 0.13)
        e = adsr(n, 0.2, 0.3, 0.7, 0.6)
        s = np.zeros(n)
        for det in (-0.07, 0.07):
            f = vibrato(np.full(n, midi(m + det)), 5, 0.06, delay=0.3)
            s += 0.5 * osc("saw", f) + 0.4 * osc("sine", f)
        place(out, fft_filter(s, low=1800) * e, secs(i * 0.13), 0.5)
    place(out, bell(84, 1.1, 0.4), secs(0.4), 0.35)
    sparkle(out, 0.45, [96, 100, 103], 0.06, 0.15, 261)
    return fft_filter(out, low=6500, high=60)


# ----------------------------------------------------------------------------
# Landing
# ----------------------------------------------------------------------------


def parachute_pop() -> np.ndarray:
    """The chute opens: a whoomp of air, then the fabric flutters and settles."""
    out = np.zeros(secs(1.0))
    n = secs(0.35)
    whoomp = onepole_sweep(noise(n, 301), glide(n, [(0, 1500), (0.35, 250)]))
    place(out, whoomp * perc(n, 0.006, 0.09), 0, 0.6)
    place(out, osc("sine", glide(n, [(0, 170), (0.35, 70)])) * perc(n, 0.005, 0.08), 0, 0.45)
    n = secs(0.8)
    t = np.arange(n) / SR
    rate = np.interp(t, [0, 0.8], [22, 12])
    flap = (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(rate) / SR)) ** 2
    fabric = fft_filter(noise(n, 302), low=1800, high=350) * flap
    place(out, fabric * env_pts(n, [(0, 0), (0.05, 1), (0.8, 0)]) ** 1.5, secs(0.12), 0.8)
    return fft_filter(out, high=50)


def crane_lower() -> np.ndarray:
    """The winch lets the rover down: a gentle whirr that slowly drops in pitch."""
    n = secs(1.05)
    t = np.arange(n) / SR
    f = glide(n, [(0, 330), (1.05, 220)])
    teeth = 1.0 + 0.2 * np.sin(2 * np.pi * np.cumsum(f / 9) / SR)
    s = (0.55 * osc("saw", f) + 0.3 * osc("triangle", f * 0.5) + 0.15 * osc("sine", f * 2)) * teeth
    s = fft_filter(s, low=1500, high=90)
    s += 0.12 * fft_filter(noise(n, 311), low=2000, high=500) * (0.5 + 0.5 * np.sin(2 * np.pi * 6 * t))
    return s * adsr(n, 0.12, 0.1, 0.85, 0.25)


def touchdown() -> np.ndarray:
    """A soft dust whump on Mars."""
    out = np.zeros(secs(0.7))
    n = secs(0.35)
    place(out, osc("sine", glide(n, [(0, 130), (0.35, 55)])) * perc(n, 0.003, 0.11), 0, 1.0)
    n = secs(0.6)
    dust = fft_filter(noise(n, 321), low=1100, high=150)
    place(out, dust * env_pts(n, [(0, 0), (0.03, 1), (0.6, 0)]) ** 2, 0, 0.5)
    return fft_filter(out, high=45)


def crane_bye() -> np.ndarray:
    """The sky crane flies off: a whoosh that rises away, and two little 'bye' beeps."""
    out = np.zeros(secs(0.95))
    n = secs(0.7)
    cutoff = glide(n, [(0, 400), (0.5, 3000), (0.7, 3500)])
    y = onepole_sweep(onepole_sweep(noise(n, 331), cutoff), cutoff)
    place(out, fft_filter(y, high=200) * env_pts(n, [(0, 0), (0.2, 1), (0.7, 0)]) ** 1.5, 0, 1.0)
    for st, m in ((0.42, 84), (0.62, 79)):
        n = secs(0.18)
        f = vibrato(np.full(n, midi(m)), 8, 0.2, delay=0.05)
        s = (0.6 * osc("square", f, duty=0.5) + 0.4 * osc("sine", f)) * adsr(n, 0.004, 0.04, 0.5, 0.08)
        place(out, fft_filter(s, low=4000), secs(st), 0.35)
    return fft_filter(out, high=100)


# ----------------------------------------------------------------------------
# Mars
# ----------------------------------------------------------------------------


def drill() -> np.ndarray:
    """A friendly rumble: a wobbling motor tone and a gritty grind that comes and goes."""
    n = secs(1.0)
    t = np.arange(n) / SR
    f = vibrato(glide(n, [(0, 95), (0.15, 120), (1.0, 115)]), 8, 0.6)
    motor = fft_filter(0.6 * osc("saw", f) + 0.4 * osc("square", f * 2, duty=0.4), low=900, high=60)
    grit_rate = 38 + 6 * np.sin(2 * np.pi * 3 * t)
    grit_am = (0.5 + 0.5 * np.sin(2 * np.pi * np.cumsum(grit_rate) / SR)) ** 3
    grit = fft_filter(osc("noise", np.full(n, 3000.0), rng=np.random.default_rng(401)), low=1600, high=400)
    s = motor + 0.5 * grit * grit_am
    return s * adsr(n, 0.08, 0.1, 0.85, 0.2)


def sample_pop() -> np.ndarray:
    """A sample capsule pops out: a soft pop and a bright ding."""
    out = np.zeros(secs(0.7))
    n = secs(0.05)
    place(out, fft_filter(noise(n, 411), low=3000, high=300) * perc(n, 0.001, 0.01), 0, 0.6)
    n = secs(0.09)
    place(out, osc("sine", glide(n, [(0, 220), (0.09, 520)])) * perc(n, 0.002, 0.03), 0, 0.8)
    place(out, bell(84, 0.6, 0.22), secs(0.07), 0.5)
    place(out, bell(91, 0.5, 0.18), secs(0.13), 0.35)
    return fft_filter(out, low=7000, high=80)


def heli_loop() -> np.ndarray:
    """The little helicopter does a loop-the-loop: rotor chops that swoop up and back down."""
    n = secs(0.6)
    t = np.arange(n) / SR
    rate = np.interp(t, [0, 0.3, 0.6], [20, 34, 22])
    chop = (0.5 + 0.5 * np.cos(2 * np.pi * np.cumsum(rate) / SR)) ** 4
    f = glide(n, [(0, 260), (0.3, 520), (0.6, 300)])
    body = fft_filter(0.6 * osc("triangle", f) + 0.4 * osc("saw", f), low=2200, high=100)
    air = fft_filter(noise(n, 421), low=2500, high=300)
    s = (body + 0.5 * air) * chop
    return s * env_pts(n, [(0, 0), (0.08, 1), (0.45, 1), (0.6, 0)])


def phone_home() -> np.ndarray:
    """The beam home: a sine sweeping up with a gentle shimmer, sparkles, a soft landing ding."""
    out = np.zeros(secs(1.6))
    n = secs(1.3)
    f = vibrato(glide(n, [(0, 260), (1.3, 1560)]), 6, 0.15, delay=0.2)
    beam = osc("sine", f) + 0.3 * osc("sine", f * 1.5) + 0.15 * osc("triangle", f * 2)
    place(out, beam * env_pts(n, [(0, 0), (0.3, 0.8), (1.1, 1), (1.3, 0)]), 0, 0.6)
    sparkle(out, 0.35, [91, 96, 100, 103, 96, 100, 103, 108, 103, 108], 0.08, 0.18, 431)
    place(out, bell(91, 0.45, 0.15), secs(1.12), 0.35)
    return fft_filter(out, low=7000, high=100)


def party() -> np.ndarray:
    """The mission is done: a happy fanfare, da-da-da-DAAA-da-da-DAAAAA, with bass and a cymbal."""
    beat = 0.14
    melody = [(72, 1), (76, 1), (79, 1), (84, 3), (79, 1), (81, 1), (84, 7)]
    harmony = [(64, 1), (67, 1), (72, 1), (76, 3), (76, 1), (77, 1), (76, 7)]
    total = sum(d for _, d in melody) * beat + 0.55
    out = np.zeros(secs(total))
    for voice, kind, duty, g in [(melody, "square", 0.25, 0.55), (harmony, "square", 0.5, 0.28)]:
        t = 0.0
        for i, (m, d) in enumerate(voice):
            last = i == len(voice) - 1
            n = secs(d * beat + (0.5 if last else 0.0))
            f = np.full(n, midi(m))
            if d >= 3:
                f = vibrato(f, 6.5, 0.3, delay=0.12)
            e = adsr(n, 0.004, 0.06, 0.65, 0.4 if last else 0.03)
            place(out, osc(kind, f, duty=duty) * e, secs(t), g)
            t += d * beat
    t = 0.0
    for m, d in [(48, 3), (53, 3), (55, 2), (48, 7)]:
        n = secs(d * beat + (0.4 if d == 7 else 0.02))
        place(out, osc("triangle", np.full(n, midi(m))) * adsr(n, 0.004, 0.05, 0.8, 0.3 if d == 7 else 0.03),
              secs(t), 0.5)
        t += d * beat
    rng = np.random.default_rng(441)
    for i in range(8):  # soft snare roll into the last note
        n = secs(0.06)
        s = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=800) * perc(n, 0.001, 0.02)
        place(out, s, secs(6 * beat + i * beat / 4), 0.14 + 0.03 * i)
    n = secs(1.0)
    cym = fft_filter(osc("white", np.ones(n), rng=rng), low=8000, high=3500) * perc(n, 0.002, 0.3)
    place(out, cym, secs(8 * beat), 0.12)
    sparkle(out, 8 * beat + 0.1, [96, 100, 103, 108, 103, 108], 0.09, 0.15, 442)
    return fft_filter(out, low=7000, high=60)
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


def _whole_cycles(n: int, *freqs: float) -> None:
    for f in freqs:
        cycles = f * n / SR
        assert abs(cycles - round(cycles)) < 1e-9, f"{f} Hz is not a whole number of cycles in the loop"


def rover_hum() -> tuple[np.ndarray, int]:
    """3 s of soft electric motor hum; every component has a whole number of cycles in the loop."""
    n = secs(3.0)
    t = np.arange(n) / SR
    _whole_cycles(n, 120, 240, 360, 600, 1.0, 2.0 / 3.0)
    lfo = 1.0 + 0.18 * np.sin(2 * np.pi * 1.0 * t) + 0.08 * np.sin(2 * np.pi * (2.0 / 3.0) * t)
    x = (np.sin(2 * np.pi * 120 * t) + 0.4 * np.sin(2 * np.pi * 240 * t)
         + 0.15 * np.sin(2 * np.pi * 360 * t) + 0.04 * np.sin(2 * np.pi * 600 * t)) * lfo
    x += 0.15 * fft_filter(np.random.default_rng(501).uniform(-1, 1, n), low=900, high=150, circular=True)
    return fft_filter(x, low=2000, circular=True), n


def heli_buzz() -> tuple[np.ndarray, int]:
    """1.5 s of a light rotor buzz: 24 blade chops a second over a small motor tone."""
    n = secs(1.5)
    t = np.arange(n) / SR
    _whole_cycles(n, 24, 176, 352, 2.0)
    chop = (0.5 + 0.5 * np.cos(2 * np.pi * 24 * t)) ** 3
    air = fft_filter(np.random.default_rng(511).uniform(-1, 1, n), low=2200, high=300, circular=True)
    motor = np.sin(2 * np.pi * 176 * t) + 0.35 * np.sin(2 * np.pi * 352 * t)
    wob = 1.0 + 0.1 * np.sin(2 * np.pi * 2.0 * t)
    x = (0.8 * air * chop + 0.35 * motor * (0.6 + 0.4 * chop)) * wob
    return fft_filter(x, low=3000, high=90, circular=True), n


def render_song(bpm: float, chords: list[list[int]], bass: list[list[tuple[int, int]]],
                melody: list[dict[int, int]], *, seed: int, mel_voice, mel_gain: float,
                arp: list[int] | None = None, arp_steps: int = 8, arp_voice=None, arp_gain: float = 0.25,
                echo: float = 0.0, stabs: list[int] | None = None, pad_gain: float = 0.12,
                pad_low: float = 1300, pad_attack: float = 0.5, bass_voice: str = "triangle",
                shaker: float = 0.0, shaker_steps: tuple[int, ...] = (), tick_steps: tuple[int, ...] = (),
                tick: float = 0.0) -> tuple[np.ndarray, int]:
    """Pads, bass, an optional arpeggio / chord stabs, a melody and light percussion,
    all placed circularly on a 16-step grid so the loop is seamless."""
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    bars = len(chords)
    total = bar_len * bars
    rng = np.random.default_rng(seed)

    def at(b: int, step: float) -> int:
        return int(round(b * bar_len + step * bar_len / 16))

    pad = np.zeros(total)
    for b, chord in enumerate(chords):
        n = bar_len + secs(0.8)
        e = adsr(n, pad_attack, 0.4, 0.8, 0.8)
        for m in chord:
            for det in (-0.06, 0.06):
                s = osc("saw", vibrato(np.full(n, midi(m + det)), 0.3 + rng.uniform(0, 0.2), 0.05))
                place(pad, s * e, b * bar_len, pad_gain, circular=True)
    pad = fft_filter(pad, low=pad_low, circular=True)

    low = np.zeros(total)
    for b, notes_ in enumerate(bass):
        for step, m in notes_:
            n = secs(0.8)
            s = osc(bass_voice, np.full(n, midi(m))) * perc(n, 0.004, 0.3)
            s += 0.3 * osc("sine", np.full(n, midi(m + 12))) * perc(n, 0.002, 0.08)
            place(low, s, at(b, step), 0.7, circular=True)
    low = fft_filter(low, low=1200, circular=True)

    arp_buf = np.zeros(total)
    if arp:
        per = 16 // arp_steps
        for b, chord in enumerate(chords):
            tones = sorted(chord)
            for k in range(arp_steps):
                i = arp[k % len(arp)]
                m = tones[i % len(tones)] + 12 * (1 + i // len(tones))
                place(arp_buf, arp_voice(m), at(b, k * per), arp_gain * (1.0 if k % 2 == 0 else 0.8),
                      circular=True)
    if stabs:
        for b, chord in enumerate(chords):
            for step in stabs:
                for m in chord:
                    place(arp_buf, pluck(m + 12, 0.18, duty=0.5), at(b, step), arp_gain, circular=True)
    if echo:
        d = bar_len * 3 // 16  # a dotted eighth
        arp_buf = arp_buf + echo * np.roll(arp_buf, d) + echo * echo * np.roll(arp_buf, 2 * d)
    arp_buf = fft_filter(arp_buf, low=5000, high=150, circular=True)

    mel = np.zeros(total)
    for b, bar in enumerate(melody):
        for step, m in bar.items():
            place(mel, mel_voice(m), at(b, step), mel_gain, circular=True)
    mel = fft_filter(mel, low=5500, circular=True)

    perc_buf = np.zeros(total)
    for b in range(bars):
        for step in shaker_steps:
            n = secs(0.05)
            sh = fft_filter(osc("white", np.ones(n), rng=rng), high=5000, low=9000) * perc(n, 0.004, 0.015)
            place(perc_buf, sh, at(b, step), shaker, circular=True)
        for step in tick_steps:  # a soft woodblock
            n = secs(0.06)
            s = osc("sine", glide(n, [(0, 1250), (0.06, 1050)])) * perc(n, 0.001, 0.015)
            place(perc_buf, s, at(b, step), tick, circular=True)
    mix = pad + low + arp_buf + mel + perc_buf
    return fft_filter(mix, high=40, circular=True), bar_len


# Orbit: C lydian, 72 bpm, 8 bars: Cmaj7 D/C Am7 Fmaj7 | Cmaj7 D/C Em7 Fmaj7.
# Slow bell arpeggios with a dotted-eighth echo over wide pads; the D major
# chord over a C bass is the lydian "wonder" colour.
ORBIT_CHORDS = [[60, 64, 67, 71], [62, 66, 69, 72], [57, 60, 64, 67], [53, 57, 60, 64],
                [60, 64, 67, 71], [62, 66, 69, 72], [52, 55, 59, 62], [53, 57, 60, 64]]
ORBIT_BASS = [[(0, a), (8, b)] for a, b in ((48, 55), (48, 57), (45, 52), (41, 48),
                                            (48, 55), (48, 57), (52, 47), (41, 48))]
ORBIT_MELODY = [
    {0: 76, 8: 79, 12: 83}, {0: 81, 8: 78, 12: 76}, {0: 76, 8: 72}, {4: 72, 8: 74},
    {0: 79, 6: 81, 8: 83, 12: 84}, {0: 86, 8: 81, 12: 78}, {0: 79, 8: 83, 12: 79}, {0: 77, 8: 76},
]

# Mars: G major, 100 bpm, 8 bars: G Em C D | G Em Am D. Plucky marimba with a
# few chromatic "hmm?" neighbour notes, a bouncing bass and a soft woodblock.
MARS_CHORDS = [[55, 59, 62, 67], [55, 59, 64], [55, 60, 64], [54, 57, 62],
               [55, 59, 62, 67], [55, 59, 64], [57, 60, 64], [54, 57, 62]]
MARS_BASS = [[(0, r), (6, r + 7), (8, r + 12), (12, r + 7)] for r in (43, 40, 48, 50, 43, 40, 45, 50)]
MARS_MELODY = [
    {0: 74, 3: 76, 4: 74, 8: 71, 12: 67}, {0: 71, 4: 74, 6: 76, 8: 79, 12: 76},
    {0: 76, 2: 75, 4: 76, 8: 79, 12: 84}, {0: 81, 4: 78, 8: 74, 10: 76, 12: 78},
    {0: 79, 4: 74, 6: 76, 8: 79, 12: 83}, {0: 81, 3: 79, 4: 76, 8: 79, 12: 71},
    {0: 72, 4: 76, 8: 81, 10: 79, 12: 76}, {0: 78, 4: 81, 8: 78, 12: 74},
]

# Menu: F major, 90 bpm, 8 bars: F Bb F C | Dm Bb C F. Oom-pah bounce: bass on
# the beats, soft chord stabs on the off-beats, a chiptune pluck melody.
MENU_CHORDS = [[65, 69, 72], [65, 70, 74], [65, 69, 72], [64, 67, 72],
               [62, 65, 69], [65, 70, 74], [64, 67, 72], [65, 69, 72]]
MENU_BASS = [[(0, r), (8, r + 7)] for r in (41, 46, 41, 48, 38, 46, 48, 41)]
MENU_MELODY = [
    {0: 72, 4: 77, 6: 79, 8: 81, 12: 77}, {0: 79, 4: 77, 8: 74, 12: 77},
    {0: 81, 4: 84, 8: 81, 10: 79, 12: 77}, {0: 79, 8: 76, 12: 72},
    {0: 74, 4: 77, 8: 81, 12: 84}, {0: 82, 4: 81, 8: 79, 12: 77},
    {0: 76, 4: 79, 8: 84, 12: 79}, {0: 77, 8: 72},
]


def music_orbit() -> tuple[np.ndarray, int]:
    return render_song(72, ORBIT_CHORDS, ORBIT_BASS, ORBIT_MELODY, seed=72,
                       mel_voice=lambda m: glass(m, 1.4), mel_gain=0.4,
                       arp=[0, 2, 1, 3, 4, 3, 2, 1], arp_steps=8, arp_voice=lambda m: bell(m, 0.9, 0.3),
                       arp_gain=0.22, echo=0.35, pad_gain=0.12, pad_low=1100, pad_attack=1.0,
                       bass_voice="sine")


def music_mars() -> tuple[np.ndarray, int]:
    return render_song(100, MARS_CHORDS, MARS_BASS, MARS_MELODY, seed=100,
                       mel_voice=lambda m: marimba(m, 0.5), mel_gain=0.5,
                       arp=[1, 2, 3, 2], arp_steps=4, arp_voice=lambda m: pluck(m, 0.2),
                       arp_gain=0.12, pad_gain=0.06, pad_low=1200,
                       shaker=0.05, shaker_steps=(2, 6, 10, 14), tick=0.12, tick_steps=(4, 12))


def music_menu() -> tuple[np.ndarray, int]:
    return render_song(90, MENU_CHORDS, MENU_BASS, MENU_MELODY, seed=90,
                       mel_voice=lambda m: pluck(m, 0.35), mel_gain=0.4,
                       stabs=[4, 12], arp_gain=0.1, pad_gain=0.05, pad_low=1500,
                       shaker=0.06, shaker_steps=(2, 6, 10, 14))

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
    "quindar_in": quindar(2525.0, 101), "quindar_out": quindar(2475.0, 102),
    "thruster": thruster, "arm_move": arm_move, "grab": grab, "clunk": clunk, "solar_unfold": solar_unfold,
    "sunrise_chime": sunrise_chime, "photo_golden": photo_golden,
    "parachute_pop": parachute_pop, "crane_lower": crane_lower, "touchdown": touchdown, "crane_bye": crane_bye,
    "drill": drill, "sample_pop": sample_pop, "heli_loop": heli_loop, "phone_home": phone_home, "party": party,
    "boing": boing, "wave": wave_hi, "dock": dock,
    "join": join, "select": select, "ready": ready, "whoosh": whoosh,
}
for _i in range(3):
    SFX[f"camera_{_i + 1}"] = camera(_i)
# Per-sound loudness trims (dB from the target). The Quindar tones are pure
# 2.5 kHz sines: at the same LUFS they feel louder than a broadband sound, so
# they sit a little lower.
TRIM_DB = {"quindar_in": -3.0, "quindar_out": -3.0}
MUSIC = {"rover_hum": rover_hum, "heli_buzz": heli_buzz,
         "music_orbit": music_orbit, "music_mars": music_mars, "music_menu": music_menu}
MAX_BYTES = 9e6


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
            x = normalise(fade_edges(fn()), SFX_LUFS + TRIM_DB.get(name, 0.0), loop=False)
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
