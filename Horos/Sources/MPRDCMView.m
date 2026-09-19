/*=========================================================================
 This file is part of the Horos Project (www.horosproject.org)
 
 Horos is free software: you can redistribute it and/or modify
 it under the terms of the GNU Lesser General Public License as published by
 the Free Software Foundation,  version 3 of the License.
 
 The Horos Project was based originally upon the OsiriX Project which at the time of
 the code fork was licensed as a LGPL project.  However, not all of the the source-code
 was properly documented and file headers were not all updated with the appropriate
 license terms. The Horos Project, originally was licensed under the  GNU GPL license.
 However, contributors to the software since that time have agreed to modify the license
 to the GNU LGPL in order to be conform to the changes previously made to the
 OsiriX Project.
 
 Horos is distributed in the hope that it will be useful, but
 WITHOUT ANY WARRANTY EXPRESS OR IMPLIED, INCLUDING ANY WARRANTY OF
 MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE OR USE.  See the
 GNU Lesser General Public License for more details.
 
 You should have received a copy of the GNU Lesser General Public License
 along with Horos.  If not, see http://www.gnu.org/licenses/lgpl.html
 
 Prior versions of this file were published by the OsiriX team pursuant to
 the below notice and licensing protocol.
 ============================================================================
 Program:   OsiriX
  Copyright (c) OsiriX Team
  All rights reserved.
  Distributed under GNU - LGPL
  
  See http://www.osirix-viewer.com/copyright.html for details.
     This software is distributed WITHOUT ANY WARRANTY; without even
     the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR
     PURPOSE.
 ============================================================================*/

#import "SekhmetMPRKategorie.h" // SekhVet Stufe 6c
#import "options.h"

#import "SekhmetSpine.h" // Sekhmet
#import "MPRDCMView.h"
#import "VRController.h"
#import "VRView.h"
#import "DCMCursor.h"
#import "ROI.h"
#import "Notifications.h"
#import "OSIEnvironment.h"
#import "OSIROI.h"
#import "OSIVolumeWindow.h"
#import "OSIGeometry.h"

static float deg2rad = M_PI/180.0; 

#define CROSS(dest,v1,v2) \
          dest[0]=v1[1]*v2[2]-v1[2]*v2[1]; \
          dest[1]=v1[2]*v2[0]-v1[0]*v2[2]; \
          dest[2]=v1[0]*v2[1]-v1[1]*v2[0];
		  
BOOL arePlanesParallel( float *Pn1, float *Pn2)
{
	float u[ 3];
	
	CROSS(u, Pn1, Pn2);
	
	float    ax = (u[0] >= 0 ? u[0] : -u[0]);
    float    ay = (u[1] >= 0 ? u[1] : -u[1]);
    float    az = (u[2] >= 0 ? u[2] : -u[2]);
	
    if ((ax+ay+az) < 0.001)
		return YES;
	
    return NO;
}

#define VIEW_COLOR_LABEL_SIZE 25

// SekhVet Paket AT: der Zoom-Zustand des Doppelklicks lag hier als Datei-Statik und galt
// damit fuer ALLE MPR-Fenster zugleich. Er sitzt jetzt am MPRController (je Fenster).
unsigned int minimumStep;

@interface MPRDCMView ()
- (void)drawOSIROIs;
- (OSIROIManager *)ROIManager;
- (N3Plane)plane;
@end

@interface MPRDCMView (Dummy)
- (void)delayedFullLODRendering:(id)dummy;
@end;

// SekhVet Paket BK (macOS 27): zusammengeklappte MPR-Ansichten behalten einen Rest von 2 pt. Eine Ansicht mit 0 Pixeln
// laesst AppKit beim Anbinden/Zeichnen des GL-Kontexts in CABackingStoreEndUpdate abbrechen (Absturz beim Doppelklick-Zoom).
#define SEKHMET_SPLIT_REST 2
// Ansichten schmaler als SEKHMET_MIN_VIEW gelten als zusammengeklappt: nicht zeichnen, nicht rendern, den gemeinsamen
// vrView nicht auf ihre Groesse setzen (sonst zeigt eine wachsende Nachbaransicht ein weisses Bild, Befund 17.09. in der VM).
#define SEKHMET_MIN_VIEW 8

@implementation MPRDCMView

@synthesize dontUseAutoLOD, pix, camera, angleMPR, vrView, viewExport, toIntervalExport, fromIntervalExport, rotateLines, moveCenter, displayCrossLines, LOD;

- (BOOL)becomeFirstResponder
{
	BOOL v = [super becomeFirstResponder];
	
	[windowController updateToolbarItems];

	return v;
}

- (void) setDisplayCrossLines: (BOOL) b
{
	displayCrossLines = b;
	[windowController updateToolbarItems];
}

- (BOOL)is2DTool:(ToolMode)tool;
{
	switch( tool)
	{
		case tWL:
			if( vrView.renderingMode == 1 || vrView.renderingMode == 3 || vrView.renderingMode == 2) return YES; // MIP
			else return NO; // VR
		break;
		
		case tNext:
		case tMesure:
		case tROI:
		case tOval:
		case tOPolygon:
		case tCPolygon:
		case tAngle:
		case tArrow:
		case tText:
		case tPencil:
		case tPlain:
		case t2DPoint:
		case tRepulsor:
		case tLayerROI:
		case tROISelector:
			return YES;
        default:;
	}
	
	return NO;
}

- (void) setDCMPixList:(NSMutableArray*)pixList filesList:(NSArray*)files roiList:(NSMutableArray*)rois firstImage:(short)firstImage type:(char)type reset:(BOOL)reset;
{
	[super setPixels:pixList files:files rois:rois firstImage:firstImage level:type reset:reset];

	[[NSNotificationCenter defaultCenter]	addObserver: self
											selector: @selector(removeROI:)
											name: OsirixRemoveROINotification
											object: nil];


	rotation = 0;
	
	pix = [pixList lastObject];
	
	currentTool = t3DRotate;
	
	displayCrossLines = YES;
	
	windowController = [self windowController];
	windowController.sekhmetFrameZoomed = NO;
	
	[windowController updateToolbarItems];
}

- (void) setVRView: (VRView*) v viewID:(int) i
{
	viewID = i;
	vrView = v;
	[vrView prepareFullDepthCapture];
}

- (void) saveCamera
{
	[camera release];
	camera = [[vrView cameraWithThumbnail: NO] retain];
}

- (void) setFrame:(NSRect)frameRect
{
    NSDisableScreenUpdates();
    
	if( NSEqualRects( frameRect, [self frame]) == NO)
	{
		[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(updateViewsAccordingToFrame:) object: nil];
		[windowController performSelector: @selector(updateViewsAccordingToFrame:) withObject: nil afterDelay: 0.1];
	}
	
	if( blendingView)
	{
		[blendingView setFrame: frameRect];
		blendingView.drawingFrameRect = [self convertRectToBacking: frameRect]; // very important to have correct position values with PET-CT
	}
	
	// SekhVet Paket BK (macOS 27): eine auf 0 Pixel zusammengeklappte Ansicht (Doppelklick-Zoom, Teiler am Anschlag)
	// darf ihren GL-Kontext nicht mehr an das Fenster binden. AppKit ruft in [super setFrame:] [NSOpenGLContext update],
	// und QuartzCore bricht unter macOS 27 mit einer Assertion in CABackingStoreEndUpdate ab (Absturz 17.09.2026,
	// Doppelklick im Double-MPR). Zeichenflaeche loesen, solange die Ansicht keine Flaeche hat; wieder anbinden,
	// sobald sie eine bekommt.
	BOOL sekhmetDegenerate = (frameRect.size.width < 1 || frameRect.size.height < 1);
	if( sekhmetDegenerate && sekhmetGLDetached == NO)
	{
		[[self openGLContext] clearDrawable];
		sekhmetGLDetached = YES;
	}
	
	[super setFrame: frameRect];
	
	if( sekhmetDegenerate == NO && sekhmetGLDetached)
	{
		[[self openGLContext] setView: self];
		sekhmetGLDetached = NO;
		[self setNeedsDisplay: YES];
	}
    
    NSEnableScreenUpdates();
}

// SekhVet Paket AV: Abschluss des Doppelklick-Zooms, nachdem die NSSplitView ihr Layout hat.
// Paket BF: nicht nur die angeklickte Ansicht, sondern JEDE Ansicht mit Flaeche neu rendern (beim Zurueckstellen
// wachsen zwei Ansichten, die sonst ihr altes Bild nur skaliert zeigten), und 0,25 s spaeter ein zweiter Durchgang
// mit aufgefrischtem GL-Kontext — das ist, was der "zweite Doppelklick" von Hand tat.
- (void) sekhmetFinishZoom
{
	if( sekhmetDetached) return;
	windowController.lowLOD = NO;
	[self sekhmetRenderVisibleViews];
	[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetFinishZoomSecondPass) object: nil];
	[self performSelector: @selector(sekhmetFinishZoomSecondPass) withObject: nil afterDelay: 0.25 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
}

- (void) sekhmetRenderVisibleViews
{
	if( sekhmetDetached || windowController == nil) return;
	MPRDCMView *views[ 3] = { windowController.mprView1, windowController.mprView2, windowController.mprView3 };
	for( int i = 0; i < 3; i++)
	{
		MPRDCMView *v = views[ i];
		if( v == nil || [v frame].size.width < SEKHMET_MIN_VIEW || [v frame].size.height < SEKHMET_MIN_VIEW) continue;
		v.camera.forceUpdate = YES;
		[v restoreCamera];            // setzt ueber checkForFrame den gemeinsamen vrView auf die Groesse dieser Ansicht
		[v updateViewMPR];
	}
	// die angeklickte Ansicht zuletzt, damit der vrView mit ihrer Groesse stehen bleibt
	if( [self frame].size.width >= SEKHMET_MIN_VIEW && [self frame].size.height >= SEKHMET_MIN_VIEW)
	{
		camera.forceUpdate = YES;
		[self restoreCamera];
		[self updateViewMPR];
	}
}

