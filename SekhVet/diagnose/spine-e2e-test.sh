#!/bin/zsh
# SekhVet Paket BR — Spine Labeling End-to-End, headless.
# Setzt L1-L3 in die erste Serie (>= 30 Schichten), prueft Studienliste + JSON-Datei, loggt die Hoehenfolge je Schicht
# in ALLEN offenen Serien der Studie, benennt L1 in T13 um (Neuzaehlung) und loescht die Punkte wieder.
# Aufruf: spine-e2e-test.sh <PatientID>
# Braucht einen Bau MIT Testhaken (-xcconfig SekhVet/SekhVet-Testhaken.xcconfig).
# Erwartet: Schritt 2 "- L1 L1-L2 L2 L2-L3 L3 -" in jeder Serie, Schritt 4 "- T13 T13-L1 L1 L1-L2 L2 -", Schritt 6 "Liste 0 ... weg".
PID_PAT=${1:?PatientID angeben}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/Horos
LOG=/tmp/sekhvet-spine-e2e.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/Horos" >/dev/null && { pkill -f "horos-vet/build.*MacOS/Horos"; sleep 3; }
defaults write vet.kappa1.sekhvet.horos CloseAllWindowsBeforeXMLRPCOpen -bool NO

rm -f $LOG
SEKHVET_SPINE_E2E_TEST=1 nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 8
curl -s -m 30 -X POST http://127.0.0.1:8085/ -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 200
echo ""
echo "--- warte 65 s ---"
sleep 65
echo "=================== Protokoll ==================="
grep -E "Spine-E2E|spine labels" $LOG | sed -E 's/^[0-9-]+ [0-9:.]+ Horos\[[0-9:a-f]+\] //'
echo "================================================="
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
