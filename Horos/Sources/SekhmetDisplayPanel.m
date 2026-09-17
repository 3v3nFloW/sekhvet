/*=========================================================================
 Sekhmet — Anzeige-Einstellungen. Siehe Header.
 ============================================================================*/

#import "SekhmetDisplayPanel.h"
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#import "AppController.h"
#import "BrowserController.h" // SekhVet Paket N
#import "MyOutlineView.h"
#import "Notifications.h"
#import "NSFont_OpenGL.h"
#include <sys/sysctl.h> // SekhVet Paket AZ: Mac-Modell fuer die Feedback-Mail

NSString* const SekhmetScreenAreasKey = @"SekhmetScreenAreas";
NSString* const SekhmetScreenAreaRectsKey = @"SekhmetScreenAreaRects";
NSString* const SekhmetAnnotationBackgroundKey = @"SekhmetAnnotationBackground";
NSString* const SekhmetMPRSyncKey = @"SekhmetMPRSync";
NSString* const SekhmetTile3DWindowsKey = @"SekhmetTile3DWindows";
NSString* const SekhmetAppearanceKey = @"SekhmetAppearance"; // SekhVet Paket N
NSString* const SekhmetModalityColorsKey = @"SekhmetModalityColors";
NSString* const SekhmetROITextColorModeKey = @"SekhmetROITextColorMode";
NSString* const SekhmetROITextColorKey = @"SekhmetROITextColor";
NSString* const SekhmetAnnotationBoxColorKey = @"SekhmetAnnotationBoxColor";

static NSString* const sekhmetFontNames[] = { @"Helvetica-Bold", @"Helvetica", @"Geneva", @"Arial-BoldMT", @"Menlo-Bold", @"Monaco" };
static NSString* const sekhmetFontTitles[] = { @"Helvetica Bold", @"Helvetica", @"Geneva", @"Arial Bold", @"Menlo Bold", @"Monaco" };
#define SEKHMET_FONT_COUNT 6

static SekhmetDisplayPanel *sekhmetDisplayPanel = nil;

@interface SekhmetDisplayPanel ()
- (void) loadFromDefaults;
+ (NSColor*) colorFromString:(NSString*) s fallback:(NSColor*) fb; // SekhVet Paket N
+ (NSString*) stringFromColor:(NSColor*) c withAlpha:(BOOL) withAlpha;
- (void) sekhmetRedrawViewers;
@end

@implementation SekhmetDisplayPanel

+ (SekhmetDisplayPanel*) shared
{
    if( sekhmetDisplayPanel == nil)
        sekhmetDisplayPanel = [[SekhmetDisplayPanel alloc] init];
    return sekhmetDisplayPanel;
}

+ (NSArray*) areaModeNames
{
    return [NSArray arrayWithObjects:
            NSLocalizedString( @"Full screen", nil),
            NSLocalizedString( @"Left half", nil),
            NSLocalizedString( @"Right half", nil),
            NSLocalizedString( @"Left two thirds", nil),
            NSLocalizedString( @"Right two thirds", nil),
            NSLocalizedString( @"Center half", nil),
            NSLocalizedString( @"Pixel rectangle (x y w h)", nil), nil];
}

+ (NSInteger) modeForIndex:(NSInteger) i
{
    // Popup-Index -> Modus (Pixel-Rechteck ist 9)
    return (i == 6) ? SekhmetAreaPixelRect : i;
}

+ (NSInteger) indexForMode:(NSInteger) m
{
    return (m == SekhmetAreaPixelRect) ? 6 : m;
}

+ (NSInteger) modeForScreen:(NSScreen*) screen
{
    NSInteger idx = [[NSScreen screens] indexOfObject: screen];
    if( idx == NSNotFound) return SekhmetAreaFull;
    return [[[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreasKey] objectForKey: [NSString stringWithFormat: @"%d", (int) idx]] integerValue];
}

+ (void) setMode:(NSInteger) mode forScreen:(NSScreen*) screen
{
    NSInteger idx = [[NSScreen screens] indexOfObject: screen];
    if( idx == NSNotFound) return;
    NSMutableDictionary *areas = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreasKey]];
    [areas setObject: [NSNumber numberWithInteger: mode] forKey: [NSString stringWithFormat: @"%d", (int) idx]];
    [[NSUserDefaults standardUserDefaults] setObject: areas forKey: SekhmetScreenAreasKey];
    if( sekhmetDisplayPanel) [sekhmetDisplayPanel loadFromDefaults];
}

// SekhVet Paket N: Erscheinungsbild der ganzen App (nil = System)
+ (void) applyAppearance
{
    NSInteger m = [[NSUserDefaults standardUserDefaults] integerForKey: SekhmetAppearanceKey];
    NSAppearance *a = nil;
    if( m == 1) a = [NSAppearance appearanceNamed: NSAppearanceNameAqua];
    else if( m == 2) a = [NSAppearance appearanceNamed: NSAppearanceNameDarkAqua];
    [NSApp setAppearance: a];
}

// SekhVet Paket N: Toenung je Modalitaet (Studie kann "CT\\SR" tragen: erster nicht-sekundaerer Eintrag zaehlt)
+ (NSColor*) modalityColorForModality:(NSString*) modality
{
    if( [modality length] == 0) return nil;
    static NSSet *secondary = nil;
    if( secondary == nil) secondary = [[NSSet alloc] initWithObjects: @"SR", @"PR", @"KO", @"OT", @"SC", @"DOC", @"PDF", @"REG", @"SEG", @"RTSTRUCT", nil];
    NSArray *tokens = [[modality uppercaseString] componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"\\/,; "]];
    NSString *m = nil;
    for( NSString *t in tokens) if( t.length && ![secondary containsObject: t]) { m = t; break; }
    if( m == nil) for( NSString *t in tokens) if( t.length) { m = t; break; }
    if( m == nil) return nil;
    float r, g, b;
    if( [m isEqualToString: @"CT"]) { r = 0.25; g = 0.55; b = 1.00; }
    else if( [m isEqualToString: @"MR"]) { r = 0.70; g = 0.40; b = 1.00; }
    else if( [m isEqualToString: @"DX"] || [m isEqualToString: @"CR"] || [m isEqualToString: @"DR"] || [m isEqualToString: @"RG"]) { r = 0.30; g = 0.85; b = 0.40; }
    else if( [m isEqualToString: @"US"]) { r = 1.00; g = 0.65; b = 0.20; }
    else if( [m isEqualToString: @"XA"] || [m isEqualToString: @"RF"]) { r = 1.00; g = 0.35; b = 0.35; }
    else if( [m isEqualToString: @"NM"] || [m isEqualToString: @"PT"]) { r = 1.00; g = 0.90; b = 0.20; }
    else if( [m isEqualToString: @"MG"]) { r = 1.00; g = 0.45; b = 0.75; }
    else if( [m isEqualToString: @"ES"] || [m isEqualToString: @"XC"] || [m isEqualToString: @"OP"]) { r = 0.20; g = 0.80; b = 0.80; }
    else if( [secondary containsObject: m]) { r = 0.60; g = 0.60; b = 0.60; }
    else return nil;
    return [NSColor colorWithCalibratedRed: r green: g blue: b alpha: 0.22];
}

+ (void) placeWindow:(NSWindow*) w nearWindow:(NSWindow*) ref centered:(BOOL) centered
{
    if( w == nil || [w isVisible]) return;
    NSScreen *screen = ref.screen ? ref.screen : ([NSApp keyWindow].screen ? [NSApp keyWindow].screen : [NSScreen mainScreen]);
    NSRect area = [self areaForScreen: screen frame: [screen visibleFrame]];
    NSRect f = [w frame];
    if( centered) f.origin = NSMakePoint( NSMidX( area) - f.size.width / 2, NSMidY( area) - f.size.height / 2);
    else f.origin = NSMakePoint( NSMinX( area) + 24, NSMaxY( area) - f.size.height - 24);
    [w setFrameOrigin: f.origin];
}

