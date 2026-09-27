"""Greyssie and Kira sound synth: the cats' meows, the house sounds and four music loops, all made by our own code.

Run: uv run python tools/sfx.py [--check DIR] [--only name,name]

Copied from Zoo Keeper's tools/sfx.py (oscillators with polyBLEP, ADSR,
glides, zero-phase filters, the formant voice, loudness measurement,
seamless circular music loops). New here:

- The meows are data: every cat in game/data/cats.json gets meow_<id>_1..3
  from its "voice" block (pitch, parts, bright, length, vowels). A new cat or
  a new voice is a JSON edit plus `make sfx`.
- Real recordings dropped at game/audio/real/meow_<id>_*.wav replace the
  synthesized meows in the game (Game handles that); this script never
  touches game/audio/real/.

Everything is seeded, so a rerun writes byte-identical files. Output:
game/audio/<name>.wav, 16-bit mono 44100 Hz. Loudness: SFX -16 LUFS, cat
voices -14 LUFS, music -17 LUFS, purr -20 LUFS; no peak above -1 dBFS. The
report printed at the end is the verification (peak, RMS, LUFS, loop seams);
--check DIR also writes spectrogram + waveform PNGs.
"""
from __future__ import annotations

import argparse
import json
import math
import sys
import wave
from pathlib import Path

import numpy as np

SR = 44100
ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "game" / "audio"

PEAK_DBFS = -1.0
SFX_LUFS = -16.0
# sfx.gd plays music at -8 dB, so a -14 LUFS file sits about 7 dB under the SFX in game.
MUSIC_LUFS = -17.0
PURR_LUFS = -20.0

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
# Cat voices: read from game/data/cats.json, one set per cat
# ----------------------------------------------------------------------------

CATS_JSON = ROOT / "game" / "data" / "cats.json"


def load_cats() -> list[dict]:
    data = json.loads(CATS_JSON.read_text())
    return [c for c in data.get("cats", []) if isinstance(c, dict) and c.get("id")]


def meow(voice: dict, variant: int, seed: int) -> np.ndarray:
    """A cute formant meow: nasal 'm' onset, then the vowel path (e.g. i-a-u),
    pitch gliding up then down. parts=2 makes a two-part 'mi-aow' call."""
    pitch = float(voice.get("pitch", 650))
    parts = int(voice.get("parts", 1))
    bright = float(voice.get("bright", 1.0))
    length = float(voice.get("length", 0.35))
    vowels = [v for v in voice.get("vowels", ["i", "a", "u"]) if v in VOWELS] or ["i", "a", "u"]
    # Variants: 0 = the plain call, 1 = higher and shorter, 2 = lower, longer, more question-like.
    p_mul = [1.0, 1.12, 0.9][variant]
    l_mul = [1.0, 0.85, 1.2][variant]
    peak_at = [0.35, 0.3, 0.55][variant]
    out = np.zeros(secs(parts * (length * l_mul + 0.08) + 0.15))
    t = 0.0
    for k in range(parts):
        d = length * l_mul * (0.7 if parts == 2 and k == 0 else 1.0)
        hz = pitch * p_mul * (0.92 if parts == 2 and k == 0 else 1.0)
        m_len = min(0.05, d * 0.18)
        track = [(0.0, "m"), (m_len, vowels[0])]
        rest = vowels[1:] if not (parts == 2 and k == 0) else vowels[:1]
        for j, v in enumerate(rest):
            track.append((m_len + (d - m_len) * (j + 1) / (len(rest) + 0.3), v))
        track.append((d, track[-1][1]))
        contour = [(0, hz * 0.78), (m_len, hz * 0.9), (d * peak_at, hz * 1.12), (d, hz * 0.8)]
        if variant == 2 and k == parts - 1:
            contour[-1] = (d, hz * 1.02)  # a little questioning lift at the end
        s = syllable(d, contour, track, fscale=bright * 1.45, kind="saw", q=5.5, vib=0.35,
                     breath=0.04 + 0.03 * (bright < 1.0), seed=seed + k, attack=0.03, release=0.09)
        place(out, s, secs(t), 1.0 if k == parts - 1 else 0.75)
        t += d + 0.06
    top = 9000 if bright >= 1.0 else 5000
    return fft_filter(out, low=top, high=250)


