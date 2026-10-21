extends RefCounted
## The bot driver. It is the "every shift can be won" check in CI and the
## driver in every recorded clip.
##
## Each tick it:
## 1. Picks a job: the drop-off if someone's aboard, otherwise the request
##    with the best dollars per second (pickup drive + ride).
## 2. Follows the app's route by steering at a point a little way along it.
## 3. Picks a target speed: slow enough for the next corner and to stop at
##    the end (v^2 = 2ad), slower behind traffic, gentle with Nana.
## 4. Backs up and turns if it has been stuck against something.

const Riders := preload("res://scripts/riders.gd")

const CORNER_SPEED := 250.0
const DECEL := 800.0           # braking it plans with, a bit under the car's real BRAKE
const NANA_CAP := 430.0        # stays under Riders.SPEEDY with Nana aboard
const KEEP_RIGHT := 14.0
const OVERTAKE := 32.0
const PULL_RIGHT := 44.0

var stunts := false            # show-off routing over ramps (for videos)
var reckless := false          # full speed everywhere, no manners (for funny footage)
var rookie := false             # drive like a new player on a keyboard (feel tests)
var _rk_steer := 0.0
var _rk_think := 0.0
var _rk_uturn := 0.0
var _rk_stuck := 0.0
var hunt := false              # chase down and ram the getaway car / motorcade (for videos)
var _target := Vector2i(-1, -1)
var _path: Array = []
var _repath := 0.0
var _stuck := 0.0
var _reverse := 0.0
var _rev_steer := 1.0


func drive(game) -> Dictionary:
	if rookie:
		return _drive_rookie(game)
	var car = game.car
	var city = game.city
	var dt := 1.0 / 60.0
	var prey: Dictionary = _prey(game) if hunt else {}
	var here0: Vector2i = city.tile_of(car.position)
	var target := _choose(game)
	if not prey.is_empty():
		# Intercept: find where it will be by the time we can get there
		# (route length / our speed, refined a few times), and go there.
		var meet: Vector2 = prey.pos
		for k in 4:
			var secs: float = city.route(here0, city.tile_of(meet)).size() * city.TILE / 560.0
			meet = game.traffic.future_pos(prey, secs + 0.6)
		target = city.tile_of(meet)
		if not city.is_road(target):
			target = city.tile_of(prey.pos)
	_repath -= dt
	var here: Vector2i = city.tile_of(car.position)
	if target != _target or _repath <= 0.0 or _path.is_empty():
		_target = target
		_repath = 0.25
		_path = city.route(here, target, stunts) if target.x >= 0 else []

	var out := {"throttle": 0.0, "steer": 0.0, "drift": false}
	if _path.is_empty():
		out.throttle = -1.0
		return out

	var pts: Array = [car.position]
	for i in range(1, _path.size()):
		pts.append(city.center(_path[i]))
	var v: float = car.forward_speed()

	# Steer at a point `look` px along the route.
	var look := 70.0 + 0.3 * absf(v)
	var aim: Vector2 = pts.back()
	var walked := 0.0
	for i in range(1, pts.size()):
		var seg: float = pts[i - 1].distance_to(pts[i])
		if walked + seg >= look:
			aim = pts[i - 1].lerp(pts[i], (look - walked) / seg)
			break
		walked += seg
	# Keep a little right of the centre line, clear of oncoming traffic, or
	# pull out left to overtake.
	var lane: Array = _traffic(game, absf(v))
	var to_aim: Vector2 = (aim - car.position).normalized()
	aim += Vector2(-to_aim.y, to_aim.x) * float(lane[0])
	# Ram only from the front or side: from behind we'd hit the cruisers first.
	var ramming: bool = not prey.is_empty() and car.position.distance_to(prey.pos) < 280.0 \
			and (car.position - prey.pos).dot(prey.dir) > -30.0
	if ramming:
		aim = prey.pos + prey.dir * prey.speed * 0.25   # lead the target a little
	var diff := wrapf((aim - car.position).angle() - car.heading, -PI, PI)
	out.steer = clampf(diff * 2.5, -1.0, 1.0)
	if ramming and absf(diff) < 1.2:
		out.throttle = 1.0
		return out

	# Three-point turn: if the route is behind us, or we've been nosed into a
	# wall, back up steering the "wrong" way, which swings the nose round.
	if _reverse > 0.0:
		_reverse -= dt
		if absf(diff) < 0.8:
			_reverse = 0.0
		else:
			out.throttle = -1.0
			out.steer = _rev_steer
			return out
	if car.speed() < 25.0 and not _arriving(game):
		_stuck += dt
	else:
		_stuck = 0.0
	if _stuck > 0.8 or (absf(diff) > 2.0 and absf(v) < 140.0):
		_stuck = 0.0
		_reverse = 1.2
		_rev_steer = -signf(diff) if diff != 0.0 else 1.0
		out.throttle = -1.0
		out.steer = _rev_steer
		return out

	# Speed: limited by the next real corner and by the stop at the end.
	var want: float = 740.0
	var dist := 0.0
	for i in range(1, pts.size()):
		dist += pts[i - 1].distance_to(pts[i])
		if i + 1 < pts.size():
			var d1: Vector2 = (pts[i] - pts[i - 1]).normalized()
			var d2: Vector2 = (pts[i + 1] - pts[i]).normalized()
			if d1.dot(d2) < 0.7:
				var vc: float = CORNER_SPEED * (0.55 + 0.45 * car.grip_scale)   # slower in the rain
				want = minf(want, sqrt(vc * vc + 2.0 * DECEL * maxf(0.0, dist - 50.0)))
				break
	var total := 0.0
	for i in range(1, pts.size()):
		total += pts[i - 1].distance_to(pts[i])
	want = minf(want, sqrt(2.0 * DECEL * maxf(0.0, total - 25.0)) + 20.0)
	if absf(diff) > 1.0:
		want = minf(want, 200.0)
	if reckless:
		# Only slow down for the stop itself and for really sharp turns.
		want = maxf(want, 740.0) if total > 300.0 else want
		if absf(diff) > 1.3:
			want = minf(want, 260.0)
	else:
		if not game.ride.is_empty() and game.ride.kind == "nana":
			want = minf(want, NANA_CAP)
		want = minf(want, float(lane[1]))
	if stunts and _jump_ahead(game.city):
		want = 800.0   # flat out: anything slower ends in the canal
	out.throttle = clampf((want - v) / 90.0, -1.0, 1.0)
	return out


