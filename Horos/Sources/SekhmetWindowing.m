/*=========================================================================
 SekhVet Paket AE — Fensterung (WL/WW) beim Oeffnen. Siehe Header.
 ============================================================================*/

#import "SekhmetWindowing.h"
#import "SekhmetDisplayPanel.h"
#import "ViewerController.h"
#import "DCMView.h"
#import "DCMPix.h"
#import "DicomStudy.h"
#import "DicomSeries.h"
#import "DCM.h"

static NSString* const SekhmetWLWWRulesVersionKey = @"SekhmetWLWWRulesVersion"; // SekhVet Paket AH: 2 = Regeln nach Kernel
#define SEKHMET_WLWW_RULES_VERSION 2

NSString* const SekhmetWLWWRulesKey = @"SekhmetWLWWRules";
NSString* const SekhmetWLWWApplyOnOpenKey = @"SekhmetWLWWApplyOnOpen";

static NSDictionary* sekhmetRule( NSString *modality, NSString *keywords, float wl, float ww, NSString *name)
{
    return [NSDictionary dictionaryWithObjectsAndKeys: modality, @"modality", keywords, @"keywords",
            [NSNumber numberWithFloat: wl], @"wl", [NSNumber numberWithFloat: ww], @"ww", name, @"name", nil];
}

@implementation SekhmetWindowing

+ (NSArray*) defaultRules
{
    // Reihenfolge = Prioritaet: die erste passende Regel gewinnt; leeres Stichwort = Vorgabe der Modalitaet.
    // Paket AH (11.09.): der Faltungskern (0018,1210) entscheidet — Lunge vor Knochen vor Weichteil.
    // Vokabular aus 359 CT-Serien auf dem Orthanc: Siemens Br40/Hr40 weich, Br64/Hr64 Knochen, Bl64 Lunge;
    // GE STANDARD weich, BONE/BONEPLUS/EDGE Knochen, LUNG Lunge; Canon FC08/FC14/FC26 weich, FC30/BONE/BODY_SHARP Knochen,
    // LUNG/FC81/FC85/FC86 Lunge; Planmed ohne Kernel ("stitch") Knochen. Kopf/Spine/Abdomen mit weichem Kernel -> Weichteil.
    return [NSArray arrayWithObjects:
            sekhmetRule( @"CT", @"LUNG|Lunge|Bl64|Bl57|FC81|FC85|FC86", -500, 1400, @"Lung"),
            sekhmetRule( @"CT", @"Bone|Knochen|Osso|KF |Br64|Br69|Hr64|Hr68|BONEPLUS|EDGE|BODY_SHARP|FC30|FC31|FC35|stitch", 700, 5000, @"Bone (vet)"),
            sekhmetRule( @"CT", @"", 40, 400, @"Soft tissue"),
            sekhmetRule( @"MR", @"", 400, 800, @"MR (as ImagoPilot)"),
            nil];
}

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues
{
    [defaultValues setObject: [self defaultRules] forKey: SekhmetWLWWRulesKey];
    [defaultValues setObject: [NSNumber numberWithBool: YES] forKey: SekhmetWLWWApplyOnOpenKey];
    // Paket AH: im Panel gespeicherte Regeln der Version 1 (Kopf weich / Rest Knochen) einmalig durch die Kernel-Regeln ersetzen
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d integerForKey: SekhmetWLWWRulesVersionKey] < SEKHMET_WLWW_RULES_VERSION)
    {
        [d removeObjectForKey: SekhmetWLWWRulesKey];
        [d setInteger: SEKHMET_WLWW_RULES_VERSION forKey: SekhmetWLWWRulesVersionKey];
    }
}

+ (NSString*) kernelForViewer:(ViewerController*) v // SekhVet Paket AH: Faltungskern (0018,1210) + Koerperregion (0018,0015) der ersten Datei
{
    static NSMutableDictionary *cache = nil;
    if( cache == nil) cache = [[NSMutableDictionary alloc] init];
    NSString *path = nil;
    @try { path = [[[v imageView] curDCM] srcFile]; } @catch (NSException *e) { }
    if( path.length == 0) return @"";
    NSString *cached = [cache objectForKey: path];
    if( cached) return cached;
    NSMutableString *s = [NSMutableString string];
    @try
    {
        DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
        NSString *k = [o attributeValueWithName: @"ConvolutionKernel"];
        NSString *b = [o attributeValueWithName: @"BodyPartExamined"];
        if( k.length) [s appendString: k];
        if( b.length) [s appendFormat: @" %@", b];
    }
    @catch (NSException *e) { }
    if( cache.count > 500) [cache removeAllObjects];
    [cache setObject: s forKey: path];
    return s;
}

