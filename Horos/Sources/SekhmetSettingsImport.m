// Teil des SekhVet-Forks von Horos, LGPL-3.0.
// SekhVet Paket EI (29.10.2026): Einstellungen aus Horos / OsiriX uebernehmen. Siehe Header.

#import "SekhmetSettingsImport.h"
#import "SekhmetTesthaken.h"
#import "AppController.h"
#import "QueryController.h"
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <netdb.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>

NSString* const SekhmetSettingsImportOfferedKey = @"SekhmetSettingsImportOffered";

static NSString* const kGroupNodes = @"nodes";
static NSString* const kGroupListener = @"listener";
static NSString* const kGroupHotkeys = @"hotkeys";
static NSString* const kGroupPresets = @"presets";
static NSString* const kGroupDisplay = @"display";
static NSString* const kGroupQuery = @"query";

// Quellen: Domain -> Anzeigename. org.horosproject.horos ist die Domain, die Horos 3/4 tatsaechlich schreibt.
static NSArray* sekhmetSourceDomains( void)
{
    return @[ @[ @"org.horosproject.horos", @"Horos" ], @[ @"com.horosproject.horos", @"Horos" ],
              @[ @"com.rossetantoine.osirix", @"OsiriX" ], @[ @"com.pixmeo.osirixlite", @"OsiriX Lite" ] ];
}

// Skalare Schluessel je Gruppe (Regel: nur gefuellt, wenn SekhVet den Schluessel noch nicht selbst gesetzt hat)
static NSArray* sekhmetDisplayKeys( void)
{
    return @[ @"ANNOTATIONS", @"DEFAULTLEFTTOOL", @"CLUTBARS", @"AUTOTILING", @"AUTOHIDEMATRIX", @"NOINTERPOLATION", @"SOFTWAREINTERPOLATION",
              @"USEALWAYSTOOLBARPANEL2", @"MAPPERMODEVR", @"VRDefaultViewSize", @"syncPreviewList", @"nextSeriesToAllViewers", @"SeriesListVisible",
              @"ROIColorR", @"ROIColorG", @"ROIColorB", @"ROIOpacity", @"ROIThickness", @"ROITextColorR", @"ROITextColorG", @"ROITextColorB",
              @"ROITextThickness", @"ROIRegionColorR", @"ROIRegionColorG", @"ROIRegionColorB", @"ROIRegionOpacity", @"ROIRegionThickness",
              @"ROIArrowThickness", @"ROITEXTNAMEONLY", @"ROITEXTIFSELECTED", @"ROIDrawPlainEdge", @"ROIColorRotation" ];
}
static NSArray* sekhmetQueryKeys( void)
{
    return @[ @"savedDICOMQuerySettings", @"savedAutoDICOMQuerySettingsArray", @"SavedQueryArray", @"SavedQueryArrayAuto", @"QRLastDateFilterValue",
              @"autoRefreshQueryResults", @"autoRefreshQueryResultsAutoQR", @"NewQueryControllerTableColumns", @"NewQueryControllerTableColumnsAutoQR",
              @"QueryControllerTableColumnsSortDescriptor", @"QueryControllerTableColumnsSortDescriptorAutoQR", @"searchType", @"autoRetrieving" ];
}
static NSArray* sekhmetPresetKeys( void) { return @[ @"WLWW3", @"OPACITY", @"CLUTDefinition", @"CONVOLUTIONKERNELS" ]; }

@implementation SekhmetSettingsImport

static SekhmetSettingsImport *sekhmetSettingsImportShared = nil;

+ (SekhmetSettingsImport*) shared
{
    if( sekhmetSettingsImportShared == nil) sekhmetSettingsImportShared = [[SekhmetSettingsImport alloc] init];
    return sekhmetSettingsImportShared;
}

#pragma mark Quellen

+ (NSString*) ownDomain { return [[NSBundle mainBundle] bundleIdentifier]; }

+ (NSArray*) foundSources
{
    NSMutableArray *out = [NSMutableArray array];
    NSString *own = [self ownDomain];
    for( NSArray *paar in sekhmetSourceDomains())
    {
        NSString *domain = [paar objectAtIndex: 0];
        if( [domain isEqualToString: own]) continue;
        NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName: domain];
        if( prefs.count == 0) continue;
        NSString *plist = [[NSHomeDirectory() stringByAppendingPathComponent: @"Library/Preferences"] stringByAppendingPathComponent: [domain stringByAppendingPathExtension: @"plist"]];
        NSDate *mod = [[[NSFileManager defaultManager] attributesOfItemAtPath: plist error: nil] fileModificationDate] ?: [NSDate distantPast];
        [out addObject: [NSDictionary dictionaryWithObjectsAndKeys: domain, @"domain", [paar objectAtIndex: 1], @"name", mod, @"modified", prefs, @"prefs", nil]];
    }
    [out sortUsingComparator: ^NSComparisonResult( id a, id b) { return [[b objectForKey: @"modified"] compare: [a objectForKey: @"modified"]]; }];
    return out;
}

