"""Paint Party sound synth: every sound, the brush loop and both music loops, made by our own code.

Copied from PixelPals's tools/sfx.py (same synth, measurement and report);
the sounds themselves are Paint Party's. music_menu and join/select/ready/
party/whoosh are PixelPals's, reused as they are.

Run: uv run python tools/sfx.py [--check DIR]

A small sfxr-style synth (square/saw/triangle/sine/noise oscillators with
polyBLEP, ADSR envelopes, pitch slides by breakpoints, vibrato, arpeggios and
a zero-phase low/high-pass filter). Everything is seeded, so a rerun writes
byte-identical files. Output: game/audio/<name>.wav, 16-bit mono 44100 Hz.

Loudness: SFX are normalised to about -15 LUFS (whole clip, K-weighted,
BS.1770 without gating) and music to MUSIC_LUFS; no file peaks above -1 dBFS.
The report printed at the end is the verification: peak, RMS, LUFS, length,
and for the music loops the bar count and the loop-seam continuity.
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
# Sound effects
# ----------------------------------------------------------------------------


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



# ----------------------------------------------------------------------------
# Paint Party sounds
# ----------------------------------------------------------------------------


def bell(m: float, n: int, decay: float = 0.35) -> np.ndarray:
    """A small bell: a sine with an inharmonic partial, fast attack."""
    f = midi(m)
    t = np.arange(n) / SR
    s = np.sin(2 * np.pi * f * t) + 0.35 * np.sin(2 * np.pi * f * 2.76 * t) * np.exp(-t / (decay * 0.3))
    return s * perc(n, 0.002, decay)


def stamp(variant: int) -> np.ndarray:
    """A rubber stamp: a soft low thunk, a tiny click, then a bell."""
    out = np.zeros(secs(0.7))
    rng = np.random.default_rng(200 + variant)
    n = secs(0.16)
    thunk = osc("sine", glide(n, [(0, 190 + 15 * variant), (0.12, 70)])) * perc(n, 0.002, 0.045)
    place(out, thunk, 0, 0.9)
    n = secs(0.03)
    click = fft_filter(osc("white", np.ones(n), rng=rng), low=3000, high=500) * perc(n, 0.001, 0.006)
    place(out, click, 0, 0.35)
    note = [79, 83, 86, 91][variant - 1]
    n = secs(0.6)
    place(out, bell(note, n, 0.22), secs(0.05), 0.45)
    place(out, bell(note + 7, n, 0.15), secs(0.08), 0.15)
    return fft_filter(out, low=8000, high=50)


def splat(variant: int) -> np.ndarray:
    """A wet paint splat: a noise burst through a closing low-pass, a low pitch
    drop underneath, and droplet blips pattering after it."""
    rng = np.random.default_rng(300 + variant)
    out = np.zeros(secs(0.75))
    n = secs(0.35)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 3500 + 400 * variant), (0.08, 1400), (0.35, 300)])
    wet = onepole_sweep(onepole_sweep(noise, cutoff), cutoff) * perc(n, 0.002, 0.08)
    place(out, wet, 0, 2.2)
    n = secs(0.3)
    drop = osc("sine", glide(n, [(0, 260 - 20 * variant), (0.25, 55)])) * perc(n, 0.003, 0.09)
    place(out, drop, 0, 0.8)
    for _ in range(3 + variant):
        n = secs(0.035)
        f0 = rng.uniform(700, 1300)
        blip = osc("sine", glide(n, [(0, f0), (0.035, f0 * 1.8)])) * perc(n, 0.002, 0.012)
        place(out, blip, secs(rng.uniform(0.12, 0.55)), 0.3)
    return fft_filter(out, low=7000, high=40)


def rainbow() -> np.ndarray:
    """The rainbow splat: a splat under a two-octave pentatonic run up and sparkles."""
    out = np.zeros(secs(1.3))
    place(out, splat(1), 0, 0.6)
    run = [72, 74, 76, 79, 81, 84, 86, 88, 91, 93, 96]
    for i, m in enumerate(run):
        n = secs(0.25)
        s = 0.7 * osc("triangle", np.full(n, midi(m))) + 0.3 * osc("sine", np.full(n, midi(m) * 2))
        place(out, s * perc(n, 0.002, 0.08), secs(0.06 + 0.055 * i), 0.4)
    rng = np.random.default_rng(404)
    for _ in range(8):
        n = secs(0.09)
        s = osc("sine", np.full(n, midi(rng.choice([96, 100, 103, 108])))) * perc(n, 0.002, 0.03)
        place(out, s, secs(rng.uniform(0.5, 1.15)), 0.22)
    return fft_filter(out, low=8000, high=60)


def pot_pick(variant: int) -> np.ndarray:
    """One pentatonic marimba note per pot (C D E G), with a small bloop."""
    m = [72, 74, 76, 79][variant - 1]
    n = secs(0.4)
    f = np.full(n, midi(m))
    t = np.arange(n) / SR
    s = osc("sine", f) + 0.25 * osc("sine", f * 4) * np.exp(-t / 0.03)
    out = s * perc(n, 0.002, 0.12)
    n2 = secs(0.07)
    bloop = osc("sine", glide(n2, [(0, midi(m - 12)), (0.07, midi(m))])) * perc(n2, 0.002, 0.03)
    place(out, bloop, 0, 0.35)
    return fft_filter(out, low=6000, high=120)


def page_turn() -> np.ndarray:
    """Paper flipping: three quick bandpassed noise flutters and a soft rising tone."""
    rng = np.random.default_rng(55)
    out = np.zeros(secs(0.4))
    for i in range(3):
        n = secs(0.07)
        f = fft_filter(osc("white", np.ones(n), rng=rng), low=6000, high=1800) * perc(n, 0.004, 0.02)
        place(out, f, secs(0.05 * i), 0.6 - 0.12 * i)
    n = secs(0.2)
    place(out, osc("sine", glide(n, [(0, 600), (0.2, 900)])) * adsr(n, 0.01, 0.05, 0.5, 0.1), secs(0.06), 0.25)
    return fft_filter(out, low=8000, high=200)


def undo() -> np.ndarray:
    """A reverse whoosh with a tone sliding down."""
    w = whoosh()[::-1].copy()
    n = len(w)
    tone_ = osc("triangle", glide(n, [(0, 700), (n / SR, 330)])) * env_pts(n, [(0, 0), (0.1, 0.4), (n / SR, 0)])
    return fft_filter(w + 0.25 * tone_, high=100)


def frame_it() -> np.ndarray:
    """Ta-da: a two-note fanfare into a big major chord with shimmer."""
    out = np.zeros(secs(1.7))
    for (m, at, d) in [(67, 0.0, 0.12), (72, 0.14, 0.9)]:
        n = secs(d + 0.3)
        f = np.full(n, midi(m))
        if d > 0.5:
            f = vibrato(f, 6, 0.25, delay=0.15)
        s = osc("square", f, duty=0.3) * adsr(n, 0.004, 0.08, 0.6, 0.3)
        place(out, s, secs(at), 0.5)
    n = secs(1.4)
    t = np.arange(n) / SR
    chord = np.zeros(n)
    for m in [60, 64, 67, 72, 76]:
        chord += osc("sine", vibrato(np.full(n, midi(m)), 5.5, 0.12)) + 0.3 * osc("triangle", np.full(n, midi(m)))
    chord *= (1 + 0.15 * np.sin(2 * np.pi * 7 * t)) * adsr(n, 0.01, 0.3, 0.5, 0.6)
    place(out, chord, secs(0.14), 0.22)
    rng = np.random.default_rng(12)
    for _ in range(10):
        n = secs(0.08)
        place(out, osc("sine", np.full(n, midi(rng.choice([96, 100, 103, 108])))) * perc(n, 0.002, 0.025),
              secs(rng.uniform(0.3, 1.4)), 0.2)
    n = secs(1.0)
    cym = fft_filter(osc("white", np.ones(n), rng=rng), low=10000, high=5000) * perc(n, 0.003, 0.3)
    place(out, cym, secs(0.14), 0.12)
    return fft_filter(out, low=8000, high=60)


def clap() -> np.ndarray:
    """A little crowd clapping four times: each clap is a few noise micro-bursts."""
    rng = np.random.default_rng(66)
    out = np.zeros(secs(1.3))
    for k in range(4):
        base = 0.28 * k
        for _person in range(4):
            at = base + rng.uniform(0, 0.03)
            centre = rng.uniform(900, 1800)
            for b in range(3):
                n = secs(0.05)
                burst = fft_filter(osc("white", np.ones(n), rng=rng), low=centre * 2.5, high=centre * 0.6)
                place(out, burst * perc(n, 0.0005, 0.004 if b < 2 else 0.03), secs(at + b * 0.008), 0.5)
    return fft_filter(out, low=9000, high=300)


def giggle() -> np.ndarray:
    """Hee-hee-hee: four short syllables of a high voice, each sliding down."""
    out = np.zeros(secs(0.75))
    for i, start in enumerate([0.0, 0.14, 0.28, 0.43]):
        n = secs(0.1 if i < 3 else 0.18)
        f0 = 820 - 30 * i
        f = vibrato(glide(n, [(0, f0), (n / SR, f0 * 0.8)]), 18, 0.5)
        voice = osc("saw", f)
        # two formants of an "ee" vowel
        v = fft_filter(voice, low=3200, high=2200) * 1.6 + fft_filter(voice, low=600, high=250) * 0.8
        place(out, v * adsr(n, 0.008, 0.02, 0.8, 0.04), secs(start), 1.0)
        # breathy onset
        rng = np.random.default_rng(70 + i)
        nb = secs(0.03)
        place(out, fft_filter(osc("white", np.ones(nb), rng=rng), low=6000, high=2500) * perc(nb, 0.002, 0.01),
              secs(start), 0.2)
    return fft_filter(out, low=7000, high=150)


def brush_loop() -> tuple[np.ndarray, int]:
    """A soft filtered-noise swish, 2 s, seamless (built circularly). The game
    loops it while painting and bends its pitch with the brush speed."""
    n = secs(2.0)
    rng = np.random.default_rng(9)
    noise = osc("white", np.ones(n), rng=rng)
    band = fft_filter(noise, low=2400, high=450, circular=True)
    t = np.arange(n) / SR
    swish = 0.65 + 0.35 * np.sin(2 * np.pi * 3.0 * t) ** 2  # 6 swishes per loop, whole cycles
    x = band * swish
    return fft_filter(x, high=60, circular=True), n


# G major, 80 BPM, 8 bars of quarters: G Em C D x2. Gentle: triangle lead,
# soft kick and hat only, quieter than the menu so the family can talk over it.
_PAINT_TRIADS = {43: [55, 59, 62], 40: [52, 55, 59], 48: [60, 64, 67], 38: [62, 66, 69]}
PAINT_LEAD = [
    [67, 71, 74, 71], [71, S, 67, S], [72, 76, 74, 72], [74, S, S, None],
    [79, 76, 74, 71], [71, 74, 67, S], [69, 72, 71, 69], [66, S, 67, S],
]
_PAINT_ROOTS = [43, 40, 48, 38, 43, 40, 48, 38]
PAINT_BASS = [[r, S, r + 7, S] for r in _PAINT_ROOTS]
PAINT_CHORDS = [_PAINT_TRIADS[r] for r in _PAINT_ROOTS]
PAINT_DRUMS = "k-------h-------"


def music_paint() -> tuple[np.ndarray, int]:
    return render_song(80, 8, 4, PAINT_LEAD, PAINT_BASS, PAINT_CHORDS, 0.5, 1800, 0.55,
                       PAINT_DRUMS, 80, 0.07, lead_kind="triangle")


_TRIADS = {48: [60, 64, 67], 43: [55, 59, 62], 45: [57, 60, 64], 41: [53, 57, 60],
           53: [65, 69, 72], 50: [62, 65, 69], 46: [58, 62, 65]}

# F major, 100 BPM, 8 bars of quarters: F Dm Bb C x2 (PixelPals's menu music).
MENU_LEAD = [
    [81, S, 77, 79], [81, S, 74, S], [74, 77, 82, S], [79, S, S, None],
    [81, 84, 81, 77], [79, 77, 74, S], [77, 74, 70, 74], [72, S, 76, S],
]
_MENU_ROOTS = [53, 50, 46, 48, 53, 50, 46, 48]
MENU_BASS = [[r, S, r + 7, S] for r in _MENU_ROOTS]
MENU_CHORDS = [_TRIADS[r if r != 48 else 48] for r in _MENU_ROOTS]
MENU_DRUMS = "k---h---k---h---"


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
    "stamp_1": lambda: stamp(1), "stamp_2": lambda: stamp(2), "stamp_3": lambda: stamp(3), "stamp_4": lambda: stamp(4),
    "splat_1": lambda: splat(1), "splat_2": lambda: splat(2), "splat_3": lambda: splat(3), "splat_4": lambda: splat(4),
    "rainbow": rainbow,
    "pot_pick_1": lambda: pot_pick(1), "pot_pick_2": lambda: pot_pick(2),
    "pot_pick_3": lambda: pot_pick(3), "pot_pick_4": lambda: pot_pick(4),
    "page_turn": page_turn, "undo": undo, "frame_it": frame_it, "clap": clap, "giggle": giggle,
    "join": join, "select": select, "ready": ready, "party": party, "whoosh": whoosh,
}
# Loops: name -> (function returning (samples, bar length), loudness target).
MUSIC = {
    "brush_loop": (brush_loop, SFX_LUFS),
    "music_menu": (music_menu, MUSIC_LUFS),
    "music_paint": (music_paint, MUSIC_LUFS - 3.0),
}


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
    rows = [(n, f, False, SFX_LUFS) for n, f in SFX.items()] + [(n, f, True, lu) for n, (f, lu) in MUSIC.items()]
    for name, fn, loop, target in rows:
        if loop:
            x, bar_len = fn()
            x = normalise(x, target, loop=True)
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
