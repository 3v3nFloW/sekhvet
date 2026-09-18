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

    [ViewerController closeAllWindows];   // wie Horos' Unify: kein Viewer auf Dateien, die gleich umgeschrieben werden

    NSString *dobDICOM = dob ? [[self dicomDateFormatter] stringFromDate: dob] : nil;
    NSMutableArray *failed = [NSMutableArray array];

    for( DicomStudy *study in studies)
    {
        NSString *oldName = sekhmetRawName( study);
        NSString *oldID = study.patientID ? study.patientID : @"";
        NSMutableArray *files = [NSMutableArray arrayWithArray: [[study paths] allObjects]];
        [files removeDuplicatedStrings];

        // Historie wie Horos' Unify: bisherige Werte an OtherPatientIDs / OtherPatientNames anhaengen.
        // (Horos liest die beiden Tags dort vertauscht; hier richtig herum.)
        NSString *otherIDs = @"", *otherNames = @"";
        if( files.count)
        {
            DCMObject *o = [DCMObject objectWithContentsOfFile: [files objectAtIndex: 0] decodingPixelData: NO];
            if( [o attributeValueWithName: @"OtherPatientIDs"]) otherIDs = [o attributeValueWithName: @"OtherPatientIDs"];
            if( [o attributeValueWithName: @"OtherPatientNames"]) otherNames = [o attributeValueWithName: @"OtherPatientNames"];
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

        BOOL ok = YES;
        @try
        {
            if( files.count) ok = [XMLController modifyDicom: tagAndValues dicomFiles: files];
            for( NSString *f in files) [[NSFileManager defaultManager] removeItemAtPath: [f stringByAppendingString: @".bak"] error: NULL];
        }
        @catch (NSException *e) { NSLog( @"SekhVet Rename: %@", e); ok = NO; }

        if( ok == NO)
        {
            NSLog( @"SekhVet Rename: files of %@ (%@) NOT written, database unchanged", oldName, oldID);
            [failed addObject: [NSString stringWithFormat: @"%@ (%@)", oldName, oldID]];
            continue;
        }

        // Datenbank erst nach den Dateien; patientUID wie beim Import, damit die Studien
        // unter EINEM Patienten zusammenlaufen. Ohne neues Geburtsdatum zaehlt das alte.
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
        NSLog( @"SekhVet Rename: %@ %@ -> %@ %@ (%lu files)", oldName, oldID, name, pid, (unsigned long) files.count);
    }

    [[[BrowserController currentBrowser] database] save: nil];

    if( failed.count)
    {
        if( error) *error = [NSString stringWithFormat: NSLocalizedString( @"The DICOM files of these studies could not be changed, their database entries were left as they were:\n%@", nil), [failed componentsJoinedByString: @"\n"]];
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

- (IBAction) cancel:(id) sender
{
    [[self window] orderOut: self];
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

    NSUInteger fileCount = 0;
    for( DicomStudy *st in studies) fileCount += [[st paths] count];

    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Rename to %@ (%@)?", nil), name, pid]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"This DEFINITIVELY rewrites %lu DICOM files of %lu study(ies) and updates the database. Open viewers will be closed.", nil), (unsigned long) fileCount, (unsigned long) studies.count]];
    [a addButtonWithTitle: NSLocalizedString( @"Rename", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;

    [[self window] orderOut: self];
    WaitRendering *wait = [[[WaitRendering alloc] init: NSLocalizedString( @"Updating files...", nil)] autorelease];
    [wait showWindow: self];
    NSString *error = nil;
    BOOL ok = [SekhmetRename applyName: name patientID: pid birthDate: dob sex: sex toStudies: studies error: &error];
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
