/*=========================================================================
 Sekhmet — Spine Labeling (Vet). Siehe Header.
 ============================================================================*/

#import "SekhmetSpine.h"
#import "SekhmetDisplayPanel.h"
#import "ROI.h"
#import "DCMView.h"
#import "ViewerController.h"
#import "MPRController.h"
#import "Window3DController.h"
#import "MPRDCMView.h"
#import "DCMPix.h"
#import "DicomDatabase.h"
#import "StringTexture.h"
#import "Notifications.h"
#include <OpenGL/gl.h>
#include <OpenGL/glext.h>

static SekhmetSpine *sekhmetSpine = nil;
static NSMutableDictionary *sekhmetKnownNames = nil;   // NSValue(ROI*) -> zuletzt gesehener Name (erkennt Umbenennungen)
static BOOL sekhmetRenumbering = NO;
static NSString* const kRegionLetters[ 5] = { @"C", @"T", @"L", @"S", @"Cd" };
// Wirbelformel je Tierart: Hund/Katze, Kaninchen, Pferd (Cd offen)
static const int kCounts[ 3][ 5] = { { 7, 13, 7, 3, 99 }, { 7, 12, 7, 4, 99 }, { 7, 18, 6, 5, 99 } };
// SekhVet Paket BT: zwei Schalter statt des Popups. Marker = die Punkte und ihre Beschriftung ueberhaupt (Vorgabe an);
// Elsewhere = Punkte auch ausserhalb der sagittalen Ansicht (Vorgabe AUS: dort steht nur die Hoehe als Eck-Label).
static NSString* const kMarkersOffKey = @"SekhmetSpineMarkersHidden";
static NSString* const kElsewhereKey = @"SekhmetSpinePointsElsewhere";
static NSString* const kSpeciesKey = @"SekhmetSpineSpecies";
static NSString* const kColorKey = @"SekhmetSpineTextColor";   // SekhVet Paket BU: "r g b" (0..1), Vorgabe Gruen

@implementation SekhmetSpine

+ (SekhmetSpine*) shared
{
    if( sekhmetSpine == nil) sekhmetSpine = [[SekhmetSpine alloc] init];
    return sekhmetSpine;
}

+ (BOOL) isActive { return sekhmetSpine != nil && sekhmetSpine->active; }

// SekhVet Paket BU: Farbe der Wirbel-Beschriftung (Eck-Label, projizierte Marker, Namen der Punkt-ROIs)
+ (void) labelColorR:(float*) r g:(float*) g b:(float*) b
{
    float c[ 3] = { 0.35f, 1.0f, 0.45f };
    NSString *s = [[NSUserDefaults standardUserDefaults] stringForKey: kColorKey];
    if( s.length) sscanf( [s UTF8String], "%f %f %f", &c[ 0], &c[ 1], &c[ 2]);
    *r = c[ 0]; *g = c[ 1]; *b = c[ 2];
}

+ (NSArray*) speciesNames
{
    return [NSArray arrayWithObjects: NSLocalizedString( @"Dog / Cat (7-13-7-3)", nil), NSLocalizedString( @"Rabbit (7-12-7-4)", nil), NSLocalizedString( @"Horse (7-18-6-5)", nil), nil];
}

+ (NSArray*) regionNames
{
    return [NSArray arrayWithObjects: @"C — cervical", @"T — thoracic", @"L — lumbar", @"S — sacral", @"Cd — caudal", nil];
}

// Der Zeichen-Haken muss leben, sobald die App laeuft -- auch wenn das Panel nie geoeffnet wurde
+ (void) load
{
    [[NSNotificationCenter defaultCenter] addObserverForName: NSApplicationDidFinishLaunchingNotification object: nil queue: nil usingBlock: ^(NSNotification *n) { [SekhmetSpine shared]; }];
}

- (id) init
{
    NSPanel *w = [[[NSPanel alloc] initWithContentRect: NSMakeRect( 0, 0, 340, 526)
                                             styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow
                                               backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"Spine Labeling (SekhVet)", nil)];
    [w setReleasedWhenClosed: NO];
    [w setFloatingPanel: YES];
    [w setBecomesKeyOnlyIfNeeded: YES];

    self = [super initWithWindow: w];
    if( self)
    {
        [w setDelegate: self];   // SekhVet Paket BU: Schliessen des Panels beendet das Beschriften
        createdROIs = [[NSMutableArray alloc] init];
        store = [[NSMutableDictionary alloc] init];
        roiSeries = [[NSMutableDictionary alloc] init];
        notedViewers = [[NSMutableSet alloc] init];
        region = 2; number = 1; backwards = NO;
        NSInteger sp = MAX( 0, MIN( 2, [[NSUserDefaults standardUserDefaults] integerForKey: kSpeciesKey]));
        for( int i = 0; i < 5; i++) counts[ i] = kCounts[ sp][ i];
        [self buildUI];
        [speciesPopup selectItemAtIndex: sp];
        [self showFormula];
        [self updateNextLabel];
        NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
        [nc addObserver: self selector: @selector(roiRemoved:) name: OsirixRemoveROINotification object: nil];
        [nc addObserver: self selector: @selector(viewerClosed:) name: OsirixCloseViewerNotification object: nil];
        [nc addObserver: self selector: @selector(roiChanged:) name: OsirixROIChangeNotification object: nil];
        [nc addObserver: self selector: @selector(drawObjects:) name: OsirixDrawObjectsNotification object: nil];
        [nc addObserver: self selector: @selector(windowBecameKey:) name: NSWindowDidBecomeKeyNotification object: nil];
        if( sekhmetKnownNames == nil) sekhmetKnownNames = [[NSMutableDictionary alloc] init];
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [createdROIs release]; [lastVertebra release]; [store release]; [roiSeries release]; [notedViewers release];
    [currentStudyUID release]; [tableRows release];
    [super dealloc];
}

#pragma mark - UI

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

- (NSPopUpButton*) popup:(NSArray*) titles frame:(NSRect) r action:(SEL) sel
{
    NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame: r pullsDown: NO] autorelease];
    [p addItemsWithTitles: titles];
    [p setTarget: self]; [p setAction: sel];
    return p;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float y = 526 - 34;

    [cv addSubview: [self label: NSLocalizedString( @"Species:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    speciesPopup = [self popup: [SekhmetSpine speciesNames] frame: NSMakeRect( 90, y - 2, 234, 26) action: @selector(speciesChanged:)];
    [cv addSubview: speciesPopup];

    // Wirbelformel: Vorgabe aus der Tierart, je Studie aenderbar (Uebergangswirbel: T12/T14, L6/L8, S2/S4)
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Formula:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    for( int i = 0; i < 4; i++)
    {
        [cv addSubview: [self label: kRegionLetters[ i] frame: NSMakeRect( 92 + i * 58, y + 2, 14, 20)]];
        formulaFields[ i] = [[[NSTextField alloc] initWithFrame: NSMakeRect( 106 + i * 58, y, 34, 22)] autorelease];
        [formulaFields[ i] setTarget: self]; [formulaFields[ i] setAction: @selector(formulaChanged:)];
        [formulaFields[ i] setToolTip: NSLocalizedString( @"Number of vertebrae in this region for this study — change it for transitional vertebrae (e.g. L 6 or 8). Counting and renumbering follow it.", nil)];
        [cv addSubview: formulaFields[ i]];
    }

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Start at:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    regionPopup = [self popup: [SekhmetSpine regionNames] frame: NSMakeRect( 90, y - 2, 150, 26) action: @selector(settingsChanged:)];
    [regionPopup selectItemAtIndex: 2];
    [cv addSubview: regionPopup];
    numberField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 250, y, 50, 22)] autorelease];
    [numberField setIntegerValue: 1];
    [numberField setTarget: self]; [numberField setAction: @selector(settingsChanged:)];
    [cv addSubview: numberField];

    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Direction:", nil) frame: NSMakeRect( 16, y + 2, 70, 20)]];
    directionPopup = [self popup: [NSArray arrayWithObjects: NSLocalizedString( @"Automatic (from the first two clicks)", nil), NSLocalizedString( @"Cranial → caudal", nil), NSLocalizedString( @"Caudal → cranial", nil), nil]
                           frame: NSMakeRect( 90, y - 2, 234, 26) action: @selector(settingsChanged:)];
    [cv addSubview: directionPopup];

    y -= 34;
    nextLabel = [self label: @"" frame: NSMakeRect( 16, y, 308, 24)];
    [nextLabel setFont: [NSFont boldSystemFontOfSize: 16]];
    [cv addSubview: nextLabel];

    y -= 38;
    startButton = [self button: NSLocalizedString( @"Start", nil) frame: NSMakeRect( 12, y, 100, 30) action: @selector(toggle:)];
    [cv addSubview: startButton];
    [cv addSubview: [self button: NSLocalizedString( @"⌫ Undo last", nil) frame: NSMakeRect( 112, y, 120, 30) action: @selector(undoAction:)]];
    [cv addSubview: [self button: NSLocalizedString( @"Delete all", nil) frame: NSMakeRect( 232, y, 96, 30) action: @selector(clearAll:)]];

    y -= 36;
    NSTextField *hint = [self label: NSLocalizedString( @"Click = vertebra · click between two labels = disc (Alt-click forces a disc) · ⌫ = undo · Esc = stop", nil) frame: NSMakeRect( 16, y, 312, 32)];
    [hint setFont: [NSFont systemFontOfSize: 11]];
    [[hint cell] setWraps: YES];
    [cv addSubview: hint];

    // Liste der Labels dieser Studie: Klick = hinspringen, Doppelklick = umbenennen (zaehlt die folgenden neu)
    y -= 26;
    listStatus = [self label: @"" frame: NSMakeRect( 16, y, 312, 18)];
    [listStatus setFont: [NSFont boldSystemFontOfSize: 12]];
    [cv addSubview: listStatus];
    y -= 150;
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 16, y, 308, 146)] autorelease];
    labelTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 308, 146)] autorelease];
    NSTableColumn *c1 = [[[NSTableColumn alloc] initWithIdentifier: @"label"] autorelease];
    [[c1 headerCell] setStringValue: NSLocalizedString( @"Label", nil)]; [c1 setWidth: 80]; [c1 setEditable: YES];
    NSTableColumn *c2 = [[[NSTableColumn alloc] initWithIdentifier: @"seriesName"] autorelease];
    [[c2 headerCell] setStringValue: NSLocalizedString( @"Set in series", nil)]; [c2 setWidth: 205]; [c2 setEditable: NO];
    [labelTable addTableColumn: c1]; [labelTable addTableColumn: c2];
    [labelTable setDataSource: self]; [labelTable setDelegate: self];
    [labelTable setUsesAlternatingRowBackgroundColors: YES];
    [sv setDocumentView: labelTable]; [sv setHasVerticalScroller: YES]; [sv setBorderType: NSBezelBorder];
    [cv addSubview: sv];

    y -= 34;
    [cv addSubview: [self button: NSLocalizedString( @"Delete label", nil) frame: NSMakeRect( 12, y, 120, 30) action: @selector(deleteSelectedLabel:)]];
    [cv addSubview: [self label: NSLocalizedString( @"Label colour:", nil) frame: NSMakeRect( 176, y + 7, 90, 18)]];
    float lc[ 3]; [SekhmetSpine labelColorR: &lc[ 0] g: &lc[ 1] b: &lc[ 2]];
    colorWell = [[[NSColorWell alloc] initWithFrame: NSMakeRect( 270, y + 3, 54, 24)] autorelease];   // SekhVet Paket BU
    [colorWell setColor: [NSColor colorWithCalibratedRed: lc[ 0] green: lc[ 1] blue: lc[ 2] alpha: 1.0]];
    [colorWell setToolTip: NSLocalizedString( @"Colour of the vertebra labels, the level shown across the spine and the projected points", nil)];
    [colorWell setTarget: self]; [colorWell setAction: @selector(colorChanged:)];
    [cv addSubview: colorWell];

    y -= 26;
    markersButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 16, y, 312, 18)] autorelease];
    [markersButton setButtonType: NSButtonTypeSwitch];
    [markersButton setTitle: NSLocalizedString( @"Show the label points (sagittal view)", nil)];
    [markersButton setFont: [NSFont systemFontOfSize: 12]];
    [markersButton setTarget: self]; [markersButton setAction: @selector(visibilityChanged:)];
    [markersButton setState: [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey] ? NSControlStateValueOff : NSControlStateValueOn];
    [cv addSubview: markersButton];
    y -= 22;
    elsewhereButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 16, y, 312, 18)] autorelease];
    [elsewhereButton setButtonType: NSButtonTypeSwitch];
    [elsewhereButton setTitle: NSLocalizedString( @"… also in the transverse and dorsal views", nil)];
    [elsewhereButton setFont: [NSFont systemFontOfSize: 12]];
    [elsewhereButton setToolTip: NSLocalizedString( @"Off: the other views show only the level (e.g. L3, L3-L4). On: the points appear there too and can be dragged there.", nil)];
    [elsewhereButton setTarget: self]; [elsewhereButton setAction: @selector(visibilityChanged:)];
    [elsewhereButton setState: [[NSUserDefaults standardUserDefaults] boolForKey: kElsewhereKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [cv addSubview: elsewhereButton];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: NO]; // SekhVet: innerhalb der Viewer-Flaeche
    [super showWindow: sender];
    [self reloadTable];
}

