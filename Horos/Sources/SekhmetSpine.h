/*=========================================================================
 Sekhmet — Spine Labeling (Vet): Klick-Zaehlwerk fuer Wirbel-Labels.
 Jeder Klick mit dem Punkt-Werkzeug setzt eine 2D-Punkt-ROI mit dem naechsten
 Label (C1–7, T1–13, L1–7, S1–3, Cd1…; Tierarten Hund/Katze, Kaninchen, Pferd);
 Alt-Klick = Bandscheibe (L1-L2). Im 3D-MPR wird der Punkt in der Originalserie
 angelegt (Horos add2DPoint) und in allen Ebenen gezeigt; ROIs bleiben in der
 Datenbank. ⌫ nimmt das letzte zurueck, Esc beendet.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ROI, DCMView;

@interface SekhmetSpine : NSWindowController
{
    NSPopUpButton *speciesPopup, *regionPopup;
    NSTextField *numberField, *nextLabel;
    NSButton *backwardsButton, *startButton;
    BOOL active;
    NSInteger species, region, number;
    BOOL backwards;
    NSString *lastVertebra;
    NSMutableArray *createdROIs;   // persistente ROIs (2D-Viewer), fuer ⌫
}

+ (SekhmetSpine*) shared;
+ (BOOL) isActive;
+ (NSArray*) speciesNames;
+ (NSArray*) regionNames;

// Haken fuer DCMView (neue Punkt-ROI entsteht) und MPRDCMView (persistente Kopie)
+ (void) willCreatePointROI:(ROI*) roi inView:(DCMView*) view modifiers:(NSUInteger) flags;
+ (void) notePersistentROI:(ROI*) roi;
+ (BOOL) handleKey:(unichar) c;     // YES = verbraucht

// Umbenennen mit Neuzaehlung ab dort (ImagoPilot-Praemisse 8): Labels parsen und zaehlen
+ (BOOL) parseLabel:(NSString*) label region:(NSInteger*) region number:(NSInteger*) number;   // "C1".."Cd12"
+ (BOOL) isDiscLabel:(NSString*) label;                                                          // "L1-L2"
+ (double) rankOfLabel:(NSString*) label;                                                        // Reihenfolge entlang der Wirbelsaeule, < 0 = kein Label
#if SEKHVET_TESTHAKEN
+ (NSString*) debugSelfTest;
#endif // SEKHVET_TESTHAKEN
+ (NSString*) levelLabelForMPRView:(id) view;            // naechstes Wirbel-Label entlang der Ebenennormalen, nil wenn keins
+ (void) updateLevelAnnotationForMPRView:(id) view;      // schreibt "Spine level: L3" in die TopLeft-Beschriftung des MPR-Pix                                                                     // SEKHVET_SPINE_TEST: Zaehl- und Umbenenn-Logik ohne GUI

- (void) toggleWithWindowController:(NSWindowController*) wc;
- (void) start;
- (void) stop;
- (void) undo;
- (NSString*) peekLabel;
- (NSString*) takeLabelWithModifiers:(NSUInteger) flags;   // naechstes Label holen und weiterzaehlen (Alt = Bandscheibe)

@end
