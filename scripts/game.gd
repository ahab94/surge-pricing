extends Node2D
## Surge Pricing. This script runs a shift: it builds the city, traffic and
## car, spawns ride requests, handles pickups and drop-offs, turns your
## driving into tips, moods, reviews and a driver rating, and decides when the
## shift is won or lost. It also owns the camera, input, saves and dev flags.
##
## Dev flags go after `--` on the command line, e.g.
##   godot --path . -- --level=2 --autopilot --exit-on-end
## See CLAUDE.md for the full list.

const Levels := preload("res://scripts/levels.gd")
const Riders := preload("res://scripts/riders.gd")
const City := preload("res://scripts/city.gd")
const Car := preload("res://scripts/car.gd")
const Traffic := preload("res://scripts/traffic.gd")
const Fx := preload("res://scripts/fx.gd")
const Autopilot := preload("res://scripts/autopilot.gd")
const Hud := preload("res://scripts/hud.gd")
const View3D := preload("res://scripts/view3d.gd")
const Sound := preload("res://scripts/sound.gd")

const SAVE_PATH := "user://progress.cfg"
const PICKUP_RADIUS := 112.0
const DROP_RADIUS := 124.0
const STOP_SPEED := 170.0        # px/s: slow enough to board or get out (a slow roll is fine)
const RATING_WINDOW := 20        # the rating is the average of the last 20 reviews
const START_REVIEWS := [5, 5, 5, 5, 4, 5, 5, 4, 5, 5, 5, 5, 5, 5, 5, 5, 4, 5, 5, 4]
const NEAR_MISS := 78.0          # px between centres that counts as a close call
const NEAR_MISS_SPEED := 280.0
const SURGE_MOVE := 20.0         # seconds between surge zone moves
const SURGE_RADIUS := 440.0
const SPECIAL_CLOSE := {
	"getaway": "WHOA, A CAR CHASE!", "police": "CLOSE CALL: COPS!", "ambulance": "CLOSE CALL: AMBULANCE!",
	"trash": "SQUEEZED PAST THE TRASH!", "suv": "BUZZED THE VIP!", "bike": "BUZZED THE VIP!",
}
const VIEW := 760.0              # world px across the short side of the screen

enum State { MENU, DRIVING, WON, FAILED }

var state := State.MENU
var level_index := 0
var level: Dictionary = {}
var world: Node2D
var city
var car
var traffic
var camera: Camera2D
var hud
var bot
var view                         # the angled 3D view; null with --flat
var sound
var _last_tick := 99
var rng := RandomNumberGenerator.new()
var review_rng := RandomNumberGenerator.new()
var save_enabled := true
var best_stars := {}
var best_times := {}

# The shift
var money := 0.0
var clock := 0.0                 # shift clock, counts down
var elapsed := 0.0               # time since the first press of the gas
var started := false
var reviews: Array = []
var rides_done := 0
var bails := 0
var crashes := 0
var waiting: Array = []          # open ride requests, see _spawn_request
var ride: Dictionary = {}        # the passenger on board, or empty
var surge_zones: Array = []
var fail_reason := ""
var result_stars := 0

# Read by fx.gd
var route_points := PackedVector2Array()
var arrow_dir := Vector2.ZERO
var popups: Array = []
var splashes: Array = []         # {pos, t}: water splashes playing out
var splash_hold := 0.0           # seconds the car stays sunk before it respawns
var splash_pos := Vector2.ZERO
var bubble_text := ""           # what the passenger is shouting right now
var bubble_t := 0.0
var _say_cd := 0.0
var _mutter_t := 0.0
var say_rng := RandomNumberGenerator.new()
var look_at_tile := Vector2i(-1, -1)   # --look-at=x,y (dev): camera frames this tile
var no_cutaway := false          # --no-cutaway (dev): draw buildings solid, for comparisons
var cam_scale := 1.0             # 3D camera distance multiplier (--close-cam for videos)
var clock_time := 0.0

var _route_timer := 0.0
var _special_timer := 0.0
var _special_index := 0
var _chaser_t := 0.0
var _surge_timer := 0.0
var _sim_time := 0.0
var _flags := {}


