/*=========================================================================
 SekhVet Paket BC — Patient umbenennen (DICOM-Header und Datenbank).
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Horos kennt "Unify patient identity" nur fuer ZWEI oder mehr markierte Studien
 und nimmt die Identitaet aus einer davon. Der Praxisfall ist aber die einzelne
 Roentgenstudie, die am Geraet als "Notfall" registriert wurde und ihren
 richtigen Namen bekommen soll, oder CT und MR desselben Tiers mit leicht
 abweichender Schreibweise. Dieses Fenster nimmt eine oder mehrere Studien,
 laesst Name, Patienten-ID, Geburtsdatum und Geschlecht frei eingeben oder von
 einem vorhandenen Patienten der Datenbank uebernehmen, und schreibt sie wie
 Horos' Unify in die DICOM-Dateien (gdcm ueber XMLController modifyDicom) und
 in die Datenbank. Die alten Werte wandern nach OtherPatientIDs (0010,1000)
 und OtherPatientNames (0010,1001), so wie Horos es tut. Die Datenbank wird
 je Studie erst geaendert, wenn deren Dateien geschrieben sind.
 ============================================================================*/

#import <Cocoa/Cocoa.h>

@class DicomStudy;

@interface SekhmetRename : NSWindowController

+ (SekhmetRename*) shared;
+ (NSArray*) selectedStudies;                       // markierte Studien der Datenbank (Serien -> ihre Studie), ohne Doppelte
- (void) runForStudies:(NSArray*) studies;          // Fenster, vorbelegt mit der ersten Studie

// Motor ohne Dialog. dob/sex nil = unveraendert. Liefert NO, wenn eine Studie nicht geschrieben werden konnte.
+ (BOOL) applyName:(NSString*) name patientID:(NSString*) pid birthDate:(NSDate*) dob sex:(NSString*) sex toStudies:(NSArray*) studies error:(NSString**) error;

+ (void) debugRenameFromEnvironment;                // Testhaken SEKHVET_RENAME_TEST="<PatientID>|<Name>|<ID>[|<YYYYMMDD>]"

@end
