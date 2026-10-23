// Teil des SekhVet-Forks von Horos, LGPL-3.0.
// SekhVet Paket DR: Vet Tools > New Study Database from Folder... (see header)
#import "SekhmetStudienDB.h"
#import <AppKit/AppKit.h>
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#import "BrowserController.h"
#import "DicomDatabase.h"
#import "DicomImage.h"
#import "DicomFile.h"
#import "DCMObject.h"
#import "DCMPix.h" // SekhVet Paket DV: purgeCachedDictionaries before ejecting
#import "ThreadsManager.h"
#import "NSThread+N2.h"
#import "N2Debug.h"
#import "AppController.h" // SekhVet Paket DU: notificationTitle:description:name:

static NSString * const SekhmetStudyDBParentKey = @"SekhmetStudyDBParent";   // last parent folder chosen
static NSMutableSet *sekhmetLaufendeImporte = nil;   // SekhVet Paket DV: destination folders of running study imports

@interface SekhmetStudienDB ()
{
    NSString *quelle;        // source folder (only read)
    NSString *ziel;          // folder that holds "SekhVet Data"
    DicomDatabase *db;       // the study database (main-thread object)
}
- (void) run;
@end

@implementation SekhmetStudienDB

#pragma mark - SOPInstanceUID from the file header

// VRs with a 2-byte reserved field and a 4-byte length in explicit VR
static BOOL sekhmetLongVR( const uint8_t *vr)
{
    static const char *lang[] = { "OB", "OW", "OF", "SQ", "UT", "UN", "OL", "OD", "OV", "UC", "UR", "SV", "UV", NULL };
    for( int i = 0; lang[i]; i++)
        if( vr[0] == (uint8_t) lang[i][0] && vr[1] == (uint8_t) lang[i][1]) return YES;
    return NO;
}

static NSString *sekhmetUIDString( const char *v, uint32_t len)
{
    while( len > 0 && (v[len-1] == 0 || v[len-1] == ' ')) len--;
    if( len == 0) return nil;
    return [[[NSString alloc] initWithBytes: v length: len encoding: NSASCIIStringEncoding] autorelease];
}

+ (NSString*) sopInstanceUIDOfFile:(NSString*) path
{
    NSString *uid = nil;
    @autoreleasepool
    {
        // Fast path: walk the elements of a Part-10 file (little endian) up to (0008,0018). Anything unusual
        // (big endian, undefined length before the UID, no preamble) goes to the full parser.
        NSFileHandle *fh = [NSFileHandle fileHandleForReadingAtPath: path];
        NSData *d = nil;
        @try { d = [fh readDataOfLength: 65536]; } @catch (NSException *e) { d = nil; }
        [fh closeFile];
        const uint8_t *b = (const uint8_t*) [d bytes];
        NSUInteger n = [d length];
        BOOL fallback = YES;
        if( n >= 140 && memcmp( b + 128, "DICM", 4) == 0)
        {
            NSUInteger p = 132;
            BOOL inMeta = YES, explicitVR = YES, datasetExplicit = YES;
            fallback = NO;
            while( p + 8 <= n)
            {
                uint16_t g = b[p] | (b[p+1] << 8), e = b[p+2] | (b[p+3] << 8);
                if( inMeta && g != 0x0002) { inMeta = NO; explicitVR = datasetExplicit; }
                uint32_t len; NSUInteger head;
                if( explicitVR)
                {
                    if( sekhmetLongVR( b + p + 4))
                    {
                        if( p + 12 > n) { fallback = YES; break; }
                        len = b[p+8] | (b[p+9] << 8) | (b[p+10] << 16) | ((uint32_t) b[p+11] << 24);
                        head = 12;
                    }
                    else { len = b[p+6] | (b[p+7] << 8); head = 8; }
                }
                else { len = b[p+4] | (b[p+5] << 8) | (b[p+6] << 16) | ((uint32_t) b[p+7] << 24); head = 8; }
                if( len == 0xFFFFFFFF || p + head + len > n) { fallback = YES; break; }
                const char *v = (const char*) b + p + head;
                if( g == 0x0002 && e == 0x0010)
                {
                    NSString *ts = sekhmetUIDString( v, len);
                    if( [ts isEqualToString: @"1.2.840.10008.1.2"]) datasetExplicit = NO;          // implicit VR little endian
                    else if( [ts isEqualToString: @"1.2.840.10008.1.2.2"]) { fallback = YES; break; } // big endian
                }
                if( g == 0x0008 && e == 0x0018) { uid = sekhmetUIDString( v, len); break; }
                if( inMeta == NO && g > 0x0008) break;   // past (0008,0018): the file has none
                p += head + len;
            }
        }
        if( uid == nil && fallback)
        {
            @try
            {
                DCMObject *o = [DCMObject objectWithContentsOfFile: path decodingPixelData: NO];
                id v = [o attributeValueWithName: @"SOPInstanceUID"];
                if( [v isKindOfClass: [NSString class]] && [v length]) uid = v;
            }
            @catch (NSException *e) { uid = nil; }
        }
        [uid retain];
    }
    return [uid autorelease];
}

