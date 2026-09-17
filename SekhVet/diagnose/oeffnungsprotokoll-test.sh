#!/bin/zsh
# SekhVet Paket AU — Oeffnungsprotokoll headless.
# Aufruf: /tmp/sekh_test80.sh <Namensteil> [black]
#   ohne "black": eingebaute Vorgabeprotokolle (Luecken ruecken auf)
#   mit  "black": Testprotokoll 2x2 mit Luecke in der MITTE, Luecken als schwarze Kachel
NEEDLE=${1:?Namensteil der Studie angeben}
MODE=${2:-plain}
APP=~/Projects/horos-vet/build/Build/Products/Release/Horos.app/Contents/MacOS/Horos
LOG=/tmp/sekhvet-test80.log
DOM=vet.kappa1.sekhvet.horos

curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
sleep 3
pgrep -f "horos-vet/build.*MacOS/Horos" >/dev/null && { pkill -f "horos-vet/build.*MacOS/Horos"; sleep 3; }

defaults write $DOM CloseAllWindowsBeforeXMLRPCOpen -bool NO
defaults delete $DOM SekhmetOpeningProtocols 2>/dev/null

if [[ "$MODE" == "black" ]]; then
  # Position 2 findet nichts -> Zelle 1 (rechts oben) bleibt MITTENDRIN frei.
  defaults write $DOM SekhmetOpeningProtocols '(
    {
      name = "CT Testraster";
      modality = "CT";
      region = "";
      rows = 2;
      columns = 2;
      blackTiles = 1;
      positions = (
        { keywords = ""; without = ""; window = "Soft tissue"; contrast = 1; wl = 0; ww = 0; },
        { keywords = "gibtesnicht"; without = ""; window = ""; contrast = 0; wl = 0; ww = 0; },
        { keywords = ""; without = ""; window = "Bone (vet)"; contrast = 1; wl = 0; ww = 0; },
        { keywords = ""; without = ""; window = "Bone (vet)"; contrast = 2; wl = 0; ww = 0; }
      );
    }
  )'
  echo "Testprotokoll 2x2 mit schwarzen Kacheln gesetzt"
fi

rm -f $LOG
SEKHVET_OPENING_SELFTEST=1 SEKHVET_OPENING_TAKE_TEST=1 SEKHVET_OPENING_TEST="$NEEDLE" nohup $APP > $LOG 2>&1 &
APID=$!
echo "gestartet, PID $APID"
sleep 10
lldb -p $APID --batch -o 'expression (void)[NSApp stopModalWithCode: 1]' -o detach >/dev/null 2>&1
sleep 60
echo "=================== Protokoll ==================="
grep -E "Oeffnungsprotokoll|Oeffnungstest" $LOG
echo "================================================="
curl -s -m 5 -X POST http://127.0.0.1:8085/ -d '<?xml version="1.0"?><methodCall><methodName>KillOsiriX</methodName><params></params></methodCall>' >/dev/null 2>&1
defaults delete $DOM SekhmetOpeningProtocols 2>/dev/null
