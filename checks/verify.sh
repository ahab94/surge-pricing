#!/bin/bash
# Done when: the project imports, the smoke and gameplay tests pass, and the
# autopilot delivers every level.
set -euo pipefail
cd "$(dirname "$0")/.."
GODOT=$(command -v godot || true)
[ -z "$GODOT" ] && [ -x /Applications/Godot.app/Contents/MacOS/Godot ] && GODOT=/Applications/Godot.app/Contents/MacOS/Godot
[ -n "$GODOT" ] || { echo "Godot is not installed"; exit 1; }
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
out=$("$GODOT" --headless --path . --script res://tests/smoke_test.gd 2>&1) || { echo "$out"; exit 1; }
if echo "$out" | grep -q "SCRIPT ERROR" || ! echo "$out" | grep -q "SMOKE OK"; then echo "$out"; echo "smoke test failed"; exit 1; fi
out=$("$GODOT" --headless --path . --script res://tests/game_test.gd 2>&1) || { echo "$out"; exit 1; }
if echo "$out" | grep -qE "SCRIPT ERROR|FAIL:" || ! echo "$out" | grep -q "GAME OK"; then echo "$out"; echo "gameplay test failed"; exit 1; fi
bash "$(dirname "$0")/autoplay.sh" | tail -1
echo "surge-pricing: all good"
