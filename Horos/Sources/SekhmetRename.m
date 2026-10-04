/*=========================================================================
 SekhVet Paket BC — Patient umbenennen. Siehe Header.
 ============================================================================*/

#import "SekhmetRename.h"
#import "SekhmetTesthaken.h"
#import "BrowserController.h"
#import "DicomDatabase.h"
#import "DicomStudy.h"
#import "DicomFile.h"
#import "DCM.h"
#import "XMLController.h"
#import "XMLControllerDCMTKCategory.h"
#import "MutableArrayCategory.h"
#import "WaitRendering.h"
#import "ViewerController.h"
#import "DicomImage.h"                 // SekhVet Paket CS: inDatabaseFolder (linked files)
#import "DicomFileDCMTKCategory.h"     // SekhVet Paket CS: character set of a file
#import "DICOMToNSString.h"            // SekhVet Paket CS: encodingForDICOMCharacterSet:
#include <stdio.h>
#include <unistd.h>
#include <limits.h>

static SekhmetRename *sekhmetRename = nil;

// DicomStudy -name ersetzt '^' durch ' ' (Anzeigeform). Was in DICOM geschrieben oder
// im Fenster vorbelegt wird, braucht den Rohwert mit Caret, sonst verliert die Datei
// die Trennung Besitzer^Tier und ein PACS sieht einen anderen Patienten.
static NSString* sekhmetRawName( DicomStudy *st)
{
    if( st == nil) return @"";
    [st willAccessValueForKey: @"name"];
    NSString *raw = [st primitiveValueForKey: @"name"];
    [st didAccessValueForKey: @"name"];
    return raw ? raw : @"";
}

@interface SekhmetRename ()
{
    NSArray *studies;                 // retained
    NSArray *patients;                // retained; Dictionaries name / patientID / dateOfBirth / patientSex
    NSTextField *infoLabel, *nameField, *idField, *dobField;
    NSPopUpButton *patientPopup, *sexPopup;
}
- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold small:(BOOL) small;
- (NSTextField*) field:(NSRect) r placeholder:(NSString*) ph;
- (void) reloadPatients;
- (void) forgetStudies;                                                                  // SekhVet Paket CS
+ (DicomDatabase*) databaseForStudies:(NSArray*) studies error:(NSString**) error;       // SekhVet Paket CS
+ (NSString*) characterSetOfFiles:(NSArray*) files notHolding:(NSArray*) values;         // SekhVet Paket CS
- (void) fillFromName:(NSString*) name patientID:(NSString*) pid dob:(NSDate*) dob sex:(NSString*) sex;
- (IBAction) patientChosen:(id) sender;
- (IBAction) rename:(id) sender;
- (IBAction) cancel:(id) sender;
@end

@implementation SekhmetRename

+ (NSDateFormatter*) dicomDateFormatter
{
    static NSDateFormatter *f = nil;
    if( f == nil)
    {
        f = [[NSDateFormatter alloc] init];
        [f setDateFormat: @"yyyyMMdd"];
        [f setLocale: [[[NSLocale alloc] initWithLocaleIdentifier: @"en_US_POSIX"] autorelease]];
        [f setTimeZone: [NSTimeZone localTimeZone]];   // wie Horos' DicomFile beim Import
    }
    return f;
}

+ (SekhmetRename*) shared
{
    if( sekhmetRename == nil) sekhmetRename = [[SekhmetRename alloc] init];
    return sekhmetRename;
}

+ (NSArray*) selectedStudies
{
    NSMutableArray *result = [NSMutableArray array];
    for( id item in [[BrowserController currentBrowser] databaseSelection])
    {
        id study = item;
        if( [[item valueForKey: @"type"] isEqualToString: @"Study"] == NO) study = [item valueForKey: @"study"];
        if( study && [study isKindOfClass: [DicomStudy class]] && [result containsObject: study] == NO) [result addObject: study];
    }
    return result;
}

#pragma mark - Motor

+ (NSString*) rawNameOfStudy:(DicomStudy*) study
{
    return sekhmetRawName( study);
}