- (void) sekhmetFinishZoomSecondPass
{
	if( sekhmetDetached || windowController == nil) return;
	MPRDCMView *views[ 3] = { windowController.mprView1, windowController.mprView2, windowController.mprView3 };
	for( int i = 0; i < 3; i++)
		if( views[ i] && [views[ i] frame].size.width >= SEKHMET_MIN_VIEW && [views[ i] frame].size.height >= SEKHMET_MIN_VIEW)
			[[views[ i] openGLContext] update];   // Zeichenflaeche des NSOpenGLView auf den neuen Rahmen bringen
	[self sekhmetRenderVisibleViews];
	for( int i = 0; i < 3; i++) [views[ i] setNeedsDisplay: YES];
}

- (void) checkForFrame
{
	NSRect frame = [self convertRectToBacking: [self frame]];
	NSPoint o = [self convertPoint: NSMakePoint(0, 0) toView:0L];
	frame.origin = o;
	
	// SekhVet Paket BF: eine zusammengeklappte Ansicht (Doppelklick-Zoom, Teiler am Anschlag) darf den GEMEINSAMEN
	// vrView nicht auf null Flaeche setzen — jede spaetere Ausgabe der anderen Ansichten rendert sonst gegen 0 Pixel.
	if( frame.size.width < SEKHMET_MIN_VIEW || frame.size.height < SEKHMET_MIN_VIEW)
		return;
	
	if( NSEqualRects( frame, [vrView frame]) == NO)
	{
		[vrView setFrame: frame];
	}
}
//
//- (BOOL) hasCameraMoved: (Camera*) currentCamera
//{
//	if( fabs( currentCamera.position.x - camera.position.x) > 0.1) return YES;
//	if( fabs( currentCamera.position.y - camera.position.y) > 0.1) return YES;
//	if( fabs( currentCamera.position.z - camera.position.z) > 0.1) return YES;
//
//	if( fabs( currentCamera.focalPoint.x - camera.focalPoint.x) > 0.1) return YES;
//	if( fabs( currentCamera.focalPoint.y - camera.focalPoint.y) > 0.1) return YES;
//	if( fabs( currentCamera.focalPoint.z - camera.focalPoint.z) > 0.1) return YES;
//
//	if( fabs( currentCamera.viewUp.x - camera.viewUp.x) > 0.1) return YES;
//	if( fabs( currentCamera.viewUp.y - camera.viewUp.y) > 0.1) return YES;
//	if( fabs( currentCamera.viewUp.z - camera.viewUp.z) > 0.1) return YES;
//
//	if( fabs( currentCamera.viewAngle - camera.viewAngle) > 3) return YES;
//	if( fabs( currentCamera.eyeAngle - camera.eyeAngle) > 3) return YES;
//	
//	return NO;
//
//}

- (float) displayedScaleValue
{
    DCMPix *o = [windowController originalPix];
    
    return [o pixelSpacingX] / previousResolution;
}

- (float) displayedRotation
{
    return camera.rollAngle;
}

- (BOOL) hasCameraChanged: (Camera*) currentCamera
{
	if( camera.forceUpdate)
	{
		camera.forceUpdate = NO;
		return YES;
	}
	
	#define PRECISION 0.0001
	
	if( fabs( currentCamera.position.x - camera.position.x) > PRECISION) return YES;
	if( fabs( currentCamera.position.y - camera.position.y) > PRECISION) return YES;
	if( fabs( currentCamera.position.z - camera.position.z) > PRECISION) return YES;

	if( fabs( currentCamera.focalPoint.x - camera.focalPoint.x) > PRECISION) return YES;
	if( fabs( currentCamera.focalPoint.y - camera.focalPoint.y) > PRECISION) return YES;
	if( fabs( currentCamera.focalPoint.z - camera.focalPoint.z) > PRECISION) return YES;

	if( fabs( currentCamera.viewUp.x - camera.viewUp.x) > PRECISION) return YES;
	if( fabs( currentCamera.viewUp.y - camera.viewUp.y) > PRECISION) return YES;
	if( fabs( currentCamera.viewUp.z - camera.viewUp.z) > PRECISION) return YES;

	if( fabs( currentCamera.viewAngle - camera.viewAngle) > PRECISION) return YES;
	if( fabs( currentCamera.eyeAngle - camera.eyeAngle) > PRECISION) return YES;
	if( fabs( currentCamera.parallelScale - camera.parallelScale) > PRECISION) return YES;

	if( currentCamera.clippingRangeNear != camera.clippingRangeNear) return YES;
	if( currentCamera.clippingRangeFar != camera.clippingRangeFar) return YES;
	
//	if( currentCamera.LOD < camera.LOD) return YES;
	
	if( currentCamera.wl != camera.wl) return YES;
	if( currentCamera.ww != camera.ww) return YES;
	
	return NO;
}

- (void) restoreCamera
{
	return [self restoreCameraAndCheckForFrame: YES];
}

- (void) restoreCameraAndCheckForFrame: (BOOL) v
{
	if( v)
		[self checkForFrame];
	// SekhVet Paket BK: die Kamera traegt eine eigene Fensterung, und VRView setCamera: wendet sie an (ww > 1). Ist sie
	// veraltet (Kamera vom gemeinsamen vrView, Fensterung des 2D-Viewers), springt die sichtbare Fensterung beim
	// Doppelklick-Zoom oder Double-MPR-Mitlauf (Weichteil -> Knochen, 0/2; macOS-27-VM 17.09.2026). Die Fensterung
	// des angezeigten Schnittbilds ist die Wahrheit.
	if( camera && self.curDCM && self.curDCM.ww > 1)
		[camera setWLWW: self.curDCM.wl : self.curDCM.ww];
	[vrView setCamera: camera];
}

- (void) dealloc
{
//	[vrView restoreFullDepthCapture];
	[camera release];
	
	[super dealloc];
}

- (IBAction) actualSize:(id)sender
{
	[self setOriginX: 0 Y: 0];
	self.rotation = 0.0f;
    
    DCMPix *o = [windowController originalPix];
    
    camera.forceUpdate = YES;
	camera.parallelScale *= [o pixelSpacingX] / previousResolution;
	
    [self restoreCamera];
	[self updateViewMPR];
}

- (IBAction) realSize:(id)sender
{
    CGSize f = CGDisplayScreenSize( [[[[[self window] screen] deviceDescription] valueForKey: @"NSScreenNumber"] intValue]);
    CGRect r = CGDisplayBounds( [[[[[self window] screen] deviceDescription] valueForKey: @"NSScreenNumber"] intValue]); 
    
    if( f.width != 0 && f.height != 0)
    {
        NSLog( @"screen pixel ratio: %f", fabs( (f.width/r.size.width) - (f.height/r.size.height)));
        if( fabs( (f.width/r.size.width) - (f.height/r.size.height)) < 0.01)
        {
//            DCMPix *o = [windowController originalPix];
            
            camera.forceUpdate = YES;
            camera.parallelScale *= (f.width/r.size.width) / previousResolution;
            
            [self restoreCamera];
            [self updateViewMPR];
        }
        else
            NSRunCriticalAlertPanel(NSLocalizedString(@"Actual Size Error",nil), NSLocalizedString(@"Displayed pixels are non-squared pixel. Images cannot be displayed at actual size.",nil) , NSLocalizedString( @"OK",nil), nil, nil);
    }
    else
        NSRunCriticalAlertPanel(NSLocalizedString(@"Actual Size Error",nil), NSLocalizedString(@"This screen doesn't support this function.",nil) , NSLocalizedString( @"OK",nil), nil, nil);
}


- (BOOL)validateMenuItem:(NSMenuItem *)item
{
    if( [item action] == @selector(scaleToFit:))
    {
        return NO;
    }
    
    return YES;
}


