extends Node2D
## The city: a tile map written as text and drawn once in code (no art files).
## It also answers the questions the rest of the game asks: what is at this
## spot, is it solid, and which way to a stop (the in-app route).
##
## Every city's map, stops, traffic loops, landmarks and look live in
## cities.gd, which tools/maps/make_cities.py generates.
##
## Map letters:
##   #  office block (solid)         H  house on a lawn (solid)
##   .  road                         ,  grass (drivable, but slow)
##   :  sand (drivable, but slow)    L  landmark footprint (solid)
##   T  tree (solid)                 F  fountain (solid)
##   M  hill / rock (solid)          ~  water (solid, unless you jump it)
##   ^  ramp: hit it fast to fly
##   S  where the car starts         a-z  ride stops (road), named in stop_names
##   X  scramble crossing (road, painted with zebra stripes every way)

const Cities := preload("res://scripts/cities.gd")

const TILE := 128.0
const D := 96.0                 # the design grid the art is drawn in
const K := TILE / D

const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const INF := 1 << 30

const ASPHALT := Color("3d4250")
const LANE_PAINT := Color("f2d24b")
const SIDEWALK := Color("c9c2b4")
const GRASS := Color("78c25f")
const GRASS_DARK := Color("62a94c")
const WATER := Color("3b9fd6")
const ROOFS := [Color("e8875f"), Color("f0b75a"), Color("8fb8de"), Color("b39ddb"),
		Color("e57373"), Color("7fc8a9"), Color("f4e1a1"), Color("a1887f")]

var key := ""
var data: Dictionary = {}
var w := 0
var h := 0
var stops := {}        # letter -> Vector2i
var stop_names := {}   # letter -> landmark name
var loops: Array = []  # traffic circuits: corner tiles of closed rectangles along roads
var landmarks: Array = []
var drive_left := false   # traffic keeps left (London, Tokyo, Bangkok, Singapore)
var start := Vector2i.ZERO
var _rows: Array = []
var _fields := {}      # destination tile -> PackedInt32Array of route costs


func _init(city_key := "classic") -> void:
	key = city_key
	data = Cities.CITIES[key]
	stop_names = data.stops
	loops = data.loops
	landmarks = data.landmarks
	drive_left = bool(data.get("drive_left", false))
	_rows = data.map.duplicate()
	h = _rows.size()
	w = String(_rows[0]).length()
	for y in h:
		for x in w:
			var c := cell(Vector2i(x, y))
			if c == "S":
				start = Vector2i(x, y)
			elif stop_names.has(c):
				stops[c] = Vector2i(x, y)


# ---------------------------------------------------------------- queries

func cell(t: Vector2i) -> String:
	if t.x < 0 or t.y < 0 or t.x >= w or t.y >= h:
		return "#"
	return String(_rows[t.y])[t.x]


func tile_of(p: Vector2) -> Vector2i:
	return Vector2i(floori(p.x / TILE), floori(p.y / TILE))


func center(t: Vector2i) -> Vector2:
	return (Vector2(t) + Vector2(0.5, 0.5)) * TILE


func size_px() -> Vector2:
	return Vector2(w, h) * TILE


## Road-like: anything you can drive at full speed.
func is_road(t: Vector2i) -> bool:
	var c := cell(t)
	return c == "." or c == "^" or c == "S" or c == "X" or stop_names.has(c)


func is_solid(t: Vector2i, airborne := false) -> bool:
	var c := cell(t)
	if c == "~":
		return not airborne   # you can fly over water, just not drive on it
	return c == "#" or c == "H" or c == "T" or c == "F" or c == "L" or c == "M"


## How far a circle at `p` with radius `r` overlaps solid tiles, as the push
## that moves it back out. Trees are round; everything else is a box.
func push_out(p: Vector2, r: float, airborne := false) -> Vector2:
	var total := Vector2.ZERO
	var t := tile_of(p)
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var n := t + Vector2i(dx, dy)
			if not is_solid(n, airborne):
				continue
			var c := cell(n)
			if c == "T":
				var d := p - center(n)
				var reach := r + 30.0 * K
				if d.length() < reach and d.length() > 0.001:
					total += d.normalized() * (reach - d.length())
				continue
			var inset := 14.0 * K if c == "H" else 0.0
			var lo := Vector2(n) * TILE + Vector2(inset, inset)
			var hi := lo + Vector2(TILE, TILE) - Vector2(inset, inset) * 2.0
			var q := p.clamp(lo, hi)
			var d := p - q
			var dist := d.length()
			if dist < r:
				if dist < 0.001:
					d = p - (lo + hi) * 0.5   # centre is inside the box
					dist = 0.0
				total += d.normalized() * (r - dist)
	return total