+ (NSRect) areaForScreen:(NSScreen*) screen frame:(NSRect) f
{
    NSInteger idx = [[NSScreen screens] indexOfObject: screen];
    if( idx == NSNotFound) return f;

    NSString *key = [NSString stringWithFormat: @"%d", (int) idx];
    NSInteger mode = [[[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreasKey] objectForKey: key] integerValue];

    switch( mode)
    {
        case SekhmetAreaLeftHalf:      f.size.width = f.size.width / 2.; break;
        case SekhmetAreaRightHalf:     f.origin.x += f.size.width / 2.; f.size.width = f.size.width / 2.; break;
        case SekhmetAreaLeftTwoThirds: f.size.width = f.size.width * 2. / 3.; break;
        case SekhmetAreaRightTwoThirds: f.origin.x += f.size.width / 3.; f.size.width = f.size.width * 2. / 3.; break;
        case SekhmetAreaCenterHalf:    f.origin.x += f.size.width / 4.; f.size.width = f.size.width / 2.; break;
        case SekhmetAreaPixelRect:
        {
            NSString *r = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreaRectsKey] objectForKey: key];
            NSArray *c = [r componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @" ,;"]];
            NSMutableArray *nums = [NSMutableArray array];
            for( NSString *s in c) if( s.length) [nums addObject: s];
            if( nums.count == 4)
            {
                NSRect p = NSMakeRect( f.origin.x + [[nums objectAtIndex: 0] floatValue], f.origin.y + [[nums objectAtIndex: 1] floatValue], [[nums objectAtIndex: 2] floatValue], [[nums objectAtIndex: 3] floatValue]);
                p = NSIntersectionRect( p, f);
                if( p.size.width > 200 && p.size.height > 200) f = p;
            }
            break;
        }
        default: break;
    }
    return f;
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES]; // SekhVet: innerhalb der Viewer-Flaeche
    [super showWindow: sender];
}