# ----------------------------------------------------------------------------
# Cat noises that belong to both cats
# ----------------------------------------------------------------------------


def mrrp() -> np.ndarray:
    """A questioning trill: a rolled 'rr' (amplitude flutter) rising in pitch."""
    d = 0.32
    n = secs(d)
    f = glide(n, [(0, 420), (0.12, 470), (d, 720)])
    tt = np.arange(n) / SR
    flutter = 0.55 + 0.45 * np.sin(2 * np.pi * 28 * tt)
    src = (0.7 * osc("saw", f) + 0.3 * osc("triangle", f)) * flutter
    v = formant_voice(src, vowel_track(n, [(0, "m"), (0.08, "u"), (d, "e")], 1.4), q=5.0)
    return fft_filter(v * adsr(n, 0.02, 0.05, 0.85, 0.08), low=7000, high=200)


def purr() -> np.ndarray:
    """~2 s seamless purr: low pulses at ~26 Hz, in and out breaths (loop-safe)."""
    n = secs(2.0)
    tt = np.arange(n) / SR
    rng = np.random.default_rng(7)
    buzz = fft_filter(osc("white", np.ones(n), rng=rng), low=400, high=40, circular=True)
    pulses = (0.5 + 0.5 * np.sin(2 * np.pi * 26 * tt)) ** 3  # 52 pulses in 2 s: whole cycles
    breath = 0.65 + 0.35 * np.sin(2 * np.pi * tt / 2.0 - np.pi / 2) ** 2
    body = osc("sine", np.full(n, 52.0)) * 0.3
    return fft_filter((buzz * 1.4 + body) * pulses * breath, low=900, circular=True)


def prrt() -> np.ndarray:
    """The playful chirp instead of a hiss: a short bright rolled 'prrt!'."""
    d = 0.16
    n = secs(d)
    f = glide(n, [(0, 700), (0.06, 1000), (d, 850)])
    tt = np.arange(n) / SR
    src = osc("saw", f) * (0.5 + 0.5 * np.sin(2 * np.pi * 40 * tt))
    v = formant_voice(src, vowel_track(n, [(0, "e"), (d, "i")], 1.5), q=5.0)
    rng = np.random.default_rng(12)
    t_ = fft_filter(osc("white", np.ones(secs(0.03)), rng=rng), low=8000, high=3000) * perc(secs(0.03), 0.001, 0.008)
    out = np.zeros(secs(0.22))
    place(out, v * adsr(n, 0.008, 0.03, 0.8, 0.05), 0)
    place(out, t_, secs(0.15), 0.4)
    return fft_filter(out, low=9000, high=250)


# ----------------------------------------------------------------------------
# Sound effects
# ----------------------------------------------------------------------------


def treat_shake(variant: int) -> np.ndarray:
    """Kibble rattling in a crinkly bag: 3-4 shakes of pitched clicks plus crinkle."""
    rng = np.random.default_rng(100 + variant)
    shakes = [[0.0, 0.14, 0.28], [0.0, 0.12, 0.24, 0.36], [0.0, 0.18]][variant]
    out = np.zeros(secs(max(shakes) + 0.3))
    for st in shakes:
        for _ in range(14):
            at = st + rng.uniform(0, 0.09)
            n = secs(0.012)
            f = rng.uniform(2500, 5200)
            click = osc("sine", np.full(n, f)) * perc(n, 0.0005, 0.002)
            place(out, click, secs(at), rng.uniform(0.3, 0.8))
        n = secs(0.11)
        crinkle = fft_filter(osc("noise", np.full(n, 9000.0), rng=rng), low=9000, high=2500) * perc(n, 0.004, 0.04)
        place(out, crinkle, secs(st), 0.45)
    return fft_filter(out, low=11000, high=400)