#pragma mark - Start

+ (void) alert:(NSString*) title text:(NSString*) text
{
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: title];
    [a setInformativeText: text];
    [a runModal];
}

// Checks the destination; nil = ok, otherwise the reason (shown to the user)
+ (NSString*) problemWithSource:(NSString*) src destination:(NSString*) dst
{
    if( [dst isEqualToString: src] || [dst hasPrefix: [src stringByAppendingString: @"/"]])
        return NSLocalizedString( @"The database cannot be created inside the folder that is imported. Choose a place outside of it.", nil);
    NSString *mainBase = [[[DicomDatabase defaultDatabase] baseDirPath] stringByStandardizingPath];
    NSString *dstBase = [dst stringByAppendingPathComponent: OsirixDataDirName];
    if( mainBase.length && ([dstBase isEqualToString: mainBase] || [dst hasPrefix: [mainBase stringByAppendingString: @"/"]]))
        return NSLocalizedString( @"This is the folder of the main database. Choose another place for the study database.", nil);
    return nil;
}

+ (BOOL) isSyncedFolder:(NSString*) path
{
    return [path rangeOfString: @"/Library/CloudStorage/"].location != NSNotFound
        || [path rangeOfString: @"/Library/Mobile Documents/"].location != NSNotFound
        || [path rangeOfString: @"/Dropbox/"].location != NSNotFound;
}

+ (BOOL) startImportFrom:(NSString*) src to:(NSString*) dst
{
    BrowserController *browser = [BrowserController currentBrowser];
    if( browser == nil) return NO;
    NSError *err = nil;
    if( [[NSFileManager defaultManager] createDirectoryAtPath: dst withIntermediateDirectories: YES attributes: nil error: &err] == NO)
    {
        NSLog( @"SekhVet study DB: cannot create %@ (%@)", dst, err);
        [self alert: NSLocalizedString( @"The folder could not be created", nil) text: [err localizedDescription] ?: dst];
        return NO;
    }
    [browser openDatabasePath: dst];   // creates "SekhVet Data", shows it, adds it to Sources
    NSString *want = [[dst stringByAppendingPathComponent: OsirixDataDirName] stringByStandardizingPath];
    if( [[[[browser database] baseDirPath] stringByStandardizingPath] isEqualToString: want] == NO)
    {
        NSLog( @"SekhVet study DB: database not opened (%@ instead of %@)", [[browser database] baseDirPath], want);
        return NO;
    }

    SekhmetStudienDB *job = [[[SekhmetStudienDB alloc] init] autorelease];
    job->quelle = [src copy];
    job->ziel = [dst copy];
    job->db = [[browser database] retain];
    NSThread *t = [[[NSThread alloc] initWithTarget: job selector: @selector(run) object: nil] autorelease];
    t.name = [NSString stringWithFormat: NSLocalizedString( @"Study database “%@”", nil), [dst lastPathComponent]];
    t.supportsCancel = YES;
    [[ThreadsManager defaultManager] addThreadAndStart: t];
    NSLog( @"SekhVet study DB: import started, source %@ -> %@", src, want);
    return YES;
}

