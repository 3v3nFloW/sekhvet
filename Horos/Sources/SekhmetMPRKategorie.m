/*=========================================================================
 MPRController (SekhVet) — Umsetzung.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in MPRController.m — zusammen rund 450 Zeilen fremder Code in
 Horos-eigenen Dateien. Als Kategorie stehen sie jetzt fuer sich; in
 MPRController.m bleiben nur die Haken, die sie rufen, und die
 Instanzvariablen (die kann eine Kategorie nicht tragen).
 ============================================================================*/

#import "SekhmetMPRKategorie.h"
#import "MPRDCMView.h"
#import "VRView.h"
#import "DCMPix.h"
#import "DCMView.h"
#import "ViewerController.h"
#import "Point3D.h"
#import "Camera.h"
#import "SekhmetOrientation.h"
#import "SekhmetSpine.h"
#import "SekhmetDisplayPanel.h"

// In MPRController.m nicht oeffentlich deklariert, aber vorhanden.
@interface MPRController (SekhVetHorosPrivat)
- (void) delayedFullLODRendering:(id) sender;
@end

NSString* const SekhmetMPRDidChangeNotification = @"SekhmetMPRDidChangeNotification";
BOOL SekhmetMPRSyncing = NO;

@implementation MPRController (SekhVet)

// ---- Sekhmet: Faltung im MPR, Gleichlauf, Kachelung ----
- (DCMPix*) sekhmetFirstPix
{
    if( pixList[ 0].count) return [pixList[ 0] objectAtIndex: 0];
    return nil;
}

- (MPRDCMView*) sekhmetView:(int) i
{
    if( i == 0) return mprView1;
    if( i == 1) return mprView2;
    return mprView3;
}

- (void) sekhmetApplyConvolutionToPix:(DCMPix*) pix
{
    if( pix == nil) return;
    NSDictionary *aConv = sekhmetConvName ? [[[NSUserDefaults standardUserDefaults] dictionaryForKey: @"Convolution"] objectForKey: sekhmetConvName] : nil;
    if( aConv == nil)
    {
        [pix setConvolutionKernel: nil :0 :0];
        return;
    }
    float vals[ 25];
    short size = [[aConv objectForKey: @"Size"] intValue];
    if( size != 3 && size != 5) return;
    NSArray *m = [aConv objectForKey: @"Matrix"];
    if( m.count < size*size) return;
    for( int i = 0; i < size*size; i++) vals[ i] = [[m objectAtIndex: i] floatValue];
    float norm = [[aConv objectForKey: @"Normalization"] floatValue];
    if( norm == 0) norm = 1;
    [pix setConvolutionKernel: vals :size :norm];
}

- (IBAction) sekhmetConvChanged:(id) sender
{
    NSString *name = [[sender selectedItem] title];
    [sekhmetConvName release];
    sekhmetConvName = ([sender indexOfSelectedItem] == 0) ? nil : [name retain];
    // updateViewMPR rendert mit der Kamera, die gerade in der gemeinsamen VRView steht: ohne restoreCamera bekaemen
    // Ansicht 2 und 3 die Kamera von Ansicht 1 (gemeldet: "neue Orientierung der Viewports" nach Filterwechsel)
    [mprView1 restoreCamera]; [mprView1 updateViewMPR];
    [mprView2 restoreCamera]; [mprView2 updateViewMPR];
    [mprView3 restoreCamera]; [mprView3 updateViewMPR];
}

- (IBAction) sekhmetSpineTool:(id) sender
{
    [[SekhmetSpine shared] toggleWithWindowController: self];
}

