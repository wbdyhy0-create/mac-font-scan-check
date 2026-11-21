#!/bin/bash
# Opens the published program with the test fonts installed. Reads what its own font list shows for them (which families, which
# weights, and which of them stay when the list shows Hebrew fonts only), and measures the processor time the program uses: when the
# font list is opened the first time and again, when it is set to show Hebrew fonts only, and when the text tool is chosen after the
# program was opened again with the list still set so.
set -u
APP_NAME="eMood Trial 30"
OUT="$PWD/out"
mkdir -p "$OUT"
AX() { osascript -l JavaScript speed-check/ax.js "$APP_NAME" "$@" 2>&1; }
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import time,sys; print(round(time.time()-float(sys.argv[1]),1))" "$1"; }
minus() { python3 -c "import sys; print(round(float(sys.argv[1])-float(sys.argv[2]),2))" "$1" "$2"; }
used() { ps -Ao cputime,comm | grep -E "$APP_NAME|com.apple.WebKit" | grep -v grep | awk '{n=split($1,a,":"); s+=(n==3 ? a[1]*3600+a[2]*60+a[3] : a[1]*60+a[2])} END{printf "%.2f", s}'; }
until_calm() {
  local max=$1 from prev cur calm=0
  from=$(now); prev=$(used)
  while [ "$(python3 -c "import time,sys; print(1 if time.time()-float(sys.argv[1]) < float(sys.argv[2]) else 0)" "$from" "$max")" = "1" ]; do
    sleep 2
    cur=$(used)
    if [ "$(python3 -c "import sys; print(1 if float(sys.argv[1])-float(sys.argv[2]) < 0.15 else 0)" "$cur" "$prev")" = "1" ]; then calm=$((calm+1)); else calm=0; fi
    prev=$cur
    [ "$calm" -ge 3 ] && break
  done
}
key() { osascript -e "tell application \"System Events\" to keystroke \"$1\"" 2>&1; }
all() { osascript -e 'tell application "System Events" to keystroke "a" using command down' 2>&1; }
# the font names and the weight arrows the open list shows
rows() { AX dump > "$OUT/$1.txt"; grep -E 'Probe|בדיקה|משקלים של' "$OUT/$1.txt" | sed 's/^ *//' | sort | uniq -c | cut -c1-120; }
open_program() {
  open -n app/*.app
  for i in $(seq 1 80); do
    n=$(AX windows)
    if [ "$n" -ge 1 ] 2>/dev/null; then echo "window is open"; break; fi
    sleep 0.5
  done
  sleep 6
  AX front
  AX bounds
  AX click '^(אני מסכים|I agree)$'
}

sw_vers
sysctl -n machdep.cpu.brand_string hw.ncpu 2>/dev/null
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then pat="aarch64"; else pat="x86_64"; fi
gh release download "$RELEASE_TAG" -R "$RELEASE_REPO" -p "*${pat}.app.tar.gz" -D dl || exit 1
mkdir -p app && tar -xzf dl/*.tar.gz -C app
xattr -cr app/*.app 2>/dev/null

open_program
sleep 12
AX rclick '^(סגור|Close)$'
sleep 6

escape() { osascript -e 'tell application "System Events" to key code 53' 2>&1; }

echo "== A. the text tool is chosen; the font list is set to show every font =="
u=$(used); t=$(now)
key t
until_calm 60
echo "processor time used: $(minus "$(used)" "$u") s (calm again after $(since "$t") s, of which the last 6 s are the waiting)"

echo "== B1. the font list is opened, the first time =="
u=$(used); t=$(now)
AX click '^Segoe UI$'
until_calm 90
echo "processor time used: $(minus "$(used)" "$u") s (with the search for the button; calm again after $(since "$t") s)"
escape
sleep 4

echo "== B2. the font list is opened again =="
u=$(used); t=$(now)
AX click '^Segoe UI$'
until_calm 90
echo "processor time used: $(minus "$(used)" "$u") s (with the search for the button; calm again after $(since "$t") s)"
screencapture -x "$OUT/b2-list-open.png"

echo "== C. what the list shows for the test fonts =="
key probe
sleep 3
screencapture -x "$OUT/c1-probe.png"
rows c-probe
all; key "probe glued"; sleep 2; screencapture -x "$OUT/c2-glued.png"
all; key "probe win"; sleep 2; screencapture -x "$OUT/c3-win.png"
all; key "probe same"; sleep 2; screencapture -x "$OUT/c4-same.png"
all; osascript -e 'tell application "System Events" to key code 51' 2>&1
sleep 2

echo "== D. the list is set to show Hebrew fonts only =="
u=$(used); t=$(now)
AX click '^(גופנים בעברית|Hebrew fonts)$'
until_calm 90
echo "processor time used: $(minus "$(used)" "$u") s (with the search for the button; calm again after $(since "$t") s)"
screencapture -x "$OUT/d-hebrew-only.png"
AX dump > "$OUT/d-hebrew-only.txt"
echo "families the list shows as Hebrew fonts: $(grep -c 'AXStaticText' "$OUT/d-hebrew-only.txt") text lines; the test families among them:"
grep -E 'Probe|בדיקה' "$OUT/d-hebrew-only.txt" | sed 's/^ *//' | sort | uniq -c | cut -c1-120
escape

echo "== E. the program is closed and opened again (the list remembers 'Hebrew fonts only'); a document is opened and the text tool chosen =="
sleep 6
osascript -e 'tell application "System Events" to keystroke "q" using command down'
sleep 5
pkill -f "$APP_NAME" 2>/dev/null
sleep 3
open_program
sleep 12
AX dump > "$OUT/e0-welcome.txt"
AX click 'A4'
sleep 6
echo "the text tool is on the screen: $(AX exists '^טקסט \(T\)$')"
screencapture -x "$OUT/e1-document.png"
AX front
u=$(used); t=$(now)
key t
until_calm 90
echo "processor time used: $(minus "$(used)" "$u") s (calm again after $(since "$t") s, of which the last 6 s are the waiting)"
screencapture -x "$OUT/e2-text-tool.png"
AX click '^Segoe UI$'
sleep 4
screencapture -x "$OUT/e3-list.png"