- (void) updateViewMPROnLoading:(BOOL) isLoading :(BOOL) computeCrossReferenceLines
{
    if( [self frame].size.width < SEKHMET_MIN_VIEW)
        return;
    
    if( [self frame].size.height < SEKHMET_MIN_VIEW)
        return;
    
    // SekhVet Paket AV: zweiter Riegel — der vrView ist EIN gemeinsamer VTK-Blick fuer alle drei
    // Ansichten und traegt waehrend eines Teilerwechsels kurz die Groesse einer zusammengeklappten
    // Ansicht. Ein Renderziel ohne Flaeche liefert ein schwarzes oder weisses Bild; wir lassen den
    // Durchgang aus, die 0,1-s-Nachzuegler-Aktualisierung (setFrame:) holt ihn nach.
    if( [vrView frame].size.width < SEKHMET_MIN_VIEW || [vrView frame].size.height < SEKHMET_MIN_VIEW)
        return;
    
    long h, w;
    float previousWW, previousWL;
    BOOL isRGB;
    BOOL previousOriginInPlane = NO;
    
    [self getWLWW: &previousWL :&previousWW];
    
    Camera *currentCamera = [vrView cameraWithThumbnail: NO];
    
    minimumStep = 1;
    
    if( [self hasCameraChanged: currentCamera] == YES)
    {
        // AutoLOD
        if( dontUseAutoLOD == NO && lastRenderingWasMoveCenter == NO)
        {
            DCMPix *o = [windowController originalPix];
            
            float minimumResolution = [o pixelSpacingX];
            
            if( minimumResolution > [o pixelSpacingY])
                minimumResolution = [o pixelSpacingY];
            
            if( minimumResolution > [o sliceInterval])
                minimumResolution = [o sliceInterval];
            
            if( windowController.clippingRangeThickness <= 3)
                minimumResolution *= 0.9;
            else
                minimumResolution *= 0.7;
            
            if( minimumResolution > previousPixelSpacing && previousPixelSpacing != 0)
                LOD *= ( minimumResolution / previousPixelSpacing);
            
            if( previousResolution == 0)
                previousResolution = [vrView getResolution];
            
            float currentResolution = [vrView getResolution];
            
            if( previousResolution < currentResolution)
                LOD *= (previousResolution / currentResolution);
            
            if( LOD < windowController.LOD)
                LOD = windowController.LOD;
            
            if( LOD > 4) LOD = 4;
            
            if( windowController.lowLOD)
                [vrView setLOD: LOD * vrView.lowResLODFactor];
            else
                [vrView setLOD: LOD];
        }
        else
            [vrView setLOD: LOD];
        
        if( [self frame].size.width >= SEKHMET_MIN_VIEW && [self frame].size.height >= SEKHMET_MIN_VIEW)
        {
            if( windowController.maxMovieIndex > 1 && (windowController.clippingRangeMode == 1 || windowController.clippingRangeMode == 3 || windowController.clippingRangeMode == 2))	//To avoid the wrong pixel value bug...
                [vrView prepareFullDepthCapture];
            
            if( moveCenter)
            {
                lastRenderingWasMoveCenter = YES;
                [vrView setLOD: 100];	// We dont need to really compute the image - we just want image origin for the other views.
            }
            else lastRenderingWasMoveCenter = NO;
            
            if (isLoading == NO)
                [vrView render];
        }
        
        float *imagePtr = nil;
        
        if( moveCenter)
        {
            imagePtr = [pix fImage];
            w = [pix pwidth];
            h = [pix pheight];
            isRGB = [pix isRGB];
            
            [vrView setLOD: LOD];
        }
        else
            imagePtr = [vrView imageInFullDepthWidth: &w height: &h isRGB: &isRGB];
        
        ////
        float orientation[ 9];
        [vrView getOrientation: orientation];
        
        float location[ 3] = {previousOrigin[ 0], previousOrigin[ 1], previousOrigin[ 2]}, orig[ 3] = {currentCamera.position.x, currentCamera.position.y, currentCamera.position.z}, locationTemp[ 3];
        float distance = [DCMView pbase_Plane: location :orig :&(orientation[ 6]) :locationTemp];
        if( distance < pix.sliceThickness / 2.)
            previousOriginInPlane = YES;
        else
            previousOriginInPlane = NO;
        
        [self saveCamera];
        
        if( imagePtr)
        {
            BOOL cameraMoved = YES;
            
            if( [curRoiList count] > 0)
            {
                if( previousOriginInPlane == NO || arePlanesParallel( orientation+6, previousOrientation+6) == NO)
                    cameraMoved = YES;
                else
                    cameraMoved = NO;
                
                if( cameraMoved == YES)
                {
                    for( int i = (long)[curRoiList count] -1 ; i >= 0; i--)
                    {
                        ROI *r = [curRoiList objectAtIndex: i];
                        if( [r type] != t2DPoint)
                            [curRoiList removeObjectAtIndex: i];
                    }
                }
            }
            
            if( [pix pwidth] == w && [pix pheight] == h && isRGB == [pix isRGB])
            {
                if( imagePtr != [pix fImage])
                {
                    memcpy( [pix fImage], imagePtr, w*h*sizeof( float));
                    free( imagePtr);
                }
            }
            else
            {
                [pix setRGB: isRGB];
                [pix setfImage: imagePtr];
                [pix freefImageWhenDone: YES];
                [pix setPwidth: w];
                [pix setPheight: h];
                
                NSMutableArray *savedROIs = [[curRoiList copy] autorelease];
                
                [self setIndex: 0];
                
                [curRoiList addObjectsFromArray: savedROIs];
            }
            float porigin[ 3];
            [vrView getOrigin: porigin windowCentered: YES sliceMiddle: YES];
            [pix setOrigin: porigin];
            
            float resolution = 0;
            if( !moveCenter)
            {
                resolution = [vrView getResolution] * [vrView imageSampleDistance];
                if( resolution > 0)
                {
                    [pix setPixelSpacingX: resolution];
                    [pix setPixelSpacingY: resolution];
                }
            }
            
            [pix setOrientation: orientation];
            [pix setSliceThickness: [vrView getClippingRangeThicknessInMm]];
            [windowController sekhmetApplyConvolutionToPix: pix]; // Sekhmet: Faltung auf das Schnittbild
            
            // SekhVet Paket BF: Diagnose fuer "Bild tiefschwarz / alles weiss" — ein Schnittbild aus lauter gleichen Werten
            // ist nie ein echtes Bild. Einmal je Vorfall ins Protokoll (Konsole / log show, Prozess Horos).
            {
                float *f = [pix fImage];
                long n = (long) w * h;
                if( f && n > 64)
                {
                    BOOL uniform = YES;
                    float v0 = f[ 0];
                    for( int k = 1; k < 64 && uniform; k++)
                        if( f[ (n - 1) * k / 63] != v0) uniform = NO;
                    if( uniform)
                        NSLog( @"SekhVet MPR: uniform slice image (value %.1f, %ldx%ld) in view %d, frame %.0fx%.0f, vrView %.0fx%.0f, WL/WW %.0f/%.0f, LOD %.2f, zoomed %d", v0, w, h, viewID, [self frame].size.width, [self frame].size.height, [vrView frame].size.width, [vrView frame].size.height, previousWL, previousWW, LOD, (int) windowController.sekhmetFrameZoomed);
                }
            }
            
            [self setWLWW: previousWL :previousWW];
            
            if( !moveCenter)
            {
                [self setScaleValue: [vrView imageSampleDistance]];
                
                float rotationPlane = 0;
                if( cameraMoved == NO && [curRoiList count] > 0)
                {
                    if( previousOrientation[ 0] != 0 || previousOrientation[ 1] != 0 || previousOrientation[ 2] != 0)
                        rotationPlane = -[MPRController angleBetweenVector: orientation andPlane: previousOrientation];
                    if( fabs( rotationPlane) < 0.01)
                        rotationPlane = 0;
                }
                
                NSPoint rotationCenter = NSMakePoint( [pix pwidth]/2., [pix pheight]/2.);
                
                for( ROI* r in curRoiList)
                {
                    if( rotationPlane)
                    {
                        [r setOriginAndSpacing: resolution : resolution : r.imageOrigin :NO];
                        
                        [r rotate: rotationPlane :rotationCenter];
                        r.imageOrigin = [DCMPix originCorrectedAccordingToOrientation: pix];
                        r.pixelSpacingX = [pix pixelSpacingX];
                        r.pixelSpacingY = [pix pixelSpacingY];
                    }
                    else
                        [r setOriginAndSpacing: resolution : resolution :[DCMPix originCorrectedAccordingToOrientation: pix] :NO];
                }
                
                [pix orientation: previousOrientation];
                previousOrigin[ 0] = currentCamera.position.x;
                previousOrigin[ 1] = currentCamera.position.y;
                previousOrigin[ 2] = currentCamera.position.z;
                
                [self detect2DPointInThisSlice];
                
                previousResolution = [vrView getResolution];
                previousPixelSpacing = [pix pixelSpacingX];
            }
        }
        
        if( blendingView)
        {
            [blendingView getWLWW: &previousWL :&previousWW];
            
            [vrView renderBlendedVolume];
            
            float *blendedImagePtr = nil;
            DCMPix *bPix = blendingView.curDCM;
            
            if( moveCenter)
            {
                blendedImagePtr = [bPix fImage];
                w = [bPix pwidth];
                h = [bPix pheight];
                isRGB = [bPix isRGB];
            }
            else
                blendedImagePtr = [vrView imageInFullDepthWidth: &w height: &h isRGB: &isRGB blendingView: YES];
            
            if( [bPix pwidth] == w && [bPix pheight] == h && isRGB == [bPix isRGB])
            {
                if( blendedImagePtr != [bPix fImage])
                {
                    memcpy( [bPix fImage], blendedImagePtr, w*h*sizeof( float));
                    free( blendedImagePtr);
                }
            }
            else
            {
                [bPix setRGB: isRGB];
                [bPix setfImage: blendedImagePtr];
                [bPix setPwidth: w];
                [bPix setPheight: h];
                
                [blendingView setIndex: 0];
            }
            float porigin[ 3];
            [vrView getOrigin: porigin windowCentered: YES sliceMiddle: YES blendedView: YES];
            [bPix setOrigin: porigin];
            
            if( !moveCenter)
            {
                float resolution = [vrView getResolution] * [vrView blendingImageSampleDistance];
                [bPix setPixelSpacingX: resolution];
                [bPix setPixelSpacingY: resolution];
            }
            
            float orientation[ 9];
            [vrView getOrientation: orientation];
            [bPix setOrientation: orientation];
            [windowController sekhmetApplyConvolutionToPix: bPix]; // Sekhmet
            [bPix setSliceThickness: [vrView getClippingRangeThicknessInMm]];
            
            [blendingView setWLWW: previousWL :previousWW];
            
            if( !moveCenter)
                [blendingView setScaleValue: [vrView blendingImageSampleDistance]];
        }
    }
    
    if( dontReenterCrossReferenceLines == NO)
    {
        dontReenterCrossReferenceLines = YES;
        
        if( computeCrossReferenceLines)
            [windowController computeCrossReferenceLines: self];
        else
            [windowController computeCrossReferenceLines: nil];
        
        dontReenterCrossReferenceLines = NO;
    }
    
    if( isLoading == NO) [windowController sekhmetScheduleSyncBroadcast]; // Sekhmet: Double MPR
    
    [self setNeedsDisplay: YES];
}

- (void) updateViewMPROnLoading:(BOOL) isLoading
{
    [self updateViewMPROnLoading:isLoading :YES];
}

- (void) updateViewMPR:(BOOL) computeCrossReferenceLines
{
    [self updateViewMPROnLoading:NO :computeCrossReferenceLines];
}

-(void) updateViewMPR
{
    [self updateViewMPR:YES];
}