- (void) sekhmetApplyHangingProtocol
{
    if( windowWillClose) return;
    [SekhmetOrientation applyToMPR: self];   // SekhVet Paket CS: writes its result into the window title (review finding 3)
    if( [self sekhmetRestoreViewState]) // SekhVet Paket AH: zuletzt gerade gerichtete Lage dieser Serie (gleiches Preset) wieder herstellen
    {
        // SekhVet Paket CS: the remembered state replaces whatever applyToMPR reached, so a "not applied" note from
        // above no longer describes the window. The state was saved under this protocol with these rules.
        NSInteger preset = [SekhmetOrientation presetForMPR: self];
        [SekhmetOrientation setBadge: preset == SekhmetPresetOff ? nil : [NSString stringWithFormat: @"HP: %@", [SekhmetOrientation nameForPreset: preset]]
                     inTitleOfWindow: [self window]];
    }
    sekhmetHPApplied = YES; // SekhVet Paket O: ab jetzt darf dieses Fenster seinen Stand senden
    // Gleichlauf an: ein bereits offenes MPR derselben Studie gibt seinen Stand vor, damit nicht zwei Fenster mit verschiedener Lage starten
    if( [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey])
    {
        for( NSWindow *w in [NSApp orderedWindows])
        {
            id wc = [w windowController];
            if( wc != self && [wc isKindOfClass: [MPRController class]] && [(MPRController*) wc windowWillClose] == NO && [(MPRController*) wc sekhmetHPApplied]) // Paket O: nur ein Fenster mit HP gibt vor
            {
                DCMPix *sp = [(MPRController*) wc sekhmetFirstPix], *mp = [self sekhmetFirstPix];
                if( sp && mp && [[self sekhmetFoRForPix: sp] isEqualToString: [self sekhmetFoRForPix: mp]]) { [(MPRController*) wc sekhmetBroadcastSync]; break; }
            }
        }
    }
}

// SekhVet Paket CS (review finding 4): the protocol was applied while a view was zoomed by double-click, so the two
// collapsed views could not be set. MPRDCMView calls this when the three views are back (second pass after un-zoom).
- (void) sekhmetApplyPendingHangingProtocol
{
    if( windowWillClose || self.sekhmetHPPending == NO || self.sekhmetFrameZoomed) return;
    self.sekhmetHPPending = NO;
    BOOL was = SekhmetMPRSyncing;
    SekhmetMPRSyncing = YES;   // like a protocol change: no sync message while the planes are laid out
    @try { [SekhmetOrientation applyToMPR: self straighten: YES]; }
    @catch (NSException *e) { NSLog( @"SekhVet Hanging Protocol MPR after un-zoom: %@", e); }
    @finally { SekhmetMPRSyncing = was; }
    [self sekhmetSettleAfterHP];
}

// SekhVet Paket CS (dead code): this was a copy of +updatePresetToolbarItemInWindow:viewer:.
- (void) sekhmetPresetDidChange:(NSNotification*) n
{
    [SekhmetOrientation updatePresetToolbarItemInWindow: [self window] viewer: [self viewer]];
}

- (IBAction) sekhmetPresetChanged:(id) sender
{
    [SekhmetOrientation presetPopupChanged: sender viewer: [self viewer]];   // 2D-Viewer und alle MPR-Fenster der Studie, inkl. diesem
}

// SekhVet Paket CS (review finding 18): the switch is global, so every open MPR window and the Display panel follow -
// the notification is posted here and by the panel's checkbox; before, only the clicked toolbar item changed.
- (IBAction) sekhmetToggleSync:(id) sender
{
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey];
    [[NSUserDefaults standardUserDefaults] setBool: on forKey: SekhmetMPRSyncKey];
    [[NSNotificationCenter defaultCenter] postNotificationName: SekhmetMPRSyncSettingDidChangeNotification object: self];
    if( on) [self sekhmetScheduleSyncBroadcast];
}

- (void) sekhmetSyncSettingDidChange:(NSNotification*) n
{
    BOOL on = [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey];
    for( NSToolbarItem *item in [[[self window] toolbar] items])
        if( [[item itemIdentifier] isEqualToString: @"SekhmetMPRSync"])
            [item setImage: [NSImage imageNamed: on ? @"SyncLock.pdf" : @"Sync.pdf"]];
}

- (BOOL) sekhmetHPApplied { return sekhmetHPApplied; } // SekhVet Paket O

+ (void) sekhmetSetSyncSuppressed:(BOOL) on { SekhmetMPRSyncing = on; } // SekhVet Paket AF

- (void) sekhmetSettleAfterHP // SekhVet Paket AF
{
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetBroadcastSync) object: nil];
    sekhmetSyncPending = NO;
    [sekhmetLastSyncFingerprint release]; sekhmetLastSyncFingerprint = [[self sekhmetCameraFingerprint] retain];
}

