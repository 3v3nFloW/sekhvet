/*=========================================================================
 SekhVet Paket DZ — Vet-Einstellungen. Siehe Header.
 ============================================================================*/

#import "SekhmetEinstellungen.h"

NSString* const SekhmetSettingsFileExtension = @"sekhvet-settings";
NSString* const SekhmetPracticeSettingsFolderKey = @"SekhmetPracticeSettingsFolder";
NSString* const SekhmetPracticeSettingsAutoApplyKey = @"SekhmetPracticeSettingsAutoApply";

// The pure logic stands above "#ifndef SEKHVET_LOGIC_TEST": SekhVet/test/einstellungen-test.sh compiles exactly this
// part without the application classes (the same pattern as SekhmetOpening / keyword-test).

static NSArray *svGruppen( void)
{
    return @[ @"opening", @"hanging", @"window", @"display", @"overlay", @"measure", @"network"];
}

// key -> group. Settings that exist only as built-in defaults are not stored and need no entry to be "kept": taking
// a group over removes every stored key of the group first, so a key absent in the file falls back to its default.
static NSDictionary *svExakt( void)
{
    static NSDictionary *d = nil;
    static dispatch_once_t einmal;
    dispatch_once( &einmal, ^{
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        NSDictionary *liste = @{
            @"opening": @[ @"SekhmetOpeningProtocols", @"SekhmetOpeningEnabled", @"SekhmetOpeningSmallWidth", @"SekhmetOpeningSmallMax",
                           @"SekhmetTwoViewEnabled", @"SekhmetTwoViewLateralLeft"],
            @"hanging": @[ @"SekhmetVetOrientationKeywords", @"SekhmetVetOrientationPreset", @"SekhmetVetProtocolList", @"SekhmetVetProtocolNextID",
                           @"SekhmetVetPresetOverrides", @"SekhmetVetPresetOverrideOrder", @"SekhmetVetPresetInsertedOrtho", @"SekhmetVetKeywordsAddedCS",
                           @"SekhmetDXRules", @"SekhmetMPRLayouts", @"HANGINGPROTOCOLS"],
            @"window": @[ @"SekhmetWLWWRules", @"SekhmetWLWWRulesVersion", @"SekhmetWLWWApplyOnOpen", @"SekhmetWLWWKeepUserWindow", @"WLWW3"],
            @"display": @[ @"SekhmetAnnotationBackground", @"SekhmetAnnotationBoxColor", @"SekhmetAnnotGraphicsWithOrientation", @"SekhmetAppearance",
                           @"SekhmetROITextColor", @"SekhmetROITextColorMode", @"SekhmetModalityColors", @"SekhmetLupeGroesse", @"SekhmetLupeZoom",
                           @"SekhmetMessLupe", @"SekhmetMessNavigator", @"SekhmetMPRCenterZone", @"SekhmetMPRLineZone", @"SekhmetMPRStaticCursor",
                           @"SekhmetMPRSync", @"SekhmetMPRSyncWLWW", @"SekhmetMPRSyncLayout", @"SekhmetMPRThickSlabMode", @"SekhmetTile3DWindows", @"syncZoomLevelMPR", @"ANNOTATIONS",
                           @"FONTNAME", @"FONTSIZE", @"LabelFONTNAME", @"LabelFONTSIZE", @"ROIThickness", @"ROIArrowThickness", @"ROIRegionThickness",
                           @"ROITextThickness", @"ROIColorR", @"ROIColorG", @"ROIColorB", @"ROIOpacity", @"ROIRegionColorR", @"ROIRegionColorG",
                           @"ROIRegionColorB", @"ROIRegionOpacity", @"ROITextColorR", @"ROITextColorG", @"ROITextColorB", @"ROITEXTNAMEONLY",
                           @"MagneticWindows"],
            @"overlay": @[ @"SekhmetOverlayKeyNext", @"SekhmetOverlayKeyPrev", @"SekhmetOverlayDeselected2", @"HOTKEYS"],
            @"measure": @[ @"SekhmetSpineSpecies", @"SekhmetSpineMarkersHidden", @"SekhmetSpinePointsElsewhere", @"SekhmetSpineTextColor",
                           @"SekhmetDIRisk", @"SekhmetUSCalibrationFallback", @"SekhmetUSCalibrationFallbackVendors"],
            @"network": @[ @"SERVERS", @"SekhmetDICOMwebNodes", @"SekhmetDICOMwebSelectedNode", @"SekhmetDICOMwebInstitutionFilter",
                           @"SekhmetDICOMwebInstitutionText"],
        };
        for( NSString *g in liste) for( NSString *k in liste[ g]) m[ k] = g;
        d = [m copy];
    });
    return d;
}

static NSArray *svPraefixe( void)   // @[ prefix, group ]
{
    return @[ @[ @"SekhmetVetRules2_", @"hanging"], @[ @"MPR_AXIS_", @"display"]];
}

static NSString *svName( id e)
{
    if( [e isKindOfClass: [NSDictionary class]] == NO) return nil;
    for( NSString *k in @[ @"name", @"Name", @"Description", @"AETitle", @"title"])
        if( [e[ k] isKindOfClass: [NSString class]] && [e[ k] length]) return e[ k];
    return nil;
}

static NSString *svListe( NSArray *namen)
{
    if( namen.count <= 6) return [namen componentsJoinedByString: @", "];
    return [NSString stringWithFormat: @"%@ … (+%lu)", [[namen subarrayWithRange: NSMakeRange( 0, 6)] componentsJoinedByString: @", "], (unsigned long) namen.count - 6];
}

@implementation SekhmetEinstellungen

+ (NSArray*) gruppen { return svGruppen(); }

+ (NSString*) titelFuerGruppe:(NSString*) g
{
    NSDictionary *t = @{ @"opening": @"Opening protocols", @"hanging": @"Hanging protocols & orientation", @"window": @"Window rules & WL/WW presets",
                         @"display": @"Display & annotations", @"overlay": @"Overlay & keys", @"measure": @"Measurement tools",
                         @"network": @"Network targets (DICOM / DICOMweb nodes, no passwords)"};
    return t[ g] ?: g;
}

+ (BOOL) istGesperrt:(NSString*) k
{
    static NSSet *exakt = nil;
    static dispatch_once_t einmal;
    dispatch_once( &einmal, ^{
        exakt = [[NSSet alloc] initWithArray: @[ @"STORESCP", @"STORESCPTLS", @"AETITLE", @"AEPORT", @"publishDICOMBonjour", @"searchDICOMBonjour",
            @"bonjourSharing", @"activateCFINDSCP", @"activateCGETSCP", @"httpWebServer", @"httpXMLRPCServer", @"DATABASELOCATION",
            @"DATABASELOCATIONURL", @"DefaultDatabasePath", @"localDatabasePaths", @"SekhmetStudyDBParent", @"SekhmetScreenAreas",
            @"SekhmetScreenAreaRects", @"NonViewerScreens", @"SekhmetWorkplaces", @"SekhVetInstallUUID", @"SekhVetUpdateConsentAsked", @"CheckHorosUpdates",
            @"SekhmetDisclaimerAccepted", @"SekhmetDICOMwebAutoRetrieve", @"SekhmetDICOMwebAutoMinutes", @"SekhmetDICOMwebCleartextConsent"]];
    });
    if( k.length == 0 || [exakt containsObject: k]) return YES;
    if( [k hasPrefix: @"NS"] || [k hasPrefix: @"SekhmetPractice"] || [k hasPrefix: @"SekhmetSettings"]) return YES;   // window/table state, this package's own machine keys
    NSString *l = [k lowercaseString];
    for( NSString *teil in @[ @"password", @"passwd", @"secret", @"token", @"routing", @"webportal", @"plugin"])
        if( [l rangeOfString: teil].location != NSNotFound) return YES;
    return NO;
}