+ (BOOL) isLocalAddress:(NSString*) a
{
    if( ![a isKindOfClass: [NSString class]]) return YES;
    a = [[a lowercaseString] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    return a.length == 0 || [a isEqualToString: @"127.0.0.1"] || [a isEqualToString: @"localhost"] || [a isEqualToString: @"::1"];
}

+ (BOOL) hasOwnNodes
{
    NSDictionary *own = [[NSUserDefaults standardUserDefaults] persistentDomainForName: [self ownDomain]];
    for( id s in [own objectForKey: @"SERVERS"])
        if( [s isKindOfClass: [NSDictionary class]] && ![self isLocalAddress: [s objectForKey: @"Address"]]) return YES;
    return NO;
}

+ (void) offerAtStartIfNeeded
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [d boolForKey: SekhmetSettingsImportOfferedKey]) return;
    [d setBool: YES forKey: SekhmetSettingsImportOfferedKey];
    if( [self hasOwnNodes]) return;
    NSArray *q = [self foundSources];
    if( q.count == 0) return;
    [[self shared] show: nil];
    [[self shared] setStatus: [NSString stringWithFormat: NSLocalizedString( @"SekhVet found %@ settings on this Mac. Nothing is taken over until you click “Import”; your Horos / OsiriX settings are only read.", nil),
                               [[q valueForKey: @"name"] componentsJoinedByString: @" / "]]];
}

+ (NSString*) suggestedAETitleFrom:(NSString*) aet
{
    NSString *base = [[aet stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] uppercaseString];
    if( base.length == 0) base = @"SEKHVET";
    if( base.length > 14) base = [base substringToIndex: 14];
    return [base stringByAppendingString: @"SV"];
}

// Listener-Werte, wie die Quelle sie wirklich benutzt: ohne AETITLE nimmt Horos den Rechnernamen (DefaultsOsiriX),
// ohne AEPORT den Standardport der jeweiligen App (Horos 11112, OsiriX 4096). Build 197: vorher blieb bei fehlendem
// AETITLE im Modus "Same as source" der alte SekhVet-Titel stehen.
+ (NSString*) sourceAETitle:(NSDictionary*) prefs
{
    NSString *aet = [prefs objectForKey: @"AETITLE"];
    if( [aet isKindOfClass: [NSString class]] && aet.length) return aet.length > 16 ? [aet substringToIndex: 16] : aet;
    char s[_POSIX_HOST_NAME_MAX + 1]; gethostname( s, _POSIX_HOST_NAME_MAX);
    NSString *host = [[[NSString stringWithUTF8String: s] componentsSeparatedByString: @"."] firstObject];
    if( host.length > 16) host = [host substringToIndex: 16];
    return host.length ? host : @"HOROS";
}

+ (int) sourcePort:(NSDictionary*) prefs domain:(NSString*) domain
{
    int p = [[prefs objectForKey: @"AEPORT"] intValue];
    if( p > 0) return p;
    return [domain rangeOfString: @"horos"].location != NSNotFound ? 11112 : 4096;
}

// SekhVet beenden und neu oeffnen: der laufende DICOM-Listener (DCMTKQueryRetrieveSCP) laesst sich nicht im Betrieb auf
// einen anderen Port umhaengen; Horos verlangt dafuer ebenfalls einen Neustart ("Restart to apply these changes").
+ (void) relaunch
{
    NSString *cmd = [NSString stringWithFormat: @"while kill -0 %d 2>/dev/null; do sleep 0.3; done; open \"%@\"", getpid(), [[NSBundle mainBundle] bundlePath]];
    [NSTask launchedTaskWithLaunchPath: @"/bin/sh" arguments: @[ @"-c", cmd ]];
    [NSApp terminate: nil];
}

#pragma mark Uebernahme

+ (NSString*) backupCurrentSettings
{
    NSString *dir = [[NSSearchPathForDirectoriesInDomains( NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject] stringByAppendingPathComponent: @"SekhVet"];
    [[NSFileManager defaultManager] createDirectoryAtPath: dir withIntermediateDirectories: YES attributes: nil error: nil];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateFormat: @"yyyyMMdd-HHmmss"];
    NSString *path = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"prefs-vor-import-%@.plist", [f stringFromDate: [NSDate date]]]];
    NSDictionary *own = [[NSUserDefaults standardUserDefaults] persistentDomainForName: [self ownDomain]] ?: [NSDictionary dictionary];
    return [own writeToFile: path atomically: YES] ? path : nil;
}

+ (NSString*) nodeIdentity:(NSDictionary*) n
{
    return [NSString stringWithFormat: @"%@|%@|%d", [[n objectForKey: @"AETitle"] uppercaseString], [n objectForKey: @"Address"], [[n objectForKey: @"Port"] intValue]];
}

// Liste von Dictionaries (SERVERS, OSIRIXSERVERS) mischen: gleiche Identitaet = Duplikat (uebersprungen, bei overwrite ersetzt). Liefert die Zahl der Aenderungen.
+ (int) mergeList:(NSArray*) incoming intoKey:(NSString*) key identity:(NSString* (^)(NSDictionary*)) ident overwrite:(BOOL) overwrite
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSMutableArray *list = [NSMutableArray arrayWithArray: [d arrayForKey: key] ?: [NSArray array]];
    int changed = 0;
    for( id n in incoming)
    {
        if( ![n isKindOfClass: [NSDictionary class]]) continue;
        NSString *id1 = ident( n);
        NSUInteger found = NSNotFound;
        for( NSUInteger i = 0; i < list.count; i++)
            if( [[list objectAtIndex: i] isKindOfClass: [NSDictionary class]] && [ident( [list objectAtIndex: i]) isEqualToString: id1]) { found = i; break; }
        if( found == NSNotFound) { [list addObject: n]; changed++; }
        else if( overwrite && ![[list objectAtIndex: found] isEqualToDictionary: n]) { [list replaceObjectAtIndex: found withObject: n]; changed++; }
    }
    if( changed) [d setObject: list forKey: key];
    return changed;
}

