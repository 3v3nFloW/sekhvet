# SekhVet — Anleitung (Deutsch)

Version 1.0, Build 174 · Stand 04.10.2026

> **SekhVet ist ein veterinärmedizinischer DICOM-Viewer und kein zertifiziertes Medizinprodukt.**
> Es ist weder FDA-cleared noch CE-gekennzeichnet und hat keine formale Validierung durchlaufen.
> Es ist ausschliesslich für Veterinärmedizin, Forschung und Lehre bestimmt und darf nicht für
> die Diagnose oder Behandlung von Menschen eingesetzt werden. Messwerkzeuge und
> Orientierungshilfen sind Hilfsmittel; Bildinterpretation und Diagnose bleiben in der
> Verantwortung der Tierärztin oder des Tierarztes. SekhVet wird ohne Gewährleistung
> bereitgestellt (GNU LGPL v3).

> **Version 1.0.** SekhVet 1.0 ist die erste reguläre Version nach der öffentlichen Beta
> (Builds 45–149, August bis Oktober 2026). Der Horos-Kern und die Vet-Werkzeuge sind in einer
> Praxis täglich im Einsatz; einige Funktionen sind als *neu in 1.0* markiert, weil sie erst an
> wenigen Geräten geprüft sind. Abschnitt 7 zählt sie auf. Bitte melden Sie, was Ihnen auffällt
> (Abschnitt 5.15).

## 1. Was SekhVet ist

SekhVet ist ein Fork von Horos 4.0 (horosproject.org), das seinerseits auf OsiriX beruht.
Der Horos-Kern ist unverändert: Datenbank, 2D-Viewer, 3D-MPR, Volume Rendering, CPR,
Fusion, Subtraktion, Key Images, Export, DICOM-Netzwerk (C-STORE, C-FIND, C-MOVE, WADO-URI),
Plugins. Alles, was Sie in Horos kennen, funktioniert gleich.

Dazu kommt eine Schicht veterinärmedizinischer Funktionen, gesammelt im Menü **Vet Tools**,
plus eine Reihe von Bedienverbesserungen. Die Oberfläche von SekhVet ist Englisch.

Entwickelt und gepflegt von der Kappa1-VRS GmbH, Zürich. Lizenz GNU LGPL-3.0, Quellcode auf
GitHub. Horos wird seit 2025 kaum noch gepflegt; SekhVet ist ein eigenständiger Pflegefork,
kein Upstream-Beitrag.

## 2. Systemvoraussetzungen

| | |
|---|---|
| Mac | Apple Silicon (M1 oder neuer). Kein Intel-Build. |
| macOS | 12 Monterey oder neuer. Getestet unter macOS 26 Tahoe (täglich) und macOS 27 (Testinstallation, Double MPR mit grossem CT). |
| Bildschirm | Läuft auf jedem Bildschirm; die Funktion „Screen Area" ist für breite Monitore gedacht. |
| Netz | Für DICOMweb einen Server mit QIDO-RS/WADO-RS (z. B. Orthanc mit DICOMweb-Plugin). |

## 3. Installation

1. `SekhVet-1.0-build174-macOS.dmg` von der Releases-Seite
   https://github.com/3v3nFloW/sekhvet/releases laden und öffnen. Die Zip-Datei auf derselben
   Seite enthält dieselbe App, für alle, die das lieber mögen.
2. Im geöffneten Fenster SekhVet auf den Ordner „Programme“ ziehen, danach das Laufwerk
   auswerfen. Liegt dort schon eine ältere SekhVet-Kopie: **zuerst beenden**, dann ersetzen. Laufen zwei Kopien mit
   eingeschaltetem DICOM-Listener gleichzeitig, meldet die zweite „DICOM Listener Error", weil der Empfangsport schon belegt ist.
3. **Gatekeeper:** SekhVet ist ad hoc signiert, nicht notarisiert (kein Apple-Developer-Konto).
   Der erste Start wird von macOS blockiert. Danach: **Systemeinstellungen › Datenschutz &
   Sicherheit › „Trotzdem öffnen"**. Seit macOS 15 gibt es den Rechtsklick-Umweg nicht mehr.
   Alternative im Terminal:
   ```
   xattr -d com.apple.quarantine /Applications/SekhVet.app
   ```
4. Beim ersten Zugriff auf den Ordner „Dokumente" fragt macOS nach Erlaubnis. „Erlauben" klicken,
   sonst bleibt das Fenster leer.
5. **Beim ersten Start** zeigt SekhVet einmalig den Hinweis, dass es kein zertifiziertes
   Medizinprodukt ist. „I understand" bestätigt ihn, „Quit" beendet das Programm. Der Hinweis
   kommt erst wieder, wenn sich sein Wortlaut ändert. Direkt danach fragt SekhVet einmal, ob es
   täglich auf GitHub nach Updates sehen darf („SekhVet can check GitHub once a day …“):
   **Check for Updates** oder **Don't Check**; umschaltbar später unter Preferences › General.
6. Prüfsumme (optional): `shasum -a 256 SekhVet-1.0-build174-macOS.dmg` (oder die Zip)
   muss mit dem Wert auf der Releases-Seite übereinstimmen.

**SekhVet neben Horos oder OsiriX:** SekhVet hat eine eigene Datenbank
(`~/Documents/SekhVet Data`), eigene Einstellungen und einen eigenen Plugin-Ordner
(`~/Library/Application Support/SekhVet/Plugins`); Web-Portal-Benutzer und Vorlagen liegen
ebenfalls unter `~/Library/Application Support/SekhVet/` und starten leer. Horos und OsiriX
bleiben unberührt und können parallel installiert bleiben. Alles, was eine URL mit `sekhvet://`
öffnet, landet in SekhVet; `horos://` bleibt bei Horos.

**Netz: der DICOM-Listener ist ab Werk aus.** Eine frische Installation empfängt nichts, meldet
sich nicht per Bonjour und beantwortet weder C-FIND noch C-GET; ihre Kennung im Netz ist eine
Zufalls-UUID. Senden an andere Knoten geht sofort, DICOMweb (5.12) ebenfalls. Für den Empfang:
**Preferences › Listener**, Listener einschalten, Port (Vorschlag 11113; Horos: 11112, damit
beide gleichzeitig laufen können) und AE-Titel setzen, dann SekhVet neu starten. Ohne Listener
gibt es kein klassisches Query/Retrieve (die Abfrage meldet das). „Reset preferences“ schaltet
den Listener wieder aus. SekhVet prüft keine Plugin-Updates; der Web-Reiter des Plugin-Managers
ist leer.

**Updates:** SekhVet kann einmal täglich auf GitHub nach einer neuen Version sehen (Frage beim
ersten Start, umschaltbar unter Preferences › General). Geprüft wird höchstens alle 24 Stunden,
etwa 15 Sekunden nach dem Start, und nur gegen reguläre Releases. Gibt es eine neuere Version,
zeigt ein Dialog die Release Notes an und bietet **Download** (öffnet die DMG-Adresse im
Browser), **Release Notes**, **Later** und das Häkchen **Skip this version**. SekhVet installiert
nichts selbst: das DMG lädt und installiert man von Hand, ein neuer Build wird einfach über den
alten kopiert (vorher beenden); Datenbank und Einstellungen bleiben erhalten. **SekhVet ›
Check for Updates** prüft sofort und meldet „up-to-date (build N)“ oder „No Internet
connection“; trägt ein Release keine Build-Nummer, sagt SekhVet, dass es den Stand nicht
vergleichen kann, und bietet **Open Releases Page** an.

**Datenbank-Index:** Lässt sich der Index beim Start nicht öffnen, bietet der Dialog **Try
Again**, **Reveal in Finder**, **Reset SQL Index…** und **Quit SekhVet**; vor einem Neuaufbau
wird der alte Index immer gesichert.

## 4. Erste Schritte

1. Studien hereinholen wie in Horos: Dateien ins Fenster ziehen, **File › Import**, DICOM-Empfang
   (nach dem Einschalten des Listeners, Abschnitt 3), per DICOMweb (Abschnitt 5.12) oder aus
   einer Horos-/OsiriX-Datenbank (5.18). Während des Empfangs zeigt das Dock das SekhVet-Signet
   mit Pfeil.
2. Studie per Doppelklick öffnen. Welche Serien aufgehen und wie sie hängen, bestimmen die
   Öffnungsprotokolle (5.3) und das Hanging Protocol (5.2). Röntgenstudien mit genau zwei
   Aufnahmen hängen VD links, seitlich rechts (5.3).
