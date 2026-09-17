/*=========================================================================
 SekhVet — Norberg Angle and Distraction Index. See header.
 ============================================================================*/

#import "SekhmetNorberg.h"
#import "ROI.h"
#import "DCMView.h"
#import "DCMPix.h"
#import "ViewerController.h"
#import "Notifications.h"
#import "StringTexture.h"
#import <math.h>

static SekhmetNorberg *sekhmetNorberg = nil;
static BOOL sekhmetNorbergUpdating = NO;      // setName: posts OsirixROIChangeNotification -> no recursion

static NSString* const kHeadName[ 2]    = { @"HD head R", @"HD head L" };
static NSString* const kNorbergName[ 2] = { @"Norberg R", @"Norberg L" };   // prefix; full name "Norberg R: 104.3°"
static NSString* const kRadiusName[ 2]  = { @"HD radius R", @"HD radius L" }; // Paket W: grip point on the rim, drag = resize
static NSString* const kCupName[ 2]     = { @"HD cup R", @"HD cup L" };     // Paket BE: acetabular cup circle; full name "HD cup R: 0.65" (value = DI)
static NSString* const kCupGripName[ 2] = { @"HD cup radius R", @"HD cup radius L" }; // grip on the inner side of the cup circle
static const RGBColor kRadiusColor      = { 0xFFFF, 0xDCDC, 0x0000 };         // #FFDC00 (ScrutPilot radius handle)
static const RGBColor kCupColor         = { 0xFFFF, 0xD7D7, 0x0000 };         // #FFD700: acetabular cup (yellow, as in the PennHIP illustration)
static const float kMinRadiusPx = 2;
static const RGBColor kSideColor[ 2]    = { { 0x0000, 0xBFBF, 0xFFFF },      // R: #00BFFF (ScrutPilot)
                                            { 0xFFFF, 0x6363, 0x4747 } };    // L: #FF6347
static NSString* const kDIRiskKey = @"SekhmetDIRisk";                         // Paket BE: show the risk level in the DI label (option)

// Parts of the measurement (Paket BD): the femoral head circles (+ grips) are shared by both measurements.
// kPartCups covers the cup circles + their grips and the "HD ace" points of Build 90.
enum { kPartHeads = 1, kPartRims = 2, kPartCups = 4, kPartAll = 7 };

@implementation SekhmetNorberg

+ (SekhmetNorberg*) shared
{
    if( sekhmetNorberg == nil) sekhmetNorberg = [[SekhmetNorberg alloc] init];
    return sekhmetNorberg;
}

- (id) init
{
    self = [super init];
    if( self)
    {
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(drawObjects:) name: OsirixDrawObjectsNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(roiChanged:) name: OsirixROIChangeNotification object: nil];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [super dealloc];
}

#pragma mark - Geometry

+ (double) angleAtCenter:(NSPoint) c rim:(NSPoint) rim other:(NSPoint) other spacingX:(double) sx spacingY:(double) sy
{
    if( sx <= 0 || sy <= 0) { sx = 1; sy = 1; }
    double rx = (other.x - c.x) * sx, ry = (other.y - c.y) * sy;
    double ax = (rim.x - c.x) * sx,   ay = (rim.y - c.y) * sy;
    double lr = hypot( rx, ry), la = hypot( ax, ay);
    if( lr == 0 || la == 0) return 0;
    double cosv = (rx*ax + ry*ay) / (lr*la);
    if( cosv > 1) cosv = 1; if( cosv < -1) cosv = -1;
    return round( acos( cosv) * 180.0 / M_PI * 10.0) / 10.0;
}

+ (double) distractionIndexAtCenter:(NSPoint) c radius:(double) r cup:(NSPoint) cup spacingX:(double) sx spacingY:(double) sy
{
    if( sx <= 0 || sy <= 0) { sx = 1; sy = 1; }
    double rmm = fabs( r) * sx;                        // Horos oval: size.width = radius in pixels along x
    if( rmm <= 0) return 0;
    double d = hypot( (cup.x - c.x) * sx, (cup.y - c.y) * sy);
    return round( d / rmm * 1000.0) / 1000.0;
}

+ (NSString*) riskTextForDI:(double) di
{
    return di < 0.3 ? @"low" : di < 0.7 ? @"moderate" : @"high";
}

+ (BOOL) showsRisk
{
    return [[NSUserDefaults standardUserDefaults] boolForKey: kDIRiskKey];
}

+ (void) setShowsRisk:(BOOL) on
{
    [[NSUserDefaults standardUserDefaults] setBool: on forKey: kDIRiskKey];
    for( ViewerController *vc in [ViewerController getDisplayed2DViewers])
        [[vc imageView] setNeedsDisplay: YES];
}

