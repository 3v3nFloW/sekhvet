/*=========================================================================
 SekhVet Paket DO — Messungen-Navigator im 2D-Viewer. Siehe Header.
 ============================================================================*/

#import "SekhmetMessNavigator.h"
#import "ViewerController.h"
#import "DCMView.h"
#import "DCMPix.h"
#import "ROI.h"
#import "MyPoint.h"
#import "Notifications.h"
#import "ToolbarPanel.h"
#import <objc/runtime.h>

NSString* const SekhmetMessNavigatorKey = @"SekhmetMessNavigator";
NSString* const SekhmetMessNavigatorToolbarItemIdentifier = @"SekhmetMessNavigator";
NSString* const SekhmetMessLoeschenToolbarItemIdentifier = @"SekhmetMessLoeschen";
NSString* const SekhmetMessNavigatorDidChangeNotification = @"SekhmetMessNavigatorDidChange";

static char kLeisteKey;                    // assoziiertes Objekt am ViewerController
static const CGFloat kBild = 64;           // Kantenlaenge einer Vorschau (pt)
static const CGFloat kAbstand = 6;
static const CGFloat kBeschriftung = 14;   // Schichtnummer unter der Vorschau
static const CGFloat kRand = 6;
static const CGFloat kKnopf = 22;
static const NSUInteger kMaxVorschauen = 400;   // mehr Schichten mit Messung zeigt die Leiste nicht (Pinsel-Segmentierungen)
// DO-4: der Viewer, in dessen Fenster zuletzt geklickt oder gerollt wurde (nicht gehalten; abmelden: setzt zurueck).
// Bei nebeneinander gekachelten Viewern zeigt die Symbolleiste nicht verlaesslich die des aktiven Viewers.
static ViewerController *letzterViewer = nil;
static id mausBeobachter = nil;

@class SekhmetMessNavigatorInhalt;

@interface ViewerController (SekhmetMessNavigator)   // DO-3
- (IBAction) sekhmetMessungenLoeschen:(id) sender;
@end

@interface ViewerController (SekhmetMessNavigatorHorosIntern)   // DO-6: in ViewerController.m implementiert, nicht im Header
+ (void) clearFrontMost2DViewerCache;
@end

@interface SekhmetMessNavigator ()
{
    ViewerController *viewer;                 // assign; abmelden: setzt nil
    NSScrollView *scroll;
    SekhmetMessNavigatorInhalt *inhalt;
    NSButton *schliessen, *loeschen;
    NSArray *schichten;                       // NSNumber: pix-Index, in Anzeigereihenfolge
    NSMutableDictionary *vorschauen;          // NSNumber pix-Index -> { key, image }
    NSString *signatur;                       // was zuletzt gezeigt wurde
    NSTimer *uhr;                             // Rueckfallebene: nicht jede ROI-Aenderung meldet sich
    NSView *beobachtet;                       // Superview, deren Rahmen beobachtet wird
}
- (id) initWithViewer:(ViewerController*) v;
- (void) pruefe;
- (void) loesen;
- (ViewerController*) viewer;
- (NSArray*) schichten;
- (NSImage*) vorschauFuerIndex:(long) i;
- (void) springeZuIndex:(long) i;
- (NSString*) tooltipFuerIndex:(long) i;
@end

#pragma mark - Inhalt (Dokument der Scrollansicht)

@interface SekhmetMessNavigatorInhalt : NSView
{
@public
    SekhmetMessNavigator *leiste;             // assign
    long gedrueckt;                           // Paket DO-2: Vorschaubild unter dem mouseDown, -1 = keins
}
- (NSRect) rahmenFuerPosition:(NSUInteger) k;
- (void) aktualisiereTooltips;
@end

@implementation SekhmetMessNavigatorInhalt

- (BOOL) isFlipped { return YES; }
- (BOOL) acceptsFirstMouse:(NSEvent*) e { return YES; }
- (BOOL) acceptsFirstResponder { return NO; }

- (NSRect) rahmenFuerPosition:(NSUInteger) k
{
    return NSMakeRect( k * (kBild + kAbstand), 0, kBild, kBild + kBeschriftung);
}

