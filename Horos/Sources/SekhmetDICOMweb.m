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
#import "PieChartImage.h"     // Paket AO: dieselbe Kugel wie Horos' Q/R-Fenster
#import "ImageAndTextCell.h"  // Paket AO: Kugel links vom Namen
#import <Security/Security.h>

NSString* const SekhmetDICOMwebNodesKey = @"SekhmetDICOMwebNodes";
static NSString* const kService = @"SekhVet DICOMweb";
static SekhmetDICOMweb *sekhmetDICOMweb = nil;
static NSMutableDictionary *sekhmetSessionPasswords = nil; // Fallback, wenn der Schluesselbund verweigert (z.B. ssh-Sitzung)

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
- (void) debugLocalListLog;              // Paket AM
- (void) debugLocalSeriesLog;           // Paket AM
- (void) debugPieLog;                   // Paket AO
- (NSNumber*) localFractionForStudy:(NSDictionary*) r;                            // Paket AO
- (NSNumber*) localFractionForSeries:(NSDictionary*) s inStudy:(NSDictionary*) r; // Paket AO
- (NSString*) localTipWithHave:(int) have want:(int) want;                        // Paket AO
- (void) annotateSeries:(NSMutableDictionary*) s inStudy:(NSDictionary*) r;       // Paket AO
- (float) legendIn:(NSView*) cv x:(float) x y:(float) y percentage:(float) p text:(NSString*) t; // Paket AO
- (int) drainMultipartFinal:(BOOL) final;
- (void) stowFinishedWithData:(NSData*) data response:(NSURLResponse*) response error:(NSError*) error;
@end

@implementation SekhmetDICOMweb

+ (SekhmetDICOMweb*) shared
{
    if( sekhmetDICOMweb == nil)
        sekhmetDICOMweb = [[SekhmetDICOMweb alloc] init];
    return sekhmetDICOMweb;
}

+ (NSArray*) defaultNodes
{
    // Keine vorbelegten Knoten: der Quelltext ist LGPL und wird veroeffentlicht,
    // Adressen und Benutzer der eigenen Infrastruktur gehoeren nicht hinein
    // (Review 12.09.2026). Knoten legt man im DICOMweb-Fenster mit "+" an.
    // Installationen, die je einen Knoten bearbeitet haben (saveNodes), behalten
    // ihre Liste in den Prefs; wer nur die alten Vorgaben nutzte, legt die
    // Knoten einmal neu an -- gleicher URL + Benutzer findet das Passwort im
    // Schluesselbund wieder (accountForNode = url|user).
    return [NSArray array];
}

