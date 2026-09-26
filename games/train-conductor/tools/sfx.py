"""Train Conductor sound synth: every sound and the three music loops, made by our own code.

The synth core (oscillators, envelopes, filters, loudness measurement, the
report and the inspection images) is copied from games/pixelpals/tools/sfx.py
and proposed for extraction into shared/tools/synth.py; the sounds are new.

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
                arp_gain: float) -> tuple[np.ndarray, int]:
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

    lead_buf = fft_filter(voice_track(lead, "square", lead_duty, lead_gain, 0.55, True), low=lead_low, circular=True)
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


_TRIADS = {48: [60, 64, 67], 43: [55, 59, 62], 45: [57, 60, 64], 41: [53, 57, 60],
           53: [65, 69, 72], 50: [62, 65, 69], 46: [58, 62, 65]}

# F major, 100 BPM, 8 bars of quarters: F Dm Bb C x2.
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
# Train Conductor sounds
# ----------------------------------------------------------------------------


def _steam_whistle(chord: list[float], dur: float, seed: int, scoop: float = 0.0, droop: float = 0.0) -> np.ndarray:
    """A steam whistle is a chord: a few sines with a breathy noise band, a scoop up at the start."""
    n = secs(dur)
    rng = np.random.default_rng(seed)
    out = np.zeros(n)
    for i, m in enumerate(chord):
        pts = [(0, midi(m - scoop)), (0.06, midi(m)), (max(dur - 0.15, 0.07), midi(m)), (dur, midi(m - droop))]
        f = vibrato(glide(n, pts), 5.5, 0.08, delay=0.1)
        out += (osc("sine", f) + 0.18 * osc("sine", f * 2)) * (1.0 - 0.15 * i)
    breath = fft_filter(osc("white", np.ones(n), rng=rng), low=3200, high=900) * 0.35
    e = adsr(n, 0.04, 0.08, 0.85, min(0.18, dur * 0.4))
    return fft_filter((out * 0.4 + breath) * e, low=6000, high=200)


def whistle_1() -> np.ndarray:
    return _steam_whistle([81, 85, 88], 0.55, 1, scoop=2.0)  # A major


def whistle_2() -> np.ndarray:
    return _steam_whistle([79, 83, 86], 0.5, 2, scoop=1.5)  # G major


def whistle_3() -> np.ndarray:
    """Toot-TOOOT: a short and a long one."""
    out = np.zeros(secs(0.95))
    place(out, _steam_whistle([77, 81, 84], 0.2, 3, scoop=1.0), 0, 0.8)
    place(out, _steam_whistle([77, 81, 84], 0.62, 4, scoop=2.0), secs(0.3))
    return out


def whistle_long() -> np.ndarray:
    return _steam_whistle([76, 80, 83, 88], 1.5, 5, scoop=2.5, droop=1.5)


def chuff_loop() -> tuple[np.ndarray, int]:
    """Four steam chuffs (chuff-a chuff-a), circular so the loop is seamless.
    The game changes its playback rate with the train's speed."""
    total = secs(0.8)
    out = np.zeros(total)
    rng = np.random.default_rng(10)
    for k, gain in enumerate([1.0, 0.55, 0.8, 0.5]):
        n = secs(0.17)
        burst = osc("white", np.ones(n), rng=rng) * perc(n, 0.004, 0.045)
        body = fft_filter(burst, low=1400, high=150, order=2)
        thump = osc("sine", glide(n, [(0, 110), (0.17, 70)])) * perc(n, 0.002, 0.03) * 0.5
        place(out, body + thump, k * (total // 4), gain, circular=True)
    out = fft_filter(out, high=40, circular=True)
    return out, total // 4


def brake_squeal() -> np.ndarray:
    n = secs(0.8)
    f = vibrato(glide(n, [(0, 2600), (0.8, 2350)]), 11, 0.25)
    e = adsr(n, 0.03, 0.1, 0.7, 0.3)
    squeal = osc("sine", f) + 0.3 * osc("sine", f * 1.5)
    hiss = fft_filter(osc("white", np.ones(n), rng=np.random.default_rng(11)), low=7000, high=2500) * 0.4
    return fft_filter((squeal * 0.4 + hiss) * e, low=7000, high=400)


def beep_beep() -> np.ndarray:
    """Friendly 'beep beep' before the roll-back."""
    out = np.zeros(secs(0.5))
    for start in (0.0, 0.2):
        n = secs(0.13)
        f = np.full(n, midi(76))
        s = 0.6 * osc("square", f, duty=0.35) + 0.4 * osc("triangle", f * 1.5)
        place(out, s * adsr(n, 0.005, 0.03, 0.7, 0.04), secs(start))
    return fft_filter(out, low=4000, high=200)


def horn() -> np.ndarray:
    """The driver's toy horn: a warm two-note reed chord."""
    n = secs(0.55)
    out = np.zeros(n)
    for m, g in ((57, 1.0), (61, 0.8), (64, 0.6)):
        f = vibrato(glide(n, [(0, midi(m - 0.6)), (0.05, midi(m)), (0.55, midi(m))]), 6, 0.1, delay=0.1)
        out += (0.6 * osc("saw", f) + 0.4 * osc("square", f, duty=0.4)) * g
    return fft_filter(out * adsr(n, 0.02, 0.08, 0.8, 0.12), low=1800, high=90)


def points_clack() -> np.ndarray:
    """Wooden clack-clock of the points swinging over."""
    out = np.zeros(secs(0.25))
    rng = np.random.default_rng(12)
    for start, pitch, g in ((0.0, 900, 1.0), (0.09, 650, 0.8)):
        n = secs(0.08)
        knock = osc("sine", glide(n, [(0, pitch * 1.3), (0.08, pitch)])) * perc(n, 0.001, 0.018)
        click = fft_filter(osc("white", np.ones(n), rng=rng), low=4000, high=1200) * perc(n, 0.0005, 0.006)
        place(out, knock + click * 0.8, secs(start), g)
    return fft_filter(out, high=150)


def doors_open() -> np.ndarray:
    """Air 'pssh' and a sliding door."""
    n = secs(0.6)
    rng = np.random.default_rng(13)
    hiss = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 5000), (0.6, 1500)])
    y = onepole_sweep(hiss, cutoff) * env_pts(n, [(0, 0), (0.03, 1), (0.6, 0)])
    slide = osc("triangle", glide(n, [(0, 300), (0.6, 520)])) * env_pts(n, [(0, 0), (0.1, 0.3), (0.5, 0.3), (0.6, 0)])
    return fft_filter(y * 0.7 + slide * 0.5, high=150)