- (void) showFormula
{
    for( int i = 0; i < 4; i++) [formulaFields[ i] setIntegerValue: counts[ i]];
}

#pragma mark - Studie und Speicher

+ (ViewerController*) viewerForView:(DCMView*) view
{
    id wc = [[view window] windowController];
    if( [wc isKindOfClass: [ViewerController class]]) return wc;
    if( [wc isKindOfClass: [Window3DController class]]) { id v = [(Window3DController*) wc viewer]; if( [v isKindOfClass: [ViewerController class]]) return v; }
    return nil;
}

+ (NSString*) seriesUIDOfViewer:(ViewerController*) v
{
    NSString *uid = nil;
    @try { uid = [[v currentSeries] valueForKey: @"seriesDICOMUID"]; } @catch (NSException *e) { }
    return uid.length ? uid : nil;
}

+ (BOOL) viewerIsAlive:(ViewerController*) v
{
    if( v == nil) return NO;
    for( ViewerController *x in [ViewerController getDisplayed2DViewers])
        if( x == v) return [x windowWillClose] == NO;
    return NO;
}

- (NSString*) storeDirectory
{
    NSString *base = [[DicomDatabase activeLocalDatabase] baseDirPath];
    if( base.length == 0) return nil;
    NSString *dir = [base stringByAppendingPathComponent: @"SPINE"];
    [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: NULL];
    return dir;
}

- (NSString*) pathForStudy:(NSString*) studyUID
{
    NSMutableCharacterSet *ok = [NSMutableCharacterSet alphanumericCharacterSet]; [ok addCharactersInString: @".-_"];
    NSString *safe = [[studyUID componentsSeparatedByCharactersInSet: [ok invertedSet]] componentsJoinedByString: @"_"];
    NSString *dir = [self storeDirectory];
    return dir && safe.length ? [dir stringByAppendingPathComponent: [safe stringByAppendingPathExtension: @"json"]] : nil;
}

- (NSMutableDictionary*) dataForStudy:(NSString*) studyUID
{
    if( studyUID.length == 0) return nil;
    NSMutableDictionary *d = [store objectForKey: studyUID];
    if( d) return d;
    d = [NSMutableDictionary dictionary];
    NSMutableArray *labels = [NSMutableArray array];
    NSString *path = [self pathForStudy: studyUID];
    NSData *raw = path ? [NSData dataWithContentsOfFile: path] : nil;
    id json = raw.length ? [NSJSONSerialization JSONObjectWithData: raw options: 0 error: NULL] : nil;
    if( [json isKindOfClass: [NSDictionary class]])
    {
        for( NSDictionary *l in [json objectForKey: @"labels"])
            if( [l isKindOfClass: [NSDictionary class]] && [SekhmetSpine rankOfLabel: [l objectForKey: @"label"]] >= 0) [labels addObject: l];
        NSArray *f = [json objectForKey: @"formula"];
        if( [f isKindOfClass: [NSArray class]] && f.count == 4) [d setObject: f forKey: @"formula"];
    }
    [d setObject: labels forKey: @"labels"];
    [store setObject: d forKey: studyUID];
    return d;
}

- (void) saveStudy:(NSString*) studyUID
{
    NSMutableDictionary *d = [store objectForKey: studyUID];
    NSString *path = [self pathForStudy: studyUID];
    if( d == nil || path == nil) return;
    if( [[d objectForKey: @"labels"] count] == 0 && [d objectForKey: @"formula"] == nil) { [[NSFileManager defaultManager] removeItemAtPath: path error: NULL]; return; }
    NSData *raw = [NSJSONSerialization dataWithJSONObject: d options: NSJSONWritingPrettyPrinted error: NULL];
    if( raw) [raw writeToFile: path atomically: YES];
}

- (void) redrawAll
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [v needsDisplayUpdate];
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] && [w isVisible]) [[w contentView] setNeedsDisplay: YES];
    }
}

// Alle Wirbel- und Bandscheiben-Punkte der Serie dieses Viewers in die Studienliste uebernehmen (ersetzt deren bisherige Eintraege).
// Die ROIs sind die Wahrheit; aufgerufen nur nach ROI-Ereignissen in diesem Viewer oder wenn er Wirbel-ROIs mitbringt.
- (void) syncFromViewer:(ViewerController*) v
{
    if( [SekhmetSpine viewerIsAlive: v] == NO) return;
    NSString *studyUID = [v studyInstanceUID], *seriesUID = [SekhmetSpine seriesUIDOfViewer: v];
    if( studyUID.length == 0 || seriesUID.length == 0) return;

    NSString *seriesName = @"";
    @try { seriesName = [[v currentSeries] valueForKey: @"name"]; } @catch (NSException *e) { }
    NSMutableArray *fresh = [NSMutableArray array];
    NSArray *roiList = [v roiList], *pixList = [v pixList];
    for( NSUInteger i = 0; i < roiList.count && i < pixList.count; i++)
    {
        DCMPix *pix = [pixList objectAtIndex: i];
        for( ROI *r in [roiList objectAtIndex: i])
        {
            if( [r type] != t2DPoint || [SekhmetSpine rankOfLabel: r.name] < 0) continue;
            float loc[ 3];
            [pix convertPixX: r.rect.origin.x pixY: r.rect.origin.y toDICOMCoords: loc pixelCenter: YES];
            [fresh addObject: [NSDictionary dictionaryWithObjectsAndKeys: r.name, @"label",
                               [NSNumber numberWithFloat: loc[ 0]], @"x", [NSNumber numberWithFloat: loc[ 1]], @"y", [NSNumber numberWithFloat: loc[ 2]], @"z",
                               pix.frameofReferenceUID ? pix.frameofReferenceUID : @"", @"for", seriesUID, @"series", seriesName ? seriesName : @"", @"seriesName", nil]];
            [roiSeries setObject: seriesUID forKey: [NSValue valueWithPointer: r]];
            if( r.name) [sekhmetKnownNames setObject: r.name forKey: [NSValue valueWithPointer: r]];
            BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey];
            if( r.hidden != hide) r.hidden = hide;
        }
    }
    NSMutableDictionary *d = [self dataForStudy: studyUID];
    NSMutableArray *labels = [d objectForKey: @"labels"];
    for( NSInteger i = (NSInteger) labels.count - 1; i >= 0; i--)
        if( [[[labels objectAtIndex: i] objectForKey: @"series"] isEqualToString: seriesUID]) [labels removeObjectAtIndex: i];
    [labels addObjectsFromArray: fresh];
    [self saveStudy: studyUID];
    [self reloadTable];
    [self redrawAll];
}

- (void) syncScheduled:(NSDictionary*) info
{
    ViewerController *v = [[info objectForKey: @"viewer"] pointerValue];
    if( [SekhmetSpine viewerIsAlive: v] == NO) return;                                    // inzwischen geschlossen: Bestand bleibt
    if( [[info objectForKey: @"series"] isEqualToString: [SekhmetSpine seriesUIDOfViewer: v]] == NO) return;   // Serie gewechselt: die Loesch-Meldungen galten der alten
    [self syncFromViewer: v];
}

- (void) scheduleSyncForViewer:(ViewerController*) v
{
    NSString *seriesUID = [SekhmetSpine seriesUIDOfViewer: v];
    if( v == nil || seriesUID == nil) return;
    NSDictionary *info = [NSDictionary dictionaryWithObjectsAndKeys: [NSValue valueWithPointer: v], @"viewer", seriesUID, @"series", nil];
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(syncScheduled:) object: nil];
    [self performSelector: @selector(syncScheduled:) withObject: info afterDelay: 0.25];
}

