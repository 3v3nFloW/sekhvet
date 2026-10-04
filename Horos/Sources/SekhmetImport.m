/*=========================================================================
 SekhVet — Bild und PDF als DICOM importieren. Siehe Header.
 ============================================================================*/

#import "SekhmetImport.h"
#import "SekhmetTesthaken.h" // SekhVet: Testhaken nur mit Build-Flag SEKHVET_TESTHAKEN=1
#import "SekhmetDisplayPanel.h"
#import "DicomDatabase.h"
#import "BrowserController.h"
#import "DicomStudy.h"
#import "DicomFile.h"
#import "DICOMExport.h"
#import "DCM.h"
#import "DCMEncapsulatedPDF.h"
#import "AppController.h" // SekhVet: COPYDATABASEMODE-Werte (always) fuer den Datenbank-Import
#import "SekhmetRename.h" // SekhVet Paket CS: rawNameOfStudy: (PatientName with '^')

static SekhmetImport *sekhmetImport = nil;

@interface SekhmetImport ()
- (void) buildUI;
- (void) prefillFromSelection;
- (void) updateFilesLabel;
- (void) setStatus:(NSString*) s;
@end

@implementation SekhmetImport

+ (SekhmetImport*) shared
{
    if( sekhmetImport == nil) sekhmetImport = [[SekhmetImport alloc] init];
    return sekhmetImport;
}

+ (NSArray*) imageExtensions
{
    return [NSArray arrayWithObjects: @"jpg", @"jpeg", @"png", @"tif", @"tiff", @"gif", @"bmp", @"heic", nil];
}

+ (NSArray*) allExtensions
{
    return [[self imageExtensions] arrayByAddingObject: @"pdf"];
}

- (IBAction) showWindow:(id) sender
{
    [SekhmetDisplayPanel placeWindow: [self window] nearWindow: [NSApp keyWindow] centered: YES]; // SekhVet: innerhalb der Viewer-Flaeche
    [super showWindow: sender];
}

#pragma mark - Init / UI

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 600, 470)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                                                 backing: NSBackingStoreBuffered defer: NO] autorelease];
    [w setTitle: NSLocalizedString( @"SekhVet — Image / PDF as DICOM", nil)];
    [w setReleasedWhenClosed: NO];

    self = [super initWithWindow: w];
    if( self)
    {
        files = [[NSMutableArray alloc] init];
        [self buildUI];
        [w center];
    }
    return self;
}

- (void) dealloc
{
    [files release]; [attachStudyUID release]; [attachStudyTitle release];
    [super dealloc];
}

- (NSTextField*) label:(NSString*) text frame:(NSRect) r bold:(BOOL) bold
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setStringValue: text]; [t setBezeled: NO]; [t setDrawsBackground: NO]; [t setEditable: NO]; [t setSelectable: NO];
    [t setFont: bold ? [NSFont boldSystemFontOfSize: 13] : [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSTextField*) field:(NSRect) r placeholder:(NSString*) ph
{
    NSTextField *t = [[[NSTextField alloc] initWithFrame: r] autorelease];
    [t setPlaceholderString: ph]; [t setFont: [NSFont systemFontOfSize: 12]];
    return t;
}

- (NSButton*) checkbox:(NSString*) title frame:(NSRect) r
{
    NSButton *b = [[[NSButton alloc] initWithFrame: r] autorelease];
    [b setButtonType: NSButtonTypeSwitch]; [b setTitle: title]; [b setFont: [NSFont systemFontOfSize: 12]];
    return b;
}

- (void) buildUI
{
    NSView *cv = [[self window] contentView];
    float W = [cv frame].size.width;
    float y = [cv frame].size.height - 36;

    filesLabel = [self label: @"" frame: NSMakeRect( 20, y, W - 40, 20) bold: YES];
    [cv addSubview: filesLabel];
    y -= 26;
    NSButton *pick = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y - 4, 160, 28)] autorelease];
    [pick setTitle: NSLocalizedString( @"Choose files…", nil)]; [pick setBezelStyle: NSBezelStyleRounded]; [pick setFont: [NSFont systemFontOfSize: 12]];
    [pick setTarget: self]; [pick setAction: @selector(chooseFiles:)];
    [cv addSubview: pick];

    y -= 40;
    attachButton = [self checkbox: @"" frame: NSMakeRect( 20, y, W - 40, 18)];
    [attachButton setTarget: self]; [attachButton setAction: @selector(attachChanged:)];
    [cv addSubview: attachButton];

    y -= 34;
    [cv addSubview: [self label: NSLocalizedString( @"Patient:", nil) frame: NSMakeRect( 20, y + 2, 140, 20) bold: NO]];
    nameField = [self field: NSMakeRect( 160, y, 250, 22) placeholder: NSLocalizedString( @"Last^First (Owner^Animal)", nil)];
    idField = [self field: NSMakeRect( 420, y, 160, 22) placeholder: NSLocalizedString( @"Patient ID", nil)];
    [cv addSubview: nameField]; [cv addSubview: idField];

    y -= 32;
    birthKnownButton = [self checkbox: NSLocalizedString( @"Birth date:", nil) frame: NSMakeRect( 20, y + 2, 140, 18)];
    [cv addSubview: birthKnownButton];
    birthPicker = [[[NSDatePicker alloc] initWithFrame: NSMakeRect( 160, y, 130, 24)] autorelease];
    [birthPicker setDatePickerStyle: NSDatePickerStyleTextField]; [birthPicker setDatePickerElements: NSDatePickerElementFlagYearMonthDay];
    [birthPicker setDateValue: [NSDate date]];
    [cv addSubview: birthPicker];
    [cv addSubview: [self label: NSLocalizedString( @"Sex:", nil) frame: NSMakeRect( 310, y + 2, 90, 20) bold: NO]];
    sexPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 400, y - 2, 180, 26) pullsDown: NO] autorelease];
    [sexPopup addItemsWithTitles: [NSArray arrayWithObjects: NSLocalizedString( @"unknown", nil), @"M", @"F", @"O", nil]];
    [cv addSubview: sexPopup];

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Study description:", nil) frame: NSMakeRect( 20, y + 2, 140, 20) bold: NO]];
    studyDescField = [self field: NSMakeRect( 160, y, 250, 22) placeholder: NSLocalizedString( @"e.g. photo documentation", nil)];
    [cv addSubview: studyDescField];
    [cv addSubview: [self label: NSLocalizedString( @"Date:", nil) frame: NSMakeRect( 420, y + 2, 50, 20) bold: NO]];
    studyDatePicker = [[[NSDatePicker alloc] initWithFrame: NSMakeRect( 470, y, 110, 24)] autorelease];
    [studyDatePicker setDatePickerStyle: NSDatePickerStyleTextField]; [studyDatePicker setDatePickerElements: NSDatePickerElementFlagYearMonthDay];
    [studyDatePicker setDateValue: [NSDate date]];
    [cv addSubview: studyDatePicker];

    y -= 32;
    [cv addSubview: [self label: NSLocalizedString( @"Series description:", nil) frame: NSMakeRect( 20, y + 2, 140, 20) bold: NO]];
    seriesDescField = [self field: NSMakeRect( 160, y, 250, 22) placeholder: NSLocalizedString( @"e.g. surgical photos", nil)];
    [cv addSubview: seriesDescField];
    [cv addSubview: [self label: NSLocalizedString( @"Modality:", nil) frame: NSMakeRect( 420, y + 2, 70, 20) bold: NO]];
    modalityPopup = [[[NSPopUpButton alloc] initWithFrame: NSMakeRect( 490, y - 2, 90, 26) pullsDown: NO] autorelease];
    [modalityPopup addItemsWithTitles: [NSArray arrayWithObjects: @"OT", @"XC", @"ES", @"DX", @"US", nil]];
    [modalityPopup setToolTip: NSLocalizedString( @"Modality of the images: OT other, XC photo (external camera), ES endoscopy", nil)];
    [cv addSubview: modalityPopup];

    y -= 34;
    pdfPagesButton = [self checkbox: NSLocalizedString( @"Write PDF pages as images (instead of Encapsulated PDF; for viewers without PDF display)", nil) frame: NSMakeRect( 20, y, W - 40, 18)];
    [cv addSubview: pdfPagesButton];

    y -= 50;
    importButton = [[[NSButton alloc] initWithFrame: NSMakeRect( 20, y, 220, 30)] autorelease];
    [importButton setTitle: NSLocalizedString( @"Import as DICOM", nil)]; [importButton setBezelStyle: NSBezelStyleRounded];
    [importButton setKeyEquivalent: @"\r"];
    [importButton setTarget: self]; [importButton setAction: @selector(importNow:)];
    [cv addSubview: importButton];
    statusField = [self label: @"" frame: NSMakeRect( 250, y + 6, W - 270, 20) bold: NO];
    [cv addSubview: statusField];

    y -= 30;
    [cv addSubview: [self label: NSLocalizedString( @"Images → Secondary Capture (RGB), PDF → Encapsulated PDF. Target: INCOMING of the active database.", nil) frame: NSMakeRect( 20, y, W - 40, 20) bold: NO]];

    [self updateFilesLabel];
    [self prefillFromSelection];
}

