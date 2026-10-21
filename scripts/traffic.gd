extends Node2D
## City traffic. Ordinary cars drive fixed loops (city.gd LOOPS) in the
## right-hand lane, braking for the player and for cars ahead. Every so often
## the game spawns a *special event*: a convoy of special vehicles that drives
## part of a loop and then leaves:
##   chase      a getaway car and two police cruisers, flat out, sirens on
##   ambulance  sirens on, fast; it slows behind you (and you get fined)
##   trash      a long garbage truck crawling along, stopping to collect
##   motorcade  escort bikes and black SUVs with little flags
## Siren vehicles drive down the middle of the road and ordinary cars pull
## over to the kerb for them, so they slip past without crashing.
## Everything is decided from positions alone, so replays are identical.

const LANE := 32.0           # distance from the road's centre line to a lane
const PULL_OVER := 22.0      # how far ordinary cars move toward the kerb
const SIREN_RANGE := 380.0   # how close a siren must be before cars pull over
const COLORS := [Color("e74c3c"), Color("3498db"), Color("f1c40f"), Color("ecf0f1"),
		Color("9b59b6"), Color("e67e22"), Color("1abc9c"), Color("34495e")]

## Vehicle shapes and behaviour. Lengths and widths are in px (the player's car is 48x26).
const KINDS := {
	"car": {"length": 46.0, "width": 24.0, "siren": false},
	"trash": {"length": 86.0, "width": 30.0, "siren": false, "color": Color("3f8f4f")},
	"ambulance": {"length": 60.0, "width": 28.0, "siren": true, "color": Color("f4f4f4")},
	"police": {"length": 48.0, "width": 25.0, "siren": true, "color": Color("1f2a44")},
	"getaway": {"length": 46.0, "width": 24.0, "siren": false, "color": Color("d62839")},
	"suv": {"length": 56.0, "width": 29.0, "siren": false, "color": Color("17181c")},
	"bike": {"length": 30.0, "width": 12.0, "siren": true, "color": Color("e8e8e8")},
}

## Special events. convoy = [kind, gap behind the leader in px]. center = drives
## down the middle (siren convoys). loops = which LOOPS it may use. dist = how
## far it drives before leaving (px; 0 = one full lap).
const EVENTS := {
	"chase": {"alert": "Police chase in progress!", "speed": 600.0, "center": true, "loops": [0],
			"convoy": [["getaway", 0.0], ["police", 90.0], ["police", 170.0]], "dist": 0.0},
	"ambulance": {"alert": "Ambulance coming through. Pull over!", "speed": 470.0, "center": true,
			"loops": [0, 1, 3, 4], "convoy": [["ambulance", 0.0]], "dist": 0.0},
	"trash": {"alert": "Garbage truck on its rounds. Ew.", "speed": 150.0, "center": false,
			"loops": [1, 2, 4, 5], "convoy": [["trash", 0.0]], "dist": 4500.0},
	"motorcade": {"alert": "VIP motorcade! Do NOT touch it.", "speed": 220.0, "center": true,
			"loops": [1, 0], "dist": 6500.0,
			"convoy": [["bike", 0.0], ["suv", 55.0], ["suv", 125.0], ["suv", 195.0], ["bike", 255.0]]},
}

var cars: Array = []         # dicts, see _add_car
var _paths := {}             # [loop, reversed] -> [lane path, total length]
var _next_id := 0


func setup(city, spec: Array, speed: float) -> void:
	cars.clear()
	_paths.clear()
	for entry in spec:
		var lp: Array = _path_for(city, int(entry[0]), bool(entry[2]))
		var n := int(entry[1])
		for k in n:
			_add_car("car", lp[0], lp[1], lp[1] * k / n, speed)
	for car in cars:
		_place(car)
		car.angle = car.dir.angle()
	queue_redraw()


func _path_for(city, loop: int, reversed: bool) -> Array:
	var key := Vector2i(loop, 1 if reversed else 0)
	if not _paths.has(key):
		var corners: Array = city.LOOPS[loop].duplicate()
		if reversed:
			corners.reverse()
		var path := _lane_path(city, corners)
		var total := 0.0
		for i in path.size():
			total += path[i].distance_to(path[(i + 1) % path.size()])
		_paths[key] = [path, total]
	return _paths[key]