+ (NSString*) gruppeFuerSchluessel:(NSString*) k
{
    if( [k isKindOfClass: [NSString class]] == NO || [self istGesperrt: k]) return nil;
    NSString *g = svExakt()[ k];
    if( g) return g;
    for( NSArray *p in svPraefixe()) if( [k hasPrefix: p[ 0]]) return p[ 1];
    return nil;
}

+ (id) bereinigt:(id) w
{
    if( [w isKindOfClass: [NSDictionary class]])
    {
        NSMutableDictionary *m = [NSMutableDictionary dictionary];
        for( id k in w)
        {
            if( [k isKindOfClass: [NSString class]])
            {
                NSString *l = [(NSString*) k lowercaseString];
                if( [l rangeOfString: @"pass"].location != NSNotFound || [l rangeOfString: @"secret"].location != NSNotFound || [l rangeOfString: @"token"].location != NSNotFound) continue;
            }
            m[ k] = [self bereinigt: w[ k]];
        }
        return m;
    }
    if( [w isKindOfClass: [NSArray class]])
    {
        NSMutableArray *a = [NSMutableArray array];
        for( id x in w) [a addObject: [self bereinigt: x]];
        return a;
    }
    return w;
}

+ (NSDictionary*) gruppenAus:(NSDictionary*) domain gruppen:(NSArray*) gruppen
{
    NSMutableDictionary *aus = [NSMutableDictionary dictionary];
    for( NSString *g in gruppen) if( [svGruppen() containsObject: g]) aus[ g] = [NSMutableDictionary dictionary];
    for( NSString *k in domain)
    {
        NSString *g = [self gruppeFuerSchluessel: k];
        if( g && aus[ g]) aus[ g][ k] = [self bereinigt: domain[ k]];
    }
    return aus;
}

+ (NSDictionary*) domain:(NSDictionary*) domain nachUebernahmeVon:(NSDictionary*) werte gruppen:(NSArray*) gruppen
{
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary: domain ?: @{}];
    NSSet *gs = [NSSet setWithArray: gruppen ?: @[]];
    for( NSString *k in [[m allKeys] copy]) if( [gs containsObject: [self gruppeFuerSchluessel: k] ?: @""]) [m removeObjectForKey: k];
    for( NSString *g in gs)
    {
        NSDictionary *gw = werte[ g];
        if( [gw isKindOfClass: [NSDictionary class]] == NO) continue;
        for( NSString *k in gw) if( [[self gruppeFuerSchluessel: k] isEqualToString: g]) m[ k] = [self bereinigt: gw[ k]];
    }
    return m;
}


// "alt" and "neu" are the effective values ({ key: value }) of the group before and after.
+ (NSString*) zusammenfassungVon:(NSDictionary*) alt nach:(NSDictionary*) neu gruppe:(NSString*) gruppe
{
    NSMutableSet *schluessel = [NSMutableSet set];
    for( NSString *k in alt) if( [[self gruppeFuerSchluessel: k] isEqualToString: gruppe]) [schluessel addObject: k];
    for( NSString *k in neu) if( [[self gruppeFuerSchluessel: k] isEqualToString: gruppe]) [schluessel addObject: k];
    NSMutableArray *teile = [NSMutableArray array];
    int sonst = 0;
    for( NSString *k in [[schluessel allObjects] sortedArrayUsingSelector: @selector(compare:)])
    {
        id a = alt[ k], b = neu[ k];
        if( (a == nil && b == nil) || [a isEqual: b]) continue;
        NSMutableArray *na = [NSMutableArray array], *nb = [NSMutableArray array];
        BOOL benannt = NO;
        if( ([a isKindOfClass: [NSArray class]] || a == nil) && ([b isKindOfClass: [NSArray class]] || b == nil))
        {
            benannt = YES;
            for( id e in (NSArray*) a) { NSString *n = svName( e); if( n == nil) { benannt = NO; break; } [na addObject: n]; }
            for( id e in (NSArray*) b) { NSString *n = svName( e); if( n == nil) { benannt = NO; break; } [nb addObject: n]; }
            if( na.count + nb.count == 0) benannt = NO;
        }
        else if( ([a isKindOfClass: [NSDictionary class]] || a == nil) && ([b isKindOfClass: [NSDictionary class]] || b == nil) && ([k isEqualToString: @"WLWW3"] || [k isEqualToString: @"HOTKEYS"]))
        {
            benannt = YES;
            [na addObjectsFromArray: [[(NSDictionary*) a allKeys] sortedArrayUsingSelector: @selector(compare:)] ?: @[]];
            [nb addObjectsFromArray: [[(NSDictionary*) b allKeys] sortedArrayUsingSelector: @selector(compare:)] ?: @[]];
        }
        if( benannt == NO) { sonst++; continue; }
        NSMutableArray *dazu = [NSMutableArray array], *weg = [NSMutableArray array];
        for( NSString *n in nb) if( [na containsObject: n] == NO) [dazu addObject: n];
        for( NSString *n in na) if( [nb containsObject: n] == NO) [weg addObject: n];
        NSMutableArray *z = [NSMutableArray array];
        if( dazu.count) [z addObject: [NSString stringWithFormat: @"new: %@", svListe( dazu)]];
        if( weg.count) [z addObject: [NSString stringWithFormat: @"removed: %@", svListe( weg)]];
        if( z.count == 0) [z addObject: @"changed or reordered"];
        [teile addObject: [NSString stringWithFormat: @"%lu → %lu entries (%@)", (unsigned long) na.count, (unsigned long) nb.count, [z componentsJoinedByString: @"; "]]];
    }
    if( sonst) [teile addObject: [NSString stringWithFormat: sonst == 1 ? @"%d setting changes" : @"%d settings change", sonst]];
    return teile.count ? [teile componentsJoinedByString: @" · "] : nil;
}

+ (NSDictionary*) dateiInhaltAus:(NSDictionary*) gruppenWerte build:(NSInteger) build version:(NSString*) version rechner:(NSString*) rechner
{
    return @{ @"SekhVetSettings": @1, @"Version": version ?: @"", @"Build": @( build), @"Date": [NSDate date], @"Computer": rechner ?: @"",
              @"ID": [[NSUUID UUID] UUIDString], @"Groups": gruppenWerte ?: @{}};
}

+ (NSDictionary*) gepruefterDateiInhalt:(id) plist fehler:(NSString**) fehler
{
    NSString *dummy = nil;
    if( fehler == NULL) fehler = &dummy;
    if( [plist isKindOfClass: [NSDictionary class]] == NO || [plist[ @"SekhVetSettings"] isKindOfClass: [NSNumber class]] == NO || [plist[ @"Groups"] isKindOfClass: [NSDictionary class]] == NO)
    {
        *fehler = @"This is not a SekhVet settings file.";
        return nil;
    }
    if( [plist[ @"SekhVetSettings"] intValue] != 1)
    {
        *fehler = @"This settings file was written by a newer SekhVet. Update SekhVet first.";
        return nil;
    }
    NSMutableDictionary *gr = [NSMutableDictionary dictionary];
    NSDictionary *roh = plist[ @"Groups"];
    for( NSString *g in roh)
    {
        if( [svGruppen() containsObject: g] == NO || [roh[ g] isKindOfClass: [NSDictionary class]] == NO) continue;   // unknown groups are dropped
        NSMutableDictionary *w = [NSMutableDictionary dictionary];
        for( NSString *k in roh[ g]) if( [[self gruppeFuerSchluessel: k] isEqualToString: g]) w[ k] = [self bereinigt: roh[ g][ k]];
        gr[ g] = w;
    }
    NSMutableDictionary *aus = [NSMutableDictionary dictionary];
    for( NSString *k in @[ @"Version", @"Computer", @"ID"]) aus[ k] = [plist[ k] isKindOfClass: [NSString class]] ? plist[ k] : @"";
    aus[ @"Build"] = [plist[ @"Build"] isKindOfClass: [NSNumber class]] ? plist[ @"Build"] : @0;
    if( [plist[ @"Date"] isKindOfClass: [NSDate class]]) aus[ @"Date"] = plist[ @"Date"];
    aus[ @"Groups"] = gr;
    return aus;
}