+ (void) newStudyDatabaseFromFolder:(id) sender
{
    if( [BrowserController currentBrowser] == nil) return;

    NSOpenPanel *op = [NSOpenPanel openPanel];
    [op setCanChooseDirectories: YES];
    [op setCanChooseFiles: NO];
    [op setAllowsMultipleSelection: NO];
    [op setTitle: NSLocalizedString( @"New Study Database from Folder", nil)];
    [op setMessage: NSLocalizedString( @"Step 1 of 2: choose the folder with the DICOM studies. It is only read, nothing in it changes.", nil)];
    [op setPrompt: NSLocalizedString( @"Choose", nil)];
    if( [op runModal] != NSModalResponseOK || [op URL] == nil) return;
    NSString *src = [[[op URL] path] stringByStandardizingPath];

    NSSavePanel *sp = [NSSavePanel savePanel];
    [sp setTitle: NSLocalizedString( @"New Study Database from Folder", nil)];
    [sp setMessage: NSLocalizedString( @"Step 2 of 2: where should the study database be created? SekhVet makes a folder with this name and puts the database into it (e.g. on an external disk).", nil)];
    [sp setPrompt: NSLocalizedString( @"Create", nil)];
    [sp setNameFieldStringValue: [src lastPathComponent]];
    [sp setCanCreateDirectories: YES];
    NSString *last = [[NSUserDefaults standardUserDefaults] stringForKey: SekhmetStudyDBParentKey];
    BOOL isDir = NO;
    if( last && [[NSFileManager defaultManager] fileExistsAtPath: last isDirectory: &isDir] && isDir)
        [sp setDirectoryURL: [NSURL fileURLWithPath: last]];
    if( [sp runModal] != NSModalResponseOK || [sp URL] == nil) return;
    NSString *dst = [[[sp URL] path] stringByStandardizingPath];

    NSString *problem = [self problemWithSource: src destination: dst];
    if( problem) { [self alert: NSLocalizedString( @"Not possible here", nil) text: problem]; return; }

    if( [self isSyncedFolder: dst])
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setAlertStyle: NSAlertStyleWarning];
        [a setMessageText: NSLocalizedString( @"This folder is synchronised (Dropbox / iCloud)", nil)];
        [a setInformativeText: NSLocalizedString( @"A database in a synchronised folder can be damaged while it is in use, and the cloud copies everything again. Better choose a local folder or an external disk.", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Create Anyway", nil)];
        if( [a runModal] != NSAlertSecondButtonReturn) return;
    }
    if( [[NSFileManager defaultManager] fileExistsAtPath: [dst stringByAppendingPathComponent: OsirixDataDirName]])
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"There is already a study database here", nil)];
        [a setInformativeText: NSLocalizedString( @"The images of the folder are added to it; images that are already in it are skipped.", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Add to It", nil)];
        [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
        if( [a runModal] != NSAlertFirstButtonReturn) return;
    }
    [[NSUserDefaults standardUserDefaults] setObject: [dst stringByDeletingLastPathComponent] forKey: SekhmetStudyDBParentKey];
    [self startImportFrom: src to: dst];
}

- (void) dealloc
{
    [quelle release];
    [ziel release];
    [db release];
    [super dealloc];
}

#pragma mark - Import thread

static NSString *sekhmetCount( NSUInteger n) { return [NSNumberFormatter localizedStringFromNumber: @(n) numberStyle: NSNumberFormatterDecimalStyle]; }

- (void) run
{
    @autoreleasepool
    {
        // The Mac must not idle-sleep half-way (the owner kept it awake with a 3-hour video); display sleep is allowed.
        id wach = [[[NSProcessInfo processInfo] beginActivityWithOptions: NSActivityUserInitiated reason: @"SekhVet: importing a study database"] retain];
        @synchronized( [SekhmetStudienDB class]) { if( sekhmetLaufendeImporte == nil) sekhmetLaufendeImporte = [[NSMutableSet alloc] init]; [sekhmetLaufendeImporte addObject: ziel]; } // SekhVet Paket DV
        NSThread *thread = [NSThread currentThread];
        NSFileManager *fm = [NSFileManager defaultManager];
        NSDate *start = [NSDate date];
        NSMutableArray *files = [NSMutableArray array];
        NSMutableArray *ohneDICOM = [NSMutableArray array], *ohneUID = [NSMutableArray array], *doppelt = [NSMutableArray array];
        NSMutableArray *doppeltVon = [NSMutableArray array];   // SekhVet Paket DU: per duplicate the path of the image that was kept
        NSMutableArray *kopierFehler = [NSMutableArray array], *fehlt = [NSMutableArray array];
        NSMutableDictionary *sopZuPfad = [NSMutableDictionary dictionary];   // first source path per SOPInstanceUID
        NSMutableArray *zuKopieren = [NSMutableArray array];
        unsigned long long bytes = 0;
        NSUInteger schonDa = 0, kopiert = 0, inDB = 0;
        BOOL abgebrochen = NO, fehler = NO;
        NSString *bericht = nil;

        @try
        {
            // 1. collect the files (hidden ones and hidden folders are skipped)
            thread.status = NSLocalizedString( @"Collecting files…", nil);
            thread.progress = -1;
            NSDirectoryEnumerator *en = [fm enumeratorAtPath: quelle];
            NSString *rel;
            while( (rel = [en nextObject]))
            {
                NSDictionary *attr = [en fileAttributes];
                if( [[rel lastPathComponent] hasPrefix: @"."])
                {
                    if( [[attr objectForKey: NSFileType] isEqual: NSFileTypeDirectory]) [en skipDescendants];
                    continue;
                }
                if( [[attr objectForKey: NSFileType] isEqual: NSFileTypeRegular]) { [files addObject: rel]; bytes += [attr fileSize]; }
            }
            [files sortUsingSelector: @selector(compare:)];
            NSLog( @"SekhVet study DB: %d files, %llu bytes in %@", (int) files.count, bytes, quelle);

            // free space: a warning, the user decides
            NSNumber *frei = [[fm attributesOfFileSystemForPath: ziel error: NULL] objectForKey: NSFileSystemFreeSize];
            const unsigned long long reserve = 1024ULL * 1024 * 1024;
            if( frei && [frei unsignedLongLongValue] < bytes + reserve)
            {
                __block BOOL weiter = NO;
                dispatch_sync( dispatch_get_main_queue(), ^{
                    NSAlert *a = [[[NSAlert alloc] init] autorelease];
                    [a setAlertStyle: NSAlertStyleWarning];
                    [a setMessageText: NSLocalizedString( @"Probably not enough free disk space", nil)];
                    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"The folder holds %@, but only %@ are free at the destination. The import would stop half-way.", nil),
                                            [NSByteCountFormatter stringFromByteCount: (long long) bytes countStyle: NSByteCountFormatterCountStyleFile],
                                            [NSByteCountFormatter stringFromByteCount: [frei longLongValue] countStyle: NSByteCountFormatterCountStyleFile]]];
                    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
                    [a addButtonWithTitle: NSLocalizedString( @"Import Anyway", nil)];
                    weiter = ([a runModal] == NSAlertSecondButtonReturn);
                });
                if( weiter == NO) abgebrochen = YES;
            }

            DicomDatabase *idb = [db independentDatabase];

            if( abgebrochen == NO)
            {
                // 2. images that are already in the study database (adding to an existing one)
                thread.status = NSLocalizedString( @"Reading the study database…", nil);
                NSMutableSet *vorher = [NSMutableSet set];
                for( DicomImage *im in [idb objectsForEntity: idb.imageEntity])
                {
                    NSString *s = [im sopInstanceUID];
                    if( s.length) [vorher addObject: s];
                }

                // 3. read the SOPInstanceUID of every file: duplicates in the source are copied once
                NSTimeInterval naechsterStatus = 0;
                for( NSUInteger i = 0; i < files.count; i++)
                {
                    @autoreleasepool
                    {
                        if( thread.isCancelled) { abgebrochen = YES; break; }
                        NSTimeInterval jetzt = [NSDate timeIntervalSinceReferenceDate];
                        if( jetzt > naechsterStatus)
                        {
                            thread.status = [NSString stringWithFormat: NSLocalizedString( @"Reading %@ of %@ files…", nil), sekhmetCount( i), sekhmetCount( files.count)];
                            thread.progress = 0.1 * i / MAX( files.count, 1);
                            naechsterStatus = jetzt + 1;
                        }
                        NSString *r = [files objectAtIndex: i];
                        NSString *pfad = [quelle stringByAppendingPathComponent: r];
                        NSString *sop = [SekhmetStudienDB sopInstanceUIDOfFile: pfad];
                        if( sop == nil)
                        {
                            if( [DicomFile isDICOMFile: pfad]) { [ohneUID addObject: r]; [zuKopieren addObject: r]; }
                            else [ohneDICOM addObject: r];
                            continue;
                        }
                        if( [sopZuPfad objectForKey: sop]) { [doppelt addObject: r]; [doppeltVon addObject: [sopZuPfad objectForKey: sop]]; continue; }
                        [sopZuPfad setObject: r forKey: sop];
                        if( [vorher containsObject: sop]) { schonDa++; continue; }
                        [zuKopieren addObject: r];
                    }
                }
                NSLog( @"SekhVet study DB: %d images (different SOPInstanceUIDs), %d duplicates, %d already in the database, %d not DICOM, %d without SOPInstanceUID, %d to copy",
                      (int) sopZuPfad.count, (int) doppelt.count, (int) schonDa, (int) ohneDICOM.count, (int) ohneUID.count, (int) zuKopieren.count);
            }

            // 4. copy into the database and index in batches (as BrowserController+Sources+Copy does)
            if( abgebrochen == NO)
            {
                NSMutableArray *dstPaths = [NSMutableArray array];
                NSTimeInterval kopierStart = [NSDate timeIntervalSinceReferenceDate];
                NSTimeInterval naechstesIndex = kopierStart + 5, naechsterStatus = 0;
                for( NSUInteger i = 0; i < zuKopieren.count; i++)
                {
                    @autoreleasepool
                    {
                        if( thread.isCancelled) { abgebrochen = YES; break; }
                        NSString *r = [zuKopieren objectAtIndex: i];
                        NSString *srcPath = [quelle stringByAppendingPathComponent: r];
                        NSString *dstPath = [idb uniquePathForNewDataFileWithExtension: @"dcm"];
                        if( dstPath.length && SekhmetCopyDataOnly( srcPath, dstPath)) { [dstPaths addObject: dstPath]; kopiert++; } // SekhVet Paket DT
                        else [kopierFehler addObject: [NSString stringWithFormat: @"%@  (%@)", r, dstPath.length ? [NSString stringWithUTF8String: strerror( errno)] : @"no destination path"]];

                        NSTimeInterval jetzt = [NSDate timeIntervalSinceReferenceDate];
                        if( jetzt > naechstesIndex && dstPaths.count)
                        {
                            thread.status = [NSString stringWithFormat: NSLocalizedString( @"Indexing %@ images…", nil), sekhmetCount( dstPaths.count)];
                            [idb addFilesAtPaths: dstPaths postNotifications: YES dicomOnly: YES rereadExistingItems: NO generatedByOsiriX: NO importedFiles: YES returnArray: NO];
                            [dstPaths removeAllObjects];
                            naechstesIndex = [NSDate timeIntervalSinceReferenceDate] + 5;
                        }
                        if( jetzt > naechsterStatus)
                        {
                            // SekhVet Paket DU: remaining time from the rate so far (copy + indexing), after the first minute
                            NSTimeInterval bisher = jetzt - kopierStart;
                            NSString *rest = @"";
                            if( bisher > 60 && i > 0)
                            {
                                double minuten = bisher / (i + 1) * (zuKopieren.count - i - 1) / 60.;
                                rest = minuten < 1.5 ? NSLocalizedString( @" – about 1 min left", nil)
                                     : minuten < 90 ? [NSString stringWithFormat: NSLocalizedString( @" – about %.0f min left", nil), minuten]
                                     : [NSString stringWithFormat: NSLocalizedString( @" – about %.1f h left", nil), minuten / 60.];
                            }
                            thread.status = [NSString stringWithFormat: NSLocalizedString( @"Copying %@ of %@ images%@…", nil), sekhmetCount( i + 1), sekhmetCount( zuKopieren.count), rest];
                            thread.progress = 0.1 + 0.85 * (i + 1) / MAX( zuKopieren.count, 1);
                            naechsterStatus = jetzt + 1;
                        }
                    }
                }
                if( dstPaths.count)
                {
                    thread.status = [NSString stringWithFormat: NSLocalizedString( @"Indexing %@ images…", nil), sekhmetCount( dstPaths.count)];
                    [idb addFilesAtPaths: dstPaths postNotifications: YES dicomOnly: YES rereadExistingItems: NO generatedByOsiriX: NO importedFiles: YES returnArray: NO];
                }
            }

            // 5. check: every SOPInstanceUID of the source must be in the study database
            thread.status = NSLocalizedString( @"Checking the study database…", nil);
            thread.progress = 0.97;
            DicomDatabase *vdb = [db independentDatabase];
            NSMutableSet *nachher = [NSMutableSet set];
            for( DicomImage *im in [vdb objectsForEntity: vdb.imageEntity])
            {
                NSString *s = [im sopInstanceUID];
                if( s.length) [nachher addObject: s];
            }
            for( NSString *sop in sopZuPfad)
            {
                if( [nachher containsObject: sop]) inDB++;
                else [fehlt addObject: [sopZuPfad objectForKey: sop]];
            }
            [fehlt sortUsingSelector: @selector(compare:)];
        }
        @catch (NSException *e)
        {
            N2LogExceptionWithStackTrace( e);
            fehler = YES;
        }

        // 6. report next to the database
        @try
        {
            NSDateFormatter *df = [[[NSDateFormatter alloc] init] autorelease];
            [df setDateFormat: @"yyyy-MM-dd HH-mm"];
            NSString *berichtPfad = [ziel stringByAppendingPathComponent: [NSString stringWithFormat: @"Import report %@.txt", [df stringFromDate: start]]];
            BOOL vollstaendig = (abgebrochen == NO && fehler == NO && fehlt.count == 0 && kopierFehler.count == 0);
            NSMutableString *t = [NSMutableString string];
            [t appendFormat: @"SekhVet – study database import\n\nStarted:   %@\nDuration:  %.0f min\nSource:    %@\nDatabase:  %@\n\n",
             [NSDateFormatter localizedStringFromDate: start dateStyle: NSDateFormatterMediumStyle timeStyle: NSDateFormatterShortStyle],
             -[start timeIntervalSinceNow] / 60., quelle, [ziel stringByAppendingPathComponent: OsirixDataDirName]];
            [t appendFormat: @"Files in the source folder:                 %@ (%@)\n", sekhmetCount( files.count), [NSByteCountFormatter stringFromByteCount: (long long) bytes countStyle: NSByteCountFormatterCountStyleFile]];
            [t appendFormat: @"Different images (SOPInstanceUID):          %@\n", sekhmetCount( sopZuPfad.count)];
            [t appendFormat: @"Duplicates in the source (kept once):       %@\n", sekhmetCount( doppelt.count)];
            [t appendFormat: @"Already in the database before:             %@\n", sekhmetCount( schonDa)];
            [t appendFormat: @"Copied now:                                 %@\n", sekhmetCount( kopiert)];
            [t appendFormat: @"Not DICOM (not imported):                   %@\n", sekhmetCount( ohneDICOM.count)];
            [t appendFormat: @"DICOM without SOPInstanceUID (not checked): %@\n", sekhmetCount( ohneUID.count)];
            [t appendFormat: @"Copy errors:                                %@\n", sekhmetCount( kopierFehler.count)];
            [t appendFormat: @"Images of the source found in the database: %@ of %@\n\n", sekhmetCount( inDB), sekhmetCount( sopZuPfad.count)];
            if( vollstaendig) [t appendString: @"RESULT: COMPLETE – every image of the source folder is in the study database.\n"];
            else if( abgebrochen) [t appendString: @"RESULT: CANCELLED – the import did not finish. Running it again into the same folder adds what is missing.\n"];
            else if( fehler) [t appendString: @"RESULT: ERROR – the import stopped with an error (see the console). Running it again adds what is missing.\n"];
            else [t appendFormat: @"RESULT: INCOMPLETE – %@ images of the source are missing in the database (list below).\n", sekhmetCount( fehlt.count)];
            // SekhVet Paket DU: long lists per folder (a whole duplicated series used to be 666 lines); the missing images
            // and copy errors keep every path below the summary, they are what the user has to act on
            void (^proOrdner)(NSArray*) = ^(NSArray *a) {
                NSCountedSet *ordner = [NSCountedSet set];
                for( NSString *s in a) [ordner addObject: [s stringByDeletingLastPathComponent].length ? [s stringByDeletingLastPathComponent] : @"(top level)"];
                for( NSString *o in [[ordner allObjects] sortedArrayUsingSelector: @selector(compare:)]) [t appendFormat: @"  %@: %@\n", o, sekhmetCount( [ordner countForObject: o])];
            };
            void (^liste)(NSString*, NSArray*, BOOL) = ^(NSString *titel, NSArray *a, BOOL alle) {
                if( a.count == 0) return;
                [t appendFormat: @"\n%@ (%@):\n", titel, sekhmetCount( a.count)];
                if( a.count > 30) { proOrdner( a); if( alle) [t appendString: @"  --\n"]; }
                if( a.count <= 30 || alle) for( NSString *s in a) [t appendFormat: @"  %@\n", s];
            };
            liste( @"Missing in the database (source path)", fehlt, YES);
            liste( @"Copy errors", kopierFehler, YES);
            liste( @"Not DICOM", ohneDICOM, NO);
            liste( @"DICOM without SOPInstanceUID", ohneUID, NO);
            if( doppelt.count)   // folder of the duplicate = folder of the image that was kept
            {
                NSCountedSet *paare = [NSCountedSet set];
                for( NSUInteger k = 0; k < doppelt.count; k++)
                    [paare addObject: [NSString stringWithFormat: @"%@  =  %@", [[doppelt objectAtIndex: k] stringByDeletingLastPathComponent], [[doppeltVon objectAtIndex: k] stringByDeletingLastPathComponent]]];
                [t appendFormat: @"\nDuplicates in the source, not copied a second time (%@) – folder  =  folder of the image kept:\n", sekhmetCount( doppelt.count)];
                for( NSString *p in [[paare allObjects] sortedArrayUsingSelector: @selector(compare:)]) [t appendFormat: @"  %@: %@ %@\n", p, sekhmetCount( [paare countForObject: p]), [paare countForObject: p] == 1 ? @"image" : @"images"];
            }
            if( [t writeToFile: berichtPfad atomically: YES encoding: NSUTF8StringEncoding error: NULL]) bericht = berichtPfad;
            NSLog( @"SekhVet study DB: done in %.0f s – %@ – %d of %d images in the database, %d missing, %d copy errors, report %@",
                  -[start timeIntervalSinceNow], vollstaendig ? @"COMPLETE" : @"NOT COMPLETE", (int) inDB, (int) sopZuPfad.count, (int) fehlt.count, (int) kopierFehler.count, bericht);

            NSString *titel = vollstaendig ? NSLocalizedString( @"Study database complete", nil)
                            : abgebrochen ? NSLocalizedString( @"Study database import cancelled", nil)
                            : NSLocalizedString( @"Study database NOT complete", nil);
            NSString *text = [NSString stringWithFormat: NSLocalizedString( @"“%@”: %@ of %@ images of the source are in the database.\n%@ duplicates in the source were kept once, %@ files were not DICOM.\nThe report lies next to the database.", nil),
                              [ziel lastPathComponent], sekhmetCount( inDB), sekhmetCount( sopZuPfad.count), sekhmetCount( doppelt.count), sekhmetCount( ohneDICOM.count)];
            NSString *berichtKopie = [[bericht copy] autorelease];
            // SekhVet Paket DU: a system notification (the import runs for hours, nobody is at the Mac) and the result as a
            // sheet on the database window. The modal alert held the main run loop until someone clicked OK - timers
            // (DICOMweb auto-refresh, delayed tasks) stood still meanwhile.
            [[AppController sharedAppController] notificationTitle: titel description: [NSString stringWithFormat: NSLocalizedString( @"“%@”: %@ of %@ images", nil), [ziel lastPathComponent], sekhmetCount( inDB), sekhmetCount( sopZuPfad.count)] name: @"study-database"];
            dispatch_async( dispatch_get_main_queue(), ^{
                NSAlert *a = [[[NSAlert alloc] init] autorelease];
                if( vollstaendig == NO) [a setAlertStyle: NSAlertStyleWarning];
                [a setMessageText: titel];
                [a setInformativeText: text];
                [a addButtonWithTitle: NSLocalizedString( @"OK", nil)];
                if( berichtKopie) [a addButtonWithTitle: NSLocalizedString( @"Show Report", nil)];
                void (^antwort)(NSModalResponse) = ^(NSModalResponse r) {
                    if( r == NSAlertSecondButtonReturn && berichtKopie) [[NSWorkspace sharedWorkspace] openFile: berichtKopie];
                };
                NSWindow *w = [[BrowserController currentBrowser] window];
                if( w && [w isVisible] && [w attachedSheet] == nil) [a beginSheetModalForWindow: w completionHandler: antwort];
                else antwort( [a runModal]);
            });
        }
        @catch (NSException *e) { N2LogExceptionWithStackTrace( e); }

        @synchronized( [SekhmetStudienDB class]) { [sekhmetLaufendeImporte removeObject: ziel]; } // SekhVet Paket DV
        [[NSProcessInfo processInfo] endActivity: wach];
        [wach release];
    }
}