// Dictionary (Name -> Wert) mischen: fehlt der Schluessel in SekhVets eigenen Prefs ganz, kommt die Quelle komplett; sonst Name fuer Name.
+ (int) mergeDictionaryKey:(NSString*) key from:(NSDictionary*) src own:(NSDictionary*) own overwrite:(BOOL) overwrite
{
    NSDictionary *in = [src objectForKey: key];
    if( ![in isKindOfClass: [NSDictionary class]] || in.count == 0) return 0;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [own objectForKey: key] == nil && !overwrite)
    {
        // noch nie selbst gesetzt: Quelle ueber die Werksvorgabe legen, Werksnamen bleiben erhalten
        NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary: [d dictionaryForKey: key] ?: [NSDictionary dictionary]];
        int changed = 0;
        for( id k in in) if( [m objectForKey: k] == nil) { [m setObject: [in objectForKey: k] forKey: k]; changed++; }
        if( changed) [d setObject: m forKey: key];
        return changed;
    }
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary: [d dictionaryForKey: key] ?: [NSDictionary dictionary]];
    int changed = 0;
    for( id k in in)
    {
        id have = [m objectForKey: k];
        if( have == nil || (overwrite && ![have isEqual: [in objectForKey: k]])) { [m setObject: [in objectForKey: k] forKey: k]; changed++; }
    }
    if( changed) [d setObject: m forKey: key];
    return changed;
}

// HOTKEYS: Horos speichert Taste -> Funktionsnummer. Gemischt wird je Funktion: eine Funktion, die in SekhVet schon eine Taste hat, behaelt sie.
+ (int) mergeHotkeysFrom:(NSDictionary*) src own:(NSDictionary*) own overwrite:(BOOL) overwrite
{
    NSDictionary *in = [src objectForKey: @"HOTKEYS"];
    if( ![in isKindOfClass: [NSDictionary class]] || in.count == 0) return 0;
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    if( [own objectForKey: @"HOTKEYS"] == nil) { [d setObject: in forKey: @"HOTKEYS"]; return (int) in.count; }   // noch nie angepasst: komplett
    NSMutableDictionary *m = [NSMutableDictionary dictionaryWithDictionary: [d dictionaryForKey: @"HOTKEYS"] ?: [NSDictionary dictionary]];
    NSMutableDictionary *keyForAction = [NSMutableDictionary dictionary];   // Funktionsnummer -> Taste (eigener Stand)
    for( id k in m) [keyForAction setObject: k forKey: [m objectForKey: k]];
    int changed = 0;
    for( id key in in)
    {
        id action = [in objectForKey: key];
        id ownKey = [keyForAction objectForKey: action];
        if( ownKey != nil && !overwrite) continue;                       // Funktion hat schon eine Taste
        if( ownKey != nil && [ownKey isEqual: key]) continue;            // gleich
        if( [m objectForKey: key] != nil && !overwrite) continue;        // Taste in SekhVet anders belegt
        if( ownKey) [m removeObjectForKey: ownKey];
        [m setObject: action forKey: key];
        [keyForAction setObject: key forKey: action];
        changed++;
    }
    if( changed) [d setObject: m forKey: @"HOTKEYS"];
    return changed;
}

+ (int) takeScalars:(NSArray*) keys from:(NSDictionary*) src own:(NSDictionary*) own overwrite:(BOOL) overwrite
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    int changed = 0;
    for( NSString *k in keys)
    {
        id v = [src objectForKey: k];
        if( v == nil) continue;
        if( [own objectForKey: k] != nil && !overwrite) continue;
        if( [[own objectForKey: k] isEqual: v]) continue;
        [d setObject: v forKey: k];
        changed++;
    }
    return changed;
}

