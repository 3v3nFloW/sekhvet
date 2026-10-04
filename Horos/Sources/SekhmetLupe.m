/*=========================================================================
 DCMView (SekhVetLupe) — Paket CC. Siehe Header.
 ============================================================================*/

#import "SekhmetLupe.h"
#import "ROI.h"
#import "DCMPix.h"
#import "ViewerController.h"
#import "MPRDCMView.h"
#import <objc/runtime.h>
#include <OpenGL/CGLMacro.h>

#define LUPE_ZOOM_MIN 1.5
#define LUPE_ZOOM_MAX 12.0

static float lupeZoom( void)
{
    float z = [[NSUserDefaults standardUserDefaults] floatForKey: @"SekhmetLupeZoom"];
    return z >= LUPE_ZOOM_MIN && z <= LUPE_ZOOM_MAX ? z : 3.0;
}

static float lupeGroesse( void)     // Anteil an der kuerzeren Seite des Viewers
{
    float g = [[NSUserDefaults standardUserDefaults] floatForKey: @"SekhmetLupeGroesse"];
    // Paket CF-2: bis Build 128 schrieben auch die Zoomtasten die Groesse mit ab — ein gespeicherter Wert
    // von genau 0,36 ist also die alte Vorgabe, nie eine eigene Wahl (Pfeil hoch/runter geht in Schritten x1,2).
    if( fabsf( g - 0.36f) < 0.0005f) return 0.55;
    return g >= 0.15 && g <= 0.8 ? g : 0.55;     // Paket CF: Vorgabe 36 -> 55 % (Nutzerwunsch 28.09.: um die Haelfte groesser)
}

// Ecke der Messlupe: beim Start einer Messung einmal gewaehlt und dann festgehalten
// (Rueckmeldung 27.09.: "springt in die jeweiligen Ecken, wenn man zieht"). Sie wechselt nur,
// wenn der Zeiger ins Feld hineinlaeuft. Bit 0 = rechts, Bit 1 = oben; -1 = keine Messung.
static int lupeEcke = -1;
static DCMView *lupeEckeView = nil;     // nicht gehalten, nur verglichen

static NSRect eckFeld( int ecke, float w, float h, float g, float rand)
{
    return NSMakeRect( (ecke & 1) ? w - g - rand : rand, (ecke & 2) ? h - g - rand : rand, g, g);
}

@implementation DCMView (SekhVetLupe)

// Paket CE (28.09.2026): die Lupe gilt auch in den MPR-Ansichten (MPRDCMView ist eine DCMView).
// Das Fadenkreuz zeichnet die MPR-Ansicht in subDrawRect:, NACH drawRectIn: — der zweite
// Durchgang der Lupe bringt es darum nicht mit (so gewollt, Entscheid vom 28.09.: nur die Messlinien).
- (BOOL) sekhmetLupeErlaubt
{
    return [self is2DViewer] || [self isKindOfClass: [MPRDCMView class]];
}

- (BOOL) sekhmetLupeBeimMessen
{
    if( ![self sekhmetLupeErlaubt] || _imageColumns > 1 || _imageRows > 1) return NO;
    id aus = [[NSUserDefaults standardUserDefaults] objectForKey: @"SekhmetMessLupe"];
    if( aus && ![aus boolValue]) return NO;
    if( ([NSEvent pressedMouseButtons] & 1) == 0) return NO;

    // Paket CO (Nutzerwunsch 30.09.2026): die Messlupe nur bei der Laengenmessung — beim Oval und den anderen Werkzeugen stoert sie.
    for( ROI *r in curRoiList)
        if( r.type == tMesure && (r.ROImode == ROI_drawing || r.ROImode == ROI_selectedModify))
            return YES;
    return NO;
}

#if SEKHVET_TESTHAKEN   // SekhVet Paket CS: only used by +[SekhmetUeberlagerung debugLupe:]
- (BOOL) sekhmetFreieLupeAktiv
{
    return lensTexture != nil;
}
#endif // SEKHVET_TESTHAKEN

