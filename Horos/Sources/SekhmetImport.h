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
+ (NSString*) debugImportCPath:(const char*) path;   // lldb-Test ohne GUI: Testpatient, Datei nach INCOMING
+ (void) debugImportFromEnvironment;                 // SEKHVET_IMPORT_TEST="a.jpg:b.pdf" — Testlauf 20 s nach dem Start (AppController)

@end
