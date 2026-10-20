extends RefCounted
## Shifts (levels) as data. Every shift happens in the same city; what changes
## is who's riding, how busy the streets are, and the target.
##
## name, tip   shown in the menu and at the start.
## goal        dollars to earn to finish the shift.
## clock       starting shift clock in seconds. Fast drop-offs add time.
## floor       driver rating below this = deactivated (fail).
## kinds       passenger mix: kind -> weight (see riders.gd).
## traffic     [loop index, car count, reversed] per loop (see city.gd LOOPS).
## traffic_speed  px/s for traffic cars.
## waiting     how many ride requests are open at once.
## surge       surge zones on (pickups inside pay double).
## rain        slippery roads.
## par         seconds to reach the goal for the third star.
## seed        fixes who appears where, so every run of a shift is the same.

const LEVELS := [
	{
		"name": "First Shift", "goal": 40, "clock": 60, "floor": 4.0, "seed": 11,
		"kinds": {"regular": 1}, "traffic": [], "traffic_speed": 0, "waiting": 3,
		"surge": false, "rain": false, "par": 70,
		"tip": "Stop in a green circle to pick up. Follow the arrow. Fast drop-offs add time!",
	},
	{
		"name": "Close Calls", "goal": 60, "clock": 60, "floor": 4.0, "seed": 23,
		"kinds": {"regular": 1},
		"traffic": [[0, 6, false], [1, 4, true], [3, 3, false]], "traffic_speed": 230, "waiting": 3,
		"surge": false, "rain": false, "par": 95,
		"tip": "Traffic! Whiz past cars without touching them for tips. Crashes cost stars.",
	},
	{
		"name": "Content Creators", "goal": 80, "clock": 60, "floor": 4.0, "seed": 37,
		"kinds": {"regular": 2, "streamer": 2},
		"traffic": [[0, 6, false], [1, 4, true], [2, 3, false]], "traffic_speed": 230, "waiting": 3,
		"surge": false, "rain": false, "par": 110,
		"tip": "Livestreamers LOVE chaos. Hit the yellow ramps at full speed. Try the canal...",
	},
	{
		"name": "Sunny Acres", "goal": 90, "clock": 65, "floor": 4.0, "seed": 41,
		"kinds": {"regular": 2, "nana": 2, "streamer": 1},
		"traffic": [[0, 7, false], [1, 5, true], [4, 3, false]], "traffic_speed": 230, "waiting": 3,
		"surge": false, "rain": false, "par": 125,
		"tip": "Nana pays well but hates speed and bumps. Drive like you're carrying soup.",
	},
	{
		"name": "Hustle Hour", "goal": 110, "clock": 60, "floor": 4.1, "seed": 53,
		"kinds": {"regular": 2, "hustler": 2, "nana": 1},
		"traffic": [[0, 8, false], [1, 5, true], [2, 3, false], [5, 3, true]],
		"traffic_speed": 250, "waiting": 3, "surge": false, "rain": false, "par": 130,
		"tip": "Hustle Bros pay double and hate waiting. Hold SPACE to drift corners for tips.",
	},
	{
		"name": "Surge!", "goal": 160, "clock": 65, "floor": 4.2, "seed": 67,
		"kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1},
		"traffic": [[0, 8, false], [1, 6, true], [3, 3, false], [4, 3, true]],
		"traffic_speed": 250, "waiting": 4, "surge": true, "rain": false, "par": 140,
		"tip": "Pink zones are surging: rides picked up there pay DOUBLE. The zones move!",
	},
	{
		"name": "Rain Check", "goal": 120, "clock": 70, "floor": 4.2, "seed": 79,
		"kinds": {"regular": 2, "hustler": 1, "streamer": 1, "nana": 1},
		"traffic": [[0, 8, false], [1, 6, true], [2, 3, true], [5, 3, false]],
		"traffic_speed": 210, "waiting": 4, "surge": true, "rain": true, "par": 150,
		"tip": "Rain! The roads are slick. Brake early... or don't, the streamers will love it.",
	},
]


static func count() -> int:
	return LEVELS.size()


static func get_level(i: int) -> Dictionary:
	return LEVELS[i]
