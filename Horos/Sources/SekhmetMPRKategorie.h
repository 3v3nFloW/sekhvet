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
- (void) sekhmetUpdatePresetPopup;
- (void) sekhmetPresetDidChange:(NSNotification*) n;
- (IBAction) sekhmetPresetChanged:(id) sender;
- (IBAction) sekhmetToggleSync:(id) sender;
- (BOOL) sekhmetHPApplied;
+ (void) sekhmetSetSyncSuppressed:(BOOL) on;
- (void) sekhmetSettleAfterHP;  // SekhVet Paket AF
- (IBAction) sekhmetToggleZoomSync:(id) sender;  // SekhVet Paket P/Q: nur Horos-Zoomsync der drei Ansichten (Fenster-Massstab laeuft immer mit)
- (void) sekhmetScheduleSyncBroadcast;
- (void) sekhmetBroadcastSync;
- (NSString*) sekhmetStateSeriesUID;
- (NSInteger) sekhmetStatePreset;
- (void) sekhmetSaveViewState;
- (BOOL) sekhmetRestoreViewState;
- (IBAction) sekhmetResetView:(id) sender;
- (NSString*) sekhmetCameraFingerprint;  // SekhVet Paket R: Kamerastand der drei Ansichten, gerundet (Echo-Erkennung)
- (void) sekhmetDelayedFullLODRendering;  // SekhVet Paket R: scharf nachrendern als Folge eines Empfangs -> nichts zuruecksenden
- (NSString*) sekhmetFoRForPix:(DCMPix*) pix;
- (void) sekhmetSyncFromNotification:(NSNotification*) n;
@end