+ (NSDictionary*) importFrom:(NSDictionary*) prefs domain:(NSString*) domain groups:(NSSet*) groups nodes:(NSArray*) selectedNodes listenerMode:(int) mode aeTitle:(NSString*) aet port:(NSString*) port overwrite:(BOOL) overwrite
{
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSString *backup = [self backupCurrentSettings];
    [result setObject: backup ?: @"" forKey: @"backup"];
    if( backup == nil) { [result setObject: @YES forKey: @"backupFailed"]; return result; }   // ohne Sicherung keine Uebernahme
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSDictionary *own = [d persistentDomainForName: [self ownDomain]] ?: [NSDictionary dictionary];
    BOOL listenerRestart = NO;

    if( [groups containsObject: kGroupNodes])
    {
        int n = [self mergeList: selectedNodes intoKey: @"SERVERS" identity: ^NSString*( NSDictionary *x) { return [self nodeIdentity: x]; } overwrite: overwrite];
        n += [self mergeList: [prefs objectForKey: @"OSIRIXSERVERS"] intoKey: @"OSIRIXSERVERS" identity: ^NSString*( NSDictionary *x) {
            return [NSString stringWithFormat: @"%@|%d", [x objectForKey: @"Address"], [[x objectForKey: @"Port"] intValue]]; } overwrite: overwrite];
        [result setObject: [NSNumber numberWithInt: n] forKey: kGroupNodes];
    }
    if( [groups containsObject: kGroupListener] && mode != SekhmetListenerKeep)
    {
        int n = 0;
        NSString *newAET = mode == SekhmetListenerNew ? aet : [self sourceAETitle: prefs];
        NSString *newPort = mode == SekhmetListenerNew ? port : [NSString stringWithFormat: @"%d", [self sourcePort: prefs domain: domain]];
        if( newAET.length) { [d setObject: newAET forKey: @"AETITLE"]; n++; }
        if( [newPort intValue] > 0) { [d setObject: newPort forKey: @"AEPORT"]; n++; }
        [d setBool: YES forKey: @"STORESCP"]; n++;
        listenerRestart = YES;
        [result setObject: [NSNumber numberWithInt: n] forKey: kGroupListener];
    }
    if( [groups containsObject: kGroupHotkeys])
        [result setObject: [NSNumber numberWithInt: [self mergeHotkeysFrom: prefs own: own overwrite: overwrite]] forKey: kGroupHotkeys];
    if( [groups containsObject: kGroupPresets])
    {
        int n = 0;
        for( NSString *k in sekhmetPresetKeys()) n += [self mergeDictionaryKey: k from: prefs own: own overwrite: overwrite];
        [result setObject: [NSNumber numberWithInt: n] forKey: kGroupPresets];
    }
    if( [groups containsObject: kGroupDisplay])
    {
        int n = [self takeScalars: sekhmetDisplayKeys() from: prefs own: own overwrite: overwrite];
        n += [self mergeDictionaryKey: @"HANGINGPROTOCOLS" from: prefs own: own overwrite: overwrite];
        [result setObject: [NSNumber numberWithInt: n] forKey: kGroupDisplay];
    }
    if( [groups containsObject: kGroupQuery])
        [result setObject: [NSNumber numberWithInt: [self takeScalars: sekhmetQueryKeys() from: prefs own: own overwrite: overwrite]] forKey: kGroupQuery];
    [d synchronize];
    [result setObject: [NSNumber numberWithBool: listenerRestart] forKey: @"listenerRestart"];   // Build 197: heisst "Neustart noetig" -- der Listener wird nicht mehr im Betrieb umgehaengt (wirkungslos, alter Port blieb offen)
    NSLog( @"SekhVet settings import: %@", result);
    return result;
}

#pragma mark Echo

// TCP-Verbindung mit 3 s Frist; erst wenn der Port antwortet, folgt der echte C-ECHO (dessen eigene Frist ist laenger).
+ (BOOL) tcpReachable:(NSString*) host port:(int) port seconds:(int) seconds
{
    struct addrinfo hints, *res = NULL;
    memset( &hints, 0, sizeof( hints));
    hints.ai_family = AF_UNSPEC; hints.ai_socktype = SOCK_STREAM;
    char portStr[16]; snprintf( portStr, sizeof( portStr), "%d", port);
    if( getaddrinfo( [host UTF8String], portStr, &hints, &res) != 0 || res == NULL) return NO;
    BOOL ok = NO;
    for( struct addrinfo *a = res; a && !ok; a = a->ai_next)
    {
        int s = socket( a->ai_family, a->ai_socktype, a->ai_protocol);
        if( s < 0) continue;
        fcntl( s, F_SETFL, fcntl( s, F_GETFL, 0) | O_NONBLOCK);
        int r = connect( s, a->ai_addr, a->ai_addrlen);
        if( r == 0) ok = YES;
        else if( errno == EINPROGRESS)
        {
            fd_set w; FD_ZERO( &w); FD_SET( s, &w);
            struct timeval tv = { seconds, 0 };
            if( select( s + 1, NULL, &w, NULL, &tv) > 0)
            {
                int err = 0; socklen_t len = sizeof( err);
                if( getsockopt( s, SOL_SOCKET, SO_ERROR, &err, &len) == 0 && err == 0) ok = YES;
            }
        }
        close( s);
    }
    freeaddrinfo( res);
    return ok;
}

- (void) checkNodes
{
    int generation = ++echoGeneration;
    for( NSMutableDictionary *entry in nodes)
    {
        [entry setObject: NSLocalizedString( @"checking…", nil) forKey: @"echo"];
        NSDictionary *node = [entry objectForKey: @"node"];
        dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            @autoreleasepool {
                NSString *text;
                if( ![SekhmetSettingsImport tcpReachable: [node objectForKey: @"Address"] port: [[node objectForKey: @"Port"] intValue] seconds: 3])
                    text = NSLocalizedString( @"no answer", nil);
                else
                {
                    BOOL ok = NO;
                    @try { ok = [QueryController echoServer: node]; } @catch( NSException *e) { ok = NO; }
                    text = ok ? NSLocalizedString( @"echo OK", nil) : NSLocalizedString( @"port open, echo rejected", nil);
                }
                dispatch_async( dispatch_get_main_queue(), ^{
                    if( generation != echoGeneration) return;
                    [entry setObject: text forKey: @"echo"];
                    [nodeTable reloadData];
                });
            }
        });
    }
    [nodeTable reloadData];
}

