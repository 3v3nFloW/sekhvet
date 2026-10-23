#!/bin/bash
# SekhVet Paket EE: end-to-end test of the workplaces. Needs the build WITH test hooks (SekhVet-Testhaken.xcconfig).
# Call: bash SekhVet/diagnose/arbeitsplatz-e2e.sh
# Four starts with the EDID of screen 1 replaced (SEKHVET_MONITORE_TEST): A = DELL 27-inch, B = Samsung 49-inch, A, B.
# Every workplace must get back its own area, viewer screens and database window place; the first one takes over the
# settings from before the update. The SekhVet prefs are saved before and restored afterwards.
export PATH=/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/SekhVet
PREFS=~/Library/Preferences/vet.kappa1.sekhvet.horos.plist
W=${TMPDIR:-/tmp}/sekhvet-arbeitsplatz-e2e; rm -rf $W; mkdir -p $W
pgrep -f "MacOS/SekhVet" >/dev/null && { echo "SekhVet laeuft schon -- Abbruch"; exit 1; }
cp $PREFS $W/prefs-vorher.plist
restore() {
  pkill -f "Release/Horos.app/Contents/MacOS/SekhVet"; sleep 2
  defaults import $PREFS $W/prefs-vorher.plist   # merges: keys the run added stay, so delete them
  for k in $(python3 -c 'import plistlib,subprocess,sys; v=plistlib.load(open(sys.argv[1],"rb")); n=plistlib.loads(subprocess.run(["defaults","export",sys.argv[2],"-"],capture_output=True).stdout); print(" ".join(k for k in n if k not in v))' $W/prefs-vorher.plist $PREFS); do defaults delete $PREFS $k; done
  defaults export $PREFS - | plutil -convert xml1 -o $W/prefs-nachher.xml -
  plutil -convert xml1 -o $W/prefs-vorher.xml $W/prefs-vorher.plist
  cmp -s $W/prefs-vorher.xml $W/prefs-nachher.xml && echo "prefs restored (identical)" || echo "PREFS DIFFER after restore -- see $W"
}
trap restore EXIT
defaults delete $PREFS SekhmetWorkplaces 2>/dev/null
defaults write $PREFS SekhmetScreenAreas -dict 0 -int 4 id99 -int 4   # state before the update: right two thirds, by index
defaults write $PREFS NonViewerScreens -array

A="10ac:a0c4:0:DELL U2723QE"; B="4c2d:7181:1297233712:LS49A950U"
ok=0; bad=0
run() {   # run <name> <monitor> <steps>
  local log=$W/$1.log
  SEKHVET_MONITORE_TEST="$2" SEKHVET_ARBEITSPLATZ_TEST="$3" SEKHVET_SKIP_DISCLAIMER=1 $APP > $log 2>&1 & local pid=$!
  local t=0; until grep -q "Arbeitsplatz-Test: fertig" $log; do sleep 2; t=$((t+2)); [ $t -ge 120 ] && { echo "TIMEOUT $1"; break; }; done
  kill $pid; wait $pid 2>/dev/null; sleep 2
  grep -E "Arbeitsplatz-Test|SekhVet workplace" $log | sed 's/^.*\] //' > $W/$1.txt
}
expect() {   # expect <run> <n-th line matching the pattern> <pattern> <what>
  local line=$(grep -E "$3" $W/$1.txt | sed -n "${2}p")
  if [ -n "$line" ]; then ok=$((ok+1)); echo "ok   $1: $4"; else bad=$((bad+1)); echo "FAIL $1: $4 -- no line '$3' #$2"; grep -E "screen 1|NonViewer|workplace" $W/$1.txt | sed 's/^/       /'; fi
}

run 1A "$A" "show|set:2|db:100 100 900 600|viewer:0|show"
expect 1A 1 "workplace taken over: 10ac-a0c4 \(DELL U2723QE\)" "first workplace takes over the old settings"
expect 1A 1 "screen 1 '10ac-a0c4' label '1 · DELL U2723QE' mode 4 " "old area (right two thirds) taken over"
expect 1A 1 "screen 1 .* mode 2 area \{\{960, " "set to right half: area starts in the middle"
expect 1A 1 "NonViewerScreens [0-9]+ usedForViewers 0 db \{\{100, 100\}, \{900, 600\}\}" "screen 1 not for viewers, DB window moved"

run 2B "$B" "show|window:0 0 1280 1000|db:300 200 800 500|show"
expect 2B 1 "workplace new: 4c2d-7181-1297233712 \(LS49A950U\)" "second monitor = new workplace"
expect 2B 1 "screen 1 '4c2d-7181-1297233712' .* mode 0 " "new workplace starts with the whole screen (old code: 2)"
expect 2B 1 "NonViewerScreens  usedForViewers 1 " "new workplace: all screens for viewers"
expect 2B 1 "take from window .* -> 1" "window on the left two thirds taken"
expect 2B 1 "screen 1 .* mode 3 area \{\{0, " "snapped to left two thirds"

run 3A "$A" "show|viewer:1|show"
expect 3A 1 "screen 1 '10ac-a0c4' .* mode 2 area \{\{960, " "A again: right half back"
expect 3A 1 "NonViewerScreens [0-9]+ usedForViewers 0 db \{\{100, 100\}, \{900, 600\}\}" "A again: viewer screens and DB window back (Horos itself would restore B's place)"
expect 3A 1 "NonViewerScreens  usedForViewers 1 " "screen 1 for viewers again"

run 4B "$B" "show|window:600 100 700 700|show|identify"
expect 4B 1 "screen 1 '4c2d-7181-1297233712' .* mode 3 " "B again: left two thirds back"
expect 4B 1 "NonViewerScreens  usedForViewers 1 db \{\{300, 200\}, \{800, 500\}\}" "B again: DB window back"
expect 4B 1 "take from window .* -> 1" "odd window place taken"
expect 4B 1 "screen 1 .* mode 9 area \{\{600, [0-9]+\}, \{700, 700\}\}" "pixel rectangle"

run 5A "$A" "show"
expect 5A 1 "screen 1 '10ac-a0c4' .* mode 2 " "A after B's pixel rectangle: still right half"
expect 5A 1 "NonViewerScreens  usedForViewers 1 " "A: screen 1 for viewers (changed in run 3)"
echo; echo "$ok ok, $bad failed (logs in $W)"
[ $bad -eq 0 ]
