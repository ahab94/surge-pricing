extends SceneTree
## Map and shift validation plus live mechanics. Prints FAIL: lines on
## problems and GAME OK at the end. Run:
##   godot --headless --path . --script res://tests/game_test.gd

const City := preload("res://scripts/city.gd")
const Levels := preload("res://scripts/levels.gd")
const Riders := preload("res://scripts/riders.gd")

var failures := 0


func check(ok: bool, what: String) -> void:
	if not ok:
		failures += 1
		print("FAIL: ", what)


func _initialize() -> void:
	_static_checks()
	var game = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	game.save_enabled = false
	root.add_child(game)
	_live.call_deferred(game)


func _static_checks() -> void:
	for key in City.Cities.CITIES:
		_check_city(City.new(key))
	for i in Levels.count():
		var lv: Dictionary = Levels.get_level(i)
		check(City.Cities.CITIES.has(lv.get("city", "classic")), "shift %d city exists" % i)
		var c = City.new(String(lv.get("city", "classic")))
		for k in lv.kinds:
			check(Riders.KINDS.has(k), "shift %d kind %s exists" % [i, k])
		for e in lv.traffic:
			check(int(e[0]) < c.loops.size(), "shift %d traffic loop %d exists" % [i, int(e[0])])
		c.free()


func _check_city(city) -> void:
	for row in city.data.map:
		check(String(row).length() == city.w, "%s: map rows all the same width" % city.key)
	check(city.cell(city.start) == "S", "%s: the map has a start" % city.key)
	check(city.stops.size() == city.stop_names.size(), "%s: every named stop is on the map" % city.key)
	for letter in city.stops:
		var r: Array = city.route(city.start, city.stops[letter])
		check(not r.is_empty() and r.back() == city.stops[letter], "%s: stop %s reachable" % [city.key, letter])
	for i in city.loops.size():
		var loop: Array = city.loops[i]
		for k in loop.size():
			var a: Vector2i = loop[k]
			var b: Vector2i = loop[(k + 1) % loop.size()]
			check(a.x == b.x or a.y == b.y, "loop %d side %d is straight" % [i, k])
			var step := (b - a).sign()
			var t := a
			while t != b:
				check(city.is_road(t) and city.cell(t) != "^", "%s: loop %d runs on plain road at %s" % [city.key, i, t])
				t += step
	city.free()