- (void) drawRect:(NSRect) dirty
{
    NSArray *s = [leiste schichten];
    ViewerController *v = [leiste viewer];
    if( v == nil) return;
    long aktuell = [[v imageView] curImage];
    long n = [[v pixList] count];
    BOOL flipped = [[v imageView] flippedData];
    NSDictionary *attr = @{ NSFontAttributeName: [NSFont systemFontOfSize: 10], NSForegroundColorAttributeName: [NSColor whiteColor] };
    for( NSUInteger k = 0; k < s.count; k++)
    {
        NSRect r = [self rahmenFuerPosition: k];
        if( NSIntersectsRect( r, dirty) == NO) continue;
        long i = [[s objectAtIndex: k] longValue];
        NSRect bild = NSMakeRect( r.origin.x, r.origin.y, kBild, kBild);
        NSImage *im = [leiste vorschauFuerIndex: i];
        if( im) [im drawInRect: bild fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1 respectFlipped: YES hints: nil];
        NSBezierPath *rand = [NSBezierPath bezierPathWithRect: NSInsetRect( bild, 0.5, 0.5)];
        if( i == aktuell) { [[NSColor systemYellowColor] set]; [rand setLineWidth: 2]; }
        else { [[NSColor colorWithCalibratedWhite: 0.55 alpha: 1] set]; [rand setLineWidth: 1]; }
        [rand stroke];
        // Schichtnummer wie in der Bildecke (1-basiert, Anzeigereihenfolge), dahinter die Zahl der Messungen
        long nummer = (flipped ? n - 1 - i : i) + 1;
        int zahl = 0;
        NSArray *rl = [v roiList];
        if( i < (long) rl.count) for( ROI *roi in [rl objectAtIndex: i]) if( [roi hidden] == NO) zahl++;
        NSString *text = zahl > 1 ? [NSString stringWithFormat: @"%ld · %d", nummer, zahl] : [NSString stringWithFormat: @"%ld", nummer];
        NSSize ts = [text sizeWithAttributes: attr];
        [text drawAtPoint: NSMakePoint( NSMidX( r) - ts.width / 2, kBild + 1) withAttributes: attr];
    }
}

- (long) indexBei:(NSEvent*) e
{
    NSPoint p = [self convertPoint: [e locationInWindow] fromView: nil];
    NSArray *s = [leiste schichten];
    for( NSUInteger k = 0; k < s.count; k++)
        if( NSPointInRect( p, [self rahmenFuerPosition: k])) return [[s objectAtIndex: k] longValue];
    return -1;
}

// Paket DO-2 (04.10.: "die Messung springt woanders hin"): jedes Mausereignis bleibt in der Leiste -- nichts
// davon darf ueber die Responder-Kette weiterlaufen. Gesprungen wird beim Loslassen ueber demselben Vorschaubild.
- (void) mouseDown:(NSEvent*) e { gedrueckt = [self indexBei: e]; }
- (void) mouseDragged:(NSEvent*) e { }
- (void) mouseUp:(NSEvent*) e
{
    long i = [self indexBei: e];
    if( i >= 0 && i == gedrueckt) [leiste springeZuIndex: i];
    gedrueckt = -1;
}
- (void) rightMouseDown:(NSEvent*) e { }
- (void) rightMouseUp:(NSEvent*) e { }
- (void) otherMouseDown:(NSEvent*) e { }
- (void) otherMouseUp:(NSEvent*) e { }

- (void) aktualisiereTooltips
{
    [self removeAllToolTips];
    NSArray *s = [leiste schichten];
    for( NSUInteger k = 0; k < s.count; k++)
        [self addToolTipRect: [self rahmenFuerPosition: k] owner: self userData: (void*) (intptr_t) [[s objectAtIndex: k] longValue]];
}

- (NSString*) view:(NSView*) view stringForToolTip:(NSToolTipTag) tag point:(NSPoint) point userData:(void*) data
{
    return [leiste tooltipFuerIndex: (long) (intptr_t) data];
}

@end

#pragma mark - Leiste

@implementation SekhmetMessNavigator

+ (BOOL) eingeschaltet
{
    id o = [[NSUserDefaults standardUserDefaults] objectForKey: SekhmetMessNavigatorKey];
    return o == nil || [o boolValue];
}

+ (void) syncToolbars
{
    BOOL an = [self eingeschaltet];
    for( ViewerController *v in [ViewerController get2DViewers])
        for( NSToolbarItem *it in [[v toolbar] items])
        {
            if( [[it itemIdentifier] isEqualToString: SekhmetMessNavigatorToolbarItemIdentifier] == NO) continue;
            NSSegmentedControl *seg = (NSSegmentedControl*) [it view];
            if( [seg isKindOfClass: [NSSegmentedControl class]] && [seg segmentCount] > 0 && [seg isSelectedForSegment: 0] != an)
                [seg setSelected: an forSegment: 0];
        }
}

+ (void) setEingeschaltet:(BOOL) an
{
    [[NSUserDefaults standardUserDefaults] setBool: an forKey: SekhmetMessNavigatorKey];
    for( ViewerController *v in [ViewerController get2DViewers]) [self aktualisiere: v];
    [self syncToolbars];
    [[NSNotificationCenter defaultCenter] postNotificationName: SekhmetMessNavigatorDidChangeNotification object: nil];
}

+ (void) beobachteMaus   // DO-4
{
    if( mausBeobachter) return;
    mausBeobachter = [[NSEvent addLocalMonitorForEventsMatchingMask: NSEventMaskLeftMouseDown | NSEventMaskRightMouseDown | NSEventMaskOtherMouseDown | NSEventMaskScrollWheel
                                                            handler: ^NSEvent*( NSEvent *e) {
        id wc = [[e window] windowController];
        if( [wc isKindOfClass: [ViewerController class]]) letzterViewer = wc;   // Klicks in die Symbolleisten-Tafel zaehlen nicht
        return e;
    }] retain];
}

