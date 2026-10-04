/*=========================================================================
 DCMView (SekhVet) — Umsetzung.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Beschreibung im Header.
 ============================================================================*/

#import "SekhmetDCMViewKategorie.h"
#import "ViewerController.h"
#import "DCMPix.h"
#import "SekhmetTesthaken.h"

@implementation DCMView (SekhVet)

// SekhVet Paket AM: Die Punkt-Marker leben nur bis zur naechsten Schichtbewegung oder bis das Point-Werkzeug abgewaehlt wird
// (13.09.2026). Loescht in ALLEN 2D-Viewern beides: den eigenen Klickpunkt (orange) und das empfangene Kreuz.
+ (void) sekhmetClearPointMarkers
{
    for( ViewerController *vc in [ViewerController getDisplayed2DViewers])
        for( DCMView *v in [vc imageViews])
            [v sekhmetClearPointMarker];
}

- (void) sekhmetClearPointMarker
{
    BOOL had = (sekhmetOwnPointSet || slicePoint3D[ 0] != HUGE_VALF);
    sekhmetOwnPointSet = NO;
    sekhmetOwnPointImage = -1;
    slicePoint3D[ 0] = HUGE_VALF;
    if( had) [self setNeedsDisplay: YES];
}

// SekhVet Build 67: Point-Werkzeug — Punkt in Pixelkoordinaten setzen, im eigenen Bild markieren (orange), an alle anderen 2D-Viewer senden
- (void) sekhmetSync3DPointAtPixX:(float) x pixY:(float) y
{
    if( self.curDCM == nil || curImage < 0) return;
    mouseXPos = x; mouseYPos = y; // sync3DPosition liest mouseX/YPos (sonst Stand des letzten mouseMoved)
    float loc[ 3];
    [self.curDCM convertPixX: x pixY: y toDICOMCoords: loc pixelCenter: YES];
    [self.curDCM convertDICOMCoords: loc toSliceCoords: sekhmetOwnPoint pixelCenter: YES];
    sekhmetOwnPointImage = curImage; sekhmetOwnPointSet = YES;
#if SEKHVET_TESTHAKEN
    if( sekhvetTesthaken( "SEKHVET_POINT_TEST"))
        NSLog( @"SekhVet Point-Test Quelle %@: pix (%.1f, %.1f) img %d -> DICOM (%.2f %.2f %.2f) eigener Punkt (%.2f %.2f)", [[self seriesObj] valueForKey: @"name"], x, y, curImage, loc[ 0], loc[ 1], loc[ 2], sekhmetOwnPoint[ 0], sekhmetOwnPoint[ 1]);
#endif // SEKHVET_TESTHAKEN
    [self sync3DPosition];
    [self setNeedsDisplay: YES];
}

#if SEKHVET_TESTHAKEN
- (void) sekhmetDebugLogPoint // SekhVet Build 67: Testhaken — Lage des empfangenen 3D-Punkts dieses Viewers
{
    NSString *name = [[self seriesObj] valueForKey: @"name"];
    if( slicePoint3D[ 0] == HUGE_VALF || self.curDCM == nil) { NSLog( @"SekhVet Point-Test Lage %@: img %d von %d, kein Kreuz, eigener Punkt %@", name, curImage, (int) [dcmPixList count], sekhmetOwnPointSet ? @"JA" : @"nein"); return; }
    // SekhVet Paket CS: uncalibrated images have pixel spacing 0 — no division by zero in the log line
    float sx = self.curDCM.pixelSpacingX > 0 ? self.curDCM.pixelSpacingX : 1, sy = self.curDCM.pixelSpacingY > 0 ? self.curDCM.pixelSpacingY : 1;
    float d[ 3], px = slicePoint3D[ 0] / sx, py = slicePoint3D[ 1] / sy;
    [self.curDCM convertPixX: px pixY: py toDICOMCoords: d pixelCenter: YES];
    NSLog( @"SekhVet Point-Test Lage %@: img %d von %d, slicePt (%.2f %.2f) = pix (%.1f %.1f) -> DICOM (%.2f %.2f %.2f), eigener Punkt %@", name, curImage, (int) [dcmPixList count], slicePoint3D[ 0], slicePoint3D[ 1], px, py, d[ 0], d[ 1], d[ 2], sekhmetOwnPointSet ? @"JA" : @"nein");
}
#endif // SEKHVET_TESTHAKEN

@end