// Ein Viewer, der zum ersten Mal zeichnet und Wirbel-ROIs mitbringt (aus frueheren Sitzungen oder Builds), liefert seinen Bestand
- (void) noteViewerOnce:(ViewerController*) v
{
    NSString *seriesUID = [SekhmetSpine seriesUIDOfViewer: v];
    if( seriesUID == nil) return;
    NSString *key = [NSString stringWithFormat: @"%p|%@", v, seriesUID];
    if( [notedViewers containsObject: key]) return;
    [notedViewers addObject: key];
    for( NSArray *slice in [v roiList])
        for( ROI *r in slice)
            if( [r type] == t2DPoint && [SekhmetSpine rankOfLabel: r.name] >= 0) { [self scheduleSyncForViewer: v]; return; }
}

#pragma mark - Zaehlwerk

- (int) countForRegion:(NSInteger) r
{
    if( r < 0 || r > 4) return 99;
    return (int) counts[ r];
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

- (void) successorOfRegion:(NSInteger*) r number:(NSInteger*) n
{
    // wie advance, aber auf uebergebenen Werten
    NSInteger sr = region, sn = number;
    region = *r; number = *n;
    [self advance];
    *r = region; *n = number;
    region = sr; number = sn;
}

// Bandscheibe, wenn der Klick zwischen zwei benachbarten Wirbelpunkten der Studie liegt (mittleres Drittel der Strecke,
// seitlich hoechstens die halbe Strecke entfernt) und es dieses Label noch nicht gibt
- (NSString*) discLabelForPoint:(float*) p study:(NSString*) studyUID frameOfReference:(NSString*) forUID
{
    NSMutableArray *vert = [NSMutableArray array];
    NSMutableSet *names = [NSMutableSet set];
    for( NSDictionary *l in [[self dataForStudy: studyUID] objectForKey: @"labels"])
    {
        NSString *f = [l objectForKey: @"for"];
        if( forUID.length && f.length && [f isEqualToString: forUID] == NO) continue;
        [names addObject: [l objectForKey: @"label"]];
        if( [SekhmetSpine parseLabel: [l objectForKey: @"label"] region: NULL number: NULL]) [vert addObject: l];
    }
    [vert sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        double ra = [SekhmetSpine rankOfLabel: [a objectForKey: @"label"]], rb = [SekhmetSpine rankOfLabel: [b objectForKey: @"label"]];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    for( NSUInteger i = 0; i + 1 < vert.count; i++)
    {
        NSDictionary *a = [vert objectAtIndex: i], *b = [vert objectAtIndex: i + 1];
        float A[ 3] = { [[a objectForKey: @"x"] floatValue], [[a objectForKey: @"y"] floatValue], [[a objectForKey: @"z"] floatValue] };
        float d[ 3] = { [[b objectForKey: @"x"] floatValue] - A[ 0], [[b objectForKey: @"y"] floatValue] - A[ 1], [[b objectForKey: @"z"] floatValue] - A[ 2] };
        float len2 = d[ 0]*d[ 0] + d[ 1]*d[ 1] + d[ 2]*d[ 2];
        if( len2 < 1) continue;
        float q[ 3] = { p[ 0] - A[ 0], p[ 1] - A[ 1], p[ 2] - A[ 2] };
        float t = (q[ 0]*d[ 0] + q[ 1]*d[ 1] + q[ 2]*d[ 2]) / len2;
        if( t < 0.33f || t > 0.67f) continue;
        float off[ 3] = { q[ 0] - t*d[ 0], q[ 1] - t*d[ 1], q[ 2] - t*d[ 2] };
        if( off[ 0]*off[ 0] + off[ 1]*off[ 1] + off[ 2]*off[ 2] > 0.25f * len2) continue;
        NSString *disc = [NSString stringWithFormat: @"%@-%@", [a objectForKey: @"label"], [b objectForKey: @"label"]];
        if( [names containsObject: disc]) return nil;
        return disc;
    }
    return nil;
}

- (NSString*) takeLabelWithModifiers:(NSUInteger) flags point:(float*) p study:(NSString*) studyUID frameOfReference:(NSString*) forUID
{
    if( flags & NSEventModifierFlagOption)
    {
        // Bandscheibe zwischen dem letzten Wirbel und dem naechsten; zaehlt nicht weiter
        NSString *next = [self peekLabel];
        if( lastVertebra.length == 0) return [NSString stringWithFormat: @"%@-%@", next, next];
        return backwards ? [NSString stringWithFormat: @"%@-%@", next, lastVertebra] : [NSString stringWithFormat: @"%@-%@", lastVertebra, next];
    }
    if( p)
    {
        NSString *disc = [self discLabelForPoint: p study: studyUID frameOfReference: forUID];
        if( disc) return disc;

        // Richtung aus den ersten zwei Klicks: DICOM +z zeigt nach kranial (Superior). Geht der zweite Klick nach kranial,
        // wird rueckwaerts gezaehlt. Nur wenn die Strecke ueberwiegend laengs liegt; sonst bleibt die bisherige Richtung.
        if( [directionPopup indexOfSelectedItem] == 0 && placedInRun == 1 && lastVertebra.length)
        {
            float v[ 3] = { p[ 0] - lastPoint[ 0], p[ 1] - lastPoint[ 1], p[ 2] - lastPoint[ 2] };
            float len = sqrtf( v[ 0]*v[ 0] + v[ 1]*v[ 1] + v[ 2]*v[ 2]);
            if( len > 2 && fabsf( v[ 2]) >= 0.5f * len)
            {
                BOOL wantBackwards = v[ 2] > 0;
                if( wantBackwards != backwards)
                {
                    NSInteger r, n;
                    backwards = wantBackwards;
                    if( [SekhmetSpine parseLabel: lastVertebra region: &r number: &n]) { [self successorOfRegion: &r number: &n]; region = r; number = n; }
                }
            }
        }
        lastPoint[ 0] = p[ 0]; lastPoint[ 1] = p[ 1]; lastPoint[ 2] = p[ 2];
    }
    NSString *l = [self peekLabel];
    [lastVertebra release]; lastVertebra = [l retain];
    placedInRun++;
    [self advance];
    [self updateNextLabel];
    return l;
}

- (void) updateNextLabel
{
    NSString *dir = backwards ? NSLocalizedString( @"→ cranial", nil) : NSLocalizedString( @"→ caudal", nil);
    if( [directionPopup indexOfSelectedItem] == 0 && placedInRun < 2) dir = NSLocalizedString( @"direction: 2nd click", nil);
    [nextLabel setStringValue: [NSString stringWithFormat: NSLocalizedString( @"%@  Next: %@   (%@)", nil), active ? @"●" : @"○", [self peekLabel], dir]];
    [startButton setTitle: active ? NSLocalizedString( @"Stop", nil) : NSLocalizedString( @"Start", nil)];
}

#pragma mark - Haken

+ (void) willCreatePointROI:(ROI*) roi inView:(DCMView*) view modifiers:(NSUInteger) flags
{
    if( [self isActive] == NO) return;
    SekhmetSpine *s = sekhmetSpine;

    // Die ROI hat hier noch keine Lage: Klickpunkt aus dem laufenden Ereignis, wie DCMView mouseDown ihn rechnet
    float loc[ 3]; float *p = NULL;
    NSString *studyUID = nil, *forUID = nil;
    NSEvent *ev = [NSApp currentEvent];
    DCMPix *pix = view.curDCM;
    if( pix && ev && [ev window] == [view window])
    {
        NSPoint pt = [view ConvertFromNSView2GL: [view convertPoint: [ev locationInWindow] fromView: nil]];
        [pix convertPixX: pt.x pixY: pt.y toDICOMCoords: loc pixelCenter: YES];
        p = loc;
        forUID = pix.frameofReferenceUID;
    }
    ViewerController *viewer = [self viewerForView: view];
    studyUID = [viewer studyInstanceUID];
    [s setCurrentStudy: studyUID];

    NSString *l = [s takeLabelWithModifiers: flags point: p study: studyUID frameOfReference: forUID];
    [ROI setDefaultName: l];            // DCMView vergibt gleich diesen Namen
    [ROI performSelector: @selector(setDefaultName:) withObject: nil afterDelay: 0];
    if( [view isKindOfClass: NSClassFromString( @"MPRDCMView")] == NO)
    {
        [s->createdROIs addObject: roi];   // 2D-Viewer: die ROI ist bereits die persistente
        [s scheduleSyncForViewer: viewer];
    }
}

+ (void) notePersistentROI:(ROI*) roi
{
    if( roi == nil || sekhmetSpine == nil) return;
    if( [self isActive]) [sekhmetSpine->createdROIs addObject: roi];
    // auch ohne aktives Werkzeug: ein im MPR verschobener Wirbelpunkt wird geloescht und neu angelegt
    if( [self rankOfLabel: roi.name] >= 0)
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
            for( NSArray *slice in [v roiList])
                if( [slice indexOfObjectIdenticalTo: roi] != NSNotFound) { [sekhmetSpine scheduleSyncForViewer: v]; return; }
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
    id obj = [n object];
    NSValue *key = [NSValue valueWithPointer: obj];
    NSString *seriesUID = [[[roiSeries objectForKey: key] retain] autorelease];
    [createdROIs removeObjectIdenticalTo: obj];
    [sekhmetKnownNames removeObjectForKey: key];
    [roiSeries removeObjectForKey: key];
    if( seriesUID == nil) return;
    // Nur echte Loeschungen zaehlen: der Viewer zeigt noch dieselbe Serie und schliesst nicht (ROI dealloc meldet sich genauso)
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        if( [v windowWillClose] == NO && [seriesUID isEqualToString: [SekhmetSpine seriesUIDOfViewer: v]]) { [self scheduleSyncForViewer: v]; return; }
}

#pragma mark - Umbenennen mit Neuzaehlung

+ (BOOL) parseLabel:(NSString*) l region:(NSInteger*) region number:(NSInteger*) number
{
    if( [l isKindOfClass: [NSString class]] == NO || l.length < 2) return NO;
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
    if( [l isKindOfClass: [NSString class]] == NO) return NO;
    NSArray *parts = [l componentsSeparatedByString: @"-"];
    return parts.count == 2 && [self parseLabel: [parts objectAtIndex: 0] region: NULL number: NULL] && [self parseLabel: [parts objectAtIndex: 1] region: NULL number: NULL];
}

+ (double) rankOfLabel:(NSString*) l
{
    NSInteger r, n;
    if( [self parseLabel: l region: &r number: &n]) return r * 1000 + n;
    if( [self isDiscLabel: l])
    {
        NSArray *parts = [l componentsSeparatedByString: @"-"];
        return MIN( [self rankOfLabel: [parts objectAtIndex: 0]], [self rankOfLabel: [parts objectAtIndex: 1]]) + 0.5;
    }
    return -1;
}

- (void) noteNamesInViewer:(ViewerController*) v
{
    NSString *seriesUID = [SekhmetSpine seriesUIDOfViewer: v];
    for( NSArray *slice in [v roiList])
        for( ROI *x in slice)
            if( [x type] == t2DPoint && x.name)
            {
                [sekhmetKnownNames setObject: x.name forKey: [NSValue valueWithPointer: x]];
                if( seriesUID && [SekhmetSpine rankOfLabel: x.name] >= 0) [roiSeries setObject: seriesUID forKey: [NSValue valueWithPointer: x]];
            }
}

- (void) roiChanged:(NSNotification*) n
{
    ROI *roi = [n object];
    if( sekhmetRenumbering || [roi isKindOfClass: [ROI class]] == NO || [roi type] != t2DPoint) return;

    NSValue *key = [NSValue valueWithPointer: roi];
    NSString *old = [[[sekhmetKnownNames objectForKey: key] retain] autorelease];
    NSString *new = roi.name ? roi.name : @"";
    [sekhmetKnownNames setObject: new forKey: key];

    BOOL spine = [SekhmetSpine rankOfLabel: new] >= 0 || (old && [SekhmetSpine rankOfLabel: old] >= 0);
    ViewerController *viewer = spine ? [SekhmetSpine viewerForView: [roi curView]] : nil;
    if( viewer && roi.parentROI == nil) [self scheduleSyncForViewer: viewer];   // verschoben oder umbenannt: Studienliste folgt

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
    if( viewer) [self scheduleSyncForViewer: viewer];
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

    // Neuzaehlung laeuft immer kranial -> kaudal, unabhaengig von der Setz-Richtung
    BOOL savedBackwards = backwards; backwards = NO;
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
    backwards = savedBackwards;

    if( active && backwards == NO)   // Zaehlwerk laeuft ab dem letzten neuen Label weiter
    {
        region = cr; number = cn;
        [lastVertebra release]; lastVertebra = [prevVertebra retain];
        [self updateNextLabel];
    }
    [[target curView] setNeedsDisplay: YES];
    NSLog( @"SekhVet spine labels: %@ -> %@, %d labels recounted from there", old, [self labelFor: r number: num], (int) (sorted.count - idx));
}

#pragma mark - Hoehe und Zeichnen

+ (NSString*) levelForPosition:(float) t points:(NSArray*) pts
{
    if( pts.count == 0) return nil;
    if( pts.count == 1)
        return fabsf( t - [[[pts objectAtIndex: 0] objectForKey: @"t"] floatValue]) <= 10 ? [[pts objectAtIndex: 0] objectForKey: @"label"] : nil;

    float first = [[[pts objectAtIndex: 0] objectForKey: @"t"] floatValue], last = [[[pts lastObject] objectForKey: @"t"] floatValue];
    float firstGap = [[[pts objectAtIndex: 1] objectForKey: @"t"] floatValue] - first;
    float lastGap = last - [[[pts objectAtIndex: pts.count - 2] objectForKey: @"t"] floatValue];
    if( t < first) return (first - t) <= 0.5f * firstGap ? [[pts objectAtIndex: 0] objectForKey: @"label"] : nil;
    if( t > last) return (t - last) <= 0.5f * lastGap ? [[pts lastObject] objectForKey: @"label"] : nil;
    for( NSUInteger i = 0; i + 1 < pts.count; i++)
    {
        NSDictionary *a = [pts objectAtIndex: i], *b = [pts objectAtIndex: i + 1];
        float ta = [[a objectForKey: @"t"] floatValue], tb = [[b objectForKey: @"t"] floatValue];
        if( t < ta || t > tb) continue;
        float f = tb > ta ? (t - ta) / (tb - ta) : 0;
        if( f < 0.4f) return [a objectForKey: @"label"];
        if( f > 0.6f) return [b objectForKey: @"label"];
        // Bandscheibenzone zwischen den beiden gesetzten Nachbarn
        return [NSString stringWithFormat: @"%@-%@", [a objectForKey: @"label"], [b objectForKey: @"label"]];
    }
    return nil;
}

// Hoehe einer Schicht quer zur Wirbelsaeule. vert = Wirbel-Eintraege, nach Rang geordnet.
- (NSString*) levelForPix:(DCMPix*) pix vertebrae:(NSArray*) vert
{
    if( vert.count == 0) return nil;
    float o[ 9]; [pix orientation: o];
    float nrm[ 3] = { o[ 6], o[ 7], o[ 8] };
    float ctr[ 3]; [pix convertPixX: pix.pwidth / 2. pixY: pix.pheight / 2. toDICOMCoords: ctr pixelCenter: YES];
    NSMutableArray *pts = [NSMutableArray array];
    float tSlice = 0;
    NSDictionary *a = [vert objectAtIndex: 0], *b = [vert lastObject];
    float A[ 3] = { [[a objectForKey: @"x"] floatValue], [[a objectForKey: @"y"] floatValue], [[a objectForKey: @"z"] floatValue] };
    float axis[ 3] = { [[b objectForKey: @"x"] floatValue] - A[ 0], [[b objectForKey: @"y"] floatValue] - A[ 1], [[b objectForKey: @"z"] floatValue] - A[ 2] };
    float len = sqrtf( axis[ 0]*axis[ 0] + axis[ 1]*axis[ 1] + axis[ 2]*axis[ 2]);
    if( vert.count >= 2 && len > 1)
    {
        axis[ 0] /= len; axis[ 1] /= len; axis[ 2] /= len;
        float denom = axis[ 0]*nrm[ 0] + axis[ 1]*nrm[ 1] + axis[ 2]*nrm[ 2];
        if( fabsf( denom) < 0.3f) return nil;
        for( NSDictionary *l in vert)
        {
            float q[ 3] = { [[l objectForKey: @"x"] floatValue] - A[ 0], [[l objectForKey: @"y"] floatValue] - A[ 1], [[l objectForKey: @"z"] floatValue] - A[ 2] };
            [pts addObject: [NSDictionary dictionaryWithObjectsAndKeys: [l objectForKey: @"label"], @"label", [NSNumber numberWithFloat: q[ 0]*axis[ 0] + q[ 1]*axis[ 1] + q[ 2]*axis[ 2]], @"t", nil]];
        }
        [pts sortUsingDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"t" ascending: YES]]];
        // Schnitt der Schichtebene mit der Achse: A + t*axis liegt in der Ebene
        tSlice = ((ctr[ 0] - A[ 0])*nrm[ 0] + (ctr[ 1] - A[ 1])*nrm[ 1] + (ctr[ 2] - A[ 2])*nrm[ 2]) / denom;
    }
    else
    {
        [pts addObject: [NSDictionary dictionaryWithObjectsAndKeys: [a objectForKey: @"label"], @"label", [NSNumber numberWithFloat: 0], @"t", nil]];
        tSlice = (ctr[ 0] - A[ 0])*nrm[ 0] + (ctr[ 1] - A[ 1])*nrm[ 1] + (ctr[ 2] - A[ 2])*nrm[ 2];
    }
    return [SekhmetSpine levelForPosition: tSlice points: pts];
}