+ (NSString*) debugSelfTest
{
    // Same construction as the ScrutPilot test: centres 200 px apart, rim 80 px from the centre at 105 degrees.
    NSPoint cR = NSMakePoint( 100, 300), cL = NSMakePoint( 300, 300);
    double a = 105.0 * M_PI / 180.0;
    NSPoint rimR = NSMakePoint( cR.x + 80*cos( a), cR.y - 80*sin( a));            // y grows downwards in image space
    NSPoint rimL = NSMakePoint( cL.x - 80*cos( a), cL.y - 80*sin( a));
    double wR = [self angleAtCenter: cR rim: rimR other: cL spacingX: 1 spacingY: 1];
    double wL = [self angleAtCenter: cL rim: rimL other: cR spacingX: 1 spacingY: 1];
    // Non-square pixels: rim straight above the centre stays 90 degrees whatever the spacing.
    double wAniso = [self angleAtCenter: cR rim: NSMakePoint( cR.x, cR.y - 40) other: cL spacingX: 1 spacingY: 2];
    // Caudal rim gives the same inner angle (documented limitation, as in ScrutPilot).
    double wCaudal = [self angleAtCenter: cR rim: NSMakePoint( cR.x + 80*cos( a), cR.y + 80*sin( a)) other: cL spacingX: 1 spacingY: 1];
    // Paket BD: distraction index d/r — 40 px medial of an 80 px head = 0.5; with 1x2 mm pixels a point 20 px above = 40 mm / 80 mm = 0.5;
    // 3-4-5 triangle: (24, 32) px -> 40 / 80 = 0.5; radius 0 -> 0.
    double diR = [self distractionIndexAtCenter: cR radius: 80 cup: NSMakePoint( cR.x + 40, cR.y) spacingX: 1 spacingY: 1];
    double diAniso = [self distractionIndexAtCenter: cR radius: 80 cup: NSMakePoint( cR.x, cR.y - 20) spacingX: 1 spacingY: 2];
    double diDiag = [self distractionIndexAtCenter: cR radius: 80 cup: NSMakePoint( cR.x + 24, cR.y + 32) spacingX: 1 spacingY: 1];
    double diZero = [self distractionIndexAtCenter: cR radius: 0 cup: NSMakePoint( cR.x + 24, cR.y + 32) spacingX: 1 spacingY: 1];
    BOOL ok = fabs( wR - 105.0) < 0.05 && fabs( wL - 105.0) < 0.05 && fabs( wAniso - 90.0) < 0.05 && fabs( wCaudal - 105.0) < 0.05
           && fabs( diR - 0.5) < 0.0005 && fabs( diAniso - 0.5) < 0.0005 && fabs( diDiag - 0.5) < 0.0005 && diZero == 0
           && [[self riskTextForDI: 0.29] isEqualToString: @"low"] && [[self riskTextForDI: 0.3] isEqualToString: @"moderate"]
           && [[self riskTextForDI: 0.69] isEqualToString: @"moderate"] && [[self riskTextForDI: 0.7] isEqualToString: @"high"];
    return [NSString stringWithFormat: @"R=%.1f L=%.1f aniso=%.1f caudal=%.1f DI=%.3f DIaniso=%.3f DIdiag=%.3f DIzero=%.3f risk(0.29/0.3/0.69/0.7)=%@/%@/%@/%@ -> %@", wR, wL, wAniso, wCaudal, diR, diAniso, diDiag, diZero, [self riskTextForDI: 0.29], [self riskTextForDI: 0.3], [self riskTextForDI: 0.69], [self riskTextForDI: 0.7], ok ? @"OK" : @"FAIL"];
}

#pragma mark - ROI lookup

static ROI* sekhmetFindROI( NSArray *list, NSString *name, BOOL prefix)
{
    for( ROI *r in list)
    {
        if( prefix ? [r.name hasPrefix: name] : [r.name isEqualToString: name])
            return r;
    }
    return nil;
}

// heads[0]=R, heads[1]=L, rims, grips, cups and cup grips likewise (grips may be nil for measurements from Build 55-57,
// rims/cups nil when only the other measurement exists); YES if both heads exist
static BOOL sekhmetFindGroup( NSArray *list, ROI *heads[ 2], ROI *rims[ 2], ROI *grips[ 2], ROI *cups[ 2], ROI *cupGrips[ 2])
{
    for( int s = 0; s < 2; s++)
    {
        heads[ s]    = sekhmetFindROI( list, kHeadName[ s], NO);
        rims[ s]     = sekhmetFindROI( list, kNorbergName[ s], YES);
        grips[ s]    = sekhmetFindROI( list, kRadiusName[ s], NO);
        cups[ s]     = sekhmetFindROI( list, kCupName[ s], YES);
        cupGrips[ s] = sekhmetFindROI( list, kCupGripName[ s], NO);
        if( heads[ s] && heads[ s].type != tOval) heads[ s] = nil;
        if( rims[ s] && rims[ s].type != t2DPoint) rims[ s] = nil;
        if( grips[ s] && grips[ s].type != t2DPoint) grips[ s] = nil;
        if( cups[ s] && cups[ s].type != tOval) cups[ s] = nil;
        if( cupGrips[ s] && cupGrips[ s].type != t2DPoint) cupGrips[ s] = nil;
    }
    return heads[ 0] != nil && heads[ 1] != nil;
}

// Which part of the measurement a ROI belongs to (0 = not ours). Grips belong to the circles.
static int sekhmetPartOf( ROI *r)
{
    NSString *n = r.name;
    if( n == nil) return 0;
    if( [n hasPrefix: @"HD head "] || [n hasPrefix: @"HD radius "]) return kPartHeads;
    if( [n hasPrefix: @"Norberg "]) return kPartRims;
    if( [n hasPrefix: @"HD cup "] || [n hasPrefix: @"HD ace "]) return kPartCups;   // "HD ace" = centre points of Build 90
    return 0;
}

static BOOL sekhmetIsOurROI( ROI *r)
{
    return sekhmetPartOf( r) != 0;
}

// Gap between rim and grip in image pixels (18 view points): the grip must not overlap the rim.
static float sekhmetGripGap( DCMView *v)
{
    float sf = v.window.backingScaleFactor > 0 ? v.window.backingScaleFactor : 1;
    float scale = v.scaleValue > 0 ? v.scaleValue : 1;
    return 18.0f * sf / scale;
}

// Outer direction of a hip: from the other femoral head through this one (unit vector, image space).
static NSPoint sekhmetOuterDir( ROI *head, ROI *other, int side)
{
    float dx = head.rect.origin.x - other.rect.origin.x, dy = head.rect.origin.y - other.rect.origin.y, d = hypotf( dx, dy);
    if( d < 0.001) return NSMakePoint( side == 0 ? -1 : 1, 0);
    return NSMakePoint( dx / d, dy / d);
}

// Grip just outside the rim of its circle (Paket X: never on the rim); sign +1 = outer side (head), -1 = inner side (cup, Paket BE).
static void sekhmetGripOntoRimSigned( ROI *circle, ROI *grip, ROI *other, int side, float gap, float sign)
{
    NSRect rc = circle.rect;
    NSPoint dir = sekhmetOuterDir( circle, other, side);
    dir.x *= sign; dir.y *= sign;
    NSPoint g = grip.rect.origin;
    NSPoint np = NSMakePoint( rc.origin.x + dir.x * (rc.size.width + gap), rc.origin.y + dir.y * (rc.size.width + gap));
    if( fabs( np.x - g.x) > 0.01 || fabs( np.y - g.y) > 0.01)
        [grip setROIRect: NSMakeRect( np.x, np.y, 0, 0)];
}

static void sekhmetGripOntoRim( ROI *head, ROI *grip, ROI *other, int side, float gap)
{
    sekhmetGripOntoRimSigned( head, grip, other, side, gap, 1);
}

#pragma mark - Placement

- (void) removeParts:(int) mask in:(DCMView*) v
{
    NSMutableArray *list = [v curRoiList];
    for( ROI *r in [[list copy] autorelease])
    {
        if( sekhmetPartOf( r) & mask)
        {
            [[NSNotificationCenter defaultCenter] postNotificationName: OsirixRemoveROINotification object: r userInfo: nil];
            [list removeObject: r];
        }
    }
}