+ (void) registerDefaults:(NSMutableDictionary*) defaultValues
{
    [defaultValues setObject: [self defaultNodes] forKey: SekhmetDICOMwebNodesKey];
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

+ (void) setPassword:(NSString*) pw forNode:(NSDictionary*) node
{
    if( node == nil) return;
    if( sekhmetSessionPasswords == nil) sekhmetSessionPasswords = [[NSMutableDictionary alloc] init];
    if( pw.length) [sekhmetSessionPasswords setObject: pw forKey: [self accountForNode: node]];
    else [sekhmetSessionPasswords removeObjectForKey: [self accountForNode: node]];
    NSDictionary *q = [NSDictionary dictionaryWithObjectsAndKeys:
                       (id) kSecClassGenericPassword, (id) kSecClass,
                       kService, (id) kSecAttrService,
                       [self accountForNode: node], (id) kSecAttrAccount, nil];
    SecItemDelete( (CFDictionaryRef) q);
    if( pw.length == 0) return;
    NSMutableDictionary *a = [NSMutableDictionary dictionaryWithDictionary: q];
    [a setObject: [pw dataUsingEncoding: NSUTF8StringEncoding] forKey: (id) kSecValueData];
    [a setObject: @"SekhVet DICOMweb Passwort" forKey: (id) kSecAttrLabel];
    OSStatus st = SecItemAdd( (CFDictionaryRef) a, NULL);
    if( st != errSecSuccess) NSLog( @"Sekhmet DICOMweb: Schluesselbund-Fehler %d", (int) st);
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
        [self buildUI];
        [self loadNodes];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [session invalidateAndCancel]; [session release]; [retrieveTask release]; [stowTask release]; [stowTempPath release]; [retrieveStamp release];
    [receivedData release]; [retrieveBoundary release]; [retrieveStudyUID release];
    [results release]; [nodes release];
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
    [[c headerCell] setStringValue: ident]; [c setWidth: w]; [c setEditable: e];
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
    [cv addSubview: nodePopup];
    stowButton = [self button: NSLocalizedString( @"Send selected studies (STOW-RS)", nil) frame: NSMakeRect( 560, y - 4, 240, 30) action: @selector(stow:)];
    [cv addSubview: stowButton];

    y -= 34;
    nameField = [self field: NSMakeRect( 20, y, 180, 22) placeholder: NSLocalizedString( @"Name (partial)", nil)];
    idField = [self field: NSMakeRect( 210, y, 120, 22) placeholder: NSLocalizedString( @"Patient ID", nil)];
    dateFromField = [self field: NSMakeRect( 340, y, 100, 22) placeholder: @"von JJJJMMTT"];
    dateToField = [self field: NSMakeRect( 450, y, 100, 22) placeholder: @"bis JJJJMMTT"];
    modalityField = [self field: NSMakeRect( 560, y, 70, 22) placeholder: @"CT/MR/DX"];
    searchButton = [self button: NSLocalizedString( @"Search", nil) frame: NSMakeRect( 640, y - 4, 100, 30) action: @selector(search:)];
    [cv addSubview: nameField]; [cv addSubview: idField]; [cv addSubview: dateFromField]; [cv addSubview: dateToField]; [cv addSubview: modalityField]; [cv addSubview: searchButton];

    // Paket R: Zeitraum ohne Datumseingabe -> fuellt von/bis und sucht sofort
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Period:", nil) frame: NSMakeRect( 20, y + 2, 70, 20)]];
    periodPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 90, y - 2, 170, 26) pullsDown: NO] autorelease];
    [periodPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"Any date", nil), NSLocalizedString( @"Today", nil), NSLocalizedString( @"Yesterday", nil),
                                      NSLocalizedString( @"Last 3 days", nil), NSLocalizedString( @"Last 4 days", nil), NSLocalizedString( @"Last week", nil), NSLocalizedString( @"Last month", nil), nil]];
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
    [resultTable setDataSource: self]; [resultTable setDelegate: self];
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
    progress = [[[NSProgressIndicator alloc] initWithFrame: NSMakeRect( 210, y + 6, 200, 16)] autorelease];
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
    NSScrollView *nsv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, y, 560, 124)] autorelease];
    [nsv setAutoresizingMask: NSViewMaxYMargin];
    nodeTable = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, 560, 124)] autorelease];
    [nodeTable setIdentifier: @"nodes"];
    [nodeTable addTableColumn: [self column: @"Node" width: 150 editable: YES]];
    [nodeTable addTableColumn: [self column: @"URL" width: 300 editable: YES]];
    [nodeTable addTableColumn: [self column: @"User" width: 90 editable: YES]];
    [nodeTable setDataSource: self]; [nodeTable setDelegate: self];
    [nodeTable setUsesAlternatingRowBackgroundColors: YES];
    [nsv setDocumentView: nodeTable]; [nsv setHasVerticalScroller: YES]; [nsv setBorderType: NSBezelBorder];
    [cv addSubview: nsv];

    NSButton *plus = [self button: @"+" frame: NSMakeRect( 590, y + 96, 40, 26) action: @selector(addNode:)];
    NSButton *minus = [self button: @"−" frame: NSMakeRect( 635, y + 96, 40, 26) action: @selector(removeNode:)];
    [plus setAutoresizingMask: NSViewMaxYMargin]; [minus setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: plus]; [cv addSubview: minus];

    passwordField = [[[NSSecureTextField alloc] initWithFrame: NSMakeRect( 590, y + 50, 200, 22)] autorelease];
    [passwordField setPlaceholderString: NSLocalizedString( @"Password of the selected node", nil)];
    [passwordField setAutoresizingMask: NSViewMaxYMargin];
    [cv addSubview: passwordField];
    NSButton *save = [self button: NSLocalizedString( @"Save password", nil) frame: NSMakeRect( 590, y + 14, 200, 30) action: @selector(savePassword:)];
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
    [nodes addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: @"Neuer Knoten", @"name", @"http://server:8042/dicom-web", @"url", @"", @"user", nil]];
    [self saveNodes];
    [nodeTable editColumn: 0 row: nodes.count - 1 withEvent: nil select: YES];
}

- (IBAction) removeNode:(id) sender
{
    NSInteger r = [nodeTable selectedRow];
    if( r >= 0 && r < (NSInteger) nodes.count) { [nodes removeObjectAtIndex: r]; [self saveNodes]; }
}