// SekhVet Paket BS: Hoehe an einem Punkt (Fadenkreuz des MPR) -- fuer die Dorsalebene, die laengs zur Wirbelsaeule liegt
- (NSString*) levelForPoint:(float*) P vertebrae:(NSArray*) vert
{
    if( vert.count == 0) return nil;
    NSDictionary *a = [vert objectAtIndex: 0], *b = [vert lastObject];
    float A[ 3] = { [[a objectForKey: @"x"] floatValue], [[a objectForKey: @"y"] floatValue], [[a objectForKey: @"z"] floatValue] };
    float axis[ 3] = { [[b objectForKey: @"x"] floatValue] - A[ 0], [[b objectForKey: @"y"] floatValue] - A[ 1], [[b objectForKey: @"z"] floatValue] - A[ 2] };
    float len = sqrtf( axis[ 0]*axis[ 0] + axis[ 1]*axis[ 1] + axis[ 2]*axis[ 2]);
    NSMutableArray *pts = [NSMutableArray array];
    if( vert.count < 2 || len <= 1)
    {
        float d = sqrtf( (P[ 0]-A[ 0])*(P[ 0]-A[ 0]) + (P[ 1]-A[ 1])*(P[ 1]-A[ 1]) + (P[ 2]-A[ 2])*(P[ 2]-A[ 2]));
        [pts addObject: [NSDictionary dictionaryWithObjectsAndKeys: [a objectForKey: @"label"], @"label", [NSNumber numberWithFloat: 0], @"t", nil]];
        return [SekhmetSpine levelForPosition: d points: pts];
    }
    axis[ 0] /= len; axis[ 1] /= len; axis[ 2] /= len;
    for( NSDictionary *l in vert)
    {
        float q[ 3] = { [[l objectForKey: @"x"] floatValue] - A[ 0], [[l objectForKey: @"y"] floatValue] - A[ 1], [[l objectForKey: @"z"] floatValue] - A[ 2] };
        [pts addObject: [NSDictionary dictionaryWithObjectsAndKeys: [l objectForKey: @"label"], @"label", [NSNumber numberWithFloat: q[ 0]*axis[ 0] + q[ 1]*axis[ 1] + q[ 2]*axis[ 2]], @"t", nil]];
    }
    [pts sortUsingDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: @"t" ascending: YES]]];
    return [SekhmetSpine levelForPosition: (P[ 0]-A[ 0])*axis[ 0] + (P[ 1]-A[ 1])*axis[ 1] + (P[ 2]-A[ 2])*axis[ 2] points: pts];
}

