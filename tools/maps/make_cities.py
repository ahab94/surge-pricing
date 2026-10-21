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
  S  start                 a-z  ride stops (on road)    X  scramble crossing (road)
"""
import os
import sys
from collections import deque

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "scripts", "cities.gd")
DRIVABLE = set(".,:^SX") | set("abcdefghijklmnopqrstuvwxyz")
PLAIN_ROAD = set(".SX") | set("abcdefghijklmnopqrstuvwxyz")


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

    def prop(self, kind, x, y, w, h, **extra):
        """A decorative model that doesn't block anything (umbrellas, pylons)."""
        self.landmarks.append(dict(kind=kind, x=x, y=y, w=w, h=h, **extra))

    def water_h(self, y0, y1, x0=1, x1=None, bridges=(), ramps=()):
        """A river across the map; roads at `bridges` columns cross it on
        bridges, at `ramps` columns you have to jump it."""
        x1 = self.w - 2 if x1 is None else x1
        self.rect(x0, y0, x1, y1, "~")
        for x in bridges:
            self.rect(x, y0, x, y1, ".")
        for x in ramps:
            self.put(x, y0 - 1, "^")
            self.put(x, y1 + 1, "^")

    def water_v(self, x0, x1, y0=1, y1=None, bridges=(), ramps=()):
        y1 = self.h - 2 if y1 is None else y1
        self.rect(x0, y0, x1, y1, "~")
        for y in bridges:
            self.rect(x0, y, x1, y, ".")
        for y in ramps:
            self.put(x0 - 1, y, "^")
            self.put(x1 + 1, y, "^")

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


# ---------------------------------------------------------------- World Tour
# Landmarks are generic shapes and stop names are parodies: no trademarks,
# no real businesses. Each city's level (levels.gd) adds one new thing.

def stops(m, entries):
    for letter, x, y, name in entries:
        m.stop(letter, x, y, name)


@city("paris")
def paris():
    m = Map(44, 30)
    m.grid([1, 7, 13, 20, 28], [1, 9, 17, 26, 34, 42])
    m.water_h(16, 17, bridges=(1, 9, 17, 26, 34, 42))
    m.rect(13, 14, 13, 19, ".")                        # a lane down to the river...
    m.put(13, 15, "^"), m.put(13, 18, "^")             # ...that you can jump
    m.rect(13, 16, 13, 17, "~")
    m.rect(18, 2, 25, 6, ".")                          # the big roundabout
    m.landmark("arch", 21, 3, 2, 3)
    m.park(27, 21, 33, 27, [(27, 21), (33, 21), (27, 27), (33, 27), (28, 24), (32, 24)])
    m.landmark("iron_tower", 29, 22, 3, 3)
    m.park(2, 8, 8, 12, [(2, 8), (8, 8), (2, 12), (8, 12)])
    m.rect(4, 9, 5, 10, "F")
    stops(m, [("a", 18, 4, "Arch Roundabout"), ("b", 5, 7, "Croissant Corner"), ("c", 22, 13, "Mime Academy"),
              ("d", 30, 20, "Iron Tower Lawn"), ("e", 12, 20, "Bouquinistes Row"), ("f", 38, 7, "Beret Boutique"),
              ("g", 9, 4, "Museum of Tiny Smiles"), ("h", 30, 13, "Baguette Bakery"), ("i", 26, 18, "Love Lock Bridge"),
              ("j", 38, 28, "Cafe Snooty"), ("k", 34, 10, "Grand Opera"), ("l", 5, 28, "Fashion Week Hall"),
              ("m", 17, 24, "Escargot Express"), ("n", 30, 1, "Hilltop Painters"), ("o", 1, 24, "Crepe Stand"),
              ("p", 42, 4, "North Station"), ("q", 21, 28, "Riverboat Pier"), ("r", 9, 13, "Perfume Parlour")])
    m.start_at(17, 10)
    m.loop(1, 1, 42, 28)
    m.loop(9, 7, 34, 20)
    m.loop(17, 13, 26, 28)
    m.loop(1, 7, 9, 28)
    m.loop(34, 1, 42, 13)
    m.loop(26, 1, 34, 7)
    return m, dict(name="Paris", drive_left=False, look=dict(
        facades=["#efe6d2", "#e8dcc2", "#f2ead8", "#ddd0b6", "#e6dccb"], roof="#8a97a6", h_min=1.6, h_step=0.12,
        h_boost=0.5, center=(21, 10), sidewalk="#d8d1c2", water="#5f8fa8", harbour="#3f6f88", sky="#a9cfe8",
        trees="round", glass="#4a5568"))