- (IBAction) savePassword:(id) sender
{
    NSInteger r = [nodeTable selectedRow];
    if( r < 0) r = [nodePopup indexOfSelectedItem];
    if( r < 0 || r >= (NSInteger) nodes.count) { [self setStatus: NSLocalizedString( @"No node selected", nil)]; return; }
    [SekhmetDICOMweb setPassword: [passwordField stringValue] forNode: [nodes objectAtIndex: r]];
    [passwordField setStringValue: @""];
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Password for \"%@\" saved", nil), [[nodes objectAtIndex: r] objectForKey: @"name"]]];
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
        c.timeoutIntervalForResource = 3600;
        session = [[NSURLSession sessionWithConfiguration: c delegate: self delegateQueue: [NSOperationQueue mainQueue]] retain];
    }
    return session;
}

- (void) setStatus:(NSString*) s
{
    [statusField setStringValue: s ? s : @""];
}

- (NSString*) value:(NSDictionary*) item tag:(NSString*) tag
{
    id v = [[item objectForKey: tag] objectForKey: @"Value"];
    if( [v isKindOfClass: [NSArray class]] == NO || [v count] == 0) return @"";
    id first = [v objectAtIndex: 0];
    if( [first isKindOfClass: [NSDictionary class]]) return [first objectForKey: @"Alphabetic"] ? [first objectForKey: @"Alphabetic"] : @"";
    if( [v count] > 1) return [v componentsJoinedByString: @"/"];
    return [first description];
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
        case 3: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -2 toDate: today options: 0]; break;
        case 4: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -3 toDate: today options: 0]; break;
        case 5: from = [cal dateByAddingUnit: NSCalendarUnitDay value: -7 toDate: today options: 0]; break;
        case 6: from = [cal dateByAddingUnit: NSCalendarUnitMonth value: -1 toDate: today options: 0]; break;
        default: break;
    }
    [dateFromField setStringValue: from ? [self periodDateString: from] : @""];
    [dateToField setStringValue: from ? [self periodDateString: to] : @""];
    if( from && doSearch) [self search: self];
}