+ (NSDictionary*) vorgabeVersionen
{
    // SekhVet Paket DZ: raise a group's number when a build changes its built-in defaults. 2 = build 182/183
    // (opening: CT protocols by region; window: BODY_SHARP is a soft-tissue kernel).
    return @{ @"opening": @2, @"hanging": @1, @"window": @2, @"display": @1, @"overlay": @1, @"measure": @1, @"network": @1};
}

@end

#ifndef SEKHVET_LOGIC_TEST   // everything below needs the application classes

#import <Cocoa/Cocoa.h>

static NSString* const SekhmetSettingsBackupBuildKey = @"SekhmetSettingsBackupBuild";
static NSString* const SekhmetSettingsDefaultsSeenKey = @"SekhmetSettingsDefaultsSeen";
static NSString* const SekhmetPracticeSettingsSeenIDKey = @"SekhmetPracticeSettingsSeenID";
static NSString* const SekhmetPracticeSettingsOwnIDKey = @"SekhmetPracticeSettingsOwnID";
static NSString* const SekhmetPracticeFileName = @"SekhVet Practice Settings.sekhvet-settings";
static NSString* const SekhmetPracticePreviousName = @"SekhVet Practice Settings (previous).sekhvet-settings";
#define SEKHMET_SETTINGS_BACKUPS_KEEP 20
#define SEKHMET_SETTINGS_MAX_BYTES (20 * 1024 * 1024)

static BOOL svPraxisLaeuft = NO;      // a practice check / dialog is running
static NSDate *svPraxisZuletzt = nil; // last practice check (throttle)
static BOOL svPraxisOrdnerGemeldet = NO;

@implementation SekhmetEinstellungen (App)

#pragma mark Domain

+ (NSString*) domainName { return [[NSBundle mainBundle] bundleIdentifier] ?: @"vet.kappa1.sekhvet.horos"; }

+ (NSDictionary*) domain
{
    [[NSUserDefaults standardUserDefaults] synchronize];
    return [[NSUserDefaults standardUserDefaults] persistentDomainForName: [self domainName]] ?: @{};
}

// Writes the difference between the current domain and "neu" key by key, so that observers of NSUserDefaults see the change.
+ (void) uebernimmDomain:(NSDictionary*) neu
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *alt = [self domain];
    for( NSString *k in alt) if( neu[ k] == nil) [d removeObjectForKey: k];
    for( NSString *k in neu) if( [alt[ k] isEqual: neu[ k]] == NO) [d setObject: neu[ k] forKey: k];
    [d synchronize];
}

+ (NSInteger) build { return [[[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleVersion"] integerValue]; }
+ (NSString*) versionsText { return [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"] ?: @""; }
+ (NSString*) rechner { return [[NSHost currentHost] localizedName] ?: @""; }

// Effective values of a group: what is stored, otherwise the built-in default.
+ (NSDictionary*) wirksameWerteAus:(NSDictionary*) domain gruppe:(NSString*) g
{
    NSMutableDictionary *m = [NSMutableDictionary dictionary];
    NSDictionary *vorgabe = [[NSUserDefaults standardUserDefaults] volatileDomainForName: NSRegistrationDomain];
    for( NSString *k in vorgabe) if( [[self gruppeFuerSchluessel: k] isEqualToString: g]) m[ k] = vorgabe[ k];
    for( NSString *k in domain) if( [[self gruppeFuerSchluessel: k] isEqualToString: g]) m[ k] = domain[ k];
    return m;
}

#pragma mark Backups

+ (NSString*) sicherungsOrdner
{
    NSString *o = [[NSSearchPathForDirectoriesInDomains( NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent: @"SekhVet/Settings Backups"];
    [[NSFileManager defaultManager] createDirectoryAtPath: o withIntermediateDirectories: YES attributes: nil error: nil];
    return o;
}

+ (BOOL) schreibe:(NSDictionary*) inhalt nach:(NSString*) pfad fehler:(NSString**) fehler
{
    NSError *e = nil;
    NSData *daten = [NSPropertyListSerialization dataWithPropertyList: inhalt format: NSPropertyListXMLFormat_v1_0 options: 0 error: &e];
    if( daten == nil || [daten writeToFile: pfad options: NSDataWritingAtomic error: &e] == NO)
    {
        if( fehler) *fehler = [NSString stringWithFormat: @"%@ could not be written: %@", [pfad lastPathComponent], e.localizedDescription ?: @"unknown error"];
        return NO;
    }
    return YES;
}

// A backup of every group (network targets included, passwords never). The newest SEKHMET_SETTINGS_BACKUPS_KEEP stay.
+ (NSString*) sicherung:(NSString*) anlass
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"]];
    [f setDateFormat: @"yyyy-MM-dd HHmmss"];
    NSString *name = [NSString stringWithFormat: @"%@ build%ld %@.%@", [f stringFromDate: [NSDate date]], (long) [self build], anlass, SekhmetSettingsFileExtension];
    NSString *ordner = [self sicherungsOrdner], *pfad = [ordner stringByAppendingPathComponent: name];
    NSDictionary *inhalt = [self dateiInhaltAus: [self gruppenAus: [self domain] gruppen: svGruppen()] build: [self build] version: [self versionsText] rechner: [self rechner]];
    NSString *fehler = nil;
    if( [self schreibe: inhalt nach: pfad fehler: &fehler] == NO) { NSLog( @"SekhVet settings: backup failed: %@", fehler); return nil; }
    NSMutableArray *alle = [NSMutableArray array];
    for( NSString *n in [[NSFileManager defaultManager] contentsOfDirectoryAtPath: ordner error: nil])
        if( [[n pathExtension] isEqualToString: SekhmetSettingsFileExtension]) [alle addObject: n];
    [alle sortUsingSelector: @selector(compare:)];   // names start with the date
    while( alle.count > SEKHMET_SETTINGS_BACKUPS_KEEP)
    {
        [[NSFileManager defaultManager] removeItemAtPath: [ordner stringByAppendingPathComponent: alle[ 0]] error: nil];
        [alle removeObjectAtIndex: 0];
    }
    NSLog( @"SekhVet settings: backup written (%@)", anlass);
    return pfad;
}

+ (void) sicherungFuerNeuenBuild
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d integerForKey: SekhmetSettingsBackupBuildKey] >= [self build]) return;
    if( [self sicherung: @"new build"]) [d setInteger: [self build] forKey: SekhmetSettingsBackupBuildKey];
}

#pragma mark Dialog: group choice with preview

// One checkbox per group with its summary underneath. "zusammenfassungen" may lack a group (= no change).
+ (NSView*) auswahlFuer:(NSArray*) gruppen zusammenfassungen:(NSDictionary*) zf angehakt:(NSSet*) an knoepfe:(NSMutableArray*) knoepfe
{
    CGFloat breite = 520, y = 0;
    NSMutableArray *zeilen = [NSMutableArray array];
    for( NSString *g in gruppen)
    {
        NSButton *b = [NSButton checkboxWithTitle: [self titelFuerGruppe: g] target: nil action: nil];
        [b setState: [an containsObject: g] ? NSControlStateValueOn : NSControlStateValueOff];
        [b setIdentifier: g];
        [knoepfe addObject: b];
        NSString *text = zf[ g] ?: @"no change";
        NSTextField *t = [NSTextField wrappingLabelWithString: text];
        [t setFont: [NSFont systemFontOfSize: 11]];
        [t setTextColor: [NSColor secondaryLabelColor]];
        [t setPreferredMaxLayoutWidth: breite - 24];
        [zeilen addObject: @[ b, t]];
    }
    // lay out from the bottom up (flipped coordinates are not available in a plain NSView)
    NSView *v = [[[NSView alloc] initWithFrame: NSZeroRect] autorelease];
    for( NSArray *z in [zeilen reverseObjectEnumerator])
    {
        NSTextField *t = z[ 1];
        NSSize ts = [t fittingSize];
        [t setFrame: NSMakeRect( 22, y, breite - 24, ts.height)];
        y += ts.height + 2;
        NSButton *b = z[ 0];
        [b sizeToFit];
        [b setFrameOrigin: NSMakePoint( 0, y)];
        y += NSHeight( [b frame]) + 8;
        [v addSubview: t];
        [v addSubview: b];
    }
    [v setFrame: NSMakeRect( 0, 0, breite, y)];
    if( y <= 360) return v;
    NSScrollView *s = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 0, 0, breite + 18, 360)] autorelease];
    [s setHasVerticalScroller: YES];
    [s setDocumentView: v];
    [v scrollPoint: NSMakePoint( 0, y)];
    return s;
}

+ (NSArray*) angehakt:(NSArray*) knoepfe
{
    NSMutableArray *a = [NSMutableArray array];
    for( NSButton *b in knoepfe) if( [b state] == NSControlStateValueOn) [a addObject: [b identifier]];
    return a;
}

+ (NSString*) herkunftVon:(NSDictionary*) inhalt
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateStyle: NSDateFormatterMediumStyle];
    [f setTimeStyle: NSDateFormatterShortStyle];
    return [NSString stringWithFormat: @"From %@, SekhVet %@ (build %@), %@.", [inhalt[ @"Computer"] length] ? inhalt[ @"Computer"] : @"an unknown computer",
            inhalt[ @"Version"], inhalt[ @"Build"], inhalt[ @"Date"] ? [f stringFromDate: inhalt[ @"Date"]] : @"date unknown"];
}

