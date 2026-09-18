/*=========================================================================
 SekhVet Paket AU — Oeffnungsprotokolle je Modalitaet und Koerperregion.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Beim Doppelklick auf eine Studie in der Datenbank entscheidet ein Protokoll,
 WELCHE Serien aufgehen, in welcher Reihenfolge (links -> rechts), in welcher
 Kachelung und mit welcher Fensterung. Das erste passende Protokoll gewinnt;
 passt keines, oeffnet Horos wie bisher.

 Warum nicht Horos' Hanging Protocol: dessen "SeriesOrder" ist reine
 Stichwortsuche auf der Serienbeschreibung, kennt weder nativ/KM noch eine
 Fensterung je Viewport, und die Studienbeschreibung ist beim Esaote-MR der Praxis
 durchgehend leer (siehe [[reference-seriennamen-ct-mr-kappa1]]).

 Erkennung, alles aus den Serien-Tags der ersten Datei je Serie:
   - Region   : Serienname + ProtocolName (0018,1030) + BodyPartExamined (0018,0015)
   - Fenster  : ueber die WL/WW-Regel aus Paket AE/AH (Name der Regel, z.B. "Bone (vet)")
   - Kontrast : "nativ"/"N" gegen "KM"/"post KM"/"CE"/"C" als eigenes Wort
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class DicomStudy, DicomSeries, ViewerController;

extern NSString* const SekhmetOpeningProtocolsKey;     // Array von Protokoll-Dictionaries
extern NSString* const SekhmetOpeningEnabledKey;       // BOOL, Hauptschalter
extern NSString* const SekhmetOpeningSmallWidthKey;    // float: Bildschirmbreite, unter der gedeckelt wird
extern NSString* const SekhmetOpeningSmallMaxKey;      // int: hoechstens so viele Viewer auf kleinem Schirm
extern NSString* const SekhmetTwoViewEnabledKey;       // BOOL: Roentgen-Zweiebenen nebeneinander (Paket AY)
extern NSString* const SekhmetTwoViewLateralLeftKey;   // BOOL: seitliche Aufnahme links (Vorgabe: rechts)

/** Kontrastphase einer Serie. */
enum {
    SekhmetContrastAny    = 0,
    SekhmetContrastNative = 1,
    SekhmetContrastAgent  = 2
};

/** Schluessel eines Protokoll-Dictionaries:
 *    name        NSString   Anzeigename ("MR Kopf")
 *    modality    NSString   "CT" / "MR"; leer = jede
 *    region      NSString   |-Liste von Stichworten auf dem Regionstext; leer = jede Region
 *    rows        NSNumber   Kachelung, Zeilen
 *    columns     NSNumber   Kachelung, Spalten
 *    blackTiles  NSNumber   BOOL: leere Zellen als schwarze Kachel stehen lassen
 *                           (aus = die uebrigen ruecken auf)
 *    positions   NSArray    Positionen, Reihenfolge = links -> rechts, dann naechste Zeile
 *
 *  Schluessel einer Position:
 *    keywords    NSString   |-Liste; eines muss im Suchtext der Serie vorkommen; leer = egal
 *    without     NSString   |-Liste; kommt eines vor, scheidet die Serie aus
 *    window      NSString   Name einer WL/WW-Regel aus Paket AE ("Soft tissue"); leer = egal
 *    contrast    NSNumber   SekhmetContrast*
 *    wl, ww      NSNumber   erzwungene Fensterung; ww <= 0 = Regel aus Paket AE gilt
 */

@interface SekhmetOpening : NSObject

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues;
+ (NSArray*) defaultProtocols;

/** Das erste Protokoll, das zu dieser Studie passt, oder nil. */
+ (NSDictionary*) protocolForStudy:(DicomStudy*) study;

/** Suchtext einer Serie (Serienname + Kernel + ProtocolName + BodyPartExamined), zwischengespeichert. */
+ (NSString*) searchTextForSeries:(DicomSeries*) series;

/** Kontrastphase aus dem Suchtext. */
+ (NSInteger) contrastForSeries:(DicomSeries*) series;

/** Serien in Positionsreihenfolge; NSNull fuer eine Position, die keine Serie fand. */
+ (NSArray*) seriesForProtocol:(NSDictionary*) protocol study:(DicomStudy*) study;

