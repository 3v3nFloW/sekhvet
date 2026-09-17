# SekhVet — Anleitung (Deutsch)

Version 1.0 beta, Build 95 · Stand 17.09.2026

> **SekhVet ist ein veterinärmedizinischer DICOM-Viewer und kein zertifiziertes Medizinprodukt.**
> Es ist weder FDA-cleared noch CE-gekennzeichnet und hat keine formale Validierung durchlaufen.
> Es ist ausschliesslich für Veterinärmedizin, Forschung und Lehre bestimmt und darf nicht für
> die Diagnose oder Behandlung von Menschen eingesetzt werden. Messwerkzeuge und
> Orientierungshilfen sind Hilfsmittel; Bildinterpretation und Diagnose bleiben in der
> Verantwortung der Tierärztin oder des Tierarztes. SekhVet wird ohne Gewährleistung
> bereitgestellt (GNU LGPL v3).

> **Öffentliche Beta.** SekhVet 1.0 erscheint als Beta. Der Horos-Kern und die meisten
> Vet-Werkzeuge sind in einer Praxis täglich im Einsatz; einige Funktionen sind als
> *experimentell* markiert, weil sie erst an wenigen Geräten oder noch nicht am echten Gerät
> geprüft sind. Abschnitt 7 zählt sie auf. Bitte melden Sie, was Ihnen auffällt (Abschnitt 5.15).

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
| macOS | 12 Monterey oder neuer. Getestet unter macOS 26 Tahoe (täglich) und macOS 27 (Build 93, Testinstallation). |
| Bildschirm | Läuft auf jedem Bildschirm; die Funktion „Screen Area" ist für breite Monitore gedacht. |
| Netz | Für DICOMweb einen Server mit QIDO-RS/WADO-RS (z. B. Orthanc mit DICOMweb-Plugin). |

## 3. Installation

1. `SekhVet-1.0-beta-build95-macOS.zip` von der Releases-Seite
   https://github.com/3v3nFloW/sekhvet/releases laden und entpacken.
2. `SekhVet.app` nach `/Programme` ziehen. Liegt dort schon eine ältere SekhVet-Kopie:
   **zuerst beenden**, dann ersetzen. Laufen zwei Kopien gleichzeitig, meldet die zweite
   „DICOM Listener Error", weil der Empfangsport schon belegt ist.
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
   kommt erst wieder, wenn sich sein Wortlaut ändert.
6. Prüfsumme (optional): `shasum -a 256 SekhVet-1.0-beta-build95-macOS.zip` muss mit dem Wert
   auf der Releases-Seite übereinstimmen.

**SekhVet neben Horos oder OsiriX:** SekhVet hat eine eigene Datenbank
(`~/Documents/SekhVet Data`), eigene Einstellungen und einen eigenen Plugin-Ordner
(`~/Library/Application Support/SekhVet/Plugins`). Horos und OsiriX bleiben unberührt und können
parallel installiert bleiben. Der DICOM-Empfangsport von SekhVet ist 11113 (Horos: 11112),
damit beide gleichzeitig laufen können. Der Port lässt sich unter Preferences › Listener ändern.

**Updates:** SekhVet prüft nicht automatisch auf neue Versionen. Neue Builds erscheinen auf der
Releases-Seite auf GitHub. Ein neuer Build wird einfach über den alten kopiert (vorher
beenden); Datenbank und Einstellungen bleiben erhalten.

## 4. Erste Schritte

1. Studien hereinholen wie in Horos: Dateien ins Fenster ziehen, **File › Import**, DICOM-Empfang
   auf Port 11113, oder per DICOMweb (Abschnitt 5.12). Während des Empfangs zeigt das Dock das
   SekhVet-Signet mit Pfeil.
2. Studie per Doppelklick öffnen. Welche Serien aufgehen und wie sie hängen, bestimmen die
   Öffnungsprotokolle (5.3) und das Hanging Protocol (5.2). Röntgenstudien mit genau zwei
   Aufnahmen hängen VD links, seitlich rechts (5.3).
