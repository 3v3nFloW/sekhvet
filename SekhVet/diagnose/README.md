# SekhVet Diagnose ohne Bildschirm

Screenshots per ssh scheitern an TCC. Stattdessen:

1. SekhVet (Debug-Build, nur fuer lldb) starten und CT-Studie per XML-RPC (Port 8085, in den SekhVet-Prefs eingeschaltet) oeffnen: bash start-und-pruefen.sh
2. Fensterliste (Lage, Sichtbarkeit) ohne Screen-Recording: swift fensterliste.swift <pid>
3. View-Baum von Werkzeugleiste, DB- und Viewer-Fenster: lldb -p <pid> --batch -s toolbar-layout.lldb

lldb-Fallen: @import AppKit greift nicht, Struct-Literale (CGRect) und variadische Methoden scheitern -> nur po mit Casts und App-eigene Methoden rufen.
defaults-Falle: die CLI loest vet.kappa1.sekhvet.horos auf den alten Sandbox-Container auf; immer mit Pfad ~/Library/Preferences/vet.kappa1.sekhvet.horos.plist arbeiten.

Sauber beenden statt pkill (nur dann speichert AppKit den Fensterzustand):
  curl -s -X POST http://127.0.0.1:8085/ -H "Content-Type: text/xml" --data "<?xml version=\"1.0\"?><methodCall><methodName>KillOsiriX</methodName><params><param><value><struct></struct></value></param></params></methodCall>"
Fensterzustand unter macOS 26: ~/Library/Daemon\ Containers/<UUID>/Data/Library/Saved\ Application\ State/<UUID>.savedState/windows.plist (per UUID, nicht Bundle-ID).

## Testskripte der Pakete AT/AU/AV (15.09.2026)

Beide brauchen einen Bau **mit** Testhaken:
`xcodebuild … -xcconfig SekhVet/SekhVet-Testhaken.xcconfig` — danach ohne die xcconfig neu
bauen, bevor die App installiert oder weitergegeben wird.

- `double-mpr-zoom-test.sh <PatientID> <Ansicht 1..3>` — Paket AT/AV. Oeffnet die Studie,
  macht in jedem Viewer eine MPR auf (`SEKHVET_MPR_TEST=all`), klickt synthetisch doppelt in
  die genannte Ansicht des ersten MPR-Fensters und protokolliert je Fenster Zoomzustand,
  Ansichtshoehen, Fadenkreuz, vrView-Groesse, WL/WW und LOD — vor dem Klick, SOFORT danach und
  1,5 s spaeter. Ein `<-- ENTARTET (0 Pixel)` in der Ausgabe ist der Fehler aus Paket AV.
- `oeffnungsprotokoll-test.sh <Namensteil> [black]` — Paket AU/AV. Selbsttest der
  Kontrasterkennung, dann Protokollwahl, Kandidatenserien mit Suchtext/Fensterregel/Kontrast,
  Belegung je Position, Oeffnen, Lage und WL/WW der Viewer, schwarze Kacheln; mit `black` ein
  Testraster 2x2 mit unbesetzter Position in der Mitte. `SEKHVET_OPENING_TAKE_TEST=1` haengt
  ausserdem "Take from screen" auf ein Wegwerf-Protokoll an.

**Warum im Repo und nicht in /tmp:** die Skripte der Pakete AM/AN lagen in `/tmp` und waren
beim naechsten Zugriff weg.

## Testskripte der Pakete AX/AY (16.09.2026)

Beide brauchen ebenfalls den Bau **mit** Testhaken.

- `hp-dreh-test.sh <PatientID> <"Grad,mm,vN"> <Preset-Folge> [take]` — Paket AX. Oeffnet die
  Studie, macht in jedem Viewer eine MPR auf, dreht bei 12 s das Fadenkreuz in Ansicht N um die
  angegebenen Grad (`90,0,v0` = der gemeldete Handgriff vom 16.09.: Fenster 2 und 3 tauschen die
  Ebene), und schaltet ab 20 s alle 6 s die Presets der Folge (1 Head/Spine, 2 Hindlimbs,
  3 Forelimbs). Protokolliert je Fenster Buchstaben, Normale, Kamera und `<-- NaN`.
  Mit `take` wird bei 16 s "Take from screen" fuer das aktive Preset ausgefuehrt und die
  Test-Anordnung am Ende wieder geloescht.
  Grundbelegung (ohne eigene Anordnung): Ansicht 0 Normale x, Ansicht 1 z, Ansicht 2 y.
- `zweiebenen-test.sh <Namensteil> [links]` — Paket AY. Selbsttest (Kontrast + Zwei-Ebenen),
  Paarbildung, Oeffnen, Lage der Viewer (x-Koordinate). `links` schaltet fuer den Lauf
  "seitliche Aufnahme links" ein. Testpaare in der Test-Datenbank: Katzogramm, Abdomen,
  Thorax — bei allen dreien hat die SEITLICHE die kleinere Seriennummer,
  Horos allein wuerde sie also links haengen.
