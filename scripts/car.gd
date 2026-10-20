extends Node2D
## The player's car: a hand-rolled arcade car model instead of a physics body.
##
## Why not RigidBody2D? Top-down arcade driving feels best when the rules are
## simple and explicit: push along the nose, and bleed off sideways speed
## ("grip"). Letting go of grip (the handbrake) is what makes a drift. It also
## keeps every run exactly repeatable, which the autopilot and tests rely on.
##
## Each physics tick the game sets throttle/steer/drift, calls step(), then
## reads `events` (crash, takeoff, land, splash, drift) to award tips.

const MAX_SPEED := 720.0     # px/s on asphalt
const GRASS_MAX := 340.0     # px/s on grass
const ACCEL := 700.0
const BRAKE := 1300.0
const REVERSE_MAX := 230.0
const DRAG := 0.25           # fraction of speed lost per second while coasting
const TURN := 3.1            # rad/s at full lock
const GRIP := 10.0           # how fast sideways speed dies (per second)
const DRIFT_GRIP := 1.4
const RADIUS := 15.0         # two circles, at +-AXLE along the car, collide with walls
const AXLE := 11.0
const JUMP_MIN_SPEED := 260.0
const CRASH_SPEED := 170.0   # impacts harder than this count as a crash
const LENGTH := 48.0
const WIDTH := 26.0

var vel := Vector2.ZERO
var heading := 0.0
var throttle := 0.0          # -1 brake/reverse .. 1 gas
var steer := 0.0             # -1 left .. 1 right
var drift := false           # handbrake held
var grip_scale := 1.0        # < 1 in the rain
var air := 0.0               # seconds left in the air
var air_len := 0.0
var drift_time := 0.0
var last_safe := Vector2.ZERO
var events: Array = []
var skids: Array = []        # recent rear-wheel positions while sliding (drawn by the game)
var _ramp_cd := 0.0
var _crash_cd := 0.0
var _flight := 0.0


func setup(p: Vector2, angle: float) -> void:
	position = p
	heading = angle
	rotation = angle
	last_safe = p
	vel = Vector2.ZERO


func forward() -> Vector2:
	return Vector2.from_angle(heading)


func speed() -> float:
	return vel.length()


func forward_speed() -> float:
	return vel.dot(forward())


func is_airborne() -> bool:
	return air > 0.0


## The two collision circles, front and back.
func circles() -> Array:
	var f := forward() * AXLE
	return [position + f, position - f]


func step(dt: float, city) -> void:
	events.clear()
	_ramp_cd -= dt
	_crash_cd -= dt
	if air > 0.0:
		_fly(dt, city)
		_update_visual()
		return

	var f := forward()
	var fs := vel.dot(f)
	var on_grass: bool = city.cell(city.tile_of(position)) == ","

	# Engine and brakes, along the nose.
	if throttle > 0.0:
		vel += f * throttle * ACCEL * dt
	elif throttle < 0.0:
		if fs > 15.0:
			vel -= f * minf(fs, BRAKE * -throttle * dt)
		elif fs > -REVERSE_MAX:
			vel += f * throttle * ACCEL * 0.6 * dt
	vel *= maxf(0.0, 1.0 - DRAG * dt)
	var cap := GRASS_MAX if on_grass else MAX_SPEED
	fs = vel.dot(f)
	if fs > cap:
		vel -= f * (fs - cap) * minf(1.0, 4.0 * dt)

	# Steering turns the nose; how fast depends on speed (no spinning on the
	# spot) and is a bit gentler at top speed so straights feel stable.
	var roll := clampf(fs / 160.0, -1.0, 1.0)
	var calm := 1.0 - 0.3 * clampf(absf(fs) / MAX_SPEED, 0.0, 1.0)
	heading += steer * TURN * roll * calm * (1.35 if drift else 1.0) * dt
	f = forward()

	# Grip: remove part of the sideways speed. Less grip = slide.
	var side := Vector2(-f.y, f.x)
	var lat := vel.dot(side)
	var g := (DRIFT_GRIP if drift else GRIP) * grip_scale
	vel -= side * lat * minf(1.0, g * dt)
	if drift:
		vel *= 1.0 - 0.3 * dt

	position += vel * dt
	_collide(city, false)

	# Drifts are scored by how long the car really slides, not button time.
	var sliding := absf(vel.dot(side)) > 110.0 and speed() > 200.0
	if sliding:
		drift_time += dt
		skids.append(position - f * 16.0)
		if skids.size() > 400:
			skids.pop_front()
	elif drift_time > 0.0:
		if drift_time > 0.6:
			events.append({"type": "drift", "secs": drift_time})
		drift_time = 0.0
	if not sliding and not skids.is_empty() and skids.back() != Vector2.INF:
		skids.append(Vector2.INF)   # a break in the skid line

	var t: Vector2i = city.tile_of(position)
	if city.cell(t) == "^" and _ramp_cd <= 0.0 and fs > JUMP_MIN_SPEED:
		air = 0.3 + fs / 1400.0
		air_len = air
		_flight = 0.0
		events.append({"type": "takeoff"})
	elif city.is_road(t) and city.cell(t) != "^":
		last_safe = position
	_update_visual()


