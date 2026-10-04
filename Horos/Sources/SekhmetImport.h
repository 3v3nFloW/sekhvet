/*=========================================================================
 SekhVet — Bild und PDF als DICOM importieren (Paket G).
 Bilder (jpg, jpeg, png, tif, tiff, gif, bmp, heic) werden als Secondary
 Capture geschrieben (DICOMExport, DCMTK), PDFs als Encapsulated PDF
 (DCMObject encapsulatedPDF:) oder wahlweise seitenweise als Bilder.
 Patientendaten kommen aus der im Browser markierten Studie oder von Hand.
 Ausgabe nach INCOMING.noindex der aktiven Datenbank, Horos importiert.
 Menue "SekhVet > Bild / PDF als DICOM importieren…".
 Klassenpraefix bleibt Sekhmet (interner Name des Forks).
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@interface SekhmetImport : NSWindowController
{
    NSTextField *nameField, *idField, *studyDescField, *seriesDescField, *filesLabel, *statusField;
    NSDatePicker *birthPicker, *studyDatePicker;
    NSButton *birthKnownButton, *attachButton, *pdfPagesButton, *importButton;
    NSPopUpButton *sexPopup, *modalityPopup;
    NSMutableArray *files;
    NSString *attachStudyUID;
    NSString *attachStudyTitle;
}

+ (SekhmetImport*) shared;
- (IBAction) chooseFiles:(id) sender;       // Menue: Dateien waehlen, dann Fenster mit Patientendaten
- (void) importPaths:(NSArray*) paths;      // Fenster fuer diese Dateien oeffnen
+ (NSMutableArray*) takeConvertibleFilesFrom:(NSArray*) paths;   // Drag&Drop / Import: Bilder+PDFs abzweigen (Dialog), Rest zurueck

// Kern ohne GUI: schreibt DICOM-Dateien nach dir, liefert die Anzahl. meta: Schluessel wie DICOMExport.metaDataDict
// (patientsName, patientID, patientsBirthdate NSDate, patientsSex, studyDate NSDate, studyDescription, modality)
+ (int) writeFiles:(NSArray*) paths meta:(NSDictionary*) meta studyUID:(NSString*) studyUID seriesDescription:(NSString*) seriesDesc pdfAsPages:(BOOL) pdfAsPages toDirectory:(NSString*) dir;
#if SEKHVET_TESTHAKEN
+ (void) debugImportFromEnvironment;                 // SEKHVET_IMPORT_TEST="a.jpg:b.pdf" — Testlauf 20 s nach dem Start (AppController)
#endif // SEKHVET_TESTHAKEN

@end


/*=========================================================================
 SekhVet — Import aus anderen Datenbanken (Horos, OsiriX, HorliX, Miele-LXIV …).
 Idee: PHORLIX Lite 1.1.6 (Dank an dessen Autor im Fenster), eigene Umsetzung
 auf Horos-Basis, mit Zustimmung des Autors vom 27.09.2026. Ersetzt den Horos-Erststart-Dialog
 O2HMigrationAssistant (nur OsiriX, nur Standardort, nur einmal beim Start).
 Gesucht wird: jeder Ordner in ~/Documents mit DATABASE.noindex (ausser der
 eigenen Datenbank), dazu die eigenen Speicherorte aus den Einstellungen von
 OsiriX und Horos; weitere Orte per "Choose Folder…". Kopiert werden die
 DICOM-Dateien (ROIs liegen dort als DICOM SR mit), Alben/Berichte/
 Einstellungen nicht; die Quelle wird nur gelesen. Bilder, die schon in
 SekhVet liegen, erkennt der Import (SOPInstanceUID) und legt sie nicht doppelt an.
 SekhVet Paket CS: before copying, the size of the other database is compared
 with the free space of the SekhVet volume (warning with "Import Anyway").
 Einstieg: Einstellungen > Database > "Import from Other Databases…" und
 Menue Vet Tools. Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

@interface SekhmetDatenbankImport : NSWindowController <NSTableViewDataSource>
{
    NSTableView *table;
    NSTextField *statusField;
    NSButton *importButton;
    NSMutableArray *quellen;        // NSMutableDictionary: name, pfad (Datenordner), db (DATABASE.noindex), herkunft, inhalt
}

+ (SekhmetDatenbankImport*) shared;
- (IBAction) zeigen:(id) sender;

/** Gefundene Datenbanken: NSDictionary name, pfad, db, herkunft. Ohne die eigene. */
+ (NSArray*) gefundeneQuellen;
/** Zu einem gewaehlten Ordner die Datenbank finden: der Ordner selbst, sein DATABASE.noindex oder ein Unterordner damit. nil = keine. */
+ (NSDictionary*) quelleFuerOrdner:(NSString*) ordner herkunft:(NSString*) herkunft;
/** Dateien aus DATABASE.noindex der Quelle in die aktive Datenbank kopieren (asynchron, Aktivitaetsanzeige). NO = nichts angestossen. */
+ (BOOL) importiere:(NSDictionary*) quelle;
/** Beim Start: einmaliger Hinweis, wenn eine fremde Datenbank da ist (statt O2HMigrationAssistant). */
+ (void) startHinweis;
#if SEKHVET_TESTHAKEN
+ (void) debugDatenbankImportFromEnvironment;   // SEKHVET_DBIMPORT_TEST=<Ordner> oder "liste"
#endif // SEKHVET_TESTHAKEN

@end
