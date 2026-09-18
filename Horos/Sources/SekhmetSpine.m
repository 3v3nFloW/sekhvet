/*=========================================================================
 Sekhmet — Spine Labeling (Vet). Siehe Header.
 ============================================================================*/

#import "SekhmetSpine.h"
#import "SekhmetDisplayPanel.h"
#import "ROI.h"
#import "DCMView.h"
#import "ViewerController.h"
#import "MPRController.h"
#import "MPRDCMView.h"
#import "DCMPix.h"
#import "Notifications.h"

static SekhmetSpine *sekhmetSpine = nil;
static NSMutableDictionary *sekhmetKnownNames = nil;   // NSValue(ROI*) -> zuletzt gesehener Name (erkennt Umbenennungen)
static BOOL sekhmetRenumbering = NO;
static NSString* const kRegionLetters[ 5] = { @"C", @"T", @"L", @"S", @"Cd" };
// Wirbelzahlen je Region: Hund/Katze, Kaninchen, Pferd (Cd offen)
static const int kCounts[ 3][ 5] = { { 7, 13, 7, 3, 99 }, { 7, 12, 7, 4, 99 }, { 7, 18, 6, 5, 99 } };

@implementation SekhmetSpine

+ (SekhmetSpine*) shared
{
    if( sekhmetSpine == nil) sekhmetSpine = [[SekhmetSpine alloc] init];
    return sekhmetSpine;
}

+ (BOOL) isActive { return sekhmetSpine != nil && sekhmetSpine->active; }

+ (NSArray*) speciesNames
{
    return [NSArray arrayWithObjects: NSLocalizedString( @"Dog / Cat (7-13-7-3)", nil), NSLocalizedString( @"Rabbit (7-12-7-4)", nil), NSLocalizedString( @"Horse (7-18-6-5)", nil), nil];
}

+ (NSArray*) regionNames
{
    return [NSArray arrayWithObjects: @"C — cervical", @"T — thoracic", @"L — lumbar", @"S — sacral", @"Cd — caudal", nil];
}

- (id) init
{
    NSPanel *w = [[[NSPanel alloc] initWithContentRect: NSMakeRect( 0, 0, 340, 232)
                                             styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                               backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"Spine Labeling (SekhVet)", nil)];
    [w setReleasedWhenClosed: NO];
    [w setFloatingPanel: YES];
    [w setBecomesKeyOnlyIfNeeded: YES];

    self = [super initWithWindow: w];
    if( self)
    {
        createdROIs = [[NSMutableArray alloc] init];
        species = 0; region = 2; number = 1; backwards = NO;
        [self buildUI];
        [self updateNextLabel];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(roiRemoved:) name: OsirixRemoveROINotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(viewerClosed:) name: OsirixCloseViewerNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(roiChanged:) name: OsirixROIChangeNotification object: nil];
        if( sekhmetKnownNames == nil) sekhmetKnownNames = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [createdROIs release]; [lastVertebra release];
    [super dealloc];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text]; [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title]; [b setBezelStyle: NSBezelStyleRounded]; [b setTarget: self]; [b setAction: sel];
    [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float y = 232 - 34;

    [cv addSubview: [self label: NSLocalizedString( @"Species:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    speciesPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 90, y - 2, 234, 26) pullsDown: NO] autorelease];
    [speciesPopup addItemsWithTitles: [SekhmetSpine speciesNames]];
    [speciesPopup setTarget: self]; [speciesPopup setAction: @selector(settingsChanged:)];
    [cv addSubview: speciesPopup];

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Start at:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    regionPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 90, y - 2, 150, 26) pullsDown: NO] autorelease];
    [regionPopup addItemsWithTitles: [SekhmetSpine regionNames]];
    [regionPopup selectItemAtIndex: 2];
    [regionPopup setTarget: self]; [regionPopup setAction: @selector(settingsChanged:)];
    [cv addSubview: regionPopup];
    numberField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 250, y, 50, 22)] autorelease];
    [numberField setIntegerValue: 1];
    [numberField setTarget: self]; [numberField setAction: @selector(settingsChanged:)];
    [cv addSubview: numberField];

    y -= 28;
    backwardsButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 90, y, 230, 18)] autorelease];
    [backwardsButton setButtonType: NSButtonTypeSwitch];
    [backwardsButton setTitle: NSLocalizedString( @"count backwards (caudal → cranial)", nil)];
    [backwardsButton setFont: [NSFont systemFontOfSize: 12]];
    [backwardsButton setTarget: self]; [backwardsButton setAction: @selector(settingsChanged:)];
    [cv addSubview: backwardsButton];

    y -= 34;
    nextLabel = [self label: @"" frame: NSMakeRect( 16, y, 308, 24)];
    [nextLabel setFont: [NSFont boldSystemFontOfSize: 16]];
    [cv addSubview: nextLabel];

    y -= 40;
    startButton = [self button: NSLocalizedString( @"Start", nil) frame: NSMakeRect( 16, y, 100, 30) action: @selector(toggle:)];
    [cv addSubview: startButton];
    [cv addSubview: [self button: NSLocalizedString( @"⌫ Undo last", nil) frame: NSMakeRect( 122, y, 120, 30) action: @selector(undoAction:)]];
    [cv addSubview: [self button: NSLocalizedString( @"Delete all", nil) frame: NSMakeRect( 246, y, 80, 30) action: @selector(clearAll:)]];

    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Click = vertebra · Alt-click = disc · Esc = stop", nil) frame: NSMakeRect( 16, y, 308, 20)]];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: NO]; // SekhVet: innerhalb der Viewer-Flaeche
    [super showWindow: sender];
}