- (void) sekhmetScheduleSyncBroadcast
{
    if( SekhmetMPRSyncing || windowWillClose) return;
    if( sekhmetHPApplied == NO) return; // SekhVet Paket O: Ladephase eines neuen Fensters nicht an die anderen senden
    if( [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey] == NO) return;
    if( sekhmetSyncPending) return;   // Drossel: waehrend des Ziehens alle 30 ms senden, nicht erst nach dem Loslassen
    sekhmetSyncPending = YES;
    [self performSelector: @selector(sekhmetBroadcastSync) withObject: nil afterDelay: 0.03 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]]; // feuert auch im Event-Tracking
}

- (void) sekhmetBroadcastSync
{
    sekhmetSyncPending = NO;
    if( windowWillClose) return;
    if( sekhmetLastSyncFingerprint && [[self sekhmetCameraFingerprint] isEqualToString: sekhmetLastSyncFingerprint]) return; // SekhVet Paket R: unveraendert seit dem Empfang = Echo, nicht senden
    [[NSNotificationCenter defaultCenter] postNotificationName: SekhmetMPRDidChangeNotification object: self];
}

#pragma mark - SekhVet Paket AH: MPR-Lage je Serie merken

static NSString* const SekhmetMPRLastStateKey = @"SekhmetMPRLastState"; // seriesUID -> {preset, date, views: [ {pos, focal, up, scale, angle, roll, near, far, xf, yf, rot} x3 ]}
#define SEKHMET_MPR_STATE_MAX 200

// SekhVet Paket CS (review, unconfirmed "state saved under the wrong series"): the series of the volume THIS window
// shows, read from its own first image. The 2D viewer's current series was asked before; when the viewer had already
// switched to another series while this window closed, the state landed under the new series. The viewer is only
// the fallback now.
- (NSString*) sekhmetStateSeriesUID
{
    NSString *uid = nil;
    DCMPix *p = [self sekhmetFirstPix];
    @try { uid = [(id) [p seriesObj] valueForKey: @"seriesInstanceUID"]; } @catch (NSException *e) { uid = nil; }
    if( uid.length == 0)
    {
        @try { uid = [[[self viewer] currentSeries] valueForKey: @"seriesInstanceUID"]; } @catch (NSException *e) { uid = nil; }
    }
    if( uid.length == 0 && p) uid = [self sekhmetFoRForPix: p];
    return uid.length ? uid : nil;
}

static NSArray* sekhmetPoint( Point3D *p) { return [NSArray arrayWithObjects: [NSNumber numberWithFloat: p.x], [NSNumber numberWithFloat: p.y], [NSNumber numberWithFloat: p.z], nil]; }
static Point3D* sekhmetPointFrom( NSArray *a) { return [Point3D pointWithX: [[a objectAtIndex: 0] floatValue] y: [[a objectAtIndex: 1] floatValue] z: [[a objectAtIndex: 2] floatValue]]; }

// SekhVet Paket AX: ein gespeicherter Stand taugt nur, wenn jede Kamera endlich ist, eine Blickrichtung und einen
// Aufwaertsvektor quer dazu hat und die drei Ebenen verschieden sind. Ein einziger kaputter Stand (NaN nach einem
// Renderziel ohne Flaeche) wurde sonst bei jedem Oeffnen der Serie wieder eingespielt (gemessen 16.09.2026).
// Alte Eintraege ohne Fadenkreuzwinkel ("amp") nur in Horos' Grundbelegung (Normalen x/z/y): mit gedrehtem
// Fadenkreuz passen sie nicht zu Horos' Kopplung, und beim ersten Scrollen springen zwei Ebenen.
static BOOL sekhmetViewStateUsable( NSArray *views)
{
    if( ![views isKindOfClass: [NSArray class]] || views.count != 3) return NO;   // SekhVet Paket CS: type checks against damaged defaults
    float nrm[3][3];
    static const int defaultAxis[3] = { 0, 2, 1 };
    for( int i = 0; i < 3; i++)
    {
        NSDictionary *d = [views objectAtIndex: i];
        if( ![d isKindOfClass: [NSDictionary class]]) return NO;
        NSArray *pos = [d objectForKey: @"pos"], *focal = [d objectForKey: @"focal"], *up = [d objectForKey: @"up"];
        if( ![pos isKindOfClass: [NSArray class]] || ![focal isKindOfClass: [NSArray class]] || ![up isKindOfClass: [NSArray class]]) return NO;
        if( pos.count != 3 || focal.count != 3 || up.count != 3) return NO;
        float n[3], u[3];
        for( int k = 0; k < 3; k++)
        {
            n[k] = [[pos objectAtIndex: k] floatValue] - [[focal objectAtIndex: k] floatValue];
            u[k] = [[up objectAtIndex: k] floatValue];
            if( !isfinite( n[k]) || !isfinite( u[k])) return NO;
        }
        float ln = sqrtf( n[0]*n[0] + n[1]*n[1] + n[2]*n[2]), lu = sqrtf( u[0]*u[0] + u[1]*u[1] + u[2]*u[2]);
        if( !(ln > 0) || !(lu > 0)) return NO;
        if( fabsf( n[0]*u[0] + n[1]*u[1] + n[2]*u[2]) / (ln * lu) > 0.9f) return NO;
        for( int k = 0; k < 3; k++) nrm[i][k] = n[k] / ln;
        if( [d objectForKey: @"amp"] == nil && fabsf( nrm[i][ defaultAxis[i]]) < 0.9f) return NO;
    }
    for( int a = 0; a < 3; a++)
        for( int b = a + 1; b < 3; b++)
            if( fabsf( nrm[a][0]*nrm[b][0] + nrm[a][1]*nrm[b][1] + nrm[a][2]*nrm[b][2]) > 0.9f) return NO;
    return YES;
}

