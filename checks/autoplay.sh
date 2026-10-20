#!/bin/bash
# The autopilot must complete every shift (earn the goal before the clock or
# the rating runs out). A failure usually means a shift got too hard; trace it:
#   godot --headless --fixed-fps 60 --path . -- --level=N --autopilot --exit-on-end --trace
set -uo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
count=$("$GODOT" --headless --path . --script res://tests/level_count.gd 2>/dev/null | grep -o 'LEVELS [0-9]*' | cut -d' ' -f2)
fail=0
for ((i = 0; i < count; i++)); do
	line=$("$GODOT" --headless --fixed-fps 60 --path . -- --level=$i --autopilot --exit-on-end --timeout=400 2>&1 | grep '^RESULT')
	echo "$line"
	echo "$line" | grep -q ' complete ' || fail=1
done
[ $fail -eq 0 ] && echo "autoplay: all $count shifts complete" || { echo "autoplay: FAILED"; exit 1; }
