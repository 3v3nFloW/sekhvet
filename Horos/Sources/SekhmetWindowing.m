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
#import "Notifications.h"
#include "SekhmetTesthaken.h"

// SekhVet Paket CS: what a rule last set per series -- [ [seriesInstanceUID, wl, ww], ... ], newest last, bounded.
// A series whose saved window differs from it was changed by the user and is left alone on open.
static NSString* const SekhmetWLWWAppliedKey = @"SekhmetWLWWApplied";
static NSString* const SekhmetWLWWKeepUserWindowKey = @"SekhmetWLWWKeepUserWindow";   // BOOL, default YES; NO = every open resets to the rule
#define SEKHMET_WLWW_APPLIED_MAX 1000

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
    [defaultValues setObject: [NSNumber numberWithBool: YES] forKey: SekhmetWLWWKeepUserWindowKey];   // SekhVet Paket CS
    // Paket AH: im Panel gespeicherte Regeln der Version 1 (Kopf weich / Rest Knochen) einmalig durch die Kernel-Regeln ersetzen
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d integerForKey: SekhmetWLWWRulesVersionKey] < SEKHMET_WLWW_RULES_VERSION)
    {
        [d removeObjectForKey: SekhmetWLWWRulesKey];
        [d setInteger: SEKHMET_WLWW_RULES_VERSION forKey: SekhmetWLWWRulesVersionKey];
    }
}

// SekhVet Paket AH: Faltungskern (0018,1210) + Koerperregion (0018,0015) der ersten Datei.
// SekhVet Paket CS: returned separately as [ kernel, body part ] (both maybe @"") -- the kernel is matched on its own.
+ (NSArray*) headerForViewer:(ViewerController*) v
{
    static NSMutableDictionary *cache = nil;
    if( cache == nil) cache = [[NSMutableDictionary alloc] init];
    NSString *path = nil;
    @try { path = [[[v imageView] curDCM] srcFile]; } @catch (NSException *e) { }
    if( path.length == 0) return [NSArray arrayWithObjects: @"", @"", nil];
    NSArray *cached = [cache objectForKey: path];
    if( cached) return cached;
    NSString *kernel = @"", *part = @"";
    @try
    {
        DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
        NSString *k = [o attributeValueWithName: @"ConvolutionKernel"];
        NSString *b = [o attributeValueWithName: @"BodyPartExamined"];
        if( [k isKindOfClass: [NSString class]] && k.length) kernel = k;
        if( [b isKindOfClass: [NSString class]] && b.length) part = b;
    }
    @catch (NSException *e) { }
    NSArray *header = [NSArray arrayWithObjects: kernel, part, nil];
    if( cache.count > 500) [cache removeAllObjects];
    [cache setObject: header forKey: path];
    return header;
}

+ (NSString*) kernelForViewer:(ViewerController*) v
{
    return [[self headerForViewer: v] objectAtIndex: 0];
}