- (void) sekhmetSaveViewState
{
    if( windowWillClose || sekhmetHPApplied == NO) return; // ohne HP ist die Lage noch nicht die des Betrachters
    NSString *uid = [self sekhmetStateSeriesUID];
    if( uid == nil) return;
    NSArray *views = [self sekhmetCurrentViews];   // SekhVet Paket DA: shared with the overlay's MPR rebuild
    if( views == nil) return;
    // SekhVet Paket CS (review finding 21): no series UID in the release log.
    if( !sekhmetViewStateUsable( views)) { NSLog( @"SekhVet MPR state NOT saved (unusable camera)"); return; }
    NSInteger preset = [SekhmetOrientation presetForMPR: self];
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLastStateKey]];
    // SekhVet Paket CS (review finding 5): "rules" = rules and MPR layout of the protocol at the time of saving.
    [all setObject: [NSDictionary dictionaryWithObjectsAndKeys: views, @"views", [NSNumber numberWithInteger: preset], @"preset",
                     [SekhmetOrientation stateSignatureForPreset: preset], @"rules",
                     [NSNumber numberWithDouble: [NSDate timeIntervalSinceReferenceDate]], @"date", nil] forKey: uid];
    if( all.count > SEKHMET_MPR_STATE_MAX) // aelteste Eintraege verwerfen
    {
        NSArray *sorted = [[all allKeys] sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
            return [[[all objectForKey: a] objectForKey: @"date"] compare: [[all objectForKey: b] objectForKey: @"date"]]; }];
        for( NSUInteger i = 0; i + SEKHMET_MPR_STATE_MAX < sorted.count; i++) [all removeObjectForKey: [sorted objectAtIndex: i]];
    }
    [[NSUserDefaults standardUserDefaults] setObject: all forKey: SekhmetMPRLastStateKey];
    NSLog( @"SekhVet MPR state saved (preset %d)", (int) preset);
}

- (BOOL) sekhmetRestoreViewState
{
    if( windowWillClose) return NO;
    NSString *uid = [self sekhmetStateSeriesUID];
    if( uid == nil) return NO;
    NSDictionary *st = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLastStateKey] objectForKey: uid];
    if( ![st isKindOfClass: [NSDictionary class]]) return NO;
    NSArray *views = [st objectForKey: @"views"];
    if( ![views isKindOfClass: [NSArray class]] || views.count != 3) return NO;
    NSInteger preset = [SekhmetOrientation presetForMPR: self];
    if( [[st objectForKey: @"preset"] integerValue] != preset) return NO; // Preset gewechselt -> HP gilt
    // SekhVet Paket CS (review finding 5): the state belongs to the rules and the MPR layout it was saved under. After
    // an edit of the rules or "Take from screen" the old camera and flips must not come back - the protocol applies.
    // States saved before this package carry no signature and are dropped once for the same reason.
    NSString *signature = [st objectForKey: @"rules"];
    if( ![signature isKindOfClass: [NSString class]] || ![signature isEqualToString: [SekhmetOrientation stateSignatureForPreset: preset]])
    {
        NSLog( @"SekhVet MPR state ignored (rules or layout of the protocol changed since it was saved)");
        return NO;
    }
    if( !sekhmetViewStateUsable( views)) { NSLog( @"SekhVet MPR state ignored (unusable or rotated without angles)"); return NO; }
    [self sekhmetApplyViews: views];   // SekhVet Paket DA
    NSLog( @"SekhVet MPR state restored");
    return YES;
}