- (void) setStatus:(NSString*) s
{
    [statusField setStringValue: s ? s : @""];
}

- (void) updateFilesLabel
{
    if( files.count == 0) [filesLabel setStringValue: NSLocalizedString( @"No files selected", nil)];
    else if( files.count == 1) [filesLabel setStringValue: [[files objectAtIndex: 0] lastPathComponent]];
    else [filesLabel setStringValue: [NSString stringWithFormat: NSLocalizedString( @"%d files, first: %@", nil), (int) files.count, [[files objectAtIndex: 0] lastPathComponent]]];
}

#pragma mark - Vorbelegung aus dem Browser

- (void) prefillFromSelection
{
    [attachStudyUID release]; attachStudyUID = nil;
    [attachStudyTitle release]; attachStudyTitle = nil;

    id study = nil;
    @try
    {
        for( id item in [[BrowserController currentBrowser] databaseSelection])
        {
            if( [item isKindOfClass: [DicomStudy class]]) { study = item; break; }
            id s = [item valueForKey: @"study"];
            if( [s isKindOfClass: [DicomStudy class]]) { study = s; break; }
        }
    }
    @catch (NSException *e) { study = nil; }

    if( study)
    {
        NSString *name = [study valueForKey: @"name"], *pid = [study valueForKey: @"patientID"];
        // SekhVet Paket CS: -name is the display form (no '^', possibly capitalised). What goes into the
        // new DICOM files must be the raw PatientName, otherwise a PACS sees a different patient.
        NSString *rawName = [SekhmetRename rawNameOfStudy: study];
        if( rawName.length == 0) rawName = name;
        attachStudyUID = [[study valueForKey: @"studyInstanceUID"] retain];
        attachStudyTitle = [[NSString stringWithFormat: @"%@ (%@)", name ? name : @"?", pid ? pid : @"?"] retain];
        [nameField setStringValue: rawName ? rawName : @""];
        [idField setStringValue: pid ? pid : @""];
        NSDate *dob = [study valueForKey: @"dateOfBirth"];
        [birthKnownButton setState: dob ? NSControlStateValueOn : NSControlStateValueOff];
        if( dob) [birthPicker setDateValue: dob];
        NSString *sex = [study valueForKey: @"patientSex"];
        NSInteger si = sex.length ? [sexPopup indexOfItemWithTitle: [sex uppercaseString]] : -1;
        [sexPopup selectItemAtIndex: si >= 0 ? si : 0];
        NSString *desc = [study valueForKey: @"studyName"];
        [studyDescField setStringValue: desc ? desc : @""];
        NSDate *date = [study valueForKey: @"date"];
        [studyDatePicker setDateValue: date ? date : [NSDate date]];
        [attachButton setEnabled: YES];
        [attachButton setState: NSControlStateValueOn];
        [attachButton setTitle: [NSString stringWithFormat: NSLocalizedString( @"Attach to selected study: %@", nil), attachStudyTitle]];
    }
    else
    {
        [attachButton setEnabled: NO];
        [attachButton setState: NSControlStateValueOff];
        [attachButton setTitle: NSLocalizedString( @"Attach to selected study (no study selected in the browser)", nil)];
    }
    [self attachChanged: nil];
}

- (IBAction) attachChanged:(id) sender
{
    // Beim Anhaengen bleiben Patient und Studie wie in der Datenbank; nur Serie ist frei
    BOOL attach = ([attachButton state] == NSControlStateValueOn && attachStudyUID.length);
    [nameField setEnabled: !attach]; [idField setEnabled: !attach];
    [birthKnownButton setEnabled: !attach]; [birthPicker setEnabled: !attach]; [sexPopup setEnabled: !attach];
    [studyDescField setEnabled: !attach]; [studyDatePicker setEnabled: !attach];
}

#pragma mark - Aktionen

- (IBAction) chooseFiles:(id) sender
{
    NSOpenPanel *p = [NSOpenPanel openPanel];
    [p setAllowsMultipleSelection: YES]; [p setCanChooseDirectories: NO]; [p setCanChooseFiles: YES];
    [p setAllowedFileTypes: [SekhmetImport allExtensions]];
    [p setTitle: NSLocalizedString( @"Import images or PDFs as DICOM", nil)];
    [p setPrompt: NSLocalizedString( @"Choose", nil)];
    if( [p runModal] != NSModalResponseOK) return;
    [self importPaths: [[p URLs] valueForKeyPath: @"path"]];
}