- (id) init
{
    NSUInteger n = [[NSScreen screens] count];
    float h = 484 + 32 * n; // SekhVet Paket N: zwei Abschnitte mehr; Paket P: Zoom-Zeile; Paket AH: Magnetic-Zeile
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 620, h)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Display", nil)];
    [w setReleasedWhenClosed: NO];

    self = [super initWithWindow: w];
    if( self)
    {
        areaPopups = [[NSMutableArray alloc] init];
        rectFields = [[NSMutableArray alloc] init];
        [[NSColorPanel sharedColorPanel] setShowsAlpha: YES]; // SekhVet Paket N: Kastendeckung
        [self buildUI];
        [self loadFromDefaults];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [areaPopups release];
    [rectFields release];
    [super dealloc];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text];
    [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 12]];
    return t;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float y = [cv frame].size.height - 36;

    [cv addSubview: [self label: NSLocalizedString( @"Viewer area per screen (tiling and toolbar respect it):", nil) frame: NSMakeRect( 20, y, 590, 20) bold: YES]];
    y -= 30;

    NSArray *screens = [NSScreen screens];
    for( NSUInteger i = 0; i < screens.count; i++)
    {
        NSScreen *s = [screens objectAtIndex: i];
        NSString *name = [NSString stringWithFormat: NSLocalizedString( @"Screen %d (%.0f × %.0f)", nil), (int) i + 1, s.frame.size.width, s.frame.size.height];
        [cv addSubview: [self label: name frame: NSMakeRect( 20, y + 2, 200, 20) bold: NO]];

        NSPopUpButton *pb = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 225, y - 2, 220, 26) pullsDown: NO] autorelease];
        [pb addItemsWithTitles: [SekhmetDisplayPanel areaModeNames]];
        [pb setTag: i]; [pb setTarget: self]; [pb setAction: @selector(areaChanged:)];
        [cv addSubview: pb];
        [areaPopups addObject: pb];

        NSTextField *tf = [[[NSTextField alloc] initWithFrame: NSMakeRect( 455, y, 150, 22)] autorelease];
        [tf setPlaceholderString: @"x y b h"];
        [tf setTag: i]; [tf setTarget: self]; [tf setAction: @selector(rectChanged:)];
        [tf setFont: [NSFont systemFontOfSize: 12]];
        [cv addSubview: tf];
        [rectFields addObject: tf];
        y -= 32;
    }

    y -= 14;
    [cv addSubview: [self label: NSLocalizedString( @"Annotations (corner text and ROI measurements):", nil) frame: NSMakeRect( 20, y, 400, 20) bold: YES]];
    annotationPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 400, y - 4, 205, 26) pullsDown: NO] autorelease];
    [annotationPopup addItemsWithTitles: [NSArray arrayWithObjects:
                                          NSLocalizedString( @"Like SekhVet (1 px shadow)", nil),
                                          NSLocalizedString( @"Outline", nil),
                                          NSLocalizedString( @"Semi-transparent box", nil),
                                          NSLocalizedString( @"Outline and box", nil), nil]];
    [annotationPopup setTarget: self]; [annotationPopup setAction: @selector(annotationChanged:)];
    [cv addSubview: annotationPopup];

    // SekhVet Paket N: Messtext (Schrift, Groesse, Textfarbe, Kastenfarbe)
    y -= 34;
    [cv addSubview: [self label: NSLocalizedString( @"ROI measurement text:", nil) frame: NSMakeRect( 20, y, 180, 20) bold: YES]];
    fontPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 200, y - 4, 150, 26) pullsDown: NO] autorelease];
    for( int i = 0; i < SEKHMET_FONT_COUNT; i++) [fontPopup addItemWithTitle: sekhmetFontTitles[i]];
    [fontPopup setTarget: self]; [fontPopup setAction: @selector(fontChanged:)];
    [cv addSubview: fontPopup];
    [cv addSubview: [self label: NSLocalizedString( @"Size", nil) frame: NSMakeRect( 360, y + 2, 35, 20) bold: NO]];
    fontSizeField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 395, y, 50, 22)] autorelease];
    [fontSizeField setFont: [NSFont systemFontOfSize: 12]]; [fontSizeField setTarget: self]; [fontSizeField setAction: @selector(fontChanged:)];
    [cv addSubview: fontSizeField];
    [cv addSubview: [self label: NSLocalizedString( @"(SekhVet: Geneva 12)", nil) frame: NSMakeRect( 455, y + 2, 150, 20) bold: NO]];
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Text color", nil) frame: NSMakeRect( 36, y + 2, 90, 20) bold: NO]];
    textColorPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 125, y - 2, 135, 26) pullsDown: NO] autorelease];
    [textColorPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"ROI color (SekhVet)", nil), NSLocalizedString( @"White", nil), NSLocalizedString( @"Yellow", nil), NSLocalizedString( @"Custom", nil), nil]];
    [textColorPopup setTarget: self]; [textColorPopup setAction: @selector(textColorModeChanged:)];
    [cv addSubview: textColorPopup];
    textColorWell = [[[NSColorWell alloc] initWithFrame: NSMakeRect( 268, y, 44, 22)] autorelease];
    [textColorWell setTarget: self]; [textColorWell setAction: @selector(textColorWellChanged:)];
    [cv addSubview: textColorWell];
    [cv addSubview: [self label: NSLocalizedString( @"Box color", nil) frame: NSMakeRect( 330, y + 2, 75, 20) bold: NO]];
    boxColorWell = [[[NSColorWell alloc] initWithFrame: NSMakeRect( 405, y, 44, 22)] autorelease];
    [boxColorWell setTarget: self]; [boxColorWell setAction: @selector(boxColorWellChanged:)];
    [cv addSubview: boxColorWell];
    [cv addSubview: [self label: NSLocalizedString( @"(opacity = alpha)", nil) frame: NSMakeRect( 458, y + 2, 150, 20) bold: NO]];

    // SekhVet Paket N: Erscheinungsbild und Modalitaetsfarben
    y -= 36;
    [cv addSubview: [self label: NSLocalizedString( @"Appearance:", nil) frame: NSMakeRect( 20, y, 110, 20) bold: YES]];
    appearancePopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 130, y - 4, 150, 26) pullsDown: NO] autorelease];
    [appearancePopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"System", nil), NSLocalizedString( @"Light", nil), NSLocalizedString( @"Dark", nil), nil]];
    [appearancePopup setTarget: self]; [appearancePopup setAction: @selector(appearanceChanged:)];
    [cv addSubview: appearancePopup];
    modalityColorsButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 300, y, 310, 18)] autorelease];
    [modalityColorsButton setButtonType: NSButtonTypeSwitch];
    [modalityColorsButton setTitle: NSLocalizedString( @"Color database rows by modality", nil)];
    [modalityColorsButton setFont: [NSFont systemFontOfSize: 12]];
    [modalityColorsButton setTarget: self]; [modalityColorsButton setAction: @selector(modalityColorsChanged:)];
    [cv addSubview: modalityColorsButton];

    y -= 40;
    [cv addSubview: [self label: NSLocalizedString( @"3D-MPR:", nil) frame: NSMakeRect( 20, y, 200, 20) bold: YES]];
    y -= 24;
    syncButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease];
    [syncButton setButtonType: NSButtonTypeSwitch];
    [syncButton setTitle: NSLocalizedString( @"Sync MPR windows of the same study (point, planes, thickness; window level separate)", nil)];
    [syncButton setFont: [NSFont systemFontOfSize: 12]];
    [syncButton setTarget: self]; [syncButton setAction: @selector(syncChanged:)];
    [cv addSubview: syncButton];
    y -= 22;
    tileButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease];
    [tileButton setButtonType: NSButtonTypeSwitch];
    [tileButton setTitle: NSLocalizedString( @"Tile 3D windows automatically when opened", nil)];
    [tileButton setFont: [NSFont systemFontOfSize: 12]];
    [tileButton setTarget: self]; [tileButton setAction: @selector(tileChanged:)];
    [cv addSubview: tileButton];
    y -= 22;
    zoomSyncButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease]; // SekhVet Paket P
    [zoomSyncButton setButtonType: NSButtonTypeSwitch];
    [zoomSyncButton setTitle: NSLocalizedString( @"Zoom the three views of an MPR window together (between windows the zoom always follows per view)", nil)];
    [zoomSyncButton setFont: [NSFont systemFontOfSize: 12]];
    [zoomSyncButton setTarget: self]; [zoomSyncButton setAction: @selector(zoomSyncChanged:)];
    [cv addSubview: zoomSyncButton];
    y -= 22;
    staticCursorButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease];
    [staticCursorButton setButtonType: NSButtonTypeSwitch];
    [staticCursorButton setTitle: NSLocalizedString( @"MPR: plain arrow cursor (no tool / crosshair cursor symbols)", nil)];
    [staticCursorButton setFont: [NSFont systemFontOfSize: 12]];
    [staticCursorButton setTarget: self]; [staticCursorButton setAction: @selector(staticCursorChanged:)];
    [cv addSubview: staticCursorButton];
    y -= 22;
    magneticButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease]; // SekhVet Paket AH
    [magneticButton setButtonType: NSButtonTypeSwitch];
    [magneticButton setTitle: NSLocalizedString( @"Magnetic windows (snap to neighbours; hold Option while dragging to move freely)", nil)];
    [magneticButton setFont: [NSFont systemFontOfSize: 12]];
    [magneticButton setTarget: self]; [magneticButton setAction: @selector(magneticChanged:)];
    [cv addSubview: magneticButton];

    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"MPR crosshair hit zones (px):  center", nil) frame: NSMakeRect( 36, y + 2, 250, 20) bold: NO]];
    centerZoneField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 290, y, 50, 22)] autorelease];
    [centerZoneField setFont: [NSFont systemFontOfSize: 12]]; [centerZoneField setTarget: self]; [centerZoneField setAction: @selector(zonesChanged:)];
    [cv addSubview: centerZoneField];
    [cv addSubview: [self label: NSLocalizedString( @"line", nil) frame: NSMakeRect( 350, y + 2, 40, 20) bold: NO]];
    lineZoneField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 390, y, 50, 22)] autorelease];
    [lineZoneField setFont: [NSFont systemFontOfSize: 12]]; [lineZoneField setTarget: self]; [lineZoneField setAction: @selector(zonesChanged:)];
    [cv addSubview: lineZoneField];
    [cv addSubview: [self label: NSLocalizedString( @"(SekhVet: 10 / 10)", nil) frame: NSMakeRect( 450, y + 2, 150, 20) bold: NO]];

    y -= 44;
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y, 220, 30)] autorelease];
    [b setTitle: NSLocalizedString( @"Re-tile windows now", nil)];
    [b setBezelStyle: NSBezelStyleRounded];
    [b setTarget: self]; [b setAction: @selector(retile:)];
    [cv addSubview: b];
}

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *areas = [d dictionaryForKey: SekhmetScreenAreasKey];
    NSDictionary *rects = [d dictionaryForKey: SekhmetScreenAreaRectsKey];
    for( NSUInteger i = 0; i < areaPopups.count; i++)
    {
        NSString *key = [NSString stringWithFormat: @"%d", (int) i];
        [[areaPopups objectAtIndex: i] selectItemAtIndex: [SekhmetDisplayPanel indexForMode: [[areas objectForKey: key] integerValue]]];
        NSString *r = [rects objectForKey: key];
        [[rectFields objectAtIndex: i] setStringValue: r ? r : @""];
    }
    [annotationPopup selectItemAtIndex: [d integerForKey: SekhmetAnnotationBackgroundKey]];
    [syncButton setState: [d boolForKey: SekhmetMPRSyncKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [tileButton setState: [d boolForKey: SekhmetTile3DWindowsKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [zoomSyncButton setState: [d boolForKey: @"syncZoomLevelMPR"] ? NSControlStateValueOn : NSControlStateValueOff]; // SekhVet Paket P
    [staticCursorButton setState: [d boolForKey: @"SekhmetMPRStaticCursor"] ? NSControlStateValueOn : NSControlStateValueOff];
    [magneticButton setState: [d boolForKey: @"MagneticWindows"] ? NSControlStateValueOn : NSControlStateValueOff]; // SekhVet Paket AH
    [centerZoneField setIntegerValue: (NSInteger) [d floatForKey: @"SekhmetMPRCenterZone"]];
    [lineZoneField setIntegerValue: (NSInteger) [d floatForKey: @"SekhmetMPRLineZone"]];

    // SekhVet Paket N
    NSString *fn = [d stringForKey: @"LabelFONTNAME"];
    NSInteger fi = 0;
    for( int i = 0; i < SEKHMET_FONT_COUNT; i++) if( [sekhmetFontNames[i] isEqualToString: fn]) fi = i;
    [fontPopup selectItemAtIndex: fi];
    [fontSizeField setIntegerValue: (NSInteger) [d floatForKey: @"LabelFONTSIZE"]];
    [textColorPopup selectItemAtIndex: MIN( 3, MAX( 0, [d integerForKey: SekhmetROITextColorModeKey]))];
    [textColorWell setColor: [SekhmetDisplayPanel colorFromString: [d stringForKey: SekhmetROITextColorKey] fallback: [NSColor whiteColor]]];
    [boxColorWell setColor: [SekhmetDisplayPanel colorFromString: [d stringForKey: SekhmetAnnotationBoxColorKey] fallback: [NSColor colorWithCalibratedWhite: 0 alpha: 0.7]]];
    [appearancePopup selectItemAtIndex: MIN( 2, MAX( 0, [d integerForKey: SekhmetAppearanceKey]))];
    [modalityColorsButton setState: [d boolForKey: SekhmetModalityColorsKey] ? NSControlStateValueOn : NSControlStateValueOff];
}

+ (NSColor*) colorFromString:(NSString*) s fallback:(NSColor*) fb
{
    float r = 0, g = 0, b = 0, a = 1;
    int n = sscanf( [s UTF8String] ?: "", "%f %f %f %f", &r, &g, &b, &a);
    if( n < 3) return fb;
    return [NSColor colorWithCalibratedRed: r green: g blue: b alpha: a];
}

+ (NSString*) stringFromColor:(NSColor*) c withAlpha:(BOOL) withAlpha
{
    NSColor *s = [c colorUsingColorSpace: [NSColorSpace sRGBColorSpace]];
    if( s == nil) s = c;
    if( withAlpha) return [NSString stringWithFormat: @"%.3f %.3f %.3f %.3f", s.redComponent, s.greenComponent, s.blueComponent, s.alphaComponent];
    return [NSString stringWithFormat: @"%.3f %.3f %.3f", s.redComponent, s.greenComponent, s.blueComponent];
}

- (void) sekhmetRedrawViewers
{
    // Fonts neu bauen (fontHeight, Display-Listen) und alle Viewer zeichnen — Horos-Weg wie bei +/- Schriftgroesse
    [NSFont resetFont: 2];
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixLabelGLFontChangeNotification object: self];
}

- (IBAction) fontChanged:(id) sender
{
    NSInteger fi = MIN( SEKHMET_FONT_COUNT - 1, MAX( 0, [fontPopup indexOfSelectedItem]));
    [[NSUserDefaults standardUserDefaults] setObject: sekhmetFontNames[fi] forKey: @"LabelFONTNAME"];
    [[NSUserDefaults standardUserDefaults] setFloat: MIN( 60, MAX( 6, [fontSizeField floatValue])) forKey: @"LabelFONTSIZE"];
    [self loadFromDefaults];
    [self sekhmetRedrawViewers];
}

- (IBAction) textColorModeChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [textColorPopup indexOfSelectedItem] forKey: SekhmetROITextColorModeKey];
    [self sekhmetRedrawViewers];
}

