/*=========================================================================
 SekhVet — Norberg Angle and Distraction Index (Hip Dysplasia, VD pelvis radiograph).
 Port of the ScrutPilot/HD-Messtool measurement to Horos ROIs (Paket U):
 two oval ROIs mark the femoral heads ("HD head R/L"), two 2D-point ROIs
 mark the craniolateral acetabular rims ("Norberg R/L"). All four are
 ordinary Horos ROIs: drag to move, drag the yellow grip point on the rim
 ("HD radius R/L", Paket W) to resize (kept circular), delete one and the whole group goes, stored with the
 series like any ROI. The angle between the line joining both centres and
 the line centre -> rim is written into the rim point's name (visible in
 its text box) and drawn as arm + arc + value over the image
 (OsirixDrawObjectsNotification). Screen left = right hip (VD convention).
 Normal >= 105 degrees.
 Paket BD/BE: Distraction Index (PennHIP formula, distraction view). Two
 more oval ROIs "HD cup R/L" (yellow) mark the acetabular cups, each with a
 grip on its inner side ("HD cup radius R/L"); they share the femoral head
 circles (and their grips / scroll-wheel resize) with the Norberg
 measurement. DI = distance(head centre, cup centre) / head radius, written
 into the cup's name ("HD cup R: 0.65") and drawn as a red centre line +
 value below the head (optionally with the risk level: < 0.30 low,
 0.30-0.70 moderate, > 0.70 high). Both measurements can live on the same
 image or alone.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import <Cocoa/Cocoa.h>
#include "SekhmetTesthaken.h"

@class ROI, DCMView, ViewerController;

@interface SekhmetNorberg : NSObject

+ (SekhmetNorberg*) shared;

/** Places a fresh measurement (both circles + both rim points) in the
 *  frontmost 2D viewer, sized relative to the window; replaces an existing one. */
- (void) placeInFrontViewer:(id) sender;
- (void) placeInViewer:(ViewerController*) vc;        // toolbar button of that viewer; an existing measurement is replaced (= reset)
- (void) deleteInViewer:(ViewerController*) vc;       // removes the Norberg measurement from that viewer (circles stay if a distraction index uses them)
- (void) deleteInFrontViewer:(id) sender;
+ (NSImage*) toolbarDeleteIcon;

/** Paket BD/BE: Distraction Index — both acetabular cup circles; the femoral head circles are
 *  created if missing, otherwise the existing ones (e.g. from a Norberg measurement) are used. */
- (void) placeDIInFrontViewer:(id) sender;
- (void) placeDIInViewer:(ViewerController*) vc;      // replaces existing cup circles (= reset)
- (void) deleteDIInViewer:(ViewerController*) vc;     // removes the cup circles (head circles stay if a Norberg measurement uses them)
/** Option "risk level in the DI label" (NSUserDefaults SekhmetDIRisk); setting it redraws all 2D viewers. */
+ (BOOL) showsRisk;
+ (void) setShowsRisk:(BOOL) on;
+ (NSString*) riskTextForDI:(double) di;              // "low" (< 0.30), "moderate" (0.30-0.70), "high" (> 0.70)
- (void) deleteDIInFrontViewer:(id) sender;
+ (NSImage*) toolbarDIIcon;
+ (NSImage*) toolbarDIDeleteIcon;

/** Scroll wheel over a femoral head circle resizes it (Paket Y). YES = consumed, DCMView must not scroll images. */
+ (BOOL) handleScrollWheel:(NSEvent*) event inView:(DCMView*) v;

/** Toolbar icon (template image): two femoral head circles, centre line, angle arc. */
+ (NSImage*) toolbarIcon;

/** Inner angle (0..180 degrees, 0.1 steps) at centre c between the line to the
 *  other centre and the line to the rim point; pixel coordinates scaled by the
 *  pixel spacing so non-square pixels measure correctly. */
+ (double) angleAtCenter:(NSPoint) c rim:(NSPoint) rim other:(NSPoint) other spacingX:(double) sx spacingY:(double) sy;

/** Distraction index (PennHIP formula): distance head centre -> cup centre divided by the
 *  head radius, in mm via the pixel spacing (radius along x), 0.001 steps; 0 if the radius is 0. */
+ (double) distractionIndexAtCenter:(NSPoint) c radius:(double) r cup:(NSPoint) cup spacingX:(double) sx spacingY:(double) sy;

/** SEKHVET_NORBERG_TEST=1: geometry check without GUI. */
#if SEKHVET_TESTHAKEN
+ (NSString*) debugSelfTest;
#endif // SEKHVET_TESTHAKEN

@end