func _ready() -> void:
	_setup_input()
	_parse_flags()
	sound = Sound.new()
	add_child(sound)
	if _flags.has("no-music"):
		sound.music_on = false
	if _flags.has("speed"):
		Engine.time_scale = float(_flags.speed)   # footage: faster pace, still every frame drawn
	if _flags.has("look-at"):
		var xy := String(_flags["look-at"]).split(",")
		look_at_tile = Vector2i(int(xy[0]), int(xy[1]))
	no_cutaway = _flags.has("no-cutaway")
	if _flags.has("close-cam"):
		cam_scale = 0.68
	_load_progress()

	# The game simulates in 2D; view3d.gd draws it in 3D. --flat keeps the
	# original top-down 2D drawing (handy for debugging).
	if not _flags.has("flat"):
		view = View3D.new()
		add_child(view)
		view.build_city(City.new(String(Levels.get_level(0).get("city", "classic"))))

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 7.0
	add_child(camera)

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	add_child(hud_layer)
	hud = Hud.new()
	hud.show_touch = DisplayServer.is_touchscreen_available() or _flags.has("touch")
	hud_layer.add_child(hud)
	hud.retry_pressed.connect(func() -> void: start_level(level_index))
	hud.next_pressed.connect(_next_level)
	hud.menu_pressed.connect(show_menu)
	hud.level_chosen.connect(start_level)
	if _flags.has("touch"):
		Input.emulate_touch_from_mouse = true

	get_window().size_changed.connect(_fit_base_size)
	_fit_base_size()
	if _flags.has("level"):
		start_level(int(_flags.level))
	else:
		show_menu()


# ---------------------------------------------------------------- shift setup

func start_level(i: int) -> void:
	_clear_world()
	level_index = clampi(i, 0, Levels.count() - 1)
	level = Levels.get_level(level_index)
	rng.seed = int(level.seed)
	review_rng.seed = int(level.seed) * 7 + 1
	say_rng.seed = int(level.seed) * 13 + 5
	bubble_text = ""
	bubble_t = 0.0
	_say_cd = 0.0

	world = Node2D.new()
	world.name = "World"
	add_child(world)
	move_child(world, 0)
	city = City.new(String(level.get("city", "classic")))
	world.add_child(city)
	var under := Fx.new()
	under.game = self
	world.add_child(under)
	traffic = Traffic.new()
	world.add_child(traffic)
	traffic.setup(city, level.traffic, float(level.traffic_speed), level.get("traffic_mix", {}), level.get("car_colors", []))
	car = Car.new()
	world.add_child(car)
	car.setup(city.center(city.start), -PI / 2.0)
	car.grip_scale = 0.6 if level.rain else 1.0
	var over := Fx.new()
	over.game = self
	over.top = true
	world.add_child(over)

	money = 0.0
	clock = float(level.clock)
	elapsed = 0.0
	started = false
	reviews = START_REVIEWS.duplicate()
	rides_done = 0
	bails = 0
	crashes = 0
	ride = {}
	waiting.clear()
	popups.clear()
	splashes.clear()
	splash_hold = 0.0
	surge_zones.clear()
	fail_reason = ""
	result_stars = 0
	_surge_timer = 0.0
	_special_timer = 0.0
	_special_index = 0
	_chaser_t = 0.0
	_route_timer = 0.0
	if level.surge:
		_move_surge()
	for k in int(level.waiting):
		_spawn_request()
	bot = Autopilot.new() if _flags.has("autopilot") else null
	# Driving aids are for people (and the rookie bot that imitates them).
	car.assist = (bot == null or _flags.has("rookie")) and not _flags.has("no-assist")
	if bot:
		bot.stunts = _flags.has("stunts")
		bot.hunt = _flags.has("hunt")
		bot.reckless = _flags.has("reckless")
		bot.rookie = _flags.has("rookie")
	state = State.DRIVING

	var s: Vector2 = city.size_px()
	camera.limit_left = 0
	camera.limit_top = 0
	camera.limit_right = int(s.x)
	camera.limit_bottom = int(s.y)
	camera.position = car.position
	camera.zoom = Vector2.ONE * _zoom()
	camera.reset_smoothing()
	_update_route()
	if view:
		world.visible = false
		view.on_level(self)
	hud.show_level(level_index, level)
	sound.silence_loops()
	sound.music(city.key)
	sound.loop("rain", -4.0 if level.rain else -80.0)
	sound.play("ui", -6.0)
	_last_tick = 99
	if _flags.has("clean"):
		hud.hide_tip()   # footage for videos: captions replace the tip
	_update_hud()


func _clear_world() -> void:
	if world:
		remove_child(world)
		world.queue_free()
	world = null
	car = null
	city = null
	traffic = null


func show_menu() -> void:
	_clear_world()
	state = State.MENU
	hud.show_menu(best_stars, Levels.LEVELS)
	sound.silence_loops()
	sound.music("menu")


func _next_level() -> void:
	if level_index + 1 < Levels.count():
		start_level(level_index + 1)
	else:
		show_menu()


# ---------------------------------------------------------------- ride requests