def psst() -> np.ndarray:
    """'psst psst': a plosive tick then a hissy 's' band, twice."""
    rng = np.random.default_rng(21)
    out = np.zeros(secs(0.7))
    for st in (0.0, 0.3):
        n = secs(0.2)
        s = fft_filter(osc("white", np.ones(n), rng=rng), low=9500, high=4200)
        s *= env_pts(n, [(0, 0), (0.02, 0.4), (0.06, 1), (0.16, 0.7), (0.2, 0)])
        p = fft_filter(osc("white", np.ones(secs(0.015)), rng=rng), low=1500, high=200) * perc(secs(0.015), 0.001, 0.004)
        place(out, p, secs(st), 0.6)
        place(out, s, secs(st + 0.012))
    return out


def pounce() -> np.ndarray:
    """A soft whump on the rug and a tiny happy squeak."""
    n = secs(0.25)
    thud = osc("sine", glide(n, [(0, 160), (0.1, 60), (0.25, 50)])) * perc(n, 0.002, 0.06)
    rng = np.random.default_rng(31)
    fluff = fft_filter(osc("white", np.ones(n), rng=rng), low=1200, high=100) * perc(n, 0.002, 0.04)
    m = secs(0.09)
    sq = osc("sine", glide(m, [(0, 1600), (0.04, 2300), (0.09, 1900)])) * adsr(m, 0.005, 0.02, 0.6, 0.03)
    out = np.zeros(secs(0.4))
    place(out, thud + 0.5 * fluff, 0)
    place(out, sq, secs(0.12), 0.35)
    return fft_filter(out, low=6000, high=40)


def zoomies() -> np.ndarray:
    """Pitter-patter of fast paws running past (~1.2 s, louder in the middle)."""
    rng = np.random.default_rng(41)
    out = np.zeros(secs(1.25))
    t = 0.0
    k = 0
    while t < 1.15:
        n = secs(0.03)
        tap = fft_filter(osc("white", np.ones(n), rng=rng), low=2500 + 400 * (k % 2), high=300) * perc(n, 0.001, 0.008)
        thump = osc("sine", np.full(n, 180.0 + 30 * (k % 4))) * perc(n, 0.001, 0.01)
        place(out, 0.8 * tap + 0.5 * thump, secs(t), 0.4 + 0.6 * math.sin(math.pi * t / 1.2))
        t += 0.055 if k % 4 != 3 else 0.09
        k += 1
    return fft_filter(out, high=80)


def cup_boing() -> np.ndarray:
    """A cartoon spring boing with wobbling pitch, plus a tiny ceramic clink."""
    n = secs(0.7)
    tt = np.arange(n) / SR
    f = glide(n, [(0, 180), (0.05, 520), (0.7, 300)]) * 2 ** (0.9 * np.sin(2 * np.pi * 11 * tt) * np.exp(-tt / 0.35) / 12 * 3)
    s = (0.7 * osc("triangle", f) + 0.3 * osc("sine", f * 2)) * adsr(n, 0.004, 0.1, 0.6, 0.35)
    m = secs(0.3)
    clink = sum(a * np.sin(2 * np.pi * midi(96) * r * np.arange(m) / SR) for r, a in [(1, 1), (2.7, 0.5), (5.1, 0.25)]) * perc(m, 0.001, 0.06)
    out = np.zeros(secs(0.8))
    place(out, clink, 0, 0.35)
    place(out, s, secs(0.04))
    return fft_filter(out, low=9000, high=80)


def open_door() -> np.ndarray:
    """A soft friendly wooden creak (a slow gliding scrape), then a knock of the latch."""
    n = secs(0.6)
    tt = np.arange(n) / SR
    f = glide(n, [(0, 260), (0.3, 380), (0.6, 310)])
    stick = (0.5 + 0.5 * np.sin(2 * np.pi * 35 * tt)) ** 4
    src = osc("saw", f) * stick
    v = formant_voice(src, vowel_track(n, [(0, "o"), (0.6, "e")], 1.0), q=6.0, gains=(0.8, 0.6, 0.2))
    v *= adsr(n, 0.06, 0.1, 0.7, 0.2)
    k = secs(0.06)
    knock = osc("sine", glide(k, [(0, 300), (0.06, 150)])) * perc(k, 0.001, 0.015)
    out = np.zeros(secs(0.7))
    place(out, knock, 0, 0.7)
    place(out, v, secs(0.05), 0.6)
    return fft_filter(out, low=4000, high=100)