// SekhVet Paket CS: the window is not modal, so the studies may have been deleted or the database
// switched while it was open. Returns the local database all studies belong to, or nil plus a message.
+ (DicomDatabase*) databaseForStudies:(NSArray*) studies error:(NSString**) error
{
    NSString *gone = NSLocalizedString( @"The selected studies are no longer available (deleted, or the database was switched). Select them again in the database window.", nil);
    DicomDatabase *db = [[BrowserController currentBrowser] database];
    if( db == nil || [db isLocal] == NO)
    {
        if( error) *error = NSLocalizedString( @"Rename Patient works only in a local database.", nil);
        return nil;
    }
    @try
    {
        for( DicomStudy *st in studies)
        {
            NSManagedObjectContext *c = [st isKindOfClass: [DicomStudy class]] ? [st managedObjectContext] : nil;
            if( c == nil || [st isDeleted] || [DicomDatabase databaseForContext: c] != db)
            {
                if( error) *error = gone;
                return nil;
            }
            [st willAccessValueForKey: nil];   // fires the fault; raises if the row is gone
        }
    }
    @catch (NSException *e)
    {
        if( error) *error = gone;
        return nil;
    }
    return db;
}

// SekhVet Paket CS: nil = every value can be written into every file; otherwise the DICOM character
// set that cannot hold them. Same choice of character set and same conversion as modifyDicom:dicomFiles:.
+ (NSString*) characterSetOfFiles:(NSArray*) files notHolding:(NSArray*) values
{
    NSMutableDictionary *known = [NSMutableDictionary dictionary];
    for( NSString *f in files)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *cs = nil;
        @try { cs = [[DicomFile getEncodingArrayForFile: f] objectAtIndex: 0]; }
        @catch (NSException *e) { cs = nil; }
        if( cs == nil) cs = @"";
        NSNumber *fits = [known objectForKey: cs];
        if( fits == nil)
        {
            NSStringEncoding enc = [NSString encodingForDICOMCharacterSet: cs];
            BOOL all = YES;
            for( NSString *v in values)
                if( [v cStringUsingEncoding: enc] == NULL) { all = NO; break; }
            fits = [NSNumber numberWithBool: all];
            [known setObject: fits forKey: cs];
        }
        BOOL ok = [fits boolValue];
        [cs retain];
        [pool release];
        [cs autorelease];
        if( ok == NO) return cs.length ? cs : @"ISO_IR 100";
    }
    return nil;
}

static unsigned long long sekhmetFreeBytes( NSString *path)
{
    NSNumber *n = [[[NSFileManager defaultManager] attributesOfFileSystemForPath: path error: NULL] objectForKey: NSFileSystemFreeSize];
    return n ? [n unsignedLongLongValue] : ULLONG_MAX;   // unknown: do not block
}

// SekhVet Paket CS: put one backed-up file back in place of the original, atomically where possible.
static BOOL sekhmetRestoreFile( NSString *backup, NSString *original)
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if( [fm fileExistsAtPath: backup] == NO) return NO;
    NSString *tmp = [original stringByAppendingString: @".sekhvet-restore"];
    [fm removeItemAtPath: tmp error: NULL];
    if( [fm copyItemAtPath: backup toPath: tmp error: NULL] && rename( [tmp fileSystemRepresentation], [original fileSystemRepresentation]) == 0) return YES;
    [fm removeItemAtPath: tmp error: NULL];
    return NO;
}