// SekhVet Paket DA: the camera part of sekhmetSaveViewState / sekhmetRestoreViewState, also used when the overlay
// closes and reopens an MPR to stack more series (same position afterwards).
- (NSArray*) sekhmetCurrentViews
{
    NSMutableArray *views = [NSMutableArray array];
    for( int i = 0; i < 3; i++)
    {
        MPRDCMView *v = [self sekhmetView: i];
        Camera *c = v.camera;
        if( c == nil || c.position == nil || c.focalPoint == nil || c.viewUp == nil) return nil;
        [views addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                           sekhmetPoint( c.position), @"pos", sekhmetPoint( c.focalPoint), @"focal", sekhmetPoint( c.viewUp), @"up",
                           [NSNumber numberWithFloat: c.parallelScale], @"scale", [NSNumber numberWithFloat: c.viewAngle], @"angle",
                           [NSNumber numberWithFloat: c.rollAngle], @"roll", [NSNumber numberWithFloat: c.clippingRangeNear], @"near",
                           [NSNumber numberWithFloat: c.clippingRangeFar], @"far", [NSNumber numberWithBool: v.xFlipped], @"xf",
                           [NSNumber numberWithBool: v.yFlipped], @"yf", [NSNumber numberWithFloat: v.rotation], @"rot",
                           [NSNumber numberWithFloat: v.angleMPR], @"amp", nil]];   // SekhVet Paket AX: Fadenkreuzwinkel
    }
    return views;
}

- (BOOL) sekhmetApplyViews:(NSArray*) views
{
    if( windowWillClose || !sekhmetViewStateUsable( views)) return NO;
    for( int i = 0; i < 3; i++)   // SekhVet Paket AX: Fadenkreuzwinkel zuerst, die Kopplung beim Update rechnet damit
        [self sekhmetView: i].angleMPR = [[[views objectAtIndex: i] objectForKey: @"amp"] floatValue];
    SekhmetMPRSyncing = YES;
    @try
    {
        for( int i = 0; i < 3; i++)
        {
            NSDictionary *d = [views objectAtIndex: i];
            MPRDCMView *v = [self sekhmetView: i];
            Camera *c = v.camera;
            if( c == nil) continue;
            float wl = c.wl, ww = c.ww;
            c.position = sekhmetPointFrom( [d objectForKey: @"pos"]);
            c.focalPoint = sekhmetPointFrom( [d objectForKey: @"focal"]);
            c.viewUp = sekhmetPointFrom( [d objectForKey: @"up"]);
            c.parallelScale = [[d objectForKey: @"scale"] floatValue];
            c.viewAngle = [[d objectForKey: @"angle"] floatValue];
            c.rollAngle = [[d objectForKey: @"roll"] floatValue];
            c.clippingRangeNear = [[d objectForKey: @"near"] floatValue];
            c.clippingRangeFar = [[d objectForKey: @"far"] floatValue];
            [c setWLWW: wl :ww];
            c.forceUpdate = YES;
            if( v.xFlipped != [[d objectForKey: @"xf"] boolValue]) v.xFlipped = [[d objectForKey: @"xf"] boolValue];
            if( v.yFlipped != [[d objectForKey: @"yf"] boolValue]) v.yFlipped = [[d objectForKey: @"yf"] boolValue];
            if( v.rotation != [[d objectForKey: @"rot"] floatValue]) v.rotation = [[d objectForKey: @"rot"] floatValue];
            [v restoreCamera];
            [v updateViewMPR];
        }
    }
    @catch (NSException *e) { NSLog( @"SekhVet MPR state restore: %@", e); }
    SekhmetMPRSyncing = NO;
    [self sekhmetSettleAfterHP];
    return YES;
}

