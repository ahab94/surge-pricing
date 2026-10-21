#!/usr/bin/env python3
"""Music bed and comedy stingers for the videos. Original: synthesized from
scratch with tools/synth.py (Python standard library only), nothing to license.

    python3 tools/video/make_video_audio.py   ->  build/video_audio/*.wav
"""
import math
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))
import synth as A  # noqa: E402

OUT = os.path.join(A.HERE, "..", "build", "video_audio")
tone, noise, layer, at, hz, Track = A.tone, A.noise, A.layer, A.at, A.hz, A.Track


def vibrato(freq, dur, vol, depth, rate, shape="sine", glide_to=None, decay=None, lowpass=None):
    """A note with wobble: the basis of slide whistles, trombones and horns."""
    n = int(dur * A.SR)
    out = [0.0] * n
    p = 0.0
    y = 0.0
    k = 1 - math.exp(-A.TAU * lowpass / A.SR) if lowpass else None
    for i in range(n):
        t = i / A.SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        f *= 1 + depth * math.sin(A.TAU * rate * t)
        p = (p + f / A.SR) % 1.0
        s = A._wave(shape, p)
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / 0.02) * (math.exp(-t / decay) if decay else 1.0)
        env *= min(1.0, (dur - t) / 0.04)
        out[i] = s * env * vol
    return out


# --- drums -----------------------------------------------------------------

def kick(vol=0.55):
    return layer(tone(150, 0.25, "sine", vol, decay=0.07, glide_to=45),
                 noise(0.01, vol * 0.3, decay=0.003, highpass=2000, seed=40))


def clap(vol=0.3, seed=41):
    # A clap is a few noise bursts a hair apart.
    return layer(*[at(k * 0.011, noise(0.16, vol, decay=0.045, lowpass=5000, highpass=1000, seed=seed + k))
                   for k in range(3)])


def hat(vol=0.08, seed=42, open_=False):
    return noise(0.2 if open_ else 0.05, vol, decay=0.08 if open_ else 0.015, highpass=7000, seed=seed)


# --- music ----------------------------------------------------------------

def gig_groove():
    """The theme: a bouncy, funky groove in F major, 108 BPM. Popping octave
    bass, clap backbeat, syncopated electric-piano stabs, and a cheeky lead
    that sounds like a phone notification grew up. 8 bars, loops."""
    bpm = 108
    beat = 60 / bpm
    bar = 4 * beat
    chords = ["F", "F", "Dm", "Dm", "Bb", "C", "F", "C"]
    roots = {"F": "F2", "Dm": "D2", "Bb": "Bb1", "C": "C2"}
    tri = {"F": ["A4", "C5", "F5"], "Dm": ["A4", "D5", "F5"], "Bb": ["Bb4", "D5", "F5"], "C": ["G4", "C5", "E5"]}
    # Bass pattern in eighths: root, rest, octave pop, root... (1 = root, 2 = octave, 0 = rest)
    pattern = [1, 0, 2, 1, 0, 1, 2, 0]
    lead = {1: [(0, "C6", 0.5), (0.5, "A5", 0.5), (1.5, "C6", 0.5), (2.5, "F6", 1.0)],
            3: [(0, "D6", 0.5), (0.5, "C6", 0.5), (1, "A5", 1.0), (2.5, "F5", 0.5)],
            5: [(0, "E6", 0.5), (0.5, "D6", 0.5), (1, "C6", 0.5), (1.5, "G5", 1.0)],
            7: [(0, "C6", 0.25), (0.25, "C6", 0.25), (0.5, "D6", 0.5), (1, "E6", 0.5), (1.5, "G6", 1.5)]}
    mix = Track(len(chords) * bar, loop=True)
    for b, ch in enumerate(chords):
        t0 = b * bar
        r = hz(roots[ch])
        for k, step in enumerate(pattern):
            if step:
                f = r * (2 if step == 2 else 1)
                mix.add(t0 + k * beat / 2, tone(f, beat * 0.4, "saw", 0.24, attack=0.002, decay=0.09, lowpass=650))
        for k in (0, 2.5):
            mix.add(t0 + k * beat, kick())
        for k in (1, 3):
            mix.add(t0 + k * beat, clap(0.3, seed=60 + b))
        for k in range(8):
            mix.add(t0 + k * beat / 2, hat(0.09 if k % 2 else 0.05, seed=70 + k, open_=(k == 7)))
        # Electric-piano stabs on the off-beats (the funk lives there).
        for k in (0.5, 1.75, 3.5):
            for n in tri[ch]:
                mix.add(t0 + k * beat, tone(hz(n), beat * 0.3, "tri", 0.06, decay=0.12, tremolo=0.2, tremolo_hz=6))
        if b in lead:
            for off, note, beats in lead[b]:
                mix.add(t0 + off * beat, tone(hz(note), beats * beat * 0.9, "square", 0.05, attack=0.005,
                                              decay=beats * beat * 0.6, lowpass=3500))
    return mix.buf


