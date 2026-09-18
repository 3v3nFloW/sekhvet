/*=========================================================================
 SekhVet — Ultraschall-Kalibrierung von einem Nachbarbild uebernehmen (Paket BH).
 Regel und Anlass: siehe SekhmetUSKalibrierung.h.
 Teil des SekhVet-Forks von Horos, LGPL-3.0.
 ============================================================================*/

#import "SekhmetUSKalibrierung.h"
#import "DCMPix.h"

static NSString * const kFallbackKey = @"SekhmetUSCalibrationFallback";
static const double kMinIoU = 0.9;
static const int kMinMaskPixels = 100;

@implementation SekhmetBorrowedUSRegion

@synthesize sourceLabel;

+ (SekhmetBorrowedUSRegion*) borrowedRegionFrom:(DCMUSRegion*) r label:(NSString*) label
{
    SekhmetBorrowedUSRegion *c = [[[SekhmetBorrowedUSRegion alloc] init] autorelease];
    c.regionSpatialFormat = r.regionSpatialFormat;
    c.regionDataType = r.regionDataType;
    c.regionFlags = r.regionFlags;
    c.regionLocationMinX0 = r.regionLocationMinX0;
    c.regionLocationMinY0 = r.regionLocationMinY0;
    c.regionLocationMaxX1 = r.regionLocationMaxX1;
    c.regionLocationMaxY1 = r.regionLocationMaxY1;
    c.referencePixelX0 = r.referencePixelX0;
    c.referencePixelY0 = r.referencePixelY0;
    c.isReferencePixelX0Present = r.isReferencePixelX0Present;
    c.isReferencePixelY0Present = r.isReferencePixelY0Present;
    c.physicalUnitsXDirection = r.physicalUnitsXDirection;
    c.physicalUnitsYDirection = r.physicalUnitsYDirection;
    c.refPixelPhysicalValueX = r.refPixelPhysicalValueX;
    c.refPixelPhysicalValueY = r.refPixelPhysicalValueY;
    c.physicalDeltaX = r.physicalDeltaX;
    c.physicalDeltaY = r.physicalDeltaY;
    c.dopplerCorrectionAngle = r.dopplerCorrectionAngle;
    c.sourceLabel = label;
    return c;
}

- (void) dealloc
{
    [sourceLabel release];
    [super dealloc];
}

@end

// Kategorie: usRegions ist nach aussen nur lesbar, die Instanzvariablen erreicht nur DCMPix selbst.
@interface DCMPix (SekhmetUSKalibrierung)
- (void) sekhmetSetBorrowedUSRegions:(NSArray*) regions spacingX:(double) sx spacingY:(double) sy;
@end

@implementation DCMPix (SekhmetUSKalibrierung)

- (void) sekhmetSetBorrowedUSRegions:(NSArray*) regions spacingX:(double) sx spacingY:(double) sy
{
    [usRegions release];
    usRegions = [[NSMutableArray arrayWithArray: regions] retain];
    pixelSpacingX = sx;
    pixelSpacingY = sy;
    pixelSpacingFromUltrasoundRegions = YES;
}

@end

@implementation SekhmetUSKalibrierung

+ (BOOL) isUS:(DCMPix*) p
{
    return [[p modalityString] isEqualToString: @"US"];
}

+ (DCMUSRegion*) calibrated2DRegionOf:(DCMPix*) p
{
    for( DCMUSRegion *r in [p usRegions])
    {
        if( r.regionSpatialFormat == 1 && r.physicalUnitsXDirection == 3 && r.physicalUnitsYDirection == 3 && r.physicalDeltaX != 0 && r.physicalDeltaY != 0)
            return r;
    }
    return nil;
}

+ (NSString*) borrowedSourceForPix:(DCMPix*) pix
{
    if( [pix hasUSRegions] == NO) return nil;
    for( DCMUSRegion *r in [pix usRegions])
    {
        if( [r isKindOfClass: [SekhmetBorrowedUSRegion class]])
            return [(SekhmetBorrowedUSRegion*) r sourceLabel];
    }
    return nil;
}