- (IBAction) search:(id) sender
{
    NSDictionary *node = [self currentNode];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }

    NSMutableArray *params = [NSMutableArray array];
    NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *pid = [[idField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *from = [[dateFromField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *to = [[dateToField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *mod = [[[modalityField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]] uppercaseString];
    NSCharacterSet *allowed = [NSCharacterSet URLQueryAllowedCharacterSet];

    if( name.length) [params addObject: [NSString stringWithFormat: @"PatientName=%@", [[NSString stringWithFormat: @"*%@*", name] stringByAddingPercentEncodingWithAllowedCharacters: allowed]]];
    if( pid.length) [params addObject: [NSString stringWithFormat: @"PatientID=%@", [pid stringByAddingPercentEncodingWithAllowedCharacters: allowed]]];
    if( from.length || to.length) [params addObject: [NSString stringWithFormat: @"StudyDate=%@-%@", from, to]];
    if( mod.length) [params addObject: [NSString stringWithFormat: @"ModalitiesInStudy=%@", mod]];
    [params addObject: @"includefield=00201206,00201208,00080061,00080080"]; // Build 67: + InstitutionName
    [params addObject: @"limit=300"];

    NSString *url = [NSString stringWithFormat: @"%@/studies?%@", [node objectForKey: @"url"], [params componentsJoinedByString: @"&"]];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"application/dicom+json" node: node];

    [self setStatus: NSLocalizedString( @"Searching…", nil)];
    [progress setHidden: NO]; [progress startAnimation: nil];
    [searchButton setEnabled: NO];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        [progress stopAnimation: nil]; [progress setHidden: YES];
        [searchButton setEnabled: YES];
        NSInteger code = [(NSHTTPURLResponse*) response statusCode];
        if( error) { [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Error: %@", nil), error.localizedDescription]]; return; }
        if( code == 401) { [self setStatus: NSLocalizedString( @"401: user/password rejected (save the password below)", nil)]; return; }
        if( code == 204 || data.length == 0) { [results removeAllObjects]; [resultTable reloadData]; [self setStatus: NSLocalizedString( @"No results", nil)]; return; }
        if( code != 200) { [self setStatus: [NSString stringWithFormat: @"HTTP %d", (int) code]]; return; }

        NSError *jerr = nil;
        id json = [NSJSONSerialization JSONObjectWithData: data options: 0 error: &jerr];
        if( [json isKindOfClass: [NSArray class]] == NO) { [self setStatus: NSLocalizedString( @"Response is not DICOM JSON", nil)]; return; }

        [results removeAllObjects];
        for( NSDictionary *item in json)
        {
            if( [item isKindOfClass: [NSDictionary class]] == NO) continue;
            NSString *studyUID = [self value: item tag: @"0020000D"];
            if( studyUID.length == 0) continue;
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
        [results sortUsingDescriptors: [NSArray arrayWithObjects: [NSSortDescriptor sortDescriptorWithKey: @"Date" ascending: NO], [NSSortDescriptor sortDescriptorWithKey: @"Time" ascending: NO], nil]]; // Build 67
        [self annotateLocalStatus];   // Paket AM: was liegt schon in der eigenen Datenbank?
        [resultTable reloadData];
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"%d studies", nil), (int) results.count]];
    }];
    [task resume];
}

#pragma mark - Was liegt schon hier? (Paket AM)

// Bestand der eigenen Datenbank zu einer Studie: je SeriesInstanceUID die Zahl der lokalen Bilder.
// Horos teilt eine PACS-Serie beim Import mitunter auf mehrere Serien auf (Doppelpositionen, 4D) — die Bildzahlen
// gleicher UID werden darum summiert. In Horos traegt seriesDICOMUID die echte SeriesInstanceUID
// (seriesInstanceUID bekommt bei der Trennung Zusaetze), siehe BrowserController.m:7675.
+ (NSDictionary*) localStatusForStudyUID:(NSString*) studyUID
{
    NSMutableDictionary *series = [NSMutableDictionary dictionary];
    int images = 0, localizer = 0;
    if( studyUID.length)
    {
        @try
        {
            DicomDatabase *db = [DicomDatabase activeLocalDatabase];
            NSArray *studies = [db objectsForEntity: [db studyEntity] predicate: [NSPredicate predicateWithFormat: @"studyInstanceUID == %@", studyUID]];
            for( DicomStudy *st in studies)
            {
                for( DicomSeries *se in [[st valueForKey: @"series"] allObjects])
                {
                    NSString *uid = [se valueForKey: @"seriesDICOMUID"];
                    if( uid.length == 0) continue;
                    // numberOfImages NICHT roh lesen: bei Multiframe-Serien (US-Cine-Loops) legt Horos
                    // dort den NEGIERTEN Zaehler ab ("There are frames!", DicomSeries.m:600). Roh summiert
                    // wurde der Bestand negativ, localFractionForStudy: sah <= 0 und malte trotz vollstaendig
                    // geholter Studie einen leeren Kreis (15.09.2026 an drei US-Studien aus Mellingen gesehen).
                    // noFiles ist Horos' eigener Zugriff und dreht das Vorzeichen zurueck.
                    int n = [[se valueForKey: @"noFiles"] intValue];
                    images += n;
                    // Horos fasst Localizer/Topogramme mehrerer Serien beim Import zu EINER Serie zusammen und gibt ihr
                    // eine eigene UID ("LOCALIZER" + StudyInstanceUID). Deren Bilder lassen sich keiner PACS-Serie mehr
                    // zuordnen -- solche Serien zeigen darum "?" statt "fehlt" (13.09.2026 an einer CT-Studie gesehen).
                    if( [uid hasPrefix: @"LOCALIZER"]) { localizer += n; continue; }
                    [series setObject: [NSNumber numberWithInt: n + [[series objectForKey: uid] intValue]] forKey: uid];
                }
            }
        }
        @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: lokalen Bestand lesen: %@", e); }
    }
    return [NSDictionary dictionaryWithObjectsAndKeys: series, @"series", [NSNumber numberWithInt: images], @"images",
            [NSNumber numberWithInt: localizer], @"localizer", nil];
}

- (NSString*) localTextForStudy:(NSDictionary*) r
{
    NSDictionary *local = [r objectForKey: @"local"];
    int limages = [[local objectForKey: @"images"] intValue];
    int rimages = [[r objectForKey: @"Images"] intValue];
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
        BOOL report = mod.length && [[NSArray arrayWithObjects: @"SR", @"PR", @"KO", @"DOC", @"SEG", @"RTSTRUCT", nil] containsObject: mod];
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
    int limages = [[[r objectForKey: @"local"] objectForKey: @"images"] intValue];
    int rimages = [[r objectForKey: @"Images"] intValue];
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
    for( NSMutableDictionary *r in results)
    {
        [r setObject: [SekhmetDICOMweb localStatusForStudyUID: [r objectForKey: @"uid"]] forKey: @"local"];
        [r setObject: [self localTextForStudy: r] forKey: @"Local"];
        [r setObject: [self localFractionForStudy: r] forKey: @"localFraction"];   // Paket AO
        [r setObject: [self localTipWithHave: [[[r objectForKey: @"local"] objectForKey: @"images"] intValue]
                                        want: [[r objectForKey: @"Images"] intValue]] forKey: @"localTip"];
        for( NSMutableDictionary *s in [r objectForKey: @"children"])
            [self annotateSeries: s inStudy: r];
    }
}

- (void) refreshLocalStatus   // nach einem Abruf: Horos importiert INCOMING im Hintergrund, darum zeitversetzt nachzaehlen
{
    [self annotateLocalStatus];
    [resultTable reloadData];
}

// Serien einer Studie beim Aufklappen vom Knoten holen (QIDO-RS /studies/<uid>/series)
- (void) loadSeriesForStudy:(NSMutableDictionary*) study
{
    if( study == nil || [[study objectForKey: @"loaded"] boolValue] || [[study objectForKey: @"loading"] boolValue]) return;
    NSDictionary *node = [self currentNode];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }

    [study setObject: [NSNumber numberWithBool: YES] forKey: @"loading"];
    NSString *url = [NSString stringWithFormat: @"%@/studies/%@/series?includefield=00200011,0008103E,00080060,00201209&limit=500",
                     [node objectForKey: @"url"], [study objectForKey: @"uid"]];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"application/dicom+json" node: node];
    [self setStatus: NSLocalizedString( @"Loading series…", nil)];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        [study setObject: [NSNumber numberWithBool: NO] forKey: @"loading"];   // nicht entfernen: aendert den hash
        NSInteger code = [(NSHTTPURLResponse*) response statusCode];
        if( error) { [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Series: %@", nil), error.localizedDescription]]; return; }
        id json = (data.length && code == 200) ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
        if( [json isKindOfClass: [NSArray class]] == NO)
        {
            [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Series: HTTP %d", nil), (int) code]];
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
        [resultTable reloadItem: study reloadChildren: YES];
        [resultTable expandItem: study];
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"%d series", nil), (int) kids.count]];
    }];
    [task resume];
}

