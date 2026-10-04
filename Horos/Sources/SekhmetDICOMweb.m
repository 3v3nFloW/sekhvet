/*=========================================================================
 Sekhmet — DICOMweb. Siehe Header.
 ============================================================================*/

#import "SekhmetDICOMweb.h"
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#import "SekhmetDisplayPanel.h"
#import "DicomDatabase.h"
#import "BrowserController.h"
#import "DicomStudy.h"
#import "DicomSeries.h"
#import "DicomImage.h"
#import "DicomFile.h"
#import "ThreadsManager.h"      // SekhVet Paket CH: Versand in der Aktivitaetsliste
#import "NSThread+N2.h"
#import "AppController.h"       // SekhVet Paket CH: Mitteilung am Ende
#import "DCMObject.h"             // SekhVet Paket BQ: SeriesInstanceUID aus dem Dateikopf
#import "PieChartImage.h"     // Paket AO: dieselbe Kugel wie Horos' Q/R-Fenster
#import "ImageAndTextCell.h"  // Paket AO: Kugel links vom Namen
#import <Security/Security.h>
#include <arpa/inet.h>            // SekhVet Paket CS: inet_pton for the clear-text check

NSString* const SekhmetDICOMwebNodesKey = @"SekhmetDICOMwebNodes";
static NSString* const kService = @"SekhVet DICOMweb";
static SekhmetDICOMweb *sekhmetDICOMweb = nil;
// Fallback, wenn der Schluesselbund verweigert (z.B. ssh-Sitzung).
// SekhVet Paket CS: holds a password ONLY while the keychain refused to store it; after a successful
// SecItemAdd nothing is kept in plain text for the life of the process.
static NSMutableDictionary *sekhmetSessionPasswords = nil;
// SekhVet Paket CS: node URLs for which the user accepted sending credentials over plain http to a public host
static NSString* const SekhmetDICOMwebCleartextKey = @"SekhmetDICOMwebCleartextConsent";
// SekhVet Paket CS: upper bound for one buffered WADO-RS instance (or a non-multipart body)
static const NSUInteger SekhmetWadoMaxBufferBytes = 2048UL * 1024UL * 1024UL;
static const int SekhmetQidoStudyLimit = 300;                     // Sekhmet (DD)
static const NSUInteger SekhmetStowBatchFiles = 50;                 // Sekhmet (DD): STOW-RS in Portionen
static const unsigned long long SekhmetStowBatchBytes = 64ULL * 1024 * 1024;
// SekhVet Paket DN: automatic refresh, institution filters (kept over a restart)
static NSString* const SekhmetDICOMwebAutoMinutesKey = @"SekhmetDICOMwebAutoMinutes";            // 0 = off
static NSString* const SekhmetDICOMwebAutoRetrieveKey = @"SekhmetDICOMwebAutoRetrieve";
static NSString* const SekhmetDICOMwebInstitutionFilterKey = @"SekhmetDICOMwebInstitutionFilter"; // missing = on
static NSString* const SekhmetDICOMwebInstitutionTextKey = @"SekhmetDICOMwebInstitutionText";
static NSString* const SekhmetDICOMwebSelectedNodeKey = @"SekhmetDICOMwebSelectedNode";          // account "url|user"

// SekhVet Paket CS: everything a server sends is untrusted -- nil instead of an object of the wrong class
static id sekhmetTyped( id obj, Class cls)
{
    return [obj isKindOfClass: cls] ? obj : nil;
}

// SekhVet Paket CS: a UID from the server goes into a URL path -- escape everything that could leave its segment
static NSString* sekhmetPathEscape( NSString *s)
{
    NSMutableCharacterSet *allowed = [[[NSCharacterSet URLPathAllowedCharacterSet] mutableCopy] autorelease];
    [allowed removeCharactersInString: @"/;?#%"];
    NSString *e = [s stringByAddingPercentEncodingWithAllowedCharacters: allowed];
    return e ? e : @"";
}

@interface SekhmetDICOMweb ()
- (void) buildUI;
- (void) loadNodes;
- (void) saveNodes;
- (NSDictionary*) currentNode;
- (NSMutableURLRequest*) requestForURL:(NSString*) url accept:(NSString*) accept node:(NSDictionary*) node;
- (void) setStatus:(NSString*) s;
- (NSString*) value:(NSDictionary*) item tag:(NSString*) tag;
- (NSString*) timeString:(NSString*) t; // Build 67
- (void) retrieveNextStudy;
- (void) applyPeriodAndSearch:(BOOL) doSearch;   // Paket AP
- (void) annotateLocalStatus;            // Paket AM
- (void) refreshLocalStatus;             // Paket AM
- (NSString*) localTextForStudy:(NSDictionary*) r;                                  // Paket AM
- (NSString*) localTextForSeries:(NSDictionary*) s inStudy:(NSDictionary*) r;       // Paket AM
- (void) loadSeriesForStudy:(NSMutableDictionary*) study;                           // Paket AM
- (NSArray*) missingSeriesJobsForStudy:(NSDictionary*) study;                      // Paket BS
- (void) retrieveMissingAfterLoad:(NSDictionary*) study node:(NSDictionary*) node;  // Paket BS; SekhVet Paket CS: bound to the node
- (BOOL) mayUseNode:(NSDictionary*) node;                                           // SekhVet Paket CS
- (void) dropResultsIfNodeChanged;                                                  // SekhVet Paket CS
- (int) enqueueJobs:(NSArray*) jobs node:(NSDictionary*) node;                      // SekhVet Paket CS
- (void) seriesLoadFailedForStudy:(NSDictionary*) study status:(NSString*) status;  // SekhVet Paket CS
- (void) sendPaths:(NSArray*) paths toNode:(NSDictionary*) node studies:(NSUInteger) studies fromWindow:(BOOL) fromWindow; // SekhVet Paket CS
- (IBAction) nodeChanged:(id) sender;                                               // SekhVet Paket CS
- (IBAction) stopRetrieve:(id) sender;                                              // SekhVet Paket CS
+ (NSString*) accountForNode:(NSDictionary*) node;
+ (NSDictionary*) localStatusForStudies:(NSArray*) studies;                         // SekhVet Paket CS
- (void) sortResults;                                                              // Paket BU
- (void) retrieveFailed:(NSString*) message;                                        // Paket BU
#if SEKHVET_TESTHAKEN
- (void) debugLocalListLog;              // Paket AM
- (void) debugLocalSeriesLog;           // Paket AM
- (void) debugPieLog;                   // Paket AO
#endif // SEKHVET_TESTHAKEN
- (NSNumber*) localFractionForStudy:(NSDictionary*) r;                            // Paket AO
- (NSNumber*) localFractionForSeries:(NSDictionary*) s inStudy:(NSDictionary*) r; // Paket AO
- (NSString*) localTipWithHave:(int) have want:(int) want;                        // Paket AO
- (void) annotateSeries:(NSMutableDictionary*) s inStudy:(NSDictionary*) r;       // Paket AO
- (float) legendIn:(NSView*) cv x:(float) x y:(float) y percentage:(float) p text:(NSString*) t; // Paket AO
- (int) drainMultipartFinal:(BOOL) final;
- (void) searchAutomatically:(BOOL) automatic;                                     // SekhVet Paket DN
+ (NSArray*) institutionListForNode:(NSDictionary*) node;                         // SekhVet Paket DN
+ (NSArray*) institutionPatterns:(NSString*) text;                                // SekhVet Paket DN
+ (BOOL) institution:(NSString*) name matchesAny:(NSArray*) patterns;             // SekhVet Paket DN
- (void) updateInstitutionFilterButton;                                           // SekhVet Paket DN
- (void) restoreAutoSettings;                                                     // SekhVet Paket DN
- (void) setupAutoTimer:(BOOL) refreshSoon;                                       // SekhVet Paket DN
- (void) autoRetrieveNew;                                                         // SekhVet Paket DN
@end

@implementation SekhmetDICOMweb

+ (SekhmetDICOMweb*) shared
{
    if( sekhmetDICOMweb == nil)
        sekhmetDICOMweb = [[SekhmetDICOMweb alloc] init];
    return sekhmetDICOMweb;
}

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues
{
    // Keine vorbelegten Knoten: der Quelltext ist LGPL und wird veroeffentlicht,
    // Adressen und Benutzer der eigenen Infrastruktur gehoeren nicht hinein
    // (Review 12.09.2026). Knoten legt man im DICOMweb-Fenster mit "+" an.
    // SekhVet Paket CS: +defaultNodes removed (it only returned an empty array). This method stays:
    // DefaultsOsiriX.m calls it by name.
    [defaultValues setObject: [NSArray array] forKey: SekhmetDICOMwebNodesKey];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES]; // SekhVet: innerhalb der Viewer-Flaeche
    // Paket AP: relativer Zeitraum wird beim Zeigen nachgezogen (Fenster ueber Nacht offen);
    // "Any date" bleibt unangetastet, sonst wuerden selbst getippte Daten geloescht
    if( [periodPopup indexOfSelectedItem] > 0) [self applyPeriodAndSearch: NO];
    [super showWindow: sender];
}

#pragma mark - Schluesselbund

+ (NSString*) accountForNode:(NSDictionary*) node
{
    return [NSString stringWithFormat: @"%@|%@", [node objectForKey: @"url"], [node objectForKey: @"user"]];
}

+ (NSString*) passwordForNode:(NSDictionary*) node
{
    if( node == nil) return nil;
    NSString *mem = [sekhmetSessionPasswords objectForKey: [self accountForNode: node]];
    if( mem.length) return mem;
    NSDictionary *q = [NSDictionary dictionaryWithObjectsAndKeys:
                       (id) kSecClassGenericPassword, (id) kSecClass,
                       kService, (id) kSecAttrService,
                       [self accountForNode: node], (id) kSecAttrAccount,
                       (id) kCFBooleanTrue, (id) kSecReturnData,
                       (id) kSecMatchLimitOne, (id) kSecMatchLimit, nil];
    CFTypeRef result = NULL;
    OSStatus st = SecItemCopyMatching( (CFDictionaryRef) q, &result);
    if( st != errSecSuccess || result == NULL) return nil;
    NSString *pw = [[[NSString alloc] initWithData: (NSData*) result encoding: NSUTF8StringEncoding] autorelease];
    CFRelease( result);
    return pw;
}

// SekhVet Paket CS: returns whether the keychain really holds the password now (pw empty: whether the item is gone).
// On failure the password is kept for this session only, and the caller tells the user so.
+ (BOOL) setPassword:(NSString*) pw forNode:(NSDictionary*) node
{
    if( node == nil) return NO;
    NSString *account = [self accountForNode: node];
    [sekhmetSessionPasswords removeObjectForKey: account];
    NSDictionary *q = [NSDictionary dictionaryWithObjectsAndKeys:
                       (id) kSecClassGenericPassword, (id) kSecClass,
                       kService, (id) kSecAttrService,
                       account, (id) kSecAttrAccount, nil];
    OSStatus del = SecItemDelete( (CFDictionaryRef) q);
    if( pw.length == 0) return del == errSecSuccess || del == errSecItemNotFound;
    NSData *secret = [pw dataUsingEncoding: NSUTF8StringEncoding];
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary: q];
    [a setObject: secret forKey: (id) kSecValueData];
    [a setObject: @"SekhVet DICOMweb password" forKey: (id) kSecAttrLabel];
    OSStatus st = SecItemAdd( (CFDictionaryRef) a, NULL);
    if( st == errSecDuplicateItem)   // the old item could not be deleted (created by another build): overwrite it
        st = SecItemUpdate( (CFDictionaryRef) q, (CFDictionaryRef) [NSDictionary dictionaryWithObject: secret forKey: (id) kSecValueData]);
    if( st == errSecSuccess) return YES;
    NSLog( @"SekhVet DICOMweb: keychain error %d", (int) st);
    if( sekhmetSessionPasswords == nil) sekhmetSessionPasswords = [[NSMutableDictionary alloc] init];
    [sekhmetSessionPasswords setObject: pw forKey: account];
    return NO;
}

// SekhVet Paket CS: a node was removed or its URL / user changed -- its keychain item (account = url|user)
// would stay behind for ever. Not deleted while another node in the list still uses the same account.
+ (BOOL) forgetAccount:(NSString*) account unlessUsedBy:(NSArray*) nodeList
{
    if( account.length == 0) return NO;
    for( NSDictionary *n in nodeList)
        if( [[self accountForNode: n] isEqualToString: account]) return NO;
    [sekhmetSessionPasswords removeObjectForKey: account];
    NSDictionary *q = [NSDictionary dictionaryWithObjectsAndKeys:
                       (id) kSecClassGenericPassword, (id) kSecClass,
                       kService, (id) kSecAttrService,
                       account, (id) kSecAttrAccount, nil];
    return SecItemDelete( (CFDictionaryRef) q) == errSecSuccess;
}

#pragma mark - Init / UI

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 980, 640)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — DICOMweb", nil)];
    [w setReleasedWhenClosed: NO];
    [w setMinSize: NSMakeSize( 980, 640)];

    self = [super initWithWindow: w];
    if( self)
    {
        results = [[NSMutableArray alloc] init];
        nodes = [[NSMutableArray alloc] init];
        // SekhVet Paket CS: the retrieve queue lives in memory and every job carries its node. It used to be a
        // user default, so jobs left over from an earlier session or a crash were merged into the next retrieve.
        retrieveQueue = [[NSMutableArray alloc] init];
        [[NSUserDefaults standardUserDefaults] removeObjectForKey: @"SekhmetDICOMwebRetrieveQueue"];
        autoRetrieved = [[NSMutableDictionary alloc] init];   // SekhVet Paket DN
        [self buildUI];
        [self loadNodes];
        [self restoreAutoSettings];                            // SekhVet Paket DN: node, filters, automatic refresh
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [session invalidateAndCancel]; [session release]; [retrieveTask release]; [retrieveStamp release];
    [retrieveJob release]; [lastRetrieveError release];   // Paket BU
    [receivedData release]; [retrieveBoundary release]; [retrieveStudyUID release];
    [retrieveQueue release]; [retrieveNode release]; [resultsNode release]; [quietTried release];   // SekhVet Paket CS
    [retrieveAfterLoad release]; [quietLoads release];                                              // SekhVet Paket CS: were never released
    [results release]; [nodes release];
    [autoTimer invalidate]; [autoTimer release]; [autoRetrieved release];                           // SekhVet Paket DN
    [pickerWindow release]; [pickerItems release]; [pickerCounts release]; [pickerNode release];    // SekhVet Paket DN-2
    [super dealloc];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text]; [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSTextField*) field:(NSRect) r placeholder:(NSString*) ph
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setPlaceholderString: ph]; [t setFont: [NSFont systemFontOfSize: 12]];
    [t setAutoresizingMask: NSViewMinYMargin];
    [t setTarget: self]; [t setAction: @selector(search:)];
    return t;
}

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title]; [b setBezelStyle: NSBezelStyleRounded]; [b setTarget: self]; [b setAction: sel];
    [b setFont: [NSFont systemFontOfSize: 12]];
    [b setAutoresizingMask: NSViewMinYMargin];
    return b;
}

