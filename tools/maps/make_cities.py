#!/usr/bin/env python3
"""Builds every city map and writes scripts/cities.gd (the game reads only that).

    python3 tools/maps/make_cities.py

Each city is a few lines of drawing commands on a tile grid (roads, rivers,
parks, landmarks) plus its stops, traffic loops and look. Everything is
checked here, before the game ever sees it:
- rows the same width;
- every stop on a road and reachable from the start;
- traffic loops running only on plain road.

Map letters (the game's legend, see city.gd):
  #  building (solid)      H  house on a lawn (solid)    L  landmark footprint (solid)
  .  road                  ,  grass (slow)               :  sand (slow)
  T  tree (solid)          F  fountain (solid, 2x2)      M  hill / rock (solid)
  ~  water (solid unless you fly over it)                ^  ramp
  S  start                 a-z  ride stops (on road)
"""
import os
import sys
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "scripts", "cities.gd")
DRIVABLE = set(".,:^S") | set("abcdefghijklmnopqrstuvwxyz")
PLAIN_ROAD = set(".S") | set("abcdefghijklmnopqrstuvwxyz")


class Map:
    def __init__(self, w, h, fill="#"):
        self.w, self.h = w, h
        self.g = [[fill] * w for _ in range(h)]
        self.stops = {}         # letter -> (x, y, name)
        self.loops = []
        self.landmarks = []
        self.start = None

    def put(self, x, y, c):
        self.g[y][x] = c

    def at(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.g[y][x]
        return "#"

    def rect(self, x0, y0, x1, y1, c):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.put(x, y, c)

    def hroad(self, y, x0=1, x1=None):
        self.rect(x0, y, self.w - 2 if x1 is None else x1, y, ".")

    def vroad(self, x, y0=1, y1=None):
        self.rect(x, y0, x, self.h - 2 if y1 is None else y1, ".")

    def grid(self, rows, cols):
        for y in rows:
            self.hroad(y)
        for x in cols:
            self.vroad(x)

    def park(self, x0, y0, x1, y1, trees=(), ground=","):
        self.rect(x0, y0, x1, y1, ground)
        for x, y in trees:
            self.put(x, y, "T")

    def landmark(self, kind, x, y, w, h, **extra):
        self.rect(x, y, x + w - 1, y + h - 1, "L")
        self.landmarks.append(dict(kind=kind, x=x, y=y, w=w, h=h, **extra))

    def stop(self, letter, x, y, name):
        assert self.at(x, y) == ".", f"stop {letter} at {(x, y)} is on '{self.at(x, y)}', not road"
        self.put(x, y, letter)
        self.stops[letter] = (x, y, name)

    def start_at(self, x, y):
        assert self.at(x, y) == ".", f"start at {(x, y)} is on '{self.at(x, y)}'"
        self.put(x, y, "S")
        self.start = (x, y)

    def loop(self, x0, y0, x1, y1):
        corners = [(x0, y0), (x1, y0), (x1, y1), (x0, y1)]
        for (ax, ay), (bx, by) in zip(corners, corners[1:] + corners[:1]):
            sx = (bx > ax) - (bx < ax)
            sy = (by > ay) - (by < ay)
            x, y = ax, ay
            while (x, y) != (bx, by):
                assert self.at(x, y) in PLAIN_ROAD, f"loop {corners} crosses '{self.at(x, y)}' at {(x, y)}"
                x, y = x + sx, y + sy
        self.loops.append(corners)
        return len(self.loops) - 1

    def check(self, key):
        assert self.start, f"{key}: no start"
        seen = {self.start}
        q = deque([self.start])
        while q:
            x, y = q.popleft()
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                n = (x + dx, y + dy)
                if n not in seen and self.at(*n) in DRIVABLE:
                    seen.add(n)
                    q.append(n)
        for letter, (x, y, _) in self.stops.items():
            assert (x, y) in seen, f"{key}: stop {letter} unreachable"
        assert len(self.stops) >= 10, f"{key}: only {len(self.stops)} stops"


def gd_color(hexstr):
    return f'Color("{hexstr}")'


def gd_value(v):
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return gd_color(v) if v.startswith("#") else '"' + v.replace('"', '\\"') + '"'
    if isinstance(v, tuple):
        return f"Vector2i({v[0]}, {v[1]})"
    if isinstance(v, list):
        return "[" + ", ".join(gd_value(x) for x in v) + "]"
    if isinstance(v, dict):
        return "{" + ", ".join(f'"{k}": {gd_value(x)}' for k, x in v.items()) + "}"
    raise TypeError(v)


def emit(key, m, meta):
    m.check(key)
    rows = ["".join(r) for r in m.g]
    out = [f'\t"{key}": {{']
    for k, v in meta.items():
        out.append(f'\t\t"{k}": {gd_value(v)},')
    out.append('\t\t"map": [')
    out += [f'\t\t\t"{r}",' for r in rows]
    out.append("\t\t],")
    out.append('\t\t"stops": {' + ", ".join(f'"{k}": "{v[2]}"' for k, v in sorted(m.stops.items())) + "},")
    out.append('\t\t"loops": [' + ", ".join(gd_value(c) for c in m.loops) + "],")
    out.append('\t\t"landmarks": ' + gd_value(m.landmarks) + ",")
    out.append("\t},")
    return "\n".join(out)


# ---------------------------------------------------------------- the cities

CITIES = []   # (key, builder) in order


def city(key):
    def wrap(fn):
        CITIES.append((key, fn))
        return fn
    return wrap


@city("classic")
def classic():
    """The original test city."""
    m = Map(42, 29)
    m.grid([1, 7, 14, 21, 27], [1, 8, 15, 23, 31, 40])
    m.park(2, 2, 7, 6, [(3, 3), (6, 3), (4, 5), (7, 5), (2, 6)])
    m.rect(32, 2, 39, 6, ",")
    for x in (33, 35, 37, 39):
        m.put(x, 3, "H")
        m.put(x, 5, "H")
    m.rect(24, 2, 30, 6, ",")
    for x in (25, 27, 29):
        m.put(x, 3, "H")
    m.rect(24, 5, 30, 5, ".")
    m.rect(16, 8, 22, 13, ".")
    m.rect(18, 10, 19, 11, "F")
    m.put(21, 9, "^")
    m.rect(27, 15, 27, 20, ".")
    m.rect(32, 10, 39, 10, ".")
    m.rect(9, 17, 14, 17, ".")
    m.rect(1, 24, 40, 25, "~")
    for x in (1, 8, 23, 40):
        m.rect(x, 24, x, 25, ".")
    for x in (15, 31):
        m.put(x, 23, "^")
        m.put(x, 26, "^")
    m.park(32, 15, 39, 20, [(33, 16), (38, 19)])
    m.rect(34, 16, 37, 19, "~")
    for letter, x, y, name in [
            ("a", 19, 8, "Pixel Plaza"), ("b", 11, 7, "Bean There Cafe"), ("c", 4, 14, "Swole Patrol Gym"),
            ("d", 12, 27, "Dockside Fish Fry"), ("e", 19, 14, "City Hall-ish"), ("f", 35, 7, "Sunny Acres Home"),
            ("g", 27, 21, "Club Thump"), ("h", 28, 5, "Startup Garage"), ("i", 36, 14, "Mega Mall-o-rama"),
            ("j", 8, 11, "St. Bandaid's Clinic"), ("k", 5, 1, "Leafy Park Gate"), ("l", 37, 27, "Wing It Airport"),
            ("m", 23, 18, "Big Brain University"), ("n", 40, 4, "Hilltop Lookout"), ("o", 31, 11, "Slice Slice Baby"),
            ("p", 1, 20, "Choo-Choo Central"), ("q", 20, 27, "Ferry Terminal"), ("r", 15, 4, "Popcorn Palace")]:
        m.stop(letter, x, y, name)
    m.start_at(15, 17)
    m.loop(1, 1, 40, 27)
    m.loop(8, 7, 31, 21)
    m.loop(15, 1, 23, 14)
    m.loop(1, 7, 8, 27)
    m.loop(23, 14, 40, 21)
    m.loop(31, 1, 40, 7)
    return m, dict(name="Hometown", drive_left=False, look=dict())


def main():
    parts = []
    for key, fn in CITIES:
        m, meta = fn()
        parts.append(emit(key, m, meta))
        print(f"{key:10s} {m.w}x{m.h}  stops={len(m.stops)}  loops={len(m.loops)}  landmarks={len(m.landmarks)}")
    text = ('extends RefCounted\n'
            '## GENERATED by tools/maps/make_cities.py. Do not edit by hand: edit the\n'
            '## generator and run it again.\n\n'
            'const CITIES := {\n' + "\n".join(parts) + "\n}\n")
    with open(OUT, "w") as f:
        f.write(text)
    print("wrote", os.path.relpath(OUT, ROOT))


if __name__ == "__main__":
    main()
