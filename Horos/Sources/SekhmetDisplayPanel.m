/*=========================================================================
 Sekhmet — Anzeige-Einstellungen. Siehe Header.
 ============================================================================*/

#import "SekhmetDisplayPanel.h"
#import "SekhmetUeberlagerung.h" // SekhVet Paket CJ
#import "SekhmetMessNavigator.h" // SekhVet Paket DO
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#import "AppController.h"
#import "BrowserController.h" // SekhVet Paket N
#import "MyOutlineView.h"
#import "Notifications.h"
#import "NSFont_OpenGL.h"
#import "ROI.h"              // SekhVet Paket CD: Liniendicke
#import "ViewerController.h" // SekhVet Paket CD
#import "DCMView.h"          // SekhVet Paket CD
#import "ThumbnailsListPanel.h"     // SekhVet Paket EE: Breite der Miniaturen-Leiste
#import "NSUserDefaults+OsiriX.h"  // SekhVet Paket EE: Bildschirme fuer Viewer
#include <sys/sysctl.h> // SekhVet Paket AZ: Mac-Modell fuer die Feedback-Mail

NSString* const SekhmetScreenAreasKey = @"SekhmetScreenAreas";
NSString* const SekhmetScreenAreaRectsKey = @"SekhmetScreenAreaRects";
NSString* const SekhmetWorkplacesKey = @"SekhmetWorkplaces"; // SekhVet Paket EE
NSString* const SekhmetAnnotationBackgroundKey = @"SekhmetAnnotationBackground";
NSString* const SekhmetMPRSyncKey = @"SekhmetMPRSync";
NSString* const SekhmetMPRSyncWLWWKey = @"SekhmetMPRSyncWLWW"; // SekhVet Paket EC
NSString* const SekhmetMPRSyncSettingDidChangeNotification = @"SekhmetMPRSyncSettingDidChangeNotification"; // SekhVet Paket CS
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
- (void) buildUI;
- (void) commitEditingForRebuild;
- (void) screensChanged:(NSNotification*) n;
- (void) syncSettingChanged:(NSNotification*) n;
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

// SekhVet Paket EE: the areas are kept per workplace (the combination of connected monitors) and per monitor, the
// monitor known by vendor/model/serial instead of the display number macOS hands out (see SekhmetArbeitsplatz.h).
// Paket CS stored them under "id<NSScreenNumber>" and the index; those two keys are read once more, for the first
// workplace after the update, and then left alone.

static BOOL sekhmetWorkplacePending = YES;   // until the workplace is recognised (start, screen change): moves of the DB window are macOS rearranging, not the user
static NSString *sekhmetMonitorSignature = nil;
static NSArray *sekhmetMonitorCache = nil;

+ (NSDictionary*) monitorForScreen:(NSScreen*) s
{
    NSNumber *n = [[s deviceDescription] objectForKey: @"NSScreenNumber"];
    CGDirectDisplayID d = [n isKindOfClass: [NSNumber class]] ? [n unsignedIntValue] : 0;
    NSString *name = [s respondsToSelector: @selector(localizedName)] ? [s localizedName] : nil;
    NSRect f = [s frame];
    return [NSDictionary dictionaryWithObjectsAndKeys:
            [NSNumber numberWithUnsignedInt: d ? CGDisplayVendorNumber( d) : 0], @"vendor",
            [NSNumber numberWithUnsignedInt: d ? CGDisplayModelNumber( d) : 0], @"model",
            [NSNumber numberWithUnsignedInt: d ? CGDisplaySerialNumber( d) : 0], @"serial",
            name.length ? name : NSLocalizedString( @"Display", nil), @"name",
            [NSNumber numberWithDouble: f.origin.x], @"x", [NSNumber numberWithDouble: f.origin.y], @"y",
            [NSNumber numberWithDouble: f.size.width], @"w", [NSNumber numberWithDouble: f.size.height], @"h", nil];
}

// descriptions of [NSScreen screens], same order; kept until the screens (numbers or frames) change
+ (NSArray*) monitors
{
    NSArray *screens = [NSScreen screens];
    NSMutableString *sig = [NSMutableString string];
    for( NSScreen *s in screens) [sig appendFormat: @"%@ %@;", [[s deviceDescription] objectForKey: @"NSScreenNumber"], NSStringFromRect( [s frame])];
    if( sekhmetMonitorCache && [sig isEqualToString: sekhmetMonitorSignature]) return sekhmetMonitorCache;

    NSMutableArray *a = [NSMutableArray array];
    for( NSScreen *s in screens) [a addObject: [self monitorForScreen: s]];
#if SEKHVET_TESTHAKEN
    // "vendor:model:serial:name;..." (hex, hex, decimal) replaces the EDID of screen 1, 2, ... -- other monitors without a second screen
    const char *t = sekhvetTesthaken( "SEKHVET_MONITORE_TEST");
    if( t)
    {
        NSArray *eintraege = [[NSString stringWithUTF8String: t] componentsSeparatedByString: @";"];
        for( NSUInteger i = 0; i < a.count && i < eintraege.count; i++)
        {
            NSArray *p = [[eintraege objectAtIndex: i] componentsSeparatedByString: @":"];
            if( p.count < 4) continue;
            unsigned v = 0, m = 0;
            [[NSScanner scannerWithString: [p objectAtIndex: 0]] scanHexInt: &v];
            [[NSScanner scannerWithString: [p objectAtIndex: 1]] scanHexInt: &m];
            NSMutableDictionary *d = [NSMutableDictionary dictionaryWithDictionary: [a objectAtIndex: i]];
            [d setObject: [NSNumber numberWithUnsignedInt: v] forKey: @"vendor"];
            [d setObject: [NSNumber numberWithUnsignedInt: m] forKey: @"model"];
            [d setObject: [NSNumber numberWithUnsignedInt: (unsigned) [[p objectAtIndex: 2] longLongValue]] forKey: @"serial"];
            [d setObject: [p objectAtIndex: 3] forKey: @"name"];
            [a replaceObjectAtIndex: i withObject: d];
        }
    }
#endif
    [sekhmetMonitorSignature release]; sekhmetMonitorSignature = [sig copy];
    [sekhmetMonitorCache release]; sekhmetMonitorCache = [a copy];
    return sekhmetMonitorCache;
}

+ (NSString*) monitorKeyForScreen:(NSScreen*) screen
{
    NSUInteger i = screen ? [[NSScreen screens] indexOfObject: screen] : NSNotFound;
    if( i == NSNotFound) return nil;
    NSArray *k = sekhmetMonitorKennungen( [self monitors]);
    return i < k.count ? [k objectAtIndex: i] : nil;
}

+ (NSString*) workplaceKey
{
    return sekhmetArbeitsplatzKennung( sekhmetMonitorKennungen( [self monitors]));
}

+ (NSString*) workplaceName
{
    NSArray *sortiert = [[self monitors] sortedArrayUsingComparator: ^NSComparisonResult( id a, id b) { return sekhmetMonitorLinksVorRechts( a, b); }];
    return [[sortiert valueForKey: @"name"] componentsJoinedByString: @" + "];
}