// Helligkeit je Pixel im Streifen; RGB liegt in fImage als ARGB-Bytes.
static double *rulerLuminance( DCMPix *p, int x0, int x1, int y0, int y1, int offset)
{
    float *img = [p fImage];
    if( img == NULL) return NULL;
    long w = [p pwidth], h = [p pheight];
    int sw = x1 - x0, sh = y1 - y0;
    double *out = calloc( (size_t) sw * sh, sizeof( double));
    if( out == NULL) return NULL;
    BOOL rgb = [p isRGB];
    for( int y = 0; y < sh; y++)
    {
        long sy = y0 + y - offset;
        if( sy < 0 || sy >= h) continue;
        for( int x = 0; x < sw; x++)
        {
            long i = x0 + x + sy * w;
            double v;
            if( rgb)
            {
                unsigned char *px = ((unsigned char*) img) + 4 * i;
                v = MAX( px[1], MAX( px[2], px[3]));
            }
            else v = img[ i];
            out[ x + y * sw] = v;
        }
    }
    return out;
}

static int rulerMask( double *lum, int n, BOOL *mask)
{
    double lo = lum[0], hi = lum[0];
    for( int i = 1; i < n; i++) { if( lum[i] < lo) lo = lum[i]; if( lum[i] > hi) hi = lum[i]; }
    if( hi <= lo) return 0;
    double t = lo + 0.5 * (hi - lo);
    int count = 0;
    for( int i = 0; i < n; i++) { mask[i] = lum[i] > t; if( mask[i]) count++; }
    return count;
}

+ (double) rulerIoUBetween:(DCMPix*) a and:(DCMPix*) b region:(DCMUSRegion*) r offsetB:(int) offsetB
{
    long w = [a pwidth], h = [a pheight];
    if( w != [b pwidth] || h != [b pheight] || [a isRGB] != [b isRGB] || w < 100 || h < 100) return -1;

    int x1 = (int) w, x0 = (int) (w - MAX( 40, (long) (w * 0.08)));
    int y0 = MAX( 0, r.regionLocationMinY0), y1 = MIN( (int) h, r.regionLocationMaxY1);
    if( y1 - y0 < 50) return -1;
    int n = (x1 - x0) * (y1 - y0);

    double *la = rulerLuminance( a, x0, x1, y0, y1, 0);
    double *lb = rulerLuminance( b, x0, x1, y0, y1, offsetB);
    BOOL *ma = calloc( n, sizeof( BOOL)), *mb = calloc( n, sizeof( BOOL));
    double iou = -1;
    if( la && lb && ma && mb)
    {
        int ca = rulerMask( la, n, ma), cb = rulerMask( lb, n, mb);
        if( ca >= kMinMaskPixels && cb >= kMinMaskPixels)
        {
            int inter = 0, uni = 0;
            for( int i = 0; i < n; i++) { if( ma[i] && mb[i]) inter++; if( ma[i] || mb[i]) uni++; }
            iou = uni ? (double) inter / uni : -1;
        }
    }
    free( la); free( lb); free( ma); free( mb);
    return iou;
}

