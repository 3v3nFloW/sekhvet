/*=========================================================================
 Sekhmet — Einstellungsfenster fuer die Vet-Orientierung. Siehe Header.
 ============================================================================*/

#import "SekhmetOrientationPanel.h"
#import "SekhmetDisplayPanel.h"
#import "SekhmetOrientation.h"
#import "MPRController.h"   // SekhVet Paket AX

static SekhmetOrientationPanel *sekhmetPanel = nil;

static NSString* const kRowType = @"vet.kappa1.sekhvet.protocolrow";   // SekhVet Paket BP: Zeile ziehen = Reihenfolge
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
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 640, 700)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable   // SekhVet Paket BS: groesser und skalierbar
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Hanging Protocol", nil)];
    [w setReleasedWhenClosed: NO];

    self = [super initWithWindow: w];
    if( self)
    {
        ruleButtons = [[NSMutableArray alloc] init];
        keywords = [[NSMutableArray alloc] init];
        dxRules = [[NSMutableArray alloc] init];
        protocols = [[NSMutableArray alloc] init];
        [self buildUI];
        [self loadFromDefaults];
        [w setContentMinSize: NSMakeSize( 640, 700)];
        [w setContentSize: NSMakeSize( 760, 820)];   // die Masken aus buildUI verteilen den Zuwachs
        [w center];
        [w setFrameAutosaveName: @"SekhmetHangingProtocolPanel"];
    }
    return self;
}

- (void) dealloc
{
    [ruleButtons release];
    [keywords release];
    [dxRules release];
    [protocols release];
    [super dealloc];
}