3. In der Serienleiste des Viewers und in der Vorschau der Datenbank tragen die Miniaturen
   **Plaketten**: bei MRT die Sequenz (T1, T2, FLAIR, STIR …), bei CT und MRT **KM** für eine
   Kontrastmittelserie und SUB für Subtraktionen. Der Serienname steht in bis zu drei Zeilen
   unter der Miniatur, der volle Name als Tooltip.
4. Die eigenen Fenster von SekhVet öffnen sich innerhalb der Viewer-Fläche und stehen im Menü
   **Vet Tools**. Das Hilfe-Menü enthält nur noch **Report a bug** (öffnet die SekhVet-Issues).

## 5. Vet Tools im Einzelnen

### 5.1 Veterinäre Randbuchstaben

Horos schreibt A/P, S/I, R/L an die Bildränder. SekhVet schreibt **Cr/Cd** (kranial/kaudal),
**D/V** (dorsal/ventral) und **R/L**; in 2D, im MPR und am Orientierungswürfel der 3D-Fenster.

Die Zuordnung: A → V, P → D, S → Cr, I → Cd; R und L bleiben.

Die Buchstaben sind ab Werk an. Wer die Horos-Buchstaben zurückhaben will, tippt im Terminal:
```
defaults write vet.kappa1.sekhvet.horos VetOrientationLetters -bool NO
```
und startet SekhVet neu.

### 5.2 Hanging Protocol (Vet Tools › Hanging Protocol…)

Ein Hanging-Protokoll legt fest, **wie eine Serie auf dem Bildschirm gedreht wird**: welche
anatomische Richtung oben und welche links steht — in 2D-Fenstern und in den drei Ebenen des
3D-MPR. Es ist eine reine Anzeigetransformation (Drehung und Spiegelung), die Bilddaten werden
nie verändert. Welche Serien aufgehen und in welchem Raster, regeln dagegen die
Öffnungsprotokolle (5.3).

**Die Protokolle.** Mitgeliefert sind *Head / Spine*, *Hindlimbs*, *Forelimbs*, *Custom 1* und
*Custom 2*, dazu **Off**. Mit Off verhält sich SekhVet wie Horos und stellt die zuletzt
gespeicherte Ausrichtung wieder her. Die Liste links im Fenster gehört Ihnen:

| Sie möchten … | So geht es |
|---|---|
| ein Protokoll anlegen | **+** unter der Liste, Namen eintippen. Es beginnt mit den Regeln von Head / Spine. |
| ein Protokoll umbenennen | Doppelklick auf den Namen. |
| die Reihenfolge ändern | Zeile ziehen. Die Popups in den Werkzeugleisten von Viewer und MPR folgen dieser Reihenfolge. |
| ein Protokoll löschen | markieren, **−**. Seine Regeln, MPR-Anordnung und Stichwörter gehen mit; Studien, die es benutzt haben, fallen auf Stichwort oder Vorgabe zurück. Die drei eingebauten (Head / Spine, Hindlimbs, Forelimbs) lassen sich umbenennen und verschieben, aber nicht löschen. |

Umbenennen und Umsortieren macht nichts kaputt: Stichwörter, Regeln, MPR-Anordnung und die je
Studie gemerkte Wahl hängen am Protokoll selbst, nicht an seinem Namen oder Platz. Das Fenster
ist in der Grösse veränderbar und merkt sich seine Grösse.

**Regeln des markierten Protokolls** (rechte Seite; zuerst ein Protokoll markieren). Die vier
Regel-Schalter gelten für Protokolle **ohne eigene MPR-Anordnung** („Standard layout“); hat ein
Protokoll eine Anordnung („Take from screen“, siehe unten), bestimmt diese die Ausrichtung je
Ebene, und die Schalter wirken nicht.

| Regel | an | aus |
|---|---|---|
| Transverse: dorsal up | dorsal oben | ventral oben |
| Sagittal: cranial left | kranial links, dorsal oben | kranial/proximal oben (Gliedmassen) |
| Dorsal plane: cranial up | kranial oben | kranial links |
| Patient left on the right side of the image | radiologische Konvention | links ist links |
| Limb: proximal = caudal (forelimb) | nach vorn gestreckte Vordergliedmasse: kaudal (= proximal) oben | — |

**Welches Protokoll eine Studie bekommt**, in dieser Reihenfolge:

1. was Sie für diese Studie im **Popup „Hanging Protocol“** der Viewer- oder MPR-Werkzeugleiste
   gewählt haben (bleibt je Studie gemerkt, auch nach einem Neustart). Der erste Eintrag des
   Popups, **Automatic (by keywords)**, hebt diese Wahl wieder auf;
2. das **Stichwort**, das in Studien- oder Serienbeschreibung vorkommt (Tabelle „Keywords“:
   Text → Protokoll; z. B. „Ellbogen“, „Schulter“, „Karpus“ → Forelimbs). Passen mehrere, gewinnt
   das längste; kurze Stichwörter zählen nur als ganzes Wort („Kopf“ trifft nicht „Kopfstütze“);
3. das **Vorgabe-Protokoll** oben im Fenster.

**3D-MPR.** Die drei Ebenen werden so gedreht, dass die Randbuchstaben stimmen (bei Head /
Spine: sagittal Cr links, transversal D oben, dorsal Cr oben), auch wenn die Ebenen vorher
schräg standen. Um festzulegen, *welche Ebene in welcher der drei Ansichten liegt*: ein
MPR-Fenster so anordnen wie gewünscht, das Protokoll in der Liste markieren, **Take from
screen** drücken. Jedes MPR-Fenster, das mit diesem Protokoll aufgeht oder darauf umgeschaltet
wird, ordnet sich danach so an. **Standard layout** nimmt die Anordnung wieder weg. Die zuletzt
geradegestellte Lage einer Serie wird je Protokoll gemerkt; sie gilt nur, solange die Regeln
des Protokolls unverändert sind. Der Fenstertitel des MPR zeigt den Stand, z. B. „HP: Head /
Spine“ oder „HP: Head / Spine (not applied: oblique)“; mit **Off** kehrt der schlichte Titel
zurück. Vor „Reset“ fragt SekhVet nach.

**Eine MPR-Anordnung gilt auch in 2D und im Orthogonal-MPR.** Hat ein Protokoll eine Anordnung,
bestimmt sie die Ausrichtung je Ebene nicht nur im 3D-MPR, sondern auch in den 2D-Fenstern und
im 2D Orthogonal MPR. Beispiel Knie-MRT: die sagittale Serie steht im 2D-Fenster so wie im MPR
(kaudal oben, dorsal links), auch wenn sie frisch in ein Fenster gezogen wird. Das Popup
„Hanging Protocol“ gibt es ausserdem im **Curved MPR** und im **2D Orthogonal MPR**; dort werden
die Ebenen wie im 3D-MPR gerichtet (im Curved MPR bleibt die Achsen-Anordnung, wie sie ist).

**Röntgen (DX/CR)** hat keine Ebenen und bekommt stattdessen eine Regel je Quelle: Text im
StationName oder in der Modalität → Drehung und Spiegelung. Bilder eines Geräts, das „immer
falsch ankommt“, hängen damit vom ersten Öffnen an richtig.

**Apply to open viewers** (Knopf, und Vet Tools › Apply Hanging Protocol to Open Viewers)
wendet die aktuellen Einstellungen auf alle offenen Fenster an. Localizer und schräge Serien
werden gekennzeichnet, nicht gedreht. Die Fensterung bleibt unberührt (siehe 5.4).

**Zwei MPR-Fenster nebeneinander.** Mit „Tile 3D windows automatically when opened“ (Vet Tools ›
Display) stehen die MPR-Fenster in der Reihenfolge ihrer 2D-Quellserien: das MPR der linken
Serie steht links, auch wenn Sie ein Fenster vorher verschoben haben. Ohne die Option
platzieren Sie MPR-Fenster selbst; ein MPR öffnet dann über seinem eigenen 2D-Fenster.

### 5.3 Öffnungsprotokolle (Vet Tools › Opening Protocols (which series open)…)

Legt je Modalität und Körperregion fest, **welche Serien** beim Doppelklick aufgehen, in welcher
Anordnung und mit welcher Fensterung. Greift ein Protokoll, macht es alles; greift keines, öffnet
Horos wie gewohnt.

- **Erkennung** aus der ersten Datei jeder Serie: Region aus Serienname, Protokollname und
  Körperregion; bei CT die Fensterregel (z. B. Soft tissue, Bone) aus dem Faltungskern und die
  Kontrastphase (nativ / KM als ganzes Wort); bei MR der Sequenzname.