- (void) colorForView:(int) v
{
	CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
	switch( v)
	{
		case 1:
			//glColor4f (VIEW_1_RED, VIEW_1_GREEN, VIEW_1_BLUE, VIEW_1_ALPHA);
			glColor4f ([windowController.colorAxis1 redComponent], [windowController.colorAxis1 greenComponent], [windowController.colorAxis1 blueComponent], [windowController.colorAxis1 alphaComponent]);
		break;
		
		case 2:
			//glColor4f (VIEW_2_RED, VIEW_2_GREEN, VIEW_2_BLUE, VIEW_2_ALPHA);
			glColor4f ([windowController.colorAxis2 redComponent], [windowController.colorAxis2 greenComponent], [windowController.colorAxis2 blueComponent], [windowController.colorAxis2 alphaComponent]);
		break;
		
		case 3:
			//glColor4f (VIEW_3_RED, VIEW_3_GREEN, VIEW_3_BLUE, VIEW_3_ALPHA);
			glColor4f ([windowController.colorAxis3 redComponent], [windowController.colorAxis3 greenComponent], [windowController.colorAxis3 blueComponent], [windowController.colorAxis3 alphaComponent]);
		break;
	}
}

- (void) drawLine: (float[2][3]) sft thickness: (float) thickness
{
	CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
	if( thickness > 2)
	{
		glLineWidth(2.0 * self.window.backingScaleFactor);
		[self drawCrossLines: sft ctx: cgl_ctx withShift: 0];
		
		glLineWidth(1.0 * self.window.backingScaleFactor);
		[self drawCrossLines: sft ctx: cgl_ctx withShift: -thickness/2.];
		[self drawCrossLines: sft ctx: cgl_ctx withShift: thickness/2.];
	}
	else
	{
		glLineWidth(2.0 * self.window.backingScaleFactor);
		[self drawCrossLines: sft ctx: cgl_ctx withShift: 0];
	}
}

- (void) drawExportLines: (float[2][3]) sft
{
	CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
	glLineWidth(1.0 * self.window.backingScaleFactor);
						
	if( fromIntervalExport > 0)
	{
		for( int i = 1; i <= fromIntervalExport; i++)
			[self drawCrossLines: sft ctx: cgl_ctx withShift: -i * [windowController dcmInterval]];
	}
	
	if( !windowController.dcmBatchReverse)
		[self drawCrossLines: sft ctx: cgl_ctx withShift: -fromIntervalExport * [windowController dcmInterval] showPoint: YES];
	
	if( toIntervalExport > 0)
	{
		for( int i = 1; i <= toIntervalExport; i++)
			[self drawCrossLines: sft ctx: cgl_ctx withShift: i * [windowController dcmInterval]];
	}
	
	if( windowController.dcmBatchReverse)
		[self drawCrossLines: sft ctx: cgl_ctx withShift: toIntervalExport * [windowController dcmInterval] showPoint: YES];
}

- (void) drawRotationLines: (float[2][3]) sft
{
	CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
	for( int i = 1; i < windowController.dcmNumberOfFrames; i++)
	{
		glRotatef( (float) (i * windowController.dcmRotation) / (float) windowController.dcmNumberOfFrames, 0, 0, 1);
		[self drawCrossLines: sft ctx: cgl_ctx perpendicular: NO withShift: 0 half: YES];
		glRotatef( -(float) (i * windowController.dcmRotation) / (float) windowController.dcmNumberOfFrames, 0, 0, 1);
	}
}

- (void) drawTextualData:(NSRect) size :(long) annotations
{
	float copyScale = scaleValue;
	scaleValue = 1;
	[super drawTextualData: size :annotations];
	scaleValue = copyScale;
}

// SekhVet Paket AB: Nach dem Schliessen des MPR-Fensters (z.B. closeAllViewers bei Bildschirmwechsel nach dem Aufwachen)
// zeichnet die OpenGL-Ebene der Ansicht noch einen CoreAnimation-Commit lang weiter, der MPRController ist da schon
// freigegeben -> objc_msgSend auf windowController in subDrawRect (Horos #753/#758). Abkoppeln und nichts mehr zeichnen.
- (void) sekhmetDetachFromController
{
    sekhmetDetached = YES;
    windowController = nil;
    vrView = nil;
}

- (void) drawRect:(NSRect) r
{
    if( sekhmetDetached) return;
    // SekhVet Paket BK (macOS 27): eine Ansicht ohne Flaeche (Doppelklick-Zoom) nie zeichnen — das layer-backed
    // NSOpenGLView ruft drawRect: trotzdem, und flushBuffer bricht dann in CABackingStoreEndUpdate ab.
    if( [self frame].size.width < SEKHMET_MIN_VIEW || [self frame].size.height < SEKHMET_MIN_VIEW) return;
    [super drawRect: r];
}

- (void) subDrawRect: (NSRect) r
{
    if( sekhmetDetached || windowController == nil) return; // SekhVet Paket AB

	if( [stringID isEqualToString: @"export"] && [[NSUserDefaults standardUserDefaults] boolForKey: @"exportDCMIncludeAllViews"] == NO)
		return;
	
	rotation = 0;
	
	CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
	glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA );
	glEnable(GL_BLEND);
	glEnable(GL_POINT_SMOOTH);
	glEnable(GL_LINE_SMOOTH);
	glPointSize( 12 * self.window.backingScaleFactor);
	
	if( displayCrossLines && windowController.sekhmetFrameZoomed == NO)
	{
		// All pix have the same thickness
		float thickness = [pix sliceThickness];
		
		switch( viewID)
		{
			case 1:
				glColor4f ([windowController.colorAxis2 redComponent], [windowController.colorAxis2 greenComponent], [windowController.colorAxis2 blueComponent], [windowController.colorAxis2 alphaComponent]);
				if( crossLinesA[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesA thickness: thickness];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesA];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesA];
				}
				glColor4f ([windowController.colorAxis3 redComponent], [windowController.colorAxis3 greenComponent], [windowController.colorAxis3 blueComponent], [windowController.colorAxis3 alphaComponent]);
				if( crossLinesB[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesB thickness: thickness];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesB];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesB];
				}
			break;
			
			case 2:
				glColor4f ([windowController.colorAxis1 redComponent], [windowController.colorAxis1 greenComponent], [windowController.colorAxis1 blueComponent], [windowController.colorAxis1 alphaComponent]);
				if( crossLinesA[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesA thickness: thickness];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesA];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesA];
				}
				
				glColor4f ([windowController.colorAxis3 redComponent], [windowController.colorAxis3 greenComponent], [windowController.colorAxis3 blueComponent], [windowController.colorAxis3 alphaComponent]);
				if( crossLinesB[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesB thickness: thickness];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesB];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesB];
				}
			break;
			
			case 3:
				glColor4f ([windowController.colorAxis1 redComponent], [windowController.colorAxis1 greenComponent], [windowController.colorAxis1 blueComponent], [windowController.colorAxis1 alphaComponent]);
				if( crossLinesA[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesA thickness: thickness];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesA];
					
					if( viewExport == 0 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesA];
				}
				
				glColor4f ([windowController.colorAxis2 redComponent], [windowController.colorAxis2 greenComponent], [windowController.colorAxis2 blueComponent], [windowController.colorAxis2 alphaComponent]);
				if( crossLinesB[ 0][ 0] != HUGE_VALF)
				{
					[self drawLine: crossLinesB thickness: thickness];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 0)
						[self drawExportLines: crossLinesB];
					
					if( viewExport == 1 && windowController.dcmMode == 0 && windowController.dcmSeriesMode == 1) // Rotation
						[self drawRotationLines: crossLinesB];
				}
			break;
		}
	}
	
	if( [stringID isEqualToString: @"export"])
		return;
	
	float heighthalf = [self convertSizeToBacking: self.frame.size].height/2;
	float widthhalf = [self convertSizeToBacking: self.frame.size].width/2;
	
	[self colorForView: viewID];
	
	// Red Square
	if( [[self window] firstResponder] == self && windowController.sekhmetFrameZoomed == NO)
	{
		glLineWidth(8.0 * self.window.backingScaleFactor);
		glBegin(GL_LINE_LOOP);
			glVertex2f(  -widthhalf, -heighthalf);
			glVertex2f(  -widthhalf, heighthalf);
			glVertex2f(  widthhalf, heighthalf);
			glVertex2f(  widthhalf, -heighthalf);
		glEnd();
	}
	
	glLineWidth(2.0 * self.window.backingScaleFactor);
	glBegin(GL_POLYGON);
		glVertex2f(widthhalf-VIEW_COLOR_LABEL_SIZE, -heighthalf+VIEW_COLOR_LABEL_SIZE);
		glVertex2f(widthhalf-VIEW_COLOR_LABEL_SIZE, -heighthalf);
		glVertex2f(widthhalf, -heighthalf);
		glVertex2f(widthhalf, -heighthalf+VIEW_COLOR_LABEL_SIZE);
	glEnd();
	glLineWidth(1.0 * self.window.backingScaleFactor);
	
	if( displayCrossLines && windowController.sekhmetFrameZoomed == NO && windowController.displayMousePosition && !windowController.mprView1.rotateLines && !windowController.mprView2.rotateLines && !windowController.mprView3.rotateLines
																					&& !windowController.mprView1.moveCenter && !windowController.mprView2.moveCenter && !windowController.mprView3.moveCenter)
	{
		// Mouse Position
		if( viewID == windowController.mouseViewID)
		{
			DCMPix *pixA, *pixB;
			int viewIDA, viewIDB;
			
			switch (viewID)
			{	
				case 1:
					pixA = [windowController.mprView2 pix];
					pixB = [windowController.mprView3 pix];
					viewIDA = 2;
					viewIDB = 3;
					break;
				case 2:
					pixA = [windowController.mprView1 pix];
					pixB = [windowController.mprView3 pix];
					viewIDA = 1;
					viewIDB = 3;					
					break;
				case 3:
					pixA = [windowController.mprView1 pix];
					pixB = [windowController.mprView2 pix];
					viewIDA = 1;
					viewIDB = 2;
					break;		
			}
			
			[self colorForView:viewIDA];
			Point3D *pt = windowController.mousePosition;
			float sc[ 3], dc[ 3] = { pt.x, pt.y, pt.z}, location[ 3];
			[pixA convertDICOMCoords: dc toSliceCoords: sc pixelCenter: YES];
			sc[0] = sc[ 0] / pixA.pixelSpacingX;
			sc[1] = sc[ 1] / pixA.pixelSpacingY;
			[pixA convertPixX:sc[0] pixY:sc[1] toDICOMCoords:location pixelCenter:YES];
			[pix convertDICOMCoords:location toSliceCoords:sc pixelCenter:YES];
			
			glPointSize( 10 * self.window.backingScaleFactor);
			glBegin( GL_POINTS);
			sc[0] = sc[ 0] / self.curDCM.pixelSpacingX;
			sc[1] = sc[ 1] / self.curDCM.pixelSpacingY;
			sc[0] -= self.curDCM.pwidth * 0.5f;
			sc[1] -= self.curDCM.pheight * 0.5f;
			glVertex2f( scaleValue*sc[ 0], scaleValue*sc[ 1]);
			glEnd();

			
			[self colorForView:viewIDB];
			pt = windowController.mousePosition;
			dc[0] = pt.x; dc[1] = pt.y; dc[2] = pt.z;
			[pixB convertDICOMCoords: dc toSliceCoords: sc pixelCenter: YES];
			sc[0] = sc[ 0] / pixB.pixelSpacingX;
			sc[1] = sc[ 1] / pixB.pixelSpacingY;
			[pixB convertPixX:sc[0] pixY:sc[1] toDICOMCoords:location pixelCenter:YES];
			[pix convertDICOMCoords:location toSliceCoords:sc pixelCenter:YES];
			
			glPointSize( 10 * self.window.backingScaleFactor);
			glBegin( GL_POINTS);
			sc[0] = sc[ 0] / self.curDCM.pixelSpacingX;
			sc[1] = sc[ 1] / self.curDCM.pixelSpacingY;
			sc[0] -= self.curDCM.pwidth * 0.5f;
			sc[1] -= self.curDCM.pheight * 0.5f;
			glVertex2f( scaleValue*sc[ 0], scaleValue*sc[ 1]);
			glEnd();

		}
		if( viewID != windowController.mouseViewID)
		{
			[self colorForView: viewID];
//			[self colorForView: windowController.mouseViewID];
			Point3D *pt = windowController.mousePosition;
			float sc[ 3], dc[ 3] = { pt.x, pt.y, pt.z};
			
			[pix convertDICOMCoords: dc toSliceCoords: sc pixelCenter: YES];
			
			glPointSize( 10 * self.window.backingScaleFactor);
			glBegin( GL_POINTS);
			sc[0] = sc[ 0] / self.curDCM.pixelSpacingX;
			sc[1] = sc[ 1] / self.curDCM.pixelSpacingY;
			sc[0] -= self.curDCM.pwidth * 0.5f;
			sc[1] -= self.curDCM.pheight * 0.5f;
			glVertex2f( scaleValue*sc[ 0], scaleValue*sc[ 1]);
			glEnd();
		}
	}
    
    [self drawOSIROIs];
	
	glDisable(GL_LINE_SMOOTH);
	glDisable(GL_POLYGON_SMOOTH);
	glDisable(GL_POINT_SMOOTH);
	glDisable(GL_BLEND);
}

