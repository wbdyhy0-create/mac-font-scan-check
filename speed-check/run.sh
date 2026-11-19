#!/bin/bash
# Starts the published program on this Mac, notes how long it takes to open and how busy it is at rest, then runs the program's own
# self test (Help > Self test), which times its parts from the inside, and keeps the report it makes. Last, with a document open, it
# sends a burst of tool keys and notes how much processor time the program needs for them.
set -u
APP_NAME="eMood Trial 30"
OUT="$PWD/out"
mkdir -p "$OUT"
AX() { osascript -l JavaScript speed-check/ax.js "$APP_NAME" "$@" 2>&1; }
now() { python3 -c 'import time; print(time.time())'; }
since() { python3 -c "import time,sys; print(round(time.time()-float(sys.argv[1]),1))" "$1"; }
minus() { python3 -c "import sys; print(round(float(sys.argv[1])-float(sys.argv[2]),2))" "$1" "$2"; }
busy() { ps -Ao pcpu,rss,comm | grep -E "$APP_NAME|com.apple.WebKit" | grep -v grep | awk '{c=$1; r=$2; $1=""; $2=""; n=$0; sub(/^ +/,"",n); sub(/.*\//,"",n); printf "    %6.1f%% cpu  %6d MB  %s\n", c, r/1024, n}'; }
# the processor time the program and its web view have used so far, in seconds
used() { ps -Ao cputime,comm | grep -E "$APP_NAME|com.apple.WebKit" | grep -v grep | awk '{n=split($1,a,":"); s+=(n==3 ? a[1]*3600+a[2]*60+a[3] : a[1]*60+a[2])} END{printf "%.2f", s}'; }
# waits until the program has used almost no processor time for a few looks in a row (at most $1 seconds); prints how long it waited
until_calm() {
  local max=$1 from prev cur calm=0
  from=$(now); prev=$(used)
  while [ "$(python3 -c "import time,sys; print(1 if time.time()-float(sys.argv[1]) < float(sys.argv[2]) else 0)" "$from" "$max")" = "1" ]; do
    sleep 2
    cur=$(used)
    if [ "$(python3 -c "import sys; print(1 if float(sys.argv[1])-float(sys.argv[2]) < 0.15 else 0)" "$cur" "$prev")" = "1" ]; then calm=$((calm+1)); else calm=0; fi
    prev=$cur
    [ "$calm" -ge 4 ] && break
  done
  since "$from"
}
pressed() { case "$1" in PRESSED*|CLICKED*) return 0 ;; *) return 1 ;; esac; }

echo "== the Mac =="
sw_vers
uname -m
sysctl -n machdep.cpu.brand_string hw.ncpu hw.memsize 2>/dev/null
system_profiler SPDisplaysDataType 2>/dev/null | grep -E "Chipset|VRAM|Metal|Resolution" | head -6

echo "== the program =="
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then pat="aarch64"; else pat="x86_64"; fi
gh release download "$RELEASE_TAG" -R "$RELEASE_REPO" -p "*${pat}.app.tar.gz" -D dl || exit 1
mkdir -p app && tar -xzf dl/*.tar.gz -C app
xattr -cr app/*.app 2>/dev/null
ls dl app

echo "== opening =="
t0=$(now)
open -n app/*.app
opened=""
for i in $(seq 1 80); do
  n=$(AX windows)
  if [ "$n" -ge 1 ] 2>/dev/null; then opened=$(since "$t0"); break; fi
  sleep 0.5
done
echo "window after: ${opened:-not seen} s"
sleep 5
AX front
AX bounds
sleep 1

echo "== the trial notice =="
answer=$(AX click '^(אני מסכים|I agree)$'); echo "$answer"
sleep 6
screencapture -x "$OUT/1-after-notice.png"

echo "== at rest, the program open (five looks, two seconds apart) =="
u0=$(used)
for i in 1 2 3 4 5; do echo "  look $i"; busy; sleep 2; done
echo "processor time used in those 10 s: $(minus "$(used)" "$u0") s"

echo "== what the window holds =="
t1=$(now)
AX dump > "$OUT/tree-1.txt"
echo "elements: $(wc -l < "$OUT/tree-1.txt")   read in $(since "$t1") s"
grep -nE "\| (Help|עזרה|File|קובץ|A4)" "$OUT/tree-1.txt" | head -10

echo "== the self test =="
finished=""
answer=$(AX click '^(Help|עזרה)$'); echo "$answer"
if pressed "$answer"; then
  sleep 1.5
  screencapture -x "$OUT/2-help-menu.png"
  answer=$(AX click '(Self test|בדיקה עצמית)'); echo "$answer"
fi
if pressed "$answer"; then
  sleep 3
  screencapture -x "$OUT/3-self-test-window.png"
  u1=$(used)
  started=$(now)
  answer=$(AX rclick '^(Run the check|הרץ בדיקה)$'); echo "$answer"
fi
if pressed "$answer"; then
  sleep 4
  screencapture -x "$OUT/4-running.png"
  waited=$(until_calm 1500)
  finished=$(since "$started")
  echo "self test: calm again after ${finished} s from the press (the last 8 s of that are the waiting for calm); processor time used: $(minus "$(used)" "$u1") s"
  busy
  screencapture -x "$OUT/5-finished.png"
  answer=$(AX rclick '(Copy as a request|העתק כבקשה)'); echo "$answer"
  sleep 2
  pbpaste > "$OUT/report.md"
  echo "report: $(wc -c < "$OUT/report.md") bytes"
  echo "== the report the program made =="
  cat "$OUT/report.md"
  echo
  echo "== end of the report =="
  answer=$(AX rclick '^(Close|סגור)$'); echo "$answer"
  sleep 2
else
  echo "the self test was not started: see the pictures and tree-1.txt"
  screencapture -x "$OUT/x-not-started.png"
fi

echo "== a document open, and a burst of tool keys =="
answer=$(AX click 'A4'); echo "$answer"
sleep 5
screencapture -x "$OUT/6-document.png"
u2=$(used)
sleep 10
echo "at rest with a document, processor time used in 10 s: $(minus "$(used)" "$u2") s"
busy
u3=$(used)
t3=$(now)
osascript -e 'tell application "System Events"
  repeat 12 times
    repeat with k in {"v", "m", "l", "y", "s", "p", "n", "b", "h", "z"}
      keystroke k
      delay 0.04
    end repeat
  end repeat
  keystroke "v"
end tell' 2>&1
sent=$(since "$t3")
calm=$(until_calm 120)
echo "121 tool keys sent in ${sent} s; calm again $(since "$t3") s after the first key (the last 8 s are the waiting for calm); processor time used: $(minus "$(used)" "$u3") s"
screencapture -x "$OUT/7-after-keys.png"