## A new passenger appears at a free stop, wanting to go to another stop.
## Colour band (green/yellow/red) says how far, like the fare will.
func _spawn_request() -> void:
	var taken := {}
	for w in waiting:
		taken[w.letter] = true
	if not ride.is_empty():
		taken[ride.dest] = true
	var letters: Array = []
	for letter in city.stops:
		if taken.has(letter):
			continue
		if car != null and city.center(city.stops[letter]).distance_to(car.position) < 5.0 * City.TILE:
			continue   # not right on top of the car: make the player drive a bit
		letters.append(letter)
	if letters.is_empty():
		return
	var letter: String = letters[rng.randi() % letters.size()]
	var dests: Array = []
	for d in city.stops:
		if d != letter:
			dests.append(d)
	var dest: String = dests[rng.randi() % dests.size()]
	var kind := _pick_kind()
	if _flags.has("rider"):
		kind = String(_flags.rider)   # footage: everyone is Nana (the rng is still consumed, so rides match)
	var info: Dictionary = Riders.KINDS[kind]
	var tiles: int = city.route(city.stops[letter], city.stops[dest]).size()
	waiting.append({
		"letter": letter, "tile": city.stops[letter], "dest": dest, "dest_tile": city.stops[dest],
		"dest_name": city.stop_names[dest],
		"kind": kind, "name": Riders.pick_name(kind, rng, city.key), "label": Riders.label(kind, city.key),
		"fare": snappedf((3.0 + 0.45 * tiles) * float(info.fare), 0.05),
		"limit": (7.0 + 0.36 * tiles) * float(info.time),
		"band": 0 if tiles < 16 else (1 if tiles < 30 else 2),
		"surge": false,
	})


func _pick_kind() -> String:
	var total := 0.0
	for k in level.kinds:
		total += float(level.kinds[k])
	var roll := rng.randf() * total
	for k in level.kinds:
		roll -= float(level.kinds[k])
		if roll <= 0.0:
			return k
	return level.kinds.keys()[0]


func _move_surge() -> void:
	surge_zones.clear()
	var letters: Array = city.stops.keys()
	for i in 2:
		var tile: Vector2i = city.stops[letters[rng.randi() % letters.size()]]
		surge_zones.append({"pos": city.center(tile), "r": SURGE_RADIUS})


func _in_surge(tile: Vector2i) -> bool:
	for z in surge_zones:
		if city.center(tile).distance_to(z.pos) < z.r:
			return true
	return false


# ---------------------------------------------------------------- the shift

func _physics_process(delta: float) -> void:
	_sim_time += delta
	if _flags.has("timeout") and _sim_time > float(_flags.timeout):
		_report("timeout")
	if car == null:
		return
	clock_time += delta
	if state == State.DRIVING:
		_read_controls()
		if not started and absf(car.throttle) > 0.1:
			started = true
		if started:
			elapsed += delta
			clock -= delta
	else:
		car.throttle = -1.0
		car.steer = 0.0
		car.drift = false
	# After a splash the car stays under water for a beat (the camera lingers
	# on the splash) before reappearing on the bank.
	car.prev_pos = car.position
	car.prev_heading = car.heading
	if splash_hold > 0.0:
		splash_hold -= delta
		car.vel = Vector2.ZERO
		car.events.clear()   # step() isn't running, so don't replay its last events
	else:
		car.step(delta, city)
	for sp in splashes:
		sp.t += delta
	splashes = splashes.filter(func(sp) -> bool: return sp.t < 1.6)
	traffic.update(delta, car)
	_update_sound()
	if state == State.DRIVING:
		_traffic_contacts()
		for e in car.events:
			_on_event(e)
		_update_surge(delta)
		_update_specials(delta)
		_update_ride(delta)
		_check_stops()
		_check_end()
	_route_timer -= delta
	if _route_timer <= 0.0:
		_route_timer = 0.2
		_update_route()
	_say_cd -= delta
	bubble_t = maxf(0.0, bubble_t - delta)
	for p in popups:
		p.t -= delta
	popups = popups.filter(func(p) -> bool: return p.t > 0.0)
	if _flags.has("trace") and fmod(_sim_time, 0.5) < delta:
		var near_special := INF
		for npc in traffic.cars:
			if npc.special:
				near_special = minf(near_special, car.position.distance_to(npc.pos))
		print("TRACE t=%.1f pos=(%.0f,%.0f) v=%.0f thr=%.2f steer=%.2f money=%.1f clock=%.1f ride=%s special=%.0f hd=%.2f wall=%s pin=%.1f" % [
			_sim_time, car.position.x, car.position.y, car.speed(), car.throttle, car.steer,
			money, clock, ride.get("dest", "-"), near_special, car.heading, car._wall_n, car._pinned])
	_update_hud()