// SekhVet Paket CS: rewritten to be all-or-nothing per study.
//  1. Everything is validated BEFORE any file is touched: studies still exist, local database, no linked
//     files outside the database folder, all files present, new values encodable in every file's
//     character set, enough free disk space.
//  2. Per study every file is copied to <database folder>/SekhVet-Rename-Backup.noindex/<UUID>/ first
//     (not TEMP.noindex: that folder is emptied at every start). If a single file of the study fails,
//     ALL files of that study are restored and its database entry stays as it was.
//  3. The backup is deleted only after all files are written and the database is saved.
// The log carries counts and StudyInstanceUIDs only, never names or patient IDs.
+ (BOOL) applyName:(NSString*) name patientID:(NSString*) pid birthDate:(NSDate*) dob sex:(NSString*) sex toStudies:(NSArray*) studies error:(NSString**) error
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    name = [name stringByTrimmingCharactersInSet: ws];
    pid = [pid stringByTrimmingCharactersInSet: ws];
    if( name.length == 0 || pid.length == 0)
    {
        if( error) *error = NSLocalizedString( @"Patient name and patient ID must not be empty.", nil);
        return NO;
    }
    if( studies.count == 0)
    {
        if( error) *error = NSLocalizedString( @"No study selected.", nil);
        return NO;
    }

    NSString *problem = nil;
    DicomDatabase *db = [self databaseForStudies: studies error: &problem];
    if( db == nil)
    {
        if( error) *error = problem;
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *dobDICOM = dob ? [[self dicomDateFormatter] stringFromDate: dob] : nil;
    NSMutableArray *plans = [NSMutableArray array];
    unsigned long long largestStudy = 0, largestFile = 0;

    // ---- 1. validate everything; nothing is modified in this block
    @try
    {
        for( DicomStudy *study in studies)
        {
            NSString *oldName = sekhmetRawName( study);
            NSString *oldID = study.patientID ? study.patientID : @"";
            NSString *label = [NSString stringWithFormat: @"%@ (%@)", oldName, oldID];   // for the dialog only, never logged

            NSUInteger linked = 0;
            for( id im in [study images])
                if( [[im valueForKey: @"inDatabaseFolder"] boolValue] == NO) linked++;
            if( linked)
            {
                if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"%@: %lu image(s) of this study are only linked — their files live outside the SekhVet database folder (for example on a network drive, a CD copy or in another program's database). Rename Patient does not rewrite files it does not own. Copy the study into the database first (right-click it › “Copy Linked Files to Database Folder”), then rename. Nothing was changed.", nil), label, (unsigned long) linked];
                return NO;
            }

            NSMutableArray *files = [NSMutableArray arrayWithArray: [[study paths] allObjects]];
            [files removeDuplicatedStrings];

            unsigned long long bytes = 0;
            NSUInteger missing = 0;
            for( NSString *f in files)
            {
                NSDictionary *a = [fm attributesOfItemAtPath: f error: NULL];
                if( a == nil || [fm isWritableFileAtPath: f] == NO) { missing++; continue; }
                unsigned long long s = [a fileSize];
                bytes += s;
                if( s > largestFile) largestFile = s;
            }
            if( missing)
            {
                if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"%@: %lu of %lu file(s) of this study are missing or not writable. Nothing was changed.", nil), label, (unsigned long) missing, (unsigned long) files.count];
                return NO;
            }
            if( bytes > largestStudy) largestStudy = bytes;

            // Historie wie Horos' Unify: bisherige Werte an OtherPatientIDs / OtherPatientNames anhaengen.
            // (Horos liest die beiden Tags dort vertauscht; hier richtig herum.)
            NSString *otherIDs = @"", *otherNames = @"";
            if( files.count)
            {
                DCMObject *o = [DCMObject objectWithContentsOfFile: [files objectAtIndex: 0] decodingPixelData: NO];
                if( [[o attributeValueWithName: @"OtherPatientIDs"] isKindOfClass: [NSString class]]) otherIDs = [o attributeValueWithName: @"OtherPatientIDs"];
                if( [[o attributeValueWithName: @"OtherPatientNames"] isKindOfClass: [NSString class]]) otherNames = [o attributeValueWithName: @"OtherPatientNames"];
            }
            if( otherIDs.length) otherIDs = [otherIDs stringByAppendingString: @" - "];
            if( otherNames.length) otherNames = [otherNames stringByAppendingString: @" - "];
            otherIDs = [otherIDs stringByAppendingString: oldID];
            otherNames = [otherNames stringByAppendingString: oldName];

            NSMutableArray *tagAndValues = [NSMutableArray array];
            [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,0010)"], name, nil]];
            [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,0020)"], pid, nil]];
            if( dobDICOM) [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,0030)"], dobDICOM, nil]];
            if( sex.length) [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,0040)"], sex, nil]];
            [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,1000)"], otherIDs, nil]];
            [tagAndValues addObject: [NSArray arrayWithObjects: [DCMAttributeTag tagWithTagString: @"(0010,1001)"], otherNames, nil]];

            // One pass over the files for all values; the message then says whether the NEW values or the history do not fit
            NSMutableArray *allValues = [NSMutableArray array];
            for( NSArray *tv in tagAndValues) [allValues addObject: [tv lastObject]];
            NSString *cs = [self characterSetOfFiles: files notHolding: allValues];
            if( cs)
            {
                NSStringEncoding enc = [NSString encodingForDICOMCharacterSet: cs];
                if( [name cStringUsingEncoding: enc] == NULL || [pid cStringUsingEncoding: enc] == NULL)
                {
                    if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"%@: the new name or patient ID contains characters that cannot be stored in the character set of these DICOM files (%@). Use only characters of that character set — for ISO_IR 100 that is Western European (Latin-1), without letters such as ł, š, ő, without € and without typographic quotes or dashes. Nothing was changed.", nil), label, cs];
                }
                else if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"%@: the previous name or ID cannot be stored in the character set of all DICOM files of this study (%@), so the history in Other Patient Names / IDs cannot be written. Nothing was changed.", nil), label, cs];
                return NO;
            }

            [plans addObject: [NSDictionary dictionaryWithObjectsAndKeys: study, @"study", files, @"files", tagAndValues, @"values", label, @"label", nil]];
        }
    }
    @catch (NSException *e)
    {
        NSLog( @"SekhVet Rename: validation raised %@", e.name);
        if( error) *error = NSLocalizedString( @"The selected studies could not be read (deleted in the meantime?). Nothing was changed.", nil);
        return NO;
    }

    NSString *backupRoot = [[db dataBaseDirPath] stringByAppendingPathComponent: @"SekhVet-Rename-Backup.noindex"];
    const unsigned long long reserve = 64ULL * 1024 * 1024;
    unsigned long long need = largestStudy + largestFile + reserve;
    if( sekhmetFreeBytes( [db dataBaseDirPath]) < need || sekhmetFreeBytes( [db dataDirPath]) < largestFile + reserve)
    {
        if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"Not enough free disk space for the safety copy: %@ are needed on the volume of the database. Nothing was changed.", nil),
                             [NSByteCountFormatter stringFromByteCount: (long long) need countStyle: NSByteCountFormatterCountStyleFile]];
        return NO;
    }

    [ViewerController closeAllWindows];   // wie Horos' Unify: kein Viewer auf Dateien, die gleich umgeschrieben werden

    // ---- 2. per study: backup, rewrite, database, remove backup
    NSMutableArray *failed = [NSMutableArray array];

    for( NSDictionary *plan in plans)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        DicomStudy *study = [plan objectForKey: @"study"];
        NSArray *files = [plan objectForKey: @"files"];
        NSString *label = [plan objectForKey: @"label"];
        NSString *reason = nil;
        NSString *backupDir = [backupRoot stringByAppendingPathComponent: [[NSUUID UUID] UUIDString]];
        NSMutableArray *backups = [NSMutableArray array];   // same order as files
        BOOL keepBackup = NO;

        @try
        {
            NSString *studyUID = [study valueForKey: @"studyInstanceUID"];

            // a) safety copy of every file
            BOOL copied = [fm createDirectoryAtPath: backupDir withIntermediateDirectories: YES attributes: nil error: NULL];
            for( NSUInteger i = 0; copied && i < files.count; i++)
            {
                NSString *b = [backupDir stringByAppendingPathComponent: [NSString stringWithFormat: @"%lu.dcm", (unsigned long) i]];
                copied = [fm copyItemAtPath: [files objectAtIndex: i] toPath: b error: NULL];
                if( copied) [backups addObject: b];
            }
            BOOL touched = copied;   // from here on the files of the study may have been rewritten
            if( copied == NO) reason = NSLocalizedString( @"the safety copy could not be created — nothing was changed", nil);

            // b) rewrite the files
            if( reason == nil)
            {
                BOOL ok = YES;
                @try { if( files.count) ok = [XMLController modifyDicom: [plan objectForKey: @"values"] dicomFiles: files]; }
                @catch (NSException *e) { NSLog( @"SekhVet Rename: modifyDicom raised %@", e.name); ok = NO; }
                if( ok == NO) reason = NSLocalizedString( @"at least one DICOM file could not be rewritten", nil);
            }

            // c) database, only after all files; patientUID wie beim Import, damit die Studien
            //    unter EINEM Patienten zusammenlaufen. Ohne neues Geburtsdatum zaehlt das alte.
            if( reason == nil)
            {
                NSString *oldRaw = [[sekhmetRawName( study) copy] autorelease], *oldPID = [[study.patientID copy] autorelease], *oldUID = [[study.patientUID copy] autorelease];
                NSDate *oldDOB = [[study.dateOfBirth retain] autorelease];
                NSString *oldSex = [[study.patientSex copy] autorelease];

                NSMutableDictionary *src = [NSMutableDictionary dictionary];
                [src setObject: name forKey: @"patientName"];
                [src setObject: pid forKey: @"patientID"];
                NSDate *uidDOB = dob ? dob : study.dateOfBirth;
                if( uidDOB) [src setObject: uidDOB forKey: @"patientBirthDate"];
                study.name = name;
                study.patientID = pid;
                study.patientUID = [DicomFile patientUID: src];
                if( dob) study.dateOfBirth = dob;
                if( sex.length) study.patientSex = sex;

                if( [db save: NULL] == NO)
                {
                    study.name = oldRaw;
                    study.patientID = oldPID;
                    study.patientUID = oldUID;
                    if( dob) study.dateOfBirth = oldDOB;
                    if( sex.length) study.patientSex = oldSex;
                    reason = NSLocalizedString( @"the database could not be saved", nil);
                }
            }

            // d) failure after the files were touched: put ALL files of this study back
            if( reason && touched)
            {
                NSUInteger notRestored = 0;
                for( NSUInteger i = 0; i < files.count; i++)
                    if( sekhmetRestoreFile( [backups objectAtIndex: i], [files objectAtIndex: i]) == NO) notRestored++;
                if( notRestored)
                {
                    keepBackup = YES;
                    reason = [reason stringByAppendingFormat: NSLocalizedString( @"; %lu file(s) could NOT be restored — the untouched originals are kept in %@ (files 0.dcm, 1.dcm, …)", nil), (unsigned long) notRestored, backupDir];
                }
                else reason = [reason stringByAppendingString: NSLocalizedString( @" — all files of the study were restored, database entry unchanged", nil)];
                NSLog( @"SekhVet Rename: study %@ NOT renamed, %lu files, %lu not restored", studyUID, (unsigned long) files.count, (unsigned long) notRestored);
            }
            else if( reason) NSLog( @"SekhVet Rename: study %@ NOT renamed, no file touched", studyUID);
            else NSLog( @"SekhVet Rename: study %@ renamed, %lu files", studyUID, (unsigned long) files.count);
        }
        @catch (NSException *e)
        {
            // Unexpected (e.g. the study vanished in between): keep the backup, it may be the only intact copy
            NSLog( @"SekhVet Rename: exception %@ while renaming a study", e.name);
            keepBackup = YES;
            reason = [NSString stringWithFormat: NSLocalizedString( @"unexpected error — the safety copy of the files is kept in %@", nil), backupDir];
        }

        if( keepBackup == NO) [fm removeItemAtPath: backupDir error: NULL];
        if( reason) [failed addObject: [NSString stringWithFormat: @"%@: %@", label, reason]];
        [pool release];
    }

    rmdir( [backupRoot fileSystemRepresentation]);   // only succeeds when empty, i.e. no backup was kept

    if( failed.count)
    {
        if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"These studies were NOT renamed:\n%@", nil), [failed componentsJoinedByString: @"\n"]];
        return NO;
    }
    return YES;
}