# ---------------------------------------------------------------- routes

## Cost of driving onto a tile. The route sticks to roads, cuts across grass
## only when it saves a lot, and avoids ramps (the app is not reckless; you are).
func _cost(t: Vector2i, stunt := false) -> int:
	var c := cell(t)
	if c == "," or c == ":":
		return 4
	if c == "^":
		return 1 if stunt else 30
	if c == "~" and stunt and _jump_lane(t):
		return 1   # flown over, not driven
	if is_road(t):
		return 1
	return INF


## Water you can jump: a straight north-south run with a ramp at each end.
func _jump_lane(t: Vector2i) -> bool:
	var up := t
	while cell(up) == "~":
		up.y -= 1
	var down := t
	while cell(down) == "~":
		down.y += 1
	return cell(up) == "^" and cell(down) == "^"


## Cost-to-go from every tile to `dest`, computed once per destination with
## Dijkstra's algorithm. Costs are small integers, so a list of buckets (one
## per cost) replaces the usual priority queue.
func _field(dest: Vector2i, stunt := false) -> PackedInt32Array:
	var key := Vector3i(dest.x, dest.y, 1 if stunt else 0)
	if _fields.has(key):
		return _fields[key]
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(INF)
	dist[dest.y * w + dest.x] = 0
	var buckets := {0: [dest]}
	var c := 0
	var pending := 1
	while pending > 0:
		if not buckets.has(c):
			c += 1
			continue
		var list: Array = buckets[c]
		buckets.erase(c)
		for t in list:
			pending -= 1
			if dist[t.y * w + t.x] != c:
				continue   # a cheaper way here was found after this was queued
			for d in DIRS:
				var n: Vector2i = t + d
				var step := _cost(n, stunt)
				if step >= INF or n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
					continue
				var nc := c + step
				if nc < dist[n.y * w + n.x]:
					dist[n.y * w + n.x] = nc
					if not buckets.has(nc):
						buckets[nc] = []
					buckets[nc].append(n)
					pending += 1
	_fields[key] = dist
	return dist


## Tiles from `from` to `dest`, both included. Empty if there's no way.
## With `stunt`, the route happily takes ramps and jumps the canal (the bot's
## show-off mode for recording videos).
func route(from: Vector2i, dest: Vector2i, stunt := false) -> Array:
	var f := _field(dest, stunt)
	var out: Array = [from]
	var t := from
	if from.x < 0 or from.y < 0 or from.x >= w or from.y >= h or f[t.y * w + t.x] >= INF:
		# Off the drivable grid (e.g. nudged onto a kerb): start from the best neighbour.
		var best := INF
		for d in DIRS:
			var n: Vector2i = from + d
			if n.x >= 0 and n.y >= 0 and n.x < w and n.y < h and f[n.y * w + n.x] < best:
				best = f[n.y * w + n.x]
				t = n
		if best >= INF:
			return []
		out.append(t)
	var guard := w * h
	while t != dest and guard > 0:
		guard -= 1
		var best_n := t
		var best := f[t.y * w + t.x]
		for d in DIRS:
			var n: Vector2i = t + d
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if f[n.y * w + n.x] < best:
				best = f[n.y * w + n.x]
				best_n = n
		if best_n == t:
			break
		t = best_n
		out.append(t)
	return out


func route_cost(from: Vector2i, dest: Vector2i, stunt := false) -> int:
	return _field(dest, stunt)[from.y * w + from.x]


# ---------------------------------------------------------------- drawing

func _ready() -> void:
	z_index = -10
	queue_redraw()


## Drawn once. Godot keeps the list of draw commands, so a big static _draw
## costs nothing per frame until queue_redraw() is called again.
func _draw() -> void:
	var font := ThemeDB.fallback_font
	# Art is drawn in a 96 px design grid and scaled up to the real TILE size.
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(K, K))
	draw_rect(Rect2(Vector2(-12, -12) * D, Vector2(w + 24, h + 24) * D), Color("2a2d36"))
	for y in h:
		for x in w:
			_draw_ground(Vector2i(x, y))
	for y in h:
		for x in w:
			_draw_shadow(Vector2i(x, y))
	for y in h:
		for x in w:
			_draw_object(Vector2i(x, y))
	for letter in stops:
		var p := center(stops[letter]) / K
		var label: String = stop_names[letter]
		draw_string_outline(font, p + Vector2(-120, -30), label, HORIZONTAL_ALIGNMENT_CENTER,
				240, 15, 5, Color(0, 0, 0, 0.55))
		draw_string(font, p + Vector2(-120, -30), label, HORIZONTAL_ALIGNMENT_CENTER, 240, 15,
				Color("fff8e7"))