## Engine, tyres and sirens follow the driving every frame.
func _update_sound() -> void:
	if state != State.DRIVING:
		sound.loop("engine", -80.0)
		sound.loop("skid", -80.0)
		sound.loop("siren", -80.0)
		return
	var v: float = car.speed() / Car.MAX_SPEED
	var rev := 1.0 if car.is_airborne() else absf(car.throttle)
	sound.loop("engine", -16.0 + 6.0 * rev + 4.0 * v, 0.55 + 0.9 * v + 0.15 * rev)
	sound.loop("skid", -14.0 if car.drift_time > 0.05 and not car.is_airborne() else -80.0)
	var near_siren := INF
	for npc in traffic.cars:
		if npc.siren:
			near_siren = minf(near_siren, car.position.distance_to(npc.pos))
	sound.loop("siren", lerpf(-6.0, -36.0, clampf(near_siren / 1100.0, 0.0, 1.0)) if near_siren < 1300.0 else -80.0)
	var secs := ceili(clock)
	if secs <= 10 and secs < _last_tick and secs > 0:
		sound.play("tick", -6.0, 1.0, 0.0)
	_last_tick = secs


func _read_controls() -> void:
	if bot:
		var c: Dictionary = bot.drive(self)
		car.throttle = c.throttle
		car.steer = c.steer
		car.drift = c.drift
		return
	car.throttle = Input.get_axis("brake", "gas")
	car.steer = Input.get_axis("left", "right")
	car.drift = Input.is_action_pressed("drift")
	# Touch: the stick points where you want to go; the car turns that way.
	var stick: Vector2 = hud.stick
	if stick.length() > 0.25:
		var diff := wrapf(stick.angle() - car.heading, -PI, PI)
		if absf(diff) > 2.5 and car.forward_speed() < 60.0:
			car.throttle = -1.0                 # pointing behind you: back up and swing round
			car.steer = -signf(diff)
		else:
			car.throttle = clampf(stick.length(), 0.0, 1.0)
			car.steer = clampf(diff * 2.2, -1.0, 1.0)


## Contacts with traffic: bumps push you off, close passes are close calls.
func _traffic_contacts() -> void:
	if car.is_airborne():
		return
	for npc in traffic.cars:
		var touching := false
		var reach: float = Car.RADIUS + traffic.radius(npc)
		for a in car.circles():
			for b in traffic.circles(npc):
				var d: Vector2 = a - b
				if d.length() < reach and d.length() > 0.001:
					touching = true
					car.position += d.normalized() * (reach - d.length())
					car.bounce(d.normalized(), traffic.velocity(npc))
					car.touching(d.normalized())   # lets the unstick assist free you from a jam
					if npc.honk <= 0.0:
						sound.play("honk", -8.0, 0.8 + 0.1 * float(npc.id % 5))
					npc.honk = maxf(npc.honk, 1.2)
		if touching and npc.special and npc.hit_cd <= 0.0:
			npc.hit_cd = 2.0
			_hit_special(npc)
		_special_rules(npc)
		var dist: float = car.position.distance_to(npc.pos)
		var near: float = NEAR_MISS + (npc.length - 46.0) * 0.5
		if touching:
			npc.touched = true
		if dist < near and car.speed() > NEAR_MISS_SPEED:
			npc.close = true
		elif dist > near + 20.0 and npc.close:
			if not npc.touched:
				_on_event({"type": "near_miss", "kind": npc.kind})
			npc.close = false
			npc.touched = false
		elif dist > near + 20.0:
			npc.touched = false


## Bumping into a special vehicle has consequences.
func _hit_special(npc: Dictionary) -> void:
	var streamer: bool = not ride.is_empty() and ride.kind == "streamer"
	_log_event({"type": "hit_special", "kind": npc.kind})
	match npc.kind:
		"getaway":
			if npc.busted < 0.0:
				traffic.bust(npc)
				money += 15.0
				_popup("CITIZEN'S ARREST! +$15", Color("57e36b"), 42)
				_say("arrest", true)
				sound.play("arrest", -2.0)
				if not ride.is_empty():
					ride.mood += 20.0 if streamer else 5.0
		"police":
			_fine(10.0, "Bumped a cop!")
		"ambulance":
			_fine(10.0, "You hit an AMBULANCE?!")
		"suv", "bike":
			_fine(25.0, "DIPLOMATIC INCIDENT!")
			_say("incident", true)
			sound.play("incident", -3.0)
			if not ride.is_empty():
				ride.mood += 25.0 if streamer else -30.0
		"trash":
			_popup("EWW!", Color("9bd36b"), 40)
			if not ride.is_empty():
				ride.mood += 4.0 if streamer else -6.0