- (void) removeExistingIn:(DCMView*) v
{
    [self removeParts: kPartAll in: v];
}

// Inserted at the FRONT of curRoiList: DCMView mouseDown takes the first ROI that is hit, so points must precede the circles.
- (ROI*) addROIOfType:(ToolMode) t at:(NSPoint) c radius:(float) r name:(NSString*) name side:(int) side group:(NSTimeInterval) gid view:(DCMView*) v
{
    DCMPix *pix = v.curDCM;
    ROI *roi = [[[ROI alloc] initWithType: t :pix.pixelSpacingX :pix.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pix]] autorelease];
    [roi setROIRect: NSMakeRect( c.x, c.y, r, r)];   // tOval: origin = centre, size = radii; t2DPoint: origin = point
    [roi setName: name];
    [roi setColor: kSideColor[ side]];
    (void) gid;                                       // NO common groupID: Horos selects and drags a whole group together (DCMView setMode:toROIGroupWithID:) -> distance/angle could not change
    if( t == tOval) roi.displayTextualData = NO;      // no area/mean box on the head circles
    [roi setCurView: v];
    [[v curRoiList] insertObject: roi atIndex: 0];
    NSDictionary *userInfo = [NSDictionary dictionaryWithObjectsAndKeys: roi, @"ROI", [NSNumber numberWithInt: v.curImage], @"sliceNumber", nil];
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixAddROINotification object: v userInfo: userInfo];
    return roi;
}

- (void) placeInFrontViewer:(id) sender
{
    [self placeInViewer: [ViewerController frontMostDisplayed2DViewer]];
}

- (void) placeDIInFrontViewer:(id) sender
{
    [self placeDIInViewer: [ViewerController frontMostDisplayed2DViewer]];
}

+ (NSImage*) toolbarIcon
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage alloc] initWithSize: NSMakeSize( 32, 32)];
    [icon lockFocus];
    [[NSColor blackColor] set];
    NSBezierPath *bp = [NSBezierPath bezierPath];
    [bp setLineWidth: 2.0];
    // two femoral heads
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 2.5, 8.5, 11, 11)];
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 18.5, 8.5, 11, 11)];
    [bp stroke];
    // centre line (dashed) and both arms to the rims
    NSBezierPath *ln = [NSBezierPath bezierPath];
    [ln setLineWidth: 1.5];
    CGFloat dash[ 2] = { 2.5, 2.0 };
    [ln setLineDash: dash count: 2 phase: 0];
    [ln moveToPoint: NSMakePoint( 8, 14)]; [ln lineToPoint: NSMakePoint( 24, 14)];
    [ln stroke];
    NSBezierPath *arm = [NSBezierPath bezierPath];
    [arm setLineWidth: 2.0];
    [arm moveToPoint: NSMakePoint( 8, 14)];  [arm lineToPoint: NSMakePoint( 4.5, 29)];
    [arm moveToPoint: NSMakePoint( 24, 14)]; [arm lineToPoint: NSMakePoint( 27.5, 29)];
    [arm stroke];
    // angle arcs
    NSBezierPath *arc = [NSBezierPath bezierPath];
    [arc setLineWidth: 1.5];
    [arc appendBezierPathWithArcWithCenter: NSMakePoint( 8, 14) radius: 7 startAngle: 0 endAngle: 103];
    [arc stroke];
    NSBezierPath *arc2 = [NSBezierPath bezierPath];
    [arc2 setLineWidth: 1.5];
    [arc2 appendBezierPathWithArcWithCenter: NSMakePoint( 24, 14) radius: 7 startAngle: 77 endAngle: 180];
    [arc2 stroke];
    [icon unlockFocus];
    [icon setTemplate: YES];
    return icon;
}

// Paket BD: two heads, each with the acetabular centre (dot) displaced medially and a dashed line centre -> dot
static void sekhmetDrawDIIconBody( void)
{
    [[NSColor blackColor] set];
    NSBezierPath *bp = [NSBezierPath bezierPath];
    [bp setLineWidth: 2.0];
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 2.5, 8.5, 11, 11)];
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 18.5, 8.5, 11, 11)];
    [bp stroke];
    NSBezierPath *ln = [NSBezierPath bezierPath];
    [ln setLineWidth: 1.5];
    CGFloat dash[ 2] = { 2.0, 1.5 };
    [ln setLineDash: dash count: 2 phase: 0];
    [ln moveToPoint: NSMakePoint( 8, 14)];  [ln lineToPoint: NSMakePoint( 13.5, 17)];
    [ln moveToPoint: NSMakePoint( 24, 14)]; [ln lineToPoint: NSMakePoint( 18.5, 17)];
    [ln stroke];
    NSBezierPath *dots = [NSBezierPath bezierPath];
    [dots appendBezierPathWithOvalInRect: NSMakeRect( 12, 15.5, 3, 3)];
    [dots appendBezierPathWithOvalInRect: NSMakeRect( 17, 15.5, 3, 3)];
    [dots fill];
    NSBezierPath *ctr = [NSBezierPath bezierPath];
    [ctr setLineWidth: 1.5];
    [ctr moveToPoint: NSMakePoint( 6, 14)];  [ctr lineToPoint: NSMakePoint( 10, 14)];
    [ctr moveToPoint: NSMakePoint( 8, 12)];  [ctr lineToPoint: NSMakePoint( 8, 16)];
    [ctr moveToPoint: NSMakePoint( 22, 14)]; [ctr lineToPoint: NSMakePoint( 26, 14)];
    [ctr moveToPoint: NSMakePoint( 24, 12)]; [ctr lineToPoint: NSMakePoint( 24, 16)];
    [ctr stroke];
}

+ (NSImage*) toolbarDIIcon
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage alloc] initWithSize: NSMakeSize( 32, 32)];
    [icon lockFocus];
    sekhmetDrawDIIconBody();
    // "DI" above the heads
    NSDictionary *attr = [NSDictionary dictionaryWithObjectsAndKeys: [NSFont boldSystemFontOfSize: 9], NSFontAttributeName, [NSColor blackColor], NSForegroundColorAttributeName, nil];
    NSString *t = @"DI";
    NSSize ts = [t sizeWithAttributes: attr];
    [t drawAtPoint: NSMakePoint( 16 - ts.width / 2, 21) withAttributes: attr];
    [icon unlockFocus];
    [icon setTemplate: YES];
    return icon;
}