## A ramp with water right after it within the next few tiles of the route.
## A new player on a keyboard: steering is all-or-nothing, decided only every
## quarter second (reaction time); the gas stays down unless the turn is
## sharp, and they brake only when pointing the wrong way. Used to measure
## how often normal people hit walls (tests/feel.gd).
func _drive_rookie(game) -> Dictionary:
	var car = game.car
	var city = game.city
	var dt := 1.0 / 60.0
	var target := _choose(game)
	var here: Vector2i = city.tile_of(car.position)
	_repath -= dt
	if target != _target or _repath <= 0.0 or _path.is_empty():
		_target = target
		_repath = 0.25
		_path = city.route(here, target) if target.x >= 0 else []
	var out := {"throttle": 0.0, "steer": 0.0, "drift": false}
	if _path.size() < 2:
		out.throttle = -1.0
		return out
	var aim: Vector2 = city.center(_path[mini(2, _path.size() - 1)])
	var diff := wrapf((aim - car.position).angle() - car.heading, -PI, PI)
	_rk_think -= dt
	if _rk_think <= 0.0:
		_rk_think = 0.25
		_rk_steer = 0.0 if absf(diff) < 0.15 else signf(diff)
	out.steer = _rk_steer
	var to_goal: float = car.position.distance_to(city.center(target))
	# Facing the wrong way: a U-turn, committed to one direction, like people do.
	if absf(diff) > 2.0 and _rk_uturn == 0.0:
		_rk_uturn = signf(diff) if diff != 0.0 else 1.0
	if _rk_uturn != 0.0:
		if absf(diff) < 0.8:
			_rk_uturn = 0.0
		else:
			out.steer = _rk_uturn
			out.throttle = 0.6 if car.forward_speed() < 260.0 else -1.0
			if car.speed() < 15.0:
				_rk_stuck += dt
			if _rk_stuck > 0.5:      # nosed into a wall: back up a bit
				out.throttle = -1.0
				out.steer = -_rk_uturn
				if _rk_stuck > 1.2:
					_rk_stuck = 0.0
			return out
	# Pressing into something and not moving: back up, steering the other way.
	if car.speed() < 15.0 and absf(diff) < 2.0:
		_rk_stuck += dt
		if _rk_stuck > 0.8:
			out.throttle = -1.0
			out.steer = -_rk_steer
			if _rk_stuck > 1.6:
				_rk_stuck = 0.0
			return out
	else:
		_rk_stuck = 0.0
	if to_goal < 200.0:
		out.throttle = -1.0 if car.forward_speed() > 140.0 else 0.4   # roll in slowly
	elif absf(diff) > 1.0:
		out.throttle = 0.0
	else:
		out.throttle = 1.0
	return out