// Summaries for taking over the groups of a file: current effective values -> values after the take-over.
+ (NSDictionary*) zusammenfassungenFuerDatei:(NSDictionary*) inhalt
{
    NSDictionary *domain = [self domain];
    NSMutableDictionary *zf = [NSMutableDictionary dictionary];
    for( NSString *g in inhalt[ @"Groups"])
    {
        NSDictionary *nachher = [self domain: domain nachUebernahmeVon: inhalt[ @"Groups"] gruppen: @[ g]];
        NSString *z = [self zusammenfassungVon: [self wirksameWerteAus: domain gruppe: g] nach: [self wirksameWerteAus: nachher gruppe: g] gruppe: g];
        if( z) zf[ g] = z;
    }
    return zf;
}

+ (NSArray*) geordnet:(id) gruppen
{
    NSMutableArray *a = [NSMutableArray array];
    for( NSString *g in svGruppen()) if( [gruppen containsObject: g]) [a addObject: g];
    return a;
}

// Takes the chosen groups of a checked file over: backup first, then group by group as a whole.
+ (void) uebernimm:(NSDictionary*) inhalt gruppen:(NSArray*) gruppen anlass:(NSString*) anlass
{
    [self sicherung: anlass];
    [self uebernimmDomain: [self domain: [self domain] nachUebernahmeVon: inhalt[ @"Groups"] gruppen: gruppen]];
    NSLog( @"SekhVet settings: %lu group(s) taken over (%@)", (unsigned long) gruppen.count, anlass);
}

+ (NSDictionary*) leseDatei:(NSString*) pfad fehler:(NSString**) fehler
{
    NSDictionary *attr = [[NSFileManager defaultManager] attributesOfItemAtPath: pfad error: nil];
    if( attr == nil) { *fehler = @"The file cannot be read."; return nil; }
    if( [attr fileSize] > SEKHMET_SETTINGS_MAX_BYTES) { *fehler = @"The file is too large for a SekhVet settings file."; return nil; }
    NSData *daten = [NSData dataWithContentsOfFile: pfad];
    id plist = daten ? [NSPropertyListSerialization propertyListWithData: daten options: NSPropertyListImmutable format: NULL error: nil] : nil;
    return [self gepruefterDateiInhalt: plist fehler: fehler];
}

+ (void) zeigeFehler:(NSString*) text titel:(NSString*) titel
{
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: titel];
    [a setInformativeText: text ?: @""];
    [a runModal];
}

#pragma mark Export / Import / Restore

+ (void) exportieren:(id) sender
{
    NSDictionary *domain = [self domain];
    NSDictionary *werte = [self gruppenAus: domain gruppen: svGruppen()];
    NSMutableDictionary *zf = [NSMutableDictionary dictionary];
    for( NSString *g in werte) zf[ g] = [NSString stringWithFormat: @"%lu stored setting(s); settings you never changed travel as built-in defaults", (unsigned long) [werte[ g] count]];
    NSMutableArray *knoepfe = [NSMutableArray array];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"Export Vet Settings", nil)];
    [a setInformativeText: NSLocalizedString( @"Choose what goes into the file. Passwords, the DICOM listener, routing, database locations and screen layout are never included.", nil)];
    [a setAccessoryView: [self auswahlFuer: svGruppen() zusammenfassungen: zf angehakt: [NSSet setWithArray: [svGruppen() subarrayWithRange: NSMakeRange( 0, 6)]] knoepfe: knoepfe]];
    [a addButtonWithTitle: NSLocalizedString( @"Export…", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    NSArray *gruppen = [self angehakt: knoepfe];
    if( gruppen.count == 0) return;
    NSSavePanel *sp = [NSSavePanel savePanel];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateFormat: @"yyyy-MM-dd"];
    [sp setNameFieldStringValue: [NSString stringWithFormat: @"SekhVet Settings %@.%@", [f stringFromDate: [NSDate date]], SekhmetSettingsFileExtension]];
    if( [sp runModal] != NSModalResponseOK) return;
    NSString *fehler = nil;
    NSDictionary *inhalt = [self dateiInhaltAus: [self gruppenAus: domain gruppen: gruppen] build: [self build] version: [self versionsText] rechner: [self rechner]];
    if( [self schreibe: inhalt nach: [[sp URL] path] fehler: &fehler] == NO) [self zeigeFehler: fehler titel: NSLocalizedString( @"Export Vet Settings", nil)];
}

