#!/bin/zsh
# SekhVet Paket CJ — Ueberlagern End-to-End, headless auf dem Studio.
# Oeffnet die Studie, stapelt den Vorschlag, setzt je ein Oval auf Gefaess (groesste KM-nativ-Differenz) und Knochen,
# liest die Enhancement-Zeile, schaltet mit < / y (Schicht, Zoom, Ausschnitt, Fenster je Serie), speichert die Messungen
# (nur an der Bezugsserie), schaltet im MPR und raeumt auf. Dazu der Selbsttest der Regeln und der Neuabtastung.
# Aufruf: overlay-e2e-test.sh <PatientID of a CT study with native/contrast series>      (z. B. 4 CT-Serien nativ/KM x Br40/Br64)
# Braucht einen Bau MIT Testhaken (-xcconfig SekhVet/SekhVet-Testhaken.xcconfig).
# Erwartet: Selbsttest "alle N ok"; Schritt 1b Drop-Entscheid 0, 1/JA, 0; 1c 2, 1, +1, 2; 1d curMovieIndex wie erwartet;
# Schritt 2 gestapelt JA, 4 Chips, ROI-Listen geteilt JA; Schritt 4 Gefaess Δ >> 0,
# Knochen |Δ| klein; Schritt 6 Schicht/Zoom/Ausschnitt gleich; Schritt 8 Fenster 111/777; 8b Taste ueber das Fenster wechselt die Serie; Schritt 9 Bezug JA, andere nein;
# Schritt 11 MPR-Taste JA, Mittelwert aendert sich; Schritt 12 gestapelt nein, Drop-Entscheid 0;
# 7b ROI rechnet auf der sichtbaren Serie; 11c MPR-Fenster = Soll der Knochenserie; 11d Taste y; 13 Knopf in der echten Leiste,
# 13b/13c Serie ab- und wieder anwaehlen; 14 Chip und X.
PID_PAT=${1:?PatientID angeben}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/SekhVet
LOG=/tmp/sekhvet-overlay-e2e.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/SekhVet" >/dev/null && { pkill -f "horos-vet/build.*MacOS/SekhVet"; sleep 3; }
defaults write vet.kappa1.sekhvet.horos CloseAllWindowsBeforeXMLRPCOpen -bool NO

rm -f $LOG
SEKHVET_OVERLAY_TEST=1 SEKHVET_OVERLAY_E2E_TEST=1 nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 8
curl -s -m 30 -X POST http://127.0.0.1:8085/ -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 200
echo ""
echo "--- warte 140 s ---"
sleep 140
echo "=================== Protokoll ==================="
grep -E "Overlay" $LOG | sed -E 's/^[0-9-]+ [0-9:.]+ Horos\[[0-9:a-f]+\] //'
echo "================================================="
grep -E "Exception|exception|SIGSEGV|crash" $LOG | head -5
kill -0 $APID 2>/dev/null && echo "App laeuft noch (kein Absturz)" || echo "APP BEENDET/ABGESTUERZT"
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