- (IBAction) textColorWellChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setObject: [SekhmetDisplayPanel stringFromColor: [textColorWell color] withAlpha: NO] forKey: SekhmetROITextColorKey];
    [[NSUserDefaults standardUserDefaults] setInteger: 3 forKey: SekhmetROITextColorModeKey]; // eigene Farbe gewaehlt
    [self loadFromDefaults];
    [self sekhmetRedrawViewers];
}

- (IBAction) boxColorWellChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setObject: [SekhmetDisplayPanel stringFromColor: [boxColorWell color] withAlpha: YES] forKey: SekhmetAnnotationBoxColorKey];
    [self sekhmetRedrawViewers];
}

- (IBAction) appearanceChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [appearancePopup indexOfSelectedItem] forKey: SekhmetAppearanceKey];
    [SekhmetDisplayPanel applyAppearance];
}

- (IBAction) modalityColorsChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([modalityColorsButton state] == NSControlStateValueOn) forKey: SekhmetModalityColorsKey];
    [[[BrowserController currentBrowser] databaseOutline] setNeedsDisplay: YES];
}

+ (NSImage*) crosshairIcon // SekhVet Paket AH: Kreis mit vier Strichen und freier Mitte, wie ein Zielfernrohr
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage imageWithSize: NSMakeSize( 32, 32) flipped: NO drawingHandler: ^BOOL(NSRect r) {
        [[NSColor blackColor] set];
        NSPoint c = NSMakePoint( 16, 16);
        NSBezierPath *p = [NSBezierPath bezierPath];
        [p setLineWidth: 2.2];
        [p appendBezierPathWithOvalInRect: NSMakeRect( c.x - 10, c.y - 10, 20, 20)];
        [p moveToPoint: NSMakePoint( c.x, c.y + 14)]; [p lineToPoint: NSMakePoint( c.x, c.y + 4)];
        [p moveToPoint: NSMakePoint( c.x, c.y - 14)]; [p lineToPoint: NSMakePoint( c.x, c.y - 4)];
        [p moveToPoint: NSMakePoint( c.x + 14, c.y)]; [p lineToPoint: NSMakePoint( c.x + 4, c.y)];
        [p moveToPoint: NSMakePoint( c.x - 14, c.y)]; [p lineToPoint: NSMakePoint( c.x - 4, c.y)];
        [p stroke];
        [[NSBezierPath bezierPathWithOvalInRect: NSMakeRect( c.x - 1.5, c.y - 1.5, 3, 3)] fill];
        return YES;
    }] retain];
    [icon setTemplate: YES];
    return icon;
}

- (IBAction) magneticChanged:(id) sender // SekhVet Paket AH
{
    [[NSUserDefaults standardUserDefaults] setBool: ([magneticButton state] == NSControlStateValueOn) forKey: @"MagneticWindows"];
}

- (IBAction) staticCursorChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([staticCursorButton state] == NSControlStateValueOn) forKey: @"SekhmetMPRStaticCursor"];
}

- (IBAction) zonesChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setFloat: MAX( 3, [centerZoneField floatValue]) forKey: @"SekhmetMPRCenterZone"];
    [[NSUserDefaults standardUserDefaults] setFloat: MAX( 3, [lineZoneField floatValue]) forKey: @"SekhmetMPRLineZone"];
    [self loadFromDefaults];
}

- (IBAction) areaChanged:(id) sender
{
    NSMutableDictionary *areas = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreasKey]];
    [areas setObject: [NSNumber numberWithInteger: [SekhmetDisplayPanel modeForIndex: [sender indexOfSelectedItem]]] forKey: [NSString stringWithFormat: @"%d", (int) [sender tag]]];
    [[NSUserDefaults standardUserDefaults] setObject: areas forKey: SekhmetScreenAreasKey];
}

- (IBAction) rectChanged:(id) sender
{
    NSMutableDictionary *rects = [NSMutableDictionary dictionaryWithDictionary: [[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetScreenAreaRectsKey]];
    [rects setObject: [sender stringValue] forKey: [NSString stringWithFormat: @"%d", (int) [sender tag]]];
    [[NSUserDefaults standardUserDefaults] setObject: rects forKey: SekhmetScreenAreaRectsKey];
}

- (IBAction) annotationChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [annotationPopup indexOfSelectedItem] forKey: SekhmetAnnotationBackgroundKey];
}

- (IBAction) syncChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([syncButton state] == NSControlStateValueOn) forKey: SekhmetMPRSyncKey];
}

- (IBAction) zoomSyncChanged:(id) sender // SekhVet Paket P
{
    [[NSUserDefaults standardUserDefaults] setBool: ([zoomSyncButton state] == NSControlStateValueOn) forKey: @"syncZoomLevelMPR"]; // Paket Q: nur Horos-Zoomsync
}

- (IBAction) tileChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([tileButton state] == NSControlStateValueOn) forKey: SekhmetTile3DWindowsKey];
}

- (IBAction) retile:(id) sender
{
    [[AppController sharedAppController] tileWindows: nil];
    [[AppController sharedAppController] tile3DWindows: nil];
}

@end

#pragma mark - SekhVet Paket F: About

static SekhmetAbout *sekhmetAbout = nil;

@implementation SekhmetAbout

+ (SekhmetAbout*) shared
{
    if( sekhmetAbout == nil) sekhmetAbout = [[SekhmetAbout alloc] init];
    return sekhmetAbout;
}

// SekhVet Paket AA: Hinweis "kein zertifiziertes Medizinprodukt" beim ersten Start.
// Der Default merkt sich die BESTAETIGTE Textfassung — steigt die Zahl, kommt der Hinweis erneut.
#define SEKHMET_DISCLAIMER_VERSION 1

+ (void) showDisclaimerIfNeeded
{
#if SEKHVET_TESTHAKEN                               // nur Test-Build (Flag): Headless-Testlaeufe nie blockieren
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    if( [env objectForKey: @"SEKHVET_SKIP_DISCLAIMER"]) return;
    for( NSString *k in env)
        if( [k hasPrefix: @"SEKHVET_"] && [k hasSuffix: @"_TEST"]) return;
#endif

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d integerForKey: @"SekhmetDisclaimerAccepted"] >= SEKHMET_DISCLAIMER_VERSION) return;

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleInformational];
    [a setMessageText: NSLocalizedString( @"SekhVet is not a certified medical device", nil)];
    [a setInformativeText: NSLocalizedString(
        @"SekhVet is a veterinary DICOM viewer. It is not cleared by the FDA, not CE-marked and has not undergone any formal validation.\n\n"
        @"It is intended for use in veterinary medicine, research and education only and must not be used for the diagnosis or treatment of humans.\n\n"
        @"Measurements and orientation aids are tools; the interpretation of images and the diagnosis remain the responsibility of the veterinarian. "
        @"SekhVet is provided “as is”, without warranty of any kind (GNU LGPL v3).", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"I understand", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Quit", nil)];

    if( [a runModal] == NSAlertFirstButtonReturn)
        [d setInteger: SEKHMET_DISCLAIMER_VERSION forKey: @"SekhmetDisclaimerAccepted"];
    else
        [NSApp terminate: nil];
}

+ (void) openURLKey:(NSString*) key
{
    NSString *u = [[NSUserDefaults standardUserDefaults] stringForKey: key];
    if( u.length == 0)
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"Link not set yet", nil)];
        [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"Set it in Terminal:\ndefaults write %@ %@ \"https://…\"", nil), [[NSBundle mainBundle] bundleIdentifier], key]];
        [a runModal];
        return;
    }
    [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: u]];
}