// Study name + series name + body part. SekhVet Paket CS: without the kernel, which is passed on its own.
+ (NSString*) descriptionForViewer:(ViewerController*) v
{
    NSMutableString *s = [NSMutableString string];
    @try
    {
        NSString *a = [[v currentStudy] valueForKey: @"studyName"];
        NSString *b = [[v currentSeries] valueForKey: @"name"];
        if( a) [s appendString: a];
        if( b) [s appendFormat: @" %@", b];
        NSString *part = [[self headerForViewer: v] objectAtIndex: 1];
        if( part.length) [s appendFormat: @" %@", part];
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
    return [self ruleForModality: [self modalityForViewer: v] kernel: [self kernelForViewer: v] description: [self descriptionForViewer: v] onOpen: NO];
}

// SekhVet Paket CS: the documented priority -- the convolution kernel decides. If the series has a kernel, the keywords
// are compared with the kernel ONLY: a study called "Thorax Lunge" no longer puts its soft-kernel series into the lung
// window; they fall through to the rule without keywords. Only without a kernel (e.g. CBCT, radiographs) the
// description (study/series name, body part) is searched as before.
// onOpen is kept for the callers; the built-in MR rule (400/800) applies on open as before (owner's decision).
+ (NSDictionary*) ruleForModality:(NSString*) modality kernel:(NSString*) kernel description:(NSString*) description onOpen:(BOOL) onOpen
{
    modality = [modality uppercaseString];
    if( modality.length == 0) return nil;
    if( description == nil) description = @"";
    kernel = [kernel stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *text = kernel.length ? kernel : description;
    for( NSDictionary *r in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetWLWWRulesKey])
    {
        NSString *rm = [[r objectForKey: @"modality"] uppercaseString];
        if( rm.length && [modality rangeOfString: rm].location == NSNotFound) continue;
        NSString *kw = [r objectForKey: @"keywords"];
        if( kw.length == 0) return r;
        for( NSString *k in [kw componentsSeparatedByString: @"|"])
        {
            NSString *t = [k stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
            if( t.length && [text rangeOfString: t options: NSCaseInsensitiveSearch].location != NSNotFound) return r;
        }
    }
    return nil;
}

+ (NSDictionary*) ruleForModality:(NSString*) modality kernel:(NSString*) kernel description:(NSString*) description
{
    return [self ruleForModality: modality kernel: kernel description: description onOpen: NO];
}

// SekhVet Paket AU: Das Oeffnungsprotokoll braucht dieselbe Entscheidung, bevor ein Viewer
// existiert — Modalitaet und Suchtext kommen dann aus der Datenbank statt aus dem Viewer.
// SekhVet Paket CS: the callers put the kernel into the text as " [kernel]"; the last such bracket is taken out and
// handed over as the kernel, so that this entry decides like the viewer does.
+ (NSDictionary*) ruleForModality:(NSString*) modality description:(NSString*) description
{
    NSString *kernel = nil;
    NSRange open = description.length ? [description rangeOfString: @" [" options: NSBackwardsSearch] : NSMakeRange( NSNotFound, 0);
    if( open.location != NSNotFound)
    {
        NSUInteger start = NSMaxRange( open);
        NSRange close = [description rangeOfString: @"]" options: 0 range: NSMakeRange( start, description.length - start)];
        if( close.location != NSNotFound)
        {
            kernel = [description substringWithRange: NSMakeRange( start, close.location - start)];
            description = [[description substringToIndex: open.location] stringByAppendingString: [description substringFromIndex: NSMaxRange( close)]];
        }
    }
    return [self ruleForModality: modality kernel: kernel description: description onOpen: NO];
}

#pragma mark - SekhVet Paket CS: a window the user saved with the series is not overridden on open

static BOOL sekhmetWLWWNear( float a, float b)
{
    return fabsf( a - b) <= 1e-3f * MAX( 1.0f, MAX( fabsf( a), fabsf( b)));
}

+ (NSString*) seriesUIDOfViewer:(ViewerController*) v
{
    NSString *uid = nil;
    @try { uid = [[v currentSeries] valueForKey: @"seriesInstanceUID"]; } @catch (NSException *e) { }
    return [uid isKindOfClass: [NSString class]] && uid.length ? uid : nil;
}

+ (NSArray*) appliedRecordForSeries:(NSString*) uid
{
    if( uid == nil) return nil;
    for( NSArray *e in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetWLWWAppliedKey])
        if( [e isKindOfClass: [NSArray class]] && e.count == 3 && [[e objectAtIndex: 0] isEqual: uid]) return e;
    return nil;
}

+ (void) noteAppliedWL:(float) wl WW:(float) ww forSeries:(NSString*) uid
{
    if( uid == nil) return;
    NSArray *old = [self appliedRecordForSeries: uid];
    if( old && sekhmetWLWWNear( [[old objectAtIndex: 1] floatValue], wl) && sekhmetWLWWNear( [[old objectAtIndex: 2] floatValue], ww)) return;
    NSMutableArray *all = [NSMutableArray array];
    for( NSArray *e in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetWLWWAppliedKey])
        if( [e isKindOfClass: [NSArray class]] && e.count == 3 && [[e objectAtIndex: 0] isEqual: uid] == NO) [all addObject: e];
    [all addObject: [NSArray arrayWithObjects: uid, [NSNumber numberWithFloat: wl], [NSNumber numberWithFloat: ww], nil]];
    while( all.count > SEKHMET_WLWW_APPLIED_MAX) [all removeObjectAtIndex: 0];
    [[NSUserDefaults standardUserDefaults] setObject: all forKey: SekhmetWLWWAppliedKey];
}

