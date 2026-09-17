/*=========================================================================
 Sekhmet — Einstellungsfenster fuer die Vet-Orientierung. Siehe Header.
 ============================================================================*/

#import "SekhmetOrientationPanel.h"
#import "SekhmetDisplayPanel.h"
#import "SekhmetOrientation.h"
#import "MPRController.h"   // SekhVet Paket AX

static SekhmetOrientationPanel *sekhmetPanel = nil;

static NSString* const kRuleKeys[ 5] = { @"transversalDorsalUp", @"sagittalCranialLeft", @"dorsalCranialUp", @"leftOnRight", @"proximalCaudal" }; // SekhVet Paket AF: fuenfte Regel

@implementation SekhmetOrientationPanel

+ (SekhmetOrientationPanel*) shared
{
    if( sekhmetPanel == nil)
        sekhmetPanel = [[SekhmetOrientationPanel alloc] init];
    return sekhmetPanel;
}

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 640, 640)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Hanging Protocol", nil)];
    [w setReleasedWhenClosed: NO];

    self = [super initWithWindow: w];
    if( self)
    {
        ruleButtons = [[NSMutableArray alloc] init];
        keywords = [[NSMutableArray alloc] init];
        dxRules = [[NSMutableArray alloc] init];
        [self buildUI];
        [self loadFromDefaults];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [ruleButtons release];
    [keywords release];
    [dxRules release];
    [super dealloc];
}

- (IBAction) showWindow:(id) sender
{
    MPRController *c = [SekhmetOrientation frontMPR];   // SekhVet Paket AX: das Preset, unter dem man gerade anordnet
    NSInteger p = c ? [SekhmetOrientation presetForMPR: c] : SekhmetPresetOff;
    if( p >= SekhmetPresetHeadSpine && p <= SekhmetPresetLast) [layoutPresetPopup selectItemAtIndex: p - SekhmetPresetHeadSpine];
    [self updateLayoutStatus];
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES]; // SekhVet: innerhalb der Viewer-Flaeche
    [super showWindow: sender];
}