#pragma mark - Fenster

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 540, 356)
                                              styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Rename Patient (DICOM)", nil)];
    [w setReleasedWhenClosed: NO];
    self = [super initWithWindow: w];
    if( self == nil) return nil;

    NSView *c = [w contentView];
    float y = 356 - 36;
    infoLabel = [self label: @"" frame: NSMakeRect( 20, y, 500, 18) bold: YES small: NO];
    [c addSubview: infoLabel];

    y -= 34;
    [c addSubview: [self label: NSLocalizedString( @"Take identity from:", nil) frame: NSMakeRect( 20, y, 150, 18) bold: NO small: NO]];
    patientPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 176, y - 5, 344, 26) pullsDown: NO] autorelease];
    [patientPopup setTarget: self];
    [patientPopup setAction: @selector( patientChosen:)];
    [c addSubview: patientPopup];

    y -= 38;
    [c addSubview: [self label: NSLocalizedString( @"Patient name:", nil) frame: NSMakeRect( 20, y, 150, 18) bold: NO small: NO]];
    nameField = [self field: NSMakeRect( 176, y - 3, 344, 24) placeholder: NSLocalizedString( @"Owner^Animal   (DICOM: Last^First)", nil)];
    [c addSubview: nameField];

    y -= 34;
    [c addSubview: [self label: NSLocalizedString( @"Patient ID:", nil) frame: NSMakeRect( 20, y, 150, 18) bold: NO small: NO]];
    idField = [self field: NSMakeRect( 176, y - 3, 344, 24) placeholder: NSLocalizedString( @"e.g. clinic number", nil)];
    [c addSubview: idField];

    y -= 34;
    [c addSubview: [self label: NSLocalizedString( @"Birth date:", nil) frame: NSMakeRect( 20, y, 150, 18) bold: NO small: NO]];
    dobField = [self field: NSMakeRect( 176, y - 3, 344, 24) placeholder: NSLocalizedString( @"YYYYMMDD, empty = unchanged", nil)];
    [c addSubview: dobField];

    y -= 34;
    [c addSubview: [self label: NSLocalizedString( @"Sex:", nil) frame: NSMakeRect( 20, y, 150, 18) bold: NO small: NO]];
    sexPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 176, y - 5, 200, 26) pullsDown: NO] autorelease];
    [sexPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"(unchanged)", nil), @"M", @"F", @"O", nil]];
    [c addSubview: sexPopup];

    y -= 58;
    [c addSubview: [self label: NSLocalizedString( @"Writes the new identity into every DICOM file of the selected studies and into the database. The previous name and ID are kept in Other Patient Names / IDs. Open viewers are closed first. A PACS that already holds these studies keeps the old name.", nil) frame: NSMakeRect( 20, y, 500, 48) bold: NO small: YES]];

    NSButton *cancel = [[[NSButton alloc] initWithFrame: NSMakeRect( 314, 14, 100, 32)] autorelease];
    [cancel setBezelStyle: NSBezelStyleRounded];
    [cancel setTitle: NSLocalizedString( @"Cancel", nil)];
    [cancel setKeyEquivalent: @"\e"];
    [cancel setTarget: self];
    [cancel setAction: @selector( cancel:)];
    [c addSubview: cancel];

    NSButton *ok = [[[NSButton alloc] initWithFrame: NSMakeRect( 420, 14, 100, 32)] autorelease];
    [ok setBezelStyle: NSBezelStyleRounded];
    [ok setTitle: NSLocalizedString( @"Rename…", nil)];
    [ok setKeyEquivalent: @"\r"];
    [ok setTarget: self];
    [ok setAction: @selector( rename:)];
    [c addSubview: ok];

    return self;
}