+ (ViewerController*) aktiverViewerStatt:(ViewerController*) v   // DO-4: zuletzt angeklickter Viewer, sofern noch offen
{
    if( letzterViewer && [[ViewerController getDisplayed2DViewers] indexOfObjectIdenticalTo: letzterViewer] != NSNotFound) return letzterViewer;
    return v;
}

+ (void) aktualisiere:(ViewerController*) v
{
    if( v == nil || [v imageView] == nil) return;
    [self beobachteMaus];
    SekhmetMessNavigator *l = objc_getAssociatedObject( v, &kLeisteKey);
    if( l == nil)
    {
        if( [self eingeschaltet] == NO) return;   // abgeschaltet: gar nicht erst anlegen
        l = [[[SekhmetMessNavigator alloc] initWithViewer: v] autorelease];
        objc_setAssociatedObject( v, &kLeisteKey, l, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    [l pruefe];
}

+ (void) abmelden:(ViewerController*) v
{
    if( v == nil) return;
    if( letzterViewer == v) letzterViewer = nil;
    SekhmetMessNavigator *l = objc_getAssociatedObject( v, &kLeisteKey);
    if( l == nil) return;
    [l loesen];
    objc_setAssociatedObject( v, &kLeisteKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (NSButton*) knopf:(NSString*) symbol tip:(NSString*) tip action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect( 0, 0, kKnopf, kKnopf)] autorelease];
    [b setBordered: NO];
    [b setImage: [NSImage imageWithSystemSymbolName: symbol accessibilityDescription: tip]];
    [b setImageScaling: NSImageScaleProportionallyUpOrDown];
    [b setContentTintColor: [NSColor whiteColor]];
    [b setToolTip: tip];
    [b setTarget: self]; [b setAction: sel];
    return b;
}

- (id) initWithViewer:(ViewerController*) v
{
    self = [super initWithFrame: NSMakeRect( 0, 0, 200, kRand + kBild + kBeschriftung + kRand)];
    if( self == nil) return nil;
    viewer = v;
    schichten = [[NSArray alloc] init];
    vorschauen = [[NSMutableDictionary alloc] init];
    [self setWantsLayer: YES];
    [self setHidden: YES];

    scroll = [[NSScrollView alloc] initWithFrame: NSMakeRect( 0, 0, 100, kBild + kBeschriftung)];
    [scroll setDrawsBackground: NO];
    [scroll setBorderType: NSNoBorder];
    [scroll setHasHorizontalScroller: YES];
    [scroll setHasVerticalScroller: NO];
    [scroll setAutohidesScrollers: YES];
    [scroll setScrollerStyle: NSScrollerStyleOverlay];
    [[scroll contentView] setDrawsBackground: NO];
    inhalt = [[SekhmetMessNavigatorInhalt alloc] initWithFrame: NSMakeRect( 0, 0, 100, kBild + kBeschriftung)];
    inhalt->leiste = self;
    inhalt->gedrueckt = -1;
    [scroll setDocumentView: inhalt];
    [self addSubview: scroll];

    schliessen = [[self knopf: @"xmark.circle.fill" tip: NSLocalizedString( @"Hide the measurement navigator (show it again with the toolbar button \"Measurements\" or in Vet Tools › Display)", nil) action: @selector(schliessen:)] retain];
    loeschen = [[self knopf: @"trash" tip: NSLocalizedString( @"Delete all measurements of this series (locked ones stay; Cmd-Z brings them back)", nil) action: @selector(alleLoeschen:)] retain];
    [self addSubview: schliessen];
    [self addSubview: loeschen];

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    for( NSString *name in @[ OsirixROIChangeNotification, OsirixAddROINotification, OsirixRemoveROINotification, OsirixROIRemovedFromArrayNotification,
                              OsirixDCMUpdateCurrentImageNotification, OsirixChangeWLWWNotification])
        [nc addObserver: self selector: @selector(meldung:) name: name object: nil];
    uhr = [[NSTimer scheduledTimerWithTimeInterval: 1.0 target: self selector: @selector(tick:) userInfo: nil repeats: YES] retain];
    [uhr setTolerance: 0.3];
    return self;
}

// Haelt der Timer die Leiste, laeuft dealloc erst nach loesen -- dort wird alles abgebaut.
- (void) loesen
{
    viewer = nil;
    [NSObject cancelPreviousPerformRequestsWithTarget: self];
    [[NSNotificationCenter defaultCenter] removeObserver: self];
    [uhr invalidate]; [uhr release]; uhr = nil;
    [beobachtet release]; beobachtet = nil;
    [self removeFromSuperview];
}

- (void) dealloc
{
    [self loesen];
    inhalt->leiste = nil;
    [inhalt release]; [scroll release]; [schliessen release]; [loeschen release];
    [schichten release]; [vorschauen release]; [signatur release];
    [super dealloc];
}

- (BOOL) isFlipped { return YES; }
- (BOOL) acceptsFirstResponder { return NO; }
- (BOOL) acceptsFirstMouse:(NSEvent*) e { return YES; }
// Paket DO-2: Klicks auf den Rand der Leiste enden hier
- (void) mouseDown:(NSEvent*) e { }
- (void) mouseDragged:(NSEvent*) e { }
- (void) mouseUp:(NSEvent*) e { }
- (void) rightMouseDown:(NSEvent*) e { }
- (void) otherMouseDown:(NSEvent*) e { }
- (ViewerController*) viewer { return viewer; }
- (NSArray*) schichten { return schichten; }

- (void) drawRect:(NSRect) dirty
{
    [[NSColor colorWithCalibratedWhite: 0 alpha: 0.6] set];
    [[NSBezierPath bezierPathWithRoundedRect: [self bounds] xRadius: 6 yRadius: 6] fill];
}

- (void) meldung:(NSNotification*) n
{
    // viele Meldungen kommen in Schueben (Ziehen einer Messung): einmal nach dem Schub auffrischen
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(pruefe) object: nil];
    [self performSelector: @selector(pruefe) withObject: nil afterDelay: 0.15];
}