- (NSTableColumn*) column:(NSString*) ident width:(float) w editable:(BOOL) e
{
    NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: ident] autorelease];
    // SekhVet Paket CS: the identifier stays the (English) key, the header shows its localisation
    [[c headerCell] setStringValue: NSLocalizedString( ident, nil)]; [c setWidth: w]; [c setEditable: e];
    return c;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float W = [cv frame].size.width, H = [cv frame].size.height;
    float y = H - 36;

    [cv addSubview: [self label: NSLocalizedString( @"Node:", nil) frame: NSMakeRect( 20, y + 2, 60, 20)]];
    nodePopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 80, y - 2, 260, 26) pullsDown: NO] autorelease];
    [nodePopup setAutoresizingMask: NSViewMinYMargin];
    [nodePopup setTarget: self]; [nodePopup setAction: @selector(nodeChanged:)];   // SekhVet Paket CS: results belong to one node
    [cv addSubview: nodePopup];
    stowButton = [self button: NSLocalizedString( @"Send selected studies (STOW-RS)", nil) frame: NSMakeRect( 560, y - 4, 240, 30) action: @selector(stow:)];
    [cv addSubview: stowButton];

    y -= 34;
    nameField = [self field: NSMakeRect( 20, y, 180, 22) placeholder: NSLocalizedString( @"Name (partial)", nil)];
    idField = [self field: NSMakeRect( 210, y, 120, 22) placeholder: NSLocalizedString( @"Patient ID", nil)];
    dateFromField = [self field: NSMakeRect( 340, y, 100, 22) placeholder: NSLocalizedString( @"from YYYYMMDD", nil)];
    dateToField = [self field: NSMakeRect( 450, y, 100, 22) placeholder: NSLocalizedString( @"to YYYYMMDD", nil)];
    modalityField = [self field: NSMakeRect( 560, y, 70, 22) placeholder: @"CT/MR/DX"];
    // SekhVet Paket DN: institution (part of the name; several separated by ";"). Filtered here, not sent to the node --
    // QIDO-RS servers differ in whether they match InstitutionName at all, and case-sensitively.
    institutionField = [self field: NSMakeRect( 640, y, 170, 22) placeholder: NSLocalizedString( @"Institution (partial; a; b)", nil)];
    [institutionField setToolTip: NSLocalizedString( @"Show only studies whose institution name contains this text (upper/lower case and accents do not matter). Several names: separate them with \";\". The node is asked as usual; the filter is applied to its answer.", nil)];
    searchButton = [self button: NSLocalizedString( @"Search", nil) frame: NSMakeRect( 820, y - 4, 100, 30) action: @selector(search:)];
    [cv addSubview: nameField]; [cv addSubview: idField]; [cv addSubview: dateFromField]; [cv addSubview: dateToField]; [cv addSubview: modalityField]; [cv addSubview: institutionField]; [cv addSubview: searchButton];

    // Paket R: Zeitraum ohne Datumseingabe -> fuellt von/bis und sucht sofort
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Period:", nil) frame: NSMakeRect( 20, y + 2, 70, 20)]];
    periodPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 90, y - 2, 170, 26) pullsDown: NO] autorelease];
    [periodPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"Any date", nil), NSLocalizedString( @"Today", nil), NSLocalizedString( @"Yesterday", nil),
                                      NSLocalizedString( @"Last 2 days", nil), /* Paket CL */ NSLocalizedString( @"Last 3 days", nil), NSLocalizedString( @"Last 4 days", nil), NSLocalizedString( @"Last week", nil), NSLocalizedString( @"Last month", nil), nil]];
    [periodPopup setAutoresizingMask: NSViewMinYMargin];
    [periodPopup setTarget: self]; [periodPopup setAction: @selector(periodChanged:)];
    [cv addSubview: periodPopup];
    [periodPopup selectItemAtIndex: 1];          // Paket AP: Vorgabe "Today"
    [self applyPeriodAndSearch: NO];             // fuellt von/bis, sucht aber noch nicht

    // Paket AO: Legende zur Kugel
    float lx = 480;
    lx = [self legendIn: cv x: lx y: y percentage: 1.0 text: NSLocalizedString( @"here", nil)];
    lx = [self legendIn: cv x: lx y: y percentage: 0.4 text: NSLocalizedString( @"partly here", nil)];
    [self legendIn: cv x: lx y: y percentage: 0.0 text: NSLocalizedString( @"not here", nil)];

    // SekhVet Paket DN: automatic refresh (like OsiriX' auto query/retrieve) and the institution list of the node
    y -= 30;
    NSTextField *autoLabel = [self label: NSLocalizedString( @"Auto-refresh:", nil) frame: NSMakeRect( 20, y + 2, 90, 20)];
    [autoLabel setAutoresizingMask: NSViewMinYMargin];
    [cv addSubview: autoLabel];
    autoPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 110, y - 2, 150, 26) pullsDown: NO] autorelease];
    [autoPopup addItemWithTitle: NSLocalizedString( @"Off", nil)];
    [[autoPopup lastItem] setTag: 0];
    for( NSNumber *m in [NSArray arrayWithObjects: @1, @3, @5, @10, @15, @30, nil])
    {
        [autoPopup addItemWithTitle: [NSString stringWithFormat: NSLocalizedString( @"Every %d min.", nil), [m intValue]]];
        [[autoPopup lastItem] setTag: [m intValue]];
    }
    [autoPopup setAutoresizingMask: NSViewMinYMargin];
    [autoPopup setTarget: self]; [autoPopup setAction: @selector(autoChanged:)];
    [autoPopup setToolTip: NSLocalizedString( @"Repeat the search with the current fields every few minutes — also while this window is closed. Kept after a restart.", nil)];
    [cv addSubview: autoPopup];
    autoRetrieveButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 275, y + 1, 280, 18)] autorelease];
    [autoRetrieveButton setButtonType: NSButtonTypeSwitch];
    [autoRetrieveButton setTitle: NSLocalizedString( @"Retrieve new studies automatically", nil)];
    [autoRetrieveButton setFont: [NSFont systemFontOfSize: 12]];
    [autoRetrieveButton setAutoresizingMask: NSViewMinYMargin];
    [autoRetrieveButton setTarget: self]; [autoRetrieveButton setAction: @selector(autoChanged:)];
    [autoRetrieveButton setToolTip: NSLocalizedString( @"After every automatic refresh, studies of the list that are not (completely) here are retrieved by WADO-RS. Needs a period (e.g. Today). Only the studies the filters show.", nil)];
    [cv addSubview: autoRetrieveButton];
    // SekhVet Paket DN-2: the list is chosen from the institutions the node really has
    chooseInstitutionsButton = [self button: NSLocalizedString( @"Choose…", nil) frame: NSMakeRect( 860, y - 5, 100, 30) action: @selector(chooseInstitutions:)];
    [chooseInstitutionsButton setToolTip: NSLocalizedString( @"Read all institutions of this node and tick the ones to show", nil)];
    [cv addSubview: chooseInstitutionsButton];
    institutionFilterButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 560, y + 1, 295, 18)] autorelease];
    [institutionFilterButton setButtonType: NSButtonTypeSwitch];
    [institutionFilterButton setFont: [NSFont systemFontOfSize: 12]];
    [institutionFilterButton setAutoresizingMask: NSViewMinYMargin];
    [institutionFilterButton setTarget: self]; [institutionFilterButton setAction: @selector(institutionFilterChanged:)];
    [institutionFilterButton setToolTip: NSLocalizedString( @"Show only studies of the referring institutions listed for this node (column \"Institutions filter\" in the node list below, separated by \";\").", nil)];
    [cv addSubview: institutionFilterButton];

    // Ergebnisse
    float tableTop = y - 12, tableBottom = 250;
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, tableBottom, W - 40, tableTop - tableBottom)] autorelease];
    [sv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    // Paket AM: Outline statt Tabelle — Dreieck klappt die Serien der Studie auf, Spalte "Local" sagt, was schon hier liegt
    resultTable = [[[NSOutlineView alloc] initWithFrame: NSMakeRect( 0, 0, W - 40, tableTop - tableBottom)] autorelease];
    [resultTable setIdentifier: @"results"];
    NSTableColumn *nameCol = [self column: @"Name" width: 200 editable: NO];
    // Paket AO: Kugel vor dem Namen — gruen = alles hier, orange teilgefuellt = Teilbestand, leer = nichts hier
    ImageAndTextCell *nameCell = [[[ImageAndTextCell alloc] initTextCell: @""] autorelease];
    [nameCell setFont: [[nameCol dataCell] font]];
    [nameCell setLineBreakMode: NSLineBreakByTruncatingMiddle];
    [nameCol setDataCell: nameCell];
    [resultTable addTableColumn: nameCol];
    [resultTable setOutlineTableColumn: nameCol];
    [resultTable addTableColumn: [self column: @"ID" width: 80 editable: NO]];
    [resultTable addTableColumn: [self column: @"Date" width: 80 editable: NO]];
    [resultTable addTableColumn: [self column: @"Time" width: 50 editable: NO]];       // Build 67
    [resultTable addTableColumn: [self column: @"Modality" width: 70 editable: NO]];
    [resultTable addTableColumn: [self column: @"Description" width: 200 editable: NO]];
    [resultTable addTableColumn: [self column: @"Institution" width: 130 editable: NO]]; // Build 67
    [resultTable addTableColumn: [self column: @"Series" width: 50 editable: NO]];
    [resultTable addTableColumn: [self column: @"Images" width: 60 editable: NO]];
    [resultTable addTableColumn: [self column: @"Local" width: 130 editable: NO]];      // Paket AM
    // SekhVet Paket BU: Klick auf den Spaltenkopf sortiert die Studien (Serien bleiben in ihrer Reihenfolge); Datum/Zeit zuerst absteigend.
    // Bei Gleichstand gilt immer: neueste zuerst. Die Wahl bleibt ueber den Neustart erhalten.
    for( NSTableColumn *c in [resultTable tableColumns])
    {
        BOOL newestFirst = [[c identifier] isEqualToString: @"Date"] || [[c identifier] isEqualToString: @"Time"];
        [c setSortDescriptorPrototype: [NSSortDescriptor sortDescriptorWithKey: [c identifier] ascending: newestFirst == NO]];
    }
    [resultTable setDataSource: self]; [resultTable setDelegate: self];
    NSDictionary *savedSort = [[NSUserDefaults standardUserDefaults] dictionaryForKey: @"SekhmetDICOMwebSort"];
    NSString *sortKey = [savedSort objectForKey: @"key"];
    if( [resultTable tableColumnWithIdentifier: sortKey ?: @""] == nil) sortKey = @"Date";
    BOOL sortAsc = savedSort ? [[savedSort objectForKey: @"ascending"] boolValue] : NO;
    [resultTable setSortDescriptors: [NSArray arrayWithObject: [NSSortDescriptor sortDescriptorWithKey: sortKey ascending: sortAsc]]];
    [resultTable setUsesAlternatingRowBackgroundColors: YES];
    [resultTable setAllowsMultipleSelection: YES];
    [resultTable setIndentationPerLevel: 14];
    [resultTable setAutoresizesOutlineColumn: NO];
    [resultTable setDoubleAction: @selector(retrieve:)]; [resultTable setTarget: self];
    [sv setDocumentView: resultTable]; [sv setHasVerticalScroller: YES]; [sv setBorderType: NSBezelBorder];
    [cv addSubview: sv];

    y = tableBottom - 34;
    retrieveButton = [self button: NSLocalizedString( @"Retrieve (WADO-RS)", nil) frame: NSMakeRect( 20, y - 2, 180, 30) action: @selector(retrieve:)];
    [retrieveButton setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: retrieveButton];
    // SekhVet Paket CS: a running retrieve (and everything still queued) can be stopped
    stopButton = [self button: NSLocalizedString( @"Stop", nil) frame: NSMakeRect( 204, y - 2, 70, 30) action: @selector(stopRetrieve:)];
    [stopButton setAutoresizingMask: NSViewMaxYMargin];
    [stopButton setEnabled: NO];
    [cv addSubview: stopButton];
    progress = [[[NSProgressIndicator alloc] initWithFrame: NSMakeRect( 282, y + 6, 128, 16)] autorelease];
    [progress setStyle: NSProgressIndicatorStyleBar]; [progress setIndeterminate: YES]; [progress setHidden: YES];
    [progress setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: progress];
    statusField = [self label: @"" frame: NSMakeRect( 420, y + 4, W - 440, 20)];
    [statusField setAutoresizingMask: NSViewMaxYMargin | NSViewWidthSizable];
    [cv addSubview: statusField];

    // Knoten
    y -= 34;
    NSTextField *l = [self label: NSLocalizedString( @"Nodes (URL up to /dicom-web, password in keychain):", nil) frame: NSMakeRect( 20, y, 500, 20)];
    [l setAutoresizingMask: NSViewMaxYMargin]; [cv addSubview: l];
    y -= 130;
    // SekhVet Paket DN: one column more -- the referring institutions shown for this node; table wider, buttons to the right
    NSScrollView *nsv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, y, 760, 124)] autorelease];
    [nsv setAutoresizingMask: NSViewMaxYMargin];
    nodeTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 760, 124)] autorelease];
    [nodeTable setIdentifier: @"nodes"];
    [nodeTable addTableColumn: [self column: @"Node" width: 130 editable: YES]];
    [nodeTable addTableColumn: [self column: @"URL" width: 260 editable: YES]];
    [nodeTable addTableColumn: [self column: @"User" width: 80 editable: YES]];
    NSTableColumn *instCol = [self column: @"Institutions filter" width: 270 editable: YES];
    [[instCol headerCell] setStringValue: NSLocalizedString( @"Institutions filter (a; b; …)", nil)];
    [nodeTable addTableColumn: instCol];
    [nodeTable setDataSource: self];   // SekhVet Paket CS: no delegate -- no table delegate method is implemented
    [nodeTable setUsesAlternatingRowBackgroundColors: YES];
    [nsv setDocumentView: nodeTable]; [nsv setHasVerticalScroller: YES]; [nsv setBorderType: NSBezelBorder];
    [cv addSubview: nsv];

    NSButton *plus = [self button: @"+" frame: NSMakeRect( 790, y + 96, 40, 26) action: @selector(addNode:)];
    NSButton *minus = [self button: @"−" frame: NSMakeRect( 835, y + 96, 40, 26) action: @selector(removeNode:)];
    [plus setAutoresizingMask: NSViewMaxYMargin]; [minus setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: plus]; [cv addSubview: minus];

    passwordField = [[[NSSecureTextField alloc] initWithFrame: NSMakeRect( 790, y + 50, 170, 22)] autorelease];
    [passwordField setPlaceholderString: NSLocalizedString( @"Password of the selected node", nil)];
    [passwordField setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: passwordField];
    NSButton *save = [self button: NSLocalizedString( @"Save password", nil) frame: NSMakeRect( 790, y + 14, 170, 30) action: @selector(savePassword:)];
    [save setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: save];
}

#pragma mark - Knoten

- (void) loadNodes
{
    [nodes removeAllObjects];
    for( NSDictionary *n in [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetDICOMwebNodesKey])
        [nodes addObject: [[n mutableCopy] autorelease]];
    [nodeTable reloadData];
    NSInteger sel = [nodePopup indexOfSelectedItem];
    [nodePopup removeAllItems];
    for( NSDictionary *n in nodes) [nodePopup addItemWithTitle: [n objectForKey: @"name"]];
    if( sel >= 0 && sel < (NSInteger) nodes.count) [nodePopup selectItemAtIndex: sel];
    [self dropResultsIfNodeChanged];   // SekhVet Paket CS: the same index may now be another node
    [self updateInstitutionFilterButton];   // SekhVet Paket DN: the list may have been edited
}

// SekhVet Paket DN: the node's list of referring institutions -- "institutions" in the node, separated by ";"
+ (NSArray*) institutionListForNode:(NSDictionary*) node
{
    return [self institutionPatterns: sekhmetTyped( [node objectForKey: @"institutions"], [NSString class])];
}

+ (NSArray*) institutionPatterns:(NSString*) text
{
    NSMutableArray *a = [NSMutableArray array];
    for( NSString *p in [text ?: @"" componentsSeparatedByCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @";\n"]])
    {
        NSString *t = [p stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
        if( t.length) [a addObject: t];
    }
    return a;
}

// contains, ignoring upper/lower case and accents ("tierklinik zurich" finds "Tierklinik Zürich AG").
// SekhVet Paket DN-2: the entry "(none)" stands for studies without an institution name.
static NSString* const SekhmetNoInstitution = @"(none)";

+ (BOOL) institution:(NSString*) name matchesAny:(NSArray*) patterns
{
    NSString *n = [name ?: @"" stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    for( NSString *p in patterns)
    {
        if( [p caseInsensitiveCompare: SekhmetNoInstitution] == NSOrderedSame) { if( n.length == 0) return YES; continue; }
        if( [n rangeOfString: p options: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) return YES;
    }
    return NO;
}

#pragma mark - Institutionen waehlen (SekhVet Paket DN-2)

// Wunsch 04.10.2026: die Liste nicht abtippen, sondern aus dem fuellen, was der Knoten wirklich hat, und
// ankreuzen, was angezeigt werden soll. Gelesen wird seitenweise nur das Feld InstitutionName aller Studien.
static const int SekhmetPickerPage = 500, SekhmetPickerMaxPages = 40;   // hoechstens 20 000 Studien

- (void) buildPicker
{
    pickerWindow = [[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 520, 460) styleMask: NSWindowStyleMaskTitled backing: NSBackingStoreBuffered defer: YES];
    [pickerWindow setReleasedWhenClosed: NO];
    NSView *cv = [pickerWindow contentView];
    NSTextField *t = [self label: NSLocalizedString( @"Show the studies of these institutions (ticked):", nil) frame: NSMakeRect( 20, 424, 480, 20)];
    [t setFont: [NSFont boldSystemFontOfSize: 12]];
    [cv addSubview: t];
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, 90, 480, 326)] autorelease];
    pickerTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 480, 326)] autorelease];
    [pickerTable setIdentifier: @"institutions"];
    NSTableColumn *on = [[[NSTableColumn alloc] initWithIdentifier: @"on"] autorelease];
    [[on headerCell] setStringValue: @""]; [on setWidth: 24];
    NSButtonCell *box = [[[NSButtonCell alloc] init] autorelease];
    [box setButtonType: NSButtonTypeSwitch]; [box setTitle: @""];
    [on setDataCell: box];
    [pickerTable addTableColumn: on];
    NSTableColumn *nameCol = [[[NSTableColumn alloc] initWithIdentifier: @"name"] autorelease];
    [[nameCol headerCell] setStringValue: NSLocalizedString( @"Institution", nil)]; [nameCol setWidth: 360]; [nameCol setEditable: NO];
    [pickerTable addTableColumn: nameCol];
    NSTableColumn *countCol = [[[NSTableColumn alloc] initWithIdentifier: @"count"] autorelease];
    [[countCol headerCell] setStringValue: NSLocalizedString( @"Studies", nil)]; [countCol setWidth: 70]; [countCol setEditable: NO];
    [pickerTable addTableColumn: countCol];
    [pickerTable setDataSource: self];
    [pickerTable setUsesAlternatingRowBackgroundColors: YES];
    [sv setDocumentView: pickerTable]; [sv setHasVerticalScroller: YES]; [sv setBorderType: NSBezelBorder];
    [cv addSubview: sv];
    pickerStatus = [self label: @"" frame: NSMakeRect( 20, 62, 480, 20)];
    [cv addSubview: pickerStatus];
    for( NSView *v in @[ [self button: NSLocalizedString( @"All", nil) frame: NSMakeRect( 20, 16, 70, 30) action: @selector(pickerAll:)],
                          [self button: NSLocalizedString( @"None", nil) frame: NSMakeRect( 94, 16, 70, 30) action: @selector(pickerNone:)],
                          [self button: NSLocalizedString( @"Cancel", nil) frame: NSMakeRect( 300, 16, 96, 30) action: @selector(pickerCancel:)]])
    {
        [(NSButton*) v setAutoresizingMask: NSViewNotSizable];
        [cv addSubview: v];
    }
    pickerSaveButton = [self button: NSLocalizedString( @"Save", nil) frame: NSMakeRect( 404, 16, 96, 30) action: @selector(pickerSave:)];
    [pickerSaveButton setAutoresizingMask: NSViewNotSizable];
    [pickerSaveButton setKeyEquivalent: @"\r"];
    [cv addSubview: pickerSaveButton];
}

- (IBAction) chooseInstitutions:(id) sender
{
    NSDictionary *node = [[[self currentNode] copy] autorelease];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }
    if( [self mayUseNode: node] == NO) return;
    if( pickerWindow == nil) [self buildPicker];
    if( pickerItems == nil) pickerItems = [[NSMutableArray alloc] init];
    [pickerItems removeAllObjects];
    [pickerCounts release]; pickerCounts = [[NSMutableDictionary alloc] init];
    [pickerNode release]; pickerNode = [node retain];
    pickerGeneration++;
    [pickerTable reloadData];
    [pickerSaveButton setEnabled: NO];
    [pickerStatus setStringValue: NSLocalizedString( @"Reading the institutions of the node…", nil)];
    [pickerWindow setTitle: [NSString stringWithFormat: NSLocalizedString( @"Institutions of %@", nil), [node objectForKey: @"name"] ?: @""]];
    [[self window] beginSheet: pickerWindow completionHandler: nil];
    [self readInstitutionsPage: 0 generation: pickerGeneration];
}

- (void) readInstitutionsPage:(int) page generation:(int) generation
{
    NSString *url = [NSString stringWithFormat: @"%@/studies?includefield=00080080&limit=%d&offset=%d", [pickerNode objectForKey: @"url"], SekhmetPickerPage, page * SekhmetPickerPage];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"application/dicom+json" node: pickerNode];
    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        if( generation != pickerGeneration) return;   // sheet closed or opened again meanwhile
        @try
        {
            NSInteger code = [response isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) response statusCode] : 0;
            id json = (code == 200 && data.length) ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : (code == 204 ? [NSArray array] : nil);
            if( error || [json isKindOfClass: [NSArray class]] == NO)
            {
                [pickerStatus setStringValue: error ? [NSString stringWithFormat: NSLocalizedString( @"Error: %@", nil), error.localizedDescription]
                                                    : (code == 401 ? NSLocalizedString( @"401: user/password rejected", nil) : [NSString stringWithFormat: @"HTTP %d", (int) code])];
                if( page > 0) [self finishInstitutionPicker: YES];
                return;
            }
            for( NSDictionary *item in json)
            {
                if( [item isKindOfClass: [NSDictionary class]] == NO) continue;
                NSString *name = [[self value: item tag: @"00080080"] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]];
                if( name.length == 0) name = SekhmetNoInstitution;
                [pickerCounts setObject: [NSNumber numberWithInt: [[pickerCounts objectForKey: name] intValue] + 1] forKey: name];
            }
            int studies = 0;
            for( NSNumber *c in [pickerCounts allValues]) studies += [c intValue];
            [pickerStatus setStringValue: [NSString stringWithFormat: NSLocalizedString( @"Reading… %d studies, %d institutions", nil), studies, (int) pickerCounts.count]];
            if( [json count] >= (NSUInteger) SekhmetPickerPage && page + 1 < SekhmetPickerMaxPages) [self readInstitutionsPage: page + 1 generation: generation];
            else [self finishInstitutionPicker: [json count] >= (NSUInteger) SekhmetPickerPage];
        }
        @catch (NSException *e)
        {
            NSLog( @"SekhVet DICOMweb: institution list raised %@", e.name);
            [pickerStatus setStringValue: NSLocalizedString( @"Error: the answer of the node could not be read", nil)];
        }
    }];
    [task resume];
}