#pragma mark Fenster

- (NSButton*) checkbox:(NSString*) title frame:(NSRect) r
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setButtonType: NSButtonTypeSwitch];
    [b setTitle: title];
    [b setState: NSControlStateValueOn];
    return b;
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r
{
    NSTextField *t = [NSTextField labelWithString: text];
    [t setFrame: r];
    return t;
}

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 820, 640)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: YES] autorelease];
    [w setTitle: NSLocalizedString( @"Import Settings from Horos / OsiriX", nil)];
    self = [super initWithWindow: w];
    if( self == nil) return nil;
    sources = [[NSMutableArray alloc] init];
    nodes = [[NSMutableArray alloc] init];
    groupButtons = [[NSMutableDictionary alloc] init];
    NSView *v = [w contentView];
    float y = 600;

    NSTextField *info = [NSTextField wrappingLabelWithString: NSLocalizedString( @"Takes DICOM nodes, listener, hotkeys, presets, display and query settings from a Horos or OsiriX installation on this Mac. Rule: settings you already changed in SekhVet stay as they are; only what is missing is added. Horos / OsiriX and their image databases are only read, never changed.", nil)];
    [info setFrame: NSMakeRect( 20, y - 52, 780, 52)];
    [v addSubview: info];
    y -= 86;

    [v addSubview: [self label: NSLocalizedString( @"Source:", nil) frame: NSMakeRect( 20, y + 3, 60, 20)]];
    sourcePopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 80, y - 1, 400, 26) pullsDown: NO] autorelease];
    [sourcePopup setTarget: self]; [sourcePopup setAction: @selector(sourceChanged:)];
    [v addSubview: sourcePopup];
    y -= 34;

    [v addSubview: [self label: NSLocalizedString( @"Take over:", nil) frame: NSMakeRect( 20, y, 100, 20)]];
    NSArray *groups = @[ @[ kGroupNodes, NSLocalizedString( @"DICOM nodes (list below)", nil) ], @[ kGroupListener, NSLocalizedString( @"Listener (AE title, port — see below)", nil) ],
                         @[ kGroupHotkeys, NSLocalizedString( @"Hotkeys", nil) ], @[ kGroupPresets, NSLocalizedString( @"Window / CLUT / opacity presets", nil) ],
                         @[ kGroupDisplay, NSLocalizedString( @"Display: ROI colours, annotations, hanging protocols, default tool", nil) ], @[ kGroupQuery, NSLocalizedString( @"Query / retrieve settings", nil) ] ];
    for( NSUInteger i = 0; i < groups.count; i++)
    {
        NSButton *b = [self checkbox: [[groups objectAtIndex: i] objectAtIndex: 1] frame: NSMakeRect( 120 + (i % 2) * 340, y - (i / 2) * 24, 340, 20)];
        [b setTarget: self]; [b setAction: @selector(groupChanged:)];
        [groupButtons setObject: b forKey: [[groups objectAtIndex: i] objectAtIndex: 0]];
        [v addSubview: b];
    }
    y -= 3 * 24 + 8;

    [v addSubview: [self label: NSLocalizedString( @"DICOM nodes found in the source (unchecked ones are not taken over):", nil) frame: NSMakeRect( 20, y, 780, 20)]];
    y -= 150;
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, y, 780, 146)] autorelease];
    [sv setHasVerticalScroller: YES]; [sv setBorderType: NSBezelBorder];
    nodeTable = [[[NSTableView alloc] initWithFrame: [sv bounds]] autorelease];
    NSArray *spalten = @[ @[ @"use", @"", @30 ], @[ @"AETitle", NSLocalizedString( @"AE title", nil), @120 ], @[ @"Address", NSLocalizedString( @"Address", nil), @150 ],
                          @[ @"Port", NSLocalizedString( @"Port", nil), @60 ], @[ @"Description", NSLocalizedString( @"Description", nil), @220 ], @[ @"echo", NSLocalizedString( @"Check (C-ECHO)", nil), @170 ] ];
    for( NSArray *s in spalten)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [s objectAtIndex: 0]] autorelease];
        [[c headerCell] setStringValue: [s objectAtIndex: 1]];
        [c setWidth: [[s objectAtIndex: 2] floatValue]];
        if( [[s objectAtIndex: 0] isEqualToString: @"use"])
        {
            NSButtonCell *cell = [[[NSButtonCell alloc] init] autorelease];
            [cell setButtonType: NSButtonTypeSwitch]; [cell setTitle: @""];
            [c setDataCell: cell]; [c setEditable: YES];
        }
        else [c setEditable: NO];
        [nodeTable addTableColumn: c];
    }
    [nodeTable setDataSource: self]; [nodeTable setDelegate: self];
    [nodeTable setUsesAlternatingRowBackgroundColors: YES];
    [sv setDocumentView: nodeTable];
    [v addSubview: sv];
    y -= 30;

    [v addSubview: [self label: NSLocalizedString( @"Listener:", nil) frame: NSMakeRect( 20, y, 100, 20)]];
    listenerNewButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 120, y, 330, 20)] autorelease];
    [listenerNewButton setButtonType: NSButtonTypeRadio]; [listenerNewButton setTitle: NSLocalizedString( @"New AE title and port (run beside Horos / OsiriX)", nil)];
    [listenerNewButton setTarget: self]; [listenerNewButton setAction: @selector(listenerModeChanged:)];
    [v addSubview: listenerNewButton];
    listenerSameButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 460, y, 340, 20)] autorelease];
    [listenerSameButton setButtonType: NSButtonTypeRadio]; [listenerSameButton setTitle: NSLocalizedString( @"Same as the source (never run both at once)", nil)];
    [listenerSameButton setTarget: self]; [listenerSameButton setAction: @selector(listenerModeChanged:)];
    [v addSubview: listenerSameButton];
    y -= 28;
    [v addSubview: [self label: NSLocalizedString( @"AE title:", nil) frame: NSMakeRect( 120, y + 2, 60, 20)]];
    aeField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 185, y, 150, 22)] autorelease];
    [v addSubview: aeField];
    [v addSubview: [self label: NSLocalizedString( @"Port:", nil) frame: NSMakeRect( 350, y + 2, 40, 20)]];
    portField = [[[NSTextField alloc] initWithFrame: NSMakeRect( 395, y, 70, 22)] autorelease];
    [v addSubview: portField];
    y -= 44;
    listenerHint = [NSTextField wrappingLabelWithString: @""];
    [listenerHint setFrame: NSMakeRect( 120, y, 680, 40)];
    [listenerHint setTextColor: [NSColor secondaryLabelColor]];
    [v addSubview: listenerHint];
    y -= 28;

    overwriteButton = [self checkbox: NSLocalizedString( @"Overwrite existing SekhVet settings with the source (default: only add what is missing)", nil) frame: NSMakeRect( 20, y, 780, 20)];
    [overwriteButton setState: NSControlStateValueOff];
    [v addSubview: overwriteButton];
    y -= 34;

    statusField = [NSTextField wrappingLabelWithString: @""];
    [statusField setFrame: NSMakeRect( 20, 50, 780, 34)];
    [statusField setTextColor: [NSColor secondaryLabelColor]];
    [v addSubview: statusField];

    importButton = [NSButton buttonWithTitle: NSLocalizedString( @"Import", nil) target: self action: @selector(importNow:)];
    [importButton setFrame: NSMakeRect( 600, 12, 100, 28)];
    [importButton setKeyEquivalent: @"\r"];
    [v addSubview: importButton];
    NSButton *zu = [NSButton buttonWithTitle: NSLocalizedString( @"Cancel", nil) target: w action: @selector(performClose:)];
    [zu setFrame: NSMakeRect( 706, 12, 94, 28)];
    [v addSubview: zu];
    [w center];
    return self;
}

