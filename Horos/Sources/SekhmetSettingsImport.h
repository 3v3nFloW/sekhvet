// Teil des SekhVet-Forks von Horos, LGPL-3.0.
// SekhVet Paket EI (29.10.2026): Einstellungen aus Horos / OsiriX uebernehmen -- Dialog beim ersten Start
// (SekhVet ohne eigene DICOM-Knoten, Quelle gefunden) und jederzeit ueber File / Vet Tools.
// Regel: ergaenzen, nicht ersetzen. Ein Schluessel, der in SekhVets eigenen Prefs schon steht, bleibt;
// Listen (Knoten, Tastenkuerzel, Presets, Hanging) werden gemischt. "Overwrite existing" (Standard aus)
// dreht das um. Horos Data und der Datenbank-Ort werden nie angefasst.

#import <Cocoa/Cocoa.h>

extern NSString* const SekhmetSettingsImportOfferedKey;   // BOOL: Erststart-Dialog wurde schon angeboten

enum { SekhmetListenerKeep = 0, SekhmetListenerNew = 1, SekhmetListenerSame = 2 };

@interface SekhmetSettingsImport : NSWindowController <NSTableViewDataSource, NSTableViewDelegate>
{
    NSMutableArray *sources;        // je Quelle: domain, name, modified (NSDate), prefs (NSDictionary)
    NSMutableArray *nodes;          // je Knoten der gewaehlten Quelle: node (NSDictionary), use (NSNumber), echo (NSString)
    NSPopUpButton *sourcePopup;
    NSMutableDictionary *groupButtons;   // Gruppen-Kennung -> NSButton
    NSTableView *nodeTable;
    NSButton *listenerNewButton, *listenerSameButton;
    NSTextField *aeField, *portField, *listenerHint;
    NSButton *overwriteButton;
    NSTextField *statusField;
    NSButton *importButton;
    int echoGeneration;
}

+ (SekhmetSettingsImport*) shared;
+ (NSArray*) foundSources;              // Quellen mit Prefs, zuletzt geaenderte zuerst
+ (BOOL) hasOwnNodes;                   // SekhVet hat schon einen echten DICOM-Knoten (nicht 127.0.0.1)
+ (void) offerAtStartIfNeeded;          // Erststart: einmalig, nur ohne eigene Knoten und mit Quelle
+ (NSString*) suggestedAETitleFrom:(NSString*) aet;   // "<AE>SV", auf 16 Zeichen gekuerzt
+ (NSString*) sourceAETitle:(NSDictionary*) prefs;    // AETITLE der Quelle, sonst Rechnername (wie Horos ohne AETITLE)
+ (int) sourcePort:(NSDictionary*) prefs domain:(NSString*) domain;   // AEPORT der Quelle, sonst Standardport (Horos 11112, OsiriX 4096)
+ (void) relaunch;                      // SekhVet beenden und wieder oeffnen (Listener-Werte greifen erst nach Neustart)
/** Uebernahme. groups: Menge aus "nodes","listener","hotkeys","presets","display","query". nodes: die gewaehlten Knoten (Dictionaries wie in SERVERS).
    Liefert ein Dictionary mit den Zaehlern je Gruppe ("nodes","listener",…), "backup" (Pfad) und "listenerRestart" (BOOL: Neustart noetig). */
+ (NSDictionary*) importFrom:(NSDictionary*) prefs domain:(NSString*) domain groups:(NSSet*) groups nodes:(NSArray*) selectedNodes listenerMode:(int) mode aeTitle:(NSString*) aet port:(NSString*) port overwrite:(BOOL) overwrite;
+ (NSString*) backupCurrentSettings;    // schreibt die eigenen Prefs als plist, liefert den Pfad (nil bei Fehler)
- (IBAction) show:(id) sender;
#if SEKHVET_TESTHAKEN
+ (void) debugImportFromEnvironment;    // SEKHVET_SETTINGS_IMPORT_TEST=<domain>:<listenerMode>[:<port>]
#endif
@end
