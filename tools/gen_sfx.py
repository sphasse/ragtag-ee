#!/usr/bin/env python3
"""Generate the ragtag sound cues into ee/ragtag/sfx/ (stdlib only, deterministic).

    python tools/gen_sfx.py            # write all cues
    python tools/gen_sfx.py --check    # report length/peak/RMS only, write nothing

Cues are mono 44.1 kHz 16-bit WAV (EmptyEpsilon plays WAV; there is no OGG
encoder on the dev machine). Mono so any cue can also be used positionally.
Edit the recipes below, rerun, then update RT.SOUNDS `seconds` in
ee/ragtag/core.lua if a length changed (the script prints the numbers).
"""
import argparse
import math
import random
import struct
import sys
import wave
from pathlib import Path

SR = 44100
OUT = Path(__file__).resolve().parent.parent / "ee" / "ragtag" / "sfx"
TAU = 2 * math.pi

# Warp jammer cues play at half their original amplitude (peaks 0.85 / 0.55 / 0.8 before).
JAMMER_GAIN = 0.5


def n(sec):
    return int(sec * SR)


def silence(sec):
    return [0.0] * n(sec)


def env_ar(i, total, attack, release):
    """Attack/release envelope for sample i of total."""
    t = i / SR
    dur = total / SR
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = min(1.0, (dur - t) / release) if release > 0 else 1.0
    return max(0.0, min(a, r))


def tone(freq, sec, vol=1.0, attack=0.01, release=0.05, harmonics=((1, 1.0),)):
    total = n(sec)
    out = []
    for i in range(total):
        t = i / SR
        s = sum(w * math.sin(TAU * freq * h * t) for h, w in harmonics)
        out.append(s * vol * env_ar(i, total, attack, release))
    return out


def sweep(f0, f1, sec, vol=1.0, attack=0.01, release=0.05, curve=1.0, harmonics=((1, 1.0),)):
    """Frequency sweep f0->f1 (curve>1 bends late). Phase-accumulated, no clicks."""
    total = n(sec)
    out, phase = [], 0.0
    for i in range(total):
        x = (i / total) ** curve
        f = f0 + (f1 - f0) * x
        phase += TAU * f / SR
        s = sum(w * math.sin(phase * h) for h, w in harmonics)
        out.append(s * vol * env_ar(i, total, attack, release))
    return out