def open_box() -> np.ndarray:
    """Cardboard flaps: two papery rustle swipes and a soft flap thud."""
    rng = np.random.default_rng(51)
    out = np.zeros(secs(0.45))
    for st, lo in [(0.0, 3500), (0.13, 5000)]:
        n = secs(0.12)
        r = fft_filter(osc("noise", np.full(n, 6000.0), rng=rng), low=lo, high=700) * env_pts(n, [(0, 0), (0.02, 1), (0.12, 0)])
        place(out, r, secs(st))
    k = secs(0.1)
    place(out, osc("sine", glide(k, [(0, 140), (0.1, 80)])) * perc(k, 0.002, 0.03), secs(0.26), 0.8)
    return out


def stairs_step() -> np.ndarray:
    """A soft hollow wooden step."""
    n = secs(0.12)
    rng = np.random.default_rng(61)
    thud = osc("sine", glide(n, [(0, 190), (0.12, 110)])) * perc(n, 0.002, 0.03)
    wood = osc("sine", np.full(n, 620.0)) * perc(n, 0.001, 0.012) * 0.4
    tap = fft_filter(osc("white", np.ones(n), rng=rng), low=2000, high=300) * perc(n, 0.001, 0.01) * 0.4
    return thud + wood + tap


def bowl_fill() -> np.ndarray:
    """Kibble pouring into a bowl: a dense shower of clicks, a little ring of the bowl."""
    rng = np.random.default_rng(71)
    d = 0.9
    out = np.zeros(secs(d + 0.3))
    for _ in range(90):
        at = rng.uniform(0, d) ** 1.1
        n = secs(0.01)
        f = rng.uniform(2000, 4500)
        place(out, osc("sine", np.full(n, f)) * perc(n, 0.0005, 0.002), secs(at), rng.uniform(0.2, 0.6))
    n = secs(1.0)
    tt = np.arange(n) / SR
    ring = (np.sin(2 * np.pi * 1320 * tt) + 0.4 * np.sin(2 * np.pi * 3100 * tt)) * np.exp(-tt / 0.3)
    place(out, ring * np.minimum(tt / 0.01, 1), 0, 0.12)
    return fft_filter(out, low=10000, high=500)


def eat_crunch() -> np.ndarray:
    """Four small crunches."""
    rng = np.random.default_rng(81)
    out = np.zeros(secs(0.75))
    for k, st in enumerate([0.0, 0.17, 0.33, 0.52]):
        n = secs(0.07)
        c = fft_filter(osc("noise", np.full(n, 5000.0 + 800 * k), rng=rng), low=5500, high=900) * perc(n, 0.001, 0.02)
        place(out, c, secs(st), 0.9 - 0.1 * k)
    return out


def chime_note(m: float, n: int, decay: float = 0.5) -> np.ndarray:
    t = np.arange(n) / SR
    f = midi(m)
    s = np.sin(2 * np.pi * f * t) + 0.3 * np.sin(2 * np.pi * f * 2.0 * t) * np.exp(-t / 0.15) \
        + 0.15 * np.sin(2 * np.pi * f * 3.01 * t) * np.exp(-t / 0.08)
    out = s * np.exp(-t / decay) * np.minimum(t / 0.002, 1.0)
    fade = min(n, secs(0.01))
    out[n - fade:] *= np.linspace(1, 0, fade)
    return out


def notes(seq: list[tuple[float, float]], voice=chime_note, tail: float = 0.5, gain: float = 1.0) -> np.ndarray:
    total = sum(d for _, d in seq) + tail
    out = np.zeros(secs(total))
    t = 0.0
    for i, (m, d) in enumerate(seq):
        n = secs(d + (tail if i == len(seq) - 1 else 0.35))
        place(out, voice(m, n), secs(t), gain)
        t += d
    return out