@city("new_york")
def new_york():
    m = Map(44, 30)
    m.grid([1, 4, 7, 10, 13, 16, 19, 22, 25], [1, 8, 15, 22, 29, 36, 42])
    m.rect(16, 5, 28, 12, ",")                         # the big park eats a few blocks
    m.rect(20, 8, 24, 9, "~")
    for t in [(17, 6), (27, 6), (17, 11), (27, 11), (19, 10), (25, 7), (22, 11)]:
        m.put(*t, "T")
    m.rect(1, 26, 42, 29, "~")                         # the harbour
    m.rect(30, 27, 33, 28, ":")
    m.landmark("statue", 31, 27, 2, 1)
    m.landmark("deco_tower", 24, 17, 4, 2)
    m.rect(9, 14, 14, 15, ".")                         # the bright-lights square
    stops(m, [("a", 11, 13, "Big Lights Square"), ("b", 4, 4, "Bagel Bros"), ("c", 22, 13, "Park Gate South"),
              ("d", 18, 4, "Park Gate North"), ("e", 33, 25, "Harbor Ferry"), ("f", 40, 10, "Museum of Old Stuff"),
              ("g", 29, 19, "Deco Tower Lobby"), ("h", 5, 22, "Bodega Cat HQ"), ("i", 15, 25, "Stock Exchange-ish"),
              ("j", 36, 4, "Rooftop Bar"), ("k", 8, 19, "Jazz Basement"), ("l", 42, 22, "Food Truck Alley"),
              ("m", 26, 25, "Hot Dog Cart"), ("n", 1, 10, "Cab Depot"), ("o", 32, 13, "Slice Window"),
              ("p", 12, 7, "Theater Row")])
    m.start_at(15, 18)
    m.loop(1, 1, 42, 25)
    m.loop(8, 1, 15, 25)
    m.loop(29, 1, 36, 25)
    m.loop(1, 13, 42, 16)
    m.loop(15, 16, 29, 25)
    m.loop(36, 1, 42, 13)
    return m, dict(name="New York", drive_left=False, look=dict(
        facades=["#b5573c", "#9c4a37", "#c8bfb0", "#8aa3b8", "#d6cfc2", "#6e7f91"], h_min=2.2, h_step=0.55,
        h_boost=2.2, center=(22, 18), sidewalk="#bdb7ad", water="#3d6f8f", harbour="#2f5c78", sky="#9fc6e4"))


@city("rio")
def rio():
    m = Map(44, 30)
    m.grid([1, 7, 13, 19], [1, 9, 17, 26, 34, 42])
    m.hroad(22, 1, 35)                                 # the beach avenue
    m.vroad(1, 19, 22), m.vroad(9, 19, 22), m.vroad(17, 19, 22), m.vroad(26, 19, 22), m.vroad(34, 19, 22)
    m.rect(1, 23, 35, 25, ":")                         # the beach...
    m.rect(1, 26, 42, 29, "~")                         # ...and the ocean
    m.rect(36, 14, 42, 25, "M")                        # the sugarloaf hills by the sea
    m.rect(38, 11, 42, 13, "M")
    m.rect(18, 8, 25, 12, "~")                         # the lagoon
    m.park(10, 8, 16, 12, [(11, 9), (15, 11), (13, 8)])
    m.water_h(16, 17, x0=1, x1=33, bridges=(1, 9, 34), ramps=(17, 26))   # a canal to jump
    m.prop("umbrellas", 4, 23, 4, 3)
    m.prop("umbrellas", 19, 23, 4, 3)
    m.prop("umbrellas", 28, 23, 4, 3)
    stops(m, [("a", 5, 22, "Beach Volley Court"), ("b", 13, 22, "Coconut Stand"), ("c", 22, 22, "Surf Shop"),
              ("d", 30, 22, "Seafood Shack"), ("e", 21, 7, "Lagoon Kiosk"), ("f", 4, 1, "Hilltop Lookout"),
              ("g", 13, 13, "Samba School"), ("h", 30, 13, "Juice Bar"), ("i", 34, 9, "Cable Car Station"),
              ("j", 1, 15, "Carnival Warehouse"), ("k", 21, 1, "Football Pitch"), ("l", 9, 4, "Bossa Nova Bar"),
              ("m", 26, 4, "Flip-Flop Store"), ("n", 42, 4, "Mountain Trail"), ("o", 17, 19, "Feijoada Spot")])
    m.start_at(9, 10)
    m.loop(1, 1, 42, 7)
    m.loop(1, 1, 9, 13)
    m.loop(9, 7, 34, 13)
    m.loop(26, 1, 34, 13)
    m.loop(1, 19, 34, 22)
    return m, dict(name="Rio", drive_left=False, look=dict(
        facades=["#f7c7a3", "#a3d9f7", "#f7f0a3", "#c3f7a3", "#f7a3c9", "#ffffff"], h_min=1.4, h_step=0.4,
        h_boost=1.2, center=(26, 18), sand="#f1dfa8", sidewalk="#e9e2d0", water="#2fa3c9", harbour="#1f8fb8",
        sky="#8fd8f5", trees="palm", rock="#7d8571", sun=0.95))


