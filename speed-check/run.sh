#!/bin/bash
# Starts the published program on this Mac, notes how long it takes to open and how busy it is at rest, then runs the program's own
# self test (Help > Self test), which times its parts from the inside, and keeps the report it makes.
set -u
APP_NAME="eMood Trial 30"
OUT="$PWD/out"
mkdir -p "$OUT"
AX() { osascript -l JavaScript speed-check/ax.js "$APP_NAME" "$@" 2>&1; }
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import time,sys; print(round(time.time()-float(sys.argv[1]),1))" "$1"; }
busy() { ps -Ao pcpu,rss,comm | grep -E "$APP_NAME|com.apple.WebKit" | grep -v grep | awk '{c=$1; r=$2; $1=""; $2=""; n=$0; sub(/^ +/,"",n); sub(/.*\//,"",n); printf "    %6.1f%% cpu  %6d MB  %s\n", c, r/1024, n}'; }

echo "== the Mac =="
sw_vers
uname -m
sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize 2>/dev/null
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset|Type:|VRAM|Vendor|Metal|Resolution" | head -8

echo "== the program =="
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then pat="aarch64"; else pat="x86_64"; fi
gh release download "$RELEASE_TAG" -R "$RELEASE_REPO" -p "*${pat}.app.tar.gz" -D dl || exit 1
ls -la dl
mkdir -p app && tar -xzf dl/*.tar.gz -C app
xattr -cr app/*.app 2>/dev/null
ls app

echo "== opening =="
t0=$(now)
open -n app/*.app
opened=""
for i in $(seq 1 80); do
  n=$(AX windows)
  if [ "$n" -ge 1 ] 2>/dev/null; then opened=$(since "$t0"); break; fi
  sleep 0.5
done
echo "window after: ${opened:-not seen} s   (last answer: $n)"
sleep 6
AX front
AX bounds
sleep 2
screencapture -x "$OUT/1-opened.png"

echo "== at rest (five looks, two seconds apart) =="
for i in 1 2 3 4 5; do echo "  look $i"; busy; sleep 2; done

echo "== what the window holds =="
t1=$(now)
AX dump > "$OUT/tree-1.txt"
echo "elements: $(wc -l < "$OUT/tree-1.txt")   read in $(since "$t1") s"
grep -nE "Help|עזרה|Self|בדיקה|File|קובץ" "$OUT/tree-1.txt" | head -12

echo "== the self test =="
AX click '^(Help|עזרה)$'
sleep 1.5
screencapture -x "$OUT/2-help-menu.png"
AX click '(Self test|בדיקה עצמית)'
sleep 3
screencapture -x "$OUT/3-self-test-window.png"
AX dump > "$OUT/tree-2.txt"
grep -nE "Run the check|הרץ בדיקה|Quick|מהירה|CheckBox" "$OUT/tree-2.txt" | head -12
started=$(now)
AX click '^(Run the check|הרץ בדיקה)$'
sleep 5
screencapture -x "$OUT/4-running.png"
done_after=""
for i in $(seq 1 110); do
  sleep 8
  if [ $((i % 4)) -eq 0 ]; then echo "  after $(since "$started") s:"; busy; fi
  answer=$(AX exists '^(Save report|שמור דוח)$')
  case "$answer" in FOUND*) done_after=$(since "$started"); break ;; esac
done
echo "self test finished after: ${done_after:-NOT FINISHED in time} s (measured from outside, to the nearest look)"
screencapture -x "$OUT/5-finished.png"
AX click '(Copy as a request|העתק כבקשה)'
sleep 2
pbpaste > "$OUT/report.md"
echo "report: $(wc -c < "$OUT/report.md") bytes"
echo "== the report the program made =="
cat "$OUT/report.md"
echo
echo "== at rest again =="
sleep 5
busy