def find_star() -> np.ndarray:
    """A sparkly rising chime with shimmer."""
    out = notes([(84, 0.07), (88, 0.07), (91, 0.07), (96, 0.12)], tail=0.6)
    rng = np.random.default_rng(91)
    for _ in range(10):
        at = rng.uniform(0.1, 0.7)
        place(out, chime_note(rng.choice([96, 100, 103, 108]), secs(0.15), 0.05), secs(at), 0.15)
    return fft_filter(out, low=11000, high=200)


def funny_find() -> np.ndarray:
    """A silly 'boop-bwoop': a low boop, then a sliding bwoop up."""
    out = np.zeros(secs(0.55))
    n = secs(0.12)
    place(out, osc("sine", np.full(n, 330.0)) * adsr(n, 0.005, 0.03, 0.7, 0.05), 0)
    m = secs(0.3)
    f = glide(m, [(0, 250), (0.3, 620)])
    s = (0.7 * osc("sine", f) + 0.3 * osc("triangle", f)) * adsr(m, 0.01, 0.05, 0.8, 0.1)
    place(out, s, secs(0.16))
    return fft_filter(out, low=5000, high=120)


def day_chime() -> np.ndarray:
    """Three gentle notes: the next part of the day."""
    return fft_filter(notes([(79, 0.22), (84, 0.22), (88, 0.3)], tail=0.9, voice=lambda m, n: chime_note(m, n, 0.8)),
                      low=9000, high=150)


def goodnight() -> np.ndarray:
    """A soft music-box phrase, four notes falling to the low tonic."""
    return fft_filter(notes([(84, 0.35), (79, 0.35), (76, 0.35), (72, 0.6)], voice=lambda m, n: box_note(m, n), tail=1.2),
                      low=8000, high=120)


def giggle() -> np.ndarray:
    """A tiny playful giggle: four quick up-down formant chirps, 'hi-hi-hi-hi'."""
    out = np.zeros(secs(0.6))
    for k in range(4):
        d = 0.075
        hz = 900 - 45 * k
        s = syllable(d, [(0, hz * 1.1), (0.03, hz * 1.2), (d, hz * 0.9)], [(0, "i"), (d, "e")],
                     fscale=1.6, q=5.0, vib=0.0, breath=0.15, seed=300 + k, attack=0.005, release=0.02)
        place(out, s, secs(0.02 + k * 0.11), 1.0 - 0.12 * k)
    return fft_filter(out, low=9000, high=300)


def whoosh() -> np.ndarray:
    n = secs(0.45)
    rng = np.random.default_rng(88)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 250), (0.2, 2600), (0.45, 350)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.18, 1), (0.45, 0)]) ** 1.5
    return fft_filter(y * e, high=120)


def join() -> np.ndarray:
    return fft_filter(notes([(72, 0.07), (76, 0.07), (79, 0.07), (84, 0.14)], voice=marimba_note, tail=0.25), low=7000, high=150)


def select() -> np.ndarray:
    return marimba_note(84, secs(0.12)) * 0.9


def ready() -> np.ndarray:
    return fft_filter(notes([(76, 0.09), (84, 0.2)], voice=marimba_note, tail=0.3), low=7000, high=150)


def heart() -> np.ndarray:
    """A soft bubbly pop."""
    n = secs(0.14)
    f = glide(n, [(0, 500), (0.05, 1100), (0.14, 900)])
    return osc("sine", f) * adsr(n, 0.004, 0.04, 0.5, 0.06)


# ----------------------------------------------------------------------------
# Music: circular buffers so every loop is seamless.
# ----------------------------------------------------------------------------

S = "-"  # hold


def marimba_note(m: float, n: int, decay: float = 0.32) -> np.ndarray:
    t = np.arange(n) / SR
    f = midi(m)
    body = np.sin(2 * np.pi * f * t) * np.exp(-t / decay)
    over = 0.35 * np.sin(2 * np.pi * f * 3.93 * t) * np.exp(-t / (decay * 0.18))
    tick = 0.15 * np.sin(2 * np.pi * f * 9.2 * t) * np.exp(-t / 0.008)
    out = (body + over + tick) * np.minimum(t / 0.0015, 1.0)
    fade = min(n, secs(0.01))
    out[n - fade:] *= np.linspace(1, 0, fade)
    return out