@city("rome")
def rome():
    m = Map(44, 30)
    m.grid([1, 5, 9, 13, 17, 21, 25, 28], [1, 6, 11, 16, 21, 26, 31, 36, 42])
    m.water_v(7, 8, y0=1, y1=14, bridges=(1, 5, 9, 13))      # the river, with a bend
    m.rect(7, 14, 10, 15, "~")
    m.water_v(9, 10, y0=15, y1=28, bridges=(17, 21, 25, 28))
    m.rect(22, 10, 30, 16, ".")                        # the arena's roundabout
    m.landmark("arena", 24, 11, 5, 5)
    m.rect(32, 18, 35, 20, ".")                        # the fountain square
    m.rect(33, 19, 34, 20, "F")
    m.park(37, 2, 41, 8, [(37, 2), (41, 2), (39, 4), (37, 8), (41, 8)])
    stops(m, [("a", 26, 10, "Arena Gate"), ("b", 3, 5, "Gelato Corner"), ("c", 33, 18, "Coin Fountain"),
              ("d", 16, 3, "Nonna's Pasta"), ("e", 13, 21, "Espresso Bar"), ("f", 39, 1, "Garden Villa"),
              ("g", 21, 26, "Square Pizza Slices"), ("h", 31, 23, "Scooter Rental"), ("i", 1, 19, "Riverbank Market"),
              ("j", 26, 19, "Grand Steps"), ("k", 36, 13, "Opera House"), ("l", 42, 25, "Leather Goods"),
              ("m", 18, 9, "Trattoria Mamma"), ("n", 3, 28, "Old Bakery"), ("o", 33, 5, "Ruins Kiosk")])
    m.start_at(16, 15)
    m.loop(1, 1, 42, 28)
    m.loop(11, 5, 21, 25)
    m.loop(31, 9, 42, 21)
    m.loop(16, 17, 36, 25)
    m.loop(11, 1, 31, 9)
    return m, dict(name="Rome", drive_left=False, look=dict(
        facades=["#e0a25e", "#d9874f", "#e8c27a", "#c7663f", "#f0d9a8", "#d4a373"], roof="#b85c38", h_min=1.2,
        h_step=0.25, h_boost=0.6, center=(26, 13), sidewalk="#d9c9a8", water="#6b9a6e", harbour="#4f7d52",
        sky="#9fd0f0", trees="pine", plaza="#d9c294"))


