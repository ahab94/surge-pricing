extends Node2D
## World overlays drawn every frame from the game's state. Two copies exist:
## `top = false` sits under the cars (skid marks, surge zones, stops, the
## route line) and `top = true` sits over them (the big arrow, popups).

const Riders := preload("res://scripts/riders.gd")

const INK := Color("2a2d36")
const ROUTE := Color("37b7ff")
const SURGE := Color("ff4fa3")

var game
var top := false


func _process(_delta: float) -> void:
	queue_redraw()


func _draw() -> void:
	if game == null or game.car == null:
		return
	if top:
		_draw_arrow()
		_draw_popups()
	else:
		_draw_skids()
		_draw_surge()
		_draw_route()
		_draw_waiting()
		_draw_destination()


func _pulse(speed := 4.0) -> float:
	return 0.5 + 0.5 * sin(game.clock_time * speed)


func _draw_skids() -> void:
	var line := PackedVector2Array()
	for p in game.car.skids:
		if p == Vector2.INF:
			if line.size() > 1:
				draw_polyline(line, Color(0, 0, 0, 0.35), 7.0)
			line.clear()
		else:
			line.append(p)
	if line.size() > 1:
		draw_polyline(line, Color(0, 0, 0, 0.35), 7.0)


func _draw_surge() -> void:
	for z in game.surge_zones:
		var col := SURGE
		col.a = 0.12 + 0.08 * _pulse(3.0)
		draw_circle(z.pos, z.r, col)
		draw_arc(z.pos, z.r, 0, TAU, 64, Color(SURGE, 0.7), 5.0, true)
		var font := ThemeDB.fallback_font
		draw_string_outline(font, z.pos + Vector2(-100, 8), "SURGE x2", HORIZONTAL_ALIGNMENT_CENTER,
				200, 34, 8, INK)
		draw_string(font, z.pos + Vector2(-100, 8), "SURGE x2", HORIZONTAL_ALIGNMENT_CENTER, 200, 34, SURGE)


func _draw_route() -> void:
	var pts: PackedVector2Array = game.route_points
	if pts.size() < 2:
		return
	var col := ROUTE if not game.ride.is_empty() else Color(ROUTE, 0.45)
	draw_polyline(pts, Color(col, col.a * 0.35), 22.0, true)
	draw_polyline(pts, col, 8.0, true)


func _person(p: Vector2, col: Color, bob: float) -> void:
	var b := Vector2(0, -bob)
	draw_circle(p + b + Vector2(3, 4), 13, Color(0, 0, 0, 0.25))
	draw_circle(p + b, 13, col)
	draw_arc(p + b, 13, 0, TAU, 20, INK, 2.5, true)
	draw_circle(p + b + Vector2(0, -2), 6, Color("ffe0bd"))


func _draw_waiting() -> void:
	for w in game.waiting:
		var p: Vector2 = game.city.center(w.tile)
		var band: Color = [Color("4dbb5f"), Color("ffd23f"), Color("ff4d6d")][w.band]
		var r := 112.0
		draw_circle(p, r, Color(band, 0.18 + 0.1 * _pulse()))
		draw_arc(p, r, 0, TAU, 48, band, 4.0, true)
		var kind: Dictionary = Riders.KINDS[w.kind]
		_person(p, kind.color, 6.0 * _pulse(6.0))
		if w.surge:
			draw_string(ThemeDB.fallback_font, p + Vector2(-40, 44), "x2", HORIZONTAL_ALIGNMENT_CENTER,
					80, 22, SURGE)


func _draw_destination() -> void:
	if game.ride.is_empty():
		return
	var p: Vector2 = game.city.center(game.ride.dest_tile)
	var r := 124.0 + 8.0 * _pulse()
	draw_circle(p, r, Color(ROUTE, 0.18))
	for i in 12:
		var a: float = game.clock_time * 1.5 + i * TAU / 12.0
		draw_arc(p, r, a, a + TAU / 24.0, 4, ROUTE, 7.0)
	# A map pin.
	var pin := p + Vector2(0, -20 - 8 * _pulse(5.0))
	draw_colored_polygon(PackedVector2Array([pin + Vector2(-14, -18), pin + Vector2(14, -18), pin + Vector2(0, 10)]), ROUTE)
	draw_circle(pin + Vector2(0, -22), 16, ROUTE)
	draw_circle(pin + Vector2(0, -22), 6, Color.WHITE)


## Arcade-taxi style: a fat arrow orbiting the car, pointing where the route goes.
func _draw_arrow() -> void:
	var dir: Vector2 = game.arrow_dir
	if dir == Vector2.ZERO:
		return
	var riding: bool = not game.ride.is_empty()
	var col := Color("57e36b") if riding else Color("ffd23f")
	var base: Vector2 = game.car.position + dir * 62.0
	var side := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array([
		base + dir * 34, base + side * 26, base + side * 10, base - dir * 16 + side * 10,
		base - dir * 16 - side * 10, base - side * 10, base - side * 26])
	var shadow := PackedVector2Array()
	for q in pts:
		shadow.append(q + Vector2(4, 6))
	draw_colored_polygon(shadow, Color(0, 0, 0, 0.3))
	draw_colored_polygon(pts, col)
	pts.append(pts[0])
	draw_polyline(pts, INK, 3.0, true)


func _draw_popups() -> void:
	var font := ThemeDB.fallback_font
	for p in game.popups:
		var a: float = clampf(p.t / 0.4, 0.0, 1.0)
		var pos: Vector2 = p.pos + Vector2(-260, -(1.4 - p.t) * 50.0)
		var size: int = p.size
		draw_string_outline(font, pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, 520, size, 9, Color(INK, a))
		draw_string(font, pos, p.text, HORIZONTAL_ALIGNMENT_CENTER, 520, size, Color(p.color, a))