func _fly(dt: float, city) -> void:
	air -= dt
	_flight += dt
	position += vel * dt
	_collide(city, true)
	if air > 0.0:
		return
	air = 0.0
	_ramp_cd = 0.6   # don't relaunch off the ramp on the far bank
	if city.cell(city.tile_of(position)) == "~":
		events.append({"type": "splash"})
		position = last_safe
		vel = Vector2.ZERO
	else:
		events.append({"type": "land", "air": _flight})


func _collide(city, airborne: bool) -> void:
	var normal := Vector2.ZERO
	for i in 2:
		for c in circles():
			var push: Vector2 = city.push_out(c, RADIUS, airborne)
			if push != Vector2.ZERO:
				position += push
				normal += push
	if normal == Vector2.ZERO:
		return
	bounce(normal.normalized(), Vector2.ZERO)


## Shared by walls and traffic: reflect the part of the velocity going into
## the obstacle (minus the obstacle's own velocity), and report a crash if it
## was hard enough.
func bounce(n: Vector2, other_vel: Vector2) -> void:
	var rel := vel - other_vel
	var vn := rel.dot(n)
	if vn >= 0.0:
		return
	vel -= n * vn * 1.35
	vel *= 0.9
	if -vn > CRASH_SPEED and _crash_cd <= 0.0:
		_crash_cd = 0.6
		events.append({"type": "crash", "impact": -vn})


func _update_visual() -> void:
	rotation = heading
	var lift := 0.0
	if air > 0.0 and air_len > 0.0:
		lift = sin(PI * clampf(1.0 - air / air_len, 0.0, 1.0))
	scale = Vector2.ONE * (1.0 + 0.35 * lift)
	set_meta("lift", lift)
	queue_redraw()


func _draw() -> void:
	var lift: float = get_meta("lift", 0.0)
	# The shadow stays on the ground: offset in world space, so undo our rotation.
	var sh := (Vector2(6, 9) + Vector2(14, 22) * lift).rotated(-heading) / scale.x
	_body(sh, Color(0, 0, 0, 0.3 - 0.12 * lift), true)
	_body(Vector2.ZERO, Color("9be24a"), false)


func _body(off: Vector2, col: Color, shadow: bool) -> void:
	var hl := LENGTH * 0.5
	var hw := WIDTH * 0.5
	var pts := PackedVector2Array([
		Vector2(hl, -hw + 5), Vector2(hl - 4, -hw), Vector2(-hl + 3, -hw), Vector2(-hl, -hw + 4),
		Vector2(-hl, hw - 4), Vector2(-hl + 3, hw), Vector2(hl - 4, hw), Vector2(hl, hw - 5)])
	for i in pts.size():
		pts[i] += off
	draw_colored_polygon(pts, col)
	if shadow:
		return
	pts.append(pts[0])
	draw_polyline(pts, Color("2a2d36"), 2.0, true)
	# Windscreen, roof, rear window, and the app's glowing roof sign.
	draw_rect(Rect2(Vector2(5, -hw + 4), Vector2(9, WIDTH - 8)), Color("2c3e5c"))
	draw_rect(Rect2(Vector2(-12, -hw + 4), Vector2(17, WIDTH - 8)), Color("b8f07a"))
	draw_rect(Rect2(Vector2(-19, -hw + 5), Vector2(6, WIDTH - 10)), Color("2c3e5c"))
	draw_rect(Rect2(Vector2(-8, -5), Vector2(10, 10)), Color("ff4fa3"))
	draw_rect(Rect2(Vector2(-8, -5), Vector2(10, 10)), Color("2a2d36"), false, 1.5)
	# Headlights, and brake lights when slowing.
	draw_rect(Rect2(Vector2(hl - 3, -hw + 3), Vector2(3, 5)), Color("fff3a0"))
	draw_rect(Rect2(Vector2(hl - 3, hw - 8), Vector2(3, 5)), Color("fff3a0"))
	var braking := throttle < -0.1 or drift
	var tail := Color("ff2a3a") if braking else Color("8a1f28")
	draw_rect(Rect2(Vector2(-hl, -hw + 3), Vector2(3, 5)), tail)
	draw_rect(Rect2(Vector2(-hl, hw - 8), Vector2(3, 5)), tail)