- (IBAction) sekhmetResetView:(id) sender
{
    NSString *uid = [self sekhmetStateSeriesUID];
    if( uid)
    {
        NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLastStateKey]];
        [all removeObjectForKey: uid];
        [[NSUserDefaults standardUserDefaults] setObject: all forKey: SekhmetMPRLastStateKey];
    }
    [self showWindow: sender];
}

- (NSString*) sekhmetCameraFingerprint // SekhVet Paket R: Kamerastand der drei Ansichten, gerundet (Echo-Erkennung)
{
    NSMutableString *s = [NSMutableString string];
    for( int i = 0; i < 3; i++)
    {
        Camera *c = [self sekhmetView: i].camera;
        if( c == nil) { [s appendString: @"-|"]; continue; }
        [s appendFormat: @"%.2f %.2f %.2f %.2f %.2f %.2f %.3f %.3f %.3f %.3f|", c.position.x, c.position.y, c.position.z,
         c.focalPoint.x, c.focalPoint.y, c.focalPoint.z, c.viewUp.x, c.viewUp.y, c.viewUp.z, c.parallelScale];
    }
    return s;
}

- (void) sekhmetDelayedFullLODRendering // SekhVet Paket R: scharf nachrendern als Folge eines Empfangs -> nichts zuruecksenden
{
    if( windowWillClose) return;
    BOOL was = SekhmetMPRSyncing;
    SekhmetMPRSyncing = YES;
    @try { [self delayedFullLODRendering: nil]; }
    @catch (NSException *e) { NSLog( @"SekhVet MPR sync LOD: %@", e); }
    SekhmetMPRSyncing = was;
}

- (NSString*) sekhmetFoRForPix:(DCMPix*) pix
{
    // DICOM Frame of Reference = gleicher Patientenraum. Ohne FoR-UID Rueckfall: gleiche Studie + gleiche Bildorientierung
    if( pix.frameofReferenceUID.length) return [@"FoR:" stringByAppendingString: pix.frameofReferenceUID];
    NSString *study = nil;
    @try { study = [pix.imageObj valueForKeyPath: @"series.study.studyInstanceUID"]; } @catch (NSException *e) { study = nil; }
    // SekhVet Paket CS (review finding 14): without a study UID the key was "(null)|orientation" - the same for every
    // such series, so MPR windows of different patients could sync. No frame of reference known = nil; every caller
    // compares with isEqualToString:, which is NO for nil on either side, so such a window never syncs.
    if( study.length == 0) return nil;
    float o[ 9]; [pix orientation: o];
    return [NSString stringWithFormat: @"%@|%.2f %.2f %.2f %.2f %.2f %.2f", study, o[0], o[1], o[2], o[3], o[4], o[5]];
}