3. Die eigenen Fenster von SekhVet öffnen sich innerhalb der Viewer-Fläche und stehen im Menü
   **Vet Tools**.

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

Hängt Serien veterinär richtig auf: Drehung und Spiegelung nach Regeln je Preset. Es ist eine
reine Anzeigetransformation; die Bilddaten werden nicht verändert.

- **Presets:** Off · Head / Spine · Limbs · Custom. Vorgabe im Panel, Umschalten je Studie über
  das Popup in der Viewer-Toolbar.
- **Regeln je Preset** (einzeln schaltbar):
  „Sagittal: cranial left", „Transverse: dorsal up", „Dorsal plane: cranial up",
  „Patient left on the right side of the image".
- **Keywords:** Tabelle „study/series description contains … → preset". Ein Treffer überstimmt
  die Vorgabe. Beispiel: „Ellbogen", „Schulter", „Karpus" → Limbs.
- **Röntgen (DX/CR):** Regel je Quelle (Station/Modalität → Drehung, Flip). Damit hängen Aufnahmen
  eines Geräts, das „immer falsch" liefert, ab dem ersten Öffnen richtig.
- **Apply Hanging Protocol to Open Viewers** wendet das Preset auf alle offenen Fenster an.
- **Take from screen** übernimmt die Lage der offenen Fenster in das gewählte Protokoll.
- Gilt auch im **3D-MPR**: die drei Ebenen werden so gedreht, dass die Buchstaben stimmen
  (sagittal Cr links, transversal D oben, dorsal Cr oben), auch wenn die Ebenen vorher schräg
  standen. Popup in der MPR-Toolbar. Die zuletzt gerade gerichtete Lage einer Serie wird je
  Preset gemerkt und beim nächsten Öffnen wiederhergestellt.
- Localizer und schräge Serien werden markiert, nicht gedreht.
- Fensterung wird hier nicht angefasst (dafür 5.4).

Bei Preset **Off** verhält sich SekhVet wie Horos und nimmt die zuletzt gespeicherte Lage.

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

### 5.4 Fensterung beim Öffnen (Vet Tools › Window Presets (WL/WW on open)…)

Regeln „Modalität + Beschreibung enthält … → Fensterwerte" (z. B. Bone (vet), Soft tissue),
die beim Öffnen greifen. Die Öffnungsprotokolle (5.3) verwenden dieselben Regelnamen.

### 5.5 Spine Labeling (Vet Tools › Spine Labeling…)

Wirbel per Klick zählen, in CT-MPR und MRT-Stapeln.

1. Panel öffnen: Tierart wählen (**Dog / Cat 7-13-7-3**, **Rabbit 7-12-7-4**,
   **Horse 7-18-6-5** = C-T-L-S), Startlabel (z. B. L1) und Zählrichtung.
2. Mit dem Point-Werkzeug klicken: jeder Klick setzt das nächste Label, Übergänge
   C7→T1→…→L7→S1→…→Cd1 laufen automatisch.