#pragma mark - Abruf (WADO-RS)

- (IBAction) retrieve:(id) sender
{
    NSIndexSet *sel = [resultTable selectedRowIndexes];
    if( sel.count == 0) { [self setStatus: NSLocalizedString( @"No study selected", nil)]; return; }
    if( retrieveStudyUID) { [self setStatus: NSLocalizedString( @"Retrieve already running", nil)]; return; }

    // Paket AM: markiert sein koennen Studien- und Serienzeilen. Auftrag ist "<StudyUID>" oder "<StudyUID>|<SeriesUID>";
    // ist die ganze Studie markiert, fallen ihre einzeln markierten Serien weg.
    NSMutableArray *queue = [NSMutableArray array];
    NSMutableSet *wholeStudies = [NSMutableSet set];
    [sel enumerateIndexesUsingBlock: ^(NSUInteger idx, BOOL *stop) {
        id item = [resultTable itemAtRow: idx];
        if( [item objectForKey: @"seriesUID"] == nil && [item objectForKey: @"uid"]) [wholeStudies addObject: [item objectForKey: @"uid"]];
    }];
    [sel enumerateIndexesUsingBlock: ^(NSUInteger idx, BOOL *stop) {
        id item = [resultTable itemAtRow: idx];
        NSString *seriesUID = [item objectForKey: @"seriesUID"];
        NSString *job = nil;
        if( seriesUID == nil) job = [item objectForKey: @"uid"];
        else if( [wholeStudies containsObject: [item objectForKey: @"studyUID"]] == NO)
            job = [NSString stringWithFormat: @"%@|%@", [item objectForKey: @"studyUID"], seriesUID];
        if( job.length && [queue containsObject: job] == NO) [queue addObject: job];
    }];
    if( queue.count == 0) { [self setStatus: NSLocalizedString( @"No study selected", nil)]; return; }
    [[NSUserDefaults standardUserDefaults] setObject: queue forKey: @"SekhmetDICOMwebRetrieveQueue"];
    filesWritten = 0;
    [self retrieveNextStudy];
}