- (void) dealloc
{
    [sources release]; [nodes release]; [groupButtons release];
    [super dealloc];
}

- (void) setStatus:(NSString*) s { [statusField setStringValue: s ?: @""]; }

- (NSDictionary*) currentSource
{
    NSInteger i = [sourcePopup indexOfSelectedItem];
    return (i >= 0 && i < (NSInteger) sources.count) ? [sources objectAtIndex: i] : nil;
}

- (void) reload
{
    [sources setArray: [SekhmetSettingsImport foundSources]];
    [sourcePopup removeAllItems];
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateStyle: NSDateFormatterMediumStyle]; [f setTimeStyle: NSDateFormatterShortStyle];
    for( NSDictionary *s in sources)
        [sourcePopup addItemWithTitle: [NSString stringWithFormat: @"%@ (%@, %@)", [s objectForKey: @"name"], [s objectForKey: @"domain"], [f stringFromDate: [s objectForKey: @"modified"]]]];
    [importButton setEnabled: sources.count > 0];
    if( sources.count == 0) [self setStatus: NSLocalizedString( @"Nothing to take over: no Horos or OsiriX settings were found on this Mac.", nil)];
    [self sourceChanged: nil];
}

- (IBAction) sourceChanged:(id) sender
{
    NSDictionary *src = [[self currentSource] objectForKey: @"prefs"];
    [nodes removeAllObjects];
    for( id n in [src objectForKey: @"SERVERS"])
        if( [n isKindOfClass: [NSDictionary class]])
            [nodes addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: n, @"node", @YES, @"use", @"", @"echo", nil]];
    NSString *srcAET = [SekhmetSettingsImport sourceAETitle: src];
    int srcPort = [SekhmetSettingsImport sourcePort: src domain: [[self currentSource] objectForKey: @"domain"]];
    [aeField setStringValue: [SekhmetSettingsImport suggestedAETitleFrom: srcAET]];
    [portField setStringValue: [NSString stringWithFormat: @"%d", srcPort + 1]];
    [listenerNewButton setState: NSControlStateValueOn]; [listenerSameButton setState: NSControlStateValueOff];
    [self listenerModeChanged: nil];
    if( src) [self checkNodes]; else [nodeTable reloadData];
}

- (IBAction) groupChanged:(id) sender
{
    BOOL listener = [[groupButtons objectForKey: kGroupListener] state] == NSControlStateValueOn;
    [listenerNewButton setEnabled: listener]; [listenerSameButton setEnabled: listener];
    [self listenerModeChanged: nil];
}