## The special vehicle worth ramming on camera: the getaway car (citizen's
## arrest) or a motorcade SUV (diplomatic incident).
func _prey(game) -> Dictionary:
	for npc in game.traffic.cars:
		if (npc.kind == "getaway" and npc.busted < 0.0) or (npc.kind == "suv" and npc.hit_cd <= 0.0):
			return npc
	return {}


func _jump_ahead(city) -> bool:
	for i in range(0, mini(_path.size() - 1, 6)):
		if city.cell(_path[i]) == "^" and city.cell(_path[i + 1]) == "~":
			return true
	return false


func _arriving(game) -> bool:
	return game.car.position.distance_to(game.city.center(_target)) < 100.0 if _target.x >= 0 else false


## Best value per second among requests, judged by route lengths.
func _choose(game) -> Vector2i:
	if not game.ride.is_empty():
		return game.ride.dest_tile
	var city = game.city
	var here: Vector2i = city.tile_of(game.car.position)
	var best := Vector2i(-1, -1)
	var best_score := -1.0
	for w in game.waiting:
		var to_pick: int = city.route_cost(here, w.tile)
		var ride_len: int = city.route_cost(w.tile, w.dest_tile)
		var secs := (to_pick + ride_len) * 0.22 + 2.0
		var pay: float = w.fare * (2.0 if w.surge else 1.0)
		var score := pay / secs
		if score > best_score:
			best_score = score
			best = w.tile
	return best


## Same-direction traffic in our path: overtake on the left if the other lane
## is clear of oncoming cars, else queue behind it. Oncoming cars stay in their
## lane, and waiting for them could deadlock (they wait for us too).
## Returns [lane offset to the right of the route, speed cap].
func _traffic(game, v: float) -> Array:
	var car = game.car
	var f: Vector2 = car.forward()
	# "right" here means the kerb side: the left in left-driving cities.
	var side: float = game.traffic.side
	var right := Vector2(-f.y, f.x) * side
	# Sirens nearby: hug the kerb so they pass down the middle (and no fines).
	for npc in game.traffic.cars:
		if npc.siren and npc.pos.distance_to(car.position) < 380.0:
			return [PULL_RIGHT * side, INF]
	var block := INF
	for npc in game.traffic.cars:
		if npc.dir.dot(f) < 0.3:
			continue
		var d: Vector2 = npc.pos - car.position
		var along := d.dot(f)
		var lat := d.dot(right)
		if along > 0.0 and along < 170.0 + 0.3 * v and lat > -24.0 and lat < 50.0:
			block = minf(block, along)
	if block == INF:
		return [KEEP_RIGHT * side, INF]
	for npc in game.traffic.cars:
		if npc.dir.dot(f) > -0.3:
			continue
		var d: Vector2 = npc.pos - car.position
		var along := d.dot(f)
		var lat := d.dot(right)
		if along > -40.0 and along < 500.0 and lat > -80.0 and lat < 10.0:
			return [KEEP_RIGHT * side, maxf(0.0, block - 60.0)]
	return [-OVERTAKE * side, INF]