- (void) tick:(NSTimer*) t
{
    // ein Viewer, der ohne windowWillClose: verschwunden ist, darf nicht mehr angefasst werden
    if( viewer && [[ViewerController get2DViewers] indexOfObjectIdenticalTo: viewer] == NSNotFound) { [self loesen]; return; }
    [self pruefe];
}

#pragma mark Inhalt bestimmen

// Kennung der sichtbaren Messungen einer Schicht (nil = keine): Zeiger, Typ, Lage. Billig genug fuer den Sekundentakt;
// tPlain (Pinsel) liefert seine Punkte nur ueber eine Konturberechnung -- dort zaehlt nur der Rahmen.
+ (NSString*) signaturFuerROIs:(NSArray*) rois
{
    NSMutableString *s = nil;
    for( ROI *r in rois)
    {
        if( [r hidden]) continue;
        if( s == nil) s = [NSMutableString string];
        NSRect q = [r rect];
        [s appendFormat: @"%p/%d/%.1f,%.1f,%.1f,%.1f", r, (int) [r type], q.origin.x, q.origin.y, q.size.width, q.size.height];
        if( [r type] != tPlain && [r type] != tOval && [r type] != tROI && [r type] != t2DPoint)
        {
            NSArray *p = [r points];
            [s appendFormat: @"/%lu", (unsigned long) p.count];
            if( p.count)
            {
                NSPoint a = [[p firstObject] point], b = [[p lastObject] point], c = [[p objectAtIndex: p.count / 2] point];
                [s appendFormat: @"/%.1f,%.1f,%.1f,%.1f,%.1f,%.1f", a.x, a.y, b.x, b.y, c.x, c.y];
            }
        }
        [s appendString: @";"];
    }
    return s;
}

- (NSView*) zielAnsicht
{
    NSView *iv = [viewer imageView];
    NSView *serie = [iv superview];                 // SeriesView
    return [serie superview] ? [serie superview] : serie;   // StudyView: Geschwister ueber dem Bild, nicht im OpenGL-View
}

- (void) rahmenGeaendert:(NSNotification*) n
{
    if( [self isHidden] == NO) [self ordne];
}

- (void) ordne
{
    NSView *sv = [self superview];
    if( sv == nil) return;
    NSRect b = [sv bounds];
    CGFloat knoepfe = 2 * (kKnopf + kAbstand);
    CGFloat inhaltBreite = MAX( kBild, schichten.count * (kBild + kAbstand) - kAbstand);
    CGFloat breite = MIN( b.size.width - 20, inhaltBreite + knoepfe + 2 * kRand);
    breite = MAX( breite, MIN( b.size.width, kBild + knoepfe + 2 * kRand));
    CGFloat hoehe = kRand + kBild + kBeschriftung + kRand;
    CGFloat y = [sv isFlipped] ? NSMaxY( b) - hoehe - 8 : NSMinY( b) + 8;
    [self setFrame: NSMakeRect( NSMinX( b) + floor( (b.size.width - breite) / 2), y, breite, hoehe)];
    [schliessen setFrame: NSMakeRect( kRand, kRand, kKnopf, kKnopf)];
    [loeschen setFrame: NSMakeRect( breite - kRand - kKnopf, kRand + (kBild - kKnopf) / 2, kKnopf, kKnopf)];
    CGFloat sichtbar = breite - 2 * kRand - knoepfe;
    [scroll setFrame: NSMakeRect( kRand + kKnopf + kAbstand, kRand, sichtbar, kBild + kBeschriftung)];
    [inhalt setFrame: NSMakeRect( 0, 0, MAX( inhaltBreite, sichtbar), kBild + kBeschriftung)];
    [self setNeedsDisplay: YES];
}