// Schnittpunkt der drei MPR-Ebenen in Patientenkoordinaten (aus den drei Schnittbildern, nicht aus den VTK-Kameras)
+ (BOOL) crossPointOfMPR:(MPRController*) c into:(float*) K
{
    MPRDCMView *views[ 3] = { c.mprView1, c.mprView2, c.mprView3 };
    float n[ 3][ 3], d[ 3];
    for( int i = 0; i < 3; i++)
    {
        DCMPix *p = views[ i].curDCM;
        if( p == nil) return NO;
        float o[ 9], ctr[ 3]; [p orientation: o];
        [p convertPixX: p.pwidth / 2. pixY: p.pheight / 2. toDICOMCoords: ctr pixelCenter: YES];
        for( int k = 0; k < 3; k++) n[ i][ k] = o[ 6 + k];
        d[ i] = n[ i][ 0]*ctr[ 0] + n[ i][ 1]*ctr[ 1] + n[ i][ 2]*ctr[ 2];
    }
    float det = n[0][0]*(n[1][1]*n[2][2] - n[1][2]*n[2][1]) - n[0][1]*(n[1][0]*n[2][2] - n[1][2]*n[2][0]) + n[0][2]*(n[1][0]*n[2][1] - n[1][1]*n[2][0]);
    if( fabsf( det) < 1e-4f) return NO;
    K[ 0] = (d[0]*(n[1][1]*n[2][2] - n[1][2]*n[2][1]) - n[0][1]*(d[1]*n[2][2] - n[1][2]*d[2]) + n[0][2]*(d[1]*n[2][1] - n[1][1]*d[2])) / det;
    K[ 1] = (n[0][0]*(d[1]*n[2][2] - n[1][2]*d[2]) - d[0]*(n[1][0]*n[2][2] - n[1][2]*n[2][0]) + n[0][2]*(n[1][0]*d[2] - d[1]*n[2][0])) / det;
    K[ 2] = (n[0][0]*(n[1][1]*d[2] - d[1]*n[2][1]) - n[0][1]*(n[1][0]*d[2] - d[1]*n[2][0]) + d[0]*(n[1][0]*n[2][1] - n[1][1]*n[2][0])) / det;
    return YES;
}

// Nach dem Loeschen einer 2D-ROI haelt das MPR noch ihre Kopie (Horos meldet die Loeschung, BEVOR die ROI aus der Liste ist,
// die Kopie wird also gleich wieder angelegt) -- "L1 bleibt stehen". Kopien aus dem jetzigen Bestand neu aufbauen.
- (void) refreshMPRPoints
{
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        MPRController *c = wc;
        for( MPRDCMView *mv in [NSArray arrayWithObjects: c.mprView1, c.mprView2, c.mprView3, nil])
        {
            @try { [mv detect2DPointInThisSlice]; } @catch (NSException *e) { }
            [mv setNeedsDisplay: YES];
        }
    }
}

static void sekhmetSpineText( DCMView *v, NSString *txt, float size, BOOL green, float alpha, float x, float y, BOOL centered)
{
    static NSCache *cache = nil;
    if( cache == nil) { cache = [[NSCache alloc] init]; cache.countLimit = 120; }
    CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];   // CGLMacro: die gl-Aufrufe brauchen ihn im Sichtbereich
    if( cgl_ctx == nil) return;
    float sf = v.window.backingScaleFactor > 0 ? v.window.backingScaleFactor : 1;
    float lc[ 3] = { 1, 1, 1 };
    if( green) [SekhmetSpine labelColorR: &lc[ 0] g: &lc[ 1] b: &lc[ 2]];   // SekhVet Paket BU: "green" = die gewaehlte Label-Farbe
    NSString *key = [NSString stringWithFormat: @"%@|%.0f|%.3f %.3f %.3f|%.1f", txt, size, lc[ 0], lc[ 1], lc[ 2], sf];
    StringTexture *sT = [cache objectForKey: key];
    if( sT == nil)
    {
        NSMutableDictionary *attrib = [NSMutableDictionary dictionary];
        [attrib setObject: [NSFont boldSystemFontOfSize: size] forKey: NSFontAttributeName];
        [attrib setObject: [NSColor colorWithCalibratedRed: lc[ 0] green: lc[ 1] blue: lc[ 2] alpha: 1.0] forKey: NSForegroundColorAttributeName];
        sT = [[[StringTexture alloc] initWithString: txt withAttributes: attrib] autorelease];
        [sT setAntiAliasing: YES];
        [sT genTextureWithBackingScaleFactor: sf];
        [cache setObject: sT forKey: key];
    }
    float w = [sT texSize].width, h = [sT texSize].height;
    float xc = centered ? x - w / 2 : x, yc = y - h / 2;
    glEnable( GL_TEXTURE_RECTANGLE_EXT);
    glEnable( GL_BLEND);
    glBlendFunc( GL_ONE, GL_ONE_MINUS_SRC_ALPHA);        // vormultiplizierte Textur, wie DCMView/ROI sie zeichnen
    glColor4f( 0, 0, 0, alpha);                          // dunkle Kontur fuer helle Bilder
    [sT drawAtPoint: NSMakePoint( xc - 1, yc - 1)]; [sT drawAtPoint: NSMakePoint( xc + 1, yc - 1)];
    [sT drawAtPoint: NSMakePoint( xc - 1, yc + 1)]; [sT drawAtPoint: NSMakePoint( xc + 1, yc + 1)];
    glColor4f( alpha, alpha, alpha, alpha);
    [sT drawAtPoint: NSMakePoint( xc, yc)];
    glDisable( GL_TEXTURE_RECTANGLE_EXT);
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);
}

- (void) drawObjects:(NSNotification*) note
{
    DCMView *v = [note object];
    if( [v isKindOfClass: [DCMView class]] == NO) return;
    DCMPix *pix = v.curDCM;
    if( pix == nil || pix.isOriginDefined == NO) return;
    ViewerController *viewer = [SekhmetSpine viewerForView: v];
    if( viewer == nil) return;
    BOOL is2D = [[[v window] windowController] isKindOfClass: [ViewerController class]];
    if( is2D) [self noteViewerOnce: viewer];

    NSString *studyUID = [viewer studyInstanceUID];
    if( studyUID.length == 0) return;
    NSArray *all = [[self dataForStudy: studyUID] objectForKey: @"labels"];
    if( all.count == 0 && active == NO) return;

    CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil) return;

    // Eintraege im selben Patientenraum; Wirbel getrennt, nach Rang geordnet
    NSString *forUID = pix.frameofReferenceUID;
    NSMutableArray *labels = [NSMutableArray array], *vert = [NSMutableArray array];
    for( NSDictionary *l in all)
    {
        NSString *f = [l objectForKey: @"for"];
        if( forUID.length && f.length && [f isEqualToString: forUID] == NO) continue;
        [labels addObject: l];
        if( [SekhmetSpine parseLabel: [l objectForKey: @"label"] region: NULL number: NULL]) [vert addObject: l];
    }
    [vert sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        double ra = [SekhmetSpine rankOfLabel: [a objectForKey: @"label"]], rb = [SekhmetSpine rankOfLabel: [b objectForKey: @"label"]];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];

    float o[ 9]; [pix orientation: o];
    float nrm[ 3] = { o[ 6], o[ 7], o[ 8] };
    float ctr[ 3]; [pix convertPixX: pix.pwidth / 2. pixY: pix.pheight / 2. toDICOMCoords: ctr pixelCenter: YES];

    // Achse der Wirbelsaeule: erster -> letzter Wirbel
    float axis[ 3] = { 0, 0, 0 }; BOOL haveAxis = NO; float A[ 3] = { 0, 0, 0 };
    if( vert.count >= 2)
    {
        NSDictionary *a = [vert objectAtIndex: 0], *b = [vert lastObject];
        A[ 0] = [[a objectForKey: @"x"] floatValue]; A[ 1] = [[a objectForKey: @"y"] floatValue]; A[ 2] = [[a objectForKey: @"z"] floatValue];
        axis[ 0] = [[b objectForKey: @"x"] floatValue] - A[ 0]; axis[ 1] = [[b objectForKey: @"y"] floatValue] - A[ 1]; axis[ 2] = [[b objectForKey: @"z"] floatValue] - A[ 2];
        float len = sqrtf( axis[ 0]*axis[ 0] + axis[ 1]*axis[ 1] + axis[ 2]*axis[ 2]);
        if( len > 1) { axis[ 0] /= len; axis[ 1] /= len; axis[ 2] /= len; haveAxis = YES; }
    }
    float across = haveAxis ? fabsf( axis[ 0]*nrm[ 0] + axis[ 1]*nrm[ 1] + axis[ 2]*nrm[ 2]) : 0;
    (void) across;
    int planeClass = [SekhmetSpine planeClassForPix: pix vertebrae: vert];
    BOOL transverse = planeClass == 0;
    BOOL showMarkers = [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey] == NO;
    BOOL elsewhere = [[NSUserDefaults standardUserDefaults] boolForKey: kElsewhereKey];

    NSRect fr = v.drawingFrameRect;
    float sf = v.window.backingScaleFactor > 0 ? v.window.backingScaleFactor : 1;
    float lc[ 3]; [SekhmetSpine labelColorR: &lc[ 0] g: &lc[ 1] b: &lc[ 2]];   // SekhVet Paket BU
    glPushMatrix();
    glLoadIdentity();
    glScalef( 2.0f / fr.size.width, -2.0f / fr.size.height, 1.0f);   // Ansichtsraum: Pixel, Mitte = 0, y nach unten
    glEnable( GL_BLEND);
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    float top = -fr.size.height / 2;
    if( transverse && vert.count)
    {
        NSString *level = [self levelForPix: pix vertebrae: vert];
        if( level) sekhmetSpineText( v, level, 26, YES, 1.0f, 0, top + 58 * sf, YES);
    }
    if( transverse == NO && planeClass == 2 && vert.count && [v isKindOfClass: [MPRDCMView class]])
    {
        // SekhVet Paket BS: Dorsalebene im MPR -- die Hoehe am Fadenkreuz wie im Querschnitt, keine Punkte im Raum
        float K[ 3];
        MPRController *mc = (MPRController*) [[v window] windowController];
        if( [mc isKindOfClass: [MPRController class]] && [SekhmetSpine crossPointOfMPR: mc into: K])
        {
            NSString *level = [self levelForPoint: K vertebrae: vert];
            if( level) sekhmetSpineText( v, level, 26, YES, 1.0f, 0, top + 58 * sf, YES);
        }
    }
    if( transverse == NO && labels.count)
    {
        // SekhVet Paket BT: projizierte Punkte nur in der sagittalen Ansicht, ausser der Schalter holt sie auch in die dorsale
        if( showMarkers && (planeClass == 1 || elsewhere))
        {
            NSString *viewSeries = [SekhmetSpine seriesUIDOfViewer: viewer];
            float thick = MAX( 1.0f, pix.sliceThickness);
            // Versatz der Schrift quer zur Wirbelsaeule im Bild, immer zur selben Seite
            NSPoint dirV = NSMakePoint( 0, -1);
            if( haveAxis)
            {
                float B[ 3] = { A[ 0] + axis[ 0] * 50, A[ 1] + axis[ 1] * 50, A[ 2] + axis[ 2] * 50 }, sa[ 3], sb[ 3];
                [pix convertDICOMCoords: A toSliceCoords: sa pixelCenter: YES]; [pix convertDICOMCoords: B toSliceCoords: sb pixelCenter: YES];
                NSPoint pa = [v ConvertFromGL2View: NSMakePoint( sa[ 0] / pix.pixelSpacingX, sa[ 1] / pix.pixelSpacingY)];
                NSPoint pb = [v ConvertFromGL2View: NSMakePoint( sb[ 0] / pix.pixelSpacingX, sb[ 1] / pix.pixelSpacingY)];
                float dx = pb.x - pa.x, dy = pb.y - pa.y, len = sqrtf( dx*dx + dy*dy);
                if( len > 1) { dirV = NSMakePoint( dy / len, -dx / len); if( dirV.y > 0) dirV = NSMakePoint( -dirV.x, -dirV.y); }   // nach oben im Bild
            }
            for( NSDictionary *l in labels)
            {
                float P[ 3] = { [[l objectForKey: @"x"] floatValue], [[l objectForKey: @"y"] floatValue], [[l objectForKey: @"z"] floatValue] }, sc[ 3];
                float dist = fabsf( (P[ 0] - ctr[ 0])*nrm[ 0] + (P[ 1] - ctr[ 1])*nrm[ 1] + (P[ 2] - ctr[ 2])*nrm[ 2]);
                // In der eigenen Serie zeichnet Horos die ROI selbst, sobald die Schicht sie enthaelt (MPR: Kopie innerhalb der Schichtdicke)
                if( dist < thick && [[l objectForKey: @"series"] isEqualToString: viewSeries]) continue;
                [pix convertDICOMCoords: P toSliceCoords: sc pixelCenter: YES];
                float px = sc[ 0] / pix.pixelSpacingX, py = sc[ 1] / pix.pixelSpacingY;
                if( px < 0 || py < 0 || px > pix.pwidth || py > pix.pheight) continue;
                NSPoint c = [v ConvertFromGL2View: NSMakePoint( px, py)];
                BOOL disc = [SekhmetSpine isDiscLabel: [l objectForKey: @"label"]];
                float alpha = dist < thick ? 0.95f : 0.6f, rad = (disc ? 3 : 4) * sf, off = (disc ? 22 : 34) * sf;
                NSPoint tp = NSMakePoint( c.x + dirV.x * off, c.y + dirV.y * off);
                glDisable( GL_TEXTURE_RECTANGLE_EXT);
                glColor4f( lc[ 0], lc[ 1], lc[ 2], alpha);
                glLineWidth( 1.0f * sf);
                glBegin( GL_LINE_LOOP);
                for( int k = 0; k < 16; k++) glVertex2f( c.x + rad * cosf( k * M_PI / 8), c.y + rad * sinf( k * M_PI / 8));
                glEnd();
                glBegin( GL_LINES);
                glVertex2f( c.x + dirV.x * rad, c.y + dirV.y * rad); glVertex2f( c.x + dirV.x * (off - 9 * sf), c.y + dirV.y * (off - 9 * sf));
                glEnd();
                sekhmetSpineText( v, [l objectForKey: @"label"], disc ? 10 : 12, YES, alpha, tp.x, tp.y, YES);
            }
        }
    }

    // Naechstes Label im Fenster, in dem gerade gesetzt wird
    if( active && [[v window] isKeyWindow])
        sekhmetSpineText( v, [NSString stringWithFormat: NSLocalizedString( @"Spine ▸ next: %@", nil), [self peekLabel]], 13, NO, 0.95f, 0, top + 84 * sf, YES);

    glPopMatrix();
}

