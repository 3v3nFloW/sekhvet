// SekhVet Paket EE: monitors and workplaces (viewer area per screen, remembered per monitor combination).
// Foundation only, so SekhVet/test/arbeitsplatz-test.sh can run it without the app.
//
// Seen 21.10.2026: the viewer area per screen was stored under the display number macOS hands out
// ("id<NSScreenNumber>", index as fallback). That number is not stable -- one installation's prefs carried id1, id2 and id3
// for the one 49-inch monitor -- and the index fallback put "Screen 2: right half" on whatever monitor came second at
// another desk. Two identical 27-inch monitors could not be told apart at all.
//
// Now:
//   - a monitor is known by vendor, model and serial number from its EDID (name only when there is no EDID); two
//     monitors with the same key (same model without serial, or a shared serial) get #1, #2 from left to right;
//   - a workplace is the set of connected monitors; every workplace keeps its own areas, viewer screens and database
//     window place. A workplace seen for the first time starts with the full area on every screen.
//
// A monitor description is a dictionary: vendor, model, serial (NSNumber), name (NSString), x, y (NSNumber, origin of
// the screen frame in global coordinates), w, h (NSNumber, size of the screen frame).

#ifndef SEKHMET_ARBEITSPLATZ_H
#define SEKHMET_ARBEITSPLATZ_H

#import <Foundation/Foundation.h>

enum {
    SekhmetAreaFull = 0,
    SekhmetAreaLeftHalf = 1,
    SekhmetAreaRightHalf = 2,
    SekhmetAreaLeftTwoThirds = 3,
    SekhmetAreaRightTwoThirds = 4,
    SekhmetAreaCenterHalf = 5,
    SekhmetAreaPixelRect = 9
};

// key of one monitor without the position suffix
static inline NSString *sekhmetMonitorBasis( NSDictionary *m)
{
    unsigned v = [[m objectForKey: @"vendor"] unsignedIntValue], mo = [[m objectForKey: @"model"] unsignedIntValue], s = [[m objectForKey: @"serial"] unsignedIntValue];
    if( v == 0 && mo == 0)   // no EDID (virtual or AirPlay display): the name is all there is
    {
        NSString *n = [m objectForKey: @"name"];
        return [NSString stringWithFormat: @"n:%@", [n length] ? n : @"?"];
    }
    if( s) return [NSString stringWithFormat: @"%04x-%04x-%u", v, mo, s];
    return [NSString stringWithFormat: @"%04x-%04x", v, mo];
}

static inline NSComparisonResult sekhmetMonitorLinksVorRechts( NSDictionary *a, NSDictionary *b)
{
    double ax = [[a objectForKey: @"x"] doubleValue], bx = [[b objectForKey: @"x"] doubleValue];
    if( ax != bx) return ax < bx ? NSOrderedAscending : NSOrderedDescending;
    double ay = [[a objectForKey: @"y"] doubleValue], by = [[b objectForKey: @"y"] doubleValue];   // one above the other: the upper one first
    if( ay != by) return ay > by ? NSOrderedAscending : NSOrderedDescending;
    return NSOrderedSame;
}

// keys of all monitors, in the order of the input; equal keys get #1, #2, ... from left to right (then top to bottom)
static inline NSArray *sekhmetMonitorKennungen( NSArray *monitore)
{
    NSMutableArray *basis = [NSMutableArray array];
    for( NSDictionary *m in monitore) [basis addObject: sekhmetMonitorBasis( m)];
    NSMutableArray *k = [NSMutableArray arrayWithArray: basis];
    for( NSUInteger i = 0; i < basis.count; i++)
    {
        NSString *b = [basis objectAtIndex: i];
        NSMutableArray *gleiche = [NSMutableArray array];
        for( NSUInteger j = 0; j < basis.count; j++)
            if( [[basis objectAtIndex: j] isEqualToString: b]) [gleiche addObject: [monitore objectAtIndex: j]];
        if( gleiche.count < 2) continue;
        NSArray *sortiert = [gleiche sortedArrayUsingComparator: ^NSComparisonResult( id a, id c) { return sekhmetMonitorLinksVorRechts( a, c); }];
        NSUInteger rang = [sortiert indexOfObjectIdenticalTo: [monitore objectAtIndex: i]];
        [k replaceObjectAtIndex: i withObject: [NSString stringWithFormat: @"%@#%d", b, (int) rang + 1]];
    }
    return k;
}

// key of the workplace: the monitor keys sorted, so the order macOS lists the screens in does not matter
static inline NSString *sekhmetArbeitsplatzKennung( NSArray *kennungen)
{
    return [[kennungen sortedArrayUsingSelector: @selector(compare:)] componentsJoinedByString: @" + "];
}

