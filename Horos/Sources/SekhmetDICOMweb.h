/*=========================================================================
 Sekhmet — DICOMweb (QIDO-RS Suche, WADO-RS Abruf) als eigenes Fenster.
 Abgerufene Studien landen als Dateien in INCOMING.noindex der aktiven
 Datenbank; Horos importiert sie von selbst. Knoten (Name, URL, Benutzer)
 liegen in den Einstellungen, das Passwort im Schluesselbund.
 Menue "Sekhmet > DICOMweb-Abfrage…".
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

extern NSString* const SekhmetDICOMwebNodesKey;   // Array von {name, url, user}

@interface SekhmetDICOMweb : NSWindowController <NSTableViewDataSource, NSTableViewDelegate, NSOutlineViewDataSource, NSOutlineViewDelegate, NSURLSessionDelegate, NSURLSessionDataDelegate>
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

    // Senden (STOW-RS)
    NSURLSessionTask *stowTask;
    NSString *stowTempPath;
    int stowFileCount;
    NSButton *stowButton;
    NSMutableData *receivedData;
    NSString *retrieveBoundary;
    NSString *retrieveStudyUID;
    long long expectedLength;
    long long receivedLength;
    int filesWritten;
}

+ (SekhmetDICOMweb*) shared;
+ (NSString*) passwordForNode:(NSDictionary*) node;
+ (void) setPassword:(NSString*) pw forNode:(NSDictionary*) node;
+ (NSArray*) selectedDICOMPaths;                 // DICOM-Dateien der im Browser markierten Studien/Serien/Bilder
+ (NSDictionary*) localStatusForStudyUID:(NSString*) studyUID;  // Paket AM: {series: {seriesUID -> Bildzahl lokal}, images: Gesamtzahl}
- (IBAction) stow:(id) sender;                  // markierte Studien an den gewaehlten Knoten (STOW-RS)
- (void) stowPaths:(NSArray*) paths;
#if SEKHVET_TESTHAKEN
- (void) debugStowFromEnvironment;              // SEKHVET_STOW_TEST="a.dcm:b.dcm" [+ SEKHVET_DICOMWEB_PW], Knoten 0 (muss im Fenster angelegt sein)
- (void) debugWadoFromEnvironment;              // SEKHVET_WADO_TEST="<StudyInstanceUID>" [+ SEKHVET_DICOMWEB_PW], Knoten 0
- (void) debugLocalListFromEnvironment;         // SekhVet Paket AM: SEKHVET_DICOMWEB_LIST_TEST="<Namensteil>" — Bestandsanzeige + Serien-Aufklappen
#endif // SEKHVET_TESTHAKEN

@end
