/*=========================================================================
 ViewerController (SekhVet) — Umsetzung.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in ViewerController.m — zusammen rund 450 Zeilen fremder Code in
 Horos-eigenen Dateien. Als Kategorie stehen sie jetzt fuer sich; in
 ViewerController.m bleiben nur die Haken, die sie rufen, und die
 Instanzvariablen (die kann eine Kategorie nicht tragen).
 ============================================================================*/

#import "SekhmetViewerKategorie.h"
#import "DCMView.h"
#import "AppController.h"
#import "Notifications.h"
#import "SekhmetOrientation.h"
#import "SekhmetOrientationPanel.h"
#import "SekhmetDisplayPanel.h"
#import "SekhmetSpine.h"
#import "SekhmetNorberg.h"
#import "SekhmetUSKalibrierung.h"
#import "DCMPix.h"
#import <objc/runtime.h>

NSString* const SekhmetVetPresetToolbarItemIdentifier = @"SekhmetVetPreset";
NSString* const SekhmetSpineToolbarItemIdentifier = @"SekhmetSpine";
NSString* const SekhmetNorbergToolbarItemIdentifier = @"SekhmetNorberg";
NSString* const SekhmetNorbergDeleteToolbarItemIdentifier = @"SekhmetNorbergDelete";
NSString* const SekhmetDIToolbarItemIdentifier = @"SekhmetDI";
NSString* const SekhmetDIDeleteToolbarItemIdentifier = @"SekhmetDIDelete";
NSString* const SekhmetMPRSwapToolbarItemIdentifier = @"SekhmetMPRSwap"; // SekhVet Paket BW-2
NSString* const SekhmetScreenAreaToolbarItemIdentifier = @"SekhmetScreenArea";

@implementation ViewerController (SekhVet)

// Sekhmet: Werkzeug "Punkt in anderen Serien zeigen" (OsiriX-MD-Toolbar); Klick ins Bild ruft DCMView sync3DPosition
- (IBAction) sekhmetShow3DPointTool:(id) sender
{
    // wie Horos' Werkzeugwahl: alle 2D-Viewer bekommen das Werkzeug, sonst wirkt der Klick nur in einem Fenster
    [[NSNotificationCenter defaultCenter] postNotificationName: OsirixDefaultToolModifiedNotification object: nil userInfo: [NSDictionary dictionaryWithObjectsAndKeys: @(t3Dpoint), @"toolIndex", nil]];
}

// Sekhmet: Vet-Orientierung — Preset-Popup in der Werkzeugleiste
- (void) sekhmetUpdatePresetPopup
{
    for( NSToolbarItem *item in [toolbar items])
    {
        if( [[item itemIdentifier] isEqualToString: SekhmetVetPresetToolbarItemIdentifier])
            {
                NSPopUpButton *pb = (NSPopUpButton*) [item view];   // SekhVet Paket BP: Liste kann sich geaendert haben
                [pb setMenu: [SekhmetOrientation presetMenuIncludingOff: YES]];
                [pb selectItemWithTag: [SekhmetOrientation presetForStudyUID: [self studyInstanceUID] description: [SekhmetOrientation descriptionForViewer: self]]];
            }
    }
}

// SekhVet Paket BH: US-Bilder ohne Kalibrierung uebernehmen sie von einem Bild derselben Serie mit gleicher Tiefenskala
- (void) sekhmetBorrowUSCalibration:(NSArray*) pixListArray
{
    for( NSUInteger m = 0; m < pixListArray.count && m < (NSUInteger) [self maxMovieIndex]; m++)
    {
        NSArray *pl = [pixListArray objectAtIndex: m];
        NSArray *fl = fileList[ m];
        if( fl.count != pl.count) continue;

        BOOL candidate = NO;
        for( DCMPix *p in pl)
            if( [[p modalityString] isEqualToString: @"US"] && [p hasUSRegions] == NO) { candidate = YES; break; }
        if( candidate == NO) continue;

        NSMutableArray *labels = [NSMutableArray arrayWithCapacity: pl.count];
        for( NSUInteger i = 0; i < pl.count; i++)
        {
            id inst = nil;
            @try { inst = [[fl objectAtIndex: i] valueForKey: @"instanceNumber"]; } @catch( NSException *e) { inst = nil; }
            [labels addObject: inst ? [NSString stringWithFormat: @"image %@", inst] : [NSString stringWithFormat: @"image %lu", (unsigned long) i + 1]];
        }
        if( [SekhmetUSKalibrierung borrowCalibrationInPixList: pl labels: labels])
            [imageView setNeedsDisplay: YES];
    }
}

- (IBAction) sekhmetSpineTool:(id) sender
{
    [[SekhmetSpine shared] toggleWithWindowController: self];
}

- (IBAction) sekhmetNorbergTool:(id) sender // SekhVet Paket V
{
    [[SekhmetNorberg shared] placeInViewer: self];
}

- (IBAction) sekhmetNorbergDeleteTool:(id) sender // SekhVet Paket W
{
    [[SekhmetNorberg shared] deleteInViewer: self];
}

- (IBAction) sekhmetDITool:(id) sender // SekhVet Paket BD
{
    [[SekhmetNorberg shared] placeDIInViewer: self];
}