- (void) importPaths:(NSArray*) paths
{
    [files setArray: paths];
    [self updateFilesLabel];
    [self prefillFromSelection];
    [self setStatus: nil];
    [self showWindow: nil];
    [[self window] makeKeyAndOrderFront: nil];
}

// Drag&Drop und "Import > Files": Bilder und PDFs aus der Dateiliste herausnehmen und ueber den Dialog wandeln, Rest zurueckgeben
+ (NSMutableArray*) takeConvertibleFilesFrom:(NSArray*) paths
{
    NSMutableArray *rest = [NSMutableArray array], *conv = [NSMutableArray array];
    NSArray *exts = [self allExtensions];
    for( NSString *p in paths)
    {
        if( [exts containsObject: [[p pathExtension] lowercaseString]] && [DicomFile isDICOMFile: p] == NO) [conv addObject: p];
        else [rest addObject: p];
    }
    if( conv.count) [[self shared] importPaths: conv];
    return rest;
}

- (IBAction) importNow:(id) sender
{
    if( files.count == 0) { [self setStatus: NSLocalizedString( @"No files selected", nil)]; return; }
    NSString *dir = [[DicomDatabase activeLocalDatabase] incomingDirPath];
    if( dir.length == 0) { [self setStatus: NSLocalizedString( @"No active database", nil)]; return; }

    BOOL attach = ([attachButton state] == NSControlStateValueOn && attachStudyUID.length);
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    NSString *name = [[nameField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    NSString *pid = [[idField stringValue] stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
    if( name.length == 0 || pid.length == 0) { [self setStatus: NSLocalizedString( @"Patient name and patient ID are required", nil)]; return; }
    [meta setObject: name forKey: @"patientsName"];
    [meta setObject: pid forKey: @"patientID"];
    if( [birthKnownButton state] == NSControlStateValueOn) [meta setObject: [birthPicker dateValue] forKey: @"patientsBirthdate"];
    if( [sexPopup indexOfSelectedItem] > 0) [meta setObject: [[sexPopup selectedItem] title] forKey: @"patientsSex"];
    [meta setObject: [studyDatePicker dateValue] forKey: @"studyDate"];
    NSString *sd = [studyDescField stringValue];
    if( sd.length) [meta setObject: sd forKey: @"studyDescription"];
    [meta setObject: [[modalityPopup selectedItem] title] forKey: @"modality"];

    NSString *studyUID = attach ? attachStudyUID : [DCMObject newStudyInstanceUID];
    NSString *seriesDesc = [seriesDescField stringValue];
    if( seriesDesc.length == 0) seriesDesc = NSLocalizedString( @"SekhVet Import", nil);

    [importButton setEnabled: NO];
    [self setStatus: NSLocalizedString( @"Writing…", nil)];
    int n = [SekhmetImport writeFiles: files meta: meta studyUID: studyUID seriesDescription: seriesDesc pdfAsPages: ([pdfPagesButton state] == NSControlStateValueOn) toDirectory: dir];
    [importButton setEnabled: YES];

    if( n == 0) [self setStatus: NSLocalizedString( @"Nothing written — file unreadable? (console)", nil)];
    else
    {
        [self setStatus: [NSString stringWithFormat: NSLocalizedString( @"%d DICOM file(s) written to INCOMING — importing now", nil), n]];
        [files removeAllObjects];
        [self updateFilesLabel];
    }
}

#pragma mark - Kern ohne GUI

// Zeichnet in ein 32-bit-RGBA-Bitmap (CoreGraphics kennt kein 24-bit RGB ohne Alpha) und kopiert nach 24-bit RGB,
// 72 dpi, Groesse = Pixel: DICOMExport liest [rep size] als Pixelmass und kennt kein Alpha
+ (NSImage*) rgbImageWidth:(NSInteger) w height:(NSInteger) h draw:(void (^)(void)) draw
{
    if( w <= 0 || h <= 0) return nil;
    NSBitmapImageRep *rgba = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: w pixelsHigh: h bitsPerSample: 8 samplesPerPixel: 4
                                                                         hasAlpha: YES isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace bitmapFormat: 0 bytesPerRow: w * 4 bitsPerPixel: 32] autorelease];
    NSGraphicsContext *ctx = rgba ? [NSGraphicsContext graphicsContextWithBitmapImageRep: rgba] : nil;
    if( ctx == nil) { NSLog( @"SekhVet Import: no graphics context for %d x %d", (int) w, (int) h); return nil; }

    [NSGraphicsContext saveGraphicsState];
    [NSGraphicsContext setCurrentContext: ctx];
    [[NSColor whiteColor] set];
    NSRectFill( NSMakeRect( 0, 0, w, h));
    draw();
    [ctx flushGraphics];
    [NSGraphicsContext restoreGraphicsState];

    NSBitmapImageRep *rgb = [[[NSBitmapImageRep alloc] initWithBitmapDataPlanes: NULL pixelsWide: w pixelsHigh: h bitsPerSample: 8 samplesPerPixel: 3
                                                                        hasAlpha: NO isPlanar: NO colorSpaceName: NSCalibratedRGBColorSpace bitmapFormat: 0 bytesPerRow: w * 3 bitsPerPixel: 24] autorelease];
    if( rgb == nil) return nil;
    unsigned char *s = [rgba bitmapData], *d = [rgb bitmapData];
    NSInteger sbpr = [rgba bytesPerRow], dbpr = [rgb bytesPerRow];
    for( NSInteger y = 0; y < h; y++)
    {
        unsigned char *sr = s + y * sbpr, *dr = d + y * dbpr;
        for( NSInteger x = 0; x < w; x++) { dr[ x*3] = sr[ x*4]; dr[ x*3+1] = sr[ x*4+1]; dr[ x*3+2] = sr[ x*4+2]; }
    }
    NSImage *out = [[[NSImage alloc] initWithSize: NSMakeSize( w, h)] autorelease];
    [out addRepresentation: rgb];
    return out;
}

+ (NSImage*) flattenedRGBImage:(NSImage*) src
{
    if( src == nil) return nil;
    NSInteger w = 0, h = 0;
    for( NSImageRep *r in [src representations])
    {
        if( [r pixelsWide] > w) { w = [r pixelsWide]; h = [r pixelsHigh]; }
    }
    if( w <= 0 || h <= 0) { w = (NSInteger) [src size].width; h = (NSInteger) [src size].height; }
    if( w <= 0 || h <= 0) { NSLog( @"SekhVet Import: image without pixel dimensions"); return nil; }
    return [self rgbImageWidth: w height: h draw: ^{
        [src drawInRect: NSMakeRect( 0, 0, w, h) fromRect: NSZeroRect operation: NSCompositingOperationSourceOver fraction: 1.0];
    }];
}

+ (NSImage*) imageFromPDFRep:(NSPDFImageRep*) rep dpi:(float) dpi
{
    NSRect b = [rep bounds];
    float s = dpi / 72.;
    NSInteger w = (NSInteger) ceil( b.size.width * s), h = (NSInteger) ceil( b.size.height * s);
    return [self rgbImageWidth: w height: h draw: ^{
        [rep drawInRect: NSMakeRect( 0, 0, w, h)];
    }];
}

+ (BOOL) writeImage:(NSImage*) img exporter:(DICOMExport**) exporter meta:(NSDictionary*) meta studyUID:(NSString*) studyUID seriesUID:(NSString*) seriesUID seriesDescription:(NSString*) seriesDesc toPath:(NSString*) outPath
{
    NSImage *flat = [self flattenedRGBImage: img];
    if( flat == nil) return NO;

    if( *exporter == nil)
    {
        // eine Serie fuer alle Bilder dieses Laufs; DICOMExport zaehlt die Instanznummer selbst hoch
        *exporter = [[[DICOMExport alloc] init] autorelease];
        NSMutableDictionary *d = [*exporter metaDataDict];
        [d removeObjectForKey: @"patientsBirthdate"];   // Vorgaben von DICOMExport (1900, M) nicht erfinden
        [d removeObjectForKey: @"patientsSex"];
        [d addEntriesFromDictionary: meta];
        [d setObject: studyUID forKey: @"studyUID"];
        [d setObject: seriesUID forKey: @"seriesUID"];
        [*exporter setSeriesDescription: seriesDesc];
        [*exporter setSeriesNumber: 1];
        [*exporter setModalityAsSource: NO];
    }
    // Nicht setPixelNSImage: das kopiert die Zeilen mit den noch ungesetzten Ivars width/height (Horos-Bug) und liefert Muell.
    // Unser Rep ist 24-bit RGB, zusammenhaengend (bytesPerRow = w*3), also direkt uebergeben; das Rep lebt bis zum Pool-Ende.
    NSBitmapImageRep *rep = (NSBitmapImageRep*) [[flat representations] objectAtIndex: 0];
    if( [*exporter setPixelData: [rep bitmapData] samplesPerPixel: 3 bitsPerSample: 8 width: [rep pixelsWide] height: [rep pixelsHigh]] != 0)
    {
        NSLog( @"SekhVet Import: setPixelData failed for %@", outPath);
        return NO;
    }
    NSString *r = [*exporter writeDCMFile: outPath];
    if( r == nil) NSLog( @"SekhVet Import: writeDCMFile failed for %@", outPath);
    return r != nil;
}

+ (BOOL) writeEncapsulatedPDF:(NSData*) pdf title:(NSString*) title meta:(NSDictionary*) meta studyUID:(NSString*) studyUID seriesNumber:(int) seriesNumber seriesDescription:(NSString*) seriesDesc toPath:(NSString*) outPath
{
    DCMObject *o = [DCMObject encapsulatedPDF: pdf];
    if( o == nil) return NO;

    NSDate *studyDate = [meta objectForKey: @"studyDate"];
    if( studyDate == nil) studyDate = [NSDate date];

    [o setAttributeValues: [NSMutableArray arrayWithObject: studyUID] forName: @"StudyInstanceUID"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [meta objectForKey: @"patientsName"]] forName: @"PatientsName"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [meta objectForKey: @"patientID"]] forName: @"PatientID"];
    if( [meta objectForKey: @"patientsBirthdate"])
        [o setAttributeValues: [NSMutableArray arrayWithObject: [DCMCalendarDate dicomDateWithDate: [meta objectForKey: @"patientsBirthdate"]]] forName: @"PatientsBirthDate"];
    if( [meta objectForKey: @"patientsSex"])
        [o setAttributeValues: [NSMutableArray arrayWithObject: [meta objectForKey: @"patientsSex"]] forName: @"PatientsSex"];
    if( [meta objectForKey: @"studyDescription"])
        [o setAttributeValues: [NSMutableArray arrayWithObject: [meta objectForKey: @"studyDescription"]] forName: @"StudyDescription"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [DCMCalendarDate dicomDateWithDate: studyDate]] forName: @"StudyDate"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [DCMCalendarDate dicomTimeWithDate: studyDate]] forName: @"StudyTime"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [DCMCalendarDate dicomDateWithDate: [NSDate date]]] forName: @"SeriesDate"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [DCMCalendarDate dicomTimeWithDate: [NSDate date]]] forName: @"SeriesTime"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: @"1"] forName: @"StudyID"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: [NSString stringWithFormat: @"%d", seriesNumber]] forName: @"SeriesNumber"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: seriesDesc] forName: @"SeriesDescription"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: title] forName: @"DocumentTitle"];
    [o setAttributeValues: [NSMutableArray arrayWithObject: @"SekhVet"] forName: @"Manufacturer"];

    BOOL ok = [o writeToFile: outPath withTransferSyntax: [DCMTransferSyntax ExplicitVRLittleEndianTransferSyntax] quality: DCMLosslessQuality atomically: YES];
    if( ok == NO) NSLog( @"SekhVet Import: writing encapsulated PDF failed for %@", outPath);
    return ok;
}