def noise(sec, rng, vol=1.0, attack=0.005, release=0.05, lowpass=None):
    total = n(sec)
    out, y = [], 0.0
    a = 1.0 if lowpass is None else 1 - math.exp(-TAU * lowpass / SR)
    for i in range(total):
        y += a * ((rng.random() * 2 - 1) - y)
        out.append(y * vol * env_ar(i, total, attack, release))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    length = max(len(t) + n(o) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for t, o in zip(tracks, offsets):
        base = n(o)
        for i, v in enumerate(t):
            out[base + i] += v
    return out


def cat(*tracks):
    out = []
    for t in tracks:
        out.extend(t)
    return out


def softclip(x):
    return math.tanh(x)


def finish(samples, peak=0.8, fade=0.01):
    """Soft-limit, normalise to `peak`, short edge fades so there are no clicks."""
    samples = [softclip(s) for s in samples]
    m = max(abs(s) for s in samples) or 1.0
    g = peak / m
    f = n(fade)
    out = []
    for i, s in enumerate(samples):
        e = min(1.0, i / f if f else 1.0, (len(samples) - 1 - i) / f if f else 1.0)
        out.append(s * g * e)
    return out


# -- Recipes -----------------------------------------------------------------

def concord_hail():
    """Comms chirp (two rising notes) over a low drone: 'a patrol has you'."""
    rng = random.Random(1)
    drone = tone(55, 3.4, vol=0.45, attack=0.4, release=1.2,
                 harmonics=((1, 1.0), (2, 0.4), (3, 0.15)))
    c1 = sweep(880, 1320, 0.16, vol=0.8, attack=0.01, release=0.05)
    c2 = sweep(1100, 1760, 0.20, vol=0.8, attack=0.01, release=0.12)
    hiss = noise(0.4, rng, vol=0.08, attack=0.05, release=0.3, lowpass=6000)
    return finish(mix(drone, c1, c2, hiss, offsets=[0, 0.15, 0.42, 0.1]))


def concord_warning():
    """Two sharp alert pulses (10 s left on the compliance clock)."""
    h = ((1, 1.0), (2, 0.3))
    p = tone(1000, 0.2, attack=0.004, release=0.04, harmonics=h)
    return finish(cat(p, silence(0.1), p), peak=0.85)


def concord_hostile():
    """Descending two-tone klaxon, repeated: 'warrant issued'."""
    h = ((1, 1.0), (2, 0.5), (3, 0.3))  # buzzy
    hi = tone(720, 0.35, attack=0.01, release=0.04, harmonics=h)
    lo = tone(480, 0.45, attack=0.01, release=0.15, harmonics=h)
    one = cat(hi, lo, silence(0.08))
    return finish(cat(one, one), peak=0.85)


def jammer_engage():
    """Rising power-surge sweep into a crackling thud: the field slams on."""
    rng = random.Random(2)
    rise = sweep(120, 1400, 1.6, vol=0.7, attack=0.05, release=0.0, curve=2.2,
                 harmonics=((1, 1.0), (2, 0.5)))
    thud = tone(48, 1.6, vol=1.0, attack=0.005, release=1.4)
    crackle = []
    for k in range(14):  # random short noise bursts through the tail
        crackle.append((0.25 + k * 0.08 + rng.random() * 0.05,
                        noise(0.03 + rng.random() * 0.04, rng, vol=0.5 + rng.random() * 0.4,
                              attack=0.002, release=0.02, lowpass=5000)))
    parts = [rise, thud] + [c for _, c in crackle]
    offsets = [0.0, 1.5] + [1.5 + o for o, _ in crackle]
    return finish(mix(*parts, offsets=offsets), peak=0.85 * JAMMER_GAIN)


def jammer_bed():
    """Interference hum: detuned low sines, band-limited hiss, slow wobble.
    Re-fired every 10 s by RT.soundLoop, so it fades in and out."""
    rng = random.Random(3)
    sec = 8.0
    total = n(sec)
    hiss = noise(sec, rng, vol=0.25, attack=0.8, release=0.8, lowpass=2500)
    out = []
    for i in range(total):
        t = i / SR
        wob = 0.6 + 0.4 * math.sin(TAU * 0.35 * t)
        hum = (math.sin(TAU * 62 * t) + 0.8 * math.sin(TAU * 62.7 * t)
               + 0.4 * math.sin(TAU * 124 * t + 1.0)) * 0.35 * wob
        whine = 0.08 * math.sin(TAU * (2200 + 160 * math.sin(TAU * 0.6 * t)) * t)
        out.append((hum + whine) * env_ar(i, total, 0.8, 0.8) + hiss[i])
    return finish(out, peak=0.55 * JAMMER_GAIN, fade=0.2)  # a bed sits under the dialogue


def jammer_release():
    """Falling tone and a soft click: the field lets go."""
    rng = random.Random(4)
    fall = sweep(900, 180, 1.5, vol=0.7, attack=0.01, release=0.6, curve=0.6,
                 harmonics=((1, 1.0), (2, 0.25)))
    click = noise(0.05, rng, vol=0.5, attack=0.001, release=0.03, lowpass=3500)
    return finish(mix(fall, click), peak=0.8 * JAMMER_GAIN)


CUES = {
    "concord_hail": concord_hail,
    "concord_warning": concord_warning,
    "concord_hostile": concord_hostile,
    "jammer_engage": jammer_engage,
    "jammer_bed": jammer_bed,
    "jammer_release": jammer_release,
}


def write_wav(path, samples):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1.0, min(1.0, s)) * 32767)) for s in samples))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="print stats, write nothing")
    args = ap.parse_args()
    if not args.check:
        OUT.mkdir(parents=True, exist_ok=True)
    print(f"{'cue':<18}{'seconds':>8}{'peak':>8}{'rms':>8}")
    for name, fn in CUES.items():
        s = fn()
        peak = max(abs(x) for x in s)
        rms = math.sqrt(sum(x * x for x in s) / len(s))
        print(f"{name:<18}{len(s) / SR:>8.2f}{peak:>8.2f}{rms:>8.3f}")
        if not args.check:
            write_wav(OUT / f"{name}.wav", s)
    return 0


if __name__ == "__main__":
    sys.exit(main())