// "Screen 1 · DELL U2723QE (left)"
+ (NSString*) labelForScreenAtIndex:(NSUInteger) i
{
    NSArray *m = [self monitors];
    if( i >= m.count) return @"";
    NSString *lage = sekhmetMonitorLage( m, i);
    NSString *name = [[m objectAtIndex: i] objectForKey: @"name"];
    return lage ? [NSString stringWithFormat: @"%d · %@ (%@)", (int) i + 1, name, NSLocalizedString( lage, nil)] : [NSString stringWithFormat: @"%d · %@", (int) i + 1, name];
}

// before Paket EE: display number first, index as fallback -- only read for the first workplace
+ (id) legacyValueForScreen:(NSScreen*) screen defaultsKey:(NSString*) defaultsKey
{
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] dictionaryForKey: defaultsKey];
    NSNumber *n = [[screen deviceDescription] objectForKey: @"NSScreenNumber"];
    id v = [n isKindOfClass: [NSNumber class]] ? [d objectForKey: [NSString stringWithFormat: @"id%u", [n unsignedIntValue]]] : nil;
    NSUInteger idx = [[NSScreen screens] indexOfObject: screen];
    if( v == nil && idx != NSNotFound) v = [d objectForKey: [NSString stringWithFormat: @"%d", (int) idx]];
    return v;
}

+ (NSArray*) monitorKeysOfScreenNumbers:(NSArray*) nummern
{
    NSMutableArray *k = [NSMutableArray array];
    NSArray *screens = [NSScreen screens], *keys = sekhmetMonitorKennungen( [self monitors]);
    for( NSUInteger i = 0; i < screens.count && i < keys.count; i++)
    {
        NSNumber *n = [[[screens objectAtIndex: i] deviceDescription] objectForKey: @"NSScreenNumber"];
        if( n && [nummern containsObject: [NSNumber numberWithUnsignedInteger: [n unsignedIntegerValue]]]) [k addObject: [keys objectAtIndex: i]];
    }
    return k;
}

// the entry of the workplace connected now, created on first sight. The first entry ever (no SekhmetWorkplaces yet:
// first start after the update) takes over the areas and viewer screens set before; a later new workplace starts
// with the whole of every screen and all screens for viewers, and SekhVet offers once to set it up.
+ (NSDictionary*) workplaceEntry
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [self workplaceKey];
    NSDictionary *alle = [ud dictionaryForKey: SekhmetWorkplacesKey];
    NSDictionary *e = [alle objectForKey: key];
    if( [e isKindOfClass: [NSDictionary class]]) return e;

    NSMutableDictionary *areas = [NSMutableDictionary dictionary], *rects = [NSMutableDictionary dictionary];
    NSArray *nonViewer = [NSArray array];
    BOOL uebernahme = (alle == nil);
    if( uebernahme)
    {
        NSArray *screens = [NSScreen screens], *keys = sekhmetMonitorKennungen( [self monitors]);
        for( NSUInteger i = 0; i < screens.count && i < keys.count; i++)
        {
            id a = [self legacyValueForScreen: [screens objectAtIndex: i] defaultsKey: SekhmetScreenAreasKey];
            id r = [self legacyValueForScreen: [screens objectAtIndex: i] defaultsKey: SekhmetScreenAreaRectsKey];
            if( [a isKindOfClass: [NSNumber class]]) [areas setObject: a forKey: [keys objectAtIndex: i]];
            if( [r isKindOfClass: [NSString class]]) [rects setObject: r forKey: [keys objectAtIndex: i]];
        }
        nonViewer = [self monitorKeysOfScreenNumbers: [ud arrayForKey: @"NonViewerScreens"]];
    }
    NSMutableDictionary *n = [NSMutableDictionary dictionaryWithObjectsAndKeys: [self workplaceName], @"name", areas, @"areas", rects, @"rects",
                              nonViewer, @"nonViewer", [NSNumber numberWithBool: uebernahme || [[NSScreen screens] count] < 2], @"hinted", [NSDate date], @"used", nil];
    NSMutableDictionary *neu = [NSMutableDictionary dictionaryWithDictionary: alle];
    [neu setObject: n forKey: key];
    [ud setObject: neu forKey: SekhmetWorkplacesKey];
    NSLog( @"SekhVet workplace %@: %@ (%@), areas %@", uebernahme ? @"taken over" : @"new", key, [n objectForKey: @"name"], areas);
    return n;
}

+ (void) setWorkplaceField:(NSString*) field monitor:(NSString*) monitor value:(id) value   // monitor nil: value is the whole field
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    NSString *key = [self workplaceKey];
    NSMutableDictionary *e = [NSMutableDictionary dictionaryWithDictionary: [self workplaceEntry]];
    if( monitor)
    {
        NSMutableDictionary *f = [NSMutableDictionary dictionaryWithDictionary: [e objectForKey: field]];
        if( value) [f setObject: value forKey: monitor]; else [f removeObjectForKey: monitor];
        [e setObject: f forKey: field];
    }
    else if( value) [e setObject: value forKey: field];
    else [e removeObjectForKey: field];
    [e setObject: [NSDate date] forKey: @"used"];
    NSMutableDictionary *alle = [NSMutableDictionary dictionaryWithDictionary: [ud dictionaryForKey: SekhmetWorkplacesKey]];
    [alle setObject: e forKey: key];
    [ud setObject: alle forKey: SekhmetWorkplacesKey];
}

+ (NSString*) fieldForDefaultsKey:(NSString*) defaultsKey
{
    return [defaultsKey isEqualToString: SekhmetScreenAreaRectsKey] ? @"rects" : @"areas";
}

+ (id) storedValueForScreen:(NSScreen*) screen defaultsKey:(NSString*) defaultsKey
{
    NSString *m = [self monitorKeyForScreen: screen];
    if( m == nil) return nil;
    return [[[self workplaceEntry] objectForKey: [self fieldForDefaultsKey: defaultsKey]] objectForKey: m];
}

+ (void) storeValue:(id) value forScreen:(NSScreen*) screen defaultsKey:(NSString*) defaultsKey
{
    NSString *m = [self monitorKeyForScreen: screen];
    if( value == nil || m == nil) return;
    [self setWorkplaceField: [self fieldForDefaultsKey: defaultsKey] monitor: m value: value];
}

+ (NSInteger) modeForScreen:(NSScreen*) screen
{
    return [[self storedValueForScreen: screen defaultsKey: SekhmetScreenAreasKey] integerValue];   // nil -> 0 = SekhmetAreaFull
}

+ (void) setMode:(NSInteger) mode forScreen:(NSScreen*) screen
{
    if( [self monitorKeyForScreen: screen] == nil) return;
    [self storeValue: [NSNumber numberWithInteger: mode] forScreen: screen defaultsKey: SekhmetScreenAreasKey];
    if( sekhmetDisplayPanel) [sekhmetDisplayPanel loadFromDefaults];
}