def box_note(m: float, n: int, decay: float = 0.7) -> np.ndarray:
    """Music-box tine: bright inharmonic partials over a soft sine."""
    t = np.arange(n) / SR
    f = midi(m)
    s = np.sin(2 * np.pi * f * t) * np.exp(-t / decay) \
        + 0.3 * np.sin(2 * np.pi * f * 4.2 * t) * np.exp(-t / (decay * 0.12)) \
        + 0.12 * np.sin(2 * np.pi * f * 6.8 * t) * np.exp(-t / 0.03)
    out = s * np.minimum(t / 0.001, 1.0)
    fade = min(n, secs(0.01))
    out[n - fade:] *= np.linspace(1, 0, fade)
    return out


def pluck(m: float, n: int) -> np.ndarray:
    t = np.arange(n) / SR
    f = midi(m)
    s = (0.6 * osc("triangle", np.full(n, f)) + 0.4 * osc("saw", np.full(n, f))) * np.exp(-t / 0.09)
    return fft_filter(s * np.minimum(t / 0.002, 1.0), low=2400)


def triad(root: int, minor: bool) -> list[int]:
    return [root + 12, root + 12 + (3 if minor else 4), root + 12 + 7]


def render_song(bpm: float, lead: list, roots: list, steps: int, lead_voice, lead_gain: float,
                style: str, seed: int) -> tuple[np.ndarray, int]:
    """style: 'cosy' (soft pads/plucks + brush), 'box' (music box + low hum), 'menu', 'party' (drums)."""
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, f"{bpm} BPM: a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    assert bar_len % steps == 0 and bar_len % 8 == 0
    bars = len(lead)
    total = bar_len * bars
    step = bar_len // steps
    rng = np.random.default_rng(seed)
    lead_buf = np.zeros(total)
    for b, bar in enumerate(lead):
        for k, m in enumerate(bar):
            if m is None or m == S:
                continue
            place(lead_buf, lead_voice(m, secs(1.1)), b * bar_len + k * step, lead_gain, circular=True)
            if style == "box":
                place(lead_buf, box_note(m + 12, secs(0.5), 0.2), b * bar_len + k * step, lead_gain * 0.2, circular=True)
    bass_buf = np.zeros(total)
    quarter = bar_len // 4
    for b, (r, minor) in enumerate(roots):
        pattern = {"party": [r, r + 7, r + 12, r + 7], "cosy": [r, None, r + 7, None],
                   "box": [r, None, None, None], "menu": [r, None, r + 7, None]}[style]
        for k, m in enumerate(pattern):
            if m is None:
                continue
            n = (quarter * (4 if style == "box" else 1)) - secs(0.02)
            t = np.arange(n) / SR
            dec = 0.9 if style == "box" else 0.25
            s = osc("triangle", np.full(n, midi(m))) * np.exp(-t / dec) * np.minimum(t / 0.006, 1.0)
            place(bass_buf, s, b * bar_len + k * quarter, 0.5 if style != "box" else 0.35, circular=True)
    bass_buf = fft_filter(bass_buf, low=1000, circular=True)
    chord_buf = np.zeros(total)
    eighth = bar_len // 8
    if style in ("cosy", "party", "menu"):
        for b, (r, minor) in enumerate(roots):
            ks = (1, 3, 5, 7) if style != "menu" else (2, 6)
            for k in ks:
                for m in triad(r, minor):
                    place(chord_buf, pluck(m + (12 if style == "party" else 0), eighth), b * bar_len + k * eighth,
                          0.1 if style != "party" else 0.12, circular=True)
    drum_buf = np.zeros(total)
    sixteenth = bar_len // 16
    if style in ("cosy", "party"):
        kick_n = secs(0.14)
        kick = osc("sine", glide(kick_n, [(0, 110), (0.08, 55), (0.14, 50)])) * perc(kick_n, 0.002, 0.05)
        for b in range(bars):
            for k in range(16):
                pos = b * bar_len + k * sixteenth
                if style == "party" and k in (0, 8):
                    place(drum_buf, kick, pos, 0.8, circular=True)
                if style == "party" and k in (4, 12):
                    n = secs(0.08)
                    cl = fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=1200) * perc(n, 0.001, 0.02)
                    place(drum_buf, 0.45 * cl, pos, 0.8, circular=True)
                if style == "cosy" and k in (0, 10):
                    place(drum_buf, kick, pos, 0.35, circular=True)
                if style == "cosy" and k in (4, 12):  # a soft brush
                    n = secs(0.12)
                    br = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=2000) * env_pts(n, [(0, 0), (0.03, 1), (0.12, 0)])
                    place(drum_buf, br, pos, 0.15, circular=True)
                if style == "party" or k % 2 == 0:
                    n = secs(0.03)
                    sh = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.003, 0.008)
                    place(drum_buf, sh, pos, (0.1 if k % 2 == 0 else 0.06) * (0.5 if style == "cosy" else 1), circular=True)
        drum_buf = fft_filter(drum_buf, low=10000, circular=True)
    mix = lead_buf + bass_buf + chord_buf + drum_buf
    return fft_filter(mix, high=30, circular=True), bar_len


