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
        attachStudyUID = [[study valueForKey: @"studyInstanceUID"] retain];
        attachStudyTitle = [[NSString stringWithFormat: @"%@ (%@)", name ? name : @"?", pid ? pid : @"?"] retain];
        [nameField setStringValue: name ? name : @""];
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
    if( ctx == nil) { NSLog( @"SekhVet Import: kein Grafikkontext fuer %d x %d", (int) w, (int) h); return nil; }

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
    if( w <= 0 || h <= 0) { NSLog( @"SekhVet Import: Bild ohne Pixelmass"); return nil; }
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
        NSLog( @"SekhVet Import: setPixelData scheiterte fuer %@", outPath);
        return NO;
    }
    NSString *r = [*exporter writeDCMFile: outPath];
    if( r == nil) NSLog( @"SekhVet Import: writeDCMFile scheiterte fuer %@", outPath);
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
    if( ok == NO) NSLog( @"SekhVet Import: Encapsulated PDF schreiben scheiterte fuer %@", outPath);
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
                if( pdf.length == 0) { NSLog( @"SekhVet Import: PDF unlesbar %@", path); }
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
                if( img == nil) NSLog( @"SekhVet Import: Bild unlesbar %@", path);
                else
                {
                    NSString *out = [dir stringByAppendingPathComponent: [NSString stringWithFormat: @"SekhVet-%@-%d.dcm", stamp, index++]];
                    if( [self writeImage: img exporter: &exporter meta: meta studyUID: studyUID seriesUID: imageSeriesUID seriesDescription: seriesDesc toPath: out]) count++;
                }
            }
        }
        @catch (NSException *e) { NSLog( @"SekhVet Import: Ausnahme bei %@: %@", path, e); }
        [exporter retain];      // ueberlebt den Pool, damit die Instanznummern weiterzaehlen
        [pool release];
        [exporter autorelease];
    }
    return count;
}

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

+ (NSString*) debugImportCPath:(const char*) path
{
    NSString *p = [NSString stringWithUTF8String: path];
    NSMutableDictionary *meta = [NSMutableDictionary dictionary];
    [meta setObject: @"SekhVet^Test" forKey: @"patientsName"];
    [meta setObject: @"SEKHVET-TEST" forKey: @"patientID"];
    [meta setObject: [NSDate date] forKey: @"studyDate"];
    [meta setObject: @"SekhVet Import-Test" forKey: @"studyDescription"];
    [meta setObject: @"XC" forKey: @"modality"];
    NSString *dir = [[DicomDatabase activeLocalDatabase] incomingDirPath];
    int n = [self writeFiles: [NSArray arrayWithObject: p] meta: meta studyUID: [DCMObject newStudyInstanceUID] seriesDescription: @"Test" pdfAsPages: NO toDirectory: dir];
    return [NSString stringWithFormat: @"%d Datei(en) nach %@", n, dir];
}

@end
