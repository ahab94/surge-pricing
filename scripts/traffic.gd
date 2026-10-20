extends Node2D
## City traffic. Each car drives a fixed loop (city.gd LOOPS) in the right-hand
## lane. Cars brake for the player and for cars ahead, so queues form instead
## of cars driving through each other. Everything is decided from positions
## alone, so a replay of the same inputs plays out exactly the same.

const LANE := 32.0           # distance from the road's centre line to a lane
const LENGTH := 46.0
const WIDTH := 24.0
const RADIUS := 13.0         # two circles per car, at +-AXLE along it
const AXLE := 11.0
const COLORS := [Color("e74c3c"), Color("3498db"), Color("f1c40f"), Color("ecf0f1"),
		Color("9b59b6"), Color("e67e22"), Color("1abc9c"), Color("34495e")]

var cars: Array = []         # dicts, see _add_car


func setup(city, spec: Array, speed: float) -> void:
	cars.clear()
	for entry in spec:
		var corners: Array = city.LOOPS[int(entry[0])].duplicate()
		if entry[2]:
			corners.reverse()
		var path := _lane_path(city, corners)
		var total := 0.0
		for i in path.size():
			total += path[i].distance_to(path[(i + 1) % path.size()])
		var n := int(entry[1])
		for k in n:
			_add_car(path, total, total * k / n, speed)
	for car in cars:
		_place(car)
		car.angle = car.dir.angle()
	queue_redraw()


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


func _add_car(path: PackedVector2Array, total: float, s: float, speed: float) -> void:
	cars.append({
		"path": path, "total": total, "s": s, "top": speed, "speed": speed,
		"pos": Vector2.ZERO, "dir": Vector2.RIGHT, "angle": 0.0,
		"color": COLORS[cars.size() % COLORS.size()],
		"honk": 0.0,        # seconds left on the angry honk bubble
		"close": false,     # player is whizzing past right now
		"touched": false,   # ...and has touched this car during the pass
		"index": cars.size(),
	})


func _place(car: Dictionary) -> void:
	var path: PackedVector2Array = car.path
	var s: float = fposmod(car.s, car.total)
	for i in path.size():
		var a := path[i]
		var b := path[(i + 1) % path.size()]
		var seg := a.distance_to(b)
		if s <= seg:
			car.dir = (b - a) / seg
			car.pos = a + car.dir * s
			# Turn smoothly over the last bit of each side instead of snapping.
			var target: float = car.dir.angle()
			car.angle = lerp_angle(car.angle, target, 0.25) if car.speed > 0 else car.angle
			return
		s -= seg


## Moves every car. `player` is the player's car (may be null in tests).
func update(dt: float, player) -> void:
	for car in cars:
		var target: float = car.top
		if _blocked(car, player):
			target = 0.0
		var rate := 900.0 if target < car.speed else 300.0
		car.speed = move_toward(car.speed, target, rate * dt)
		car.s = fposmod(car.s + car.speed * dt, car.total)
		car.honk = maxf(0.0, car.honk - dt)
		_place(car)
	queue_redraw()


## Something in my lane just ahead? The player always counts. Other cars count
## if they go my way, or cross my path and were placed earlier (a fixed
## priority, so two cars at a crossing can never wait for each other forever).
func _blocked(car: Dictionary, player) -> bool:
	var dir: Vector2 = car.dir
	var right := _right(dir)
	if player != null and not player.is_airborne():
		var d: Vector2 = player.position - car.pos
		var along := d.dot(dir)
		if along > 0.0 and along < 95.0 and absf(d.dot(right)) < 28.0:
			return true
	for other in cars:
		if other == car:
			continue
		var d: Vector2 = other.pos - car.pos
		var along := d.dot(dir)
		if along <= 0.0 or along > 80.0 or absf(d.dot(right)) > 24.0:
			continue
		var same_way: bool = other.dir.dot(dir) > 0.5
		if same_way or other.index < car.index:
			return true
	return false


func circles(car: Dictionary) -> Array:
	var f: Vector2 = car.dir * AXLE
	return [car.pos + f, car.pos - f]


func velocity(car: Dictionary) -> Vector2:
	return car.dir * car.speed


func _draw() -> void:
	for car in cars:
		draw_set_transform(car.pos + Vector2(5, 8), car.angle)
		draw_rect(Rect2(-LENGTH * 0.5, -WIDTH * 0.5, LENGTH, WIDTH), Color(0, 0, 0, 0.28))
		draw_set_transform(car.pos, car.angle)
		var col: Color = car.color
		draw_rect(Rect2(-LENGTH * 0.5, -WIDTH * 0.5, LENGTH, WIDTH), col)
		draw_rect(Rect2(-LENGTH * 0.5, -WIDTH * 0.5, LENGTH, WIDTH), Color("2a2d36"), false, 2.0)
		draw_rect(Rect2(4, -WIDTH * 0.5 + 3, 9, WIDTH - 6), Color("2c3e5c"))
		draw_rect(Rect2(-12, -WIDTH * 0.5 + 3, 16, WIDTH - 6), col.lightened(0.2))
		draw_rect(Rect2(-18, -WIDTH * 0.5 + 4, 5, WIDTH - 8), Color("2c3e5c"))
		var tail := Color("ff2a3a") if car.speed < car.top * 0.6 else Color("8a1f28")
		draw_rect(Rect2(-LENGTH * 0.5, -WIDTH * 0.5 + 2, 3, 5), tail)
		draw_rect(Rect2(-LENGTH * 0.5, WIDTH * 0.5 - 7, 3, 5), tail)
	draw_set_transform(Vector2.ZERO, 0.0)
	var font := ThemeDB.fallback_font
	for car in cars:
		if car.honk > 0.0:
			var p: Vector2 = car.pos + Vector2(-40, -34)
			draw_string_outline(font, p, "HONK!", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, 6, Color("2a2d36"))
			draw_string(font, p, "HONK!", HORIZONTAL_ALIGNMENT_CENTER, 80, 18, Color("ffd23f"))