// Import and restore share this dialog. "anlass" names the backup that is written first.
+ (void) importiereDatei:(NSString*) pfad titel:(NSString*) titel knopf:(NSString*) knopf anlass:(NSString*) anlass
{
    NSString *fehler = nil;
    NSDictionary *inhalt = [self leseDatei: pfad fehler: &fehler];
    if( inhalt == nil) { [self zeigeFehler: fehler titel: titel]; return; }
    NSArray *gruppen = [self geordnet: [inhalt[ @"Groups"] allKeys]];
    if( gruppen.count == 0) { [self zeigeFehler: NSLocalizedString( @"The file contains no settings SekhVet can take over.", nil) titel: titel]; return; }
    NSMutableSet *an = [NSMutableSet setWithArray: gruppen];
    [an removeObject: @"network"];   // network targets only when ticked on purpose
    NSMutableArray *knoepfe = [NSMutableArray array];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: titel];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"%@ Each ticked group replaces your current one as a whole. A backup of your current settings is made first (Vet Tools › Vet Settings › Restore Settings Backup…).", nil), [self herkunftVon: inhalt]]];
    [a setAccessoryView: [self auswahlFuer: gruppen zusammenfassungen: [self zusammenfassungenFuerDatei: inhalt] angehakt: an knoepfe: knoepfe]];
    [a addButtonWithTitle: knopf];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    NSArray *gewaehlt = [self angehakt: knoepfe];
    if( gewaehlt.count == 0) return;
    [self uebernimm: inhalt gruppen: gewaehlt anlass: anlass];
    [self zeigeFehler: NSLocalizedString( @"Done. Some changes (hanging protocols, keys, toolbars) take full effect after SekhVet is restarted.", nil) titel: titel];
}

+ (NSString*) waehleDateiIn:(NSString*) ordner titel:(NSString*) titel
{
    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setTitle: titel];
    [op setAllowedFileTypes: @[ SekhmetSettingsFileExtension]];
    [op setCanChooseDirectories: NO];
    [op setAllowsMultipleSelection: NO];
    if( ordner) [op setDirectoryURL: [NSURL fileURLWithPath: ordner]];
    return [op runModal] == NSModalResponseOK ? [[op URL] path] : nil;
}

+ (void) importieren:(id) sender
{
    NSString *t = NSLocalizedString( @"Import Vet Settings", nil);
    NSString *p = [self waehleDateiIn: nil titel: t];
    if( p) [self importiereDatei: p titel: t knopf: NSLocalizedString( @"Import", nil) anlass: @"before import"];
}

+ (void) wiederherstellen:(id) sender
{
    NSString *t = NSLocalizedString( @"Restore Settings Backup", nil);
    NSString *p = [self waehleDateiIn: [self sicherungsOrdner] titel: t];
    if( p) [self importiereDatei: p titel: t knopf: NSLocalizedString( @"Restore", nil) anlass: @"before restore"];
}

#pragma mark Practice settings folder

+ (NSString*) praxisOrdner
{
    NSString *o = [[NSUserDefaults standardUserDefaults] stringForKey: SekhmetPracticeSettingsFolderKey];
    return o.length ? o : nil;
}

+ (void) praxisOrdnerEinstellen:(id) sender
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    for( ;;)
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"Practice Settings Folder", nil)];
        NSString *o = [self praxisOrdner];
        [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"A folder all SekhVet computers of the practice can read, e.g. on the NAS. Whoever may change the practice settings needs write access there. SekhVet looks for new practice settings at start and whenever it comes to the front, and shows what would change before anything is taken over. No network port is opened.\n\nCurrent folder: %@", nil), o ?: NSLocalizedString( @"none", nil)]];
        NSButton *auto_ = [NSButton checkboxWithTitle: NSLocalizedString( @"Apply new practice settings without asking (network targets are never applied this way)", nil) target: nil action: nil];
        [auto_ setState: [d boolForKey: SekhmetPracticeSettingsAutoApplyKey] ? NSControlStateValueOn : NSControlStateValueOff];
        [auto_ sizeToFit];
        [a setAccessoryView: auto_];
        [a addButtonWithTitle: NSLocalizedString( @"Done", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Choose Folder…", nil)];
        if( o) [a addButtonWithTitle: NSLocalizedString( @"Remove Folder", nil)];
        NSModalResponse r = [a runModal];
        [d setBool: [auto_ state] == NSControlStateValueOn forKey: SekhmetPracticeSettingsAutoApplyKey];
        if( r == NSAlertFirstButtonReturn) break;
        if( r == NSAlertSecondButtonReturn)
        {
            NSOpenPanel *op = [NSOpenPanel openPanel];
            [op setCanChooseDirectories: YES];
            [op setCanChooseFiles: NO];
            [op setCanCreateDirectories: YES];
            [op setPrompt: NSLocalizedString( @"Use Folder", nil)];
            if( [op runModal] == NSModalResponseOK)
            {
                [d setObject: [[op URL] path] forKey: SekhmetPracticeSettingsFolderKey];
                svPraxisOrdnerGemeldet = NO;
            }
            continue;
        }
        [d removeObjectForKey: SekhmetPracticeSettingsFolderKey];
    }
    [d synchronize];
    if( [self praxisOrdner]) [self performSelector: @selector(pruefePraxisordnerJetzt) withObject: nil afterDelay: 0.5];
}

+ (void) pruefePraxisordnerJetzt { [self pruefePraxisordnerErzwungen: YES]; }

// Writes the practice file in place: the previous version is kept next to it under a fixed name.
+ (BOOL) veroeffentliche:(NSDictionary*) inhalt imOrdner:(NSString*) ordner fehler:(NSString**) fehler
{
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *ziel = [ordner stringByAppendingPathComponent: SekhmetPracticeFileName], *vorher = [ordner stringByAppendingPathComponent: SekhmetPracticePreviousName];
    NSString *tmp = [ordner stringByAppendingPathComponent: [NSString stringWithFormat: @".sekhvet-%@.tmp", [[NSUUID UUID] UUIDString]]];
    if( [self schreibe: inhalt nach: tmp fehler: fehler] == NO) return NO;
    if( [fm fileExistsAtPath: ziel])
    {
        [fm removeItemAtPath: vorher error: nil];
        [fm moveItemAtPath: ziel toPath: vorher error: nil];
    }
    NSError *e = nil;
    if( [fm moveItemAtPath: tmp toPath: ziel error: &e] == NO)
    {
        [fm removeItemAtPath: tmp error: nil];
        if( fehler) *fehler = [NSString stringWithFormat: @"The practice settings could not be written: %@", e.localizedDescription];
        return NO;
    }
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [d setObject: inhalt[ @"ID"] forKey: SekhmetPracticeSettingsOwnIDKey];
    [d setObject: inhalt[ @"ID"] forKey: SekhmetPracticeSettingsSeenIDKey];   // the publishing computer is not asked about its own version
    return YES;
}

