#!/usr/bin/env python3
"""Every sound in the game, synthesized from scratch (Python stdlib only):
original music, so nothing to license.

    python3 tools/make_audio.py      ->  audio/music/*.wav  audio/sfx/*.wav  audio/loops/*.wav

Music: a theme per city, each in a style that city is known for. They are
written as patterns (chords, bass, drums, a melody) over 8 bars, and they loop
seamlessly:
- Paris: a musette waltz.
- New York: swing.
- Rio: bossa.
- Rome: a tarantella.
- Dubai: Arabic pop on a hijaz scale.
- London: ska.
- Tokyo: city pop.
- Istanbul: a 9/8 karsilama.
- Bangkok: a pentatonic mallet groove.
- Singapore: night synthwave.

Effects follow the house rule from the earlier games: anything that repeats a
lot (engine, tyres, passenger chatter) is kept quiet and dark.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(__file__))
import synth as A  # noqa: E402

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
SR = A.SR
tone, noise, layer, at, hz, Track = A.tone, A.noise, A.layer, A.at, A.hz, A.Track


def out(folder, name, samples, peak=0.89):
    A.write_wav(os.path.join(ROOT, "audio", folder, name + ".wav"), samples, peak)


# ---------------------------------------------------------------- instruments

def kick(vol=0.55):
    return layer(tone(150, 0.25, "sine", vol, decay=0.07, glide_to=45),
                 noise(0.01, vol * 0.3, decay=0.003, highpass=2000, seed=40))


def snare(vol=0.3, seed=41):
    return layer(noise(0.2, vol, decay=0.06, lowpass=6000, highpass=900, seed=seed), tone(190, 0.1, "tri", vol * 0.5, decay=0.04))


def clap(vol=0.28, seed=61):
    return layer(*[at(k * 0.011, noise(0.15, vol, decay=0.045, lowpass=5000, highpass=1000, seed=seed + k)) for k in range(3)])


def hat(vol=0.07, seed=42, open_=False):
    return noise(0.2 if open_ else 0.05, vol, decay=0.08 if open_ else 0.015, highpass=7000, seed=seed)


def shaker(vol=0.05, seed=43):
    return noise(0.07, vol, decay=0.02, highpass=5000, lowpass=11000, seed=seed, attack=0.01)


def rim(vol=0.18):
    return layer(tone(1700, 0.04, "sine", vol, decay=0.008), noise(0.02, vol * 0.5, decay=0.004, highpass=3000, seed=44))


def jingle(vol=0.08, seed=45):   # tambourine
    return layer(*[at(k * 0.018, noise(0.1, vol, decay=0.03, highpass=6000, seed=seed + k)) for k in range(3)])


def dum(vol=0.45):               # darbuka, low
    return layer(tone(110, 0.3, "sine", vol, decay=0.09, glide_to=80), noise(0.02, vol * 0.2, decay=0.006, lowpass=900, seed=46))


def tek(vol=0.2, seed=47):       # darbuka, rim
    return layer(tone(900, 0.06, "sine", vol, decay=0.015), noise(0.04, vol * 0.7, decay=0.01, highpass=2500, seed=seed))


def ride(vol=0.05, seed=48):
    return layer(noise(0.3, vol, decay=0.12, highpass=6000, seed=seed), tone(5200, 0.3, "sine", vol * 0.3, decay=0.1))


def bass(note, dur, vol=0.22, shape="saw", lp=550):
    return tone(hz(note), dur, shape, vol, attack=0.004, decay=dur * 0.7, lowpass=lp)


def pluck(note, dur, vol=0.12, lp=2800, shape="saw"):
    return tone(hz(note), dur, shape, vol, attack=0.002, decay=0.18, lowpass=lp)


def accordion(note, dur, vol=0.06):
    return tone(hz(note), dur, "square", vol, attack=0.03, lowpass=2600, detune=0.006, tremolo=0.25, tremolo_hz=6.5)


def organ(note, dur, vol=0.05):
    f = hz(note)
    return layer(tone(f, dur, "sine", vol, attack=0.005, release=0.02), tone(f * 2, dur, "sine", vol * 0.5, attack=0.005),
                 tone(f * 3, dur, "sine", vol * 0.25, attack=0.005))


def brass(note, dur, vol=0.08):
    return tone(hz(note), dur, "saw", vol, attack=0.03, lowpass=2000, detune=0.003)


def mallet(note, dur, vol=0.14):
    f = hz(note)
    return layer(tone(f, dur, "sine", vol, decay=0.25), tone(f * 3.9, dur * 0.5, "sine", vol * 0.25, decay=0.05))


def flute(note, dur, vol=0.08):
    return tone(hz(note), dur, "sine", vol, attack=0.04, tremolo=0.1, tremolo_hz=5.0)


def reed(note, dur, vol=0.06):   # clarinet-ish
    return tone(hz(note), dur, "square", vol, attack=0.03, lowpass=1600, tremolo=0.08, tremolo_hz=5.5)


def pad(note, dur, vol=0.035):
    return tone(hz(note), dur, "saw", vol, attack=dur * 0.3, release=dur * 0.3, lowpass=1300, detune=0.008)


def lead(note, dur, vol=0.06, shape="square", lp=3200):
    return tone(hz(note), dur, shape, vol, attack=0.01, decay=dur * 0.8, lowpass=lp, detune=0.004)


# ---------------------------------------------------------------- composer

def theme(bpm, beats_per_bar, bars, parts):
    """parts: list of (instrument_fn, [(bar, beat, note_or_None, beats), ...], gain)."""
    beat = 60.0 / bpm
    tr = Track(bars * beats_per_bar * beat, loop=True)
    for fn, events, gain in parts:
        for b, pos, note, length in events:
            t = (b * beats_per_bar + pos) * beat
            s = fn(length * beat) if note is None else fn(note, length * beat)
            tr.add(t, s, gain)
    return tr.buf


def every_bar(bars, pattern):
    """Repeat a [(beat, note, beats)] pattern on every bar."""
    return [(b, p, n, d) for b in range(bars) for p, n, d in pattern]


def drum(fn):
    return lambda dur: fn()


def melody(spec):
    """'bar:beat:note:beats ...' -> events (note "-" = rest)."""
    ev = []
    for tok in spec.split():
        b, p, n, d = tok.split(":")
        if n != "-":
            ev.append((int(b), float(p), n, float(d)))
    return ev


def chords_events(chords, voicing, beats, pattern):
    ev = []
    for b, ch in enumerate(chords):
        for p in pattern:
            for n in voicing[ch]:
                ev.append((b, p, n, beats))
    return ev


def paris():
    ch = ["C", "G7", "G7", "C", "F", "C", "G7", "C"]
    v = {"C": ["E4", "G4", "C5"], "G7": ["F4", "G4", "B4"], "F": ["F4", "A4", "C5"]}
    root = {"C": "C3", "G7": "G2", "F": "F2"}
    return theme(160, 3, 8, [
        (bass, [(b, 0, root[c], 0.9) for b, c in enumerate(ch)], 1.0),
        (accordion, chords_events(ch, v, 0.5, [1, 2]), 0.8),
        (accordion, melody("0:0:E5:1 0:1:G5:1 0:2:C6:1 1:0:B5:2 1:2:A5:1 2:0:G5:2 2:2:F5:1 3:0:E5:3 "
                           "4:0:F5:1 4:1:A5:1 4:2:C6:1 5:0:E6:2 5:2:D6:1 6:0:C6:1 6:1:B5:1 6:2:D6:1 7:0:C6:3"), 1.6),
        (drum(lambda: hat(0.05)), every_bar(8, [(1, None, 0.2), (2, None, 0.2)]), 1.0),
    ])


def new_york():
    walk = ["F2", "A2", "C3", "D3", "Bb2", "D3", "F3", "D3", "G2", "Bb2", "C3", "E3", "C3", "E3", "G3", "E3"]
    bars = 8
    bass_ev = [(b, q, walk[(b * 4 + q) % len(walk)], 0.9) for b in range(bars) for q in range(4)]
    ch = ["F", "Bb", "G", "C", "F", "Bb", "C", "F"]
    v = {"F": ["A3", "C4", "E4"], "Bb": ["A3", "D4", "F4"], "G": ["F3", "A3", "D4"], "C": ["E3", "G3", "Bb3"]}
    return theme(126, 4, bars, [
        (bass, bass_ev, 0.9),
        (lambda n, d: pluck(n, d, 0.07, 2200, "tri"), chords_events(ch, v, 0.4, [1.66, 3.66]), 1.0),
        (drum(lambda: ride(0.05)), every_bar(bars, [(0, None, 1), (1, None, 1), (1.66, None, 1), (2, None, 1), (3, None, 1), (3.66, None, 1)]), 1.0),
        (drum(lambda: snare(0.12)), every_bar(bars, [(1, None, 1), (3, None, 1)]), 1.0),
        (drum(lambda: kick(0.3)), every_bar(bars, [(0, None, 1), (2.66, None, 1)]), 1.0),
        (lambda n, d: lead(n, d, 0.05, "square", 1800), melody(
            "0:0:C5:0.66 0:0.66:D5:0.34 0:1:F5:1.5 0:3:A5:1 1:0:G5:1 1:1:F5:0.66 1:1.66:D5:1.34 "
            "2:0:F5:0.66 2:0.66:G5:0.34 2:1:A5:1.5 3:0:G5:3 4:0:C6:1 4:1:A5:0.66 4:1.66:F5:1.34 "
            "5:0:D5:1 5:1:F5:1 5:2:A5:2 6:0:G5:1.5 6:1.5:E5:0.5 6:2:C5:2 7:0:F5:3"), 1.0),
    ])


def rio():
    ch = ["Am7", "D7", "Gmaj7", "Cmaj7", "Fmaj7", "Bm7b5", "E7", "Am7"]
    v = {"Am7": ["G3", "C4", "E4"], "D7": ["F#3", "C4", "E4"], "Gmaj7": ["F#3", "B3", "D4"], "Cmaj7": ["E3", "B3", "G4"],
         "Fmaj7": ["E3", "A3", "C4"], "Bm7b5": ["A3", "D4", "F4"], "E7": ["G#3", "D4", "E4"]}
    root = {"Am7": "A2", "D7": "D2", "Gmaj7": "G2", "Cmaj7": "C3", "Fmaj7": "F2", "Bm7b5": "B2", "E7": "E2"}
    return theme(104, 4, 8, [
        (bass, [(b, p, root[c], 0.8) for b, c in enumerate(ch) for p in (0, 1.5, 2, 3.5)], 0.8),
        (lambda n, d: pluck(n, d, 0.06, 1800, "tri"), chords_events(ch, v, 0.4, [0, 0.75, 1.5, 2.5, 3.25]), 1.0),
        (drum(lambda: shaker(0.045)), every_bar(8, [(q * 0.25, None, 0.2) for q in range(16)]), 1.0),
        (drum(rim), every_bar(8, [(0.75, None, 1), (1.5, None, 1), (2.75, None, 1), (3.5, None, 1)]), 0.8),
        (drum(lambda: kick(0.35)), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),
        (flute, melody("0:0:E5:1.5 0:1.5:C5:0.5 0:2:D5:2 1:0:C5:1.5 1:1.5:A4:0.5 1:2:B4:2 2:0:D5:1 2:1:B4:1 2:2:A4:2 "
                       "3:0:G4:4 4:0:A4:1 4:1:C5:1 4:2:E5:2 5:0:D5:2 5:2:F5:2 6:0:E5:1 6:1:D5:1 6:2:B4:2 7:0:A4:4"), 1.0),
    ])


def rome():
    # 6/8 felt as 2 beats of 3 eighths: write in eighths (6 per bar), fast.
    ch = ["Dm", "Dm", "A7", "A7", "Gm", "Dm", "A7", "Dm"]
    v = {"Dm": ["F4", "A4", "D5"], "A7": ["E4", "G4", "C#5"], "Gm": ["G4", "Bb4", "D5"]}
    root = {"Dm": "D3", "A7": "A2", "Gm": "G2"}
    tremolo = lambda n, d: layer(*[at(k * 0.06, pluck(n, 0.07, 0.07, 3200)) for k in range(max(1, int(d / 0.06)))])
    return theme(420, 6, 8, [
        (bass, [(b, p, root[c], 2.5) for b, c in enumerate(ch) for p in (0, 3)], 0.9),
        (accordion, chords_events(ch, v, 1.5, [1, 4]), 0.6),
        (drum(lambda: jingle(0.07)), every_bar(8, [(0, None, 1), (2, None, 1), (3, None, 1), (5, None, 1)]), 1.0),
        (tremolo, melody("0:0:A5:2 0:2:F5:1 0:3:D5:3 1:0:E5:2 1:2:F5:1 1:3:G5:3 2:0:A5:2 2:2:G5:1 2:3:E5:3 "
                         "3:0:C#5:3 3:3:E5:3 4:0:D5:2 4:2:Bb4:1 4:3:G5:3 5:0:F5:2 5:2:E5:1 5:3:D5:3 "
                         "6:0:E5:2 6:2:C#5:1 6:3:A4:3 7:0:D5:6"), 1.0),
    ])


def dubai():
    # Hijaz on D: D Eb F# G A Bb C. Maqsum: dum tek - tek dum - tek -
    return theme(100, 4, 8, [
        (bass, every_bar(8, [(0, "D2", 0.9), (1.5, "D2", 0.4), (2, "A2", 0.9), (3, "D2", 0.9)]), 0.9),
        (drum(dum), every_bar(8, [(0, None, 1), (1.5, None, 1), (2, None, 1)]), 1.0),
        (drum(tek), every_bar(8, [(0.5, None, 1), (1, None, 1), (2.5, None, 1), (3, None, 1), (3.5, None, 1)]), 0.9),
        (drum(lambda: kick(0.3)), every_bar(8, [(0, None, 1), (2, None, 1)]), 1.0),
        (pad, [(b, 0, n, 4) for b in range(8) for n in ("D4", "A4")], 1.0),
        (lambda n, d: pluck(n, d, 0.09, 2400, "saw"), melody(
            "0:0:D5:0.5 0:0.5:Eb5:0.5 0:1:F#5:1 0:2:G5:0.5 0:2.5:F#5:0.5 0:3:Eb5:1 1:0:D5:2 1:2:A4:2 "
            "2:0:G5:0.5 2:0.5:A5:0.5 2:1:Bb5:1 2:2:A5:0.5 2:2.5:G5:0.5 2:3:F#5:1 3:0:G5:2 3:2:Eb5:2 "
            "4:0:D5:0.5 4:0.5:F#5:0.5 4:1:A5:1 4:2:C6:1 4:3:Bb5:1 5:0:A5:2 5:2:G5:1 5:3:F#5:1 "
            "6:0:G5:1 6:1:F#5:0.5 6:1.5:Eb5:0.5 6:2:F#5:1 6:3:Eb5:1 7:0:D5:4"), 1.0),
    ])


def london():
    ch = ["G", "G", "C", "D", "G", "Em", "C", "D"]
    v = {"G": ["B3", "D4", "G4"], "C": ["C4", "E4", "G4"], "D": ["D4", "F#4", "A4"], "Em": ["B3", "E4", "G4"]}
    root = {"G": "G2", "C": "C3", "D": "D3", "Em": "E2"}
    return theme(150, 4, 8, [
        (bass, [(b, p, root[c], 0.45) for b, c in enumerate(ch) for p in (0, 1, 2, 2.5, 3)], 0.9),
        (organ, chords_events(ch, v, 0.25, [0.5, 1.5, 2.5, 3.5]), 0.8),   # the ska off-beat
        (drum(lambda: kick(0.4)), every_bar(8, [(0, None, 1), (2, None, 1)]), 1.0),
        (drum(lambda: snare(0.2)), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),
        (drum(lambda: hat(0.05)), every_bar(8, [(q * 0.5, None, 1) for q in range(8)]), 1.0),
        (brass, melody("0:0:D5:1 0:1:B4:1 0:2:G4:2 1:0:A4:1 1:1:B4:1 1:2:D5:2 2:0:E5:1 2:1:D5:1 2:2:C5:2 "
                       "3:0:A4:3 4:0:D5:1 4:1:G5:1 4:2:F#5:1 4:3:E5:1 5:0:D5:2 5:2:B4:2 6:0:C5:1 6:1:E5:1 6:2:G5:2 7:0:F#5:4"), 1.0),
    ])


def tokyo():
    ch = ["Fmaj7", "G", "Em7", "Am7", "Dm7", "G", "Cmaj7", "E7"]
    arp = {"Fmaj7": ["F4", "A4", "C5", "E5"], "G": ["G4", "B4", "D5", "G5"], "Em7": ["E4", "G4", "B4", "D5"],
           "Am7": ["A4", "C5", "E5", "G5"], "Dm7": ["D4", "F4", "A4", "C5"], "Cmaj7": ["C4", "E4", "G4", "B4"],
           "E7": ["E4", "G#4", "B4", "D5"]}
    root = {"Fmaj7": "F2", "G": "G2", "Em7": "E2", "Am7": "A2", "Dm7": "D2", "Cmaj7": "C2", "E7": "E2"}
    arp_ev = [(b, q * 0.25, arp[c][q % 4], 0.22) for b, c in enumerate(ch) for q in range(16)]
    return theme(124, 4, 8, [
        (lambda n, d: bass(n, d, 0.22, "square", 700), [(b, p, root[c], 0.4) for b, c in enumerate(ch) for p in (0, 0.75, 1.5, 2, 2.75, 3.5)], 0.8),
        (lambda n, d: lead(n, d, 0.035, "square", 3000), arp_ev, 1.0),
        (drum(lambda: kick(0.4)), every_bar(8, [(q, None, 1) for q in range(4)]), 1.0),
        (drum(clap), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),
        (drum(lambda: hat(0.05)), every_bar(8, [(q + 0.5, None, 1) for q in range(4)]), 1.0),
        (lambda n, d: lead(n, d, 0.06, "saw", 2600), melody(
            "0:0:A5:1 0:1:G5:0.5 0:1.5:A5:1.5 0:3:C6:1 1:0:B5:2 1:2:G5:2 2:0:E5:1 2:1:G5:1 2:2:B5:2 3:0:A5:4 "
            "4:0:F5:1 4:1:A5:1 4:2:C6:1 4:3:D6:1 5:0:B5:2 5:2:G5:2 6:0:E6:2 6:2:D6:1 6:3:B5:1 7:0:G#5:4"), 1.0),
    ])


def istanbul():
    # 9/8 as eighths: 2+2+2+3. Hicaz on A: A Bb C# D E F G.
    return theme(330, 9, 8, [
        (bass, every_bar(8, [(0, "A2", 1.8), (2, "A2", 1.8), (4, "E2", 1.8), (6, "A2", 2.8)]), 0.9),
        (drum(dum), every_bar(8, [(0, None, 1), (4, None, 1), (6, None, 1)]), 1.0),
        (drum(tek), every_bar(8, [(2, None, 1), (3, None, 1), (5, None, 1), (7, None, 1), (8, None, 1)]), 0.9),
        (reed, melody("0:0:A5:2 0:2:Bb5:2 0:4:C#6:2 0:6:D6:3 1:0:E6:2 1:2:D6:2 1:4:C#6:2 1:6:Bb5:3 "
                      "2:0:A5:2 2:2:C#6:2 2:4:E6:2 2:6:F6:3 3:0:E6:4 3:4:D6:2 3:6:C#6:3 "
                      "4:0:D6:2 4:2:E6:2 4:4:F6:2 4:6:G6:3 5:0:F6:2 5:2:E6:2 5:4:D6:2 5:6:C#6:3 "
                      "6:0:Bb5:2 6:2:C#6:2 6:4:Bb5:2 6:6:A5:3 7:0:A5:9"), 1.0),
    ])


def bangkok():
    pent = ["C5", "D5", "E5", "G5", "A5", "C6", "D6"]
    rnd = random.Random(7)
    mel = []
    for b in range(8):
        i = rnd.randrange(3)
        for q in range(8):
            i = max(0, min(len(pent) - 1, i + rnd.choice([-1, 1, 1, 2, -2, 0])))
            if rnd.random() < 0.85:
                mel.append((b, q * 0.5, pent[i], 0.45))
    return theme(118, 4, 8, [
        (bass, every_bar(8, [(0, "C2", 0.8), (1, "G2", 0.8), (2, "A2", 0.8), (3, "G2", 0.8)]), 0.9),
        (lambda n, d: tone(hz(n), d, "saw", 0.025, attack=0.05, lowpass=1200), [(b, 0, n, 4) for b in range(8) for n in ("C4", "G4")], 1.0),  # reed drone
        (mallet, mel, 1.0),
        (drum(lambda: tone(3100, 0.18, "sine", 0.08, decay=0.05)), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),   # ching
        (drum(lambda: kick(0.35)), every_bar(8, [(0, None, 1), (2, None, 1), (2.5, None, 1)]), 1.0),
        (drum(lambda: snare(0.14)), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),
    ])


def singapore():
    ch = ["Fm", "Db", "Ab", "Eb", "Fm", "Db", "Bbm", "C"]
    arp = {"Fm": ["F4", "Ab4", "C5"], "Db": ["Db4", "F4", "Ab4"], "Ab": ["Ab4", "C5", "Eb5"], "Eb": ["Eb4", "G4", "Bb4"],
           "Bbm": ["Bb3", "Db4", "F4"], "C": ["C4", "E4", "G4"]}
    root = {"Fm": "F2", "Db": "Db2", "Ab": "Ab2", "Eb": "Eb2", "Bbm": "Bb1", "C": "C2"}
    arp_ev = [(b, q * 0.25, arp[c][q % 3], 0.22) for b, c in enumerate(ch) for q in range(16)]
    return theme(104, 4, 8, [
        (lambda n, d: bass(n, d, 0.2, "saw", 500), [(b, q * 0.5, root[c], 0.45) for b, c in enumerate(ch) for q in range(8)], 0.8),
        (pad, [(b, 0, n, 4) for b, c in enumerate(ch) for n in arp[c]], 1.0),
        (lambda n, d: lead(n, d, 0.03, "saw", 2400), arp_ev, 1.0),
        (drum(lambda: kick(0.45)), every_bar(8, [(0, None, 1), (2, None, 1)]), 1.0),
        (drum(lambda: layer(snare(0.25), noise(0.4, 0.06, decay=0.25, highpass=800, seed=88))), every_bar(8, [(1, None, 1), (3, None, 1)]), 1.0),
        (drum(lambda: hat(0.04)), every_bar(8, [(q * 0.5, None, 1) for q in range(8)]), 1.0),
        (lambda n, d: lead(n, d, 0.05, "square", 2000), melody(
            "0:0:C6:2 0:2:Ab5:2 1:0:F5:3 1:3:Ab5:1 2:0:Eb6:2 2:2:C6:2 3:0:Bb5:4 "
            "4:0:C6:1 4:1:Db6:1 4:2:C6:2 5:0:Ab5:3 5:3:F5:1 6:0:Db6:2 6:2:Bb5:2 7:0:G5:4"), 1.0),
    ])


# ---------------------------------------------------------------- loops and effects

def seamless(fn, seconds, base_hz):
    """A loop whose waveform period divides the length exactly, so it repeats without a click."""
    cycles = max(1, round(seconds * base_hz))
    return fn(cycles / base_hz)


def engine_loop():
    def make(dur):
        n = int(dur * SR)
        f0 = round(70 * dur) / dur
        y = 0.0
        out_ = []
        rnd = random.Random(3)
        for i in range(n):
            t = i / SR
            s = 0.6 * (2 * ((f0 * t) % 1.0) - 1) + 0.4 * math.sin(math.tau * f0 * 2 * t) + 0.25 * (rnd.random() * 2 - 1)
            y += 0.12 * (s - y)   # dark: low-pass
            out_.append(y * (0.8 + 0.2 * math.sin(math.tau * (f0 / 7) * t)))
        return out_
    return seamless(make, 1.0, 70)


def skid_loop():
    rnd = random.Random(5)
    n = SR
    out_ = []
    y = y2 = 0.0
    for i in range(n):
        t = i / SR
        s = rnd.random() * 2 - 1
        y += 0.35 * (s - y)
        y2 += 0.5 * (y - y2)
        squeal = 0.35 * math.sin(math.tau * 1100 * t + 3 * math.sin(math.tau * 9 * t))
        out_.append((y - y2) * 0.8 + squeal * 0.5)
    return out_


def siren_loop():
    parts = [at(k * 0.45, tone(hz("B5") if k % 2 == 0 else hz("E5"), 0.45, "tri", 0.3, attack=0.02, release=0.04, lowpass=2500))
             for k in range(4)]
    s = layer(*parts)
    return s[:int(1.8 * SR)]


def rain_loop():
    rnd = random.Random(9)
    out_ = []
    y = 0.0
    for i in range(int(2.0 * SR)):
        s = rnd.random() * 2 - 1
        y += 0.25 * (s - y)
        out_.append(y * (0.7 + 0.3 * rnd.random()))
    return out_


def vibrato(freq, dur, vol, depth, rate, shape="sine", glide_to=None, decay=None, lowpass=None):
    n = int(dur * SR)
    out_ = [0.0] * n
    p = y = 0.0
    k = 1 - math.exp(-A.TAU * lowpass / SR) if lowpass else None
    for i in range(n):
        t = i / SR
        f = freq if glide_to is None else freq * (glide_to / freq) ** (t / dur)
        f *= 1 + depth * math.sin(A.TAU * rate * t)
        p = (p + f / SR) % 1.0
        s = A._wave(shape, p)
        if k:
            y += k * (s - y)
            s = y
        env = min(1.0, t / 0.02) * (math.exp(-t / decay) if decay else 1.0) * min(1.0, (dur - t) / 0.04)
        out_[i] = s * env * vol
    return out_


def effects():
    s = {}
    s["crash"] = layer(tone(140, 0.35, "sine", 0.7, decay=0.09, glide_to=40),
                       noise(0.4, 0.5, decay=0.12, lowpass=3000, seed=11),
                       at(0.05, noise(0.3, 0.15, decay=0.08, highpass=5000, seed=12)))     # a little glass
    s["bump"] = layer(tone(120, 0.18, "sine", 0.5, decay=0.05, glide_to=60), noise(0.08, 0.15, decay=0.03, lowpass=1200, seed=13))
    s["honk"] = layer(vibrato(hz("F4"), 0.3, 0.3, 0.004, 30, shape="square", lowpass=1500),
                      vibrato(hz("A4"), 0.3, 0.25, 0.004, 30, shape="square", lowpass=1500))
    s["splash"] = layer(noise(0.7, 0.6, decay=0.22, lowpass=3000, sweep_to=400, seed=14),
                        at(0.15, tone(500, 0.12, "sine", 0.3, glide_to=1200, decay=0.04)))
    s["jump"] = noise(0.5, 0.4, lowpass=300, sweep_to=4000, highpass=150, seed=15, attack=0.15)
    s["land"] = layer(tone(90, 0.25, "sine", 0.6, decay=0.07, glide_to=45), noise(0.1, 0.2, decay=0.03, lowpass=900, seed=16))
    s["kaching"] = layer(noise(0.12, 0.2, decay=0.03, highpass=3000, seed=17),
                         at(0.06, tone(hz("E6"), 0.7, "sine", 0.35, decay=0.22)),
                         at(0.14, tone(hz("B6"), 0.6, "sine", 0.25, decay=0.18)))
    s["pickup"] = layer(tone(hz("A5"), 0.12, "sine", 0.35, decay=0.05), at(0.1, tone(hz("E6"), 0.25, "sine", 0.35, decay=0.1)))
    s["review_good"] = layer(tone(hz("C6"), 0.5, "sine", 0.3, decay=0.2), at(0.08, tone(hz("G6"), 0.5, "sine", 0.25, decay=0.2)))
    s["review_bad"] = tone(160, 0.35, "square", 0.18, decay=0.15, lowpass=900, glide_to=110)
    s["fine"] = layer(tone(hz("E4"), 0.18, "square", 0.15, lowpass=1500), at(0.18, tone(hz("C4"), 0.35, "square", 0.15, lowpass=1500, decay=0.2)))
    s["alert"] = layer(*[at(k * 0.11, tone(hz(n), 0.18, "sine", 0.3, decay=0.08)) for k, n in enumerate(["C6", "E6", "G6"])])
    s["arrest"] = layer(*[at(k * 0.1, tone(hz(n), 0.3 if k < 3 else 0.6, "saw", 0.12, attack=0.01, lowpass=2500, decay=0.3))
                          for k, n in enumerate(["C5", "E5", "G5", "C6"])])
    s["incident"] = layer(tone(hz("D3"), 1.2, "sine", 0.4, decay=0.6), tone(hz("D3") * 2.7, 1.0, "sine", 0.15, decay=0.4))  # a gong
    s["near"] = noise(0.35, 0.25, decay=None, lowpass=600, sweep_to=3500, highpass=200, seed=18, attack=0.1)
    s["tick"] = tone(1800, 0.05, "sine", 0.18, decay=0.01)
    s["ui"] = tone(900, 0.06, "sine", 0.2, decay=0.02, glide_to=1300)
    s["talk"] = tone(440, 0.08, "square", 0.12, attack=0.004, decay=0.04, lowpass=1600, glide_to=520)  # one gibberish syllable
    s["win"] = layer(*[at(k * 0.12, tone(hz(n), 0.5, "tri", 0.25, decay=0.3)) for k, n in enumerate(["C5", "E5", "G5", "C6", "E6"])])
    notes = [("D4", 0.32), ("C#4", 0.32), ("C4", 0.32), ("B3", 1.0)]
    t = 0.0
    parts = []
    for i, (n, d) in enumerate(notes):
        last = i == len(notes) - 1
        parts.append(at(t, vibrato(hz(n), d, 0.3, 0.03 if last else 0.012, 5.5, shape="saw",
                                   glide_to=hz(n) * (0.97 if last else 0.995), lowpass=1500)))
        t += d * 0.95
    s["lose"] = layer(*parts)
    s["scratch"] = layer(noise(0.12, 0.6, decay=0.08, lowpass=900, sweep_to=4500, seed=21),
                         at(0.1, noise(0.16, 0.6, decay=0.1, lowpass=4500, sweep_to=600, seed=22)))
    return s


def main():
    for name, fn in [("paris", paris), ("new_york", new_york), ("rio", rio), ("rome", rome), ("dubai", dubai),
                     ("london", london), ("tokyo", tokyo), ("istanbul", istanbul), ("bangkok", bangkok),
                     ("singapore", singapore)]:
        out("music", name, fn())
    sys.path.insert(0, os.path.join(os.path.dirname(__file__), "video"))
    from make_video_audio import gig_groove   # the menu: the same groove as the videos
    out("music", "menu", gig_groove())
    out("loops", "engine", engine_loop(), peak=0.7)
    out("loops", "skid", skid_loop(), peak=0.6)
    out("loops", "siren", siren_loop(), peak=0.7)
    out("loops", "rain", rain_loop(), peak=0.5)
    for name, samples in effects().items():
        out("sfx", name, samples)


if __name__ == "__main__":
    main()