- (IBAction) showWindow:(id) sender
{
    MPRController *c = [SekhmetOrientation frontMPR];   // SekhVet Paket AX: das Preset, unter dem man gerade anordnet
    NSInteger p = c ? [SekhmetOrientation presetForMPR: c] : SekhmetPresetOff;
    [self loadFromDefaults];
    if( p != SekhmetPresetOff) [self selectProtocol: p];
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
            [pc setMenu: [SekhmetOrientation presetMenuIncludingOff: YES]];
            [pc setBordered: NO];
            keywordPresetCell = pc;
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
    float y = 700 - 40;   // SekhVet Paket AX: 80 pt mehr fuer die MPR-Anordnung unten

    [cv addSubview: [self label: NSLocalizedString( @"Default preset (used when no keyword matches):", nil) frame: NSMakeRect( 20, y, 360, 20) bold: YES]];
    presetPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 380, y - 4, 240, 26) pullsDown: NO] autorelease];
    [presetPopup setMenu: [SekhmetOrientation presetMenuIncludingOff: YES]];
    [presetPopup setTarget: self]; [presetPopup setAction: @selector(presetChanged:)];
    [cv addSubview: presetPopup];

    // SekhVet Paket BP: links die Protokoll-Liste (umbenennen per Doppelklick, Reihenfolge per Ziehen, +/-),
    // rechts die fuenf Regeln des markierten Protokolls. Vorher: festes Raster Regel x fuenf Presets.
    NSArray *ruleTitles = [NSArray arrayWithObjects:
                           NSLocalizedString( @"Transverse: dorsal up (else ventral up)", nil),
                           NSLocalizedString( @"Sagittal: cranial left (else cranial/proximal up)", nil),
                           NSLocalizedString( @"Dorsal plane: cranial up (else cranial left)", nil),
                           NSLocalizedString( @"Patient left on the right side of the image", nil),
                           NSLocalizedString( @"Limb: proximal = caudal (forelimb) → caudal up", nil), nil];

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Protocols (double-click = rename, drag = reorder)", nil) frame: NSMakeRect( 20, y, 300, 20) bold: YES]];
    ruleHeading = [self label: @"" frame: NSMakeRect( 330, y, 290, 20) bold: YES];
    [cv addSubview: ruleHeading];

    NSScrollView *psv = [self tableWithFrame: NSMakeRect( 20, y - 186, 250, 182) identifier: @"protocols"
                                     columns: [NSArray arrayWithObjects: @"Name", nil]
                                      widths: [NSArray arrayWithObjects: @"225", nil]];
    protocolTable = (NSTableView*) [psv documentView];
    [protocolTable setHeaderView: nil];
    [protocolTable registerForDraggedTypes: [NSArray arrayWithObject: kRowType]];
    [protocolTable setDraggingSourceOperationMask: NSDragOperationMove forLocal: YES];
    [cv addSubview: psv];
    [cv addSubview: [self button: @"+" frame: NSMakeRect( 274, y - 32, 40, 26) action: @selector(addProtocol:) tag: 0]];
    removeProtocolButton = [self button: @"−" frame: NSMakeRect( 274, y - 60, 40, 26) action: @selector(removeProtocol:) tag: 0];
    [cv addSubview: removeProtocolButton];

    float ry = y - 24;
    for( int r = 0; r < 5; r++)
    {
        NSButton *b = [[[NSButton alloc] initWithFrame: NSMakeRect( 330, ry, 300, 18)] autorelease];
        [b setButtonType: NSButtonTypeSwitch];
        [b setTitle: [ruleTitles objectAtIndex: r]];
        [b setFont: [NSFont systemFontOfSize: 11]];
        [b setTag: r];
        [b setTarget: self]; [b setAction: @selector(ruleChanged:)];
        [cv addSubview: b];
        [ruleButtons addObject: b];
        ry -= 21;
    }
    y -= 190;

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
    [cv addSubview: [self label: NSLocalizedString( @"MPR layout — arrange an MPR window as you want it, then take it for the protocol selected above:", nil) frame: NSMakeRect( 20, y, 600, 20) bold: YES]];
    y -= 30;
    layoutHeading = [self label: @"" frame: NSMakeRect( 20, y + 2, 155, 20) bold: NO];
    [cv addSubview: layoutHeading];
    [cv addSubview: [self button: NSLocalizedString( @"Take from screen", nil) frame: NSMakeRect( 180, y - 3, 150, 30) action: @selector(takeMPRLayout:) tag: 0]];
    [cv addSubview: [self button: NSLocalizedString( @"Standard layout", nil) frame: NSMakeRect( 335, y - 3, 140, 30) action: @selector(resetMPRLayout:) tag: 0]];
    layoutStatus = [self label: @"" frame: NSMakeRect( 20, y - 26, 600, 18) bold: NO];
    [layoutStatus setFont: [NSFont systemFontOfSize: 11]];
    [cv addSubview: layoutStatus];

    // SekhVet Paket BS: Fenster skalierbar. Die Stichwort-Tabelle nimmt die Hoehe auf; was darueber liegt, haengt oben,
    // was darunter liegt, unten. In der Breite wachsen die drei Tabellen, alles rechts davon haengt am rechten Rand.
    for( NSView *s in [cv subviews])
    {
        NSUInteger m = 0;
        if( s == ksv) m = NSViewWidthSizable | NSViewHeightSizable;
        else
        {
            m = NSMinY( [s frame]) >= NSMinY( [ksv frame]) + 60 ? NSViewMinYMargin : NSViewMaxYMargin;   // +60: die +/- Knoepfe neben der Tabelle haengen oben
            if( s == psv || s == dsv) m |= NSViewWidthSizable;
            else if( NSMinX( [s frame]) >= 270) m |= NSViewMinXMargin;
        }
        [s setAutoresizingMask: m];
    }
}

#pragma mark - SekhVet Paket AX: MPR-Anordnung

- (NSInteger) selectedProtocol   // SekhVet Paket BP: id des markierten Protokolls
{
    NSInteger r = [protocolTable selectedRow];
    if( r < 0 || r >= (NSInteger) protocols.count) return SekhmetPresetOff;
    return [[[protocols objectAtIndex: r] objectForKey: @"id"] integerValue];
}

- (void) selectProtocol:(NSInteger) preset
{
    for( NSUInteger i = 0; i < protocols.count; i++)
        if( [[[protocols objectAtIndex: i] objectForKey: @"id"] integerValue] == preset)
            [protocolTable selectRowIndexes: [NSIndexSet indexSetWithIndex: i] byExtendingSelection: NO];
    [self protocolSelectionChanged];
}

- (NSInteger) layoutPreset
{
    return [self selectedProtocol];
}

- (void) updateLayoutStatus
{
    NSInteger p = [self layoutPreset];
    [layoutHeading setStringValue: p == SekhmetPresetOff ? @"" : [SekhmetOrientation nameForPreset: p]];
    [layoutStatus setStringValue: p == SekhmetPresetOff ? @"" : [SekhmetOrientation describeMPRLayout: [SekhmetOrientation mprLayoutForPreset: p]]];
}