- (void) retrieveNextStudy
{
    NSMutableArray *queue = [NSMutableArray arrayWithArray: [[NSUserDefaults standardUserDefaults] arrayForKey: @"SekhmetDICOMwebRetrieveQueue"]];
    if( queue.count == 0)
    {
        [retrieveStudyUID release]; retrieveStudyUID = nil;
        [progress stopAnimation: nil]; [progress setHidden: YES];
        [retrieveButton setEnabled: YES];
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Done: %d files written to INCOMING — importing now", nil), filesWritten]];
        // Paket AM: Horos importiert INCOMING im Hintergrund — Bestandsanzeige zweimal zeitversetzt nachziehen
        [self performSelector: @selector(refreshLocalStatus) withObject: nil afterDelay: 8];
        [self performSelector: @selector(refreshLocalStatus) withObject: nil afterDelay: 30];
        return;
    }
    NSString *job = [queue objectAtIndex: 0];
    NSArray *parts = [job componentsSeparatedByString: @"|"];   // Paket AM: "<StudyUID>" oder "<StudyUID>|<SeriesUID>"
    NSString *uid = [parts objectAtIndex: 0];
    NSString *seriesUID = parts.count > 1 ? [parts objectAtIndex: 1] : nil;
    [queue removeObjectAtIndex: 0];
    [[NSUserDefaults standardUserDefaults] setObject: queue forKey: @"SekhmetDICOMwebRetrieveQueue"];

    NSDictionary *node = [self currentNode];
    if( node == nil) return;

    [retrieveStudyUID release]; retrieveStudyUID = [uid retain];
    [receivedData release]; receivedData = [[NSMutableData alloc] init];
    [retrieveBoundary release]; retrieveBoundary = nil;
    expectedLength = -1; receivedLength = 0;
    multipartStarted = NO; scanPos = 0;
    [retrieveStamp release]; retrieveStamp = [[NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]] retain];

    NSString *url = seriesUID.length ? [NSString stringWithFormat: @"%@/studies/%@/series/%@", [node objectForKey: @"url"], uid, seriesUID]
                                     : [NSString stringWithFormat: @"%@/studies/%@", [node objectForKey: @"url"], uid];
    NSMutableURLRequest *req = [self requestForURL: url accept: @"multipart/related; type=\"application/dicom\"; transfer-syntax=*" node: node];

    [retrieveButton setEnabled: NO];
    [progress setIndeterminate: YES]; [progress setHidden: NO]; [progress startAnimation: nil];
    [self setStatus: seriesUID.length ? NSLocalizedString( @"Retrieving series…", nil) : NSLocalizedString( @"Retrieving…", nil)];

    NSURLSessionDataTask *task = [[self session] dataTaskWithRequest: req];
    [retrieveTask release]; retrieveTask = [task retain];
    [task resume];
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
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Retrieve: HTTP %d", nil), (int) r.statusCode]];
        completionHandler( NSURLSessionResponseCancel);
        [retrieveStudyUID release]; retrieveStudyUID = nil;
        [progress stopAnimation: nil]; [progress setHidden: YES]; [retrieveButton setEnabled: YES];
        return;
    }
    if( expectedLength > 0) { [progress setIndeterminate: NO]; [progress setMinValue: 0]; [progress setMaxValue: expectedLength]; [progress setDoubleValue: 0]; }
    completionHandler( NSURLSessionResponseAllow);
}

- (void) URLSession:(NSURLSession*) s dataTask:(NSURLSessionDataTask*) task didReceiveData:(NSData*) data
{
    if( task != retrieveTask) return;
    [receivedData appendData: data];
    receivedLength += data.length;
    if( expectedLength > 0) [progress setDoubleValue: receivedLength];
    if( retrieveBoundary.length) filesWritten += [self drainMultipartFinal: NO];   // Stream: jede fertige Instanz sofort nach INCOMING
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Retrieving… %.0f MB, %d files written", nil), receivedLength / 1048576., filesWritten]];
}