#pragma mark - Zaehlwerk

- (int) countForRegion:(NSInteger) r
{
    if( species < 0 || species > 2 || r < 0 || r > 4) return 99;
    return kCounts[ species][ r];
}

- (NSString*) labelFor:(NSInteger) r number:(NSInteger) n
{
    return [NSString stringWithFormat: @"%@%d", kRegionLetters[ MAX( 0, MIN( 4, r))], (int) n];
}

- (NSString*) peekLabel
{
    return [self labelFor: region number: number];
}

- (void) advance
{
    if( backwards)
    {
        number--;
        if( number < 1)
        {
            if( region > 0) { region--; number = [self countForRegion: region]; }
            else number = 1;
        }
    }
    else
    {
        number++;
        if( number > [self countForRegion: region] && region < 4)
        {
            region++; number = 1;
        }
    }
}

- (void) retreat
{
    // Gegenteil von advance (fuer ⌫)
    BOOL saved = backwards; backwards = !backwards;
    [self advance];
    backwards = saved;
}

- (NSString*) takeLabelWithModifiers:(NSUInteger) flags
{
    if( flags & NSEventModifierFlagOption)
    {
        // Bandscheibe zwischen dem letzten Wirbel und dem naechsten; zaehlt nicht weiter
        NSString *next = [self peekLabel];
        if( lastVertebra.length == 0) return [NSString stringWithFormat: @"%@-%@", next, next];
        return [NSString stringWithFormat: @"%@-%@", lastVertebra, next];
    }
    NSString *l = [self peekLabel];
    [lastVertebra release]; lastVertebra = [l retain];
    [self advance];
    [self updateNextLabel];
    return l;
}

- (void) updateNextLabel
{
    [nextLabel setStringValue: [NSString stringWithFormat: NSLocalizedString( @"%@  Next label: %@", nil), active ? @"●" : @"○", [self peekLabel]]];
    [startButton setTitle: active ? NSLocalizedString( @"Stop", nil) : NSLocalizedString( @"Start", nil)];
}

#pragma mark - Haken

+ (void) willCreatePointROI:(ROI*) roi inView:(DCMView*) view modifiers:(NSUInteger) flags
{
    if( [self isActive] == NO) return;
    NSString *l = [sekhmetSpine takeLabelWithModifiers: flags];
    [ROI setDefaultName: l];            // DCMView vergibt gleich diesen Namen
    [ROI performSelector: @selector(setDefaultName:) withObject: nil afterDelay: 0];
    if( [view isKindOfClass: NSClassFromString( @"MPRDCMView")] == NO)
        [sekhmetSpine->createdROIs addObject: roi];   // 2D-Viewer: die ROI ist bereits die persistente
}

+ (void) notePersistentROI:(ROI*) roi
{
    if( [self isActive] == NO || roi == nil) return;
    [sekhmetSpine->createdROIs addObject: roi];
}