- (IBAction) donate:(id) sender   { [[SekhmetContribute shared] showWindow: sender]; }  // SekhVet Paket AR: QR-Fenster statt Link
- (IBAction) voiceInk:(id) sender { [SekhmetAbout openURLKey: @"SekhmetVoiceInkURL"]; }

// SekhVet Paket AZ: Rueckmeldung per Mail — ohne Konto, mit allem, was man zum Nachstellen braucht.
// Screenshots aus der Praxis tragen Besitzer- und Tiernamen; darum der Hinweis in der Vorlage.
+ (NSString*) feedbackBody
{
    NSBundle *b = [NSBundle mainBundle];
    char model[64] = "";
    size_t len = sizeof( model);
    if( sysctlbyname( "hw.model", model, &len, NULL, 0) != 0) model[0] = 0;
#if defined(__arm64__)
    NSString *arch = @"Apple Silicon";
#else
    NSString *arch = @"Intel";
#endif
    return [NSString stringWithFormat: NSLocalizedString(
        @"What happened, or what would you like SekhVet to do?\n\n\n"
        @"If something went wrong, what steps were taken?\n1. \n2. \n3. \n\n"
        @"Please do not send screenshots that show owner or animal names. Crop them or anonymise the study first.\n\n"
        @"--\nSekhVet %@ (build %@)\n%@\nMac: %s (%@)\n", nil),
        [b objectForInfoDictionaryKey: @"CFBundleShortVersionString"], [b objectForInfoDictionaryKey: @"CFBundleVersion"],
        [[[NSProcessInfo processInfo] operatingSystemVersionString] stringByReplacingOccurrencesOfString: @"Version " withString: @"macOS "], model, arch];
}

- (IBAction) feedback:(id) sender
{
    NSString *to = [[NSUserDefaults standardUserDefaults] stringForKey: @"SekhmetFeedbackAddress"];
    if( to.length == 0) to = @"sekhvet@kappa1.vet";
    NSURLComponents *u = [[[NSURLComponents alloc] init] autorelease];
    u.scheme = @"mailto";
    u.path = to;
    u.queryItems = [NSArray arrayWithObjects:
                    [NSURLQueryItem queryItemWithName: @"subject" value: [NSString stringWithFormat: @"SekhVet feedback (build %@)", [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"]]],
                    [NSURLQueryItem queryItemWithName: @"body" value: [SekhmetAbout feedbackBody]], nil];
    if( u.URL && [[NSWorkspace sharedWorkspace] openURL: u.URL]) return;

    // Kein Mailprogramm eingerichtet: Adresse zeigen und die Vorlage in die Zwischenablage legen
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString: [SekhmetAbout feedbackBody] forType: NSPasteboardTypeString];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"No mail program found", nil)];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"Please write to %@. A template with your SekhVet and macOS version is on the clipboard.", nil), to]];
    [a runModal];
}
- (IBAction) source:(id) sender   { [SekhmetAbout openURLKey: @"SekhmetSourceURL"]; }
- (IBAction) license:(id) sender  { [[NSWorkspace sharedWorkspace] openURL: [NSURL URLWithString: @"https://www.gnu.org/licenses/lgpl-3.0.html"]]; }

- (NSTextField*) aboutLabel:(NSString*) text frame:(NSRect) r size:(float) size bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text]; [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: YES];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size]];
    [[t cell] setWraps: YES]; [[t cell] setLineBreakMode: NSLineBreakByWordWrapping];
    return t;
}

- (NSButton*) aboutButton:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title]; [b setBezelStyle: NSBezelStyleRounded]; [b setTarget: self]; [b setAction: sel];
    [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (id) init
{
    float W = 620, H = 470;   // SekhVet Paket AA: Platz fuer den Hinweis-Absatz
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, W, H)
                                                styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                  backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"About SekhVet", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self == nil) return nil;

    NSView *cv = [w contentView];
    NSImageView *iv = [[[NSImageView alloc] initWithFrame: NSMakeRect( 24, H - 104, 80, 80)] autorelease];
    [iv setImage: [NSApp applicationIconImage]]; [iv setImageScaling: NSImageScaleProportionallyUpOrDown];
    [cv addSubview: iv];

    NSString *ver = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
    NSString *build = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"];
    [cv addSubview: [self aboutLabel: @"SekhVet" frame: NSMakeRect( 120, H - 56, W - 140, 32) size: 24 bold: YES]];
    [cv addSubview: [self aboutLabel: [NSString stringWithFormat: NSLocalizedString( @"Veterinary DICOM viewer for macOS\nVersion %@ (build %@), based on Horos 4.0.0", nil), ver, build]
                                frame: NSMakeRect( 120, H - 92, W - 140, 34) size: 12 bold: NO]];
    [cv addSubview: [self aboutLabel: NSLocalizedString( @"© 2026 Kappa1-VRS GmbH, Switzerland", nil) frame: NSMakeRect( 120, H - 110, W - 140, 18) size: 11 bold: NO]];

    NSString *txt = NSLocalizedString(
        @"SekhVet is a veterinary DICOM viewer and is not a certified medical device. It is not cleared by the FDA, "
        @"not CE-marked and has not undergone any formal validation. It is intended for veterinary medicine, research "
        @"and education only and must not be used for the diagnosis or treatment of humans. Measurements are tools; "
        @"interpretation and diagnosis remain the responsibility of the veterinarian.\n\n"
        @"SekhVet is a veterinary fork of Horos (horosproject.org), which is based on OsiriX (Pixmeo SARL). "
        @"Horos and OsiriX are trademarks of their respective owners; portions © Horos Project and © OsiriX Foundation / Pixmeo.\n\n"
        @"SekhVet is free software under the GNU Lesser General Public License, version 3.0. It comes without any warranty. "
        @"The source code of this version, including all changes to Horos, is available at the address behind \"Source code\".\n\n"
        @"If SekhVet is useful to you, a contribution helps to keep it going. Dictation in SekhVet works well with VoiceInk (partner link).", nil);
    [cv addSubview: [self aboutLabel: txt frame: NSMakeRect( 24, 70, W - 48, H - 200) size: 12 bold: NO]];

    float bw = (W - 48 - 3 * 8) / 4, x = 24;
    [cv addSubview: [self aboutButton: NSLocalizedString( @"Contribute to SekhVet…", nil) frame: NSMakeRect( x, 22, bw, 30) action: @selector(donate:)]]; x += bw + 8;
    [cv addSubview: [self aboutButton: NSLocalizedString( @"VoiceInk…", nil) frame: NSMakeRect( x, 22, bw, 30) action: @selector(voiceInk:)]]; x += bw + 8;
    [cv addSubview: [self aboutButton: NSLocalizedString( @"Source code…", nil) frame: NSMakeRect( x, 22, bw, 30) action: @selector(source:)]]; x += bw + 8;
    [cv addSubview: [self aboutButton: NSLocalizedString( @"LGPL 3.0…", nil) frame: NSMakeRect( x, 22, bw, 30) action: @selector(license:)]];
    return self;
}

- (void) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: nil centered: YES];
    [super showWindow: sender];
}

@end

#pragma mark - SekhVet Paket AR: Beitrag (Zahlungs-QR)

