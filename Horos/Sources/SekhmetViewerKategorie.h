/*=========================================================================
 ViewerController (SekhVet) — Werkzeugleisten-Aktionen des 2D-Viewers:
 Punkt-Werkzeug, Wirbel, Norberg, Bildschirmbereich, Vet-Protokoll.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in ViewerController.m — zusammen rund 450 Zeilen fremder Code in
 Horos-eigenen Dateien. Als Kategorie stehen sie jetzt fuer sich; in
 ViewerController.m bleiben nur die Haken, die sie rufen, und die
 Instanzvariablen (die kann eine Kategorie nicht tragen).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#import "ViewerController.h"

// Werkzeugleisten-Kennungen der SekhVet-Knoepfe. Standen bis Stufe 6c als `static`
// mitten zwischen den Horos-eigenen Kennungen in ViewerController.m — und waren
// damit fuer die Kategorie unsichtbar.
extern NSString* const SekhmetVetPresetToolbarItemIdentifier;  // „SekhmetVetPreset" — Vet-Orientierung: Preset je Studie
extern NSString* const SekhmetSpineToolbarItemIdentifier;  // „SekhmetSpine" — Wirbel-Labels
extern NSString* const SekhmetNorbergToolbarItemIdentifier;  // „SekhmetNorberg" — Norberg-Winkel (HD), Paket V
extern NSString* const SekhmetNorbergDeleteToolbarItemIdentifier;  // „SekhmetNorbergDelete" — Messung entfernen, Paket W
extern NSString* const SekhmetDIToolbarItemIdentifier;  // „SekhmetDI" — Distraktionsindex (PennHIP), Paket BD
extern NSString* const SekhmetDIDeleteToolbarItemIdentifier;  // „SekhmetDIDelete" — Distraktionsindex entfernen, Paket BD
extern NSString* const SekhmetScreenAreaToolbarItemIdentifier;  // „SekhmetScreenArea" — Bildschirmflaeche

@interface ViewerController (SekhVet)
- (IBAction) sekhmetShow3DPointTool:(id) sender;
- (void) sekhmetUpdatePresetPopup;
- (void) sekhmetBorrowUSCalibration:(NSArray*) pixListArray; // SekhVet Paket BH
- (IBAction) sekhmetSpineTool:(id) sender;
- (IBAction) sekhmetNorbergTool:(id) sender;  // SekhVet Paket V
- (IBAction) sekhmetNorbergDeleteTool:(id) sender;  // SekhVet Paket W
- (IBAction) sekhmetDITool:(id) sender;  // SekhVet Paket BD
- (IBAction) sekhmetDIDeleteTool:(id) sender;  // SekhVet Paket BD
- (void) sekhmetEnsureNorbergToolbarItem;
- (IBAction) sekhmetScreenAreaChanged:(id) sender;
- (IBAction) sekhmetPresetChanged:(id) sender;
- (void) sekhmetPresetDidChange:(NSNotification*) n;
@end