@city("dubai")
def dubai():
    m = Map(44, 30)
    m.grid([1, 7, 13, 19], [1, 8, 15, 22, 29, 36, 42])
    m.rect(1, 20, 42, 29, "~")                         # the gulf
    m.vroad(8, 19, 26)                                 # the palm island: a trunk...
    for y in (22, 25):                                 # ...and fronds, with water gaps to jump
        m.hroad(y, 3, 13)
    m.rect(2, 27, 14, 27, ".")
    m.vroad(2, 22, 27), m.vroad(14, 22, 27)
    m.put(8, 24, "^"), m.put(8, 26, "^")               # jump the gap on the trunk
    m.rect(8, 25, 8, 25, "~")
    m.rect(37, 2, 41, 6, ":")                          # desert
    m.rect(23, 14, 28, 18, ":")
    m.landmark("spire", 17, 9, 3, 3)
    m.rect(23, 8, 28, 12, ".")                         # the mall fountain plaza
    m.rect(25, 9, 26, 10, "F")
    stops(m, [("a", 16, 7, "Spire Base"), ("b", 4, 1, "Gold Market"), ("c", 25, 8, "Mega Mall Fountain"),
              ("d", 8, 21, "Palm Trunk Villas"), ("e", 13, 25, "Frond Beach Club"), ("f", 39, 7, "Desert Safari Camp"),
              ("g", 29, 4, "Indoor Ski Slope"), ("h", 36, 16, "Marina Yacht Club"), ("i", 22, 19, "Camel Milk Cafe"),
              ("j", 1, 16, "Creek Water Taxi"), ("k", 42, 13, "Supercar Showroom"), ("l", 11, 13, "Spice Market"),
              ("m", 5, 27, "Frond Tip Mansion"), ("n", 32, 19, "Sky Lounge"), ("o", 15, 4, "Falcon Clinic")])
    m.start_at(15, 16)
    m.loop(1, 1, 42, 19)
    m.loop(8, 1, 22, 13)
    m.loop(22, 1, 36, 13)
    m.loop(1, 7, 15, 19)
    m.loop(29, 7, 42, 19)
    return m, dict(name="Dubai", drive_left=False, look=dict(
        facades=["#cfe3ef", "#b6cfe0", "#e9e4d8", "#d9c9a8", "#9fb8cc", "#f2efe8"], h_min=2.0, h_step=0.7,
        h_boost=3.6, center=(18, 10), sand="#e9cf96", sidewalk="#e4d6b7", water="#2bb3c9", harbour="#1c9db4",
        sky="#cfe7f2", trees="palm", glass="#3f6f8f", sun=1.0))


@city("london")
def london():
    m = Map(44, 30)
    m.grid([1, 7, 12, 18, 23, 28], [1, 8, 15, 22, 29, 36, 42])
    m.water_h(14, 15, x0=1, x1=21, bridges=(1, 8, 15))      # the river, with a bend
    m.rect(20, 14, 21, 17, "~")
    m.water_h(16, 17, x0=22, x1=42, bridges=(22, 29, 42), ramps=(36,))
    m.rect(16, 16, 19, 16, "#")
    m.landmark("clock_tower", 16, 10, 2, 2)
    m.landmark("wheel", 24, 19, 3, 2)
    m.park(2, 2, 7, 6, [(2, 2), (7, 2), (4, 4), (2, 6), (7, 6)])
    m.park(30, 2, 35, 6, [(31, 3), (34, 5)])
    stops(m, [("a", 18, 12, "Big Clock Corner"), ("b", 4, 7, "Tea Room"), ("c", 26, 18, "Riverside Wheel"),
              ("d", 11, 1, "Royal-ish Palace Gates"), ("e", 33, 23, "Fish & Chip Shop"), ("f", 40, 7, "Market Hall"),
              ("g", 25, 12, "Theatre Row"), ("h", 8, 20, "Pub: The Soggy Crumpet"), ("i", 1, 25, "Bus Depot"),
              ("j", 36, 12, "Underground Station"), ("k", 20, 28, "Umbrella Shop"), ("l", 42, 25, "Museum of Rocks"),
              ("m", 15, 4, "Cab Rank"), ("n", 29, 28, "Bakery on the Corner"), ("o", 33, 1, "Park Lane Gates")])
    m.start_at(22, 9)
    m.loop(1, 1, 42, 28)
    m.loop(8, 7, 29, 23)
    m.loop(29, 1, 42, 12)
    m.loop(1, 18, 22, 28)
    m.loop(15, 1, 22, 12)
    return m, dict(name="London", drive_left=True, look=dict(
        facades=["#a65a45", "#8f4b3b", "#cfc6b4", "#bfb39a", "#7d8a96", "#e2ddd2"], h_min=1.6, h_step=0.35,
        h_boost=1.4, center=(18, 12), sidewalk="#b8b4ab", water="#5b7480", harbour="#465d68", sky="#b9c6d0",
        trees="round", lane="#f2f2f2", sun=0.6))