# 90 BPM, C major, 8 bars: C Am F G | C Am Dm G
HOUSE_LEAD = [
    [72, S, 76, 79, 76, S, 74, S], [72, S, 69, 72, 76, S, S, S],
    [77, S, 76, 74, 72, S, 69, S], [71, S, 74, S, 79, S, S, S],
    [79, S, 76, 72, 76, S, 79, S], [81, S, 79, 76, 72, S, S, S],
    [74, S, 77, 81, 79, S, 77, S], [76, S, 74, S, 71, S, None, None],
]
HOUSE_ROOTS = [(48, False), (45, True), (41, False), (43, False), (48, False), (45, True), (50, True), (43, False)]
# 72 BPM lullaby, F major pentatonic-ish, 6 bars of quarters.
NIGHT_LEAD = [
    [77, 81, 84, 81], [79, S, 77, S], [74, 77, 81, 79], [77, S, 72, S],
    [74, 77, 79, 81], [77, S, S, None],
]
NIGHT_ROOTS = [(41, False), (46, False), (38, True), (41, False), (46, False), (41, False)]
# Menu 100 BPM, G major, 8 bars of quarters.
MENU_LEAD = [
    [79, 76, 74, 71], [72, 74, 76, S], [74, 71, 67, 69], [71, S, 74, S],
    [79, 76, 74, 71], [72, 76, 79, S], [78, 74, 76, 78], [79, S, S, None],
]
MENU_ROOTS = [(43, False), (36, False), (43, False), (38, False), (43, False), (36, False), (38, False), (43, False)]
# Party 105 BPM (a bar = 100800 samples), C major, 8 bars of 8ths.
PARTY_LEAD = [
    [72, 76, 79, 84, 79, 76, 79, S], [81, S, 77, S, 81, 84, 81, S],
    [79, 76, 72, 76, 79, S, 84, S], [83, S, 79, S, 74, 79, 83, S],
    [84, S, 83, 81, 79, S, 76, S], [77, 81, 84, S, 81, S, 77, S],
    [76, 79, 84, S, 79, S, 76, S], [74, 77, 79, 83, 84, S, None, None],
]
PARTY_ROOTS = [(48, False), (41, False), (48, False), (43, False), (45, True), (41, False), (48, False), (43, False)]


def music_house():
    return render_song(90, HOUSE_LEAD, HOUSE_ROOTS, 8, lambda m, n: marimba_note(m, n, 0.45), 0.55, "cosy", 200)


def music_night():
    return render_song(72, NIGHT_LEAD, NIGHT_ROOTS, 4, box_note, 0.5, "box", 201)


def music_menu():
    return render_song(100, MENU_LEAD, MENU_ROOTS, 4, lambda m, n: marimba_note(m, n, 0.5), 0.5, "menu", 202)


def music_party():
    return render_song(105, PARTY_LEAD, PARTY_ROOTS, 8, marimba_note, 0.6, "party", 203)


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


def _variants(fn, count: int) -> dict:
    return {f"{fn.__name__}_{i + 1}": (lambda i=i: fn(i)) for i in range(count)}