- (void) setCrossReferenceLines: (float[2][3]) a and: (float[2][3]) b
{	
	crossLinesA[ 0][ 0] = a[ 0][ 0];
	crossLinesA[ 0][ 1] = a[ 0][ 1];
	crossLinesA[ 0][ 2] = a[ 0][ 2];
	crossLinesA[ 1][ 0] = a[ 1][ 0];
	crossLinesA[ 1][ 1] = a[ 1][ 1];
	crossLinesA[ 1][ 2] = a[ 1][ 2];
	
	crossLinesB[ 0][ 0] = b[ 0][ 0];
	crossLinesB[ 0][ 1] = b[ 0][ 1];
	crossLinesB[ 0][ 2] = b[ 0][ 2];
	crossLinesB[ 1][ 0] = b[ 1][ 0];
	crossLinesB[ 1][ 1] = b[ 1][ 1];
	crossLinesB[ 1][ 2] = b[ 1][ 2];
}

-(void) setCurrentTool:(ToolMode) i
{
	if( i != tRepulsor)
		[super setCurrentTool: i];
}

- (void)keyDown:(NSEvent *)theEvent
{
    if( [[theEvent characters] length] == 0) return;
    
    unichar c = [[theEvent characters] characterAtIndex:0];
    
	if( c ==  ' ' || c == 27) // 27 : escape
	{
		[windowController keyDown:theEvent];
	}
    else if( c == NSUpArrowFunctionKey || c == NSDownArrowFunctionKey || c == NSRightArrowFunctionKey || c ==  NSLeftArrowFunctionKey)
    {
        moveCenter = YES;
        
        [self restoreCamera];
        
        NSPoint center = NSMakePoint( [self frame].size.width/2., [self frame].size.height/2.);
        
        NSPoint b1 = NSMakePoint( crossLinesA[ 0][ 0], crossLinesA[ 0][ 1]);
        NSPoint b2 = NSMakePoint( crossLinesA[ 1][ 0], crossLinesA[ 1][ 1]);
        
        NSPoint vector = NSMakePoint( b2.x-b1.x, b2.y-b1.y);
        
        float length = sqrt( (vector.x * vector.x) + (vector.y * vector.y));
        
        float slopeX = vector.x / length;
        float slopeY = vector.y / length;
        
        if( xFlipped)
        {
            if( c == NSLeftArrowFunctionKey)
                c = NSRightArrowFunctionKey;
            
            if( c == NSRightArrowFunctionKey)
                c = NSLeftArrowFunctionKey;
        }
        
        if( yFlipped)
        {
            if( c == NSUpArrowFunctionKey)
                c = NSDownArrowFunctionKey;
            
            if( c == NSDownArrowFunctionKey)
                c = NSUpArrowFunctionKey;
        }
        
        if( c == NSDownArrowFunctionKey || c == NSUpArrowFunctionKey)
        {
            if( fabs( slopeY) < fabs( slopeX))
            {
                float c = slopeY;
                slopeY = -slopeX;
                slopeX = c;
            }
            
            if( slopeY < 0)
            {
                slopeY = -slopeY;
                slopeX = -slopeX;
            }
        }
        else
        {
            if( fabs( slopeX) < fabs( slopeY))
            {
                float c = slopeY;
                slopeY = -slopeX;
                slopeX = c;
            }
            
            if( slopeX < 0)
            {
                slopeY = -slopeY;
                slopeX = -slopeX;
            }
        }
        
        float move = 2;
        
        if( [theEvent modifierFlags] & NSAlternateKeyMask) move = 6;
        if( [theEvent modifierFlags] & NSCommandKeyMask) move = 1;
        
        if( c == NSDownArrowFunctionKey) { center.y -= move*slopeY; center.x += move*slopeX;}
        if( c == NSUpArrowFunctionKey) { center.y += move*slopeY; center.x -= move*slopeX;}
        
        if( c == NSRightArrowFunctionKey) { center.y -= move*slopeY; center.x += move*slopeX;}
        if( c == NSLeftArrowFunctionKey) { center.y += move*slopeY; center.x -= move*slopeX;}
        
        [vrView setWindowCenter: center];
        [self updateViewMPR];
        
        moveCenter = NO;
        camera.windowCenterX = 0;
        camera.windowCenterY = 0;
        camera.forceUpdate = YES;
        [self restoreCamera];
		[self updateViewMPR];
        
        moveCenter = NO;
    }
	else
	{
        float scale = self.scaleValue;
        
		[super keyDown: theEvent];
		
        self.scaleValue = scale;
        
		[windowController propagateWLWW: self];
	}
}

- (N3AffineTransform)pixToDicomTransform // converts points in the DCMPix's coordinate space ("Slice Coordinates") into the DICOM space (patient space with mm units)
{
    N3AffineTransform pixToDicomTransform;
    double spacingX;
    double spacingY;
    //    double spacingZ;
    double orientation[9];
    
    memset(orientation, 0, sizeof(double) * 9);
    [pix orientationDouble:orientation];
    spacingX = pix.pixelSpacingX;
    spacingY = pix.pixelSpacingY;
    //    spacingZ = pix.sliceInterval;
    
    pixToDicomTransform = N3AffineTransformIdentity;
    pixToDicomTransform.m41 = pix.originX;
    pixToDicomTransform.m42 = pix.originY;
    pixToDicomTransform.m43 = pix.originZ;
    pixToDicomTransform.m11 = orientation[0]*spacingX;
    pixToDicomTransform.m12 = orientation[1]*spacingX;
    pixToDicomTransform.m13 = orientation[2]*spacingX;
    pixToDicomTransform.m21 = orientation[3]*spacingY;
    pixToDicomTransform.m22 = orientation[4]*spacingY;
    pixToDicomTransform.m23 = orientation[5]*spacingY;
    pixToDicomTransform.m31 = orientation[6];
    pixToDicomTransform.m32 = orientation[7];
    pixToDicomTransform.m33 = orientation[8];
    
#ifndef NDEBUG
	if( isnan( pix.pixelSpacingX) || isnan( pix.pixelSpacingY) || pix.pixelSpacingX <= 0 || pix.pixelSpacingY <= 0 || pix.pixelSpacingX > 1000 || pix.pixelSpacingY > 1000)
		NSLog( @"******* CPR pixel spacing incorrect for pixToSubDrawRectTransform");
#endif
	
    return pixToDicomTransform;
}


#pragma mark-
#pragma mark 3D ROI Point	