#pragma mark - Liste im Panel

- (void) setCurrentStudy:(NSString*) studyUID
{
    if( studyUID.length == 0 || [studyUID isEqualToString: currentStudyUID]) return;
    [currentStudyUID release]; currentStudyUID = [studyUID copy];
    NSArray *f = [[self dataForStudy: studyUID] objectForKey: @"formula"];
    if( f.count == 4) for( int i = 0; i < 4; i++) counts[ i] = MAX( 1, [[f objectAtIndex: i] integerValue]);
    else { NSInteger sp = MAX( 0, [speciesPopup indexOfSelectedItem]); for( int i = 0; i < 4; i++) counts[ i] = kCounts[ sp][ i]; }
    [self showFormula];
    [self reloadTable];
}

- (void) windowBecameKey:(NSNotification*) n
{
    id wc = [[n object] windowController];
    ViewerController *v = [wc isKindOfClass: [ViewerController class]] ? wc : ([wc isKindOfClass: [MPRController class]] ? [(MPRController*) wc viewer] : nil);
    if( v && [[self window] isVisible]) [self setCurrentStudy: [v studyInstanceUID]];
}

- (void) reloadTable
{
    NSArray *labels = currentStudyUID ? [[self dataForStudy: currentStudyUID] objectForKey: @"labels"] : nil;
    NSArray *sorted = [labels sortedArrayUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        double ra = [SekhmetSpine rankOfLabel: [a objectForKey: @"label"]], rb = [SekhmetSpine rankOfLabel: [b objectForKey: @"label"]];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    [tableRows release]; tableRows = [sorted retain];
    [listStatus setStringValue: [NSString stringWithFormat: NSLocalizedString( @"Labels of this study: %d", nil), (int) tableRows.count]];
    [labelTable reloadData];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv { return tableRows.count; }

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( row < 0 || row >= (NSInteger) tableRows.count) return nil;
    return [[tableRows objectAtIndex: row] objectForKey: [col identifier]];
}

// Die ROI zum Listeneintrag: nur wenn ihre Serie offen ist (die ROI ist die Wahrheit, die Liste folgt ihr)
- (ROI*) roiForEntry:(NSDictionary*) e viewer:(ViewerController**) outViewer
{
    float P[ 3] = { [[e objectForKey: @"x"] floatValue], [[e objectForKey: @"y"] floatValue], [[e objectForKey: @"z"] floatValue] };
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        if( [[e objectForKey: @"series"] isEqualToString: [SekhmetSpine seriesUIDOfViewer: v]] == NO) continue;
        NSArray *roiList = [v roiList], *pixList = [v pixList];
        for( NSUInteger i = 0; i < roiList.count && i < pixList.count; i++)
            for( ROI *r in [roiList objectAtIndex: i])
            {
                if( [r type] != t2DPoint || [r.name isEqualToString: [e objectForKey: @"label"]] == NO) continue;
                float loc[ 3];
                [[pixList objectAtIndex: i] convertPixX: r.rect.origin.x pixY: r.rect.origin.y toDICOMCoords: loc pixelCenter: YES];
                if( fabsf( loc[ 0] - P[ 0]) + fabsf( loc[ 1] - P[ 1]) + fabsf( loc[ 2] - P[ 2]) < 1.5f) { if( outViewer) *outViewer = v; return r; }
            }
    }
    return nil;
}

- (void) needSeriesOpen:(NSDictionary*) e
{
    NSBeep();
    [listStatus setStringValue: [NSString stringWithFormat: NSLocalizedString( @"Open series \"%@\" to change this label", nil), [e objectForKey: @"seriesName"]]];
}

- (void) tableView:(NSTableView*) tv setObjectValue:(id) value forTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( row < 0 || row >= (NSInteger) tableRows.count) return;
    NSDictionary *e = [[[tableRows objectAtIndex: row] retain] autorelease];
    NSString *name = [[value description] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    if( name.length == 0 || [name isEqualToString: [e objectForKey: @"label"]]) return;
    ROI *r = [self roiForEntry: e viewer: NULL];
    if( r == nil) { [self needSeriesOpen: e]; return; }
    [sekhmetKnownNames setObject: [e objectForKey: @"label"] forKey: [NSValue valueWithPointer: r]];
    [r setName: name];
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixROIChangeNotification object: r userInfo: nil];   // zaehlt die folgenden neu, Liste folgt
}

// Klick in die Liste: alle 2D-Viewer der Studie auf die Schicht des Labels
- (void) tableViewSelectionDidChange:(NSNotification*) n
{
    NSInteger row = [labelTable selectedRow];
    if( row < 0 || row >= (NSInteger) tableRows.count) return;
    NSDictionary *e = [tableRows objectAtIndex: row];
    float P[ 3] = { [[e objectForKey: @"x"] floatValue], [[e objectForKey: @"y"] floatValue], [[e objectForKey: @"z"] floatValue] };
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        if( [currentStudyUID isEqualToString: [v studyInstanceUID]] == NO) continue;
        NSArray *pixList = [v pixList];
        NSInteger best = -1; float bestDist = 0;
        for( NSUInteger i = 0; i < pixList.count; i++)
        {
            DCMPix *p = [pixList objectAtIndex: i];
            NSString *f = p.frameofReferenceUID, *ef = [e objectForKey: @"for"];
            if( f.length && ef.length && [f isEqualToString: ef] == NO) break;
            float o[ 9], c[ 3]; [p orientation: o];
            [p convertPixX: 0 pixY: 0 toDICOMCoords: c pixelCenter: YES];
            float d = fabsf( (P[ 0] - c[ 0])*o[ 6] + (P[ 1] - c[ 1])*o[ 7] + (P[ 2] - c[ 2])*o[ 8]);
            if( best < 0 || d < bestDist) { best = i; bestDist = d; }
        }
        if( best < 0) continue;
        if( [[v imageView] flippedData]) best = (NSInteger) pixList.count - 1 - best;
        [v setImageIndex: best];
    }
}

- (IBAction) deleteSelectedLabel:(id) sender
{
    NSInteger row = [labelTable selectedRow];
    if( row < 0 || row >= (NSInteger) tableRows.count) return;
    NSDictionary *e = [[[tableRows objectAtIndex: row] retain] autorelease];
    ViewerController *v = nil;
    ROI *r = [self roiForEntry: e viewer: &v];
    if( r == nil) { [self needSeriesOpen: e]; return; }
    [roiSeries setObject: [e objectForKey: @"series"] forKey: [NSValue valueWithPointer: r]];
    [v deleteROI: r];
    [self refreshMPRPoints];
    [self scheduleSyncForViewer: v];
}