- **Vorlagen** für MR Kopf (2×2: T2 sag · T2 tra · T1 tra · T1 tra post KM), Wirbelsäule (1×2)
  und Knie (1×4); alles editierbar. Leere Kacheln wahlweise schwarz füllen.
- **Take from screen:** Studie so öffnen, wie sie sein soll, dann den Knopf drücken; die
  Positionen des gewählten Protokolls füllen sich aus den offenen Fenstern.
- **Röntgen-Zweiebenen:** hat eine Studie genau zwei Röntgenaufnahmen derselben Körperregion,
  hängt die VD/DV-Aufnahme links und die seitliche rechts. Schalter und Seitenwahl („lateral on
  the left") im selben Panel.

### 5.4 Fensterungs-Presets (Vet Tools › Window Presets (WL/WW)…)

Das Panel hat zwei Teile.

**Regeln beim Öffnen.** Regeln „Modalität + Beschreibung enthält … → Fensterwerte" (z. B.
Bone (vet), Soft tissue), die beim Öffnen einer Serie greifen. Die erste passende Regel von oben
gewinnt. Bei einem CT mit Faltungskern im Header entscheidet **nur der Kern** (Knochenkern →
Knochenfenster), nicht der Serienname. Ein Fenster, das Sie selbst verstellt und mit der Serie
gespeichert haben, bleibt beim Wiederöffnen erhalten; die Regeln greifen nur beim ersten
Öffnen. Die Öffnungsprotokolle (5.3) verwenden dieselben Regelnamen.

**Globale WL/WW-Presets.** Die Tabelle darunter enthält die Presets des WL/WW-Menüs in jedem
Viewer, zum Beispiel „CT - Bone" oder „CT - Abdomen". Name, WL und WW lassen sich direkt
ändern; **+** legt ein Preset an, **−** löscht das markierte, **Reset presets to defaults** stellt
die SekhVet-Werte wieder her. Offene Viewer übernehmen Änderungen sofort. Die Tasten 1–9 wenden
die Presets in der alphabetischen Reihenfolge der Tabelle an.

### 5.5 Spine Labeling (Vet Tools › Spine Labeling…)

Wirbel per Klick zählen, im CT (2D oder MPR) und im MRT. Nicht für Röntgenbilder gedacht.

**Wohin klicken — das ist wichtig.** Setzen Sie jeden Punkt **in die Mitte des Wirbelkörpers**,
auf einem sagittalen Bild nahe der Medianen. Aus diesen Punkten leitet SekhVet die Höhe jeder
anderen Schicht ab: auf der Strecke von einer Wirbelkörpermitte zur nächsten gehören die ersten
40 % zum ersten Wirbel, die letzten 40 % zum nächsten, und die **mittleren 20 % werden als
Zwischenwirbelspalt angezeigt** („L3-L4“). Gleichmässig mittig gesetzte Punkte ergeben
Bandscheiben-Labels, die auf der Bandscheibe liegen; ein Punkt an der Endplatte verschiebt die
Bandscheibenzone um genau diesen Betrag. Vor dem ersten und nach dem letzten beschrifteten
Wirbel wird die Höhe noch einen halben Wirbelabstand weit angezeigt, danach nichts.
Sonderfälle: C1 — Mitte des Atlasrings auf Höhe des Dens; Kreuzbein — ein Punkt je Segment oder
nur S1; Blockwirbel oder Übergangswirbel — siehe „Formula“ unten.

**Schritt für Schritt**

1. **Spine Labeling** in der Werkzeugleiste des 2D- oder MPR-Fensters drücken (oder das Menü).
   Das Fenster öffnet sich, das Beschriften läuft, das Punkt-Werkzeug ist gewählt.
2. **Species** setzt die Wirbelformel (**Dog / Cat 7-13-7-3**, **Rabbit 7-12-7-4**,
   **Horse 7-18-6-5** = C-T-L-S). **Formula:** eine Zahl ändern, wenn dieses Tier abweicht — z. B.
   L = 6 oder 8, T = 12 oder 14 bei einem Übergangswirbel. Die geänderte Formel wird mit der
   Studie gespeichert; Zählen und Neuzählen folgen ihr (bei L = 6 folgt S1 auf L6).
3. **Start at:** der Wirbel, den Sie zuerst anklicken, z. B. L1 — einen wählen, den Sie sicher
   bestimmen können (letzte Rippe → T13, Kreuzbein → L7, C2).
4. Den ersten Wirbel anklicken, dann den Nachbarn. Mit **Direction: Automatic** nimmt SekhVet
   die Zählrichtung aus diesen ersten zwei Klicks (Richtung Schwanz = aufwärts zählen, Richtung
   Kopf = abwärts). Bei ungewöhnlicher Lagerung die Richtung von Hand wählen. Das nächste Label
   steht im Fenster und oben im aktiven Bild („Spine ▸ next: L3“).
5. Weiterklicken; die Übergänge C7→T1, T13→L1, L7→S1, S3→Cd1 kommen von selbst.
6. **Bandscheiben:** ein Klick **zwischen** zwei beschriftete Nachbarn wird zu „L3-L4“, ohne dass
   das Zählwerk weiterläuft; zwischen zwei Wirbeln, die nicht Nachbarn sind (L2 und L5), gibt es
   kein Bandscheiben-Label. **Alt-Klick** erzwingt während des Zählens eine Bandscheibe
   zwischen dem letzten und dem nächsten Wirbel.
7. **⌫** nimmt das letzte Label zurück; ist in der Liste eine Messung ausgewählt, löscht ⌫ diese,
   auch während des Beschriftens. **Esc**, **Stop** oder das Schliessen des Fensters beendet
   das Beschriften; in jedem Fenster kommt das vorher gewählte Werkzeug zurück. Zählen in
   Richtung Kopf endet bei C1.

**Label colour** (Farbfeld in der Zeile von „Delete label“) bestimmt die Farbe der Höhenanzeige,
der projizierten Marker und der Namen der Label-Punkte. Vorgabe: das bisherige Grün.

**Was Sie danach sehen**

- **Transversale Bilder** — jede Serie der Studie mit demselben Frame of Reference und die
  transversale MPR-Ansicht — zeigen die Höhe gross und grün oben im Bild: „L3“, zwischen zwei
  Wirbeln „L3-L4“. Das läuft beim Scrollen mit und braucht keine Punkte in dieser Serie. Die
  Höhe läuft über mehrere Serien weiter: bei einer Thorax- und einer Abdomen-Serie zeigt die
  Abdomen-Serie L1, L2 … und nicht „T13“ bis zum Becken.
- Die **dorsale MPR-Ansicht** zeigt genauso die Höhe an der Stelle des Fadenkreuzes.
- Die **sagittale Ansicht** zeigt die Punkte mit Namen; in anderen sagittalen Serien der Studie
  erscheinen sie als kleine Kreise mit Hilfslinie.
- **Show the label points** (Haken im Fenster) blendet alle Punkte auf einmal aus und ein; die
  Höhenanzeige bleibt. Beim Start des Beschriftens werden die Punkte wieder eingeblendet.
- **… also in the transverse and dorsal views** ist in der Vorgabe aus, damit die Punkte diese
  Ansichten nicht stören. Einschalten, wenn Sie einen Punkt dort sehen oder **verschieben**
  möchten, z. B. um ihn links–rechts zu zentrieren.

**Korrigieren**

- Punkt **ziehen** = verschieben; die Höhenanzeige folgt.
- **Umbenennen mit Neuzählung:** Doppelklick auf ein Label in der Liste des Fensters (oder auf
  den Punkt selbst) und den richtigen Namen eintippen, z. B. L1 → T13. Alle Labels kaudal davon
  werden neu gezählt, Bandscheiben eingeschlossen, nach der Formel dieser Studie. So korrigiert
  man einen Zählfehler am Anfang.
- Die **Liste** im Fenster zeigt alle Labels der Studie. Ein Klick springt in allen 2D-Fenstern
  der Studie auf diese Schicht. **Delete label** löscht eines, **Delete all** alle Labels der
  Studie. Umbenennen und Löschen setzen voraus, dass die Serie offen ist, in der das Label
  gesetzt wurde.

Labels sind gewöhnliche Punkt-ROIs, die die Datenbank wie in Horos mit der Serie speichert.
Zusätzlich hält SekhVet die 3D-Lagen je Studie im Ordner `SPINE` des Datenordners; daraus
zeigen die anderen Serien die Höhe.

### 5.6 Norberg-Winkel (Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset)