- (void) URLSession:(NSURLSession*) s task:(NSURLSessionTask*) task didCompleteWithError:(NSError*) error
{
    if( task != retrieveTask || retrieveStudyUID == nil) return; // Suche und STOW laufen ueber Completion-Handler

    if( error)
    {
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Retrieve error: %@", nil), error.localizedDescription]];
        NSLog( @"SekhVet DICOMweb: WADO-RS Fehler %@", error);
        [retrieveStudyUID release]; retrieveStudyUID = nil;
        [receivedData release]; receivedData = nil;
        [progress stopAnimation: nil]; [progress setHidden: YES]; [retrieveButton setEnabled: YES];
        return;
    }

    if( retrieveBoundary.length) filesWritten += [self drainMultipartFinal: YES];
    else if( receivedData.length)
    {
        // Kein Multipart: eine Datei (application/dicom)
        NSString *incoming = [[DicomDatabase activeLocalDatabase] incomingDirPath];
        if( incoming && [receivedData writeToFile: [incoming stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVetWADO-%@-0.dcm", retrieveStamp]] atomically: YES]) filesWritten++;
    }
    [receivedData release]; receivedData = nil;
    NSLog( @"SekhVet DICOMweb: WADO-RS Studie %@ fertig, %d Dateien bisher", retrieveStudyUID, filesWritten);
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
        if( hdrEnd.location == NSNotFound) return count;
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
            next = NSMakeRange( len, 0); truncated = YES;   // Strom endete ohne schliessenden Delimiter: Rest als letzte Instanz
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
            NSString *path = [incoming stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVetWADO-%@-%d.dcm", retrieveStamp, filesWritten + count]];
            if( [part writeToFile: path atomically: YES]) count++;
            else NSLog( @"SekhVet DICOMweb: Schreiben scheiterte %@", path);
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
    @catch (NSException *e) { NSLog( @"SekhVet DICOMweb: Auswahl lesen: %@", e); }
    return paths;
}

- (IBAction) stow:(id) sender
{
    NSArray *paths = [SekhmetDICOMweb selectedDICOMPaths];
    if( paths.count == 0) { [self setStatus: NSLocalizedString( @"No DICOM study/series selected in the browser", nil)]; return; }
    [self stowPaths: paths];
}

- (void) stowPaths:(NSArray*) paths
{
    NSDictionary *node = [self currentNode];
    if( node == nil) { [self setStatus: NSLocalizedString( @"No node", nil)]; return; }
    if( stowTask) { [self setStatus: NSLocalizedString( @"Send already running", nil)]; return; }
    if( paths.count == 0) { [self setStatus: NSLocalizedString( @"Nothing to send", nil)]; return; }

    // Multipart-Koerper als Datei (grosse Studien nicht im RAM), Teile: Content-Type application/dicom
    NSString *boundary = [NSString stringWithFormat: @"SekhVet-%@", [[NSUUID UUID] UUIDString]];
    NSString *tmpDir = [[DicomDatabase activeLocalDatabase] tempDirPath];
    if( tmpDir.length == 0) tmpDir = NSTemporaryDirectory();
    NSString *tmp = [tmpDir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-STOW-%.0f.bin", [NSDate timeIntervalSinceReferenceDate]]];
    [[NSFileManager defaultManager] createFileAtPath: tmp contents: [NSData data] attributes: nil];
    NSFileHandle *fh = [NSFileHandle fileHandleForWritingAtPath: tmp];
    if( fh == nil) { [self setStatus: NSLocalizedString( @"Cannot create temporary file", nil)]; return; }

    int n = 0;
    for( NSString *p in paths)
    {
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
    }
    [fh writeData: [[NSString stringWithFormat: @"--%@--\r\n", boundary] dataUsingEncoding: NSUTF8StringEncoding]];
    [fh closeFile];
    if( n == 0) { [[NSFileManager defaultManager] removeItemAtPath: tmp error: nil]; [self setStatus: NSLocalizedString( @"No readable DICOM file", nil)]; return; }

    unsigned long long size = [[[NSFileManager defaultManager] attributesOfItemAtPath: tmp error: NULL] fileSize];
    NSMutableURLRequest *req = [self requestForURL: [NSString stringWithFormat: @"%@/studies", [node objectForKey: @"url"]] accept: @"application/dicom+json" node: node];
    [req setHTTPMethod: @"POST"];
    [req setValue: [NSString stringWithFormat: @"multipart/related; type=\"application/dicom\"; boundary=%@", boundary] forHTTPHeaderField: @"Content-Type"];

    [stowTempPath release]; stowTempPath = [tmp retain];
    stowFileCount = n;
    [stowButton setEnabled: NO];
    [progress setIndeterminate: NO]; [progress setMinValue: 0]; [progress setMaxValue: (double) size]; [progress setDoubleValue: 0];
    [progress setHidden: NO]; [progress startAnimation: nil];
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Sending %d files (%.0f MB) to %@…", nil), n, size / 1048576., [node objectForKey: @"name"]]];
    NSLog( @"SekhVet DICOMweb: STOW-RS %d Dateien, %llu Bytes an %@", n, size, [node objectForKey: @"url"]);

    NSURLSessionUploadTask *task = [[self session] uploadTaskWithRequest: req fromFile: [NSURL fileURLWithPath: tmp] completionHandler: ^(NSData *data, NSURLResponse *response, NSError *error) {
        [self stowFinishedWithData: data response: response error: error];
    }];
    [stowTask release]; stowTask = [task retain];
    [task resume];
}

- (void) URLSession:(NSURLSession*) s task:(NSURLSessionTask*) task didSendBodyData:(int64_t) bytesSent totalBytesSent:(int64_t) totalBytesSent totalBytesExpectedToSend:(int64_t) totalBytesExpectedToSend
{
    if( task != stowTask) return;
    if( totalBytesExpectedToSend > 0) { [progress setMaxValue: (double) totalBytesExpectedToSend]; [progress setDoubleValue: (double) totalBytesSent]; }
    [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"Sending… %.0f of %.0f MB", nil), totalBytesSent / 1048576., totalBytesExpectedToSend / 1048576.]];
}

- (void) stowFinishedWithData:(NSData*) data response:(NSURLResponse*) response error:(NSError*) error
{
    if( stowTempPath) [[NSFileManager defaultManager] removeItemAtPath: stowTempPath error: nil];
    [stowTempPath release]; stowTempPath = nil;
    [stowTask release]; stowTask = nil;
    [stowButton setEnabled: YES];
    [progress stopAnimation: nil]; [progress setHidden: YES];

    if( error)
    {
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"STOW-RS error: %@", nil), error.localizedDescription]];
        NSLog( @"SekhVet DICOMweb: STOW-RS Fehler %@", error);
        return;
    }
    NSInteger code = [(NSHTTPURLResponse*) response statusCode];
    int failed = 0, stored = 0;
    id json = data.length ? [NSJSONSerialization JSONObjectWithData: data options: 0 error: NULL] : nil;
    if( [json isKindOfClass: [NSDictionary class]])
    {
        failed = (int) [[[json objectForKey: @"00081198"] objectForKey: @"Value"] count];   // FailedSOPSequence
        stored = (int) [[[json objectForKey: @"00081199"] objectForKey: @"Value"] count];   // ReferencedSOPSequence
    }
    NSString *msg;
    if( code == 401) msg = NSLocalizedString( @"STOW-RS 401: user/password rejected", nil);
    else if( (code == 200 || code == 202) && failed == 0) msg = [NSString stringWithFormat: NSLocalizedString( @"STOW-RS: %d files accepted (HTTP %d)", nil), stored > 0 ? stored : stowFileCount, (int) code];
    else if( code == 200 || code == 202 || code == 409) msg = [NSString stringWithFormat: NSLocalizedString( @"STOW-RS HTTP %d: %d accepted, %d rejected", nil), (int) code, stored, failed];
    else msg = [NSString stringWithFormat: NSLocalizedString( @"STOW-RS: HTTP %d", nil), (int) code];
    [self setStatus: msg];
    NSLog( @"SekhVet DICOMweb: %@", msg);
}