// Ticked = matches the list stored with the node. Entries of that list the node no longer has stay (ticked, 0 studies).
- (void) finishInstitutionPicker:(BOOL) truncated
{
    NSArray *stored = [SekhmetDICOMweb institutionListForNode: pickerNode];
    NSMutableSet *covered = [NSMutableSet set];
    [pickerItems removeAllObjects];
    int studies = 0;
    for( NSString *name in pickerCounts)
    {
        BOOL on = [name isEqualToString: SekhmetNoInstitution] ? [SekhmetDICOMweb institution: @"" matchesAny: stored] : [SekhmetDICOMweb institution: name matchesAny: stored];
        for( NSString *p in stored)
            if( [name rangeOfString: p options: NSCaseInsensitiveSearch | NSDiacriticInsensitiveSearch].location != NSNotFound) [covered addObject: p];
        studies += [[pickerCounts objectForKey: name] intValue];
        [pickerItems addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: name, @"name", [pickerCounts objectForKey: name], @"count", [NSNumber numberWithBool: on], @"on", nil]];
    }
    for( NSString *p in stored)
        if( [covered containsObject: p] == NO && [pickerCounts objectForKey: p] == nil)
            [pickerItems addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: p, @"name", @0, @"count", @YES, @"on", nil]];
    [pickerItems sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        return [[a objectForKey: @"name"] localizedStandardCompare: [b objectForKey: @"name"]];
    }];
    [pickerTable reloadData];
    [pickerSaveButton setEnabled: YES];
    NSString *s = [NSString stringWithFormat: NSLocalizedString( @"%d institutions in %d studies", nil), (int) pickerCounts.count, studies];
    if( truncated) s = [s stringByAppendingString: NSLocalizedString( @" (stopped after 20 000 studies)", nil)];
    [pickerStatus setStringValue: s];
}

- (IBAction) pickerAll:(id) sender { for( NSMutableDictionary *d in pickerItems) [d setObject: @YES forKey: @"on"]; [pickerTable reloadData]; }
- (IBAction) pickerNone:(id) sender { for( NSMutableDictionary *d in pickerItems) [d setObject: @NO forKey: @"on"]; [pickerTable reloadData]; }

- (void) closePicker
{
    pickerGeneration++;
    [[self window] endSheet: pickerWindow];
    [pickerWindow orderOut: nil];
}

- (IBAction) pickerCancel:(id) sender
{
    [self closePicker];
}

- (IBAction) pickerSave:(id) sender
{
    NSMutableArray *names = [NSMutableArray array];
    for( NSDictionary *d in pickerItems)
        if( [[d objectForKey: @"on"] boolValue]) [names addObject: [[d objectForKey: @"name"] stringByReplacingOccurrencesOfString: @";" withString: @" "]];
    NSString *account = [SekhmetDICOMweb accountForNode: pickerNode];
    for( NSMutableDictionary *n in nodes)
        if( [[SekhmetDICOMweb accountForNode: n] isEqualToString: account] && [[n objectForKey: @"name"] isEqual: [pickerNode objectForKey: @"name"]])
        {
            [n setObject: [names componentsJoinedByString: @"; "] forKey: @"institutions"];
            break;
        }
    [self closePicker];
    if( names.count) [[NSUserDefaults standardUserDefaults] setBool: YES forKey: SekhmetDICOMwebInstitutionFilterKey];
    [self saveNodes];   // -> loadNodes -> updateInstitutionFilterButton
    [self search: self];
}

- (void) updateInstitutionFilterButton
{
    NSUInteger n = [[SekhmetDICOMweb institutionListForNode: [self currentNode]] count];
    id stored = [[NSUserDefaults standardUserDefaults] objectForKey: SekhmetDICOMwebInstitutionFilterKey];
    [institutionFilterButton setTitle: n ? [NSString stringWithFormat: NSLocalizedString( @"Only the %d chosen institutions", nil), (int) n]
                                         : NSLocalizedString( @"Only chosen institutions (none chosen)", nil)];
    [institutionFilterButton setEnabled: n > 0];
    [institutionFilterButton setState: (n > 0 && (stored == nil || [stored boolValue])) ? NSControlStateValueOn : NSControlStateValueOff];
}

- (IBAction) institutionFilterChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setBool: [institutionFilterButton state] == NSControlStateValueOn forKey: SekhmetDICOMwebInstitutionFilterKey];
    if( resultsNode) [self search: sender];   // the list on screen follows at once
}

// SekhVet Paket CS: results (and what is expanded below them) came from exactly one node. When another
// node is selected, or the selected one now has another URL / user, they are cleared -- otherwise
// "Retrieve" would send their StudyInstanceUIDs, with the other node's credentials, to a different server.
- (void) dropResultsIfNodeChanged
{
    if( resultsNode == nil) return;
    NSDictionary *now = [self currentNode];
    if( now && [[SekhmetDICOMweb accountForNode: now] isEqualToString: [SekhmetDICOMweb accountForNode: resultsNode]]) return;
    [resultsNode release]; resultsNode = nil;
    [results removeAllObjects];
    [quietLoads removeAllObjects]; [quietTried removeAllObjects];
    [resultTable reloadData];
    [self setStatus: NSLocalizedString( @"Node changed — results cleared, search again", nil)];
}

- (IBAction) nodeChanged:(id) sender
{
    [self dropResultsIfNodeChanged];
    // SekhVet Paket DN: the automatic refresh asks the node chosen here, also after a restart
    NSDictionary *n = [self currentNode];
    if( n) [[NSUserDefaults standardUserDefaults] setObject: [SekhmetDICOMweb accountForNode: n] forKey: SekhmetDICOMwebSelectedNodeKey];
    [self updateInstitutionFilterButton];
}

- (void) saveNodes
{
    [[NSUserDefaults standardUserDefaults] setObject: nodes forKey: SekhmetDICOMwebNodesKey];
    [self loadNodes];
}

- (NSDictionary*) currentNode
{
    NSInteger i = [nodePopup indexOfSelectedItem];
    if( i < 0 || i >= (NSInteger) nodes.count) return nil;
    return [nodes objectAtIndex: i];
}

- (IBAction) addNode:(id) sender
{
    [nodes addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: NSLocalizedString( @"New node", nil), @"name", @"http://server:8042/dicom-web", @"url", @"", @"user", nil]];
    [self saveNodes];
    [nodeTable editColumn: 0 row: nodes.count - 1 withEvent: nil select: YES];
}

- (IBAction) removeNode:(id) sender
{
    NSInteger r = [nodeTable selectedRow];
    if( r >= 0 && r < (NSInteger) nodes.count)
    {
        // SekhVet Paket CS: take the node's keychain item and its clear-text consent with it
        NSString *account = [SekhmetDICOMweb accountForNode: [nodes objectAtIndex: r]];
        NSString *url = [[[[nodes objectAtIndex: r] objectForKey: @"url"] retain] autorelease];
        [nodes removeObjectAtIndex: r];
        [SekhmetDICOMweb forgetAccount: account unlessUsedBy: nodes];
        if( url && [[nodes valueForKey: @"url"] containsObject: url] == NO)
        {
            NSMutableArray *consent = [NSMutableArray arrayWithArray: [[NSUserDefaults standardUserDefaults] stringArrayForKey: SekhmetDICOMwebCleartextKey]];
            [consent removeObject: url];
            [[NSUserDefaults standardUserDefaults] setObject: consent forKey: SekhmetDICOMwebCleartextKey];
        }
        [self saveNodes];
    }
}

- (IBAction) savePassword:(id) sender
{
    NSInteger r = [nodeTable selectedRow];
    if( r < 0) r = [nodePopup indexOfSelectedItem];
    if( r < 0 || r >= (NSInteger) nodes.count) { [self setStatus: NSLocalizedString( @"No node selected", nil)]; return; }
    // SekhVet Paket CS: say what really happened -- the keychain can refuse (locked, ssh session, item of another build)
    BOOL empty = [[passwordField stringValue] length] == 0;
    BOOL stored = [SekhmetDICOMweb setPassword: [passwordField stringValue] forNode: [nodes objectAtIndex: r]];
    [passwordField setStringValue: @""];
    NSString *nodeName = [[nodes objectAtIndex: r] objectForKey: @"name"];
    if( empty) [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Password for \"%@\" removed", nil), nodeName]];
    else if( stored) [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Password for \"%@\" saved", nil), nodeName]];
    else
    {
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Keychain refused the password for \"%@\" — it works until SekhVet quits only", nil), nodeName]];
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setAlertStyle: NSAlertStyleWarning];
        [a setMessageText: NSLocalizedString( @"The password could not be saved in the keychain", nil)];
        [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"macOS refused to store the password for \"%@\" (keychain locked, access denied, or no login session). SekhVet keeps it in memory until it quits; after the next start you have to enter it again. Unlock the login keychain (Keychain Access) and save the password once more.", nil), nodeName]];
        [a runModal];
    }
}

#pragma mark - HTTP

- (NSMutableURLRequest*) requestForURL:(NSString*) url accept:(NSString*) accept node:(NSDictionary*) node
{
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL: [NSURL URLWithString: url] cachePolicy: NSURLRequestReloadIgnoringLocalCacheData timeoutInterval: 600];
    [req setValue: accept forHTTPHeaderField: @"Accept"];
    NSString *user = [node objectForKey: @"user"];
    NSString *pw = [SekhmetDICOMweb passwordForNode: node];
    if( user.length)
    {
        NSData *d = [[NSString stringWithFormat: @"%@:%@", user, pw ? pw : @""] dataUsingEncoding: NSUTF8StringEncoding];
        [req setValue: [NSString stringWithFormat: @"Basic %@", [d base64EncodedStringWithOptions: 0]] forHTTPHeaderField: @"Authorization"];
    }
    return req;
}

- (NSURLSession*) session
{
    if( session == nil)
    {
        NSURLSessionConfiguration *c = [NSURLSessionConfiguration ephemeralSessionConfiguration];
        c.timeoutIntervalForResource = 24 * 3600;   // SekhVet Paket CS: was 1 h, which cut every longer transfer; a stalled one still ends after 600 s without data (request timeout)
        session = [[NSURLSession sessionWithConfiguration: c delegate: self delegateQueue: [NSOperationQueue mainQueue]] retain];
    }
    return session;
}

// SekhVet Paket CS: a redirect is followed only to the same host and never from https down to http.
// Otherwise the 3xx answer itself is delivered ("HTTP 302") -- the queries carry patient names and IDs
// in the URL, they must not be replayed to whatever host a proxy or captive portal names.
- (void) URLSession:(NSURLSession*) s task:(NSURLSessionTask*) task willPerformHTTPRedirection:(NSHTTPURLResponse*) response newRequest:(NSURLRequest*) request completionHandler:(void (^)(NSURLRequest*)) completionHandler
{
    NSURL *from = task.currentRequest.URL ? task.currentRequest.URL : task.originalRequest.URL, *to = request.URL;
    BOOL sameHost = from.host.length && to.host.length && [from.host caseInsensitiveCompare: to.host] == NSOrderedSame;
    BOOL downgrade = [[from.scheme lowercaseString] isEqualToString: @"https"] && [[to.scheme lowercaseString] isEqualToString: @"https"] == NO;
    completionHandler( (sameHost && downgrade == NO) ? request : nil);
}

// SekhVet Paket CS: YES = this Mac, a private or link-local address, a Tailscale address (100.64.0.0/10,
// fd7a:…) or a name that only resolves inside a local network. Plain http to such a host is the normal
// in-clinic setup (Orthanc on the LAN) and is not questioned.
+ (BOOL) hostIsLocal:(NSString*) host
{
    host = [[host lowercaseString] stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"[]"]];
    NSRange zone = [host rangeOfString: @"%"];
    if( zone.location != NSNotFound) host = [host substringToIndex: zone.location];
    if( host.length == 0) return NO;

    struct in_addr a4;
    struct in6_addr a6;
    if( inet_pton( AF_INET, [host UTF8String], &a4) == 1)
    {
        uint32_t ip = ntohl( a4.s_addr);
        return (ip >> 24) == 127 || (ip >> 24) == 10 || (ip >> 20) == 0xAC1 || (ip >> 16) == 0xC0A8 || (ip >> 16) == 0xA9FE || (ip >> 22) == (0x64400000U >> 22);
    }
    if( inet_pton( AF_INET6, [host UTF8String], &a6) == 1)
    {
        const uint8_t *b = a6.s6_addr;
        BOOL loopback = YES;
        for( int i = 0; i < 15; i++) if( b[ i]) loopback = NO;
        if( b[ 15] != 1) loopback = NO;
        return loopback || (b[ 0] & 0xFE) == 0xFC || (b[ 0] == 0xFE && (b[ 1] & 0xC0) == 0x80);
    }
    if( [host isEqualToString: @"localhost"] || [host rangeOfString: @"."].location == NSNotFound) return YES;   // single-label name: resolved by the LAN
    for( NSString *suffix in [NSArray arrayWithObjects: @".local", @".lan", @".home.arpa", @".internal", @".localdomain", @".ts.net", nil])
        if( [host hasSuffix: suffix]) return YES;
    return NO;
}

// SekhVet Paket CS: a node with a user name sends "Authorization: Basic" with every request. Over plain
// http to a host outside the local network, user, password, patient names and images are readable on the
// way. Asked once per node URL (remembered in the defaults); NO = the user declined. Main thread only.
- (BOOL) mayUseNode:(NSDictionary*) node
{
    NSString *urlString = sekhmetTyped( [node objectForKey: @"url"], [NSString class]);
    if( [sekhmetTyped( [node objectForKey: @"user"], [NSString class]) length] == 0) return YES;
    NSURL *u = urlString.length ? [NSURL URLWithString: urlString] : nil;
    if( u == nil || [[[u scheme] lowercaseString] isEqualToString: @"http"] == NO) return YES;
    if( [SekhmetDICOMweb hostIsLocal: [u host]]) return YES;
    NSArray *consent = [[NSUserDefaults standardUserDefaults] stringArrayForKey: SekhmetDICOMwebCleartextKey];
    if( [consent containsObject: urlString]) return YES;

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleWarning];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"“%@” is not encrypted", nil), sekhmetTyped( [node objectForKey: @"name"], [NSString class]) ?: urlString]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"%@\n\nThis address uses http:// and is not in your local network. User name, password, patient names and images would cross the Internet unencrypted, readable by anyone on the way. Use an https:// address if the server offers one.\n\n“Send anyway” is remembered for this node.", nil), urlString]];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Send anyway", nil)];
    if( [a runModal] != NSAlertSecondButtonReturn)
    {
        [self setStatus: NSLocalizedString( @"Cancelled — nothing was sent to the node", nil)];
        return NO;
    }
    [[NSUserDefaults standardUserDefaults] setObject: [(consent ? consent : [NSArray array]) arrayByAddingObject: urlString] forKey: SekhmetDICOMwebCleartextKey];
    return YES;
}

- (void) setStatus:(NSString*) s
{
    [statusField setStringValue: s ? s : @""];
}

// SekhVet Paket CS: always returns an NSString, whatever the server put into the JSON (NSNull, numbers,
// nested objects). Before, a non-dictionary attribute raised and a non-string value was returned as is.
- (NSString*) value:(NSDictionary*) item tag:(NSString*) tag
{
    NSDictionary *attr = sekhmetTyped( [sekhmetTyped( item, [NSDictionary class]) objectForKey: tag], [NSDictionary class]);
    NSArray *v = sekhmetTyped( [attr objectForKey: @"Value"], [NSArray class]);
    if( v.count == 0) return @"";
    id first = [v objectAtIndex: 0];
    if( [first isKindOfClass: [NSDictionary class]])   // PN: {"Alphabetic": "…"}
    {
        NSString *alpha = sekhmetTyped( [first objectForKey: @"Alphabetic"], [NSString class]);
        return alpha ? alpha : @"";
    }
    NSMutableArray *parts = [NSMutableArray array];
    for( id e in v)
    {
        if( [e isKindOfClass: [NSString class]]) [parts addObject: e];
        else if( [e isKindOfClass: [NSNumber class]]) [parts addObject: [e stringValue]];
    }
    return [parts componentsJoinedByString: @"/"];
}

- (NSString*) timeString:(NSString*) t // Build 67: DICOM TM "HHMMSS.ffffff" -> "HH:MM"
{
    if( t.length < 4) return t ? t : @"";
    return [NSString stringWithFormat: @"%@:%@", [t substringToIndex: 2], [t substringWithRange: NSMakeRange( 2, 2)]];
}

#pragma mark - Suche (QIDO-RS)

- (NSString*) periodDateString:(NSDate*) d // Paket R
{
    NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
    [f setDateFormat: @"yyyyMMdd"]; [f setLocale: [NSLocale localeWithLocaleIdentifier: @"en_US_POSIX"]];
    return [f stringFromDate: d];
}

- (IBAction) periodChanged:(id) sender // Paket R: Heute, Gestern, letzte 3/4 Tage, letzte Woche, letzter Monat
{
    [self applyPeriodAndSearch: YES];
}

// Paket AP: Zeitraum in die Datumsfelder schreiben. doSearch = NO beim Oeffnen des Fensters —
// das Fenster steht dann auf "Today", ohne ungefragt eine Abfrage an den Knoten zu schicken.
- (void) applyPeriodAndSearch:(BOOL) doSearch
{
    NSInteger i = [periodPopup indexOfSelectedItem];
    NSCalendar *cal = [NSCalendar currentCalendar];
    NSDate *today = [cal startOfDayForDate: [NSDate date]];
    NSDate *from = nil, *to = today;
    switch( i)
    {
        case 1: from = today; break;
        case 2: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -1 toDate: today options: 0]; to = from; break;
        case 3: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -1 toDate: today options: 0]; break;   // Paket CL: "Last 2 days" = gestern + heute
        case 4: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -2 toDate: today options: 0]; break;
        case 5: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -3 toDate: today options: 0]; break;
        case 6: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -7 toDate: today options: 0]; break;
        case 7: from = [cal dateByAddingUnit: NSCalendarUnitMonth value: -1 toDate: today options: 0]; break;
        default: break;
    }
    [dateFromField setStringValue: from ? [self periodDateString: from] : @""];
    [dateToField setStringValue: from ? [self periodDateString: to] : @""];
    if( from && doSearch) [self search: self];
}

- (IBAction) search:(id) sender
{
    [self searchAutomatically: NO];
}