@city("tokyo")
def tokyo():
    m = Map(44, 30)
    m.grid([1, 4, 7, 10, 13, 16, 19, 22, 25, 28], [1, 6, 11, 16, 21, 26, 31, 36, 42])
    m.rect(20, 12, 22, 14, "X")                        # the scramble crossing
    m.park(2, 2, 10, 6, [(2, 2), (5, 3), (8, 2), (3, 5), (7, 6), (10, 5)])
    m.landmark("red_tower", 32, 20, 3, 2)
    m.rect(26, 26, 30, 27, "#")
    stops(m, [("a", 20, 10, "Crossing Plaza"), ("b", 11, 2, "Garden Gate"), ("c", 33, 19, "Tower Lookout"),
              ("d", 3, 13, "Ramen Counter"), ("e", 16, 9, "Karaoke Box"), ("f", 26, 5, "Arcade Center"),
              ("g", 38, 10, "Vending Machine Alley"), ("h", 13, 22, "Sushi Train"), ("i", 6, 26, "Cat Cafe"),
              ("j", 24, 16, "Capsule Hotel"), ("k", 42, 21, "Electronics Town"), ("l", 31, 27, "Fish Market"),
              ("m", 18, 28, "Anime Store"), ("n", 36, 3, "Bento Shop"), ("o", 1, 18, "Photo Booth Mall"),
              ("p", 28, 13, "Neon Alley")])
    m.start_at(16, 18)
    m.loop(1, 1, 42, 28)
    m.loop(11, 7, 31, 19)
    m.loop(26, 1, 42, 13)
    m.loop(1, 16, 16, 28)
    m.loop(21, 19, 36, 28)
    m.loop(6, 7, 11, 25)
    return m, dict(name="Tokyo", drive_left=True, look=dict(
        facades=["#e9ecef", "#cfd6dd", "#b8c2cc", "#f2f2f2", "#9aa7b4", "#dcd3c6"], h_min=1.8, h_step=0.5,
        h_boost=2.0, center=(21, 13), sidewalk="#c4c4c4", sky="#b7d3ea", trees="blossom", neon=True,
        lane="#f2f2f2"))


@city("istanbul")
def istanbul():
    m = Map(44, 30)
    m.grid([1, 7, 12, 17, 21, 28], [1, 8, 15, 27, 34, 42])
    m.water_v(20, 23, bridges=(7, 21))                 # the strait, two long bridges
    m.water_h(13, 14, x0=1, x1=19, bridges=(1, 8, 15))  # the inlet on the west side
    m.rect(1, 12, 19, 12, ".")
    m.prop("pylons", 20, 6, 4, 3, turn=90)
    m.prop("pylons", 20, 20, 4, 3, turn=90)
    m.landmark("round_tower", 10, 9, 2, 2)
    m.rect(29, 22, 33, 26, ".")                        # the covered market square
    m.landmark("arch", 30, 23, 3, 3)
    stops(m, [("a", 11, 7, "Old Round Tower"), ("b", 4, 1, "Simit Cart"), ("c", 16, 21, "Ferry Dock West"),
              ("d", 27, 9, "Ferry Dock East"), ("e", 31, 22, "Covered Market"), ("f", 38, 7, "Tea Garden"),
              ("g", 5, 17, "Kebab House"), ("h", 12, 28, "Carpet Shop"), ("i", 34, 14, "Spice Market"),
              ("j", 1, 24, "Hamam Bathhouse"), ("k", 42, 25, "Baklava Bakery"), ("l", 15, 4, "Fish Sandwich Boat"),
              ("m", 30, 1, "Hilltop Cafe"), ("n", 38, 28, "University Gate"), ("o", 8, 22, "Lokum Shop")])
    m.start_at(15, 18)
    m.loop(1, 7, 42, 21)
    m.loop(1, 1, 15, 12)
    m.loop(27, 1, 42, 7)
    m.loop(1, 21, 15, 28)
    m.loop(27, 21, 42, 28)
    return m, dict(name="Istanbul", drive_left=False, look=dict(
        facades=["#e8d6b9", "#d9a77c", "#c9cdd2", "#efe2c8", "#b9806a", "#dcc7a1"], roof="#b5654a", h_min=1.3,
        h_step=0.35, h_boost=1.2, center=(12, 9), sidewalk="#d6ccb8", water="#2f7fa6", harbour="#24678a",
        sky="#a9d3ee", trees="pine"))