// where a monitor sits, for the labels: "left", "middle", "right" (or "top"/"bottom" when they are stacked); nil alone
static inline NSString *sekhmetMonitorLage( NSArray *monitore, NSUInteger i)
{
    NSUInteger n = monitore.count;
    if( n < 2 || i >= n) return nil;
    NSArray *sortiert = [monitore sortedArrayUsingComparator: ^NSComparisonResult( id a, id c) { return sekhmetMonitorLinksVorRechts( a, c); }];
    NSUInteger rang = [sortiert indexOfObjectIdenticalTo: [monitore objectAtIndex: i]];
    double minX = 1e9, maxX = -1e9, minY = 1e9, maxY = -1e9;
    for( NSDictionary *m in monitore)
    {
        double x = [[m objectForKey: @"x"] doubleValue] + [[m objectForKey: @"w"] doubleValue] / 2, y = [[m objectForKey: @"y"] doubleValue] + [[m objectForKey: @"h"] doubleValue] / 2;
        minX = MIN( minX, x); maxX = MAX( maxX, x); minY = MIN( minY, y); maxY = MAX( maxY, y);
    }
    BOOL gestapelt = (maxY - minY) > (maxX - minX);
    if( gestapelt)   // sorted by x first: for a stack sort by height instead
    {
        sortiert = [monitore sortedArrayUsingComparator: ^NSComparisonResult( NSDictionary *a, NSDictionary *c) {
            double ay = [[a objectForKey: @"y"] doubleValue], cy = [[c objectForKey: @"y"] doubleValue];
            return ay == cy ? NSOrderedSame : (ay > cy ? NSOrderedAscending : NSOrderedDescending); }];
        rang = [sortiert indexOfObjectIdenticalTo: [monitore objectAtIndex: i]];
        if( rang == 0) return @"top";
        if( rang == n - 1) return @"bottom";
        return n == 3 ? @"middle" : [NSString stringWithFormat: @"%d from top", (int) rang + 1];
    }
    if( rang == 0) return @"left";
    if( rang == n - 1) return @"right";
    return n == 3 ? @"middle" : [NSString stringWithFormat: @"%d from left", (int) rang + 1];
}

// the rectangle of a fraction mode inside the visible frame f; the pixel rectangle is handled by the caller
static inline NSRect sekhmetFlaecheRechteck( NSInteger mode, NSRect f)
{
    switch( mode)
    {
        case SekhmetAreaLeftHalf:       f.size.width = f.size.width / 2.; break;
        case SekhmetAreaRightHalf:      f.origin.x += f.size.width / 2.; f.size.width = f.size.width / 2.; break;
        case SekhmetAreaLeftTwoThirds:  f.size.width = f.size.width * 2. / 3.; break;
        case SekhmetAreaRightTwoThirds: f.origin.x += f.size.width / 3.; f.size.width = f.size.width * 2. / 3.; break;
        case SekhmetAreaCenterHalf:     f.origin.x += f.size.width / 4.; f.size.width = f.size.width / 2.; break;
        default: break;
    }
    return f;
}

// "Use this window's position": a window frame w on a screen with the visible frame f becomes the nearest fraction
// mode when both side edges are within 4 % of the width (at least 40 pt) and it is at least 80 % as high; otherwise
// the pixel rectangle, written to *rect as "x y w h" relative to f. -1 when the window hardly lies on that screen.
static inline NSInteger sekhmetFlaecheEinrasten( NSRect w, NSRect f, NSString **rect)
{
    NSRect i = NSIntersectionRect( w, f);
    if( i.size.width < 200 || i.size.height < 200) return -1;
    double tol = MAX( 40., f.size.width * 0.04), bester = 1e9;
    NSInteger modus = -1;
    if( i.size.height >= f.size.height * 0.8)
    {
        for( NSInteger m = SekhmetAreaFull; m <= SekhmetAreaCenterHalf; m++)
        {
            NSRect c = sekhmetFlaecheRechteck( m, f);
            double links = fabs( NSMinX( i) - NSMinX( c)), rechts = fabs( NSMaxX( i) - NSMaxX( c));
            if( links <= tol && rechts <= tol && links + rechts < bester) { bester = links + rechts; modus = m; }
        }
    }
    if( modus >= 0) return modus;
    if( rect) *rect = [NSString stringWithFormat: @"%.0f %.0f %.0f %.0f", NSMinX( i) - NSMinX( f), NSMinY( i) - NSMinY( f), i.size.width, i.size.height];
    return SekhmetAreaPixelRect;
}

#endif