## Shift each corner of the loop into the right-hand lane. For a square
## corner the offset is the sum of the "right" vectors of the two roads.
func _lane_path(city, corners: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	var n := corners.size()
	for i in n:
		var a: Vector2 = city.center(corners[(i - 1 + n) % n])
		var b: Vector2 = city.center(corners[i])
		var c: Vector2 = city.center(corners[(i + 1) % n])
		var din := (b - a).normalized()
		var dout := (c - b).normalized()
		out.append(b + (_right(din) + _right(dout)) * LANE)
	return out


func _right(d: Vector2) -> Vector2:
	return Vector2(-d.y, d.x)   # y points down on screen, so this is the driver's right


func _add_car(kind: String, path: PackedVector2Array, total: float, s: float, speed: float) -> Dictionary:
	var info: Dictionary = KINDS[kind]
	var car := {
		"kind": kind, "id": _next_id, "special": kind != "car",
		"path": path, "total": total, "s": s, "top": speed, "speed": speed,
		"pos": Vector2.ZERO, "dir": Vector2.RIGHT, "angle": 0.0,
		"length": info.length, "width": info.width, "siren": info.siren,
		"color": info.get("color", COLORS[_next_id % COLORS.size()]),
		"shift": 0.0,       # sideways offset from the lane (pulling over, or centre line)
		"honk": 0.0,        # seconds left on the angry honk bubble
		"close": false,     # player is whizzing past right now
		"touched": false,   # ...and has touched this car during the pass
		"hit_cd": 0.0,      # cooldown so one bump is one fine
		"blocked_t": 0.0,   # how long the player has been in its way
		"left": INF,        # specials: distance left before they leave
		"busted": -1.0,     # chase: seconds since the getaway car was caught
		"cycle": 0.0,       # garbage truck: time into its drive/collect cycle
		"event": "",        # which special event it belongs to
		"index": _next_id,
	}
	_next_id += 1
	cars.append(car)
	return car


# ---------------------------------------------------------------- special events

func event_active() -> bool:
	for car in cars:
		if car.special:
			return true
	return false


## Starts a special event on one of its loops, at a point away from the player
## so it drives into view instead of popping up next to you.
func spawn_event(name: String, city, rng: RandomNumberGenerator, player_pos: Vector2, near := 1100.0) -> void:
	var ev: Dictionary = EVENTS[name]
	var loops: Array = ev.loops
	var lp: Array = _path_for(city, int(loops[rng.randi() % loops.size()]), rng.randf() < 0.5)
	var total: float = lp[1]
	var s0 := 0.0
	var best := -1.0
	for k in 16:
		var s := total * k / 16.0
		var d := _point_at(lp[0], total, s).distance_to(player_pos)
		if d > near and d < near + 1300.0:
			s0 = s
			best = d
			break
		if d > best:
			best = d
			s0 = s
	var dist: float = ev.dist if ev.dist > 0.0 else total
	for member in ev.convoy:
		var car := _add_car(member[0], lp[0], total, s0 - float(member[1]), ev.speed)
		car.left = dist
		car.shift = -LANE if ev.center else 0.0
		car.event = name
		_place(car)
		car.angle = car.dir.angle()


## The getaway car was rammed: the whole chase stops, then leaves.
func bust(chase_car: Dictionary) -> void:
	for car in cars:
		if car.get("event", "") == "chase":
			car.busted = 0.0
	chase_car.honk = 1.5


func _point_at(path: PackedVector2Array, total: float, s: float) -> Vector2:
	s = fposmod(s, total)
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var seg := a.distance_to(b)
		if s <= seg:
			return a + (b - a) / seg * s
		s -= seg
	return path[0]


func _place(car: Dictionary) -> void:
	var path: PackedVector2Array = car.path
	var s: float = fposmod(car.s, car.total)
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var seg := a.distance_to(b)
		if s <= seg:
			car.dir = (b - a) / seg
			car.pos = a + car.dir * s + _right(car.dir) * car.shift
			# Turn smoothly over the last bit of each side instead of snapping.
			var target: float = car.dir.angle()
			car.angle = lerp_angle(car.angle, target, 0.25) if car.speed > 0 else car.angle
			return
		s -= seg


# ---------------------------------------------------------------- moving

## Moves every vehicle. `player` is the player's car (may be null in tests).
func update(dt: float, player) -> void:
	var sirens: Array = cars.filter(func(c) -> bool: return c.siren)
	var gone: Array = []
	for car in cars:
		var target: float = car.top
		car.hit_cd = maxf(0.0, car.hit_cd - dt)
		car.honk = maxf(0.0, car.honk - dt)
		match car.kind:
			"car":
				# Pull over for sirens: slide toward the kerb and stop.
				var pull := false
				for sv in sirens:
					if sv.pos.distance_to(car.pos) < SIREN_RANGE:
						pull = true
						break
				car.shift = move_toward(car.shift, PULL_OVER if pull else 0.0, 60.0 * dt)
				if pull or _blocked(car, player):
					target = 0.0
			"trash":
				# Drive 7 s, stop 3 s to collect, repeat.
				car.cycle = fmod(car.cycle + dt, 10.0)
				if car.cycle > 7.0 or _blocked(car, player):
					target = 0.0
			"getaway", "police":
				pass   # a chase stops for nothing...
			_:
				# Ambulances and motorcades slow down behind you, and the game
				# fines you for every second you're in the way.
				if _player_ahead(car, player, 140.0, 30.0):
					target = 0.0
					car.blocked_t += dt
				else:
					car.blocked_t = 0.0
		if car.busted >= 0.0:
			car.busted += dt
			target = 0.0
			if car.busted > 4.0:
				gone.append(car)
		var rate := 900.0 if target < car.speed else 300.0
		car.speed = move_toward(car.speed, target, rate * dt)
		var ds: float = car.speed * dt
		car.s = fposmod(car.s + ds, car.total)
		if car.special:
			car.left -= ds
			if car.left <= 0.0:
				gone.append(car)
		_place(car)
	for car in gone:
		cars.erase(car)
	queue_redraw()


func _player_ahead(car: Dictionary, player, reach: float, half_width: float) -> bool:
	if player == null or player.is_airborne():
		return false
	var d: Vector2 = player.position - car.pos
	var along := d.dot(car.dir)
	return along > 0.0 and along < car.length * 0.5 + reach and absf(d.dot(_right(car.dir))) < half_width


## Something in my lane just ahead? The player always counts. Other cars count
## if they go my way, or cross my path and were placed earlier (a fixed
## priority, so two cars at a crossing can never wait for each other forever).
func _blocked(car: Dictionary, player) -> bool:
	var dir: Vector2 = car.dir
	var right := _right(dir)
	if _player_ahead(car, player, 72.0, 28.0):
		return true
	var reach: float = car.length * 0.5 + 57.0
	for other in cars:
		if other == car:
			continue
		var d: Vector2 = other.pos - car.pos
		var along := d.dot(dir)
		if along <= 0.0 or along > reach + other.length * 0.5 - 23.0 or absf(d.dot(right)) > 24.0:
			continue
		var same_way: bool = other.dir.dot(dir) > 0.5
		if same_way or other.index < car.index:
			return true
	return false


## Collision circles along the vehicle, enough to cover long trucks.
func circles(car: Dictionary) -> Array:
	var r := radius(car)
	var half: float = maxf(0.0, car.length * 0.5 - r)
	var n := maxi(2, ceili(car.length / 22.0))
	var out: Array = []
	for i in n:
		out.append(car.pos + car.dir * lerpf(-half, half, float(i) / (n - 1)))
	return out


func radius(car: Dictionary) -> float:
	return car.width * 0.5 + 1.0


func velocity(car: Dictionary) -> Vector2:
	return car.dir * car.speed


# ---------------------------------------------------------------- flat 2D drawing (--flat)

func _draw() -> void:
	var flash := int(Time.get_ticks_msec() / 150) % 2 == 0
	for car in cars:
		var l: float = car.length
		var w: float = car.width
		draw_set_transform(car.pos + Vector2(5, 8), car.angle)
		draw_rect(Rect2(-l * 0.5, -w * 0.5, l, w), Color(0, 0, 0, 0.28))
		draw_set_transform(car.pos, car.angle)
		var col: Color = car.color
		draw_rect(Rect2(-l * 0.5, -w * 0.5, l, w), col)
		draw_rect(Rect2(-l * 0.5, -w * 0.5, l, w), Color("2a2d36"), false, 2.0)
		draw_rect(Rect2(l * 0.5 - 19, -w * 0.5 + 3, 9, w - 6), Color("2c3e5c"))
		if car.siren:
			draw_rect(Rect2(-4, -w * 0.5 + 2, 8, w * 0.5 - 2), Color("ff2a3a") if flash else Color("2a6bff"))
			draw_rect(Rect2(-4, 0, 8, w * 0.5 - 2), Color("2a6bff") if flash else Color("ff2a3a"))
	draw_set_transform(Vector2.ZERO, 0.0)
	var font := ThemeDB.fallback_font
	for car in cars:
		if car.honk > 0.0:
			var p: Vector2 = car.pos + Vector2(-40, -34)
			draw_string_outline(font, p, "HONK!", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, 6, Color("2a2d36"))
			draw_string(font, p, "HONK!", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color("ffd23f"))
