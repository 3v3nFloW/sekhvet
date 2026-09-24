/*=========================================================================
 Sekhmet — Spine Labeling (Vet): Klick-Zaehlwerk fuer Wirbel-Labels.
 Jeder Klick mit dem Punkt-Werkzeug setzt eine 2D-Punkt-ROI mit dem naechsten
 Label (C1–7, T1–13, L1–7, S1–3, Cd1…; Wirbelformel je Tierart, je Studie
 aenderbar fuer Uebergangswirbel). Die Zaehlrichtung ergibt sich aus den
 ersten zwei Klicks, ein Klick zwischen zwei Labels setzt die Bandscheibe
 (Alt-Klick erzwingt sie). ⌫ nimmt das letzte zurueck, Esc beendet.

 Paket BR (19.09.2026): die ROIs bleiben die Wahrheit (ziehen, loeschen,
 umbenennen, Horos speichert sie mit der Serie); daneben haelt SekhVet je
 Studie eine Liste der 3D-Punkte (JSON in <Datenordner>/SPINE). Aus ihr
 zeichnet jede Ansicht mit gleichem Frame of Reference: quer zur
 Wirbelsaeule die Hoehe als Eck-Label ("L3", zwischen zwei Wirbeln
 "L3-L4"), laengs dazu die projizierten Marker mit Hilfslinie.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ROI, DCMView;

@interface SekhmetSpine : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSWindowDelegate>
{
    NSPopUpButton *speciesPopup, *regionPopup, *directionPopup;
    NSButton *markersButton, *elsewhereButton;   // SekhVet Paket BT
    NSTextField *numberField, *nextLabel, *listStatus;
    NSTextField *formulaFields[ 4];    // C, T, L, S
    NSButton *startButton;
    NSColorWell *colorWell;            // SekhVet Paket BU: Label-Farbe
    NSTableView *labelTable;
    BOOL active;
    NSInteger region, number;
    NSInteger counts[ 5];              // Wirbelformel, Cd offen
    BOOL backwards;
    int placedInRun;                   // Wirbel seit Start / seit einer Aenderung am Startfeld (Richtung aus den ersten zwei)
    float lastPoint[ 3];
    NSString *lastVertebra;
    NSMutableArray *createdROIs;       // persistente ROIs (2D-Viewer), fuer ⌫
    NSMutableDictionary *store;        // StudyInstanceUID -> { labels: [ {label,x,y,z,for,series,seriesName} ], formula: [C,T,L,S] }
    NSMutableDictionary *roiSeries;    // NSValue(ROI*) -> seriesDICOMUID (Loesch-Meldungen beim Serienwechsel/Schliessen aussortieren)
    NSMutableSet *notedViewers;        // "<Zeiger>|<SerienUID>": Bestand dieser Serie schon uebernommen
    NSString *currentStudyUID;         // Studie, die das Panel zeigt
    NSArray *tableRows;
}

+ (SekhmetSpine*) shared;
+ (BOOL) isActive;
+ (void) labelColorR:(float*) r g:(float*) g b:(float*) b;   // SekhVet Paket BU
+ (NSArray*) speciesNames;
+ (NSArray*) regionNames;

// Haken fuer DCMView (neue Punkt-ROI entsteht) und MPRDCMView (persistente Kopie)
+ (void) willCreatePointROI:(ROI*) roi inView:(DCMView*) view modifiers:(NSUInteger) flags;
+ (void) notePersistentROI:(ROI*) roi;
+ (BOOL) handleKey:(unichar) c;     // YES = verbraucht
+ (void) filterPointCopiesInMPRView:(id) view;   // SekhVet Paket BT: Haken am Ende von MPRDCMView detect2DPointInThisSlice

// Umbenennen mit Neuzaehlung ab dort: Labels parsen und zaehlen
+ (BOOL) parseLabel:(NSString*) label region:(NSInteger*) region number:(NSInteger*) number;   // "C1".."Cd12"
+ (BOOL) isDiscLabel:(NSString*) label;                                                          // "L1-L2"
+ (double) rankOfLabel:(NSString*) label;                                                        // Reihenfolge entlang der Wirbelsaeule, < 0 = kein Label
// Hoehe der Schicht aus den Wirbelpunkten: t = Lage der Schicht entlang der Achse erster -> letzter Wirbel (wie die Punkte)
+ (NSString*) levelForPosition:(float) t points:(NSArray*) sortedByT;                            // Eintraege {label, t}; nil ausserhalb
#if SEKHVET_TESTHAKEN
+ (void) debugE2E;                 // SEKHVET_SPINE_E2E_TEST=1
+ (NSString*) debugSelfTest;        // SEKHVET_SPINE_TEST: Zaehl-, Umbenenn- und Hoehenlogik ohne GUI
#endif // SEKHVET_TESTHAKEN

- (void) toggleWithWindowController:(NSWindowController*) wc;
- (void) start;
- (void) stop;
- (void) undo;
- (NSString*) peekLabel;

@end
