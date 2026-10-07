#!/bin/zsh
# Records the review walkthrough: a fresh sample project, the app launched
# and driven through its typical flow by scripts/tour.applescript, trimmed
# to the length of the tour. Needs Accessibility and Screen Recording for
# the terminal. Output: dist/Take-<version>-review-recording.mov.
#
#   scripts/record.sh [path/to/Take.app]
set -euo pipefail
cd "$(dirname "$0")/.."
app=${1:-dist/0.1-1/Take.app}
version=$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$app/Contents/Info.plist")
support=~/Library/Containers/com.siddharthnigam.take/Data/Library/Application\ Support/Take
work=$(mktemp -d)
mkdir -p dist

swiftc -O -o "$work/click" scripts/click.swift
export TAKE_CLICK="$work/click"

# A fresh sample: the last copy is set aside, not deleted, and the app
# reseeds and remembers the new one as its last project.
osascript -e 'tell application "Take" to quit' 2>/dev/null || true; sleep 2
if [[ -d "$support/Sample Project" ]]; then
    mv "$support/Sample Project" "$support/Sample Project.$(date +%Y%m%d-%H%M%S)"
fi
open "$app"; sleep 4
osascript -e 'tell application "System Events" to tell process "Take"
    set frontmost to true
    set position of window 1 to {0, 25}
    set size of window 1 to {1280, 803}
    click menu item "Open Sample Project" of menu "File" of menu bar 1
end tell' >/dev/null; sleep 3
osascript -e 'tell application "Take" to quit'; sleep 2

# Launch inside the recording, then drive.
screencapture -V 150 -C -x "$work/raw.mov" &
sleep 1.5; open "$app"; sleep 1
start=$(date +%s)
osascript scripts/tour.applescript
length=$(( $(date +%s) - start + 3 ))
wait

out="dist/Take-$version-review-recording.mov"
ffmpeg -loglevel error -y -i "$work/raw.mov" -t "$length" -r 30 -c:v libx264 -crf 20 \
    -preset fast -pix_fmt yuv420p -movflags +faststart "$out"
rm -r "$work"
echo "recorded $out ($length s)"