#pragma mark - Eject (SekhVet Paket DV)

+ (NSURL*) externalVolumeForPath:(NSString*) path
{
    if( path.length == 0 || [[NSFileManager defaultManager] fileExistsAtPath: path] == NO) return nil;
    NSURL *u = [NSURL fileURLWithPath: path], *vol = nil;
    NSNumber *isLocal = nil, *isInternal = nil;
    [u getResourceValue: &vol forKey: NSURLVolumeURLKey error: NULL];
    [u getResourceValue: &isLocal forKey: NSURLVolumeIsLocalKey error: NULL];
    [u getResourceValue: &isInternal forKey: NSURLVolumeIsInternalKey error: NULL];
    if( vol == nil || isLocal.boolValue == NO || isInternal.boolValue || [[vol path] isEqualToString: @"/"]) return nil;
    return vol;
}

+ (NSButton*) ejectButtonForDatabasePath:(NSString*) path
{
    NSURL *vol = [self externalVolumeForPath: path];
    if( vol == nil) return nil;
    static NSMutableDictionary *knoepfe = nil;   // one button per database path; target is the class, so no dangling target
    if( knoepfe == nil) knoepfe = [[NSMutableDictionary alloc] init];
    NSButton *b = [knoepfe objectForKey: path];
    if( b == nil)
    {
        b = [[[NSButton alloc] initWithFrame: NSMakeRect( 0, 0, 14, 14)] autorelease];
        b.image = [NSImage imageNamed: @"Eject_gray"];
        b.image.size = NSMakeSize( 10, 11);
        b.alternateImage = [NSImage imageNamed: @"Eject_lightgray"];
        b.alternateImage.size = NSMakeSize( 10, 11);
        b.imagePosition = NSImageOnly;
        b.bezelStyle = 0;
        [b setButtonType: NSMomentaryLightButton];
        [b setBordered: NO];
        NSButtonCell *cell = b.cell;
        cell.gradientType = NSGradientNone;
        [cell setHighlightsBy: NSContentsCellMask];
        b.identifier = path;
        b.target = self;
        b.action = @selector(ejectButtonClicked:);
        [knoepfe setObject: b forKey: path];
    }
    NSString *name = nil;
    [vol getResourceValue: &name forKey: NSURLVolumeLocalizedNameKey error: NULL];
    b.toolTip = [NSString stringWithFormat: NSLocalizedString( @"Eject “%@”", nil), name ?: [[vol path] lastPathComponent]];
    return b;
}