func _hash(t: Vector2i, salt := 0) -> int:
	return absi((t.x * 73856093) ^ (t.y * 19349663) ^ (salt * 83492791))


func _draw_ground(t: Vector2i) -> void:
	var c := cell(t)
	var r := Rect2(Vector2(t) * D, Vector2(D, D))
	if c == "," or c == "T" or c == "H" or c == ":":
		draw_rect(r, GRASS)
		for i in 4:
			var k := _hash(t, i)
			var p := r.position + Vector2(k % 90, (k / 97) % 90)
			draw_circle(p, 4.0, GRASS_DARK)
	elif c == "~":
		draw_rect(r, WATER)
		var k := _hash(t)
		for i in 2:
			var p := r.position + Vector2(10 + (k >> i) % 60, 22 + i * 44)
			draw_arc(p, 10, PI * 1.15, PI * 1.85, 6, Color(1, 1, 1, 0.35), 2.5)
			draw_arc(p + Vector2(20, 0), 10, PI * 1.15, PI * 1.85, 6, Color(1, 1, 1, 0.35), 2.5)
	elif c == "#":
		draw_rect(r, SIDEWALK)
	else:
		_draw_road(t, r)


func _draw_road(t: Vector2i, r: Rect2) -> void:
	var c := cell(t)
	draw_rect(r, ASPHALT)
	var road_l := is_road(t + Vector2i(-1, 0)) or cell(t + Vector2i(-1, 0)) == "F"
	var road_r := is_road(t + Vector2i(1, 0)) or cell(t + Vector2i(1, 0)) == "F"
	var road_u := is_road(t + Vector2i(0, -1)) or cell(t + Vector2i(0, -1)) == "F"
	var road_d := is_road(t + Vector2i(0, 1)) or cell(t + Vector2i(0, 1)) == "F"
	var water_lr := cell(t + Vector2i(-1, 0)) == "~" and cell(t + Vector2i(1, 0)) == "~"
	var water_ud := cell(t + Vector2i(0, -1)) == "~" and cell(t + Vector2i(0, 1)) == "~"
	var mid := r.get_center()
	if c == "F":
		pass
	elif water_lr:   # a bridge running north-south: railings on both sides
		draw_rect(Rect2(r.position, Vector2(8, D)), Color("9aa0ad"))
		draw_rect(Rect2(r.position + Vector2(D - 8, 0), Vector2(8, D)), Color("9aa0ad"))
	elif water_ud:
		draw_rect(Rect2(r.position, Vector2(D, 8)), Color("9aa0ad"))
		draw_rect(Rect2(r.position + Vector2(0, D - 8), Vector2(D, 8)), Color("9aa0ad"))
	# Centre-line dashes only on plain stretches, not at junctions or in the plaza.
	if c != "^":
		if road_l and road_r and not road_u and not road_d:
			for i in 2:
				draw_rect(Rect2(r.position + Vector2(8 + i * 48, D * 0.5 - 2), Vector2(30, 4)), LANE_PAINT)
		elif road_u and road_d and not road_l and not road_r:
			for i in 2:
				draw_rect(Rect2(r.position + Vector2(D * 0.5 - 2, 8 + i * 48), Vector2(4, 30)), LANE_PAINT)
	if c == "^":
		# Hazard-striped ramp with chevrons pointing over the water (or "up").
		draw_rect(r.grow(-6), Color("ffd23f"))
		for i in 4:
			var x0 := r.position.x + 6 + i * 22
			draw_line(Vector2(x0, r.position.y + 6), Vector2(x0 + 14, r.end.y - 6), Color("2a2d36"), 6)
		var dir := Vector2.UP
		if cell(t + Vector2i(0, 1)) == "~":
			dir = Vector2.DOWN
		for k in 2:
			var tip := mid + dir * (14 - k * 22)
			var side := Vector2(-dir.y, dir.x) * 22
			draw_polyline(PackedVector2Array([tip - dir * 16 + side, tip, tip - dir * 16 - side]),
					Color.WHITE, 7)
	if stop_names.has(c):
		# A pickup sign on the kerb: a pink pin on a post.
		var post := r.position + Vector2(D - 10, 12)
		draw_line(post, post + Vector2(0, 22), Color("d9d9d9"), 3)
		draw_circle(post, 8, Color("ff4fa3"))
		draw_circle(post, 3, Color.WHITE)


