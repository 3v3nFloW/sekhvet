/*=========================================================================
 DCMView (SekhVetLupe) — Paket CC: Lupe beim Messen + ueberarbeitete freie Lupe.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Nutzerwunsch 27.09.2026: beim Messen ein vergroessertes Bild des Messbereichs.
 Eigene Umsetzung auf der Horos-Codebasis (kein OsiriX-Code, keine OsiriX-Texte).

 Ein Zeichner fuer beide Faelle: der Bildausschnitt um den Punkt wird ein
 zweites Mal gezeichnet, mit hoeherem Zoom in ein eigenes Feld — dieselben
 Texturen, dieselbe Fensterung, Drehung und Spiegelung, und die Messlinien
 (ROIs) liegen darin. Die alte Horos-Lupe kopierte dagegen den 8-Bit-Puffer
 in einen runden Ausschnitt direkt UNTER dem Zeiger, ohne ROIs, und war mit
 einem Messwerkzeug gesperrt.

 - Beim Messen (linke Taste gedrueckt, eine LAENGENMESSUNG wird gezeichnet oder
   einer ihrer Punkte gezogen — seit Paket CO nur noch tMesure): Feld in der
   Ecke, die vom Zeiger am weitesten weg ist.
   Abschaltbar mit dem Schluessel SekhmetMessLupe = NO.
 - Freie Lupe (Shift ueber dem Bild, Einstellung "Show Magnifying Lens with
   'shift' key"): dasselbe Feld neben dem Zeiger statt darueber.
 - Solange die Lupe sichtbar ist: → / ← (oder + / −, oder Scrollrad) Vergroesserung,
   ↑ / ↓ Groesse des Felds. Beides bleibt gespeichert
   (SekhmetLupeZoom, SekhmetLupeGroesse).
 Im 2D-Viewer und (seit Paket CE) in den MPR-Ansichten; andere
 DCMView-Unterklassen behalten die alte Horos-Lupe.
 SekhVet Paket CS: never drawn into an export view; the second pass no longer
 leaves the ROIs' text-box hit rectangles in lens coordinates. In a fused
 (blended) view the lens shows the base series only.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"
#import "DCMView.h"

@interface DCMView (SekhVetLupe)
- (BOOL) sekhmetLupeErlaubt;                 // 2D-Viewer oder MPR-Ansicht (Paket CE)
- (BOOL) sekhmetLupeBeimMessen;             // wird gerade eine LAENGE gemessen (Lupe in der Ecke)? Paket CO: nur tMesure
#if SEKHVET_TESTHAKEN
- (BOOL) sekhmetFreieLupeAktiv;             // Horos' Shift-Lupe ist gerade an (lensTexture); SekhVet Paket CS: only used by the overlay test
#endif // SEKHVET_TESTHAKEN
- (void) sekhmetZeichneLupe;                 // aus drawRect:withContext:, nach dem Bild und den ROIs
- (BOOL) sekhmetLupeTaste:(unichar) c;       // aus keyDown:; YES = Taste verbraucht
- (BOOL) sekhmetLupeRad:(NSEvent*) e;        // aus scrollWheel:; YES = Rad veraendert den Lupenzoom
@end