+ (BOOL) handleKey:(unichar) c
{
    if( [self isActive] == NO) return NO;
    if( c == NSDeleteCharacter || c == NSBackspaceCharacter || c == 127 || c == 8) { [sekhmetSpine undo]; return YES; }
    if( c == 27) { [sekhmetSpine stop]; return YES; }
    return NO;
}

- (void) roiRemoved:(NSNotification*) n
{
    [createdROIs removeObjectIdenticalTo: [n object]];
    [sekhmetKnownNames removeObjectForKey: [NSValue valueWithPointer: [n object]]];
}

#pragma mark - Umbenennen mit Neuzaehlung

+ (BOOL) parseLabel:(NSString*) l region:(NSInteger*) region number:(NSInteger*) number
{
    if( l.length < 2) return NO;
    NSInteger ri = -1; NSUInteger p = 0;
    if( [l hasPrefix: @"Cd"]) { ri = 4; p = 2; }
    else
    {
        unichar c = [l characterAtIndex: 0];
        ri = (c == 'C') ? 0 : (c == 'T') ? 1 : (c == 'L') ? 2 : (c == 'S') ? 3 : -1;
        p = 1;
    }
    if( ri < 0 || p >= l.length) return NO;
    NSString *num = [l substringFromIndex: p];
    if( [num rangeOfCharacterFromSet: [[NSCharacterSet decimalDigitCharacterSet] invertedSet]].location != NSNotFound) return NO;
    NSInteger n = [num integerValue];
    if( n < 1) return NO;
    if( region) *region = ri;
    if( number) *number = n;
    return YES;
}

+ (BOOL) isDiscLabel:(NSString*) l
{
    NSArray *parts = [l componentsSeparatedByString: @"-"];
    return parts.count == 2 && [self parseLabel: [parts objectAtIndex: 0] region: NULL number: NULL] && [self parseLabel: [parts objectAtIndex: 1] region: NULL number: NULL];
}

+ (double) rankOfLabel:(NSString*) l
{
    NSInteger r, n;
    if( [self parseLabel: l region: &r number: &n]) return r * 1000 + n;
    if( [self isDiscLabel: l]) return [self rankOfLabel: [[l componentsSeparatedByString: @"-"] objectAtIndex: 0]] + 0.5;
    return -1;
}

- (void) successorOfRegion:(NSInteger*) r number:(NSInteger*) n
{
    // wie advance, aber auf uebergebenen Werten
    NSInteger sr = region, sn = number;
    region = *r; number = *n;
    [self advance];
    *r = region; *n = number;
    region = sr; number = sn;
}

- (void) noteNamesInViewer:(ViewerController*) v
{
    for( NSArray *slice in [v roiList])
        for( ROI *x in slice)
            if( [x type] == t2DPoint && x.name) [sekhmetKnownNames setObject: x.name forKey: [NSValue valueWithPointer: x]];
}

- (void) roiChanged:(NSNotification*) n
{
    ROI *roi = [n object];
    if( sekhmetRenumbering || [roi isKindOfClass: [ROI class]] == NO || [roi type] != t2DPoint) return;

    NSValue *key = [NSValue valueWithPointer: roi];
    NSString *old = [sekhmetKnownNames objectForKey: key];
    NSString *new = roi.name ? roi.name : @"";
    [sekhmetKnownNames setObject: new forKey: key];
    if( old == nil || [old isEqualToString: new]) return;
    if( [SekhmetSpine rankOfLabel: old] < 0) return;                 // vorher kein Wirbel-Label: nichts zu zaehlen

    NSInteger r, num;
    if( [SekhmetSpine parseLabel: new region: &r number: &num] == NO) return;   // frei benannt: nur dieses Label

    ROI *target = roi;
    if( roi.parentROI)                                               // MPR-Kopie: das Original in der 2D-Serie gilt
    {
        target = roi.parentROI;
        sekhmetRenumbering = YES;
        [target setName: new];
        sekhmetRenumbering = NO;
        [sekhmetKnownNames setObject: new forKey: [NSValue valueWithPointer: target]];
    }
    [self renumberFrom: target oldLabel: old region: r number: num];
}

