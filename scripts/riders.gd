extends RefCounted

const Locales := preload("res://scripts/locales.gd")
## Passenger types. Each one reacts differently to how you drive, which is the
## whole game: the same stunt that makes a Livestreamer tip big makes Nana
## leave one star.
##
## mood     starting mood, 0-100. Stars at drop-off = ceil(mood / 20).
## crash    mood change per crash (bumping a wall or a car hard).
## stunt    mood change per stunt (close call, drift second, big air).
## tip      tip multiplier for stunts. 0 means they never tip for stunts.
## fast     mood per second above SPEEDY (negative = hates speed).
## slow     mood per second below CRAWL while riding (impatience).
## fare     fare multiplier.  time  time-limit multiplier.
## color    the marker and badge colour.
## says     what they shout in a speech bubble, per moment (pickup, crash,
##          jump, near, splash, drift, slow, fast, arrest, incident).

const SPEEDY := 470.0
const CRAWL := 170.0

const KINDS := {
	"regular": {
		"label": "Rider", "mood": 80.0, "crash": -10.0, "stunt": 3.0, "tip": 1.0,
		"fast": 0.0, "slow": -1.5, "fare": 1.0, "time": 1.0, "color": Color("4dbb5f"),
		"names": ["Dave", "Priya", "Marco", "Jen", "Tomás", "Aisha", "Kev", "Lena", "Sam", "Yuki"],
		"reviews": [
			["Car smelled like regret.", "Drove through a wall. Twice. One star."],
			["Survived. Barely.", "I've had calmer rides on a shopping cart."],
			["Got there. Mostly in one piece.", "Fine. My coffee did not survive."],
			["Fast and only a little terrifying.", "Great music, greater speed."],
			["Is this person a stunt double?? 5 stars", "Arrived before I left. Legend."],
		],
		"bail": ["I'll walk, thanks.", "Faster on foot, honestly."],
		"says": {
			"pickup": ["Hi! Nice and normal, please.", "Is this car green on purpose?"],
			"crash": ["DUDE!", "My coffee!!", "I have kids!", "Was that a WALL?!"],
			"jump": ["WHY ARE WE FLYING", "THIS IS NOT THE ROUTE"],
			"near": ["Eyes on the road!", "That was SO close!"],
			"splash": ["I can't swim!!", "Is this a car or a boat?!"],
			"drift": ["Wheee... wait, no."],
			"slow": ["Any day now..."],
			"arrest": ["Did we just catch a criminal?!"],
			"incident": ["Am I going to jail?!"],
		},
	},
	"streamer": {
		"label": "Livestreamer", "mood": 55.0, "crash": 6.0, "stunt": 9.0, "tip": 2.5,
		"fast": 2.0, "slow": -6.0, "fare": 1.0, "time": 1.1, "color": Color("c86bff"),
		"names": ["xXBlazeXx", "LilVlogz", "ChadCam", "ZoomerZed", "Kaylee.Live", "TotallyNotBot"],
		"reviews": [
			["Zero views. Zero stars. Boring.", "My chat fell asleep."],
			["Chat said 'mid'.", "Needed more chaos tbh."],
			["Decent content. Mid air time.", "Would clip. Maybe."],
			["Chat went WILD.", "That jump?? Viral."],
			["SUBSCRIBE TO THIS DRIVER", "Best content of my career. 5 stars + follow."],
		],
		"bail": ["This ride is NOT content.", "Ending stream. Walking."],
		"says": {
			"pickup": ["Yo chat, we're in a rideshare!", "Do something crazy, I'm LIVE!"],
			"crash": ["CLIP IT!", "CHAT SAW THAT!", "AGAIN! AGAIN!"],
			"jump": ["CHAT ARE YOU SEEING THIS?!", "WE'RE GOING VIRAL!"],
			"near": ["OHHHH!", "So close!! Do it again!"],
			"splash": ["THIS IS CONTENT!", "Underwater stream, let's go!"],
			"drift": ["DRIFT KING!"],
			"slow": ["Bro this is boring.", "Chat is leaving..."],
			"arrest": ["CITIZEN'S ARREST ON STREAM!"],
			"incident": ["INTERNATIONAL CONTENT!"],
		},
	},
	"nana": {
		"label": "Nana", "mood": 92.0, "crash": -25.0, "stunt": -12.0, "tip": 0.0,
		"fast": -7.0, "slow": 0.0, "fare": 1.6, "time": 1.5, "color": Color("ff9ec4"),
		"names": ["Nana Rose", "Grandpa Walt", "Auntie Bea", "Mr. Pemberton", "Granny Ola"],
		"reviews": [
			["My hip has filed a complaint.", "I have seen the other side, young man."],
			["I dropped my knitting. And my dentures.", "Too zippy. Far too zippy."],
			["A bit brisk, dear.", "Reminded me of the war. Which one, I won't say."],
			["Lovely young driver. Bit quick.", "Smooth as my late husband's jazz records."],
			["Like riding a cloud. Have a butterscotch.", "Such a nice driver. I'll tell my bridge club."],
		],
		"bail": ["I'll call my grandson instead.", "I'm taking the bus. It has a bench."],
		"says": {
			"pickup": ["Nice and slow now, dear.", "I'm in no hurry, sweetie."],
			"crash": ["MY HIP!", "Young man!!", "I'm calling your mother.", "My dentures!"],
			"jump": ["Lord have mercy!", "I've seen the light!"],
			"near": ["Oh my stars!", "I dropped my knitting!"],
			"splash": ["My good cardigan!", "Not the river again!"],
			"drift": ["Is the car sliding, dear?"],
			"fast": ["Slow down, sonny!", "This isn't a race!"],
			"arrest": ["Oh! Was that legal?"],
			"incident": ["I'm writing to the newspaper."],
		},
	},
	"hustler": {
		"label": "Hustle Bro", "mood": 66.0, "crash": -6.0, "stunt": 3.0, "tip": 1.5,
		"fast": 4.0, "slow": -9.0, "fare": 2.0, "time": 0.7, "color": Color("ffb02e"),
		"names": ["Brayden (CEO)", "Chad from Sales", "Tyson, Founder", "Jaxon.eth", "Logan Grindset"],
		"reviews": [
			["Lost a deal waiting at a light.", "Slower than our quarterly growth."],
			["Not disruptive enough.", "I've seen faster spreadsheets."],
			["Adequate velocity.", "Will circle back on this ride."],
			["Moves fast. Breaks things. Respect.", "Synergy. Pure synergy."],
			["Hired this driver as COO.", "10x driver. Rise and grind."],
		],
		"bail": ["Time is money. You cost me both.", "Jumping on a scooter. Bye."],
		"says": {
			"pickup": ["Make it quick. I'm closing a deal.", "Time is money, driver."],
			"crash": ["That's a write-off.", "Sending you the invoice."],
			"jump": ["Disruptive. I like it.", "Okay, THIS is a growth hack."],
			"near": ["Bold move. Respect."],
			"splash": ["Liquidity event!", "Underwater. Like my startup."],
			"drift": ["Pivot! PIVOT!"],
			"slow": ["Is this the scenic route?!", "My meeting started 5 minutes ago."],
			"fast": ["Now we're scaling!"],
			"arrest": ["Adding this to my profile."],
			"incident": ["We're going to need lawyers."],
		},
	},
}


