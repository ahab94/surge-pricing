# Surge Pricing: notes for Claude

A top-down arcade-taxi rideshare game in Godot 4.7 (GDScript). You drive for the parody app "Yoink": pick up passengers, follow the route, earn tips for stunts, and beat the shift clock. Your driver rating, the average of the last 20 reviews, is your health bar. README.md holds the design and roadmap.

## Run and check
- Play: `godot --path .` (or open in the editor and press F5).
- Every change: `bash checks/verify.sh` must end with `surge-pricing: all good` (~20 s).
  - It runs `tests/smoke_test.gd`, `tests/game_test.gd` (map/shift validation plus live mechanics) and `checks/autoplay.sh`.
  - autoplay.sh is the winnability gate: the autopilot must complete every shift.
- Wrap headless runs in `perl -e 'alarm 90; exec @ARGV' godot ...`. A script parse error leaves a test SceneTree running forever.
- Dev flags go after `--`:
  - `--level=N` (0-based) skips the menu.
  - `--autopilot` has the bot drive. `--trace` prints its state every 0.5 s.
  - `--log-events` prints `EVENT t=… {json}`. Event types: pickup, dropoff, bail, crash, near_miss, takeoff, land, drift, splash. Use the timestamps to cut videos.
  - `--exit-on-end` prints `RESULT level=… complete|failed|timeout money=… goal=… rating=… rides=… bails=… crashes=… time=… stars=… reason=…`, then quits.
  - `--timeout=S` counts simulated seconds.
  - `--screenshot=path.png --wait=S` saves a frame after S simulated seconds, then quits.
  - `--touch` shows the touch controls; the mouse can press them.
  - Put `--fixed-fps 60` (a Godot flag, before `--`) to run headless faster than real time.
- Portrait: `godot --path . --resolution 720x1280 -- ...`. The game switches its base size to 720x1280 when the window is taller than wide.

## Layout
- `scripts/city.gd`: the map, as ASCII rows (the legend is at the top of the file).
  - STOP_NAMES are the parody landmarks. LOOPS are the traffic circuits.
  - TILE is 128 px of game space. The art is drawn on a 96 px design grid (D) and scaled by K.
  - Routes come from a cached Dijkstra cost-to-go field per destination (bucket queue). Roads cost 1, grass 4, ramps 30.
  - `push_out` handles collisions: a box per solid tile, round trees, inset houses.
- `scripts/car.gd`: a kinematic arcade car.
  - Throttle and brake act along the nose. Grip bleeds off sideways speed; DRIFT_GRIP is the handbrake.
  - Two collision circles. `bounce()` is shared by walls and traffic.
  - Ramps launch it for `0.3 + v/1400` s. Landing in water is a splash and a respawn.
  - It emits `events` that game.gd turns into tips and moods.
- `scripts/traffic.gd`: cars on lane-offset loops.
  - They brake for the player and for cars ahead going their way. Crossing cars yield by index, so no deadlocks.
  - `circles()` and `velocity()` are used for contacts.
- `scripts/riders.gd`: passenger types (mood and tip tuning, names, reviews per star level, bail lines).
- `scripts/levels.gd`: shifts as data: goal, clock, rating floor, rider mix, traffic loops, surge, rain, par, seed.
- `scripts/game.gd`: the shift rules:
  - requests, pickup and drop-off, fare and tip payout, clock bonuses;
  - mood, reviews and rating;
  - win and lose;
  - near misses and traffic contacts;
  - the route and arrow, the camera, saves, flags, RESULT.
- `scripts/autopilot.gd`:
  - Picks the best dollars-per-second request.
  - Follows the route with lookahead and keeps right.
  - Corner speed comes from v² = 2ad and slows in the rain.
  - Overtakes on the left when there's no oncoming car, and three-point-turns when the route is behind it.
- `scripts/fx.gd`: world overlays, as two instances. Under the cars: skids, surge zones, requests, route, destination. Over them: the arrow and popups.
- `scripts/hud.gd`: the shift clock, the Yoink app card, review toasts, results, the menu, touch controls (floating stick plus BRAKE/DRIFT TouchScreenButtons) and the rain overlay.

## Conventions
- When a shift changes, run autoplay. Tune goals and clocks so the bot finishes with some margin.
- GDScript gotcha: `:=` on values from untyped objects or dictionaries fails to parse. Declare the type explicitly.
- The default font lacks symbol glyphs: draw stars as polygons.
- Scripts reference each other with `preload`, not `class_name`. Everything is drawn in code. Comments explain why. The user is learning Godot, so briefly explain new engine concepts.
- Never show real brand, company, country or person names. Rider names are generic first names or obvious parodies. No real rideshare app names anywhere.