// Horos keeps "Screens used for viewers" as display numbers (NonViewerScreens); they follow the workplace
+ (void) applyViewerScreens:(NSDictionary*) e
{
    NSArray *non = [e objectForKey: @"nonViewer"];
    if( ![non isKindOfClass: [NSArray class]]) return;
    NSMutableArray *nummern = [NSMutableArray array];
    NSArray *screens = [NSScreen screens], *keys = sekhmetMonitorKennungen( [self monitors]);
    for( NSUInteger i = 0; i < screens.count && i < keys.count; i++)
        if( [non containsObject: [keys objectAtIndex: i]])
            [nummern addObject: [NSNumber numberWithUnsignedInteger: [[[[screens objectAtIndex: i] deviceDescription] objectForKey: @"NSScreenNumber"] unsignedIntegerValue]]];
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if( ![nummern isEqualToArray: [ud arrayForKey: @"NonViewerScreens"]]) [ud setObject: nummern forKey: @"NonViewerScreens"];
}

+ (void) rememberViewerScreens
{
    [self setWorkplaceField: @"nonViewer" monitor: nil value: [self monitorKeysOfScreenNumbers: [[NSUserDefaults standardUserDefaults] arrayForKey: @"NonViewerScreens"]]];
}

+ (NSWindow*) databaseWindow
{
    NSWindow *w = [[BrowserController currentBrowser] window];
    return ([w isVisible] && ![w isMiniaturized] && ([w styleMask] & NSWindowStyleMaskFullScreen) == 0) ? w : nil;
}

+ (void) storeDatabaseFrame
{
    NSWindow *w = [self databaseWindow];
    if( sekhmetWorkplacePending || w == nil) return;
    NSString *f = NSStringFromRect( [w frame]);
    if( ![f isEqualToString: [[self workplaceEntry] objectForKey: @"db"]]) [self setWorkplaceField: @"db" monitor: nil value: f];
}

+ (void) windowMovedForWorkplace:(NSNotification*) n
{
    if( sekhmetWorkplacePending || [n object] != [self databaseWindow]) return;
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(storeDatabaseFrame) object: nil];
    [self performSelector: @selector(storeDatabaseFrame) withObject: nil afterDelay: 1];
}

+ (void) screensChangedForWorkplace:(NSNotification*) n
{
    sekhmetWorkplacePending = YES;
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(storeDatabaseFrame) object: nil];
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(recognizeWorkplace) object: nil];
    [self performSelector: @selector(recognizeWorkplace) withObject: nil afterDelay: 2];   // macOS moves the windows first
}

+ (void) startWorkplaces
{
    static BOOL gestartet = NO;
    if( gestartet) return;
    gestartet = YES;
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver: self selector: @selector(screensChangedForWorkplace:) name: NSApplicationDidChangeScreenParametersNotification object: nil];
    [nc addObserver: self selector: @selector(windowMovedForWorkplace:) name: NSWindowDidMoveNotification object: nil];
    [nc addObserver: self selector: @selector(windowMovedForWorkplace:) name: NSWindowDidResizeNotification object: nil];
    [self performSelector: @selector(recognizeWorkplace) withObject: nil afterDelay: 3];   // the database window is up by then
}

+ (void) recognizeWorkplace
{
    static NSString *letzter = nil;
    NSString *key = [self workplaceKey];
    NSDictionary *e = [self workplaceEntry];
    BOOL gewechselt = letzter && ![letzter isEqualToString: key];
    [letzter release]; letzter = [key retain];

    [self applyViewerScreens: e];
    NSWindow *w = [self databaseWindow];
    NSString *db = [e objectForKey: @"db"];
    if( w && [db isKindOfClass: [NSString class]])
    {
        NSRect r = NSRectFromString( db);
        CGFloat sichtbar = 0;
        for( NSScreen *s in [NSScreen screens])
        {
            NSRect i = NSIntersectionRect( r, [s visibleFrame]);
            sichtbar += i.size.width * i.size.height;
        }
        if( r.size.width > 100 && r.size.height > 100 && sichtbar >= 0.5 * r.size.width * r.size.height && !NSEqualRects( r, [w frame]))
            [w setFrame: r display: YES];
    }
    sekhmetWorkplacePending = NO;
    if( db == nil) [self storeDatabaseFrame];
    NSLog( @"SekhVet workplace recognised: %@ (%@)%@", key, [e objectForKey: @"name"], gewechselt ? @", changed -> re-tile" : @"");

    if( gewechselt && [[ViewerController getDisplayed2DViewers] count]) [[AppController sharedAppController] tileWindows: nil];
    if( sekhmetDisplayPanel && [[sekhmetDisplayPanel window] isVisible]) [sekhmetDisplayPanel loadFromDefaults];
    if( ![[e objectForKey: @"hinted"] boolValue]) [self offerSetupForNewWorkplace];
}