## Ongoing rules around special vehicles: blocking an ambulance or motorcade
## costs you, and tailgating an ambulance through traffic pays (it clears the road).
func _special_rules(npc: Dictionary) -> void:
	if npc.blocked_t > 1.2:
		npc.blocked_t = 0.0
		_fine(5.0, "MOVE IT!" if npc.kind == "ambulance" else "Blocking the motorcade!")
	if npc.kind == "ambulance":
		var d: Vector2 = car.position - npc.pos
		var behind: float = -d.dot(npc.dir)
		var side: float = absf(d.dot(Vector2(-npc.dir.y, npc.dir.x)))
		if behind > 40.0 and behind < 220.0 and side < 40.0 and car.speed() > 300.0:
			_chaser_t += get_physics_process_delta_time()
			if _chaser_t > 1.5:
				_chaser_t = 0.0
				_stunt(1.0, "AMBULANCE CHASER!", 1.0)


## Dev flag --watch-special: the camera follows the special convoy's leader
## instead of your car (screenshots and video cutaways). Empty = follow the car.
func watch_special() -> Dictionary:
	if not _flags.has("watch-special") or traffic == null:
		return {}
	for npc in traffic.cars:
		if npc.special:
			return npc
	return {}


func _fine(amount: float, why: String) -> void:
	money = maxf(0.0, money - amount)
	_popup("%s  -$%d" % [why, int(amount)], Color("ff4d6d"), 36)
	_log_event({"type": "fine", "amount": amount})
	sound.play("fine", -5.0)


## Special events: one at a time, a short break after each, cycling through
## the shift's list.
func _update_specials(delta: float) -> void:
	var list: Array = level.get("specials", [])
	if _flags.has("special") and _special_index == 0 and _sim_time >= float(_flags.get("special-at", 0.0)):
		# Dev flag: start this event right away, close by (screenshots, videos).
		_special_index = 1
		traffic.spawn_event(String(_flags.special), city, rng, car.position, 450.0)
		hud.alert(String(Traffic.EVENTS[String(_flags.special)].alert))
		return
	if list.is_empty() or traffic.event_active():
		return
	_special_timer += delta
	if _special_timer < (10.0 if _special_index == 0 else 16.0):
		return
	_special_timer = 0.0
	var name: String = list[_special_index % list.size()]
	_special_index += 1
	traffic.spawn_event(name, city, rng, car.position)
	hud.alert(String(Traffic.EVENTS[name].alert))
	sound.play("alert", -6.0)
	_log_event({"type": "special", "kind": name})


func _on_event(e: Dictionary) -> void:
	_log_event(e)
	var riding := not ride.is_empty()
	var kind: Dictionary = Riders.KINDS[ride.kind] if riding else {}
	match e.type:
		"crash":
			crashes += 1
			sound.play("crash", -3.0)
			_say("crash", float(e.impact) > 300.0)   # a big hit interrupts
			if riding:
				ride.mood += float(kind.crash)
				if float(kind.crash) > 0.0:
					_tip(1.0, "CONTENT!")
				else:
					_popup("OOF!", Color("ff4d6d"), 38)
			else:
				_popup("BONK", Color("ff4d6d"), 30)
		"near_miss":
			sound.play("near", -8.0)
			_say("near")
			var label: String = SPECIAL_CLOSE.get(e.get("kind", "car"), "CLOSE CALL!")
			var big: bool = e.get("kind", "car") != "car"
			_stunt(2.5 if big else 1.0, label, 2.0 if big else 1.0)
		"land":
			sound.play("land", -4.0)
			_say("jump", true)
			var air: float = e.air
			_stunt(2.0 + air * 4.0, "BIG AIR! %.1fs" % air, 2.0)
		"drift":
			_say("drift")
			var secs: float = e.secs
			_stunt(secs * 1.5, "DRIFT %.1fs" % secs, secs)
		"splash":
			crashes += 1
			sound.play("splash", 0.0)
			_say("splash", true)
			if riding:
				ride.mood += 12.0 if ride.kind == "streamer" else -30.0
			splash_pos = e.at
			splash_hold = 1.2
			splashes.append({"pos": e.at, "t": 0.0})
			_popup("SPLASH!", Color("37b7ff"), 46)
		"takeoff":
			sound.play("jump", -4.0)
		"bump":
			sound.play("bump", -10.0)


## The passenger shouts something in a speech bubble. `force` interrupts a
## bubble that's still up (big moments); otherwise there's a short cooldown so
## they don't talk over themselves.
func _say(moment: String, force := false) -> void:
	if ride.is_empty() or (_say_cd > 0.0 and not force):
		return
	var line: String = Riders.say(ride.kind, moment, say_rng, city.key)
	for k in 3:   # don't say the same thing twice in a row
		if line != bubble_text:
			break
		line = Riders.say(ride.kind, moment, say_rng, city.key)
	if line == "" or (line == bubble_text and not force):
		return   # nothing new to say
	bubble_text = line
	bubble_t = 2.0
	sound.talk(ride.kind, line.split(" ").size() + 1)
	_say_cd = 1.4
	_log_event({"type": "say", "kind": ride.kind, "text": line})