+ (int) writeFiles:(NSArray*) paths meta:(NSDictionary*) meta studyUID:(NSString*) studyUID seriesDescription:(NSString*) seriesDesc pdfAsPages:(BOOL) pdfAsPages toDirectory:(NSString*) dir
{
    if( paths.count == 0 || dir.length == 0 || studyUID.length == 0) return 0;

    NSString *stamp = [NSString stringWithFormat: @"%.0f", [NSDate timeIntervalSinceReferenceDate]];
    NSString *imageSeriesUID = [DCMObject newSeriesInstanceUID];
    DICOMExport *exporter = nil;
    int count = 0, index = 0, pdfSeries = 0;

    for( NSString *path in paths)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        @try
        {
            NSString *ext = [[path pathExtension] lowercaseString];
            if( [ext isEqualToString: @"pdf"])
            {
                NSData *pdf = [NSData dataWithContentsOfFile: path];
                if( pdf.length == 0) { NSLog( @"SekhVet Import: unreadable PDF (file %d of %d)", (int) [paths indexOfObject: path] + 1, (int) paths.count); }   // SekhVet Paket CS: no source paths in the log
                else if( pdfAsPages)
                {
                    NSPDFImageRep *rep = [NSPDFImageRep imageRepWithData: pdf];
                    for( NSInteger p = 0; p < [rep pageCount]; p++)
                    {
                        [rep setCurrentPage: p];
                        NSImage *img = [self imageFromPDFRep: rep dpi: 150];
                        NSString *out = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-%@-%d.dcm", stamp, index++]];
                        if( [self writeImage: img exporter: &exporter meta: meta studyUID: studyUID seriesUID: imageSeriesUID seriesDescription: seriesDesc toPath: out]) count++;
                    }
                }
                else
                {
                    NSString *out = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-%@-%d.dcm", stamp, index++]];
                    NSString *title = [[path lastPathComponent] stringByDeletingPathExtension];
                    NSString *desc = (paths.count > 1) ? [NSString stringWithFormat: @"%@ – %@", seriesDesc, title] : seriesDesc;
                    if( [self writeEncapsulatedPDF: pdf title: title meta: meta studyUID: studyUID seriesNumber: 6000 + pdfSeries++ seriesDescription: desc toPath: out]) count++;
                }
            }
            else
            {
                NSImage *img = [[[NSImage alloc] initWithContentsOfFile: path] autorelease];
                if( img == nil) NSLog( @"SekhVet Import: unreadable image (file %d of %d, .%@)", (int) [paths indexOfObject: path] + 1, (int) paths.count, ext);   // SekhVet Paket CS: no source paths in the log
                else
                {
                    NSString *out = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-%@-%d.dcm", stamp, index++]];
                    if( [self writeImage: img exporter: &exporter meta: meta studyUID: studyUID seriesUID: imageSeriesUID seriesDescription: seriesDesc toPath: out]) count++;
                }
            }
        }
        @catch (NSException *e) { NSLog( @"SekhVet Import: exception %@ at file %d of %d", e.name, (int) [paths indexOfObject: path] + 1, (int) paths.count); }   // SekhVet Paket CS: no source paths in the log
        [exporter retain];      // ueberlebt den Pool, damit die Instanznummern weiterzaehlen
        [pool release];
        [exporter autorelease];
    }
    return count;
}