- (void) detect2DPointInThisSlice
{
	ViewerController *viewer2D = [windowController viewer];
	
	if (viewer2D)
	{
		// First delete all 2D Points in our pix
		
		NSMutableDictionary *ROIsStateSaved = [NSMutableDictionary dictionary];
		
		for( int i = (long)[curRoiList count] -1 ; i >= 0; i--)
		{
			ROI *r = [curRoiList objectAtIndex: i];
			if( [r type] == t2DPoint)
			{
				if( r.parentROI)
					[ROIsStateSaved setObject: [NSNumber numberWithInt: [r ROImode]] forKey: [NSValue valueWithPointer: r.parentROI]];
				[curRoiList removeObjectAtIndex: i];
			}
		}
		
		NSArray *roiList = [viewer2D roiList: [windowController curMovieIndex]];
		NSArray *pixList = [viewer2D pixList: [windowController curMovieIndex]];
		
		for( int i = 0; i < [roiList count]; i++)
		{
			NSArray *pts = [roiList objectAtIndex: i];
			DCMPix *p = [pixList objectAtIndex: i];
			
			for( ROI *r in pts)
			{
				if( [r type] == t2DPoint)
				{
					float location[ 3];
					
					[p convertPixX: r.rect.origin.x pixY: r.rect.origin.y toDICOMCoords: location pixelCenter: YES];
					
					// Is this point in our plane?
					
					float	vectors[ 9], orig[ 3], locationTemp[ 3];
					float	distance = 999999;
					
					orig[ 0] = [pix originX];
					orig[ 1] = [pix originY];
					orig[ 2] = [pix originZ];
					
					[pix orientation: vectors];
					
					distance = [DCMView pbase_Plane: location :orig :&(vectors[ 6]) :locationTemp];
					
					if( distance < pix.sliceThickness)
					{
						float sc[ 3];
						
						[pix convertDICOMCoords: location toSliceCoords: sc pixelCenter: YES];
						
						sc[ 0] = sc[ 0] / pix.pixelSpacingX;
						sc[ 1] = sc[ 1] / pix.pixelSpacingY;
						
						ROI *new2DPointROI = [[ROI alloc] initWithType: t2DPoint :pix.pixelSpacingX :pix.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pix]];
						
						[new2DPointROI setROIRect: NSMakeRect( sc[ 0], sc[ 1], 0, 0)];
						
						[new2DPointROI setParentROI: r];
						[new2DPointROI setName: r.name]; // Sekhmet: Label in allen MPR-Ebenen zeigen
						[self roiSet: new2DPointROI];
						[curRoiList addObject: new2DPointROI];
						
						int mode = [[ROIsStateSaved objectForKey: [NSValue valueWithPointer: r]] intValue];
						if( mode)
							[new2DPointROI setROIMode: mode];
					}
				}
			}
		}
		
		[SekhmetSpine filterPointCopiesInMPRView: self]; // SekhVet Paket BT: Wirbelpunkte nur in der sagittalen Ansicht (Schalter im Spine-Panel)
		[self setNeedsDisplay: YES];
	}
}

static ROI *sekhmetLastAdded = nil;
- (ROI*) sekhmetLastAdded2DPoint { ROI *r = sekhmetLastAdded; sekhmetLastAdded = nil; return r; }

- (void) add2DPoint: (float*) r
{
	ViewerController *viewer2D = [windowController viewer];
	sekhmetLastAdded = nil; // Sekhmet: nie einen Zeiger aus einem frueheren Aufruf liefern
	
	if (viewer2D)
	{
		DCMPix *p = [[viewer2D pixList] objectAtIndex: 0];
		
		float sc[ 3];
		
		[p convertDICOMCoords: r toSliceCoords: sc pixelCenter: YES];

		sc[ 0] = sc[ 0] / p.pixelSpacingX;
		sc[ 1] = sc[ 1] / p.pixelSpacingY;
		sc[ 2] = sc[ 2] / p.sliceInterval;
		
		sc[ 2] = round( sc[ 2]);
		
		if (sc[ 2] >= 0 && sc[ 2] < [[viewer2D pixList] count])
		{
			// Create the new 2D Point ROI
			ROI *new2DPointROI = [[[ROI alloc] initWithType: t2DPoint :p.pixelSpacingX :p.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: p]] autorelease];
			
			[new2DPointROI setROIRect: NSMakeRect( sc[ 0], sc[ 1], 0, 0)];
			
			[[viewer2D imageView] roiSet:new2DPointROI];
			[[[viewer2D roiList] objectAtIndex: sc[ 2]] addObject: new2DPointROI];
			sekhmetLastAdded = new2DPointROI; // Sekhmet (nicht retained; nur fuer den unmittelbaren Aufrufer)
			
			// notify the change
			[[NSNotificationCenter defaultCenter] postNotificationName: OsirixROIChangeNotification object: new2DPointROI userInfo: nil];
		}
	}
}

-(void) roiChange:(NSNotification*)note
{
	if( dontCheckRoiChange == NO)
	{
		ROI *r = [note object];
		
		if( [r curView] != nil && [r curView] == [[windowController viewer] imageView])
			[self detect2DPointInThisSlice];
	}
	
	[super roiChange: note];
}

- (void) removeROI: (NSNotification*) note
{
	ROI *r = [note object];
	
	if( [r type] == t2DPoint && r.parentROI)
	{
		[[windowController viewer] deleteROI: r.parentROI];
		r.parentROI = nil;
		
	}
	
	if( dontCheckRoiChange == NO)
	{
		if( [r curView] != nil && [r curView] == [[windowController viewer] imageView])
			[self detect2DPointInThisSlice];
	}
}

#pragma mark-
#pragma mark Mouse Events	

// SekhVet: Fadenkreuz-Zonen einstellbar (Bildschirmpunkte); Horos: 10/10. Zu grosse Zonen lassen den Cursor staendig wechseln.
static float sekhmetCenterZone( void) { float v = [[NSUserDefaults standardUserDefaults] floatForKey: @"SekhmetMPRCenterZone"]; return v > 0 ? v : 18; }
static float sekhmetLineZone( void)   { float v = [[NSUserDefaults standardUserDefaults] floatForKey: @"SekhmetMPRLineZone"];   return v > 0 ? v : 12; }
#define BS sekhmetCenterZone()
static BOOL sekhmetStaticCursor( void) { return [[NSUserDefaults standardUserDefaults] boolForKey: @"SekhmetMPRStaticCursor"]; }

- (float) angleBetween:(NSPoint) mouseLocation center:(NSPoint) center
{
	mouseLocation.x -= center.x;
	mouseLocation.y -= center.y;
	
	return -atan2( mouseLocation.x, mouseLocation.y) / deg2rad;
}

- (NSPoint) centerLines
{
    NSPoint r = NSMakePoint( 0, 0);
    
    // One line or no lines : find the middle of the line
    if( crossLinesB[ 0][ 0] == HUGE_VALF)
    {
        NSPoint a1 = NSMakePoint( crossLinesA[ 0][ 0], crossLinesA[ 0][ 1]);
        NSPoint a2 = NSMakePoint( crossLinesA[ 1][ 0], crossLinesA[ 1][ 1]);
        
        r.x = a2.x + (a1.x - a2.x) / 2.;
        r.y = a2.y + (a1.y - a2.y) / 2.;
        
        return r;
    }
    
    // One line or no lines : find the middle of the line
    if( crossLinesA[ 0][ 0] == HUGE_VALF)
    {
        NSPoint b1 = NSMakePoint( crossLinesB[ 0][ 0], crossLinesB[ 0][ 1]);
        NSPoint b2 = NSMakePoint( crossLinesB[ 1][ 0], crossLinesB[ 1][ 1]);
        
        r.x = b2.x + (b1.x - b2.x) / 2.;
        r.y = b2.y + (b1.y - b2.y) / 2.;
        
        return r;
    }
    
	NSPoint a1 = NSMakePoint( crossLinesA[ 0][ 0], crossLinesA[ 0][ 1]);
	NSPoint a2 = NSMakePoint( crossLinesA[ 1][ 0], crossLinesA[ 1][ 1]);
	
	NSPoint b1 = NSMakePoint( crossLinesB[ 0][ 0], crossLinesB[ 0][ 1]);
	NSPoint b2 = NSMakePoint( crossLinesB[ 1][ 0], crossLinesB[ 1][ 1]);
	
	[DCMView intersectionBetweenTwoLinesA1: a1 A2: a2 B1: b1 B2: b2 result: &r];
	
	return r;
}

- (int) mouseOnLines: (NSPoint) mouseLocation
{
	if( [[NSUserDefaults standardUserDefaults] integerForKey: @"ANNOTATIONS"] == annotNone)
		return 0;
	
	if( displayCrossLines == NO || windowController.sekhmetFrameZoomed)
		return 0;
	
	if( LOD == 0)
		return 0;
	
	if( self.curDCM.pixelSpacingX == 0)
		return 0;
	
	// Intersection of the lines
	NSPoint r = [self centerLines];
	
	if( r.x != 0 || r.y != 0)
	{
		mouseLocation = [self ConvertFromNSView2GL: mouseLocation];
		
		mouseLocation.x *= self.curDCM.pixelSpacingX;
		mouseLocation.y *= self.curDCM.pixelSpacingY;
		
		float f = self.curDCM.pixelSpacingX / LOD * self.window.backingScaleFactor;
		
		if( mouseLocation.x > r.x - BS * f && mouseLocation.x < r.x + BS* f && mouseLocation.y > r.y - BS* f && mouseLocation.y < r.y + BS* f)
		{
			return 2;
		}
		else
		{
			float distance1 = 1000, distance2 = 1000;
			
            if( crossLinesA[ 0][ 0] != HUGE_VALF)
            {
                NSPoint a1 = NSMakePoint( crossLinesA[ 0][ 0], crossLinesA[ 0][ 1]);
                NSPoint a2 = NSMakePoint( crossLinesA[ 1][ 0], crossLinesA[ 1][ 1]);
                [DCMView DistancePointLine:mouseLocation :a1 :a2 :&distance1];
                distance1 /= self.curDCM.pixelSpacingX;
            }
            
            if( crossLinesB[ 0][ 0] != HUGE_VALF)
            {
                NSPoint b1 = NSMakePoint( crossLinesB[ 0][ 0], crossLinesB[ 0][ 1]);
                NSPoint b2 = NSMakePoint( crossLinesB[ 1][ 0], crossLinesB[ 1][ 1]);
                
                [DCMView DistancePointLine:mouseLocation :b1 :b2 :&distance2];
                distance2 /= self.curDCM.pixelSpacingX;
			}
            
			if( distance1 * scaleValue < sekhmetLineZone()*self.window.backingScaleFactor || distance2 * scaleValue < sekhmetLineZone()*self.window.backingScaleFactor)
			{
				return 1;
			}
		}
	}
	
	return 0;
}

