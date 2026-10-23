// SekhVet Paket EE: unit test of monitor keys, workplaces and snapping (SekhmetArbeitsplatz.h).
// The case of 21.10.2026: two identical 27-inch monitors, the right half of the second one for the report.
#import <Foundation/Foundation.h>
#import "SekhmetArbeitsplatz.h"

static int ok = 0, bad = 0;
static void check( const char *what, NSString *got, NSString *want)
{
    if( (got == nil && want == nil) || [got isEqualToString: want]) { ok++; printf( "ok   %-58s %s\n", what, [[got description] UTF8String]); }
    else { bad++; printf( "FAIL %-58s %s (expected %s)\n", what, [[got description] UTF8String], [[want description] UTF8String]); }
}
static NSString *num( NSInteger i) { return [NSString stringWithFormat: @"%ld", (long) i]; }

static NSDictionary *mon( unsigned v, unsigned m, unsigned s, NSString *name, double x, double y, double w, double h)
{
    return @{ @"vendor": @(v), @"model": @(m), @"serial": @(s), @"name": name, @"x": @(x), @"y": @(y), @"w": @(w), @"h": @(h) };
}

int main( void)
{
    @autoreleasepool
    {
        // two DELL U2723QE without serial; macOS lists the right one first (it is the main display)
        NSDictionary *rechts = mon( 0x10ac, 0xa0c4, 0, @"DELL U2723QE", 2560, 0, 2560, 1440);
        NSDictionary *links  = mon( 0x10ac, 0xa0c4, 0, @"DELL U2723QE", 0, 0, 2560, 1440);
        NSArray *k = sekhmetMonitorKennungen( @[ rechts, links]);
        check( "1 identical monitors: right one is #2", [k objectAtIndex: 0], @"10ac-a0c4#2");
        check( "2 identical monitors: left one is #1", [k objectAtIndex: 1], @"10ac-a0c4#1");
        NSArray *k2 = sekhmetMonitorKennungen( @[ links, rechts]);
        check( "3 other screen order: same keys", [k2 objectAtIndex: 1], @"10ac-a0c4#2");
        check( "4 workplace key independent of screen order", sekhmetArbeitsplatzKennung( k), sekhmetArbeitsplatzKennung( k2));
        check( "5 workplace key", sekhmetArbeitsplatzKennung( k), @"10ac-a0c4#1 + 10ac-a0c4#2");
        check( "6 place of the right one", sekhmetMonitorLage( @[ rechts, links], 0), @"right");
        check( "7 place of the left one", sekhmetMonitorLage( @[ rechts, links], 1), @"left");

        // with serial numbers: no suffix, and the key survives a new display number / port
        NSDictionary *a = mon( 0x10ac, 0xa0c4, 811, @"DELL U2723QE", 0, 0, 2560, 1440);
        NSDictionary *b = mon( 0x10ac, 0xa0c4, 812, @"DELL U2723QE", 2560, 0, 2560, 1440);
        NSArray *ks = sekhmetMonitorKennungen( @[ a, b]);
        check( "8 serial distinguishes", [ks objectAtIndex: 0], @"10ac-a0c4-811");
        NSDictionary *bVertauscht = mon( 0x10ac, 0xa0c4, 812, @"DELL U2723QE", -2560, 0, 2560, 1440);   // arrangement swapped in System Settings
        check( "9 serial: key follows the monitor, not the place", [sekhmetMonitorKennungen( @[ a, bVertauscht]) objectAtIndex: 1], @"10ac-a0c4-812");
        check( "10 a shared serial gets the position suffix", [sekhmetMonitorKennungen( @[ a, mon( 0x10ac, 0xa0c4, 811, @"DELL U2723QE", 2560, 0, 2560, 1440)]) objectAtIndex: 1], @"10ac-a0c4-811#2");

        // three workplaces of one laptop are three different keys
        NSDictionary *intern = mon( 0x610, 0xa050, 0, @"Built-in Retina Display", 0, 0, 1728, 1117);
        NSDictionary *s49 = mon( 0x4c2d, 0x7181, 0x4d5a3330, @"LS49A950U", 1728, 0, 5120, 1440);
        NSString *allein = sekhmetArbeitsplatzKennung( sekhmetMonitorKennungen( @[ intern]));
        NSString *mit49 = sekhmetArbeitsplatzKennung( sekhmetMonitorKennungen( @[ intern, s49]));
        NSString *praxis = sekhmetArbeitsplatzKennung( sekhmetMonitorKennungen( @[ intern, rechts, links]));
        check( "11 laptop alone", allein, @"0610-a050");
        check( "12 laptop + 49 inch differs", [mit49 isEqualToString: allein] ? @"same" : @"differs", @"differs");
        check( "13 practice differs from 49 inch desk", [praxis isEqualToString: mit49] ? @"same" : @"differs", @"differs");
        check( "14 three monitors: middle", sekhmetMonitorLage( @[ intern, rechts, links], 2), @"middle");
        check( "15 one monitor has no place", sekhmetMonitorLage( @[ intern], 0), nil);
        check( "16 no EDID: name", sekhmetMonitorBasis( mon( 0, 0, 0, @"Sidecar Display", 0, 0, 1366, 1024)), @"n:Sidecar Display");
        NSDictionary *oben = mon( 0x10ac, 0xa0c4, 1, @"DELL", 0, 1440, 2560, 1440), *unten = mon( 0x10ac, 0xa0c4, 2, @"DELL", 0, 0, 2560, 1440);
        check( "17 stacked: upper one", sekhmetMonitorLage( @[ unten, oben], 1), @"top");

        // snapping, on the right 27-inch (visible frame without menu bar)
        NSRect f = NSMakeRect( 2560, 0, 2560, 1415);
        NSString *r = nil;
        check( "18 window on the right half -> right half", num( sekhmetFlaecheEinrasten( NSMakeRect( 3840, 0, 1280, 1337 + 78), f, &r)), num( SekhmetAreaRightHalf));
        check( "19 a bit off (60 pt) still snaps", num( sekhmetFlaecheEinrasten( NSMakeRect( 3780, 40, 1330, 1300), f, &r)), num( SekhmetAreaRightHalf));
        check( "20 whole screen", num( sekhmetFlaecheEinrasten( NSMakeRect( 2565, 0, 2550, 1415), f, &r)), num( SekhmetAreaFull));
        check( "21 left two thirds", num( sekhmetFlaecheEinrasten( NSMakeRect( 2560, 0, 1700, 1415), f, &r)), num( SekhmetAreaLeftTwoThirds));
        r = nil;
        check( "22 odd place -> pixel rectangle", num( sekhmetFlaecheEinrasten( NSMakeRect( 3000, 100, 1500, 1200), f, &r)), num( SekhmetAreaPixelRect));
        check( "23 pixel rectangle relative to the screen", r, @"440 100 1500 1200");
        check( "24 half height is not a half", num( sekhmetFlaecheEinrasten( NSMakeRect( 3840, 0, 1280, 700), f, &r)), num( SekhmetAreaPixelRect));
        check( "25 window on another screen", num( sekhmetFlaecheEinrasten( NSMakeRect( 0, 0, 1280, 1415), f, &r)), @"-1");
        NSRect h = sekhmetFlaecheRechteck( SekhmetAreaRightHalf, f);
        check( "26 right half rectangle", NSStringFromRect( h), @"{{3840, 0}, {1280, 1415}}");
        check( "27 center half rectangle", NSStringFromRect( sekhmetFlaecheRechteck( SekhmetAreaCenterHalf, f)), @"{{3200, 0}, {1280, 1415}}");

        printf( "\n%d ok, %d failed\n", ok, bad);
    }
    return bad ? 1 : 0;
}