// YES only when it is certain: a rule was applied to this series before, and the window saved with the series (Horos
// writes every WL/WW change there and restores it on open) is neither that value, nor the rule's, nor a DICOM default
// of the series. In every doubtful case the answer is NO and the rule is applied as it always was.
+ (BOOL) userWindowSavedInViewer:(ViewerController*) v ruleWL:(float) wl WW:(float) ww
{
    if( [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetWLWWKeepUserWindowKey] == NO) return NO;
    NSArray *rec = [self appliedRecordForSeries: [self seriesUIDOfViewer: v]];
    if( rec == nil) return NO;
    NSNumber *sww = nil, *swl = nil;
    @try { sww = [[v currentSeries] valueForKey: @"windowWidth"]; swl = [[v currentSeries] valueForKey: @"windowLevel"]; } @catch (NSException *e) { }
    if( [sww isKindOfClass: [NSNumber class]] == NO || [swl isKindOfClass: [NSNumber class]] == NO || [sww floatValue] <= 0) return NO;
    float savedWL = [swl floatValue], savedWW = [sww floatValue];
    if( sekhmetWLWWNear( savedWL, [[rec objectAtIndex: 1] floatValue]) && sekhmetWLWWNear( savedWW, [[rec objectAtIndex: 2] floatValue])) return NO;
    if( sekhmetWLWWNear( savedWL, wl) && sekhmetWLWWNear( savedWW, ww)) return NO;
    for( DCMPix *p in [v pixList])
        if( sekhmetWLWWNear( savedWL, p.savedWL) && sekhmetWLWWNear( savedWW, p.savedWW)) return NO;
    return YES;
}

#pragma mark -

// Called when a series opens (ViewerController finishLoadImageData:)
+ (BOOL) applyToViewer:(ViewerController*) v
{
    return [self applyToViewer: v onOpen: YES];
}

+ (BOOL) applyToViewer:(ViewerController*) v onOpen:(BOOL) onOpen
{
    if( v == nil || [v imageView] == nil) return NO;
    NSString *modality = [self modalityForViewer: v];
    NSDictionary *r = [self ruleForModality: modality kernel: [self kernelForViewer: v] description: [self descriptionForViewer: v] onOpen: onOpen];
    if( r == nil) return NO;
    float wl = [[r objectForKey: @"wl"] floatValue], ww = [[r objectForKey: @"ww"] floatValue];
    if( ww <= 0) return NO;
    if( onOpen && [self userWindowSavedInViewer: v ruleWL: wl WW: ww])
    {
        NSLog( @"SekhVet Window preset: %@ keeps the window saved with the series (rule %@ not applied)", modality, [r objectForKey: @"name"]);
        return NO;
    }
    [[v imageView] setWLWW: wl :ww];   // wie ApplyWLWW: — DCMView setzt das Bild, die Serie folgt ueber OsirixChangeWLWWNotification
    [self noteAppliedWL: wl WW: ww forSeries: [self seriesUIDOfViewer: v]];
    // SekhVet Paket CS: study and series descriptions are free text (owner or animal names) -- not in the log of a release build
#if SEKHVET_TESTHAKEN
    NSLog( @"SekhVet Window preset: %@ \"%@\" [%@] -> WL %.0f / WW %.0f (%@)", modality, [self descriptionForViewer: v], [self kernelForViewer: v], wl, ww, [r objectForKey: @"name"]);
#else
    NSLog( @"SekhVet Window preset: %@ -> WL %.0f / WW %.0f (%@)", modality, wl, ww, [r objectForKey: @"name"]);
#endif
    return YES;
}