- (void)scrollWheel:(NSEvent *)theEvent
{
	[windowController addToUndoQueue:@"mprCamera"];
	
	if( [[self window] firstResponder] != self)
		[[self window] makeFirstResponder: self];
	
	[self restoreCamera];
	
	windowController.lowLOD = YES;
	
	[vrView scrollWheel: theEvent];
	
	[self updateViewMPR: NO];
	[self updateMousePosition: theEvent];
	
    [self displayIfNeeded];
    
	[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: self];	
	[windowController performSelector: @selector(delayedFullLODRendering:) withObject: self afterDelay: 0.2];
}

- (void)rightMouseDown:(NSEvent *)theEvent
{
	[self flagsChanged: theEvent];

	[windowController addToUndoQueue:@"mprCamera"];
	
	if( [[self window] firstResponder] != self)
		[[self window] makeFirstResponder: self];
	
	[self magicTrick];
	
	rotateLines = NO;
	moveCenter = NO;
	
	[self restoreCamera];
	
	[vrView rightMouseDown: theEvent];
	
	[self updateViewMPR];
}

- (void)rightMouseDragged:(NSEvent *)theEvent
{
	[self flagsChanged: theEvent];
	
	[self restoreCamera];
	
	windowController.lowLOD = YES;
	
	[vrView rightMouseDragged: theEvent];
	
	[self updateViewMPR: NO];
	
	[self updateMousePosition: theEvent];
	
	[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
	[windowController performSelector: @selector(delayedFullLODRendering:) withObject: nil afterDelay: 0.4];
}

- (void)rightMouseUp:(NSEvent *)theEvent
{
	[self flagsChanged: theEvent];
	
	[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
	
	windowController.lowLOD = NO;
	
	windowController.mprView1.LOD *= 0.9;
	windowController.mprView2.LOD *= 0.9;
	windowController.mprView3.LOD *= 0.9;
	
	[self restoreCamera];
	
	[vrView rightMouseUp: theEvent];

	if( vrView.lowResLODFactor > 1)
	{
		windowController.mprView1.camera.forceUpdate = YES;
		windowController.mprView2.camera.forceUpdate = YES;
		windowController.mprView3.camera.forceUpdate = YES;
	}
			
	[self updateViewMPR];
	
	[self updateMousePosition: theEvent];
}

- (void) magicTrick	// Dont ask me to explain this function... it's just magic : rendering time is increased by 2 after this call...
{
	[self restoreCamera];
	camera.forceUpdate = YES;
	dontUseAutoLOD = YES;
	moveCenter = YES;
	[self updateViewMPR: NO];
	moveCenter = NO;
	dontUseAutoLOD = NO;
}

- (void) mouseDown:(NSEvent *)theEvent
{
	if( [[self window] firstResponder] != self)
		[[self window] makeFirstResponder: self];
	
	dontCheckRoiChange = YES;
	
	[self checkCursor];
	
	int clickCount = 1;
	
	@try
	{
		if( [theEvent type] ==	NSLeftMouseDown || [theEvent type] ==	NSRightMouseDown || [theEvent type] ==	NSLeftMouseUp || [theEvent type] == NSRightMouseUp)
			clickCount = [theEvent clickCount];
	}
	@catch (NSException * e)
	{
		clickCount = 1;
	}
	
	if( clickCount == 2 && drawingROI == NO)
	{
		mouseDownTool = [self getTool: theEvent];
		
		NSPoint tempPt = [self convertPoint: [theEvent locationInWindow] fromView: nil];
		tempPt = [self ConvertFromNSView2GL:tempPt];
		
		if( [self roiTool: mouseDownTool] && [self clickInROI: tempPt])
		{
			[[self windowController] roiGetInfo: self];
		}
		else
		{
			if( windowController.sekhmetFrameZoomed == NO)
			{
                if( [windowController.horizontalSplit isVertical])
                    windowController.sekhmetSplitH = [[windowController mprView2] frame].origin.x;
				else
                    windowController.sekhmetSplitH = [[windowController mprView2] frame].origin.y;
                
                if( [windowController.verticalSplit isVertical])
                    windowController.sekhmetSplitV = [[windowController mprView3] frame].origin.x;
				else
                    windowController.sekhmetSplitV = [[windowController mprView3] frame].origin.y;
                
				windowController.sekhmetFrameZoomed = YES;
				switch( viewID)
				{
					case 1:
						[windowController.horizontalSplit setPosition: [windowController.horizontalSplit maxPossiblePositionOfDividerAtIndex: 0] - SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
						[windowController.verticalSplit setPosition: [windowController.verticalSplit maxPossiblePositionOfDividerAtIndex: 0] - SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
					break;
					
					case 2:
						[windowController.horizontalSplit setPosition: [windowController.horizontalSplit minPossiblePositionOfDividerAtIndex: 0] + SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
						[windowController.verticalSplit setPosition: [windowController.verticalSplit maxPossiblePositionOfDividerAtIndex: 0] - SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
					break;
					
					case 3:
						[windowController.horizontalSplit setPosition: [windowController.horizontalSplit minPossiblePositionOfDividerAtIndex: 0] + SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
						[windowController.verticalSplit setPosition: [windowController.verticalSplit minPossiblePositionOfDividerAtIndex: 0] + SEKHMET_SPLIT_REST ofDividerAtIndex: 0];
					break;
				}
			}
			else
			{
				windowController.sekhmetFrameZoomed = NO;
                [windowController.verticalSplit setPosition: windowController.sekhmetSplitV ofDividerAtIndex: 0];
				[windowController.horizontalSplit setPosition: windowController.sekhmetSplitH ofDividerAtIndex: 0];
			}
			
			// SekhVet Paket AV: erst im naechsten Runloop-Durchgang rendern. Sofort gerendert
			// traegt der GEMEINSAME vrView noch die Groesse der Ansicht, die der Teilerwechsel
			// gerade auf 0 zusammenklappt (gemessen: vrView 0x942) — das gibt ein tiefschwarzes
			// und beim Zurueckstellen ein weisses Bild. Rueckmeldung 15.09.
			// SekhVet Paket BK: der Doppelklick ist ein Zoom, kein Werkzeugklick. Das folgende mouseUp (und ein etwaiges
			// mouseDragged) darf nicht an DCMView gehen — dort rechnet der WL/WW-Handler den Mausweg gegen den Startpunkt,
			// und die Ansicht ist inzwischen verschoben/vergroessert: Fensterung springt um Hunderte (2150/400, WW 2; VM 17.09.).
			sekhmetZoomClick = YES;
			[NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(sekhmetFinishZoom) object: nil];
			[self performSelector: @selector(sekhmetFinishZoom) withObject: nil afterDelay: 0 inModes: [NSArray arrayWithObject: NSRunLoopCommonModes]];
		}
	}
	else
	{
		[self magicTrick];
		
		[windowController addToUndoQueue:@"mprCamera"];
		
		rotateLines = NO;
		moveCenter = NO;
		
		int mouseOnLines = [self mouseOnLines: [self convertPoint:[theEvent locationInWindow] fromView:nil]];
		if( mouseOnLines == 2)
		{
			moveCenter = YES;
			
			[self mouseDragged: theEvent];
			
			if( sekhmetStaticCursor() == NO) [[NSCursor closedHandCursor] set];
		}
		else if( mouseOnLines == 1)
		{
			rotateLines = YES;
			
			NSPoint mouseLocation = [self ConvertFromNSView2GL: [self convertPoint: [theEvent locationInWindow] fromView: nil]];
			mouseLocation.x *= self.curDCM.pixelSpacingX;	mouseLocation.y *= self.curDCM.pixelSpacingY;
			rotateLinesStartAngle = [self angleBetween: mouseLocation center: [self centerLines]] - angleMPR;
			
			[self mouseDragged: theEvent];
			
			if( sekhmetStaticCursor() == NO) [[NSCursor rotateAxisCursor] set];
		}
		else
		{
			mouseDownTool = [self getTool: theEvent];
			
			if( [self roiTool: currentTool])
			{
				NSPoint tempPt = [self ConvertFromNSView2GL: [self convertPoint: [theEvent locationInWindow] fromView: nil]];
				if( [self clickInROI: tempPt])
					mouseDownTool = currentTool;
			}
			
			vrView.keep3DRotateCentered = YES;
			if( mouseDownTool == tCamera3D)
			{
				if( displayCrossLines == NO || windowController.sekhmetFrameZoomed == YES)
					vrView.keep3DRotateCentered = NO;
				else
				{
					if( [theEvent modifierFlags] & NSAlternateKeyMask)
						vrView.keep3DRotateCentered = NO;
				}
			}
			
			[self restoreCamera];
			
			if([self is2DTool: mouseDownTool])
			{
				[super mouseDown: theEvent];
				[windowController propagateWLWW: self];
				
				for( ROI *r in curRoiList)
				{
					int mode;
					
					if( [r type] == t2DPoint && r.parentROI)
					{
						mode = [r ROImode];
						if( mode == ROI_selected || mode == ROI_selectedModify || mode == ROI_drawing)
						{
							[[windowController viewer] deleteROI: r.parentROI];
							r.parentROI = nil;
						}
					}
				}
			}
			else
			{
				[vrView mouseDown: theEvent];
				
				if( [vrView _tool] == tRotate)
					[self updateViewMPR: NO];
				else
					[self updateViewMPR];
			}
		}
	}
}

- (void) mouseUp:(NSEvent *)theEvent
{
	[self checkCursor];
	
	if( sekhmetZoomClick) // SekhVet Paket BK: Ende des Doppelklick-Zooms, kein Werkzeug
	{
		sekhmetZoomClick = NO;
		windowController.lowLOD = NO;
		return;
	}
	
	[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
	
	windowController.lowLOD = NO;
		
	[self restoreCamera];
	
	if( rotateLines || moveCenter)
	{
		if( moveCenter)
		{
			camera.windowCenterX = 0;
			camera.windowCenterY = 0;
			camera.forceUpdate = YES;
		}
		
		if( vrView.lowResLODFactor > 1)
		{
			windowController.mprView1.camera.forceUpdate = YES;
			windowController.mprView2.camera.forceUpdate = YES;
			windowController.mprView3.camera.forceUpdate = YES;
		}
		
		rotateLines = NO;
		moveCenter = NO;

		windowController.mprView1.LOD *= 0.9;
		windowController.mprView2.LOD *= 0.9;
		windowController.mprView3.LOD *= 0.9;

		[self restoreCamera];
		[self updateViewMPR];
		
		[cursor set];
	}
	else
	{
		if([self is2DTool: mouseDownTool])
		{
			[super mouseUp: theEvent];
			[windowController propagateWLWW: self];
		
			if( mouseDownTool == tNext)
				[windowController updateViewsAccordingToFrame: self];
			
			for( ROI *r in curRoiList)
			{
				if( [r type] == t2DPoint && r.parentROI == nil)
				{
					float location[ 3];
					[pix convertPixX: r.rect.origin.x pixY: r.rect.origin.y toDICOMCoords: location pixelCenter: YES];
					[self add2DPoint: location];
					if( r.name.length) { ROI *pers = [self sekhmetLastAdded2DPoint]; if( pers) { [pers setName: r.name]; [SekhmetSpine notePersistentROI: pers]; } } // Sekhmet
				}
			}
			
			[self detect2DPointInThisSlice];
		}
		else
		{
			[vrView mouseUp: theEvent];
			
			if( vrView.lowResLODFactor > 1)
			{
				windowController.mprView1.camera.forceUpdate = YES;
				windowController.mprView2.camera.forceUpdate = YES;
				windowController.mprView3.camera.forceUpdate = YES;
			}
			
			windowController.mprView1.LOD *= 0.9;
			windowController.mprView2.LOD *= 0.9;
			windowController.mprView3.LOD *= 0.9;
			
			if( [vrView _tool] == tRotate)
				[self updateViewMPR: NO];
			else
				[self updateViewMPR];
		}
	}
	
	[self updateMousePosition: theEvent];
	
	dontCheckRoiChange = NO;
}

- (void) mouseDraggedImageScroll:(NSEvent *) event
{
	[self checkCursor];
	
	NSPoint current = [self currentPointInView: event];
	
	if( scrollMode == 0)
	{
		if( fabs( start.x - current.x) < fabs( start.y - current.y))
		{
			if( fabs( start.y - current.y) > 3) scrollMode = 1;
		}
		else if( fabs( start.x - current.x) >= fabs( start.y - current.y))
		{
			if( fabs( start.x - current.x) > 3) scrollMode = 2;
		}
	}
	
	float delta;
	
	if( scrollMode == 1)
		delta = ((previous.y - current.y) * 512. )/ ([self convertSizeToBacking: self.frame.size].width/2);
	else
		delta = ((current.x - previous.x) * 512. )/ ([self convertSizeToBacking: self.frame.size].width/2);
	
	[self restoreCamera];
	windowController.lowLOD = YES;
	[vrView scrollInStack: delta];
	[self updateViewMPR];
	[self updateMousePosition: event];
	windowController.lowLOD = NO;
}

-(void) magnifyWithEvent:(NSEvent *)anEvent
{
}

-(void) rotateWithEvent:(NSEvent *)anEvent
{
}

- (void) mouseDragged:(NSEvent *)theEvent
{
	if( sekhmetZoomClick) return; // SekhVet Paket BK
	[self restoreCamera];
	
	if( rotateLines)
	{
		if( sekhmetStaticCursor() == NO) [[NSCursor rotateAxisCursor] set];
		
		windowController.lowLOD = YES;
		
		NSPoint mouseLocation = [self ConvertFromNSView2GL: [self convertPoint: [theEvent locationInWindow] fromView: nil]];
		mouseLocation.x *= self.curDCM.pixelSpacingX;	mouseLocation.y *= self.curDCM.pixelSpacingY;
		angleMPR = [self angleBetween: mouseLocation center: [self centerLines]];
		
		angleMPR -= rotateLinesStartAngle;
		
		[self updateViewMPR];
		
		[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
		[windowController performSelector: @selector(delayedFullLODRendering:) withObject: nil afterDelay: 0.4];
	}
	else if( moveCenter)
	{
		windowController.lowLOD = YES;
        
        NSPoint point = [self convertPoint: [theEvent locationInWindow] fromView: nil];
        
        point = [self convertPointToBacking: point];
        
        if( yFlipped)
            point.y = [self convertSizeToBacking: self.frame.size].height - point.y;
        
        if( xFlipped)
            point.x = [self convertSizeToBacking: self.frame.size].width - point.x;
        
		[vrView setWindowCenter: point];
		
        [self updateViewMPR];
		
		[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
		[windowController performSelector: @selector(delayedFullLODRendering:) withObject: nil afterDelay: 0.4];
	}
	else
	{
		if( [self is2DTool: mouseDownTool])
		{
			[super mouseDragged: theEvent];
			[windowController propagateWLWW: self];
		}
		else
		{
			float before[ 9], after[ 9];
			
			windowController.lowLOD = YES;
			
			if( [vrView _tool] == tRotate)
				[self.pix orientation: before];
			
			[vrView mouseDragged: theEvent];
			
			if( [vrView _tool] == tRotate)
			{
				[vrView getCosMatrix: after];
				angleMPR -= [MPRController angleBetweenVector: after andPlane: before];
				
				[self updateViewMPR: NO];
			}
			else if( [vrView _tool] == tZoom) [self updateViewMPR: [[NSUserDefaults standardUserDefaults] boolForKey: @"syncZoomLevelMPR"]]; // SekhVet Paket S: mit Zoom-Schalter die anderen zwei Ansichten live mitzoomen, nicht erst beim Loslassen
			else [self updateViewMPR];
			
			[NSObject cancelPreviousPerformRequestsWithTarget: windowController selector:@selector(delayedFullLODRendering:) object: nil];
			[windowController performSelector: @selector(delayedFullLODRendering:) withObject: nil afterDelay: 0.4];
		}
	}
	
	[self updateMousePosition: theEvent];
}

- (void) updateMousePosition: (NSEvent*) theEvent
{
	float location[ 3];
	
	[pix convertPixX: mouseXPos pixY: mouseYPos toDICOMCoords: location pixelCenter: YES];

	Point3D *pt = [Point3D pointWithX: location[ 0] y: location[ 1] z: location[ 2]];
	windowController.mousePosition = pt;
	windowController.mouseViewID = viewID;
}

- (void) mouseMoved: (NSEvent *) theEvent
{
	if( ![[self window] isVisible])
		return;
	
	if( [windowController windowWillClose])
		return;
		
	NSView* view = [[[theEvent window] contentView] hitTest:[theEvent locationInWindow]];
	
	if( view == self)
	{
		if( NSPointInRect( [self convertPoint: [theEvent locationInWindow] fromView: nil], [self bounds]) == NO)
			return;
		
		[super mouseMoved: theEvent];
		
		int mouseOnLines = [self mouseOnLines: [self convertPoint: [theEvent locationInWindow] fromView:nil]];
		if( mouseOnLines==2)
		{
			if( [theEvent type] == NSLeftMouseDragged) [[NSCursor closedHandCursor] set];
			else [[NSCursor openHandCursor] set];
		}
		else if( mouseOnLines==1)
		{
			[[NSCursor rotateAxisCursor] set];
		}
		else
		{
			[cursor set];
		}
		if( sekhmetStaticCursor()) [[NSCursor arrowCursor] set];   // SekhVet: kein Hin- und Herspringen zwischen Hand/Drehen/Werkzeug
		
		[self updateMousePosition: theEvent];
	}
	else
	{
		[view mouseMoved:theEvent];
	}
}

#pragma mark-
#pragma mark Private Methods
- (void)drawOSIROIs
{
    double pixToSubdrawRectOpenGLTransform[16];
    CGLContextObj cgl_ctx;
    OSIROI *roi;
    
    cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil)
        return;
    
    if ([self ROIManager] == nil) {
        return;
    }
    
    N3AffineTransformGetOpenGLMatrixd([self pixToSubDrawRectTransform], pixToSubdrawRectOpenGLTransform);
    
    for (roi in [[self ROIManager] ROIs]) {
        glMatrixMode(GL_MODELVIEW);
        glPushMatrix();
        glMultMatrixd(pixToSubdrawRectOpenGLTransform);
        
        [roi drawSlab:OSISlabMake([self plane], 0) inCGLContext:cgl_ctx pixelFormat:(CGLPixelFormatObj)[[self pixelFormat] CGLPixelFormatObj]
                dicomToPixTransform:N3AffineTransformInvert([self pixToDicomTransform])];
        
        glMatrixMode(GL_MODELVIEW);
        glPopMatrix();
        
    }
}

- (OSIROIManager *)ROIManager
{
    if (_ROIManager == nil) {
        OSIEnvironment *environment;
        OSIVolumeWindow *volumeWindow;
        environment = [OSIEnvironment sharedEnvironment];
        
        if (environment == nil) {
            return nil;
        }
        
        volumeWindow = [environment volumeWindowForViewerController:[windowController viewer]];
        _ROIManager = [[OSIROIManager alloc] initWithVolumeWindow:volumeWindow coalesceROIs:YES];
    }
    
    return _ROIManager;
}


- (N3Plane)plane
{
    N3AffineTransform pixToDicomTransform;
	N3Plane plane;
    
    pixToDicomTransform = [self pixToDicomTransform];
    
    plane.point = N3VectorApplyTransform(N3VectorMake((CGFloat)self.curDCM.pwidth/2.0, (CGFloat)self.curDCM.pheight/2.0, 0.0), pixToDicomTransform);
    plane.normal = N3VectorNormalize(N3VectorApplyTransformToDirectionalVector(N3VectorMake(0.0, 0.0, 1.0), pixToDicomTransform));
    
	if (N3PlaneIsValid(plane)) {
		return plane;
	} else {
		return N3PlaneInvalid;
	}
}




#pragma mark-

@end
 