- (void) dealloc
{
    [studies release];
    [patients release];
    [super dealloc];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold small:(BOOL) small
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text];
    [t setBezeled: NO];
    [t setDrawsBackground: NO];
    [t setEditable: NO];
    [t setSelectable: NO];
    float size = small ? [NSFont smallSystemFontSize] : [NSFont systemFontSize];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: size] : [NSFont systemFontOfSize: size]];
    if( small) [t setTextColor: [NSColor secondaryLabelColor]];
    [[t cell] setWraps: YES];
    [[t cell] setLineBreakMode: NSLineBreakByWordWrapping];
    return t;
}

- (NSTextField*) field:(NSRect) r placeholder:(NSString*) ph
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [[t cell] setPlaceholderString: ph];
    [t setFont: [NSFont systemFontOfSize: [NSFont systemFontSize]]];
    return t;
}

- (void) reloadPatients
{
    DicomDatabase *db = [[BrowserController currentBrowser] database];
    NSMutableDictionary *byKey = [NSMutableDictionary dictionary];
    @try
    {
        for( DicomStudy *st in [db objectsForEntity: db.studyEntity])
        {
            NSString *rawName = sekhmetRawName( st);
            if( rawName.length == 0) continue;
            NSString *key = [NSString stringWithFormat: @"%@|%@", rawName, st.patientID ? st.patientID : @""];
            if( [byKey objectForKey: key]) continue;
            NSMutableDictionary *d = [NSMutableDictionary dictionary];
            [d setObject: rawName forKey: @"name"];
            [d setObject: st.patientID ? st.patientID : @"" forKey: @"patientID"];
            if( st.dateOfBirth) [d setObject: st.dateOfBirth forKey: @"dateOfBirth"];
            if( st.patientSex.length) [d setObject: st.patientSex forKey: @"patientSex"];
            [byKey setObject: d forKey: key];
        }
    }
    @catch (NSException *e) { NSLog( @"SekhVet Rename: patient list: %@", e); }

    NSArray *sorted = [[byKey allValues] sortedArrayUsingComparator: ^NSComparisonResult( id a, id b) {
        return [[a objectForKey: @"name"] localizedCaseInsensitiveCompare: [b objectForKey: @"name"]];
    }];
    [patients release];
    patients = [sorted retain];

    [patientPopup removeAllItems];
    [patientPopup addItemWithTitle: NSLocalizedString( @"— free entry —", nil)];
    for( NSDictionary *d in patients)
    {
        NSString *title = [NSString stringWithFormat: @"%@   ·   %@", [d objectForKey: @"name"], [d objectForKey: @"patientID"]];
        [[patientPopup menu] addItem: [[[NSMenuItem alloc] initWithTitle: title action: nil keyEquivalent: @""] autorelease]];   // ohne Doppelten-Filter von addItemWithTitle
    }
}