- (IBAction) listenerModeChanged:(id) sender
{
    if( sender == listenerNewButton) [listenerSameButton setState: NSControlStateValueOff];
    if( sender == listenerSameButton) [listenerNewButton setState: NSControlStateValueOff];
    BOOL listener = [[groupButtons objectForKey: kGroupListener] state] == NSControlStateValueOn;
    BOOL neu = [listenerNewButton state] == NSControlStateValueOn;
    [aeField setEnabled: listener && neu]; [portField setEnabled: listener && neu];
    NSDictionary *src = [[self currentSource] objectForKey: @"prefs"];
    if( !listener) [listenerHint setStringValue: NSLocalizedString( @"Listener settings stay as they are in SekhVet.", nil)];
    else if( neu) [listenerHint setStringValue: [NSString stringWithFormat: NSLocalizedString( @"SekhVet listens on its own AE title and port, so Horos / OsiriX can keep running. Your PACS does not know this new AE title yet: register “%@”, this Mac and port %@ there as a second destination, or retrieve (C-MOVE) will fail.", nil), [aeField stringValue], [portField stringValue]]];
    else [listenerHint setStringValue: [NSString stringWithFormat: NSLocalizedString( @"SekhVet takes AE title “%@” and port %@ from the source. The PACS needs no change, but Horos / OsiriX and SekhVet must never run at the same time: the second one cannot open the port.", nil), [SekhmetSettingsImport sourceAETitle: src], [NSString stringWithFormat: @"%d", [SekhmetSettingsImport sourcePort: src domain: [[self currentSource] objectForKey: @"domain"]]]]];
}

- (IBAction) show:(id) sender
{
    [self reload];
    [self showWindow: self];
    [[self window] makeKeyAndOrderFront: self];
}