+ (NSImage*) toolbarDIDeleteIcon
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage alloc] initWithSize: NSMakeSize( 32, 32)];
    [icon lockFocus];
    sekhmetDrawDIIconBody();
    NSBezierPath *x = [NSBezierPath bezierPath];
    [x setLineWidth: 2.5];
    [x moveToPoint: NSMakePoint( 11, 21)]; [x lineToPoint: NSMakePoint( 21, 31)];
    [x moveToPoint: NSMakePoint( 21, 21)]; [x lineToPoint: NSMakePoint( 11, 31)];
    [x stroke];
    [icon unlockFocus];
    [icon setTemplate: YES];
    return icon;
}

- (void) deleteInFrontViewer:(id) sender
{
    [self deleteInViewer: [ViewerController frontMostDisplayed2DViewer]];
}

- (void) deleteDIInFrontViewer:(id) sender
{
    [self deleteDIInViewer: [ViewerController frontMostDisplayed2DViewer]];
}

// Norberg: rim points go; the circles (+ grips) only if no distraction index uses them.
- (void) deleteInViewer:(ViewerController*) vc
{
    DCMView *v = [vc imageView];
    if( v == nil || v.curDCM == nil) { NSBeep(); return; }
    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips);
    BOOL keepHeads = (cups[ 0] || cups[ 1]);
    [self removeParts: kPartRims | (keepHeads ? 0 : kPartHeads) in: v];
    [v setNeedsDisplay: YES];
}

// Distraction index: cup circles go; the head circles (+ grips) only if no Norberg measurement uses them.
- (void) deleteDIInViewer:(ViewerController*) vc
{
    DCMView *v = [vc imageView];
    if( v == nil || v.curDCM == nil) { NSBeep(); return; }
    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips);
    BOOL keepHeads = (rims[ 0] || rims[ 1]);
    [self removeParts: kPartCups | (keepHeads ? 0 : kPartHeads) in: v];
    [v setNeedsDisplay: YES];
}

+ (NSImage*) toolbarDeleteIcon
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage alloc] initWithSize: NSMakeSize( 32, 32)];
    [icon lockFocus];
    [[NSColor blackColor] set];
    NSBezierPath *bp = [NSBezierPath bezierPath];
    [bp setLineWidth: 2.0];
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 2.5, 8.5, 11, 11)];
    [bp appendBezierPathWithOvalInRect: NSMakeRect( 18.5, 8.5, 11, 11)];
    [bp stroke];
    NSBezierPath *ln = [NSBezierPath bezierPath];
    [ln setLineWidth: 1.5];
    CGFloat dash[ 2] = { 2.5, 2.0 };
    [ln setLineDash: dash count: 2 phase: 0];
    [ln moveToPoint: NSMakePoint( 8, 14)]; [ln lineToPoint: NSMakePoint( 24, 14)];
    [ln stroke];
    // cross = delete
    NSBezierPath *x = [NSBezierPath bezierPath];
    [x setLineWidth: 2.5];
    [x moveToPoint: NSMakePoint( 11, 21)]; [x lineToPoint: NSMakePoint( 21, 31)];
    [x moveToPoint: NSMakePoint( 21, 21)]; [x lineToPoint: NSMakePoint( 11, 31)];
    [x stroke];
    [icon unlockFocus];
    [icon setTemplate: YES];
    return icon;
}

// Fresh femoral head circles + grips, sized relative to the window (as ScrutPilot does): screen left = right hip.
// Fills heads[]/grips[]; rPx = radius in view points, hPx = half distance of the centres in view points.
- (void) placeHeadsIn:(DCMView*) v heads:(ROI*[ 2]) heads grips:(ROI*[ 2]) grips rPx:(float*) rPxOut hPx:(float*) hPxOut
{
    NSRect f = v.drawingFrameRect;
    float W = f.size.width;
    float rPx = MAX( 30, W * 0.06), hPx = MAX( 50, W * 0.11);
    float scale = v.scaleValue > 0 ? v.scaleValue : 1;
    float r = rPx / scale;                            // image pixels

    NSPoint centre[ 2] = { [v ConvertFromView2GL: NSMakePoint( -hPx, 0)], [v ConvertFromView2GL: NSMakePoint( hPx, 0)] };
    NSTimeInterval gid = [NSDate timeIntervalSinceReferenceDate];
    float gap = sekhmetGripGap( v);
    // Insertion is at the front of curRoiList -> circles first, then the grips end up before them.
    for( int s = 0; s < 2; s++)
        heads[ s] = [self addROIOfType: tOval at: centre[ s] radius: r name: kHeadName[ s] side: s group: gid view: v];
    for( int s = 0; s < 2; s++)
    {
        float dx = centre[ s].x - centre[ 1-s].x, dy = centre[ s].y - centre[ 1-s].y, d = hypotf( dx, dy);
        if( d < 0.001) { dx = s == 0 ? -1 : 1; dy = 0; d = 1; }
        NSPoint gp = NSMakePoint( centre[ s].x + dx / d * (r + gap), centre[ s].y + dy / d * (r + gap));
        grips[ s] = [self addROIOfType: t2DPoint at: gp radius: 0 name: kRadiusName[ s] side: s group: gid view: v];
        [grips[ s] setColor: kRadiusColor];
        grips[ s].displayTextualData = NO;
    }
    if( rPxOut) *rPxOut = rPx;
    if( hPxOut) *hPxOut = hPx;
}

// Grips for circles that have none (measurements from Build 55-57, or circles the user re-created).
- (void) ensureGripsIn:(DCMView*) v heads:(ROI*[ 2]) heads grips:(ROI*[ 2]) grips
{
    float gap = sekhmetGripGap( v);
    for( int s = 0; s < 2; s++)
    {
        if( grips[ s]) continue;
        NSPoint dir = sekhmetOuterDir( heads[ s], heads[ 1-s], s);
        NSRect rc = heads[ s].rect;
        NSPoint gp = NSMakePoint( rc.origin.x + dir.x * (rc.size.width + gap), rc.origin.y + dir.y * (rc.size.width + gap));
        grips[ s] = [self addROIOfType: t2DPoint at: gp radius: 0 name: kRadiusName[ s] side: s group: 0 view: v];
        [grips[ s] setColor: kRadiusColor];
        grips[ s].displayTextualData = NO;
    }
}