+ (void) veroeffentlichen:(id) sender
{
    NSString *t = NSLocalizedString( @"Publish Practice Settings", nil);
    if( [self praxisOrdner] == nil)
    {
        [self praxisOrdnerEinstellen: nil];
        if( [self praxisOrdner] == nil) return;
    }
    NSDictionary *domain = [self domain];
    NSMutableDictionary *zf = [NSMutableDictionary dictionary];
    NSDictionary *werte = [self gruppenAus: domain gruppen: svGruppen()];
    for( NSString *g in werte) zf[ g] = [NSString stringWithFormat: @"%lu stored setting(s) of this computer", (unsigned long) [werte[ g] count]];
    NSMutableArray *knoepfe = [NSMutableArray array];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: t];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"The ticked groups of THIS computer become the practice settings in\n%@\nEvery SekhVet computer using this folder will offer them, with a preview, before taking them over. The previous practice settings are kept in the same folder.", nil), [self praxisOrdner]]];
    [a setAccessoryView: [self auswahlFuer: svGruppen() zusammenfassungen: zf angehakt: [NSSet setWithArray: [svGruppen() subarrayWithRange: NSMakeRange( 0, 6)]] knoepfe: knoepfe]];
    [a addButtonWithTitle: NSLocalizedString( @"Publish", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    NSArray *gruppen = [self angehakt: knoepfe];
    if( gruppen.count == 0) return;
    NSString *fehler = nil;
    NSDictionary *inhalt = [self dateiInhaltAus: [self gruppenAus: domain gruppen: gruppen] build: [self build] version: [self versionsText] rechner: [self rechner]];
    if( [self veroeffentliche: inhalt imOrdner: [self praxisOrdner] fehler: &fehler] == NO) [self zeigeFehler: fehler titel: t];
    else [self zeigeFehler: NSLocalizedString( @"The practice settings are published. The other computers offer them the next time SekhVet starts or comes to the front.", nil) titel: t];
}

+ (void) pruefePraxisordnerErzwungen:(BOOL) erzwungen
{
    if( svPraxisLaeuft) return;
    if( erzwungen == NO && svPraxisZuletzt && -[svPraxisZuletzt timeIntervalSinceNow] < 60) return;
    if( [NSApp modalWindow]) return;   // never on top of another dialog; the next activation tries again
    NSString *ordner = [self praxisOrdner];
    if( ordner == nil) return;
    [svPraxisZuletzt release];
    svPraxisZuletzt = [[NSDate date] retain];
    NSString *pfad = [ordner stringByAppendingPathComponent: SekhmetPracticeFileName];
    BOOL istOrdner = NO;
    if( [[NSFileManager defaultManager] fileExistsAtPath: ordner isDirectory: &istOrdner] == NO || istOrdner == NO)
    {
        if( svPraxisOrdnerGemeldet == NO) NSLog( @"SekhVet settings: practice settings folder not reachable");
        svPraxisOrdnerGemeldet = YES;
        return;
    }
    if( [[NSFileManager defaultManager] fileExistsAtPath: pfad] == NO) return;
    NSString *fehler = nil;
    NSDictionary *inhalt = [self leseDatei: pfad fehler: &fehler];
    if( inhalt == nil) { NSLog( @"SekhVet settings: practice settings file not readable: %@", fehler); return; }   // e.g. still being written
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *kennung = inhalt[ @"ID"];
    if( kennung.length == 0 || [kennung isEqualToString: [d stringForKey: SekhmetPracticeSettingsSeenIDKey] ?: @""]) return;
    NSArray *gruppen = [self geordnet: [inhalt[ @"Groups"] allKeys]];
    if( [d boolForKey: SekhmetPracticeSettingsAutoApplyKey])
    {
        NSMutableArray *ohneNetz = [NSMutableArray arrayWithArray: gruppen];
        [ohneNetz removeObject: @"network"];
        [self uebernimm: inhalt gruppen: ohneNetz anlass: @"before practice settings"];
        [d setObject: kennung forKey: SekhmetPracticeSettingsSeenIDKey];
        return;
    }
    svPraxisLaeuft = YES;
    NSMutableSet *an = [NSMutableSet setWithArray: gruppen];
    [an removeObject: @"network"];
    NSMutableArray *knoepfe = [NSMutableArray array];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"New Practice Settings", nil)];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"%@ This is what would change on this computer. Each ticked group replaces your current one as a whole; a backup of your current settings is made first.", nil), [self herkunftVon: inhalt]]];
    [a setAccessoryView: [self auswahlFuer: gruppen zusammenfassungen: [self zusammenfassungenFuerDatei: inhalt] angehakt: an knoepfe: knoepfe]];
    [a addButtonWithTitle: NSLocalizedString( @"Apply", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Later", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Reject", nil)];
    NSModalResponse r = [a runModal];
    svPraxisLaeuft = NO;
    if( r == NSAlertFirstButtonReturn)
    {
        NSArray *gewaehlt = [self angehakt: knoepfe];
        if( gewaehlt.count) [self uebernimm: inhalt gruppen: gewaehlt anlass: @"before practice settings"];
        [d setObject: kennung forKey: SekhmetPracticeSettingsSeenIDKey];
    }
    else if( r == NSAlertThirdButtonReturn) [d setObject: kennung forKey: SekhmetPracticeSettingsSeenIDKey];
    else
    {
        [svPraxisZuletzt release];   // Later: not before the next minute
        svPraxisZuletzt = [[NSDate date] retain];
    }
}

+ (void) wurdeAktiv { [self pruefePraxisordnerErzwungen: NO]; }

#pragma mark New built-in defaults

// Groups whose built-in defaults are newer than what this computer has seen and that hold own values different from
// those defaults. A first installation has seen everything; an installation from before this package has seen version 1.
+ (NSArray*) gruppenMitNeuenVorgaben
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *domain = [self domain];
    NSMutableDictionary *gesehen = [NSMutableDictionary dictionaryWithDictionary: [d dictionaryForKey: SekhmetSettingsDefaultsSeenKey] ?: @{}];
    if( [d dictionaryForKey: SekhmetSettingsDefaultsSeenKey] == nil)
    {
        BOOL alt = NO;
        for( NSString *k in domain) if( [self gruppeFuerSchluessel: k]) { alt = YES; break; }
        for( NSString *g in svGruppen()) gesehen[ g] = alt ? @1 : [self vorgabeVersionen][ g];
        [d setObject: gesehen forKey: SekhmetSettingsDefaultsSeenKey];
    }
    NSDictionary *vorgabe = [d volatileDomainForName: NSRegistrationDomain];
    NSMutableArray *aus = [NSMutableArray array];
    for( NSString *g in svGruppen())
    {
        if( [[self vorgabeVersionen][ g] intValue] <= [gesehen[ g] intValue]) continue;
        BOOL eigen = NO;
        for( NSString *k in domain)
            if( [[self gruppeFuerSchluessel: k] isEqualToString: g] && [domain[ k] isEqual: vorgabe[ k]] == NO) { eigen = YES; break; }
        if( eigen) [aus addObject: g];
        else gesehen[ g] = [self vorgabeVersionen][ g];   // nothing of its own: the new defaults apply anyway
    }
    [d setObject: gesehen forKey: SekhmetSettingsDefaultsSeenKey];
    return aus;
}

+ (void) merkeVorgabenGesehen:(NSArray*) gruppen
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableDictionary *gesehen = [NSMutableDictionary dictionaryWithDictionary: [d dictionaryForKey: SekhmetSettingsDefaultsSeenKey] ?: @{}];
    for( NSString *g in gruppen) gesehen[ g] = [self vorgabeVersionen][ g];
    [d setObject: gesehen forKey: SekhmetSettingsDefaultsSeenKey];
}

+ (void) ersetzeDurchVorgaben:(NSArray*) gruppen
{
    [self sicherung: @"before new defaults"];
    [self uebernimmDomain: [self domain: [self domain] nachUebernahmeVon: @{} gruppen: gruppen]];   // remove = built-in default
    [self merkeVorgabenGesehen: gruppen];
    NSLog( @"SekhVet settings: %lu group(s) replaced by the new built-in defaults", (unsigned long) gruppen.count);
}

