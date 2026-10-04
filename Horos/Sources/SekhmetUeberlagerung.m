/*=========================================================================
 SekhVet Paket CJ — Ueberlagern (Umsetzung). Beschreibung im Header.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import "SekhmetUeberlagerung.h"
#import "SekhmetRestrictedUnarchiver.h" // SekhVet Paket DE: Archive nur mit erlaubten Klassen auspacken
#import "SekhmetSequenz.h"
#import "SekhmetWindowing.h"
#import "SekhmetTesthaken.h"   // SekhVet Paket CS: the test methods at the end exist only with SEKHVET_TESTHAKEN
#import "SekhmetLupe.h"
#import "DCMView.h"
#import "DCMPix.h"
#import "ROI.h"
#import "DicomSeries.h"
#import "DicomStudy.h"
#import "DicomImage.h"
#import "BrowserController.h"
#import "MPRController.h"
#import "MPRDCMView.h"
#import "SekhmetMPRKategorie.h"   // SekhVet Paket DA: sekhmetCurrentViews / sekhmetApplyViews:
#import "Window3DController.h"
#import "ToolbarPanel.h"
#import "WaitRendering.h"
#import "SRAnnotation.h"   // SekhVet Paket CS: count the saved measurements of an overlaid series
#import "DCM.h"
#import "SeriesView.h"   // SekhVet Paket CX
#import <objc/runtime.h>

NSString* const SekhmetOverlayToolbarItemIdentifier = @"SekhmetOverlay";
NSString* const SekhmetOverlayKeyNextKey = @"SekhmetOverlayKeyNext";
NSString* const SekhmetOverlayKeyPrevKey = @"SekhmetOverlayKeyPrev";
static NSString* const SekhmetOverlayDeselectedKey = @"SekhmetOverlayDeselected";   // Paket CN: abgewaehlte CT-Raenge (0 Nativ, 1 KM, 3 Nativ Kn, 4 KM Kn)

#define SEKHMET_STAPEL_MAX 4

@interface ViewerController (SekhVetUeberlagerungPrivat)
- (void)sendWillFreeVolumeDataNotificationWithVolumeData:(NSData *)volumeData movieIndex:(NSInteger)movieIndex;
@end

static char SekhmetStapelKey;
static char SekhmetZeileKey;
static char SekhmetZeileCacheKey;   // SekhVet Paket CS: @[ signature, enhancement line or NSNull ] per ROI
static unsigned svGeneration = 0;   // SekhVet Paket CS: counts successful staple: calls, part of the cache signature
static char SekhmetBereitKey;   // SekhVet Paket CK: "Overlay" ist an, aber noch nichts gestapelt (SeriesInstanceUID der Serie im Fenster)

#pragma mark - Zustand je Viewer

// Ein Eintrag je Movie-Index des Viewers (0 = Bezugsserie). "reihenfolge" = Movie-Indizes in Rangfolge
// (Nativ, KM, Nativ Kn, KM Kn): so stehen die Chips, so schalten "<" und "y".
@interface SekhmetStapel : NSObject
{
@public
    NSMutableArray *namen, *serienNamen, *serienUIDs, *phasen, *knochen, *sequenzen, *mrKM, *fenster, *versteckt, *reihenfolge;
    NSMutableArray *aus;   // Paket CN: @YES = abgewaehlt (geladen, aber ohne Chip und nicht im Durchschalten)
    NSString *modalitaet;
    void *refPixList;   // nur zum Vergleich: haengt noch unser Stapel im Viewer?
    // SekhVet Paket CS:
    void *refPixList1;          // second address for the same comparison (first overlaid series)
    BOOL warPostprocessed;      // the viewer's "postprocessed" flag before stacking, restored by beende:
    NSInteger gezeigt;          // movie index SekhVet showed last; differs from curMovieIndex after a switch by Horos' own 4D paths
    int richtung;               // +1 / -1: direction of that last foreign switch
    unsigned generation;        // svGeneration at the last successful staple:
}
@end

@implementation SekhmetStapel
- (id) init
{
    self = [super init];
    if( self)
    {
        namen = [[NSMutableArray alloc] init]; serienNamen = [[NSMutableArray alloc] init]; serienUIDs = [[NSMutableArray alloc] init];
        phasen = [[NSMutableArray alloc] init]; knochen = [[NSMutableArray alloc] init]; sequenzen = [[NSMutableArray alloc] init];
        mrKM = [[NSMutableArray alloc] init]; fenster = [[NSMutableArray alloc] init]; versteckt = [[NSMutableArray alloc] init];
        reihenfolge = [[NSMutableArray alloc] init]; aus = [[NSMutableArray alloc] init];
    }
    return self;
}
- (void) dealloc
{
    [namen release]; [serienNamen release]; [serienUIDs release]; [phasen release]; [knochen release]; [sequenzen release];
    [mrKM release]; [fenster release]; [versteckt release]; [reihenfolge release]; [aus release]; [modalitaet release];
    [super dealloc];
}
- (NSUInteger) count { return namen.count; }
@end

#pragma mark - Neuabtastung (C)

// Quellserie: parallele Schichten gleicher Groesse, nach Lage auf der Normalen aufsteigend sortiert.
typedef struct
{
    const float **img;      // je Schicht
    const double *pos;      // Lage auf der Normalen, relativ zu Schicht 0
    const double *shiftU, *shiftV;  // Verschiebung der Schicht in der Ebene (Pixel), relativ zu Schicht 0
    int ns, w, h;
    double o0[3], r[3], c[3], n[3], sx, sy, tolz;
} SVQuelle;

static inline double svDot( const double *a, const double *b) { return a[0]*b[0] + a[1]*b[1] + a[2]*b[2]; }

static inline float svBilinear( const float *im, int w, int h, double u, double v, float fill, BOOL *ok)
{
    if( u < -0.5 || v < -0.5 || u > w - 0.5 || v > h - 0.5) { *ok = NO; return fill; }
    if( u < 0) u = 0; if( v < 0) v = 0;
    if( u > w - 1) u = w - 1; if( v > h - 1) v = h - 1;
    int x0 = (int) u, y0 = (int) v;
    int x1 = x0 + 1 < w ? x0 + 1 : x0, y1 = y0 + 1 < h ? y0 + 1 : y0;
    double fx = u - x0, fy = v - y0;
    const float *a = im + (long) y0 * w, *b = im + (long) y1 * w;
    double top = a[x0] + (a[x1] - a[x0]) * fx, bot = b[x0] + (b[x1] - b[x0]) * fx;
    *ok = YES;
    return (float) (top + (bot - top) * fy);
}

// Eine Zielschicht: Ursprung o, Zeilen-/Spaltenrichtung dr/dc, Pixelabstand dsx/dsy, Groesse dw x dh.
static void svResampleSlice( const SVQuelle *q, const double *o, const double *dr, const double *dc, double dsx, double dsy, int dw, int dh, float *dst, float fill)
{
    double d0[3] = { o[0] - q->o0[0], o[1] - q->o0[1], o[2] - q->o0[2] };
    double z00 = svDot( d0, q->n), u00 = svDot( d0, q->r) / q->sx, v00 = svDot( d0, q->c) / q->sy;
    double dzx = dsx * svDot( dr, q->n), dzy = dsy * svDot( dc, q->n);
    double dux = dsx * svDot( dr, q->r) / q->sx, duy = dsy * svDot( dc, q->r) / q->sx;
    double dvx = dsx * svDot( dr, q->c) / q->sy, dvy = dsy * svDot( dc, q->c) / q->sy;
    int j = 0;
    for( int y = 0; y < dh; y++)
    {
        float *row = dst + (long) y * dw;
        for( int x = 0; x < dw; x++)
        {
            double z = z00 + x * dzx + y * dzy;
            double t = 0;
            if( z < q->pos[ 0])
            {
                if( q->pos[ 0] - z > q->tolz) { row[ x] = fill; continue; }
                j = 0; t = 0;
            }
            else if( z >= q->pos[ q->ns - 1])
            {
                if( z - q->pos[ q->ns - 1] > q->tolz) { row[ x] = fill; continue; }
                j = q->ns - 1; t = 0;
            }
            else
            {
                if( !(q->pos[ j] <= z && z < q->pos[ j + 1]))
                {
                    int lo = 0, hi = q->ns - 1;
                    while( hi - lo > 1) { int mid = (lo + hi) / 2; if( q->pos[ mid] <= z) lo = mid; else hi = mid; }
                    j = lo;
                }
                double span = q->pos[ j + 1] - q->pos[ j];
                t = span > 1e-9 ? (z - q->pos[ j]) / span : 0;
            }
            double u = u00 + x * dux + y * duy, v = v00 + x * dvx + y * dvy;
            BOOL ok0 = NO, ok1 = YES;
            float a = svBilinear( q->img[ j], q->w, q->h, u - q->shiftU[ j], v - q->shiftV[ j], fill, &ok0);
            if( !ok0) { row[ x] = fill; continue; }
            if( t > 1e-6 && j + 1 < q->ns)
            {
                float b = svBilinear( q->img[ j + 1], q->w, q->h, u - q->shiftU[ j + 1], v - q->shiftV[ j + 1], fill, &ok1);
                row[ x] = ok1 ? (float) (a + (b - a) * t) : a;
            }
            else row[ x] = a;
        }
    }
}

static void svKreuz( const double *a, const double *b, double *out)
{
    out[ 0] = a[1]*b[2] - a[2]*b[1];
    out[ 1] = a[2]*b[0] - a[0]*b[2];
    out[ 2] = a[0]*b[1] - a[1]*b[0];
    double l = sqrt( svDot( out, out));
    if( l > 1e-12) { out[0] /= l; out[1] /= l; out[2] /= l; }
}

// Geometrie einer DCMPix: Ursprung, Zeile, Spalte, Normale (n darf NULL sein).
static void svGeometrie( DCMPix *p, double *o, double *r, double *c, double *n)
{
    double or9[ 9];
    [p orientationDouble: or9];
    o[ 0] = p.originX; o[ 1] = p.originY; o[ 2] = p.originZ;
    for( int k = 0; k < 3; k++) { r[ k] = or9[ k]; c[ k] = or9[ 3 + k]; }
    if( n) svKreuz( r, c, n);   // SekhVet Paket CS: n may be NULL
}

#pragma mark - Implementierung

// SekhVet Paket CX
@interface DCMView (SekhVetCX)
- (void) reapplyWindowLevel;   // in DCMView.m vorhanden, nicht im Header
@end

@implementation SekhmetUeberlagerung

#pragma mark Regeln

static NSRegularExpression *svRegex( NSString *muster, BOOL ci)
{
    return [[NSRegularExpression alloc] initWithPattern: muster options: ci ? NSRegularExpressionCaseInsensitive : 0 error: nil];
}

static BOOL svTrifft( NSRegularExpression *re, NSString *s)
{
    return s.length && [re firstMatchInString: s options: 0 range: NSMakeRange( 0, s.length)] != nil;
}

// SekhVet Paket CS: the rule lives in SekhmetSequenz (+ctPhaseFuer:) so that the standalone unit test covers it.
// It now also takes "pre KM", "vor KM", "without contrast", "pre contrast" ... as native — they used to count as
// contrast, which gave the native series the chip "Contrast" and dropped the real contrast series from the suggestion.
+ (int) phaseFuer:(NSString*) beschreibung
{
    return [SekhmetSequenz ctPhaseFuer: beschreibung];
}

+ (BOOL) istKnochenkern:(NSString*) kernel beschreibung:(NSString*) beschreibung
{
    static NSRegularExpression *reKern = nil, *reName = nil;
    if( reKern == nil)
    {
        reKern = svRegex( @"^(BR|HR|UR|QR)?[6-9]\\d|^B[7-9]\\d|^FC8\\d|BONE|KNOCHEN|SHARP|EDGE|YB|YC", NO);
        reName = svRegex( @"(^|\\s)(KNOCHEN|BONE|KF)(\\s|$)", YES);
    }
    return svTrifft( reKern, [(kernel ?: @"") uppercaseString]) || svTrifft( reName, beschreibung ?: @"");
}

static int svRang( NSDictionary *s)
{
    int p = [SekhmetUeberlagerung phaseFuer: s[ @"desc"]];
    BOOL kn = [SekhmetUeberlagerung istKnochenkern: s[ @"kernel"] beschreibung: s[ @"desc"]];
    int phase = p == 1 ? 0 : p == 2 ? 1 : 2;
    return (kn ? 3 : 0) + phase;
}

static NSString *svRegion( NSString *d)
{
    static NSRegularExpression *reFuell = nil, *reKern = nil, *reZahl = nil, *reLeer = nil;
    if( reFuell == nil)
    {
        // SekhVet Paket CS: VOR, WITHOUT, SANS, PLAIN, UNENHANCED, KONTRASTMITTEL added — the phase rule knows them now,
        // and "Abdomen vor KM" / "Abdomen post KM" must stay one region.
        reFuell = svRegex( @"\\b(KM|CE|C|N|NATIV|NATIVE|POST|PRE|VOR|KONTRAST|KONTRASTMITTEL|CONTRAST|BONE|KNOCHEN|KF|WT|VOL|MIT|OHNE|WITH|WITHOUT|SANS|PLAIN|UNENHANCED|NO|NON|UND|AND)\\b", NO);
        reKern = svRegex( @"\\b[A-Z]{1,3}\\d+[A-Z]?\\b", NO);
        reZahl = svRegex( @"[\\d.,]+", NO);
        reLeer = svRegex( @"\\s+", NO);
    }
    NSString *s = [(d ?: @"") uppercaseString];
    s = [reFuell stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @" "];
    s = [reKern stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @" "];
    s = [reZahl stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @" "];
    s = [reLeer stringByReplacingMatchesInString: s options: 0 range: NSMakeRange( 0, s.length) withTemplate: @" "];
    return [s stringByTrimmingCharactersInSet: [NSCharacterSet whitespaceCharacterSet]];
}

static BOOL svGleicheEbene( NSDictionary *a, NSDictionary *b)
{
    NSArray *n = a[ @"normal"], *m = b[ @"normal"];
    if( n.count != 3 || m.count != 3) return YES;
    double d = [n[0] doubleValue] * [m[0] doubleValue] + [n[1] doubleValue] * [m[1] doubleValue] + [n[2] doubleValue] * [m[2] doubleValue];
    return fabs( d) >= 0.966;
}

static BOOL svIstTopogramm( NSString *beschreibung)
{
    static NSRegularExpression *reTopo = nil;
    if( reTopo == nil) reTopo = svRegex( @"TOPOGRAM|SCOUT|LOCALI[SZ]ER|SURVIEW|SCANOGRAM|ÜBERSICHT|UEBERSICHT|PROTOKOLL|DOSIS", YES);
    return svTrifft( reTopo, beschreibung);
}

+ (NSArray*) vorschlagAus:(NSArray*) alle aktuell:(NSDictionary*) aktuell
{

    NSMutableArray *kandidaten = [NSMutableArray array];
    for( NSDictionary *s in alle)
    {
        if( [s[ @"modality"] isEqualToString: aktuell[ @"modality"]] == NO) continue;
        if( [(s[ @"study"] ?: @"") isEqualToString: aktuell[ @"study"] ?: @""] == NO) continue;
        if( [s[ @"count"] intValue] < 10) continue;
        if( svIstTopogramm( s[ @"desc"])) continue;
        if( svGleicheEbene( s, aktuell) == NO) continue;
        [kandidaten addObject: s];
    }
    NSString *regionAktuell = svRegion( aktuell[ @"desc"]);
    NSMutableArray *gleicheRegion = [NSMutableArray array];
    for( NSDictionary *s in kandidaten) if( [svRegion( s[ @"desc"]) isEqualToString: regionAktuell]) [gleicheRegion addObject: s];
    NSArray *pool = gleicheRegion.count >= 2 ? gleicheRegion : kandidaten;
    NSArray *sortiert = [pool sortedArrayUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *b) {
        int ra = svRang( a), rb = svRang( b);
        if( ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        int na = [a[ @"number"] intValue], nb = [b[ @"number"] intValue];
        return na < nb ? NSOrderedAscending : na > nb ? NSOrderedDescending : NSOrderedSame;
    }];
    // Je Rang UND Region nur eine Serie: beim CT nehmen so nicht zwei "Nativ" derselben Region den Platz,
    // beim MRT (alles ohne Phase/Kern = ein Rang) bleiben T1/T2/GE derselben Ebene verschiedene Sequenzen.
    NSMutableSet *gesehen = [NSMutableSet set];
    NSMutableArray *aus = [NSMutableArray array];
    for( NSDictionary *s in sortiert)
    {
        NSString *r = [NSString stringWithFormat: @"%d|%@", svRang( s), svRegion( s[ @"desc"])];
        if( [gesehen containsObject: r] && [s[ @"uid"] isEqualToString: aktuell[ @"uid"]] == NO) continue;
        [gesehen addObject: r]; [aus addObject: s];
    }
    BOOL drin = NO;
    for( NSDictionary *s in aus) if( [s[ @"uid"] isEqualToString: aktuell[ @"uid"]]) drin = YES;
    if( drin == NO) [aus insertObject: aktuell atIndex: 0];
    return [aus subarrayWithRange: NSMakeRange( 0, MIN( aus.count, (NSUInteger) SEKHMET_STAPEL_MAX))];
}

#pragma mark Serien lesen

// Kern, Koerperregion und Schichtnormale der Serie aus dem Kopf EINER Datei (wie SekhmetWindowing), zwischengespeichert.
+ (NSDictionary*) infoFuerSerie:(DicomSeries*) s
{
    static NSMutableDictionary *cache = nil;
    if( cache == nil) cache = [[NSMutableDictionary alloc] init];
    NSString *uid = s.seriesInstanceUID ?: @"";
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[ @"uid"] = uid;
    d[ @"desc"] = s.name ?: @"";
    d[ @"modality"] = [(s.modality ?: @"") uppercaseString];
    d[ @"study"] = [s valueForKeyPath: @"study.studyInstanceUID"] ?: @"";
    d[ @"count"] = @( [[s valueForKey: @"images"] count]);
    d[ @"number"] = s.id ?: @0;
    d[ @"series"] = s;
    NSDictionary *kopf = uid.length ? [cache objectForKey: uid] : nil;
    if( kopf == nil)
    {
        NSMutableDictionary *k = [NSMutableDictionary dictionary];
        BOOL gelesen = NO;
        @try
        {
            DicomImage *img = [[s valueForKey: @"images"] anyObject];
            DCMObject *o = img ? [DCMObject objectWithContentsOfFile: [img valueForKey: @"completePath"] decodingPixelData: NO] : nil;
            gelesen = (o != nil);
            NSString *kern = [o attributeValueWithName: @"ConvolutionKernel"];
            NSString *teil = [o attributeValueWithName: @"BodyPartExamined"];
            if( kern.length) k[ @"kernel"] = kern;
            if( teil.length) k[ @"bodypart"] = teil;
            NSArray *iop = [[o attributeWithName: @"ImageOrientationPatient"] values];
            if( iop.count == 6)
            {
                double r[3] = { [iop[0] doubleValue], [iop[1] doubleValue], [iop[2] doubleValue] };
                double c[3] = { [iop[3] doubleValue], [iop[4] doubleValue], [iop[5] doubleValue] };
                double n[3]; svKreuz( r, c, n);
                k[ @"normal"] = @[ @(n[0]), @(n[1]), @(n[2])];
            }
        }
        @catch( NSException *e) { gelesen = NO; }
        // SekhVet Paket CS: keep only a header that was really read — a failed read (file still arriving, volume not
        // mounted) stayed cached as "no kernel" for the whole session; series without a UID all shared the key @"".
        if( gelesen && uid.length)
        {
            if( cache.count > 500) [cache removeAllObjects];
            [cache setObject: k forKey: uid];
        }
        kopf = k;
    }
    [d addEntriesFromDictionary: kopf];
    return d;
}

+ (NSString*) kurznameFuer:(NSDictionary*) info
{
    NSString *mod = info[ @"modality"];
    if( [mod isEqualToString: @"MR"])
    {
        BOOL km = NO, sub = NO;
        NSString *seq = [SekhmetSequenz kontrastFuer: info[ @"desc"] km: &km sub: &sub];
        if( seq.length) return km ? [NSString stringWithFormat: @"%@ %@", seq, NSLocalizedString( @"CM", @"contrast medium, short")] : seq;
        return [NSString stringWithFormat: @"S%@", info[ @"number"]];
    }
    int p = [self phaseFuer: info[ @"desc"]];
    BOOL kn = [self istKnochenkern: info[ @"kernel"] beschreibung: info[ @"desc"]];
    NSString *teil = p == 2 ? NSLocalizedString( @"Contrast", @"overlay chip") : p == 1 ? NSLocalizedString( @"Native", @"overlay chip") : nil;
    if( teil && kn) return [NSString stringWithFormat: @"%@ %@", teil, NSLocalizedString( @"bone", @"overlay chip: bone kernel")];
    if( teil) return teil;
    if( kn) return [NSString stringWithFormat: @"S%@ %@", info[ @"number"], NSLocalizedString( @"bone", nil)];
    return [NSString stringWithFormat: @"S%@", info[ @"number"]];
}

+ (NSArray*) vorschlagFuerViewer:(ViewerController*) v
{
    DicomSeries *aktuell = [v currentSeries];
    DicomStudy *studie = [v currentStudy];
    if( aktuell == nil || studie == nil) return @[];
    NSMutableArray *alle = [NSMutableArray array];
    for( id s in [[BrowserController currentBrowser] childrenArray: studie])
        if( [s isKindOfClass: [DicomSeries class]]) [alle addObject: [self infoFuerSerie: s]];
    NSArray *vorschlag = [self vorschlagAus: alle aktuell: [self infoFuerSerie: aktuell]];
    NSMutableArray *aus = [NSMutableArray array];
    for( NSDictionary *d in vorschlag) [aus addObject: d[ @"series"]];
    return aus;
}

#pragma mark Zustand

+ (SekhmetStapel*) stapelVon:(ViewerController*) v
{
    if( v == nil) return nil;
    SekhmetStapel *st = objc_getAssociatedObject( v, &SekhmetStapelKey);
    if( st == nil) return nil;
    // Horos hat die Daten ersetzt (andere Serie geladen, Fenster umgebaut) — dann ist der Stapel weg.
    // SekhVet Paket CS: the address of the first overlaid list is compared as well — one recycled address alone
    // (Horos swapped in a 4D set with the same count) must not pass as our stack.
    if( [v maxMovieIndex] != (short) st.count || (void*) [v pixList: 0] != st->refPixList || (void*) [v pixList: 1] != st->refPixList1)
    {
        objc_setAssociatedObject( v, &SekhmetStapelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    return st;
}

+ (BOOL) istGestapelt:(ViewerController*) v
{
    return [self stapelVon: v] != nil;
}

// SekhVet Paket CK: Der Knopf "Overlay" fand keinen Vorschlag und bleibt an — die naechste aufs Bild gezogene
// Serie wird ueberlagert. Gemerkt ist die Serie im Fenster: laedt Horos eine andere, verfaellt die Bereitschaft.
+ (BOOL) istBereit:(ViewerController*) v
{
    if( v == nil) return NO;
    NSString *uid = objc_getAssociatedObject( v, &SekhmetBereitKey);
    if( uid == nil) return NO;
    if( [uid isEqualToString: [[v currentSeries] seriesInstanceUID] ?: @""]) return YES;
    objc_setAssociatedObject( v, &SekhmetBereitKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return NO;
}

+ (void) setzeBereit:(BOOL) an viewer:(ViewerController*) v
{
    if( v == nil) return;
    objc_setAssociatedObject( v, &SekhmetBereitKey, an ? [[v currentSeries] seriesInstanceUID] : nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// Ein 3D-Fenster (MPR, VR, CPR, Ortho ...) haelt Zeiger auf die Volumendaten des Viewers. Alle erben von
// Window3DController (-viewer); andere Fenster (Serienliste, Navigator ...) duerfen den Stapel nicht sperren.
// SekhVet Paket CS: a window minimised to the Dock is not "visible" but still uses the volumes — ending the overlay
// freed them and restoring the MPR crashed. Minimised windows block now too. (A closed window that AppKit has not
// released yet is neither visible nor minimised and still does not block.)
+ (BOOL) dreiDFensterOffenFuer:(ViewerController*) v
{
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [Window3DController class]] && ([w isVisible] || [w isMiniaturized]) && [(Window3DController*) wc viewer] == v) return YES;
    }
    return NO;
}

#pragma mark Laden + Neuabtasten

// Liest eine Serie vollstaendig (eigener Puffer), sortiert nach Lage auf der Normalen.
// Rueckgabe: Pixel (DCMPix, geladen), passende DicomImages, Puffer, Lagen.
+ (BOOL) ladeSerie:(DicomSeries*) s pix:(NSMutableArray*) pixOut bilder:(NSMutableArray*) bilderOut daten:(NSData**) datenOut meldung:(NSString**) meldung
{
    NSArray *imgs = [s sortedImages];
    if( imgs.count < 2) { *meldung = NSLocalizedString( @"The series has fewer than two images.", nil); return NO; }
    long w = [[imgs[ 0] valueForKey: @"width"] intValue], h = [[imgs[ 0] valueForKey: @"height"] intValue];
    for( DicomImage *img in imgs)
    {
        if( [[img valueForKey: @"numberOfFrames"] intValue] > 1) { *meldung = NSLocalizedString( @"Multi-frame series cannot be overlaid yet.", nil); return NO; }
        if( [[img valueForKey: @"width"] intValue] != w || [[img valueForKey: @"height"] intValue] != h) { *meldung = NSLocalizedString( @"The images of the series differ in size.", nil); return NO; }
    }
    if( w <= 0 || h <= 0) { *meldung = NSLocalizedString( @"The series has no readable image size.", nil); return NO; }
    float *buf = malloc( (size_t) w * h * imgs.count * sizeof( float));
    if( buf == NULL) { *meldung = NSLocalizedString( @"Not enough memory for the overlay.", nil); return NO; }
    NSData *daten = [NSData dataWithBytesNoCopy: buf length: (size_t) w * h * imgs.count * sizeof( float) freeWhenDone: YES];
    NSMutableArray *paare = [NSMutableArray array];
    for( NSUInteger i = 0; i < imgs.count; i++)
    {
        DicomImage *img = imgs[ i];
        DCMPix *p = [[[DCMPix alloc] initWithPath: [img valueForKey: @"completePath"] :i :imgs.count :buf + (long) i * w * h :[[img valueForKey: @"frameID"] intValue] :[[img valueForKeyPath: @"series.id"] intValue] isBonjour: NO imageObj: img] autorelease];
        if( p == nil) { *meldung = [NSString stringWithFormat: NSLocalizedString( @"Image %lu of the series is not readable.", nil), (unsigned long) i + 1]; return NO; }
        [p CheckLoad];
        if( p.pwidth != w || p.pheight != h || p.fImage == NULL) { *meldung = NSLocalizedString( @"An image of the series could not be loaded.", nil); return NO; }
        // SekhVet Paket CS: RGB pixels are ARGB bytes, not floats — the resampler must never see them
        if( p.isRGB) { *meldung = NSLocalizedString( @"Colour (RGB) series cannot be overlaid.", nil); return NO; }
        [paare addObject: @[ p, img]];
    }
    double o[3], r[3], c[3], n[3];
    svGeometrie( paare[ 0][ 0], o, r, c, n);
    double n0 = n[ 0], n1 = n[ 1], n2 = n[ 2];   // Bloecke duerfen keine C-Arrays einfangen
    NSArray *sortiert = [paare sortedArrayUsingComparator: ^NSComparisonResult( NSArray *a, NSArray *b) {
        double oa[3], ob[3], x[3], y[3], z[3], nn[3] = { n0, n1, n2 };
        svGeometrie( a[ 0], oa, x, y, z); svGeometrie( b[ 0], ob, x, y, z);
        double la = svDot( oa, nn), lb = svDot( ob, nn);
        return la < lb ? NSOrderedAscending : la > lb ? NSOrderedDescending : NSOrderedSame;
    }];
    for( NSArray *pr in sortiert) { [pixOut addObject: pr[ 0]]; [bilderOut addObject: pr[ 1]]; }
    *datenOut = daten;
    return YES;
}

// SekhVet Paket CS: the reference (the series in the window) must be ONE regular block — every slice the same size,
// pixel spacing and row/column direction. tasteAb: takes all of that from slice 0 and the buffer is w*h*count of
// slice 0; a localizer with several planes, a radial series or mixed image sizes would be resampled wrongly or
// written past the buffer. Returns nil if the grid is fine, otherwise the message for the user.
+ (NSString*) mangelAmBezugsgitter:(NSArray*) zielPix
{
    if( zielPix.count == 0) return NSLocalizedString( @"The series in this window has no images.", nil);
    DCMPix *p0 = zielPix[ 0];
    if( p0.isRGB) return NSLocalizedString( @"Overlay needs greyscale CT or MR images; the series in this window is a colour (RGB) series.", nil);
    double o[3], r0[3], c0[3];
    svGeometrie( p0, o, r0, c0, NULL);
    long w = p0.pwidth, h = p0.pheight;
    if( w <= 0 || h <= 0) return NSLocalizedString( @"The series in this window has no readable image size.", nil);
    for( DCMPix *p in zielPix)
    {
        double r[3], c[3];
        svGeometrie( p, o, r, c, NULL);
        if( p.isRGB || p.pwidth != w || p.pheight != h || fabs( p.pixelSpacingX - p0.pixelSpacingX) > 1e-4 || fabs( p.pixelSpacingY - p0.pixelSpacingY) > 1e-4)
            return NSLocalizedString( @"The series in this window cannot be the base of an overlay: its images differ in size or pixel spacing.", nil);
        if( svDot( r, r0) < 0.9999 || svDot( c, c0) < 0.9999)
            return NSLocalizedString( @"The series in this window cannot be the base of an overlay: its slices are not parallel (for example a localizer with several planes or a radial series).", nil);
    }
    return nil;
}

// Tastet die geladene Quellserie auf die Zielschichten ab. Rueckgabe NO + Meldung, wenn die Quelle nicht passt.
+ (BOOL) tasteAb:(NSArray*) quellPix auf:(NSArray*) zielPix nach:(float*) ziel fuell:(float) fuell naechste:(NSMutableArray*) naechsteOut meldung:(NSString**) meldung
{
    int ns = (int) quellPix.count;
    DCMPix *q0 = quellPix[ 0];
    SVQuelle q;
    memset( &q, 0, sizeof q);
    double o0[3], r[3], c[3], n[3];
    svGeometrie( q0, o0, r, c, n);
    memcpy( q.o0, o0, sizeof o0); memcpy( q.r, r, sizeof r); memcpy( q.c, c, sizeof c); memcpy( q.n, n, sizeof n);
    q.sx = q0.pixelSpacingX > 0 ? q0.pixelSpacingX : 1; q.sy = q0.pixelSpacingY > 0 ? q0.pixelSpacingY : 1;
    q.w = (int) q0.pwidth; q.h = (int) q0.pheight; q.ns = ns;
    const float **img = malloc( ns * sizeof( float*));
    double *pos = malloc( ns * sizeof( double)), *su = malloc( ns * sizeof( double)), *sv = malloc( ns * sizeof( double));
    BOOL passt = YES;
    for( int j = 0; j < ns; j++)
    {
        DCMPix *p = quellPix[ j];
        double o[3], rr[3], cc[3], nn[3];
        svGeometrie( p, o, rr, cc, nn);
        if( svDot( rr, r) < 0.9999 || svDot( cc, c) < 0.9999 || fabs( p.pixelSpacingX - q0.pixelSpacingX) > 1e-4 || fabs( p.pixelSpacingY - q0.pixelSpacingY) > 1e-4) passt = NO;
        double d[3] = { o[0] - o0[0], o[1] - o0[1], o[2] - o0[2] };
        pos[ j] = svDot( d, n); su[ j] = svDot( d, r) / q.sx; sv[ j] = svDot( d, c) / q.sy;
        img[ j] = p.fImage;
    }
    // mittlerer Schichtabstand -> Toleranz an den Enden (halber Abstand)
    q.tolz = ns > 1 ? 0.5 * fabs( pos[ ns - 1] - pos[ 0]) / (ns - 1) : 0.5;
    if( q.tolz < 1e-3) q.tolz = 0.5 * MAX( q0.sliceThickness, 0.1);
    for( int j = 1; j < ns; j++) if( pos[ j] - pos[ j - 1] < 1e-4) passt = NO;   // doppelte Schichten
    q.img = img; q.pos = pos; q.shiftU = su; q.shiftV = sv;
    if( passt == NO)
    {
        free( img); free( pos); free( su); free( sv);
        *meldung = NSLocalizedString( @"The slices of the series are not parallel, not evenly sized or contain duplicates.", nil);
        return NO;
    }
    // SekhVet Paket CS: size, spacing AND row/column direction come from reference slice 0 (the direction used to be
    // whatever the last slice had); staple: refuses a reference where they are not the same for every slice.
    NSString *mangel = [self mangelAmBezugsgitter: zielPix];
    if( mangel)
    {
        free( img); free( pos); free( su); free( sv);
        *meldung = mangel;
        return NO;
    }
    NSUInteger nz = zielPix.count;
    DCMPix *z0 = zielPix[ 0];
    long dw = z0.pwidth, dh = z0.pheight;
    double *zo = malloc( nz * 3 * sizeof( double)), zr[3], zc[3], zo0[3];
    svGeometrie( z0, zo0, zr, zc, NULL);
    double dsx = z0.pixelSpacingX > 0 ? z0.pixelSpacingX : 1, dsy = z0.pixelSpacingY > 0 ? z0.pixelSpacingY : 1;
    int *naechste = malloc( nz * sizeof( int));
    for( NSUInteger i = 0; i < nz; i++)
    {
        double o[3], ri[3], ci[3];
        svGeometrie( zielPix[ i], o, ri, ci, NULL);
        memcpy( zo + 3 * i, o, sizeof o);
        // naechste Quellschicht zur Bildmitte (fuer fileList: die KM-Serie zeigt ihre eigenen Bilder)
        double m[3] = { o[0] + zr[0] * dsx * dw / 2 + zc[0] * dsy * dh / 2 - o0[0], o[1] + zr[1] * dsx * dw / 2 + zc[1] * dsy * dh / 2 - o0[1], o[2] + zr[2] * dsx * dw / 2 + zc[2] * dsy * dh / 2 - o0[2] };
        double z = svDot( m, n);
        int best = 0; double bd = DBL_MAX;
        for( int j = 0; j < ns; j++) { double dd = fabs( pos[ j] - z); if( dd < bd) { bd = dd; best = j; } }
        naechste[ i] = best;
    }
    double *zrc = malloc( 6 * sizeof( double)), *zcc = zrc + 3;   // Bloecke duerfen keine C-Arrays einfangen
    memcpy( zrc, zr, sizeof zr); memcpy( zcc, zc, sizeof zc);
    SVQuelle *qp = &q;
    dispatch_apply( nz, dispatch_get_global_queue( DISPATCH_QUEUE_PRIORITY_HIGH, 0), ^( size_t i) {
        svResampleSlice( qp, zo + 3 * i, zrc, zcc, dsx, dsy, (int) dw, (int) dh, ziel + (long) i * dw * dh, fuell);
    });
    for( NSUInteger i = 0; i < nz; i++) [naechsteOut addObject: @( naechste[ i])];
    free( zrc); free( naechste); free( zo); free( img); free( pos); free( su); free( sv);
    return YES;
}

#pragma mark Stapeln

+ (NSDictionary*) fensterFuerInfo:(NSDictionary*) info studie:(NSString*) studienName ersatz:(DCMPix*) p
{
    NSMutableString *desc = [NSMutableString stringWithString: studienName ?: @""];
    [desc appendFormat: @" %@", info[ @"desc"] ?: @""];
    if( [info[ @"bodypart"] length]) [desc appendFormat: @" %@", info[ @"bodypart"]];
    // SekhVet Paket CS: kernel on its own, so that a body part is not taken for a kernel
    NSDictionary *regel = [SekhmetWindowing ruleForModality: info[ @"modality"] kernel: info[ @"kernel"] description: desc];
    if( regel[ @"ww"] && [regel[ @"ww"] floatValue] > 0) return @{ @"wl": @( [regel[ @"wl"] floatValue]), @"ww": @( [regel[ @"ww"] floatValue]) };
    if( p && p.savedWW > 0) return @{ @"wl": @( p.savedWL), @"ww": @( p.savedWW) };
    return nil;
}

// SekhVet Paket CS: -[ViewerController loadROI:] skips "generated" images, so the measurements saved with an overlaid
// series are NOT loaded while it is overlaid (the "(N hidden)" hint counted the loaded ones and was therefore always 0).
// Count what is saved instead: the ROI SR images of the study carry "<sopInstanceUID>-<frameID>" of their image as
// comment (DicomStudy roiForImage:inArray:). Read-only — nothing is merged, deleted or loaded into the viewer.
+ (NSUInteger) gespeicherteMessungenVon:(NSArray*) bilder
{
    if( bilder.count == 0 || [[NSUserDefaults standardUserDefaults] boolForKey: @"SAVEROIS"] == NO) return 0;
    NSUInteger n = 0;
    DicomStudy *studie = [bilder[ 0] valueForKeyPath: @"series.study"];
    NSManagedObjectContext *ctx = [studie managedObjectContext];
    [ctx lock];
    @try
    {
        NSMutableDictionary *srFuer = [NSMutableDictionary dictionary];
        for( DicomImage *sr in [[[studie roiSRSeries] valueForKey: @"images"] allObjects])
        {
            NSString *k = [sr valueForKey: @"comment"];
            if( k.length == 0) continue;
            DicomImage *schon = srFuer[ k];
            NSDate *neuer = [sr valueForKey: @"date"], *alt = [schon valueForKey: @"date"];
            if( schon == nil || (neuer && alt && [neuer compare: alt] == NSOrderedDescending)) srFuer[ k] = sr;   // the most recent, as Horos
        }
        if( srFuer.count)
            for( DicomImage *img in bilder)
            {
                NSString *k = [NSString stringWithFormat: @"%@-%d", [img valueForKey: @"sopInstanceUID"], [[img valueForKey: @"frameID"] intValue]];
                NSString *pfad = [srFuer[ k] valueForKey: @"completePathResolved"];
                if( pfad.length == 0) continue;
                NSData *data = [SRAnnotation roiFromDICOM: pfad];
                NSArray *rois = data ? [SekhmetRestrictedUnarchiver unarchiveROIsWithData: data] : nil; // Sekhmet (DE)
                if( [rois isKindOfClass: [NSArray class]]) n += rois.count;
            }
    }
    @catch( NSException *e) { NSLog( @"SekhVet Overlay: counting the saved measurements failed: %@", e); }
    @finally { [ctx unlock]; }
    return n;
}

// Haengt EINE Serie als neuen Movie-Eintrag an den Viewer. Die Bezugsserie ist pixList[0].
+ (BOOL) haengeAn:(DicomSeries*) s info:(NSDictionary*) info viewer:(ViewerController*) v stapel:(SekhmetStapel*) st meldung:(NSString**) meldung
{
    NSArray *ziel = [v pixList: 0];
    DCMPix *ref = ziel[ 0];
    NSMutableArray *qpix = [NSMutableArray array], *qbilder = [NSMutableArray array];
    NSData *qdaten = nil;
    if( [self ladeSerie: s pix: qpix bilder: qbilder daten: &qdaten meldung: meldung] == NO) return NO;
    NSString *forRef = ref.frameofReferenceUID, *forQ = [qpix[ 0] frameofReferenceUID];
    if( forRef.length == 0 || forQ.length == 0 || [forRef isEqualToString: forQ] == NO)
    {
        *meldung = [NSString stringWithFormat: NSLocalizedString( @"\"%@\" has a different frame of reference (patient repositioned or another session). Overlaying it would show slices that only look aligned.", nil), s.name];
        return NO;
    }
    long w = ref.pwidth, h = ref.pheight;
    float *buf = malloc( (size_t) w * h * ziel.count * sizeof( float));
    if( buf == NULL) { *meldung = NSLocalizedString( @"Not enough memory for the overlay.", nil); return NO; }
    NSData *daten = [[[NSData alloc] initWithBytesNoCopy: buf length: (size_t) w * h * ziel.count * sizeof( float) freeWhenDone: YES] autorelease];
    float fuell = [[ref modalityString] isEqualToString: @"CT"] ? -1024.f : 0.f;
    NSMutableArray *naechste = [NSMutableArray array];
    if( [self tasteAb: qpix auf: ziel nach: buf fuell: fuell naechste: naechste meldung: meldung] == NO) return NO;

    NSDictionary *fenster = [self fensterFuerInfo: info studie: [[v currentStudy] valueForKey: @"studyName"] ersatz: qpix[ 0]];
    NSMutableArray *neuPix = [NSMutableArray arrayWithCapacity: ziel.count], *neuDateien = [NSMutableArray arrayWithCapacity: ziel.count];
    for( NSUInteger i = 0; i < ziel.count; i++)
    {
        DCMPix *zp = ziel[ i];
        DCMPix *kopie = [[zp copy] autorelease];     // Geometrie der Bezugsschicht, "generated" = YES
        [kopie freefImageWhenDone: NO];              // der geteilte Zeiger gehoert nicht der Kopie ...
        [kopie setfImage: buf + (long) i * w * h];   // ... und der neue auch nicht (NSData gibt ihn frei)
        DCMPix *nah = qpix[ [naechste[ i] intValue]];
        if( nah.annotationsDictionary) kopie.annotationsDictionary = nah.annotationsDictionary;
        if( nah.annotationsDBFields) kopie.annotationsDBFields = nah.annotationsDBFields;
        if( fenster) { kopie.savedWL = [fenster[ @"wl"] floatValue]; kopie.savedWW = [fenster[ @"ww"] floatValue]; }
        [kopie computePixMinPixMax];
        [neuPix addObject: kopie];
        [neuDateien addObject: qbilder[ [naechste[ i] intValue]]];
    }
    int m = [v maxMovieIndex];
    [v addMovieSerie: neuPix : neuDateien : daten];
    // SekhVet Paket CS: Horos loads no measurements for generated images (the list of movie entry m is empty) — the
    // saved measurements of this series are counted from the database for the "(N hidden)" hint on its chip.
    NSUInteger eigene = [self gespeicherteMessungenVon: qbilder];
    [v sekhmetUeberlagerungTeileROIs: m];

    [st->namen addObject: [self eindeutig: [self kurznameFuer: info] in: st->namen]];
    [st->serienNamen addObject: s.name ?: @""];
    [st->serienUIDs addObject: info[ @"uid"]];
    [st->phasen addObject: @( [self phaseFuer: info[ @"desc"]])];
    [st->knochen addObject: @( [self istKnochenkern: info[ @"kernel"] beschreibung: info[ @"desc"]])];
    BOOL km = NO, sub = NO;
    NSString *seq = [SekhmetSequenz kontrastFuer: info[ @"desc"] km: &km sub: &sub];
    [st->sequenzen addObject: seq ?: (id) [NSNull null]];
    [st->mrKM addObject: @( km)];
    [st->fenster addObject: fenster ?: (id) [NSNull null]];
    [st->versteckt addObject: @( eigene)];
    [st->aus addObject: @NO];
    return YES;
}

+ (void) eintragFuerBezug:(SekhmetStapel*) st viewer:(ViewerController*) v info:(NSDictionary*) info
{
    [st->namen addObject: [self kurznameFuer: info]];
    [st->serienNamen addObject: info[ @"desc"] ?: @""];
    [st->serienUIDs addObject: info[ @"uid"]];
    [st->phasen addObject: @( [self phaseFuer: info[ @"desc"]])];
    [st->knochen addObject: @( [self istKnochenkern: info[ @"kernel"] beschreibung: info[ @"desc"]])];
    BOOL km = NO, sub = NO;
    NSString *seq = [SekhmetSequenz kontrastFuer: info[ @"desc"] km: &km sub: &sub];
    [st->sequenzen addObject: seq ?: (id) [NSNull null]];
    [st->mrKM addObject: @( km)];
    float wl = 0, ww = 0;
    [[v imageView] getWLWW: &wl :&ww];
    [st->fenster addObject: @{ @"wl": @( wl), @"ww": @( ww)}];
    [st->versteckt addObject: @0];
    [st->aus addObject: @NO];
}

+ (void) ordneStapel:(SekhmetStapel*) st
{
    NSMutableArray *idx = [NSMutableArray array];
    for( NSUInteger i = 0; i < st.count; i++) [idx addObject: @( i)];
    [idx sortUsingComparator: ^NSComparisonResult( NSNumber *a, NSNumber *b) {
        int ia = a.intValue, ib = b.intValue;
        int pa = [st->phasen[ ia] intValue], pb = [st->phasen[ ib] intValue];
        int ra = ([st->knochen[ ia] boolValue] ? 3 : 0) + (pa == 1 ? 0 : pa == 2 ? 1 : 2);
        int rb = ([st->knochen[ ib] boolValue] ? 3 : 0) + (pb == 1 ? 0 : pb == 2 ? 1 : 2);
        if( [st->modalitaet isEqualToString: @"MR"]) ra = rb = 0;   // MRT: Reihenfolge der Serien
        if( ra != rb) return ra < rb ? NSOrderedAscending : NSOrderedDescending;
        return ia < ib ? NSOrderedAscending : ia > ib ? NSOrderedDescending : NSOrderedSame;
    }];
    [st->reihenfolge setArray: idx];
}

// gleiche Kurznamen unterscheiden (z. B. zwei "S…"-Serien derselben Gewichtung)
+ (NSString*) eindeutig:(NSString*) n in:(NSArray*) liste
{
    if( [liste containsObject: n] == NO) return n;
    return [NSString stringWithFormat: @"%@ (%lu)", n, (unsigned long) liste.count + 1];
}

// SekhVet Paket CS: the overlay resamples float pixels of CT and MR (fill value, phase/sequence rules).
static BOOL svStapelbar( NSString *modalitaet)
{
    return [modalitaet isEqualToString: @"CT"] || [modalitaet isEqualToString: @"MR"];
}

+ (BOOL) staple:(NSArray*) serien inViewer:(ViewerController*) v meldung:(NSString**) meldung
{
    NSString *dummy = nil;
    if( meldung == NULL) meldung = &dummy;
    if( [v is2DViewer] == NO) { *meldung = NSLocalizedString( @"Overlay works in the 2D viewer.", nil); return NO; }
    if( [v isEverythingLoaded] == NO) { *meldung = NSLocalizedString( @"The series is still loading. Try again in a moment.", nil); return NO; }
    if( [self dreiDFensterOffenFuer: v])
    {
        // SekhVet Paket DA: an open MPR is closed, the series are stacked, and the MPR reopens in the same position
        NSArray *spaeter = [[serien copy] autorelease];
        BOOL geplant = [self mitMPRNeuaufbau: v aktion: ^{
            NSString *m = nil;
            BOOL gestapelt = [self staple: spaeter inViewer: v meldung: &m];
            if( gestapelt) [self setzeBereit: NO viewer: v];
            if( gestapelt == NO || m.length) NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), @"%@", NSLocalizedString( @"OK", nil), nil, nil, m ?: @"");
        }];
        if( geplant) { *meldung = nil; return YES; }
        *meldung = NSLocalizedString( @"Close the 3D windows (MPR, VR …) of this series first, then overlay.", nil);
        return NO;
    }
    // SekhVet Paket CS: hold the stack for this call — if anything below makes stapelVon: drop it (count mismatch
    // between addMovieSerie and our own appends), st must not be freed under us. It is re-attached at the end.
    SekhmetStapel *st = [[[self stapelVon: v] retain] autorelease];
    if( st == nil && [v maxMovieIndex] > 1) { *meldung = NSLocalizedString( @"This window already shows a 4D series.", nil); return NO; }
    // SekhVet Paket CS: only the drag path checked the modality; the reference grid was never checked at all.
    if( svStapelbar( st ? st->modalitaet : [[[v currentSeries] modality] uppercaseString]) == NO) { *meldung = NSLocalizedString( @"Overlay is available for CT and MR series.", nil); return NO; }
    NSString *mangel = [self mangelAmBezugsgitter: [v pixList: 0]];
    if( mangel) { *meldung = mangel; return NO; }

    BOOL neu = (st == nil);
    if( neu)
    {
        st = [[[SekhmetStapel alloc] init] autorelease];
        NSDictionary *bezug = [self infoFuerSerie: [v currentSeries]];
        st->modalitaet = [bezug[ @"modality"] retain];
        st->gezeigt = [v curMovieIndex];
        st->richtung = 1;
        [self eintragFuerBezug: st viewer: v info: bezug];
    }
    NSMutableArray *dazu = [NSMutableArray array];
    for( DicomSeries *s in serien)
    {
        NSString *uid = s.seriesInstanceUID ?: @"";
        if( [st->serienUIDs containsObject: uid]) continue;
        if( st.count + dazu.count >= SEKHMET_STAPEL_MAX) break;
        [dazu addObject: s];
    }
    if( dazu.count == 0)
    {
        *meldung = st.count >= SEKHMET_STAPEL_MAX ? NSLocalizedString( @"An overlay holds at most four series.", nil) : NSLocalizedString( @"No other series of this study matches for an overlay (same modality, at least 10 images, same region and plane).", nil);
        return NO;
    }

    WaitRendering *warte = [[WaitRendering alloc] init: NSLocalizedString( @"Preparing overlay…", nil)];
    [warte showWindow: nil];
    NSDate *start = [NSDate date];
    NSMutableArray *fehler = [NSMutableArray array];
    for( DicomSeries *s in dazu)
    {
        NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
        NSString *m = nil;
        if( [self haengeAn: s info: [self infoFuerSerie: s] viewer: v stapel: st meldung: &m] == NO && m) [fehler addObject: [m retain]];
        [pool release];
    }
    for( NSString *f in fehler) [f autorelease];
    [warte close];
    [warte autorelease];
    NSLog( @"SekhVet Overlay: %lu series in %.1f s, %lu refused", (unsigned long) st.count, -[start timeIntervalSinceNow], (unsigned long) fehler.count);

    if( st.count < 2)
    {
        *meldung = fehler.count ? [fehler componentsJoinedByString: @"\n"] : NSLocalizedString( @"No series could be added.", nil);
        return NO;
    }
    st->refPixList = (void*) [v pixList: 0];
    st->refPixList1 = (void*) [v pixList: 1];
    st->generation = ++svGeneration;
    [self ordneStapel: st];
    objc_setAssociatedObject( v, &SekhmetStapelKey, st, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if( neu)
    {
        // SekhVet Paket CS: the overlaid images are copies of the reference slices and keep ITS source file. Horos'
        // "Revert" (also behind DICOM overlays on/off, Apply LUT, SUV off, the VR's revert) reloads every movie entry
        // from that file — all chips then showed the reference pixels, the enhancement line read Δ 0. Horos protects
        // generated 4D data with the viewer's "postprocessed" flag (revertSeries: refuses with a message); we do the
        // same while stacked. Side effects of the flag: key images cannot be set or browsed, and zoom/offset/flip/
        // rotation are not written back to the series while stacked. beende: restores the previous value.
        st->warPostprocessed = [v isPostprocessed];
        [v setPostprocessed: YES];
        [v adjustKeyImage];
    }
    [v sekhmetUeberlagerungSperre4DBedienung];   // SekhVet Paket CS: addMovieSerie: enabled Horos' 4D slider and Play
    [self aktualisiereToolbar: v];
    [v setWindowTitle: self];
    [[v imageView] setNeedsDisplay: YES];
    if( fehler.count) *meldung = [fehler componentsJoinedByString: @"\n"];
    return YES;
}

+ (void) beende:(ViewerController*) v
{
    if( [self stapelVon: v] == nil) return;
    if( [self dreiDFensterOffenFuer: v] && [self mitMPRNeuaufbau: v aktion: ^{ [self beende: v]; }]) return;   // SekhVet Paket DA
    if( [self dreiDFensterOffenFuer: v])
    {
        NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), NSLocalizedString( @"Close the 3D windows (MPR, VR …) of this series first, then end the overlay.", nil), NSLocalizedString( @"OK", nil), nil, nil);
        return;
    }
    SekhmetStapel *st = [[[self stapelVon: v] retain] autorelease];   // SekhVet Paket CS: held — it is used after the viewer lost its movie entries
    [self merkeFenster: v stapel: st];
    st->gezeigt = 0;
    [v sekhmetUeberlagerungEntferneAb: 1];
    NSDictionary *f = [st->fenster firstObject];
    if( [f isKindOfClass: [NSDictionary class]]) [[v imageView] setWLWW: [f[ @"wl"] floatValue] :[f[ @"ww"] floatValue]];
    objc_setAssociatedObject( v, &SekhmetStapelKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    // SekhVet Paket CS: "postprocessed" was set by staple: (Revert guard) — back to what the viewer had before
    [v setPostprocessed: st->warPostprocessed];
    [v adjustKeyImage];
    [self rechneROIsNeu: v];
    [self aktualisiereToolbar: v];
    [v setWindowTitle: self];
    [v matrixPreviewSelectCurrentSeries];   // Paket CO: in der Serienleiste blieben sonst alle Stapelserien markiert
}

#pragma mark Umschalten

+ (void) merkeFenster:(ViewerController*) v stapel:(SekhmetStapel*) st
{
    NSInteger cm = [v curMovieIndex];
    if( cm < 0 || cm >= (NSInteger) st.count) return;
    float wl = 0, ww = 0;
    [[v imageView] getWLWW: &wl :&ww];
    if( ww > 0) st->fenster[ cm] = @{ @"wl": @( wl), @"ww": @( ww)};
}

// Paket CN: Eine ROI merkt sich das DCMPix, auf dem sie gezeichnet wurde, und rechnet Mittelwert/SD immer daraus —
// im Stapel (geteilte Liste) blieb der Wert deshalb beim Umschalten stehen. Jetzt gilt das Pixel der sichtbaren Serie;
// nach dem Beenden wieder das der Bezugsserie (die neu abgetasteten Puffer sind dann freigegeben).
+ (void) rechneROIsNeu:(ViewerController*) v
{
    NSInteger cm = [v curMovieIndex];
    if( cm < 0 || cm >= [v maxMovieIndex]) cm = 0;
    NSArray *pl = [v pixList: cm], *rl = [v roiList: 0];
    for( NSUInteger i = 0; i < rl.count; i++)
        for( ROI *r in rl[ i])
        {
            if( i < pl.count) r.pix = pl[ i];
            [r recompute];
        }
    for( DCMView *iv in [v imageViews]) [iv setNeedsDisplay: YES];
}

+ (void) zeige:(NSInteger) movieIndex inViewer:(ViewerController*) v
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil || movieIndex < 0 || movieIndex >= (NSInteger) st.count || movieIndex == [v curMovieIndex]) return;
    [self merkeFenster: v stapel: st];
    st->gezeigt = movieIndex;   // SekhVet Paket CS: before the switch, so that folgeFremdemWechsel: knows it is ours
    [v setMovieIndex: movieIndex];
    NSDictionary *f = st->fenster[ movieIndex];
    if( [f isKindOfClass: [NSDictionary class]] && [f[ @"ww"] floatValue] > 0)
        [[v imageView] setWLWW: [f[ @"wl"] floatValue] :[f[ @"ww"] floatValue]];
    [self rechneROIsNeu: v];
    [self aktualisiereToolbar: v];
}

// SekhVet Paket CS: Horos has its own ways to change the movie index that never pass zeige: — arrow up/down,
// Option + scroll wheel, a click on a stacked series in the series list, "propagate settings" from another viewer,
// the 4D export. All of them end in -setMovieIndex:, which calls -setWindowTitle:, which calls aktualisiereToolbar:.
// From there this method gives the series that is now visible its own window and lets the ROIs compute on it
// (before: WL/WW and ROI mean/SD stayed from the previous series). The window of the series that was left is not
// stored on this path. A deselected series is left again on the next run-loop turn (verlasseAbgewaehlte:).
+ (void) folgeFremdemWechsel:(ViewerController*) v stapel:(SekhmetStapel*) st
{
    NSInteger cm = [v curMovieIndex], n = st.count;
    if( cm == st->gezeigt || cm < 0 || cm >= n) return;
    st->richtung = (cm == (st->gezeigt + 1) % n) ? 1 : -1;
    st->gezeigt = cm;
    NSDictionary *f = st->fenster[ cm];
    if( [f isKindOfClass: [NSDictionary class]] && [f[ @"ww"] floatValue] > 0)
        [[v imageView] setWLWW: [f[ @"wl"] floatValue] :[f[ @"ww"] floatValue]];
    [self rechneROIsNeu: v];
    if( [st->aus[ cm] boolValue])
    {
        [NSObject cancelPreviousPerformRequestsWithTarget: self selector: @selector(verlasseAbgewaehlte:) object: v];
        [self performSelector: @selector(verlasseAbgewaehlte:) withObject: v afterDelay: 0];
    }
}

+ (void) verlasseAbgewaehlte:(ViewerController*) v
{
    if( [v windowWillClose]) return;
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil) return;
    NSInteger cm = [v curMovieIndex], n = st.count;
    if( cm < 0 || cm >= n || [st->aus[ cm] boolValue] == NO) return;
    NSInteger z = cm;
    for( NSInteger k = 0; k < n; k++)   // the reference series (0) is never deselected, so this ends on a visible one
    {
        z = (z + st->richtung + n) % n;
        if( [st->aus[ z] boolValue] == NO) break;
    }
    if( z != cm) [self zeigeSerie: z viewer: v];
}

// Paket CN: Movie-Indizes in Rangfolge ohne die abgewaehlten — so stehen die Chips, so schalten die Tasten.
+ (NSArray*) sichtbar:(SekhmetStapel*) st
{
    NSMutableArray *a = [NSMutableArray array];
    for( NSNumber *m in st->reihenfolge) if( [st->aus[ m.intValue] boolValue] == NO) [a addObject: m];
    return a;
}

+ (NSInteger) nachbarVon:(NSInteger) aktuell schritt:(int) schritt stapel:(SekhmetStapel*) st
{
    NSArray *s = [self sichtbar: st];
    NSInteger n = s.count;
    if( n == 0) return aktuell;
    NSUInteger pos = [s indexOfObject: @( aktuell)];
    if( pos == NSNotFound) return [s[ 0] integerValue];
    return [s[ ((NSInteger) pos + schritt % n + n) % n] integerValue];
}

+ (void) schalte:(ViewerController*) v schritt:(int) schritt
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil) return;
    [self zeigeSerie: [self nachbarVon: [v curMovieIndex] schritt: schritt stapel: st] viewer: v];   // ein offenes MPR schaltet mit
}

+ (MPRController*) mprFuer:(ViewerController*) v
{
    for( NSWindow *w in [NSApp windows])
    {
        id wc = [w windowController];
        if( [wc isKindOfClass: [MPRController class]] == NO || [w isVisible] == NO) continue;
        ViewerController *x = nil;
        @try { x = [wc valueForKey: @"viewer2D"]; } @catch( NSException *e) { x = nil; }
        if( x == v) return wc;
    }
    return nil;
}

#pragma mark MPR neu aufbauen (Paket DA)

// SekhVet Paket DA (02.10.2026: "Overlay-Funktion auch im MPR aktivieren und dort auswaehlen, welche Serien").
// The MPR holds the viewer's movie entries without retaining them and cannot take new ones; Horos builds them into the
// MPR when it opens. So stacking or ending with an open MPR closes the MPR first (after the click that asked for it has
// returned), changes the stack in the 2D viewer one run-loop turn later, when the closed controller has let go, and
// opens the MPR again with the same cameras, crosshair angles, window frame and focus.
// NO = no visible MPR of this viewer (the caller refuses as before, e.g. for a VR window or a minimised MPR).
+ (NSDictionary*) zustandVon:(MPRController*) mpr
{
    NSMutableDictionary *z = [NSMutableDictionary dictionary];
    NSArray *views = nil;
    @try { views = [mpr sekhmetCurrentViews]; } @catch( NSException *e) { views = nil; }
    if( views) [z setObject: views forKey: @"views"];
    [z setObject: [NSValue valueWithRect: [[mpr window] frame]] forKey: @"frame"];
    [z setObject: [NSNumber numberWithBool: [[mpr window] isKeyWindow]] forKey: @"key"];
    return z;
}

+ (BOOL) mitMPRNeuaufbau:(ViewerController*) v aktion:(void (^)(void)) aktion
{
    MPRController *mpr = [self mprFuer: v];
    if( mpr == nil || [mpr windowWillClose]) return NO;
    void (^danach)(void) = [[aktion copy] autorelease];
    dispatch_async( dispatch_get_main_queue(), ^{
        MPRController *m = [self mprFuer: v];
        if( m == nil || [v windowWillClose]) return;
        NSDictionary *z = [[self zustandVon: m] retain];
        NSLog( @"SekhVet Overlay: MPR closed for the overlay change, reopened afterwards");
        [[m window] close];
        dispatch_after( dispatch_time( DISPATCH_TIME_NOW, (int64_t) (0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if( [v windowWillClose] == NO)
            {
                danach();
                [self oeffneMPRWieder: v zustand: z];
            }
            [z release];
        });
    });
    return YES;
}

+ (void) oeffneMPRWieder:(ViewerController*) v zustand:(NSDictionary*) z
{
    if( [v windowWillClose] || [[v window] isVisible] == NO) return;
    NSInteger ziel = [v curMovieIndex];
    // the MPR opens on movie entry 0 with the 2D window/level - so show entry 0 first, then switch both together;
    // otherwise the window of the visible series would be remembered as the window of entry 0
    if( [self stapelVon: v] && ziel != 0) [self zeigeSerie: 0 viewer: v];
    [v mprViewer: nil];
    MPRController *mpr = [self mprFuer: v];
    if( mpr == nil) { NSLog( @"SekhVet Overlay: MPR not reopened"); [self aktualisiereToolbar: v]; return; }
    NSValue *rahmen = [z objectForKey: @"frame"];
    if( rahmen) [[mpr window] setFrame: [rahmen rectValue] display: YES];
    NSArray *views = [[z objectForKey: @"views"] retain];
    BOOL key = [[z objectForKey: @"key"] boolValue];
    [mpr retain];
    [rahmen retain];
    // after the hanging protocol of the new MPR (0.5 s after opening), which would otherwise turn the planes back
    dispatch_after( dispatch_time( DISPATCH_TIME_NOW, (int64_t) (0.8 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        if( [mpr windowWillClose] == NO && [[mpr window] isVisible])
        {
            SekhmetStapel *st = [self stapelVon: v];
            if( st && ziel > 0 && ziel < (NSInteger) st.count && mpr.maxMovieIndex + 1 == (int) st.count) [self zeige: ziel imMPR: mpr viewer: v stapel: st];
            if( views && [mpr sekhmetApplyViews: views] == NO) NSLog( @"SekhVet Overlay: MPR position not restored (unusable camera)");
            if( rahmen && NSEqualRects( [[mpr window] frame], [rahmen rectValue]) == NO) [[mpr window] setFrame: [rahmen rectValue] display: YES];   // the 3D tiling may have moved it after opening
            if( key) { [[mpr window] makeKeyAndOrderFront: nil]; [[mpr window] makeFirstResponder: [mpr selectedView]]; }
        }
        [self aktualisiereToolbar: v];
        [views release];
        [rahmen release];
        [mpr release];
    });
}

// Paket CN: Im MPR gilt das Fenster der MPR-Ansichten — beim Umschalten merken und das der neuen Serie setzen
// (Knochen-/Weichteilfenster), wie im 2D-Fenster. Bis Build 140 blieb das Fenster im MPR stehen.
+ (void) zeige:(NSInteger) neu imMPR:(MPRController*) mpr viewer:(ViewerController*) v stapel:(SekhmetStapel*) st
{
    int alt = mpr.curMovieIndex;
    if( neu == alt || neu < 0 || neu >= (NSInteger) st.count) return;
    float wl = 0, ww = 0;
    [mpr.mprView1 getWLWW: &wl :&ww];
    if( ww > 0 && alt >= 0 && alt < (int) st.count) st->fenster[ alt] = @{ @"wl": @( wl), @"ww": @( ww)};
    st->gezeigt = neu;                       // SekhVet Paket CS: our own switch, see folgeFremdemWechsel:
    mpr.curMovieIndex = (int) neu;           // schaltet auch den 2D-Viewer (setMovieIndex:)
    NSDictionary *f = st->fenster[ neu];
    if( [f isKindOfClass: [NSDictionary class]] && [f[ @"ww"] floatValue] > 0)
    {
        wl = [f[ @"wl"] floatValue]; ww = [f[ @"ww"] floatValue];
        for( MPRDCMView *mv in @[ mpr.mprView1, mpr.mprView2, mpr.mprView3])
        {
            [mv setWLWW: wl :ww];
            mv.camera.wl = wl; mv.camera.ww = ww;
        }
        [[v imageView] setWLWW: wl :ww];
    }
    [self rechneROIsNeu: v];
    [self aktualisiereToolbar: v];
    [v setWindowTitle: self];
}

// Chip, Menue: ist ein MPR der Serie offen, schaltet es mit (sonst liefen MPR und 2D auseinander).
+ (void) zeigeSerie:(NSInteger) m viewer:(ViewerController*) v
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil) return;
    MPRController *mpr = [self mprFuer: v];
    if( mpr && mpr.maxMovieIndex + 1 == (int) st.count) [self zeige: m imMPR: mpr viewer: v stapel: st];   // im MPR ist maxMovieIndex der LETZTE Index
    else [self zeige: m inViewer: v];
}

+ (NSString*) taste:(NSString*) key vorgabe:(NSString*) vorgabe
{
    NSString *t = [[NSUserDefaults standardUserDefaults] stringForKey: key];
    return t.length ? [t substringToIndex: 1] : vorgabe;
}

+ (BOOL) handleKeyEvent:(NSEvent*) e inView:(DCMView*) view
{
    if( e.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) return NO;
    NSString *ch = [e characters];
    if( ch.length != 1) return NO;
    NSString *vor = [self taste: SekhmetOverlayKeyNextKey vorgabe: @"<"], *zurueck = [self taste: SekhmetOverlayKeyPrevKey vorgabe: @"y"];
    int schritt = [ch isEqualToString: vor] ? 1 : [ch isEqualToString: zurueck] ? -1 : 0;
    if( schritt == 0) return NO;

    id wc = [view windowController];
    if( [wc isKindOfClass: [ViewerController class]])
    {
        if( [self istGestapelt: wc] == NO) return NO;
        [self schalte: wc schritt: schritt];
        return YES;
    }
    if( [wc isKindOfClass: [MPRController class]])
    {
        MPRController *mpr = wc;
        ViewerController *v = nil;
        @try { v = [mpr valueForKey: @"viewer2D"]; } @catch( NSException *x) { v = nil; }
        SekhmetStapel *st = [self stapelVon: v];
        if( st == nil || mpr.maxMovieIndex + 1 != (int) st.count) return NO;   // im MPR ist maxMovieIndex der LETZTE Index
        [self zeige: [self nachbarVon: mpr.curMovieIndex schritt: schritt stapel: st] imMPR: mpr viewer: v stapel: st];
        return YES;
    }
    return NO;
}

#pragma mark Handweg (Serie aufs Fenster ziehen)

// SekhVet Paket CK (Nutzerwunsch 30.09.2026: "unpraktisch, wenn man jedes Mal gefragt wird"): keine Rueckfrage mehr.
// Der Knopf "Overlay" entscheidet: aus = Horos zeigt die gezogene Serie wie immer, an (gestapelt oder bereit) =
// die Serie kommt in den Stapel. Eine Serie, die schon im Stapel liegt, wird nur angezeigt.
// Rueckgabe: 0 Horos zeigt die Serie, 1 ueberlagern, 2 Stapelserie anzeigen.
+ (int) handwegEntscheidFuerSerie:(DicomSeries*) s viewer:(ViewerController*) v
{
    if( s == nil || v == nil || [v is2DViewer] == NO) return 0;
    SekhmetStapel *st = [self stapelVon: v];
    if( st && [st->serienUIDs containsObject: s.seriesInstanceUID ?: @""]) return 2;
    if( st == nil && [self istBereit: v] == NO) return 0;
    DicomSeries *aktuell = [v currentSeries];
    if( aktuell == nil || s == aktuell) return 0;
    if( [[s valueForKey: @"study"] isEqual: [aktuell valueForKey: @"study"]] == NO) return 0;
    NSString *mod = [s.modality uppercaseString];
    if( ([mod isEqualToString: @"CT"] || [mod isEqualToString: @"MR"]) == NO || [mod isEqualToString: [aktuell.modality uppercaseString]] == NO) return 0;
    if( [[s valueForKey: @"images"] count] < 10 || [[aktuell valueForKey: @"images"] count] < 10) return 0;
    return 1;
}

+ (BOOL) handwegFuerSerie:(DicomSeries*) s viewer:(ViewerController*) v
{
    if( [self handwegEntscheidFuerSerie: s viewer: v] == 0) return NO;
    // Erst nach dem Drop arbeiten: waehrend performDragOperation laeuft noch die Drag-Sitzung.
    [self performSelector: @selector(fuehreHandwegAus:) withObject: @[ s, v] afterDelay: 0];
    return YES;
}

+ (void) fuehreHandwegAus:(NSArray*) args
{
    DicomSeries *s = args[ 0];
    ViewerController *v = args[ 1];
    int entscheid = [self handwegEntscheidFuerSerie: s viewer: v];
    if( entscheid == 2)
    {
        SekhmetStapel *st = [self stapelVon: v];
        NSUInteger m = [st->serienUIDs indexOfObject: s.seriesInstanceUID ?: @""];
        if( m != NSNotFound) [self zeige: (NSInteger) m inViewer: v];
    }
    else if( entscheid == 1)
    {
        NSString *m = nil;
        BOOL ok = [self staple: @[ s] inViewer: v meldung: &m];
        if( ok) [self setzeBereit: NO viewer: v];
        if( ok == NO || m.length)
            NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), @"%@", NSLocalizedString( @"OK", nil), nil, nil, m ?: @"");
        [self aktualisiereToolbar: v];
    }
}

#pragma mark Enhancement-Zeile

// The stack whose enhancement line belongs on this ROI: an area ROI in an image view of a stacked 2D viewer. nil = no line.
+ (SekhmetStapel*) stapelFuerZeileVonROI:(ROI*) r viewer:(ViewerController**) vOut
{
    long typ = r.type;
    if( typ != tOval && typ != tROI && typ != tCPolygon && typ != tPencil) return nil;
    DCMView *view = r.curView;
    id wc = [view windowController];
    if( [wc isKindOfClass: [ViewerController class]] == NO) return nil;
    ViewerController *v = wc;
    if( [[v imageViews] containsObject: view] == NO) return nil;
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil) return nil;
    NSInteger cm = [v curMovieIndex];
    if( cm < 0 || cm >= (NSInteger) st.count) return nil;
    if( vOut) *vOut = v;
    return st;
}

+ (NSString*) enhancementZeileFuerROI:(ROI*) r
{
    ViewerController *v = nil;
    SekhmetStapel *st = [self stapelFuerZeileVonROI: r viewer: &v];
    if( st == nil) return nil;
    DCMView *view = r.curView;
    NSInteger cm = [v curMovieIndex], idx = [view curImage];
    BOOL kn = [st->knochen[ cm] boolValue];
    NSMutableArray *gruppe = [NSMutableArray array];
    for( NSNumber *m in st->reihenfolge) if( [st->knochen[ m.intValue] boolValue] == kn) [gruppe addObject: m];
    if( gruppe.count < 2) return nil;

    NSMutableDictionary *mittel = [NSMutableDictionary dictionary];
    for( NSNumber *m in gruppe)
    {
        NSArray *pl = [v pixList: m.intValue];
        if( idx < 0 || idx >= (NSInteger) pl.count) return nil;
        DCMPix *pk = pl[ idx];
        ROI *c = [r copy];
        c.pix = pk;
        [c setOriginAndSpacing: pk.pixelSpacingX :pk.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pk]];
        float mean = 0, total = 0, dev = 0, mn = 0, mx = 0;
        [pk computeROI: c :&mean :&total :&dev :&mn :&mx];
        [c release];
        mittel[ m] = @( mean);
    }
    BOOL mr = [st->modalitaet isEqualToString: @"MR"];
    NSString *einheit = mr ? @"" : @" HU";
    NSMutableArray *teile = [NSMutableArray array];
    for( NSNumber *m in gruppe) [teile addObject: [NSString stringWithFormat: @"%@ %.0f", st->namen[ m.intValue], [mittel[ m] floatValue]]];

    // Δ = KM − nativ: CT ueber die Phase, MRT ueber dieselbe Gewichtung ohne/mit KM. Genau ein Paar, sonst kein Δ.
    NSNumber *nativ = nil, *km = nil; int nN = 0, nK = 0;
    if( mr == NO)
    {
        for( NSNumber *m in gruppe)
        {
            int p = [st->phasen[ m.intValue] intValue];
            if( p == 1) { nativ = m; nN++; } else if( p == 2) { km = m; nK++; }
        }
    }
    else
    {
        for( NSNumber *m in gruppe) if( [st->mrKM[ m.intValue] boolValue]) { km = m; nK++; }
        if( nK == 1)
        {
            id seq = st->sequenzen[ km.intValue];
            for( NSNumber *m in gruppe)
                if( [st->mrKM[ m.intValue] boolValue] == NO && [seq isKindOfClass: [NSString class]] && [st->sequenzen[ m.intValue] isEqual: seq]) { nativ = m; nN++; }
        }
    }
    if( nN == 1 && nK == 1)
    {
        float a = [mittel[ nativ] floatValue], b = [mittel[ km] floatValue];
        if( mr == NO) [teile addObject: [NSString stringWithFormat: @"Δ %+.0f HU", b - a]];
        else if( fabsf( a) > 1e-3) [teile addObject: [NSString stringWithFormat: @"%+.0f %%", 100.f * (b - a) / a]];
    }
    return [[teile componentsJoinedByString: @" · "] stringByAppendingString: (nN == 1 && nK == 1) ? @"" : einheit];
}

static inline uint64_t svMische( uint64_t h, double w)   // FNV-1a step over the bits of one value
{
    uint64_t b = 0;
    memcpy( &b, &w, sizeof b);
    return (h ^ b) * 1099511628211ULL;
}

// SekhVet Paket CS: -[ROI prepareTextualData:] runs on EVERY draw (and twice while the magnifier is up), and the line
// costs a copy of the ROI plus computeROI on up to four series. The line is kept per ROI and only computed again when
// its inputs change: the stack (generation), the visible series, the slice, the ROI's type and geometry, and the
// statistics Horos itself just computed on the visible series (they change when the pixels under the ROI change).
+ (NSString*) gemerkteEnhancementZeileFuerROI:(ROI*) r
{
    ViewerController *v = nil;
    SekhmetStapel *st = [self stapelFuerZeileVonROI: r viewer: &v];
    if( st == nil)
    {
        if( objc_getAssociatedObject( r, &SekhmetZeileCacheKey)) objc_setAssociatedObject( r, &SekhmetZeileCacheKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return nil;
    }
    long typ = r.type;
    NSRect q = r.rect;
    uint64_t h = 1469598103934665603ULL;
    h = svMische( h, q.origin.x); h = svMische( h, q.origin.y); h = svMische( h, q.size.width); h = svMische( h, q.size.height);
    if( typ == tCPolygon || typ == tPencil)
        for( MyPoint *pt in r.points) { h = svMische( h, pt.x); h = svMische( h, pt.y); }
    h = svMische( h, r.mean); h = svMische( h, r.min); h = svMische( h, r.max);
    NSString *sig = [NSString stringWithFormat: @"%u|%ld|%ld|%ld|%llx", st->generation, (long) [v curMovieIndex], (long) [r.curView curImage], typ, (unsigned long long) h];
    NSArray *gemerkt = objc_getAssociatedObject( r, &SekhmetZeileCacheKey);
    if( gemerkt.count == 2 && [gemerkt[ 0] isEqualToString: sig])
        return [gemerkt[ 1] isKindOfClass: [NSString class]] ? gemerkt[ 1] : nil;
    NSString *zeile = [self enhancementZeileFuerROI: r];
    objc_setAssociatedObject( r, &SekhmetZeileCacheKey, @[ sig, zeile ?: (id) [NSNull null]], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return zeile;
}

+ (void) ergaenzeTextboxVonROI:(ROI*) r
{
    NSString *alt = objc_getAssociatedObject( r, &SekhmetZeileKey);
    NSString *zeile = [self gemerkteEnhancementZeileFuerROI: r];   // SekhVet Paket CS: cached
    // unsere Zeile vom letzten Zeichnen erkennen: Horos setzt Zeile 5/6 nur bei Fusion neu
    if( alt && [r.textualBoxLine5 isEqualToString: alt]) r.textualBoxLine5 = nil;
    if( alt && [r.textualBoxLine6 isEqualToString: alt]) r.textualBoxLine6 = nil;
    if( zeile.length)
    {
        if( r.textualBoxLine5.length == 0) r.textualBoxLine5 = zeile;
        else if( r.textualBoxLine6.length == 0) r.textualBoxLine6 = zeile;
        else zeile = nil;
    }
    objc_setAssociatedObject( r, &SekhmetZeileKey, zeile.length ? zeile : nil, OBJC_ASSOCIATION_COPY_NONATOMIC);
}

#pragma mark Werkzeugleiste

+ (NSImage*) icon
{
    static NSImage *bild = nil;
    if( bild == nil)
    {
        bild = [[NSImage imageWithSize: NSMakeSize( 32, 32) flipped: NO drawingHandler: ^BOOL( NSRect rect) {
            [[NSColor blackColor] set];
            for( int k = 0; k < 3; k++)
            {
                NSRect q = NSMakeRect( 4 + k * 5, 14 - k * 5, 15, 15);
                NSBezierPath *p = [NSBezierPath bezierPathWithRoundedRect: q xRadius: 2 yRadius: 2];
                [[NSColor colorWithCalibratedWhite: 0 alpha: 0.18 + 0.2 * k] setFill];
                [p fill];
                [p setLineWidth: 1.5];
                [p stroke];
            }
            return YES;
        }] retain];
        [bild setTemplate: YES];
    }
    return bild;
}

+ (void) konfiguriereToolbarItem:(NSToolbarItem*) item viewer:(ViewerController*) v
{
    [item setLabel: NSLocalizedString( @"Overlay", nil)];
    [item setPaletteLabel: NSLocalizedString( @"Overlay Series (SekhVet)", nil)];
    [item setToolTip: NSLocalizedString( @"Overlay the native/contrast/bone series of this study in this window; switch with < and y (Vet Tools › Display), slice and zoom stay", nil)];
    NSSegmentedControl *seg = [[[NSSegmentedControl alloc] initWithFrame: NSMakeRect( 0, 0, 44, 25)] autorelease];
    [seg setSegmentStyle: NSSegmentStyleTexturedRounded];
    [seg setTarget: self];
    [seg setAction: @selector(segmentGeklickt:)];
    [item setView: seg];
    [self fuelle: seg item: item viewer: v];
}

+ (void) fuelle:(NSSegmentedControl*) seg item:(NSToolbarItem*) item viewer:(ViewerController*) v
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil)
    {
        [seg setSegmentCount: 1];
        BOOL bereit = [self istBereit: v];   // SekhVet Paket CK: an ohne Stapel = wartet auf eine gezogene Serie
        [[seg cell] setTrackingMode: NSSegmentSwitchTrackingSelectAny];
        [seg setImage: [self icon] forSegment: 0];
        [seg setLabel: @"" forSegment: 0];
        [seg setWidth: 40 forSegment: 0];
        [seg setToolTip: bereit ? NSLocalizedString( @"Overlay is on: drag a series from the series list onto the image to overlay it. Click to switch it off.", nil) : NSLocalizedString( @"Overlay matching series of this study in this window", nil) forSegment: 0];
        [seg setSelected: bereit forSegment: 0];
    }
    else
    {
        NSArray *sicht = [self sichtbar: st];
        NSUInteger n = sicht.count;
        [seg setSegmentCount: n + 2];
        [[seg cell] setTrackingMode: NSSegmentSwitchTrackingSelectOne];
        NSFont *f = [NSFont systemFontOfSize: 11];
        for( NSUInteger k = 0; k < n; k++)
        {
            int m = [sicht[ k] intValue];
            NSString *titel = st->namen[ m];
            int versteckt = [st->versteckt[ m] intValue];
            NSString *tipp = st->serienNamen[ m];
            if( versteckt > 0)
            {
                titel = [titel stringByAppendingFormat: @" (%d %@)", versteckt, NSLocalizedString( @"hidden", @"overlay chip: own measurements hidden")];
                tipp = [tipp stringByAppendingFormat: NSLocalizedString( @"\n%d measurement(s) of this series are hidden while overlaid; they stay saved with the series.", nil), versteckt];
            }
            [seg setImage: nil forSegment: k];
            [seg setLabel: titel forSegment: k];
            [seg setWidth: ceil( [titel sizeWithAttributes: @{ NSFontAttributeName: f}].width) + 16 forSegment: k];
            [seg setToolTip: tipp forSegment: k];
            [seg setSelected: m == [v curMovieIndex] forSegment: k];
        }
        [seg setLabel: @"▾" forSegment: n];
        [seg setImage: nil forSegment: n];
        [seg setWidth: 24 forSegment: n];
        [seg setToolTip: NSLocalizedString( @"Choose which series of this study are overlaid", nil) forSegment: n];
        [seg setSelected: NO forSegment: n];
        [seg setLabel: @"✕" forSegment: n + 1];
        [seg setImage: nil forSegment: n + 1];
        [seg setWidth: 24 forSegment: n + 1];
        [seg setToolTip: NSLocalizedString( @"End the overlay", nil) forSegment: n + 1];
        [seg setSelected: NO forSegment: n + 1];
    }
    [seg sizeToFit];
    NSSize sz = [seg frame].size;
    [item setMinSize: sz];
    [item setMaxSize: sz];
}

// SekhVet Paket CM: Horos haengt die Viewer-Symbolleiste in ein eigenes Fenster (ToolbarPanelController,
// USEALWAYSTOOLBARPANEL2) — dessen windowController ist NICHT der Viewer. Bis Build 139 tat der Knopf deshalb nichts.
+ (ViewerController*) viewerFuerToolbarFenster:(NSWindow*) w
{
    id wc = [w windowController];
    if( [wc isKindOfClass: [ViewerController class]]) return wc;
    if( [wc isKindOfClass: [ToolbarPanelController class]]) return [(ToolbarPanelController*) wc viewer];
    if( [wc isKindOfClass: [MPRController class]]) return [(Window3DController*) wc viewer];   // SekhVet Paket DA: Knopf im MPR
    return nil;
}

// SekhVet Paket DA: after a click in the MPR toolbar the keys < and y belong to the MPR, not to the 2D window
+ (void) fokus:(ViewerController*) v ausMPR:(BOOL) ausMPR
{
    MPRController *mpr = ausMPR ? [self mprFuer: v] : nil;
    if( mpr == nil) { [self fokusAufsBild: v]; return; }
    [[mpr window] makeKeyWindow];
    [[mpr window] makeFirstResponder: [mpr selectedView]];
}

+ (void) fokusAufsBild:(ViewerController*) v
{
    [[v window] makeKeyWindow];                       // nach dem Klick in die Leiste gehen "<" und "y" sonst ins Leere
    [[v window] makeFirstResponder: [v imageView]];
}

#pragma mark Auswahl der Serien (Paket CN)

// Nutzerwunsch 30.09.2026: "nicht alle Serien durchschalten, sondern nur Weichteil nativ und KM und EINE Knochen, oder nur
// zwei davon" -> Segment "▾" mit Haken je Serie. Abwaehlen nimmt die Serie aus Chips und Durchschalten (sie bleibt
// geladen, die Enhancement-Zeile rechnet weiter mit ihr); beim CT merkt sich SekhVet den abgewaehlten Rang und laedt
// ihn beim naechsten Klick auf "Overlay" gar nicht erst. Die Bezugsserie bleibt immer.
+ (NSArray*) kandidatenFuerViewer:(ViewerController*) v
{
    DicomSeries *aktuell = [v currentSeries];
    DicomStudy *studie = [v currentStudy];
    SekhmetStapel *st = [self stapelVon: v];
    if( studie == nil) return @[];
    NSString *mod = st ? st->modalitaet : [(aktuell.modality ?: @"") uppercaseString];
    NSMutableArray *aus = [NSMutableArray array];
    for( id s in [[BrowserController currentBrowser] childrenArray: studie])
    {
        if( [s isKindOfClass: [DicomSeries class]] == NO) continue;
        DicomSeries *ds = s;
        if( [[(ds.modality ?: @"") uppercaseString] isEqualToString: mod] == NO) continue;
        BOOL imStapel = st && [st->serienUIDs containsObject: ds.seriesInstanceUID ?: @""];
        if( imStapel == NO && ([[ds valueForKey: @"images"] count] < 10 || svIstTopogramm( ds.name))) continue;
        [aus addObject: ds];
    }
    return aus;
}

+ (NSNumber*) merkbarerRang:(DicomSeries*) s
{
    NSDictionary *info = [self infoFuerSerie: s];
    if( [info[ @"modality"] isEqualToString: @"CT"] == NO || [self phaseFuer: info[ @"desc"]] == 0) return nil;
    return @( svRang( info));
}

+ (NSArray*) ohneAbgewaehlte:(NSArray*) serien
{
    NSArray *ab = [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetOverlayDeselectedKey];
    if( ab.count == 0) return serien;
    NSMutableArray *aus = [NSMutableArray array];
    for( DicomSeries *s in serien)
    {
        NSNumber *rang = [self merkbarerRang: s];
        if( rang == nil || [ab containsObject: rang] == NO) [aus addObject: s];
    }
    return aus.count ? aus : serien;   // alles abgewaehlt waere kein Overlay — dann gilt der Vorschlag
}

+ (BOOL) setzeSerie:(DicomSeries*) s an:(BOOL) an viewer:(ViewerController*) v meldung:(NSString**) meldung
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil || s == nil) return NO;
    NSUInteger m = [st->serienUIDs indexOfObject: s.seriesInstanceUID ?: @""];
    if( m == 0) return NO;                                   // die Bezugsserie bleibt
    if( m != NSNotFound)
    {
        st->aus[ m] = @( an == NO);
        MPRController *mpr = [self mprFuer: v];
        NSInteger sichtbarJetzt = mpr ? mpr.curMovieIndex : [v curMovieIndex];
        if( an == NO && sichtbarJetzt == (NSInteger) m) [self zeigeSerie: 0 viewer: v];   // die abgewaehlte lag gerade im Fenster
    }
    else if( an)
    {
        if( [self staple: @[ s] inViewer: v meldung: meldung] == NO) return NO;
    }
    else return NO;
    NSNumber *rang = [self merkbarerRang: s];
    if( rang)
    {
        NSMutableArray *ab = [NSMutableArray arrayWithArray: [[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetOverlayDeselectedKey] ?: @[]];
        [ab removeObject: rang];
        if( an == NO) [ab addObject: rang];
        [[NSUserDefaults standardUserDefaults] setObject: ab forKey: SekhmetOverlayDeselectedKey];
    }
    [self aktualisiereToolbar: v];
    [[v imageView] setNeedsDisplay: YES];
    return YES;
}

// SekhVet Paket CS: series and viewer travel with the menu item (representedObject = @[ series, viewer ]). Before,
// the viewer sat in a static that was only set while popUpMenuPositioningItem: ran — that relied on AppKit sending
// the action before the call returns.
+ (void) auswahlGeklickt:(NSMenuItem*) item
{
    NSArray *ziel = [item representedObject];
    if( [ziel isKindOfClass: [NSArray class]] == NO || ziel.count != 2) return;
    DicomSeries *s = ziel[ 0];
    ViewerController *v = ziel[ 1];
    if( [v windowWillClose]) return;
    NSString *m = nil;
    [self setzeSerie: s an: [item state] != NSControlStateValueOn viewer: v meldung: &m];
    if( m.length) NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), @"%@", NSLocalizedString( @"OK", nil), nil, nil, m);
}

+ (void) zeigeAuswahlMenu:(ViewerController*) v
{
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil) return;
    NSMenu *menu = [[[NSMenu alloc] initWithTitle: @""] autorelease];
    [menu setAutoenablesItems: NO];
    for( DicomSeries *s in [self kandidatenFuerViewer: v])
    {
        NSUInteger m = [st->serienUIDs indexOfObject: s.seriesInstanceUID ?: @""];
        NSString *kurz = m != NSNotFound ? st->namen[ m] : [self kurznameFuer: [self infoFuerSerie: s]];
        NSMenuItem *it = [menu addItemWithTitle: [NSString stringWithFormat: @"%@ — %@", kurz, s.name ?: @""] action: @selector(auswahlGeklickt:) keyEquivalent: @""];
        [it setTarget: self];
        [it setRepresentedObject: @[ s, v]];
        [it setState: (m != NSNotFound && [st->aus[ m] boolValue] == NO) ? NSControlStateValueOn : NSControlStateValueOff];
        [it setEnabled: m != 0];
    }
    [menu popUpMenuPositioningItem: nil atLocation: [NSEvent mouseLocation] inView: nil];
}

+ (void) aktualisiereToolbar:(ViewerController*) v
{
    // SekhVet Paket CS: called from -[ViewerController setWindowTitle:], i.e. after every change of the movie index
    SekhmetStapel *st = [self stapelVon: v];
    if( st && st->gezeigt != [v curMovieIndex]) [self folgeFremdemWechsel: v stapel: st];
    for( NSToolbarItem *it in [[v toolbar] items])
        if( [[it itemIdentifier] isEqualToString: SekhmetOverlayToolbarItemIdentifier] && [[it view] isKindOfClass: [NSSegmentedControl class]])
            [self fuelle: (NSSegmentedControl*) [it view] item: it viewer: v];
    MPRController *mpr = [self mprFuer: v];   // SekhVet Paket DA: the same button in the MPR toolbar
    if( mpr)
        for( NSToolbarItem *it in [[[mpr window] toolbar] items])
            if( [[it itemIdentifier] isEqualToString: @"SekhmetMPROverlay"] && [[it view] isKindOfClass: [NSSegmentedControl class]])
                [self fuelle: (NSSegmentedControl*) [it view] item: it viewer: v];
}

+ (void) segmentGeklickt:(NSSegmentedControl*) seg
{
    ViewerController *v = [self viewerFuerToolbarFenster: [seg window]];
    if( v == nil) { NSLog( @"SekhVet Overlay: no viewer for the toolbar window %@", [[seg window] windowController]); return; }
    BOOL ausMPR = [[[seg window] windowController] isKindOfClass: [MPRController class]];   // SekhVet Paket DA
    SekhmetStapel *st = [self stapelVon: v];
    if( st == nil)
    {
        if( [self istBereit: v]) { [self setzeBereit: NO viewer: v]; [self aktualisiereToolbar: v]; return; }   // SekhVet Paket CK: wieder aus
        // SekhVet Paket CS: CT and MR only, also on the button path (before, only a dragged series was checked) —
        // otherwise the button would stay "on" for a modality whose series can never be dropped in.
        if( svStapelbar( [[[v currentSeries] modality] uppercaseString]) == NO)
        {
            NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), @"%@", NSLocalizedString( @"OK", nil), nil, nil, NSLocalizedString( @"Overlay is available for CT and MR series.", nil));
            [self aktualisiereToolbar: v];
            return;
        }
        NSArray *vorschlag = [self vorschlagFuerViewer: v];
        NSMutableArray *andere = [NSMutableArray array];
        for( DicomSeries *s in vorschlag) if( s != [v currentSeries]) [andere addObject: s];
        NSString *m = nil;
        if( andere.count == 0)
        {
            // SekhVet Paket CK: kein Vorschlag -> Knopf bleibt an, die naechste gezogene Serie wird ueberlagert
            [self setzeBereit: YES viewer: v];
            m = NSLocalizedString( @"No other series of this study matches automatically (same modality, at least 10 images, same region and plane). Overlay is now on: drag a series from the series list onto the image to overlay it. Click the button again to switch it off.", nil);
        }
        else [self staple: [self ohneAbgewaehlte: andere] inViewer: v meldung: &m];
        if( m.length) NSRunAlertPanel( NSLocalizedString( @"Overlay", nil), @"%@", NSLocalizedString( @"OK", nil), nil, nil, m);
        [self aktualisiereToolbar: v];
        [self fokus: v ausMPR: ausMPR];
        return;
    }
    NSInteger k = [seg selectedSegment];
    if( k < 0) return;
    NSArray *sicht = [self sichtbar: st];
    if( k == (NSInteger) sicht.count) { [self zeigeAuswahlMenu: v]; [self aktualisiereToolbar: v]; [self fokus: v ausMPR: ausMPR]; return; }
    if( k > (NSInteger) sicht.count) { [self beende: v]; return; }
    [self zeigeSerie: [sicht[ k] integerValue] viewer: v];
    [self fokus: v ausMPR: ausMPR];
}

#pragma mark Tests

// SekhVet Paket CS: debugLupe:, debugSelfTest and debugE2E (they write and delete ROIs and change
// SekhmetOverlayDeselected) were compiled into release builds; their only callers in AppController.m are test hooks.

#pragma mark - SekhVet Paket CX: Subtraktion nach Ort

// Horos' Fusion-Blatt "Subtraction" (Bild eines Viewers auf einen anderen ziehen) blaetterte die Maske nur ueber die
// Sync-Nachricht mit: Zielschicht setzen, sendSyncMessage, dann die gerade angezeigte Maskenschicht abziehen. Die Maske
// folgt aber nur, wenn das Ziel das vorderste Fenster ist und Sync an ist -- nach dem Ziehen liegt die Maske vorne,
// also wurde von JEDER Schicht dieselbe Maskenschicht abgezogen (Befund 01.10.2026: "ein Bild bleibt statisch
// schwarz im Hintergrund"). Jetzt wird jede Zielschicht direkt mit der Maskenschicht am selben Ort verrechnet.

static void sekhmetSchichtMitte( DCMPix *p, float mitte[ 3], float normale[ 3])
{
    float o[ 9];
    [p orientation: o];
    normale[ 0] = o[ 6]; normale[ 1] = o[ 7]; normale[ 2] = o[ 8];
    [p convertPixX: p.pwidth / 2.f pixY: p.pheight / 2.f toDICOMCoords: mitte];
}

+ (NSInteger) partnerVon:(DCMPix*) a in:(NSArray*) maske
{
    if( a == nil || maske.count == 0) return -1;

    float ma[ 3], na[ 3], mb[ 3], nb[ 3];
    sekhmetSchichtMitte( a, ma, na);
    if( na[ 0] == 0 && na[ 1] == 0 && na[ 2] == 0) return -1;   // keine Geometrie

    NSInteger best = -1;
    double bestD = HUGE_VAL;
    for( NSUInteger j = 0; j < maske.count; j++)
    {
        sekhmetSchichtMitte( maske[ j], mb, nb);
        if( fabs( na[ 0]*nb[ 0] + na[ 1]*nb[ 1] + na[ 2]*nb[ 2]) < 0.99) continue;   // nicht parallel (mehr als ~8 Grad)
        double d = fabs( (ma[ 0]-mb[ 0])*nb[ 0] + (ma[ 1]-mb[ 1])*nb[ 1] + (ma[ 2]-mb[ 2])*nb[ 2]);
        if( d < bestD) { bestD = d; best = j; }
    }
    if( best < 0) return -1;

    // Toleranz: ein Schichtabstand der Maske (mindestens ihre Schichtdicke) -- weiter weg liegt die Zielschicht ausserhalb der Maske
    double abstand = 0;
    if( maske.count > 1)
    {
        float m0[ 3], m1[ 3], n0[ 3];
        sekhmetSchichtMitte( maske[ 0], m0, n0);
        sekhmetSchichtMitte( maske[ 1], m1, nb);
        abstand = fabs( (m1[ 0]-m0[ 0])*n0[ 0] + (m1[ 1]-m0[ 1])*n0[ 1] + (m1[ 2]-m0[ 2])*n0[ 2]);
    }
    double toleranz = MAX( abstand, [(DCMPix*) maske[ best] sliceThickness]);
    if( toleranz <= 0) toleranz = 1;

    return bestD <= toleranz + 0.01 ? best : -1;
}

+ (BOOL) verrechne:(ViewerController*) ziel mit:(ViewerController*) maske art:(int) art absolut:(BOOL) absolut nachIndex:(BOOL) nachIndex
{
    if( ziel == nil || maske == nil || (art != 2 && art != 3)) return NO;

    [ziel checkEverythingLoaded];
    [maske checkEverythingLoaded];

    NSArray *aPix = [ziel pixList], *bPix = [maske pixList];
    if( aPix.count == 0 || bPix.count == 0) return NO;

    // Gleiche Patientenkoordinaten: gleicher FrameOfReference, ohne FoR dieselbe Untersuchung
    DCMPix *a0 = aPix[ 0], *b0 = bPix[ 0];
    BOOL gleicheWelt;
    if( a0.frameofReferenceUID.length && b0.frameofReferenceUID.length)
        gleicheWelt = [a0.frameofReferenceUID isEqualToString: b0.frameofReferenceUID];
    else
        gleicheWelt = [[ziel studyInstanceUID] isEqualToString: [maske studyInstanceUID]];

    NSUInteger ohnePartner = 0, andereGroesse = 0, verrechnet = 0;
    for( NSUInteger i = 0; i < aPix.count; i++)
    {
        DCMPix *a = aPix[ i];
        NSInteger j;

        if( nachIndex)                                                      // Ctrl: Bild fuer Bild (Horos)
            j = i < bPix.count ? (NSInteger) i : -1;
        else if( gleicheWelt)
            j = [self partnerVon: a in: bPix];
        else if( aPix.count == bPix.count)
            j = i;
        else
            j = MIN( (NSInteger) bPix.count - 1, (NSInteger) lround( (double) i * bPix.count / aPix.count));

        [a CheckLoad];

        if( j < 0)
        {
            // Zielschicht liegt ausserhalb der Maske: nicht stehen lassen (sie saehe aus wie ein Subtraktionsbild), sondern leeren
            if( a.fImage && a.isRGB == NO) memset( a.fImage, 0, (size_t) a.pwidth * a.pheight * sizeof( float));
            ohnePartner++;
            continue;
        }

        DCMPix *b = bPix[ j];
        [b CheckLoad];
        if( a.pwidth != b.pwidth || a.pheight != b.pheight || a.fImage == nil || b.fImage == nil) { andereGroesse++; continue; }

        if( art == 2) [a imageArithmeticSubtraction: b absolute: absolut];
        else [a imageArithmeticMultiplication: b];
        verrechnet++;
    }

    for( DCMView *v in [[ziel seriesView] imageViews])
    {
        [v setIndex: [v curImage]];
        [v reapplyWindowLevel];
        [v loadTextures];
        [v setNeedsDisplay: YES];
    }

    NSLog( @"SekhVet %@: %lu Schichten verrechnet (%@), %lu ausserhalb der Maske geleert, %lu andere Groesse", art == 2 ? @"Subtraktion" : @"Multiplikation",
          (unsigned long) verrechnet, nachIndex ? @"Bild fuer Bild" : (gleicheWelt ? @"nach Ort" : @"nach Index"), (unsigned long) ohnePartner, (unsigned long) andereGroesse);

    return YES;
}

#if SEKHVET_TESTHAKEN

// Paket CO: Horos' freie Lupe (Shift) ueber flagsChanged:, einmal mit dem Fenster-Werkzeug, einmal mit dem Oval.
+ (NSString*) debugLupe:(ViewerController*) v
{
    DCMView *iv = [v imageView];
    DCMPix *p = [iv curDCM];
    [iv setValue: @( p.pwidth / 2.f) forKey: @"mouseXPos"];
    [iv setValue: @( p.pheight / 2.f) forKey: @"mouseYPos"];
    NSEvent *an = [NSEvent keyEventWithType: NSEventTypeFlagsChanged location: NSMakePoint( 5, 5) modifierFlags: NSEventModifierFlagShift timestamp: 0 windowNumber: [[v window] windowNumber] context: nil characters: @"" charactersIgnoringModifiers: @"" isARepeat: NO keyCode: 56];
    NSEvent *aus = [NSEvent keyEventWithType: NSEventTypeFlagsChanged location: NSMakePoint( 5, 5) modifierFlags: 0 timestamp: 0 windowNumber: [[v window] windowNumber] context: nil characters: @"" charactersIgnoringModifiers: @"" isARepeat: NO keyCode: 56];
    ToolMode alt = [iv currentTool];
    NSMutableArray *t = [NSMutableArray array];
    for( NSNumber *w in @[ @( tWL), @( tOval), @( tMesure)])
    {
        [iv setCurrentTool: (ToolMode) w.intValue];
        [iv flagsChanged: an];
        [t addObject: [NSString stringWithFormat: @"%@ %@", w.intValue == tWL ? @"Fenster" : w.intValue == tOval ? @"Oval" : @"Laenge", [iv sekhmetFreieLupeAktiv] ? @"JA" : @"NEIN"]];
        [iv flagsChanged: aus];
    }
    [iv setCurrentTool: alt];
    return [NSString stringWithFormat: @"%@ (Einstellung magnifyingLens %@)", [t componentsJoinedByString: @", "], [[NSUserDefaults standardUserDefaults] boolForKey: @"magnifyingLens"] ? @"an" : @"AUS"];
}

+ (NSString*) debugSelfTest
{
    NSMutableArray *fehler = [NSMutableArray array];
    int ok = 0;
    #define PRUEFE( bed, text) do { if( bed) ok++; else [fehler addObject: text]; } while( 0)

    // Phase
    PRUEFE( [self phaseFuer: @"Wirbelsäule nativ 0,80 Br40"] == 1, @"phase nativ");
    PRUEFE( [self phaseFuer: @"Schulter Ellbogen KM 0 60 Br40 S2"] == 2, @"phase KM");
    PRUEFE( [self phaseFuer: @"Wirbelsäule ohne KM"] == 1, @"phase ohne KM");
    PRUEFE( [self phaseFuer: @"Abdomen post KM"] == 2, @"phase post KM");
    PRUEFE( [self phaseFuer: @"SST1"] == 0, @"phase SST1");
    PRUEFE( [self phaseFuer: @"CT Kopf"] == 0, @"phase CT enthaelt C");
    PRUEFE( [self phaseFuer: @"Thorax C+"] == 2, @"phase C+");
    // SekhVet Paket CS: negated / pre-contrast names (the full list is in SekhVet/test/sequenz-test.m)
    PRUEFE( [self phaseFuer: @"Abdomen pre KM"] == 1, @"phase pre KM");
    PRUEFE( [self phaseFuer: @"Abdomen vor KM"] == 1, @"phase vor KM");
    PRUEFE( [self phaseFuer: @"Abdomen without contrast"] == 1, @"phase without contrast");
    PRUEFE( [self phaseFuer: @"Abdomen pre contrast"] == 1, @"phase pre contrast");
    {
        NSDictionary *(^ct)( NSString*, NSString*, int) = ^NSDictionary*( NSString *uid, NSString *desc, int nr) {
            return @{ @"uid": uid, @"desc": desc, @"kernel": @"Br40d", @"modality": @"CT", @"study": @"S3", @"count": @( 300), @"number": @( nr)};
        };
        NSArray *pp = @[ ct( @"pre", @"Abdomen pre KM 1.0", 2), ct( @"post", @"Abdomen post KM 1.0", 3)];
        NSString *u = [[[self vorschlagAus: pp aktuell: pp[ 0]] valueForKey: @"uid"] componentsJoinedByString: @","];
        PRUEFE( [u isEqualToString: @"pre,post"], ([NSString stringWithFormat: @"vorschlag pre/post KM %@", u]));
    }
    // Kern
    PRUEFE( [self istKnochenkern: @"Br64d" beschreibung: @""], @"kern Br64");
    PRUEFE( [self istKnochenkern: @"Br40d" beschreibung: @""] == NO, @"kern Br40");
    PRUEFE( [self istKnochenkern: @"" beschreibung: @"Wirbelsäule nativ 0 80 Br64 KF"], @"kern KF im Namen");
    PRUEFE( [self istKnochenkern: @"FC08" beschreibung: @""] == NO, @"kern FC08");
    PRUEFE( [self istKnochenkern: @"BONE" beschreibung: @""], @"kern BONE");

    // Vorschlag: 4 CT-Serien + Topogramm + andere Region
    NSDictionary *(^ser)( NSString*, NSString*, NSString*, int, int) = ^NSDictionary*( NSString *uid, NSString *desc, NSString *kern, int count, int nr) {
        return @{ @"uid": uid, @"desc": desc, @"kernel": kern, @"modality": @"CT", @"study": @"S1", @"count": @( count), @"number": @( nr)};
    };
    NSArray *alle = @[ ser( @"a", @"Schulter Ellbogen nativ 0 60 Br64", @"Br64d", 400, 3), ser( @"b", @"Schulter Ellbogen nativ 0 60 Br40 S2", @"Br40d", 400, 2),
                       ser( @"c", @"Schulter Ellbogen KM 0 60 Br64", @"Br64d", 400, 5), ser( @"d", @"Schulter Ellbogen KM 0 60 Br40 S2", @"Br40d", 400, 4),
                       ser( @"t", @"Topogramm 0.6 T20s", @"T20s", 1, 1), ser( @"x", @"Becken nativ 0 60 Br40", @"Br40d", 300, 6)];
    NSArray *v1 = [self vorschlagAus: alle aktuell: alle[ 1]];
    NSString *uids = [[v1 valueForKey: @"uid"] componentsJoinedByString: @""];
    PRUEFE( [uids isEqualToString: @"bdac"], ([NSString stringWithFormat: @"vorschlag CT %@ statt bdac", uids]));
    // "mit KM" (Namen aus einer echten Studie): Fuellwort darf die Region nicht trennen
    NSArray *z = @[ ser( @"n", @"Wirbelsäule nativ 0,80 Br40 WT", @"Br40", 800, 2), ser( @"k", @"Wirbelsäule mit KM 0,80 Br40 WT", @"Br40", 800, 4),
                    ser( @"nk", @"Wirbelsäule nativ 0,80 Br64 KF", @"Br64", 800, 3), ser( @"kk", @"Wirbelsäule mit KM 0,80 Br64 KF", @"Br64", 800, 5)];
    uids = [[[self vorschlagAus: z aktuell: z[ 0]] valueForKey: @"uid"] componentsJoinedByString: @","];
    PRUEFE( [uids isEqualToString: @"n,k,nk,kk"], ([NSString stringWithFormat: @"vorschlag mit KM %@", uids]));
    // MRT: gleiche Ebene
    NSDictionary *(^mr)( NSString*, NSString*, NSArray*, int) = ^NSDictionary*( NSString *uid, NSString *desc, NSArray *n, int nr) {
        return @{ @"uid": uid, @"desc": desc, @"kernel": @"", @"modality": @"MR", @"study": @"S2", @"count": @( 30), @"number": @( nr), @"normal": n};
    };
    NSArray *tra = @[ @0, @0, @1], *sag = @[ @1, @0, @0];
    // Namen wie bei Esaote/Hitachi ("HKCL SE T1 tra post KM"): die Regionsregel streicht T1/T2 wie einen Kern,
    // getrennt werden die Sequenzen ueber SE/GE — genau wie in ImagoPilot. KM hat Rang 1, steht also vorn.
    NSArray *m = @[ mr( @"t2t", @"SE T2 tra", tra, 1), mr( @"t1t", @"GE T1 tra", tra, 2), mr( @"t1k", @"GE T1 tra post KM", tra, 3), mr( @"t2s", @"SE T2 sag", sag, 4)];
    uids = [[[self vorschlagAus: m aktuell: m[ 0]] valueForKey: @"uid"] componentsJoinedByString: @","];
    PRUEFE( [uids isEqualToString: @"t1k,t2t,t1t"], ([NSString stringWithFormat: @"vorschlag MR %@", uids]));
    uids = [[[self vorschlagAus: m aktuell: m[ 3]] valueForKey: @"uid"] componentsJoinedByString: @","];
    PRUEFE( [uids isEqualToString: @"t2s"], ([NSString stringWithFormat: @"vorschlag MR sag allein %@", uids]));

    // Neuabtastung: Quelle 1 mm Gitter, lineares Feld f = x + 2y + 3z; Ziel um 0,5/0,25/0,7 mm versetzt, anderer Abstand.
    // Trilinear ist fuer ein lineares Feld exakt — jede Abweichung ist ein Rechenfehler.
    {
        int w = 40, h = 30, ns = 25;
        float *src = malloc( sizeof( float) * w * h * ns);
        const float **img = malloc( sizeof( float*) * ns);
        double *pos = malloc( sizeof( double) * ns), *su = calloc( ns, sizeof( double)), *sv = calloc( ns, sizeof( double));
        for( int k = 0; k < ns; k++)
        {
            for( int y = 0; y < h; y++) for( int x = 0; x < w; x++) src[ (long) k * w * h + y * w + x] = x + 2 * y + 3 * (k * 1.5);
            img[ k] = src + (long) k * w * h; pos[ k] = k * 1.5;
        }
        SVQuelle q = { img, pos, su, sv, ns, w, h, { 0, 0, 0}, { 1, 0, 0}, { 0, 1, 0}, { 0, 0, 1}, 1, 1, 0.75};
        int dw = 20, dh = 20;
        float *dst = malloc( sizeof( float) * dw * dh);
        double dr[3] = { 1, 0, 0}, dc[3] = { 0, 1, 0};
        double maxErr = 0; int fuellungen = 0;
        for( int s = 0; s < 10; s++)
        {
            double o[3] = { 0.5, 0.25, 0.7 + s * 2.0};
            svResampleSlice( &q, o, dr, dc, 1.3, 0.9, dw, dh, dst, -1024);
            for( int y = 0; y < dh; y++) for( int x = 0; x < dw; x++)
            {
                double erwartet = (0.5 + x * 1.3) + 2 * (0.25 + y * 0.9) + 3 * o[ 2];
                double e = fabs( dst[ y * dw + x] - erwartet);
                if( e > maxErr) maxErr = e;
            }
        }
        PRUEFE( maxErr < 1e-3, ([NSString stringWithFormat: @"neuabtastung linear max. Fehler %.5f", maxErr]));
        double o[3] = { 0, 0, 40};   // jenseits der letzten Schicht (36 + 0,75)
        svResampleSlice( &q, o, dr, dc, 1, 1, dw, dh, dst, -1024);
        for( int i = 0; i < dw * dh; i++) if( dst[ i] == -1024) fuellungen++;
        PRUEFE( fuellungen == dw * dh, ([NSString stringWithFormat: @"neuabtastung ausserhalb %d/%d gefuellt", fuellungen, dw * dh]));
        double o2[3] = { 30, 0, 3};  // rechts halb aus dem Bild: x 30..49 bei Breite 40
        svResampleSlice( &q, o2, dr, dc, 1, 1, dw, dh, dst, -1024);
        PRUEFE( dst[ 0] > -1024 && dst[ dw - 1] == -1024, @"neuabtastung Bildrand");
        free( dst); free( src); free( img); free( pos); free( su); free( sv);
    }
    #undef PRUEFE
    return fehler.count ? [NSString stringWithFormat: @"%d ok, FEHLER: %@", ok, [fehler componentsJoinedByString: @"; "]] : [NSString stringWithFormat: @"alle %d ok", ok];
}

// End-to-End mit einer geoeffneten CT-Studie (Testhaken SEKHVET_OVERLAY_E2E_TEST, Skript overlay-e2e-test.sh).
+ (void) debugE2E
{
    static int schritt = 0;
    static ViewerController *v = nil;
    static ROI *gefaess = nil, *knochen = nil;
    static float scale = 0; static NSPoint origin; static long bild = 0;
    NSString *P = @"SekhVet Overlay-E2E";
    @try
    {
    if( schritt == 0)
    {
        for( ViewerController *x in [ViewerController getDisplayed2DViewers])
            if( v == nil && [[x pixList] count] >= 10 && [[[x currentSeries] modality] isEqualToString: @"CT"]) v = [x retain];
        if( v == nil) { NSLog( @"%@: kein CT-Viewer offen", P); return; }
        // bis alles geladen ist
        if( [v isEverythingLoaded] == NO) { NSLog( @"%@: warte auf Laden", P); [self performSelector: _cmd withObject: nil afterDelay: 3]; return; }
        NSArray *vorschlag = [self vorschlagFuerViewer: v];
        NSLog( @"%@ 1: Bezug '%@', Vorschlag: %@", P, [[v currentSeries] name], [[vorschlag valueForKey: @"name"] componentsJoinedByString: @" | "]);
        NSMutableArray *andere = [NSMutableArray array];
        for( DicomSeries *s in vorschlag) if( s != [v currentSeries]) [andere addObject: s];
        NSString *m = nil;
        NSLog( @"%@ 1a: Shift-Lupe vor dem Stapel: %@", P, [self debugLupe: v]);
        if( [NSClassFromString( @"SekhmetOrientation") respondsToSelector: NSSelectorFromString( @"debugLayout2DTest:")])   // nur im Testbau vorhanden
            NSLog( @"%@ 0: 2D-Fenster folgt der MPR-Anordnung (Paket CP): %@", P, [NSClassFromString( @"SekhmetOrientation") performSelector: NSSelectorFromString( @"debugLayout2DTest:") withObject: v]);
        // Paket CK: Drop ohne Rueckfrage. Knopf aus -> 0 (Horos zeigt), bereit -> 1, wieder aus -> 0.
        DicomSeries *letzte = andere.count >= 2 ? [[[andere lastObject] retain] autorelease] : nil;
        if( andere.count)
        {
            int e0 = [self handwegEntscheidFuerSerie: andere[ 0] viewer: v];
            [self setzeBereit: YES viewer: v];
            int e1 = [self handwegEntscheidFuerSerie: andere[ 0] viewer: v];
            BOOL b1 = [self istBereit: v];
            [self setzeBereit: NO viewer: v];
            int e2 = [self handwegEntscheidFuerSerie: andere[ 0] viewer: v];
            NSLog( @"%@ 1b: Drop-Entscheid Knopf aus %d (erwartet 0), bereit %d/%@ (erwartet 1/JA), wieder aus %d (erwartet 0)", P, e0, e1, b1 ? @"JA" : @"NEIN", e2);
        }
        if( letzte) [andere removeLastObject];   // die letzte Serie kommt ueber den Drop-Weg dazu
        NSDate *t0 = [NSDate date];
        BOOL ok = [self staple: andere inViewer: v meldung: &m];
        if( letzte && [self stapelVon: v])
        {
            SekhmetStapel *vor = [self stapelVon: v];
            NSUInteger n0 = vor.count;
            int eMitglied = [self handwegEntscheidFuerSerie: andere[ 0] viewer: v];
            int eNeu = [self handwegEntscheidFuerSerie: letzte viewer: v];
            [self fuehreHandwegAus: @[ letzte, v]];
            SekhmetStapel *nach = [self stapelVon: v];
            NSLog( @"%@ 1c: Drop bei laufendem Stapel: Stapelserie %d (erwartet 2), neue Serie %d (erwartet 1), Stapel %lu -> %lu (erwartet +1), danach dieselbe Serie %d (erwartet 2)", P,
                  eMitglied, eNeu, (unsigned long) n0, (unsigned long) nach.count, [self handwegEntscheidFuerSerie: letzte viewer: v]);
            [self fuehreHandwegAus: @[ andere[ 0], v]];
            NSUInteger mZiel = [nach->serienUIDs indexOfObject: [andere[ 0] seriesInstanceUID] ?: @""];
            NSLog( @"%@ 1d: Stapelserie gezogen -> curMovieIndex %d (erwartet %lu), Stapel noch %lu", P, (int) [v curMovieIndex], (unsigned long) mZiel, (unsigned long) [self stapelVon: v].count);
            [self zeige: 0 inViewer: v];
        }
        SekhmetStapel *st = [self stapelVon: v];
        if( st == nil)
        {
            SekhmetStapel *roh = objc_getAssociatedObject( v, &SekhmetStapelKey);
            NSLog( @"%@ 2: KEIN Stapel -- staple %@, Meldung '%@', maxMovieIndex %d, roh %@ (count %lu, pixList gleich %@)", P, ok ? @"JA" : @"NEIN", m ?: @"-", [v maxMovieIndex],
                  roh ? @"da" : @"nil", (unsigned long) roh.count, roh && roh->refPixList == (void*) [v pixList: 0] ? @"ja" : @"nein");
            return;
        }
        BOOL geteilt = YES;
        for( int k = 1; k < [v maxMovieIndex]; k++) if( [v roiList: k] != [v roiList: 0]) geteilt = NO;
        NSMutableArray *chips = [NSMutableArray array];
        for( NSNumber *k in st->reihenfolge) [chips addObject: st->namen[ k.intValue]];
        NSLog( @"%@ 2: gestapelt %@ in %.1f s, maxMovieIndex %d, Chips [%@], ROI-Listen geteilt %@, Meldung %@", P, ok ? @"JA" : @"NEIN", -[t0 timeIntervalSinceNow], [v maxMovieIndex], [chips componentsJoinedByString: @", "], geteilt ? @"JA" : @"NEIN", m ?: @"-");
    }
    else if( schritt == 1)
    {
        SekhmetStapel *st = [self stapelVon: v];
        // Bezug (Index 0) und KM desselben Kerns suchen
        int km = -1;
        for( int k = 1; k < (int) st.count; k++)
            if( [st->phasen[ k] intValue] == 2 && [st->knochen[ k] boolValue] == [st->knochen[ 0] boolValue]) km = k;
        long n = [[v pixList: 0] count];
        long idx = n / 2;
        [[v imageView] setIndex: idx];
        DCMPix *pn = [v pixList: 0][ idx], *pk = km >= 0 ? [v pixList: km][ idx] : nil;
        long w = pn.pwidth, h = pn.pheight;
        // groesste mittlere Differenz KM − nativ (7x7) = Gefaess; hoechster nativer Mittelwert = Knochen
        double bestD = -1e9, bestB = -1e9; int gx = 0, gy = 0, bx = 0, by = 0;
        for( long y = 4; y < h - 4; y += 2) for( long x = 4; x < w - 4; x += 2)
        {
            double sn = 0, sk = 0;
            for( int dy = -3; dy <= 3; dy++) for( int dx = -3; dx <= 3; dx++)
            {
                sn += pn.fImage[ (y + dy) * w + x + dx];
                if( pk) sk += pk.fImage[ (y + dy) * w + x + dx];
            }
            sn /= 49; sk /= 49;
            if( pk && sn > -200 && sk - sn > bestD) { bestD = sk - sn; gx = (int) x; gy = (int) y; }
            if( sn > bestB) { bestB = sn; bx = (int) x; by = (int) y; }
        }
        NSMutableArray *roisHier = [[v roiList: 0] objectAtIndex: idx];
        gefaess = [[ROI alloc] initWithType: tOval :pn.pixelSpacingX :pn.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pn]];
        [gefaess setROIRect: NSMakeRect( gx, gy, 2.5, 2.5)]; [gefaess setName: @"E2E Gefaess"];
        knochen = [[ROI alloc] initWithType: tOval :pn.pixelSpacingX :pn.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pn]];
        [knochen setROIRect: NSMakeRect( bx, by, 2.5, 2.5)]; [knochen setName: @"E2E Knochen"];
        for( ROI *r in @[ gefaess, knochen]) { [[v imageView] roiSet: r]; [r setCurView: [v imageView]]; [roisHier addObject: r]; }
        [[v imageView] setNeedsDisplay: YES];
        NSLog( @"%@ 3: Schicht %ld, Gefaess (%d,%d) Diff %.0f, Knochen (%d,%d) nativ %.0f", P, idx, gx, gy, bestD, bx, by, bestB);
        NSLog( @"%@ 4: Zeile Gefaess: %@", P, [self enhancementZeileFuerROI: gefaess]);
        NSLog( @"%@ 4: Zeile Knochen: %@", P, [self enhancementZeileFuerROI: knochen]);
        BOOL inAllen = YES;
        for( int k = 0; k < [v maxMovieIndex]; k++) if( [[[v roiList: k] objectAtIndex: idx] containsObject: gefaess] == NO) inAllen = NO;
        NSLog( @"%@ 5: Messung in allen Serien derselben Schicht: %@", P, inAllen ? @"JA" : @"NEIN");
    }
    else if( schritt == 2)
    {
        DCMView *iv = [v imageView];
        [iv setScaleValue: 2.0]; [iv setOrigin: NSMakePoint( 20, -15)];
        scale = iv.scaleValue; origin = iv.origin; bild = iv.curImage;
        [iv setWLWW: 111 :777];
        [self schalte: v schritt: 1];
        float wl, ww; [iv getWLWW: &wl :&ww];
        NSLog( @"%@ 6: nach '<': Serie '%@', Schicht %ld->%ld, Zoom %.2f->%.2f, Ausschnitt %@->%@, Fenster %.0f/%.0f (eigenes, nicht 111/777)", P,
              [[v currentSeries] name], bild, (long) iv.curImage, scale, iv.scaleValue, NSStringFromPoint( origin), NSStringFromPoint( iv.origin), wl, ww);
        NSLog( @"%@ 7: Zeile Gefaess jetzt: %@", P, [self enhancementZeileFuerROI: gefaess]);
        NSLog( @"%@ 7a: Shift-Lupe im Stapel (Movie %d): %@", P, (int) [v curMovieIndex], [self debugLupe: v]);
        {   // Paket CN: der eigene Mittelwert der ROI folgt der sichtbaren Serie
            long i7 = iv.curImage; int cm7 = (int) [v curMovieIndex];
            float mw = 0, tot = 0, sd = 0, mn = 0, mx = 0;
            [gefaess.pix computeROI: gefaess :&mw :&tot :&sd :&mn :&mx];
            NSLog( @"%@ 7b: ROI rechnet auf der sichtbaren Serie %@ (Movie %d), eigener Mittelwert %.0f (erwartet der Contrast-Wert aus Zeile 7)", P, gefaess.pix == [v pixList: cm7][ i7] ? @"JA" : @"NEIN", cm7, mw);
        }
        [self schalte: v schritt: -1];
        [iv getWLWW: &wl :&ww];
        NSLog( @"%@ 8: nach '>': Serie '%@', Schicht %ld, Fenster %.0f/%.0f (erwartet 111/777)", P, [[v currentSeries] name], (long) iv.curImage, wl, ww);
        // Paket CL: die Taste auf dem Weg einer echten Eingabe (Fenster -> firstResponder -> keyDown:), nicht ueber schalte:
        NSEvent *ke = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0 windowNumber: [[v window] windowNumber] context: nil characters: @"<" charactersIgnoringModifiers: @"<" isARepeat: NO keyCode: 50];
        int vorher = (int) [v curMovieIndex];
        [[v window] sendEvent: ke];
        NSLog( @"%@ 8b: Taste '<' ueber das Fenster: firstResponder %@, Viewer ist keyWindow %@, curMovieIndex %d -> %d (erwartet Wechsel)", P,
              NSStringFromClass( [[[v window] firstResponder] class]), [NSApp keyWindow] == [v window] ? @"JA" : @"NEIN", vorher, (int) [v curMovieIndex]);
        [self zeige: 0 inViewer: v];
    }
    else if( schritt == 3)
    {
        // Speichern: nur an der Bezugsserie
        [v saveROI: 0];
        for( int k = 1; k < [v maxMovieIndex]; k++) [v saveROI: k];
        long idx = [[v imageView] curImage];
        DicomImage *ref = [[v fileList: 0] objectAtIndex: idx];
        DicomStudy *studie = [ref valueForKeyPath: @"series.study"];
        NSArray *rois = [[[studie roiSRSeries] valueForKey: @"images"] allObjects];
        NSMutableArray *andere = [NSMutableArray array];
        for( int k = 1; k < [v maxMovieIndex]; k++) [andere addObject: [studie roiPathForImage: [[v fileList: k] objectAtIndex: idx] inArray: rois] ? @"JA" : @"nein"];
        NSLog( @"%@ 9: ROI-Datei an der Bezugsserie %@, an den anderen: %@", P, [studie roiPathForImage: ref inArray: rois] ? @"JA" : @"FEHLT", [andere componentsJoinedByString: @" "]);
        // MPR oeffnen
        MPRController *mpr = [v openMPRViewer];
        NSLog( @"%@ 10: MPR %@, Serien im MPR %d", P, mpr ? @"offen" : @"NICHT offen", mpr ? mpr.maxMovieIndex + 1 : -1);
    }
    else if( schritt == 4)
    {
        MPRController *mpr = nil;
        for( NSWindow *w in [NSApp windows]) if( [[w windowController] isKindOfClass: [MPRController class]]) mpr = [w windowController];
        if( mpr)
        {
            DCMPix *a = [mpr.mprView1 curDCM];
            double s0 = 0; long n0 = 0; for( long i = 0; i < a.pwidth * a.pheight; i++) if( isfinite( a.fImage[ i])) { s0 += a.fImage[ i]; n0++; }
            NSEvent *e = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0 windowNumber: [[mpr window] windowNumber] context: nil characters: @"<" charactersIgnoringModifiers: @"<" isARepeat: NO keyCode: 50];
            BOOL genommen = [self handleKeyEvent: e inView: mpr.mprView1];
            [mpr.mprView1 display];

            DCMPix *b = [mpr.mprView1 curDCM];
            double s1 = 0; long n1 = 0; for( long i = 0; i < b.pwidth * b.pheight; i++) if( isfinite( b.fImage[ i])) { s1 += b.fImage[ i]; n1++; }
            NSLog( @"%@ 11: MPR-Taste genommen %@, curMovieIndex MPR %d / 2D %d, Mittel Ebene 1 %.1f -> %.1f", P, genommen ? @"JA" : @"NEIN", mpr.curMovieIndex, [v curMovieIndex], n0 ? s0 / n0 : 0, n1 ? s1 / n1 : 0);
            {   // Paket CN: Fenster je Serie auch im MPR; Knochenserie per Chip-Weg, Taste "y" zurueck
                SekhmetStapel *st = [self stapelVon: v];
                int kn = -1; for( int k = 0; k < (int) st.count; k++) if( [st->knochen[ k] boolValue]) kn = k;
                float wl = 0, ww = 0, wl2 = 0, ww2 = 0;
                if( kn >= 0)
                {
                    // Paket CO: ein Oval in der (jetzt gezeichneten) MPR-Ansicht — sein gemerkter Mittelwert muss beim Umschalten verfallen
                    DCMPix *pa = [mpr.mprView1 curDCM];
                    ROI *mo = [[[ROI alloc] initWithType: tOval :pa.pixelSpacingX :pa.pixelSpacingY :[DCMPix originCorrectedAccordingToOrientation: pa]] autorelease];
                    [mo setROIRect: NSMakeRect( pa.pwidth / 2, pa.pheight / 2, 6, 6)]; [mo setName: @"E2E MPR"];
                    [mpr.mprView1 roiSet: mo]; [mo setCurView: mpr.mprView1]; mo.pix = pa;
                    [[mpr.mprView1 curRoiList] addObject: mo];
                    float mwA = 0, mwB = 0, tot = 0, sd = 0, mn = 0, mx = 0;
                    [pa computeROI: mo :&mwA :&tot :&sd :&mn :&mx];
                    [mo setValue: @( 12345.f) forKey: @"rtotal"];      // "schon gerechnet"
                    [[mpr window] makeFirstResponder: mpr.mprView1];   // wie am Geraet: die Messung liegt in der gewaehlten Ansicht
                    [mpr.mprView1 display];
                    BOOL nachZeichnen = [[mpr.mprView1 curRoiList] containsObject: mo];
                    [mpr.mprView1 updateViewMPR];
                    BOOL nachUpdate = [[mpr.mprView1 curRoiList] containsObject: mo];
                    float rtUpdate = [[mo valueForKey: @"rtotal"] floatValue];
                    if( nachUpdate == NO) [[mpr.mprView1 curRoiList] addObject: mo];
                    [mo setValue: @( 12345.f) forKey: @"rtotal"];
                    NSLog( @"%@ 11a0: Oval nach Zeichnen in der Ansicht %@, nach updateViewMPR %@ (rtotal %.0f)", P, nachZeichnen ? @"JA" : @"NEIN", nachUpdate ? @"JA" : @"NEIN", rtUpdate);
                    NSDictionary *soll = st->fenster[ kn];
                    [self zeigeSerie: kn viewer: v];
                    [mpr.mprView1 display];
                    [[mpr.mprView1 curDCM] computeROI: mo :&mwB :&tot :&sd :&mn :&mx];
                    NSLog( @"%@ 11a-: gewaehlte Ansicht ist Ansicht 1: %@", P, [mpr selectedView] == mpr.mprView1 ? @"JA" : @"NEIN");
                    NSLog( @"%@ 11a: Oval im MPR: noch in der Ansicht %@, gemerkter Wert verfallen %@ (rtotal %.0f statt 12345), Mittelwert %.1f -> %.1f", P, [[mpr.mprView1 curRoiList] containsObject: mo] ? @"JA" : @"NEIN",
                          [[mo valueForKey: @"rtotal"] floatValue] != 12345.f ? @"JA" : @"NEIN", [[mo valueForKey: @"rtotal"] floatValue], mwA, mwB);
                    [[mpr.mprView1 curRoiList] removeObject: mo];
                    [mpr.mprView1 getWLWW: &wl :&ww]; [mpr.mprView3 getWLWW: &wl2 :&ww2];
                    NSLog( @"%@ 11c: MPR auf Knochenserie (Movie %d): Fenster Ansicht 1 %.0f/%.0f, Ansicht 3 %.0f/%.0f, Soll %@/%@", P, mpr.curMovieIndex, wl, ww, wl2, ww2, [soll isKindOfClass: [NSDictionary class]] ? soll[ @"wl"] : @"-", [soll isKindOfClass: [NSDictionary class]] ? soll[ @"ww"] : @"-");
                }
                int vorY = mpr.curMovieIndex;
                NSEvent *ey = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0 windowNumber: [[mpr window] windowNumber] context: nil characters: @"y" charactersIgnoringModifiers: @"y" isARepeat: NO keyCode: 6];
                BOOL gy = [self handleKeyEvent: ey inView: mpr.mprView1];
                [mpr.mprView1 getWLWW: &wl :&ww];
                NSLog( @"%@ 11d: Taste 'y' im MPR genommen %@, Movie %d -> %d (erwartet eine Serie zurueck), Fenster %.0f/%.0f", P, gy ? @"JA" : @"NEIN", vorY, mpr.curMovieIndex, wl, ww);
            }
        }
    }
    else if( schritt == 5)
    {
        // MPR wie ein Benutzer schliessen, eigener Durchlauf (nicht im selben Zyklus wie das Zeichnen)
        for( NSWindow *w in [NSApp windows]) if( [[w windowController] isKindOfClass: [MPRController class]]) [w performClose: nil];
        NSLog( @"%@ 11b: MPR geschlossen", P);
    }
    else if( schritt == 6)
    {
        // aufraeumen: Messungen weg, gespeicherten Zustand zuruecksetzen, Stapel beenden
        for( ROI *r in @[ gefaess, knochen]) [v deleteROI: r];
        [v saveROI: 0];
        [self beende: v];
        DicomSeries *andereSerie = nil;
        for( DicomSeries *s in [self vorschlagFuerViewer: v]) if( s != [v currentSeries]) andereSerie = s;
        NSLog( @"%@ 12: beendet, maxMovieIndex %d, gestapelt %@, Drop-Entscheid danach %d (erwartet 0) -- fertig", P, [v maxMovieIndex], [self istGestapelt: v] ? @"NOCH" : @"nein",
              andereSerie ? [self handwegEntscheidFuerSerie: andereSerie viewer: v] : -1);
        [gefaess release]; [knochen release]; gefaess = knochen = nil;
        NSLog( @"%@ 12a: Shift-Lupe nach dem Beenden: %@", P, [self debugLupe: v]);
    }
    else if( schritt == 7)
    {
        // Paket CM: der Knopf in der Symbolleiste, so wie sie wirklich haengt (ToolbarPanel)
        NSSegmentedControl *seg = nil;
        for( NSToolbarItem *it in [[v toolbar] items])
            if( [[it itemIdentifier] isEqualToString: SekhmetOverlayToolbarItemIdentifier] && [[it view] isKindOfClass: [NSSegmentedControl class]]) seg = (NSSegmentedControl*) [it view];
        if( seg == nil) NSLog( @"%@ 13: Knopf NICHT in der Symbolleiste (Leiste %@, %lu Elemente)", P, [v toolbar], (unsigned long) [[[v toolbar] items] count]);
        else
        {
            NSString *fensterKlasse = NSStringFromClass( [[[seg window] windowController] class]);
            BOOL findet = [self viewerFuerToolbarFenster: [seg window]] == v;
            [self segmentGeklickt: seg];
            SekhmetStapel *st = [self stapelVon: v];
            NSLog( @"%@ 13: Knopf in %@, findet den Viewer %@; Klick -> gestapelt %@ (%lu Serien), Segmente %ld (erwartet Serien + 2), firstResponder %@", P, fensterKlasse, findet ? @"JA" : @"NEIN",
                  st ? @"JA" : @"NEIN", (unsigned long) st.count, (long) [seg segmentCount], NSStringFromClass( [[[v window] firstResponder] class]));
            if( st)
            {
                // Paket CN: eine Serie abwaehlen -> kein Chip, nicht im Durchschalten, Rang gemerkt; wieder anwaehlen
                DicomSeries *ab = nil; NSUInteger mAb = [[st->reihenfolge lastObject] unsignedIntegerValue];
                for( DicomSeries *k in [self kandidatenFuerViewer: v]) if( [k.seriesInstanceUID isEqualToString: st->serienUIDs[ mAb]]) ab = k;
                NSUInteger kandidaten = [[self kandidatenFuerViewer: v] count];
                BOOL okAb = [self setzeSerie: ab an: NO viewer: v meldung: NULL];
                NSMutableArray *runde = [NSMutableArray array];
                for( int q = 0; q < 4; q++) { [self schalte: v schritt: 1]; [runde addObject: @( [v curMovieIndex])]; }
                NSLog( @"%@ 13b: %lu Kandidaten; '%@' abgewaehlt %@ -> Segmente %ld (erwartet 5), Durchschalten %@ (ohne Movie %lu), gemerkt %@", P, (unsigned long) kandidaten, st->namen[ mAb], okAb ? @"JA" : @"NEIN",
                      (long) [seg segmentCount], [runde componentsJoinedByString: @" "], (unsigned long) mAb, [[[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetOverlayDeselectedKey] componentsJoinedByString: @","]);
                BOOL okAn = [self setzeSerie: ab an: YES viewer: v meldung: NULL];
                DicomSeries *bez = nil;
                for( DicomSeries *k in [self kandidatenFuerViewer: v]) if( [k.seriesInstanceUID isEqualToString: st->serienUIDs[ 0]]) bez = k;
                BOOL bezug = bez ? [self setzeSerie: bez an: NO viewer: v meldung: NULL] : YES;
                [self zeige: 0 inViewer: v];
                NSLog( @"%@ 13c: wieder angewaehlt %@ -> Segmente %ld (erwartet 6), gemerkt '%@' (erwartet leer); Bezugsserie abwaehlbar %@ (erwartet NEIN)", P, okAn ? @"JA" : @"NEIN", (long) [seg segmentCount],
                      [[[NSUserDefaults standardUserDefaults] arrayForKey: SekhmetOverlayDeselectedKey] componentsJoinedByString: @","], bezug ? @"JA" : @"NEIN");
                int erwartet = [st->reihenfolge[ 1] intValue];   // vor dem Beenden lesen, danach ist der Stapel freigegeben
                [seg setSelectedSegment: 1];
                [self segmentGeklickt: seg];
                int nachChip = (int) [v curMovieIndex];
                [seg setSelectedSegment: [seg segmentCount] - 1];
                [self segmentGeklickt: seg];
                NSLog( @"%@ 14: Chip 2 geklickt -> curMovieIndex %d (erwartet %d); X geklickt -> gestapelt %@, Segmente %ld (erwartet 1)", P, nachChip, erwartet,
                      [self istGestapelt: v] ? @"NOCH" : @"nein", (long) [seg segmentCount]);
            }
        }
        NSLog( @"%@: fertig", P);
        [v release]; v = nil;
        return;
    }
    }
    @catch( NSException *e) { NSLog( @"%@: AUSNAHME in Schritt %d: %@", P, schritt, e); }
    schritt++;
    [self performSelector: _cmd withObject: nil afterDelay: 4];
}


// SekhVet Paket CX: Subtraktion End-to-End. Oeffnet KM (Ziel) und nativ (Maske) in zwei Fenstern, legt -- wie nach dem
// Ziehen -- die Maske nach vorne und ruft Horos' Fusion-Subtraktion. Prueft je Stichprobe, welche Maskenschicht
// tatsaechlich abgezogen wurde (beste Uebereinstimmung ueber alle Maskenschichten) gegen die Schicht am selben Ort
// (naechste sliceLocation).
static double sekhmetMittlererFehler( float *r, float *a0, float *b, long n)
{
    double s = 0; long k = 0;
    for( long p = 0; p < n; p += 7) { s += fabs( r[ p] - (a0[ p] - b[ p])); k++; }
    return k ? s / k : HUGE_VAL;
}

+ (void) debugSubtraktionE2E
{
    static int schritt = 0;
    static ViewerController *ziel = nil, *maske = nil;
    static NSMutableArray *proben = nil, *vorher = nil;
    static long maskeAnfang = -1;
    NSString *P = @"SekhVet Subtraktion-E2E";
    @try
    {
    if( schritt == 0)
    {
        ViewerController *v = nil;
        for( ViewerController *x in [ViewerController getDisplayed2DViewers])
            if( v == nil && [[x pixList] count] >= 10 && [[[x currentSeries] modality] isEqualToString: @"CT"]) v = x;
        if( v == nil) { NSLog( @"%@: kein CT-Viewer offen", P); return; }
        if( [v isEverythingLoaded] == NO) { [self performSelector: _cmd withObject: nil afterDelay: 3]; return; }
        NSArray *vs = [self vorschlagFuerViewer: v];
        if( vs.count < 2) { NSLog( @"%@: kein Paar nativ/KM im Vorschlag", P); return; }
        DicomSeries *nativ = vs[ 0], *km = vs[ 1];
        NSLog( @"%@ 1: Ziel (KM) '%@', Maske (nativ) '%@'", P, km.name, nativ.name);
        ziel = [[[BrowserController currentBrowser] loadSeries: km : nil : NO keyImagesOnly: NO] retain];
        maske = [[[BrowserController currentBrowser] loadSeries: nativ : nil : NO keyImagesOnly: NO] retain];
        schritt = 1;
        [self performSelector: _cmd withObject: nil afterDelay: 10];
        return;
    }
    if( schritt == 1)
    {
        if( [ziel isEverythingLoaded] == NO || [maske isEverythingLoaded] == NO) { [self performSelector: _cmd withObject: nil afterDelay: 3]; return; }
        NSArray *aPix = [ziel pixList], *bPix = [maske pixList];
        NSLog( @"%@ 2: Ziel %lu Schichten, Maske %lu Schichten, Groesse %ldx%ld / %ldx%ld", P, (unsigned long) aPix.count, (unsigned long) bPix.count,
              [aPix[ 0] pwidth], [aPix[ 0] pheight], [bPix[ 0] pwidth], [bPix[ 0] pheight]);
        // Maske auf eine feste Schicht in der Mitte, dann nach vorne (wie nach dem Ziehen aus diesem Fenster)
        [[maske imageView] setIndex: (short) (bPix.count / 2)];
        maskeAnfang = [[maske imageView] curImage];
        [[ziel window] makeKeyAndOrderFront: nil];
        [[maske window] makeKeyAndOrderFront: nil];

        proben = [NSMutableArray new]; vorher = [NSMutableArray new];
        for( int k = 1; k <= 5; k++)
        {
            NSUInteger i = aPix.count * k / 6;
            DCMPix *a = aPix[ i]; [a CheckLoad];
            [proben addObject: @( i)];
            [vorher addObject: [NSData dataWithBytes: a.fImage length: (NSUInteger) a.pwidth * a.pheight * sizeof( float)]];
        }
        NSLog( @"%@ 3: Maske steht auf Schicht %ld, vorderstes Fenster '%@', Sync-Modus Ziel %d", P, maskeAnfang,
              [[[ViewerController frontMostDisplayed2DViewer] currentSeries] name], (int) [[ziel imageView] syncro]);

        NSDate *t0 = [NSDate date];
        [ziel blendWithViewer: maske blendingType: 2];
        NSLog( @"%@ 4: Subtraktion in %.1f s", P, -[t0 timeIntervalSinceNow]);

        int gut = 0;
        for( NSUInteger k = 0; k < proben.count; k++)
        {
            NSUInteger i = [proben[ k] unsignedIntegerValue];
            DCMPix *a = aPix[ i];
            float *a0 = (float*) [vorher[ k] bytes];
            long n = (long) a.pwidth * a.pheight;
            // erwartet: naechste sliceLocation
            NSInteger jOrt = -1; double dOrt = HUGE_VAL;
            for( NSUInteger j = 0; j < bPix.count; j++)
            {
                double d = fabs( [(DCMPix*) bPix[ j] sliceLocation] - a.sliceLocation);
                if( d < dOrt) { dOrt = d; jOrt = j; }
            }
            // tatsaechlich abgezogen: Maskenschicht mit dem kleinsten Restfehler
            NSInteger jBest = -1; double fBest = HUGE_VAL;
            for( NSUInteger j = 0; j < bPix.count; j++)
            {
                DCMPix *b = bPix[ j]; [b CheckLoad];
                double f = sekhmetMittlererFehler( a.fImage, a0, b.fImage, n);
                if( f < fBest) { fBest = f; jBest = j; }
            }
            BOOL ok = jBest == jOrt && fBest < 0.5;
            if( ok) gut++;
            NSLog( @"%@ 5.%lu: Zielschicht %lu (Ort %.1f) -> abgezogen Maskenschicht %ld (Restfehler %.2f), erwartet %ld (Ort %.1f, Abstand %.2f mm) %@", P,
                  (unsigned long) k + 1, (unsigned long) i, a.sliceLocation, (long) jBest, fBest, (long) jOrt, [(DCMPix*) bPix[ jOrt] sliceLocation], dOrt, ok ? @"OK" : @"FALSCH");
        }
        NSLog( @"%@ 6: %d von %lu Stichproben mit der Maskenschicht am selben Ort (erwartet alle; Fehlerbild: immer Schicht %ld)", P, gut, (unsigned long) proben.count, maskeAnfang);
        // Gegenprobe: Maske in umgekehrter Reihenfolge -- nach Ort muss der Partner mitwandern (nach Index nicht)
        NSArray *rueck = [[bPix reverseObjectEnumerator] allObjects];
        int ortTreu = 0;
        for( NSNumber *n in proben)
        {
            NSInteger j = [self partnerVon: aPix[ n.unsignedIntegerValue] in: bPix], jr = [self partnerVon: aPix[ n.unsignedIntegerValue] in: rueck];
            if( j >= 0 && jr == (NSInteger) bPix.count - 1 - j) ortTreu++;
        }
        NSLog( @"%@ 7: Partner nach Ort bei umgekehrter Maske %d von %lu (erwartet alle)", P, ortTreu, (unsigned long) proben.count);
        schritt = 2;
    }
    }
    @catch( NSException *e) { NSLog( @"%@: Ausnahme %@", P, e); }
}


// SekhVet Paket DA: overlay started, extended and ended while an MPR is open. Expected: every change returns at once
// (deferred), the MPR is rebuilt with all series, the visible series, its window, the window frame and the three
// cameras are the same as before (max. difference < 0.01 mm), and the 2D viewer follows.
static NSString *svDAKameras( NSArray *a, NSArray *b)
{
    if( a.count != 3 || b.count != 3) return @"(keine Kameras)";
    float maxd = 0; NSString *wo = @"";
    for( int i = 0; i < 3; i++)
    {
        for( NSString *k in @[ @"pos", @"focal", @"up"])
            for( int j = 0; j < 3; j++)
            {
                float d = fabsf( [a[ i][ k][ j] floatValue] - [b[ i][ k][ j] floatValue]);
                if( d > maxd) { maxd = d; wo = [NSString stringWithFormat: @"Ansicht %d %@[%d] %.2f -> %.2f", i + 1, k, j, [a[ i][ k][ j] floatValue], [b[ i][ k][ j] floatValue]]; }
            }
        float ds = fabsf( [a[ i][ @"scale"] floatValue] - [b[ i][ @"scale"] floatValue]);
        if( ds > maxd) { maxd = ds; wo = [NSString stringWithFormat: @"Ansicht %d Zoom", i + 1]; }
    }
    return [NSString stringWithFormat: @"max. Abweichung %.4f %@ %@", maxd, maxd < 0.01f ? @"OK" : @"ABWEICHUNG", maxd < 0.01f ? @"" : wo];
}

+ (void) debugMPROverlayE2E
{
    static int schritt = 0;
    static ViewerController *v = nil;
    static MPRController *mpr0 = nil;
    static NSArray *kameras = nil, *andere = nil;
    static NSRect rahmen;
    static float wlSerie1 = 0, wwSerie1 = 0;
    NSString *P = @"SekhVet MPR-Overlay-E2E";
    @try
    {
    if( schritt == 0)
    {
        for( ViewerController *x in [ViewerController getDisplayed2DViewers])
            if( v == nil && [[x pixList] count] >= 10 && [[[x currentSeries] modality] isEqualToString: @"CT"]) v = [x retain];
        if( v == nil) { NSLog( @"%@: kein CT-Viewer offen", P); return; }
        if( [v isEverythingLoaded] == NO) { [v release]; v = nil; [self performSelector: _cmd withObject: nil afterDelay: 3]; return; }
        NSMutableArray *o = [NSMutableArray array];
        for( DicomSeries *s in [self vorschlagFuerViewer: v]) if( s != [v currentSeries]) [o addObject: s];
        if( o.count < 2) { NSLog( @"%@: weniger als zwei weitere Serien im Vorschlag (%lu)", P, (unsigned long) o.count); return; }
        andere = [o retain];
        NSLog( @"%@ 1: Viewer '%@', weitere Serien '%@', '%@'", P, [[v currentSeries] name], [o[ 0] name], [o[ 1] name]);
        [v mprViewer: nil];
        schritt = 1;
        [self performSelector: _cmd withObject: nil afterDelay: 8];
        return;
    }
    if( schritt == 1)
    {
        MPRController *m = [self mprFuer: v];
        if( m == nil) { NSLog( @"%@ 2: MPR NICHT offen", P); return; }
        NSRect f = [[m window] frame];
        rahmen = NSMakeRect( f.origin.x + 30, f.origin.y - 20, f.size.width - 60, f.size.height - 40);   // eigene Lage, die der Neuaufbau halten muss
        [[m window] setFrame: rahmen display: YES];
        [[m window] makeKeyAndOrderFront: nil];
        mpr0 = [m retain];
        {   // eigene Lage statt der Ausgangslage, die das Hanging Protocol ohnehin wieder herstellen wuerde
            NSArray *vorher = [m sekhmetCurrentViews];
            Camera *c = m.mprView2.camera;
            c.parallelScale = c.parallelScale * 0.6f;
            c.focalPoint = [Point3D pointWithX: c.focalPoint.x + 12 y: c.focalPoint.y z: c.focalPoint.z];
            c.position = [Point3D pointWithX: c.position.x + 12 y: c.position.y z: c.position.z];
            c.forceUpdate = YES;
            [m.mprView2 restoreCamera];
            [m.mprView2 updateViewMPR];
            NSLog( @"%@ 2a: Zoom und Ausschnitt der Ansicht 2 veraendert, gegen vorher %@ (Soll: ABWEICHUNG)", P, svDAKameras( vorher, [m sekhmetCurrentViews]));
        }
        schritt = 10;   // erst nach dem Einschwingen lesen und stapeln
        [self performSelector: _cmd withObject: nil afterDelay: 3];
        return;
    }
    if( schritt == 10)
    {
        MPRController *m = mpr0;
        kameras = [[m sekhmetCurrentViews] retain];
        NSLog( @"%@ 2: MPR offen, Serien %d, Kameras %@", P, m.maxMovieIndex + 1, kameras ? @"gelesen" : @"FEHLEN");
        NSString *meldung = @"x";
        BOOL ok = [self staple: @[ andere[ 0]] inViewer: v meldung: &meldung];
        NSLog( @"%@ 3: staple mit offenem MPR -> %@, Meldung %@, sofort gestapelt %@ (Soll: JA, (null), nein)", P, ok ? @"JA" : @"NEIN", meldung, [self istGestapelt: v] ? @"ja" : @"nein");
        schritt = 2;
        [self performSelector: _cmd withObject: nil afterDelay: 15];
        return;
    }
    if( schritt == 2)
    {
        MPRController *m = [self mprFuer: v];
        SekhmetStapel *st = [self stapelVon: v];
        NSLog( @"%@ 4: gestapelt %@ (%lu Serien), MPR neu %@, Serien im MPR %d, Rahmen gleich %@, Fenster vorne %@, Kameras %@", P,
              st ? @"JA" : @"NEIN", (unsigned long) st.count, (m && m != mpr0) ? @"JA" : @"NEIN", m ? m.maxMovieIndex + 1 : -1,
              (m && NSEqualRects( [[m window] frame], rahmen)) ? @"JA" : @"NEIN", [[m window] isKeyWindow] ? @"JA" : @"nein",
              svDAKameras( kameras, [m sekhmetCurrentViews]));
        if( m == nil || st == nil) { NSLog( @"%@: Abbruch", P); return; }
        [self zeigeSerie: 1 viewer: v];   // die zweite Serie sichtbar, MPR schaltet mit
        [m.mprView1 getWLWW: &wlSerie1 :&wwSerie1];
        NSLog( @"%@ 5: Serie 1 sichtbar: 2D %d, MPR %d, Fenster MPR %.0f/%.0f", P, [v curMovieIndex], m.curMovieIndex, wlSerie1, wwSerie1);
        [mpr0 release]; mpr0 = [m retain];
        [kameras release]; kameras = [[m sekhmetCurrentViews] retain];
        NSString *meldung = @"x";
        BOOL ok = [self staple: @[ andere[ 1]] inViewer: v meldung: &meldung];
        NSLog( @"%@ 6: dritte Serie mit offenem MPR -> %@, Meldung %@", P, ok ? @"JA" : @"NEIN", meldung);
        schritt = 3;
        [self performSelector: _cmd withObject: nil afterDelay: 15];
        return;
    }
    if( schritt == 3)
    {
        MPRController *m = [self mprFuer: v];
        SekhmetStapel *st = [self stapelVon: v];
        float wl = 0, ww = 0; [m.mprView1 getWLWW: &wl :&ww];
        NSLog( @"%@ 7: %lu Serien, MPR neu %@, Serien im MPR %d, sichtbar 2D %d / MPR %d (Soll 1/1), Fenster %.0f/%.0f (Soll %.0f/%.0f), Rahmen gleich %@, Kameras %@", P,
              (unsigned long) st.count, (m && m != mpr0) ? @"JA" : @"NEIN", m ? m.maxMovieIndex + 1 : -1, [v curMovieIndex], m.curMovieIndex,
              wl, ww, wlSerie1, wwSerie1, (m && NSEqualRects( [[m window] frame], rahmen)) ? @"JA" : @"NEIN", svDAKameras( kameras, [m sekhmetCurrentViews]));
        // Taste "<" im MPR schaltet weiter
        NSEvent *e = [NSEvent keyEventWithType: NSEventTypeKeyDown location: NSZeroPoint modifierFlags: 0 timestamp: 0 windowNumber: [[m window] windowNumber] context: nil characters: @"<" charactersIgnoringModifiers: @"<" isARepeat: NO keyCode: 50];
        BOOL genommen = [self handleKeyEvent: e inView: m.mprView1];
        NSLog( @"%@ 8: Taste < im MPR genommen %@, sichtbar jetzt 2D %d / MPR %d", P, genommen ? @"JA" : @"NEIN", [v curMovieIndex], m.curMovieIndex);
        [mpr0 release]; mpr0 = [m retain];
        [kameras release]; kameras = [[m sekhmetCurrentViews] retain];
        [self beende: v];
        NSLog( @"%@ 9: beenden mit offenem MPR, sofort noch gestapelt %@ (Soll: ja)", P, [self istGestapelt: v] ? @"ja" : @"nein");
        schritt = 4;
        [self performSelector: _cmd withObject: nil afterDelay: 12];
        return;
    }
    if( schritt == 4)
    {
        MPRController *m = [self mprFuer: v];
        NSLog( @"%@ 10: gestapelt %@ (Soll nein), MPR neu %@, Serien im MPR %d (Soll 1), 2D Index %d, Rahmen gleich %@, Kameras %@", P,
              [self istGestapelt: v] ? @"ja" : @"nein", (m && m != mpr0) ? @"JA" : @"NEIN", m ? m.maxMovieIndex + 1 : -1, [v curMovieIndex],
              (m && NSEqualRects( [[m window] frame], rahmen)) ? @"JA" : @"NEIN", svDAKameras( kameras, [m sekhmetCurrentViews]));
        NSLog( @"%@ 10b: Rahmen Soll %@ / Ist %@", P, NSStringFromRect( rahmen), NSStringFromRect( [[m window] frame]));
        NSUInteger knopf = 0;
        for( NSToolbarItem *it in [[[m window] toolbar] items]) if( [[it itemIdentifier] isEqualToString: @"SekhmetMPROverlay"]) knopf++;
        NSLog( @"%@ 11: Overlay-Knopf in der MPR-Leiste %lu (Soll 1)", P, (unsigned long) knopf);
        [[m window] close];
        NSLog( @"%@: fertig", P);
        schritt = 5;
    }
    }
    @catch( NSException *x) { NSLog( @"%@: Ausnahme %@", P, x); }
}

#endif // SEKHVET_TESTHAKEN

@end

#pragma mark - ViewerController (SekhVetUeberlagerung)

@implementation ViewerController (SekhVetUeberlagerung)

- (void) sekhmetUeberlagerungTeileROIs:(int) m
{
    if( m <= 0 || m >= maxMovieIndex || roiList[ m] == roiList[ 0]) return;
    [roiList[ m] release];
    roiList[ m] = [roiList[ 0] retain];
    if( curMovieIndex == m) [imageView setNeedsDisplay: YES];
}

// SekhVet Paket CS: Horos' 4D slider and Play button call -setMovieIndex: directly (no per-series window, deselected
// series shown, Play would cycle the series at movie rate). While stacked the chips and the keys do the switching, so
// the 4D controls are off; sekhmetUeberlagerungEntferneAb: leaves them the way Horos has them without 4D data.
- (void) sekhmetUeberlagerungSperre4DBedienung
{
    [movieRateSlider setEnabled: NO];
    [moviePosSlider setEnabled: NO];
    [moviePlayStop setEnabled: NO];
}

- (void) sekhmetUeberlagerungEntferneAb:(int) m
{
    if( m < 1 || m >= maxMovieIndex) return;
    if( curMovieIndex >= m) [self setMovieIndex: 0];
    for( int i = maxMovieIndex - 1; i >= m; i--)
    {
        [copyRoiList[ i] release]; copyRoiList[ i] = nil;
        [roiList[ i] release]; roiList[ i] = nil;          // geteilte Liste: nur unsere Referenz
        [pixList[ i] release]; pixList[ i] = nil;
        [fileList[ i] release]; fileList[ i] = nil;
        [self sendWillFreeVolumeDataNotificationWithVolumeData: volumeData[ i] movieIndex: i];
        [volumeData[ i] release]; volumeData[ i] = nil;
    }
    maxMovieIndex = m;
    [moviePosSlider setMaxValue: MAX( 0, maxMovieIndex - 1)];
    [moviePosSlider setNumberOfTickMarks: maxMovieIndex];
    BOOL vier = maxMovieIndex > 1;
    [movieRateSlider setEnabled: vier];
    [moviePosSlider setEnabled: vier];
    [moviePlayStop setEnabled: vier];
}

@end
