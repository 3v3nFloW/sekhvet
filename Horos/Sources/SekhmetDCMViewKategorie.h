/*=========================================================================
 DCMView (SekhVet) — Punkt-Werkzeug: Klickpunkt setzen, markieren,
 an die anderen 2D-Viewer senden, Marker wieder abraeumen.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in DCMView.m — zusammen rund 450 Zeilen fremder Code in
 Horos-eigenen Dateien. Als Kategorie stehen sie jetzt fuer sich; in
 DCMView.m bleiben nur die Haken, die sie rufen, und die
 Instanzvariablen (die kann eine Kategorie nicht tragen).
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#import "DCMView.h"

@interface DCMView (SekhVet)
+ (void) sekhmetClearPointMarkers;
- (void) sekhmetClearPointMarker;
- (void) sekhmetSync3DPointAtPixX:(float) x pixY:(float) y;
- (void) sekhmetDebugLogPoint;  // SekhVet Build 67: Testhaken — Lage des empfangenen 3D-Punkts dieses Viewers
@end