def build_tables() -> tuple[dict, dict, set]:
    voices = {}
    for ci, cat in enumerate(load_cats()):
        v = cat.get("voice", {}) or {}
        for i in range(3):
            voices[f"meow_{cat['id']}_{i + 1}"] = (lambda v=v, i=i, ci=ci: meow(v, i, 1000 + ci * 10 + i))
    sfx = {
        **_variants(treat_shake, 3), "psst": psst, **voices, "mrrp": mrrp, "prrt": prrt,
        "pounce": pounce, "zoomies": zoomies, "cup_boing": cup_boing, "open_door": open_door,
        "open_box": open_box, "stairs_step": stairs_step, "bowl_fill": bowl_fill, "eat_crunch": eat_crunch,
        "find_star": find_star, "funny_find": funny_find, "day_chime": day_chime, "goodnight": goodnight,
        "giggle": giggle, "whoosh": whoosh, "join": join, "select": select, "ready": ready, "heart": heart,
    }
    music = {"purr": purr, "music_house": music_house, "music_night": music_night,
             "music_menu": music_menu, "music_party": music_party}
    loud_voices = set(voices) | {"mrrp", "prrt"}
    return sfx, music, loud_voices


VOICE_LUFS = -14.0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", type=Path, help="write spectrogram/seam PNGs to this directory")
    ap.add_argument("--only", help="comma-separated names to (re)build")
    args = ap.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    if args.check:
        args.check.mkdir(parents=True, exist_ok=True)
    only = set(args.only.split(",")) if args.only else None
    SFX, MUSIC, VOICES = build_tables()

    ok = True
    total_bytes = 0
    print(f"{'file':<20}{'secs':>7}{'peak dBFS':>11}{'RMS dBFS':>10}{'LUFS':>8}{'ST max':>8}{'DC':>10}")
    rows = [(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in MUSIC.items()]
    for name, fn, loop in rows:
        if only and name not in only:
            p = OUT / f"{name}.wav"
            if p.exists():
                total_bytes += p.stat().st_size
            continue
        if loop:
            res = fn()
            x, bar_len = res if isinstance(res, tuple) else (res, None)
            target = PURR_LUFS if name == "purr" else MUSIC_LUFS
            x = normalise(x, target, loop=True)
        else:
            target = VOICE_LUFS if name in VOICES else SFX_LUFS
            x = normalise(fade_edges(fn()), target, loop=False)
            x = fade_edges(x)
        pcm = to_pcm(x)
        path = OUT / f"{name}.wav"
        write_wav(path, pcm)
        total_bytes += path.stat().st_size
        y = pcm.astype(np.float64) / 32768.0
        peak = np.abs(y).max()
        loud, st = lufs(y, loop)
        print(f"{name:<20}{len(y) / SR:>7.2f}{db(peak):>11.2f}{db(np.sqrt((y * y).mean())):>10.2f}"
              f"{loud:>8.1f}{st:>8.1f}{y.mean():>10.5f}")
        if db(peak) > PEAK_DBFS + 0.01:
            ok = False
            print(f"  FAIL: {name} peaks above {PEAK_DBFS} dBFS")
        if loop:
            step = np.abs(np.diff(y))
            seam = abs(y[0] - y[-1])
            p99 = np.percentile(step, 99)
            good = seam <= p99
            desc = ""
            if bar_len:
                bars = len(y) / bar_len
                good &= bars == int(bars)
                desc = f"{bars:g} bars x {bar_len}; "
            ok &= good
            print(f"  loop: {len(y)} samples = {desc}seam jump {seam:.5f} vs p99 step {p99:.5f} -> {'OK' if good else 'FAIL'}")
        else:
            if abs(y[0]) > 1e-3 or abs(y[-1]) > 1e-3:
                ok = False
                print(f"  FAIL: {name} does not start/end at zero")
        if args.check:
            spectrogram_png(name, y, args.check / f"{name}.png")
            if loop:
                seam_png(name, y, args.check / f"{name}_seam.png")
    print(f"total {total_bytes / 1e6:.2f} MB in {OUT.relative_to(ROOT)}")
    if total_bytes > 10e6:
        ok = False
        print("FAIL: audio total above 10 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