+ (void) offerSetupForNewWorkplace
{
#if SEKHVET_TESTHAKEN                               // test build only: never block a headless test run
    for( NSString *k in [[NSProcessInfo processInfo] environment])
        if( [k hasPrefix: @"SEKHVET_"]) return;
#endif
    NSWindow *w = [self databaseWindow];
    if( w == nil || [w attachedSheet]) return;   // asked the next time this workplace is recognised
    [self setWorkplaceField: @"hinted" monitor: nil value: [NSNumber numberWithBool: YES]];

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleInformational];
    [a setMessageText: NSLocalizedString( @"New monitor arrangement", nil)];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"SekhVet sees these monitors together for the first time: %@.\n\nViewers use the whole of every screen for now. To keep part of a screen free, for example half of the second monitor for the report, choose the viewer area per screen. SekhVet remembers it for this combination of monitors and uses it again whenever they are connected.", nil), [self workplaceName]]];
    [a addButtonWithTitle: NSLocalizedString( @"Set Up Screens…", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Keep Whole Screens", nil)];
    [a beginSheetModalForWindow: w completionHandler: ^( NSModalResponse r) {
        if( r != NSAlertFirstButtonReturn) return;
        [[SekhmetDisplayPanel shared] showWindow: nil];
        [[[SekhmetDisplayPanel shared] window] makeKeyAndOrderFront: nil];
        [SekhmetDisplayPanel identifyScreens];
    }];
}

// the area a viewer window stands for: the floating toolbar above it and the thumbnails list beside it belong to it
+ (NSRect) areaFrameOfWindow:(NSWindow*) w
{
    NSRect f = [w frame];
    if( [[w windowController] isKindOfClass: [ViewerController class]])
    {
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        if( [AppController USETOOLBARPANEL] || [d boolForKey: @"USEALWAYSTOOLBARPANEL2"]) f.size.height += 78;   // as usefullRectForScreen:
        if( [d boolForKey: @"UseFloatingThumbnailsList"] && [d boolForKey: @"SeriesListVisible"])
        {
            f.origin.x -= [ThumbnailsListPanel fixedWidth];
            f.size.width += [ThumbnailsListPanel fixedWidth];
        }
    }
    return f;
}

+ (BOOL) takeAreaFromWindow:(NSWindow*) w
{
    NSScreen *s = [w screen];
    CGFloat best = 0;
    if( s == nil)   // a window that is not on screen (yet): the screen it overlaps most
        for( NSScreen *c in [NSScreen screens])
        {
            NSRect i = NSIntersectionRect( [w frame], [c frame]);
            if( i.size.width * i.size.height > best) { best = i.size.width * i.size.height; s = c; }
        }
    if( s == nil) return NO;
    NSString *r = nil;
    NSInteger m = sekhmetFlaecheEinrasten( [self areaFrameOfWindow: w], [s visibleFrame], &r);
    if( m < 0) return NO;
    if( m == SekhmetAreaPixelRect) [self storeValue: r forScreen: s defaultsKey: SekhmetScreenAreaRectsKey];
    [self setMode: m forScreen: s];
    NSLog( @"SekhVet workplace: area of screen %@ taken from a window: mode %d %@", [self monitorKeyForScreen: s], (int) m, r ?: @"");
    return YES;
}

+ (void) identifyScreens
{
    NSArray *screens = [NSScreen screens], *namen = [self areaModeNames];
    NSMutableArray *fenster = [NSMutableArray array];
    for( NSUInteger i = 0; i < screens.count; i++)
    {
        NSScreen *s = [screens objectAtIndex: i];
        NSRect area = [self areaForScreen: s frame: [s visibleFrame]];
        NSInteger idx = [self indexForMode: [self modeForScreen: s]];
        NSString *flaeche = (idx >= 0 && idx < (NSInteger) namen.count) ? [namen objectAtIndex: idx] : @"";

        // the viewer area, tinted
        NSWindow *aw = [[NSWindow alloc] initWithContentRect: area styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO];
        [aw setOpaque: NO]; [aw setHasShadow: NO]; [aw setIgnoresMouseEvents: YES]; [aw setReleasedWhenClosed: NO];
        [aw setLevel: NSStatusWindowLevel];
        [aw setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient];
        [aw setBackgroundColor: [[NSColor systemBlueColor] colorWithAlphaComponent: 0.16]];
        [[aw contentView] setWantsLayer: YES];
        [[[aw contentView] layer] setBorderWidth: 6];
        [[[aw contentView] layer] setBorderColor: [[NSColor systemBlueColor] CGColor]];
        [fenster addObject: aw]; [aw release];

        // name, place and area in the middle of it
        NSRect lr = NSMakeRect( NSMidX( area) - 300, NSMidY( area) - 80, 600, 160);
        NSWindow *lw = [[NSWindow alloc] initWithContentRect: lr styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO];
        [lw setOpaque: NO]; [lw setHasShadow: YES]; [lw setIgnoresMouseEvents: YES]; [lw setReleasedWhenClosed: NO];
        [lw setLevel: NSStatusWindowLevel + 1];
        [lw setCollectionBehavior: NSWindowCollectionBehaviorCanJoinAllSpaces | NSWindowCollectionBehaviorTransient];
        [lw setBackgroundColor: [NSColor clearColor]];
        NSView *cv = [lw contentView];
        [cv setWantsLayer: YES];
        [[cv layer] setBackgroundColor: [[NSColor colorWithCalibratedWhite: 0 alpha: 0.82] CGColor]];
        [[cv layer] setCornerRadius: 18];
        NSTextField *t = [NSTextField labelWithString: [NSString stringWithFormat: @"%@\n%@: %@", [self labelForScreenAtIndex: i], NSLocalizedString( @"Viewer area", nil), flaeche]];
        [t setFrame: NSInsetRect( [cv bounds], 20, 24)];
        [t setFont: [NSFont boldSystemFontOfSize: 28]];
        [t setTextColor: [NSColor whiteColor]];
        [t setAlignment: NSTextAlignmentCenter];
        [t setMaximumNumberOfLines: 2];
        [[t cell] setLineBreakMode: NSLineBreakByTruncatingTail];
        [cv addSubview: t];
        [fenster addObject: lw]; [lw release];
    }
    for( NSWindow *w in fenster) [w orderFrontRegardless];
    dispatch_after( dispatch_time( DISPATCH_TIME_NOW, (int64_t) (3.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        for( NSWindow *w in fenster) [w orderOut: nil];
    });
}

#if SEKHVET_TESTHAKEN
// SEKHVET_ARBEITSPLATZ_TEST="<step>|<step>..." with the steps
//   show                 key, name, per screen key/mode/area, NonViewerScreens, DB frame
//   set:<mode>           area mode of screen 1
//   window:<x y w h>     "Use this window's position" with a window at that place (relative to the visible frame of screen 1)
//   viewer:<0|1>         screen 1 used for viewers (Horos setting)
//   db:<x y w h>         move the database window (absolute)
//   identify             show the screen labels
+ (void) debugWorkplaceFromEnvironment
{
    NSArray *schritte = [[NSString stringWithUTF8String: sekhvetTesthaken( "SEKHVET_ARBEITSPLATZ_TEST")] componentsSeparatedByString: @"|"];
    [self debugWorkplaceSteps: schritte];
}

+ (void) debugWorkplaceSteps:(NSArray*) schritte
{
    if( schritte.count == 0)
    {
        [[NSUserDefaults standardUserDefaults] synchronize];
        NSLog( @"Arbeitsplatz-Test: fertig");
        return;
    }
    NSString *schritt = [schritte objectAtIndex: 0], *arg = @"";
    NSRange dp = [schritt rangeOfString: @":"];
    if( dp.location != NSNotFound) { arg = [schritt substringFromIndex: dp.location + 1]; schritt = [schritt substringToIndex: dp.location]; }
    NSScreen *s0 = [[NSScreen screens] firstObject];
    NSArray *zahlen = [arg componentsSeparatedByString: @" "];
    NSRect r = zahlen.count == 4 ? NSMakeRect( [[zahlen objectAtIndex: 0] doubleValue], [[zahlen objectAtIndex: 1] doubleValue], [[zahlen objectAtIndex: 2] doubleValue], [[zahlen objectAtIndex: 3] doubleValue]) : NSZeroRect;

    if( [schritt isEqualToString: @"show"])
    {
        NSLog( @"Arbeitsplatz-Test: workplace '%@' name '%@' known %lu", [self workplaceKey], [self workplaceName], (unsigned long) [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetWorkplacesKey] count]);
        NSArray *screens = [NSScreen screens];
        for( NSUInteger i = 0; i < screens.count; i++)
        {
            NSScreen *s = [screens objectAtIndex: i];
            NSLog( @"Arbeitsplatz-Test: screen %d '%@' label '%@' mode %d area %@ visible %@", (int) i + 1, [self monitorKeyForScreen: s], [self labelForScreenAtIndex: i],
                  (int) [self modeForScreen: s], NSStringFromRect( [self areaForScreen: s frame: [s visibleFrame]]), NSStringFromRect( [s visibleFrame]));
        }
        NSLog( @"Arbeitsplatz-Test: NonViewerScreens %@ usedForViewers %d db %@", [[[NSUserDefaults standardUserDefaults] arrayForKey: @"NonViewerScreens"] componentsJoinedByString: @","],
              (int) [[[NSUserDefaults standardUserDefaults] screensUsedForViewers] count], [self databaseWindow] ? NSStringFromRect( [[self databaseWindow] frame]) : @"-");
    }
    else if( [schritt isEqualToString: @"set"]) [self setMode: [arg integerValue] forScreen: s0];
    else if( [schritt isEqualToString: @"window"])
    {
        NSRect v = [s0 visibleFrame];
        NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSOffsetRect( r, v.origin.x, v.origin.y) styleMask: NSWindowStyleMaskBorderless backing: NSBackingStoreBuffered defer: NO] autorelease];
        [w setReleasedWhenClosed: NO];
        [w setFrame: NSOffsetRect( r, v.origin.x, v.origin.y) display: NO];
        NSLog( @"Arbeitsplatz-Test: take from window %@ -> %d", NSStringFromRect( [w frame]), (int) [self takeAreaFromWindow: w]);
    }
    else if( [schritt isEqualToString: @"viewer"])
    {
        [[NSUserDefaults standardUserDefaults] screen: s0 setIsUsedForViewers: [arg boolValue]];   // the setter hands it to rememberViewerScreens (NSUserDefaults+OsiriX.mm)
    }
    else if( [schritt isEqualToString: @"db"]) [[self databaseWindow] setFrame: r display: YES];
    else if( [schritt isEqualToString: @"identify"]) [self identifyScreens];

    NSArray *rest = [schritte subarrayWithRange: NSMakeRange( 1, schritte.count - 1)];
    [self performSelector: @selector(debugWorkplaceSteps:) withObject: rest afterDelay: 2.5];   // DB frame is stored 1 s after the move
}
#endif

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
    if( [self monitorKeyForScreen: screen] == nil) return f;

    NSInteger mode = [self modeForScreen: screen];   // SekhVet Paket EE: per workplace and monitor

    switch( mode)
    {
        case SekhmetAreaLeftHalf: case SekhmetAreaRightHalf: case SekhmetAreaLeftTwoThirds: case SekhmetAreaRightTwoThirds: case SekhmetAreaCenterHalf:
            f = sekhmetFlaecheRechteck( mode, f);   // SekhVet Paket EE: same rectangles as "Use this window's position" snaps to
            break;
        case SekhmetAreaPixelRect:
        {
            NSString *r = [self storedValueForScreen: screen defaultsKey: SekhmetScreenAreaRectsKey];
            if( ![r isKindOfClass: [NSString class]]) r = nil;
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

+ (float) contentHeight   // one row per screen on top of the fixed part
{
    NSUInteger n = [[NSScreen screens] count];
    return 484 + 66 + 30 + 30 + 22 + 22 + 22 + 32 * n; // SekhVet Paket EE: Arbeitsplatz-Zeile (+22); Paket EC: WL/WW-Zeile (+22); Paket N: zwei Abschnitte mehr; Paket P: Zoom-Zeile; Paket AH: Magnetic-Zeile; Paket CD: Messungen (+66); Paket CF: Lupengroesse (+30); Paket CJ: Overlay-Tasten (+30); Paket DO: Navigator (+22)
}

- (id) init
{
    float h = [SekhmetDisplayPanel contentHeight];
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
        // SekhVet Paket CS (review findings 16 and 18): follow a changed screen list and the MPR-Sync toolbar button
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(screensChanged:) name: NSApplicationDidChangeScreenParametersNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(syncSettingChanged:) name: SekhmetMPRSyncSettingDidChangeNotification object: nil];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(navigatorSettingChanged:) name: SekhmetMessNavigatorDidChangeNotification object: nil]; // SekhVet Paket DO
    }
    return self;
}