// SekhVet Paket DN: automatic = started by the auto-refresh timer. Then the selection and the expanded studies of the
// list survive the refresh, and new results may be retrieved afterwards (autoRetrieveNew).
- (void) searchAutomatically:(BOOL) automatic
{
    NSDictionary *node = [[[self currentNode] copy] autorelease];   // SekhVet Paket CS: snapshot -- the results are bound to this node
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }
    if( [self mayUseNode: node] == NO) return;                      // SekhVet Paket CS: plain http to a public host, asked once

    // SekhVet Paket DN: institution filters -- the field (kept over a restart) and the list stored with the node
    NSString *institutionText = [[institutionField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    [[NSUserDefaults standardUserDefaults] setObject: institutionText forKey: SekhmetDICOMwebInstitutionTextKey];
    NSArray *fieldPatterns = [SekhmetDICOMweb institutionPatterns: institutionText];
    NSArray *listPatterns = [institutionFilterButton state] == NSControlStateValueOn ? [SekhmetDICOMweb institutionListForNode: node] : [NSArray array];
    NSMutableSet *selectedUIDs = [NSMutableSet set], *expandedUIDs = [NSMutableSet set], *previousUIDs = [NSMutableSet set];
    if( automatic && resultsNode && [[SekhmetDICOMweb accountForNode: resultsNode] isEqualToString: [SekhmetDICOMweb accountForNode: node]])
    {
        for( NSDictionary *r in results)
        {
            NSString *u = [r objectForKey: @"uid"];
            if( u == nil) continue;
            [previousUIDs addObject: u];
            if( [resultTable isItemExpanded: r]) [expandedUIDs addObject: u];
        }
        [[resultTable selectedRowIndexes] enumerateIndexesUsingBlock: ^(NSUInteger idx, BOOL *stop) {
            id item = [resultTable itemAtRow: idx];
            NSString *u = [item objectForKey: @"seriesUID"] ? nil : [item objectForKey: @"uid"];
            if( u) [selectedUIDs addObject: u];
        }];
    }

    NSMutableArray *params = [NSMutableArray array];
    NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *pid = [[idField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *from = [[dateFromField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *to = [[dateToField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *mod = [[[modalityField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] uppercaseString];
    // SekhVet Paket CS: URLQueryAllowedCharacterSet leaves & + = ; untouched -- a name like "A&B" or "Smith+Co"
    // split or altered the query. Every value is encoded, including dates and modality.
    NSMutableCharacterSet *allowed = [[[NSCharacterSet URLQueryAllowedCharacterSet] mutableCopy] autorelease];
    [allowed removeCharactersInString: @"&+=;#"];
    NSString* (^enc)(NSString*) = ^NSString* (NSString *v) {
        NSString *e = [v stringByAddingPercentEncodingWithAllowedCharacters: allowed];
        return e ? e : @"";
    };

    if( name.length) [params addObject: [NSString stringWithFormat: @"PatientName=%@", enc( [NSString stringWithFormat: @"*%@*", name])]];
    if( pid.length) [params addObject: [NSString stringWithFormat: @"PatientID=%@", enc( pid)]];
    if( from.length || to.length) [params addObject: [NSString stringWithFormat: @"StudyDate=%@-%@", enc( from), enc( to)]];
    if( mod.length) [params addObject: [NSString stringWithFormat: @"ModalitiesInStudy=%@", enc( mod)]];
    [params addObject: @"includefield=00201206,00201208,00080061,00080080"]; // Build 67: + InstitutionName
    [params addObject: [NSString stringWithFormat: @"limit=%d", SekhmetQidoStudyLimit]];

    NSString *url = [NSString stringWithFormat: @"%@/studies?%@", [node objectForKey: @"url"], [params componentsJoinedByString: @"&"]];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"application/dicom+json" node: node];

    [self setStatus: automatic ? NSLocalizedString( @"Auto-refresh: searching…", nil) : NSLocalizedString( @"Searching…", nil)];
    [progress setHidden: NO]; [progress startAnimation: nil];
    [searchButton setEnabled: NO];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        [progress stopAnimation: nil]; [progress setHidden: YES];
        [searchButton setEnabled: YES];
        @try   // SekhVet Paket CS: an exception in a session callback would terminate the app
        {
            NSInteger code = [response isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) response statusCode] : 0;
            if( error) { [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Error: %@", nil), error.localizedDescription]]; return; }
            // SekhVet Paket CS: another node was selected while the search ran -- this answer is not for the visible node
            NSDictionary *now = [self currentNode];
            if( now == nil || [[SekhmetDICOMweb accountForNode: now] isEqualToString: [SekhmetDICOMweb accountForNode: node]] == NO)
            {
                [self setStatus: NSLocalizedString( @"Node changed — search again", nil)];
                return;
            }
            if( code == 401) { [self setStatus: NSLocalizedString( @"401: user/password rejected (save the password below)", nil)]; return; }
            if( code != 200 && code != 204) { [self setStatus: [NSString stringWithFormat: @"HTTP %d", (int) code]]; return; }   // SekhVet Paket CS: an empty error answer is not "No results"

            id json = nil;
            if( code == 200 && data.length)
            {
                json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL];
                if( [json isKindOfClass: [NSArray class]] == NO) { [self setStatus: NSLocalizedString( @"Response is not DICOM JSON", nil)]; return; }
            }

            [resultsNode release]; resultsNode = [node retain];   // SekhVet Paket CS
            [quietTried removeAllObjects];
            [results removeAllObjects];
            hiddenByInstitution = 0;   // SekhVet Paket DN
            for( NSDictionary *item in json)
            {
                if( [item isKindOfClass: [NSDictionary class]] == NO) continue;
                NSString *studyUID = [self value: item tag: @"0020000D"];
                if( studyUID.length == 0) continue;
                // SekhVet Paket DN: institution field AND (if switched on) the node's list -- each matches by "contains"
                NSString *institution = [self value: item tag: @"00080080"];
                if( (fieldPatterns.count && [SekhmetDICOMweb institution: institution matchesAny: fieldPatterns] == NO)
                   || (listPatterns.count && [SekhmetDICOMweb institution: institution matchesAny: listPatterns] == NO))
                {
                    hiddenByInstitution++;
                    continue;
                }
                [results addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                     [self value: item tag: @"00100010"], @"Name",
                                     [self value: item tag: @"00100020"], @"ID",
                                     [self value: item tag: @"00080020"], @"Date",
                                     [self timeString: [self value: item tag: @"00080030"]], @"Time",       // Build 67
                                     [self value: item tag: @"00080080"], @"Institution",                   // Build 67
                                     [self value: item tag: @"00080061"], @"Modality",
                                     [self value: item tag: @"00081030"], @"Description",
                                     [self value: item tag: @"00201206"], @"Series",
                                     [self value: item tag: @"00201208"], @"Images",
                                     studyUID, @"uid",
                                     // NSOutlineView fuehrt ihre Items in einer hash-basierten Zuordnung, und
                                     // NSDictionary leitet seinen hash aus der ANZAHL der Eintraege ab. Wurde
                                     // beim Aufklappen "children"/"loading" nachtraeglich angelegt, sprang der
                                     // hash und die Outline fand die Zeile nicht mehr wieder: aufklappen ging,
                                     // einklappen nicht mehr (15.09.2026). Darum stehen alle spaeter belegten
                                     // Schluessel schon hier — danach wird nur noch der WERT getauscht.
                                     [NSMutableArray array], @"children",
                                     [NSNumber numberWithBool: NO], @"loaded",
                                     [NSNumber numberWithBool: NO], @"loading", nil]];
            }
            // SekhVet Paket DN: say how many the institution filters hid; an automatic refresh also says when and how many are new
            NSString *hiddenText = hiddenByInstitution ? [NSString stringWithFormat: NSLocalizedString( @" (%d hidden by the institution filter)", nil), hiddenByInstitution] : @"";
            NSString *autoText = @"";
            if( automatic)
            {
                NSDateFormatter *f = [[[NSDateFormatter alloc] init] autorelease];
                [f setDateFormat: @"HH:mm"];
                int fresh = 0;
                for( NSDictionary *r in results) if( previousUIDs.count && [previousUIDs containsObject: [r objectForKey: @"uid"]] == NO) fresh++;
                autoText = fresh ? [NSString stringWithFormat: NSLocalizedString( @"Auto-refresh %@, %d new: ", nil), [f stringFromDate: [NSDate date]], fresh]
                                 : [NSString stringWithFormat: NSLocalizedString( @"Auto-refresh %@: ", nil), [f stringFromDate: [NSDate date]]];
            }
            if( results.count == 0) { [resultTable reloadData]; [self setStatus: [NSString stringWithFormat: @"%@%@%@", autoText, NSLocalizedString( @"No results", nil), hiddenText]]; return; }
            [self annotateLocalStatus];   // Paket AM: was liegt schon in der eigenen Datenbank?
            [self sortResults];           // Paket BU: nach der Spalte, die der Benutzer gewaehlt hat (Vorgabe Datum, neueste zuerst)
            [resultTable reloadData];
            if( automatic)   // SekhVet Paket DN: expanded studies and the selection survive the refresh
            {
                NSMutableIndexSet *rows = [NSMutableIndexSet indexSet];
                for( NSMutableDictionary *r in [NSArray arrayWithArray: results])
                {
                    NSString *u = [r objectForKey: @"uid"];
                    if( [expandedUIDs containsObject: u]) [resultTable expandItem: r];   // loads the series again (outlineViewItemWillExpand:)
                    if( [selectedUIDs containsObject: u])
                    {
                        NSInteger row = [resultTable rowForItem: r];
                        if( row >= 0) [rows addIndex: row];
                    }
                }
                if( rows.count) [resultTable selectRowIndexes: rows byExtendingSelection: NO];
            }
            // Sekhmet (DD): bei voller Seite sagen, dass es mehr geben kann - vorher wurde still bei 300 abgeschnitten
            // (nach ThalesMMS/horos e948e313, dort mit Paging)
            NSUInteger answered = [json isKindOfClass: [NSArray class]] ? [json count] : 0;
            NSString *warning = [[(NSHTTPURLResponse*) response allHeaderFields] objectForKey: @"Warning"];
            if( answered >= SekhmetQidoStudyLimit || [warning rangeOfString: @"299"].location != NSNotFound)
                [self setStatus: [NSString stringWithFormat: @"%@%@%@", autoText, [NSString stringWithFormat: NSLocalizedString( @"%d studies — the node may have more: narrow the search (name, ID, date)", nil), (int) results.count], hiddenText]];
            else
                [self setStatus: [NSString stringWithFormat: @"%@%@%@", autoText, [NSString stringWithFormat: NSLocalizedString( @"%d studies", nil), (int) results.count], hiddenText]];
            if( automatic && [autoRetrieveButton state] == NSControlStateValueOn) [self autoRetrieveNew];   // SekhVet Paket DN
        }
        @catch (NSException *e)
        {
            NSLog( @"SekhVet DICOMweb: search answer raised %@", e.name);
            [resultTable reloadData];
            [self setStatus: NSLocalizedString( @"Error: the answer of the node could not be read", nil)];
        }
    }];
    [task resume];
}

#pragma mark - Automatische Aktualisierung (SekhVet Paket DN)

// Wunsch 04.10.2026: wie OsiriX' "Autom. Suchen/Anfordern" -- die Suche mit den aktuellen Feldern alle
// 1-30 Minuten wiederholen (auch bei geschlossenem Fenster, ueber einen Neustart hinweg) und neue Treffer auf Wunsch
// selbst holen. Die Felder Name/ID/Modalitaet gelten, wie sie im Fenster stehen; nach einem Neustart sind sie leer,
// Zeitraum "Today", Institution und Knoten wie zuletzt.

+ (void) startAutoRefreshIfConfigured
{
    if( [[NSUserDefaults standardUserDefaults] integerForKey: SekhmetDICOMwebAutoMinutesKey] > 0)
        [SekhmetDICOMweb shared];   // init -> restoreAutoSettings starts the timer
}

- (void) restoreAutoSettings
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *account = [d stringForKey: SekhmetDICOMwebSelectedNodeKey];
    for( NSUInteger i = 0; account && i < nodes.count; i++)
        if( [[SekhmetDICOMweb accountForNode: [nodes objectAtIndex: i]] isEqualToString: account]) { [nodePopup selectItemAtIndex: i]; break; }
    [institutionField setStringValue: [d stringForKey: SekhmetDICOMwebInstitutionTextKey] ?: @""];
    [self updateInstitutionFilterButton];
    NSInteger minutes = [d integerForKey: SekhmetDICOMwebAutoMinutesKey];
    if( [autoPopup indexOfItemWithTag: minutes] < 0) minutes = 0;
    [autoPopup selectItemWithTag: minutes];
    [autoRetrieveButton setState: [d boolForKey: SekhmetDICOMwebAutoRetrieveKey] ? NSControlStateValueOn : NSControlStateValueOff];
    [self setupAutoTimer: minutes > 0];
}

- (IBAction) autoChanged:(id) sender
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger minutes = [[autoPopup selectedItem] tag];
    BOOL fetch = [autoRetrieveButton state] == NSControlStateValueOn;
    // retrieving by itself without a period would pull every study the node has -- refuse with a word instead
    if( fetch && minutes > 0 && [[dateFromField stringValue] length] == 0 && [[dateToField stringValue] length] == 0)
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"Automatic retrieve needs a period", nil)];
        [a setInformativeText: NSLocalizedString( @"Choose a period first (for example \"Today\" or \"Last 2 days\"). Without one, every study of the node that is not here would be retrieved.", nil)];
        [a runModal];
        [autoRetrieveButton setState: NSControlStateValueOff];
        fetch = NO;
    }
    [d setInteger: minutes forKey: SekhmetDICOMwebAutoMinutesKey];
    [d setBool: fetch forKey: SekhmetDICOMwebAutoRetrieveKey];
    NSDictionary *n = [self currentNode];
    if( n) [d setObject: [SekhmetDICOMweb accountForNode: n] forKey: SekhmetDICOMwebSelectedNodeKey];
    [self setupAutoTimer: sender == autoPopup && minutes > 0];   // switched on: first refresh right away
    if( minutes == 0) [self setStatus: NSLocalizedString( @"Auto-refresh off", nil)];
}

- (void) setupAutoTimer:(BOOL) refreshSoon
{
    [autoTimer invalidate]; [autoTimer release]; autoTimer = nil;
    NSInteger minutes = [[autoPopup selectedItem] tag];
    if( minutes <= 0) return;
    autoTimer = [[NSTimer scheduledTimerWithTimeInterval: minutes * 60.0 target: self selector: @selector(autoTimerFired:) userInfo: nil repeats: YES] retain];
    [autoTimer setTolerance: 5];
    if( refreshSoon) [self performSelector: @selector(autoTimerFired:) withObject: nil afterDelay: 2];
}

- (void) autoTimerFired:(NSTimer*) t
{
    if( [[autoPopup selectedItem] tag] <= 0) return;
    if( [searchButton isEnabled] == NO) return;               // a search is still running
    if( [[self window] attachedSheet]) return;
    if( [periodPopup indexOfSelectedItem] > 0) [self applyPeriodAndSearch: NO];   // "Today" moves on at midnight
    [self searchAutomatically: YES];
}

// After an automatic refresh: every study of the (filtered) list that is not completely here is retrieved -- once per
// session, and again only when the node has more images of it than at the last automatic retrieve (still arriving).
- (void) autoRetrieveNew
{
    if( resultsNode == nil) return;
    if( [[dateFromField stringValue] length] == 0 && [[dateToField stringValue] length] == 0)
    {
        [self setStatus: [[statusField stringValue] stringByAppendingString: NSLocalizedString( @" — automatic retrieve needs a period", nil)]];
        return;
    }
    NSDictionary *node = [[resultsNode retain] autorelease];
    NSMutableArray *jobs = [NSMutableArray array];
    int partial = 0;
    for( NSMutableDictionary *r in [NSArray arrayWithArray: results])
    {
        NSString *uid = [r objectForKey: @"uid"];
        if( uid.length == 0) continue;
        id f = [r objectForKey: @"localFraction"];
        int remote = [[r objectForKey: @"Images"] intValue];
        int have = [[[r objectForKey: @"local"] objectForKey: @"images"] intValue];
        float frac = [f isKindOfClass: [NSNumber class]] ? [f floatValue] : (have > 0 ? 1.0f : 0.0f);   // NSNull = node gave no image count
        if( frac >= 1.0f) continue;
        NSNumber *done = [autoRetrieved objectForKey: uid];
        if( done && remote <= [done intValue]) continue;
        [autoRetrieved setObject: [NSNumber numberWithInt: remote] forKey: uid];
        if( frac > 0)   // part is here: only the missing series (series list first, if not loaded yet)
        {
            if( [[r objectForKey: @"loaded"] boolValue]) [jobs addObjectsFromArray: [self missingSeriesJobsForStudy: r]];
            else
            {
                if( retrieveAfterLoad == nil) retrieveAfterLoad = [[NSMutableSet alloc] init];
                [retrieveAfterLoad addObject: uid];
                [self loadSeriesForStudy: r];
            }
            partial++;
        }
        else [jobs addObject: uid];
    }
    if( jobs.count == 0 && partial == 0) return;
    BOOL running = (retrieveStudyUID != nil || retrieveQueue.count > 0);
    int added = [self enqueueJobs: jobs node: node];
    NSLog( @"SekhVet DICOMweb: auto-retrieve %d jobs (%d partly here)", added, partial);
    if( running == NO && retrieveQueue.count) { filesWritten = 0; failedJobs = 0; [self retrieveNextStudy]; }
}

#pragma mark - Was liegt schon hier? (Paket AM)

// Bestand der eigenen Datenbank zu einer Studie: je SeriesInstanceUID die Zahl der lokalen Bilder.
// Horos teilt eine PACS-Serie beim Import mitunter auf mehrere Serien auf (Doppelpositionen, 4D) — die Bildzahlen
// gleicher UID werden darum summiert. In Horos traegt seriesDICOMUID die echte SeriesInstanceUID
// (seriesInstanceUID bekommt bei der Trennung Zusaetze), siehe BrowserController.m:7675.
// SekhVet Paket BQ: Horos' Localizer-Sammelserie verliert die SeriesInstanceUID ihrer Bilder; im Dateikopf steht sie noch.
// Wenige Bilder je Studie, Ergebnis je Pfad gemerkt -- so bekommen Topogramme eine echte Kugel statt "? localizer".
+ (NSString*) seriesUIDOfFile:(NSString*) path
{
    static NSMutableDictionary *cache = nil;
    if( cache == nil) cache = [[NSMutableDictionary alloc] init];
    if( path.length == 0) return nil;
    NSString *uid = [cache objectForKey: path];
    if( uid) return uid.length ? uid : nil;
    @try
    {
        DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
        uid = [o attributeValueWithName: @"SeriesInstanceUID"];
    }
    @catch (NSException *e) { uid = nil; }
    if( cache.count > 5000) [cache removeAllObjects];
    [cache setObject: uid.length ? uid : @"" forKey: path];
    return uid.length ? uid : nil;
}

+ (NSDictionary*) localStatusForStudyUID:(NSString*) studyUID
{
    NSArray *studies = nil;
    if( studyUID.length)
    {
        @try
        {
            DicomDatabase *db = [DicomDatabase activeLocalDatabase];
            studies = [db objectsForEntity: [db studyEntity] predicate: [NSPredicate predicateWithFormat: @"studyInstanceUID == %@", studyUID]];
        }
        @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: reading local studies: %@", e.name); studies = nil; }
    }
    return [self localStatusForStudies: studies];
}

// SekhVet Paket CS: the counting, separated from the fetch -- annotateLocalStatus fetches the local
// studies of ALL results in one go instead of one Core Data fetch per result row.
+ (NSDictionary*) localStatusForStudies:(NSArray*) studies
{
    NSMutableDictionary *series = [NSMutableDictionary dictionary];
    int images = 0, localizer = 0;
    if( studies.count)
    {
        @try
        {
            for( DicomStudy *st in studies)
            {
                for( DicomSeries *se in [[st valueForKey: @"series"] allObjects])
                {
                    NSString *uid = [se valueForKey: @"seriesDICOMUID"];
                    if( uid.length == 0) continue;
                    // numberOfImages NICHT roh lesen: bei Multiframe-Serien (US-Cine-Loops) legt Horos
                    // dort den NEGIERTEN Zaehler ab ("There are frames!", DicomSeries.m:600). Roh summiert
                    // wurde der Bestand negativ, localFractionForStudy: sah <= 0 und malte trotz vollstaendig
                    // geholter Studie einen leeren Kreis (15.09.2026 an drei US-Studien gesehen).
                    // noFiles ist Horos' eigener Zugriff und dreht das Vorzeichen zurueck.
                    int n = [[se valueForKey: @"noFiles"] intValue];
                    images += n;
                    // Horos fasst Localizer/Topogramme mehrerer Serien beim Import zu EINER Serie zusammen und gibt ihr
                    // eine eigene UID ("LOCALIZER" + StudyInstanceUID). Deren Bilder lassen sich keiner PACS-Serie mehr
                    // zuordnen -- solche Serien zeigen darum "?" statt "fehlt" (13.09.2026 an einer CT-Studie gesehen).
                    if( [uid hasPrefix: @"LOCALIZER"])
                    {
                        int resolved = 0;   // SekhVet Paket BQ: je Bild die echte Serie aus dem Dateikopf
                        for( DicomImage *im in [[se valueForKey: @"images"] allObjects])
                        {
                            NSString *real = [self seriesUIDOfFile: [im valueForKey: @"completePath"]];
                            if( real.length == 0) continue;
                            [series setObject: [NSNumber numberWithInt: 1 + [[series objectForKey: real] intValue]] forKey: real];
                            resolved++;
                        }
                        localizer += MAX( 0, n - resolved);   // nur der nicht lesbare Rest bleibt "?"
                        continue;
                    }
                    [series setObject: [NSNumber numberWithInt: n + [[series objectForKey: uid] intValue]] forKey: uid];
                }
            }
        }
        @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: reading local studies: %@", e.name); }
    }
    return [NSDictionary dictionaryWithObjectsAndKeys: series, @"series", [NSNumber numberWithInt: images], @"images",
            [NSNumber numberWithInt: localizer], @"localizer", nil];
}