#if SEKHVET_TESTHAKEN
// Headless-Test ohne lldb: SEKHVET_IMPORT_TEST="/pfad/a.jpg:/pfad/b.pdf" in der Umgebung, AppController ruft dies 20 s nach dem Start
+ (void) debugImportFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_IMPORT_TEST");
    if( env == NULL || strlen( env) == 0) return;
    NSArray *paths = [[NSString stringWithUTF8String: env] componentsSeparatedByString: @":"];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    [meta setObject: @"SekhVet^Test" forKey: @"patientsName"];
    [meta setObject: @"SEKHVET-TEST" forKey: @"patientID"];
    [meta setObject: [NSDate date] forKey: @"studyDate"];
    [meta setObject: @"SekhVet Import-Test" forKey: @"studyDescription"];
    [meta setObject: @"XC" forKey: @"modality"];
    NSString *dir = [[DicomDatabase activeLocalDatabase] incomingDirPath];
    BOOL pages = (sekhvetTesthaken( "SEKHVET_IMPORT_TEST_PAGES") != NULL);
    int n = [self writeFiles: paths meta: meta studyUID: [DCMObject newStudyInstanceUID] seriesDescription: @"Umgebungstest" pdfAsPages: pages toDirectory: dir];
    NSLog( @"SekhVet Import-Test (Umgebung): %d von %d Datei(en) nach %@", n, (int) paths.count, dir);
}
#endif // SEKHVET_TESTHAKEN

@end


#pragma mark - SekhmetDatenbankImport

// SekhVet: Import aus anderen Datenbanken (Kopf siehe SekhmetImport.h).

static NSString * const SekhmetDBImportVerlaufKey = @"SekhmetDatenbankImportVerlauf";   // { pfad: NSDate letzter Import }
static NSString * const SekhmetDBImportHinweisKey = @"SekhmetDatenbankImportHinweisGezeigt";

@implementation SekhmetDatenbankImport

+ (SekhmetDatenbankImport*) shared
{
    static SekhmetDatenbankImport *s = nil;
    if( s == nil) s = [[SekhmetDatenbankImport alloc] init];
    return s;
}

+ (NSString*) eigenerDatenordner
{
    return [[[DicomDatabase activeLocalDatabase] baseDirPath] stringByStandardizingPath];
}

+ (NSDictionary*) quelleFuerOrdner:(NSString*) ordner herkunft:(NSString*) herkunft
{
    if( ordner.length == 0) return nil;
    NSFileManager *fm = [NSFileManager defaultManager];
    ordner = [[ordner stringByResolvingSymlinksInPath] stringByStandardizingPath];
    BOOL dir = NO;
    if( [[ordner lastPathComponent] isEqualToString: @"DATABASE.noindex"] && [fm fileExistsAtPath: ordner isDirectory: &dir] && dir)
        ordner = [ordner stringByDeletingLastPathComponent];
    NSMutableArray *kandidaten = [NSMutableArray arrayWithObject: ordner];
    for( NSString *n in [fm contentsOfDirectoryAtPath: ordner error: nil])
        if( [n hasPrefix: @"."] == NO) [kandidaten addObject: [ordner stringByAppendingPathComponent: n]];
    NSString *eigen = [self eigenerDatenordner];
    for( NSString *k in kandidaten)
    {
        NSString *db = [k stringByAppendingPathComponent: @"DATABASE.noindex"];
        if( [fm fileExistsAtPath: db isDirectory: &dir] && dir)
        {
            if( eigen && [[k stringByStandardizingPath] isEqualToString: eigen]) continue; // die eigene Datenbank
            return @{ @"name": [k lastPathComponent], @"pfad": k, @"db": db, @"herkunft": herkunft ?: @"" };
        }
    }
    return nil;
}

/** Speicherort aus den Einstellungen einer anderen App (OsiriX/Horos): DEFAULT_DATABASELOCATION 1 = eigener Ort. */
+ (NSString*) eigenerOrtInEinstellungenVon:(NSString*) domaene
{
    NSDictionary *d = [[NSUserDefaults standardUserDefaults] persistentDomainForName: domaene];
    if( d == nil) return nil;
    if( [[d objectForKey: @"DEFAULT_DATABASELOCATION"] intValue] != 1 && [[d objectForKey: @"DATABASELOCATION"] intValue] != 1) return nil;
    NSString *url = [d objectForKey: @"DEFAULT_DATABASELOCATIONURL"];
    if( url.length == 0) url = [d objectForKey: @"DATABASELOCATIONURL"];
    return url.length ? url : nil;
}

