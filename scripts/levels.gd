extends RefCounted
## Shifts (levels) as data: the World Tour, one city per level (cities.gd).
## Each level adds one new thing on top of the ones before.
##
## name, tip   shown in the menu and at the start.
## goal        dollars to earn to finish the shift.
## clock       starting shift clock in seconds. Fast drop-offs add time.
## floor       driver rating below this = deactivated (fail).
## kinds       passenger mix: kind -> weight (see riders.gd).
## city        which city (cities.gd key).
## traffic     [loop index, car count, reversed] per loop (the city's `loops`).
## traffic_mix share of ordinary cars that are local vehicles, e.g. {"bus": 0.3}.
## car_colors  paint for the ordinary cars (optional).
## night       dark, with lit windows and headlights.
## traffic_speed  px/s for traffic cars.
## waiting     how many ride requests are open at once.
## surge       surge zones on (pickups inside pay double).
## rain        slippery roads.
## par         seconds to reach the goal for the third star.
## specials    special traffic events, in order (see traffic.gd EVENTS): police
##             chase, ambulance, garbage truck, VIP motorcade.
## seed        fixes who appears where, so every run of a shift is the same.

const LEVELS := [
	{
		"name": "Paris", "city": "paris", "specials": [], "goal": 40, "clock": 60, "floor": 4.0, "seed": 11,
		"kinds": {"regular": 1}, "traffic": [[0, 4, false], [1, 3, true]], "traffic_speed": 190, "waiting": 3,
		"surge": false, "rain": false, "par": 60,
		"tip": "Bonjour! Stop in a green circle to pick up. Follow the arrow. Fast drop-offs add time!",
	},
	{
		"name": "New York", "city": "new_york", "specials": ["trash"], "goal": 60, "clock": 60, "floor": 4.0, "seed": 23,
		"kinds": {"regular": 1}, "traffic_mix": {"cab": 0.6},
		"traffic": [[0, 8, false], [1, 5, true], [2, 5, false], [3, 6, true]], "traffic_speed": 230, "waiting": 3,
		"surge": false, "rain": false, "par": 75,
		"tip": "Traffic! Whiz past cars without touching them for tips. Crashes cost stars.",
	},
	{
		"name": "Rio", "city": "rio", "specials": ["ambulance"], "goal": 80, "clock": 60, "floor": 4.0, "seed": 37,
		"kinds": {"regular": 2, "streamer": 2},
		"traffic": [[0, 6, false], [2, 4, true], [4, 5, false]], "traffic_speed": 230, "waiting": 3,
		"surge": false, "rain": false, "par": 95,
		"tip": "Livestreamers LOVE chaos. Hit the yellow ramps at full speed and fly the canal.",
	},
	{
		"name": "Rome", "city": "rome", "specials": ["trash", "ambulance"], "goal": 100, "clock": 65, "floor": 4.0,
		"seed": 41, "kinds": {"regular": 2, "nana": 2, "streamer": 1}, "traffic_mix": {"scooter": 0.4},
		"traffic": [[0, 8, false], [1, 5, true], [3, 5, false]], "traffic_speed": 220, "waiting": 3,
		"surge": false, "rain": false, "par": 105,
		"tip": "Nonna... we mean Nana pays well but hates speed and bumps. Drive like you're carrying soup.",
	},
	{
		"name": "Dubai", "city": "dubai", "specials": ["motorcade", "trash"], "goal": 100, "clock": 60, "floor": 4.1,
		"seed": 53, "kinds": {"regular": 2, "hustler": 2, "nana": 1}, "traffic_mix": {"supercar": 0.35},
		"car_colors": [Color("f4f4f4"), Color("17181c"), Color("c0c6cc"), Color("e2b13c")],
		"traffic": [[0, 8, false], [1, 4, true], [2, 4, false], [4, 4, true]], "traffic_speed": 260, "waiting": 3,
		"surge": false, "rain": false, "par": 110,
		"tip": "Hustle Bros pay double and hate waiting. Hold SPACE to drift corners for tips. Don't touch the motorcade!",
	},
	{
		"name": "London", "city": "london", "specials": ["ambulance", "motorcade"], "goal": 110, "clock": 70,
		"floor": 4.1, "seed": 59, "kinds": {"regular": 2, "hustler": 1, "nana": 1, "streamer": 1},
		"traffic_mix": {"bus": 0.3}, "traffic": [[0, 8, false], [1, 5, true], [2, 4, false], [3, 4, true]],
		"traffic_speed": 220, "waiting": 3, "surge": false, "rain": true, "par": 115,
		"tip": "Drive on the LEFT, and it's raining (of course). Brake early on slick roads.",
	},
	{
		"name": "Tokyo", "city": "tokyo", "specials": ["trash", "ambulance"], "goal": 260, "clock": 65, "floor": 4.1,
		"seed": 67, "kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1},
		"traffic": [[0, 8, false], [1, 6, true], [2, 4, false], [3, 4, true]], "traffic_speed": 240, "waiting": 4,
		"surge": true, "rain": false, "par": 125,
		"tip": "Pink zones are surging: rides picked up there pay DOUBLE. Drift the tight corners!",
	},
	{
		"name": "Istanbul", "city": "istanbul", "specials": ["chase", "ambulance"], "goal": 215, "clock": 65,
		"floor": 4.2, "seed": 71, "kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1},
		"traffic": [[0, 8, false], [1, 4, true], [3, 4, false], [4, 4, true]], "traffic_speed": 240, "waiting": 4,
		"surge": true, "rain": false, "par": 130,
		"tip": "Police chase across the bridges! Ram the getaway car for a citizen's arrest. Don't bump the cops.",
	},
	{
		"name": "Bangkok", "city": "bangkok", "specials": ["chase", "trash", "ambulance"], "goal": 130, "clock": 70,
		"floor": 4.2, "seed": 79, "kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1},
		"traffic_mix": {"tuktuk": 0.4, "scooter": 0.2},
		"traffic": [[0, 8, false], [1, 4, true], [3, 4, false], [4, 4, true]], "traffic_speed": 210, "waiting": 4,
		"surge": true, "rain": true, "par": 130,
		"tip": "Monsoon season, canals everywhere, tuk-tuks everywhere. Keep left and jump the canals.",
	},
	{
		"name": "Singapore", "city": "singapore", "specials": ["chase", "ambulance", "trash", "motorcade"],
		"goal": 230, "clock": 70, "floor": 4.3, "seed": 83,
		"kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1}, "traffic_mix": {"supercar": 0.15},
		"traffic": [[0, 8, false], [1, 5, true], [2, 4, false], [4, 4, true]], "traffic_speed": 240, "waiting": 4,
		"surge": true, "rain": false, "night": true, "par": 155,
		"tip": "The night shift. Everything at once, rating floor 4.3. Good luck, driver.",
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[i]