+ (void) bieteNeueVorgabenAn
{
    NSArray *gruppen = [self gruppenMitNeuenVorgaben];
    if( gruppen.count == 0) return;
    NSDictionary *domain = [self domain];
    NSMutableDictionary *zf = [NSMutableDictionary dictionary];
    for( NSString *g in gruppen)
    {
        NSDictionary *nachher = [self domain: domain nachUebernahmeVon: @{} gruppen: @[ g]];
        zf[ g] = [self zusammenfassungVon: [self wirksameWerteAus: domain gruppe: g] nach: [self wirksameWerteAus: nachher gruppe: g] gruppe: g] ?: @"no change";
    }
    for( ;;)
    {
        NSMutableArray *knoepfe = [NSMutableArray array];
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"New Default Settings in This Version", nil)];
        [a setInformativeText: NSLocalizedString( @"This version of SekhVet brings new built-in settings for groups you have changed yourself. Replace a group to get the new defaults; your current settings go into a backup first (Vet Tools › Vet Settings › Restore Settings Backup…).", nil)];
        [a setAccessoryView: [self auswahlFuer: gruppen zusammenfassungen: zf angehakt: [NSSet setWithArray: gruppen] knoepfe: knoepfe]];
        [a addButtonWithTitle: NSLocalizedString( @"Replace", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Not Now", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"View…", nil)];
        NSModalResponse r = [a runModal];
        if( r == NSAlertFirstButtonReturn)
        {
            NSArray *gewaehlt = [self angehakt: knoepfe];
            if( gewaehlt.count) [self ersetzeDurchVorgaben: gewaehlt];
            NSMutableArray *rest = [NSMutableArray arrayWithArray: gruppen];
            [rest removeObjectsInArray: gewaehlt];
            [self merkeVorgabenGesehen: rest];   // unticked groups: decided, not asked again for this version
            return;
        }
        if( r == NSAlertSecondButtonReturn) return;   // asked again at the next start
        [self zeigeVorgaben: gruppen];
    }
}

// "View…": the built-in defaults of the groups, readable, next to what this computer has.
+ (void) zeigeVorgaben:(NSArray*) gruppen
{
    NSDictionary *domain = [self domain];
    NSMutableString *s = [NSMutableString string];
    for( NSString *g in gruppen)
    {
        [s appendFormat: @"%@\n", [self titelFuerGruppe: g]];
        NSDictionary *jetzt = [self wirksameWerteAus: domain gruppe: g], *neu = [self wirksameWerteAus: [self domain: domain nachUebernahmeVon: @{} gruppen: @[ g]] gruppe: g];
        for( NSString *k in [[neu allKeys] sortedArrayUsingSelector: @selector(compare:)])
        {
            if( [jetzt[ k] isEqual: neu[ k]]) continue;
            NSMutableArray *namen = [NSMutableArray array];
            if( [neu[ k] isKindOfClass: [NSArray class]]) for( id e in neu[ k]) { NSString *n = svName( e); if( n) [namen addObject: n]; }
            if( namen.count) [s appendFormat: @"  new: %@\n", [namen componentsJoinedByString: @", "]];
            namen = [NSMutableArray array];
            if( [jetzt[ k] isKindOfClass: [NSArray class]]) for( id e in jetzt[ k]) { NSString *n = svName( e); if( n) [namen addObject: n]; }
            if( namen.count) [s appendFormat: @"  yours: %@\n", [namen componentsJoinedByString: @", "]];
        }
        [s appendString: @"\n"];
    }
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 0, 0, 540, 300)] autorelease];
    NSTextView *tv = [[[NSTextView alloc] initWithFrame: NSMakeRect( 0, 0, 522, 300)] autorelease];
    [tv setString: s];
    [tv setEditable: NO];
    [tv setFont: [NSFont systemFontOfSize: 11]];
    [sv setHasVerticalScroller: YES];
    [sv setDocumentView: tv];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"New Default Settings", nil)];
    [a setAccessoryView: sv];
    [a runModal];
}

#pragma mark Start / menu

// SekhVet Paket EF: a fresh install has no settings of its own. gruppenMitNeuenVorgaben used to decide "old install"
// from any group key in the domain -- but by the time beimStart runs, the start itself has written some (e.g.
// SekhmetWLWWRulesVersion), so every new user got "New Default Settings in This Version" on the first start.
// Decided here instead, before NSApplicationMain: an empty domain means all current defaults count as seen.
+ (void) merkeErstenStart
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *dom = [d persistentDomainForName: [self domainName]];
    if( dom.count > 0 || [d objectForKey: SekhmetSettingsDefaultsSeenKey]) return;
    [d setObject: [self vorgabeVersionen] forKey: SekhmetSettingsDefaultsSeenKey];
    NSLog( @"SekhVet settings: fresh install, current defaults count as seen");
}

+ (void) beimStart
{
    if( [NSApp modalWindow]) { [self performSelector: _cmd withObject: nil afterDelay: 10]; return; }   // e.g. the first-start notice is up
    @try
    {
        [self sicherungFuerNeuenBuild];
        [self bieteNeueVorgabenAn];
        [self pruefePraxisordnerErzwungen: YES];
    }
    @catch( NSException *e) { NSLog( @"SekhVet settings: start check failed: %@", e); }
}

+ (NSMenu*) menu
{
    NSMenu *m = [[[NSMenu alloc] initWithTitle: NSLocalizedString( @"Vet Settings", nil)] autorelease];
    [[m addItemWithTitle: NSLocalizedString( @"Export Vet Settings…", nil) action: @selector(exportieren:) keyEquivalent: @""] setTarget: self];
    [[m addItemWithTitle: NSLocalizedString( @"Import Vet Settings…", nil) action: @selector(importieren:) keyEquivalent: @""] setTarget: self];
    [[m addItemWithTitle: NSLocalizedString( @"Restore Settings Backup…", nil) action: @selector(wiederherstellen:) keyEquivalent: @""] setTarget: self];
    [m addItem: [NSMenuItem separatorItem]];
    [[m addItemWithTitle: NSLocalizedString( @"Practice Settings Folder…", nil) action: @selector(praxisOrdnerEinstellen:) keyEquivalent: @""] setTarget: self];
    [[m addItemWithTitle: NSLocalizedString( @"Publish Practice Settings…", nil) action: @selector(veroeffentlichen:) keyEquivalent: @""] setTarget: self];
    return m;
}

#pragma mark Test