## Buildings cast a short shadow onto the ground to their lower right, which
## sells the "seen from a drone" look.
func _draw_shadow(t: Vector2i) -> void:
	var c := cell(t)
	if c != "#" and c != "H":
		return
	var r := Rect2(Vector2(t) * D, Vector2(D, D))
	if c == "H":
		r = r.grow(-14)
	if not is_solid(t + Vector2i(1, 0)) or c == "H":
		draw_rect(Rect2(Vector2(r.end.x, r.position.y + 14), Vector2(16, r.size.y)), Color(0, 0, 0, 0.22))
	if not is_solid(t + Vector2i(0, 1)) or c == "H":
		draw_rect(Rect2(Vector2(r.position.x + 14, r.end.y), Vector2(r.size.x, 16)), Color(0, 0, 0, 0.22))


func _draw_object(t: Vector2i) -> void:
	var c := cell(t)
	var r := Rect2(Vector2(t) * D, Vector2(D, D))
	match c:
		"#":
			_draw_building(t, r)
		"H":
			_draw_house(t, r)
		"T":
			draw_circle(r.get_center() + Vector2(8, 10), 34, Color(0, 0, 0, 0.2))
			draw_circle(r.get_center(), 34, Color("3f8f3a"))
			draw_circle(r.get_center() + Vector2(-9, -9), 20, Color("57ad4b"))
		"F":
			# The fountain is 2x2 tiles; draw it once from its top-left tile.
			if cell(t + Vector2i(-1, 0)) != "F" and cell(t + Vector2i(0, -1)) != "F":
				var mid := r.position + Vector2(D, D)
				draw_circle(mid, D * 0.95, Color("b8b2a6"))
				draw_circle(mid, D * 0.8, WATER)
				draw_circle(mid, 26, Color("d8f1ff"))
				draw_circle(mid, 12, Color("ffffff"))


func _draw_building(t: Vector2i, r: Rect2) -> void:
	# Each 2x2 chunk of office tiles is one building with its own roof colour.
	var chunk := Vector2i(t.x / 2, t.y / 2)
	var k := _hash(chunk, 7)
	var roof: Color = ROOFS[k % ROOFS.size()]
	var inner := r
	# Leave a strip of sidewalk wherever the block meets something else.
	var m := 10.0
	if cell(t + Vector2i(-1, 0)) != "#":
		inner.position.x += m
		inner.size.x -= m
	if cell(t + Vector2i(1, 0)) != "#":
		inner.size.x -= m
	if cell(t + Vector2i(0, -1)) != "#":
		inner.position.y += m
		inner.size.y -= m
	if cell(t + Vector2i(0, 1)) != "#":
		inner.size.y -= m
	draw_rect(inner, roof.darkened(0.25))
	draw_rect(Rect2(inner.position, inner.size - Vector2(0, 7)), roof)
	# A seam where two buildings meet inside a block.
	if t.x % 2 == 0 and cell(t + Vector2i(-1, 0)) == "#":
		draw_line(inner.position, inner.position + Vector2(0, inner.size.y), roof.darkened(0.45), 3)
	if t.y % 2 == 0 and cell(t + Vector2i(0, -1)) == "#":
		draw_line(inner.position, inner.position + Vector2(inner.size.x, 0), roof.darkened(0.45), 3)
	# Rooftop clutter: AC units, skylights, the odd garden.
	var d := _hash(t, 3) % 6
	var p := inner.position + Vector2(18 + _hash(t, 4) % 30, 16 + _hash(t, 5) % 30)
	match d:
		0, 1:
			draw_rect(Rect2(p, Vector2(22, 16)), Color("dcdcdc"))
			draw_circle(p + Vector2(11, 8), 5, Color("9a9a9a"))
		2:
			draw_rect(Rect2(p, Vector2(28, 18)), Color("bfe3f7"))
			draw_rect(Rect2(p, Vector2(28, 18)), Color(1, 1, 1, 0.6), false, 2)
		3:
			draw_circle(p + Vector2(10, 10), 9, Color("5fae4f"))
			draw_circle(p + Vector2(24, 14), 7, Color("5fae4f"))


func _draw_house(t: Vector2i, r: Rect2) -> void:
	var body := r.grow(-14)
	var roof: Color = [Color("c0504d"), Color("4f81bd"), Color("8064a2"), Color("f79646")][_hash(t) % 4]
	# Pitched roof seen from above: two halves, one in shade.
	draw_rect(Rect2(body.position, Vector2(body.size.x, body.size.y * 0.5)), roof)
	draw_rect(Rect2(body.position + Vector2(0, body.size.y * 0.5), Vector2(body.size.x, body.size.y * 0.5)),
			roof.darkened(0.25))
	draw_line(body.position + Vector2(0, body.size.y * 0.5), body.position + Vector2(body.size.x, body.size.y * 0.5),
			roof.darkened(0.5), 2)
	draw_rect(Rect2(body.position + Vector2(body.size.x - 22, 8), Vector2(10, 12)), Color("7a5c4a"))