+ (BOOL) isReportModality:(NSString*) mod
{
    // exakter Vergleich, kein Teilstring: "RTSTRUCT" enthaelt "CT"
    return mod.length && [[NSArray arrayWithObjects: @"SR", @"PR", @"KO", @"DOC", @"SEG", @"RTSTRUCT", nil] containsObject: mod];
}

// SekhVet Paket BS: Soll und Ist einer Studie. Ist die Serienliste geladen, zaehlen nur Bildserien -- Berichte (SR, PR, KO ...)
// legt Horos nicht als Serie an; mit ihnen im Soll blieb eine vollstaendig geholte Studie fuer immer orange (gesehen 19.09.2026: 3391 von 3393).
- (void) countsForStudy:(NSDictionary*) r have:(int*) have want:(int*) want
{
    NSDictionary *local = [r objectForKey: @"local"];
    *have = [[local objectForKey: @"images"] intValue];
    *want = [[r objectForKey: @"Images"] intValue];
    NSArray *kids = [r objectForKey: @"children"];
    if( [[r objectForKey: @"loaded"] boolValue] == NO || kids.count == 0) return;
    int h = 0, w = 0;
    for( NSDictionary *s in kids)
    {
        NSNumber *n = [[local objectForKey: @"series"] objectForKey: [s objectForKey: @"seriesUID"]];
        if( n == nil && [SekhmetDICOMweb isReportModality: [s objectForKey: @"Modality"]]) continue;
        int sw = [[s objectForKey: @"Images"] intValue];
        w += sw;
        h += sw > 0 ? MIN( [n intValue], sw) : [n intValue];
    }
    h += [[local objectForKey: @"localizer"] intValue];   // nicht zuordenbarer Rest der Sammelserie
    *have = MIN( h, w); *want = w;
}

- (NSString*) localTextForStudy:(NSDictionary*) r
{
    int limages, rimages;
    [self countsForStudy: r have: &limages want: &rimages];
    if( limages == 0) return @"";
    if( rimages == 0 || limages >= rimages) return NSLocalizedString( @"✓ complete", nil);
    // Serienzahlen sind nicht vergleichbar (Horos buendelt Localizer, trennt Doppelpositionen) -- Bilder sind das Mass
    return [NSString stringWithFormat: NSLocalizedString( @"partial %d/%d images", nil), limages, rimages];
}

- (NSString*) localTextForSeries:(NSDictionary*) s inStudy:(NSDictionary*) r
{
    NSNumber *have = [[[r objectForKey: @"local"] objectForKey: @"series"] objectForKey: [s objectForKey: @"seriesUID"]];
    if( have == nil)
    {
        // Kandidat fuer Horos' Localizer-Sammelserie: Bildserie (kein Bericht) mit hoechstens so vielen Bildern,
        // wie die lokale Sammelserie hat. Dann steht "?" statt "fehlt" -- die Zuordnung ist ueber die UID nicht moeglich.
        int bundle = [[[r objectForKey: @"local"] objectForKey: @"localizer"] intValue];
        NSString *mod = [s objectForKey: @"Modality"];
        // exakter Vergleich, kein Teilstring: "RTSTRUCT" enthaelt "CT"
        BOOL report = [SekhmetDICOMweb isReportModality: mod];
        if( report) return NSLocalizedString( @"report — not in the database", nil);   // SekhVet Paket BS
        if( bundle > 0 && report == NO && [[s objectForKey: @"Images"] intValue] <= bundle) return NSLocalizedString( @"? localizer", nil);
        return @"";
    }
    int n = [have intValue], want = [[s objectForKey: @"Images"] intValue];
    if( want == 0 || n >= want) return NSLocalizedString( @"✓ here", nil);
    return [NSString stringWithFormat: NSLocalizedString( @"partial %d/%d", nil), n, want];
}

// Paket AO: derselbe Bestand als Zahl 0…1 fuer die Kugel. 1.0 = alles hier (gruen),
// dazwischen = orange teilgefuellt, 0.0 = leerer Kreis, nil = nicht beurteilbar (keine Kugel).
- (NSNumber*) localFractionForStudy:(NSDictionary*) r
{
    int limages, rimages;
    [self countsForStudy: r have: &limages want: &rimages];
    if( limages <= 0) return [NSNumber numberWithFloat: 0.0];
    if( rimages <= 0) return [NSNumber numberWithFloat: 1.0];   // PACS nennt keine Bildzahl -> was hier liegt, gilt als alles
    float f = (float) limages / (float) rimages;
    return [NSNumber numberWithFloat: f > 1.0 ? 1.0 : f];
}

- (NSNumber*) localFractionForSeries:(NSDictionary*) s inStudy:(NSDictionary*) r
{
    NSNumber *have = [[[r objectForKey: @"local"] objectForKey: @"series"] objectForKey: [s objectForKey: @"seriesUID"]];
    if( have == nil)
    {
        // "? localizer": die Bilder stecken in Horos' Sammelserie, eine Zuordnung ist unmoeglich -> keine Kugel
        if( [[self localTextForSeries: s inStudy: r] isEqualToString: NSLocalizedString( @"? localizer", nil)]) return nil;
        if( [SekhmetDICOMweb isReportModality: [s objectForKey: @"Modality"]]) return nil;   // SekhVet Paket BS: Bericht, keine Kugel
        return [NSNumber numberWithFloat: 0.0];
    }
    int want = [[s objectForKey: @"Images"] intValue];
    if( want <= 0) return [NSNumber numberWithFloat: 1.0];
    float f = (float) [have intValue] / (float) want;
    return [NSNumber numberWithFloat: f > 1.0 ? 1.0 : f];
}

- (NSString*) localTipWithHave:(int) have want:(int) want
{
    if( want <= 0) return [NSString stringWithFormat: NSLocalizedString( @"%d images here (node gives no count)", nil), have];
    return [NSString stringWithFormat: NSLocalizedString( @"%d of %d images here (%d %%)", nil), have, want, (int) (100.0 * have / want + 0.5)];
}

// Text und Kugel einer Serienzeile in einem Zug — beide lesen denselben Bestand
- (void) annotateSeries:(NSMutableDictionary*) s inStudy:(NSDictionary*) r
{
    [s setObject: [self localTextForSeries: s inStudy: r] forKey: @"Local"];
    NSNumber *f = [self localFractionForSeries: s inStudy: r];
    // NSNull statt removeObjectForKey: — auch das Entfernen aendert die Eintragsanzahl und damit den hash
    [s setObject: f ? (id) f : (id) [NSNull null] forKey: @"localFraction"];
    NSNumber *have = [[[r objectForKey: @"local"] objectForKey: @"series"] objectForKey: [s objectForKey: @"seriesUID"]];
    [s setObject: [self localTipWithHave: [have intValue] want: [[s objectForKey: @"Images"] intValue]] forKey: @"localTip"];
}

- (float) legendIn:(NSView*) cv x:(float) x y:(float) y percentage:(float) p text:(NSString*) t
{
    NSImageView *iv = [[[NSImageView alloc] initWithFrame: NSMakeRect( x, y + 4, 14, 14)] autorelease];
    [iv setImage: [NSImage pieChartImageWithPercentage: p]];
    [iv setAutoresizingMask: NSViewMinYMargin];
    [cv addSubview: iv];
    NSTextField *l = [self label: t frame: NSMakeRect( x + 18, y + 2, 90, 20)];
    [l setAutoresizingMask: NSViewMinYMargin];
    [cv addSubview: l];
    return x + 118;
}

- (void) annotateLocalStatus
{
    // SekhVet Paket CS: this runs on the main thread after every search and retrieve. It used to do one
    // Core Data fetch per result (up to 300); now ONE fetch covers all results.
    NSMutableDictionary *localByUID = [NSMutableDictionary dictionary];   // StudyInstanceUID -> NSMutableArray of DicomStudy
    if( results.count)
    {
        @try
        {
            DicomDatabase *db = [DicomDatabase activeLocalDatabase];
            NSArray *uids = [results valueForKey: @"uid"];
            for( DicomStudy *st in [db objectsForEntity: [db studyEntity] predicate: [NSPredicate predicateWithFormat: @"studyInstanceUID IN %@", uids]])
            {
                NSString *u = [st valueForKey: @"studyInstanceUID"];
                if( u.length == 0) continue;
                NSMutableArray *list = [localByUID objectForKey: u];
                if( list == nil) { list = [NSMutableArray array]; [localByUID setObject: list forKey: u]; }
                [list addObject: st];
            }
        }
        @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: reading local studies: %@", e.name); }
    }

    int quiet = 0;
    for( NSMutableDictionary *r in results)
    {
        [r setObject: [SekhmetDICOMweb localStatusForStudies: [localByUID objectForKey: [r objectForKey: @"uid"]]] forKey: @"local"];
        [r setObject: [self localTextForStudy: r] forKey: @"Local"];
        [r setObject: [self localFractionForStudy: r] forKey: @"localFraction"];   // Paket AO
        int have, want;
        [self countsForStudy: r have: &have want: &want];
        [r setObject: [self localTipWithHave: have want: want] forKey: @"localTip"];
        for( NSMutableDictionary *s in [r objectForKey: @"children"])
            [self annotateSeries: s inStudy: r];
        // SekhVet Paket BS: fast vollstaendig, Serienliste unbekannt -> still nachladen; vielleicht fehlen nur Berichte
        // SekhVet Paket CS: at most once per study and result list -- a failing series query is not repeated with every refresh
        if( have > 0 && have < want && [[r objectForKey: @"loaded"] boolValue] == NO && [[r objectForKey: @"loading"] boolValue] == NO && quiet < 10
           && [quietTried containsObject: [r objectForKey: @"uid"]] == NO)
        {
            if( quietLoads == nil) quietLoads = [[NSMutableSet alloc] init];
            if( quietTried == nil) quietTried = [[NSMutableSet alloc] init];
            [quietLoads addObject: [r objectForKey: @"uid"]];
            [quietTried addObject: [r objectForKey: @"uid"]];
            [self loadSeriesForStudy: r];
            quiet++;
        }
    }
}

- (void) refreshLocalStatus   // nach einem Abruf: Horos importiert INCOMING im Hintergrund, darum zeitversetzt nachzaehlen
{
    [self annotateLocalStatus];
    [resultTable reloadData];
}

// SekhVet Paket CS: a series list that could not be loaded must not leave its study marked "retrieve the
// missing series once loaded" -- expanding that study later started a retrieve nobody asked for.
- (void) seriesLoadFailedForStudy:(NSDictionary*) study status:(NSString*) status
{
    NSString *uid = [study objectForKey: @"uid"];
    BOOL wanted = uid && [retrieveAfterLoad containsObject: uid];
    if( uid) { [retrieveAfterLoad removeObject: uid]; [quietLoads removeObject: uid]; }
    [self setStatus: wanted ? [status stringByAppendingString: NSLocalizedString( @" — nothing retrieved for this study", nil)] : status];
}

// Serien einer Studie beim Aufklappen vom Knoten holen (QIDO-RS /studies/<uid>/series)
- (void) loadSeriesForStudy:(NSMutableDictionary*) study
{
    if( study == nil || [[study objectForKey: @"loaded"] boolValue] || [[study objectForKey: @"loading"] boolValue]) return;
    // SekhVet Paket CS: the node the results came from, not whatever the popup shows at this moment
    NSDictionary *node = resultsNode ? [[resultsNode retain] autorelease] : [[[self currentNode] copy] autorelease];
    if( node == nil) { [self seriesLoadFailedForStudy: study status: NSLocalizedString( @"No node", nil)]; return; }

    [study setObject: [NSNumber numberWithBool: YES] forKey: @"loading"];
    NSString *url = [NSString stringWithFormat: @"%@/studies/%@/series?includefield=00200011,0008103E,00080060,00201209&limit=500",
                     [node objectForKey: @"url"], sekhmetPathEscape( [study objectForKey: @"uid"])];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"application/dicom+json" node: node];
    [self setStatus: NSLocalizedString( @"Loading series…", nil)];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        [study setObject: [NSNumber numberWithBool: NO] forKey: @"loading"];   // nicht entfernen: aendert den hash
        @try   // SekhVet Paket CS
        {
            NSInteger code = [response isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) response statusCode] : 0;
            if( error) { [self seriesLoadFailedForStudy: study status: [NSString stringWithFormat: NSLocalizedString( @"Series: %@", nil), error.localizedDescription]]; return; }
            id json = (data.length && code == 200) ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
            if( code == 204 || (code == 200 && data.length == 0)) json = [NSArray array];   // Sekhmet (DD): 204 = keine Serien, kein Fehler
            if( [json isKindOfClass: [NSArray class]] == NO)
            {
                [self seriesLoadFailedForStudy: study status: [NSString stringWithFormat: NSLocalizedString( @"Series: HTTP %d", nil), (int) code]];
                return;
            }
            NSMutableArray *kids = [NSMutableArray array];
            for( NSDictionary *item in json)
            {
                if( [item isKindOfClass: [NSDictionary class]] == NO) continue;
                NSString *suid = [self value: item tag: @"0020000E"];
                if( suid.length == 0) continue;
                NSString *number = [self value: item tag: @"00200011"];
                NSMutableDictionary *s = [NSMutableDictionary dictionaryWithObjectsAndKeys:
                                          number.length ? [NSString stringWithFormat: NSLocalizedString( @"Series %@", nil), number] : NSLocalizedString( @"Series", nil), @"Name",
                                          [self value: item tag: @"00080060"], @"Modality",
                                          [self value: item tag: @"0008103E"], @"Description",
                                          [self value: item tag: @"00201209"], @"Images",
                                          number, @"SeriesNumber",
                                          suid, @"seriesUID",
                                          [study objectForKey: @"uid"], @"studyUID", nil];
                [self annotateSeries: s inStudy: study];   // Paket AO: Text, Kugel und Tooltip
                [kids addObject: s];
            }
            [kids sortUsingComparator: ^NSComparisonResult( id a, id b) {
                return [[a objectForKey: @"SeriesNumber"] compare: [b objectForKey: @"SeriesNumber"] options: NSNumericSearch];
            }];
            [study setObject: kids forKey: @"children"];        // Schluessel besteht bereits, nur der Wert wechselt
            [study setObject: [NSNumber numberWithBool: YES] forKey: @"loaded"];
            // SekhVet Paket BS: mit der Serienliste aendert sich das Soll der Studienzeile (Berichte fallen heraus)
            [study setObject: [self localTextForStudy: study] forKey: @"Local"];
            [study setObject: [self localFractionForStudy: study] forKey: @"localFraction"];
            int have, want; [self countsForStudy: study have: &have want: &want];
            [study setObject: [self localTipWithHave: have want: want] forKey: @"localTip"];
            BOOL wasQuiet = [quietLoads containsObject: [study objectForKey: @"uid"]];
            [quietLoads removeObject: [study objectForKey: @"uid"]];
            if( [results indexOfObjectIdenticalTo: study] != NSNotFound)   // SekhVet Paket CS: the list may have been replaced meanwhile
            {
                [resultTable reloadItem: study reloadChildren: YES];
                if( wasQuiet == NO) [resultTable expandItem: study];
            }
            [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"%d series", nil), (int) kids.count]];
            [self retrieveMissingAfterLoad: study node: node];   // SekhVet Paket BS
        }
        @catch (NSException *e)
        {
            NSLog( @"SekhVet DICOMweb: series answer raised %@", e.name);
            [self seriesLoadFailedForStudy: study status: NSLocalizedString( @"Series: the answer of the node could not be read", nil)];
        }
    }];
    [task resume];
}

#pragma mark - Abruf (WADO-RS)

- (IBAction) retrieve:(id) sender
{
    NSIndexSet *sel = [resultTable selectedRowIndexes];
    if( sel.count == 0) { [self setStatus: NSLocalizedString( @"No study selected", nil)]; return; }
    // SekhVet Paket CS: the rows come from resultsNode; every job is bound to that node
    NSDictionary *node = resultsNode ? [[resultsNode retain] autorelease] : [[[self currentNode] copy] autorelease];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }
    if( [self mayUseNode: node] == NO) return;

    // Paket AM: markiert sein koennen Studien- und Serienzeilen. Auftrag ist "<StudyUID>" oder "<StudyUID>|<SeriesUID>";
    // ist die ganze Studie markiert, fallen ihre einzeln markierten Serien weg.
    // SekhVet Paket BS: liegt von der Auswahl schon etwas hier (gruene oder orange Kugel), fragt ein Dialog:
    // nur das Fehlende holen (Vorgabe), alles noch einmal, oder abbrechen. Alt-Klick auf Retrieve = alles, ohne Frage.
    [self annotateLocalStatus];
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *wholeStudies = [NSMutableSet set];
    [sel enumerateIndexesUsingBlock: ^(NSUInteger idx, BOOL *stop) {
        id item = [resultTable itemAtRow: idx];
        if( item == nil) return;
        [items addObject: item];
        if( [item objectForKey: @"seriesUID"] == nil && [item objectForKey: @"uid"]) [wholeStudies addObject: [item objectForKey: @"uid"]];
    }];
    int here = 0;
    for( NSDictionary *item in items)
    {
        id f = [item objectForKey: @"localFraction"];
        if( [f isKindOfClass: [NSNumber class]] && [f floatValue] > 0) here++;
    }
    BOOL onlyMissing = NO;
    if( here > 0 && ([[NSApp currentEvent] modifierFlags] & NSEventModifierFlagOption) == 0)
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: here == 1 && items.count == 1 ? NSLocalizedString( @"This selection is already in the local database, completely or in part.", nil)
                                                         : [NSString stringWithFormat: NSLocalizedString( @"%d of the %d selected items are already in the local database, completely or in part.", nil), here, (int) items.count]];
        [a setInformativeText: NSLocalizedString( @"“Only missing parts” skips everything marked green and retrieves only the series that are not complete here.", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Only missing parts", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Download everything again", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
        NSModalResponse r = [a runModal];
        if( r == NSAlertThirdButtonReturn) return;
        onlyMissing = (r == NSAlertFirstButtonReturn);
    }

    NSMutableArray *queue = [NSMutableArray array];
    int waiting = 0;
    for( NSMutableDictionary *item in items)
    {
        NSString *seriesUID = [item objectForKey: @"seriesUID"];
        id f = [item objectForKey: @"localFraction"];
        float frac = [f isKindOfClass: [NSNumber class]] ? [f floatValue] : 0;
        NSMutableArray *jobs = [NSMutableArray array];
        if( seriesUID)
        {
            if( [wholeStudies containsObject: [item objectForKey: @"studyUID"]]) continue;
            if( onlyMissing && frac >= 1.0f) continue;
            [jobs addObject: [NSString stringWithFormat: @"%@|%@", [item objectForKey: @"studyUID"], seriesUID]];
        }
        else if( [item objectForKey: @"uid"])
        {
            if( onlyMissing && frac >= 1.0f) continue;
            if( onlyMissing && frac > 0)
            {
                if( [[item objectForKey: @"loaded"] boolValue]) [jobs addObjectsFromArray: [self missingSeriesJobsForStudy: item]];
                else
                {
                    // Serienliste fehlt noch: erst holen, die fehlenden Serien reiht loadSeriesForStudy: danach ein
                    if( retrieveAfterLoad == nil) retrieveAfterLoad = [[NSMutableSet alloc] init];
                    [retrieveAfterLoad addObject: [item objectForKey: @"uid"]];
                    [self loadSeriesForStudy: item];
                    waiting++;
                }
            }
            else [jobs addObject: [item objectForKey: @"uid"]];
        }
        for( NSString *job in jobs) if( [queue containsObject: job] == NO) [queue addObject: job];
    }
    if( queue.count == 0)
    {
        if( waiting == 0) [self setStatus: NSLocalizedString( @"Everything selected is already here — nothing to retrieve", nil)];
        return;
    }
    // SekhVet Paket BU: laeuft schon ein Abruf, kommen die neuen Auftraege hinten an die Warteschlange (ohne Doppel, ohne den laufenden)
    // SekhVet Paket CS: the queue is an ivar of {job, node}; a non-empty queue means a retrieve is running or about to start
    BOOL running = (retrieveStudyUID != nil || retrieveQueue.count > 0);
    int added = [self enqueueJobs: queue node: node];
    if( running)
    {
        [self setStatus: added ? [NSString stringWithFormat: NSLocalizedString( @"Added to the queue: %d — %d waiting after the current retrieve", nil), added, (int) retrieveQueue.count]
                               : NSLocalizedString( @"Already in the queue", nil)];
        return;
    }
    filesWritten = 0; failedJobs = 0;
    [self retrieveNextStudy];
}

