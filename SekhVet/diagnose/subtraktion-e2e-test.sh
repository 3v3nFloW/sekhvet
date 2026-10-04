#!/bin/zsh
# SekhVet Paket CX — Subtraktion (Horos-Fusionsblatt "Subtraction") End-to-End, headless auf dem Studio.
# Oeffnet KM (Ziel) und nativ (Maske) in zwei Fenstern, legt die Maske nach vorne (wie nach dem Ziehen) und ruft
# blendWithViewer:blendingType:2. Prueft je Stichprobe, welche Maskenschicht abgezogen wurde.
# Aufruf: subtraktion-e2e-test.sh <PatientID einer CT-Studie mit nativ/KM>
# Braucht einen Bau MIT Testhaken. Erwartet: Schritt 6 "5 von 5"; Fehlerbild vor CX: immer dieselbe Maskenschicht.
PID_PAT=${1:?PatientID angeben}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/SekhVet
LOG=/tmp/sekhvet-subtraktion-e2e.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/SekhVet" >/dev/null && { pkill -f "horos-vet/build.*MacOS/SekhVet"; sleep 3; }
defaults write vet.kappa1.sekhvet.horos CloseAllWindowsBeforeXMLRPCOpen -bool NO

rm -f $LOG
SEKHVET_SUBTRAKTION_E2E_TEST=1 nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 8
curl -s -m 30 -X POST http://127.0.0.1:8085/ -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 200
echo ""
echo "--- warte 140 s ---"
sleep 120
echo "=================== Protokoll ==================="
grep -E "Subtraktion|Multiplikation" $LOG | sed -E 's/^[0-9-]+ [0-9:.]+ Horos\[[0-9:a-f]+\] //'
echo "================================================="
grep -E "Exception|exception|SIGSEGV|crash" $LOG | head -5
kill -0 $APID 2>/dev/null && echo "App laeuft noch (kein Absturz)" || echo "APP BEENDET/ABGESTUERZT"
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