// Alle Wirbel-Labels der Serie nach Rang ordnen, ab dem umbenannten Punkt neu durchzaehlen (Bandscheiben aus den Nachbarn)
- (void) renumberFrom:(ROI*) target oldLabel:(NSString*) old region:(NSInteger) r number:(NSInteger) num
{
    id wc = [[target curView] windowController];
    if( [wc isKindOfClass: [ViewerController class]] == NO) return;

    NSMutableArray *chain = [NSMutableArray array];
    for( NSArray *slice in [(ViewerController*) wc roiList])
        for( ROI *x in slice)
            if( [x type] == t2DPoint && (x == target || [SekhmetSpine rankOfLabel: x.name] >= 0)) [chain addObject: x];

    NSArray *sorted = [chain sortedArrayUsingComparator: ^NSComparisonResult( ROI *a, ROI *b) {
        double ra = (a == target) ? [SekhmetSpine rankOfLabel: old] : [SekhmetSpine rankOfLabel: a.name];
        double rb = (b == target) ? [SekhmetSpine rankOfLabel: old] : [SekhmetSpine rankOfLabel: b.name];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    NSUInteger idx = [sorted indexOfObjectIdenticalTo: target];
    if( idx == NSNotFound) return;

    NSInteger cr = r, cn = num;
    NSString *prevVertebra = nil;
    sekhmetRenumbering = YES;
    @try
    {
        for( NSUInteger i = idx; i < sorted.count; i++)
        {
            ROI *x = [sorted objectAtIndex: i];
            NSString *label;
            if( x != target && [SekhmetSpine isDiscLabel: x.name])
            {
                NSString *next = [self labelFor: cr number: cn];
                label = [NSString stringWithFormat: @"%@-%@", prevVertebra ? prevVertebra : next, next];
            }
            else
            {
                label = [self labelFor: cr number: cn];
                prevVertebra = label;
                [self successorOfRegion: &cr number: &cn];
            }
            if( [x.name isEqualToString: label] == NO) [x setName: label];
            [sekhmetKnownNames setObject: label forKey: [NSValue valueWithPointer: x]];
        }
    }
    @catch (NSException *e) { NSLog( @"SekhVet spine labels: recount: %@", e); }
    sekhmetRenumbering = NO;

    if( active)   // Zaehlwerk laeuft ab dem letzten neuen Label weiter
    {
        region = cr; number = cn;
        [lastVertebra release]; lastVertebra = [prevVertebra retain];
        [self updateNextLabel];
    }
    [[target curView] setNeedsDisplay: YES];
    NSLog( @"SekhVet spine labels: %@ -> %@, %d labels recounted from there", old, [self labelFor: r number: num], (int) (sorted.count - idx));
}

#pragma mark - Wirbelhoehe im MPR

// Alle Wirbel-Punkte der 2D-Serie mit 3D-Position (nur Wirbel, keine Bandscheiben)
+ (NSArray*) labelledPointsInViewer:(ViewerController*) viewer
{
    NSMutableArray *out = [NSMutableArray array];
    NSArray *roiList = [viewer roiList], *pixList = [viewer pixList];
    for( NSUInteger i = 0; i < roiList.count && i < pixList.count; i++)
    {
        for( ROI *r in [roiList objectAtIndex: i])
        {
            if( [r type] != t2DPoint || [self parseLabel: r.name region: NULL number: NULL] == NO) continue;
            float loc[3];
            [[pixList objectAtIndex: i] convertPixX: r.rect.origin.x pixY: r.rect.origin.y toDICOMCoords: loc pixelCenter: YES];
            [out addObject: [NSDictionary dictionaryWithObjectsAndKeys: r.name, @"name", [NSNumber numberWithDouble: [self rankOfLabel: r.name]], @"rank",
                             [NSNumber numberWithFloat: loc[0]], @"x", [NSNumber numberWithFloat: loc[1]], @"y", [NSNumber numberWithFloat: loc[2]], @"z", nil]];
        }
    }
    return [out sortedArrayUsingDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"rank" ascending: YES]]];
}