#pragma mark - Aufraeumen

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
            for( ROI *x in slice) { [sekhmetKnownNames removeObjectForKey: [NSValue valueWithPointer: x]]; [roiSeries removeObjectForKey: [NSValue valueWithPointer: x]]; }
    NSString *prefix = [NSString stringWithFormat: @"%p|", v];
    for( NSString *k in [notedViewers allObjects]) if( [k hasPrefix: prefix]) [notedViewers removeObject: k];
}

#pragma mark - Aktionen

- (void) toggleWithWindowController:(NSWindowController*) wc
{
    [self showWindow: nil];
    ViewerController *v = [wc isKindOfClass: [ViewerController class]] ? (ViewerController*) wc : ([wc isKindOfClass: [MPRController class]] ? [(MPRController*) wc viewer] : nil);
    if( v) [self setCurrentStudy: [v studyInstanceUID]];
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
    if( [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey])   // beim Setzen muss man die Punkte sehen
    {
        [markersButton setState: NSControlStateValueOn];
        [self visibilityChanged: nil];
    }
    for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [self noteNamesInViewer: v];
    [self settingsChanged: nil];
    [self redrawAll];
}

// SekhVet Paket BU: Start setzt das Punkt-Werkzeug nur in der Ansicht, die Werkzeugleiste zeigt weiter das alte.
// Stop gibt jeder Ansicht, die noch auf t2DPoint steht, das Werkzeug zurueck, das ihre Werkzeugleiste zeigt.
// Zeigt die Leiste selbst den Punkt (vom Benutzer gewaehlt), bleibt er.
+ (ToolMode) toolOfMatrix:(NSMatrix*) m
{
    NSInteger tag = [m isKindOfClass: [NSMatrix class]] ? [[m selectedCell] tag] : -1;
    return tag >= 0 ? (ToolMode) tag : tWL;
}

- (void) restoreToolbarTools
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        @try
        {
            if( [[v imageView] currentTool] != t2DPoint) continue;
            ToolMode t = [SekhmetSpine toolOfMatrix: [v valueForKey: @"toolsMatrix"]];
            if( t != t2DPoint) [[v imageView] setCurrentTool: t];
        }
        @catch (NSException *e) { }
    }
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [(MPRController*) wc windowWillClose]) continue;
        @try
        {
            MPRController *mc = (MPRController*) wc;
            if( [[mc mprView1] currentTool] != t2DPoint) continue;
            ToolMode t = [SekhmetSpine toolOfMatrix: [mc valueForKey: @"toolsMatrix"]];
            if( t != t2DPoint) [mc setToolIndex: t];
        }
        @catch (NSException *e) { }
    }
}

- (void) stop
{
    active = NO;
    [self restoreToolbarTools];
    [self updateNextLabel];
    [self redrawAll];
}

- (void) undo
{
    ROI *last = [createdROIs lastObject];
    if( last == nil) return;
    [[last retain] autorelease];
    [createdROIs removeLastObject];
    if( [SekhmetSpine isDiscLabel: last.name] == NO) { [self retreat]; placedInRun = MAX( 0, placedInRun - 1); }   // Bandscheibe hat nicht gezaehlt
    [lastVertebra release]; lastVertebra = nil;
    if( placedInRun > 0)   // der Wirbel davor ist wieder der letzte (fuer Alt-Klick und die Richtungserkennung)
    {
        NSInteger r = region, n = number;
        BOOL saved = backwards; backwards = !backwards;
        [self successorOfRegion: &r number: &n];
        backwards = saved;
        lastVertebra = [[self labelFor: r number: n] retain];
    }
    // Horos loescht ROIs nur ueber ViewerController deleteROI: (die Notification allein zeichnet nur neu)
    ViewerController *owner = nil;
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        for( NSArray *slice in [v roiList])
            if( [slice indexOfObjectIdenticalTo: last] != NSNotFound) owner = v;
    if( owner)
    {
        NSString *seriesUID = [SekhmetSpine seriesUIDOfViewer: owner];
        if( seriesUID) [roiSeries setObject: seriesUID forKey: [NSValue valueWithPointer: last]];
        [owner deleteROI: last];
        [self refreshMPRPoints];
        [self scheduleSyncForViewer: owner];
    }
    [self updateNextLabel];
}

- (void) windowWillClose:(NSNotification*) note   // SekhVet Paket BU
{
    if( active) [self stop];
}

- (IBAction) toggle:(id) sender
{
    if( active) [self stop]; else [self start];
}

- (IBAction) undoAction:(id) sender { [self undo]; }

// Alle Labels der Studie: ROIs in den offenen Serien loeschen, Studienliste leeren
- (IBAction) clearAll:(id) sender
{
    if( currentStudyUID == nil) return;
    NSMutableArray *labels = [[self dataForStudy: currentStudyUID] objectForKey: @"labels"];
    if( labels.count == 0 && createdROIs.count == 0) return;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Delete all %d spine labels of this study?", nil), (int) labels.count]];
    [a setInformativeText: NSLocalizedString( @"Labels set in a series that is not open stay in that series' ROIs and come back when it is opened; open it and delete again to remove them for good.", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Delete", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;

    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        if( [currentStudyUID isEqualToString: [v studyInstanceUID]] == NO) continue;
        NSMutableArray *kill = [NSMutableArray array];
        for( NSArray *slice in [v roiList])
            for( ROI *r in slice)
                if( [r type] == t2DPoint && [SekhmetSpine rankOfLabel: r.name] >= 0) [kill addObject: r];
        for( ROI *r in kill) [v deleteROI: r];
    }
    [self refreshMPRPoints];
    [createdROIs removeAllObjects];
    [labels removeAllObjects];
    [self saveStudy: currentStudyUID];
    [self settingsChanged: nil];
    [self reloadTable];
    [self redrawAll];
}

- (IBAction) speciesChanged:(id) sender
{
    NSInteger sp = MAX( 0, MIN( 2, [speciesPopup indexOfSelectedItem]));
    [[NSUserDefaults standardUserDefaults] setInteger: sp forKey: kSpeciesKey];
    for( int i = 0; i < 5; i++) counts[ i] = kCounts[ sp][ i];
    [self showFormula];
    [self formulaChanged: nil];
}

- (IBAction) formulaChanged:(id) sender
{
    for( int i = 0; i < 4; i++) { counts[ i] = MAX( 1, MIN( 30, [formulaFields[ i] integerValue])); }
    [self showFormula];
    if( currentStudyUID)   // die Formel gehoert zur Studie; gleich der Tierart-Vorgabe = nicht speichern
    {
        NSMutableDictionary *d = [self dataForStudy: currentStudyUID];
        NSInteger sp = MAX( 0, [speciesPopup indexOfSelectedItem]);
        BOOL isDefault = YES;
        for( int i = 0; i < 4; i++) if( counts[ i] != kCounts[ sp][ i]) isDefault = NO;
        if( isDefault) [d removeObjectForKey: @"formula"];
        else [d setObject: [NSArray arrayWithObjects: [NSNumber numberWithInteger: counts[ 0]], [NSNumber numberWithInteger: counts[ 1]], [NSNumber numberWithInteger: counts[ 2]], [NSNumber numberWithInteger: counts[ 3]], nil] forKey: @"formula"];
        [self saveStudy: currentStudyUID];
    }
    [self settingsChanged: nil];
}

- (IBAction) colorChanged:(id) sender   // SekhVet Paket BU
{
    NSColor *c = [[colorWell color] colorUsingColorSpace: [NSColorSpace genericRGBColorSpace]];
    if( c == nil) return;
    [[NSUserDefaults standardUserDefaults] setObject: [NSString stringWithFormat: @"%.3f %.3f %.3f", c.redComponent, c.greenComponent, c.blueComponent] forKey: kColorKey];
    [self redrawAll];
}

- (IBAction) visibilityChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([markersButton state] != NSControlStateValueOn) forKey: kMarkersOffKey];
    [[NSUserDefaults standardUserDefaults] setBool: ([elsewhereButton state] == NSControlStateValueOn) forKey: kElsewhereKey];
    [elsewhereButton setEnabled: [markersButton state] == NSControlStateValueOn];
    [self applyVisibility];
}

// Die Punkt-ROIs der 2D-Viewer ein-/ausblenden (ROI hidden), MPR-Kopien neu filtern, alles neu zeichnen
- (void) applyVisibility
{
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey];
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        for( NSArray *slice in [v roiList])
            for( ROI *r in slice)
                if( [r type] == t2DPoint && [SekhmetSpine rankOfLabel: r.name] >= 0 && r.hidden != hide) r.hidden = hide;
    [self refreshMPRPoints];
    [self redrawAll];
}

// 0 quer zur Wirbelsaeule, 1 sagittal (laengs, Blick von der Seite), 2 dorsal (laengs, Blick von oben/unten).
// Ohne zwei Wirbel ist die Achse unbekannt: dann entscheidet die Ebenennormale allein (DICOM x = links-rechts, y = ventro-dorsal, z = laengs).
+ (int) planeClassForPix:(DCMPix*) pix vertebrae:(NSArray*) vert
{
    float o[ 9]; [pix orientation: o];
    float nrm[ 3] = { o[ 6], o[ 7], o[ 8] };
    BOOL transverse = fabsf( nrm[ 2]) >= 0.6f;
    if( vert.count >= 2)
    {
        NSDictionary *a = [vert objectAtIndex: 0], *b = [vert lastObject];
        float ax[ 3] = { [[b objectForKey: @"x"] floatValue] - [[a objectForKey: @"x"] floatValue], [[b objectForKey: @"y"] floatValue] - [[a objectForKey: @"y"] floatValue], [[b objectForKey: @"z"] floatValue] - [[a objectForKey: @"z"] floatValue] };
        float len = sqrtf( ax[ 0]*ax[ 0] + ax[ 1]*ax[ 1] + ax[ 2]*ax[ 2]);
        if( len > 1) transverse = fabsf( (ax[ 0]*nrm[ 0] + ax[ 1]*nrm[ 1] + ax[ 2]*nrm[ 2]) / len) >= 0.6f;
    }
    if( transverse) return 0;
    return fabsf( nrm[ 1]) > fabsf( nrm[ 0]) ? 2 : 1;
}