// SekhVet Paket CS: append jobs for one node; skips what is already queued or running for that node. Returns the number added.
- (int) enqueueJobs:(NSArray*) jobs node:(NSDictionary*) node
{
    int added = 0;
    NSString *account = [SekhmetDICOMweb accountForNode: node];
    for( NSString *job in jobs)
    {
        BOOL dup = retrieveStudyUID != nil && [job isEqualToString: retrieveJob] && retrieveNode && [account isEqualToString: [SekhmetDICOMweb accountForNode: retrieveNode]];
        for( NSDictionary *q in retrieveQueue)
            if( [[q objectForKey: @"job"] isEqualToString: job] && [[SekhmetDICOMweb accountForNode: [q objectForKey: @"node"]] isEqualToString: account]) { dup = YES; break; }
        if( dup) continue;
        [retrieveQueue addObject: [NSDictionary dictionaryWithObjectsAndKeys: job, @"job", node, @"node", nil]];
        added++;
    }
    return added;
}

// SekhVet Paket BS: Auftraege "<StudyUID>|<SeriesUID>" fuer alle Serien einer aufgeklappten Studie, die hier nicht vollstaendig liegen
- (NSArray*) missingSeriesJobsForStudy:(NSDictionary*) study
{
    NSMutableArray *jobs = [NSMutableArray array];
    for( NSDictionary *k in [study objectForKey: @"children"])
    {
        id kf = [k objectForKey: @"localFraction"];
        if( [kf isKindOfClass: [NSNumber class]] && [kf floatValue] >= 1.0f) continue;
        if( [k objectForKey: @"seriesUID"]) [jobs addObject: [NSString stringWithFormat: @"%@|%@", [study objectForKey: @"uid"], [k objectForKey: @"seriesUID"]]];
    }
    return jobs;
}

- (void) retrieveMissingAfterLoad:(NSDictionary*) study node:(NSDictionary*) node
{
    NSString *uid = [study objectForKey: @"uid"];
    if( uid == nil || [retrieveAfterLoad containsObject: uid] == NO) return;
    [retrieveAfterLoad removeObject: uid];
    NSArray *jobs = [self missingSeriesJobsForStudy: study];
    if( jobs.count == 0) { [self setStatus: NSLocalizedString( @"Everything selected is already here — nothing to retrieve", nil)]; return; }
    // SekhVet Paket CS: only these jobs, bound to the node the series list came from (no merge with a stored queue)
    BOOL running = (retrieveStudyUID != nil || retrieveQueue.count > 0);
    [self enqueueJobs: jobs node: node];
    if( running == NO && retrieveQueue.count) { filesWritten = 0; failedJobs = 0; [self retrieveNextStudy]; }   // laeuft schon ein Abruf, nimmt er die Auftraege am Ende mit
}

- (void) retrieveNextStudy
{
    if( retrieveQueue.count == 0)
    {
        [retrieveStudyUID release]; retrieveStudyUID = nil;
        [retrieveJob release]; retrieveJob = nil;
        [retrieveNode release]; retrieveNode = nil;
        [progress stopAnimation: nil]; [progress setHidden: YES];
        [retrieveButton setEnabled: YES];
        [stopButton setEnabled: NO];
        NSString *done = [NSString stringWithFormat: NSLocalizedString( @"Done: %d files written to INCOMING — importing now", nil), filesWritten];
        if( failedJobs) done = [done stringByAppendingFormat: NSLocalizedString( @" (%d retrieves failed: %@)", nil), failedJobs, lastRetrieveError ?: @"?"];
        [self setStatus: done];
        // Paket AM: Horos importiert INCOMING im Hintergrund — Bestandsanzeige zweimal zeitversetzt nachziehen
        [self performSelector: @selector(refreshLocalStatus) withObject: nil afterDelay: 8];
        [self performSelector: @selector(refreshLocalStatus) withObject: nil afterDelay: 30];
        return;
    }
    NSDictionary *entry = [[[retrieveQueue objectAtIndex: 0] retain] autorelease];
    [retrieveQueue removeObjectAtIndex: 0];
    NSString *job = [entry objectForKey: @"job"];
    NSDictionary *node = [entry objectForKey: @"node"];   // SekhVet Paket CS: the node the job was created for
    NSArray *parts = [job componentsSeparatedByString: @"|"];   // Paket AM: "<StudyUID>" oder "<StudyUID>|<SeriesUID>"
    NSString *uid = [parts objectAtIndex: 0];
    NSString *seriesUID = parts.count > 1 ? [parts objectAtIndex: 1] : nil;

    [retrieveJob release]; retrieveJob = [job retain];   // Paket BU
    [retrieveNode release]; retrieveNode = [node retain];
    [stopButton setEnabled: YES];

    // SekhVet Paket CS: the node may have been removed or edited since the job was queued. The job then fails
    // like any other (the queue moves on and ends cleanly) -- before, the method just returned and every later
    // "Retrieve" only said "Added to the queue".
    BOOL known = NO;
    NSString *account = [SekhmetDICOMweb accountForNode: node];
    for( NSDictionary *n in nodes)
        if( [[SekhmetDICOMweb accountForNode: n] isEqualToString: account]) { known = YES; break; }
    if( node == nil || known == NO)
    {
        [self retrieveFailed: NSLocalizedString( @"Retrieve skipped: the node of this job was removed or changed", nil)];
        return;
    }

    [retrieveStudyUID release]; retrieveStudyUID = [uid retain];
    [receivedData release]; receivedData = [[NSMutableData alloc] init];
    [retrieveBoundary release]; retrieveBoundary = nil;
    expectedLength = -1; receivedLength = 0;
    multipartStarted = NO; scanPos = 0;
    retrieveIncomplete = NO;
    // SekhVet Paket CS: seconds alone collided when two jobs started within the same second
    [retrieveStamp release]; retrieveStamp = [[NSString stringWithFormat: @"%.0f-%@", [NSDate timeIntervalSinceReferenceDate], [[[NSUUID UUID] UUIDString] substringToIndex: 8]] retain];

    NSString *url = seriesUID.length ? [NSString stringWithFormat: @"%@/studies/%@/series/%@", [node objectForKey: @"url"], sekhmetPathEscape( uid), sekhmetPathEscape( seriesUID)]
                                     : [NSString stringWithFormat: @"%@/studies/%@", [node objectForKey: @"url"], sekhmetPathEscape( uid)];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"multipart/related; type=\"application/dicom\"; transfer-syntax=*" node: node];

    [progress setIndeterminate: YES]; [progress setHidden: NO]; [progress startAnimation: nil];   // Paket BU: Retrieve bleibt bedienbar (haengt an)
    [self setStatus: seriesUID.length ? NSLocalizedString( @"Retrieving series…", nil) : NSLocalizedString( @"Retrieving…", nil)];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req];
    [retrieveTask release]; retrieveTask = [task retain];
    [task resume];
}

// SekhVet Paket CS: stop the running retrieve and drop everything still queued. Files already written to
// INCOMING are complete instances and stay; the instance in the buffer is discarded.
- (IBAction) stopRetrieve:(id) sender
{
    if( retrieveStudyUID == nil && retrieveQueue.count == 0) return;
    [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(retrieveNextStudy) object: nil];
    [retrieveQueue removeAllObjects];
    [retrieveAfterLoad removeAllObjects];
    NSURLSessionTask *t = [retrieveTask retain];
    [retrieveTask release]; retrieveTask = nil;   // late callbacks of the cancelled task no longer count
    [t cancel]; [t release];
    [receivedData release]; receivedData = nil;
    [retrieveStudyUID release]; retrieveStudyUID = nil;
    [retrieveJob release]; retrieveJob = nil;
    [retrieveNode release]; retrieveNode = nil;
    [progress stopAnimation: nil]; [progress setHidden: YES];
    [stopButton setEnabled: NO];
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Retrieve stopped — %d files already written to INCOMING are being imported", nil), filesWritten]];
    [self performSelector: @selector(refreshLocalStatus) withObject: nil afterDelay: 8];
}

// SekhVet Paket BU: ein fehlgeschlagener Auftrag haelt die Warteschlange nicht an; der naechste startet, die Fehler stehen am Ende im Status
- (void) retrieveFailed:(NSString*) message
{
    failedJobs++;
    [lastRetrieveError release]; lastRetrieveError = [message retain];
    [self setStatus: message];
    [retrieveTask release]; retrieveTask = nil;   // spaete Meldungen des abgebrochenen Tasks zaehlen nicht mehr
    [receivedData release]; receivedData = nil;
    [retrieveStudyUID release]; retrieveStudyUID = nil;
    [self performSelector: @selector(retrieveNextStudy) withObject: nil afterDelay: 0];
}

- (void) URLSession:(NSURLSession*) s dataTask:(NSURLSessionDataTask*) task didReceiveResponse:(NSURLResponse*) response completionHandler:(void (^)(NSURLSessionResponseDisposition)) completionHandler
{
    if( task != retrieveTask) { completionHandler( NSURLSessionResponseAllow); return; } // Suche laeuft ueber den Completion-Handler
    NSHTTPURLResponse *r = (NSHTTPURLResponse*) response;
    expectedLength = r.expectedContentLength;
    NSString *ct = [[r allHeaderFields] objectForKey: @"Content-Type"];
    NSRange b = [ct rangeOfString: @"boundary=" options: NSCaseInsensitiveSearch];
    if( b.location != NSNotFound)
    {
        NSString *bd = [ct substringFromIndex: b.location + b.length];
        NSRange semi = [bd rangeOfString: @";"];
        if( semi.location != NSNotFound) bd = [bd substringToIndex: semi.location];
        bd = [bd stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"\" "]];
        [retrieveBoundary release]; retrieveBoundary = [bd retain];
    }
    if( r.statusCode != 200)
    {
        completionHandler( NSURLSessionResponseCancel);
        [self retrieveFailed: [NSString stringWithFormat: NSLocalizedString( @"Retrieve: HTTP %d", nil), (int) r.statusCode]];
        return;
    }
    if( expectedLength > 0) { [progress setIndeterminate: NO]; [progress setMinValue: 0]; [progress setMaxValue: expectedLength]; [progress setDoubleValue: 0]; }
    completionHandler( NSURLSessionResponseAllow);
}

// SekhVet Paket CS: PS3.10 file = 128 bytes preamble + "DICM"
+ (BOOL) dataLooksLikeDICOM:(NSData*) d
{
    if( d.length < 132) return NO;
    char magic[ 4];
    [d getBytes: magic range: NSMakeRange( 128, 4)];
    return memcmp( magic, "DICM", 4) == 0;
}

- (void) URLSession:(NSURLSession*) s dataTask:(NSURLSessionDataTask*) task didReceiveData:(NSData*) data
{
    if( task != retrieveTask) return;
    [receivedData appendData: data];
    receivedLength += data.length;
    if( expectedLength > 0) [progress setDoubleValue: receivedLength];
    if( retrieveBoundary.length) filesWritten += [self drainMultipartFinal: NO];   // Stream: jede fertige Instanz sofort nach INCOMING

    // SekhVet Paket CS: the buffer is bounded. A body that is neither multipart nor a DICOM file (HTML or
    // JSON error page answered with 200) is refused after its first bytes instead of being collected in RAM.
    NSString *problem = nil;
    if( retrieveBoundary.length == 0 && receivedData.length >= 132 && [SekhmetDICOMweb dataLooksLikeDICOM: receivedData] == NO)
        problem = NSLocalizedString( @"Retrieve: the node did not answer with DICOM (wrong URL or an error page?)", nil);
    else if( receivedData.length > SekhmetWadoMaxBufferBytes)
        problem = NSLocalizedString( @"Retrieve: one instance is larger than 2 GB or the stream is malformed — stopped", nil);
    if( problem)
    {
        [task cancel];
        [self retrieveFailed: problem];
        return;
    }
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Retrieving… %.0f MB, %d files written", nil), receivedLength / 1048576., filesWritten]];
}

- (void) URLSession:(NSURLSession*) s task:(NSURLSessionTask*) task didCompleteWithError:(NSError*) error
{
    if( task != retrieveTask || retrieveStudyUID == nil) return; // Suche und STOW laufen ueber Completion-Handler

    if( error)
    {
        NSLog( @"SekhVet DICOMweb: WADO-RS error %@", error);
        [self retrieveFailed: [NSString stringWithFormat: NSLocalizedString( @"Retrieve error: %@", nil), error.localizedDescription]];
        return;
    }

    if( retrieveBoundary.length) filesWritten += [self drainMultipartFinal: YES];
    else if( receivedData.length)
    {
        // Kein Multipart: eine Datei (application/dicom)
        // SekhVet Paket CS: only if it IS a DICOM file; the name is unique per job and file
        NSString *incoming = [[DicomDatabase activeLocalDatabase] incomingDirPath];
        if( [SekhmetDICOMweb dataLooksLikeDICOM: receivedData] == NO) retrieveIncomplete = YES;
        else if( incoming && [receivedData writeToFile: [incoming stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVetWADO-%@-s%d.dcm", retrieveStamp, filesWritten]] atomically: YES]) filesWritten++;
        else retrieveIncomplete = YES;
    }
    [receivedData release]; receivedData = nil;
    NSLog( @"SekhVet DICOMweb: WADO-RS study %@ done, %d files so far%@", retrieveStudyUID, filesWritten, retrieveIncomplete ? @" (incomplete)" : @"");
    if( retrieveIncomplete)   // SekhVet Paket CS: counted as a failed job; what was complete is already in INCOMING
    {
        [self retrieveFailed: NSLocalizedString( @"Retrieve incomplete: the node sent data that is not DICOM, the stream ended early, or a file could not be written", nil)];
        return;
    }
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"%d files written…", nil), filesWritten]];
    [self retrieveNextStudy];
}