+ (NSString*) levelLabelForMPRView:(id) view
{
    MPRDCMView *v = view;
    ViewerController *viewer = [(id) [v windowController] viewer];
    DCMPix *pix = v.curDCM;
    if( viewer == nil || pix == nil) return nil;
    NSArray *pts = [self labelledPointsInViewer: viewer];
    if( pts.count == 0) return nil;

    float o[9]; [pix orientation: o];
    float n[3] = { o[6], o[7], o[8] };
    float c[3]; [pix convertPixX: pix.pwidth / 2. pixY: pix.pheight / 2. toDICOMCoords: c pixelCenter: YES];

    // Nur Ebenen, die quer zur Wirbelsaeule stehen (Richtung erstes -> letztes Label); bei einem einzigen Label jede Ebene
    if( pts.count >= 2)
    {
        NSDictionary *a = [pts objectAtIndex: 0], *b = [pts lastObject];
        float d[3] = { [[b objectForKey: @"x"] floatValue] - [[a objectForKey: @"x"] floatValue], [[b objectForKey: @"y"] floatValue] - [[a objectForKey: @"y"] floatValue], [[b objectForKey: @"z"] floatValue] - [[a objectForKey: @"z"] floatValue] };
        float len = sqrtf( d[0]*d[0] + d[1]*d[1] + d[2]*d[2]);
        if( len > 0 && fabsf( (d[0]*n[0] + d[1]*n[1] + d[2]*n[2]) / len) < 0.6) return nil;
    }

    NSDictionary *best = nil; float bestDist = 0, prevS = 0; NSMutableArray *spacings = [NSMutableArray array];
    for( NSUInteger i = 0; i < pts.count; i++)
    {
        NSDictionary *p = [pts objectAtIndex: i];
        float s = ([[p objectForKey: @"x"] floatValue] - c[0]) * n[0] + ([[p objectForKey: @"y"] floatValue] - c[1]) * n[1] + ([[p objectForKey: @"z"] floatValue] - c[2]) * n[2];
        if( i > 0) [spacings addObject: [NSNumber numberWithFloat: fabsf( s - prevS)]];
        prevS = s;
        if( best == nil || fabsf( s) < bestDist) { best = p; bestDist = fabsf( s); }
    }
    float typical = 20;   // mm, Rueckfall ohne Nachbarn
    if( spacings.count) { NSArray *sorted = [spacings sortedArrayUsingSelector: @selector(compare:)]; typical = [[sorted objectAtIndex: sorted.count / 2] floatValue]; }
    if( bestDist > typical * 1.5) return nil;   // ausserhalb des beschrifteten Abschnitts
    return [best objectForKey: @"name"];
}

+ (void) updateLevelAnnotationForMPRView:(id) view
{
    MPRDCMView *v = view;
    DCMPix *pix = v.curDCM;
    if( pix == nil) return;
    NSString *label = nil;
    @try { label = [self levelLabelForMPRView: v]; } @catch (NSException *e) { label = nil; }

    static NSString *marker = @"\u25B6 Spine level: ";
    NSDictionary *orig = pix.annotationsDictionary;
    NSArray *topLeft = [orig objectForKey: @"TopLeft"];
    BOOL hasMarker = NO;
    for( NSArray *annot in topLeft) if( [annot isKindOfClass: [NSArray class]] && annot.count == 1 && [[annot objectAtIndex: 0] hasPrefix: marker]) hasMarker = YES;
    if( label == nil && hasMarker == NO) return;

    // Kopie: das Dictionary ist mit dem 2D-Pix geteilt, die Hoehe gehoert nur in die MPR-Ansicht
    NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary: orig];
    NSMutableArray *tl = [NSMutableArray array];
    for( NSArray *annot in topLeft) if( !([annot isKindOfClass: [NSArray class]] && annot.count == 1 && [[annot objectAtIndex: 0] hasPrefix: marker])) [tl addObject: annot];
    if( label) [tl insertObject: [NSArray arrayWithObject: [marker stringByAppendingString: label]] atIndex: 0];
    [d setObject: tl forKey: @"TopLeft"];
    pix.annotationsDictionary = d;
}