+ (void) ejectButtonClicked:(id) sender
{
    [self ejectVolumeOfDatabasePath: [sender identifier]];
}

+ (NSString*) missingVolumeMessageForPath:(NSString*) path
{
    NSArray *teile = [[path stringByStandardizingPath] pathComponents];   // "/", "Volumes", "<name>", ...
    if( teile.count < 3 || [[teile objectAtIndex: 1] isEqualToString: @"Volumes"] == NO) return nil;
    NSString *volPfad = [NSString pathWithComponents: [teile subarrayWithRange: NSMakeRange( 0, 3)]];
    if( [[[NSWorkspace sharedWorkspace] mountedLocalVolumePaths] containsObject: volPfad] || [[NSFileManager defaultManager] fileExistsAtPath: volPfad]) return nil;
    return [NSString stringWithFormat: NSLocalizedString( @"The disk “%@” is not connected. Connect it and click the database again.", nil), [teile objectAtIndex: 2]];
}

+ (void) ejectAlert:(NSString*) titel text:(NSString*) text
{
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setAlertStyle: NSAlertStyleWarning];
    [a setMessageText: titel];
    [a setInformativeText: text];
    NSWindow *w = [[BrowserController currentBrowser] window];
    if( w && [w isVisible] && [w attachedSheet] == nil) [a beginSheetModalForWindow: w completionHandler: nil];
    else [a runModal];
}

