"""Launcher sound synth: the menu sounds and a cosy menu loop, made by our own code.

Run: uv run python tools/sfx.py   (from launcher/, or `make -C launcher sfx`)

The engine is copied from games/pixelpals/tools/sfx.py (square/saw/triangle/
sine/noise oscillators, envelopes, glides, zero-phase filters, a circular
music renderer and BS.1770 loudness normalisation). Everything is seeded, so a
rerun writes byte-identical files. Output: game/audio/<name>.wav, 16-bit mono
44100 Hz. The report printed at the end is the verification: peak, LUFS,
length, and for the music loop the bar count and the loop-seam continuity.
"""

from __future__ import annotations

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
# sfx.gd plays music at -8 dB; the menu loop is quieter still: it is background.
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
# Launcher sounds
# ----------------------------------------------------------------------------


def move() -> np.ndarray:
    """Soft wooden 'tock' with a bell overtone: one card to the side."""
    n = secs(0.16)
    f = glide(n, [(0, midi(79) * 1.02), (0.16, midi(79))])
    body = 0.7 * osc("sine", f) + 0.3 * osc("triangle", f * 2)
    bell = osc("sine", np.full(n, midi(91))) * perc(n, 0.001, 0.03)
    return fft_filter(body * perc(n, 0.002, 0.045) + 0.25 * bell, low=5000, high=180)


def bonk() -> np.ndarray:
    """A friendly low 'boop-boop' (this card cannot start yet)."""
    out = np.zeros(secs(0.36))
    for start, m in [(0.0, 60), (0.15, 55)]:
        n = secs(0.18)
        f = vibrato(np.full(n, midi(m)), 9, 0.3)
        s = 0.8 * osc("sine", f) + 0.2 * osc("triangle", f)
        place(out, s * perc(n, 0.004, 0.07), secs(start), 0.9)
    return fft_filter(out, low=2500, high=80)


def launch() -> np.ndarray:
    """Launch: a rising air whoosh under a sparkly run up to a bright chord."""
    out = np.zeros(secs(1.25))
    rng = np.random.default_rng(101)
    n = secs(0.95)
    noise = osc("white", np.ones(n), rng=rng)
    cutoff = glide(n, [(0, 300), (0.7, 5200), (0.95, 2500)])
    y = onepole_sweep(onepole_sweep(noise, cutoff), cutoff)
    e = env_pts(n, [(0, 0), (0.6, 1), (0.95, 0)]) ** 1.3
    place(out, fft_filter(y * e, high=150), 0, 1.0)
    for i, m in enumerate([72, 76, 79, 84, 88, 91]):
        n = secs(0.16)
        s = (0.6 * osc("triangle", np.full(n, midi(m))) + 0.4 * osc("sine", np.full(n, midi(m + 12)))) \
            * perc(n, 0.002, 0.07)
        place(out, s, secs(0.08 + 0.075 * i), 0.3)
    n = secs(0.6)
    chord = sum(osc("sine", vibrato(np.full(n, midi(m)), 6, 0.12)) for m in [84, 88, 91, 96])
    place(out, chord * adsr(n, 0.01, 0.15, 0.4, 0.35), secs(0.6), 0.16)
    return fft_filter(out, low=8000, high=80)


def welcome() -> np.ndarray:
    """Welcome back: a warm three-note chime (G-C-E) with a soft bell tail."""
    out = np.zeros(secs(1.5))
    for i, m in enumerate([67, 72, 76, 79]):
        n = secs(1.1 - 0.12 * i)
        f = np.full(n, midi(m))
        s = 0.55 * osc("sine", f) + 0.25 * osc("sine", f * 2.0) * perc(n, 0.002, 0.25) \
            + 0.12 * osc("sine", f * 3.01) * perc(n, 0.002, 0.08)
        place(out, s * perc(n, 0.004, 0.45), secs(0.13 * i), 0.55)
    return fft_filter(out, low=6000, high=90)


def power_tick() -> np.ndarray:
    """A tiny tick each quarter of the power hold."""
    n = secs(0.05)
    s = osc("triangle", np.full(n, midi(86))) * perc(n, 0.001, 0.012)
    return fft_filter(s, low=6000, high=300)


def power_off() -> np.ndarray:
    """Power off: a gentle descending three-note goodbye with a fading hum."""
    out = np.zeros(secs(1.3))
    for i, m in enumerate([79, 74, 67]):
        n = secs(0.5)
        f = np.full(n, midi(m))
        s = 0.7 * osc("sine", f) + 0.3 * osc("triangle", f)
        place(out, s * perc(n, 0.004, 0.2), secs(0.16 * i), 0.6)
    n = secs(0.9)
    hum = osc("sine", glide(n, [(0, 220), (0.9, 110)])) * env_pts(n, [(0, 0), (0.1, 1), (0.9, 0)])
    place(out, hum, secs(0.35), 0.25)
    return fft_filter(out, low=4000, high=60)


# ----------------------------------------------------------------------------
# Menu music: a cosy lullaby loop (F major, 84 BPM: a beat is 31500 samples)
# ----------------------------------------------------------------------------

S = "-"