// View-space radius of a circle (view points, honours zoom).
static float sekhmetViewRadius( DCMView *v, ROI *head)
{
    NSPoint c = [v ConvertFromGL2View: head.rect.origin];
    NSPoint e = [v ConvertFromGL2View: NSMakePoint( head.rect.origin.x + head.rect.size.width, head.rect.origin.y)];
    return hypotf( e.x - c.x, e.y - c.y);
}

- (BOOL) viewerReady:(ViewerController*) vc title:(NSString*) title
{
    DCMView *v = [vc imageView];
    if( vc == nil || v == nil || v.curDCM == nil)
    {
        NSBeep();
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: title];
        [a setInformativeText: NSLocalizedString( @"Open the VD pelvis radiograph in a 2D viewer first.", nil)];
        [a runModal];
        return NO;
    }
    return YES;
}

- (void) placeInViewer:(ViewerController*) vc
{
    if( [self viewerReady: vc title: NSLocalizedString( @"Norberg Angle", nil)] == NO) return;
    DCMView *v = [vc imageView];

    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    BOOL haveHeads = sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips);
    BOOL keepHeads = haveHeads && (cups[ 0] || cups[ 1]);      // a distraction index uses the circles: keep them, only the rim points are reset
    [self removeParts: kPartRims | (keepHeads ? 0 : kPartHeads) in: v];

    NSPoint rim[ 2];
    if( keepHeads)
    {
        [self ensureGripsIn: v heads: heads grips: grips];
        for( int s = 0; s < 2; s++)                    // rim straight above the centre (view space) at 1.35 r, as in the fresh layout
        {
            NSPoint c = [v ConvertFromGL2View: heads[ s].rect.origin];
            rim[ s] = [v ConvertFromView2GL: NSMakePoint( c.x, c.y - sekhmetViewRadius( v, heads[ s]) * 1.35f)];
        }
    }
    else
    {
        float rPx = 0, hPx = 0;
        [self placeHeadsIn: v heads: heads grips: grips rPx: &rPx hPx: &hPx];
        float vPx = rPx * 1.35f;
        rim[ 0] = [v ConvertFromView2GL: NSMakePoint( -hPx, -vPx)];
        rim[ 1] = [v ConvertFromView2GL: NSMakePoint( hPx, -vPx)];
    }
    for( int s = 0; s < 2; s++)
    {
        ROI *p = [self addROIOfType: t2DPoint at: rim[ s] radius: 0 name: kNorbergName[ s] side: s group: 0 view: v];
        p.displayTextualData = NO;      // Paket X: the value is drawn at the arc; the Horos text box hid the circle
    }

    [self updateView: v];
    [vc setROIToolTag: tOval];   // Horos drags ROIs only with a ROI tool active (DCMView mouseDown: roiTool:), never with the pointer/WL tool
    [v setNeedsDisplay: YES];
}

// Paket BD/BE: acetabular cup circles (yellow), same radius as the head, centre 0.6 r medial and 0.3 r cranial of the head centre
// (DI 0.67 until dragged); grip on the inner side. DI = distance of the two centres / head radius.
- (void) placeDIInViewer:(ViewerController*) vc
{
    if( [self viewerReady: vc title: NSLocalizedString( @"Distraction Index", nil)] == NO) return;
    DCMView *v = [vc imageView];

    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    BOOL haveHeads = sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips);
    BOOL keepHeads = haveHeads && (rims[ 0] || rims[ 1]);      // a Norberg measurement uses the circles: keep them, only the cups are reset
    [self removeParts: kPartCups | (keepHeads ? 0 : kPartHeads) in: v];

    if( keepHeads)
        [self ensureGripsIn: v heads: heads grips: grips];
    else
        [self placeHeadsIn: v heads: heads grips: grips rPx: NULL hPx: NULL];

    float gap = sekhmetGripGap( v);
    NSPoint cupCentre[ 2];
    for( int s = 0; s < 2; s++)                                // cups first, then their grips end up in front of them
    {
        NSPoint c = [v ConvertFromGL2View: heads[ s].rect.origin];
        NSPoint o = [v ConvertFromGL2View: heads[ 1-s].rect.origin];
        float rp = sekhmetViewRadius( v, heads[ s]);
        float dx = o.x - c.x, dy = o.y - c.y, d = hypotf( dx, dy);
        if( d < 0.001) { dx = s == 0 ? 1 : -1; dy = 0; d = 1; }
        NSPoint cv = NSMakePoint( c.x + dx / d * rp * 0.6f, c.y + dy / d * rp * 0.6f - rp * 0.3f);   // view space: y down, cranial = up
        cupCentre[ s] = [v ConvertFromView2GL: cv];
        ROI *cup = [self addROIOfType: tOval at: cupCentre[ s] radius: heads[ s].rect.size.width name: kCupName[ s] side: s group: 0 view: v];
        [cup setColor: kCupColor];
    }
    for( int s = 0; s < 2; s++)
    {
        NSPoint dir = sekhmetOuterDir( heads[ s], heads[ 1-s], s);   // inner side = towards the other hip
        float r = heads[ s].rect.size.width;
        NSPoint gp = NSMakePoint( cupCentre[ s].x - dir.x * (r + gap), cupCentre[ s].y - dir.y * (r + gap));
        ROI *g = [self addROIOfType: t2DPoint at: gp radius: 0 name: kCupGripName[ s] side: s group: 0 view: v];
        [g setColor: kCupColor];
        g.displayTextualData = NO;
    }

    [self updateView: v];
    [vc setROIToolTag: tOval];
    [v setNeedsDisplay: YES];
}

#pragma mark - Live update

- (void) updateView:(DCMView*) v
{
    [self updateView: v changed: nil];
}