// Beide QR-Bilder stecken als PNG im Quelltext. Grund: so ist kein Eintrag im Xcode-Projekt
// noetig, und die Zahlungsdaten bleiben byteidentisch zu dem, was PostFinance erzeugt hat
// (CHF: Swiss QR-Rechnung mit offenem Betrag; EUR: GiroCode/EPC-QR fuer SEPA).
static NSString * const kSekhmetQRCHF =
    @"iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQAAAADcA+lXAAAOm0lEQVR42u2dPWws13XHf3dniSUYCLsNEyDNbL2vTuViRikEBwFk"
    @"4mV3HhVDwFMhBMgr7MatZ+gyqqXGQMIm9tPMylg4RYA0GhZulCqFWA+bFGIzRABiaM6bk+LO187Hko+UTEGebfix5OF/L+8959z/"
    @"+Z+zSnjcY8RgYDAwGBgMDAYGA4OBwcBgYDDwHRhARERC/bkSsEKYiEgGrmdF0xggAyyJJokhGeLpn56IiEgLgT3PjYFn599TSn/c"
    @"Z9wC0PpO+G6ODDxVotQfE9K712BA8AQIcgMHpwAvYPHqG//64+PfHPs+q7Mvgb2ffLF8oX/oNRIArABu/7O+E00RkUwJbmhJzCRV"
    @"IiKeFU3jSWoIgCUiCYB4rohIsrUT4/IVhFH1Rb4GWefFLNlaxFn5O/a8+iI/IiPVZWB/y8CA4NtAcKXUGJATb34xn1xN3ijlFQjE"
    @"EPE4U/Or/UkGwJlSsz4ERMWnXoEAKVGn2Z1rwLwyEFIerPx3xqM712BA8PYIxtsInMvFpwf+3ug1PgTncLvJPliu18uF5x3aI39v"
    @"hL+NIHco0xiMTAm4Uj7AigAjBREPU0QkVSKeG8I03nIoMxr7X7+G4mWqDifcswbl664ZyKgOw53/hQHB4xGssC/D62MAh4X/Spvz"
    @"BVicXm6g3EcFgiIy5RtJQis0I50juXnuZIgoEc+SSG+dfCP1RabCqaryFVTBdf8+XrlwqlIzUIT35D5eeUDwcARTkRTAVfMLM7lR"
    @"SqE8MEUS3hjCiZzMzfhG6Z+3ROIdZ2HW3MrSldXtOAtx8zDVonN2n9M4IHgiBBdKKTUCZdtWNLuZpkoQZcPVDEYiSpR7Nr+apiNR"
    @"cKKUUvvd6X79LBTpflal+7Xg2nNfqJ8Fr0jzqnR/PLrLwIDgAQiQrQe4kZlvJCkcipHln8eT1JDGowWpSra9aie+xRpQpftedRbe"
    @"Yg0GBE+BoEp1jbTYPBETycCVMlsXnaFME1AinivhNKaZ6o7LJG3WTPeFZnCdzxovISanBsLKw1bpvqIZXKO4YWBA8KQI9N89PGLv"
    @"OWqJw+ry61+sRtnxcn3uBAvv+p9PyY6BhXX51a83eRLNfMbe0ZZLi6eSKhFcCTFFUpUzN/FUJFMiIqJ9nRJckXAaTxsuLSli67xw"
    @"qlVAldZLmM8a0bl80iYq3Hp14FRrEaOYZnD9M0ag98H5v3z24+yDpQOf8dHhs80RsCJYeOy954x++7nD4hmcvnO00Vze+adHzTuT"
    @"SGJkAFZoxhNJlYjgikiMIQKup8McSkQk1Btk+840Ln1imWQ1z0L1iDqytLT0ymWa1zwL1WPekScOCB6MIHco7zncytp3fA6j659n"
    @"x/8ODthc/uHdveeyxl8FPuGPNqPffOD4BOfzBosjMYDKEJEImKQqA1ckmsYTSfXuicyYSVYwOjmJ07p8UxBRqs4fSDM6t9ZgtrU+"
    @"BTVepviqGZ1b/4UBwWMQ6ADClRm/GaMy4GLO5OovUjgR5TG9mKEylKs8MwJkhJzIuzYwSWp8YhkbqRGSctZAsHVro0lIjrfXALyi"
    @"RJJ1ElHbBgYEj0GQW/zr09sNfB7AuQcgaxy8cHEK8CZY+88W3rXz8nYz8gmAw9XqqHHpinOH4uktojKQsKh4Ks3g6YonuKElhUcZ"
    @"N4JrPbEqS2XVVh5Xr7MnvNdTu9IrV4cprVY6aRTrBgRPiKDcSMkkRQlWqOsIGWVao1Mft3xCPCyJyFOc8iUkac4f1Jjts579D3Sk"
    @"eeOcwagZCPsVAo00b0DwKAQ1FkcXq0O04xBEPKsidyQ0IzD0XcgK+yUU1U5sl8oog+t8B39Q7t52sY4yuEY7GIwBwZ8eQb6RIiaJ"
    @"keVfRYUCQiRimhh6j1qRqVUS4rmhFdFkcfbHtW3azzUVCNr8QZLWDsr2I2sbm7cZjAHBEyKg5GDycGSFRQACK2QaY4hkuJ4VmfFE"
    @"pEiDmPbcmSo5UXUWUPcv1hFG1WEKG9H5PsW6AcEDEOR3ptsNe0eyxll8+qz4uwGLd+2D0+ynKau1lmH9/osjGUlw7ntc/yzeZvMw"
    @"tCZL377zi3gI0zI/NiMwihSnefkuw2xIzSfS8onjvjWguC/Y1LwyLa+c9v0XBgSPQZBvpOuXt//xx2MIFl9fhtcv937yReb4gfZH"
    @"P71dO/657/zbf4fI7367hnP/U/vqr5Kt0DZNNHODFZqFuE+XyDFSVF71yqljD7NJB85Kn1gnomjdG9NRM1svD1PhletUGK2b6zjr"
    @"uS8MCDj/+fWH7x/L2ofLbz7ZgFoC3uJVsAGMpThfs/gkCILf+RL43sK7frn344bceJLku6rKXnCLyKSlx+QORSQs4lLNoeyPm/xB"
    @"FyE5bgXgUSPdr2dwHZRo2grAT49gvAPBSXa4OthbjXYiGO9A8KsUH/yHr8EvufcaHK6O/m+NWrJicXrgvwYJAhalR/Jh8So8OOWP"
    @"zouV43Fox9fOcSMy6dJB6GohcLYl88vrT0lZZ4rMuOfSFYY1VdmFUlptIR0lkr7qv92SpXVF5/msV38QdhkYEOxEsNW/AODqArf+"
    @"TH9rkqmq8k0hykr6L9+zJgLVRtARXKtrX1wzYKWAtNegI7x3I7AfiyBkQHAngjJDkcTIa5RRoZqQCNwUJif6mmSKSIqOTGYjMs1a"
    @"SVadTuiQlcV9xXu7i07okJXN+uQDPzgEEwkNCR+FAJg/ag2AaCeCsvId57JzTF29RHC1PDiaSIbrgRljZCBevb4wahCUFNV/VaqB"
    @"oppTbWdp4yZBWVT/BU8+KvZ91cuzI08cEDwYQUXCpNqheJjFtVgiHRcmXobrWRIBRpHqNjKUSsxjb9NAdl3wfJ+zYIfbRFRYFzzf"
    @"5ywMCJ4SwZUav1FKFQjejPLntIcyREmIKQkZKKVs68LsVc5XX/yq9JEtBFHcV7yvr8EvSwStNZjP+uQD3zqCy/UjEZwfPxIBj10D"
    @"+K4R1CKTvjNZIiJJmeLoXLkoVE3KqtW0LzKFHcGxS07UXoOEVq2tYwlq6X6PV/5zRDDehcDsnTxUIShj48jPPnB8bPcyBHzWyzoC"
    @"fxVwenD6T9kxPiuI/tfhaEtuLKKlV56ri5nZlqBdX7okmSSU1PFEOjvr7HDeXria4LmveF87C1F94S7U7GZc63duF++/awTNjusf"
    @"JIJc3Pcs2DtSKxz/8C9fcvCv/xggBACnPyM7fu0HK4B33l+qpbOCcy/vEq+J+3Q3nUhIydYAZjxN0FSw7vk2yrqDSHeuHNJqCruP"
    @"nKjKE21aTWE7BU0DgpIWPtp7/zhzHBzvcGXHoFb/EPi+B1x/uBwhsHgVhLe/f/1mDXBoH/w62GyxOEWB2xKJzIRcQkFRKtBsXjxJ"
    @"8t8I22xeUinn40bxftRWA807GM1KOT9rFO+zthoo6mB1BwRPh6BJC4tX82NurY6gtTgYWY1c6B5nUpOVdUTqu3t5OmVl3HmcBwSP"
    @"QVBPRLJ8ZEjB+OYRJ4X88q1p4eKZ7n3QleXdp9u4q2udt+k2HhB8TxDcjJUINlyo/ZsxopRSNlNJjFQp4GzO1TRBifJO1BzyYsOO"
    @"2nu13avrf0tWvav6X+3/ioBoyaoHBN8LBJV/SQ3tkTRbo/PbkGnxBGCWlcw2HVjGRrvWFFb4xKyjaNsbncNaU1jhlUcdRdve6Dwg"
    @"eACC2lQalEiuzdNKcVePv8qH0li6WJ2RFy+l++5cqsLqFcuqx7N3DeKWLq1uoOoy7V2DAcH3AMHhex+vVksJAhavvjmFvecvluBx"
    @"aANqyZqFB7yzOpK1HwRcBl+d3m6aKlE9zkTzgWl9VJLeilpunPfwVq114yYBoaJWU1jXZJ64lxKtT63bMRto1qLCBgSPRXA2v1Jj"
    @"Q0Sw3bP5hVJjMUT0YDWd+gBc7EMmSjxXJL7qTXHKWlst/FW199HdAsey1kaXBiO7W+A4IHhrBDmbZ391qrJjWOFgx3t/v1FLAsBn"
    @"D2T9OcHC4vBvbzeyXLMgtK8/fu/4dYdDkRBL4olm8PKpjYYesiaRWbB5nqV7eDvnZBFtiTiak3mqs7DfP7WuKeapT+apzkLSP7Vu"
    @"QPBABLfBRq2WOF9z/XIGIx+8FZfhtfPh8xcrHA8OPtkw8vEJ4HLD6PV2I4xuU8ANMaNJYoiIJ2FBB+YN4BN9rfewKnqn2aYaqkpO"
    @"VByBEV3UeE+bql2TE7lnDa+8RY33NMoOCB6AoFILi2S5Q6kIPCgmOHp6H+i2cDCbuXLp4sL6hSxsISg7aTruC60xmNU0U1peuUMh"
    @"OSB4QgStQVtA3orgSj6BROvOdY9Clov7mgVLthtAt1txagjS7C4iijo13l6D8eguKmxA8HQIzrQ8fARYEs0mCWKIUhJyNQM9geRs"
    @"ztX0ysjgxAMz3r9Dp7qFoNVl2orObaXs1hq0ukxb0XlA8BgEeWibxoAYOYKbaSLoCY7T+EZXMk++jBBuMsDlzPyf2bSPP6A9WKeN"
    @"YN6bpdUU0101lrTqMt0fEHx/EBQ50tUM4xaEM8V0cjW+HeEKZxcKjDdj4UTCCyu6mWaCAqx4Gt+JwGuN+qK/aDvrU843Brb3Fm0H"
    @"BI9B0Jx2DqvLPzg8f7FcP/M4P/zRf52qTByClffR5ebvZL1cEcB87z1n9Lpn2nkEk5K0i6e6EgpWhL6U53NFuWPaecdVr56l0bsG"
    @"dkeNpRZP+yYwDAi+TQS6ge52jfJ9Fv4nG27XxhJWnP/CTuBNEAQL34vYnuBYTjvHDU2JivGhrp5CUUzuq1qtapP72oRk9RYSntU7"
    @"xTLa8R4U1VtIeP1TLOdN8f+A4DEIGu/HUrXtIuS9/3pX5D3bee9/1NG/0JgZV3VQdClde31idU4ET/q1tju88oDgwQhugzwyLRzP"
    @"/up0A8KC4Pzgs48/XCFfkD+fHbNi4X35N882PW8x5XpmZNb2jt4vFJ11STGoOO7TZIV2rebaZLZ3Fm1rg7pnjRpLya3vLBsPCB6O"
    @"QA1vijsYGAwMBgYDg4HBwGBgMDAY+GEa+H/Y0YPFO15sOgAAAABJRU5ErkJggg==";