- (void) pruefe
{
    if( viewer == nil) return;
    DCMView *iv = [viewer imageView];
    NSView *ziel = [self zielAnsicht];
    if( iv == nil || ziel == nil) return;
    if( [self superview] != ziel)
    {
        [self removeFromSuperview];
        [ziel addSubview: self positioned: NSWindowAbove relativeTo: nil];
        [[NSNotificationCenter defaultCenter] removeObserver: self name: NSViewFrameDidChangeNotification object: nil];
        [ziel setPostsFrameChangedNotifications: YES];
        [[NSNotificationCenter defaultCenter] addObserver: self selector: @selector(rahmenGeaendert:) name: NSViewFrameDidChangeNotification object: ziel];
        [beobachtet release]; beobachtet = [ziel retain];
        [signatur release]; signatur = nil;
    }
    else if( [[ziel subviews] lastObject] != self)   // Horos ordnet die Serienansicht neu (Kacheln): wieder nach oben
        [ziel addSubview: self positioned: NSWindowAbove relativeTo: nil];

    NSArray *pix = [viewer pixList];
    NSArray *rl = [viewer roiList];
    BOOL flipped = [iv flippedData];
    NSUInteger n = MIN( pix.count, rl.count);
    NSMutableArray *neu = [NSMutableArray array];
    NSMutableString *sig = [NSMutableString stringWithFormat: @"%p|%d|%.2f|%.2f|%.2f|%d%d|%.0f,%.0f|", pix, (int) [iv curImage], [iv curWW], [iv curWL], [iv rotation],
                            (int) [iv xFlipped], (int) [iv yFlipped], [ziel bounds].size.width, [ziel bounds].size.height];
    for( NSUInteger k = 0; k < n && neu.count < kMaxVorschauen; k++)
    {
        NSUInteger i = flipped ? n - 1 - k : k;
        NSString *s = [SekhmetMessNavigator signaturFuerROIs: [rl objectAtIndex: i]];
        if( s == nil) continue;
        [neu addObject: [NSNumber numberWithUnsignedInteger: i]];
        [sig appendFormat: @"%lu:%@", (unsigned long) i, s];
    }

    if( [SekhmetMessNavigator eingeschaltet] == NO || neu.count == 0)
    {
        if( [self isHidden] == NO) [self setHidden: YES];
        [signatur release]; signatur = nil;
        return;
    }
    if( signatur && [sig isEqualToString: signatur] && [self isHidden] == NO) return;   // nichts geaendert
    [signatur release]; signatur = [sig copy];
    [schichten release]; schichten = [neu copy];
    if( [vorschauen count] > 2 * kMaxVorschauen) [vorschauen removeAllObjects];
    [self setHidden: NO];
    [self ordne];
    [inhalt aktualisiereTooltips];
    [inhalt setNeedsDisplay: YES];
    NSUInteger pos = [schichten indexOfObject: [NSNumber numberWithUnsignedInteger: [iv curImage]]];
    if( pos != NSNotFound) [inhalt scrollRectToVisible: NSInsetRect( [inhalt rahmenFuerPosition: pos], -kAbstand, 0)];
}

#pragma mark Vorschau

// Das Bild der Schicht wie im Viewer: Fenster (WL/WW), Drehung, Spiegelung, Pixelverhaeltnis -- dieselbe Abbildung wie
// DCMView drawRect (glScalef mit Spiegelvorzeichen, dann glRotatef), hier in y-nach-unten-Koordinaten. Ohne Zoom und
// Verschiebung: die ganze Schicht passt ins Feld. Die Messungen liegen in Pixelkoordinaten und laufen durch dieselbe Abbildung.
- (NSImage*) vorschauFuerIndex:(long) i
{
    NSArray *pix = [viewer pixList];
    NSArray *rl = [viewer roiList];
    if( viewer == nil || i < 0 || i >= (long) pix.count || i >= (long) rl.count) return nil;
    DCMView *iv = [viewer imageView];
    DCMPix *p = [pix objectAtIndex: i];
    NSArray *rois = [rl objectAtIndex: i];
    NSString *key = [NSString stringWithFormat: @"%p|%.2f|%.2f|%.2f|%d%d|%@", p, [iv curWW], [iv curWL], [iv rotation], (int) [iv xFlipped], (int) [iv yFlipped],
                     [SekhmetMessNavigator signaturFuerROIs: rois] ?: @""];
    NSDictionary *gemerkt = [vorschauen objectForKey: [NSNumber numberWithLong: i]];
    if( [[gemerkt objectForKey: @"key"] isEqualToString: key]) return [gemerkt objectForKey: @"image"];

    NSImage *roh = nil;
    @try { roh = [p generateThumbnailImageWithWW: [iv curWW] WL: [iv curWL]]; }
    @catch (NSException *e) { NSLog( @"SekhVet measurement navigator: thumbnail of image %ld raised %@", i, e.name); }

    float pw = [p pwidth], ph = [p pheight], ratio = [p pixelRatio] > 0 ? [p pixelRatio] : 1;
    if( pw < 1 || ph < 1) return nil;
    double winkel = [iv rotation] * M_PI / 180.0;
    double bw = fabs( pw * cos( winkel)) + fabs( ph * ratio * sin( winkel));
    double bh = fabs( pw * sin( winkel)) + fabs( ph * ratio * cos( winkel));
    CGFloat s = (kBild - 4) / MAX( bw, bh);

    NSImage *bild = [[[NSImage alloc] initWithSize: NSMakeSize( kBild, kBild)] autorelease];
    [bild lockFocusFlipped: YES];
    [[NSColor blackColor] set];
    NSRectFill( NSMakeRect( 0, 0, kBild, kBild));
    [NSGraphicsContext saveGraphicsState];
    NSAffineTransform *t = [NSAffineTransform transform];
    [t translateXBy: kBild / 2 yBy: kBild / 2];
    [t scaleXBy: [iv xFlipped] ? -s : s yBy: [iv yFlipped] ? -s : s];
    [t rotateByDegrees: [iv rotation]];
    [t scaleXBy: 1 yBy: ratio];
    [t translateXBy: -pw / 2 yBy: -ph / 2];
    [t concat];
    if( roh) [roh drawInRect: NSMakeRect( 0, 0, pw, ph) fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1 respectFlipped: YES hints: nil];
    for( ROI *r in rois)
    {
        if( [r hidden]) continue;
        ToolMode typ = [r type];
        RGBColor c = [r rgbcolor];
        [[NSColor colorWithCalibratedRed: c.red / 65535.0 green: c.green / 65535.0 blue: c.blue / 65535.0 alpha: 1] set];
        NSBezierPath *bp = [NSBezierPath bezierPath];
        [bp setLineWidth: 1.6 / s];
        if( typ == t2DPoint || typ == tText || typ == tPlain || typ == tLayerROI)
        {
            NSRect q = [r rect];
            NSPoint m = typ == tPlain || typ == tLayerROI ? NSMakePoint( NSMidX( q), NSMidY( q)) : q.origin;
            CGFloat rad = 3.0 / s;
            [bp appendBezierPathWithOvalInRect: NSMakeRect( m.x - rad, m.y - rad, 2 * rad, 2 * rad)];
            [bp fill];
            continue;
        }
        NSArray *pts = [r points];
        if( pts.count == 0) continue;
        [bp moveToPoint: [[pts objectAtIndex: 0] point]];
        for( NSUInteger k = 1; k < pts.count; k++) [bp lineToPoint: [[pts objectAtIndex: k] point]];
        if( typ == tOval || typ == tROI || typ == tCPolygon || typ == tPencil) [bp closePath];
        [bp stroke];
    }
    [NSGraphicsContext restoreGraphicsState];
    [bild unlockFocus];
    [vorschauen setObject: @{ @"key": key, @"image": bild } forKey: [NSNumber numberWithLong: i]];
    return bild;
}

