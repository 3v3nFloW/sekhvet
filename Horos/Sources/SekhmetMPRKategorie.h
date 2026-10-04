/*=========================================================================
 MPRController (SekhVet) — Faltung, Gleichlauf zwischen MPR-Fenstern,
 Hanging Protocol, gemerkte Lage je Serie.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in MPRController.m — zusammen rund 450 Zeilen fremder Code in
 Horos-eigenen Dateien. Als Kategorie stehen sie jetzt fuer sich; in
 MPRController.m bleiben nur die Haken, die sie rufen, und die
 Instanzvariablen (die kann eine Kategorie nicht tragen).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#import "MPRController.h"
#import "CPRController.h" // SekhVet Paket CH
#import "OrthogonalMPRViewer.h" // SekhVet Paket CH

@class DCMPix, MPRDCMView;

/** Ein MPR-Fenster hat seinen Kamerastand geaendert — die anderen ziehen nach. */
extern NSString* const SekhmetMPRDidChangeNotification;

/** Gesetzt, solange ein Fenster einen fremden Stand uebernimmt oder eine gemerkte
 *  Lage zurueckspielt: in dieser Zeit meldet niemand etwas zurueck (sonst Ping-Pong).
 *  War bis Stufe 6c ein `static` in MPRController.m; die eine Horos-Stelle, die ihn
 *  liest (Zoom-Gleichlauf der drei Ansichten), erreicht ihn jetzt hierueber. */
extern BOOL SekhmetMPRSyncing;

@interface MPRController (SekhVet)
- (DCMPix*) sekhmetFirstPix;
- (MPRDCMView*) sekhmetView:(int) i;
- (void) sekhmetApplyConvolutionToPix:(DCMPix*) pix;
- (IBAction) sekhmetConvChanged:(id) sender;
- (IBAction) sekhmetSpineTool:(id) sender;
- (void) sekhmetApplyHangingProtocol;
- (void) sekhmetApplyPendingHangingProtocol;  // SekhVet Paket CS: protocol was applied while a view was zoomed - complete it after un-zoom
- (void) sekhmetPresetDidChange:(NSNotification*) n;
- (IBAction) sekhmetPresetChanged:(id) sender;
- (IBAction) sekhmetToggleSync:(id) sender;
- (void) sekhmetSyncSettingDidChange:(NSNotification*) n;  // SekhVet Paket CS: MPR-Sync was switched somewhere else - update the toolbar item
- (BOOL) sekhmetHPApplied;
+ (void) sekhmetSetSyncSuppressed:(BOOL) on;
- (void) sekhmetSettleAfterHP;  // SekhVet Paket AF
- (void) sekhmetScheduleSyncBroadcast;
- (void) sekhmetBroadcastSync;
- (NSString*) sekhmetStateSeriesUID;
- (void) sekhmetSaveViewState;
- (BOOL) sekhmetRestoreViewState;
- (NSArray*) sekhmetCurrentViews;               // SekhVet Paket DA: cameras, flips, crosshair angles of the three views (nil = no camera)
- (BOOL) sekhmetApplyViews:(NSArray*) views;    // SekhVet Paket DA: the restore part of sekhmetRestoreViewState (NO = unusable)
- (IBAction) sekhmetResetView:(id) sender;
- (NSString*) sekhmetCameraFingerprint;  // SekhVet Paket R: Kamerastand der drei Ansichten, gerundet (Echo-Erkennung)
- (void) sekhmetDelayedFullLODRendering;  // SekhVet Paket R: scharf nachrendern als Folge eines Empfangs -> nichts zuruecksenden
- (NSString*) sekhmetFoRForPix:(DCMPix*) pix;  // nil = no frame of reference known, never sync (SekhVet Paket CS)
- (void) sekhmetSyncFromNotification:(NSNotification*) n;
@end

/** SekhVet Paket CH: Hanging Protocol auch im Curved MPR (Popup in der Toolbar, beim Oeffnen angewandt). */
@interface CPRController (SekhVet)
- (void) sekhmetConfigurePresetItem:(NSToolbarItem*) toolbarItem;
- (void) sekhmetApplyHangingProtocol;
- (void) sekhmetPresetDidChange:(NSNotification*) n;
- (IBAction) sekhmetPresetChanged:(id) sender;
@end

/** SekhVet Paket CV: tools menu for a right click without drag in an MPR view (as the contextual menu of the 2D viewer). */
@interface MPRController (SekhVetToolsMenu)
- (NSMenu*) sekhmetToolsMenu;
- (IBAction) sekhmetToolFromMenu:(id) sender;
@end

/** SekhVet Paket CH: dasselbe im Orthogonal MPR. */
@interface OrthogonalMPRViewer (SekhVet)
- (void) sekhmetConfigurePresetItem:(NSToolbarItem*) toolbarItem;
- (void) sekhmetApplyHangingProtocol;
- (void) sekhmetPresetDidChange:(NSNotification*) n;
- (IBAction) sekhmetPresetChanged:(id) sender;
@end