/** Oeffnet die Studie nach Protokoll. NO = kein Protokoll gefunden oder abgeschaltet,
 *  dann macht der Aufrufer weiter wie bisher. */
+ (BOOL) applyToStudy:(DicomStudy*) study;

/** SekhVet Paket AY — Roentgen-Zweiebenen-Aufhaengung, aus ImagoPilot (zwei-ebenen.ts) uebernommen.
 *  Eine Studie mit genau zwei Einzelaufnahmen (CR/DX/IO/PX/MG) derselben Region (BodyPartExamined)
 *  in verschiedenen Projektionen geht nebeneinander auf; die seitliche (LL/RL/ML/LM/LAT) kommt
 *  nach rechts (Vorgabe 14.09.26: "VD links, LL rechts"), per Einstellung nach links.
 *  Liefert die beiden Serien in Anzeige-Reihenfolge (links, rechts) oder nil. */
+ (NSArray*) twoViewPairForStudy:(DicomStudy*) study;

/** Projektion: ViewPosition (0018,5101), sonst letztes Wort des Seriennamens (erst ab zwei Woertern). */
+ (NSString*) projectionForViewPosition:(NSString*) viewPosition name:(NSString*) name;

/** 0 = nicht entscheidbar (Projektion fehlt oder gleich), 1 = erste links, 2 = zweite links.
 *  Ohne Datenbank, damit der Selbsttest sie prueft. */
+ (NSInteger) twoViewOrderForProjection:(NSString*) a projection:(NSString*) b lateralLeft:(BOOL) lateralLeft;

/** Kontrastphase aus einem Seriennamen — ohne Datenbank, damit der Selbsttest sie prueft. */
+ (NSString*) nameForSeries:(DicomSeries*) series;   // Serientext, siehe .m
+ (NSInteger) contrastForName:(NSString*) name;

/** Rechteck der Rasterzelle (0 = links oben, zeilenweise). */
+ (NSRect) cellRect:(int) index rows:(int) rows columns:(int) columns screen:(NSScreen*) screen;

/** Beobachter fuer das Aufraeumen der schwarzen Kacheln; einmal beim Start rufen. */
+ (void) installObservers;

/** "Take from screen": die offene Anordnung als Positionen in dieses Protokoll schreiben. */
+ (void) takeFromScreenIntoProtocol:(NSMutableDictionary*) protocol;

/** Testhaken SEKHVET_OPENING_TEST="<PatientID-Teil>": Protokollwahl und Belegung protokollieren. */
#if SEKHVET_TESTHAKEN
+ (void) debugOpeningFromEnvironment;
+ (void) debugTakeFromScreen;   // SEKHVET_OPENING_TAKE_TEST=1
+ (NSString*) debugSelfTest;   // SEKHVET_OPENING_SELFTEST: Zuordnung gegen eingebaute Beispielnamen
#endif // SEKHVET_TESTHAKEN

@end

/** Schwarze Kachel: randloses Fenster, das eine leere Rasterzelle abdeckt, damit
 *  auf dem Schirm kein Desktop durchscheint. Kein Viewer, kein DICOM. */
@interface SekhmetBlackTile : NSWindow
+ (void) showOnFreeCellsForRows:(int) rows columns:(int) columns taken:(NSArray*) taken screen:(NSScreen*) screen;
+ (void) closeAll;
@end

/** Einstellfenster "Vet Tools > Opening Protocols…". */
@interface SekhmetOpeningPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
    NSTableView *protocolTable;      // linke Liste: Protokolle
    NSTableView *positionTable;      // rechte Liste: Positionen des gewaehlten Protokolls
    NSMutableArray *protocols;       // NSMutableDictionary je Protokoll
    NSButton *enabledButton;
    NSButton *blackTilesButton;
    NSTextField *regionField, *rowsField, *columnsField;
    NSTextField *smallWidthField, *smallMaxField;
    NSButton *twoViewButton;          // SekhVet Paket AY
    NSPopUpButton *lateralSidePopup;  // SekhVet Paket AY
}
+ (SekhmetOpeningPanel*) shared;
- (NSMutableDictionary*) selectedProtocol;
@end
