#!/bin/zsh
# SekhVet Paket AT — Doppelklick-Zoom bei zwei MPR-Fenstern, headless.
# Aufruf: /tmp/sekh_test79.sh [PatientID] [Ansicht 1..3]
PID_PAT=${1:?PatientID angeben}
WHICH=${2:-1}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/Horos
LOG=/tmp/sekhvet-test79.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/Horos" >/dev/null && { pkill -f "horos-vet/build.*MacOS/Horos"; sleep 3; }

defaults write vet.kappa1.sekhvet.horos CloseAllWindowsBeforeXMLRPCOpen -bool NO

rm -f $LOG
SEKHVET_MPR_TEST=all SEKHVET_DOUBLE_MPR_ZOOM_TEST=$WHICH nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID"
# Horos' Alarm "crashed during last startup" aus +[AppController initialize] wegklicken (bekannte Falle)
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 10

curl -s -m 30 -X POST http://127.0.0.1:8085/ -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 300
echo ""
echo "--- warte auf MPR + Zoomtest ---"
sleep 90
echo "=================== Protokoll ==================="
grep -E "Double-MPR-Zoom|MPR-Test|MPR-Log" $LOG
echo "================================================="
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