+ (void) ejectVolumeOfDatabasePath:(NSString*) path
{
    NSURL *vol = [self externalVolumeForPath: path];
    if( vol == nil) return;
    NSString *volPfad = [[vol path] stringByStandardizingPath], *volPrefix = [volPfad stringByAppendingString: @"/"];
    NSString *name = nil;
    [vol getResourceValue: &name forKey: NSURLVolumeLocalizedNameKey error: NULL];
    if( name == nil) name = [volPfad lastPathComponent];

    BOOL laeuft = NO;
    @synchronized( [SekhmetStudienDB class]) { for( NSString *z in sekhmetLaufendeImporte) if( [[z stringByStandardizingPath] hasPrefix: volPrefix]) laeuft = YES; }
    if( laeuft)
    {
        NSLog( @"SekhVet eject: %@ refused - a study database import into it is running", volPfad);
        [self ejectAlert: [NSString stringWithFormat: NSLocalizedString( @"“%@” cannot be ejected yet", nil), name]
                    text: NSLocalizedString( @"A study database import into this disk is still running. Wait for it to finish or cancel it in the activity list, then eject again.", nil)];
        return;
    }
    BrowserController *b = [BrowserController currentBrowser];
    if( [[[[b database] baseDirPath] stringByStandardizingPath] hasPrefix: volPrefix])
    {
        NSLog( @"SekhVet eject: showing the main database instead of %@", [[b database] baseDirPath]);
        [b setDatabase: [DicomDatabase defaultDatabase]];   // closes the viewers of the study database
    }
    // the study database is released with the autorelease pool of this event; eject a moment later
    [self performSelector: @selector(ejectVolumeLater:) withObject: @{ @"pfad": volPfad, @"name": name, @"versuch": @1 } afterDelay: 1.0];
}