def _bell_strike(f0: float, dur: float) -> np.ndarray:
    n = secs(dur)
    out = np.zeros(n)
    for ratio, g, dec in ((1.0, 1.0, 0.5), (2.76, 0.5, 0.25), (5.4, 0.25, 0.12), (8.9, 0.1, 0.06)):
        out += osc("sine", np.full(n, f0 * ratio)) * perc(n, 0.001, dec) * g
    return out


def bell() -> np.ndarray:
    """Ding-ding."""
    out = np.zeros(secs(1.0))
    place(out, _bell_strike(1320, 0.7), 0)
    place(out, _bell_strike(1320, 0.7), secs(0.22), 0.9)
    return fft_filter(out, low=9000, high=200)


def _hop(lo: float, hi: float) -> np.ndarray:
    n = secs(0.14)
    f = glide(n, [(0, lo), (0.1, hi), (0.14, hi * 1.05)])
    s = 0.7 * osc("sine", f) + 0.3 * osc("triangle", f)
    return fft_filter(s * adsr(n, 0.004, 0.03, 0.7, 0.05), low=5000, high=150)


def hop_1() -> np.ndarray:
    return _hop(420, 820)


def hop_2() -> np.ndarray:
    return _hop(500, 980)


def hop_3() -> np.ndarray:
    return _hop(380, 700)


def _deliver(root: int) -> np.ndarray:
    """Happy arpeggio in the station's own key."""
    return arp_notes([(root, 0.09), (root + 4, 0.09), (root + 7, 0.09), (root + 12, 0.28)], kind="triangle",
                     duty=0.5, tail=0.3, low=6000) + 0.35 * arp_notes(
        [(root + 12, 0.09), (root + 16, 0.09), (root + 19, 0.09), (root + 24, 0.28)], kind="square", duty=0.25,
        tail=0.3, low=5000)


