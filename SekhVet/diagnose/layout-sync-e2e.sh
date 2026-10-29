#!/bin/zsh
# SekhVet Paket EH — Ansichtsgroessen zwischen zwei MPR-Fenstern (Double MPR), headless auf dem Studio.
# Aufruf: layout-sync-e2e.sh <PatientID einer CT-Studie mit zwei Volumenserien>   (ID aus der eigenen Datenbank)
# Braucht einen Bau MIT Testhaken in build-test/ (~/Projects/horos-vet-bau-test.sh).
# Erwartet: sechs Zeilen "Schritt n ... -> OK", "ERGEBNIS 6/6", keine "ENTARTET", kein "ZIEHEN GRIFF NICHT".
PID_PAT=${1:?PatientID angeben}
APP=~/Projects/horos-vet/build-test/Build/Products/Release/Horos.app/Contents/MacOS/SekhVet
LOG=~/Projects/sekhvet-layout-sync-e2e.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d "<?xml version=\"1.0\"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>" >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/SekhVet" >/dev/null && { echo "laeuft noch eine Instanz - abgebrochen"; exit 1; }
defaults write ~/Library/Preferences/vet.kappa1.sekhvet.horos.plist CloseAllWindowsBeforeXMLRPCOpen -bool NO

rm -f $LOG
SEKHVET_MPR_TEST=all SEKHVET_MPR_LAYOUT_TEST=1 nohup $APP > $LOG 2>&1 < /dev/null &
APID=$!
echo "gestartet, PID $APID"
sleep 20
curl -s -m 30 -X POST http://127.0.0.1:8085/ -H "Content-Type: text/xml" -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 120
echo ""
echo "--- warte auf MPR (45 s nach Start) + Layout-Test (25 s spaeter, ~25 s Dauer) ---"
sleep 95
echo "=================== Protokoll ==================="
grep -E "Layout-Sync|MPR-Test: kein|MPR layout sync" $LOG | sed -E "s/^[0-9-]+ [0-9:.]+ SekhVet\[[0-9:a-f]+\] //"
echo "================================================="
grep -E "Exception|exception|SIGSEGV|crash" $LOG | head -5
kill -0 $APID 2>/dev/null && echo "App laeuft noch (kein Absturz)" || echo "APP BEENDET/ABGESTUERZT"
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d "<?xml version=\"1.0\"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>" >/dev/null 2>&1