+ (NSUInteger) borrowCalibrationInPixList:(NSArray*) pixList labels:(NSArray*) labels
{
    NSNumber *enabled = [[NSUserDefaults standardUserDefaults] objectForKey: kFallbackKey];
    if( enabled && [enabled boolValue] == NO) return 0;
    if( pixList.count < 2 || labels.count != pixList.count) return 0;

    NSUInteger done = 0;
    for( NSUInteger i = 0; i < pixList.count; i++)
    {
        DCMPix *p = [pixList objectAtIndex: i];
        if( [self isUS: p] == NO || [p hasUSRegions] || ([p pixelSpacingX] != 0 && [p pixelSpacingY] != 0)) continue;

        // naechstgelegenen passenden Spender suchen: i-1, i+1, i-2, ...
        for( NSUInteger d = 1; d < pixList.count; d++)
        {
            DCMPix *donor = nil;
            NSUInteger k = 0;
            for( int side = 0; side < 2 && donor == nil; side++)
            {
                if( side == 0 && i < d) continue;
                k = side == 0 ? i - d : i + d;
                if( k >= pixList.count) continue;
                DCMPix *c = [pixList objectAtIndex: k];
                DCMUSRegion *r = [self calibrated2DRegionOf: c];
                if( r == nil || [self isUS: c] == NO || [self borrowedSourceForPix: c]) continue;
                double iou = [self rulerIoUBetween: p and: c region: r offsetB: 0];
                if( iou >= kMinIoU)
                {
                    donor = c;
                    NSString *label = [labels objectAtIndex: k];
                    NSMutableArray *copies = [NSMutableArray array];
                    for( DCMUSRegion *dr in [c usRegions])
                        [copies addObject: [SekhmetBorrowedUSRegion borrowedRegionFrom: dr label: label]];
                    [p sekhmetSetBorrowedUSRegions: copies spacingX: fabs( r.physicalDeltaX) * 10. spacingY: fabs( r.physicalDeltaY) * 10.];
                    NSLog( @"SekhVet US calibration: %@ takes calibration of %@ (depth scale IoU %.3f, %.4f mm/px)", [labels objectAtIndex: i], label, iou, [p pixelSpacingX]);
                    done++;
                }
            }
            if( donor) break;
        }
    }
    return done;
}

#if SEKHVET_TESTHAKEN
+ (NSString*) debugSelfTestWithDirectory:(NSString*) dir
{
    NSMutableString *log = [NSMutableString stringWithString: @"\n"];
    NSMutableArray *pixs = [NSMutableArray array], *labels = [NSMutableArray array];
    for( NSString *f in [[[NSFileManager defaultManager] contentsOfDirectoryAtPath: dir error: nil] sortedArrayUsingSelector: @selector(compare:)])
    {
        if( [[f pathExtension] caseInsensitiveCompare: @"dcm"] != NSOrderedSame) continue;
        DCMPix *p = [[[DCMPix alloc] initWithPath: [dir stringByAppendingPathComponent: f] :0 :1 :NULL :0 :0] autorelease];
        [p CheckLoad];
        if( p.modalityString == nil) p.modalityString = @"US"; // im Viewer setzt das die Datenbank (series.modality)
        [pixs addObject: p];
        [labels addObject: f];
    }
    for( NSUInteger i = 0; i < pixs.count; i++)
        [log appendFormat: @"  before %@: US=%d regions=%d spacing=%.4f\n", labels[i], [self isUS: pixs[i]], [pixs[i] hasUSRegions], [pixs[i] pixelSpacingX]];

    // Gegenprobe: Spender gegen sich selbst, senkrecht verschoben (andere Tiefe verschiebt die Striche)
    for( DCMPix *p in pixs)
    {
        DCMUSRegion *r = [self calibrated2DRegionOf: p];
        if( r == nil) continue;
        [log appendFormat: @"  shift test on first calibrated image: 0px %.3f, 1px %.3f, 4px %.3f, 12px %.3f\n",
            [self rulerIoUBetween: p and: p region: r offsetB: 0], [self rulerIoUBetween: p and: p region: r offsetB: 1],
            [self rulerIoUBetween: p and: p region: r offsetB: 4], [self rulerIoUBetween: p and: p region: r offsetB: 12]];
        break;
    }

    NSUInteger n = [self borrowCalibrationInPixList: pixs labels: labels];
    [log appendFormat: @"  borrowed: %lu\n", (unsigned long) n];
    for( NSUInteger i = 0; i < pixs.count; i++)
        [log appendFormat: @"  after %@: regions=%d spacing=%.4f source=%@\n", labels[i], [pixs[i] hasUSRegions], [pixs[i] pixelSpacingX], [self borrowedSourceForPix: pixs[i]] ?: @"-"];
    return log;
}
#endif // SEKHVET_TESTHAKEN

@end
