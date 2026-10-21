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
	if [[ $name == p-* ]]; then res=1080x1920; window 1080 1920; elif [[ $name == a-* ]]; then res=1280x720; window 1280 720; else window 1920 1080; fi
	"$GODOT" --path . --write-movie "$out/$name.avi" --fixed-fps 60 \
		-- --level="$level" --autopilot --clean --exit-on-end --log-events --timeout="$secs" "$@" \
		| grep -E "^(EVENT|RESULT)" > "$out/$name.events" || true
	rm -f override.cfg
	# Footage recorded with --speed=S runs S game-seconds per video-second.
	local scale=1; for f in "$@"; do [[ $f == --speed=* ]] && scale=${f#--speed=}; done
	echo "$scale" > "$out/$name.scale"
	# a-* clips keep the game's own sound (sound previews); the rest are silent
	# footage that the video tools score with music and stingers.
	local audio=(-an)
	[[ $name == a-* ]] && audio=(-c:a aac -b:a 160k)
	ffmpeg -loglevel error -y -i "$out/$name.avi" -c:v libx264 -preset fast -crf 16 -pix_fmt yuv420p "${audio[@]}" "$out/$name.mp4"
	rm "$out/$name.avi"
	local size; size=$(ffprobe -v error -select_streams v -show_entries stream=width,height -of csv=p=0:s=x "$out/$name.mp4")
	[ "$size" = "$res" ] || { echo "$name recorded at $size, expected $res"; exit 1; }
	echo "$name: $(grep RESULT "$out/$name.events" || echo 'no result (timeout)')"
}

ONLY="$*"
# 60 fps, and every clip only as long as the edit needs (the sim is
# deterministic, so a clip always plays out the same from the start).
for o in l p; do
	record $o-stunt 2 83 --stunts --endless --close-cam
	record $o-chase 2 23 --hunt --special=chase --special-at=10 --close-cam
	record $o-vip 2 15 --hunt --special=motorcade --special-at=6 --close-cam
	record $o-amb 1 9 --special=ambulance --watch-special --close-cam
done
# Comedy Shorts: talking passengers, game time at 1.3x (smooth, faster pace).
record l-same-nana 3 32 --reckless --rider=nana --no-fail --endless --speed=1.3 --close-cam
record l-same-streamer 3 32 --reckless --rider=streamer --no-fail --endless --speed=1.3 --close-cam
record p-nana-action 5 200 --reckless --rider=nana --speed=1.3 --close-cam --linger=2.5
record p-hustler 4 44 --rider=hustler --reckless --endless --no-fail --speed=1.3 --close-cam
record p-streamer 2 90 --rider=streamer --stunts --endless --no-fail --speed=1.3 --close-cam
# World Tour: the same reckless drive per city with different passengers
# (identical crashes, so we pick the funniest local reaction). w-<level>-<rider>.
W="--reckless --no-fail --endless --speed=1.3 --close-cam"
for spec in 0:regular:9.5 0:nana:21.5 0:hustler:9.5 1:regular:9 1:nana:12 1:hustler:9 2:nana:15.5 2:hustler:6.5 \
		3:nana:17 3:hustler:42.5 4:hustler:7.5 4:nana:15 5:nana:16 5:hustler:10 6:hustler:22 6:nana:25 \
		7:regular:13.5 7:nana:16.5 7:hustler:12.5 8:regular:13.5 8:nana:21 8:hustler:13.5 \
		9:regular:21.5 9:nana:27.5 9:hustler:13.5; do
	IFS=: read -r lv rider secs <<< "$spec"
	record "p-w$lv-$rider" "$lv" "$secs" $W --rider="$rider"
done
# Sound previews with the game's own audio (a-*), 1280x720.
P="--reckless --no-fail --endless --close-cam"
record a-paris 0 14 $P --rider=nana
record a-rome 3 14 $P --rider=nana
record a-london 5 14 $P --rider=regular
record a-tokyo 6 16 $P --rider=hustler
record l-surge 5 16
record l-rain 6 33.5