- (void) updateView:(DCMView*) v changed:(ROI*) changed
{
    if( v == nil) return;
    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    NSArray *list = [v curRoiList];
    if( sekhmetFindGroup( list, heads, rims, grips, cups, cupGrips) == NO) return;

    DCMPix *pix = v.curDCM;
    double sx = pix.pixelSpacingX, sy = pix.pixelSpacingY;
    float gap = sekhmetGripGap( v);

    sekhmetNorbergUpdating = YES;
    @try
    {
        for( int s = 0; s < 2; s++)
        {
            ROI *h = heads[ s];
            NSRect rc = h.rect;
            ROI *g = grips[ s];
            if( g && changed == g)                        // grip dragged: radius = distance grip <-> centre minus gap; grip snaps back to the outer side
            {
                float nr = MAX( kMinRadiusPx, hypotf( g.rect.origin.x - rc.origin.x, g.rect.origin.y - rc.origin.y) - gap);
                rc.size.width = nr; rc.size.height = nr;
                [h setROIRect: rc];
                sekhmetGripOntoRim( h, g, heads[ 1-s], s, gap);
            }
            else
            {
                if( rc.size.width != rc.size.height)       // keep the femoral head a circle (Horos handle would make an ellipse)
                {
                    float m = MAX( fabs( rc.size.width), fabs( rc.size.height));
                    rc.size.width = m; rc.size.height = m;
                    [h setROIRect: rc];
                }
                if( g) sekhmetGripOntoRim( h, g, heads[ 1-s], s, gap);   // circle moved/resized: grip follows, outer side
            }
            if( h.displayTextualData) h.displayTextualData = NO;
            if( g && g.displayTextualData) g.displayTextualData = NO;
            if( rims[ s] && rims[ s].displayTextualData) rims[ s].displayTextualData = NO;   // Paket X, also for older measurements

            ROI *cup = cups[ s], *cg = cupGrips[ s];        // Paket BE: the cup circle behaves like the head circle, grip on the inner side
            if( cup)
            {
                NSRect cc = cup.rect;
                if( cg && changed == cg)
                {
                    float nr = MAX( kMinRadiusPx, hypotf( cg.rect.origin.x - cc.origin.x, cg.rect.origin.y - cc.origin.y) - gap);
                    cc.size.width = nr; cc.size.height = nr;
                    [cup setROIRect: cc];
                    sekhmetGripOntoRimSigned( cup, cg, heads[ 1-s], s, gap, -1);
                }
                else
                {
                    if( cc.size.width != cc.size.height)
                    {
                        float m = MAX( fabs( cc.size.width), fabs( cc.size.height));
                        cc.size.width = m; cc.size.height = m;
                        [cup setROIRect: cc];
                    }
                    if( cg) sekhmetGripOntoRimSigned( cup, cg, heads[ 1-s], s, gap, -1);
                }
                if( cup.displayTextualData) cup.displayTextualData = NO;
                if( cg && cg.displayTextualData) cg.displayTextualData = NO;
            }

            ROI *p = rims[ s];
            if( p)
            {
                double w = [SekhmetNorberg angleAtCenter: h.rect.origin rim: p.rect.origin other: heads[ 1-s].rect.origin spacingX: sx spacingY: sy];
                NSString *name = [NSString stringWithFormat: @"%@: %.1f°", kNorbergName[ s], w];
                if( [p.name isEqualToString: name] == NO)
                    [p setName: name];
            }
            if( cup)                                      // Paket BD: value in the name, stored with the ROI
            {
                double di = [SekhmetNorberg distractionIndexAtCenter: h.rect.origin radius: h.rect.size.width cup: cup.rect.origin spacingX: sx spacingY: sy];
                NSString *name = [NSString stringWithFormat: @"%@: %.2f", kCupName[ s], di];
                if( [cup.name isEqualToString: name] == NO)
                    [cup setName: name];
            }
        }
    }
    @finally
    {
        sekhmetNorbergUpdating = NO;
    }
    [v setNeedsDisplay: YES];   // rect changes post no notification
}

- (void) roiChanged:(NSNotification*) note
{
    if( sekhmetNorbergUpdating) return;
    ROI *r = [note object];
    if( [r isKindOfClass: [ROI class]] == NO || sekhmetIsOurROI( r) == NO) return;
    [self updateView: r.curView changed: r];
}

#pragma mark - Scroll wheel = radius

+ (BOOL) handleScrollWheel:(NSEvent*) event inView:(DCMView*) v
{
    if( v == nil || v.curDCM == nil || [v isKindOfClass: [DCMView class]] == NO) return NO;
    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    if( sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips) == NO) return NO;
    NSPoint pt = [v ConvertFromNSView2GL: [v convertPoint: [event locationInWindow] fromView: nil]];   // image pixels
    float gap = sekhmetGripGap( v);
    ROI *target = nil;
    float best = 0;
    ROI *candidates[ 4] = { heads[ 0], heads[ 1], cups[ 0], cups[ 1] };   // Paket BE: head and cup overlap — the circle whose centre is nearer (relative to its radius) takes the wheel
    for( int i = 0; i < 4; i++)
    {
        ROI *c = candidates[ i];
        if( c == nil) continue;
        NSRect rc = c.rect;
        float r = fabs( rc.size.width), d = hypotf( pt.x - rc.origin.x, pt.y - rc.origin.y);
        if( d > r + gap) continue;
        float rel = d / MAX( r, kMinRadiusPx);
        if( target == nil || rel < best) { target = c; best = rel; }
    }
    if( target == nil) return NO;
    float delta = [event hasPreciseScrollingDeltas] ? [event scrollingDeltaY] * 0.25f : [event deltaY] * 3.0f;   // trackpad fine, wheel coarse
    if( delta == 0) return YES;
    float scale = v.scaleValue > 0 ? v.scaleValue : 1;
    NSRect rc = target.rect;
    float nr = MAX( kMinRadiusPx, rc.size.width + delta / scale);   // wheel up = larger, step in view points
    rc.size.width = nr; rc.size.height = nr;
    [target setROIRect: rc];
    [[SekhmetNorberg shared] updateView: v changed: target];        // grip follows the rim, angle unchanged, DI follows the head radius
    return YES;
}

#pragma mark - Drawing (arm, arc, value)

