#!/bin/zsh
# SekhVet Paket AX — Protokollwechsel nach gedrehtem Fadenkreuz, headless.
# Rueckmeldung 16.09.2026 (Wirbelsaeulen-CT): Fadenkreuz in Head/Spine um 90 Grad gedreht,
# danach griff der Wechsel auf Hindlimbs nicht mehr.
# Aufruf: hp-dreh-test.sh [PatientID] [Drehung "Grad,Verschiebung,vN"] [Preset-Folge] [take]
#   take = nach der Drehung "Take from screen" fuer das aktive Preset (Paket AX), danach wieder entfernt
#   Presets: 1 Head/Spine, 2 Hindlimbs, 3 Forelimbs
# Braucht einen Bau MIT Testhaken (-xcconfig SekhVet/SekhVet-Testhaken.xcconfig).
PID_PAT=${1:?PatientID angeben}
TILT=${2:-90,0,v0}
SEQ=${3:-2,1,3,2}
TAKE=${4:-}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/Horos
LOG=/tmp/sekhvet-hp-dreh.log

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/Horos" >/dev/null && { pkill -f "horos-vet/build.*MacOS/Horos"; sleep 3; }

defaults write vet.kappa1.sekhvet.horos CloseAllWindowsBeforeXMLRPCOpen -bool NO
# gespeicherte MPR-Lagen voriger Laeufe raus — sonst spielt Paket AH einen alten Stand zurueck
defaults delete vet.kappa1.sekhvet.horos SekhmetMPRLastState >/dev/null 2>&1

rm -f $LOG
if [ "$TAKE" = take ]; then export SEKHVET_MPR_TAKE_TEST=1; else unset SEKHVET_MPR_TAKE_TEST; fi
SEKHVET_MPR_TEST=all SEKHVET_MPR_TILT_TEST=$TILT SEKHVET_HP_SWITCH_TEST=$SEQ nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID (Drehung $TILT, Folge $SEQ)"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 10

curl -s -m 30 -X POST http://127.0.0.1:8085/ -H 'Content-Type: text/xml' -d "<?xml version=\"1.0\"?><methodCall><methodName>DisplayStudy</methodName><params><param><value><struct><member><name>PatientID</name><value><string>$PID_PAT</string></value></member></struct></value></param></params></methodCall>" | head -c 300
echo ""
N=$(( ${#${(s:,:)SEQ}} ))
WAIT=$(( 70 + 6 * N ))
echo "--- warte ${WAIT}s auf MPR, Drehung und $N Wechsel ---"
sleep $WAIT
echo "=================== Protokoll ==================="
grep -E "MPR-Test|MPR-Tilt|MPR-Take|HP-Wechsel|Hanging Protocol MPR|HP MPR|geradegerichtet|geraderichten|MPR Kandidat|getResolution: isnan" $LOG | sed -E 's/^[0-9-]+ [0-9:.]+ Horos\[[0-9:a-f]+\] //' | uniq -c | sed -E 's/^ +1 //'
echo "================================================="
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
# Test-Anordnung nicht in der Test-Instanz stehen lassen
if [ "$TAKE" = take ]; then sleep 5; defaults delete vet.kappa1.sekhvet.horos SekhmetMPRLayouts >/dev/null 2>&1; echo "Test-Anordnung entfernt"; fi