- (void) dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [areaPopups release];
    [rectFields release];
    [super dealloc];
}

// SekhVet Paket CS (review finding 16): the rows "Screen 1, 2, ..." were built once for the screens present when the
// panel was first opened; a display connected later had no row. The panel has no nib, so the whole content is built
// again for the current screens (the window keeps its place, only its height follows the number of rows).
- (void) screensChanged:(NSNotification*) n
{
    NSWindow *w = [self window];
    [self commitEditingForRebuild];
    NSView *cv = [w contentView];
    for( NSView *s in [NSArray arrayWithArray: [cv subviews]]) [s removeFromSuperview];
    [areaPopups removeAllObjects];
    [rectFields removeAllObjects];
    [w setContentSize: NSMakeSize( 620, [SekhmetDisplayPanel contentHeight])];
    [self buildUI];
    [self loadFromDefaults];
}

- (void) commitEditingForRebuild
{
    NSWindow *w = [self window];
    if( [w makeFirstResponder: nil] == NO) [w endEditingFor: nil];
    [textColorWell deactivate];   // an active colour well must not be removed while the colour panel points at it
    [boxColorWell deactivate];
}

// SekhVet Paket CS (review finding 18): MPR-Sync was switched with the toolbar button of an MPR window
- (void) syncSettingChanged:(NSNotification*) n
{
    [syncButton setState: [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetMPRSyncKey] ? NSControlStateValueOn : NSControlStateValueOff];
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
    // SekhVet Paket EE: the areas belong to this combination of monitors and come back whenever it is connected
    y -= 22;
    NSTextField *wp = [self label: [NSString stringWithFormat: NSLocalizedString( @"Remembered for this workplace: %@", nil), [SekhmetDisplayPanel workplaceName]] frame: NSMakeRect( 20, y, 590, 18) bold: NO];
    [wp setFont: [NSFont systemFontOfSize: 11]];
    [wp setTextColor: [NSColor secondaryLabelColor]];
    [[wp cell] setLineBreakMode: NSLineBreakByTruncatingTail];
    [wp setToolTip: NSLocalizedString( @"Each combination of monitors keeps its own viewer areas, viewer screens and database window place. Monitors are recognised by model and serial number, not by the order macOS lists them in.", nil)];
    [cv addSubview: wp];
    y -= 30;

    NSArray *screens = [NSScreen screens];
    for( NSUInteger i = 0; i < screens.count; i++)
    {
        NSScreen *s = [screens objectAtIndex: i];
        NSTextField *nl = [self label: [SekhmetDisplayPanel labelForScreenAtIndex: i] frame: NSMakeRect( 20, y + 2, 200, 20) bold: NO]; // SekhVet Paket EE: name and place instead of "Screen 2 (2560 x 1440)"
        [[nl cell] setLineBreakMode: NSLineBreakByTruncatingTail];
        [nl setToolTip: [NSString stringWithFormat: @"%@ — %.0f × %.0f pt — %@", [SekhmetDisplayPanel labelForScreenAtIndex: i], s.frame.size.width, s.frame.size.height, [SekhmetDisplayPanel monitorKeyForScreen: s]]];
        [cv addSubview: nl];

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
                                          NSLocalizedString( @"Classic (1 px shadow)", nil),   // SekhVet Paket CS (review finding 9): mode 0 is the original Horos look, not "Like SekhVet"
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
    // SekhVet Paket CS (review finding 9): the hints named "SekhVet" where the original Horos values were meant (blind
    // Horos -> SekhVet replacement). "classic" = the original look (Geneva 12, text in the ROI color); the registered
    // defaults are Helvetica Bold 14, white text and crosshair zones 18 / 12 (DefaultsOsiriX.m).
    [cv addSubview: [self label: NSLocalizedString( @"(classic: Geneva 12)", nil) frame: NSMakeRect( 455, y + 2, 150, 20) bold: NO]];
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Text color", nil) frame: NSMakeRect( 36, y + 2, 90, 20) bold: NO]];
    textColorPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 125, y - 2, 135, 26) pullsDown: NO] autorelease];
    [textColorPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"ROI color (classic)", nil), NSLocalizedString( @"White", nil), NSLocalizedString( @"Yellow", nil), NSLocalizedString( @"Custom", nil), nil]];
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

    // SekhVet Paket CD: Liniendicke der Messungen (Horos kannte sie nur im ROI-Info-Fenster je ROI)
    // und die Lupe beim Messen (Paket CC).
    y -= 36;
    [cv addSubview: [self label: NSLocalizedString( @"Measurements:", nil) frame: NSMakeRect( 20, y, 180, 20) bold: YES]];
    measureLoupeButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 200, y + 1, 400, 18)] autorelease];
    [measureLoupeButton setButtonType: NSButtonTypeSwitch];
    [measureLoupeButton setTitle: NSLocalizedString( @"Magnified view in a corner while measuring", nil)];
    [measureLoupeButton setFont: [NSFont systemFontOfSize: 12]];
    [measureLoupeButton setTarget: self]; [measureLoupeButton setAction: @selector(measureLoupeChanged:)];
    [cv addSubview: measureLoupeButton];
    // SekhVet Paket DO: Messungen-Navigator (Vorschaubilder der Schichten mit Messung unter dem Bild)
    y -= 22;
    navigatorButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 200, y + 1, 400, 18)] autorelease];
    [navigatorButton setButtonType: NSButtonTypeSwitch];
    [navigatorButton setTitle: NSLocalizedString( @"Measurement navigator: thumbnails of the images with measurements", nil)];
    [navigatorButton setFont: [NSFont systemFontOfSize: 12]];
    [navigatorButton setToolTip: NSLocalizedString( @"A bar at the bottom of the 2D viewer shows every image of the series that has a measurement; a click goes there. Also switched by the toolbar button \"Measurements\".", nil)];
    [navigatorButton setTarget: self]; [navigatorButton setAction: @selector(navigatorChanged:)];
    [cv addSubview: navigatorButton];
    // SekhVet Paket CF (28.09.): Groesse der Lupe als eigener Punkt, Vorgabe um die Haelfte groesser (36 -> 55 %).
    // Gilt fuer beide Lupen (beim Messen und Shift), in 2D und MPR; die Pfeiltasten aendern denselben Wert.
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Magnifier size (of the shorter side):", nil) frame: NSMakeRect( 36, y + 2, 240, 20) bold: NO]];
    loupeSizePopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 276, y - 2, 90, 26) pullsDown: NO] autorelease];
    for( int pz = 25; pz <= 75; pz += 10)
    {
        [loupeSizePopup addItemWithTitle: [NSString stringWithFormat: @"%d %%", pz]];
        [[loupeSizePopup lastItem] setTag: pz];
    }
    [loupeSizePopup setTarget: self]; [loupeSizePopup setAction: @selector(loupeSizeChanged:)];
    [cv addSubview: loupeSizePopup];
    [cv addSubview: [self label: NSLocalizedString( @"(default: 55 %;  \u2191/\u2193 while it is shown)", nil) frame: NSMakeRect( 376, y + 2, 230, 20) bold: NO]];
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Line width (px):  lines", nil) frame: NSMakeRect( 36, y + 2, 150, 20) bold: NO]];
    lineThicknessPopup = [self thicknessPopup: NSMakeRect( 186, y - 2, 60, 26)];
    [cv addSubview: lineThicknessPopup];
    [cv addSubview: [self label: NSLocalizedString( @"areas", nil) frame: NSMakeRect( 254, y + 2, 45, 20) bold: NO]];
    regionThicknessPopup = [self thicknessPopup: NSMakeRect( 298, y - 2, 60, 26)];
    [cv addSubview: regionThicknessPopup];
    [cv addSubview: [self label: NSLocalizedString( @"arrows", nil) frame: NSMakeRect( 366, y + 2, 50, 20) bold: NO]];
    arrowThicknessPopup = [self thicknessPopup: NSMakeRect( 416, y - 2, 60, 26)];
    [cv addSubview: arrowThicknessPopup];
    NSButton *apply = [[[NSButton alloc] initWithFrame: NSMakeRect( 482, y - 4, 128, 30)] autorelease];
    [apply setTitle: NSLocalizedString( @"Apply to open", nil)];
    [apply setToolTip: NSLocalizedString( @"New measurements use these widths right away. This button also changes the measurements already drawn on the images in the open viewers.", nil)];
    [apply setBezelStyle: NSBezelStyleRounded];
    [apply setTarget: self]; [apply setAction: @selector(applyThicknessToOpenViewers:)];
    [cv addSubview: apply];

    // SekhVet Paket CJ: Tasten fuer "Overlay" (Serienstapel im Fenster). Vorgabe "<" und "y" (Paket CN, 30.09.2026: mit der Hochstelltaste fuer ">" verschwindet die Lupe);
    // q/w/e sind in Horos Pfeil, Fenster und Oval und bleiben es.
    y -= 36;
    [cv addSubview: [self label: NSLocalizedString( @"Overlay:", nil) frame: NSMakeRect( 20, y, 180, 20) bold: YES]];
    [cv addSubview: [self label: NSLocalizedString( @"next series key", nil) frame: NSMakeRect( 200, y + 1, 110, 20) bold: NO]];
    overlayNextField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 310, y, 34, 22)] autorelease];
    [cv addSubview: [self label: NSLocalizedString( @"previous", nil) frame: NSMakeRect( 356, y + 1, 70, 20) bold: NO]];
    overlayPrevField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 426, y, 34, 22)] autorelease];
    for( NSTextField *t in @[ overlayNextField, overlayPrevField])
    {
        [t setAlignment: NSTextAlignmentCenter]; [t setFont: [NSFont systemFontOfSize: 13]];
        [t setTarget: self]; [t setAction: @selector(overlayKeysChanged:)];
        [cv addSubview: t];
    }
    [cv addSubview: [self label: NSLocalizedString( @"(default: < and y)", nil) frame: NSMakeRect( 470, y + 1, 140, 20) bold: NO]];

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
    [syncButton setTitle: NSLocalizedString( @"Sync MPR windows of the same study (point, planes, thickness; window level only with WL/WW below)", nil)];
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
    wlwwSyncButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 36, y, 560, 18)] autorelease]; // SekhVet Paket EC
    [wlwwSyncButton setButtonType: NSButtonTypeSwitch];
    [wlwwSyncButton setTitle: NSLocalizedString( @"WL/WW: window level follows between MPR windows of the same modality", nil)];
    [wlwwSyncButton setFont: [NSFont systemFontOfSize: 12]];
    [wlwwSyncButton setTarget: self]; [wlwwSyncButton setAction: @selector(wlwwSyncChanged:)];
    [cv addSubview: wlwwSyncButton];
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
    [cv addSubview: [self label: NSLocalizedString( @"(default: 18 / 12)", nil) frame: NSMakeRect( 450, y + 2, 150, 20) bold: NO]];

    y -= 44;
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y, 220, 30)] autorelease];
    [b setTitle: NSLocalizedString( @"Re-tile windows now", nil)];
    [b setBezelStyle: NSBezelStyleRounded];
    [b setTarget: self]; [b setAction: @selector(retile:)];
    [cv addSubview: b];
    // SekhVet Paket EE
    NSButton *ident = [[[NSButton alloc] initWithFrame: NSMakeRect( 245, y, 160, 30)] autorelease];
    [ident setTitle: NSLocalizedString( @"Identify Screens", nil)];
    [ident setToolTip: NSLocalizedString( @"Shows the name, place and viewer area on every screen for a few seconds", nil)];
    [ident setBezelStyle: NSBezelStyleRounded];
    [ident setTarget: self]; [ident setAction: @selector(identify:)];
    [cv addSubview: ident];
    NSButton *take = [[[NSButton alloc] initWithFrame: NSMakeRect( 410, y, 200, 30)] autorelease];
    [take setTitle: NSLocalizedString( @"Use Front Viewer's Place", nil)];
    [take setToolTip: NSLocalizedString( @"Place a viewer window where viewers should go (for example the right half of the second monitor), then click: its screen gets that area. Close to a half or third, it snaps to it.", nil)];
    [take setBezelStyle: NSBezelStyleRounded];
    [take setTarget: self]; [take setAction: @selector(takeFromFrontViewer:)];
    [cv addSubview: take];
}

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSArray *screens = [NSScreen screens];
    for( NSUInteger i = 0; i < areaPopups.count && i < screens.count; i++)   // SekhVet Paket CS: row i = screen i at the time the rows were built (rebuilt on every screen change)
    {
        NSScreen *s = [screens objectAtIndex: i];
        NSInteger idx = [SekhmetDisplayPanel indexForMode: [SekhmetDisplayPanel modeForScreen: s]];
        if( idx < 0 || idx >= [[areaPopups objectAtIndex: i] numberOfItems]) idx = 0;   // SekhVet Paket CS: a stored value outside the list raised in selectItemAtIndex:
        [[areaPopups objectAtIndex: i] selectItemAtIndex: idx];
        NSString *r = [SekhmetDisplayPanel storedValueForScreen: s defaultsKey: SekhmetScreenAreaRectsKey];
        [[rectFields objectAtIndex: i] setStringValue: [r isKindOfClass: [NSString class]] ? r : @""];
    }
    [annotationPopup selectItemAtIndex: MIN( 3, MAX( 0, [d integerForKey: SekhmetAnnotationBackgroundKey]))];   // SekhVet Paket CS: clamped like the other popups
    [syncButton setState: [d boolForKey: SekhmetMPRSyncKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [tileButton setState: [d boolForKey: SekhmetTile3DWindowsKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [zoomSyncButton setState: [d boolForKey: @"syncZoomLevelMPR"] ? NSControlStateValueOn : NSControlStateValueOff]; // SekhVet Paket P
    [wlwwSyncButton setState: [d boolForKey: SekhmetMPRSyncWLWWKey] ? NSControlStateValueOn : NSControlStateValueOff]; // SekhVet Paket EC
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

    // SekhVet Paket CD
    [ROI saveDefaultSettings]; // was im ROI-Info-Fenster zuletzt eingestellt wurde, steht sonst erst beim Beenden in den Defaults
    [self selectThickness: [d floatForKey: @"ROIThickness"] in: lineThicknessPopup];
    [self selectThickness: [d floatForKey: @"ROIRegionThickness"] in: regionThicknessPopup];
    [self selectThickness: [d floatForKey: @"ROIArrowThickness"] in: arrowThicknessPopup];
    id lupe = [d objectForKey: @"SekhmetMessLupe"];
    [measureLoupeButton setState: (lupe == nil || [lupe boolValue]) ? NSControlStateValueOn : NSControlStateValueOff];
    [navigatorButton setState: [SekhmetMessNavigator eingeschaltet] ? NSControlStateValueOn : NSControlStateValueOff]; // SekhVet Paket DO

    // SekhVet Paket CJ
    [overlayNextField setStringValue: [d stringForKey: SekhmetOverlayKeyNextKey].length ? [d stringForKey: SekhmetOverlayKeyNextKey] : @"<"];
    [overlayPrevField setStringValue: [d stringForKey: SekhmetOverlayKeyPrevKey].length ? [d stringForKey: SekhmetOverlayKeyPrevKey] : @"y"];

    // SekhVet Paket CF: gespeicherte Groesse; ein mit den Pfeiltasten gesetzter Zwischenwert erscheint als eigener Eintrag
    float g = [d floatForKey: @"SekhmetLupeGroesse"];
    int pz = (g >= 0.15 && g <= 0.8 && fabsf( g - 0.36f) >= 0.0005f) ? (int) lroundf( g * 100) : 55; // 0,36 = alte Vorgabe (CF-2)
    for( NSInteger i = [loupeSizePopup numberOfItems] - 1; i >= 0; i--)
        if( [[loupeSizePopup itemAtIndex: i] tag] % 10 != 5) [loupeSizePopup removeItemAtIndex: i];
    if( [loupeSizePopup indexOfItemWithTag: pz] < 0)
    {
        NSInteger at = 0;
        while( at < [loupeSizePopup numberOfItems] && [[loupeSizePopup itemAtIndex: at] tag] < pz) at++;
        [loupeSizePopup insertItemWithTitle: [NSString stringWithFormat: @"%d %%", pz] atIndex: at];
        [[loupeSizePopup itemAtIndex: at] setTag: pz];
    }
    [loupeSizePopup selectItemWithTag: pz];
}

// SekhVet Paket CD: Liniendicke 1-10 px (Horos erlaubt im ROI-Info-Fenster bis 20; ein groesserer Wert erscheint als eigener Eintrag)
- (NSPopUpButton*) thicknessPopup:(NSRect) r
{
    NSPopUpButton *p = [[[NSPopUpButton alloc] initWithFrame: r pullsDown: NO] autorelease];
    for( int i = 1; i <= 10; i++) { [p addItemWithTitle: [NSString stringWithFormat: @"%d", i]]; [[p lastItem] setTag: i]; }
    [p setTarget: self]; [p setAction: @selector(thicknessChanged:)];
    return p;
}

- (void) selectThickness:(float) v in:(NSPopUpButton*) p
{
    NSInteger t = MIN( 20, MAX( 1, (NSInteger) roundf( v)));
    if( [p indexOfItemWithTag: t] < 0) { [p addItemWithTitle: [NSString stringWithFormat: @"%d", (int) t]]; [[p lastItem] setTag: t]; }
    [p selectItemWithTag: t];
}

- (IBAction) thicknessChanged:(id) sender
{
    // ROI haelt die Vorgaben in statischen Variablen und schreibt sie beim Beenden zurueck:
    // erst deren Stand sichern, dann die neuen Werte setzen und neu laden -- sonst ueberschriebe
    // das Beenden die Einstellung wieder.
    [ROI saveDefaultSettings];
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setFloat: [[lineThicknessPopup selectedItem] tag] forKey: @"ROIThickness"];
    [d setFloat: [[regionThicknessPopup selectedItem] tag] forKey: @"ROIRegionThickness"];
    [d setFloat: [[arrowThicknessPopup selectedItem] tag] forKey: @"ROIArrowThickness"];
    [ROI loadDefaultSettings];
}

- (IBAction) applyThicknessToOpenViewers:(id) sender
{
    [self thicknessChanged: sender];
    float linie = [[lineThicknessPopup selectedItem] tag], flaeche = [[regionThicknessPopup selectedItem] tag], pfeil = [[arrowThicknessPopup selectedItem] tag];
    NSInteger n = 0;
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
    {
        for( long m = 0; m <= [v maxMovieIndex]; m++)
            for( NSArray *bild in [v roiList: m])
                for( ROI *r in bild)
                {
                    ToolMode typ = [r type];
                    if( typ == tText || typ == tLayerROI) continue;   // Text: Dicke = Schriftgroesse; tTAGT ist eine Linienmessung
                    float t = typ == tPlain ? flaeche : (typ == tArrow ? pfeil : linie);
                    if( [r thickness] != t) { [r setThickness: t globally: NO]; n++; }
                }
        for( DCMView *iv in [v imageViews]) [iv setNeedsDisplay: YES];
    }
    NSLog( @"SekhVet: line width applied to %ld measurements in open viewers", (long) n);
}

- (IBAction) loupeSizeChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setFloat: [[loupeSizePopup selectedItem] tag] / 100.0f forKey: @"SekhmetLupeGroesse"];
}

