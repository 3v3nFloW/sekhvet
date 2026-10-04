/*=========================================================================
 DCMView (SekhVet) — Punkt-Werkzeug: Klickpunkt setzen, markieren,
 an die anderen 2D-Viewer senden, Marker wieder abraeumen.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.

 Stufe 6c des Reviews vom 12.09.2026: Diese Methoden standen bis zum
 14.09.2026 mitten in DCMView.m. Als Kategorie stehen sie jetzt fuer sich; in
 DCMView.m bleiben nur die Haken, die sie rufen, das Zeichnen der Marker und
 die Instanzvariablen (die kann eine Kategorie nicht tragen).
 (SekhVet Paket CS: the line count the old header gave, "about 450", did not
 fit this file — it has about 65 lines.)
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"
#import "DCMView.h"

@interface DCMView (SekhVet)
+ (void) sekhmetClearPointMarkers;
- (void) sekhmetClearPointMarker;
- (void) sekhmetSync3DPointAtPixX:(float) x pixY:(float) y;
#if SEKHVET_TESTHAKEN
- (void) sekhmetDebugLogPoint;  // SekhVet Build 67: Testhaken — Lage des empfangenen 3D-Punkts dieses Viewers
#endif // SEKHVET_TESTHAKEN
@end