// "Apply to open viewers": asked for by the user, so a saved window gives way
+ (void) applyToAllViewers
{
    for( ViewerController *v in [ViewerController getDisplayed2DViewers]) [self applyToViewer: v onOpen: NO];
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
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 640, 650)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Window Presets (WL/WW)", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self)
    {
        rules = [[NSMutableArray alloc] init];
        presets = [[NSMutableArray alloc] init];
        [self buildUI];
        [self loadFromDefaults];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [rules release];
    [presets release];
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
    float y = 650 - 36;

    // SekhVet Paket CS: text follows the matching (kernel first)
    NSTextField *hint = [self label: NSLocalizedString( @"When a series opens, the first matching rule (top to bottom) sets WL/WW. Keywords (separated by |, empty = any) are compared with the convolution kernel (0018,1210) if there is one, otherwise with study/series description and body part. Modality empty = any.", nil) frame: NSMakeRect( 20, y - 20, 600, 40) bold: NO];
    [hint setFont: [NSFont systemFontOfSize: 11]];
    [[hint cell] setWraps: YES];
    [cv addSubview: hint];
    y -= 34;

    applyOnOpenButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y, 400, 18)] autorelease];
    [applyOnOpenButton setButtonType: NSButtonTypeSwitch];
    [applyOnOpenButton setTitle: NSLocalizedString( @"Apply window presets when a series opens", nil)];
    [applyOnOpenButton setFont: [NSFont systemFontOfSize: 12]];
    [applyOnOpenButton setTarget: self]; [applyOnOpenButton setAction: @selector(applyOnOpenChanged:)];
    // SekhVet Paket CS
    [applyOnOpenButton setToolTip: NSLocalizedString( @"A window you changed yourself is saved with the series and kept when it opens again.", nil)];
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

    // SekhVet Paket BL: globale Presets — dieselben Namen und Werte wie im WL/WW-Menue der Viewer (Tasten 1-9 in Menue-Reihenfolge)
    y -= 36;
    [cv addSubview: [self label: NSLocalizedString( @"Global WL/WW presets", nil) frame: NSMakeRect( 20, y, 400, 18) bold: YES]];
    y -= 34;
    NSTextField *hint2 = [self label: NSLocalizedString( @"The presets of the WL/WW menu in every viewer (e.g. \"CT - Bone\", \"CT - Abdomen\"). Keys 1–9 follow the alphabetical order shown here. Changes apply to the menu immediately.", nil) frame: NSMakeRect( 20, y, 600, 30) bold: NO];
    [hint2 setFont: [NSFont systemFontOfSize: 11]];
    [[hint2 cell] setWraps: YES];
    [cv addSubview: hint2];

    y -= 180;
    NSScrollView *sv2 = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, y, 500, 174)] autorelease];
    NSTableView *pt = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 500, 174)] autorelease];
    NSArray *pcols = [NSArray arrayWithObjects: @"PresetName", @"PresetWL", @"PresetWW", nil];
    NSArray *ptitles = [NSArray arrayWithObjects: @"Name", @"WL", @"WW", nil];
    NSArray *pwidths = [NSArray arrayWithObjects: @"300", @"80", @"80", nil];
    for( NSUInteger i = 0; i < pcols.count; i++)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [pcols objectAtIndex: i]] autorelease];
        [[c headerCell] setStringValue: [ptitles objectAtIndex: i]];
        [c setWidth: [[pwidths objectAtIndex: i] floatValue]];
        [c setEditable: YES];
        [pt addTableColumn: c];
    }
    [pt setDataSource: self]; [pt setDelegate: self];
    [pt setUsesAlternatingRowBackgroundColors: YES];
    [sv2 setDocumentView: pt];
    [sv2 setHasVerticalScroller: YES];
    [sv2 setBorderType: NSBezelBorder];
    presetTable = pt;
    [cv addSubview: sv2];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 530, y + 146, 40, 26) action: @selector(addPreset:)]];
    [cv addSubview: [self button: @"−" frame: NSMakeRect( 575, y + 146, 40, 26) action: @selector(removePreset:)]];

    y -= 44;
    [cv addSubview: [self button: NSLocalizedString( @"Reset presets to defaults", nil) frame: NSMakeRect( 20, y, 240, 30) action: @selector(resetPresets:)]];
}

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [applyOnOpenButton setState: [d boolForKey: SekhmetWLWWApplyOnOpenKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [rules removeAllObjects];
    for( NSDictionary *r in [d arrayForKey: SekhmetWLWWRulesKey])
        [rules addObject: [[r mutableCopy] autorelease]];
    [table reloadData];
    [self loadPresets];
}

#pragma mark - SekhVet Paket BL: globale WL/WW-Presets (WLWW3)

- (void) loadPresets
{
    [presets removeAllObjects];
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey: @"WLWW3"];
    for( NSString *name in [[dict allKeys] sortedArrayUsingSelector: @selector(caseInsensitiveCompare:)])
    {
        NSArray *v = [dict objectForKey: name];
        if( ![v isKindOfClass: [NSArray class]] || v.count < 2) continue;
        [presets addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", [v objectAtIndex: 0], @"wl", [v objectAtIndex: 1], @"ww", nil]];
    }
    [presetTable reloadData];
}

- (void) savePresets
{
    NSMutableDictionary *dict = [NSMutableDictionary dictionary];
    for( NSDictionary *p in presets)
    {
        NSString *name = [[p objectForKey: @"name"] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        float ww = [[p objectForKey: @"ww"] floatValue];
        if( name.length == 0) continue;
        if( ww < 1) ww = 1;   // wie Horos: WW 0 hiesse "Full dynamic"
        [dict setObject: [NSArray arrayWithObjects: [NSNumber numberWithFloat: [[p objectForKey: @"wl"] floatValue]], [NSNumber numberWithFloat: ww], nil] forKey: name];
    }
    [[NSUserDefaults standardUserDefaults] setObject: dict forKey: @"WLWW3"];
    // userInfo gesetzt = jeder Viewer baut sein WL/WW-Menue neu (ViewerController UpdateWLWWMenu:)
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixUpdateWLWWMenuNotification object: nil userInfo: [NSDictionary dictionary]];
}

- (IBAction) addPreset:(id) sender
{
    NSString *base = NSLocalizedString( @"New preset", nil), *name = base;
    int n = 2;
    NSDictionary *dict = [[NSUserDefaults standardUserDefaults] dictionaryForKey: @"WLWW3"];
    while( [dict objectForKey: name]) name = [NSString stringWithFormat: @"%@ %d", base, n++];
    [presets addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", @40, @"wl", @400, @"ww", nil]];
    [self savePresets];
    [self loadPresets];
    for( NSUInteger i = 0; i < presets.count; i++)
        if( [[[presets objectAtIndex: i] objectForKey: @"name"] isEqualToString: name])
        {
            [presetTable selectRowIndexes: [NSIndexSet indexSetWithIndex: i] byExtendingSelection: NO];
            [presetTable editColumn: 0 row: i withEvent: nil select: YES];
            break;
        }
}

- (IBAction) removePreset:(id) sender
{
    NSInteger r = [presetTable selectedRow];
    if( r < 0 || r >= (NSInteger) presets.count) return;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Delete the preset \"%@\"?", nil), [[presets objectAtIndex: r] objectForKey: @"name"]]];
    [a addButtonWithTitle: NSLocalizedString( @"Delete", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    [presets removeObjectAtIndex: r];
    [self savePresets];
    [self loadPresets];
}

- (IBAction) resetPresets:(id) sender
{
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"Reset all WL/WW presets to the SekhVet defaults?", nil)];
    [a setInformativeText: NSLocalizedString( @"Presets you added or changed are removed.", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Reset", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"WLWW3"];
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixUpdateWLWWMenuNotification object: nil userInfo: [NSDictionary dictionary]];
    [self loadPresets];
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
    if( tv == presetTable) return presets.count;
    return rules.count;
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( tv == presetTable)
    {
        NSDictionary *p = [presets objectAtIndex: row];
        NSString *pid = [col identifier];
        if( [pid isEqualToString: @"PresetName"]) return [p objectForKey: @"name"];
        if( [pid isEqualToString: @"PresetWL"]) return [NSString stringWithFormat: @"%g", [[p objectForKey: @"wl"] floatValue]];
        if( [pid isEqualToString: @"PresetWW"]) return [NSString stringWithFormat: @"%g", [[p objectForKey: @"ww"] floatValue]];
        return nil;
    }
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
    if( tv == presetTable)
    {
        if( row < 0 || row >= (NSInteger) presets.count) return;
        NSMutableDictionary *p = [presets objectAtIndex: row];
        NSString *pid = [col identifier];
        if( value == nil) value = @"";
        if( [pid isEqualToString: @"PresetName"])
        {
            NSString *name = [[value description] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
            if( name.length == 0 || [name isEqualToString: [p objectForKey: @"name"]]) return;
            for( NSDictionary *o in presets)
                if( o != p && [[o objectForKey: @"name"] isEqualToString: name]) { NSBeep(); return; }   // Namen sind Schluessel
            [p setObject: name forKey: @"name"];
        }
        else if( [pid isEqualToString: @"PresetWL"]) [p setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"wl"];
        else if( [pid isEqualToString: @"PresetWW"]) [p setObject: [NSNumber numberWithFloat: MAX( 1, [value floatValue])] forKey: @"ww"];
        [self savePresets];
        [self performSelector: @selector(loadPresets) withObject: nil afterDelay: 0];   // neu sortieren, nachdem das Editieren abgeschlossen ist
        return;
    }
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