## A stunt: tips (if they like it), and mood up or down by the passenger's taste.
func _stunt(base_tip: float, label: String, weight: float) -> void:
	if ride.is_empty():
		_popup(label, Color("fff8e7"), 30)
		return
	var kind: Dictionary = Riders.KINDS[ride.kind]
	ride.mood += float(kind.stunt) * weight
	if float(kind.tip) > 0.0:
		_tip(base_tip * float(kind.tip), label)
	else:
		_popup(label + "  (%s frowns)" % ride.get("label", "Nana"), Color("ff9ec4"), 30)


func _tip(amount: float, label: String) -> void:
	ride.tip += amount
	sound.play("kaching", -12.0, 1.25)
	_popup("%s  +$%.2f" % [label, amount], Color("57e36b"), 34)


## Floating text over the car. New popups stack above ones still rising.
func _popup(text: String, color: Color, size: int) -> void:
	var lift := 0.0
	for p in popups:
		if p.t > 0.5:
			lift += 46.0
	popups.append({"text": text, "color": color, "size": size,
			"pos": car.position + Vector2(0, -50.0 - lift), "stack": lift / 46.0, "t": 1.4})


func _update_ride(delta: float) -> void:
	for w in waiting:
		w.surge = _in_surge(w.tile)
	if ride.is_empty():
		return
	var kind: Dictionary = Riders.KINDS[ride.kind]
	var v: float = car.speed()
	if v > Riders.SPEEDY:
		ride.mood += float(kind.fast) * delta
	elif v < Riders.CRAWL and car.position.distance_to(city.center(ride.dest_tile)) > DROP_RADIUS * 1.5:
		ride.mood += float(kind.slow) * delta
	ride.mood = clampf(ride.mood, 0.0, 100.0)
	# Grumbling about the driving, every few seconds while it lasts.
	_mutter_t += delta
	if _mutter_t > 3.5:
		if v > Riders.SPEEDY and float(kind.fast) < 0.0 or v > Riders.SPEEDY and ride.kind == "hustler":
			_mutter_t = 0.0
			_say("fast")
		elif v < Riders.CRAWL and float(kind.slow) < -1.0 and elapsed > 1.0:
			_mutter_t = 0.0
			_say("slow")
	ride.time_left -= delta
	if ride.time_left <= 0.0:
		_bail()


func _check_stops() -> void:
	if car.speed() > STOP_SPEED or car.is_airborne():
		return
	if ride.is_empty():
		for w in waiting:
			if car.position.distance_to(city.center(w.tile)) < PICKUP_RADIUS:
				_pick_up(w)
				return
	elif car.position.distance_to(city.center(ride.dest_tile)) < DROP_RADIUS:
		_drop_off()


func _pick_up(w: Dictionary) -> void:
	waiting.erase(w)
	ride = w.duplicate()
	ride.mood = float(Riders.KINDS[w.kind].mood)
	ride.tip = 0.0
	ride.time_left = w.limit
	if w.surge:
		ride.fare *= 2.0
	_popup("%s hopped in!" % w.name, Color("fff8e7"), 30)
	_log_event({"type": "pickup", "kind": w.kind})
	sound.play("pickup", -4.0)
	_say("pickup", true)
	_mutter_t = 0.0
	_spawn_request()
	_update_route()


func _drop_off() -> void:
	var stars: int = Riders.stars_for(ride.mood)
	# Tips only come with a good ride. 3 stars keeps half, 4-5 keep it all.
	var tip: float = ride.tip * (0.0 if stars <= 2 else (0.5 if stars == 3 else 1.0))
	if ride.kind == "nana" and stars == 5:
		tip += 5.0   # and a butterscotch
	var pay: float = ride.fare + tip
	money += pay
	var left: float = ride.time_left / ride.limit
	var bonus := 4.0
	var speed_word := "Slow"
	if left > 0.5:
		bonus = 12.0
		speed_word = "SPEEDY!"
	elif left > 0.2:
		bonus = 8.0
		speed_word = "Nice"
	clock += bonus
	reviews.append(stars)
	rides_done += 1
	var quote: String = Riders.review(ride.kind, stars, review_rng, city.key)
	hud.toast(ride.name, stars, quote, "+$%.2f" % pay)
	_popup("%s +%ds" % [speed_word, int(bonus)], Color("ffd23f"), 40)
	sound.play("kaching", -3.0)
	sound.play("review_good" if stars >= 4 else "review_bad", -6.0)
	_log_event({"type": "dropoff", "kind": ride.kind, "stars": stars, "pay": pay, "name": ride.name, "quote": quote})
	ride = {}
	_update_route()


