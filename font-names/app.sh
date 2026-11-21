#!/bin/bash
# Opens the published program with the test fonts installed and writes down everything its window shows (the names of its controls),
# at the start and with the text tool chosen, with a picture of the screen each time.
set -u
APP_NAME="eMood Trial 30"
OUT="$PWD/out"
mkdir -p "$OUT"
AX() { osascript -l JavaScript speed-check/ax.js "$APP_NAME" "$@" 2>&1; }

sw_vers
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then pat="aarch64"; else pat="x86_64"; fi
gh release download "$RELEASE_TAG" -R "$RELEASE_REPO" -p "*${pat}.app.tar.gz" -D dl || exit 1
mkdir -p app && tar -xzf dl/*.tar.gz -C app
xattr -cr app/*.app 2>/dev/null

open -n app/*.app
for i in $(seq 1 80); do
  n=$(AX windows)
  if [ "$n" -ge 1 ] 2>/dev/null; then echo "window is open"; break; fi
  sleep 0.5
done
sleep 5
AX front
AX bounds
AX click '^(אני מסכים|I agree)$'
sleep 12
AX rclick '^(סגור|Close)$'
sleep 4
screencapture -x "$OUT/app-1-start.png"
AX dump > "$OUT/app-1-start.txt"
echo "controls at the start: $(wc -l < "$OUT/app-1-start.txt")"

AX front
osascript -e 'tell application "System Events" to keystroke "t"'
sleep 3
screencapture -x "$OUT/app-2-text-tool.png"
AX dump > "$OUT/app-2-text-tool.txt"
echo "controls with the text tool: $(wc -l < "$OUT/app-2-text-tool.txt")"
grep -n -i -E 'font|גופן|Arial|David|Helvetica' "$OUT/app-2-text-tool.txt" | head -40