HD-Auswertung am VD-Becken (gestreckte Aufnahme). Der Toolbar-Knopf **Norberg Angle** ist ein
**Umschaltknopf**: gedrückt heisst, die Messung liegt auf dem Bild. Ein Klick legt im vordersten
2D-Fenster zwei Femurkopfkreise (R blau, L rot) und zwei Punkte für den kranialen Pfannenrand
an; ein zweiter Klick nimmt die Messung wieder weg (**⌘Z** holt sie zurück). Der Knopf folgt dem
Bild: blättert man zu einer Aufnahme mit Messung, ist er gedrückt.

- **Kreis verschieben:** am Zentrum fassen und ziehen (grosse Trefferzone).
- **Radius ändern:** gelben Griff aussen am Kreis ziehen, oder **Mausrad** über dem Kreis
  (gesperrte Kreise reagieren nicht auf das Mausrad).
- **Pfannenrand:** Punkt an den kranialen Acetabulumrand ziehen.
- Der Winkel wird live gezeichnet (Arm, Bogen, Wert bei 10 Uhr für R, 2 Uhr für L) und im
  Namen des Punkts gespeichert („Norberg R: 104.3°"). Er bleibt in der Datenbank und kommt beim
  nächsten Öffnen zurück.
- **Reset:** Menü **Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset** legt die Messung
  neu in die Fenstermitte. **Delete Norberg Measurement** im selben Menü entfernt sie. Setzen,
  Reset und Löschen lassen sich mit ⌘Z widerrufen. Löscht man einen Femurkopfkreis von Hand,
  verschwindet der Rest der Messung mit.
- Bildschirm links = Patient rechts (VD-Konvention). Spiegeln des Bildes ändert die Zuordnung
  nicht. Zeigt das Gerät das Becken gespiegelt, tauscht **Vet Tools › Hip Measurement: Exchange
  Sides R ↔ L** die Beschriftung; Geometrie und Werte bleiben.

Gemessen wird der Innenwinkel zwischen der Zentrenlinie und der Linie Zentrum → Pfannenrand,
in Millimetern über das Pixel-Spacing der Aufnahme, auf 0,1° gerundet. Ein kaudal statt
kranial gesetzter Punkt liefert denselben Innenwinkel; der Punkt gehört an den kranialen Rand.
**Nicht enthalten:** Flückiger-Schema und automatische HD-Grad-Zuordnung. Die Beurteilung nach
FCI oder einem anderen Schema nimmt die Tierärztin oder der Tierarzt selbst vor.

### 5.7 Distraktionsindex (Vet Tools › Distraction Index (PennHIP) — Place / Reset)

Laxitätsmessung auf der **Distraktionsaufnahme** nach der PennHIP-Formel. Der Toolbar-Knopf
**Distraction Index** ist wie der Norberg-Knopf ein Umschaltknopf (gedrückt = Messung liegt auf
dem Bild, zweiter Klick entfernt sie, ⌘Z holt sie zurück). Er legt je Seite zwei Kreise an: den
Femurkopfkreis (R blau, L rot, derselbe wie beim Norberg-Winkel) und einen gelben Kreis für die
Pfanne.

- **Femurkopfkreis:** auf den Femurkopf legen, Radius über den gelben Griff aussen oder das
  Mausrad.
- **Pfannenkreis:** auf die Gelenkpfanne legen; Griff auf der Innenseite, Mausrad über dem Kreis.
  Überlappen beide Kreise, reagiert der, dessen Zentrum näher am Mauszeiger liegt.
- **DI** = Abstand der beiden Kreiszentren geteilt durch den Femurkopfradius. Eine rote Linie
  verbindet die Zentren, der Wert steht unter dem Femurkopf („DI 0.65") und wird im Namen des
  Pfannenkreises gespeichert.
- **Show DI Risk Level** (Haken im Menü Vet Tools) ergänzt das Label um die Stufe, bezogen auf
  die angezeigte, gerundete Zahl: < 0.30 low · 0.30–0.70 moderate · > 0.70 high. Diese Grenzen
  sind Praxiswerte; die rassebezogene Einordnung nach PennHIP bleibt Sache der Beurteilung.
- **Vet Tools › Distraction Index (PennHIP) — Place / Reset** legt die Messung neu,
  **Delete Distraction Index** entfernt die Pfannenkreise; beides widerrufbar.
- Norberg-Winkel und Distraktionsindex teilen sich die Femurkopfkreise. Beide Messungen können
  auf demselben Bild liegen; Reset oder Löschen der einen lässt die Kreise stehen, solange die
  andere sie braucht.

Der amtliche PennHIP-DI setzt Zertifizierung und Einsendung voraus; SekhVet misst nach derselben
Formel für den Praxisgebrauch.

### 5.8 Point-Werkzeug „Punkt in allen Serien zeigen"

Toolbar-Knopf **Point** (Fadenkreuz-Symbol): Klick ins Bild zeigt dieselbe Stelle in allen
anderen offenen Serien der Studie und springt dort auf die passende Schicht (Horos: nur über
Alt-Doppelklick erreichbar). Die Markierungen verschwinden beim Weiterblättern oder beim
Werkzeugwechsel.

### 5.9 Patient umbenennen (Rename Patient (DICOM)…)

Im Kontextmenü der Datenbank (unter „Unify patient identity") und in **Vet Tools**. Schreibt
Name (Owner^Animal), Patient-ID, Geburtsdatum und Geschlecht in die DICOM-Dateien einer oder
mehrerer markierter Studien; die alten Werte wandern wie bei Horos' „Unify" in die Felder
Other Patient Names/IDs. Das Popup **Take identity from** übernimmt die Daten eines vorhandenen
Patienten, damit eine als „Notfall" registrierte Röntgenstudie unter dem richtigen Tier landet.
Offene Viewer werden vorher geschlossen. Je Studie gilt **alles oder nichts**: vor dem Schreiben
legt SekhVet eine Sicherungskopie der Dateien an, und die Datenbank wird erst geändert, wenn
alle Dateien geschrieben sind; scheitert eine, kommt die Sicherung zurück. Abgelehnt werden
verlinkte Studien, Studien aus entfernten Datenbanken, Namen mit Zeichen, die der Zeichensatz
der Dateien nicht darstellen kann, fehlende Dateien und zu wenig freier Platz (Meldung sagt,
warum). Ein PACS, das die Studie schon hat, behält den alten Namen.

### 5.10 Double MPR

Zwei MPR-Fenster derselben Studie (z. B. nativ und Kontrastmittel) laufen synchron:
Fadenkreuzpunkt, Ebenenlage, Schichtdicke, Rotation/Spiegelung und der Zoom je Ansicht
(sagittal ↔ sagittal usw.). Fensterung bleibt je Fenster eigen. Bedingung: gleiche Studie und
gleicher Frame of Reference.

- Schalter **MPR-Sync** in der MPR-Toolbar (Vorgabe an).
- Neue MPR-Fenster öffnen über ihrer 2D-Serie und werden in der Viewer-Fläche gekachelt; sie
  bleiben frei verschiebbar.
- Ein zweites MPR übernimmt beim Öffnen die Lage des ersten.
- **Doppelklick auf eine Ansicht** vergrössert sie auf das ganze Fenster, ein zweiter Doppelklick
  stellt die drei Ansichten wieder her; das andere MPR-Fenster ist davon nicht betroffen.
- **Ein Klick** in eine 2D-Serie macht sie zur aktiven Serie: der MPR-Knopf baut das MPR dann aus
  dieser Serie (kein zweiter Klick und kein Scrollen nötig).
- **Seiten tauschen:** **⌘H** oder der Toolbar-Knopf **Swap** lässt die beiden MPR-Fenster die
  Seite wechseln, samt ihrer 2D-Serien darunter; jedes MPR liegt danach wieder über seiner
  eigenen Serie (5.17).

### 5.11 Weitere MPR-Verbesserungen

- **Convolution filter (SekhVet):** Popup in der MPR-Toolbar; Gauss, Sharpen, Unsharp Mask,
  Highpass auf allen drei Ebenen.
- **Thick Slab** steht ab Werk auf Mean (Horos: MIP). Der Modus (MIP/Mean) gilt je MPR-Fenster,
  nicht für alle offenen MPR.
- **Zoom** (Checkbox in der MPR-Toolbar): koppelt den Zoom der drei Ansichten eines Fensters.
  Vorgabe aus; zwischen Fenstern folgt der Zoom je Ansicht immer. Der Knopf lässt sich über
  Customize Toolbar entfernen.
- **Rechtsklick ohne Ziehen** öffnet in jeder MPR-Ansicht das Werkzeugmenü wie im 2D-Viewer;
  mit gedrückter rechter Taste ziehen zoomt wie in Horos.
- **Icons:** die Orientierungsknöpfe (Axial, Coronal, Sagittal und ihre Gegenseite) zeigen ein
  Wirbel-CT im Knochenfenster, „3D MPR“ einen dorsalen MRT-Schnitt mit Fadenkreuz, „2D Orthogonal
  MPR“ drei Streifen eines Knie-CT; die Funktionen sind die von Horos.
- **Fadenkreuz-Trefferzonen** grösser als in Horos (Zentrum 18 px, Linien 12 px), einstellbar in
  Vet Tools › Display.
- **Ruhiger Cursor:** Horos wechselt den Mauszeiger je nach Position; SekhVet zeigt den Pfeil
  (abschaltbar in Display).
- CT mit sehr grossem Wertebereich wird ohne Rückfrage auf −1024…7168 HU beschnitten
  (der Horos-Dialog „High Dynamic Values" entfällt).

### 5.12 DICOMweb (Vet Tools › DICOMweb Query (QIDO-RS / WADO-RS)…)

Horos spricht nur DIMSE (C-FIND/C-MOVE) und WADO-URI. SekhVet hat ein eigenes Fenster für
DICOMweb, das gegen Orthanc, dcm4chee und andere Server läuft.

1. **Knoten anlegen:** **+** legt „New node“ an; URL bis `/dicom-web` (z. B.
   `http://pacs.local:8042/dicom-web`), Benutzername. Das Passwort wird beim ersten Abruf
   abgefragt und im Schlüsselbund gespeichert (Basic Auth); ändern Sie URL oder Benutzer, fragt
   SekhVet es neu. Ein Knoten mit `http://` (unverschlüsselt), Passwort und Ziel ausserhalb des
   lokalen Netzes wird einmal mit einer Warnung bestätigt. Beim Knotenwechsel leert sich die
   Trefferliste.
2. **Suchen** nach Name, ID, Datum, Modalität; Zeitraum-Popup (Vorgabe **Today**; Any date,
   Yesterday, **Last 2 days** (gestern und heute), Last 3 days, Last 4 days, Last week, Last
   month) oder ein eigener Bereich in den Feldern „from YYYYMMDD“ / „to YYYYMMDD“. Ergebnis mit
   Serien, Bildzahl, Uhrzeit und Institution. Eine Kugel vor dem Namen zeigt, ob die Studie schon
   ganz (grün) oder teilweise (orange) in der lokalen Datenbank liegt, wie beim Horos-Q/R.
3. **Retrieve:** markierte Studien oder einzelne Serien per WADO-RS laden; die Bilder gehen in
   die Datenbank. Grosse Studien werden gestreamt, nicht ganz im Speicher gehalten. Liegt von
   der Auswahl schon etwas hier (grüne oder orange Kugel), fragt SekhVet: **Only missing parts**
   (überspringt alles Grüne, holt nur unvollständige Serien), **Download everything again** oder
   Abbrechen. Alt-Klick auf Retrieve lädt alles ohne Frage.
   **Retrieve bleibt während eines Downloads bedienbar:** weitere Studien kommen in eine
   Warteschlange (ohne Doppel; die Statuszeile zeigt „Added to the queue: N — M waiting“). Ein
   fehlgeschlagener Abruf hält die Warteschlange nicht mehr an; Fehler stehen am Ende gesammelt
   da. Die Warteschlange merkt sich den Knoten nicht: wer während des Downloads den Knoten
   wechselt, holt den Rest vom neuen. **Stop** neben Retrieve bricht den laufenden Abruf samt
   Warteschlange ab.
   **Sortieren:** Klick auf einen Spaltenkopf sortiert die Studien (Datum/Uhrzeit beim ersten
   Klick neueste zuerst, erneuter Klick kehrt um); die Wahl bleibt gemerkt.
   Strukturierte Berichte (Dosisbericht, Untersuchungsbericht) werden als eigene Serie
   importiert und öffnen als gesetzte Seite. Berichtsarten, die die Datenbank nicht aufnimmt
   (z. B. Key Object Selection), tragen „report — not in the database“ und halten eine Studie
   nicht davon ab, grün zu werden.
4. **Senden aus der Datenbank (STOW-RS):** Studien oder Serien im Datenbankfenster markieren,
   dann entweder den Toolbar-Knopf **Send DICOMweb** drücken oder mit Rechtsklick **Send via
   DICOMweb ›** wählen; beide zeigen die Liste Ihrer Knoten (und „DICOMweb Nodes…“ zum
   Anlegen). Der Versand läuft im Hintergrund, der Fortschritt steht im Aktivitätsfenster und
   lässt sich dort abbrechen; am Ende kommt eine Mitteilung. Bestätigt der Server den Empfang
   nicht ausdrücklich, heisst es „NOT confirmed“ — dann im PACS nachsehen. Dasselbe tun **Vet
   Tools › Send Selected Studies via STOW-RS…** und der Knopf **Send** im DICOMweb-Fenster.

5. **Nach Institution filtern** *(neu in Build 167)*: Feld **Institution (partial; a; b)** in der
   Suchzeile — zeigt nur Studien, deren Institution den Text enthält (Gross-/Kleinschreibung und
   Akzente egal, mehrere Namen mit „;“ trennen). Zusätzlich hat **jeder Knoten seine Zuweiser-
   Liste:** **Choose…** liest alle Institutionen des Servers (mit Zahl der Studien; „(none)“ =
   Studien ohne Institution), Sie haken an, was angezeigt werden soll (**All** / **None**), und
   **Save**. Das Häkchen **Only the N chosen institutions** schaltet den Filter ein und aus
   (Vorgabe an). Von Hand bearbeiten lässt sich die Liste in der Spalte **Institutions filter
   (a; b; …)** der Knotenliste unten. Gefiltert wird in SekhVet, nicht auf dem Server; die
   Statuszeile nennt, wie viele Studien der Filter ausgeblendet hat („… hidden by the institution
   filter“). Der Server liefert höchstens 300 Studien je Suche — darum mit Zeitraum suchen.
6. **Automatisch aktualisieren (Auto-Q/R)** *(neu in Build 167)*: Popup **Auto-refresh** (Off,
   Every 1 / 3 / 5 / 10 / 15 / 30 min.) wiederholt die Suche mit den aktuellen Feldern — auch bei
   geschlossenem Fenster und nach einem Neustart (dann Zeitraum Today, Knoten und Institution wie
   zuletzt, Name/ID/Modalität leer). Aufgeklappte Studien und die Markierung bleiben stehen; die
   Statuszeile zeigt Uhrzeit und neue Treffer („Auto-refresh 14:05, 2 new: …“). Häkchen
   **Retrieve new studies automatically** holt danach jede gezeigte Studie, die noch nicht (ganz)
   hier ist, per WADO-RS — nur mit gesetztem Zeitraum, je Studie einmal pro Sitzung und erneut,
   sobald der Server mehr Bilder davon hat (dann nur die fehlenden Serien).

Toolbar-Knöpfe **DICOMweb** (Abfrage) und **Send DICOMweb** in der Datenbank neben „Query".
Die klassischen Horos-Locations (DIMSE) bleiben unverändert nutzbar.

### 5.13 Bild / PDF als DICOM (Vet Tools › Import Image / PDF as DICOM…)

Fotos, Screenshots, Laborbefunde und Überweisungen in die Studie legen.

- Formate: JPG, PNG, TIFF, GIF, BMP, HEIC, PDF.
- Felder: Patient, ID, Geburtsdatum, Geschlecht, Studien-/Serienbeschreibung, Modalität
  (OT, XC, ES, DX, US).
- **An markierte Studie anhängen:** übernimmt Patientendaten und Study-UID der in der
  Datenbank markierten Studie.
- **PDF seitenweise als Bilder** (150 dpi) oder als Encapsulated PDF.
- Solche Dateien, die man in die Datenbank zieht oder per **File › Import** wählt, landen
  automatisch in diesem Dialog.

### 5.14 Display (Vet Tools › Display (Screen Area, Annotations, MPR)…)

- **Screen Area:** je Bildschirm festlegen, welchen Teil die Viewer-Fenster belegen
  (Brüche wie „rechte 2/3" oder ein Pixelrechteck). Popup **Screen** in der Viewer-Toolbar
  kachelt sofort. Ersetzt Magnet & Co. am breiten Monitor.
- **Annotations:** Schrift, Grösse (Vorgabe Helvetica Bold 14; „Classic (1 px shadow)“ und
  „classic: Geneva 12“ stellen das Horos-Aussehen her), Textfarbe (Vorgabe weiss, „ROI color
  (classic)“ = je Messung ihre Farbe), Kontur/Kasten für Messtexte, Ecken-Text und die Werte der
  HD-Messungen: Popup mit dem Horos-Original, **Outline** (nur Kontur, **Vorgabe**),
  „Semi-transparent box“ und „Outline and box“; Kastenfarbe und Deckkraft bleiben wählbar.
  Änderungen greifen sofort. Schrift im Bild erscheint auf jedem Bildschirm in voller Farbe und
  Deckkraft.
- **Measurements:** Häkchen **Measurement navigator: thumbnails of the images with measurements**
  (Messungen-Navigator, 5.24), Häkchen **Magnified view in a corner while measuring** (Messlupe, 5.21),
  Popup **Magnifier size (of the shorter side)** 25–75 % (Vorgabe 55 %) und **Line width (px)**
  getrennt für Linien, Flächen und Pfeile (1–10) mit Knopf **Apply to open**.
- **Overlay:** die Tasten für die nächste und die vorige Serie im Overlay (5.20); Vorgabe `<`
  und `y`.
- **Eck-Informationen (Preferences › Annotations):** die Vorgabe zeigt oben links
  Bildgrösse, WL/WW und Mausposition; oben Mitte Orientierung und Patient Orientation; oben
  rechts Patient-ID, Studien- und Serienbeschreibung; unten rechts MR-Daten, Aufnahmedatum und
  Aufnahmedauer. **CT** hat einen eigenen Eintrag, der unten links kVp, mA und mAs zeigt; CBCT-Studien
  werden als Modalität CT gespeichert und bekommen dasselbe. Eine selbst gespeicherte Belegung
  bleibt erhalten.
- **Appearance:** System / Light / Dark, Vorgabe Dark.
- **Modality colours:** Studien- und Serienzeilen in der Datenbank nach Modalität getönt
  (CT blau, MR violett, Röntgen grün, US orange …). Abschaltbar.
- **Magnetic windows:** ab Werk aus, Fenster bleiben frei verschiebbar.
- **MPR:** Trefferzonen, statischer Cursor, MPR-Sync, Kachelung, Zoom-Sync.
- Die Bildschirm-Zeilen (Screen Area) folgen neu angeschlossenen Bildschirmen von selbst.

### 5.15 Rückmeldung und Beitrag

- **Send Feedback…** öffnet eine E-Mail an das SekhVet-Postfach mit ausgefüllter Vorlage
  (Build, macOS, was passiert ist). Bilder mit Patientendaten vorher beschneiden oder
  anonymisieren.
- **Contribute to SekhVet…** zeigt zwei Zahlungs-QR (Swiss QR-Rechnung in CHF, GiroCode in EUR)
  mit IBAN zum Kopieren. Kein Zahlungsdienstleister dazwischen, Betrag frei, keine
  Gegenleistung.
- **Dictate with VoiceInk** führt zum Partnerlink der Diktiersoftware.
- **GitHub:** Fehlermeldungen und Wünsche können auch als Issue unter
  https://github.com/3v3nFloW/sekhvet/issues eingetragen werden. Gleiche Regel: keine
  Screenshots mit Besitzer- oder Tiernamen.

### 5.16 Ultraschall: Kalibrierung vom Nachbarbild *(experimentell)*

Manche Ultraschallgeräte schreiben einzelne Standbilder ohne Kalibrierdaten (keine
Ultraschall-Region und kein Pixelabstand); Längenmessungen zeigen dort nur Pixel. SekhVet
übernimmt dann die Kalibrierung eines anderen Bildes derselben Serie, sofern beide gleich gross
sind und am rechten Rand dieselbe skalenartige Tiefenskala zeigen (die Skalenstreifen werden
verglichen). Der Messtext trägt den Zusatz „US calibration from image N“ (bei Mehrbild-Dateien
„image N, frame M“), damit die Herkunft sichtbar bleibt. Cine-Loops dienen nie als Quelle.
**Ab Werk nur für Mindray-Geräte aktiv**, dem einzigen bisher geprüften Hersteller (Vetus 9).
Für andere Hersteller lässt sich die Funktion im Terminal freischalten, z. B. für Esaote:
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallbackVendors -array Mindray Esaote
```
und ganz abschalten mit
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallback -bool NO
```
Stimmt eine geborgte Kalibrierung bei Ihrem Gerät nicht, schalten Sie die Funktion ab und melden
Sie das Gerätemodell.

### 5.17 Fenster tauschen / rotieren (⌘H)

**⌘H**, der Toolbar-Knopf **Swap** (im 2D-Viewer neben Point, im MPR-Fenster neben Zoom-Sync)
oder **Vet Tools › Swap / Rotate Windows** ordnet die offenen Fenster um:

| Offen | Ergebnis |
|---|---|
| zwei MPR-Fenster | sie wechseln die Seite samt ihrer 2D-Serien; jedes MPR liegt wieder über seiner Serie |
| drei oder mehr MPR-Fenster | jedes MPR rückt samt Serie einen Platz weiter |
| kein oder ein MPR, zwei 2D-Serien | die beiden 2D-Fenster tauschen die Plätze |
| kein oder ein MPR, drei oder mehr 2D-Serien | jedes Fenster rückt einen Platz nach rechts, das letzte kommt nach vorne: `[A][B][C]` → `[C][A][B]` |

Gezählt wird je Bildschirm von links nach rechts, dann zeilenweise von oben. Das aktive Fenster
bleibt aktiv; Fensterung, Fadenkreuz und Spine-Labels bleiben unberührt. Serien, die über
mehrere Bildschirme verteilt sind, können dabei den Bildschirm wechseln. **⌘H blendet SekhVet
nicht mehr aus;** „Hide SekhVet“ steht weiter im SekhVet-Menü, ohne Kürzel, ⌥⌘H (Hide Others)
bleibt. Eine andere Taste: Systemeinstellungen › Tastatur › Tastaturkurzbefehle ›
App-Tastaturkurzbefehle, Menütitel „Swap / Rotate Windows (MPR with their 2D series, else 2D
series)“.

### 5.18 Import aus anderen Datenbanken (Einstellungen › Database › Import from Other Databases… oder Vet Tools)

Für den Umstieg von Horos, OsiriX, HorliX oder Miele-LXIV: Die Studien einer anderen
Datenbank werden in die SekhVet-Datenbank kopiert. In der Symbolleiste der Datenbank heisst der
Knopf **Import Databases** (Horos: „Migration Assistant“).

- **Gefunden werden** automatisch jeder Ordner in `~/Documents` mit einem `DATABASE.noindex`
  (z. B. „OsiriX Data", „Horos Data") und die eigenen Speicherorte aus den Einstellungen von
  OsiriX und Horos. Eine Datenbank anderswo (externe Platte) über **Choose Folder…** wählen.
- **Importieren** kopiert alle Bilder der markierten Datenbank; der Fortschritt steht im
  Aktivitätsfenster, man kann weiterarbeiten. Die **Quelle wird nur gelesen**, nie verändert.
- Bilder, die schon in SekhVet liegen, werden erkannt (SOPInstanceUID) und **nicht doppelt**
  angelegt — ein zweiter Import derselben Datenbank holt nur Neues.
- ROIs, die als DICOM (SR) in der Datenbank liegen, kommen mit. **Nicht** übernommen werden
  Alben, Berichte und Einstellungen.
- Beim ersten Start mit gefundener Fremddatenbank weist SekhVet einmal darauf hin.
- Warum „SekhVet Data" und nicht „Horos Data": SekhVet ist ein eigenständiger Fork; der
  eigene Datenordner hält die Horos-Datenbank unberührt (und die Marke „Horos" aus SekhVet heraus).

*Die Idee stammt von Hiroaki Inomata (PHORLIX) — herzlichen Dank für die freundliche
Zustimmung zu dieser eigenen Umsetzung.*

### 5.19 Suche nach Beschreibung

Im Datenbankfenster sucht der Suchtyp **Description** (früher „Study Description") in der
Studien- **und** in der Serienbeschreibung — „lat", „VD" oder „Thorax" finden die Studie auch,
wenn die Projektion nur in der Serie steht. Die Suche über **alle Felder** (ab drei Zeichen)
schliesst die Serien ebenfalls ein. PACS-Abfragen suchen weiter nur auf Studienebene.

### 5.20 Overlay: Serien überlagern (Knopf „Overlay“ im 2D-Viewer)

Nativ, Kontrastmittel und Knochenkern **derselben Untersuchung im selben Fenster** betrachten:
Schicht, Zoom und Ausschnitt bleiben beim Umschalten stehen, als blättere man zwischen Folien.
Nur CT und MRT in Graustufen, nur im 2D-Viewer; die Serien brauchen denselben Frame of Reference
(sonst Meldung, kein Overlay). Höchstens vier Serien; jede weitere Serie wird auf das Raster
der Serie im Fenster umgerechnet (trilinear geglättet, etwa 0,4 GB Speicher je CT-Serie).

- **Knopf „Overlay“** in der Viewer-Symbolleiste (neben „Swap“) sucht die passenden Serien
  von selbst: gleiche Modalität, mindestens zehn Bilder, kein Topogramm, gleiche Region, bei MRT
  dieselbe Ebene; Reihenfolge Native · Contrast · Native bone · Contrast bone. Als Kontrast
  gelten Serien mit „KM“, „contrast“, „post“, „T1+C“ …; „pre KM“, „vor KM“, „ohne KM“, „without /
  non contrast“, „plain“ gelten als nativ. Danach stehen in der Symbolleiste **Chips** je Serie,
  **▾** (Auswahl) und **✕** (beenden).
- **Findet der Knopf nichts**, bleibt er gedrückt und wartet: die nächste Serie, die Sie aus der
  Serienleiste aufs Bild ziehen, wird überlagert (eine Meldung sagt das; ein zweiter Klick
  schaltet den Knopf wieder aus).
- **Serie aufs Bild ziehen** fragt nicht mehr nach: Overlay aus → die Serie wird gezeigt wie in
  Horos; Overlay an → die Serie kommt dazu; liegt sie schon im Overlay → es wird nur
  umgeschaltet. Ein Klick auf eine Miniatur zeigt die Serie immer normal und beendet das Overlay.
- **▾ Auswahl:** Menü mit einem Haken je Serie der Untersuchung. Abgewählte Serien bekommen
  keinen Chip und werden übersprungen (bleiben geladen); die Serie, von der aus Sie gestartet
  haben, lässt sich nicht abwählen. Bei CT merkt sich SekhVet die abgewählte **Art** (z. B.
  „Contrast bone“) und lädt sie beim nächsten Overlay gar nicht erst; im Menü wieder anhakbar.
- **Tasten:** `<` nächste Serie, `y` vorige (umstellbar in Vet Tools › Display, Zeile „Overlay“).
  Sie wirken nur, solange ein Overlay läuft und das Bild den Fokus hat. `y` ist in Horos das
  Fadenkreuz-Werkzeug des Orthogonal-MPR; während eines Overlays schaltet es die Serie.
- **Fensterung je Serie** wird gemerkt: die Knochenserie bleibt im Knochenfenster, die
  Weichteilserie im Weichteilfenster, auch im MPR.
- **Messungen sind geteilt:** eine Länge oder ein Oval steht in allen Serien des Overlays an
  derselben Stelle; gespeichert wird sie nur an der Serie, von der aus das Overlay gestartet
  wurde. Frühere, eigene Messungen der anderen Serien sind währenddessen ausgeblendet (Chip
  „(n hidden)“) und bleiben gespeichert.
- **Flächen-ROI (Oval, Rechteck, Polygon, Stift):** Mean und SD gelten für die gerade sichtbare
  Serie. Dazu kommt die Zeile **„Native 42 · Contrast 168 · Δ +126 HU“** (nur zwischen Serien
  desselben Kerns; bei MRT das Enhancement in Prozent). Im MPR rechnet das Oval ebenfalls je
  Serie neu, die Δ-Zeile gibt es dort nicht.
- **Overlay im MPR:** Die MPR-Symbolleiste hat denselben Knopf **Overlay** mit Chips, **▾** und
  **✕**. Ein MPR aus dem Overlay-Fenster enthält alle Serien; `<`, `y` und die Chips schalten MPR
  und 2D gemeinsam. Starten Sie das Overlay im MPR, nehmen Sie über **▾** eine Serie dazu oder
  beenden Sie es mit **✕**, schliesst SekhVet das MPR kurz, ändert das Overlay im 2D-Fenster und
  öffnet das MPR an derselben Stelle wieder: gleiche Ebenen, gleicher Zoom, gleiche Fensterlage,
  gleiche sichtbare Serie. Das dauert je nach Serie ein paar Sekunden. **Schneller geht es, wenn
  Sie das Overlay im 2D-Fenster starten und erst danach das MPR öffnen.** Ein minimiertes MPR oder
  ein offenes Volume Rendering derselben Serie sperrt das weiterhin (Meldung).
- Während eines Overlays sind Revert, LUT, SUV und DICOM-Overlays nicht verfügbar („post
  processed“), der 4D-Regler und Play sind grau. Eine Bezugsserie mit gemischten Bildgrössen
  oder nicht parallelen Schichten wird abgelehnt.
- Grenzen: eine Kontrastserie je Overlay, keine Phasenerkennung (arteriell/venös/spät).

### 5.21 Lupe (Messlupe und freie Lupe)

- **Messlupe:** beim Ziehen einer **Längenmessung** (auch beim Nachziehen eines Endpunkts)
  erscheint in der Ecke, die am weitesten vom Zeiger entfernt ist, ein vergrössertes Feld; die
  Ecke bleibt während der Messung stehen. Nur bei der Länge, nicht bei Oval & Co. Abschaltbar
  unter Vet Tools › Display › Measurements, Häkchen „Magnified view in a corner while measuring“.
- **Freie Lupe:** **Hochstelltaste** halten, das Feld folgt neben dem Zeiger; der echte Zeiger
  bleibt im Bild sichtbar. Geht auch mit aktivem Messwerkzeug, ausser der Zeiger steht gerade
  auf einer Messung.
- **Zoom** mit `+`/`−`, `→`/`←` oder dem Scrollrad (1,5- bis 12-fach, Vorgabe 3-fach); **Grösse**
  mit `↑`/`↓` oder dem Popup „Magnifier size (of the shorter side)“, 25–75 %, Vorgabe 55 %.
- Gilt im 2D-Viewer und in den MPR-Ansichten (dort ohne Fadenkreuz in der Lupe).

### 5.22 Fusion und Subtraktion (Horos-Funktion, in SekhVet repariert)

Zieht man das Bild eines Viewers auf einen anderen, bietet Horos **Subtraction** und
**Multiply** an. SekhVet verrechnet dabei jede Zielschicht mit der Maskenschicht **am selben
Ort** (gleicher Frame of Reference oder dieselbe Untersuchung), nicht mehr mit der Schicht
gleicher Nummer; Zielschichten ausserhalb der Maske werden geleert. Ein Sync der Fenster ist
nicht nötig, die Fensterreihenfolge spielt keine Rolle. **Ctrl** beim Wählen verrechnet Bild
für Bild nach Nummer, **Option** liefert den Betrag der Differenz. Stammen beide Serien aus
Untersuchungen ohne gemeinsame Koordinaten, wird bei gleicher Schichtzahl nach Nummer, sonst
anteilig zugeordnet.

### 5.23 Freies Drehen (Werkzeug „Rotate“)

Mit dem Werkzeug **Rotate** (auch ⌘⌥-Ziehen) folgt das Bild der Maus um die Mitte der Ansicht.
Nahe der Mitte ist die Drehung gedämpft, damit kleine Mausbewegungen kleine Winkel ergeben;
weiter aussen dreht das Bild genau mit der Maus. Gilt im 2D-Viewer, im 3D-MPR und im Curved
MPR; im MPR dreht jede Ansicht um ihre eigene Mitte. Doppelklick mit dem Werkzeug dreht um 90°
(mit Hochstelltaste) oder 180° (mit Option), die Pfeiltasten drehen in 3°-Schritten.

### 5.24 Messungen-Navigator (Knopf „Measurements“ im 2D-Viewer) *(neu in Build 167)*

Sobald eine Serie Messungen (ROIs) hat, erscheint am unteren Bildrand eine Leiste mit einem
Vorschaubild je Schicht mit Messung — Fensterung, Drehung und Spiegelung wie im Viewer, die
Messungen in ihrer Farbe. Darunter steht die Schichtnummer (wie in der Bildecke), bei mehreren
Messungen auch deren Zahl; der Tooltip nennt die Namen. Die angezeigte Schicht ist gelb umrandet.

- **Klick** auf ein Vorschaubild springt auf diese Schicht; synchronisierte Viewer ziehen mit wie beim
  Scrollen.
- **Papierkorb** rechts in der Leiste (oder Symbolleisten-Knopf **Delete All**) löscht nach
  Rückfrage alle Messungen der Serie (der Symbolleisten-Knopf die des Viewers, in den zuletzt geklickt
  wurde; die Rückfrage nennt die Serie); gesperrte bleiben, **⌘Z** holt alles zurück (dasselbe wie
  Horos' ROI › Delete All ROIs).
- **x** links blendet den Navigator aus. Wieder ein: Symbolleisten-Knopf **Measurements** oder
  Vet Tools › Display, Häkchen **Measurement navigator: thumbnails of the images with
  measurements** (Vorgabe an).

Die Leiste liegt über dem Bild, das Bild verschiebt sich nicht. Gezeigt werden bis zu 400
Schichten mit Messung; bei mehr als in die Breite passen, lässt sich die Leiste seitlich rollen.

## 6. Bedienung, die anders ist als in Horos

| Thema | Horos | SekhVet |
|---|---|---|
| Randbuchstaben | A/P, S/I | Cr/Cd, D/V (schaltbar) |
| Hängung | Rows/Columns je Modalität | Presets mit Orientierungsregeln, Keywords, DX-Regeln, Öffnungsprotokolle |
| Fenster aktiv machen | Rechtsklick/Scrollrad | auch Linksklick |
| Messtext | Geneva 12 in ROI-Farbe | Helvetica Bold 14, weiss mit Kontur (umstellbar, 5.14) |
| ROI-Werte im MPR | bleiben beim Umschalten des Schnittbilds stehen | rechnen bei jedem neuen Schnittbild neu |
| Serie aufs Bild ziehen | ersetzt die Serie | ebenso; bei laufendem Overlay wird sie überlagert (5.20) |
| Taste `y` | Fadenkreuz im Orthogonal-MPR | ebenso; bei laufendem Overlay vorige Serie |
| Hochstelltaste halten | — | freie Lupe, auch mit Messwerkzeug (5.21) |
| Werkzeug Rotate | springt nahe der Bildmitte | gedämpft, folgt der Maus (5.23) |
| Subtraktion | Schicht gleicher Nummer | Schicht am selben Ort (5.22) |
| DICOM-Listener | an, Port 11112 | ab Werk aus; einschalten unter Preferences › Listener (Abschnitt 3) |
| Erscheinungsbild | folgt System | Dark als Vorgabe, umschaltbar |
| Propagate settings | je nach Protokoll wieder an | bleibt aus, bis man es einschaltet |
| Magnetische Fenster | an | aus |
| Thick Slab | MIP | Mean |
| Serie öffnen | Regler mit einem Strich je Bild (langsam bei grossen Serien) | ohne Striche, deutlich schneller |
| Update-Prüfung | stündlich gegen Horos-Server | wahlweise, einmal täglich gegen GitHub; nur Hinweis |
| Horos Cloud | Plugin | entfernt |
| Datenordner | Horos Data | SekhVet Data |
| Hilfe-Menü | Horos-Hilfe, Foren | nur „Report a bug“ |
| ⌘H | blendet das Programm aus | tauscht / rotiert Fenster (5.17) |

Alle SekhVet-Fenster öffnen sich innerhalb der Viewer-Fläche. Alle Toolbar-Knöpfe von SekhVet
lassen sich über **Customize Toolbar** verschieben oder entfernen; neue Knöpfe erscheinen einmal
automatisch, entfernt man sie, bleiben sie weg.

## 7. Stand 1.0, Grenzen und bekannte Einschränkungen (Build 174)

**Neu in 1.0, erst an wenigen Geräten geprüft.** Diese Funktionen laufen in einer Praxis, sind
aber jung. Mit kritischem Blick benutzen und Auffälligkeiten melden:

- **Overlay** (5.20): seit Ende September 2026 an CT und MRT eines Geräts im Einsatz.
- **Subtraktion nach Ort** (5.22): an CT und MRT geprüft (Oktober 2026).
- **Messungen-Navigator** (5.24) sowie **Institutionsfilter und automatisches Aktualisieren**
  bei DICOMweb (5.12): seit Oktober 2026 an einem Gerät geprüft.
- **Ultraschall-Kalibrierung vom Nachbarbild** (5.16): an einem Gerät geprüft, darum ab Werk nur
  für Mindray aktiv.
- **Update-Prüfung** (Abschnitt 3): die Prüfung gegen GitHub lässt sich erst mit dem nächsten
  Release im Alltag beurteilen.
- **macOS 27:** in einer Testinstallation geprüft, auch Double MPR mit grossem CT und der
  Doppelklick-Zoom; der Alltag läuft unter macOS 26.

**Im Alltag bewährt:** Randbuchstaben, Hanging Protocol in 2D und MPR (auch Curved und
Orthogonal), Öffnungsprotokolle samt Röntgen-Zweiebenen, Fensterungs-Presets, Spine Labeling,
Norberg-Winkel, Distraktionsindex, Point-Werkzeug, Double MPR, Faltungsfilter, Lupe, freies
Drehen, DICOMweb-Suche, -Abruf (mit Warteschlange) und -Senden, Bild- und PDF-Import, Patient
umbenennen, Import aus anderen Datenbanken, Display-Einstellungen samt CT-Eckinformation,
Feedback- und Beitragsfenster.

**Allgemeine Grenzen:**

- **Kein zertifiziertes Medizinprodukt** (siehe oben). Keine formale Validierung der Messungen.
  Geräte für den Veterinärbereich fallen weder unter die EU-Verordnung 2017/745 noch unter die
  Schweizer MepV; beide gelten für Produkte am Menschen. Für veterinärmedizinische Bildsoftware
  gibt es in keinem der beiden Rechtsräume ein Zertifizierungsverfahren.
- **Nur Apple Silicon**, macOS 12 oder neuer; praktisch getestet unter macOS 26 und 27.
- **Empfang ab Werk aus:** der DICOM-Listener muss einmal eingeschaltet werden (Abschnitt 3).
- **Nicht notarisiert:** Gatekeeper-Umweg beim ersten Start (Abschnitt 3).
- **Alter Kern:** SekhVet ist ein Pflegefork ohne Modernisierung (OpenGL, kein Metal, kein
  Swift). Bekannte Horos-Eigenheiten bleiben. Dafür bleibt es kompatibel mit Horos-Plugins
  und der Horos-Bedienung.
- **Befunde:** SekhVet nutzt den Berichtsweg von Horos. Der Knopf **Report** öffnet Pages mit
  der Vorlage aus dem Ordner `PAGES TEMPLATES` der Datenbank (Vorgabe); umstellbar auf Word,
  TextEdit (RTF) oder LibreOffice. Einen eigenen Berichtseditor gibt es nicht.
- **DICOMweb:** nur Basic Auth (kein OAuth/Token), kein QIDO auf Instanzebene, Knotenliste
  ohne Import aus den Horos-Locations.
- **HD-Messungen:** kein Flückiger-Panel, kein HD-Grad; der Distraktionsindex ist eine
  Praxismessung, kein amtlicher PennHIP-Wert.
- **Patient umbenennen:** Umlaute hängen am Zeichensatz der Dateien; ein PACS, das die Studie
  schon hat, behält den alten Namen.
- **Spine Labeling** ist für CT und MRT gedacht, nicht für Röntgen.
- **Sprache:** Oberfläche Englisch unter jeder Systemsprache, keine deutsche Lokalisierung. Die veralteten japanischen Ressourcen aus Horos sind seit Build 107 entfernt; sie überdeckten auf japanischen Systemen die gepflegten englischen Dateien (defekte Symbolleisten).
- **Keine automatische Installation von Updates**; SekhVet kann einmal täglich auf GitHub nachsehen und meldet eine neue Version, das DMG lädt und installiert man selbst.

## 8. Lizenz, Quellcode, Beitrag

SekhVet ist freie Software unter der GNU Lesser General Public License 3.0 und basiert auf
Horos (Horos Project) und OsiriX (Pixmeo SARL). Der vollständige Quellcode dieser Version,
einschliesslich aller Änderungen an Horos, liegt unter https://github.com/3v3nFloW/sekhvet
(auch hinter „Source code“ im About-Fenster).

Wer SekhVet nützlich findet, kann die Weiterentwicklung mit einem freiwilligen Beitrag
mittragen: **Vet Tools › Contribute to SekhVet…** Der Betrag ist frei wählbar, es gibt keine
Gegenleistung und keine Zusatzfunktionen dafür.

© 2026 Kappa1-VRS GmbH, Zürich. Horos und OsiriX sind Marken ihrer jeweiligen Inhaber.