#if SEKHVET_TESTHAKEN
// SEKHVET_SETTINGS_TEST=1: export -> import, password stripped, blocked keys untouched, practice folder (auto-apply),
// backup on a new build, defaults offer. Works on a snapshot of the domain and puts it back at the end.
+ (void) debugFromEnvironment
{
    NSString *P = @"SekhVet Settings-E2E";
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *schnappschuss = [[self domain] copy];
    NSString *praxis = @"/tmp/sekhvet-praxis-test";
    @try
    {
        // 1 backup on a new build
        [d setInteger: 1 forKey: SekhmetSettingsBackupBuildKey];
        NSUInteger vorher = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath: [self sicherungsOrdner] error: nil] count];
        [self sicherungFuerNeuenBuild];
        NSUInteger nachher = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath: [self sicherungsOrdner] error: nil] count];
        NSLog( @"%@ 1: Sicherung bei neuem Build %@ (%lu -> %lu Dateien), Merker %ld (erwartet %ld)", P, nachher > vorher || nachher == SEKHMET_SETTINGS_BACKUPS_KEEP ? @"JA" : @"NEIN",
              (unsigned long) vorher, (unsigned long) nachher, (long) [d integerForKey: SekhmetSettingsBackupBuildKey], (long) [self build]);

        // 2 export with a password in a DICOMweb node
        NSArray *knotenAlt = [d arrayForKey: @"SekhmetDICOMwebNodes"];
        [d setObject: @[ @{ @"name": @"E2E", @"url": @"https://example.org/dicom-web", @"user": @"e2e", @"password": @"geheim"}] forKey: @"SekhmetDICOMwebNodes"];
        NSDictionary *datei = [self dateiInhaltAus: [self gruppenAus: [self domain] gruppen: svGruppen()] build: [self build] version: [self versionsText] rechner: [self rechner]];
        NSString *pfad = @"/tmp/sekhvet-e2e.sekhvet-settings", *fehler = nil;
        BOOL ok = [self schreibe: datei nach: pfad fehler: &fehler];
        NSString *roh = [NSString stringWithContentsOfFile: pfad encoding: NSUTF8StringEncoding error: nil];
        BOOL gesperrtDrin = NO;
        for( NSString *g in datei[ @"Groups"]) for( NSString *k in datei[ @"Groups"][ g]) if( [self istGesperrt: k]) gesperrtDrin = YES;
        NSLog( @"%@ 2: Export geschrieben %@, Passwort in Datei %@ (erwartet NEIN), gesperrte Schluessel %@ (erwartet NEIN), Gruppen %lu", P, ok ? @"JA" : @"NEIN",
              [roh rangeOfString: @"geheim"].location != NSNotFound ? @"JA" : @"NEIN", gesperrtDrin ? @"JA" : @"NEIN", (unsigned long) [datei[ @"Groups"] count]);
        if( knotenAlt) [d setObject: knotenAlt forKey: @"SekhmetDICOMwebNodes"]; else [d removeObjectForKey: @"SekhmetDICOMwebNodes"];

        // 3 import: opening protocols back, STORESCP untouched
        id oeffnenAlt = [[d objectForKey: @"SekhmetOpeningProtocols"] retain];
        BOOL storeAlt = [d boolForKey: @"STORESCP"];
        [d setObject: @[] forKey: @"SekhmetOpeningProtocols"];
        [d setBool: !storeAlt forKey: @"STORESCP"];
        NSDictionary *gelesen = [self leseDatei: pfad fehler: &fehler];
        [self uebernimm: gelesen gruppen: @[ @"opening", @"window"] anlass: @"before import"];
        id oeffnenNeu = [d objectForKey: @"SekhmetOpeningProtocols"];
        NSLog( @"%@ 3: Import Oeffnungsprotokolle zurueck %@ (%lu Protokolle), STORESCP unberuehrt %@", P, [oeffnenNeu isEqual: oeffnenAlt] ? @"JA" : @"NEIN",
              (unsigned long) [oeffnenNeu count], [d boolForKey: @"STORESCP"] == !storeAlt ? @"JA" : @"NEIN");
        [d setBool: storeAlt forKey: @"STORESCP"];

        // 4 practice folder, auto-apply
        [[NSFileManager defaultManager] removeItemAtPath: praxis error: nil];
        [[NSFileManager defaultManager] createDirectoryAtPath: praxis withIntermediateDirectories: YES attributes: nil error: nil];
        [d setObject: praxis forKey: SekhmetPracticeSettingsFolderKey];
        NSDictionary *praxisInhalt = [self dateiInhaltAus: [self gruppenAus: [self domain] gruppen: @[ @"opening"]] build: [self build] version: [self versionsText] rechner: @"E2E"];
        ok = [self veroeffentliche: praxisInhalt imOrdner: praxis fehler: &fehler];
        [d removeObjectForKey: SekhmetPracticeSettingsSeenIDKey];
        [d setBool: YES forKey: SekhmetPracticeSettingsAutoApplyKey];
        [d setObject: @[] forKey: @"SekhmetOpeningProtocols"];
        [self pruefePraxisordnerErzwungen: YES];
        BOOL zurueck = [[d objectForKey: @"SekhmetOpeningProtocols"] isEqual: oeffnenAlt];
        BOOL gesehen = [[d stringForKey: SekhmetPracticeSettingsSeenIDKey] isEqualToString: praxisInhalt[ @"ID"]];
        [d setObject: @[] forKey: @"SekhmetOpeningProtocols"];
        [self pruefePraxisordnerErzwungen: YES];   // same version again: nothing happens
        BOOL nichtNochmal = [[d objectForKey: @"SekhmetOpeningProtocols"] count] == 0;
        ok = ok && [self veroeffentliche: praxisInhalt imOrdner: praxis fehler: &fehler];   // second publish keeps the previous one
        BOOL vorherDa = [[NSFileManager defaultManager] fileExistsAtPath: [praxis stringByAppendingPathComponent: SekhmetPracticePreviousName]];
        NSLog( @"%@ 4: Praxisordner veroeffentlicht %@, automatisch uebernommen %@, als gesehen gemerkt %@, gleiche Fassung nicht nochmal %@, vorige Fassung behalten %@", P,
              ok ? @"JA" : @"NEIN", zurueck ? @"JA" : @"NEIN", gesehen ? @"JA" : @"NEIN", nichtNochmal ? @"JA" : @"NEIN", vorherDa ? @"JA" : @"NEIN");

        // 5 defaults offer
        [d setObject: @{ @"opening": @1, @"hanging": @1, @"window": @2, @"display": @1, @"overlay": @1, @"measure": @1, @"network": @1} forKey: SekhmetSettingsDefaultsSeenKey];
        [d setObject: @[ @{ @"name": @"E2E only", @"modality": @"CT", @"region": @"", @"rows": @1, @"columns": @1, @"blackTiles": @NO, @"positions": @[]}] forKey: @"SekhmetOpeningProtocols"];
        NSArray *k1 = [self gruppenMitNeuenVorgaben];
        [d setObject: @{ @"opening": @1, @"hanging": @1, @"window": @2, @"display": @1, @"overlay": @1, @"measure": @1, @"network": @1} forKey: SekhmetSettingsDefaultsSeenKey];
        [d removeObjectForKey: @"SekhmetOpeningProtocols"];
        NSArray *k2 = [self gruppenMitNeuenVorgaben];
        [d setObject: @[ @{ @"name": @"E2E only", @"modality": @"CT", @"region": @"", @"rows": @1, @"columns": @1, @"blackTiles": @NO, @"positions": @[]}] forKey: @"SekhmetOpeningProtocols"];
        [self ersetzeDurchVorgaben: @[ @"opening"]];
        NSUInteger vorgabeAnzahl = [[d arrayForKey: @"SekhmetOpeningProtocols"] count];
        NSLog( @"%@ 5: Angebot mit eigenen Protokollen %@ (erwartet opening), ohne eigene %@ (erwartet leer), nach Ersetzen gespeichert %@ (erwartet NEIN), wirksam %lu Protokolle", P,
              [k1 componentsJoinedByString: @","], [k2 componentsJoinedByString: @","], [d persistentDomainForName: [self domainName]][ @"SekhmetOpeningProtocols"] ? @"JA" : @"NEIN", (unsigned long) vorgabeAnzahl);
        [oeffnenAlt release];
    }
    @catch( NSException *e) { NSLog( @"%@: AUSNAHME %@", P, e); }
    [d setPersistentDomain: schnappschuss forName: [self domainName]];
    [d synchronize];
    [schnappschuss release];
    [[NSFileManager defaultManager] removeItemAtPath: praxis error: nil];
    [[NSFileManager defaultManager] removeItemAtPath: @"/tmp/sekhvet-e2e.sekhvet-settings" error: nil];
    NSLog( @"%@: fertig, Einstellungen zurueckgesetzt", P);
}
#endif // SEKHVET_TESTHAKEN

@end

#endif // SEKHVET_LOGIC_TEST