- (NSString*) tooltipFuerIndex:(long) i
{
    NSArray *rl = [viewer roiList];
    if( viewer == nil || i < 0 || i >= (long) rl.count) return nil;
    long n = [[viewer pixList] count];
    long nummer = ([[viewer imageView] flippedData] ? n - 1 - i : i) + 1;
    NSMutableArray *namen = [NSMutableArray array];
    for( ROI *r in [rl objectAtIndex: i])
    {
        if( [r hidden]) continue;
        if( namen.count == 8) { [namen addObject: @"…"]; break; }
        [namen addObject: [r name].length ? [r name] : NSLocalizedString( @"Unnamed", nil)];
    }
    return [NSString stringWithFormat: NSLocalizedString( @"Image %ld: %@ — click to go there", nil), nummer, [namen componentsJoinedByString: @", "]];
}

#pragma mark Aktionen

- (void) springeZuIndex:(long) i
{
    if( viewer == nil) return;
    long n = [[viewer pixList] count];
    if( i < 0 || i >= n) return;
    // DO-4/5/6: so wie das Mausrad in DCMView, plus drei Bedingungen, an denen Horos' Synchronisation sonst haengen bleibt:
    // - der Absender muss Schluesselansicht sein (isKeyView, nur ueber becomeFirstResponder wieder zu bekommen);
    // - die Empfaenger folgen nur dem vordersten Viewer, und den haelt Horos zwischengespeichert;
    // - ein Empfaenger, dessen Bild gerade nicht Ersthelfer seines Fensters ist (z. B. nach Klick in die Serienliste), hoert weg.
    // setImageIndex: meldet ausserdem Schritt 0 -- bei relativer Synchronisation zieht dann niemand mit.
    NSWindow *w = [viewer window];
    DCMView *iv = [viewer imageView];
    BOOL warKey = [w isKeyWindow], warKeyView = [iv isKeyView];
    [w makeKeyAndOrderFront: nil];
    if( [iv isKeyView] == NO)
    {
        if( [w firstResponder] == iv) [w makeFirstResponder: nil];
        [w makeFirstResponder: iv];
    }
    [ViewerController clearFrontMost2DViewerCache];
    ViewerController *vorn = [ViewerController frontMostDisplayed2DViewer];
    long alt = [iv curImage];
    [iv setIndex: i];
    [viewer adjustSlider];
    long schritt = alt >= 0 ? i - alt : 0;
    if( schritt > 32000) schritt = 32000;
    if( schritt < -32000) schritt = -32000;

    Ivar kv = class_getInstanceVariable( [DCMView class], "isKeyView");
    NSMutableArray *geweckt = [NSMutableArray array];
    for( ViewerController *o in [ViewerController getDisplayed2DViewers])
    {
        if( o == viewer) continue;
        DCMView *ov = [o imageView];
        if( kv && [ov isKeyView] == NO)
        {
            *(BOOL*)((char*) ov + ivar_getOffset( kv)) = YES;   // nur fuer diese eine Nachricht hinhoeren
            [geweckt addObject: ov];
        }
    }
    [iv sendSyncMessage: (short) schritt];   // Benachrichtigung laeuft synchron
    for( DCMView *ov in geweckt) *(BOOL*)((char*) ov + ivar_getOffset( kv)) = NO;
    NSLog( @"SekhVet Navigator jump: viewer %p keyWin %d keyView %d front %p (self %d) %ld->%ld step %ld syncro %d, %d other viewers woken",
           viewer, (int) warKey, (int) warKeyView, vorn, (int) (vorn == viewer), alt, i, schritt, (int) [DCMView syncro], (int) [geweckt count]);
    [viewer propagateSettings];
    [iv displayIfNeeded];
    // Paket DO-2: die Messung wird NICHT mehr markiert -- eine markierte Messung folgt in Horos dem naechsten Ziehen im Bild
    [[viewer imageView] setNeedsDisplay: YES];
    [[viewer window] makeFirstResponder: [viewer imageView]];   // Tasten (Pfeile, Cmd-Z) gehen wieder ans Bild
    [self pruefe];
}