// Multipart-Strom abarbeiten: jede vollstaendige Instanz sofort nach INCOMING schreiben und aus dem Puffer entfernen.
// Der Puffer haelt so hoechstens eine Instanz statt der ganzen Studie. Liefert die Zahl der geschriebenen Dateien.
- (int) drainMultipartFinal:(BOOL) final
{
    NSString *incoming = [[DicomDatabase activeLocalDatabase] incomingDirPath];
    if( incoming == nil || receivedData == nil || retrieveBoundary.length == 0) return 0;

    NSData *delim = [[NSString stringWithFormat: @"--%@", retrieveBoundary] dataUsingEncoding: NSUTF8StringEncoding];
    NSData *crlf2 = [@"\r\n\r\n" dataUsingEncoding: NSUTF8StringEncoding];
    int count = 0;

    while( YES)
    {
        NSUInteger len = receivedData.length;

        if( multipartStarted == NO)
        {
            NSRange first = [receivedData rangeOfData: delim options: 0 range: NSMakeRange( 0, len)];
            if( first.location == NSNotFound)
            {
                if( len > delim.length) [receivedData replaceBytesInRange: NSMakeRange( 0, len - delim.length) withBytes: NULL length: 0]; // Praeambel weg, Ueberlappung behalten
                if( final && receivedLength > 0) retrieveIncomplete = YES;   // SekhVet Paket CS: a body without a single delimiter is not a multipart answer
                return count;
            }
            [receivedData replaceBytesInRange: NSMakeRange( 0, first.location + first.length) withBytes: NULL length: 0];
            multipartStarted = YES; scanPos = 0;
            continue;
        }

        // Puffer beginnt direkt hinter einem Delimiter: "--" = Ende, sonst CRLF + Teil-Header
        if( len < 2) return count;
        char c[ 2]; [receivedData getBytes: c range: NSMakeRange( 0, 2)];
        if( c[0] == '-' && c[1] == '-') { [receivedData setLength: 0]; return count; }

        NSRange hdrEnd = [receivedData rangeOfData: crlf2 options: 0 range: NSMakeRange( 0, len)];
        if( hdrEnd.location == NSNotFound)
        {
            if( final && len > 4) retrieveIncomplete = YES;   // SekhVet Paket CS: cut off inside a part header
            return count;
        }
        NSUInteger bodyStart = hdrEnd.location + hdrEnd.length;

        NSUInteger from = MAX( bodyStart, scanPos);
        if( from > len) from = len;
        NSRange next = [receivedData rangeOfData: delim options: 0 range: NSMakeRange( from, len - from)];
        BOOL truncated = NO;
        if( next.location == NSNotFound)
        {
            scanPos = (len > delim.length) ? len - delim.length : bodyStart;   // beim naechsten Datenblock nur den neuen Teil absuchen
            if( scanPos < bodyStart) scanPos = bodyStart;
            if( final == NO) return count;
            // Strom endete ohne schliessenden Delimiter.
            // SekhVet Paket CS: the rest is a complete last instance only if the announced Content-Length has
            // fully arrived; otherwise it was cut off and is NOT written as a (truncated) DICOM file.
            if( expectedLength <= 0 || receivedLength < expectedLength)
            {
                retrieveIncomplete = YES;
                [receivedData setLength: 0];
                return count;
            }
            next = NSMakeRange( len, 0); truncated = YES;
        }

        NSUInteger bodyEnd = next.location;
        if( bodyEnd >= bodyStart + 2)
        {
            char e[ 2]; [receivedData getBytes: e range: NSMakeRange( bodyEnd - 2, 2)];
            if( e[0] == '\r' && e[1] == '\n') bodyEnd -= 2;
        }
        if( bodyEnd > bodyStart)
        {
            NSData *part = [receivedData subdataWithRange: NSMakeRange( bodyStart, bodyEnd - bodyStart)];
            // SekhVet Paket CS: only parts that are DICOM -- declared as application/dicom or carrying the DICM
            // magic. An error text inside the multipart stream is not written into INCOMING as ".dcm".
            BOOL declared = NO;
            NSString *partHeader = [[[NSString alloc] initWithData: [receivedData subdataWithRange: NSMakeRange( 0, hdrEnd.location)] encoding: NSISOLatin1StringEncoding] autorelease];
            for( NSString *line in [[partHeader lowercaseString] componentsSeparatedByString: @"\r\n"])
            {
                if( [line hasPrefix: @"content-type:"] == NO) continue;
                NSString *type = [[line substringFromIndex: 13] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
                declared = [type isEqualToString: @"application/dicom"] || [type hasPrefix: @"application/dicom;"];
            }
            if( declared == NO && [SekhmetDICOMweb dataLooksLikeDICOM: part] == NO) retrieveIncomplete = YES;
            else
            {
                NSString *path = [incoming stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVetWADO-%@-%d.dcm", retrieveStamp, filesWritten + count]];
                if( [part writeToFile: path atomically: YES]) count++;
                else { retrieveIncomplete = YES; NSLog( @"SekhVet DICOMweb: write failed %@", path); }
            }
        }
        [receivedData replaceBytesInRange: NSMakeRange( 0, next.location + next.length) withBytes: NULL length: 0];
        scanPos = 0;
        if( truncated) return count;
    }
}

#pragma mark - Senden (STOW-RS)

+ (NSArray*) selectedDICOMPaths
{
    NSMutableArray *paths = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    @try
    {
        for( id item in [[BrowserController currentBrowser] databaseSelection])
        {
            NSMutableArray *images = [NSMutableArray array];
            if( [item isKindOfClass: [DicomStudy class]])
            {
                for( id se in [[item valueForKey: @"series"] allObjects]) [images addObjectsFromArray: [[se valueForKey: @"images"] allObjects]];
            }
            else if( [item isKindOfClass: [DicomSeries class]]) [images addObjectsFromArray: [[item valueForKey: @"images"] allObjects]];
            else if( [item isKindOfClass: [DicomImage class]]) [images addObject: item];

            for( id im in images)
            {
                NSString *p = [im valueForKey: @"completePath"];
                if( p.length == 0 || [seen containsObject: p]) continue;
                [seen addObject: p];
                if( [[NSFileManager defaultManager] fileExistsAtPath: p] && [DicomFile isDICOMFile: p]) [paths addObject: p];
            }
        }
    }
    @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: reading selection: %@", e); }
    return paths;
}

- (IBAction) stow:(id) sender
{
    NSArray *paths = [SekhmetDICOMweb selectedDICOMPaths];
    if( paths.count == 0) { [self setStatus: NSLocalizedString( @"No DICOM study/series selected in the browser", nil)]; return; }
    [self stowPaths: paths];
}

// SekhVet Paket CH: Multipart-Koerper als Datei (grosse Studien nicht im RAM), Teile: Content-Type application/dicom.
// Laeuft auch im Hintergrund-Thread (dann Fortschritt 0..0.3 und Abbruch ueber thread). nil = Datei nicht anlegbar.
+ (NSString*) newBoundary
{
    return [NSString stringWithFormat: @"SekhVet-%@", [[NSUUID UUID] UUIDString]];
}

+ (NSString*) writeMultipartForPaths:(NSArray*) paths tempDir:(NSString*) tmpDir boundary:(NSString*) boundary count:(int*) countOut thread:(NSThread*) thread
{
    if( tmpDir.length == 0) tmpDir = NSTemporaryDirectory();
    [[NSFileManager defaultManager] createDirectoryAtPath: tmpDir withIntermediateDirectories: YES attributes: nil error: NULL];
    NSString *tmp = [tmpDir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-STOW-%@.bin", [[NSUUID UUID] UUIDString]]];
    [[NSFileManager defaultManager] createFileAtPath: tmp contents: [NSData data] attributes: nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath: tmp];
    if( fh == nil) return nil;

    int n = 0, i = 0;
    // SekhVet Paket CS: NSFileHandle writeData: raises when the disk is full. This runs on a background
    // thread, where an uncaught exception ends the app -- catch it, remove the partial file, report nil.
    @try
    {
        for( NSString *p in paths)
        {
            if( thread.isCancelled) break;
            NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
            NSData *d = [NSData dataWithContentsOfFile: p options: NSDataReadingMappedIfSafe error: NULL];
            if( d.length)
            {
                [fh writeData: [[NSString stringWithFormat: @"--%@\r\nContent-Type: application/dicom\r\n\r\n", boundary] dataUsingEncoding: NSUTF8StringEncoding]];
                [fh writeData: d];
                [fh writeData: [@"\r\n" dataUsingEncoding: NSUTF8StringEncoding]];
                n++;
            }
            [pool release];
            if( thread && (++i % 20) == 0) thread.progress = 0.3 * i / paths.count;
        }
        [fh writeData: [[NSString stringWithFormat: @"--%@--\r\n", boundary] dataUsingEncoding: NSUTF8StringEncoding]];
        [fh closeFile];
    }
    @catch (NSException *e)
    {
        NSLog( @"SekhVet DICOMweb: writing the upload file raised %@ after %d files", e.name, n);
        @try { [fh closeFile]; } @catch (NSException *e2) {}
        [[NSFileManager defaultManager] removeItemAtPath: tmp error: NULL];
        if( countOut) *countOut = 0;
        return nil;
    }
    if( countOut) *countOut = n;
    return tmp;
}

- (NSMutableURLRequest*) stowRequestForNode:(NSDictionary*) node boundary:(NSString*) boundary
{
    NSMutableURLRequest *req = [self requestForURL: [NSString stringWithFormat: @"%@/studies", [node objectForKey: @"url"]] accept: @"application/dicom+json" node: node];
    [req setHTTPMethod: @"POST"];
    [req setValue: [NSString stringWithFormat: @"multipart/related; type=\"application/dicom\"; boundary=%@", boundary] forHTTPHeaderField: @"Content-Type"];
    return req;
}

// SekhVet Paket CS: reads the Store Instances Response (PS3.18): ReferencedSOPSequence (0008,1199) = stored,
// FailedSOPSequence (0008,1198) = rejected. YES only if the body IS such a response, as DICOM JSON or as
// Native DICOM XML; every level is type-checked (this also runs on the background send thread).
+ (BOOL) stowCountsFromData:(NSData*) data stored:(int*) stored failed:(int*) failed
{
    *stored = 0; *failed = 0;
    if( data.length == 0) return NO;
    @try
    {
        NSDictionary *d = sekhmetTyped( [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL], [NSDictionary class]);
        if( d)
        {
            NSDictionary *f = sekhmetTyped( [d objectForKey: @"00081198"], [NSDictionary class]);
            NSDictionary *r = sekhmetTyped( [d objectForKey: @"00081199"], [NSDictionary class]);
            if( f == nil && r == nil) return NO;
            *failed = (int) [sekhmetTyped( [f objectForKey: @"Value"], [NSArray class]) count];
            *stored = (int) [sekhmetTyped( [r objectForKey: @"Value"], [NSArray class]) count];
            return YES;
        }
        NSXMLDocument *x = [[[NSXMLDocument alloc] initWithData: data options: NSXMLNodeLoadExternalEntitiesNever error: NULL] autorelease];
        if( x == nil) return NO;
        NSArray *any = [x nodesForXPath: @"//*[local-name()='DicomAttribute'][@tag='00081198' or @tag='00081199']" error: NULL];
        if( any.count == 0) return NO;
        *failed = (int) [[x nodesForXPath: @"//*[local-name()='DicomAttribute'][@tag='00081198']/*[local-name()='Item']" error: NULL] count];
        *stored = (int) [[x nodesForXPath: @"//*[local-name()='DicomAttribute'][@tag='00081199']/*[local-name()='Item']" error: NULL] count];
        return YES;
    }
    @catch (NSException *e) { *stored = 0; *failed = 0; }
    return NO;
}

// SekhVet Paket CS: three outcomes instead of two.
//   ok          the node confirmed every file that was sent
//   unconfirmed HTTP 2xx, but no (or only a partial) store confirmation -- a wrong URL, a reverse proxy or
//               a login page answers 200 to a POST as well; the message no longer claims "N files accepted"
//   neither     rejected or failed
// The standard defines 200 / 202 / 409 with a response body; any other 2xx (204, empty body) is unconfirmed.
+ (NSString*) messageForStowData:(NSData*) data response:(NSURLResponse*) response fileCount:(int) fileCount ok:(BOOL*) ok unconfirmed:(BOOL*) unconfirmed
{
    NSInteger code = [response isKindOfClass: [NSHTTPURLResponse class]] ? [(NSHTTPURLResponse*) response statusCode] : 0;
    int failed = 0, stored = 0;
    BOOL parsed = [self stowCountsFromData: data stored: &stored failed: &failed];
    BOOL success = (code >= 200 && code < 300);
    if( ok) *ok = NO;
    if( unconfirmed) *unconfirmed = NO;

    if( code == 401) return NSLocalizedString( @"STOW-RS 401: user/password rejected", nil);
    if( success && parsed && failed == 0 && stored >= fileCount)
    {
        if( ok) *ok = YES;
        return [NSString stringWithFormat: NSLocalizedString( @"STOW-RS: %d files accepted (HTTP %d)", nil), stored, (int) code];
    }
    if( success && parsed && failed == 0 && stored > 0)
    {
        if( unconfirmed) *unconfirmed = YES;
        return [NSString stringWithFormat: NSLocalizedString( @"STOW-RS HTTP %d: the node confirmed only %d of %d files — check on the node that the study is complete", nil), (int) code, stored, fileCount];
    }
    if( (success || code == 409) && parsed && (failed > 0 || stored > 0))
        return [NSString stringWithFormat: NSLocalizedString( @"STOW-RS HTTP %d: %d accepted, %d rejected", nil), (int) code, stored, failed];
    if( success)
    {
        if( unconfirmed) *unconfirmed = YES;
        return [NSString stringWithFormat: NSLocalizedString( @"STOW-RS HTTP %d: %d files were uploaded, but the answer is not a DICOM store confirmation — NOT confirmed. Check on the node that the study arrived (wrong URL, proxy or login page?)", nil), (int) code, fileCount];
    }
    return [NSString stringWithFormat: NSLocalizedString( @"STOW-RS: HTTP %d", nil), (int) code];
}

#pragma mark - Senden aus der Datenbank (SekhVet Paket CH)

+ (NSMenuItem*) sendMenuItemWithTitle:(NSString*) title
{
    NSMenuItem *item = [[[NSMenuItem alloc] initWithTitle: title action: nil keyEquivalent: @""] autorelease];
    NSMenu *sub = [[[NSMenu alloc] initWithTitle: title] autorelease];
    [sub setDelegate: [SekhmetDICOMweb shared]]; // Knotenliste wird beim Oeffnen frisch aus den Prefs gebaut
    [item setSubmenu: sub];
    return item;
}

- (void) menuNeedsUpdate:(NSMenu*) menu
{
    [menu removeAllItems];
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetDICOMwebNodesKey];
    for( NSUInteger i = 0; i < list.count; i++)
    {
        NSDictionary *n = [list objectAtIndex: i];
        NSString *name = [n objectForKey: @"name"];
        NSMenuItem *mi = [menu addItemWithTitle: name.length ? name : [n objectForKey: @"url"] action: @selector(sendToNode:) keyEquivalent: @""];
        [mi setTarget: self];
        [mi setTag: i];
        [mi setToolTip: [n objectForKey: @"url"]];
    }
    if( list.count == 0)
        [[menu addItemWithTitle: NSLocalizedString( @"No DICOMweb node set up", nil) action: nil keyEquivalent: @""] setEnabled: NO];
    [menu addItem: [NSMenuItem separatorItem]];
    [[menu addItemWithTitle: NSLocalizedString( @"DICOMweb Nodes…", nil) action: @selector(showWindow:) keyEquivalent: @""] setTarget: self];
}

- (IBAction) sendToNode:(id) sender
{
    NSArray *list = [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetDICOMwebNodesKey];
    NSInteger i = [sender tag];
    if( i < 0 || i >= (NSInteger) list.count) return;
    NSDictionary *node = sekhmetTyped( [list objectAtIndex: i], [NSDictionary class]);
    if( node == nil) return;
    NSArray *paths = [SekhmetDICOMweb selectedDICOMPaths];
    if( paths.count == 0)
    {
        [[AppController sharedAppController] notificationTitle: NSLocalizedString( @"DICOMweb", nil) description: NSLocalizedString( @"No DICOM study/series selected in the database", nil) name: @"dicomweb-send"];
        NSBeep();
        return;
    }
    NSUInteger studies = 0;
    @try { for( id item in [[BrowserController currentBrowser] databaseSelection]) if( [item isKindOfClass: [DicomStudy class]]) studies++; }
    @catch (NSException *e) {}
    [self sendPaths: paths toNode: node studies: studies fromWindow: NO];
}

// SekhVet Paket CS: the one way to send. The "Send" button of the DICOMweb window used to build the whole
// multipart file on the main thread (frozen window for large studies) and had no cancel; it now takes the
// same background path as "Send via DICOMweb" in the database window. Main thread.
- (void) sendPaths:(NSArray*) paths toNode:(NSDictionary*) node studies:(NSUInteger) studies fromWindow:(BOOL) fromWindow
{
    node = [[node copy] autorelease];   // snapshot: the node list stays editable while the thread runs
    if( [self mayUseNode: node] == NO) return;   // plain http with credentials to a public host, asked once per node
    NSString *name = sekhmetTyped( [node objectForKey: @"name"], [NSString class]);
    if( name.length == 0) name = sekhmetTyped( [node objectForKey: @"url"], [NSString class]) ?: @"?";

    // Anfrage (Schluesselbund!) und TEMP-Pfad hier im Hauptthread, Koerper und Upload im Hintergrund
    NSString *boundary = [SekhmetDICOMweb newBoundary];
    [self session]; // einmal hier im Hauptthread anlegen
    NSDictionary *job = [NSDictionary dictionaryWithObjectsAndKeys:
                         paths, @"paths", node, @"node", boundary, @"boundary",
                         [self stowRequestForNode: node boundary: boundary], @"request",
                         [[DicomDatabase activeLocalDatabase] tempDirPath] ?: NSTemporaryDirectory(), @"tempDir",
                         [NSNumber numberWithBool: fromWindow], @"window", nil];
    NSThread *t = [[[NSThread alloc] initWithTarget: self selector: @selector(sendThread:) object: job] autorelease];
    t.name = [NSString stringWithFormat: NSLocalizedString( @"DICOMweb send to %@", nil), name];
    t.status = studies ? [NSString stringWithFormat: NSLocalizedString( @"%d studies, %d files", nil), (int) studies, (int) paths.count]
                       : [NSString stringWithFormat: NSLocalizedString( @"%d files", nil), (int) paths.count];
    t.supportsCancel = YES;
    NSLog( @"SekhVet DICOMweb: send %d files to %@ (background)", (int) paths.count, [node objectForKey: @"url"]);
    if( fromWindow) [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Sending %d files to %@ in the background — progress and cancel in the Activity list", nil), (int) paths.count, name]];
    [[ThreadsManager defaultManager] addThreadAndStart: t];
}

- (void) sendThread:(NSDictionary*) job
{
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    NSThread *thread = [NSThread currentThread];
    NSDictionary *node = [job objectForKey: @"node"];
    NSString *name = sekhmetTyped( [node objectForKey: @"name"], [NSString class]);
    if( name.length == 0) name = sekhmetTyped( [node objectForKey: @"url"], [NSString class]) ?: @"?";
    NSMutableURLRequest *req = [job objectForKey: @"request"];
    NSString *msg = nil, *tmp = nil;
    int n = 0;
    BOOL ok = NO, unconfirmed = NO;

    @try   // SekhVet Paket CS: nothing may escape from this thread -- an uncaught exception ends the app
    {
        NSArray *paths = [job objectForKey: @"paths"];
        NSString *tempDir = [job objectForKey: @"tempDir"];

        // Sekhmet (DD): in Portionen von hoechstens SekhmetStowBatchFiles Dateien bzw. SekhmetStowBatchBytes senden
        // (eine Datei, die allein groesser ist, geht allein). Vorher ging die ganze Studie in EINEM POST - hinter einem
        // Proxy oder bei einem Cloud-PACS endete eine grosse CT mit HTTP 413, alles oder nichts
        // (nach ThalesMMS/horos e948e313: 50 Dateien / 64 MB je Anfrage)
        NSMutableArray *batches = [NSMutableArray array];
        NSMutableArray *batch = [NSMutableArray array];
        unsigned long long batchBytes = 0, largestBatch = 0;
        for( NSString *p in paths)
        {
            unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath: p error: NULL] fileSize];
            if( batch.count && (batch.count >= SekhmetStowBatchFiles || batchBytes + size > SekhmetStowBatchBytes))
            {
                [batches addObject: batch];
                largestBatch = MAX( largestBatch, batchBytes);
                batch = [NSMutableArray array];
                batchBytes = 0;
            }
            [batch addObject: p];
            batchBytes += size;
        }
        if( batch.count) { [batches addObject: batch]; largestBatch = MAX( largestBatch, batchBytes); }

        // SekhVet Paket CS: the multipart body is a second copy of the files -- check the room before writing it
        // Sekhmet (DD): nur noch fuer die groesste Portion, die Temp-Datei wird je Portion neu geschrieben
        NSNumber *frei = [[[NSFileManager defaultManager] attributesOfFileSystemForPath: tempDir error: NULL] objectForKey: NSFileSystemFreeSize];
        if( frei && [frei unsignedLongLongValue] < largestBatch + 64ULL * 1024 * 1024)
            msg = [NSString stringWithFormat: NSLocalizedString( @"Not enough free disk space for the temporary upload file (%@ needed)", nil),
                   [NSByteCountFormatter stringFromByteCount: (long long) largestBatch countStyle: NSByteCountFormatterCountStyleFile]];
        else
        {
            int confirmed = 0, sentFiles = 0, batchIndex = 0;
            BOOL anyUnconfirmed = NO;
            NSString *lastMsg = nil;
            ok = YES;
            for( NSArray *part in batches)
            {
                batchIndex++;
                BOOL partOk = NO, partUnconfirmed = NO;
                int partN = 0;
                NSString *partMsg = nil;
                NSAutoreleasePool *partPool = [[NSAutoreleasePool alloc] init];

                tmp = [SekhmetDICOMweb writeMultipartForPaths: part tempDir: tempDir boundary: [job objectForKey: @"boundary"] count: &partN thread: nil];
                if( tmp == nil) partMsg = NSLocalizedString( @"Cannot write the temporary upload file (disk full?)", nil);
                else if( thread.isCancelled) partMsg = NSLocalizedString( @"Send cancelled", nil);
                else if( partN == 0) { partOk = YES; }   // nur unlesbare Dateien in dieser Portion: weiter mit der naechsten
                else
                {
                    __block NSData *rData = nil; __block NSURLResponse *rResp = nil; __block NSError *rErr = nil;
                    dispatch_semaphore_t done = dispatch_semaphore_create( 0);
                    NSURLSessionUploadTask *task = [[self session] uploadTaskWithRequest: req fromFile: [NSURL fileURLWithPath: tmp] completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
                        rData = [data retain]; rResp = [response retain]; rErr = [error retain];
                        dispatch_semaphore_signal( done);
                    }];
                    [task resume];
                    thread.status = batches.count > 1 ? [NSString stringWithFormat: NSLocalizedString( @"Sending part %d of %d (%d files)…", nil), batchIndex, (int) batches.count, partN]
                                                      : [NSString stringWithFormat: NSLocalizedString( @"Sending %d files…", nil), partN];
                    while( dispatch_semaphore_wait( done, dispatch_time( DISPATCH_TIME_NOW, 250 * NSEC_PER_MSEC)))
                    {
                        if( thread.isCancelled) [task cancel];
                        int64_t sentBytes = task.countOfBytesSent, total = task.countOfBytesExpectedToSend;
                        if( total > 0)
                            thread.progress = ((batchIndex - 1) + sentBytes / (double) total) / (double) batches.count;
                    }
                    dispatch_release( done);
                    if( rErr) partMsg = thread.isCancelled ? NSLocalizedString( @"Send cancelled", nil) : [NSString stringWithFormat: NSLocalizedString( @"STOW-RS error: %@", nil), rErr.localizedDescription];
                    else partMsg = [SekhmetDICOMweb messageForStowData: rData response: rResp fileCount: partN ok: &partOk unconfirmed: &partUnconfirmed];
                    [rData release]; [rResp release]; [rErr release];
                }
                if( tmp) { [[NSFileManager defaultManager] removeItemAtPath: tmp error: nil]; tmp = nil; }

                n += partN;
                if( partOk) { confirmed += partN; sentFiles += partN; }
                else if( partUnconfirmed) { anyUnconfirmed = YES; sentFiles += partN; }
                [lastMsg release]; lastMsg = [partMsg retain];
                [partPool release];

                if( partOk == NO && partUnconfirmed == NO)
                {
                    // harter Fehler (Login, HTTP-Fehler, Abbruch): nicht weiter senden, sagen, was schon angekommen ist
                    ok = NO;
                    msg = (batches.count > 1 && sentFiles > 0)
                        ? [NSString stringWithFormat: NSLocalizedString( @"%@ — part %d of %d; %d files were sent before", nil), lastMsg, batchIndex, (int) batches.count, sentFiles]
                        : [[lastMsg copy] autorelease];
                    break;
                }
            }
            if( msg == nil)
            {
                if( n == 0) { ok = NO; msg = NSLocalizedString( @"No readable DICOM file", nil); }
                else if( anyUnconfirmed) { ok = NO; unconfirmed = YES; msg = batches.count > 1 ? [NSString stringWithFormat: NSLocalizedString( @"%@ (%d of %d files confirmed in %d parts)", nil), lastMsg, confirmed, n, (int) batches.count] : [[lastMsg copy] autorelease]; }
                else msg = batches.count > 1 ? [NSString stringWithFormat: NSLocalizedString( @"STOW-RS: %d files accepted in %d parts", nil), confirmed, (int) batches.count] : [[lastMsg copy] autorelease];
            }
            [lastMsg release];
        }
    }
    @catch (NSException *e)
    {
        NSLog( @"SekhVet DICOMweb: send raised %@", e.name);
        ok = NO; unconfirmed = NO;
        msg = NSLocalizedString( @"Send failed: internal error (see Console)", nil);
    }
    if( tmp) [[NSFileManager defaultManager] removeItemAtPath: tmp error: nil];

    NSLog( @"SekhVet DICOMweb: send to %@: %@", [node objectForKey: @"url"], msg);
    // SekhVet Paket CS: "Sent to …" only when the node confirmed every file
    NSString *title = ok ? [NSString stringWithFormat: NSLocalizedString( @"Sent to %@", nil), name]
                    : unconfirmed ? [NSString stringWithFormat: NSLocalizedString( @"Sent to %@ — NOT confirmed by the node", nil), name]
                                  : [NSString stringWithFormat: NSLocalizedString( @"Sending to %@ failed", nil), name];
    [[AppController sharedAppController] notificationTitle: title description: msg name: @"dicomweb-send"]; // wechselt selbst in den Hauptthread
    if( [[job objectForKey: @"window"] boolValue]) [self performSelectorOnMainThread: @selector(setStatus:) withObject: msg waitUntilDone: NO];
    [pool release];
}