+ (NSArray*) gefundeneQuellen
{
    NSMutableArray *aus = [NSMutableArray array];
    NSMutableSet *gesehen = [NSMutableSet set];
    void (^dazu)(NSDictionary*) = ^(NSDictionary *q) {
        if( q == nil || [gesehen containsObject: [q objectForKey: @"pfad"]]) return;
        [gesehen addObject: [q objectForKey: @"pfad"]];
        [aus addObject: q];
    };
    // Eigene Orte aus den Einstellungen von OsiriX (MD/Lite) und Horos
    for( NSArray *paar in @[ @[ @"com.rossetantoine.osirix", @"OsiriX" ], @[ @"com.pixmeo.osirixlite", @"OsiriX Lite" ], @[ @"com.horosproject.horos", @"Horos" ] ])
    {
        NSString *ort = [self eigenerOrtInEinstellungenVon: [paar objectAtIndex: 0]];
        if( ort) dazu( [self quelleFuerOrdner: ort herkunft: [NSString stringWithFormat: NSLocalizedString( @"%@ settings", nil), [paar objectAtIndex: 1]]]);
    }
    // Jeder Ordner in ~/Documents mit DATABASE.noindex: OsiriX Data, Horos Data (auch HorliX), Miele-LXIV …
    NSString *docs = [NSSearchPathForDirectoriesInDomains( NSDocumentDirectory, NSUserDomainMask, YES) firstObject];
    NSMutableArray *namen = [[[[NSFileManager defaultManager] contentsOfDirectoryAtPath: docs error: nil] mutableCopy] autorelease];
    [namen sortUsingSelector: @selector(localizedCaseInsensitiveCompare:)];
    for( NSString *n in namen)
    {
        if( [n hasPrefix: @"."]) continue;
        NSString *p = [docs stringByAppendingPathComponent: n];
        BOOL dir = NO;
        if( [[NSFileManager defaultManager] fileExistsAtPath: [p stringByAppendingPathComponent: @"DATABASE.noindex"] isDirectory: &dir] && dir)
            dazu( [self quelleFuerOrdner: p herkunft: NSLocalizedString( @"Documents folder", nil)]);
    }
    return aus;
}

+ (BOOL) importiere:(NSDictionary*) quelle
{
    NSString *db = [quelle objectForKey: @"db"];
    BrowserController *browser = [BrowserController currentBrowser];
    if( db.length == 0 || browser == nil || [[browser database] isLocal] == NO) return NO;
    NSString *eigen = [self eigenerDatenordner];
    if( eigen && [[[quelle objectForKey: @"pfad"] stringByStandardizingPath] isEqualToString: eigen]) return NO;

    NSString *pfad = [[[quelle objectForKey: @"pfad"] copy] autorelease];
    dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        @autoreleasepool {
            // Alle Dateien sammeln (ohne versteckte). Das Sortieren nach DICOM / kein DICOM erledigt der Import (onlyDICOM).
            NSMutableArray *dateien = [NSMutableArray array];
            unsigned long long bytes = 0;   // SekhVet Paket CS: for the free-space check
            BOOL gelesen = YES;
            @try   // SekhVet Paket CS: an exception on this queue would terminate the app
            {
                NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath: db];
                NSString *rel;
                while( (rel = [en nextObject]))
                {
                    if( [[rel lastPathComponent] hasPrefix: @"."]) continue;
                    NSDictionary *attr = [en fileAttributes];
                    if( [[attr objectForKey: NSFileType] isEqual: NSFileTypeRegular])
                    {
                        [dateien addObject: [db stringByAppendingPathComponent: rel]];
                        bytes += [attr fileSize];
                    }
                }
            }
            @catch (NSException *e) { NSLog( @"SekhVet database import: collecting files raised %@", e.name); gelesen = NO; }
            NSLog( @"SekhVet database import: %d files, %llu bytes", (int) dateien.count, bytes);   // SekhVet Paket CS: counts only
            dispatch_async( dispatch_get_main_queue(), ^{
                if( gelesen == NO)
                {
                    [[SekhmetDatenbankImport shared] setStatus: NSLocalizedString( @"Import not started: the files of the other database could not be read.", nil)];
                    return;
                }
                if( dateien.count == 0)
                {
                    [[SekhmetDatenbankImport shared] setStatus: NSLocalizedString( @"Nothing to import: the other database contains no files.", nil)];
                    return;
                }
                // SekhVet Paket CS: the whole foreign database is copied -- warn before the disk runs full half-way.
                // A warning, not a refusal: on the same APFS volume copies are clones and need no extra space.
                NSNumber *frei = [[[NSFileManager defaultManager] attributesOfFileSystemForPath: [[browser database] dataBaseDirPath] error: NULL] objectForKey: NSFileSystemFreeSize];
                const unsigned long long reserve = 1024ULL * 1024 * 1024;
                if( frei && [frei unsignedLongLongValue] < bytes + reserve)
                {
                    NSAlert *a = [[[NSAlert alloc] init] autorelease];
                    [a setAlertStyle: NSAlertStyleWarning];
                    [a setMessageText: NSLocalizedString( @"Probably not enough free disk space", nil)];
                    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"The other database holds %@, but only %@ are free on the volume of the SekhVet database. The import would stop half-way when the disk is full. (If both databases are on the same APFS volume, copies need almost no extra space.)", nil),
                                            [NSByteCountFormatter stringFromByteCount: (long long) bytes countStyle: NSByteCountFormatterCountStyleFile],
                                            [NSByteCountFormatter stringFromByteCount: [frei longLongValue] countStyle: NSByteCountFormatterCountStyleFile]]];
                    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
                    [a addButtonWithTitle: NSLocalizedString( @"Import Anyway", nil)];
                    if( [a runModal] != NSAlertSecondButtonReturn)
                    {
                        [[SekhmetDatenbankImport shared] setStatus: NSLocalizedString( @"Import cancelled: not enough free disk space.", nil)];
                        return;
                    }
                }
                // Immer kopieren, unabhaengig von den COPYDATABASE-Einstellungen: die Quelle gehoert einer anderen App.
                [browser copyFilesIntoDatabaseIfNeeded: dateien options: @{ @"COPYDATABASE": @YES, @"COPYDATABASEMODE": @(always),
                                                                            @"onlyDICOM": @YES, @"async": @YES,
                                                                            @"addToAlbum": @NO, @"selectStudy": @NO }];
                NSMutableDictionary *verlauf = [[[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetDBImportVerlaufKey] mutableCopy] autorelease] ?: [NSMutableDictionary dictionary];
                [verlauf setObject: [NSDate date] forKey: pfad];
                [[NSUserDefaults standardUserDefaults] setObject: verlauf forKey: SekhmetDBImportVerlaufKey];
                [[SekhmetDatenbankImport shared] setStatus: [NSString stringWithFormat: NSLocalizedString( @"Importing %d files from “%@” — progress in the Activity window. Images already in SekhVet are skipped.", nil), (int) dateien.count, [pfad lastPathComponent]]];
                [[SekhmetDatenbankImport shared] neuLesen];
            });
        }
    });
    return YES;
}