- (IBAction) importNow:(id) sender
{
    NSDictionary *source = [self currentSource];
    if( source == nil) return;
    NSMutableSet *groups = [NSMutableSet set];
    for( NSString *k in groupButtons) if( [[groupButtons objectForKey: k] state] == NSControlStateValueOn) [groups addObject: k];
    NSMutableArray *selected = [NSMutableArray array];
    for( NSDictionary *e in nodes) if( [[e objectForKey: @"use"] boolValue]) [selected addObject: [e objectForKey: @"node"]];
    int mode = SekhmetListenerKeep;
    if( [groups containsObject: kGroupListener]) mode = [listenerNewButton state] == NSControlStateValueOn ? SekhmetListenerNew : SekhmetListenerSame;
    NSString *aet = [[aeField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *port = [[portField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    if( mode == SekhmetListenerNew && (aet.length == 0 || aet.length > 16 || [port intValue] < 1 || [port intValue] > 65535))
    {
        [self setStatus: NSLocalizedString( @"New listener: the AE title needs 1–16 characters and the port a number between 1 and 65535.", nil)];
        return;
    }
    if( mode == SekhmetListenerNew && [port intValue] == [[[source objectForKey: @"prefs"] objectForKey: @"AEPORT"] intValue])
    {
        [self setStatus: NSLocalizedString( @"New listener: the port is the same as in the source — choose another one, or pick “Same as the source”.", nil)];
        return;
    }
    NSDictionary *r = [SekhmetSettingsImport importFrom: [source objectForKey: @"prefs"] domain: [source objectForKey: @"domain"] groups: groups nodes: selected listenerMode: mode aeTitle: aet port: port overwrite: [overwriteButton state] == NSControlStateValueOn];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    if( [[r objectForKey: @"backupFailed"] boolValue])
    {
        [a setAlertStyle: NSAlertStyleWarning];
        [a setMessageText: NSLocalizedString( @"Nothing was imported", nil)];
        [a setInformativeText: NSLocalizedString( @"The backup of the current SekhVet settings could not be written to ~/Library/Application Support/SekhVet. Without a backup nothing is changed.", nil)];
        [a runModal];
        return;
    }
    NSMutableString *t = [NSMutableString string];
    NSArray *labels = @[ @[ kGroupNodes, NSLocalizedString( @"DICOM nodes", nil) ], @[ kGroupListener, NSLocalizedString( @"listener values", nil) ], @[ kGroupHotkeys, NSLocalizedString( @"hotkeys", nil) ],
                         @[ kGroupPresets, NSLocalizedString( @"presets", nil) ], @[ kGroupDisplay, NSLocalizedString( @"display settings", nil) ], @[ kGroupQuery, NSLocalizedString( @"query settings", nil) ] ];
    for( NSArray *l in labels)
        if( [r objectForKey: [l objectAtIndex: 0]]) [t appendFormat: @"%@ %@ · ", [r objectForKey: [l objectAtIndex: 0]], [l objectAtIndex: 1]];
    if( t.length) [t deleteCharactersInRange: NSMakeRange( t.length - 3, 3)];
    if( t.length == 0) [t setString: NSLocalizedString( @"nothing — everything was already set in SekhVet", nil)];
    [t appendFormat: @"\n\n%@\n%@", NSLocalizedString( @"Backup of the settings before the import:", nil), [r objectForKey: @"backup"]];
    if( mode == SekhmetListenerNew) [t appendFormat: @"\n\n%@", [NSString stringWithFormat: NSLocalizedString( @"The listener now uses AE title “%@”, port %@. Register this as a new destination at your PACS before you retrieve.", nil), aet, port]];
    if( mode == SekhmetListenerSame) [t appendFormat: @"\n\n%@", [NSString stringWithFormat: NSLocalizedString( @"The listener uses AE title “%@” and port %@, the same as the source: do not run Horos / OsiriX and SekhVet at the same time.", nil), [[NSUserDefaults standardUserDefaults] stringForKey: @"AETITLE"], [[NSUserDefaults standardUserDefaults] stringForKey: @"AEPORT"]]];
    BOOL restart = [[r objectForKey: @"listenerRestart"] boolValue];
    if( restart) [t appendFormat: @"\n\n%@", NSLocalizedString( @"The new listener values take effect after SekhVet is restarted. Quit now? SekhVet opens again by itself.", nil)];
    [a setMessageText: NSLocalizedString( @"Settings imported", nil)];
    [a setInformativeText: t];
    if( restart) { [a addButtonWithTitle: NSLocalizedString( @"Quit and reopen SekhVet", nil)]; [a addButtonWithTitle: NSLocalizedString( @"Later", nil)]; }
    NSModalResponse antwort = [a runModal];
    [[self window] performClose: self];
    if( restart && antwort == NSAlertFirstButtonReturn) [SekhmetSettingsImport relaunch];
}

#pragma mark Tabelle

- (NSInteger) numberOfRowsInTableView:(NSTableView*) t { return nodes.count; }

- (id) tableView:(NSTableView*) t objectValueForTableColumn:(NSTableColumn*) c row:(NSInteger) row
{
    NSDictionary *e = [nodes objectAtIndex: row];
    NSString *ident = [c identifier];
    if( [ident isEqualToString: @"use"]) return [e objectForKey: @"use"];
    if( [ident isEqualToString: @"echo"]) return [e objectForKey: @"echo"];
    id v = [[e objectForKey: @"node"] objectForKey: ident];
    return v ? [v description] : @"";
}

- (void) tableView:(NSTableView*) t setObjectValue:(id) v forTableColumn:(NSTableColumn*) c row:(NSInteger) row
{
    if( [[c identifier] isEqualToString: @"use"]) [[nodes objectAtIndex: row] setObject: [NSNumber numberWithBool: [v boolValue]] forKey: @"use"];
}

#if SEKHVET_TESTHAKEN
// Headless-Test: SEKHVET_SETTINGS_IMPORT_TEST=<domain>:<listenerMode 0|1|2>[:<port>] -- alle Gruppen, alle Knoten, ohne Overwrite;
// Ergebnis nach /tmp/sekhvet-settings-import.json.
+ (void) debugImportFromEnvironment
{
    const char *spec = sekhvetTesthaken( "SEKHVET_SETTINGS_IMPORT_TEST");
    if( spec == NULL) return;
    NSArray *teile = [[NSString stringWithUTF8String: spec] componentsSeparatedByString: @":"];
    NSString *domain = [teile firstObject];
    int mode = teile.count > 1 ? [[teile objectAtIndex: 1] intValue] : SekhmetListenerNew;
    NSString *port = teile.count > 2 ? [teile objectAtIndex: 2] : @"4007";
    NSDictionary *prefs = [[NSUserDefaults standardUserDefaults] persistentDomainForName: domain];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    [out setObject: domain forKey: @"domain"];
    [out setObject: [NSNumber numberWithBool: prefs != nil] forKey: @"sourceFound"];
    [out setObject: [NSNumber numberWithBool: [self hasOwnNodes]] forKey: @"hadOwnNodes"];
    [out setObject: [[self foundSources] valueForKey: @"domain"] forKey: @"foundSources"];
    if( prefs)
    {
        NSMutableArray *sel = [NSMutableArray array];
        for( id n in [prefs objectForKey: @"SERVERS"]) if( [n isKindOfClass: [NSDictionary class]]) [sel addObject: n];
        NSDictionary *r = [self importFrom: prefs domain: domain groups: [NSSet setWithArray: @[ kGroupNodes, kGroupListener, kGroupHotkeys, kGroupPresets, kGroupDisplay, kGroupQuery ]]
                                     nodes: sel listenerMode: mode aeTitle: [self suggestedAETitleFrom: [prefs objectForKey: @"AETITLE"] ?: @"HOROS"] port: port overwrite: NO];
        [out setObject: r forKey: @"result"];
        NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
        [out setObject: [d stringForKey: @"AETITLE"] ?: @"" forKey: @"AETITLE"];
        [out setObject: [d stringForKey: @"AEPORT"] ?: @"" forKey: @"AEPORT"];
        [out setObject: [NSNumber numberWithInteger: [[d arrayForKey: @"SERVERS"] count]] forKey: @"serversAfter"];
        [out setObject: [NSNumber numberWithInteger: [[d dictionaryForKey: @"HOTKEYS"] count]] forKey: @"hotkeysAfter"];
    }
    NSData *json = [NSJSONSerialization dataWithJSONObject: out options: NSJSONWritingPrettyPrinted error: NULL];
    [json writeToFile: @"/tmp/sekhvet-settings-import.json" atomically: YES];
    NSLog( @"SekhVet settings import test: %@", out);
}
#endif

@end
