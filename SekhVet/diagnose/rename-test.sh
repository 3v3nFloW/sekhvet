#!/bin/bash
# SekhVet Paket BC: Headless-Test des Umbenennens. Braucht einen Testhaken-Build (SekhVet-Testhaken.xcconfig).
# Aufruf: rename-test.sh <PatientID in der lokalen DB> <NeuerName> <NeueID> [YYYYMMDD]
PID_PAT=${1:?PatientID angeben}; NAME=${2:?Name angeben}; NEWID=${3:?ID angeben}; DOB=$4
APP=$HOME/Projects/horos-vet/build/Build/Products/Release/Horos.app
LOG=/tmp/sekhvet-rename-test.log
curl -s -m 5 -X POST http://127.0.0.1:8085/ -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3; pkill -f "horos-vet/build.*MacOS/Horos"; sleep 2
ENVV="$PID_PAT|$NAME|$NEWID"; [ -n "$DOB" ] && ENVV="$ENVV|$DOB"
SEKHVET_RENAME_TEST="$ENVV" nohup "$APP/Contents/MacOS/Horos" > "$LOG" 2>&1 < /dev/null &
for i in $(seq 1 60); do grep -q "Rename-Test" "$LOG" && break; sleep 2; done
grep "SekhVet Rename" "$LOG"
sleep 3
curl -s -m 10 -X POST http://127.0.0.1:8085/ -H "Content-Type: text/xml" --data '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null
