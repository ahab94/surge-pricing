#!/bin/bash
# How the driving feels for a new player: a "rookie" bot (all-or-nothing
# keyboard steering, quarter-second reactions, gas held down) drives each city
# for 60 s. Prints crashes per minute and rides finished. Lower crashes = kinder
# controls. Not a pass/fail gate: compare before and after a change, e.g.
#   bash checks/feel.sh              (driving aids on, like players)
#   bash checks/feel.sh --no-assist  (raw physics)
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
total=0
for i in 0 1 2 3 4 5 6 7 8 9; do
	line=$("$GODOT" --headless --fixed-fps 60 --path . -- --level=$i --autopilot --rookie --no-fail --endless --exit-on-end --timeout=60 "$@" 2>&1 | grep '^RESULT')
	c=$(echo "$line" | grep -o 'crashes=[0-9]*' | cut -d= -f2)
	r=$(echo "$line" | grep -o 'rides=[0-9]*' | cut -d= -f2)
	w=$(echo "$line" | grep -o 'walls=[0-9.]*' | cut -d= -f2)
	printf "level %d  crashes/min %3d  seconds on walls %5s  rides %d\n" "$i" "$c" "$w" "$r"
	total=$((total + c))
done
echo "feel: $total crashes in 10 minutes of rookie driving"
