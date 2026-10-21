#!/bin/bash
# Records raw autopilot gameplay for the videos into build/footage/:
#   l-<name>.mp4  landscape 1920x1080 (trailer)    p-<name>.mp4  portrait 1080x1920 (Shorts)
# Each clip gets a .events file ("EVENT t=… {json}" lines from --log-events),
# so captions can be timed to the exact jump, close call or review.
# Usage: bash tools/video/record_footage.sh [clip-name ...]   (default: all)
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT=$(command -v godot || echo /Applications/Godot.app/Contents/MacOS/Godot)
out=build/footage
mkdir -p "$out"

# Movie Maker records at the project's window size and ignores --resolution,
# so each recording writes a temporary override.cfg with the exact size.
trap 'rm -f override.cfg' EXIT
window() {  # w h
	printf '[display]\nwindow/size/viewport_width=%s\nwindow/size/viewport_height=%s\nwindow/size/window_width_override=%s\nwindow/size/window_height_override=%s\n' "$1" "$2" "$1" "$2" > override.cfg
}

record() {  # name level seconds extra-flags...
	local name=$1 level=$2 secs=$3; shift 3
	if [ -n "${ONLY:-}" ] && [[ " $ONLY " != *" $name "* ]]; then return; fi
	local res=1920x1080
	if [[ $name == p-* ]]; then res=1080x1920; window 1080 1920; else window 1920 1080; fi
	"$GODOT" --path . --write-movie "$out/$name.avi" --fixed-fps 30 \
		-- --level="$level" --autopilot --clean --exit-on-end --log-events --timeout="$secs" "$@" \
		| grep -E "^(EVENT|RESULT)" > "$out/$name.events" || true
	rm -f override.cfg
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 -pix_fmt yuv420p -an "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
	echo "$name: $(grep RESULT "$out/$name.events" || echo 'no result (timeout)')"
}

ONLY="$*"
record l-stunt 2 100 --stunts
record l-surge 5 60
record l-rain 6 45
record p-stunt 2 100 --stunts