func _live(game) -> void:
	await process_frame
	game.start_level(0)
	await physics_frame
	var car = game.car
	var city = game.city

	# Pickup: park on a request and it becomes the ride.
	var w: Dictionary = game.waiting[0]
	car.position = city.center(w.tile)
	car.vel = Vector2.ZERO
	await physics_frame
	await physics_frame
	check(not game.ride.is_empty() and game.ride.name == w.name, "stopping on a request picks it up")
	check(game.waiting.size() == int(game.level.waiting), "a new request replaces the one picked up")

	# Drop-off pays and leaves a review.
	var reviews_before: int = game.reviews.size()
	car.position = city.center(game.ride.dest_tile)
	car.vel = Vector2.ZERO
	await physics_frame
	await physics_frame
	check(game.ride.is_empty(), "stopping at the destination drops off")
	check(game.money > 0.0, "a drop-off pays")
	check(game.reviews.size() == reviews_before + 1, "a drop-off leaves a review")

	# Walls stop the car and a hard hit is a crash: drive west into the first
	# building that has road just east of it.
	game.start_level(0)
	await physics_frame
	car = game.car
	city = game.city
	var wall_road := Vector2i(-1, -1)
	for y in city.h:
		for x in range(1, city.w):
			if wall_road.x < 0 and city.cell(Vector2i(x, y)) == "." and city.cell(Vector2i(x - 1, y)) == "#":
				wall_road = Vector2i(x, y)
	var crashes_before: int = game.crashes
	car.position = city.center(wall_road)
	car.heading = PI
	car.vel = Vector2(-500, 0)
	for i in 30:
		await physics_frame
	check(city.tile_of(car.position).x >= wall_road.x, "a building stops the car")
	check(game.crashes > crashes_before, "slamming a wall is a crash")

	# Ramps launch the car over water: find a ramp with water just south of it.
	var ramp := Vector2i(-1, -1)
	var gap := 0
	for y in city.h:
		for x in city.w:
			if ramp.x < 0 and city.cell(Vector2i(x, y)) == "^" and city.cell(Vector2i(x, y + 1)) == "~":
				ramp = Vector2i(x, y)
	while city.cell(ramp + Vector2i(0, gap + 1)) == "~":
		gap += 1
	car.position = city.center(ramp + Vector2i(0, -2))
	car.heading = PI / 2.0
	car.vel = Vector2(0, 700)
	car.throttle = 1.0
	var flew := false
	var landed_y := -1
	for i in 120:
		await physics_frame
		if car.is_airborne():
			flew = true
		elif flew and landed_y < 0:
			landed_y = city.tile_of(car.position).y
	check(ramp.x >= 0 and flew, "a ramp launches the car")
	check(landed_y > ramp.y + gap, "full speed clears the water (landed y=%d, water ends %d)" % [landed_y, ramp.y + gap])

	# Rating is the average of the last reviews; Nana hates speed.
	check(is_equal_approx(game.rating(), 4.8), "starting rating is 4.8")
	check(Riders.stars_for(100.0) == 5 and Riders.stars_for(0.0) == 1, "mood maps to 1-5 stars")

	# Traffic moves and stops for the player.
	game.start_level(1)
	await physics_frame
	var npc: Dictionary = game.traffic.cars[0]
	var p0: Vector2 = npc.pos
	for i in 30:
		await physics_frame
	check(npc.pos.distance_to(p0) > 50.0, "traffic drives")
	game.car.position = npc.pos + npc.dir * 70.0
	game.car.vel = Vector2.ZERO
	for i in 60:
		await physics_frame
	check(npc.speed < 20.0, "traffic stops for the player in its lane")

	# Special traffic: cars pull over for sirens; ramming the getaway car is
	# a citizen's arrest; touching the motorcade is a fine.
	game.start_level(1)
	await physics_frame
	var tr = game.traffic
	var ordinary: Dictionary = tr.cars[0]
	tr.spawn_event("ambulance", game.city, game.rng, game.car.position)
	var amb: Dictionary = tr.cars.back()
	check(amb.siren and amb.special, "the ambulance is a siren special")
	amb.s = ordinary.s - 150.0
	amb.path = ordinary.path
	amb.total = ordinary.total
	for i in 40:
		await physics_frame
	check(ordinary.shift > 15.0, "ordinary cars pull over for a siren (shift %.0f)" % ordinary.shift)
	tr.cars = tr.cars.filter(func(c) -> bool: return not c.special)

	tr.spawn_event("chase", game.city, game.rng, game.car.position)
	var getaway: Dictionary = tr.cars.filter(func(c) -> bool: return c.kind == "getaway")[0]
	var before: float = game.money
	game.car.position = getaway.pos + getaway.dir * 30.0
	game.car.vel = -getaway.dir * 300.0
	await physics_frame
	await physics_frame
	check(getaway.busted >= 0.0, "ramming the getaway car busts the chase")
	check(game.money >= before + 15.0, "a citizen's arrest pays")
	tr.cars = tr.cars.filter(func(c) -> bool: return not c.special)

	tr.spawn_event("motorcade", game.city, game.rng, game.car.position)
	var suv: Dictionary = tr.cars.filter(func(c) -> bool: return c.kind == "suv")[0]
	game.money = 50.0
	game.car.position = suv.pos + Vector2(-suv.dir.y, suv.dir.x) * 20.0
	game.car.vel = Vector2.ZERO
	await physics_frame
	await physics_frame
	check(game.money <= 25.0, "touching the motorcade is a diplomatic incident (money %.0f)" % game.money)

	print("GAME OK" if failures == 0 else "GAME FAILED (%d)" % failures)
	quit(0)