// Value label in the measurement-text style of Paket N (LabelFONTNAME/LabelFONTSIZE, white, box + outline as configured
// in SekhVet > Display). Drawn centred at (x, y) in view space; matrix = identity + 2/w,-2/h scale (as in drawObjects:).
static void sekhmetDrawLabel( DCMView *v, NSString *txt, float x, float y)
{
    static NSCache *cache = nil;
    if( cache == nil) { cache = [[NSCache alloc] init]; cache.countLimit = 40; }
    float sf = v.window.backingScaleFactor > 0 ? v.window.backingScaleFactor : 1;
    NSString *key = [NSString stringWithFormat: @"%@|%.1f", txt, sf];
    StringTexture *sT = [cache objectForKey: key];
    if( sT == nil)
    {
        NSMutableDictionary *attrib = [NSMutableDictionary dictionary];
        NSFont *f = [NSFont fontWithName: [[NSUserDefaults standardUserDefaults] stringForKey: @"LabelFONTNAME"] size: [[NSUserDefaults standardUserDefaults] floatForKey: @"LabelFONTSIZE"]];
        if( f == nil) f = [NSFont boldSystemFontOfSize: 14];
        [attrib setObject: f forKey: NSFontAttributeName];
        [attrib setObject: [NSColor whiteColor] forKey: NSForegroundColorAttributeName];
        sT = [[[StringTexture alloc] initWithString: txt withAttributes: attrib] autorelease];
        [sT setAntiAliasing: YES];
        [sT genTextureWithBackingScaleFactor: sf];
        [cache setObject: sT forKey: key];
    }
    CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil) return;
    float w = [sT texSize].width, h = [sT texSize].height;
    float xc = x - w / 2, yc = y - h / 2;

    int bg = (int) [[NSUserDefaults standardUserDefaults] integerForKey: @"SekhmetAnnotationBackground"];
    if( bg == 2 || bg == 3)
    {
        float box[ 4] = { 0, 0, 0, 0.7f };
        sscanf( [[[NSUserDefaults standardUserDefaults] stringForKey: @"SekhmetAnnotationBoxColor"] UTF8String] ?: "", "%f %f %f %f", &box[ 0], &box[ 1], &box[ 2], &box[ 3]);
        glDisable( GL_TEXTURE_RECTANGLE_EXT);
        glEnable( GL_BLEND);
        glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
        glColor4f( box[ 0], box[ 1], box[ 2], box[ 3]);
        glBegin( GL_QUADS);
        glVertex2f( xc-3, yc-2); glVertex2f( xc+w+3, yc-2); glVertex2f( xc+w+3, yc+h+2); glVertex2f( xc-3, yc+h+2);
        glEnd();
    }
    glEnable( GL_TEXTURE_RECTANGLE_EXT);
    glEnable( GL_BLEND);
    glBlendFunc( GL_ONE, GL_ONE_MINUS_SRC_ALPHA);        // premultiplied texture, as DCMView/ROI draw it
    glColor4f( 0, 0, 0, 1.0f);
    if( bg == 1 || bg == 3)
    {
        [sT drawAtPoint: NSMakePoint( xc-1, yc-1)];
        [sT drawAtPoint: NSMakePoint( xc+1, yc-1)];
        [sT drawAtPoint: NSMakePoint( xc-1, yc+1)];
    }
    [sT drawAtPoint: NSMakePoint( xc+1, yc+1)];
    glColor4f( 1.0f, 1.0f, 1.0f, 1.0f);
    [sT drawAtPoint: NSMakePoint( xc, yc)];
    glDisable( GL_TEXTURE_RECTANGLE_EXT);
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

