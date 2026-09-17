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
    NSMutableArray *ruleButtons;        // NSButton, tag = preset*10 + regelindex
    NSTableView *keywordTable;
    NSTableView *dxTable;
    NSMutableArray *keywords;           // veraenderliche Kopie der Defaults
    NSMutableArray *dxRules;
    NSPopUpButton *layoutPresetPopup;   // SekhVet Paket AX: MPR-Anordnung je Preset
    NSTextField *layoutStatus;
}

+ (SekhmetOrientationPanel*) shared;

@end