def deliver_red() -> np.ndarray:
    return _deliver(72)  # C


def deliver_blue() -> np.ndarray:
    return _deliver(76)  # E


def deliver_yellow() -> np.ndarray:
    return _deliver(79)  # G


def deliver_green() -> np.ndarray:
    return _deliver(81)  # A


def moo() -> np.ndarray:
    """A cute cow: a buzzy low glide through a soft 'oo' formant."""
    n = secs(0.95)
    f = vibrato(glide(n, [(0, 150), (0.2, 175), (0.7, 150), (0.95, 120)]), 5, 0.3, delay=0.2)
    voice = 0.7 * osc("saw", f) + 0.3 * osc("square", f, duty=0.3)
    e = adsr(n, 0.08, 0.15, 0.8, 0.25)
    oo = fft_filter(voice * e, low=700, order=3)
    return fft_filter(oo + 0.15 * fft_filter(voice * e, low=2500, high=1800), high=70)


def quack() -> np.ndarray:
    out = np.zeros(secs(0.45))
    for start, base in ((0.0, 1.0), (0.22, 0.92)):
        n = secs(0.16)
        f = glide(n, [(0, 520 * base), (0.05, 600 * base), (0.16, 380 * base)])
        s = osc("square", f, duty=0.2) * adsr(n, 0.005, 0.03, 0.8, 0.05)
        place(out, fft_filter(s, low=2600, high=500, order=3), secs(start))
    return out


def baa() -> np.ndarray:
    n = secs(0.8)
    f = vibrato(glide(n, [(0, 330), (0.08, 370), (0.8, 330)]), 7, 0.6, delay=0.05)
    t = np.arange(n) / SR
    bleat = 1.0 - 0.45 * (0.5 + 0.5 * np.sin(2 * np.pi * 13 * t))
    voice = 0.6 * osc("saw", f) + 0.4 * osc("triangle", f * 2)
    e = adsr(n, 0.04, 0.1, 0.85, 0.2)
    return fft_filter(voice * bleat * e, low=2200, high=180, order=3)


def couple() -> np.ndarray:
    """Carriage coupling: a wooden clunk and a little rattle."""
    out = np.zeros(secs(0.4))
    n = secs(0.2)
    thump = osc("sine", glide(n, [(0, 160), (0.2, 70)])) * perc(n, 0.001, 0.06)
    place(out, thump, 0)
    rng = np.random.default_rng(14)
    for k in range(3):
        m = secs(0.05)
        c = fft_filter(osc("white", np.ones(m), rng=rng), low=3000, high=800) * perc(m, 0.0005, 0.01)
        place(out, c, secs(0.02 + k * 0.07), 0.6 - k * 0.15)
    return fft_filter(out, high=50)


def perfect_stop() -> np.ndarray:
    """Sparkle: a quick run up and a shimmer."""
    out = np.zeros(secs(0.9))
    for i, m in enumerate([84, 88, 91, 96, 100]):
        n = secs(0.25)
        s = osc("sine", vibrato(np.full(n, midi(m)), 12, 0.15)) * perc(n, 0.002, 0.08)
        place(out, s, secs(0.05 * i), 0.5)
    rng = np.random.default_rng(15)
    for _ in range(8):
        m = rng.choice([96, 100, 103, 108])
        n = secs(0.08)
        place(out, osc("sine", np.full(n, midi(m))) * perc(n, 0.002, 0.025), secs(rng.uniform(0.2, 0.75)), 0.3)
    return fft_filter(out, low=9000, high=200)


def wheee() -> np.ndarray:
    n = secs(0.6)
    f = vibrato(glide(n, [(0, 500), (0.45, 1500), (0.6, 1400)]), 7, 0.4, delay=0.2)
    s = 0.85 * osc("sine", f) + 0.15 * osc("triangle", f)
    return fft_filter(s * adsr(n, 0.03, 0.1, 0.8, 0.12), low=5000)


