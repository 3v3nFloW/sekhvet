/*=========================================================================
 SekhVet Paket CA — Sequenz-Plaketten in der Serienliste.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Nachbau der Seitenleiste aus ImagoPilot (apps/web/src/shell/sequenz.ts,
 27.09.2026): In der Serienliste war nicht zu sehen, ob eine MR-Serie T1 oder
 T2 ist, weil der Name ("HKCL SE T1 tra post KM HawkAI") abgeschnitten wurde.
 Jetzt liest dieser Erkenner Gewichtung und Kontrastmittel aus der
 SeriesDescription; Viewer-Leiste und DB-Vorschau zeigen beides als Plakette
 unten auf der Miniatur, den vollen Namen darunter mit Umbruch (hoechstens drei
 Zeilen, der ganze Name im Tooltip).

 Nur aus dem Namen, nicht aus TR/TE: der Name ist, was die MTRA gewaehlt hat,
 und bei 3D-Gradientenecho (Esaote SST1, HYCE) sagen TR/TE wenig.
 Regeln und Testfaelle 1:1 aus ImagoPilot: SekhVet/test/sequenz-test.sh
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@interface SekhmetSequenz : NSObject

// Gewichtung/Sequenztyp ("T1", "T2", "T2*", "PD", "FLAIR", "STIR", "DWI", "ADC", "SWI", "HYCE") oder nil.
// km = nach Kontrastmittel (post KM, +C, Gd ...), sub = Differenzserie aus der Subtraktion.
// SekhVet Paket CS: "ohne KM", "vor KM", "pre contrast", "non contrast", "w/o contrast" are NOT km; "T1+C" is.
+ (NSString*) kontrastFuer:(NSString*) beschreibung km:(BOOL*) km sub:(BOOL*) sub;

// SekhVet Paket CS: CT phase from the series name: 0 unknown, 1 native (also "pre KM", "without contrast"), 2 contrast.
+ (int) ctPhaseFuer:(NSString*) beschreibung;

// Farbe je Gewichtung als "#rrggbb" — T1 hell, T2 blau (Wasser hell), Rest gedaempft.
+ (NSString*) farbeFuerKontrast:(NSString*) kontrast;

#if SEKHVET_TESTHAKEN
// Name der Differenzserie aus den Woertern, in denen sich die beiden Serien unterscheiden
// ("SUB post KM", bei CT "SUB KM-nativ"), hoechstens 24 Zeichen.
// SekhVet Paket CS: no caller in the app yet, only the unit test — kept out of release builds.
+ (NSString*) subtraktionsName:(NSString*) plus minus:(NSString*) minus;
#endif // SEKHVET_TESTHAKEN

// Miniatur mit Plaketten unten links (schwarz 78 %); ohne erkannte Sequenz das Bild selbst.
// SekhVet Paket CS: with a modality, the weighting badge (T1/T2/...) is drawn for MR only; KM and SUB stay for
// every modality. The variant without modality (or modalitaet = nil) behaves as before.
+ (NSImage*) bild:(NSImage*) bild mitPlakettenFuer:(NSString*) beschreibung;
+ (NSImage*) bild:(NSImage*) bild mitPlakettenFuer:(NSString*) beschreibung modalitaet:(NSString*) modalitaet;

// Name in hoechstens drei Zeilen, die Umbrueche als "\n" schon gesetzt; laengere enden auf "…".
+ (NSString*) name:(NSString*) name dreiZeilenBreite:(CGFloat) breite font:(NSFont*) font;

@end
