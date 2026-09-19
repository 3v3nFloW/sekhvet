/*=========================================================================
 Sekhmet — Einstellungsfenster fuer die Vet-Orientierung (programmatisch,
 ohne Nib): Vorgabe-Preset, vier Regeln je Preset, Stichwort-Tabelle,
 DX-Regeln je Geraet. Menue "Sekhmet > Vet-Orientierung…".
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>

@interface SekhmetOrientationPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
    NSPopUpButton *presetPopup;
    NSMutableArray *ruleButtons;        // NSButton, tag = Regelindex; gelten fuer das markierte Protokoll (SekhVet Paket BP)
    NSTableView *protocolTable;         // SekhVet Paket BP: Protokoll-Liste (umbenennen, ziehen, +/-)
    NSMutableArray *protocols;          // veraenderliche Kopie von +protocolList
    NSTextField *ruleHeading, *layoutHeading;
    NSButton *removeProtocolButton;
    NSPopUpButtonCell *keywordPresetCell;
    NSTableView *keywordTable;
    NSTableView *dxTable;
    NSMutableArray *keywords;           // veraenderliche Kopie der Defaults
    NSMutableArray *dxRules;
    NSTextField *layoutStatus;
}

+ (SekhmetOrientationPanel*) shared;

@end