func _bail() -> void:
	reviews.append(1)
	bails += 1
	var line: String = Riders.bail_line(ride.kind, review_rng, city.key)
	hud.toast(ride.name, 1, line, "$0")
	_popup("They bailed!", Color("ff4d6d"), 40)
	sound.play("review_bad", -4.0)
	_log_event({"type": "bail", "kind": ride.kind, "name": ride.name, "quote": line})
	ride = {}
	_spawn_request()
	_update_route()


func rating() -> float:
	var recent := reviews.slice(maxi(0, reviews.size() - RATING_WINDOW))
	var sum := 0.0
	for r in recent:
		sum += float(r)
	return sum / recent.size()


func _update_surge(delta: float) -> void:
	if not level.surge:
		return
	_surge_timer += delta
	if _surge_timer >= SURGE_MOVE:
		_surge_timer = 0.0
		_move_surge()


func _check_end() -> void:
	if money >= float(level.goal) and not _flags.has("endless"):   # --endless: footage keeps rolling
		_win()
	elif _flags.has("no-fail"):
		pass   # footage: keep rolling whatever happens
	elif rating() < float(level.floor):
		_lose("DEACTIVATED!", "Your rating fell below %.1f. The app has 'concerns'." % float(level.floor))
	elif clock <= 0.0:
		clock = 0.0
		_lose("SHIFT OVER", "Short by $%.2f. Fast drop-offs add time to the clock." % (float(level.goal) - money))


func _win() -> void:
	state = State.WON
	var r := rating()
	result_stars = 1
	if r >= 4.7:
		result_stars = 2
		if elapsed <= float(level.par):
			result_stars = 3
	if result_stars > int(best_stars.get(level_index, 0)):
		best_stars[level_index] = result_stars
	if not best_times.has(level_index) or elapsed < float(best_times[level_index]):
		best_times[level_index] = elapsed
	_save_progress()
	var info := "Earned $%.2f in %.1f s.  Rating %.2f.  %d rides, %d crashes." % [
		money, elapsed, r, rides_done, crashes]
	if result_stars == 1:
		info += "\nFinish with a rating of 4.7 or better for the second star."
	elif result_stars == 2:
		info += "\nHit the goal within %d s for the third star." % int(level.par)
	hud.show_result(true, "SHIFT COMPLETE!", info, result_stars, level_index + 1 < Levels.count())
	sound.silence_loops()
	sound.play("win", -2.0)
	_report("complete")


func _lose(title: String, why: String) -> void:
	state = State.FAILED
	fail_reason = title
	hud.show_result(false, title, why, 0, false)
	sound.silence_loops()
	if title.begins_with("DEACTIVATED"):
		sound.play("scratch", -2.0)
	sound.play("lose", -3.0)
	_report("failed")


# ---------------------------------------------------------------- route, camera, HUD

## The in-app route: to the drop-off when someone's aboard, otherwise to the
## nearest ride request.
func _update_route() -> void:
	route_points = PackedVector2Array()
	arrow_dir = Vector2.ZERO
	if car == null:
		return
	var here: Vector2i = city.tile_of(car.position)
	var target := Vector2i(-1, -1)
	if not ride.is_empty():
		target = ride.dest_tile
	else:
		var best := 1 << 30
		for w in waiting:
			var cost: int = city.route_cost(here, w.tile)
			if cost < best:
				best = cost
				target = w.tile
	if target.x < 0:
		return
	var tiles: Array = city.route(here, target)
	route_points.append(car.position)
	for i in range(1, tiles.size()):
		route_points.append(city.center(tiles[i]))
	# The arrow points at a spot ~2 tiles along the route (or the goal itself).
	var aim: Vector2 = city.center(target)
	var walked := 0.0
	for i in range(1, route_points.size()):
		walked += route_points[i - 1].distance_to(route_points[i])
		if walked > 190.0:
			aim = route_points[i]
			break
	if aim.distance_to(car.position) > 1.0:
		arrow_dir = (aim - car.position).normalized()