#pragma mark - UI-Bau

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text];
    [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSButton*) button:(NSString*) title frame:(NSRect) r action:(SEL) sel tag:(NSInteger) tag
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setTitle: title];
    [b setBezelStyle: NSBezelStyleRounded];
    [b setTarget: self]; [b setAction: sel]; [b setTag: tag];
    [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (NSScrollView*) tableWithFrame:(NSRect) r identifier:(NSString*) ident columns:(NSArray*) columns widths:(NSArray*) widths
{
    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: r] autorelease];
    NSTableView *tv = [[[NSTableView alloc] initWithFrame: NSMakeRect( 0, 0, r.size.width, r.size.height)] autorelease];
    [tv setIdentifier: ident];
    for( NSUInteger i = 0; i < columns.count; i++)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [columns objectAtIndex: i]] autorelease];
        [[c headerCell] setStringValue: [columns objectAtIndex: i]];
        [c setWidth: [[widths objectAtIndex: i] floatValue]];
        [c setEditable: YES];
        if( [[columns objectAtIndex: i] isEqualToString: @"Preset"])
        {
            NSPopUpButtonCell *pc = [[[NSPopUpButtonCell alloc] initTextCell: @"" pullsDown: NO] autorelease];
            [pc addItemsWithTitles: [SekhmetOrientation presetNames]];
            [pc setBordered: NO];
            [c setDataCell: pc];
        }
        else if( [[columns objectAtIndex: i] hasPrefix: @"Flip"])
        {
            NSButtonCell *bc = [[[NSButtonCell alloc] initTextCell: @""] autorelease];
            [bc setButtonType: NSButtonTypeSwitch];
            [c setDataCell: bc];
        }
        [tv addTableColumn: c];
    }
    [tv setDataSource: self]; [tv setDelegate: self];
    [tv setUsesAlternatingRowBackgroundColors: YES];
    [sv setDocumentView: tv];
    [sv setHasVerticalScroller: YES];
    [sv setBorderType: NSBezelBorder];
    return sv;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float y = 640 - 40;   // SekhVet Paket AX: 80 pt mehr fuer die MPR-Anordnung unten

    [cv addSubview: [self label: NSLocalizedString( @"Default preset (used when no keyword matches):", nil) frame: NSMakeRect( 20, y, 360, 20) bold: YES]];
    presetPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 380, y - 4, 240, 26) pullsDown: NO] autorelease];
    [presetPopup addItemsWithTitles: [SekhmetOrientation presetNames]];
    [presetPopup setTarget: self]; [presetPopup setAction: @selector(presetChanged:)];
    [cv addSubview: presetPopup];

    // SekhVet Paket AF: Regeln als Raster (Zeile = Regel, Spalte = Preset), fuenf Regeln, fuenf Presets
    NSArray *ruleTitles = [NSArray arrayWithObjects:
                           NSLocalizedString( @"Transverse: dorsal up (else ventral up)", nil),
                           NSLocalizedString( @"Sagittal: cranial left (else cranial/proximal up)", nil),
                           NSLocalizedString( @"Dorsal plane: cranial up (else cranial left)", nil),
                           NSLocalizedString( @"Patient left on the right side of the image", nil),
                           NSLocalizedString( @"Limb: proximal = caudal (forelimb) → caudal up", nil), nil];
    NSArray *names = [SekhmetOrientation presetNames];
    float colX = 320, colW = 62;

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Rules per preset", nil) frame: NSMakeRect( 20, y, 290, 20) bold: YES]];
    for( NSInteger p = SekhmetPresetHeadSpine; p <= SekhmetPresetLast; p++)
    {
        NSTextField *h = [self label: [names objectAtIndex: p] frame: NSMakeRect( colX + (p - 1) * colW - 4, y, colW + 8, 20) bold: NO];
        [h setAlignment: NSTextAlignmentCenter];
        [h setFont: [NSFont systemFontOfSize: 10]];
        [cv addSubview: h];
    }
    y -= 22;
    for( int r = 0; r < 5; r++)
    {
        NSTextField *t = [self label: [ruleTitles objectAtIndex: r] frame: NSMakeRect( 36, y, 284, 18) bold: NO];
        [t setFont: [NSFont systemFontOfSize: 11]];
        [cv addSubview: t];
        for( NSInteger p = SekhmetPresetHeadSpine; p <= SekhmetPresetLast; p++)
        {
            NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect( colX + (p - 1) * colW + colW / 2 - 9, y, 18, 18)] autorelease];
            [b setButtonType: NSButtonTypeSwitch];
            [b setTitle: @""];
            [b setTag: p * 10 + r];
            [b setTarget: self]; [b setAction: @selector(ruleChanged:)];
            [cv addSubview: b];
            [ruleButtons addObject: b];
        }
        y -= 20;
    }
    y -= 8;

    // Stichworte
    [cv addSubview: [self label: NSLocalizedString( @"Keywords (study/series description contains …) → preset", nil) frame: NSMakeRect( 20, y, 600, 20) bold: YES]];
    y -= 130;
    NSScrollView *ksv = [self tableWithFrame: NSMakeRect( 20, y, 500, 124) identifier: @"keywords"
                                     columns: [NSArray arrayWithObjects: @"Keyword", @"Preset", nil]
                                      widths: [NSArray arrayWithObjects: @"250", @"200", nil]];
    keywordTable = (NSTableView*) [ksv documentView];
    [cv addSubview: ksv];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 530, y + 96, 40, 26) action: @selector(addKeyword:) tag: 0]];
    [cv addSubview: [self button: @"−" frame: NSMakeRect( 575, y + 96, 40, 26) action: @selector(removeKeyword:) tag: 0]];

    // DX-Regeln
    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Radiographs (DX/CR): rule per device — match in StationName or modality → rotation/flip", nil) frame: NSMakeRect( 20, y, 600, 20) bold: YES]];
    y -= 110;
    NSScrollView *dsv = [self tableWithFrame: NSMakeRect( 20, y, 500, 104) identifier: @"dx"
                                     columns: [NSArray arrayWithObjects: @"Match", @"Rotation °", @"Flip ↔", @"Flip ↕", nil]
                                      widths: [NSArray arrayWithObjects: @"220", @"90", @"70", @"70", nil]];
    dxTable = (NSTableView*) [dsv documentView];
    [cv addSubview: dsv];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 530, y + 76, 40, 26) action: @selector(addDXRule:) tag: 0]];
    [cv addSubview: [self button: @"−" frame: NSMakeRect( 575, y + 76, 40, 26) action: @selector(removeDXRule:) tag: 0]];

    y -= 44;
    [cv addSubview: [self button: NSLocalizedString( @"Apply to open viewers", nil) frame: NSMakeRect( 20, y, 240, 30) action: @selector(applyNow:) tag: 0]];
    [cv addSubview: [self button: NSLocalizedString( @"Reset keywords", nil) frame: NSMakeRect( 270, y, 200, 30) action: @selector(resetKeywords:) tag: 0]];

    // SekhVet Paket AX: MPR-Anordnung je Preset aus dem Bildschirm uebernehmen
    y -= 34;
    [cv addSubview: [self label: NSLocalizedString( @"MPR layout — arrange an MPR window as you want it, then take it for a preset:", nil) frame: NSMakeRect( 20, y, 600, 20) bold: YES]];
    y -= 30;
    layoutPresetPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 20, y - 2, 150, 26) pullsDown: NO] autorelease];
    for( NSInteger p = SekhmetPresetHeadSpine; p <= SekhmetPresetLast; p++) [layoutPresetPopup addItemWithTitle: [names objectAtIndex: p]];   // names: oben, Presetnamen
    [layoutPresetPopup setTarget: self]; [layoutPresetPopup setAction: @selector(layoutPresetChanged:)];
    [cv addSubview: layoutPresetPopup];
    [cv addSubview: [self button: NSLocalizedString( @"Take from screen", nil) frame: NSMakeRect( 180, y - 3, 150, 30) action: @selector(takeMPRLayout:) tag: 0]];
    [cv addSubview: [self button: NSLocalizedString( @"Standard layout", nil) frame: NSMakeRect( 335, y - 3, 140, 30) action: @selector(resetMPRLayout:) tag: 0]];
    layoutStatus = [self label: @"" frame: NSMakeRect( 20, y - 26, 600, 18) bold: NO];
    [layoutStatus setFont: [NSFont systemFontOfSize: 11]];
    [cv addSubview: layoutStatus];
}