+ (void) ejectVolumeLater:(NSDictionary*) d
{
    NSString *volPfad = [d objectForKey: @"pfad"], *name = [d objectForKey: @"name"];
    int versuch = [[d objectForKey: @"versuch"] intValue];
    [DCMPix purgeCachedDictionaries];
    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *err = nil;
        BOOL ok = [[NSWorkspace sharedWorkspace] unmountAndEjectDeviceAtURL: [NSURL fileURLWithPath: volPfad] error: &err];
        NSString *grund = [[[err localizedDescription] copy] autorelease];
        if( ok == NO && (([[err domain] isEqualToString: NSOSStatusErrorDomain] && [err code] == -47) || ([[err domain] isEqualToString: NSPOSIXErrorDomain] && [err code] == EBUSY)))
            grund = [NSString stringWithFormat: NSLocalizedString( @"“%@” is still in use by another program.", nil), name];   // fBsyErr / EBUSY
        dispatch_async( dispatch_get_main_queue(), ^{
            NSLog( @"SekhVet eject: %@ attempt %d: %@%@", volPfad, versuch, ok ? @"ejected" : @"refused", ok ? @"" : [NSString stringWithFormat: @" (%@)", grund]);
            if( ok)
            {
                [[AppController sharedAppController] notificationTitle: [NSString stringWithFormat: NSLocalizedString( @"“%@” ejected", nil), name]
                                                           description: NSLocalizedString( @"The disk can be unplugged now.", nil) name: @"study-database-eject"];
                return;
            }
            if( versuch < 3)   // Spotlight or a closing database may still hold the disk for a moment
            {
                [self performSelector: @selector(ejectVolumeLater:) withObject: @{ @"pfad": volPfad, @"name": name, @"versuch": @(versuch + 1) } afterDelay: 2.0];
                return;
            }
            [self ejectAlert: [NSString stringWithFormat: NSLocalizedString( @"“%@” could not be ejected", nil), name]
                        text: [NSString stringWithFormat: NSLocalizedString( @"%@\n\nSekhVet has let go of its database on this disk. Another program may still use it (a Finder window, Spotlight, a copy). Try again in a moment, or eject it in the Finder.", nil), grund ?: @""]];
        });
    });
}