@city("bangkok")
def bangkok():
    m = Map(44, 30)
    m.grid([1, 6, 15, 23, 28], [1, 7, 17, 25, 35, 42])
    m.water_v(12, 13, bridges=(1, 6, 23, 28), ramps=(15,))   # canals: bridges, and two to jump
    m.water_v(30, 31, bridges=(1, 15, 23, 28), ramps=(6,))
    m.water_h(10, 11, x0=1, x1=42, bridges=(1, 7, 17, 25, 35, 42))
    m.rect(12, 10, 13, 11, "~"), m.rect(30, 10, 31, 11, "~")
    m.water_h(19, 20, x0=1, x1=42, bridges=(1, 17, 25, 35, 42), ramps=(7,))
    m.rect(12, 19, 13, 20, "~"), m.rect(30, 19, 31, 20, "~")
    m.landmark("jagged_tower", 19, 2, 4, 3)
    m.rect(26, 24, 33, 27, ".")                        # the night market square
    m.park(37, 24, 41, 27, [(38, 25), (41, 27)])
    stops(m, [("a", 29, 24, "Night Market"), ("b", 14, 6, "Floating Market Pier"), ("c", 20, 6, "Rooftop Sky Bar"),
              ("d", 4, 6, "Pad Thai Cart"), ("e", 21, 15, "Mango Sticky Rice"), ("f", 39, 6, "Tuk-Tuk Garage"),
              ("g", 7, 25, "Muay Thai Gym"), ("h", 35, 18, "Skytrain Station"), ("i", 3, 15, "Boat Noodles"),
              ("j", 42, 13, "Golden Mall"), ("k", 17, 26, "Elephant Pants Shop"), ("l", 25, 2, "Riverside Hotel"),
              ("m", 1, 22, "Foot Massage Spa"), ("n", 37, 28, "Silk Shop"), ("o", 25, 17, "Street Food Alley")])
    m.start_at(17, 8)
    m.loop(1, 1, 42, 28)
    m.loop(1, 1, 17, 6)
    m.loop(35, 1, 42, 15)
    m.loop(17, 23, 42, 28)
    m.loop(1, 23, 17, 28)
    return m, dict(name="Bangkok", drive_left=True, look=dict(
        facades=["#f2e3c6", "#e6d1b8", "#d8e2dc", "#f7d6a0", "#c9d6e3", "#e9c6c6"], h_min=1.4, h_step=0.45,
        h_boost=2.6, center=(21, 4), sidewalk="#d4cbb8", water="#7c8f5e", harbour="#5f7a52", sky="#d9e3e8",
        trees="palm"))


@city("singapore")
def singapore():
    m = Map(44, 30)
    m.grid([1, 7, 13, 19, 25, 28], [1, 8, 15, 23, 30, 36, 42])
    m.rect(16, 20, 29, 27, "~")                        # the bay
    m.rect(16, 19, 29, 19, ".")
    m.vroad(23, 19, 22), m.put(23, 22, "^"), m.put(23, 26, "^")   # a jump over the bay
    m.rect(23, 23, 23, 25, "~")
    m.rect(23, 27, 23, 28, ".")
    m.rect(31, 14, 35, 18, ",")
    m.landmark("supertrees", 31, 14, 5, 5, count=7)
    m.landmark("wheel", 37, 20, 3, 2)
    m.park(2, 14, 7, 18, [(2, 14), (7, 14), (4, 16), (2, 18), (7, 18)])
    stops(m, [("a", 30, 16, "Supertree Grove"), ("b", 4, 1, "Hawker Centre"), ("c", 20, 19, "Bay Promenade"),
              ("d", 11, 7, "Chili Crab Kitchen"), ("e", 38, 19, "Flyer Wheel"), ("f", 26, 13, "Mega Mall Row"),
              ("g", 1, 22, "Shophouse Cafe"), ("h", 40, 1, "Airport Express"), ("i", 12, 25, "Lantern Street"),
              ("j", 33, 28, "Spice Lane"), ("k", 17, 1, "Kaya Toast Cafe"), ("l", 8, 10, "Durian Stall"),
              ("m", 26, 28, "Riverside Quay"), ("n", 42, 10, "Night Safari Bus"), ("o", 33, 7, "Rooftop Pool")])
    m.start_at(15, 10)
    m.loop(1, 1, 42, 28)
    m.loop(8, 7, 30, 13)
    m.loop(30, 1, 42, 13)
    m.loop(1, 19, 15, 28)
    m.loop(30, 19, 42, 28)
    m.loop(15, 1, 23, 13)
    return m, dict(name="Singapore", drive_left=True, look=dict(
        facades=["#dfe7ee", "#c8d6e2", "#f2efe8", "#b8c9d6", "#e4dccf", "#a9bccb"], h_min=2.0, h_step=0.6,
        h_boost=3.0, center=(22, 12), sidewalk="#cfd2d4", water="#1f6f9a", harbour="#1a5e86", sky="#20305a",
        trees="palm", night_windows=True, neon=True))


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