#pragma mark - Headless-Tests (Umgebungsvariablen)

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
    [[NSUserDefaults standardUserDefaults] setObject: [NSArray arrayWithObject: [NSString stringWithUTF8String: env]] forKey: @"SekhmetDICOMwebRetrieveQueue"];
    filesWritten = 0;
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

#pragma mark - Tabellen

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    return nodes.count;   // Paket AM: die Ergebnisse haengen jetzt an der Outline (nur nodeTable ist eine Tabelle)
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    NSDictionary *n = [nodes objectAtIndex: row];
    NSString *ident = [col identifier];
    if( [ident isEqualToString: @"Node"]) return [n objectForKey: @"name"];
    if( [ident isEqualToString: @"URL"]) return [n objectForKey: @"url"];
    return [n objectForKey: @"user"];
}

#pragma mark - Ergebnis-Outline (Paket AM)

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
    if( [[tv identifier] isEqualToString: @"nodes"] == NO) return;
    NSMutableDictionary *n = [nodes objectAtIndex: row];
    NSString *ident = [col identifier];
    if( value == nil) value = @"";
    if( [ident isEqualToString: @"Node"]) [n setObject: value forKey: @"name"];
    else if( [ident isEqualToString: @"URL"]) [n setObject: [value stringByTrimmingCharactersInSet: [NSCharacterSet characterSetWithCharactersInString: @"/ "]] forKey: @"url"];
    else [n setObject: value forKey: @"user"];
    [self saveNodes];
}

@end