- (IBAction) sekhmetDIDeleteTool:(id) sender // SekhVet Paket BD
{
    [[SekhmetNorberg shared] deleteDIInViewer: self];
}

// SekhVet Paket V: die Toolbar sichert ihre Anordnung (autosavesConfiguration) — ein neuer Standard-Knopf erscheint sonst nur
// ueber "Customize Toolbar". Einmalig einfuegen; entfernt der Benutzer ihn danach, bleibt er weg.
- (void) sekhmetEnsureNorbergToolbarItem
{
    if( toolbar == nil) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    // Paket W: Norberg + Delete Norberg (one key); Paket BD: Distraction Index; Paket BE: Delete DI — each with its own key,
    // so installations that already have the earlier buttons get the new one once as well. Paket BW-2: Swap MPR behind Point.
    NSString *wanted[ 5] = { SekhmetNorbergToolbarItemIdentifier, SekhmetNorbergDeleteToolbarItemIdentifier, SekhmetDIToolbarItemIdentifier, SekhmetDIDeleteToolbarItemIdentifier, SekhmetMPRSwapToolbarItemIdentifier };
    NSString *after[ 5]  = { SekhmetSpineToolbarItemIdentifier, SekhmetNorbergToolbarItemIdentifier, SekhmetNorbergDeleteToolbarItemIdentifier, SekhmetDIToolbarItemIdentifier, @"Sekhmet3DPoint" };
    NSString *key[ 5]    = { @"SekhmetNorbergToolbarInserted2", @"SekhmetNorbergToolbarInserted2", @"SekhmetDIToolbarInserted", @"SekhmetDIDeleteToolbarInserted", @"SekhmetMPRSwapToolbarInserted" };
    for( int w = 0; w < 5; w++)
    {
        if( [ud boolForKey: key[ w]]) continue;
        NSInteger idx = -1, i = 0;
        BOOL present = NO;
        for( NSToolbarItem *it in [toolbar items])
        {
            if( [[it itemIdentifier] isEqualToString: wanted[ w]]) { present = YES; break; }
            if( [[it itemIdentifier] isEqualToString: after[ w]]) idx = i + 1;
            i++;
        }
        if( present) continue;
        if( idx < 0) idx = [[toolbar items] count];
        [toolbar insertItemWithItemIdentifier: wanted[ w] atIndex: idx];
    }
    for( int w = 0; w < 5; w++) [ud setBool: YES forKey: key[ w]];
}

- (IBAction) sekhmetScreenAreaChanged:(id) sender
{
    [SekhmetDisplayPanel setMode: [SekhmetDisplayPanel modeForIndex: [sender indexOfSelectedItem]] forScreen: [[self window] screen]];
    [[AppController sharedAppController] tileWindows: nil];
}

- (IBAction) sekhmetPresetChanged:(id) sender
{
    [SekhmetOrientation setPresetOverride: [[sender selectedItem] tag] forStudyUID: [self studyInstanceUID]];
    [SekhmetOrientation applyToAllViewersOfStudyUID: [self studyInstanceUID]];
}

- (void) sekhmetPresetDidChange:(NSNotification*) n
{
    [self sekhmetUpdatePresetPopup];
}

@end

// SekhVet Paket BG (16.09.2026, Rueckmeldung eines Testers unter macOS 27): die Horos-Toolbar-Icons sind PDFs mit
// 300-530 pt Seitengroesse (Export.pdf 527x528). Bis macOS 26 passt NSToolbar solche Bilder von selbst in die
// Symbolgroesse ein; das SDK 27 erklaert NSToolbarSizeMode fuer "will be ignored", und beim Tester erschienen die
// Symbole etwa doppelt so gross. Jedes Toolbar-Bild wird darum beim Setzen auf hoechstens 32 pt Kantenlaenge
// gebracht (Kopie, das gemeinsame imageNamed:-Bild bleibt unveraendert; PDF verliert dabei keine Aufloesung).
// Gilt fuer alle Fenster (DB, Viewer, MPR, VR, CPR ...), weil alle ueber -[NSToolbarItem setImage:] gehen.
@implementation NSToolbarItem (SekhVetIconSize)

+ (void) load
{
    static dispatch_once_t once;
    dispatch_once( &once, ^{
        Method o = class_getInstanceMethod( [NSToolbarItem class], @selector(setImage:));
        Method n = class_getInstanceMethod( [NSToolbarItem class], @selector(sekhvetSetImage:));
        if( o && n) method_exchangeImplementations( o, n);
    });
}

- (void) sekhvetSetImage:(NSImage*) image
{
    const CGFloat kMax = 32;
    NSSize sz = image ? [image size] : NSZeroSize;
    if( image && (sz.width > kMax || sz.height > kMax) && sz.width > 0 && sz.height > 0)
    {
        CGFloat f = kMax / MAX( sz.width, sz.height);
        NSImage *c = [[image copy] autorelease];
        [c setSize: NSMakeSize( round( sz.width * f), round( sz.height * f))];
        image = c;
    }
    [self sekhvetSetImage: image];   // vertauscht: ruft das originale setImage:
}

@end