- (IBAction) overlayKeysChanged:(id) sender // SekhVet Paket CJ: je ein Zeichen, leer = Vorgabe
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *a = [[overlayNextField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *b = [[overlayPrevField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    a = a.length ? [a substringToIndex: 1] : @"<";
    b = b.length ? [b substringToIndex: 1] : @"y";
    if( [a isEqualToString: b]) b = [a isEqualToString: @"y"] ? @"<" : @"y";
    [d setObject: a forKey: SekhmetOverlayKeyNextKey];
    [d setObject: b forKey: SekhmetOverlayKeyPrevKey];
    [overlayNextField setStringValue: a];
    [overlayPrevField setStringValue: b];
}

- (IBAction) measureLoupeChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: [measureLoupeButton state] == NSControlStateValueOn forKey: @"SekhmetMessLupe"];
}

- (IBAction) navigatorChanged:(id) sender // SekhVet Paket DO: offene Viewer und Symbolleisten folgen sofort
{
    [SekhmetMessNavigator setEingeschaltet: [navigatorButton state] == NSControlStateValueOn];
}

- (void) navigatorSettingChanged:(NSNotification*) n // SekhVet Paket DO: umgeschaltet per Symbolleiste oder "x" in der Leiste
{
    [navigatorButton setState: [SekhmetMessNavigator eingeschaltet] ? NSControlStateValueOn : NSControlStateValueOff];
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

+ (NSImage*) swapMPRIcon // SekhVet Paket BW-2: zwei Fensterrahmen nebeneinander, darueber ein Doppelpfeil
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage imageWithSize: NSMakeSize( 32, 32) flipped: NO drawingHandler: ^BOOL(NSRect r) {
        [[NSColor blackColor] set];
        NSBezierPath *f = [NSBezierPath bezierPath];
        [f setLineWidth: 2.0];
        [f appendBezierPathWithRect: NSMakeRect( 3, 4, 11, 14)];
        [f appendBezierPathWithRect: NSMakeRect( 18, 4, 11, 14)];
        [f stroke];
        NSBezierPath *a = [NSBezierPath bezierPath];
        [a setLineWidth: 2.0];
        [a moveToPoint: NSMakePoint( 7, 25)]; [a lineToPoint: NSMakePoint( 25, 25)];
        [a stroke];
        NSBezierPath *h = [NSBezierPath bezierPath];
        [h moveToPoint: NSMakePoint( 3, 25)]; [h lineToPoint: NSMakePoint( 9, 29.5)]; [h lineToPoint: NSMakePoint( 9, 20.5)]; [h closePath];
        [h moveToPoint: NSMakePoint( 29, 25)]; [h lineToPoint: NSMakePoint( 23, 29.5)]; [h lineToPoint: NSMakePoint( 23, 20.5)]; [h closePath];
        [h fill];
        return YES;
    }] retain];
    [icon setTemplate: YES];
    return icon;
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