def firework() -> np.ndarray:
    """A soft pop and a sparkly crackle."""
    out = np.zeros(secs(1.0))
    rng = np.random.default_rng(16)
    n = secs(0.12)
    place(out, osc("sine", glide(n, [(0, 220), (0.12, 60)])) * perc(n, 0.001, 0.04), 0)
    place(out, fft_filter(osc("white", np.ones(n), rng=rng), low=3000) * perc(n, 0.001, 0.02), 0, 0.6)
    for _ in range(24):
        m = secs(0.02)
        c = fft_filter(osc("white", np.ones(m), rng=rng), high=3000) * perc(m, 0.0005, 0.004)
        place(out, c, secs(rng.uniform(0.1, 0.9)), rng.uniform(0.15, 0.4))
    return fft_filter(out, low=9000, high=50)


# ----------------------------------------------------------------------------
# Music loops (float step grid, rendered circularly: seamless loops)
# ----------------------------------------------------------------------------


def _pluck(f: float, n: int) -> np.ndarray:
    """Ukulele-ish pluck: a bright attack that mellows as it decays."""
    fr = np.full(n, f)
    bright = fft_filter(0.6 * osc("saw", fr) + 0.4 * osc("triangle", fr), low=3000)
    mellow = osc("triangle", fr)
    t = np.arange(n) / SR
    mix = bright * np.exp(-t / 0.05) + mellow * 0.7
    return mix * perc(n, 0.002, 0.22)


