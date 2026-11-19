#!/bin/bash
# Starts the published program on this Mac and measures how busy it keeps the processor at rest: first as it opens the first time,
# with the tour of the tools showing, then with the tour closed. Then, with the tour closed, a burst of tool keys and the program's
# own self test (Help > Self test), which times its parts from the inside.
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
# how much processor time the program uses in $1 seconds of doing nothing
rest() { local a; a=$(used); sleep "$1"; echo "processor time used in $1 s at rest: $(minus "$(used)" "$a") s"; busy; }
# waits until the program has used almost no processor time for a few looks in a row (at most $1 seconds)
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
}
# what the busiest process of the web view is doing, from three seconds of samples: the heaviest lines
what_runs() {
  local pid
  pid=$(ps -Ao pcpu,pid,comm | grep "com.apple.WebKit.$1" | grep -v grep | sort -rn | head -1 | awk '{print $2}')
  [ -z "$pid" ] && { echo "no $1 process"; return; }
  sudo sample "$pid" 3 -file "$OUT/sample-$2.txt" >/dev/null 2>&1
  echo "  $1 (pid $pid), heaviest at the top of the stack:"
  awk '/Sort by top of stack/{p=1;next} p&&NF{print "    " $0; n++} n>=14{exit}' "$OUT/sample-$2.txt" | cut -c1-150
}
pressed() { case "$1" in PRESSED*|CLICKED*) return 0 ;; *) return 1 ;; esac; }

echo "== the Mac =="
sw_vers
uname -m
sysctl -n machdep.cpu.brand_string hw.ncpu 2>/dev/null

echo "== the program =="
arch=$(uname -m)
if [ "$arch" = "arm64" ]; then pat="aarch64"; else pat="x86_64"; fi
gh release download "$RELEASE_TAG" -R "$RELEASE_REPO" -p "*${pat}.app.tar.gz" -D dl || exit 1
mkdir -p app && tar -xzf dl/*.tar.gz -C app
xattr -cr app/*.app 2>/dev/null
ls dl

echo "== opening =="
t0=$(now)
open -n app/*.app
for i in $(seq 1 80); do
  n=$(AX windows)
  if [ "$n" -ge 1 ] 2>/dev/null; then echo "window after: $(since "$t0") s"; break; fi
  sleep 0.5
done
sleep 5
AX front
AX bounds
answer=$(AX click '^(אני מסכים|I agree)$'); echo "$answer"

echo "== A. at rest, as the program opens the first time (the tour of the tools is showing) =="
sleep 25
screencapture -x "$OUT/1-first-open.png"
rest 20
what_runs WebContent tour-webcontent
what_runs GPU tour-gpu

echo "== B. at rest, the tour of the tools closed =="
answer=$(AX rclick '^(סגור|Close)$'); echo "$answer"
sleep 10
screencapture -x "$OUT/2-tour-closed.png"
rest 20
what_runs WebContent closed-webcontent

echo "== C. a burst of tool keys, the tour closed =="
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
until_calm 60
echo "121 tool keys sent in ${sent} s; calm again $(since "$t3") s after the first key (the last 8 s are the waiting for calm); processor time used: $(minus "$(used)" "$u3") s"
screencapture -x "$OUT/3-after-keys.png"

echo "== D. the self test, the tour closed =="
answer=$(AX click '^(Help|עזרה)$'); echo "$answer"
if pressed "$answer"; then sleep 1.5; answer=$(AX click '(Self test|בדיקה עצמית)'); echo "$answer"; fi
if pressed "$answer"; then
  sleep 3
  u1=$(used)
  started=$(now)
  answer=$(AX rclick '^(Run the check|הרץ בדיקה)$'); echo "$answer"
fi
if pressed "$answer"; then
  sleep 4
  until_calm 900
  echo "self test: calm again after $(since "$started") s from the press (the last 8 s are the waiting for calm); processor time used: $(minus "$(used)" "$u1") s"
  screencapture -x "$OUT/4-self-test-finished.png"
  answer=$(AX rclick '(Copy as a request|העתק כבקשה)'); echo "$answer"
  sleep 2
  pbpaste > "$OUT/report.md"
  echo "== the times of the self test, from its own report =="
  grep -E "^- (גרסה|מערכת|משך)|^\| |עמודים לקחו" "$OUT/report.md" | cut -c1-400
else
  echo "the self test was not started"
  screencapture -x "$OUT/x-not-started.png"
fi
echo "== end =="
rest 10