#pragma mark - SekhVet Paket AX: MPR-Anordnung

- (NSInteger) layoutPreset
{
    return [layoutPresetPopup indexOfSelectedItem] + SekhmetPresetHeadSpine;
}

- (void) updateLayoutStatus
{
    [layoutStatus setStringValue: [SekhmetOrientation describeMPRLayout: [SekhmetOrientation mprLayoutForPreset: [self layoutPreset]]]];
}

- (IBAction) layoutPresetChanged:(id) sender
{
    [self updateLayoutStatus];
}

- (IBAction) takeMPRLayout:(id) sender
{
    MPRController *c = [SekhmetOrientation frontMPR];
    NSString *err = nil;
    NSArray *layout = [SekhmetOrientation layoutFromMPR: c error: &err];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    if( layout == nil)
    {
        [a setMessageText: NSLocalizedString( @"The MPR layout cannot be taken", nil)];
        [a setInformativeText: err ? err : @""];
        [a runModal];
        return;
    }
    NSInteger preset = [self layoutPreset];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Use this layout for \"%@\"?", nil), [[SekhmetOrientation presetNames] objectAtIndex: preset]]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"From \"%@\":\n%@\n\nEvery MPR window opened or switched to this preset will be arranged like this.", nil),
                            [[c window] title], [SekhmetOrientation describeMPRLayout: layout]]];
    [a addButtonWithTitle: NSLocalizedString( @"Use layout", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    [SekhmetOrientation setMPRLayout: layout forPreset: preset];
    [self updateLayoutStatus];
    NSLog( @"SekhVet MPR-Anordnung fuer Preset %d uebernommen: %@", (int) preset, [SekhmetOrientation describeMPRLayout: layout]);
}

- (IBAction) resetMPRLayout:(id) sender
{
    [SekhmetOrientation setMPRLayout: nil forPreset: [self layoutPreset]];
    [self updateLayoutStatus];
}

#pragma mark - Defaults <-> UI

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    [presetPopup selectItemAtIndex: [d integerForKey: SekhmetVetPresetKey]];

    for( NSButton *b in ruleButtons)
    {
        NSInteger p = [b tag] / 10, r = [b tag] % 10;
        NSDictionary *rules = [SekhmetOrientation rulesForPreset: p];
        [b setState: [[rules objectForKey: kRuleKeys[ r]] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
    }

    [keywords removeAllObjects];
    for( NSDictionary *k in [d arrayForKey: SekhmetVetKeywordsKey])
        [keywords addObject: [[k mutableCopy] autorelease]];
    [dxRules removeAllObjects];
    for( NSDictionary *k in [d arrayForKey: SekhmetDXRulesKey])
        [dxRules addObject: [[k mutableCopy] autorelease]];

    [keywordTable reloadData];
    [dxTable reloadData];
}

- (void) saveTables
{
    [[NSUserDefaults standardUserDefaults] setObject: keywords forKey: SekhmetVetKeywordsKey];
    [[NSUserDefaults standardUserDefaults] setObject: dxRules forKey: SekhmetDXRulesKey];
}

- (IBAction) presetChanged:(id) sender
{
    [[NSUserDefaults standardUserDefaults] setInteger: [presetPopup indexOfSelectedItem] forKey: SekhmetVetPresetKey];
}

- (IBAction) ruleChanged:(id) sender
{
    NSInteger p = [sender tag] / 10;
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    for( NSButton *b in ruleButtons)
    {
        if( [b tag] / 10 == p)
            [rules setObject: [NSNumber numberWithBool: ([b state] == NSControlStateValueOn)] forKey: kRuleKeys[ [b tag] % 10]];
    }
    [SekhmetOrientation setRules: rules forPreset: p];
}

- (IBAction) addKeyword:(id) sender
{
    [keywords addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: @"", @"keyword", [NSNumber numberWithInteger: SekhmetPresetHeadSpine], @"preset", nil]];
    [self saveTables]; [keywordTable reloadData];
    [keywordTable editColumn: 0 row: keywords.count - 1 withEvent: nil select: YES];
}

- (IBAction) removeKeyword:(id) sender
{
    NSInteger r = [keywordTable selectedRow];
    if( r >= 0 && r < (NSInteger) keywords.count) { [keywords removeObjectAtIndex: r]; [self saveTables]; [keywordTable reloadData]; }
}

- (IBAction) addDXRule:(id) sender
{
    [dxRules addObject: [NSMutableDictionary dictionaryWithObjectsAndKeys: @"DX", @"match", [NSNumber numberWithFloat: 0], @"rotation", [NSNumber numberWithBool: NO], @"xFlipped", [NSNumber numberWithBool: NO], @"yFlipped", nil]];
    [self saveTables]; [dxTable reloadData];
    [dxTable editColumn: 0 row: dxRules.count - 1 withEvent: nil select: YES];
}

- (IBAction) removeDXRule:(id) sender
{
    NSInteger r = [dxTable selectedRow];
    if( r >= 0 && r < (NSInteger) dxRules.count) { [dxRules removeObjectAtIndex: r]; [self saveTables]; [dxTable reloadData]; }
}

- (IBAction) resetKeywords:(id) sender
{
    [[NSUserDefaults standardUserDefaults] removeObjectForKey: SekhmetVetKeywordsKey];
    [self loadFromDefaults];
}

- (IBAction) applyNow:(id) sender
{
    [self saveTables];
    [SekhmetOrientation applyToAllViewersOfStudyUID: nil];
}

#pragma mark - Tabellen

- (NSMutableArray*) arrayForTable:(NSTableView*) tv
{
    return [[tv identifier] isEqualToString: @"dx"] ? dxRules : keywords;
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    return [self arrayForTable: tv].count;
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    NSMutableDictionary *d = [[self arrayForTable: tv] objectAtIndex: row];
    NSString *ident = [col identifier];
    if( [ident isEqualToString: @"Keyword"]) return [d objectForKey: @"keyword"];
    if( [ident isEqualToString: @"Preset"]) return [d objectForKey: @"preset"];
    if( [ident isEqualToString: @"Match"]) return [d objectForKey: @"match"];
    if( [ident isEqualToString: @"Rotation °"]) return [d objectForKey: @"rotation"];
    if( [ident isEqualToString: @"Flip ↔"]) return [d objectForKey: @"xFlipped"];
    if( [ident isEqualToString: @"Flip ↕"]) return [d objectForKey: @"yFlipped"];
    return nil;
}

- (void) tableView:(NSTableView*) tv setObjectValue:(id) value forTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    NSMutableDictionary *d = [[self arrayForTable: tv] objectAtIndex: row];
    NSString *ident = [col identifier];
    if( value == nil) value = @"";
    if( [ident isEqualToString: @"Keyword"]) [d setObject: value forKey: @"keyword"];
    else if( [ident isEqualToString: @"Preset"]) [d setObject: [NSNumber numberWithInteger: [value integerValue]] forKey: @"preset"];
    else if( [ident isEqualToString: @"Match"]) [d setObject: value forKey: @"match"];
    else if( [ident isEqualToString: @"Rotation °"]) [d setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"rotation"];
    else if( [ident isEqualToString: @"Flip ↔"]) [d setObject: [NSNumber numberWithBool: [value boolValue]] forKey: @"xFlipped"];
    else if( [ident isEqualToString: @"Flip ↕"]) [d setObject: [NSNumber numberWithBool: [value boolValue]] forKey: @"yFlipped"];
    [self saveTables];
}

@end