- (void) fillFromName:(NSString*) name patientID:(NSString*) pid dob:(NSDate*) dob sex:(NSString*) sex
{
    [nameField setStringValue: name ? name : @""];
    [idField setStringValue: pid ? pid : @""];
    [dobField setStringValue: dob ? [[SekhmetRename dicomDateFormatter] stringFromDate: dob] : @""];
    NSInteger idx = 0;
    if( [sex isEqualToString: @"M"]) idx = 1;
    else if( [sex isEqualToString: @"F"]) idx = 2;
    else if( [sex isEqualToString: @"O"]) idx = 3;
    [sexPopup selectItemAtIndex: idx];
}

- (void) runForStudies:(NSArray*) s
{
    if( s.count == 0)
    {
        NSRunAlertPanel( NSLocalizedString( @"Rename Patient", nil), NSLocalizedString( @"Select one or more studies in the database first.", nil), nil, nil, nil);
        return;
    }
    // SekhVet Paket CS: refuse early (remote database, stale objects) instead of failing on "Rename…"
    NSString *problem = nil;
    if( [SekhmetRename databaseForStudies: s error: &problem] == nil)
    {
        NSRunAlertPanel( NSLocalizedString( @"Rename Patient", nil), @"%@", nil, nil, nil, problem);
        return;
    }
    [studies release];
    studies = [s retain];
    [self window];   // Fenster laden
    [self reloadPatients];
    DicomStudy *first = [s objectAtIndex: 0];
    NSString *info;
    if( s.count == 1) info = [NSString stringWithFormat: NSLocalizedString( @"1 study: %@ (%@)", nil), sekhmetRawName( first), first.patientID];
    else info = [NSString stringWithFormat: NSLocalizedString( @"%lu studies, first: %@ (%@)", nil), (unsigned long) s.count, sekhmetRawName( first), first.patientID];
    [infoLabel setStringValue: info];
    [self fillFromName: sekhmetRawName( first) patientID: first.patientID dob: first.dateOfBirth sex: first.patientSex];
    [patientPopup selectItemAtIndex: 0];
    [[self window] center];
    [self showWindow: self];
    [[self window] makeKeyAndOrderFront: self];
    [[self window] makeFirstResponder: nameField];
}