- (void) drawObjects:(NSNotification*) note
{
    DCMView *v = [note object];
    if( [v isKindOfClass: [DCMView class]] == NO || v.curDCM == nil) return;

    ROI *heads[ 2], *rims[ 2], *grips[ 2], *cups[ 2], *cupGrips[ 2];
    if( sekhmetFindGroup( [v curRoiList], heads, rims, grips, cups, cupGrips) == NO) return;

    CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil) return;

    NSRect f = v.drawingFrameRect;
    float sf = v.window.backingScaleFactor > 0 ? v.window.backingScaleFactor : 1;

    // Draw in view space (backing pixels, centred, y down): ConvertFromGL2View honours zoom, rotation and flips.
    glPushMatrix();
    glLoadIdentity();
    glScalef( 2.0f / f.size.width, -2.0f / f.size.height, 1.0f);
    glEnable( GL_BLEND);
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
    glEnable( GL_LINE_SMOOTH);

    NSPoint c[ 2];
    for( int s = 0; s < 2; s++) c[ s] = [v ConvertFromGL2View: heads[ s].rect.origin];

    // Line joining both centres (yellow, dashed) — only for the Norberg measurement
    if( rims[ 0] || rims[ 1])
    {
        glColor4f( 1.0f, 0.86f, 0.0f, 0.9f);
        glLineWidth( 1.5f * sf);
        glEnable( GL_LINE_STIPPLE);
        glLineStipple( 2, 0x0F0F);
        glBegin( GL_LINES);
        glVertex2f( c[ 0].x, c[ 0].y);
        glVertex2f( c[ 1].x, c[ 1].y);
        glEnd();
        glDisable( GL_LINE_STIPPLE);
    }

    DCMPix *pix = v.curDCM;
    for( int s = 0; s < 2; s++)
    {
        ROI *h = heads[ s], *p = rims[ s];
        float cr = kSideColor[ s].red / 65535.f, cg = kSideColor[ s].green / 65535.f, cb = kSideColor[ s].blue / 65535.f;

        // Centre cross
        NSPoint edge = [v ConvertFromGL2View: NSMakePoint( h.rect.origin.x + h.rect.size.width, h.rect.origin.y)];
        float rp = hypotf( edge.x - c[ s].x, edge.y - c[ s].y);
        float cs = MAX( 6*sf, rp * 0.08f);
        glColor4f( cr, cg, cb, 1.0f);
        glLineWidth( 2.0f * sf);
        glBegin( GL_LINES);
        glVertex2f( c[ s].x - cs, c[ s].y); glVertex2f( c[ s].x + cs, c[ s].y);
        glVertex2f( c[ s].x, c[ s].y - cs); glVertex2f( c[ s].x, c[ s].y + cs);
        glEnd();

        // Radius grip: yellow diamond outside the rim, tick from the rim to the grip (Horos draws the point itself underneath)
        if( grips[ s])
        {
            NSPoint g = [v ConvertFromGL2View: grips[ s].rect.origin];
            float d = 6 * sf;
            NSPoint dir = sekhmetOuterDir( h, heads[ 1-s], s);
            NSPoint rimPt = [v ConvertFromGL2View: NSMakePoint( h.rect.origin.x + dir.x * h.rect.size.width, h.rect.origin.y + dir.y * h.rect.size.width)];
            glColor4f( 1.0f, 0.86f, 0.0f, 0.9f);
            glLineWidth( 1.5f * sf);
            glBegin( GL_LINES);
            glVertex2f( rimPt.x, rimPt.y); glVertex2f( g.x, g.y);
            glEnd();
            glColor4f( 1.0f, 0.86f, 0.0f, 0.85f);
            glBegin( GL_QUADS);
            glVertex2f( g.x, g.y - d); glVertex2f( g.x + d, g.y); glVertex2f( g.x, g.y + d); glVertex2f( g.x - d, g.y);
            glEnd();
            glColor4f( 1.0f, 1.0f, 1.0f, 0.9f);
            glLineWidth( 1.5f * sf);
            glBegin( GL_LINE_LOOP);
            glVertex2f( g.x, g.y - d); glVertex2f( g.x + d, g.y); glVertex2f( g.x, g.y + d); glVertex2f( g.x - d, g.y);
            glEnd();
        }

        // Paket BD/BE: distraction index — cup circle (Horos draws it), its centre cross and inner grip, red line between the
        // two centres, value below the head circle (with the risk level when the option is on)
        if( cups[ s])
        {
            ROI *cup = cups[ s];
            NSPoint k = [v ConvertFromGL2View: cup.rect.origin];
            float yr = kCupColor.red / 65535.f, yg = kCupColor.green / 65535.f, yb = kCupColor.blue / 65535.f;
            NSPoint kEdge = [v ConvertFromGL2View: NSMakePoint( cup.rect.origin.x + cup.rect.size.width, cup.rect.origin.y)];
            float krp = hypotf( kEdge.x - k.x, kEdge.y - k.y);
            float kcs = MAX( 6*sf, krp * 0.08f);
            glColor4f( yr, yg, yb, 1.0f);
            glLineWidth( 2.0f * sf);
            glBegin( GL_LINES);
            glVertex2f( k.x - kcs, k.y); glVertex2f( k.x + kcs, k.y);
            glVertex2f( k.x, k.y - kcs); glVertex2f( k.x, k.y + kcs);
            glEnd();
            if( cupGrips[ s])
            {
                NSPoint g = [v ConvertFromGL2View: cupGrips[ s].rect.origin];
                float d = 6 * sf;
                NSPoint dir = sekhmetOuterDir( cup, heads[ 1-s], s);
                NSPoint rimPt = [v ConvertFromGL2View: NSMakePoint( cup.rect.origin.x - dir.x * cup.rect.size.width, cup.rect.origin.y - dir.y * cup.rect.size.width)];
                glColor4f( yr, yg, yb, 0.9f);
                glLineWidth( 1.5f * sf);
                glBegin( GL_LINES);
                glVertex2f( rimPt.x, rimPt.y); glVertex2f( g.x, g.y);
                glEnd();
                glColor4f( yr, yg, yb, 0.85f);
                glBegin( GL_QUADS);
                glVertex2f( g.x, g.y - d); glVertex2f( g.x + d, g.y); glVertex2f( g.x, g.y + d); glVertex2f( g.x - d, g.y);
                glEnd();
                glColor4f( 1.0f, 1.0f, 1.0f, 0.9f);
                glLineWidth( 1.5f * sf);
                glBegin( GL_LINE_LOOP);
                glVertex2f( g.x, g.y - d); glVertex2f( g.x + d, g.y); glVertex2f( g.x, g.y + d); glVertex2f( g.x - d, g.y);
                glEnd();
            }
            // red line head centre -> cup centre (the distance that is divided by the head radius)
            glColor4f( 1.0f, 0.2f, 0.2f, 1.0f);
            glLineWidth( 2.5f * sf);
            glBegin( GL_LINES);
            glVertex2f( c[ s].x, c[ s].y); glVertex2f( k.x, k.y);
            glEnd();
            double di = [SekhmetNorberg distractionIndexAtCenter: h.rect.origin radius: h.rect.size.width cup: cup.rect.origin spacingX: pix.pixelSpacingX spacingY: pix.pixelSpacingY];
            NSString *txt = [SekhmetNorberg showsRisk] ? [NSString stringWithFormat: @"DI %.2f · %@", di, [SekhmetNorberg riskTextForDI: di]]
                                                       : [NSString stringWithFormat: @"DI %.2f", di];
            sekhmetDrawLabel( v, txt, c[ s].x, c[ s].y + MAX( rp, krp) + 26*sf);
        }

        if( p == nil) continue;
        NSPoint a = [v ConvertFromGL2View: p.rect.origin];
        float dx = a.x - c[ s].x, dy = a.y - c[ s].y;
        float dist = hypotf( dx, dy);
        if( dist < 1) continue;

        // Arm from the centre through the rim point, 1.3x (white, as drawn since the grips exist — the colour left over from the grip)
        glColor4f( 1.0f, 1.0f, 1.0f, 0.9f);
        glLineWidth( 2.5f * sf);
        glBegin( GL_LINES);
        glVertex2f( c[ s].x, c[ s].y);
        glVertex2f( c[ s].x + dx * 1.3f, c[ s].y + dy * 1.3f);
        glEnd();

        // Arc between the centre line and the arm (shorter way round)
        float arcR = MAX( 20*sf, MIN( rp * 0.55f, dist * 0.45f));
        float ref = atan2f( c[ 1-s].y - c[ s].y, c[ 1-s].x - c[ s].x);
        float arm = atan2f( dy, dx);
        float span = arm - ref;
        while( span > M_PI) span -= 2*M_PI;
        while( span < -M_PI) span += 2*M_PI;
        glLineWidth( 2.0f * sf);
        glBegin( GL_LINE_STRIP);
        for( int i = 0; i <= 24; i++)
        {
            float t = ref + span * i / 24.0f;
            glVertex2f( c[ s].x + arcR * cosf( t), c[ s].y + arcR * sinf( t));
        }
        glEnd();

        // Value beside the arc
        double w = [SekhmetNorberg angleAtCenter: h.rect.origin rim: p.rect.origin other: heads[ 1-s].rect.origin spacingX: pix.pixelSpacingX spacingY: pix.pixelSpacingY];
        // Paket Z: label at a fixed clock position outside the circle — 10 o'clock for R (blue), 2 o'clock for L (red)
        float lr = rp + 34*sf;
        float clock = (s == 0) ? -0.866f : 0.866f;                 // x component: 10 o'clock left, 2 o'clock right; y = up
        NSString *txt = [NSString stringWithFormat: @"%@ %.1f°", s == 0 ? @"R" : @"L", w];
        sekhmetDrawLabel( v, txt, c[ s].x + lr * clock, c[ s].y - lr * 0.5f);
    }

    glLineWidth( 1.0f * sf);
    glPopMatrix();
}

@end
