/*=========================================================================
 Sekhmet — DICOMweb (QIDO-RS Suche, WADO-RS Abruf) als eigenes Fenster.
 Abgerufene Studien landen als Dateien in INCOMING.noindex der aktiven
 Datenbank; Horos importiert sie von selbst. Knoten (Name, URL, Benutzer)
 liegen in den Einstellungen, das Passwort im Schluesselbund.
 SekhVet Paket CS: results and retrieve jobs are bound to their node; plain
 http with credentials to a public host asks once per node; STOW reports
 "not confirmed" unless the node returned a store confirmation; WADO writes
 only DICOM bodies; server JSON is type-checked.
 SekhVet Paket DN (04.10.2026): filter by institution (field and a list
 stored per node), automatic refresh every 1-30 minutes like OsiriX'
 auto query/retrieve, optionally retrieving new results by itself.
 Menue "Sekhmet > DICOMweb-Abfrage…".
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

extern NSString* const SekhmetDICOMwebNodesKey;   // Array von {name, url, user}

@interface SekhmetDICOMweb : NSWindowController <NSTableViewDataSource, NSOutlineViewDataSource, NSOutlineViewDelegate, NSURLSessionDelegate, NSURLSessionDataDelegate, NSMenuDelegate>
{
    NSPopUpButton *nodePopup, *periodPopup; // Paket R: Zeitraum
    NSTextField *nameField, *idField, *dateFromField, *dateToField, *modalityField;
    NSOutlineView *resultTable;       // Paket AM: Studien mit aufklappbaren Serien
    NSMutableArray *results;          // Array von NSMutableDictionary (aufbereitet); "children" = Serien, sobald geladen
    NSProgressIndicator *progress;
    NSTextField *statusField;
    NSButton *retrieveButton, *searchButton;

    // Knotenverwaltung
    NSTableView *nodeTable;
    NSMutableArray *nodes;
    NSSecureTextField *passwordField;

    // Abruf
    NSURLSession *session;
    NSURLSessionTask *retrieveTask;    // nur dessen Delegate-Callbacks zaehlen
    BOOL multipartStarted;             // Stream-Parser: erster Delimiter gesehen
    NSUInteger scanPos;                // Stream-Parser: ab hier nach dem naechsten Delimiter suchen
    NSString *retrieveStamp;

    // Senden (STOW-RS) -- SekhVet Paket CS: always in a background thread (sendPaths:toNode:…), no send state in the window
    NSButton *stowButton;
    NSMutableData *receivedData;
    NSString *retrieveBoundary;
    NSString *retrieveStudyUID;
    NSString *retrieveJob;             // SekhVet Paket BU: laufender Auftrag "<StudyUID>" oder "<StudyUID>|<SeriesUID>"
    int failedJobs;                    // SekhVet Paket BU: Fehlschlaege dieser Warteschlange
    NSString *lastRetrieveError;
    long long expectedLength;
    long long receivedLength;
    int filesWritten;
    NSMutableSet *retrieveAfterLoad;   // SekhVet Paket BS: StudyUIDs, deren fehlende Serien nach dem Laden der Serienliste geholt werden
    NSMutableSet *quietLoads;          // SekhVet Paket BS: Serienliste still nachladen (ohne Aufklappen), um Berichte aus dem Soll zu nehmen

    // SekhVet Paket CS: results and retrieve jobs are bound to the node they came from
    NSDictionary *resultsNode;         // snapshot {name, url, user} of the node that answered the search shown in the list
    NSMutableArray *retrieveQueue;     // NSDictionary {job: "<StudyUID>[|<SeriesUID>]", node: snapshot}; in memory only
    NSDictionary *retrieveNode;        // node of the running job
    NSMutableSet *quietTried;          // StudyUIDs whose series list was already loaded quietly for this result list
    NSButton *stopButton;              // stops the running retrieve and clears the queue
    BOOL retrieveIncomplete;           // running job: non-DICOM part, truncated stream or failed write

    // SekhVet Paket DN: filter by institution, institution list per node, automatic refresh / retrieve
    NSTextField *institutionField;     // part of the institution name, several separated by ";" (filtered here, not on the node)
    NSButton *institutionFilterButton; // "Only listed institutions": the list stored with the node (key "institutions")
    NSPopUpButton *autoPopup;          // Off / every 1 ... 30 minutes (tag = minutes)
    NSButton *autoRetrieveButton;      // retrieve new results of an automatic refresh
    NSTimer *autoTimer;
    NSMutableDictionary *autoRetrieved; // StudyInstanceUID -> image count of the node when it was retrieved automatically (this session)
    int hiddenByInstitution;           // results of the last search hidden by the institution filters
    // SekhVet Paket DN-2: choose the institution list from what the node really has
    NSButton *chooseInstitutionsButton;
    NSWindow *pickerWindow;            // sheet: one row per institution of the node, checkbox = show
    NSTableView *pickerTable;
    NSTextField *pickerStatus;
    NSButton *pickerSaveButton;
    NSMutableArray *pickerItems;       // NSMutableDictionary {name, count, on}
    NSMutableDictionary *pickerCounts; // name -> NSNumber studies, while the pages come in
    NSDictionary *pickerNode;          // node the list is read from and saved to
    int pickerGeneration;              // a closed / reopened sheet ignores answers of the earlier one
}

+ (SekhmetDICOMweb*) shared;
+ (NSString*) passwordForNode:(NSDictionary*) node;
+ (BOOL) setPassword:(NSString*) pw forNode:(NSDictionary*) node;   // SekhVet Paket CS: YES = stored in the keychain; NO = refused, kept for this session only
+ (NSArray*) selectedDICOMPaths;                 // DICOM-Dateien der im Browser markierten Studien/Serien/Bilder
+ (NSDictionary*) localStatusForStudyUID:(NSString*) studyUID;  // Paket AM: {series: {seriesUID -> Bildzahl lokal}, images: Gesamtzahl}
- (IBAction) stow:(id) sender;                  // markierte Studien an den gewaehlten Knoten (STOW-RS)
- (void) stowPaths:(NSArray*) paths;            // an den im Fenster gewaehlten Knoten, im Hintergrund (Aktivitaetsliste, Mitteilung am Ende)
// SekhVet Paket CH: Senden direkt aus der Datenbank -- Untermenue mit einem Eintrag je Knoten,
// Versand im Hintergrund mit Fortschritt in Horos' Aktivitaetsliste und Mitteilung am Ende
+ (NSMenuItem*) sendMenuItemWithTitle:(NSString*) title;
- (IBAction) sendToNode:(id) sender;            // Tag = Index in SekhmetDICOMwebNodesKey
// SekhVet Paket DN: called once after launch -- starts the automatic refresh if it was on when SekhVet quit
+ (void) startAutoRefreshIfConfigured;
#if SEKHVET_TESTHAKEN
- (void) debugStowFromEnvironment;              // SEKHVET_STOW_TEST="a.dcm:b.dcm" [+ SEKHVET_DICOMWEB_PW], Knoten 0 (muss im Fenster angelegt sein)
- (void) debugWadoFromEnvironment;              // SEKHVET_WADO_TEST="<StudyInstanceUID>" [+ SEKHVET_DICOMWEB_PW], Knoten 0
- (void) debugLocalListFromEnvironment;         // SekhVet Paket AM: SEKHVET_DICOMWEB_LIST_TEST="<Namensteil>" — Bestandsanzeige + Serien-Aufklappen
#endif // SEKHVET_TESTHAKEN

@end