- (NSArray*) sortedVertebraeOfStudy:(NSString*) studyUID frameOfReference:(NSString*) forUID
{
    NSMutableArray *vert = [NSMutableArray array];
    for( NSDictionary *l in [[self dataForStudy: studyUID] objectForKey: @"labels"])
    {
        NSString *f = [l objectForKey: @"for"];
        if( forUID.length && f.length && [f isEqualToString: forUID] == NO) continue;
        if( [SekhmetSpine parseLabel: [l objectForKey: @"label"] region: NULL number: NULL]) [vert addObject: l];
    }
    [vert sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        double ra = [SekhmetSpine rankOfLabel: [a objectForKey: @"label"]], rb = [SekhmetSpine rankOfLabel: [b objectForKey: @"label"]];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    return vert;
}

// Haken am Ende von MPRDCMView detect2DPointInThisSlice: Horos kopiert jeden 2D-Punkt in jede MPR-Ebene, die ihn schneidet.
// Wirbelpunkte bleiben nur in der sagittalen Ansicht, ausser der Schalter "also in the transverse and dorsal views" steht.
+ (void) filterPointCopiesInMPRView:(id) mprView
{
    MPRDCMView *view = mprView;
    SekhmetSpine *s = sekhmetSpine;
    DCMPix *pix = view.curDCM;
    if( s == nil || pix == nil) return;
    BOOL hide = [[NSUserDefaults standardUserDefaults] boolForKey: kMarkersOffKey];
    BOOL elsewhere = [[NSUserDefaults standardUserDefaults] boolForKey: kElsewhereKey];
    if( hide == NO && elsewhere) return;
    NSMutableArray *list = [view curRoiList];
    int cls = -1;
    for( NSInteger i = (NSInteger) list.count - 1; i >= 0; i--)
    {
        ROI *r = [list objectAtIndex: i];
        if( [r type] != t2DPoint || r.parentROI == nil || [SekhmetSpine rankOfLabel: r.name] < 0) continue;
        if( hide == NO && cls < 0)
        {
            ViewerController *viewer = [SekhmetSpine viewerForView: view];
            cls = [SekhmetSpine planeClassForPix: pix vertebrae: [s sortedVertebraeOfStudy: [viewer studyInstanceUID] frameOfReference: pix.frameofReferenceUID]];
        }
        if( hide || cls != 1) [list removeObjectAtIndex: i];
    }
}

- (IBAction) settingsChanged:(id) sender
{
    region = [regionPopup indexOfSelectedItem];
    number = MAX( 1, [numberField integerValue]);
    if( number > [self countForRegion: region]) { number = [self countForRegion: region]; [numberField setIntegerValue: number]; }
    backwards = ([directionPopup indexOfSelectedItem] == 2);
    placedInRun = 0;
    [lastVertebra release]; lastVertebra = nil;
    [self updateNextLabel];
    [self redrawAll];
}

#if SEKHVET_TESTHAKEN
+ (NSString*) debugSelfTest
{
    // Zaehl-, Parse- und Hoehenlogik ohne ROIs: Hund, vorwaerts
    SekhmetSpine *s = [self shared];
    NSMutableString *out = [NSMutableString string];
    NSInteger r, n;
    [out appendFormat: @"parse L3=%d(%d,%d) ", [self parseLabel: @"L3" region: &r number: &n], (int) r, (int) n];
    [out appendFormat: @"parse Cd4=%d(%d,%d) ", [self parseLabel: @"Cd4" region: &r number: &n], (int) r, (int) n];
    [out appendFormat: @"parse X1=%d disc(L1-L2)=%d disc(L1)=%d ", [self parseLabel: @"X1" region: NULL number: NULL], [self isDiscLabel: @"L1-L2"], [self isDiscLabel: @"L1"]];
    [out appendFormat: @"rank T13=%.1f L1=%.1f T13-L1=%.1f L1-T13=%.1f ", [self rankOfLabel: @"T13"], [self rankOfLabel: @"L1"], [self rankOfLabel: @"T13-L1"], [self rankOfLabel: @"L1-T13"]];
    NSInteger sreg = s->region, snum = s->number, sc[ 5]; BOOL sb = s->backwards;
    for( int i = 0; i < 5; i++) { sc[ i] = s->counts[ i]; s->counts[ i] = kCounts[ 0][ i]; }
    s->backwards = NO;
    r = 1; n = 13; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"succ(T13)=%@ ", [s labelFor: r number: n]];
    r = 2; n = 7; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"succ(L7)=%@ ", [s labelFor: r number: n]];
    s->counts[ 2] = 6; r = 2; n = 6; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"L=6: succ(L6)=%@ ", [s labelFor: r number: n]];
    s->counts[ 2] = 7;
    s->backwards = YES; r = 2; n = 1; [s successorOfRegion: &r number: &n];
    [out appendFormat: @"pred(L1)=%@ ", [s labelFor: r number: n]];
    NSMutableArray *pts = [NSMutableArray array];
    for( int i = 0; i < 3; i++) [pts addObject: [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithFormat: @"L%d", i + 1], @"label", [NSNumber numberWithFloat: i * 20.f], @"t", nil]];
    [out appendFormat: @"level(-5)=%@ level(-15)=%@ level(6)=%@ level(10)=%@ level(14)=%@ level(49)=%@ level(55)=%@",
     [self levelForPosition: -5 points: pts], [self levelForPosition: -15 points: pts], [self levelForPosition: 6 points: pts], [self levelForPosition: 10 points: pts],
     [self levelForPosition: 14 points: pts], [self levelForPosition: 49 points: pts], [self levelForPosition: 55 points: pts]];
    for( int i = 0; i < 5; i++) s->counts[ i] = sc[ i];
    s->region = sreg; s->number = snum; s->backwards = sb;
    return out;
}

// SEKHVET_SPINE_E2E_TEST=1 (60 s nach dem Start, Studie vorher per XML-RPC oeffnen): drei Wirbelpunkte in die erste Serie,
// Studienliste + Datei pruefen, Hoehe je Schicht in ALLEN Viewern loggen, umbenennen (Neuzaehlung), wieder loeschen.
+ (NSArray*) debugSortedVertebrae:(NSString*) studyUID
{
    NSMutableArray *vert = [NSMutableArray array];
    for( NSDictionary *l in [[[self shared] dataForStudy: studyUID] objectForKey: @"labels"])
        if( [self parseLabel: [l objectForKey: @"label"] region: NULL number: NULL]) [vert addObject: l];
    [vert sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        double ra = [SekhmetSpine rankOfLabel: [a objectForKey: @"label"]], rb = [SekhmetSpine rankOfLabel: [b objectForKey: @"label"]];
        return ra < rb ? NSOrderedAscending : (ra > rb ? NSOrderedDescending : NSOrderedSame);
    }];
    return vert;
}

+ (void) debugE2E
{
    static int step = 0; static ViewerController *src = nil; static NSMutableArray *made = nil;
    SekhmetSpine *s = [self shared];
    if( step == 0)
    {
        for( ViewerController *v in [ViewerController getDisplayed2DViewers]) if( src == nil && [[v pixList] count] >= 30) src = v;
        if( src == nil) { NSLog( @"SekhVet Spine-E2E: kein Viewer mit >= 30 Schichten"); return; }
        made = [[NSMutableArray alloc] init];
        NSUInteger n = [[src pixList] count];
        for( int k = 0; k < 3; k++)
        {
            NSUInteger i = n * (k + 1) / 4;
            DCMPix *pix = [[src pixList] objectAtIndex: i];
            ROI *r = [[[ROI alloc] initWithType: t2DPoint :pix.pixelSpacingX :pix.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pix]] autorelease];
            [r setROIRect: NSMakeRect( pix.pwidth / 2, pix.pheight / 2, 0, 0)];
            [r setName: [NSString stringWithFormat: @"L%d", k + 1]];
            [[src imageView] roiSet: r];
            [[[src roiList] objectAtIndex: i] addObject: r];
            [made addObject: r];
        }
        [s setCurrentStudy: [src studyInstanceUID]];
        [s syncFromViewer: src];
        NSLog( @"SekhVet Spine-E2E 1: %d Viewer, Quelle '%@' %d Schichten, Liste %d Eintraege, Datei %@", (int) [[ViewerController getDisplayed2DViewers] count], [[src currentSeries] valueForKey: @"name"], (int) n,
              (int) [[[s dataForStudy: [src studyInstanceUID]] objectForKey: @"labels"] count], [[NSFileManager defaultManager] fileExistsAtPath: [s pathForStudy: [src studyInstanceUID]]] ? @"da" : @"FEHLT");
    }
    else if( step == 1 || step == 3)
    {
        NSArray *vert = [self debugSortedVertebrae: [src studyInstanceUID]];
        for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        {
            NSMutableString *seq = [NSMutableString string]; NSString *prev = @"?";
            NSArray *pl = [v pixList];
            for( NSUInteger i = 0; i < pl.count; i++)
            {
                NSString *lv = [s levelForPix: [pl objectAtIndex: i] vertebrae: vert]; if( lv == nil) lv = @"-";
                if( [lv isEqualToString: prev] == NO) { [seq appendFormat: @"%@%@@%d", seq.length ? @" " : @"", lv, (int) i]; prev = lv; }
            }
            NSLog( @"SekhVet Spine-E2E %d: '%@' (%d Schichten) Hoehenfolge: %@", step + 1, [[v currentSeries] valueForKey: @"name"], (int) pl.count, seq);
        }
    }
    else if( step == 2)
    {
        ROI *first = [made objectAtIndex: 0];
        [sekhmetKnownNames setObject: @"L1" forKey: [NSValue valueWithPointer: first]];
        [first setName: @"T13"];
        [[NSNotificationCenter defaultCenter] postNotificationName: OsirixROIChangeNotification object: first userInfo: nil];
        NSLog( @"SekhVet Spine-E2E 3: L1 -> T13, ROI-Namen jetzt: %@ %@ %@", [[made objectAtIndex: 0] name], [[made objectAtIndex: 1] name], [[made objectAtIndex: 2] name]);
    }
    else if( step == 4)
    {
        for( ROI *r in made) { [s->roiSeries setObject: [SekhmetSpine seriesUIDOfViewer: src] forKey: [NSValue valueWithPointer: r]]; [src deleteROI: r]; }
        [made removeAllObjects];
    }
    else
    {
        NSLog( @"SekhVet Spine-E2E 6: nach dem Loeschen Liste %d Eintraege, Datei %@ -- fertig", (int) [[[s dataForStudy: [src studyInstanceUID]] objectForKey: @"labels"] count],
              [[NSFileManager defaultManager] fileExistsAtPath: [s pathForStudy: [src studyInstanceUID]]] ? @"NOCH DA" : @"weg");
        return;
    }
    step++;
    [self performSelector: @selector(debugE2E) withObject: nil afterDelay: 1.5 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}
#endif // SEKHVET_TESTHAKEN

@end