- (IBAction) patientChosen:(id) sender
{
    NSInteger i = [patientPopup indexOfSelectedItem] - 1;
    if( i < 0 || i >= (NSInteger) patients.count) return;
    NSDictionary *d = [patients objectAtIndex: i];
    [self fillFromName: [d objectForKey: @"name"] patientID: [d objectForKey: @"patientID"] dob: [d objectForKey: @"dateOfBirth"] sex: [d objectForKey: @"patientSex"]];
}

// SekhVet Paket CS: the window does not keep managed objects longer than it needs them
- (void) forgetStudies
{
    [studies release];
    studies = nil;
}

- (IBAction) cancel:(id) sender
{
    [[self window] orderOut: self];
    [self forgetStudies];
}

- (IBAction) rename:(id) sender
{
    NSCharacterSet *ws = [NSCharacterSet whitespaceAndNewlineCharacterSet];
    NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet: ws];
    NSString *pid = [[idField stringValue] stringByTrimmingCharactersInSet: ws];
    NSString *dobText = [[dobField stringValue] stringByTrimmingCharactersInSet: ws];
    if( name.length == 0 || pid.length == 0)
    {
        NSRunAlertPanel( NSLocalizedString( @"Rename Patient", nil), NSLocalizedString( @"Patient name and patient ID must not be empty.", nil), nil, nil, nil);
        return;
    }
    NSDate *dob = nil;
    if( dobText.length)
    {
        dob = [[SekhmetRename dicomDateFormatter] dateFromString: dobText];
        if( dob == nil || dobText.length != 8)
        {
            NSRunAlertPanel( NSLocalizedString( @"Rename Patient", nil), NSLocalizedString( @"The birth date must be YYYYMMDD or empty.", nil), nil, nil, nil);
            return;
        }
    }
    NSString *sex = nil;
    if( [sexPopup indexOfSelectedItem] > 0) sex = [sexPopup titleOfSelectedItem];

    // SekhVet Paket CS: the studies may have been deleted, or the database switched, while this
    // window was open -- say so and close instead of raising a Core Data fault exception
    NSString *problem = nil;
    NSUInteger fileCount = 0;
    if( studies.count == 0) problem = NSLocalizedString( @"No study selected.", nil);
    else if( [SekhmetRename databaseForStudies: studies error: &problem])
    {
        @try { for( DicomStudy *st in studies) fileCount += [[st paths] count]; }
        @catch (NSException *e) { problem = NSLocalizedString( @"The selected studies are no longer available (deleted, or the database was switched). Select them again in the database window.", nil); }
    }
    if( problem)
    {
        [[self window] orderOut: self];
        [self forgetStudies];
        NSRunAlertPanel( NSLocalizedString( @"Rename Patient", nil), @"%@", nil, nil, nil, problem);
        return;
    }

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Rename to %@ (%@)?", nil), name, pid]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"This DEFINITIVELY rewrites %lu DICOM files of %lu study(ies) and updates the database. Open viewers will be closed. A safety copy of each study is kept until all its files are written; if one file fails, the whole study is put back as it was.", nil), (unsigned long) fileCount, (unsigned long) studies.count]];
    [a addButtonWithTitle: NSLocalizedString( @"Rename", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;

    [[self window] orderOut: self];
    WaitRendering *wait = [[[WaitRendering alloc] init: NSLocalizedString( @"Updating files...", nil)] autorelease];
    [wait showWindow: self];
    NSString *error = nil;
    NSArray *targets = [[studies retain] autorelease];
    [self forgetStudies];   // SekhVet Paket CS
    BOOL ok = [SekhmetRename applyName: name patientID: pid birthDate: dob sex: sex toStudies: targets error: &error];
    [wait close];

    BrowserController *b = [BrowserController currentBrowser];
    [b outlineViewRefresh];
    [b refreshMatrix: self];

    if( ok == NO)
        NSRunCriticalAlertPanel( NSLocalizedString( @"Rename Patient", nil), @"%@", nil, nil, nil, error ? error : NSLocalizedString( @"Failed to change the DICOM files.", nil));
}

#pragma mark - Testhaken

#if SEKHVET_TESTHAKEN
+ (void) debugRenameFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_RENAME_TEST");
    if( env == NULL || strlen( env) == 0) return;
    NSArray *p = [[NSString stringWithUTF8String: env] componentsSeparatedByString: @"|"];
    if( p.count < 3) { NSLog( @"SekhVet Rename-Test: FEHLER Format <PatientID>|<Name>|<ID>[|<YYYYMMDD>]"); return; }
    DicomDatabase *db = [DicomDatabase activeLocalDatabase];
    NSArray *studies = [db objectsForEntity: db.studyEntity predicate: [NSPredicate predicateWithFormat: @"patientID == %@", [p objectAtIndex: 0]]];
    NSDate *dob = (p.count > 3) ? [[self dicomDateFormatter] dateFromString: [p objectAtIndex: 3]] : nil;
    NSString *error = nil;
    BOOL ok = [self applyName: [p objectAtIndex: 1] patientID: [p objectAtIndex: 2] birthDate: dob sex: nil toStudies: studies error: &error];
    [[BrowserController currentBrowser] outlineViewRefresh];
    DicomStudy *first = studies.count ? [studies objectAtIndex: 0] : nil;
    NSString *file = [[[first paths] allObjects] count] ? [[[first paths] allObjects] objectAtIndex: 0] : nil;
    DCMObject *o = file ? [DCMObject objectWithContentsOfFile: file decodingPixelData: NO] : nil;
    NSLog( @"SekhVet Rename-Test: %@ studien=%lu db=%@|%@|%@ datei=%@|%@|dob=%@ other=%@|%@ fehler=%@",
          ok ? @"ok" : @"FEHLER", (unsigned long) studies.count, first.name, first.patientID, first.patientUID,
          [o attributeValueWithName: @"PatientsName"], [o attributeValueWithName: @"PatientID"], [o attributeValueWithName: @"PatientsBirthDate"],
          [o attributeValueWithName: @"OtherPatientNames"], [o attributeValueWithName: @"OtherPatientIDs"], error);
}
#endif // SEKHVET_TESTHAKEN

@end