static NSString * const kSekhmetQREUR =
    @"iVBORw0KGgoAAAANSUhEUgAAAgAAAAIAAQAAAADcA+lXAAAEeklEQVR42u2dza2jWBCFTxlLeIczwJnwMpgYJhJwZiaM3l0ygB1I"
    @"mDOLKrDd2zEtWjpsnt41/halUt36txH/7zlBAAEEEEAAAQQQQAABdgO0Fs9tsviAZmYGAPYDWjOcAQB2m9Z3zxKiAF8HFCRJuuJN"
    @"Zj9DRnKGq+Z0wr2ccb89DQD83V5CFOBIANfLR7EAyIhyBADzg5JkygnkC1DM/n45gg8AdZ+RJCVEAXYB5OQDtJ/hBOBpVo0gR2Mz"
    @"nFGTZJIQBfgrAJNZvd3+GdGZAZMZe+AezqmEKMD3AatuGVejapguqB7LCZ2BmC6GfDmhmF9qWBHAICEK8H3AYBGsT8Z7sQBDxqac"
    @"ga4gqiGjXYE6AXYD/N2rhCjA8Yxq9SqcEtXwohpyz0oBOYEZ/ldCFGCv6J1s1oNHTpIevftBfFKnNaqKYF/RuwBHBNQ9wJTT6pH2"
    @"AyOTK7rVXFBz/vzieiAhCvBFo8o3XeMDRtKtbKREyQYZmTKGN/B6JEQBjuYfsM/IlJOPfHFlDaMKrLpdzmAKZW/kHwiwh1F1Tfwo"
    @"iNac3ahWXMJT9UqUJ0wLGVUBDgoo3GSivbin2nQ5rRoBTKcomXr1H+0VwKA+FAG+f72HJqJkXO+921ByXM1u+LEp2lZ0vQtwSP+g"
    @"j/Cf0YfimazQbY7mfixJ9aEIsCegjaqT3TbH1KMidBeYFU9rihl3O4NtQVS90UologTYzya+ovcFNelJqEf+lqZKObd4STZRgOOp"
    @"skX4HwXRqrftNvf7PhqkmQBXdF3vAuxUMi0i74Tfs/vVuGZAvXi/de5JEwU4olFtCoZBHb0U1UT1f+vd9+o/4BGVcqoC7AHw4Tsm"
    @"IJr7zNj6aB4fU8ZmyGlRKjW7AnWnlKgAR22pyrjlVLdP01YhXQtVVNAlwK7ZfR93yhkHrnyfxfvXyJR7A9JEAY4H8Ok9r5ACQPE0"
    @"Jp/UJ0daA3i6H5N5+C//QIB9PFW7AkyTobUTAKNVa6t+TtrVVROA75xoJEQBdurN4+xz9b/3naJaK57pbVBfKVEBDgkYTsCQx84I"
    @"AK1ltFt4qm2x4H59WgPA7AJU3WnbKiEhCvD1jqh1/ilKpihnbAEUe/iEVMko7ytmEuDA/gE5enYfb935Mew3R7ffVteSKguwTyKq"
    @"Xzvz42mwHozRipc+vilPVYCD+gdrMn/bf1ZGsd9bqki+jGocSJUF+LYm2mf4//goK73XmQAAGt0X4MizfWRMnYyIoGtt7su94QpA"
    @"DKqod18A7LKZp/2Jf8tfAGALhivQGdgV9HG8ISfwPAPThSh6+JoeCVEAHHbHNJA/fcoUGVEOFlunntZ0ObVkSoA/tiK6Gr3thCk2"
    @"QnNcZ1DX7TxKRAmw1zbTT+2Mn4HIZnRFmMHhjPrfM1AmoP2HJxQSogA49LZztJcwm+UMuwH2A+B+zWi3La9qpDqiBNirzuQFUZ8R"
    @"WetM24RU/zYQpehdAPwFO6bNLkb2NKbn+09GAfebu66u6OpDEeCbAKNkIIAAAggggAACCCDAEQH/Aa8vROMwFRBmAAAAAElFTkSu"
    @"QmCC";

static NSString * const kSekhmetIBANCHF = @"CH80 0900 0000 1685 1476 9";
static NSString * const kSekhmetIBANEUR = @"CH96 0900 0000 1686 7414 3";
static NSString * const kSekhmetBIC     = @"POFICHBEXXX";

static SekhmetContribute *sekhmetContribute = nil;

@implementation SekhmetContribute

+ (SekhmetContribute*) shared
{
    if( sekhmetContribute == nil) sekhmetContribute = [[SekhmetContribute alloc] init];
    return sekhmetContribute;
}

+ (NSImage*) qrImage:(NSString*) base64
{
    NSData *d = [[[NSData alloc] initWithBase64EncodedString: base64 options: NSDataBase64DecodingIgnoreUnknownCharacters] autorelease];
    return [[[NSImage alloc] initWithData: d] autorelease];
}