3. **Alt-Klick** setzt eine Bandscheibe („L1-L2").
4. **⌫** nimmt das letzte Label zurück, **Esc** beendet.
5. **Umbenennen mit Neuzählung:** Doppelklick auf einen Punkt, Name ändern (z. B. L1 → T13);
   alle folgenden Labels der Serie werden neu gezählt.

Labels sind normale Punkt-ROIs, in der Datenbank gespeichert und in allen Ebenen des MPR
sichtbar. Im Transversalbild steht oben links „▶ Spine level: L3" für den nächstliegenden
Wirbel. Toolbar-Knopf „Spine Labeling" in 2D- und MPR-Fenstern.

### 5.6 Norberg-Winkel (Vet Tools › Norberg Angle (Hip Dysplasia) — Place / Reset)

HD-Auswertung am VD-Becken (gestreckte Aufnahme). Der Menüpunkt oder der Toolbar-Knopf
**Norberg Angle** legt im vordersten 2D-Fenster zwei Femurkopfkreise (R blau, L rot) und zwei
Punkte für den kranialen Pfannenrand an.

- **Kreis verschieben:** am Zentrum fassen und ziehen (grosse Trefferzone).
- **Radius ändern:** gelben Griff aussen am Kreis ziehen, oder **Mausrad** über dem Kreis.
- **Pfannenrand:** Punkt an den kranialen Acetabulumrand ziehen.
- Der Winkel wird live gezeichnet (Arm, Bogen, Wert bei 10 Uhr für R, 2 Uhr für L) und im
  Namen des Punkts gespeichert („Norberg R: 104.3°"). Er bleibt in der Datenbank und kommt beim
  nächsten Öffnen zurück.
- **Reset:** Menüpunkt oder Knopf erneut → Messung wird neu in die Fenstermitte gelegt.
- **Delete Norberg Measurement** (Menü oder Toolbar „Delete Norberg") entfernt sie.
- Bildschirm links = Patient rechts (VD-Konvention). Spiegeln des Bildes ändert die Zuordnung
  nicht.

Gemessen wird der Innenwinkel zwischen der Zentrenlinie und der Linie Zentrum → Pfannenrand,
in Millimetern über das Pixel-Spacing der Aufnahme, auf 0,1° gerundet. Ein kaudal statt
kranial gesetzter Punkt liefert denselben Innenwinkel; der Punkt gehört an den kranialen Rand.
**Nicht enthalten:** Flückiger-Schema und automatische HD-Grad-Zuordnung. Die Beurteilung nach
FCI oder einem anderen Schema nimmt die Tierärztin oder der Tierarzt selbst vor.

### 5.7 Distraktionsindex (Vet Tools › Distraction Index (PennHIP) — Place / Reset)

Laxitätsmessung auf der **Distraktionsaufnahme** nach der PennHIP-Formel. Der Menüpunkt oder
der Toolbar-Knopf **Distraction Index** legt je Seite zwei Kreise an: den Femurkopfkreis
(R blau, L rot, derselbe wie beim Norberg-Winkel) und einen gelben Kreis für die Pfanne.

- **Femurkopfkreis:** auf den Femurkopf legen, Radius über den gelben Griff aussen oder das
  Mausrad.
- **Pfannenkreis:** auf die Gelenkpfanne legen; Griff auf der Innenseite, Mausrad über dem Kreis.
  Überlappen beide Kreise, reagiert der, dessen Zentrum näher am Mauszeiger liegt.
- **DI** = Abstand der beiden Kreiszentren geteilt durch den Femurkopfradius. Eine rote Linie
  verbindet die Zentren, der Wert steht unter dem Femurkopf („DI 0.65") und wird im Namen des
  Pfannenkreises gespeichert.
- **Show DI Risk Level** (Haken im Menü Vet Tools) ergänzt das Label um die Stufe:
  < 0,30 low · 0,30–0,70 moderate · > 0,70 high. Diese Grenzen sind Praxiswerte; die
  rassebezogene Einordnung nach PennHIP bleibt Sache der Beurteilung.
- **Delete Distraction Index** (Menü oder Toolbar „Delete DI") entfernt die Pfannenkreise.
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
Offene Viewer werden vorher geschlossen; die Datenbank wird erst nach erfolgreichem Schreiben
geändert. Ein PACS, das die Studie schon hat, behält den alten Namen.

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

### 5.11 Weitere MPR-Verbesserungen

- **Convolution filter (SekhVet):** Popup in der MPR-Toolbar; Gauss, Sharpen, Unsharp Mask,
  Highpass auf allen drei Ebenen.
- **Thick Slab** steht ab Werk auf Mean (Horos: MIP).
- **Zoom** (Checkbox in der MPR-Toolbar): koppelt den Zoom der drei Ansichten eines Fensters.
  Vorgabe aus; zwischen Fenstern folgt der Zoom je Ansicht immer.
- **Fadenkreuz-Trefferzonen** grösser als in Horos (Zentrum 18 px, Linien 12 px), einstellbar in
  Vet Tools › Display.
- **Ruhiger Cursor:** Horos wechselt den Mauszeiger je nach Position; SekhVet zeigt den Pfeil
  (abschaltbar in Display).
- CT mit sehr grossem Wertebereich wird ohne Rückfrage auf −1024…7168 HU beschnitten
  (der Horos-Dialog „High Dynamic Values" entfällt).

### 5.12 DICOMweb (Vet Tools › DICOMweb Query (QIDO-RS / WADO-RS)…)

Horos spricht nur DIMSE (C-FIND/C-MOVE) und WADO-URI. SekhVet hat ein eigenes Fenster für
DICOMweb, das gegen Orthanc, dcm4chee und andere Server läuft.

1. **Knoten anlegen:** URL bis `/dicom-web` (z. B. `http://pacs.local:8042/dicom-web`),
   Benutzername. Das Passwort wird beim ersten Abruf abgefragt und im Schlüsselbund gespeichert
   (Basic Auth).
2. **Suchen** nach Name, ID, Datum, Modalität; Zeitraum-Popup (Vorgabe **Today**; Any date,
   Yesterday, Last 3 days, Last 4 days, Last week, Last month). Ergebnis mit Serien, Bildzahl,
   Uhrzeit und Institution. Eine Kugel vor dem Namen zeigt, ob die Studie schon ganz (grün) oder
   teilweise (orange) in der lokalen Datenbank liegt, wie beim Horos-Q/R.
3. **Abrufen:** markierte Studien per WADO-RS laden; Bilder landen in der Datenbank.
   Grosse Studien werden gestreamt, nicht komplett im Speicher gehalten.
4. **Senden:** **Vet Tools › Send Selected Studies via STOW-RS…** oder der Knopf im Fenster
   schickt die in der Datenbank markierten Studien an den Knoten.

Toolbar-Knopf **DICOMweb** in der Datenbank neben „Query". Die klassischen Horos-Locations
(DIMSE) bleiben unverändert nutzbar.

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
- **Annotations:** Schrift, Grösse (Vorgabe Helvetica Bold 14), Textfarbe (Vorgabe weiss),
  Kontur/Kasten (Vorgabe: Kasten 70 % schwarz mit Kontur) für Messtexte, Ecken-Text und die
  Werte der HD-Messungen. Änderungen greifen sofort.
- **Appearance:** System / Light / Dark, Vorgabe Dark.
- **Modality colours:** Studien- und Serienzeilen in der Datenbank nach Modalität getönt
  (CT blau, MR violett, Röntgen grün, US orange …). Abschaltbar.
- **Magnetic windows:** ab Werk aus, Fenster bleiben frei verschiebbar.
- **MPR:** Trefferzonen, statischer Cursor, MPR-Sync, Kachelung, Zoom-Sync.

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
sind und am rechten Rand dieselbe Tiefenskala zeigen (die Skalenstreifen werden verglichen).
Der Messtext trägt den Zusatz „US calibration from image N“, damit die Herkunft sichtbar bleibt.
Cine-Loops dienen nie als Quelle. Abschaltbar im Terminal:
```
defaults write vet.kappa1.sekhvet.horos SekhmetUSCalibrationFallback -bool NO
```
Bisher an einem Gerät geprüft (Mindray Vetus 9). Stimmt eine geborgte Kalibrierung bei Ihrem
Gerät nicht, schalten Sie die Funktion ab und melden Sie das Gerätemodell.

## 6. Bedienung, die anders ist als in Horos

| Thema | Horos | SekhVet |
|---|---|---|
| Randbuchstaben | A/P, S/I | Cr/Cd, D/V (schaltbar) |
| Hängung | Rows/Columns je Modalität | Presets mit Orientierungsregeln, Keywords, DX-Regeln, Öffnungsprotokolle |
| Fenster aktiv machen | Rechtsklick/Scrollrad | auch Linksklick |
| Messtext | Geneva 12 in ROI-Farbe | Helvetica Bold 14, weiss auf Kasten |
| Erscheinungsbild | folgt System | Dark als Vorgabe, umschaltbar |
| Propagate settings | je nach Protokoll wieder an | bleibt aus, bis man es einschaltet |
| Magnetische Fenster | an | aus |
| Thick Slab | MIP | Mean |
| Serie öffnen | Regler mit einem Strich je Bild (langsam bei grossen Serien) | ohne Striche, deutlich schneller |
| Update-Prüfung | stündlich gegen Horos-Server | keine |
| Horos Cloud | Plugin | entfernt |
| Datenordner | Horos Data | SekhVet Data |
| DICOM-Port | 11112 | 11113 |

Alle SekhVet-Fenster öffnen sich innerhalb der Viewer-Fläche. Alle Toolbar-Knöpfe von SekhVet
lassen sich über **Customize Toolbar** verschieben oder entfernen; neue Knöpfe erscheinen einmal
automatisch, entfernt man sie, bleiben sie weg.

## 7. Beta-Stand, Grenzen und bekannte Einschränkungen (Build 95)

**Experimentell in dieser Beta.** Diese Funktionen laufen, sind aber erst an wenigen Geräten
geprüft oder werden noch nachjustiert. Mit kritischem Blick benutzen und Auffälligkeiten melden:

- **Spine Labeling** (5.5): die Zähllogik wird noch angepasst.
- **Hanging Protocol im 3D-MPR** (5.2, MPR-Teil) und **Öffnungsprotokolle** (5.3) samt
  Röntgen-Zweiebenen-Hängung: im September 2026 neu gebaut, headless geprüft, Prüfung am Gerät
  läuft noch.
- **Ultraschall-Kalibrierung vom Nachbarbild** (5.16): an einem Gerät geprüft.
- **MPR-Doppelklick-Zoom** (5.10): in seltenen Fällen kam eine Ansicht nach dem Doppelklick
  schwarz oder weiss; Build 92 hat Riegel eingebaut, und tritt es wieder auf, steht eine
  Diagnosezeile im Systemprotokoll (`log show --predicate 'process == "Horos"' --last 30m | grep "SekhVet MPR"`).
- **macOS 27:** bisher eine Testinstallation; der Alltag läuft unter macOS 26.

**Im Alltag bewährt** (stabil im Sinn dieser Beta): Randbuchstaben, Hanging Protocol in 2D,
Fensterungs-Presets, Norberg-Winkel, Distraktionsindex, Point-Werkzeug, Double MPR,
Faltungsfilter, DICOMweb-Suche/Abruf/Senden, Bild- und PDF-Import, Patient umbenennen,
Display-Einstellungen, Feedback- und Beitragsfenster.

**Allgemeine Grenzen:**

- **Kein zertifiziertes Medizinprodukt** (siehe oben). Keine formale Validierung der Messungen.
  Geräte für den Veterinärbereich fallen weder unter die EU-Verordnung 2017/745 noch unter die
  Schweizer MepV; beide gelten für Produkte am Menschen. Für veterinärmedizinische Bildsoftware
  gibt es in keinem der beiden Rechtsräume ein Zertifizierungsverfahren.
- **Nur Apple Silicon**, macOS 12 oder neuer; praktisch getestet unter macOS 26 und 27.
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
- **Sprache:** Oberfläche Englisch, keine deutsche Lokalisierung.
- **Keine automatischen Updates**; neue Builds werden auf GitHub angekündigt.

## 8. Lizenz, Quellcode, Beitrag

SekhVet ist freie Software unter der GNU Lesser General Public License 3.0 und basiert auf
Horos (Horos Project) und OsiriX (Pixmeo SARL). Der vollständige Quellcode dieser Version,
einschliesslich aller Änderungen an Horos, liegt unter https://github.com/3v3nFloW/sekhvet
(auch hinter „Source code“ im About-Fenster).

Wer SekhVet nützlich findet, kann die Weiterentwicklung mit einem freiwilligen Beitrag
mittragen: **Vet Tools › Contribute to SekhVet…** Der Betrag ist frei wählbar, es gibt keine
Gegenleistung und keine Zusatzfunktionen dafür.

© 2026 Kappa1-VRS GmbH, Zürich. Horos und OsiriX sind Marken ihrer jeweiligen Inhaber.
