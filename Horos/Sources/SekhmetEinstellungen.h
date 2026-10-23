/*=========================================================================
 SekhVet Paket DZ — Vet-Einstellungen: Sicherung bei jedem neuen Build, Export/Import, Praxis-Einstellungsordner,
 neue Vorgaben anbieten. Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Praemissen (Klaerungsrunde 08.10.2026, Entscheid des Eigentuemers):
 - Gruppen zum Anhaken: Opening protocols, Hanging protocols & orientation, Window rules & WL/WW presets, Display &
   annotations, Overlay & keys, Measurement tools, Network targets (DICOM/DICOMweb nodes, never passwords; must be
   ticked on purpose when settings are taken over).
 - Never contained: passwords/keychain, routing rules, listener, Bonjour, database sharing, web portal, plugins, database
   locations and local paths, screen areas, window positions, install UUID, update consent. Unknown keys are dropped.
 - A backup of all groups is written on the first start of every new build and before every import or take-over
   (~/Library/Application Support/SekhVet/Settings Backups, the newest 20 stay).
 - Taking over a group replaces the group as a whole (the backup holds the previous state).
 - Practice settings folder (e.g. on a NAS): no Bonjour, no open port. Every Mac checks it at start and whenever SekhVet
   comes to the front; a new version is offered with a preview (Apply / Reject / Later), "apply without asking" is off
   by default.
 - Every group has a defaults version; when it rises and the user has own values, SekhVet asks once per start
   (Replace / View / Not Now).
 ============================================================================*/

#import <Foundation/Foundation.h>
#ifndef SEKHVET_LOGIC_TEST
#include "SekhmetTesthaken.h"
#endif

extern NSString* const SekhmetSettingsFileExtension;          // "sekhvet-settings"
extern NSString* const SekhmetPracticeSettingsFolderKey;      // path of the practice settings folder (machine setting, never exported)
extern NSString* const SekhmetPracticeSettingsAutoApplyKey;   // BOOL, default NO

@interface SekhmetEinstellungen : NSObject

// ---- pure logic (Foundation only; SekhVet/test/einstellungen-test.sh compiles this part with SEKHVET_LOGIC_TEST) ----
+ (NSArray*) gruppen;                                          // group ids in display order
+ (NSString*) titelFuerGruppe:(NSString*) gruppe;              // English title
+ (BOOL) istGesperrt:(NSString*) schluessel;                    // never exported or taken over
+ (NSString*) gruppeFuerSchluessel:(NSString*) schluessel;     // nil = not part of any group (or blocked)
+ (id) bereinigt:(id) wert;                                     // copy without password-like entries (recursive)
+ (NSDictionary*) gruppenAus:(NSDictionary*) domain gruppen:(NSArray*) gruppen;   // { group: { key: value } }
// The domain after taking over these groups from "werte" ({ group: { key: value } }): every key of a taken group is
// removed first (it falls back to the built-in default), then the values of the file are set. Other keys stay.
+ (NSDictionary*) domain:(NSDictionary*) domain nachUebernahmeVon:(NSDictionary*) werte gruppen:(NSArray*) gruppen;
+ (NSString*) zusammenfassungVon:(NSDictionary*) alt nach:(NSDictionary*) neu gruppe:(NSString*) gruppe;   // nil = no change
+ (NSDictionary*) dateiInhaltAus:(NSDictionary*) gruppenWerte build:(NSInteger) build version:(NSString*) version rechner:(NSString*) rechner;
+ (NSDictionary*) gepruefterDateiInhalt:(id) plist fehler:(NSString**) fehler;   // nil = not a SekhVet settings file
+ (NSDictionary*) vorgabeVersionen;                             // { group: NSNumber }

@end

#ifndef SEKHVET_LOGIC_TEST
@interface SekhmetEinstellungen (App)
+ (void) merkeErstenStart;     // SekhVet Paket EF: from main(), before anything writes: empty domain = fresh install
+ (void) beimStart;            // backup for a new build, defaults offer, practice folder (called once after launch)
+ (void) wurdeAktiv;           // practice folder check when SekhVet comes to the front
+ (NSMenu*) menu;              // Vet Tools > Vet Settings
#if SEKHVET_TESTHAKEN
+ (void) debugFromEnvironment; // SEKHVET_SETTINGS_TEST=1
#endif
@end
#endif