- (void) sekhmetZeichneLupe
{
    if( ![self sekhmetLupeErlaubt] || dcmPixList == nil || curImage < 0 || pTextureName == nil) return;
    if( [stringID isEqualToString: @"export"]) return;   // SekhVet Paket CS: never bake the lens into an exported image

    BOOL messen = [self sekhmetLupeBeimMessen];
    BOOL frei = !messen && lensTexture != nil;
    if( !messen && lupeEckeView == self) { lupeEcke = -1; lupeEckeView = nil; }
    if( !messen && !frei) return;

    NSPoint maus = [self convertPoint: [[self window] mouseLocationOutsideOfEventStream] fromView: nil];
    if( !NSPointInRect( maus, [self bounds]))
    {
        if( frei) return;
        maus.x = MIN( MAX( maus.x, NSMinX( [self bounds])), NSMaxX( [self bounds]));
        maus.y = MIN( MAX( maus.y, NSMinY( [self bounds])), NSMaxY( [self bounds]));
    }
    NSPoint bild = [self ConvertFromNSView2GL: maus];       // Bildpixel, wie die ROI-Punkte
    NSPoint px = [self convertPointToBacking: maus];        // Geraetepixel, Ursprung unten links wie glViewport

    CGLContextObj cgl_ctx = [[NSOpenGLContext currentContext] CGLContextObj];
    if( cgl_ctx == nil) return;

    float sf = self.window.backingScaleFactor;
    if( sf < 1) sf = 1;
    NSRect voll = drawingFrameRect;
    float w = voll.size.width, h = voll.size.height, rand = 8 * sf;
    float g = MAX( lupeGroesse() * MIN( w, h), 140 * sf);   // Paket CF: ohne die 560-pt-Kappe, sonst griffe die groessere Vorgabe auf grossen Schirmen nicht
    g = floorf( MIN( g, 0.9 * MIN( w, h) - 2 * rand));
    if( g < 60) return;

    NSRect feld;
    if( messen)     // Ecke weitab vom Zeiger — beim Start gewaehlt, dann fest
    {
        int weitab = (px.x < w / 2 ? 1 : 0) | (px.y < h / 2 ? 2 : 0);
        if( lupeEckeView != self || lupeEcke < 0) { lupeEcke = weitab; lupeEckeView = self; }
        else if( NSPointInRect( px, NSInsetRect( eckFeld( lupeEcke, w, h, g, rand), -16 * sf, -16 * sf)))
            lupeEcke = weitab;      // Zeiger laeuft ins Feld: erst dann ausweichen
        feld.origin = eckFeld( lupeEcke, w, h, g, rand).origin;
    }
    else            // neben dem Zeiger, nicht darueber
    {
        float abstand = 28 * sf;
        feld.origin.x = px.x + abstand; if( feld.origin.x + g > w - rand) feld.origin.x = px.x - abstand - g;
        feld.origin.y = px.y + abstand; if( feld.origin.y + g > h - rand) feld.origin.y = px.y - abstand - g;
        feld.origin.x = MIN( MAX( feld.origin.x, rand), w - g - rand);
        feld.origin.y = MIN( MAX( feld.origin.y, rand), h - g - rand);
    }
    feld.origin.x = floorf( feld.origin.x); feld.origin.y = floorf( feld.origin.y);
    feld.size = NSMakeSize( g, g);

    // Zweiter Durchgang mit hoeherem Zoom, den Punkt in der Feldmitte. Die Abbildung aus
    // drawRectIn: ist  Punkt -> (origin.x + (x - pw/2)*s,  -origin.y + pixelRatio*(y - ph/2)*s)
    // vor Drehung/Spiegelung; Null in der Feldmitte ergibt den neuen Ursprung.
    DCMPix *pix = self.curDCM;
    float pr = pix.pixelRatio > 0 ? pix.pixelRatio : 1;
    float altScale = scaleValue;
    NSPoint altOrigin = origin;
    NSRect altFrame = drawingFrameRect;
    float s2 = MIN( scaleValue * lupeZoom(), 40.0);

    glPushAttrib( GL_ALL_ATTRIB_BITS);
    glViewport( feld.origin.x, feld.origin.y, g, g);
    glEnable( GL_SCISSOR_TEST);
    glScissor( feld.origin.x, feld.origin.y, g, g);
    glClearColor( 0, 0, 0, 1);
    glClear( GL_COLOR_BUFFER_BIT);
    glDisable( GL_BLEND);

    @try
    {
        drawingFrameRect = NSMakeRect( 0, 0, g, g);
        scaleValue = s2;
        origin = NSMakePoint( -( bild.x - pix.pwidth / 2.) * s2, pr * ( bild.y - pix.pheight / 2.) * s2);

        [self drawRectIn: drawingFrameRect :pTextureName :NSZeroPoint :textureX :textureY :textureWidth :textureHeight];

        glMatrixMode( GL_MODELVIEW);
        glLoadIdentity();
        glScalef( 2.0f / (xFlipped ? -g : g), -2.0f / (yFlipped ? -g : g), 1.0f);
        glRotatef( rotation, 0.0f, 0.0f, 1.0f);
        glTranslatef( origin.x, -origin.y, 0.0f);
        glScalef( 1.f, pr, 1.f);

        // SekhVet Paket CS: drawing a ROI also lays out its text box (-[ROI prepareTextualData:]) with the view's
        // CURRENT scale and origin — after this pass the hit rectangle of every text box (ROI ivar "drawRect", used
        // by -[ROI clickInROI:...]) was in lens coordinates until the next draw without the lens. It is put back
        // after each ROI; the ivar has no accessor, hence KVC (checked once that the ivar exists).
        static BOOL textfeldGeprueft = NO, textfeldDa = NO;
        if( textfeldGeprueft == NO)
        {
            textfeldDa = class_getInstanceVariable( [ROI class], "drawRect") != NULL && [ROI accessInstanceVariablesDirectly];
            textfeldGeprueft = YES;
        }

        NSRecursiveLock *sperre = [[self windowController] respondsToSelector: @selector(roiLock)] ? [[self windowController] roiLock] : nil;
        if( sperre == nil || [sperre tryLock])
        {
            for( long i = (long) [curRoiList count] - 1; i >= 0; i--)
            {
                ROI *r = [[curRoiList objectAtIndex: i] retain];
                NSValue *textfeld = textfeldDa ? [r valueForKey: @"drawRect"] : nil;
                [r drawROI: scaleValue : pix.pwidth / 2. : pix.pheight / 2. : pix.pixelSpacingX : pix.pixelSpacingY];
                if( textfeld) [r setValue: textfeld forKey: @"drawRect"];
                [r release];
            }
            [sperre unlock];
        }
    }
    @catch( NSException *e)
    {
        NSLog( @"SekhVet loupe: %@", e);
    }
    @finally
    {
        scaleValue = altScale;
        origin = altOrigin;
        drawingFrameRect = altFrame;
    }

    glDisable( GL_SCISSOR_TEST);
    glViewport( 0, 0, w, h);

    // Rahmen in Geraetepixeln (Ursprung oben links)
    glMatrixMode( GL_MODELVIEW);
    glLoadIdentity();
    glScalef( 2.0f / w, -2.0f / h, 1.0f);
    glTranslatef( -w / 2.0f, -h / 2.0f, 0.0f);
    float oben = h - feld.origin.y - g, links = feld.origin.x, b = 1.5 * sf;
    glEnable( GL_BLEND);
    glBlendFunc( GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // Paket CG-2 (Entscheid vom 28.09.): KEIN Pfeil in der Lupe — gewollt ist der echte Zeiger im Original, damit man
    // sieht, wo die Mitte der Lupe liegt. Dafuer versteckt computeMagnifyLens: den Zeiger nicht mehr (DCMView.m).
    glColor4f( 1.0f, 1.0f, 1.0f, 0.85f);
    glLineWidth( 2.0 * sf);
    glBegin( GL_LINE_LOOP);
    glVertex2f( links + b / 2, oben + b / 2);
    glVertex2f( links + g - b / 2, oben + b / 2);
    glVertex2f( links + g - b / 2, oben + g - b / 2);
    glVertex2f( links + b / 2, oben + g - b / 2);
    glEnd();
    glPopAttrib();
    glLineWidth( 1.0 * sf);
}

- (BOOL) sekhmetLupeTaste:(unichar) c
{
    if( ![self sekhmetLupeErlaubt]) return NO;
    BOOL messen = [self sekhmetLupeBeimMessen];
    if( !messen && lensTexture == nil) return NO;

    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    float z = lupeZoom(), g = lupeGroesse();

    // Pfeile auch bei der Shift-Lupe: + / - kamen dort nicht an (Rueckmeldung 27.09.) — bei gehaltener
    // Shift-Taste liefert die Tastatur je nach Belegung andere Zeichen (z. B. "*" statt "+").
    if( c == '+' || c == '=' || c == '*' || c == NSRightArrowFunctionKey) z = MIN( z * 1.25, LUPE_ZOOM_MAX);
    else if( c == '-' || c == '_' || c == NSLeftArrowFunctionKey) z = MAX( z / 1.25, LUPE_ZOOM_MIN);
    else if( c == NSUpArrowFunctionKey) g = MIN( g * 1.2, 0.8);
    else if( c == NSDownArrowFunctionKey) g = MAX( g / 1.2, 0.15);
    else return NO;

    // Paket CF-2: nur den geaenderten Wert schreiben — sonst friert der Zoom die Groesse auf die Vorgabe ein
    if( z != lupeZoom()) [d setFloat: z forKey: @"SekhmetLupeZoom"];
    if( g != lupeGroesse()) [d setFloat: g forKey: @"SekhmetLupeGroesse"];
    [self setNeedsDisplay: YES];
    return YES;
}

- (BOOL) sekhmetLupeRad:(NSEvent*) e
{
    if( ![self sekhmetLupeErlaubt]) return NO;
    if( ![self sekhmetLupeBeimMessen] && lensTexture == nil) return NO;
    
    // Mit Shift macht macOS aus dem senkrechten Rad ein waagrechtes — beide Richtungen zaehlen.
    CGFloat d = [e scrollingDeltaY];
    if( fabs( d) < fabs( [e scrollingDeltaX])) d = [e scrollingDeltaX];
    if( d == 0) return YES;
    
    static NSTimeInterval zuletzt = 0;     // Trackpad liefert Dutzende Ereignisse je Wisch
    if( [e hasPreciseScrollingDeltas] && [e timestamp] - zuletzt < 0.08) return YES;
    zuletzt = [e timestamp];
    
    return [self sekhmetLupeTaste: d > 0 ? '+' : '-'];
}

@end