+ (NSString*) descriptionForViewer:(ViewerController*) v
{
    NSMutableString *s = [NSMutableString string];
    @try
    {
        NSString *a = [[v currentStudy] valueForKey: @"studyName"];
        NSString *b = [[v currentSeries] valueForKey: @"name"];
        if( a) [s appendString: a];
        if( b) [s appendFormat: @" %@", b];
        NSString *k = [self kernelForViewer: v]; // Paket AH: Kernel + Koerperregion gehoeren zum Suchtext
        if( k.length) [s appendFormat: @" [%@]", k];
    }
    @catch (NSException *e) { }
    return s;
}

+ (NSString*) modalityForViewer:(ViewerController*) v
{
    NSString *m = nil;
    @try { m = [[v currentSeries] valueForKey: @"modality"]; } @catch (NSException *e) { }
    if( m.length == 0) m = [[[v imageView] curDCM] modalityString];
    return [m uppercaseString];
}

+ (NSDictionary*) ruleForViewer:(ViewerController*) v
{
    return [self ruleForModality: [self modalityForViewer: v] description: [self descriptionForViewer: v]];
}

// SekhVet Paket AU: Das Oeffnungsprotokoll braucht dieselbe Entscheidung, bevor ein Viewer
// existiert — Modalitaet und Suchtext kommen dann aus der Datenbank statt aus dem Viewer.
+ (NSDictionary*) ruleForModality:(NSString*) modality description:(NSString*) description
{
    modality = [modality uppercaseString];
    if( modality.length == 0) return nil;
    if( description == nil) description = @"";
    for( NSDictionary *r in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetWLWWRulesKey])
    {
        NSString *rm = [[r objectForKey: @"modality"] uppercaseString];
        if( rm.length && [modality rangeOfString: rm].location == NSNotFound) continue;
        NSString *kw = [r objectForKey: @"keywords"];
        if( kw.length == 0) return r;
        for( NSString *k in [kw componentsSeparatedByString: @"|"])
        {
            NSString *t = [k stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
            if( t.length && [description rangeOfString: t options: NSCaseInsensitiveSearch].location != NSNotFound) return r;
        }
    }
    return nil;
}

+ (BOOL) applyToViewer:(ViewerController*) v
{
    if( v == nil || [v imageView] == nil) return NO;
    NSDictionary *r = [self ruleForViewer: v];
    if( r == nil) return NO;
    float wl = [[r objectForKey: @"wl"] floatValue], ww = [[r objectForKey: @"ww"] floatValue];
    if( ww <= 0) return NO;
    [[v imageView] setWLWW: wl :ww];   // wie ApplyWLWW: — DCMView setzt das Bild, die Serie folgt ueber OsirixChangeWLWWNotification
    NSLog( @"SekhVet Window preset: %@ \"%@\" -> WL %.0f / WW %.0f (%@)", [self modalityForViewer: v], [self descriptionForViewer: v], wl, ww, [r objectForKey: @"name"]);
    return YES;
}

+ (void) applyToAllViewers
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [self applyToViewer: v];
}

@end

#pragma mark -

static SekhmetWindowingPanel *sekhmetWindowingPanel = nil;

@implementation SekhmetWindowingPanel