+ (void) startHinweis
{
    if( [[NSUserDefaults standardUserDefaults] boolForKey: SekhmetDBImportHinweisKey]) return;
    NSArray *q = [self gefundeneQuellen];
    if( q.count == 0) return;
    [[NSUserDefaults standardUserDefaults] setBool: YES forKey: SekhmetDBImportHinweisKey];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: NSLocalizedString( @"Other image databases found", nil)];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"SekhVet found %@ on this Mac. You can copy their studies into SekhVet at any time via Preferences › Database › “Import from Other Databases…” or the Vet Tools menu. The original databases stay untouched.", nil),
                            [[q valueForKey: @"name"] componentsJoinedByString: @", "]]];
    [a addButtonWithTitle: NSLocalizedString( @"Show Import…", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Later", nil)];
    if( [a runModal] == NSAlertFirstButtonReturn)
        [[self shared] zeigen: nil];
}

#pragma mark Fenster

- (id) init
{
    NSWindow *w = [[[NSWindow alloc] initWithContentRect: NSMakeRect( 0, 0, 820, 380)
                                               styleMask: NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
                                                 backing: NSBackingStoreBuffered defer: YES] autorelease];
    [w setTitle: NSLocalizedString( @"Import from Other Databases", nil)];
    [w setMinSize: NSMakeSize( 640, 300)];
    self = [super initWithWindow: w];
    if( self == nil) return nil;
    quellen = [[NSMutableArray alloc] init];
    NSView *v = [w contentView];

    NSTextField *info = [NSTextField wrappingLabelWithString: NSLocalizedString( @"Copies the studies of another Horos, OsiriX, HorliX or Miele-LXIV database into SekhVet. The original database is only read, never changed. Images already in SekhVet are skipped. ROIs stored as DICOM come along; albums, reports and settings do not.", nil)];
    [info setFrame: NSMakeRect( 20, 318, 780, 48)];
    [info setAutoresizingMask: NSViewWidthSizable | NSViewMinYMargin];
    [v addSubview: info];

    NSScrollView *sv = [[[NSScrollView alloc] initWithFrame: NSMakeRect( 20, 88, 780, 222)] autorelease];
    [sv setAutoresizingMask: NSViewWidthSizable | NSViewHeightSizable];
    [sv setHasVerticalScroller: YES];
    [sv setBorderType: NSBezelBorder];
    table = [[[NSTableView alloc] initWithFrame: [sv bounds]] autorelease];
    NSArray *spalten = @[ @[ @"name", NSLocalizedString( @"Database", nil), @150 ], @[ @"pfad", NSLocalizedString( @"Location", nil), @300 ],
                          @[ @"inhalt", NSLocalizedString( @"Content", nil), @150 ], @[ @"zuletzt", NSLocalizedString( @"Last Import", nil), @150 ] ];
    for( NSArray *s in spalten)
    {
        NSTableColumn *c = [[[NSTableColumn alloc] initWithIdentifier: [s objectAtIndex: 0]] autorelease];
        [[c headerCell] setStringValue: [s objectAtIndex: 1]];
        [c setWidth: [[s objectAtIndex: 2] floatValue]];
        [c setEditable: NO];
        [table addTableColumn: c];
    }
    [table setDataSource: self];   // SekhVet Paket CS: no delegate -- the class implements no delegate method
    [table setUsesAlternatingRowBackgroundColors: YES];
    [table setDoubleAction: @selector(importieren:)];
    [table setTarget: self];
    [sv setDocumentView: table];
    [v addSubview: sv];

    statusField = [NSTextField wrappingLabelWithString: @""];
    [statusField setFrame: NSMakeRect( 20, 50, 780, 32)];
    [statusField setAutoresizingMask: NSViewWidthSizable | NSViewMaxYMargin];
    [statusField setTextColor: [NSColor secondaryLabelColor]];
    [v addSubview: statusField];

    NSTextField *dank = [NSTextField labelWithString: NSLocalizedString( @"Idea: Hiroaki Inomata (PHORLIX) — thank you!", nil)];
    [dank setFrame: NSMakeRect( 20, 18, 300, 17)];
    [dank setFont: [NSFont systemFontOfSize: [NSFont smallSystemFontSize]]];
    [dank setTextColor: [NSColor tertiaryLabelColor]];
    [v addSubview: dank];

    NSButton *wahl = [NSButton buttonWithTitle: NSLocalizedString( @"Choose Folder…", nil) target: self action: @selector(ordnerWaehlen:)];
    [wahl setFrame: NSMakeRect( 440, 12, 150, 28)];
    [wahl setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [v addSubview: wahl];
    importButton = [NSButton buttonWithTitle: NSLocalizedString( @"Import", nil) target: self action: @selector(importieren:)];
    [importButton setFrame: NSMakeRect( 600, 12, 100, 28)];
    [importButton setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [importButton setKeyEquivalent: @"\r"];
    [v addSubview: importButton];
    NSButton *zu = [NSButton buttonWithTitle: NSLocalizedString( @"Close", nil) target: w action: @selector(performClose:)];
    [zu setFrame: NSMakeRect( 706, 12, 94, 28)];
    [zu setAutoresizingMask: NSViewMinXMargin | NSViewMaxYMargin];
    [v addSubview: zu];
    [w center];
    return self;
}

- (void) dealloc
{
    [quellen release];
    [super dealloc];
}

- (void) setStatus:(NSString*) text
{
    [statusField setStringValue: text ?: @""];
}

- (IBAction) zeigen:(id) sender
{
    [self neuLesen];
    [self showWindow: self];
    [[self window] makeKeyAndOrderFront: self];
}

- (void) neuLesen
{
    NSMutableArray *alt = [[quellen copy] autorelease];
    [quellen removeAllObjects];
    for( NSDictionary *q in [SekhmetDatenbankImport gefundeneQuellen])
        [quellen addObject: [[q mutableCopy] autorelease]];
    for( NSDictionary *q in alt) // selbst gewaehlte Ordner bleiben stehen
        if( [[quellen valueForKey: @"pfad"] containsObject: [q objectForKey: @"pfad"]] == NO && [[q objectForKey: @"gewaehlt"] boolValue])
            [quellen addObject: [[q mutableCopy] autorelease]];
    [table reloadData];
    [importButton setEnabled: quellen.count > 0];
    if( quellen.count == 0)
        [self setStatus: NSLocalizedString( @"No other database found in the Documents folder or the OsiriX/Horos settings. Use “Choose Folder…” for a database elsewhere (e.g. an external disk).", nil)];
    else if( [table selectedRow] < 0)
        [table selectRowIndexes: [NSIndexSet indexSetWithIndex: 0] byExtendingSelection: NO];
    // Inhalt (Dateien, Groesse) im Hintergrund zaehlen
    for( NSMutableDictionary *q in quellen)
    {
        if( [q objectForKey: @"inhalt"]) continue;
        [q setObject: NSLocalizedString( @"counting…", nil) forKey: @"inhalt"];
        NSString *db = [q objectForKey: @"db"];
        dispatch_async( dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
            @autoreleasepool {
                unsigned long long bytes = 0; long n = 0;
                NSDirectoryEnumerator *en = [[NSFileManager defaultManager] enumeratorAtPath: db];
                while( [en nextObject])
                {
                    NSDictionary *a = [en fileAttributes];
                    if( [[a objectForKey: NSFileType] isEqual: NSFileTypeRegular]) { n++; bytes += [[a objectForKey: NSFileSize] unsignedLongLongValue]; }
                }
                NSString *text = [NSString stringWithFormat: NSLocalizedString( @"%ld files · %@", nil), n, [NSByteCountFormatter stringFromByteCount: (long long) bytes countStyle: NSByteCountFormatterCountStyleFile]];
                dispatch_async( dispatch_get_main_queue(), ^{
                    [q setObject: text forKey: @"inhalt"];
                    [table reloadData];
                });
            }
        });
    }
}

- (IBAction) ordnerWaehlen:(id) sender
{
    NSOpenPanel *p = [NSOpenPanel openPanel];
    [p setCanChooseDirectories: YES];
    [p setCanChooseFiles: NO];
    [p setMessage: NSLocalizedString( @"Choose the database folder (e.g. “OsiriX Data” or “Horos Data”) or the folder that contains it.", nil)];
    if( [p runModal] != NSModalResponseOK) return;
    NSDictionary *q = [SekhmetDatenbankImport quelleFuerOrdner: [[p URL] path] herkunft: NSLocalizedString( @"chosen", nil)];
    if( q == nil)
    {
        NSAlert *a = [[[NSAlert alloc] init] autorelease];
        [a setMessageText: NSLocalizedString( @"No database in this folder", nil)];
        [a setInformativeText: NSLocalizedString( @"The folder contains no DATABASE.noindex folder (or it is SekhVet’s own database). For loose DICOM files use File › Import instead.", nil)];
        [a runModal];
        return;
    }
    NSMutableDictionary *m = [[q mutableCopy] autorelease];
    [m setObject: @YES forKey: @"gewaehlt"];
    if( [[quellen valueForKey: @"pfad"] containsObject: [m objectForKey: @"pfad"]] == NO) [quellen addObject: m];
    NSMutableArray *alt = [[quellen mutableCopy] autorelease];
    [self neuLesen];
    for( NSDictionary *x in alt) if( [[quellen valueForKey: @"pfad"] containsObject: [x objectForKey: @"pfad"]] == NO) [quellen addObject: [[x mutableCopy] autorelease]];
    [table reloadData];
    NSUInteger i = [[quellen valueForKey: @"pfad"] indexOfObject: [m objectForKey: @"pfad"]];
    if( i != NSNotFound) [table selectRowIndexes: [NSIndexSet indexSetWithIndex: i] byExtendingSelection: NO];
    [importButton setEnabled: YES];
}

- (IBAction) importieren:(id) sender
{
    NSInteger r = [table selectedRow];
    if( r < 0 || r >= (NSInteger) quellen.count) return;
    NSDictionary *q = [quellen objectAtIndex: r];
    NSAlert *a = [[[NSAlert alloc] init] autorelease];
    [a setMessageText: [NSString stringWithFormat: NSLocalizedString( @"Import “%@”?", nil), [q objectForKey: @"name"]]];
    [a setInformativeText: [NSString stringWithFormat: NSLocalizedString( @"All images in\n%@\nare copied into SekhVet (%@). The original stays untouched. Large databases take a while; you can keep working.", nil), [q objectForKey: @"db"], [q objectForKey: @"inhalt"] ?: @"…"]];
    [a addButtonWithTitle: NSLocalizedString( @"Import", nil)];
    [a addButtonWithTitle: NSLocalizedString( @"Cancel", nil)];
    if( [a runModal] != NSAlertFirstButtonReturn) return;
    if( [SekhmetDatenbankImport importiere: q] == NO)
        [self setStatus: NSLocalizedString( @"Import not possible: the active database is not a local SekhVet database, or this is SekhVet’s own database.", nil)];
    else
        [self setStatus: NSLocalizedString( @"Collecting files…", nil)];
}

- (NSInteger) numberOfRowsInTableView:(NSTableView*) tv
{
    return quellen.count;
}

- (id) tableView:(NSTableView*) tv objectValueForTableColumn:(NSTableColumn*) col row:(NSInteger) row
{
    if( row < 0 || row >= (NSInteger) quellen.count) return nil;
    NSDictionary *q = [quellen objectAtIndex: row];
    NSString *id_ = [col identifier];
    if( [id_ isEqualToString: @"name"])
        return [NSString stringWithFormat: @"%@ (%@)", [q objectForKey: @"name"], [q objectForKey: @"herkunft"]];
    if( [id_ isEqualToString: @"pfad"]) return [[q objectForKey: @"pfad"] stringByAbbreviatingWithTildeInPath];
    if( [id_ isEqualToString: @"zuletzt"])
    {
        NSDate *d = [[[NSUserDefaults standardUserDefaults] dictionaryForKey: SekhmetDBImportVerlaufKey] objectForKey: [q objectForKey: @"pfad"]];
        return d ? [NSDateFormatter localizedStringFromDate: d dateStyle: NSDateFormatterShortStyle timeStyle: NSDateFormatterShortStyle] : NSLocalizedString( @"never", nil);
    }
    return [q objectForKey: id_];
}

#if SEKHVET_TESTHAKEN
+ (void) debugDatenbankImportFromEnvironment
{
    const char *env = sekhvetTesthaken( "SEKHVET_DBIMPORT_TEST");
    if( env == NULL) return;
    for( NSDictionary *q in [self gefundeneQuellen])
        NSLog( @"SekhVet DBIMPORT gefunden: %@ | %@ | %@", [q objectForKey: @"name"], [q objectForKey: @"herkunft"], [q objectForKey: @"pfad"]);
    NSString *ziel = [NSString stringWithUTF8String: env];
    if( [ziel isEqualToString: @"liste"]) return;
    NSDictionary *q = [self quelleFuerOrdner: ziel herkunft: @"test"];
    NSLog( @"SekhVet DBIMPORT Quelle: %@ -> %@", ziel, q);
    if( q) NSLog( @"SekhVet DBIMPORT angestossen: %d", [self importiere: q]);
}
#endif // SEKHVET_TESTHAKEN

@end
