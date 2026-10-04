/*=========================================================================
 SekhVet Paket AE — Fensterung (WL/WW) beim Oeffnen einer Serie.
 Regeln je Modalitaet und Stichwort (Studien-/Serienbeschreibung), die erste
 passende Regel gewinnt; Panel "Vet Tools > Window Presets…".
 SekhVet Paket CS: if the series has a convolution kernel, the keywords are
 compared with the kernel only (the description counts for series without
 one). On open, a window the user saved with the series is kept; "Apply to
 open viewers" applies the rules regardless.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>

@class ViewerController;

extern NSString* const SekhmetWLWWRulesKey;        // Array von {modality, keywords, wl, ww, name}
extern NSString* const SekhmetWLWWApplyOnOpenKey;  // BOOL

@interface SekhmetWindowing : NSObject
+ (void) registerDefaults:(NSMutableDictionary*) defaultValues;
+ (NSArray*) defaultRules;
+ (NSDictionary*) ruleForViewer:(ViewerController*) v;
+ (NSDictionary*) ruleForModality:(NSString*) modality description:(NSString*) description;  // SekhVet Paket AU: dieselbe Regel ohne offenen Viewer; kernel as " [kernel]" inside the text
+ (NSDictionary*) ruleForModality:(NSString*) modality kernel:(NSString*) kernel description:(NSString*) description;  // SekhVet Paket CS: kernel passed on its own (nil/empty = none)
+ (BOOL) applyToViewer:(ViewerController*) v;      // on open; YES = eine Regel wurde angewandt
+ (void) applyToAllViewers;
@end

@interface SekhmetWindowingPanel : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
    NSTableView *table;
    NSMutableArray *rules;
    NSButton *applyOnOpenButton;
    NSTableView *presetTable;      // SekhVet Paket BL: globale WL/WW-Presets (WLWW3, Menue im Viewer, Tasten 1-9)
    NSMutableArray *presets;       // {name, wl, ww}, nach Name sortiert wie das Menue
}
+ (SekhmetWindowingPanel*) shared;
@end