- (void) sekhmetSyncFromNotification:(NSNotification*) n
{
    MPRController *src = [n object];
    if( src == self || src == nil || windowWillClose || SekhmetMPRSyncing) return;
    if( [src sekhmetHPApplied] == NO) return; // SekhVet Paket O: Stand eines Fensters ohne HP nie uebernehmen
    if( [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey] == NO) return;

    DCMPix *sp = [src sekhmetFirstPix], *mp = [self sekhmetFirstPix];
    if( sp == nil || mp == nil) return;
    if( [[self sekhmetFoRForPix: sp] isEqualToString: [self sekhmetFoRForPix: mp]] == NO) return;

    SekhmetMPRSyncing = YES;
    BOOL srcLow = src.lowLOD; // Paket Q: waehrend des Ziehens im Absender auch hier grob rendern, sonst ruckelt der Mitlauf
    if( srcLow) lowLOD = YES;
    @try
    {
        // VRView legt das Volumen im Patientenraum ab (setPixSource: SetUserMatrix mit den Richtungskosinus,
        // SetPosition mit dem Ursprung), skaliert mit factor = superSampling / pixelSpacingX. Die Kameras zweier
        // Serien desselben FoR sind also direkt vergleichbar; nur der Massstab ist umzurechnen, wenn die
        // Pixelgroesse der Serien verschieden ist. Ein Ursprungs-Delta waere doppelt gerechnet.
        float fs = [[[src sekhmetView: 0] vrView] factor], fd = [[mprView1 vrView] factor];
        float ratio = (fs > 0 && fd > 0) ? fd / fs : 1;

        // SekhVet Paket AX: Fadenkreuzwinkel mit uebernehmen, und zwar vor dem ersten Update — Horos' Kopplung
        // leitet daraus die anderen Ebenen ab, sobald hier jemand scrollt. Ohne sie sprangen zwei Ebenen.
        for( int i = 0; i < 3; i++) [self sekhmetView: i].angleMPR = [src sekhmetView: i].angleMPR;

        for( int i = 0; i < 3; i++)
        {
            MPRDCMView *sv = [src sekhmetView: i], *dv = [self sekhmetView: i];
            Camera *sc = sv.camera, *dc = dv.camera;
            if( sc == nil || dc == nil) continue;

            float wl = dc.wl, ww = dc.ww;
            dc.position = [Point3D pointWithX: sc.position.x * ratio y: sc.position.y * ratio z: sc.position.z * ratio];
            dc.focalPoint = [Point3D pointWithX: sc.focalPoint.x * ratio y: sc.focalPoint.y * ratio z: sc.focalPoint.z * ratio];
            dc.viewUp = sc.viewUp;
            dc.parallelScale = sc.parallelScale * ratio; // Paket Q: Massstab je Ansicht immer mit (sagittal <-> sagittal)
            dc.viewAngle = sc.viewAngle;
            dc.rollAngle = sc.rollAngle;
            dc.clippingRangeNear = sc.clippingRangeNear * ratio;
            dc.clippingRangeFar = sc.clippingRangeFar * ratio;
            [dc setWLWW: wl :ww];
            dc.forceUpdate = YES;
            if( dv.xFlipped != sv.xFlipped) dv.xFlipped = sv.xFlipped;   // gleiche Kamera + gleiche Anzeige-Flips = gleiches Bild
            if( dv.yFlipped != sv.yFlipped) dv.yFlipped = sv.yFlipped;
            if( dv.rotation != sv.rotation) dv.rotation = sv.rotation;
            [dv restoreCamera];
            [dv updateViewMPR];
        }
    }
    @catch (NSException *e) { NSLog( @"SekhVet MPR sync: %@", e); }
    SekhmetMPRSyncing = NO;
    [sekhmetLastSyncFingerprint release]; sekhmetLastSyncFingerprint = [[self sekhmetCameraFingerprint] retain]; // Paket R
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetBroadcastSync) object: nil]; sekhmetSyncPending = NO; // Paket R: kein Echo aus der Warteschlange
    if( srcLow) // Paket Q: scharf nachziehen wie der Absender; Paket R: ohne Rueckmeldung (Horos laesst lowLOD nach dem Rendern auf YES -> sonst Ping-Pong alle 0,4 s)
    {
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetDelayedFullLODRendering) object: nil];
        [self performSelector: @selector(sekhmetDelayedFullLODRendering) withObject: nil afterDelay: 0.4];
    }
}

@end

#pragma mark - SekhVet Paket CH: Curved MPR und Orthogonal MPR

@implementation CPRController (SekhVet)

- (void) sekhmetConfigurePresetItem:(NSToolbarItem*) toolbarItem
{
    [SekhmetOrientation configurePresetToolbarItem: toolbarItem viewer: [self viewer] target: self];
}

- (void) sekhmetApplyHangingProtocol
{
    if( [self windowWillClose]) return;   // SekhVet Paket CS (fork review 15): scheduled 0.5 s after showWindow:, the window may be gone
    [SekhmetOrientation applyToCPR: self];
}

- (void) sekhmetPresetDidChange:(NSNotification*) n
{
    [SekhmetOrientation updatePresetToolbarItemInWindow: [self window] viewer: [self viewer]];
}

- (IBAction) sekhmetPresetChanged:(id) sender
{
    [SekhmetOrientation presetPopupChanged: sender viewer: [self viewer]];
}

@end

@implementation OrthogonalMPRViewer (SekhVet)

- (void) sekhmetConfigurePresetItem:(NSToolbarItem*) toolbarItem
{
    [SekhmetOrientation configurePresetToolbarItem: toolbarItem viewer: [self viewer] target: self];
}