## Stars from mood, 1-5.
static func stars_for(mood: float) -> int:
	return clampi(ceili(mood / 20.0), 1, 5)


## The city's version of a passenger type, or {} (locales.gd).
static func _local(kind: String, city: String) -> Dictionary:
	return Locales.LOCALES.get(city, {}).get(kind, {})


## Lines from the city's locale when it has them, else the general ones.
static func _pick(lines: Array, rng: RandomNumberGenerator) -> String:
	return "" if lines.is_empty() else String(lines[rng.randi() % lines.size()])


static func label(kind: String, city := "") -> String:
	return String(_local(kind, city).get("label", KINDS[kind].label))


## One rng call either way, so forcing a type or city keeps rides identical.
static func pick_name(kind: String, rng: RandomNumberGenerator, city := "") -> String:
	return _pick(_local(kind, city).get("names", KINDS[kind].names), rng)


static func review(kind: String, stars: int, rng: RandomNumberGenerator, city := "") -> String:
	var local: Array = _local(kind, city).get("reviews", {}).get(stars, [])
	return _pick(local if not local.is_empty() else KINDS[kind].reviews[stars - 1], rng)


static func bail_line(kind: String, rng: RandomNumberGenerator, city := "") -> String:
	return _pick(_local(kind, city).get("bail", KINDS[kind].bail), rng)


static func say(kind: String, moment: String, rng: RandomNumberGenerator, city := "") -> String:
	var local: Array = _local(kind, city).get("says", {}).get(moment, [])
	return _pick(local if not local.is_empty() else KINDS[kind].says.get(moment, []), rng)