#if SEKHVET_TESTHAKEN
// SEKHVET_EJECT_TEST="<database folder on an external disk>" - open it, eject via SekhVet, then click the missing entry
+ (void) debugEjectFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_EJECT_TEST");
    if( env == NULL) return;
    NSString *ordner = [[NSString stringWithUTF8String: env] stringByStandardizingPath];
    [[BrowserController currentBrowser] openDatabasePath: ordner];
    NSLog( @"SekhVet eject test: shown %@ | external volume %@ | button %@", [[[BrowserController currentBrowser] database] baseDirPath],
          [[self externalVolumeForPath: ordner] path], [self ejectButtonForDatabasePath: ordner] ? @"yes" : @"no");
    [self performSelector: @selector(debugEjectStep2:) withObject: ordner afterDelay: 3];
}

+ (void) debugEjectStep2:(NSString*) ordner
{
    [self ejectVolumeOfDatabasePath: ordner];
    NSLog( @"SekhVet eject test: after the click the browser shows %@", [[[BrowserController currentBrowser] database] baseDirPath]);
    [self performSelector: @selector(debugEjectStep3:) withObject: ordner afterDelay: 12];
}

+ (void) debugEjectStep3:(NSString*) ordner
{
    NSArray *t = [ordner pathComponents];
    NSString *vol = t.count > 2 ? [NSString pathWithComponents: [t subarrayWithRange: NSMakeRange( 0, 3)]] : ordner;
    NSLog( @"SekhVet eject test: volume still there: %d | message for the missing entry: %@", [[NSFileManager defaultManager] fileExistsAtPath: vol], [self missingVolumeMessageForPath: ordner]);
}
#endif

#if SEKHVET_TESTHAKEN
// SEKHVET_STUDYDB_TEST="<source folder>|<destination folder>" - the menu flow without the two panels and questions
+ (void) debugFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_STUDYDB_TEST");
    if( env == NULL) return;
    NSArray *p = [[NSString stringWithUTF8String: env] componentsSeparatedByString: @"|"];
    if( p.count != 2) { NSLog( @"SekhVet study DB test: expected \"source|destination\""); return; }
    NSString *src = [[p objectAtIndex: 0] stringByStandardizingPath], *dst = [[p objectAtIndex: 1] stringByStandardizingPath];
    NSString *problem = [self problemWithSource: src destination: dst];
    if( problem) { NSLog( @"SekhVet study DB test: refused – %@", problem); return; }
    [self startImportFrom: src to: dst];
}
#endif

@end