- (void) protocolSelectionChanged
{
    NSInteger p = [self selectedProtocol];
    NSDictionary *rules = p == SekhmetPresetOff ? nil : [SekhmetOrientation rulesForPreset: p];
    for( NSButton *b in ruleButtons)
    {
        [b setEnabled: rules != nil];
        [b setState: [[rules objectForKey: kRuleKeys[ [b tag]]] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
    }
    [ruleHeading setStringValue: p == SekhmetPresetOff ? @"" : [NSString stringWithFormat: NSLocalizedString( @"Rules for \"%@\"", nil), [SekhmetOrientation nameForPreset: p]]];
    [removeProtocolButton setEnabled: [SekhmetOrientation canRemovePreset: p]];
    [self updateLayoutStatus];
}

- (void) tableViewSelectionDidChange:(NSNotification*) n
{
    if( [n object] == protocolTable) [self protocolSelectionChanged];
}

- (void) saveProtocols   // Liste speichern, alle Menues (Panel + Toolbars) folgen
{
    NSInteger keep = [self selectedProtocol], def = [[presetPopup selectedItem] tag];
    [SekhmetOrientation setProtocolList: protocols];
    [self reloadPresetMenus];
    [presetPopup selectItemWithTag: [SekhmetOrientation presetExists: def] ? def : SekhmetPresetHeadSpine];
    [protocolTable reloadData];
    [self selectProtocol: keep];
    [keywordTable reloadData];
}

- (void) reloadPresetMenus
{
    [presetPopup setMenu: [SekhmetOrientation presetMenuIncludingOff: YES]];
    [keywordPresetCell setMenu: [SekhmetOrientation presetMenuIncludingOff: YES]];
}

- (IBAction) addProtocol:(id) sender
{
    NSInteger p = [SekhmetOrientation addProtocolNamed: nil];
    [self loadFromDefaults];
    [self selectProtocol: p];
    [protocolTable editColumn: 0 row: [protocolTable selectedRow] withEvent: nil select: YES];
}

- (IBAction) removeProtocol:(id) sender
{
    NSInteger p = [self selectedProtocol];
    if( [SekhmetOrientation canRemovePreset: p] == NO) return;
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Delete the protocol \"%@\"?", nil), [SekhmetOrientation nameForPreset: p]]];
    [a setInformativeText: NSLocalizedString( @"Its rules, MPR layout and keywords are deleted too. Studies that used it fall back to the keyword or default protocol.", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Delete", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    [SekhmetOrientation removeProtocol: p];
    [self loadFromDefaults];
    [SekhmetOrientation applyToAllViewersOfStudyUID: nil];
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
    if( preset == SekhmetPresetOff) return;
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Use this layout for \"%@\"?", nil), [SekhmetOrientation nameForPreset: preset]]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"From \"%@\":\n%@\n\nEvery MPR window opened or switched to this preset will be arranged like this.", nil),
                            [[c window] title], [SekhmetOrientation describeMPRLayout: layout]]];
    [a addButtonWithTitle: NSLocalizedString( @"Use layout", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    [SekhmetOrientation setMPRLayout: layout forPreset: preset];
    [self updateLayoutStatus];
    NSLog( @"SekhVet MPR layout taken for preset %d: %@", (int) preset, [SekhmetOrientation describeMPRLayout: layout]);
}

- (IBAction) resetMPRLayout:(id) sender
{
    if( [self layoutPreset] == SekhmetPresetOff) return;
    [SekhmetOrientation setMPRLayout: nil forPreset: [self layoutPreset]];
    [self updateLayoutStatus];
}

#pragma mark - Defaults <-> UI

- (void) loadFromDefaults
{
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSInteger keep = [self selectedProtocol];
    [self reloadPresetMenus];
    NSInteger def = [d integerForKey: SekhmetVetPresetKey];
    [presetPopup selectItemWithTag: [SekhmetOrientation presetExists: def] ? def : SekhmetPresetHeadSpine];

    [protocols removeAllObjects];
    for( NSDictionary *k in [SekhmetOrientation protocolList])
        [protocols addObject: [[k mutableCopy] autorelease]];
    [protocolTable reloadData];
    [self selectProtocol: [SekhmetOrientation presetExists: keep] && keep != SekhmetPresetOff ? keep : SekhmetPresetHeadSpine];

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
    [[NSUserDefaults standardUserDefaults] setInteger: [[presetPopup selectedItem] tag] forKey: SekhmetVetPresetKey];
}

- (IBAction) ruleChanged:(id) sender
{
    NSInteger p = [self selectedProtocol];
    if( p == SekhmetPresetOff) return;
    NSMutableDictionary *rules = [NSMutableDictionary dictionary];
    for( NSButton *b in ruleButtons)
        [rules setObject: [NSNumber numberWithBool: ([b state] == NSControlStateValueOn)] forKey: kRuleKeys[ [b tag]]];
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
    if( [[tv identifier] isEqualToString: @"protocols"]) return protocols;
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
    if( [ident isEqualToString: @"Name"]) return [d objectForKey: @"name"];
    if( [ident isEqualToString: @"Preset"])   // SekhVet Paket BP: gespeichert ist die id, die Zelle will den Menue-Index
    {
        NSInteger idx = [[keywordPresetCell menu] indexOfItemWithTag: [[d objectForKey: @"preset"] integerValue]];
        return [NSNumber numberWithInteger: idx < 0 ? 0 : idx];
    }
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
    else if( [ident isEqualToString: @"Name"])
    {
        NSString *name = [[value description] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
        if( name.length == 0) return;
        [d setObject: name forKey: @"name"];
        [self saveProtocols];
        return;
    }
    else if( [ident isEqualToString: @"Preset"])
    {
        NSMenuItem *mi = [[keywordPresetCell menu] itemAtIndex: MAX( 0, MIN( [value integerValue], [[keywordPresetCell menu] numberOfItems] - 1))];
        [d setObject: [NSNumber numberWithInteger: [mi tag]] forKey: @"preset"];
    }
    else if( [ident isEqualToString: @"Match"]) [d setObject: value forKey: @"match"];
    else if( [ident isEqualToString: @"Rotation °"]) [d setObject: [NSNumber numberWithFloat: [value floatValue]] forKey: @"rotation"];
    else if( [ident isEqualToString: @"Flip ↔"]) [d setObject: [NSNumber numberWithBool: [value boolValue]] forKey: @"xFlipped"];
    else if( [ident isEqualToString: @"Flip ↕"]) [d setObject: [NSNumber numberWithBool: [value boolValue]] forKey: @"yFlipped"];
    [self saveTables];
}

#pragma mark - SekhVet Paket BP: Reihenfolge per Ziehen

- (id <NSPasteboardWriting>) tableView:(NSTableView*) tv pasteboardWriterForRow:(NSInteger) row
{
    if( tv != protocolTable) return nil;
    NSPasteboardItem *it = [[[NSPasteboardItem alloc] init] autorelease];
    [it setString: [NSString stringWithFormat: @"%d", (int) row] forType: kRowType];
    return it;
}

- (NSDragOperation) tableView:(NSTableView*) tv validateDrop:(id <NSDraggingInfo>) info proposedRow:(NSInteger) row proposedDropOperation:(NSTableViewDropOperation) op
{
    if( tv != protocolTable || [info draggingSource] != protocolTable) return NSDragOperationNone;
    if( op == NSTableViewDropOn) [tv setDropRow: row dropOperation: NSTableViewDropAbove];
    return NSDragOperationMove;
}

- (BOOL) tableView:(NSTableView*) tv acceptDrop:(id <NSDraggingInfo>) info row:(NSInteger) row dropOperation:(NSTableViewDropOperation) op
{
    if( tv != protocolTable) return NO;
    NSString *s = [[info draggingPasteboard] stringForType: kRowType];
    if( s == nil) return NO;
    NSInteger from = [s integerValue];
    if( from < 0 || from >= (NSInteger) protocols.count) return NO;
    id item = [[[protocols objectAtIndex: from] retain] autorelease];
    [protocols removeObjectAtIndex: from];
    if( row > from) row--;
    row = MAX( 0, MIN( row, (NSInteger) protocols.count));
    [protocols insertObject: item atIndex: row];
    [protocolTable selectRowIndexes: [NSIndexSet indexSetWithIndex: row] byExtendingSelection: NO];
    [self saveProtocols];
    return YES;
}

@end