#if SEKHVET_TESTHAKEN
+ (NSString*) debugSelfTest
{
    // Zaehl- und Parselogik ohne ROIs: Hund, vorwaerts
    SekhmetSpine *s = [self shared];
    NSMutableString *out = [NSMutableString string];
    NSInteger r, n;
    [out appendFormat: @"parse L3=%d(%d,%d) ", [self parseLabel: @"L3" region: &r number: &n], (int) r, (int) n];
    [out appendFormat: @"parse Cd4=%d(%d,%d) ", [self parseLabel: @"Cd4" region: &r number: &n], (int) r, (int) n];
    [out appendFormat: @"parse X1=%d disc(L1-L2)=%d disc(L1)=%d ", [self parseLabel: @"X1" region: NULL number: NULL], [self isDiscLabel: @"L1-L2"], [self isDiscLabel: @"L1"]];
    [out appendFormat: @"rank T13=%.1f L1=%.1f T13-L1=%.1f ", [self rankOfLabel: @"T13"], [self rankOfLabel: @"L1"], [self rankOfLabel: @"T13-L1"]];
    NSInteger sr = s->species, sreg = s->region, snum = s->number; BOOL sb = s->backwards;
    s->species = 0; s->backwards = NO;
    r = 1; n = 13; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"succ(T13)=%@ ", [s labelFor: r number: n]];
    r = 2; n = 7; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"succ(L7)=%@ ", [s labelFor: r number: n]];
    s->backwards = YES; r = 2; n = 1; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"pred(L1)=%@", [s labelFor: r number: n]];
    s->species = sr; s->region = sreg; s->number = snum; s->backwards = sb;
    return out;
}
#endif // SEKHVET_TESTHAKEN

- (void) viewerClosed:(NSNotification*) n
{
    // ROIs des schliessenden Viewers vergessen, sonst zeigt curView ins Leere
    id v = [n object];
    for( NSInteger i = (NSInteger) createdROIs.count - 1; i >= 0; i--)
    {
        ROI *r = [createdROIs objectAtIndex: i];
        if( [r curView] == nil || [[r curView] windowController] == v) [createdROIs removeObjectAtIndex: i];
    }
    if( [v isKindOfClass: [ViewerController class]])
        for( NSArray *slice in [(ViewerController*) v roiList])
            for( ROI *x in slice) [sekhmetKnownNames removeObjectForKey: [NSValue valueWithPointer: x]];
}

#pragma mark - Aktionen

- (void) toggleWithWindowController:(NSWindowController*) wc
{
    [self showWindow: nil];
    if( active == NO) [self start];   // ein zweiter Druck (z.B. im MPR nach dem 2D-Viewer) stoppt nicht mehr, sondern setzt nur das Werkzeug
    @try
    {
        if( [wc isKindOfClass: [ViewerController class]]) [[(ViewerController*) wc imageView] setCurrentTool: t2DPoint];
        else if( [wc isKindOfClass: [MPRController class]]) [(MPRController*) wc setToolIndex: t2DPoint];
    }
    @catch (NSException *e) { }
}

- (void) start
{
    active = YES;
    for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [self noteNamesInViewer: v];
    [self settingsChanged: nil];
}

- (void) stop
{
    active = NO;
    [self updateNextLabel];
}

- (void) undo
{
    ROI *last = [createdROIs lastObject];
    if( last == nil) return;
    [[last retain] autorelease];
    [createdROIs removeLastObject];
    [self retreat];
    if( [last.name rangeOfString: @"-"].location != NSNotFound) [self advance]; // Bandscheibe hat nicht gezaehlt
    // Horos loescht ROIs nur ueber ViewerController deleteROI: (die Notification allein zeichnet nur neu)
    id wc = [[last curView] windowController];
    if( [wc isKindOfClass: [ViewerController class]]) [(ViewerController*) wc deleteROI: last];
    else for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [v deleteROI: last];
    [self updateNextLabel];
}

- (IBAction) toggle:(id) sender
{
    if( active) [self stop]; else [self start];
}

- (IBAction) undoAction:(id) sender { [self undo]; }

- (IBAction) clearAll:(id) sender
{
    if( createdROIs.count == 0) return;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Delete %d spine labels?", nil), (int) createdROIs.count]];
    [a addButtonWithTitle: NSLocalizedString( @"Delete", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    while( createdROIs.count) [self undo];
}

- (IBAction) settingsChanged:(id) sender
{
    species = [speciesPopup indexOfSelectedItem];
    region = [regionPopup indexOfSelectedItem];
    number = MAX( 1, [numberField integerValue]);
    backwards = ([backwardsButton state] == NSControlStateValueOn);
    [lastVertebra release]; lastVertebra = nil;
    [self updateNextLabel];
}

@end