# --- stingers -------------------------------------------------------------

def sfx():
    s = {}
    # Ka-ching: a till bell plus the drawer rattle. For every tip.
    s["kaching"] = layer(noise(0.12, 0.25, decay=0.03, highpass=3000, seed=11),
                         at(0.06, tone(hz("E6"), 0.8, "sine", 0.4, decay=0.25)),
                         at(0.06, tone(hz("E6") * 2.4, 0.5, "sine", 0.15, decay=0.12)),
                         at(0.14, tone(hz("B6"), 0.7, "sine", 0.3, decay=0.2)))
    # A two-tone car horn: HONK.
    s["honk"] = layer(vibrato(hz("F4"), 0.4, 0.3, 0.004, 30, shape="square", lowpass=1600),
                      vibrato(hz("A4"), 0.4, 0.25, 0.004, 30, shape="square", lowpass=1600))
    # Splash: a big noise burst falling in pitch, plus bloops.
    s["splash"] = layer(noise(0.7, 0.6, decay=0.22, lowpass=3000, sweep_to=400, seed=12),
                        at(0.15, tone(500, 0.12, "sine", 0.3, glide_to=1200, decay=0.04)),
                        at(0.3, tone(400, 0.12, "sine", 0.25, glide_to=1000, decay=0.04)))
    # A two-tone emergency siren: wee-woo, wee-woo.
    parts = []
    for k in range(4):
        parts.append(at(k * 0.42, tone(hz("B5") if k % 2 == 0 else hz("E5"), 0.42, "tri", 0.3, attack=0.02,
                                       release=0.05, lowpass=2500)))
    s["siren"] = layer(*parts)
    s["slide_up"] = vibrato(500, 0.55, 0.5, 0.012, 7, glide_to=1900)
    s["boing"] = vibrato(180, 0.6, 0.6, 0.35, 11, shape="tri", glide_to=320, decay=0.25)
    notes = [("D4", 0.32), ("C#4", 0.32), ("C4", 0.32), ("B3", 1.1)]
    t = 0.0
    parts = []
    for i, (n, d) in enumerate(notes):
        last = i == len(notes) - 1
        parts.append(at(t, vibrato(hz(n), d, 0.35, 0.03 if last else 0.012, 5.5, shape="saw",
                                   glide_to=hz(n) * (0.97 if last else 0.995), lowpass=1500)))
        t += d * 0.95
    s["sad_trombone"] = layer(*parts)
    s["record_scratch"] = layer(
        noise(0.12, 0.6, decay=0.08, lowpass=900, sweep_to=4500, seed=21),
        at(0.1, noise(0.16, 0.6, decay=0.1, lowpass=4500, sweep_to=600, seed=22)),
        tone(300, 0.26, "saw", 0.12, glide_to=900, lowpass=2500, decay=0.12))
    s["bonk"] = layer(tone(620, 0.25, "sine", 0.6, decay=0.05, glide_to=380),
                      tone(1240, 0.1, "sine", 0.2, decay=0.02))
    s["pop"] = layer(tone(900, 0.08, "sine", 0.6, decay=0.015, glide_to=1800),
                     noise(0.03, 0.2, decay=0.006, highpass=2000, seed=23))
    s["whoosh"] = noise(0.45, 0.5, decay=None, lowpass=300, sweep_to=5000, highpass=150, seed=24, attack=0.2)
    # The app's notification: two bright blips (new review / ride request).
    s["notify"] = layer(tone(hz("A5"), 0.12, "sine", 0.4, decay=0.05),
                        at(0.1, tone(hz("E6"), 0.25, "sine", 0.4, decay=0.1)))
    return s


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, samples in sfx().items():
        A.write_wav(os.path.join(OUT, name + ".wav"), samples)
    A.write_wav(os.path.join(OUT, "gig_groove.wav"), gig_groove())


if __name__ == "__main__":
    main()
