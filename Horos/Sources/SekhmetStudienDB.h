// Teil des SekhVet-Forks von Horos, LGPL-3.0.
// SekhVet Paket DR: Vet Tools > New Study Database from Folder...
// A folder of DICOM studies (e.g. a Dropbox folder of a research project) becomes its own database: the database is
// created in a folder the user picks (e.g. on an external disk), appears under Sources and is shown; every image is
// copied once (duplicates in the source by SOPInstanceUID are skipped) and indexed; at the end each SOPInstanceUID of
// the source is looked up in the new database and a report is written next to it. While it runs the Mac does not
// idle-sleep.
#import <Foundation/Foundation.h>
#include <copyfile.h>

/** SekhVet Paket DT: copy only the data of an image file - no extended attributes, ACL or dates. On exFAT/FAT every
    extended attribute (Dropbox puts some on each file) becomes a hidden "._name" file next to the image: twice the files
    and seeks on a USB hard disk (Kaninchen import 05.10.2026: 2 files per image). Measured afterwards: macOS itself
    adds com.apple.provenance (protected, cannot be removed) to files of a tracked app, so on exFAT a ._ file stays;
    only the foreign attributes no longer travel along (LaCie, 300 images: 14.2 s -> 12.2 s). Fails if dst exists, like
    -[NSFileManager copyItemAtPath:toPath:error:]. */
static inline BOOL SekhmetCopyDataOnly( NSString *src, NSString *dst)
{
    return copyfile( [src fileSystemRepresentation], [dst fileSystemRepresentation], NULL, COPYFILE_DATA | COPYFILE_EXCL) == 0;
}

@interface SekhmetStudienDB : NSObject

/** Menu action: choose source folder and destination, create the database, import, verify. */
+ (void) newStudyDatabaseFromFolder:(id) sender;

/** SOPInstanceUID of a DICOM file, nil if the file is not DICOM or has none. Reads only the start of the file. */
+ (NSString*) sopInstanceUIDOfFile:(NSString*) path;

// SekhVet Paket DV: eject the disk of a study database from within SekhVet (macOS refuses while the database is open)

/** The volume of path when it is a local disk that is not internal (USB/Thunderbolt), else nil. */
+ (NSURL*) externalVolumeForPath:(NSString*) path;

/** Eject button for the Sources row of a database on an external disk, nil for other databases. */
+ (NSButton*) ejectButtonForDatabasePath:(NSString*) path;

/** Shows the main database instead, lets go of the study database and ejects its disk; says why if that fails. */
+ (void) ejectVolumeOfDatabasePath:(NSString*) path;

/** "The disk ... is not connected" when path lies on a volume under /Volumes that is not mounted, else nil. */
+ (NSString*) missingVolumeMessageForPath:(NSString*) path;

@end