- (void) sekhmetApplyHangingProtocol
{
    if( [self windowWillClose] || [self window] == nil) return;   // SekhVet Paket CS (fork review 15): scheduled 0.5 s after showWindow:; windowWillClose: also cancels it
    [SekhmetOrientation applyToOrthogonalMPR: self];
}

- (void) sekhmetPresetDidChange:(NSNotification*) n
{
    [SekhmetOrientation updatePresetToolbarItemInWindow: [self window] viewer: [self viewer]];
}

- (IBAction) sekhmetPresetChanged:(id) sender
{
    [SekhmetOrientation presetPopupChanged: sender viewer: [self viewer]];
}

@end

// SekhVet Paket CV: the MPR views hand the right mouse button to the VR view (zoom while dragging); a right click WITHOUT
// drag did nothing. It now opens a menu at the pointer with the tools of the MPR tool palette and the ROI tools; the
// choice becomes the tool of the left mouse button, exactly as a click into the palette (setTool:).
@implementation MPRController (SekhVetToolsMenu)

static NSString* sekhmetToolTitle( long tag)
{
    switch( tag)
    {
        case tWL:        return NSLocalizedString( @"Contrast", nil);
        case tTranslate: return NSLocalizedString( @"Move", nil);
        case tZoom:      return NSLocalizedString( @"Magnify", nil);
        case tRotate:    return NSLocalizedString( @"Rotate", nil);
        case tNext:      return NSLocalizedString( @"Scroll", nil);
        default:         return nil;
    }
}

- (NSMenu*) sekhmetToolsMenu
{
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: NSLocalizedString( @"Tools", nil)] autorelease];
    long current = [[toolsMatrix selectedCell] tag];
    NSButtonCell *roiCell = ([toolsMatrix numberOfColumns] > 6) ? [toolsMatrix cellAtRow: 0 column: 6] : nil;

    for( NSButtonCell *cell in [toolsMatrix cells])
    {
        if( cell == roiCell || [cell isEnabled] == NO) continue;
        NSString *title = sekhmetToolTitle( [cell tag]);
        if( title == nil) continue;
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: title action: @selector(sekhmetToolFromMenu:) keyEquivalent: @""] autorelease];
        [item setTarget: self];
        [item setTag: [cell tag]];
        NSImage *im = [[[cell image] copy] autorelease];
        if( im) { [im setSize: NSMakeSize( 16, 16)]; [item setImage: im]; }
        if( [cell tag] == current && [toolsMatrix selectedCell] != roiCell) [item setState: NSControlStateValueOn];
        [menu addItem: item];
    }

    NSMenu *sub = [[[NSMenu alloc] initWithTitle: NSLocalizedString( @"ROI", nil)] autorelease];
    for( NSMenuItem *pi in [popupRoi itemArray])
    {
        if( [pi isSeparatorItem]) { if( [sub numberOfItems]) [sub addItem: [NSMenuItem separatorItem]]; continue; }
        if( [pi tag] <= 0 || [self imageForROI: (ToolMode) [pi tag]] == nil) continue;   // first item = the popup itself
        NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: [pi title] action: @selector(sekhmetToolFromMenu:) keyEquivalent: @""] autorelease];
        [item setTarget: self];
        [item setTag: [pi tag]];
        NSImage *im = [[[self imageForROI: (ToolMode) [pi tag]] copy] autorelease];
        if( im) { [im setSize: NSMakeSize( 16, 16)]; [item setImage: im]; }
        if( [toolsMatrix selectedCell] == roiCell && [pi tag] == current) [item setState: NSControlStateValueOn];
        [sub addItem: item];
    }
    if( [sub numberOfItems])
    {
        if( [menu numberOfItems]) [menu addItem: [NSMenuItem separatorItem]];
        NSMenuItem *roiItem = [[[NSMenuItem alloc] initWithTitle: NSLocalizedString( @"ROI", nil) action: nil keyEquivalent: @""] autorelease];
        [roiItem setSubmenu: sub];
        [menu addItem: roiItem];
    }
    return [menu numberOfItems] ? menu : nil;
}

- (IBAction) sekhmetToolFromMenu:(id) sender
{
    long tag = [sender tag];
    [toolsMatrix selectCellWithTag: tag];   // the palette follows; an ROI tool is put into the ROI cell by setROIToolTag:
    [self setTool: sender];                 // setToolIndex: + setROIToolTag: with the sender's tag
}

@end
