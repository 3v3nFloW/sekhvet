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
#import "AppController.h"
#import "DicomImage.h"
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
    [SekhmetOrientation applyToMPR: self];
    [self sekhmetRestoreViewState]; // SekhVet Paket AH: zuletzt gerade gerichtete Lage dieser Serie (gleiches Preset) wieder herstellen
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

- (void) sekhmetUpdatePresetPopup
{
    for( NSToolbarItem *item in [[[self window] toolbar] items])
        if( [[item itemIdentifier] isEqualToString: @"SekhmetVetPreset"])
            [(NSPopUpButton*) [item view] selectItemAtIndex: [SekhmetOrientation presetForStudyUID: [[self viewer] studyInstanceUID] description: [SekhmetOrientation descriptionForViewer: [self viewer]]]];
}

- (void) sekhmetPresetDidChange:(NSNotification*) n
{
    [self sekhmetUpdatePresetPopup];
}

- (IBAction) sekhmetPresetChanged:(id) sender
{
    NSString *uid = [[self viewer] studyInstanceUID];
    [SekhmetOrientation setPresetOverride: [sender indexOfSelectedItem] forStudyUID: uid];
    [SekhmetOrientation applyToAllViewersOfStudyUID: uid];   // 2D-Viewer und alle MPR-Fenster der Studie, inkl. diesem
}

- (IBAction) sekhmetToggleSync:(id) sender
{
    BOOL on = ![[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey];
    [[NSUserDefaults standardUserDefaults] setBool: on forKey: SekhmetMPRSyncKey];
    [sender setImage: [NSImage imageNamed: on ? @"SyncLock.pdf" : @"Sync.pdf"]];
    if( on) [self sekhmetScheduleSyncBroadcast];
}

- (BOOL) sekhmetHPApplied { return sekhmetHPApplied; } // SekhVet Paket O

+ (void) sekhmetSetSyncSuppressed:(BOOL) on { SekhmetMPRSyncing = on; } // SekhVet Paket AF

- (void) sekhmetSettleAfterHP // SekhVet Paket AF
{
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetBroadcastSync) object: nil];
    sekhmetSyncPending = NO;
    [sekhmetLastSyncFingerprint release]; sekhmetLastSyncFingerprint = [[self sekhmetCameraFingerprint] retain];
}

- (IBAction) sekhmetToggleZoomSync:(id) sender // SekhVet Paket P/Q: nur Horos-Zoomsync der drei Ansichten (Fenster-Massstab laeuft immer mit)
{
    [[NSUserDefaults standardUserDefaults] setBool: ([sender state] == NSControlStateValueOn) forKey: @"syncZoomLevelMPR"];
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

- (NSString*) sekhmetStateSeriesUID
{
    NSString *uid = nil;
    @try { uid = [[[self viewer] currentSeries] valueForKey: @"seriesInstanceUID"]; } @catch (NSException *e) { }
    if( uid.length == 0) { DCMPix *p = [self sekhmetFirstPix]; if( p) uid = [self sekhmetFoRForPix: p]; }
    return uid.length ? uid : nil;
}

- (NSInteger) sekhmetStatePreset
{
    return [SekhmetOrientation presetForStudyUID: [[self viewer] studyInstanceUID] description: [SekhmetOrientation descriptionForViewer: [self viewer]]];
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
    if( views.count != 3) return NO;
    float nrm[3][3];
    static const int defaultAxis[3] = { 0, 2, 1 };
    for( int i = 0; i < 3; i++)
    {
        NSDictionary *d = [views objectAtIndex: i];
        NSArray *pos = [d objectForKey: @"pos"], *focal = [d objectForKey: @"focal"], *up = [d objectForKey: @"up"];
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
    NSMutableArray *views = [NSMutableArray array];
    for( int i = 0; i < 3; i++)
    {
        MPRDCMView *v = [self sekhmetView: i];
        Camera *c = v.camera;
        if( c == nil || c.position == nil || c.focalPoint == nil || c.viewUp == nil) return;
        [views addObject: [NSDictionary dictionaryWithObjectsAndKeys:
                           sekhmetPoint( c.position), @"pos", sekhmetPoint( c.focalPoint), @"focal", sekhmetPoint( c.viewUp), @"up",
                           [NSNumber numberWithFloat: c.parallelScale], @"scale", [NSNumber numberWithFloat: c.viewAngle], @"angle",
                           [NSNumber numberWithFloat: c.rollAngle], @"roll", [NSNumber numberWithFloat: c.clippingRangeNear], @"near",
                           [NSNumber numberWithFloat: c.clippingRangeFar], @"far", [NSNumber numberWithBool: v.xFlipped], @"xf",
                           [NSNumber numberWithBool: v.yFlipped], @"yf", [NSNumber numberWithFloat: v.rotation], @"rot",
                           [NSNumber numberWithFloat: v.angleMPR], @"amp", nil]];   // SekhVet Paket AX: Fadenkreuzwinkel
    }
    if( !sekhmetViewStateUsable( views)) { NSLog( @"SekhVet MPR state NOT saved for %@ (unusable camera)", uid); return; }
    NSMutableDictionary *all = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLastStateKey]];
    [all setObject: [NSDictionary dictionaryWithObjectsAndKeys: views, @"views", [NSNumber numberWithInteger: [self sekhmetStatePreset]], @"preset",
                     [NSNumber numberWithDouble: [NSDate timeIntervalSinceReferenceDate]], @"date", nil] forKey: uid];
    if( all.count > SEKHMET_MPR_STATE_MAX) // aelteste Eintraege verwerfen
    {
        NSArray *sorted = [[all allKeys] sortedArrayUsingComparator: ^NSComparisonResult(id a, id b) {
            return [[[all objectForKey: a] objectForKey: @"date"] compare: [[all objectForKey: b] objectForKey: @"date"]]; }];
        for( NSUInteger i = 0; i + SEKHMET_MPR_STATE_MAX < sorted.count; i++) [all removeObjectForKey: [sorted objectAtIndex: i]];
    }
    [[NSUserDefaults standardUserDefaults] setObject: all forKey: SekhmetMPRLastStateKey];
    NSLog( @"SekhVet MPR state saved for %@ (preset %d)", uid, (int) [self sekhmetStatePreset]);
}

- (BOOL) sekhmetRestoreViewState
{
    if( windowWillClose) return NO;
    NSString *uid = [self sekhmetStateSeriesUID];
    if( uid == nil) return NO;
    NSDictionary *st = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetMPRLastStateKey] objectForKey: uid];
    NSArray *views = [st objectForKey: @"views"];
    if( views.count != 3) return NO;
    if( [[st objectForKey: @"preset"] integerValue] != [self sekhmetStatePreset]) return NO; // Preset gewechselt -> HP gilt
    if( !sekhmetViewStateUsable( views)) { NSLog( @"SekhVet MPR state for %@ ignored (unusable or rotated without angles)", uid); return NO; }
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
    NSLog( @"SekhVet MPR state restored for %@", uid);
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
    @try { study = [pix.imageObj valueForKeyPath: @"series.study.studyInstanceUID"]; } @catch (NSException *e) { }
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
