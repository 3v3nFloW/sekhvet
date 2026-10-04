/*=========================================================================
 SekhVet Paket DO — Messungen-Navigator im 2D-Viewer.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Wunsch 04.10.2026 (Vorbild OsiriX MD): sobald eine Serie Messungen
 (ROIs) hat, zeigt eine Leiste am unteren Bildrand je Schicht mit Messung ein
 Vorschaubild; ein Klick springt auf diese Schicht und markiert ihre Messung.
 Daneben "Delete all" (Horos' roiDeleteAll:, mit Rueckfrage; gesperrte ROIs
 bleiben, Cmd-Z holt alles zurueck) und "x" (schaltet den Navigator ab).
 Eigene Umsetzung auf der Horos-Codebasis (kein OsiriX-Code, keine OsiriX-Texte).

 Ein/aus: Vet Tools › Display (Schluessel SekhmetMessNavigator, Vorgabe an)
 und der Symbolleisten-Umschaltknopf "Measurements". Zweiter Knopf
 "Delete All" = alle Messungen der Serie loeschen (auch bei abgeschaltetem
 Navigator).

 Die Leiste ist eine eigene NSView UEBER dem Bild — Geschwister des DCMView in
 der StudyView, keine Unteransicht des OpenGL-Views; das Bild verschiebt sich
 nicht. Vorschau = DCMPix generateThumbnailImageWithWW:WL: mit Fenster,
 Drehung und Spiegelung des Viewers, die ROIs darin in ihrer Farbe.
 Die Leiste haengt als assoziiertes Objekt am ViewerController; Haken in
 ViewerController.m: setWindowTitle: (anlegen/auffrischen) und
 windowWillClose: (abmelden).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ViewerController;

extern NSString* const SekhmetMessNavigatorKey;                     // BOOL, fehlt = an
extern NSString* const SekhmetMessNavigatorToolbarItemIdentifier;   // "SekhmetMessNavigator" — Umschaltknopf
extern NSString* const SekhmetMessLoeschenToolbarItemIdentifier;    // "SekhmetMessLoeschen" — alle Messungen loeschen
extern NSString* const SekhmetMessNavigatorDidChangeNotification;   // ein/aus umgeschaltet

@interface SekhmetMessNavigator : NSView

+ (BOOL) eingeschaltet;
+ (void) setEingeschaltet:(BOOL) an;                     // alle offenen Viewer folgen sofort
+ (void) aktualisiere:(ViewerController*) v;             // aus -[ViewerController setWindowTitle:]
+ (void) abmelden:(ViewerController*) v;                 // aus -[ViewerController windowWillClose:]
+ (void) konfiguriereToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) v;          // Umschaltknopf
+ (void) konfiguriereLoeschenToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) v;  // "Delete All"
+ (void) loescheAlleMessungen:(ViewerController*) v;     // mit Rueckfrage
+ (NSImage*) toolbarIcon;
#if SEKHVET_TESTHAKEN
+ (NSString*) debugZustand:(ViewerController*) v;        // Rahmen, Schichten, sichtbar — fuer den Lauf ohne Bildschirm
#endif

@end
