#!/bin/zsh
# SekhVet Paket AY — Roentgen-Zweiebenen headless.
# Aufruf: zweiebenen-test.sh <Namensteil> [links]
#   links = Einstellung "seitliche Aufnahme links" fuer diesen Lauf, danach wieder Vorgabe (rechts)
# Braucht einen Bau MIT Testhaken. Protokolliert Selbsttest, Paarbildung und die Lage der Viewer.
NEEDLE=${1:?Namensteil der Studie angeben}
SIDE=${2:-rechts}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/Horos
LOG=/tmp/sekhvet-zweiebenen.log
DOM=vet.kappa1.sekhvet.horos

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/Horos" >/dev/null && { pkill -f "horos-vet/build.*MacOS/Horos"; sleep 3; }

if [[ "$SIDE" == "links" ]]; then defaults write $DOM SekhmetTwoViewLateralLeft -bool YES; else defaults delete $DOM SekhmetTwoViewLateralLeft 2>/dev/null; fi

rm -f $LOG
SEKHVET_OPENING_SELFTEST=1 SEKHVET_OPENING_TEST="$NEEDLE" nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID (seitlich $SIDE)"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 60
echo "=================== Protokoll ==================="
grep -E "Zwei-Ebenen|two-view|Oeffnungstest|Selbsttest|Oeffnungsprotokoll|opening protocol" $LOG | sed -E 's/^[0-9-]+ [0-9:.]+ Horos\[[0-9:a-f]+\] //'
echo "================================================="
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
defaults delete $DOM SekhmetTwoViewLateralLeft 2>/dev/null