- (void) stowPaths:(NSArray*) paths
{
    NSDictionary *node = [self currentNode];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }
    if( paths.count == 0) { [self setStatus: NSLocalizedString( @"Nothing to send", nil)]; return; }
    [self sendPaths: paths toNode: node studies: 0 fromWindow: YES];   // SekhVet Paket CS: in the background, see sendPaths:
}

#pragma mark - Headless-Tests (Umgebungsvariablen)

#if SEKHVET_TESTHAKEN
+ (void) debugApplyEnvPassword
{
    const char *pw = sekhvetTesthaken( "SEKHVET_DICOMWEB_PW");
    NSArray *nodes = [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetDICOMwebNodesKey];
    if( pw == NULL || nodes.count == 0) return;
    if( sekhmetSessionPasswords == nil) sekhmetSessionPasswords = [[NSMutableDictionary alloc] init];
    [sekhmetSessionPasswords setObject: [NSString stringWithUTF8String: pw] forKey: [self accountForNode: [nodes objectAtIndex: 0]]];
}

- (void) debugStowFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_STOW_TEST");
    if( env == NULL) return;
    [SekhmetDICOMweb debugApplyEnvPassword];
    [self loadNodes];
    if( nodes.count == 0) { NSLog( @"SekhVet Testhaken: kein DICOMweb-Knoten in den Prefs -- im Fenster mit + anlegen"); return; } // seit defaultNodes leer ist (Paket AJ)
    [nodePopup selectItemAtIndex: 0];
    [self stowPaths: [[NSString stringWithUTF8String: env] componentsSeparatedByString: @":"]];
}

- (void) debugWadoFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_WADO_TEST");
    if( env == NULL) return;
    [SekhmetDICOMweb debugApplyEnvPassword];
    [self loadNodes];
    if( nodes.count == 0) { NSLog( @"SekhVet Testhaken: kein DICOMweb-Knoten in den Prefs -- im Fenster mit + anlegen"); return; } // seit defaultNodes leer ist (Paket AJ)
    [nodePopup selectItemAtIndex: 0];
    // SekhVet Paket CS: the queue is an ivar of {job, node}
    [retrieveQueue removeAllObjects];
    [retrieveQueue addObject: [NSDictionary dictionaryWithObjectsAndKeys: [NSString stringWithUTF8String: env], @"job", [[[nodes objectAtIndex: 0] copy] autorelease], @"node", nil]];
    filesWritten = 0; failedJobs = 0;
    [self retrieveNextStudy];
}

// SekhVet Paket AM: SEKHVET_DICOMWEB_LIST_TEST="<Namensteil>" — sucht am Knoten 0, loggt je Studie den lokalen Bestand,
// klappt die erste Studie auf und loggt je Serie, was hier liegt.
- (void) debugLocalListFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_DICOMWEB_LIST_TEST");
    if( env == NULL) return;
    [SekhmetDICOMweb debugApplyEnvPassword];
    [self loadNodes];
    if( nodes.count == 0) { NSLog( @"SekhVet Bestand-Test: kein DICOMweb-Knoten in den Prefs"); return; }
    [nodePopup selectItemAtIndex: 0];
    // Paket AP: Zustand beim Oeffnen protokollieren, BEVOR der Test die Felder fuer die Namenssuche leert
    NSLog( @"SekhVet Zeitraum-Test: Vorgabe '%@', von '%@' bis '%@'",
          [periodPopup titleOfSelectedItem], [dateFromField stringValue], [dateToField stringValue]);
    [nameField setStringValue: [NSString stringWithUTF8String: env]];
    [dateFromField setStringValue: @""]; [dateToField setStringValue: @""]; [idField setStringValue: @""]; [modalityField setStringValue: @""];
    NSLog( @"SekhVet Bestand-Test: Suche '%s' am Knoten %@", env, [[nodes objectAtIndex: 0] objectForKey: @"name"]);
    [self search: nil];
    [self performSelector: @selector(debugLocalListLog) withObject: nil afterDelay: 8 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

- (void) debugLocalListLog
{
    NSLog( @"SekhVet Bestand-Test: %d Studien", (int) results.count);
    for( NSDictionary *r in results)
        NSLog( @"SekhVet Bestand-Test Studie: %@ | %@ %@ | Serien %@ Bilder %@ | lokal: '%@'",
              [r objectForKey: @"Name"], [r objectForKey: @"Date"], [r objectForKey: @"Description"],
              [r objectForKey: @"Series"], [r objectForKey: @"Images"], [r objectForKey: @"Local"]);
    if( results.count == 0) return;
    NSMutableDictionary *first = [results objectAtIndex: 0];
    NSLog( @"SekhVet Bestand-Test: klappe '%@' auf", [first objectForKey: @"Name"]);
    [self loadSeriesForStudy: first];
    [self performSelector: @selector(debugLocalSeriesLog) withObject: nil afterDelay: 8 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

// Paket AO: zaehlt die Farbflaechen der Kugel — gruen = da, orange = geladener Anteil, weiss = fehlt
+ (NSString*) debugPieStats:(NSImage*) im
{
    NSBitmapImageRep *rep = [NSBitmapImageRep imageRepWithData: [im TIFFRepresentation]];
    if( rep == nil) return @"kein Bitmap";
    int gruen = 0, orange = 0, weiss = 0;
    for( NSInteger x = 0; x < [rep pixelsWide]; x++)
        for( NSInteger y = 0; y < [rep pixelsHigh]; y++)
        {
            NSColor *c = [[rep colorAtX: x y: y] colorUsingColorSpaceName: NSCalibratedRGBColorSpace];
            if( [c alphaComponent] < 0.5) continue;
            float r = [c redComponent], g = [c greenComponent], b = [c blueComponent];
            if( g > r && g > b) gruen++;
            else if( r > 0.7 && b < 0.4 && g < 0.75) orange++;
            else if( r > 0.85 && g > 0.85 && b > 0.85) weiss++;
        }
    return [NSString stringWithFormat: @"gruen %d, orange %d, weiss %d", gruen, orange, weiss];
}

- (void) debugPieLog
{
    for( NSInteger i = 0; i < [resultTable numberOfRows]; i++)
    {
        id item = [resultTable itemAtRow: i];
        id cell = [resultTable preparedCellAtColumn: 0 row: i];   // ruft outlineView:willDisplayCell:
        NSImage *im = [cell respondsToSelector: @selector(image)] ? [cell image] : nil;
        NSLog( @"SekhVet Kugel-Test Zeile %d: '%@' | Anteil %@ | Kugel %@ | %@ | Tip '%@'",
              (int) i, [item objectForKey: @"Name"], [item objectForKey: @"localFraction"],
              im ? @"ja" : @"nein", im ? [SekhmetDICOMweb debugPieStats: im] : @"-", [item objectForKey: @"localTip"]);
    }
}

- (void) debugLocalSeriesLog
{
    NSMutableDictionary *first = results.count ? [results objectAtIndex: 0] : nil;
    NSArray *kids = [first objectForKey: @"children"];
    NSLog( @"SekhVet Bestand-Test: %d Serien geladen (Outline-Zeilen: %d)", (int) kids.count, (int) [resultTable numberOfRows]);
    for( NSDictionary *s in kids)
        NSLog( @"SekhVet Bestand-Test Serie: %@ | %@ | %@ | Bilder %@ | lokal: '%@'",
              [s objectForKey: @"Name"], [s objectForKey: @"Modality"], [s objectForKey: @"Description"], [s objectForKey: @"Images"], [s objectForKey: @"Local"]);
    [self debugPieLog];   // Paket AO
}
#endif // SEKHVET_TESTHAKEN

#pragma mark - Tabellen

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    if( tv == pickerTable) return pickerItems.count;   // SekhVet Paket DN-2
    return nodes.count;   // Paket AM: die Ergebnisse haengen jetzt an der Outline (nur nodeTable ist eine Tabelle)
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( tv == pickerTable)   // SekhVet Paket DN-2
    {
        if( row < 0 || row >= (NSInteger) pickerItems.count) return nil;
        return [[pickerItems objectAtIndex: row] objectForKey: [col identifier]];
    }
    NSDictionary *n = [nodes objectAtIndex: row];
    NSString *ident = [col identifier];
    if( [ident isEqualToString: @"Node"]) return [n objectForKey: @"name"];
    if( [ident isEqualToString: @"URL"]) return [n objectForKey: @"url"];
    if( [ident isEqualToString: @"Institutions filter"]) return [n objectForKey: @"institutions"] ?: @"";   // SekhVet Paket DN
    return [n objectForKey: @"user"];
}

#pragma mark - Ergebnis-Outline (Paket AM)

// SekhVet Paket BU: Studien nach der gewaehlten Spalte; "Local" nach dem Anteil, der hier liegt; Gleichstand = neueste zuerst
- (void) sortResults
{
    NSSortDescriptor *sd = [[resultTable sortDescriptors] firstObject];
    NSString *key = sd.key.length ? sd.key : @"Date";
    BOOL asc = sd ? sd.ascending : NO;
    [results sortUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        NSComparisonResult r = NSOrderedSame;
        if( [key isEqualToString: @"Local"])
        {
            id fa = [a objectForKey: @"localFraction"], fb = [b objectForKey: @"localFraction"];
            float xa = [fa isKindOfClass: [NSNumber class]] ? [fa floatValue] : -1, xb = [fb isKindOfClass: [NSNumber class]] ? [fb floatValue] : -1;
            r = xa < xb ? NSOrderedAscending : (xa > xb ? NSOrderedDescending : NSOrderedSame);
        }
        else
        {
            NSString *va = [[a objectForKey: key] description] ?: @"", *vb = [[b objectForKey: key] description] ?: @"";
            if( va.length == 0 || vb.length == 0) { if( va.length != vb.length) return va.length ? NSOrderedAscending : NSOrderedDescending; }   // leere Felder immer unten
            else r = [va localizedStandardCompare: vb];
        }
        if( asc == NO) r = (NSComparisonResult) -r;
        if( r != NSOrderedSame) return r;
        NSString *da = [NSString stringWithFormat: @"%@ %@", [a objectForKey: @"Date"] ?: @"", [a objectForKey: @"Time"] ?: @""];
        NSString *db = [NSString stringWithFormat: @"%@ %@", [b objectForKey: @"Date"] ?: @"", [b objectForKey: @"Time"] ?: @""];
        return [db compare: da];
    }];
}

- (void) outlineView:(NSOutlineView*) ov sortDescriptorsDidChange:(NSArray*) oldDescriptors
{
    NSSortDescriptor *sd = [[ov sortDescriptors] firstObject];
    if( sd.key.length)
        [[NSUserDefaults standardUserDefaults] setObject: [NSDictionary dictionaryWithObjectsAndKeys: sd.key, @"key", [NSNumber numberWithBool: sd.ascending], @"ascending", nil] forKey: @"SekhmetDICOMwebSort"];
    NSArray *selected = [[resultTable selectedRowIndexes] count] ? [NSArray arrayWithObject: [resultTable itemAtRow: [resultTable selectedRow]]] : nil;
    [self sortResults];
    [resultTable reloadData];
    if( selected.firstObject)
    {
        NSInteger row = [resultTable rowForItem: selected.firstObject];
        if( row >= 0) { [resultTable selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO]; [resultTable scrollRowToVisible: row]; }
    }
}

- (NSInteger) outlineView:(NSOutlineView*) ov numberOfChildrenOfItem:(id) item
{
    if( item == nil) return results.count;
    return [[item objectForKey: @"children"] count];
}

- (id) outlineView:(NSOutlineView*) ov child:(NSInteger) index ofItem:(id) item
{
    if( item == nil) return [results objectAtIndex: index];
    return [[item objectForKey: @"children"] objectAtIndex: index];
}

- (BOOL) outlineView:(NSOutlineView*) ov isItemExpandable:(id) item
{
    return [item objectForKey: @"seriesUID"] == nil;   // Studien klappen auf, Serien nicht
}

- (id) outlineView:(NSOutlineView*) ov objectValueForTableColumn:(NSTableColumn*) col byItem:(id) item
{
    id v = [item objectForKey: [col identifier]];
    return v ? v : @"";
}

// Paket AO: die Kugel haengt an der Namensspalte, wie in Horos' Q/R-Fenster
- (void) outlineView:(NSOutlineView*) ov willDisplayCell:(id) cell forTableColumn:(NSTableColumn*) col item:(id) item
{
    if( [[col identifier] isEqualToString: @"Name"] == NO) return;
    if( [cell isKindOfClass: [ImageAndTextCell class]] == NO) return;
    id f = [item objectForKey: @"localFraction"];
    if( [f isKindOfClass: [NSNumber class]] == NO) f = nil;   // NSNull = nicht beurteilbar, keine Kugel
    [(ImageAndTextCell*) cell setImage: f ? [NSImage pieChartImageWithPercentage: [f floatValue]] : nil];
}

- (NSString*) outlineView:(NSOutlineView*) ov toolTipForCell:(NSCell*) cell rect:(NSRectPointer) rect
         tableColumn:(NSTableColumn*) col item:(id) item mouseLocation:(NSPoint) mouseLocation
{
    NSString *ident = [col identifier];
    if( [ident isEqualToString: @"Name"] == NO && [ident isEqualToString: @"Local"] == NO) return nil;
    return [item objectForKey: @"localTip"];
}

- (void) outlineViewItemWillExpand:(NSNotification*) n
{
    [self loadSeriesForStudy: [[n userInfo] objectForKey: @"NSObject"]];
}

- (void) tableView:(NSTableView*) tv setObjectValue:(id) value forTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( tv == pickerTable)   // SekhVet Paket DN-2: only the checkbox is editable
    {
        if( row >= 0 && row < (NSInteger) pickerItems.count && [[col identifier] isEqualToString: @"on"])
            [[pickerItems objectAtIndex: row] setObject: [NSNumber numberWithBool: [value boolValue]] forKey: @"on"];
        return;
    }
    if( [[tv identifier] isEqualToString: @"nodes"] == NO) return;
    if( row < 0 || row >= (NSInteger) nodes.count) return;
    NSMutableDictionary *n = [nodes objectAtIndex: row];
    NSDictionary *before = [[n copy] autorelease];
    NSString *ident = [col identifier];
    if( [value isKindOfClass: [NSString class]] == NO) value = @"";
    if( [ident isEqualToString: @"Node"]) [n setObject: value forKey: @"name"];
    else if( [ident isEqualToString: @"URL"]) [n setObject: [value stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"/ "]] forKey: @"url"];
    else if( [ident isEqualToString: @"Institutions filter"])   // SekhVet Paket DN: stored as typed, split at ";" when used
    {
        [n setObject: [value stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceAndNewlineCharacterSet]] forKey: @"institutions"];
        [self saveNodes];
        if( resultsNode && [[SekhmetDICOMweb accountForNode: resultsNode] isEqualToString: [SekhmetDICOMweb accountForNode: n]]) [self search: self];
        return;
    }
    else [n setObject: value forKey: @"user"];

    // SekhVet Paket CS: the keychain account is "url|user". After a change of either, the old item would stay
    // behind for ever. It is deleted, NOT carried over: a stored password is never sent to a new address
    // without the user entering it again.
    NSString *oldAccount = [SekhmetDICOMweb accountForNode: before];
    BOOL moved = [[SekhmetDICOMweb accountForNode: n] isEqualToString: oldAccount] == NO;
    BOOL hadPassword = moved && [[SekhmetDICOMweb passwordForNode: before] length] > 0;
    if( moved) [SekhmetDICOMweb forgetAccount: oldAccount unlessUsedBy: nodes];
    [self saveNodes];
    if( hadPassword) [self setStatus: NSLocalizedString( @"URL or user changed — save the password for this node again", nil)];
}

@end