def _loop_grid(bpm: float, bars: int) -> tuple[int, float, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    return bar_len, bar_len / 16.0, bar_len * bars


# C major chugga at 160 BPM, 8 bars: C F G C / Am F G C.
RAILS_CHORDS = [[60, 64, 67], [60, 65, 69], [59, 62, 67], [60, 64, 67],
                [57, 60, 64], [57, 60, 65], [59, 62, 67], [60, 64, 67]]
RAILS_BASS = [48, 41, 43, 48, 45, 41, 43, 48]
# One note per 8th (None = rest, S = hold).
RAILS_LEAD = [
    [76, S, 79, S, 76, 74, 72, S], [77, S, 81, S, 79, 77, 76, S],
    [74, S, 79, S, 77, 76, 74, S], [72, S, 76, 79, 84, S, None, None],
    [76, S, 72, S, 76, 77, 79, S], [77, S, 76, 74, 72, S, 69, S],
    [71, 72, 74, S, 79, S, 77, 74], [72, S, S, S, None, None, None, None],
]


def music_rails() -> tuple[np.ndarray, int]:
    bar_len, six, total = _loop_grid(160, 8)
    rng = np.random.default_rng(160)
    out = np.zeros(total)
    # Chugga: noise on every 16th, accents on the 8ths (chug-a chug-a).
    for k in range(8 * 16):
        n = secs(0.07)
        g = [0.5, 0.18, 0.32, 0.18][k % 4]
        s = fft_filter(osc("white", np.ones(n), rng=rng), low=2500, high=500) * perc(n, 0.002, 0.02)
        place(out, s, int(round(k * six)), g, circular=True)
    # Soft kick on 1 and 3.
    kick_n = secs(0.15)
    kick = osc("sine", glide(kick_n, [(0, 130), (0.1, 55), (0.15, 50)])) * perc(kick_n, 0.002, 0.05)
    for b in range(8):
        for q in (0, 8):
            place(out, kick, b * bar_len + int(round(q * six)), 0.7, circular=True)
    # Ukulele strum pattern d - d u - u d u over 8ths.
    strum = [1, 0, 1, 1, 0, 1, 1, 1]
    for b, chord in enumerate(RAILS_CHORDS):
        for e8, on in enumerate(strum):
            if not on:
                continue
            start = b * bar_len + int(round(e8 * 2 * six))
            notes = chord if e8 % 2 == 0 else list(reversed(chord))
            for i, m in enumerate(notes):
                n = secs(0.3)
                place(out, _pluck(midi(m), n), start + secs(0.012 * i), 0.16, circular=True)
        n = int(bar_len / 2) - secs(0.02)
        for half in (0, 1):
            f = np.full(n, midi(RAILS_BASS[b] + (7 if half else 0)))
            place(out, osc("triangle", f) * adsr(n, 0.005, 0.1, 0.6, 0.05), b * bar_len + half * bar_len // 2, 0.45,
                  circular=True)
    # Lead: plucky square.
    flat = [x for bar in RAILS_LEAD for x in bar]
    i = 0
    while i < len(flat):
        m = flat[i]
        if m is None or m == S:
            i += 1
            continue
        j = i + 1
        while j < len(flat) and flat[j] == S:
            j += 1
        n = int(round((j - i) * 2 * six)) - secs(0.02)
        f = np.full(n, midi(m))
        s = (0.7 * osc("square", f, duty=0.25) + 0.3 * osc("triangle", f * 2)) * adsr(n, 0.004, 0.06, 0.5, 0.05)
        place(out, fft_filter(s, low=4000), int(round(i * 2 * six)), 0.32, circular=True)
        i = j
    return fft_filter(out, high=30, circular=True), bar_len


# Night: 90 BPM, 8 bars, a music box over a soft pad: Cmaj7 Am7 Fmaj7 G.
NIGHT_CHORDS = [[60, 64, 67, 71], [57, 60, 64, 67], [53, 57, 60, 64], [55, 59, 62, 65]] * 2
NIGHT_MELODY = [
    [84, None, 79, None, 83, None, 79, None], [81, None, 76, None, 79, None, None, None],
    [77, None, 81, None, 84, None, 81, None], [79, None, 74, None, 77, None, None, None],
    [84, None, 88, None, 86, None, 84, None], [81, None, 84, None, 88, None, None, None],
    [89, None, 88, None, 84, None, 81, None], [79, None, 83, None, 86, None, None, None],
]


def music_night() -> tuple[np.ndarray, int]:
    bar_len, six, total = _loop_grid(90, 8)
    out = np.zeros(total)
    t_all = np.arange(bar_len) / SR
    for b, chord in enumerate(NIGHT_CHORDS):
        pad = np.zeros(bar_len)
        for m in chord:
            f = vibrato(np.full(bar_len, midi(m)), 4.5, 0.08)
            pad += osc("sine", f) + 0.2 * osc("triangle", f)
        swell = np.sin(np.pi * t_all / (bar_len / SR)) ** 1.5
        place(out, fft_filter(pad * swell, low=2000), b * bar_len, 0.12, circular=True)
        n = bar_len // 2
        place(out, osc("sine", np.full(n, midi(chord[0] - 12))) * adsr(n, 0.05, 0.3, 0.5, 0.2), b * bar_len, 0.35,
              circular=True)
    for b, bar in enumerate(NIGHT_MELODY):
        for k, m in enumerate(bar):
            if m is None:
                continue
            place(out, _bell_strike(midi(m), 1.0), b * bar_len + int(round(k * 2 * six)), 0.22, circular=True)
    rng = np.random.default_rng(90)
    for k in range(8 * 8):
        n = secs(0.05)
        s = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.004, 0.015)
        place(out, s, int(round(k * 2 * six)), 0.05 if k % 2 else 0.09, circular=True)
    return fft_filter(out, high=30, low=9000, circular=True), bar_len


SFX = {
    "whistle_1": whistle_1, "whistle_2": whistle_2, "whistle_3": whistle_3, "whistle_long": whistle_long,
    "brake_squeal": brake_squeal, "beep_beep": beep_beep, "horn": horn, "points_clack": points_clack,
    "doors_open": doors_open, "bell": bell, "hop_1": hop_1, "hop_2": hop_2, "hop_3": hop_3,
    "deliver_red": deliver_red, "deliver_blue": deliver_blue, "deliver_yellow": deliver_yellow,
    "deliver_green": deliver_green, "moo": moo, "quack": quack, "baa": baa, "couple": couple,
    "perfect_stop": perfect_stop, "wheee": wheee, "firework": firework,
    "join": join, "select": select, "ready": ready, "party": party, "whoosh": whoosh,
}
MUSIC = {"chuff_loop": chuff_loop, "music_rails": music_rails, "music_night": music_night, "music_menu": music_menu}
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
    if total_bytes > 8e6:
        ok = False
        print("FAIL: audio total above 8 MB")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