+ (SekhmetWindowingPanel*) shared
{
    if( sekhmetWindowingPanel == nil) sekhmetWindowingPanel = [[SekhmetWindowingPanel alloc] init];
    return sekhmetWindowingPanel;
}

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 640, 360)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Window Presets (WL/WW on open)", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self)
    {
        rules = [[NSMutableArray alloc] init];
        [self buildUI];
        [self loadFromDefaults];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [rules release];
    [super dealloc];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES];
    [super showWindow: sender];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text];
    [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title];
    [b setBezelStyle: NSBezelStyleRounded];
    [b setTarget: self]; [b setAction: sel];
    [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float y = 360 - 36;

    NSTextField *hint = [self label: NSLocalizedString( @"When a series opens, the first matching rule (top to bottom) sets WL/WW. Keywords: study/series description, convolution kernel (0018,1210) or body part contains one of the words, separated by | — empty = any. Modality empty = any.", nil) frame: NSMakeRect( 20, y - 20, 600, 40) bold: NO];
    [hint setFont: [NSFont systemFontOfSize: 11]];
    [[hint cell] setWraps: YES];
    [cv addSubview: hint];
    y -= 34;

    applyOnOpenButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y, 400, 18)] autorelease];
    [applyOnOpenButton setButtonType: NSButtonTypeSwitch];
    [applyOnOpenButton setTitle: NSLocalizedString( @"Apply window presets when a series opens", nil)];
    [applyOnOpenButton setFont: [NSFont systemFontOfSize: 12]];
    [applyOnOpenButton setTarget: self]; [applyOnOpenButton setAction: @selector(applyOnOpenChanged:)];
    [cv addSubview: applyOnOpenButton];

    y -= 210;
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, y, 500, 200)] autorelease];
    NSTableView *tv = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 500, 200)] autorelease];
    NSArray *cols = [NSArray arrayWithObjects: @"Modality", @"Keywords", @"WL", @"WW", @"Name", nil];
    NSArray *widths = [NSArray arrayWithObjects: @"60", @"200", @"55", @"55", @"110", nil];
    for( NSUInteger i = 0; i < cols.count; i++)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [cols objectAtIndex: i]] autorelease];
        [[c headerCell] setStringValue: [cols objectAtIndex: i]];
        [c setWidth: [[widths objectAtIndex: i] floatValue]];
        [c setEditable: YES];
        [tv addTableColumn: c];
    }
    [tv setDataSource: self]; [tv setDelegate: self];
    [tv setUsesAlternatingRowBackgroundColors: YES];
    [sv setDocumentView: tv];
    [sv setHasVerticalScroller: YES];
    [sv setBorderType: NSBezelBorder];
    table = tv;
    [cv addSubview: sv];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 530, y + 172, 40, 26) action: @selector(addRule:)]];
    [cv addSubview: [self button: @"−" frame: NSMakeRect( 575, y + 172, 40, 26) action: @selector(removeRule:)]];
    [cv addSubview: [self button: @"↑" frame: NSMakeRect( 530, y + 138, 40, 26) action: @selector(moveUp:)]];
    [cv addSubview: [self button: @"↓" frame: NSMakeRect( 575, y + 138, 40, 26) action: @selector(moveDown:)]];

    y -= 44;
    [cv addSubview: [self button: NSLocalizedString( @"Apply to open viewers", nil) frame: NSMakeRect( 20, y, 240, 30) action: @selector(applyNow:)]];
    [cv addSubview: [self button: NSLocalizedString( @"Reset to defaults", nil) frame: NSMakeRect( 270, y, 200, 30) action: @selector(resetRules:)]];
}

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [applyOnOpenButton setState: [d boolForKey: SekhmetWLWWApplyOnOpenKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [rules removeAllObjects];
    for( NSDictionary *r in [d arrayForKey: SekhmetWLWWRulesKey])
        [rules addObject: [[r mutableCopy] autorelease]];
    [table reloadData];
}

- (void) save
{
    [[NSUserDefaults standardUserDefaults] setObject: rules forKey: SekhmetWLWWRulesKey];
}

- (IBAction) applyOnOpenChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: ([applyOnOpenButton state] == NSControlStateValueOn) forKey: SekhmetWLWWApplyOnOpenKey];
}

- (IBAction) addRule:(id) sender
{
    [rules addObject: [[sekhmetRule( @"CT", @"", 40, 400, @"") mutableCopy] autorelease]];
    [self save]; [table reloadData];
    [table editColumn: 0 row: rules.count - 1 withEvent: nil select: YES];
}

- (IBAction) removeRule:(id) sender
{
    NSInteger r = [table selectedRow];
    if( r >= 0 && r < (NSInteger) rules.count) { [rules removeObjectAtIndex: r]; [self save]; [table reloadData]; }
}

- (void) moveRow:(NSInteger) delta
{
    NSInteger r = [table selectedRow], n = r + delta;
    if( r < 0 || n < 0 || n >= (NSInteger) rules.count) return;
    [rules exchangeObjectAtIndex: r withObjectAtIndex: n];
    [self save]; [table reloadData];
    [table selectRowIndexes: [NSIndexSet indexSetWithIndex: n] byExtendingSelection: NO];
}

- (IBAction) moveUp:(id) sender { [self moveRow: -1]; }
- (IBAction) moveDown:(id) sender { [self moveRow: 1]; }

- (IBAction) resetRules:(id) sender
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: SekhmetWLWWRulesKey];
    [self loadFromDefaults];
}

- (IBAction) applyNow:(id) sender
{
    [self save];
    [SekhmetWindowing applyToAllViewers];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    return rules.count;
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    NSMutableDictionary *d = [rules objectAtIndex: row];
    NSString *ident = [col identifier];
    if( [ident isEqualToString: @"Modality"]) return [d objectForKey: @"modality"];
    if( [ident isEqualToString: @"Keywords"]) return [d objectForKey: @"keywords"];
    if( [ident isEqualToString: @"WL"]) return [NSString stringWithFormat: @"%.0f", [[d objectForKey: @"wl"] floatValue]];
    if( [ident isEqualToString: @"WW"]) return [NSString stringWithFormat: @"%.0f", [[d objectForKey: @"ww"] floatValue]];
    if( [ident isEqualToString: @"Name"]) return [d objectForKey: @"name"];
    return nil;
}

- (void) tableView:(NSTableView*) tv setObjectValue:(id) value forTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    NSMutableDictionary *d = [rules objectAtIndex: row];
    NSString *ident = [col identifier];
    if( value == nil) value = @"";
    if( [ident isEqualToString: @"Modality"]) [d setObject: [[value description] uppercaseString] forKey: @"modality"];
    else if( [ident isEqualToString: @"Keywords"]) [d setObject: [value description] forKey: @"keywords"];
    else if( [ident isEqualToString: @"WL"]) [d setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"wl"];
    else if( [ident isEqualToString: @"WW"]) [d setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"ww"];
    else if( [ident isEqualToString: @"Name"]) [d setObject: [value description] forKey: @"name"];
    [self save];
}

@end