- (void) copyString:(NSString*) s
{
    NSPasteboard *pb = [NSPasteboard generalPasteboard];
    [pb clearContents];
    [pb setString: [s stringByReplacingOccurrencesOfString: @" " withString: @""] forType: NSPasteboardTypeString];
}

- (IBAction) copyCHF:(id) sender { [self copyString: kSekhmetIBANCHF]; }
- (IBAction) copyEUR:(id) sender { [self copyString: kSekhmetIBANEUR]; }

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[SekhmetAbout shared] aboutButton: title frame: r action: sel];
    [b setTarget: self];   // aboutButton zielt auf SekhmetAbout, die Knoepfe hier gehoeren diesem Fenster
    return b;
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r size:(float) size bold:(BOOL) bold centered:(BOOL) centered
{
    NSTextField *t = [[SekhmetAbout shared] aboutLabel: text frame: r size: size bold: bold];
    if( centered) [t setAlignment: NSTextAlignmentCenter];
    return t;
}

- (id) init
{
    float W = 660, H = 575;   // Paket AR: hoeher wegen des laengeren Beitragstexts
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, W, H)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"Contribute to SekhVet", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self == nil) return nil;

    NSView *cv = [w contentView];

    [cv addSubview: [self label: NSLocalizedString( @"Contribute to SekhVet", nil)
                          frame: NSMakeRect( 24, H - 56, W - 48, 30) size: 20 bold: YES centered: NO]];

    [cv addSubview: [self label: NSLocalizedString(
        @"SekhVet is free software under the LGPL 3.0 licence, and it remains free of charge. Should you find it useful, "
        @"a voluntary contribution would be greatly appreciated and would help to ensure the continuation of this work.\n\n"
        @"Contributions are voluntary and there is no incentive to participate — all users receive the same software. "
        @"Scan the code with your banking app; the amount is yours to choose. There is no intermediary payment provider: "
        @"the transfer is made directly to the account of Kappa1-VRS GmbH.", nil)
                          frame: NSMakeRect( 24, H - 196, W - 48, 134) size: 12 bold: NO centered: NO]];

    float qr = 190, gap = 40, x1 = (W / 2 - qr - gap / 2), x2 = (W / 2 + gap / 2), qy = 168;

    NSImageView *ivCHF = [[[NSImageView alloc] initWithFrame: NSMakeRect( x1, qy, qr, qr)] autorelease];
    [ivCHF setImage: [SekhmetContribute qrImage: kSekhmetQRCHF]];
    [ivCHF setImageScaling: NSImageScaleProportionallyUpOrDown];
    [cv addSubview: ivCHF];

    NSImageView *ivEUR = [[[NSImageView alloc] initWithFrame: NSMakeRect( x2, qy, qr, qr)] autorelease];
    [ivEUR setImage: [SekhmetContribute qrImage: kSekhmetQREUR]];
    [ivEUR setImageScaling: NSImageScaleProportionallyUpOrDown];
    [cv addSubview: ivEUR];

    [cv addSubview: [self label: NSLocalizedString( @"Switzerland — CHF", nil) frame: NSMakeRect( x1, qy - 22, qr, 18) size: 12 bold: YES centered: YES]];
    [cv addSubview: [self label: NSLocalizedString( @"Euro area — EUR", nil)   frame: NSMakeRect( x2, qy - 22, qr, 18) size: 12 bold: YES centered: YES]];

    [cv addSubview: [self label: [NSString stringWithFormat: @"IBAN %@", kSekhmetIBANCHF] frame: NSMakeRect( x1 - 20, qy - 42, qr + 40, 16) size: 11 bold: NO centered: YES]];
    [cv addSubview: [self label: [NSString stringWithFormat: @"IBAN %@", kSekhmetIBANEUR] frame: NSMakeRect( x2 - 20, qy - 42, qr + 40, 16) size: 11 bold: NO centered: YES]];
    [cv addSubview: [self label: [NSString stringWithFormat: NSLocalizedString( @"BIC %@ (for transfers from abroad)", nil), kSekhmetBIC]
                          frame: NSMakeRect( 24, qy - 62, W - 48, 16) size: 11 bold: NO centered: YES]];
    [cv addSubview: [self label: NSLocalizedString( @"Kappa1-VRS GmbH, 8057 Zürich · Message: SekhVet contribution", nil)
                          frame: NSMakeRect( 24, qy - 80, W - 48, 16) size: 11 bold: NO centered: YES]];

    // SekhVet Paket BA: nur die Ueberweisung an die GmbH; kein Zahlungsanbieter (Entscheid 16.09.2026)
    float bw = 170, bx = (W - (2 * bw + 10)) / 2;
    [cv addSubview: [self button: NSLocalizedString( @"Copy CHF IBAN", nil) frame: NSMakeRect( bx, 22, bw, 30) action: @selector(copyCHF:)]]; bx += bw + 10;
    [cv addSubview: [self button: NSLocalizedString( @"Copy EUR IBAN", nil) frame: NSMakeRect( bx, 22, bw, 30) action: @selector(copyEUR:)]];

    return self;
}

- (void) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: nil centered: YES];
    [super showWindow: sender];
}

// Erinnerung: nie beim ersten Start, erst nach echter Nutzung, hoechstens zweimal, jederzeit abschaltbar.
+ (void) showReminderIfNeeded
{
#if SEKHVET_TESTHAKEN                               // Headless-Testlaeufe nie blockieren
    NSDictionary *env = [[NSProcessInfo processInfo] environment];
    for( NSString *k in env)
        if( [k hasPrefix: @"SEKHVET_"] && [k hasSuffix: @"_TEST"]) return;
#endif
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d boolForKey: @"SekhmetContributeNever"]) return;

    NSInteger launches = [d integerForKey: @"SekhmetContributeLaunches"] + 1;
    [d setInteger: launches forKey: @"SekhmetContributeLaunches"];

    double now = [NSDate timeIntervalSinceReferenceDate];
    double first = [d doubleForKey: @"SekhmetContributeFirstLaunch"];
    if( first <= 0) { [d setDouble: now forKey: @"SekhmetContributeFirstLaunch"]; return; }   // allererster Start: nur merken

    if( launches < 25) return;                                      // erst nach echter Nutzung
    if( now - first < 30 * 24 * 3600) return;                       // und fruehestens nach 30 Tagen
    if( now < [d doubleForKey: @"SekhmetContributeNextAsk"]) return;
    if( [d integerForKey: @"SekhmetContributeAsked"] >= 2) return;   // zweimal ist genug

    [self performSelector: @selector(runReminder) withObject: nil afterDelay: 3.0];  // erst wenn das Fenster steht
}

+ (void) runReminder
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleInformational];
    [a setMessageText: NSLocalizedString( @"Is SekhVet useful to you?", nil)];
    [a setInformativeText: NSLocalizedString(
        @"SekhVet is free software and stays free. A voluntary contribution helps to keep it going — it unlocks nothing, "
        @"every user receives the same software.\n\nThis message appears at most twice, and never again once you switch it off.", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Show me how…", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Not now", nil)];
    [a setShowsSuppressionButton: YES];
    [[a suppressionButton] setTitle: NSLocalizedString( @"Don't ask me again", nil)];

    NSModalResponse r = [a runModal];
    double now = [NSDate timeIntervalSinceReferenceDate];

    if( [[a suppressionButton] state] == NSControlStateValueOn)
        [d setBool: YES forKey: @"SekhmetContributeNever"];

    [d setInteger: [d integerForKey: @"SekhmetContributeAsked"] + 1 forKey: @"SekhmetContributeAsked"];
    [d setDouble: now + (r == NSAlertFirstButtonReturn ? 365 : 180) * 24 * 3600 forKey: @"SekhmetContributeNextAsk"];

    if( r == NSAlertFirstButtonReturn)
        [[SekhmetContribute shared] showWindow: nil];
}

@end

// SekhVet Paket BB: siehe Header.
void SekhmetSliderSetTickMarks(NSSlider* slider, NSInteger count)
{
    if( slider == nil) return;
    if( count < 0 || count > SEKHMET_SLIDER_MAX_TICKS) count = 0;
    if( [slider numberOfTickMarks] != count) [slider setNumberOfTickMarks: count];
    [slider setAllowsTickMarkValuesOnly: (count > 0)];
}
