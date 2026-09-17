#!/bin/bash
# SekhVet-Diagnose: Debug-Build (nur fuer lldb, laeuft nicht headless), Hilfsdateien liegen neben diesem Skript.
# Aufruf: start-und-pruefen.sh <PatientID einer CT-Studie in der lokalen Datenbank>
PID_PAT=${1:?PatientID angeben}
HIER=$(cd "$(dirname "$0")" && pwd)
APP=$HOME/Projects/horos-vet/build/Build/Products/Debug/Horos.app
echo "=== plist key in built app:"; plutil -p "$APP/Contents/Info.plist" | grep -i UIDesign
echo "=== entitlements:"; codesign -d --entitlements :- "$APP" 2>/dev/null | grep -c get-task-allow
pkill -f "horos-vet/build.*MacOS/Horos"; sleep 2
nohup "$APP/Contents/MacOS/Horos" > /tmp/sekhvet-run.log 2>&1 < /dev/null &
sleep 15
curl -s -m 60 -X POST http://127.0.0.1:8085/ -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>'"$PID_PAT"'</string></value></member></struct></value></param></params></methodCall>' | head -c 100; echo
sleep 10
echo "=== CG windows:"; swift "$HIER/fensterliste.swift" "$(pgrep -n -f "horos-vet.*MacOS/Horos")" 2>/dev/null | grep num=
lldb -p "$(pgrep -n -f "horos-vet.*MacOS/Horos")" --batch -s "$HIER/toolbar-layout.lldb" 2>&1 | grep -E "^===|error|NSThemeFrame|NSTitlebarContainerView|NSToolbarView|NSToolbarItemViewer 0x|^  \[.{15}\] h=.{3} v=.{3} NSView 0x" | grep -v "^note" | awk '/ItemViewer/{if(c++>2) next} /^===/{c=0} {print}' | cut -c1-150 | head -40
echo "=== crash/log tail:"; grep -i "exception\|crash" /tmp/sekhvet-run.log | head -3; ls -t ~/Library/Logs/DiagnosticReports/ 2>/dev/null | grep -i horos | head -2