- (IBAction) schliessen:(id) sender
{
    [SekhmetMessNavigator setEingeschaltet: NO];
}

- (IBAction) alleLoeschen:(id) sender
{
    [SekhmetMessNavigator loescheAlleMessungen: viewer];
}

+ (void) loescheAlleMessungen:(ViewerController*) v
{
    if( v == nil) { NSBeep(); return; }
    int frei = 0, gesperrt = 0;
    for( long m = 0; m < [v maxMovieIndex]; m++)
        for( NSArray *bild in [v roiList: m])
            for( ROI *r in bild) { if( [r locked]) gesperrt++; else frei++; }
    if( frei == 0)
    {
        NSBeep();
        return;
    }
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleWarning];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Delete all %d measurements of this series?", nil), frei]];
    NSString *info = NSLocalizedString( @"Edit › Undo (Cmd-Z) brings them back.", nil);
    NSString *serie = [[v currentSeries] valueForKey: @"name"];   // DO-4: welche Serie es trifft
    if( [serie isKindOfClass: [NSString class]] && [serie length]) info = [[NSString stringWithFormat: NSLocalizedString( @"Series: %@.", nil), serie] stringByAppendingFormat: @" %@", info];
    if( gesperrt) info = [[NSString stringWithFormat: NSLocalizedString( @"%d locked measurements stay.", nil), gesperrt] stringByAppendingFormat: @" %@", info];
    [a setInformativeText: info];
    [a addButtonWithTitle: NSLocalizedString( @"Delete All", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    NSLog( @"SekhVet Delete All: %d measurements, series %@, viewer %p", frei, serie, v);
    if( [a runModal] == NSAlertFirstButtonReturn)
    {
        [v roiDeleteAll: nil];   // Horos: Undo-Eintrag, gesperrte bleiben, OsirixRemoveROINotification je ROI
        for( DCMView *iv in [v imageViews]) [iv setNeedsDisplay: YES];
        [self aktualisiere: v];
    }
    [[v window] makeKeyWindow];
    [[v window] makeFirstResponder: [v imageView]];
}

#pragma mark Symbolleiste

+ (NSImage*) toolbarIcon   // drei Bildchen nebeneinander, im mittleren eine Messlinie, darunter die Schichtskala
{
    static NSImage *icon = nil;
    if( icon) return icon;
    icon = [[NSImage alloc] initWithSize: NSMakeSize( 32, 32)];
    [icon lockFocus];
    [[NSColor blackColor] set];
    NSBezierPath *rahmen = [NSBezierPath bezierPath];
    [rahmen setLineWidth: 1.5];
    [rahmen appendBezierPathWithRoundedRect: NSMakeRect( 1.5, 11.5, 8.5, 12) xRadius: 1.5 yRadius: 1.5];
    [rahmen appendBezierPathWithRoundedRect: NSMakeRect( 11.75, 11.5, 8.5, 12) xRadius: 1.5 yRadius: 1.5];
    [rahmen appendBezierPathWithRoundedRect: NSMakeRect( 22, 11.5, 8.5, 12) xRadius: 1.5 yRadius: 1.5];
    [rahmen stroke];
    NSBezierPath *linie = [NSBezierPath bezierPath];
    [linie setLineWidth: 2];
    [linie moveToPoint: NSMakePoint( 13.5, 14)]; [linie lineToPoint: NSMakePoint( 18.5, 21)];
    [linie stroke];
    NSBezierPath *skala = [NSBezierPath bezierPath];
    [skala setLineWidth: 1.2];
    [skala moveToPoint: NSMakePoint( 1.5, 6)]; [skala lineToPoint: NSMakePoint( 30.5, 6)];
    for( int k = 0; k <= 6; k++) { [skala moveToPoint: NSMakePoint( 1.5 + k * 29.0 / 6, 6)]; [skala lineToPoint: NSMakePoint( 1.5 + k * 29.0 / 6, k % 3 ? 8 : 9.5)]; }
    [skala stroke];
    [icon unlockFocus];
    [icon setTemplate: YES];
    return icon;
}

+ (ViewerController*) viewerForToolbarWindow:(NSWindow*) w
{
    id wc = [w windowController];
    if( [wc isKindOfClass: [ViewerController class]]) return wc;
    if( [wc isKindOfClass: [ToolbarPanelController class]]) return [(ToolbarPanelController*) wc viewer];
    return [ViewerController frontMostDisplayed2DViewer];
}

+ (void) konfiguriereToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) vc
{
    [item setLabel: NSLocalizedString( @"Measurements", nil)];
    [item setPaletteLabel: NSLocalizedString( @"Measurement Navigator (SekhVet)", nil)];
    [item setToolTip: NSLocalizedString( @"Measurement navigator on/off: thumbnails of all images with measurements below the image; click one to go there", nil)];
    NSSegmentedControl *seg = [[[NSSegmentedControl alloc] initWithFrame: NSMakeRect( 0, 0, 44, 25)] autorelease];
    [seg setSegmentStyle: NSSegmentStyleTexturedRounded];
    [seg setSegmentCount: 1];
    [[seg cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
    [seg setImage: [self toolbarIcon] forSegment: 0];
    [seg setLabel: @"" forSegment: 0];
    [seg setWidth: 40 forSegment: 0];
    [seg setTarget: self];
    [seg setAction: @selector(toolbarSegmentClicked:)];
    [seg setSelected: [self eingeschaltet] forSegment: 0];
    [seg sizeToFit];
    [item setView: seg];
    NSSize sz = [seg frame].size;
    [item setMinSize: sz];
    [item setMaxSize: sz];
    NSMenuItem *mi = [[[NSMenuItem alloc] initWithTitle: [item label] action: @selector(toolbarMenuClicked:) keyEquivalent: @""] autorelease];
    [mi setTarget: self];
    [item setMenuFormRepresentation: mi];
}

+ (void) toolbarSegmentClicked:(NSSegmentedControl*) seg
{
    [self setEingeschaltet: [self eingeschaltet] == NO];
    ViewerController *vc = [self viewerForToolbarWindow: [seg window]];
    [[vc window] makeKeyWindow];
    [[vc window] makeFirstResponder: [vc imageView]];
}

+ (void) toolbarMenuClicked:(NSMenuItem*) mi
{
    [self setEingeschaltet: [self eingeschaltet] == NO];
}

+ (void) konfiguriereLoeschenToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) vc
{
    [item setLabel: NSLocalizedString( @"Delete All", nil)];
    [item setPaletteLabel: NSLocalizedString( @"Delete All Measurements (SekhVet)", nil)];
    [item setToolTip: NSLocalizedString( @"Delete all measurements of this series (asks first; locked ones stay; Cmd-Z brings them back)", nil)];
    [item setImage: [NSImage imageWithSystemSymbolName: @"trash" accessibilityDescription: [item label]]];
    if( vc)   // DO-3: fest an den eigenen Viewer gebunden (wie Horos' Knoepfe); die Suche ueber den Absender traf beim zweiten Viewer den ersten
    {
        [item setTarget: vc];
        [item setAction: @selector(sekhmetMessungenLoeschen:)];
    }
    else
    {
        [item setTarget: self];
        [item setAction: @selector(loeschenKnopf:)];
    }
}

+ (void) loeschenKnopf:(id) sender
{
    NSWindow *w = [sender respondsToSelector: @selector(view)] ? [[sender view] window] : nil;   // NSToolbarItem mit Bild hat keine View
    ViewerController *vc = nil;
    for( ViewerController *v in [ViewerController getDisplayed2DViewers])
        if( [[v toolbar] items] && [[[v toolbar] items] indexOfObjectIdenticalTo: sender] != NSNotFound) { vc = v; break; }
    if( vc == nil) vc = w ? [self viewerForToolbarWindow: w] : [ViewerController frontMostDisplayed2DViewer];
    [self loescheAlleMessungen: [self aktiverViewerStatt: vc]];   // DO-4
}

#if SEKHVET_TESTHAKEN
+ (NSString*) debugZustand:(ViewerController*) v
{
    SekhmetMessNavigator *l = objc_getAssociatedObject( v, &kLeisteKey);
    if( l == nil) return @"no navigator";
    return [NSString stringWithFormat: @"hidden=%d frame=%@ superview=%@ slices=%@ on=%d", [l isHidden], NSStringFromRect( [l frame]),
            NSStringFromClass( [[l superview] class]), [[l schichten] componentsJoinedByString: @","], [self eingeschaltet]];
}
#endif

@end

@implementation ViewerController (SekhmetMessNavigator)   // DO-3: Ziel des Symbolleisten-Knopfs "Delete All"

- (IBAction) sekhmetMessungenLoeschen:(id) sender
{
    [SekhmetMessNavigator loescheAlleMessungen: [SekhmetMessNavigator aktiverViewerStatt: self]];   // DO-4
}

@end