- (NSScreen*) screenForRow:(NSInteger) row   // SekhVet Paket CS: the rows are rebuilt on every screen change, so row = current index
{
    NSArray *screens = [NSScreen screens];
    return (row >= 0 && row < (NSInteger) screens.count) ? [screens objectAtIndex: row] : nil;
}

- (IBAction) areaChanged:(id) sender
{
    [SekhmetDisplayPanel storeValue: [NSNumber numberWithInteger: [SekhmetDisplayPanel modeForIndex: [sender indexOfSelectedItem]]]
                          forScreen: [self screenForRow: [sender tag]] defaultsKey: SekhmetScreenAreasKey];
}

- (IBAction) identify:(id) sender // SekhVet Paket EE
{
    [SekhmetDisplayPanel identifyScreens];
}

- (IBAction) takeFromFrontViewer:(id) sender // SekhVet Paket EE
{
    NSWindow *w = [[ViewerController frontMostDisplayed2DViewer] window];
    if( w == nil || [SekhmetDisplayPanel takeAreaFromWindow: w] == NO)
    {
        NSBeep();
        return;
    }
    [self loadFromDefaults];
    [[AppController sharedAppController] tileWindows: nil];
    [SekhmetDisplayPanel identifyScreens];
}

- (IBAction) rectChanged:(id) sender
{
    [SekhmetDisplayPanel storeValue: [sender stringValue] forScreen: [self screenForRow: [sender tag]] defaultsKey: SekhmetScreenAreaRectsKey];
}

- (IBAction) annotationChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [annotationPopup indexOfSelectedItem] forKey: SekhmetAnnotationBackgroundKey];
}

- (IBAction) syncChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([syncButton state] == NSControlStateValueOn) forKey: SekhmetMPRSyncKey];
    [[NSNotificationCenter defaultCenter] postNotificationName: SekhmetMPRSyncSettingDidChangeNotification object: self];   // SekhVet Paket CS: the toolbar buttons of the open MPR windows follow
}

- (IBAction) zoomSyncChanged:(id) sender // SekhVet Paket P
{
    [[NSUserDefaults standardUserDefaults] setBool: ([zoomSyncButton state] == NSControlStateValueOn) forKey: @"syncZoomLevelMPR"]; // Paket Q: nur Horos-Zoomsync
}

- (IBAction) wlwwSyncChanged:(id) sender // SekhVet Paket EC: the toolbar switches of the open MPR windows follow by their binding
{
    [[NSUserDefaults standardUserDefaults] setBool: ([wlwwSyncButton state] == NSControlStateValueOn) forKey: SekhmetMPRSyncWLWWKey];
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