def render_cosy(bpm: float, bars: int, lead: list, roots: list, seed: int) -> tuple[np.ndarray, int]:
    bar_len = 4 * 60.0 / bpm * SR
    assert abs(bar_len - round(bar_len)) < 1e-6, "a bar must be a whole number of samples"
    bar_len = int(round(bar_len))
    total = bar_len * bars
    eighth = bar_len // 8
    rng = np.random.default_rng(seed)

    lead_buf = np.zeros(total)
    flat = [x for bar in lead for x in bar]
    assert len(flat) == bars * 8
    i = 0
    while i < len(flat):
        m = flat[i]
        if m is None or m == S:
            i += 1
            continue
        j = i + 1
        while j < len(flat) and flat[j] == S:
            j += 1
        n = (j - i) * eighth
        f = vibrato(np.full(n, midi(m)), 5.0, 0.12, delay=0.2)
        # A soft music-box voice: sine + a quiet octave, bell-like decay.
        s = 0.8 * osc("sine", f) + 0.2 * osc("sine", f * 2) * perc(n, 0.002, 0.2)
        place(lead_buf, s * perc(n, 0.004, 0.55), i * eighth, 0.45, circular=True)
        i = j

    pad_buf = np.zeros(total)
    bass_buf = np.zeros(total)
    triads = {53: [65, 69, 72], 50: [62, 65, 69], 46: [58, 62, 65], 48: [60, 64, 67], 45: [57, 60, 64]}
    for b, r in enumerate(roots):
        # Warm pad: detuned sines under the whole bar.
        n = bar_len + secs(0.3)
        for m in triads[r]:
            f = np.full(n, midi(m - 12))
            s = 0.5 * osc("sine", f * 1.002) + 0.5 * osc("sine", f * 0.998) + 0.15 * osc("triangle", f)
            place(pad_buf, s * adsr(n, 0.35, 0.3, 0.7, 0.4), b * bar_len, 0.12, circular=True)
        # Gentle broken-chord pluck on the eighths.
        pattern = [0, 1, 2, 1, 0, 1, 2, 1]
        for k, idx in enumerate(pattern):
            n = eighth
            m = triads[r][idx]
            s = osc("triangle", np.full(n, midi(m))) * perc(n, 0.003, 0.09)
            place(pad_buf, s, b * bar_len + k * eighth, 0.1, circular=True)
        # Bass on beats 1 and 3.
        for beat, m in [(0, r - 12), (4, r - 5)]:
            n = eighth * 4
            s = osc("sine", np.full(n, midi(m))) * adsr(n, 0.01, 0.2, 0.5, 0.2)
            place(bass_buf, s, b * bar_len + beat * eighth, 0.4, circular=True)

    shaker = np.zeros(total)
    for b in range(bars):
        for k in range(8):
            n = secs(0.05)
            h = fft_filter(osc("white", np.ones(n), rng=rng), high=6000) * perc(n, 0.004, 0.015)
            place(shaker, h, b * bar_len + k * eighth, 0.05 if k % 2 else 0.08, circular=True)

    mix = fft_filter(lead_buf, low=4000, circular=True) + fft_filter(pad_buf, low=2500, circular=True) \
        + fft_filter(bass_buf, low=800, circular=True) + shaker
    return fft_filter(mix, high=30, circular=True), bar_len


# F Dm Bb C | F Am Bb C-F, 8 bars of eighths.
MENU_ROOTS = [53, 50, 46, 48, 53, 45, 46, 48]
MENU_LEAD = [
    [81, S, S, 79, 77, S, 72, S], [74, S, 77, S, 81, S, S, None],
    [82, S, 81, 79, 77, S, 74, S], [79, S, S, S, 76, S, 72, S],
    [77, S, 81, S, 84, S, 81, S], [81, S, 79, 76, 72, S, S, None],
    [74, S, 77, 81, 82, S, 81, 79], [77, S, S, S, S, S, None, None],
]


def music_menu() -> tuple[np.ndarray, int]:
    return render_cosy(84, 8, MENU_LEAD, MENU_ROOTS, 84)


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




SFX = {"move": move, "bonk": bonk, "launch": launch, "welcome": welcome,
       "power_tick": power_tick, "power_off": power_off}
MUSIC = {"music_menu": music_menu}


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    ok = True
    total_bytes = 0
    print(f"{'file':<14}{'secs':>7}{'peak dBFS':>11}{'LUFS':>8}")
    rows = [(n, f, False) for n, f in SFX.items()] + [(n, f, True) for n, f in MUSIC.items()]
    for name, fn, loop in rows:
        if loop:
            x, bar_len = fn()
            x = normalise(x, MUSIC_LUFS, loop=True)
        else:
            x = fade_edges(normalise(fade_edges(fn()), SFX_LUFS, loop=False))
        pcm = to_pcm(x)
        path = OUT / f"{name}.wav"
        write_wav(path, pcm)
        total_bytes += path.stat().st_size
        y = pcm.astype(np.float64) / 32768.0
        loud, _ = lufs(y, loop)
        print(f"{name:<14}{len(y) / SR:>7.2f}{db(np.abs(y).max()):>11.2f}{loud:>8.1f}")
        if db(np.abs(y).max()) > PEAK_DBFS + 0.01:
            ok = False
            print(f"  FAIL: {name} peaks above {PEAK_DBFS} dBFS")
        if loop:
            bars = len(y) / bar_len
            step = np.abs(np.diff(y))
            seam = abs(y[0] - y[-1])
            good = bars == int(bars) and seam <= np.percentile(step, 99)
            ok &= good
            print(f"  loop: {bars:g} bars, seam jump {seam:.5f} -> {'OK' if good else 'FAIL'}")
    print(f"total {total_bytes / 1e6:.2f} MB in {OUT.relative_to(ROOT)}")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