func _process(delta: float) -> void:
	if view:
		view.sync(self, delta)
		# The speech bubble is HUD (always crisp), pinned above the car on screen.
		if bubble_t > 0.0 and car != null and state == State.DRIVING or bubble_t > 0.0 and state != State.MENU:
			hud.set_bubble(bubble_text, view.car_screen_pos(), clampf(bubble_t / 0.3, 0.0, 1.0))
		else:
			hud.set_bubble("", Vector2.ZERO, 0.0)
	if car != null:
		var ahead: Vector2 = car.vel * 0.35
		camera.position = car.position + ahead.limit_length(220.0)
		var rush := clampf(car.speed() / Car.MAX_SPEED, 0.0, 1.0)
		camera.zoom = Vector2.ONE * _zoom() * (1.0 - 0.15 * rush)
	if _flags.has("screenshot") and _sim_time >= float(_flags.get("wait", 1.5)):
		_take_screenshot(String(_flags.screenshot))


## Portrait windows (phones, Shorts) get a portrait base size, so the HUD keeps
## its size instead of shrinking to fit a landscape layout.
func _fit_base_size() -> void:
	var s := get_window().size
	get_window().content_scale_size = Vector2i(720, 1280) if s.y > s.x else Vector2i(1280, 720)


func _zoom() -> float:
	var s := get_viewport_rect().size
	return clampf(minf(s.x, s.y) / VIEW, 0.4, 2.0)


func _update_hud() -> void:
	if level.is_empty() or state == State.MENU:
		return
	hud.update_stats(money, float(level.goal), rating(), float(level.floor), clock, ride, waiting.size())


# ---------------------------------------------------------------- input

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("retry") and state != State.MENU:
		start_level(level_index)
	elif event.is_action_pressed("menu"):
		show_menu()
	elif event.is_action_pressed("music"):
		var on: bool = sound.toggle_music()
		if car != null:
			_popup("Music " + ("on" if on else "off"), Color("fff8e7"), 28)
	elif event.is_action_pressed("next") and state == State.WON:
		_next_level()
	elif event.is_action_pressed("next") and state == State.FAILED:
		start_level(level_index)


func _setup_input() -> void:
	_add_action("gas", [KEY_UP, KEY_W])
	_add_action("brake", [KEY_DOWN, KEY_S])
	_add_action("left", [KEY_LEFT, KEY_A])
	_add_action("right", [KEY_RIGHT, KEY_D])
	_add_action("drift", [KEY_SPACE, KEY_SHIFT])
	_add_action("retry", [KEY_R])
	_add_action("next", [KEY_ENTER, KEY_KP_ENTER])
	_add_action("menu", [KEY_ESCAPE])
	_add_action("music", [KEY_M])


func _add_action(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for k in keys:
		var e := InputEventKey.new()
		e.physical_keycode = k
		InputMap.action_add_event(action, e)


# ---------------------------------------------------------------- saves, flags, reports

func _load_progress() -> void:
	var cfg := ConfigFile.new()
	if not save_enabled or cfg.load(SAVE_PATH) != OK:
		return
	for i in Levels.count():
		best_stars[i] = int(cfg.get_value("stars", str(i), 0))
		if cfg.has_section_key("times", str(i)):
			best_times[i] = float(cfg.get_value("times", str(i)))


func _save_progress() -> void:
	if not save_enabled or _flags.has("autopilot"):
		return
	var cfg := ConfigFile.new()
	for i in best_stars:
		cfg.set_value("stars", str(i), best_stars[i])
	for i in best_times:
		cfg.set_value("times", str(i), best_times[i])
	cfg.save(SAVE_PATH)


func _parse_flags() -> void:
	for arg in OS.get_cmdline_user_args():
		var a := String(arg).trim_prefix("--")
		var eq := a.find("=")
		if eq >= 0:
			_flags[a.substr(0, eq)] = a.substr(eq + 1)
		else:
			_flags[a] = true


func _log_event(e: Dictionary) -> void:
	if _flags.has("log-events"):
		print("EVENT t=%.2f %s" % [_sim_time, JSON.stringify(e)])


## With --exit-on-end, prints one machine-readable line and quits. The checks
## and the video tools parse it.
func _report(outcome: String) -> void:
	if not _flags.has("exit-on-end"):
		return
	if _flags.has("linger") and outcome != "timeout":
		# Footage: leave the results card on screen for a moment first.
		await get_tree().create_timer(float(_flags.linger), true, false, true).timeout
	print("RESULT level=%d %s money=%.2f goal=%d rating=%.2f rides=%d bails=%d crashes=%d time=%.1f stars=%d walls=%.1f reason=%s" % [
		level_index, outcome, money, int(level.get("goal", 0)), rating() if not reviews.is_empty() else 0.0,
		rides_done, bails, crashes, elapsed, result_stars, car.wall_time if car else 0.0, fail_reason.replace(" ", "_")])
	get_tree().quit()


func _take_screenshot(path: String) -> void:
	_flags.erase("screenshot")
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("SCREENSHOT ", path)
	get_tree().quit()
